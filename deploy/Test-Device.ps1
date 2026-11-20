<#
.SYNOPSIS
Smoke-tests the development workflows against the connected phone:   .\deploy\Test-Device.ps1

.DESCRIPTION
Test-Workstation.ps1 proves the PC's tools work and never touches the phone. This is the other half:
it exercises each workflow the docs teach, end to end, on whatever system the phone is running
(stock with Magisk, or a VedoTom DSU image), and leaves nothing behind.

  device    identity, build type, SELinux, and which DSU image (if any) is running
  root      a root shell through Invoke-RootShell (Magisk's su on stock, AOSP's su 0 in an image)
  logs      logcat reads, the buffer size, and dumpsys
  native    an aarch64 binary built here with the pinned NDK, pushed, run on the phone, removed
  app       an APK built here with the pinned SDK tools (no Gradle), installed, launched, its log
            line read back, then uninstalled
  debug     adb root and back (userdebug images), and how many processes accept a debugger (JDWP)
  trace     a 2-second Perfetto trace through Trace-Device.ps1, pulled and checked, then deleted
  frida     Start-Frida, frida-ps over USB, Stop-Frida (needs root)
  mirror    scrcpy reaches the device (lists its displays; opens no window)

Exit code = number of failed checks. Run from a dev shell (. .\workstation\Enter-DevShell.ps1).

.PARAMETER Skip
Areas to leave out, e.g. -Skip frida,mirror.
#>
[CmdletBinding()]
param([string[]]$Skip = @())
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot '..\workstation\Enter-DevShell.ps1') | Out-Null
Set-Location $Root
Assert-OneDevice
$Tmp = Join-Path (Split-Path -Parent $PSScriptRoot) 'work\build\device-test'
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

# ---------------- app: the everyday loop (build, install, launch, log, uninstall) with the pinned
# SDK tools alone, no Gradle: javac against android.jar, d8, aapt2, zipalign, apksigner with a
# throwaway key. Proves an app built on this PC runs on the phone's current system.
Check 'app' 'build, install, launch and uninstall an app' {
    $pkg = 'dev.vedotom.probe'
    $btDir = $Bt.FullName; $jar = Join-Path $env:ANDROID_HOME 'platforms\android-36\android.jar'
    $d = Join-Path $Tmp 'app'; New-Item -ItemType Directory -Force (Join-Path $d 'src\dev\vedotom\probe'), (Join-Path $d 'classes'), (Join-Path $d 'dex') | Out-Null
    Set-Content -LiteralPath (Join-Path $d 'AndroidManifest.xml') -Value @"
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="$pkg">
  <application android:label="VedoTom probe" android:hasCode="true">
    <activity android:name=".Main" android:exported="true" />
  </application>
</manifest>
"@
    Set-Content -LiteralPath (Join-Path $d 'src\dev\vedotom\probe\Main.java') -Value @'
package dev.vedotom.probe;
public class Main extends android.app.Activity {
    @Override protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        android.util.Log.i("VedoTomProbe", "app probe ok on sdk " + android.os.Build.VERSION.SDK_INT);
        finish();
    }
}
'@
    & javac --release 11 -nowarn -Xlint:-options -cp $jar -d (Join-Path $d 'classes') (Join-Path $d 'src\dev\vedotom\probe\Main.java') 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'javac failed' }
    & "$btDir\d8.bat" --min-api 26 --lib $jar --output (Join-Path $d 'dex') (Get-ChildItem (Join-Path $d 'classes') -Recurse -Filter *.class).FullName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'd8 failed' }
    $unsigned = Join-Path $d 'unsigned.apk'; $aligned = Join-Path $d 'aligned.apk'; $apk = Join-Path $d 'probe.apk'
    & "$btDir\aapt2.exe" link -o $unsigned -I $jar --manifest (Join-Path $d 'AndroidManifest.xml') --min-sdk-version 26 --target-sdk-version 36 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'aapt2 link failed' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::Open($unsigned, 'Update')
    try { [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z, (Join-Path $d 'dex\classes.dex'), 'classes.dex') } finally { $z.Dispose() }
    & "$btDir\zipalign.exe" -f -p 4 $unsigned $aligned 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'zipalign failed' }
    $ks = Join-Path $d 'probe.jks'
    & keytool -genkeypair -keystore $ks -storepass probepass -keypass probepass -alias probe -keyalg RSA -keysize 2048 -validity 1 -dname 'CN=VedoTom probe' 2>&1 | Out-Null
    & "$btDir\apksigner.bat" sign --ks $ks --ks-pass pass:probepass --out $apk $aligned 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'apksigner failed' }
    $since = Sh "date '+%m-%d %H:%M:%S.000'"
    try {
        $i = (& $adb install -r -t $apk 2>&1) -join ' '
        if ($i -notmatch 'Success') { throw "install: $i" }
        Sh "am start -W -n $pkg/.Main" | Out-Null
        Start-Sleep 2
        $log = (& $adb logcat -d -T $since -s VedoTomProbe 2>$null | Select-String 'app probe ok' | Select-Object -Last 1).Line
        if (-not $log) { throw 'installed, but the activity did not log' }
        $log -replace '^.*VedoTomProbe\s*:\s*', ''
    } finally { & $adb uninstall $pkg 2>&1 | Out-Null }
}

# ---------------- debug: what a debugger can reach
# adb root works only on a real userdebug build (a VedoTom image), not on stock, whose adbd is
# compiled to stay unprivileged even with dev_debuggable's ro.debuggable=1. JDWP (what Android
# Studio's "Attach debugger" uses) reaches every app only on a userdebug build with
# persist.debug.dalvik.vm.jdwp.enabled=1, which zygote reads when it starts (so: set, reboot).
if ($inImage -and (Sh 'getprop ro.build.type') -eq 'userdebug') {
    Check 'debug' 'adb root, then back to unprivileged adbd' {
        try {
            & $adb root 2>&1 | Out-Null; & $adb wait-for-device; Start-Sleep 2
            $id = Sh 'id -u'
            if ($id -ne '0') { throw "adb root gave uid $id" }
            'uid 0 under adb root'
        } finally { & $adb unroot 2>&1 | Out-Null; & $adb wait-for-device; Start-Sleep 2 }
    }
}
Check 'debug' 'processes a debugger can attach to (JDWP)' {
    $o = Join-Path $Tmp 'jdwp.txt'
    $p = Start-Process $adb -ArgumentList 'jdwp' -NoNewWindow -PassThru -RedirectStandardOutput $o
    Start-Sleep 4; if (-not $p.HasExited) { $p.Kill() }
    $n = @(Get-Content $o -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\d+$' }).Count
    $prop = Sh 'getprop persist.debug.dalvik.vm.jdwp.enabled'
    # Informational: a count of 0 is right on a system that doesn't open JDWP for every app.
    if ($n -gt 0) { "$n (persist.debug.dalvik.vm.jdwp.enabled='$prop')" }
    else { "0: only debuggable apps you install (all apps: persist.debug.dalvik.vm.jdwp.enabled=1 on a userdebug build, then reboot)" }
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
