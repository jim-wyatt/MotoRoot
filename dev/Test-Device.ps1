<#
.SYNOPSIS
Smoke-tests the development workflows against the connected phone:   .\dev\Test-Device.ps1

.DESCRIPTION
Test-DevEnv.ps1 proves the PC's tools work and never touches the phone. This is the other half:
it exercises each workflow the docs teach, end to end, on whatever system the phone is running
(stock with Magisk, or a VedoTom DSU image), and leaves nothing behind.

  device    identity, build type, SELinux, and which DSU image (if any) is running
  root      a root shell through Invoke-RootShell (Magisk's su on stock, AOSP's su 0 in an image)
  logs      logcat reads, the buffer size, and dumpsys
  native    an aarch64 binary built here with the pinned NDK, pushed, run on the phone, removed
  trace     a 2-second Perfetto trace through Trace-Device.ps1, pulled and checked, then deleted
  frida     Start-Frida, frida-ps over USB, Stop-Frida (needs root)
  mirror    scrcpy reaches the device (lists its displays; opens no window)

Exit code = number of failed checks. Run from a dev shell (. .\dev\Enter-DevShell.ps1).

.PARAMETER Skip
Areas to leave out, e.g. -Skip frida,mirror.
#>
[CmdletBinding()]
param([string[]]$Skip = @())
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Enter-DevShell.ps1') | Out-Null
Set-Location $Root
Assert-OneDevice
$Tmp = Join-Path $PSScriptRoot 'build\device-test'
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Tmp | Out-Null

$Results = [System.Collections.Generic.List[object]]::new()
function Check([string]$Area, [string]$Name, [scriptblock]$Test) {
    if ($Area -in $Skip) { $Results.Add([pscustomobject]@{ Status = 'SKIP'; Area = $Area; Check = $Name; Detail = '-Skip' }); return }
    try {
        $r = & $Test
        if ($r -is [array]) { $r = $r[-1] }
        $ok = if ($r -is [bool]) { $r } else { [bool]$r }
        $detail = if ($r -is [bool]) { '' } else { "$r" }
        $status = if ($ok) { 'PASS' } else { 'FAIL' }
    } catch { $status = 'FAIL'; $detail = $_.Exception.Message }
    $Results.Add([pscustomobject]@{ Status = $status; Area = $Area; Check = $Name; Detail = $detail })
}
function Sh([string]$Cmd) { ((& $adb shell $Cmd 2>&1) -join "`n").Trim() }

# ---------------- device
$product = Sh 'getprop ro.product.name'
$inImage = Test-GsiRunning
Check 'device' 'identity' { "$(Sh 'getprop ro.product.model') / $product / $(Sh 'getprop ro.build.type') / Android $(Sh 'getprop ro.build.version.release')" }
Check 'device' 'system running' { if ($inImage) { "DSU image: $(Sh 'getprop ro.build.display.id')" } else { "phone's own system: $(Sh 'getprop ro.build.display.id')" } }
Check 'device' 'SELinux enforcing' { (Sh 'getenforce') -eq 'Enforcing' }
Check 'device' 'boot completed' { (Sh 'getprop sys.boot_completed') -eq '1' }

# ---------------- root
$haveRoot = Test-DeviceRoot
Check 'root' 'root shell (Invoke-RootShell)' { if ($haveRoot) { (Invoke-RootShell 'id -Z').Trim() } else { throw 'no root: Magisk Shell grant on stock, or su 0 in a userdebug image' } }

# ---------------- logs
Check 'logs' 'logcat reads' { $n = @(& $adb logcat -d -t 200 2>$null).Count; if ($n -gt 50) { "$n lines" } else { throw "only $n lines" } }
Check 'logs' 'log buffer size' { $g = Sh 'logcat -g -b main'; if ($g -match 'ring buffer is (\S+ \S+)') { $Matches[1] } else { throw $g } }
Check 'logs' 'dumpsys' { $n = @((Sh 'dumpsys -l') -split "`n").Count; if ($n -gt 100) { "$n services" } else { throw "$n services" } }

# ---------------- native: build with the pinned NDK, run on the phone, remove
Check 'native' 'NDK binary runs on the phone' {
    $c = Join-Path $Tmp 'probe.c'; $bin = Join-Path $Tmp 'vedotom-probe'
    Set-Content -LiteralPath $c -Value '#include <stdio.h>
#include <sys/utsname.h>
int main(void) { struct utsname u; uname(&u); printf("probe ok on %s %s\n", u.machine, u.release); return 0; }'
    $cc = Join-Path $env:ANDROID_NDK_HOME 'toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android36-clang.cmd'
    & $cc -O2 -o $bin $c 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'clang failed' }
    & $adb push $bin /data/local/tmp/vedotom-probe | Out-Null
    try { $o = Sh 'chmod 755 /data/local/tmp/vedotom-probe && /data/local/tmp/vedotom-probe' }
    finally { Sh 'rm -f /data/local/tmp/vedotom-probe' | Out-Null }
    if ($o -match '^probe ok on aarch64') { $o } else { throw $o }
}

# ---------------- trace: Perfetto through the project's script
Check 'trace' 'Perfetto 2 s trace (Trace-Device.ps1)' {
    $name = 'device-test-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    & (Join-Path $PSScriptRoot 'Trace-Device.ps1') -Seconds 2 -Name $name *> $null
    $f = Join-Path $Work "traces\$name.pftrace"
    try { if ((Test-Path $f) -and (Get-Item $f).Length -gt 10KB) { '{0:N0} KB' -f ((Get-Item $f).Length / 1KB) } else { throw 'no trace file or empty' } }
    finally { Remove-Item -Force -ErrorAction SilentlyContinue $f, (Join-Path $Work "traces\$name.pbtxt") }
}

# ---------------- frida (root)
Check 'frida' 'frida-server + frida-ps -U' {
    if (-not $haveRoot) { throw 'needs root' }
    Start-Frida *> $null
    try {
        $ps = @(& frida-ps -U 2>&1 | Where-Object { $_ -match '^\s*\d+\s+\S' })
        if ($ps.Count -gt 20) { "$($ps.Count) processes visible" } else { throw "frida-ps saw $($ps.Count) processes" }
    } finally { Stop-Frida }
}

# ---------------- mirror
Check 'mirror' 'scrcpy reaches the device' {
    $env:ADB = $adb
    $o = (& scrcpy --list-displays 2>&1) -join ' '
    if ($o -match '--display-id=0') { 'display 0 listed' } else { throw ($o.Substring(0, [Math]::Min(200, $o.Length))) }
}

# ---------------- report
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
$Results | Format-Table Status, Area, Check, Detail -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$Fail = @($Results | Where-Object Status -eq 'FAIL').Count
Write-Host ("{0} checks: {1} passed, {2} failed, {3} skipped" -f $Results.Count, @($Results | Where-Object Status -eq 'PASS').Count, $Fail, @($Results | Where-Object Status -eq 'SKIP').Count) -ForegroundColor ($(if ($Fail) { 'Red' } else { 'Green' }))
exit $Fail
