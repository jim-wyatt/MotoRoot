<#
.SYNOPSIS
Verifies the dev environment end to end:   .\dev\Test-DevEnv.ps1

.DESCRIPTION
Checks pins and versions, and also exercises each tool: compiles and dexes the helpers and
rebuilds the modules (comparing both with the committed copies in device\), decompiles a DEX
with jadx, cross-compiles a C program with the NDK and checks the binary, builds the docs site,
imports val-protocol, re-verifies every pinned device input, and confirms the git safety
settings. It never talks to the phone and never starts an ADB server. Scratch output goes to
dev\build\selftest (git-ignored).
Exit code = number of failed checks.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'Enter-DevShell.ps1') | Out-Null
Set-Location $Root
$Spec = Get-Content -Raw (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
$Tmp  = Join-Path $PSScriptRoot 'build\selftest'
Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Tmp | Out-Null

$Results = [System.Collections.Generic.List[object]]::new()
function Check([string]$Area, [string]$Name, [scriptblock]$Test) {
    try {
        $r = & $Test
        if ($r -is [array]) { $r = $r[-1] }
        $ok = if ($r -is [bool]) { $r } else { [bool]$r }
        $detail = if ($r -is [bool]) { '' } else { "$r" }
        $status = if ($ok) { 'PASS' } else { 'FAIL' }
    } catch { $status = 'FAIL'; $detail = $_.Exception.Message }
    $Results.Add([pscustomobject]@{ Status = $status; Area = $Area; Check = $Name; Detail = $detail })
}
function Warn([string]$Area, [string]$Name, [string]$Detail) { $Results.Add([pscustomobject]@{ Status = 'WARN'; Area = $Area; Check = $Name; Detail = $Detail }) }
function Sha256($p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower() }

# ---------------- environment
Check 'env' 'JAVA_HOME (user) -> JDK 21' { $j = [Environment]::GetEnvironmentVariable('JAVA_HOME','User'); (Test-Path "$j\bin\javac.exe") -and ((& "$j\bin\java.exe" -version 2>&1 | Select-Object -First 1) -match '"21\.') }
Check 'env' 'ANDROID_HOME (user) exists' { Test-Path ([Environment]::GetEnvironmentVariable('ANDROID_HOME','User')) }

# ---------------- Android SDK
$Sdk = $env:ANDROID_HOME
$BtVer = ($Spec.androidSdk.packages | Where-Object { $_ -like 'build-tools/*' }) -replace '^build-tools/'   # the pinned build-tools
Check 'sdk' 'android.exe CLI' { (& "$Sdk\cmdline-tools\latest\bin\android.exe" --no-metrics --version 2>&1 | Select-Object -First 1) }
Check 'sdk' 'platforms/android-36 android.jar' { Test-Path "$Sdk\platforms\android-36\android.jar" }
Check 'sdk' "build-tools $BtVer d8" { $v = & "$Sdk\build-tools\$BtVer\d8.bat" --version 2>&1 | Select-Object -First 1; if ($LASTEXITCODE -eq 0) { "$v" } else { $false } }
Check 'sdk' "build-tools $BtVer aapt2" { $v = & "$Sdk\build-tools\$BtVer\aapt2.exe" version 2>&1 | Select-Object -First 1; if ($LASTEXITCODE -eq 0) { "$v" } else { $false } }
$NdkVer = ($Spec.androidSdk.packages | Where-Object { $_ -like 'ndk/*' }) -replace '^ndk/'
Check 'sdk' "ndk $NdkVer" { Test-Path "$Sdk\ndk\$NdkVer\source.properties" }

# ---------------- pinned tools
foreach ($Jar in $Spec.jars) {
    Check 'tools' $Jar.name {
        $p = Join-Path $PSScriptRoot ".tools\$($Jar.name)"
        if ($Jar.sha256) { (Sha256 $p) -eq $Jar.sha256 } else { (Get-FileHash $p -Algorithm SHA1).Hash.ToLower() -eq $Jar.sha1 }
    }
}
Check 'tools' 'apktool runs' { $v = apktool --version 2>&1; if ($LASTEXITCODE -eq 0) { "$v" } else { $false } }
Check 'tools' 'jadx CLI pinned' { (Get-Content -Raw (Join-Path $PSScriptRoot '.tools\jadx\.pinned-sha256')).Trim() -eq ($Spec.archives | Where-Object extractTo -eq 'jadx').sha256 }
Check 'tools' 'scrcpy + bundled adb = 37.0.1' { $d = Split-Path (Get-Command scrcpy).Source; ((& "$d\adb.exe" version)[1] -match '37\.0\.1') }
# Android Studio uses the SDK's adb. If it ever differs from the pinned copy, the two servers fight over the device.
Check 'tools' 'SDK platform-tools adb = pinned adb (no server fights with Studio)' { $sdkV = (& "$Sdk\platform-tools\adb.exe" version)[1]; $pinV = (& $adb version)[1]; if ($sdkV -eq $pinV) { "$sdkV" } else { throw "SDK ${sdkV} vs pinned ${pinV}: decline the platform-tools update in Studio, or move the pin" } }
Check 'tools' 'gh CLI' { (gh --version | Select-Object -First 1) }
Check 'tools' '7-Zip' { (Get-Command 7z -ErrorAction Stop).Source }
# Optional (Bootstrap -AndroidStudio): a warning, not a failure, when it isn't installed.
if (Test-Path "$env:ProgramFiles\Android\Android Studio\bin\studio64.exe") { Check 'tools' 'Android Studio' { $true } }
else { Warn 'tools' 'Android Studio' 'not installed (optional: .\dev\Bootstrap-DevEnv.ps1 -AndroidStudio)' }

# ---------------- functional builds
# Build-Device prints one Identical=True/False row per artifact: 2 helper DEX files + one ZIP per manifest.
Check 'build' 'helpers + modules reproduce committed copies' {
    $expected = 2 + @(Get-ChildItem (Join-Path $Root 'device\modules\manifests') -Filter *.json).Count
    $o = & (Join-Path $PSScriptRoot 'Build-Device.ps1') 6>&1 2>&1 | Out-String
    if ($o -match 'False') { throw "mismatch:`n$o" }
    ([regex]::Matches($o, 'True')).Count -eq $expected
}
Check 'build' 'module scripts are LF, no BOM, executable in the ZIPs' {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($zipPath in Get-ChildItem (Join-Path $Root 'device\modules') -Filter *.zip) {
        $zip = [IO.Compression.ZipFile]::OpenRead($zipPath.FullName)
        try {
            foreach ($e in $zip.Entries | Where-Object { $_.FullName -like '*.sh' }) {
                $s = $e.Open(); $m = [IO.MemoryStream]::new(); $s.CopyTo($m); $s.Dispose(); $b = $m.ToArray()
                if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { throw "$($zipPath.Name):$($e.FullName) has a BOM" }
                if ([Text.Encoding]::UTF8.GetString($b) -match "`r") { throw "$($zipPath.Name):$($e.FullName) has CR line endings" }
                if ((($e.ExternalAttributes -shr 16) -band 73) -eq 0) { throw "$($zipPath.Name):$($e.FullName) is not executable" }   # 73 = octal 111: any execute bit
            }
        } finally { $zip.Dispose() }
    }
    $true
}
Check 'build' 'module builder unit tests (device\modules\test_build_modules.py)' {
    $o = & $py -m unittest discover -s (Join-Path $Root 'device\modules') -p 'test_*.py' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $o.Trim() }
    ([regex]::Match($o, 'Ran \d+ tests')).Value
}
Check 'build' 'jadx decompiles UpdateHelper.dex' {
    & jadx --quiet -d (Join-Path $Tmp 'jadx') (Join-Path $Root 'device\helpers\UpdateHelper.dex') 2>&1 | Out-Null
    $src = Get-ChildItem (Join-Path $Tmp 'jadx') -Recurse -Filter 'UpdateHelper.java' | Select-Object -First 1
    $src -and ((Get-Content -Raw $src.FullName) -match 'class UpdateHelper')
}
Check 'build' 'NDK cross-compiles aarch64 Android 16 binary' {
    $c = Join-Path $Tmp 'hello.c'; $bin = Join-Path $Tmp 'hello'
    Set-Content -LiteralPath $c -Value '#include <stdio.h>
int main(void) { puts("hello from XT2617V"); return 0; }'
    $cc = "$Sdk\ndk\$NdkVer\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android36-clang.cmd"
    & $cc -O2 -o $bin $c 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'clang failed' }
    $b = [IO.File]::ReadAllBytes($bin)
    # ELF magic, 64-bit, e_machine 0xB7 = AArch64
    ($b[0] -eq 0x7F -and $b[1] -eq 0x45 -and $b[2] -eq 0x4C -and $b[3] -eq 0x46 -and $b[4] -eq 2 -and $b[18] -eq 0xB7)
}
Check 'build' 'javac against android-36 android.jar' {
    $j = Join-Path $Tmp 'Probe.java'
    Set-Content -LiteralPath $j -Value 'public class Probe { public static String v() { return android.os.Build.VERSION.RELEASE; } }'
    & javac --release 8 -nowarn -Xlint:-options -cp "$Sdk\platforms\android-36\android.jar" -d (Join-Path $Tmp 'probe') $j 2>&1 | Out-Null
    $LASTEXITCODE -eq 0
}
Check 'build' 'docs site builds (zensical --strict)' {
    $z = Join-Path $PSScriptRoot '.venv-docs\Scripts\zensical.exe'
    $o = & $z build --strict --clean -f (Join-Path $Root 'zensical.toml') 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw $o.Trim() }
    Test-Path (Join-Path $Root 'site\index.html')
}

