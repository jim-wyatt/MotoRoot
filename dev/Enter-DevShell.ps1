<#
.SYNOPSIS
Dot-source in each PowerShell window:   . .\dev\Enter-DevShell.ps1

Moves to the repository root, sets the variables the device walkthrough expects, puts the
SDK/JDK tools on this window's PATH, re-verifies the pinned device inputs, and prints a
short status. It does not talk to the phone and does not change persistent settings.

  $Repo    repository root (this window's working directory after dot-sourcing)
  $Work    work\  - downloads, venv, and everything the device procedure creates (git-ignored)
  $Backup  work\private-backups - your device's original images. Never share these.
  $adb $fb work\platform-tools (pinned 37.0.1)     $py  work\.venv python (val-protocol)

Device-side files (helpers, modules, the Magisk prep script) are referenced relative to
the root: .\device\...

The pinned platform-tools (37.0.1) come first on PATH, so a bare `adb` is the tested
version. Close Android Studio while following the device procedure: it runs its own
(newer) ADB server, and two server versions fight over the connection.
#>
$Repo   = Split-Path -Parent $PSScriptRoot
$Work   = Join-Path $Repo 'work'
$adb    = Join-Path $Work 'platform-tools\adb.exe'
$fb     = Join-Path $Work 'platform-tools\fastboot.exe'
$Backup = Join-Path $Work 'private-backups'
$py     = Join-Path $Work '.venv\Scripts\python.exe'
$DevTools = Join-Path $PSScriptRoot '.tools'
Set-Location $Repo

$env:Path = @([Environment]::GetEnvironmentVariable('Path', 'Machine'), [Environment]::GetEnvironmentVariable('Path', 'User')) -join ';'
if (-not $env:JAVA_HOME)    { $env:JAVA_HOME    = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User') }
if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User') }

$Spec = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json

# The pinned build-tools and NDK (dev\toolchain.json), not whatever is newest: Android Studio
# installs its own versions into the same SDK, and the newest would silently win. If the pinned one
# is missing, fall back to the newest present and say so.
function Get-PinnedSdkDir([string]$Kind) {
    $dir = Join-Path $env:ANDROID_HOME $Kind
    $pin = ($Spec.androidSdk.packages | Where-Object { $_ -like "$Kind/*" }) -replace "^$Kind/"
    if ($pin -and (Test-Path (Join-Path $dir $pin))) { return Get-Item (Join-Path $dir $pin) }
    $newest = Get-ChildItem $dir -Directory -ErrorAction SilentlyContinue | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    if ($newest) { Write-Warning "$Kind $pin (pinned) is not installed; using $($newest.Name). Run .\dev\Bootstrap-DevEnv.ps1." }
    $newest
}
$DevPath = @(Join-Path $Work 'platform-tools')
if ($env:JAVA_HOME) { $DevPath += Join-Path $env:JAVA_HOME 'bin' }
if ($env:ANDROID_HOME) {
    $DevPath += Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'
    $Bt = Get-PinnedSdkDir 'build-tools'
    if ($Bt) { $DevPath += $Bt.FullName }
    $Ndk = Get-PinnedSdkDir 'ndk'
    if ($Ndk) { $env:ANDROID_NDK_HOME = $Ndk.FullName; $DevPath += $Ndk.FullName }
}
$DevPath += Join-Path $DevTools 'jadx\bin'
$DevPath += Join-Path $Work '.venv\Scripts'
$DevPath += Join-Path $Work '.venv-frida\Scripts'   # frida, frida-ps, frida-trace
$DevPath += Join-Path $env:ProgramFiles '7-Zip'   # 7-Zip's installer does not add itself to PATH
$env:Path = (($DevPath | Where-Object { Test-Path $_ }) + $env:Path) -join ';'

# Device helpers (Assert-OneDevice, Invoke-RootShell, Wait-DeviceBoot, Test-GsiRunning, ...) for this
# window too. -Force picks up edits to the module when the shell is re-entered.
Import-Module (Join-Path $PSScriptRoot 'VedoTom.psm1') -Global -Force

# Jar names come from the pins, so bumping a version in toolchain.json needs no edit here.
$global:VedoTomApktoolJar = Join-Path $DevTools (($Spec.jars | Where-Object { $_.name -like 'apktool*' }).name)
$global:VedoTomR8Jar      = Join-Path $DevTools (($Spec.jars | Where-Object { $_.name -like 'r8-*' }).name)
function global:apktool { & java -jar $global:VedoTomApktoolJar @args }
function global:r8d8    { & java -cp $global:VedoTomR8Jar com.android.tools.r8.D8 @args }
function global:docs    { & (Join-Path $PSScriptRoot '.venv-docs\Scripts\zensical.exe') serve -f (Join-Path $Repo 'zensical.toml') @args }
# Connect ADB over Wi-Fi: reads the phone's Wi-Fi address over USB, then connects to port 5555
# (listening from boot with the dev_adb_tcp module, or after `& $adb tcpip 5555`).
function global:adbwifi {
    $line = (& $adb shell ip -4 -o addr show wlan0 2>$null) -join ' '
    if ($line -notmatch 'inet (\d+\.\d+\.\d+\.\d+)/(\d+)') { Write-Warning 'Could not read the phone''s Wi-Fi address over USB (cable in, Wi-Fi on?).'; return }
    $phone = $Matches[1]; $prefix = [int]$Matches[2]
    # The PC must be on the phone's network. A different subnet (two routers, guest Wi-Fi, wired vs wireless)
    # is the usual reason for a silent timeout, so say so instead of waiting on it.
    $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix))
    $toInt = { param($ip) $b = ([IPAddress]$ip).GetAddressBytes(); [Array]::Reverse($b); [BitConverter]::ToUInt32($b, 0) }
    $pcAddrs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | ForEach-Object IPAddress)
    $same = @($pcAddrs | Where-Object { ((& $toInt $_) -band $mask) -eq ((& $toInt $phone) -band $mask) })
    if (-not $same) { Write-Warning "The phone is on $phone/$prefix but this PC's addresses are $($pcAddrs -join ', '): different networks. Join the PC to the phone's Wi-Fi (or the phone to the PC's) and retry."; return }
    & $adb connect "${phone}:5555"
}
# Start Frida's agent on the device as root (idempotent) so frida-ps / frida-trace work from this PC.
function global:Start-Frida {
    $bin = Join-Path $Work 'device-tools\frida-server'
    if (-not (Test-Path $bin)) { Write-Warning 'frida-server not downloaded. Run .\dev\Bootstrap-DevEnv.ps1.'; return }
    # Must run as root; a server started as shell can list processes but not inject into most of them.
    # Invoke-RootShell (dev\VedoTom.psm1) uses Magisk's su on stock and AOSP's in a DSU image.
    $running = (Invoke-RootShell 'ps -A -o USER,NAME | grep -w frida-server').Trim()
    if ($running -match '^root\s') { Write-Host 'frida-server already running as root'; return }
    if ($running) { Stop-Frida }
    & $adb push $bin /data/local/tmp/frida-server | Out-Null
    Invoke-RootShell 'chmod 755 /data/local/tmp/frida-server; nohup /data/local/tmp/frida-server >/dev/null 2>&1 &' | Out-Null
    Start-Sleep 1
    Write-Host ("frida-server: " + (Invoke-RootShell 'ps -A -o USER,PID,NAME | grep -w frida-server').Trim())
    & frida-ps -U 2>&1 | Select-Object -First 3
}
function global:Stop-Frida { Invoke-RootShell 'pkill -x frida-server' | Out-Null; Start-Sleep 1 }

