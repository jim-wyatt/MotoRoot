<#
.SYNOPSIS
Runs Google's Android GSI on the device through DSU (Dynamic System Updates), without flashing.

.DESCRIPTION
DSU boots a Generic System Image from a file in /data, on top of the device's own vendor
partition. Nothing is flashed, the slots and boot images are untouched, and a reboot returns to
the installed system. This script drives the whole cycle; the image is pinned by hash in
dev\toolchain.json (deviceTools.gsi).

  -Action Download   Download the pinned GSI zip into work\device-tools\gsi and verify its SHA-256.
                     Google's download is behind a terms-of-use click-through; pass
                     -AcceptGoogleGsiTerms only after reading the terms the script prints.
  -Action Install    Push the zip to the device and hand it to Android's own DSU installer.
                     The phone shows a confirmation; after you accept, installation takes a few
                     minutes and the script waits for `gsi_tool status` to report it installed.
  -Action Boot       Enable the installed GSI for ONE boot and reboot into it. The next reboot,
                     however it happens, returns to the installed system.
  -Action Status     Show the DSU state and whether a GSI is running right now.
  -Action Discard    Remove the installed GSI and its userdata (run from the normal system).

Requires the dev shell ($adb) and root on the device (gsi_tool). Read docs/device/gsi.md first.

.PARAMETER UserdataGiB
Size of the separate userdata the GSI gets (default 8). It lives in /data as a file and is
removed by -Action Discard.

.PARAMETER Image
Install your own image instead of the pinned one: a system.img built by dev\aosp\build-gsi.sh
(a zip with a system.img inside also works). vbmeta.img and build.prop next to it are packed
too. No hash pin applies to your own build.

.EXAMPLE
.\dev\Install-Gsi.ps1 -Action Install -Image "$Work\device-tools\gsi\own\system.img"
#>
[CmdletBinding()]
param(
    [ValidateSet('Download', 'Install', 'Boot', 'Status', 'Discard')][string]$Action = 'Status',
    [switch]$AcceptGoogleGsiTerms,
    [int]$UserdataGiB = 8,
    [string]$Image
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
$Spec = (Get-Content -Raw (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json).deviceTools.gsi
$Dir  = Join-Path $Work 'device-tools\gsi'
$Zip  = Join-Path $Dir $Spec.name
if (-not (Test-Path $Adb)) { throw 'platform-tools missing. Run .\dev\Bootstrap-DevEnv.ps1.' }

# Your own build: the DSU installer wants a zip with system.img (sparse or raw) inside, like
# Google's, so a bare image is wrapped into one next to itself. No pin: the hash check is skipped.
if ($Image) {
    $Image = (Resolve-Path -LiteralPath $Image).Path
    if ($Image -like '*.zip') { $Zip = $Image }
    else {
        $Zip = Join-Path (Split-Path $Image) 'own-gsi.zip'
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $Zip) { Remove-Item $Zip }
        $archive = [IO.Compression.ZipFile]::Open($Zip, 'Create')
        try {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $Image, 'system.img', 'Fastest') | Out-Null
            foreach ($extra in 'vbmeta.img', 'build.prop') {
                $p = Join-Path (Split-Path $Image) $extra
                if (Test-Path $p) { [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $p, $extra, 'Fastest') | Out-Null }
            }
        } finally { $archive.Dispose() }
    }
    $Spec = [pscustomobject]@{ name = (Split-Path -Leaf $Zip); sha256 = $null; url = $null; terms = $null; build = 'own build' }
}
$Remote = "/storage/emulated/0/Download/$($Spec.name)"
function Verified-Zip { (Test-Path $Zip) -and ($Image -or (Sha256 $Zip) -eq $Spec.sha256) }

function Sha256($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }
# Root, the one-device check, gsi_tool and the reboot wait come from the shared module; Root works
# with Magisk's su on the stock system and AOSP's in a DSU image.
Import-Module (Join-Path $PSScriptRoot 'VedoTom.psm1')
function Root([string]$Command) { Invoke-RootShell $Command }
function Prop([string]$Name) { ((& $Adb shell getprop $Name) -join '').Trim() }
function GsiStatus { Get-GsiStatus }
function Require-Device {
    Assert-OneDevice
    if (-not (Test-DeviceRoot)) { throw 'Root (su) is required on the device.' }
}

