<#
.SYNOPSIS
Creates a Magisk-patched init_boot image FILE from your own factory init_boot_a backup.

.DESCRIPTION
Runs Magisk 31.1's own boot_patch.sh, extracted from the pinned APK, on the connected device
with temporary root, then pulls the result to WorkDir\magisk-patched-init_boot.img.

It writes only that file. It never flashes a partition, never changes a boot slot, and never
reboots. Writing the image to init_boot_a is a separate, guarded step in the walkthrough
(docs/device/walkthrough.md, Stage 7).

Before doing anything on the device it checks that:
  - the Magisk APK in WorkDir is the pinned 31.1 release (SHA-256);
  - exactly one authorized device is connected and no other device is attached;
  - the device is the tested configuration: SKU XT2617V, the tested fingerprint, slot _a;
  - `su -c id` works (temporary root with Shell granted);
  - the init_boot_a partition on the device still matches the StockImage you supplied, so the
    image being patched is this device's own current init_boot.
Any failed check stops the script before the device is touched.

.PARAMETER WorkDir
The walkthrough's $Work folder. Must contain platform-tools\adb.exe and Magisk-v31.1.apk.
The output file and a magisk-patch-files staging folder are created here.

.PARAMETER StockImage
Your own factory init_boot_a.img backup (8 MiB), from Stage 3. Not boot_a, not another
device's image, not an already patched image.

.EXAMPLE
.\stock\Prepare-MagiskImage.ps1 -WorkDir $Work -StockImage "$Backup\init_boot_a.img"

.NOTES
Derived from parsimo2010's guide kit (MIT); see NOTICE.md.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [Parameter(Mandatory = $true)][string]$StockImage
)
$ErrorActionPreference = 'Stop'

# ---- the tested configuration ------------------------------------------------------------
$MagiskApkName       = 'Magisk-v31.1.apk'
$MagiskApkSha256     = '89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7'
$ExpectedSku         = 'XT2617V'
$ExpectedSlot        = '_a'
$ExpectedFingerprint = 'motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys'
$InitBootSize        = 8MB      # the init_boot partition is 8 MiB on this device
$DeviceStage         = '/data/local/tmp/magisk-patch-files'
# Magisk's own patch script, with the settings used on both tested units: keep verity and forced
# encryption, leave the vbmeta flag alone, and patch a normal (non-recovery) boot image.
$PatchEnvironment    = 'KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false RECOVERYMODE=false BOOTMODE=true'

# ---- paths --------------------------------------------------------------------------------
$WorkDir    = (Resolve-Path -LiteralPath $WorkDir).Path
$StockImage = (Resolve-Path -LiteralPath $StockImage).Path
$Adb   = Join-Path $WorkDir 'platform-tools\adb.exe'
$Apk   = Join-Path $WorkDir $MagiskApkName
$Out   = Join-Path $WorkDir 'magisk-patched-init_boot.img'
$Stage = Join-Path $WorkDir 'magisk-patch-files'   # pushed to $DeviceStage; the leaf names must match