# ---- status
$Spec = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
$Problems = @()
foreach ($Apk in $Spec.inputs.apks) {
    $P = Join-Path $Work $Apk.name
    if (-not (Test-Path $P) -or (Get-FileHash -LiteralPath $P).Hash.ToLower() -ne $Apk.sha256) { $Problems += "$($Apk.name) missing or hash mismatch" }
}
$VpHead = if (Get-Command git -ErrorAction SilentlyContinue) { git -C (Join-Path $Work 'val-protocol') rev-parse HEAD 2>$null } else { $null }
if ($VpHead -ne $Spec.inputs.valProtocol.commit) { $Problems += "val-protocol not at pinned commit ($VpHead)" }
if (-not (Test-Path $py)) { $Problems += '.venv missing' }
if (-not (Test-Path $adb)) { $Problems += 'platform-tools missing' }

function Get-ToolVersion($Label, [scriptblock]$Cmd) {
    try { $v = (& $Cmd 2>&1 | Select-Object -First 1) -as [string] } catch { $v = 'not found' }
    '{0,-14} {1}' -f $Label, $v.Trim()
}
Write-Host 'VedoTom dev shell' -ForegroundColor Cyan
Get-ToolVersion 'adb (pinned)' { (& $adb version)[1] }
Get-ToolVersion 'java'        { java -version }
Get-ToolVersion 'android cli' { android --no-metrics --version }
Get-ToolVersion 'build-tools' { if ($Bt) { $Bt.Name } else { 'not installed' } }
Get-ToolVersion 'ndk'         { if ($Ndk) { $Ndk.Name } else { 'not installed' } }
Get-ToolVersion 'python'      { & $py --version }
Get-ToolVersion 'scrcpy'      { scrcpy --version }
Get-ToolVersion 'jadx'        { jadx --version }
Get-ToolVersion 'gh'          { gh --version }
if ($Problems) { $Problems | ForEach-Object { Write-Warning $_ }; Write-Warning 'Run .\dev\Bootstrap-DevEnv.ps1 to fix.' }
else { Write-Host 'Device inputs: verified' -ForegroundColor Green }
Write-Host 'Variables: $Work $adb $fb $Backup $py   Commands: docs, apktool, r8d8, adbwifi, Start-Frida, Stop-Frida, Invoke-RootShell, .\dev\Set-DevSettings.ps1, .\dev\Trace-Device.ps1, .\dev\Build-Device.ps1, .\dev\Test-DevEnv.ps1, .\dev\Test-Device.ps1'
