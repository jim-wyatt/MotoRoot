<#
.SYNOPSIS
Dot-source in each PowerShell window:   . .\dev\Enter-DevShell.ps1

Sets the variables GUIDE.md expects, puts the SDK/JDK tools on this window's PATH,
re-verifies the pinned kit inputs, and prints a short status. It does not talk to the
phone and does not change persistent settings.

  $Repo    repository root (this window's working directory)
  $Kit     kit\   - the original upstream guide, helpers, modules, scripts (read-only reference)
  $Work    work\  - downloads, venv, and everything the phone procedure creates (git-ignored)
  $Backup  work\private-backups - your phone's original images. Never share these.
  $adb $fb work\platform-tools (pinned 37.0.1)     $py  work\.venv python (val-protocol)

The kit's pinned platform-tools (37.0.1) come first on PATH, so a bare `adb` is the
tested version. Close Android Studio while following the phone procedure: it runs its
own (newer) ADB server, and two server versions fight over the connection.
#>
$Repo   = Split-Path -Parent $PSScriptRoot
$Kit    = Join-Path $Repo 'kit'
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

$DevPath = @(Join-Path $Work 'platform-tools')
if ($env:JAVA_HOME) { $DevPath += Join-Path $env:JAVA_HOME 'bin' }
if ($env:ANDROID_HOME) {
    $DevPath += Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'
    $Bt = Get-ChildItem (Join-Path $env:ANDROID_HOME 'build-tools') -Directory -ErrorAction SilentlyContinue | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    if ($Bt) { $DevPath += $Bt.FullName }
    $Ndk = Get-ChildItem (Join-Path $env:ANDROID_HOME 'ndk') -Directory -ErrorAction SilentlyContinue | Sort-Object { [version]$_.Name } | Select-Object -Last 1
    if ($Ndk) { $env:ANDROID_NDK_HOME = $Ndk.FullName; $DevPath += $Ndk.FullName }
}
$DevPath += Join-Path $DevTools 'jadx\bin'
$DevPath += Join-Path $Work '.venv\Scripts'
$DevPath += Join-Path $env:ProgramFiles '7-Zip'   # 7-Zip's installer does not add itself to PATH
$env:Path = (($DevPath | Where-Object { Test-Path $_ }) + $env:Path) -join ';'

function global:apktool { & java -jar (Join-Path $DevTools 'apktool_3.0.3.jar') @args }
function global:r8d8    { & java -cp (Join-Path $DevTools 'r8-8.3.37.jar') com.android.tools.r8.D8 @args }
function global:docs    { & (Join-Path $PSScriptRoot '.venv-docs\Scripts\zensical.exe') serve -f (Join-Path $Repo 'zensical.toml') @args }

# ---- status
$Spec = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
$Problems = @()
foreach ($Apk in $Spec.kit.apks) {
    $P = Join-Path $Work $Apk.name
    if (-not (Test-Path $P) -or (Get-FileHash -LiteralPath $P).Hash.ToLower() -ne $Apk.sha256) { $Problems += "$($Apk.name) missing or hash mismatch" }
}
$VpHead = if (Get-Command git -ErrorAction SilentlyContinue) { git -C (Join-Path $Work 'val-protocol') rev-parse HEAD 2>$null } else { $null }
if ($VpHead -ne $Spec.kit.valProtocol.commit) { $Problems += "val-protocol not at pinned commit ($VpHead)" }
if (-not (Test-Path $py)) { $Problems += '.venv missing' }
if (-not (Test-Path $adb)) { $Problems += 'platform-tools missing' }

function Get-ToolVersion($Label, [scriptblock]$Cmd) {
    try { $v = (& $Cmd 2>&1 | Select-Object -First 1) -as [string] } catch { $v = 'not found' }
    '{0,-14} {1}' -f $Label, $v.Trim()
}
Write-Host 'OtomDev dev shell' -ForegroundColor Cyan
Get-ToolVersion 'adb (kit)'   { (& $adb version)[1] }
Get-ToolVersion 'java'        { java -version }
Get-ToolVersion 'android cli' { android --no-metrics --version }
Get-ToolVersion 'build-tools' { if ($Bt) { $Bt.Name } else { 'not installed' } }
Get-ToolVersion 'ndk'         { if ($Ndk) { $Ndk.Name } else { 'not installed' } }
Get-ToolVersion 'python'      { & $py --version }
Get-ToolVersion 'scrcpy'      { scrcpy --version }
Get-ToolVersion 'jadx'        { jadx --version }
Get-ToolVersion 'gh'          { gh --version }
if ($Problems) { $Problems | ForEach-Object { Write-Warning $_ }; Write-Warning 'Run .\dev\Bootstrap-DevEnv.ps1 to fix.' }
else { Write-Host 'Kit inputs: verified' -ForegroundColor Green }
Write-Host 'Guide variables: $Kit $Work $adb $fb $Backup $py   Commands: docs, apktool, r8d8, .\dev\Build-Kit.ps1, .\dev\Test-DevEnv.ps1'