# Runs adb, throws on a non-zero exit, and returns its output lines.
function Invoke-AdbChecked {
    param([string[]]$Arguments)
    $prior = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'   # adb writes progress to stderr; that must not throw
    try {
        $lines = & $Adb @Arguments 2>&1
        $status = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prior }
    if ($status -ne 0) { throw "ADB failed: $($lines -join [Environment]::NewLine)" }
    return @($lines | ForEach-Object { $_.ToString() })
}
function Get-Sha256([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower() }

# ---- PC-side checks: nothing touches the device yet -----------------------------------------
if (-not (Test-Path -LiteralPath $Adb)) { throw "adb.exe not found at $Adb. WorkDir must contain platform-tools." }
if (Test-Path -LiteralPath $Out)   { throw "Output exists: $Out. Keep it or move it aside; this script does not overwrite it." }
if (Test-Path -LiteralPath $Stage) { throw "Staging directory exists: $Stage. Review it and remove it before re-running." }
if ((Get-Item -LiteralPath $StockImage).Length -ne $InitBootSize) { throw "Expected an 8 MiB init_boot image: $StockImage" }
if ((Get-Sha256 $Apk) -ne $MagiskApkSha256) { throw "$MagiskApkName is not the pinned 31.1 release. Stop and investigate." }

# ---- device checks --------------------------------------------------------------------------
$devices = Invoke-AdbChecked @('devices')
$ready = @($devices | Where-Object { $_ -match '^\S+\s+device$' })
$other = @($devices | Where-Object { $_ -match '^\S+\s+(unauthorized|offline|recovery|sideload)$' })
if ($ready.Count -ne 1 -or $other.Count -gt 0) { throw 'Connect exactly one authorized Android device and nothing else.' }

$sku         = (Invoke-AdbChecked @('shell', 'getprop', 'ro.boot.hardware.sku')) -join ''
$fingerprint = (Invoke-AdbChecked @('shell', 'getprop', 'ro.build.fingerprint')) -join ''
$slot        = (Invoke-AdbChecked @('shell', 'getprop', 'ro.boot.slot_suffix')) -join ''
if ($sku.Trim() -ne $ExpectedSku -or $slot.Trim() -ne $ExpectedSlot -or $fingerprint.Trim() -ne $ExpectedFingerprint) {
    throw "Model, firmware, or slot differs from the tested configuration (sku=$($sku.Trim()) slot=$($slot.Trim()) fingerprint=$($fingerprint.Trim()))."
}
$identity = (Invoke-AdbChecked @('shell', 'su', '-c', 'id')) -join ''
if ($identity -notmatch 'uid=0\(root\)') { throw 'Temporary root with Shell granted is required (walkthrough, Stage 2).' }

$stockHash   = Get-Sha256 $StockImage
$currentHash = (Invoke-AdbChecked @('shell', 'su', '-c', 'sha256sum /dev/block/by-name/init_boot_a')) -join ''
if ($currentHash -notmatch ('^' + $stockHash + '\s')) {
    throw 'The supplied stock image does not match the current init_boot_a partition on this device.'
}

# ---- stage Magisk's patch script and binaries from the verified APK --------------------------
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $Stage | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($Apk)
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -in @('assets/boot_patch.sh', 'assets/util_functions.sh') -or
            $entry.FullName -like 'lib/arm64-v8a/*.so') {
            $name = [IO.Path]::GetFileName($entry.FullName)
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Stage $name), $false)
        }
    }
} finally { $zip.Dispose() }
# The APK ships the native tools as lib<name>.so; boot_patch.sh expects them by bare name.
foreach ($name in @('magisk', 'magiskboot', 'magiskinit', 'init-ld', 'busybox', 'magiskpolicy')) {
    Copy-Item -LiteralPath (Join-Path $Stage "lib$name.so") -Destination (Join-Path $Stage $name)
}

# ---- patch on the device, pull the result, verify it ----------------------------------------
Invoke-AdbChecked @('push', $Stage, '/data/local/tmp/') | Write-Output
Invoke-AdbChecked @('push', $StockImage, "$DeviceStage/stock-init_boot.img") | Write-Output
$command = "$PatchEnvironment sh $DeviceStage/boot_patch.sh $DeviceStage/stock-init_boot.img"
Invoke-AdbChecked @('shell', 'su', '-c', $command) | Write-Output
Invoke-AdbChecked @('pull', "$DeviceStage/new-boot.img", $Out) | Write-Output

$phoneHash = (Invoke-AdbChecked @('shell', 'su', '-c', "sha256sum $DeviceStage/new-boot.img")) -join ''
$pcHash = Get-Sha256 $Out
if ($phoneHash -notmatch ('^' + $pcHash + '\s')) { throw 'Output transfer hash mismatch. Do not flash.' }
if ((Get-Item -LiteralPath $Out).Length -ne $InitBootSize) { throw 'Unexpected output size. Do not flash.' }

Write-Output "Prepared file: $Out"
Write-Output "SHA256: $pcHash"
Write-Output 'No firmware partition was written. No reboot was performed.'
