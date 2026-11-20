<#
.SYNOPSIS
Collects a hardware and software inventory of the connected device into work\device-info\.

.DESCRIPTION
Read-only: every command only reads properties, /proc, /sys and service dumps. Root (su) is
used where a listing needs it (partition map, HAL list) and skipped if unavailable.

Two outputs:
  work\device-info\<timestamp>\*.txt   the raw dumps. PRIVATE: they contain the serial number,
                                       IMEI, MAC addresses and installed-app list. work\ is
                                       git-ignored and the pre-commit hook blocks it.
  work\device-info\<timestamp>\summary.txt   a curated summary with identifiers deliberately
                                       left out; the source for docs/device/hardware.md.

.PARAMETER Label
Appended to the output folder name, e.g. -Label gsi-BP4A when dumping a GSI session.

.PARAMETER Bugreport
Also take a full `adb bugreport` (every dumpsys, all log buffers, kernel log, tombstones, VINTF;
several minutes, tens of MB). The most complete record of a session; PRIVATE like the rest.

.EXAMPLE
.\deploy\Dump-DeviceInfo.ps1
.\deploy\Dump-DeviceInfo.ps1 -Label gsi-BP4A -Bugreport     # while a GSI is running
#>
[CmdletBinding()]
param([string]$Label, [switch]$Bugreport)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
Import-Module (Join-Path $PSScriptRoot '..\workstation\VedoTom.psm1')   # Assert-OneDevice, Invoke-RootShell (Magisk or AOSP su)
Assert-OneDevice

