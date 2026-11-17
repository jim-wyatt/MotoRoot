<#
.SYNOPSIS
    Puts the newest VedoTom image on the phone in one run: fetch, reboot to stock, discard, install, boot, maps, check.

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
    4. It waits for the first-boot service to log "done".
    5. Push-OfflineMaps.ps1 restores the maps, unless you pass -NoMaps.
    6. It reports the fingerprint, the HOME and BROWSER role holders, what the first-boot service
       did, and whether anything is in the crash log.

    Step 3 deletes the installed image's data: its apps' data, settings and pushed maps. So the
    script asks before it starts. -Confirm:$false skips the question.

.EXAMPLE
    .\dev\Deploy-Image.ps1
.EXAMPLE
    .\dev\Deploy-Image.ps1 -NoFetch -NoMaps -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [switch]$NoFetch,
    [switch]$NoMaps,
    [int]$UserdataGiB = 24,
    [string[]]$Region = @('United States of America')
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
$Img  = Join-Path $Work 'device-tools\gsi\own\system.img'

function Sh([string]$cmd) { (& $Adb shell $cmd 2>$null | Out-String).Trim() }
function Wait-Boot([int]$limit = 600) {
    & $Adb wait-for-device
    $t = 0
    while ($t -lt $limit) { if ((Sh 'getprop sys.boot_completed') -eq '1') { return $t }; Start-Sleep 5; $t += 5 }
    throw "The phone did not finish booting within $limit s."
}
function Step([string]$text) { Write-Host "== $text" -ForegroundColor Cyan }

$devs = @(& $Adb devices | Select-String "`tdevice$")
if ($devs.Count -ne 1) { throw "Connect exactly one authorized device (found $($devs.Count))." }

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
    Start-Sleep 15
    $s = Wait-Boot
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
$t = 0
while ($t -lt 300 -and -not ((& $Adb logcat -d -s vedotom-firstboot 2>$null) -match ': done$')) { Start-Sleep 5; $t += 5 }
$fb = & $Adb logcat -d -s vedotom-firstboot 2>$null | Select-String 'vedotom-firstboot: ' | ForEach-Object { ($_.Line -split 'vedotom-firstboot: ', 2)[1] }
if (-not ($fb -contains 'done')) { Write-Warning "The first-boot service had not logged 'done' after $t s." }

# ---- 5. maps
if (-not $NoMaps) {
    Step 'Restoring the offline maps'
    & (Join-Path $PSScriptRoot 'Push-OfflineMaps.ps1') -Region $Region
}

# ---- 6. report
Step 'Result'
$crashes = @(& $Adb logcat -d -b crash 2>$null | Select-String ' F libc|FATAL EXCEPTION').Count
[pscustomobject]@{
    Fingerprint = Sh 'getprop ro.build.fingerprint'
    Home        = Sh 'cmd role get-role-holders android.app.role.HOME'
    Browser     = Sh 'cmd role get-role-holders android.app.role.BROWSER'
    FirstBoot   = "$(@($fb | Where-Object { $_ -like 'installed *' }).Count) preloads installed, $(@($fb | Where-Object { $_ -like 'icon colour *' }).Count) icons set, failures: $(@($fb | Where-Object { $_ -like '*failed*' }).Count)"
    CrashLog    = if ($crashes) { "$crashes entries: check adb logcat -b crash" } else { 'empty' }
    DataFree    = ((Sh 'df -h /data | tail -1') -split '\s+')[3]
} | Format-List