switch ($Action) {
    'Download' {
        if ($Image) { throw '-Download applies to the pinned image only; your own image is already on this PC.' }
        if (Test-Path $Zip) {
            if ((Sha256 $Zip) -eq $Spec.sha256) { Write-Host "Already present and verified: $Zip" -ForegroundColor Green; return }
            throw "$Zip exists but does not match the pinned SHA-256. Delete it and retry."
        }
        Write-Host "Google publishes this image under its GSI terms: $($Spec.terms)"
        if (-not $AcceptGoogleGsiTerms) { throw 'Read the terms, then re-run with -AcceptGoogleGsiTerms to download.' }
        New-Item -ItemType Directory -Force $Dir | Out-Null
        $Partial = "$Zip.partial"
        $size = try { [math]::Round((Invoke-WebRequest -Uri $Spec.url -Method Head -UseBasicParsing -TimeoutSec 30).Headers['Content-Length'][0] / 1MB) } catch { '?' }
        Write-Host "Downloading $($Spec.name) ($size MB) ..."
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Spec.url -OutFile $Partial -UseBasicParsing
        if ((Sha256 $Partial) -ne $Spec.sha256) { Remove-Item $Partial; throw 'SHA-256 mismatch after download. Not keeping the file.' }
        Move-Item $Partial $Zip
        Write-Host "Verified: $Zip" -ForegroundColor Green
    }
    'Install' {
        Require-Device
        if (-not (Verified-Zip)) { throw "Run -Action Download first (missing or unverified: $Zip)." }
        if (Test-GsiRunning) { throw 'A GSI is running right now. Reboot into the normal system first.' }
        $st = GsiStatus
        if ($st -ne 'normal') { throw "DSU state is '$st', not 'normal'. Use -Action Status / -Action Discard first." }
        foreach ($p in 'ro.boot.dynamic_partitions') { if ((Prop $p) -ne 'true') { throw "$p is not true; DSU needs dynamic partitions." } }
        Write-Host "Pushing $($Spec.name) to the device (this takes a minute) ..."
        & $Adb push $Zip $Remote | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'push failed' }
        $userdata = [int64]$UserdataGiB * 1GB
        # Android's own DSU installer: it reads system.img (sparse or raw) out of the zip, creates the
        # images in /data. KEY_USERDATA_SIZE is in bytes. VerificationActivity asks for the screen-lock
        # PIN, pattern or password first only when the phone has a secure lock screen; without one
        # (as on the tested unit, 2026-11-19) the installation starts with no prompt at all.
        & $Adb shell am start-activity -n com.android.dynsystem/com.android.dynsystem.VerificationActivity `
            -a android.os.image.action.START_INSTALL -d "file://$Remote" --el KEY_USERDATA_SIZE $userdata | Out-Null
        Write-Host 'Installing (if the phone has a secure lock screen, it asks for the PIN, pattern or password first). Waiting for it to finish (up to 30 min) ...' -ForegroundColor Cyan
        # gsi_tool lists partitions as "installed" as soon as they are created, while the installer is
        # still writing them, so the installer's own status in logcat is what to wait for:
        # NOT_STARTED -> IN_PROGRESS (with a progress fraction) -> READY, or an error cause.
        & $Adb logcat -c 2>$null
        $t = 0; $state = 'NOT_STARTED'; $lastShown = ''
        while ($t -lt 1800) {
            Start-Sleep 10; $t += 10
            $line = (& $Adb logcat -d 2>$null | Select-String -Pattern 'DynamicSystemInstallationService: status: (\w+), cause: (\w+)' | Select-Object -Last 1)
            if ($line) {
                $state = $line.Matches[0].Groups[1].Value
                $progress = [regex]::Match($line.Line, 'total_progress: (\d+%)').Groups[1].Value
                $shown = "$state $progress $($line.Matches[0].Groups[2].Value)"
                if ($shown -ne $lastShown) { Write-Host "  ${t}s: $shown"; $lastShown = $shown }
                if ($state -eq 'READY') { break }
                if ($line.Matches[0].Groups[2].Value -notin 'CAUSE_NOT_SPECIFIED', 'CAUSE_INSTALL_COMPLETED') { break }
            }
        }
        & $Adb shell rm -f $Remote | Out-Null
        $st = GsiStatus
        if ($state -ne 'READY') { throw "Installation did not complete (installer state '$state', gsi_tool status '$st'). Check the notification on the phone; -Action Discard cleans up." }
        Write-Host "Installed (gsi_tool: $($st -replace "`n", ' ')). Next: .\dev\Install-Gsi.ps1 -Action Boot" -ForegroundColor Green
    }
    'Boot' {
        Require-Device
        $st = GsiStatus
        if ($st -notmatch 'installed|enabled') { throw "No installed GSI (status '$st'). Run -Action Install first." }
        Write-Host (Root 'gsi_tool enable --single-boot')
        Write-Host 'Rebooting into the GSI for ONE boot. First boot can take several minutes. If it never reaches the home screen, hold Power to reboot: the next boot is the normal system.' -ForegroundColor Cyan
        & $Adb reboot
        $t = Wait-DeviceBoot -AfterReboot
        Start-Sleep 5
        Write-Host "booted after ~${t}s: GSI running=$(Test-GsiRunning) build=$(Prop 'ro.build.display.id') fingerprint=$(Prop 'ro.build.fingerprint')"
    }
    'Status' {
        Require-Device
        "gsi_tool status:      $(GsiStatus)"
        "GSI running now:      $(Test-GsiRunning)   (gsi_tool's first line; ro.gsid.image_running is empty on this phone)"
        "build running:        $(Prop 'ro.build.display.id')"
        "zip on PC:            " + $(if ($Image) { "own build: $Zip" } elseif (Test-Path $Zip) { if ((Sha256 $Zip) -eq $Spec.sha256) { 'present, verified' } else { 'present, HASH MISMATCH' } } else { 'not downloaded' })
    }
    'Discard' {
        Require-Device
        if (Test-GsiRunning) { throw 'A GSI is running. Reboot into the normal system first, then discard.' }
        $st = GsiStatus
        if ($st -eq 'normal') { Write-Host 'Nothing installed.'; return }
        Write-Host (Root 'gsi_tool disable')
        Write-Host (Root 'gsi_tool wipe')
        Write-Host "DSU status: $(GsiStatus)" -ForegroundColor Green
    }
}