$Out = Join-Path $Work ('device-info\' + (Get-Date -Format 'yyyyMMdd-HHmmss') + $(if ($Label) { "-$Label" }))
New-Item -ItemType Directory -Force $Out | Out-Null

function Shell([string]$Command) { (& $Adb shell $Command 2>&1) -join "`n" }
function Prop([string]$Name) { (Shell "getprop $Name").Trim() }
$HaveRoot = Test-DeviceRoot
function Root([string]$Command) { if ($HaveRoot) { Invoke-RootShell $Command } else { '(no root)' } }
function Save([string]$File, [string]$Text) { Set-Content -LiteralPath (Join-Path $Out $File) -Value $Text -Encoding utf8 }

# ---- raw dumps (private) ----------------------------------------------------------------------
Save 'getprop.txt'        (Shell 'getprop')
Save 'cpuinfo.txt'        (Shell 'cat /proc/cpuinfo')
Save 'meminfo.txt'        (Shell 'cat /proc/meminfo')
Save 'version.txt'        (Shell 'cat /proc/version')
Save 'df.txt'             (Shell 'df -h')
Save 'features.txt'       (Shell 'pm list features')
Save 'packages.txt'       (Shell 'pm list packages -f')
Save 'display.txt'        (Shell 'dumpsys display')
Save 'battery.txt'        (Shell 'dumpsys battery')
Save 'sensors.txt'        (Shell 'dumpsys sensorservice')
Save 'camera.txt'         (Shell 'dumpsys media.camera')
Save 'surfaceflinger.txt' (Shell 'dumpsys SurfaceFlinger')
Save 'cpufreq.txt'        (Shell 'for c in /sys/devices/system/cpu/cpu[0-9]*; do echo $c $(cat $c/cpufreq/cpuinfo_min_freq 2>/dev/null) $(cat $c/cpufreq/cpuinfo_max_freq 2>/dev/null); done')
Save 'devicetree.txt'     (Root 'cat /proc/device-tree/model; echo; tr ''\000'' ''\n'' < /proc/device-tree/compatible')
Save 'partitions-byname.txt' (Root 'ls -l /dev/block/by-name')
Save 'partitions-proc.txt'   (Root 'cat /proc/partitions')
Save 'partitions-mapper.txt' (Root 'ls -l /dev/block/mapper')
Save 'lshal.txt'             (Root 'lshal 2>/dev/null')
Save 'mounts.txt'            (Shell 'cat /proc/mounts')
# The vendor interface: what the vendor partition offers (its VINTF manifests) and what the running
# system requires (its compatibility matrix). Different systems (stock, a GSI) negotiate the same
# vendor manifest differently; these show how.
Save 'vintf-vendor-manifest.txt'  (Shell 'for f in /vendor/etc/vintf/manifest.xml /vendor/etc/vintf/manifest/*.xml /odm/etc/vintf/manifest.xml /odm/etc/vintf/manifest/*.xml; do [ -f "$f" ] && echo "== $f" && cat "$f"; done 2>&1')
Save 'vintf-system-matrix.txt'    (Shell 'for f in /system/etc/vintf/compatibility_matrix*.xml /system/etc/vintf/manifest.xml; do [ -f "$f" ] && echo "== $f" && cat "$f"; done 2>&1')
Save 'kernel-modules.txt'         (Shell 'cat /proc/modules 2>&1')
Save 'services.txt'               (Shell 'dumpsys -l 2>&1')
Save 'vendor-hal-files.txt'       (Shell 'ls -lR /vendor/bin/hw /vendor/lib64/hw /vendor/etc/init /vendor/firmware 2>&1')
Save 'logcat-all.txt'             ((& $Adb logcat -d -b all 2>&1) -join "`n")
Save 'logcat-crash.txt'           ((& $Adb logcat -d -b crash 2>&1) -join "`n")
if ($Bugreport) {
    Write-Host 'Taking a full bugreport (several minutes) ...' -ForegroundColor Cyan
    & $Adb bugreport (Join-Path $Out 'bugreport.zip') | Out-Null
}

# ---- partition table: by-name symlink -> block device -> size from /proc/partitions ------------
$blocks = @{}
foreach ($l in Get-Content (Join-Path $Out 'partitions-proc.txt')) { if ($l -match '^\s*\d+\s+\d+\s+(\d+)\s+(\S+)$') { $blocks[$Matches[2]] = [long]$Matches[1] } }
function PartitionTable([string]$ListingFile) {
    foreach ($l in Get-Content (Join-Path $Out $ListingFile)) {
        if ($l -match '\s(\S+) -> /dev/block/(\S+)$') {
            $kb = $blocks[$Matches[2]]
            '{0,-24} {1,10} {2}' -f $Matches[1], $(if ($kb) { [math]::Round($kb / 1024, 1) } else { '?' }), $Matches[2]
        }
    }
}
$physical = @(PartitionTable 'partitions-byname.txt' | Sort-Object)
$dynamic  = @(PartitionTable 'partitions-mapper.txt' | Sort-Object)
Save 'partitions.txt' (("name                       size MiB  device`n" + ($physical -join "`n") + "`n`ndynamic (in super):`n" + ($dynamic -join "`n")))

# ---- curated summary (no identifiers) ---------------------------------------------------------
# Every extraction tolerates "no match": a missing value prints as empty rather than failing.
function Rx([string]$File, [string]$Pattern) {
    $text = Get-Content -Raw -LiteralPath (Join-Path $Out $File) -ErrorAction SilentlyContinue
    if (-not $text) { return @() }
    @([regex]::Matches($text, $Pattern) | ForEach-Object { $_.Groups[1].Value.Trim() })
}
$cpuinfo = Get-Content (Join-Path $Out 'cpuinfo.txt')
$cores = @($cpuinfo | Where-Object { $_ -match '^processor' }).Count
# ARM "CPU part" ids for the cores this family of SoCs uses; unknown ids are shown raw.
$partNames = @{ '0xd03' = 'Cortex-A53'; '0xd05' = 'Cortex-A55'; '0xd0a' = 'Cortex-A75'; '0xd0b' = 'Cortex-A76'; '0xd0d' = 'Cortex-A77'; '0xd41' = 'Cortex-A78'; '0xd46' = 'Cortex-A510'; '0xd47' = 'Cortex-A710'; '0xd4d' = 'Cortex-A715'; '0xd80' = 'Cortex-A520'; '0xd81' = 'Cortex-A720' }
$parts = @($cpuinfo | Where-Object { $_ -match '^CPU part' } | ForEach-Object { ($_ -split ':')[1].Trim() } | Group-Object | ForEach-Object { $n = $partNames[$_.Name]; "$($_.Count)x " + $(if ($n) { "$n ($($_.Name))" } else { $_.Name }) })
$freqs = @(Get-Content (Join-Path $Out 'cpufreq.txt') | ForEach-Object { if ($_ -match 'cpu(\d+)\s+(\d+)\s+(\d+)') { "cpu$($Matches[1]): $([math]::Round($Matches[3]/1e6, 2)) GHz" } })
$memKb = [int](@(Rx 'meminfo.txt' '(?m)^MemTotal:\s+(\d+)') + 0)[0]
$gles = (@(Rx 'surfaceflinger.txt' '(?m)^\s*(GLES:.*)$') + '')[0]
$wm = Shell 'wm size'; $density = Shell 'wm density'
$refresh = ((@(Rx 'display.txt' 'mSupportedRefreshRates=\[([^\]]+)\]') + '')[0] -split ',\s*' | ForEach-Object { if ($_) { [math]::Round([double]$_) } } | Sort-Object -Descending | ForEach-Object { "$_ Hz" }) -join ', '
$hdr = (@(Rx 'display.txt' 'mSupportedHdrTypes=\[([^\]]*)\]') + '')[0]
$batteryFull = (Shell 'cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null').Trim()
$cameras = (@(Rx 'camera.txt' 'Number of camera devices:\s*(\d+)') + '?')[0]
$sensorNames = @(Rx 'sensors.txt' '(?m)^0x[0-9a-fA-F]+\)\s+([^|\r\n]+?)\s*\|' | Sort-Object -Unique)
$sensorTypes = @(Rx 'sensors.txt' 'type:\s*android\.sensor\.([a-z_]+)' | Sort-Object -Unique)
$dataTotal = ((Get-Content (Join-Path $Out 'df.txt') | Where-Object { $_ -match '\s/data$' } | Select-Object -First 1) -split '\s+')[1]
$slotA = @($physical | Where-Object { $_ -match '^\S+_a\s' }).Count
$slotB = @($physical | Where-Object { $_ -match '^\S+_b\s' }).Count
$halNames = @(Rx 'lshal.txt' '(?m)^[A-Z ]+\s+[YN?]\s+((?:android|vendor|mediatek)[\w.]+(?:@[\d.]+)?(?:::\w+)?)' | Sort-Object -Unique)
$halCount = $halNames.Count

$crashers = @(Rx 'logcat-crash.txt' '(?m)>>> (\S+) <<<' | Group-Object | Sort-Object Count -Descending | ForEach-Object { "$($_.Name) x$($_.Count)" })
$denials = @(Rx 'logcat-all.txt' 'avc:\s+denied\s+\{[^}]+\}\s+for\s+.*?scontext=u:r:(\w+)' | Group-Object | Sort-Object Count -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Name) x$($_.Count)" })
$summary = @"
Device inventory (identifiers omitted). Raw dumps are beside this file and are private.

Session          build $(Prop ro.build.display.id) ($(Prop ro.build.type)); root over adb: $HaveRoot; crashes since boot: $($crashers -join ', ')
SELinux denials  $(if ($denials) { $denials -join ', ' } else { 'none in logcat' })
Model            $(Prop ro.product.model)  (SKU $(Prop ro.boot.hardware.sku); product $(Prop ro.product.device) / bootloader $(Prop ro.boot.hardware))
Android          $(Prop ro.build.version.release) (SDK $(Prop ro.build.version.sdk)), build $(Prop ro.build.id), patch $(Prop ro.build.version.security_patch)
Fingerprint      $(Prop ro.build.fingerprint)
Kernel           $((Shell 'uname -r').Trim())
Bootloader       $(Prop ro.bootloader)
Verified boot    state=$(Prop ro.boot.verifiedbootstate) flash.locked=$(Prop ro.boot.flash.locked) slot=$(Prop ro.boot.slot_suffix)
SoC              $(Prop ro.soc.manufacturer) $(Prop ro.soc.model)  (ro.hardware=$(Prop ro.hardware), platform=$(Prop ro.board.platform), mediatek.platform=$(Prop ro.vendor.mediatek.platform))
Device tree      $((Get-Content (Join-Path $Out 'devicetree.txt') | Select-Object -First 1))
CPU              $cores cores: $($parts -join ', ') (ARM part ids); $($freqs -join '; ')
GPU              $gles
RAM              $([math]::Round($memKb/1MB, 1)) GiB visible to the kernel
Storage          /data $dataTotal total; UFS/eMMC: $(Prop ro.boot.boot_devices)
Display          $($wm.Trim()); $($density.Trim()); refresh rates: $refresh; HDR types: [$hdr]
Battery          design capacity $batteryFull uAh (charge_full_design, as reported by the kernel)
Cameras          $cameras camera devices (dumpsys media.camera)
Sensors          $($sensorNames.Count) hardware/virtual sensors: $($sensorNames -join ', ')
Sensor types     $($sensorTypes -join ', ')
Partitions       $($physical.Count) physical ($slotA slot-A, $slotB slot-B), $($dynamic.Count) dynamic in super; table in partitions.txt
HALs             $halCount HAL interfaces registered (lshal)
Virtualization   AVF/pKVM: hypervisor.vm.supported='$(Prop ro.boot.hypervisor.vm.supported)' (empty = not supported)
Treble           vndk=$(Prop ro.vndk.version) first_api=$(Prop ro.product.first_api_level) gki=$(Prop ro.boot.gki)
"@
Save 'summary.txt' $summary
Write-Host $summary
Write-Host "`nRaw dumps (private, do not commit): $Out" -ForegroundColor Yellow
