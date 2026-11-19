<#
.SYNOPSIS
    Puts the newest VedoTom image on the phone in one run: fetch, reboot to stock, discard, install, boot, check.

.DESCRIPTION
    This is the delivery loop for the install machine, the PC the phone is plugged into, when images
    are built elsewhere (see docs/develop/aosp-build.md, "Building on one machine, installing from
    another"). It chains the existing scripts and adds the waits and checks between them.

    1. Get-RemoteImage.ps1 fetches and verifies the newest image. Skip this with -NoFetch to install
       the image already in work\device-tools\gsi\own\.
    2. If the phone is running a DSU image (gsi_tool status; ro.gsid.image_running reads empty on
       this device), Install-Gsi.ps1 -Action Stock disables it and reboots to the stock system.
       The DSU installer works only from there.
    3. Install-Gsi.ps1 discards the installed image, installs the new one with a -UserdataGiB data
       partition, and boots it persistently: it stays the phone's system across reboots until
       -Action Stock (-SingleBoot boots it once only).
       With work\wifi.json present (private, git-ignored), the image then joins that Wi-Fi network.
    4. It waits for the first-boot service to finish. The service writes its result to
       /data/local/vedotom-firstboot/status and every step to .../log, read here as root
       (su 0, which a userdebug image has), so the result does not depend on the log buffers.
    5. It reports the fingerprint, the HOME role holder, what the first-boot service did, the
       defaults the image sets (animations, log buffers, time zone, the hidden AOSP Files and
       keyboard icons), and whether anything is in the crash log.
    6. It runs Test-Device.ps1: the development loops (root, logs, NDK, app install, Perfetto,
       Frida, scrcpy) on the new image. -SkipDeviceTest leaves it out.

    Once the phone is up in the new image, the local copy (system.img, its sidecars) is deleted
    unless -KeepImage is given: the install PC only pushes and validates, and the build machine
    keeps every build. Its hash stays in deployed.sha256.

    Step 3 deletes the installed image's data: its apps' data and settings. So the script asks
    before it starts. -Confirm:$false skips the question.

.EXAMPLE
    .\dev\Deploy-Image.ps1
.EXAMPLE
    .\dev\Deploy-Image.ps1 -NoFetch -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$NoFetch,
    [switch]$KeepImage,   # keep the fetched image on this PC after the install (by default it is removed)
    [switch]$SingleBoot,  # boot the new image once only (by default it stays enabled across reboots)
    [switch]$SkipDeviceTest,  # leave out step 6, the development-workflow smoke test (Test-Device.ps1)
    [int]$UserdataGiB = 24
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
$Img  = Join-Path $Work 'device-tools\gsi\own\system.img'

Import-Module (Join-Path $PSScriptRoot 'VedoTom.psm1')   # Assert-OneDevice, Wait-DeviceBoot
function Sh([string]$cmd) { (& $Adb shell $cmd 2>$null | Out-String).Trim() }
function Step([string]$text) { Write-Host "== $text" -ForegroundColor Cyan }

Assert-OneDevice

# ---- 1. fetch
if (-not $NoFetch) {
    Step 'Fetching the newest image from the build machine'
    & (Join-Path $PSScriptRoot 'Get-RemoteImage.ps1')
}
if (-not (Test-Path $Img)) { throw "No image at $Img." }
$hash = (Get-FileHash -Algorithm SHA256 $Img).Hash.ToLower()
$sidecar = Join-Path (Split-Path $Img) 'system.img.sha256'
if ((Test-Path $sidecar) -and (((Get-Content $sidecar -TotalCount 1) -split '\s+')[0].ToLower() -ne $hash)) {
    throw "$Img does not match its system.img.sha256. Fetch it again."
}

if (-not $PSCmdlet.ShouldProcess('the phone', "replace the installed image and its data with $($hash.Substring(0,12))... ($UserdataGiB GB data partition)")) { return }

# ---- 2. stock system first
# A persistent image comes back on a plain reboot, so the GSI is disabled first (Install-Gsi -Action
# Stock); for a single-boot GSI that is harmless, and the reboot returns to stock either way.
$gsi = Join-Path $PSScriptRoot 'Install-Gsi.ps1'
if (Test-GsiRunning) {
    Step "The phone is in a DSU image ($(Sh 'getprop ro.product.name')): back to the stock system"
    & $gsi -Action Stock
}

# ---- 3. discard, install, boot
Step 'Discarding the installed image'
& $gsi -Action Discard
Step 'Installing the new image'
& $gsi -Action Install -Image $Img -UserdataGiB $UserdataGiB
Step 'Booting it'
# Persistent by default: the image stays the phone's system across reboots, with stock untouched on
# slot A and one command away (.\dev\Install-Gsi.ps1 -Action Stock). -SingleBoot boots it once.
& $gsi -Action Boot -Persistent:(-not $SingleBoot)
if ((Sh 'getprop ro.product.name') -notlike 'vedotom*') { throw "The phone did not come up in the VedoTom image (product $(Sh 'getprop ro.product.name'))." }
# The image is on the phone now, and the build machine keeps every build, so this PC drops its copy
# (about 1.8 GB). A re-deploy fetches it again. -KeepImage keeps it, e.g. to re-install offline.
if (-not $KeepImage) {
    $own = Split-Path $Img
    Remove-Item -Force -ErrorAction SilentlyContinue $Img, (Join-Path $own 'system.prev.img'), (Join-Path $own 'build.prop'), (Join-Path $own 'vbmeta.img'), (Join-Path $own 'own-gsi.zip')
    Move-Item -Force $sidecar (Join-Path $own 'deployed.sha256') -ErrorAction SilentlyContinue
    Write-Host "  local image removed (deployed: $($hash.Substring(0,12))..., in $own\deployed.sha256)"
}

# ---- 3b. Wi-Fi (optional)
# Every DSU install starts with empty userdata, so no network is saved. If work\wifi.json exists
# ({"ssid": ..., "security": "wpa2"|"wpa3"|..., "passphrase": ...}; private, git-ignored, like the
# rest of work\), the image joins it, so the checks that need a network (captive-portal validation,
# NTP) can run unattended. The passphrase goes to the phone over USB only.
$WifiCfg = Join-Path $Work 'wifi.json'
if (Test-Path $WifiCfg) {
    $w = Get-Content -Raw $WifiCfg | ConvertFrom-Json
    $q = { param($s) "'" + ($s -replace "'", "'\''") + "'" }
    Step "Joining Wi-Fi $($w.ssid)"
    Invoke-RootShell 'cmd wifi set-wifi-enabled enabled' | Out-Null
    Start-Sleep 3
    Invoke-RootShell "cmd wifi connect-network $(& $q $w.ssid) $($w.security) $(& $q $w.passphrase)" | Out-Null
    $t = 0
    while ($t -lt 60 -and (Sh 'dumpsys connectivity | grep -E "^ *NetworkAgentInfo.*WIFI.*VALIDATED"') -eq '') { Start-Sleep 3; $t += 3 }
    if ($t -ge 60) { Write-Warning "Wi-Fi $($w.ssid) did not validate within 60 s." } else { Write-Host "  connected and validated after ~${t}s" }
}

# ---- 4. first-boot service
Step 'Waiting for the first-boot service'
$State = '/data/local/vedotom-firstboot'
$t = 0
while ($t -lt 300 -and (Sh "su 0 cat $State/status") -notlike 'done*') { Start-Sleep 5; $t += 5 }
$status = Sh "su 0 cat $State/status"
$fb = @((Sh "su 0 cat $State/log") -split "`r?`n" | Where-Object { $_ } | ForEach-Object { ($_ -split ' ', 3)[2] })
if ($status -notlike 'done*') { Write-Warning "The first-boot service had not finished after $t s (status: '$status')." }
$fb | Where-Object { $_ -like '*failed*' -or $_ -like '*did not stick*' } | ForEach-Object { Write-Warning "first boot: $_" }

# The charge-limit service writes its result 30 s after boot completes (the module re-evaluates on its
# next battery update), and removes the previous boot's file when it starts.
$w = 0
while ($w -lt 60 -and -not (Sh "su 0 cat $State/charge-limit")) { Start-Sleep 5; $w += 5 }

# ---- 5. report
Step 'Result'
$crashes = @(& $Adb logcat -d -b crash 2>$null | Select-String ' F libc|FATAL EXCEPTION').Count
$scales = @('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale' | ForEach-Object { Sh "settings get global $_" }) -join '/'
$aospIcons = Sh 'pm query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER --components | grep -E "com.android.documentsui|com.android.inputmethod.latin"'
# Which hosts NetworkMonitor's captive-portal probes used, and the NTP server that last answered.
$validated = (Sh 'dumpsys connectivity | grep -E "^ *NetworkAgentInfo.*VALIDATED"') -ne ''
$probeHosts = @([regex]::Matches((Sh 'dumpsys network_stack | grep -E "PROBE_HTTPS? "'), 'PROBE_HTTPS? https?://([^/\s]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique) -join ', '
$ntp = [regex]::Match((Sh 'dumpsys network_time_update_service'), 'mLastSuccessfulNtpServerUri=(\S+)').Groups[1].Value
[pscustomobject]@{
    Fingerprint = Sh 'getprop ro.build.fingerprint'
    Home        = Sh 'cmd role get-role-holders android.app.role.HOME'
    FirstBoot   = "$status; $(@($fb | Where-Object { $_ -like 'icon colour *' }).Count) icons set"
    Animations  = "$scales (want 0/0/0)"
    LogBuffer   = Sh 'logcat -g -b main'
    TimeZone    = Sh 'getprop persist.sys.timezone'
    AospIcons   = if ($aospIcons) { "still in the launcher: $aospIcons" } else { 'hidden (Files, keyboard)' }
    ChargeLimit = if ($cl = Sh "su 0 cat $State/charge-limit") { "$cl; now blocking=$(Sh 'su 0 cat /sys/module/qpnp_adaptive_charge/parameters/blocking'), battery $(Sh 'cat /sys/class/power_supply/battery/capacity')%" } else { 'not applied yet (no charge-limit file)' }
    Network     = if ($validated) { "validated; probes to $(if ($probeHosts) { $probeHosts } else { '?' }); NTP $(if ($ntp) { $ntp } else { 'not synced yet' })" } else { 'no validated network (no work\wifi.json, or not joined)' }
    CrashLog    = if ($crashes) { "$crashes entries: check adb logcat -b crash" } else { 'empty' }
    DataFree    = ((Sh 'df -h /data | tail -1') -split '\s+')[3]
} | Format-List

# ---- 6. development workflows
# The report above checks what the image sets; Test-Device.ps1 checks that the development loops
# work on it: root, logs, an NDK binary, an app built here (install, launch, uninstall), a
# Perfetto trace, Frida, scrcpy. It removes what it installs. -SkipDeviceTest leaves it out.
if (-not $SkipDeviceTest) {
    Step 'Development workflows (Test-Device.ps1)'
    & (Join-Path $PSScriptRoot 'Test-Device.ps1')
    if ($LASTEXITCODE) { Write-Warning "Test-Device.ps1: $LASTEXITCODE check(s) failed (see the table above)." }
}
