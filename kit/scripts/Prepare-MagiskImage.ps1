<#
Creates a Magisk-patched init_boot FILE on the reference-model phone.
Does not flash a boot partition, change boot slots, or reboot.
Read GUIDE.md and back up your own factory image first.
#>
param(
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$StockImage,
    [string]$GuideKit
)
$ErrorActionPreference = 'Stop'
$WorkDir = (Resolve-Path -LiteralPath $WorkDir).Path
$StockImage = (Resolve-Path -LiteralPath $StockImage).Path
$Adb = Join-Path $WorkDir 'platform-tools\adb.exe'
$Apk = Join-Path $WorkDir 'Magisk-v31.1.apk'
$Out = Join-Path $WorkDir 'magisk-patched-init_boot.img'
$Stage = Join-Path $WorkDir 'magisk-patch-files'
function Invoke-AdbChecked {
    param([string[]]$Arguments)
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Adb @Arguments 2>&1
        $nativeStatus = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorPreference }
    if ($nativeStatus -ne 0) { throw "ADB failed: $($lines -join [Environment]::NewLine)" }
    return @($lines | ForEach-Object { $_.ToString() })
}
if (!(Test-Path -LiteralPath $Adb)) { throw 'ADB missing from WorkDir\platform-tools' }
if (Test-Path -LiteralPath $Out) { throw 'Output exists. Keep it or move it aside; do not overwrite it.' }
if (Test-Path -LiteralPath $Stage) { throw 'Staging directory exists. Review it and choose a clean work folder.' }
if ((Get-Item -LiteralPath $StockImage).Length -ne 8388608) { throw 'Expected an 8 MiB init_boot image' }
$apkHash = (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLower()
if ($apkHash -ne '89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7') {
    throw 'Magisk APK is not the pinned 31.1 release. Stop and investigate.'
}
$devices = Invoke-AdbChecked @('devices')
$ready = @($devices | Where-Object { $_ -match '^\S+\s+device$' })
$other = @($devices | Where-Object { $_ -match '^\S+\s+(unauthorized|offline|recovery|sideload)$' })
if ($ready.Count -ne 1 -or $other.Count -gt 0) { throw 'Connect exactly one approved Android device.' }
$sku = (Invoke-AdbChecked @('shell','getprop','ro.boot.hardware.sku')) -join ''
$fingerprint = (Invoke-AdbChecked @('shell','getprop','ro.build.fingerprint')) -join ''
$slot = (Invoke-AdbChecked @('shell','getprop','ro.boot.slot_suffix')) -join ''
if ($sku.Trim() -ne 'XT2617V' -or $slot.Trim() -ne '_a' -or
    $fingerprint.Trim() -ne 'motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys') {
    throw 'Model, firmware, or slot differs from the tested configuration.'
}
$identity = (Invoke-AdbChecked @('shell','su','-c','id')) -join ''
if ($identity -notmatch 'uid=0\(root\)') { throw 'Temporary root and Shell permission are required.' }
$stockHash = (Get-FileHash -LiteralPath $StockImage -Algorithm SHA256).Hash.ToLower()
$currentHash = (Invoke-AdbChecked @('shell','su','-c','sha256sum /dev/block/by-name/init_boot_a')) -join ''
if ($currentHash -notmatch ('^'+$stockHash+'\s')) {
    throw 'The supplied stock image does not match the current init_boot_a partition.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Path $Stage | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($Apk)
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName -in @('assets/boot_patch.sh','assets/util_functions.sh') -or
            $entry.FullName -like 'lib/arm64-v8a/*.so') {
            $name = [IO.Path]::GetFileName($entry.FullName)
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $Stage $name),$false)
        }
    }
} finally { $zip.Dispose() }
foreach ($name in @('magisk','magiskboot','magiskinit','init-ld','busybox','magiskpolicy')) {
    Copy-Item -LiteralPath (Join-Path $Stage "lib$name.so") -Destination (Join-Path $Stage $name)
}
Invoke-AdbChecked @('push',$Stage,'/data/local/tmp/') | Write-Output
Invoke-AdbChecked @('push',$StockImage,'/data/local/tmp/magisk-patch-files/stock-init_boot.img') | Write-Output
$command = 'KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false RECOVERYMODE=false BOOTMODE=true sh /data/local/tmp/magisk-patch-files/boot_patch.sh /data/local/tmp/magisk-patch-files/stock-init_boot.img'
Invoke-AdbChecked @('shell','su','-c',$command) | Write-Output
Invoke-AdbChecked @('pull','/data/local/tmp/magisk-patch-files/new-boot.img',$Out) | Write-Output
$phoneHash = (Invoke-AdbChecked @('shell','su','-c','sha256sum /data/local/tmp/magisk-patch-files/new-boot.img')) -join ''
$pcHash = (Get-FileHash -LiteralPath $Out -Algorithm SHA256).Hash.ToLower()
if ($phoneHash -notmatch ('^'+$pcHash+'\s')) { throw 'Output transfer hash mismatch. Do not flash.' }
if ((Get-Item -LiteralPath $Out).Length -ne 8388608) { throw 'Unexpected output size. Do not flash.' }
Write-Output "Prepared file: $Out"
Write-Output "SHA256: $pcHash"
Write-Output 'No firmware partition was written. No reboot was performed.'
