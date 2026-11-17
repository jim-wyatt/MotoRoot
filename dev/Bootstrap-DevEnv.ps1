<#
.SYNOPSIS
Bootstraps the Android development environment for this repository on Windows.

.DESCRIPTION
Idempotent: re-run any time. Every download is pinned in dev\toolchain.json and
hash-verified before use. Nothing here talks to a phone.

Installs or verifies:
  - winget tools: OpenJDK 21, Git, GitHub CLI, scrcpy, jadx, 7-Zip (+ Android Studio with -AndroidStudio)
  - Android SDK (cmdline-tools, platform-tools, android-36 platform, build-tools, NDK)
  - Pinned JARs in dev\.tools: R8 8.3.37 (reference helper build), apktool
  - The device procedure's exact inputs: platform-tools 37.0.1, DFRoot/KernelSU/Magisk APKs,
    Test DPC QR image, val-protocol at its pinned commit, Motorola driver (verify only)
  - work\.venv with val-protocol requirements; dev\.venv-docs with Zensical (docs site)
Downloads and generated files go in work\ (the walkthrough's $Work).
  - Git hooks (.githooks) that block committing device images and identifiers

.PARAMETER AndroidStudio
Also install Android Studio (large; not needed for the device procedure or helper builds).

.PARAMETER AcceptAndroidSdkLicenses
Accept the Android SDK licenses non-interactively. Without it, sdkmanager asks you
to review them in this console (which requires an interactive window).

.EXAMPLE
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1
#>
[CmdletBinding()]
param(
    [switch]$AndroidStudio,
    [switch]$AcceptAndroidSdkLicenses,
    [switch]$SkipWinget,
    [switch]$SkipSdk,
    [switch]$SkipInputs
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is far faster without the progress bar

$Root  = Split-Path -Parent $PSScriptRoot
$Work  = Join-Path $Root 'work'   # the walkthrough's $Work: downloads, venv, backups, outputs (git-ignored)
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Spec  = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
$Cache = Join-Path $PSScriptRoot '.cache'
$Tools = Join-Path $PSScriptRoot '.tools'
New-Item -ItemType Directory -Force -Path $Cache, $Tools | Out-Null

if ($Root -like '\\*') { throw "Run from a local NTFS folder, not a network/WSL path ($Root)." }

function Write-Step($Text) { Write-Host "`n== $Text" -ForegroundColor Cyan }
function Write-Ok($Text)   { Write-Host "   OK  $Text" -ForegroundColor Green }
function Write-Note($Text) { Write-Host "   ..  $Text" }

function Update-SessionPath {
    $env:Path = @(
        [Environment]::GetEnvironmentVariable('Path', 'Machine'),
        [Environment]::GetEnvironmentVariable('Path', 'User')
    ) -join ';'
}

function Test-FileHash([string]$Path, [string]$Algorithm, [string]$Expected) {
    (Test-Path -LiteralPath $Path) -and
        ((Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash.ToLower() -eq $Expected.ToLower())
}

# Downloads $Url to $Dest unless $Dest already matches; verifies before moving into place.
function Get-PinnedFile([string]$Url, [string]$Dest, [string]$Algorithm, [string]$Expected) {
    $Name = Split-Path -Leaf $Dest
    if (Test-FileHash $Dest $Algorithm $Expected) { Write-Ok "$Name (hash verified)"; return }
    if (Test-Path -LiteralPath $Dest) { throw "$Name exists but its $Algorithm does not match the pin. Inspect or delete it; not overwriting." }
    $Partial = "$Dest.partial"
    Write-Note "downloading $Name"
    Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Partial
    if (-not (Test-FileHash $Partial $Algorithm $Expected)) {
        Remove-Item -LiteralPath $Partial -Force
        throw "Hash mismatch for $Name from $Url. Stop: do not substitute another source."
    }
    Move-Item -LiteralPath $Partial -Destination $Dest
    Write-Ok "$Name (downloaded, hash verified)"
}

function Set-UserEnv([string]$Name, [string]$Value) {
    if ([Environment]::GetEnvironmentVariable($Name, 'User') -ne $Value) {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
        Write-Note "set user environment variable $Name=$Value"
    }
    Set-Item -Path "env:$Name" -Value $Value
}

# ---------------------------------------------------------------- winget tools
if (-not $SkipWinget) {
    Write-Step 'winget tools'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget is not available. Install "App Installer" from the Microsoft Store.' }
    foreach ($Pkg in $Spec.winget) {
        if ($Pkg.optional -and -not (Get-Variable -Name $Pkg.switch -ValueOnly)) { Write-Note "skip $($Pkg.id) (pass -$($Pkg.switch))"; continue }
        & winget list -e --id $Pkg.id --accept-source-agreements *> $null
        if ($LASTEXITCODE -eq 0) { Write-Ok $Pkg.id; continue }
        Write-Note "installing $($Pkg.id) - $($Pkg.purpose)"
        & winget install -e --id $Pkg.id --silent --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) { throw "winget install $($Pkg.id) failed ($LASTEXITCODE)." }
        Write-Ok $Pkg.id
    }
    Update-SessionPath
}

# ---------------------------------------------------------------- JDK
Write-Step 'JDK 21'
$Jdk = $env:JAVA_HOME
if (-not $Jdk -or -not (Test-Path (Join-Path $Jdk 'bin\javac.exe'))) {
    $Jdk = Get-ChildItem 'C:\Program Files\Microsoft' -Directory -Filter 'jdk-21*' -ErrorAction SilentlyContinue |
        Sort-Object Name | Select-Object -Last 1 -ExpandProperty FullName
}
if (-not $Jdk) { throw 'JDK 21 not found. Re-run without -SkipWinget, or set JAVA_HOME.' }
Set-UserEnv 'JAVA_HOME' $Jdk
Write-Ok ((& (Join-Path $Jdk 'bin\java.exe') -version 2>&1 | Select-Object -First 1) -as [string])

# ---------------------------------------------------------------- Android SDK
if (-not $SkipSdk) {
    Write-Step 'Android SDK'
    $Sdk = $env:ANDROID_HOME
    if (-not $Sdk) { $Sdk = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User') }
    if (-not $Sdk) { $Sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
    New-Item -ItemType Directory -Force -Path $Sdk | Out-Null
    Set-UserEnv 'ANDROID_HOME' $Sdk

    $SdkManager = Join-Path $Sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path $SdkManager)) {
        $Ct = $Spec.androidSdk.cmdlineTools
        $Zip = Join-Path $Cache (Split-Path -Leaf $Ct.url)
        Get-PinnedFile $Ct.url $Zip 'SHA1' $Ct.sha1
        $Tmp = Join-Path $Cache 'cmdline-tools-extract'
        Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $Zip -DestinationPath $Tmp
        New-Item -ItemType Directory -Force -Path (Join-Path $Sdk 'cmdline-tools') | Out-Null
        Move-Item (Join-Path $Tmp 'cmdline-tools') (Join-Path $Sdk 'cmdline-tools\latest')
        Remove-Item -Recurse -Force $Tmp
    }
    Write-Ok "cmdline-tools at $Sdk\cmdline-tools\latest"

    $LicenseDir = Join-Path $Sdk 'licenses'
    $HaveLicenses = (Test-Path $LicenseDir) -and (Get-ChildItem $LicenseDir -File -ErrorAction SilentlyContinue)
    if ($AcceptAndroidSdkLicenses) {
        Write-Note 'accepting Android SDK licenses (-AcceptAndroidSdkLicenses)'
        (1..30 | ForEach-Object { 'y' }) | & $SdkManager --sdk_root=$Sdk --licenses *> $null
    } elseif (-not $HaveLicenses) {
        if ([Console]::IsInputRedirected) {
            throw 'Android SDK licenses not yet accepted. Run this script in an interactive window, or pass -AcceptAndroidSdkLicenses after reviewing them.'
        }
        Write-Note 'review and accept the Android SDK licenses:'
        & $SdkManager --sdk_root=$Sdk --licenses
    }

    # cmdline-tools 23+ ship android.exe; sdkmanager.bat is a deprecated wrapper around it.
    # Call the .exe directly: through a .bat, cmd would split package names. --no-metrics opts out of CLI usage telemetry.
    $AndroidCli = Join-Path $Sdk 'cmdline-tools\latest\bin\android.exe'
    if (-not (Test-Path $AndroidCli)) { throw "android.exe not found in cmdline-tools; pinned cmdline-tools must be 23.0 or newer." }
    foreach ($Pkg in $Spec.androidSdk.packages) {
        Write-Note "installing/verifying $Pkg"
        & $AndroidCli --no-metrics --sdk=$Sdk sdk install $Pkg
        if ($LASTEXITCODE -ne 0) { throw "android sdk install $Pkg failed ($LASTEXITCODE)." }
    }
    $Installed = (& $AndroidCli --no-metrics --sdk=$Sdk sdk list 2>&1) -join "`n"
    $Missing = $Spec.androidSdk.packages | Where-Object { $Installed -notmatch "(?m)^\s*$([regex]::Escape($_))\s" }
    if ($Missing) { throw "SDK packages not installed after install step: $($Missing -join ', ')" }
    Write-Ok "SDK packages installed: $($Spec.androidSdk.packages -join ', ')"
}

# ---------------------------------------------------------------- pinned JARs
Write-Step 'Pinned JARs (dev\.tools)'
foreach ($Jar in $Spec.jars) {
    if ($Jar.sha256) { Get-PinnedFile $Jar.url (Join-Path $Tools $Jar.name) 'SHA256' $Jar.sha256 }
    else             { Get-PinnedFile $Jar.url (Join-Path $Tools $Jar.name) 'SHA1'   $Jar.sha1 }
}
foreach ($Arc in $Spec.archives) {
    $Zip = Join-Path $Cache $Arc.name
    Get-PinnedFile $Arc.url $Zip 'SHA256' $Arc.sha256
    $Dest = Join-Path $Tools $Arc.extractTo
    $Stamp = Join-Path $Dest '.pinned-sha256'
    if (-not (Test-Path $Stamp) -or (Get-Content -Raw $Stamp).Trim() -ne $Arc.sha256) {
        Remove-Item -Recurse -Force $Dest -ErrorAction SilentlyContinue
        Expand-Archive -LiteralPath $Zip -DestinationPath $Dest
        Set-Content -LiteralPath $Stamp -Value $Arc.sha256
    }
    Write-Ok "$($Arc.extractTo) extracted from $($Arc.name)"
}

# ---------------------------------------------------------------- device procedure inputs
if (-not $SkipInputs) {
    Write-Step 'Device procedure inputs (exact tested versions)'
    $Pt = $Spec.inputs.platformTools
    $PtZip = Join-Path $Work 'platform-tools.zip'
    Get-PinnedFile $Pt.url $PtZip 'SHA1' $Pt.sha1
    $Adb = Join-Path $Work 'platform-tools\adb.exe'
    # adb prints "Android Debug Bridge version 1.0.41" then "Version 37.0.1-<build>"; match the second line only.
    function Get-AdbVersion { (& $Adb version | Select-String -CaseSensitive '^Version (\S+)').Matches.Groups[1].Value }
    $AdbVersion = if (Test-Path $Adb) { Get-AdbVersion } else { $null }
    if ($AdbVersion -notlike "$($Pt.version)-*") {
        if (Test-Path (Join-Path $Work 'platform-tools')) { throw "platform-tools\ holds $AdbVersion, not $($Pt.version). Close any ADB server, remove the folder, and re-run." }
        Expand-Archive -LiteralPath $PtZip -DestinationPath $Work
        $AdbVersion = Get-AdbVersion
    }
    Write-Ok "platform-tools $AdbVersion"

    foreach ($Apk in $Spec.inputs.apks) { Get-PinnedFile $Apk.url (Join-Path $Work $Apk.name) 'SHA256' $Apk.sha256 }
    $Qr = $Spec.inputs.testDpcQr
    Get-PinnedFile $Qr.url (Join-Path $Work $Qr.name) 'SHA256' $Qr.sha256

    $Vp = $Spec.inputs.valProtocol
    $VpDir = Join-Path $Work 'val-protocol'
    if (-not (Test-Path (Join-Path $VpDir '.git'))) {
        & git clone --quiet $Vp.repo $VpDir
        if ($LASTEXITCODE -ne 0) { throw 'git clone val-protocol failed.' }
        & git -C $VpDir checkout --quiet --detach $Vp.commit
    }
    $VpHead = & git -C $VpDir rev-parse HEAD
    if ($VpHead -ne $Vp.commit) { Write-Warning "val-protocol is at $VpHead, not the pinned $($Vp.commit). Left untouched." }
    else { Write-Ok "val-protocol @ $($Vp.commit.Substring(0,12))" }

    $Drv = $Spec.inputs.motorolaDriver
    $Msi = Join-Path $Work $Drv.name
    if (-not (Test-Path $Msi)) {
        Write-Warning "$($Drv.name) not present. Download it from $($Drv.page) into $Work and re-run to verify."
    } else {
        $Sig = Get-AuthenticodeSignature -LiteralPath $Msi
        if ($Sig.Status -ne 'Valid' -or $Sig.SignerCertificate.Subject -notmatch [regex]::Escape($Drv.signer)) {
            throw "Motorola driver signature invalid: $($Sig.Status) $($Sig.SignerCertificate.Subject)"
        }
        if (Test-FileHash $Msi 'SHA256' $Drv.sha256) { Write-Ok "$($Drv.name) (signature valid, hash matches reference)" }
        else { Write-Warning "$($Drv.name) is validly Motorola-signed but differs from the reference hash (likely a newer driver)." }
    }
}

# ---------------------------------------------------------------- device tools (optional, work\device-tools)
if (-not $SkipInputs) {
    Write-Step 'Device tools (Frida server, Termux, F-Droid)'
    $ToolDir = Join-Path $Work 'device-tools'
    New-Item -ItemType Directory -Force -Path $ToolDir | Out-Null
    foreach ($Dl in $Spec.deviceTools.downloads) {
        $File = Join-Path $ToolDir $Dl.name
        Get-PinnedFile $Dl.url $File 'SHA256' $Dl.sha256
        if ($Dl.extract) {
            # .xz archives: 7-Zip extracts the single inner file; rename it to the documented name.
            $Extracted = Join-Path $ToolDir $Dl.extract
            if (-not (Test-Path $Extracted)) {
                $SevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
                if (-not (Test-Path $SevenZip)) { throw '7-Zip not found; re-run without -SkipWinget.' }
                & $SevenZip e -y "-o$ToolDir" $File | Out-Null
                if ($LASTEXITCODE -ne 0) { throw "7-Zip failed to extract $($Dl.name)" }
                Move-Item (Join-Path $ToolDir ($Dl.name -replace '\.xz$', '')) $Extracted
            }
            Write-Ok "$($Dl.extract) extracted"
        }
    }
}

# ---------------------------------------------------------------- Python venvs
# Three separate venvs: work\.venv runs val-protocol (bootloader patching) and is kept minimal;
# work\.venv-frida holds the Frida PC tools, pinned to the server version; dev\.venv-docs builds
# the documentation site. Never mix them.
function New-Venv([string]$Dir) {
    $VPy = Join-Path $Dir 'Scripts\python.exe'
    $Cfg = Join-Path $Dir 'pyvenv.cfg'
    if ((Test-Path $VPy) -and (Test-Path $Cfg)) {
        # A venv records the absolute path it was created at, and its Scripts\*.exe launchers embed it.
        # If the repository folder has been moved or renamed since, those launchers exit 1 with no output.
        $Recorded = Select-String -Path $Cfg -Pattern '^command\s*=.*-m venv\s+(.+?)\s*$' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1
        if ($Recorded -and $Recorded.TrimEnd('\') -ne $Dir.TrimEnd('\')) {
            Write-Warning "$Dir was created at $Recorded (repository moved?). Recreating it."
            Remove-Item -Recurse -Force $Dir
        }
    }
    if (-not (Test-Path $VPy)) {
        $SysPy = (Get-Command python -ErrorAction SilentlyContinue).Source
        $Ver = if ($SysPy) { & $SysPy -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>$null } else { $null }
        if (-not $Ver -or [version]$Ver -lt [version]'3.11') { throw 'Python 3.11+ not found. winget install -e --id Python.Python.3.12, open a new window, re-run.' }
        & $SysPy -m venv $Dir
    }
    $VPy
}
Write-Step 'Python venv for val-protocol (work\.venv)'
$VenvPy = New-Venv (Join-Path $Work '.venv')
$Req = Join-Path $Work 'val-protocol\requirements.txt'
if (Test-Path $Req) {
    & $VenvPy -m pip install --quiet --disable-pip-version-check -r $Req pyasn1
    if ($LASTEXITCODE -ne 0) { throw 'pip install failed.' }
}
Write-Ok ((& $VenvPy --version) -as [string])

Write-Step 'Python venv for Frida tools (work\.venv-frida)'
$Fr = $Spec.deviceTools.frida
$FridaPy = New-Venv (Join-Path $Work '.venv-frida')
& $FridaPy -m pip install --quiet --disable-pip-version-check "frida==$($Fr.version)" "frida-tools==$($Fr.toolsVersion)"
if ($LASTEXITCODE -ne 0) { throw 'pip install (frida) failed.' }
Write-Ok ((& (Join-Path $Work '.venv-frida\Scripts\frida.exe') --version) -as [string])

Write-Step 'Python venv for docs (dev\.venv-docs)'
$DocsPy = New-Venv (Join-Path $PSScriptRoot '.venv-docs')
& $DocsPy -m pip install --quiet --disable-pip-version-check -r (Join-Path $Root 'docs\requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install (docs) failed.' }
Write-Ok ((& (Join-Path $PSScriptRoot '.venv-docs\Scripts\zensical.exe') --version) -as [string])

# ---------------------------------------------------------------- git hooks
Write-Step 'Git hooks'
& git -C $Root config core.hooksPath .githooks
Write-Ok 'core.hooksPath = .githooks (blocks images, large binaries, private folders, IMEI-like numbers)'

Write-Host "`nDone. In each new PowerShell window:  . .\dev\Enter-DevShell.ps1" -ForegroundColor Cyan