# ---------------- device procedure inputs (work\)
Check 'inputs' 'platform-tools 37.0.1 (adb + fastboot)' { ((& $adb version)[1] -match '^Version 37\.0\.1-') -and ((& $fb --version | Select-Object -First 1) -match '37\.0\.1') }
Check 'inputs' 'platform-tools.zip pin' { (Get-FileHash (Join-Path $Work 'platform-tools.zip') -Algorithm SHA1).Hash.ToLower() -eq $Spec.inputs.platformTools.sha1 }
foreach ($Apk in $Spec.inputs.apks) { Check 'inputs' $Apk.name { (Sha256 (Join-Path $Work $Apk.name)) -eq $Apk.sha256 } }
Check 'inputs' 'Test DPC QR' { (Sha256 (Join-Path $Work $Spec.inputs.testDpcQr.name)) -eq $Spec.inputs.testDpcQr.sha256 }
Check 'inputs' 'val-protocol pinned commit, clean tree' { ((git -C work/val-protocol rev-parse HEAD) -eq $Spec.inputs.valProtocol.commit) -and -not (git -C work/val-protocol status --porcelain --untracked-files=no) }
Check 'inputs' 'val-protocol imports in work\.venv' { $o = & $py -c "import sys; sys.path.insert(0,'work/val-protocol'); import capstone, pyasn1, liblk, lk_static_analyzer, lk_auto_patch, lk_patch_partition, lk_repack_signed; print('ok')" 2>&1; "$o" -eq 'ok' }
Check 'inputs' 'Motorola driver installer signed + pinned' { $s = Get-AuthenticodeSignature (Join-Path $Work $Spec.inputs.motorolaDriver.name); $s.Status -eq 'Valid' -and (Sha256 (Join-Path $Work $Spec.inputs.motorolaDriver.name)) -eq $Spec.inputs.motorolaDriver.sha256 }
Check 'inputs' 'Motorola driver installed' { $d = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue | Where-Object DisplayName -match 'Motorola Mobile Drivers' | Select-Object -First 1; if ($d) { "$($d.DisplayName)" } else { $false } }

