<#
.SYNOPSIS
Records a Perfetto system trace on the connected device and pulls it into work\traces\.

.DESCRIPTION
Perfetto is Android's built-in tracing system (the `perfetto` command and the `traced`
daemons ship in the firmware; nothing is installed). This script sends a text config over
ADB, records for -Seconds, pulls the .pftrace file to work\traces\<Name>.pftrace, and deletes
the copy on the device. Open the file at https://ui.perfetto.dev (drag it onto the page; the
UI runs locally in the browser and the trace is not uploaded).

The default config records CPU scheduling and frequency, process and memory stats, the
system log, and the usual atrace categories for app and UI work. Pass -Config to use your own
text config (see https://perfetto.dev/docs/concepts/config).

No root is needed. Reproduce whatever you want to look at on the phone while it records.

.PARAMETER Seconds
Trace length. Default 10.

.PARAMETER Name
File name without extension. Default: a timestamp.

.PARAMETER Config
Path to a Perfetto text (pbtxt) config to use instead of the built-in one.

.EXAMPLE
.\dev\Trace-Device.ps1 -Seconds 15 -Name app-launch
#>
[CmdletBinding()]
param(
    [int]$Seconds = 10,
    [string]$Name = (Get-Date -Format 'yyyyMMdd-HHmmss'),
    [string]$Config
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
if ($Seconds -lt 1 -or $Seconds -gt 600) { throw 'Seconds must be between 1 and 600.' }
if ($Name -notmatch '^[A-Za-z0-9._-]+$') { throw 'Name may contain only letters, digits, dot, underscore and dash.' }

Import-Module (Join-Path $PSScriptRoot 'VedoTom.psm1')
Assert-OneDevice

$ConfigText = if ($Config) { Get-Content -Raw -LiteralPath $Config } else { @"
buffers: { size_kb: 65536 fill_policy: RING_BUFFER }
data_sources: {
  config {
    name: "linux.ftrace"
    ftrace_config {
      ftrace_events: "sched/sched_switch"
      ftrace_events: "sched/sched_wakeup"
      ftrace_events: "power/cpu_frequency"
      ftrace_events: "power/cpu_idle"
      atrace_categories: "am"
      atrace_categories: "binder_driver"
      atrace_categories: "gfx"
      atrace_categories: "input"
      atrace_categories: "view"
      atrace_categories: "wm"
      atrace_apps: "*"
    }
  }
}
data_sources: { config { name: "linux.process_stats" process_stats_config { scan_all_processes_on_start: true proc_stats_poll_ms: 1000 } } }
data_sources: { config { name: "android.log" } }
duration_ms: $($Seconds * 1000)
"@ }

$Remote = "/data/misc/perfetto-traces/$Name.pftrace"
$LocalDir = Join-Path $Work 'traces'
New-Item -ItemType Directory -Force $LocalDir | Out-Null
$Local = Join-Path $LocalDir "$Name.pftrace"
if (Test-Path -LiteralPath $Local) { throw "Trace already exists: $Local" }

# The config goes over as a file (reading it from adb's stdin works but warns about the missing PTY).
# SELinux lets perfetto read configs only from /data/misc/perfetto-configs, not /data/local/tmp.
$RemoteConfig = "/data/misc/perfetto-configs/$Name.pbtxt"
$LocalConfig = Join-Path $LocalDir "$Name.pbtxt"
Set-Content -LiteralPath $LocalConfig -Value $ConfigText -Encoding ascii -NoNewline
& $Adb push $LocalConfig $RemoteConfig | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'config push failed' }
$Length = if ($Config) { 'for the duration in the config' } else { "for $Seconds s" }
Write-Host "Recording $Length to $Remote ... reproduce what you want to see on the phone now." -ForegroundColor Cyan
& $Adb shell perfetto --txt -c $RemoteConfig -o $Remote
if ($LASTEXITCODE -ne 0) { throw 'perfetto failed on the device (is persist.traced.enable=1?).' }
& $Adb shell rm -f $RemoteConfig | Out-Null
& $Adb pull $Remote $Local | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'pull failed' }
& $Adb shell rm -f $Remote | Out-Null
$Size = [math]::Round((Get-Item -LiteralPath $Local).Length / 1MB, 1)
Write-Host "Saved $Local ($Size MB). Open https://ui.perfetto.dev and drag the file onto the page." -ForegroundColor Green
