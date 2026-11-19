<#
.SYNOPSIS
    Puts the newest VedoTom image on the phone in one run: fetch, reboot to stock, discard, install, boot, check.

.DESCRIPTION
    This is the delivery loop for the install machine, the PC the phone is plugged into, when images
    are built elsewhere (see docs/develop/aosp-build.md, "Building on one machine, installing from
    another"). It chains the existing scripts and adds the waits and checks between them.

    1. Get-RemoteImage.ps1 fetches and verifies the newest image. Skip this with -NoFetch to install
       the image already in work\device-tools\gsi\own\.
    2. If the phone is running a VedoTom image, it reboots to the stock system. The DSU installer
       works only from there. ro.gsid.image_running reads empty on this device, so the image is
       recognised by ro.product.name instead.
    3. Install-Gsi.ps1 discards the installed image, installs the new one with a -UserdataGiB data
       partition, and boots it.
    4. It waits for the first-boot service to finish. The service writes its result to
       /data/local/vedotom-firstboot/status and every step to .../log, read here as root
       (su 0, which a userdebug image has), so the result does not depend on the log buffers.
    5. It reports the fingerprint, the HOME role holder, what the first-boot service did, the
       defaults the image sets (animations, log buffers, time zone, the hidden AOSP Files and
       keyboard icons), and whether anything is in the crash log.

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
if ((Sh 'getprop ro.product.name') -like 'vedotom*') {
    Step 'The phone is in a VedoTom image: rebooting to the stock system'
    & $Adb reboot
    $s = Wait-DeviceBoot -AfterReboot
    Write-Host "  stock system up after ~${s}s ($(Sh 'getprop ro.build.display.id'))"
}

# ---- 3. discard, install, boot
$gsi = Join-Path $PSScriptRoot 'Install-Gsi.ps1'
Step 'Discarding the installed image'
& $gsi -Action Discard
Step 'Installing the new image'
& $gsi -Action Install -Image $Img -UserdataGiB $UserdataGiB
Step 'Booting it'
& $gsi -Action Boot
if ((Sh 'getprop ro.product.name') -notlike 'vedotom*') { throw "The phone did not come up in the VedoTom image (product $(Sh 'getprop ro.product.name'))." }

# ---- 4. first-boot service
Step 'Waiting for the first-boot service'
$State = '/data/local/vedotom-firstboot'
$t = 0
while ($t -lt 300 -and (Sh "su 0 cat $State/status") -notlike 'done*') { Start-Sleep 5; $t += 5 }
$status = Sh "su 0 cat $State/status"
$fb = @((Sh "su 0 cat $State/log") -split "`r?`n" | Where-Object { $_ } | ForEach-Object { ($_ -split ' ', 3)[2] })
if ($status -notlike 'done*') { Write-Warning "The first-boot service had not finished after $t s (status: '$status')." }
$fb | Where-Object { $_ -like '*failed*' -or $_ -like '*did not stick*' } | ForEach-Object { Write-Warning "first boot: $_" }

# ---- 5. report
Step 'Result'
$crashes = @(& $Adb logcat -d -b crash 2>$null | Select-String ' F libc|FATAL EXCEPTION').Count
$scales = @('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale' | ForEach-Object { Sh "settings get global $_" }) -join '/'
$aospIcons = Sh 'pm query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER --components | grep -E "com.android.documentsui|com.android.inputmethod.latin"'
[pscustomobject]@{
    Fingerprint = Sh 'getprop ro.build.fingerprint'
    Home        = Sh 'cmd role get-role-holders android.app.role.HOME'
    FirstBoot   = "$status; $(@($fb | Where-Object { $_ -like 'icon colour *' }).Count) icons set"
    Animations  = "$scales (want 0/0/0)"
    LogBuffer   = Sh 'logcat -g -b main'
    TimeZone    = Sh 'getprop persist.sys.timezone'
    AospIcons   = if ($aospIcons) { "still in the launcher: $aospIcons" } else { 'hidden (Files, keyboard)' }
    ChargeLimit = if ($cl = Sh "su 0 cat $State/charge-limit") { "$cl; now blocking=$(Sh 'su 0 cat /sys/module/qpnp_adaptive_charge/parameters/blocking'), battery $(Sh 'cat /sys/class/power_supply/battery/capacity')%" } else { 'not applied yet (no charge-limit file)' }
    CrashLog    = if ($crashes) { "$crashes entries: check adb logcat -b crash" } else { 'empty' }
    DataFree    = ((Sh 'df -h /data | tail -1') -split '\s+')[3]
} | Format-List