# ---------------- device tools (work\device-tools, work\.venv-frida)
# On an install PC (work\install-pc, set by Bootstrap-DevEnv.ps1 -InstallPc) the build-only inputs are
# deliberately absent: the build machine has them.
$InstallPc = Test-Path (Join-Path $Work 'install-pc')
$DevDownloads = @($Spec.deviceTools.downloads | Where-Object { -not ($InstallPc -and $_.buildOnly) })
foreach ($Dl in $DevDownloads) { Check 'devtools' "$($Dl.name) pin" { (Sha256 (Join-Path $Work "device-tools\$($Dl.name)")) -eq $Dl.sha256 } }
Check 'devtools' 'frida-server extracted from the pinned archive' {
    $fr = $Spec.deviceTools.downloads | Where-Object extract -eq 'frida-server'
    $st = Join-Path $Work 'device-tools\frida-server.pinned-sha256'
    (Test-Path (Join-Path $Work 'device-tools\frida-server')) -and (Test-Path $st) -and ((Get-Content -Raw $st).Trim() -eq $fr.sha256)
}
# APKs that carry a signerSha256 pin: the signing certificate inside the file must be the publisher's. The hash
# pins the bytes; this pins the identity, so re-pinning a newer version cannot silently accept a differently
# signed build.
foreach ($Dl in ($DevDownloads | Where-Object { $_.signerSha256 })) {
    Check 'devtools' "$($Dl.name) signing certificate" {
        $o = & "$Sdk\build-tools\$BtVer\apksigner.bat" verify --print-certs (Join-Path $Work "device-tools\$($Dl.name)") 2>&1 | Out-String
        if ($o -match 'certificate SHA-256 digest: ([0-9a-f]{64})' -and $Matches[1] -eq $Dl.signerSha256) { $Matches[1].Substring(0, 16) + '...' } else { $false }
    }
}
Check 'devtools' "frida-tools venv = server $($Spec.deviceTools.frida.version)" { $v = (& (Join-Path $Work '.venv-frida\Scripts\frida.exe') --version 2>&1) -as [string]; if ($v.Trim() -eq $Spec.deviceTools.frida.version) { $v.Trim() } else { throw "frida $v, server pin $($Spec.deviceTools.frida.version)" } }
Check 'devtools' 'every dev\ and device\ PowerShell script and module parses' {
    $bad = @()
    $files = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '*') -Include *.ps1, *.psm1 -File) + @(Get-ChildItem (Join-Path $Root 'device\scripts') -Filter *.ps1)
    foreach ($f in $files) {
        $errs = $null; [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs) | Out-Null
        if ($errs) { $bad += "$($f.Name): $(($errs | ForEach-Object Message) -join '; ')" }
    }
    if ($bad) { throw ($bad -join ' | ') }
    "$($files.Count) files"
}
Check 'devtools' 'GSI pin is complete (not downloaded by the bootstrap)' { $g = $Spec.deviceTools.gsi; if ($g.name -and $g.url -and $g.sha256 -match '^[0-9a-f]{64}$' -and $g.url.EndsWith($g.name)) { $g.build } else { throw 'deviceTools.gsi is incomplete' } }
Check 'devtools' 'AOSP pin is complete and dev\aosp scripts are valid bash' {
    $a = $Spec.deviceTools.aosp
    if (-not ($a.tag -match '^android-\d+' -and $a.lunch -and $a.manifest)) { throw 'deviceTools.aosp is incomplete' }
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        foreach ($s in Get-ChildItem (Join-Path $PSScriptRoot 'aosp') -Filter *.sh) {
            if ((Get-Content -Raw $s.FullName) -match "`r") { throw "$($s.Name) has CRLF line endings; bash in WSL will choke" }
            # Default WSL distro (its name varies between machines: Ubuntu, Ubuntu-26.04, ...)
            $p = '/mnt/' + $s.FullName.Substring(0, 1).ToLower() + ($s.FullName.Substring(2) -replace '\\', '/')
            $o = wsl -- bash -n $p 2>&1
            if ($LASTEXITCODE -ne 0) { throw "$($s.Name): $o" }
        }
    }
    $a.tag
}

# ---------------- git safety
Check 'git' 'pre-commit hook active' { (git config core.hooksPath) -eq '.githooks' -and (Test-Path .githooks\pre-commit) }
Check 'git' 'private paths ignored' {
    $paths = 'private-backups/lk_a.img', 'lk-analysis/x.txt', 'lk-patch-analysis/x.txt', 'magisk-patch-files/init_boot.img', 'unlock-keys.txt', 'dev/.tools/x', 'key.pem',
             'release.jks', 'app/local.properties', 'dev/.venv-docs/x', 'site/index.html', 'app/build/x', 'work/anything.txt',
             'work/traces/x.pftrace', 'traces/x.pftrace', 'blobs/vendor.so', 'extracted/x', 'x.pftrace', 'x.perfetto-trace'
    $ignored = @(git check-ignore $paths)
    if ($ignored.Count -ne $paths.Count) { throw "not ignored: $(($paths | Where-Object { $_ -notin $ignored }) -join ', ')" }
    $true
}
Check 'git' 'commit email is GitHub no-reply' { (git config user.email) -match '@users\.noreply\.github\.com$' }
# origin is intentionally PUBLIC. The safety net (ignored paths + pre-commit hook), not
# repo privacy, is what keeps device data out of the public history. Just report visibility.
try {
    $v = gh repo view (git remote get-url origin) --json visibility --jq .visibility 2>$null
    if ($LASTEXITCODE -eq 0) { Check 'git' "origin visibility ($v)" { $v -in 'PUBLIC', 'PRIVATE' } } else { Warn 'git' 'origin visibility' 'gh could not reach GitHub' }
} catch { Warn 'git' 'origin visibility' $_.Exception.Message }

# ---------------- ADB hygiene (read-only: never starts a server)
$adbProcs = Get-Process adb -ErrorAction SilentlyContinue
if ($adbProcs) {
    $paths = $adbProcs | ForEach-Object { $_.Path } | Sort-Object -Unique
    $vers = $paths | ForEach-Object { (& $_ version)[1] } | Sort-Object -Unique
    if (@($vers).Count -gt 1) { Warn 'adb' 'running ADB servers' "multiple versions running: $($vers -join '; ') - run & `$adb kill-server" }
    else { Check 'adb' 'running ADB server version' { "$vers" -match '37\.0\.1' } }
}
if (Get-Process studio64 -ErrorAction SilentlyContinue) { Warn 'adb' 'Android Studio running' 'close it before phone work (its ADB server is newer)' }

# ---------------- report
$Results | Format-Table Status, Area, Check, Detail -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$Fail = @($Results | Where-Object Status -eq 'FAIL').Count
$Warn = @($Results | Where-Object Status -eq 'WARN').Count
Write-Host ("{0} checks: {1} passed, {2} failed, {3} warnings" -f $Results.Count, ($Results.Count - $Fail - $Warn), $Fail, $Warn) -ForegroundColor ($(if ($Fail) { 'Red' } else { 'Green' }))
exit $Fail
