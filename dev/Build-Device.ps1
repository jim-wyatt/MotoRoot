<#
.SYNOPSIS
Rebuilds the device-side artifacts (helper DEX files and Magisk module ZIPs) into dev\build\
and compares them with the committed copies in device\.

.DESCRIPTION
Never overwrites device\ unless -Promote is given, and never talks to the phone.
  - Helpers (device\helpers\*.java -> *.dex): javac --release 8, then D8 from the pinned
    R8 8.3.37. Compared byte for byte. A mismatch usually means a different javac build,
    which changes the debug line tables rather than the bytecode; it is reported, not fatal.
  - Modules (device\modules\manifests\*.json -> device\modules\*.zip): built by
    device\modules\build_modules.py. The build is deterministic (fixed timestamps), so the
    ZIPs are compared by hash.
Run from a dev shell (. .\dev\Enter-DevShell.ps1) so JAVA_HOME is set.

.PARAMETER Promote
Copy each rebuilt artifact that differs over the committed one. Review git diff, then commit
the source and the artifact together.
#>
[CmdletBinding()]
param([switch]$Promote)
$ErrorActionPreference = 'Stop'
$Root   = Split-Path -Parent $PSScriptRoot
$Device = Join-Path $Root 'device'
$Out    = Join-Path $PSScriptRoot 'build'
# The pinned R8 jar, as dev\toolchain.json names it (so a version bump needs no edit here).
$R8Name = ((Get-Content -Raw (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json).jars | Where-Object { $_.name -like 'r8-*' }).name
$R8     = Join-Path $PSScriptRoot ".tools\$R8Name"
$Java   = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin' } else { throw 'JAVA_HOME not set. Run . .\dev\Enter-DevShell.ps1 first.' }
$Py     = Join-Path $Root 'work\.venv\Scripts\python.exe'
if (-not (Test-Path $R8)) { throw 'R8 jar missing. Run .\dev\Bootstrap-DevEnv.ps1.' }
if (-not (Test-Path $Py)) { throw 'work\.venv missing. Run .\dev\Bootstrap-DevEnv.ps1.' }
Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out | Out-Null

function Get-Sha256($Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Compare-Artifact([string]$Label, [string]$Built, [string]$Target) {
    [pscustomobject]@{
        Artifact  = $Label
        Identical = (Test-Path -LiteralPath $Target) -and ((Get-Sha256 $Built) -eq (Get-Sha256 $Target))
        Built     = $Built
        Target    = $Target
    }
}
$Results = @()

# ---- helpers: .java -> .class (javac) -> classes.dex (D8) ----------------------------------
foreach ($Src in Get-ChildItem (Join-Path $Device 'helpers') -Filter *.java) {
    $Name    = $Src.BaseName
    $Classes = Join-Path $Out "classes\$Name"
    $Dex     = Join-Path $Out "dex\$Name"
    New-Item -ItemType Directory -Force $Classes, $Dex | Out-Null
    & "$Java\javac.exe" --release 8 -nowarn -Xlint:-options -d $Classes $Src.FullName
    if ($LASTEXITCODE -ne 0) { throw "javac failed for $Name" }
    [string[]]$ClassFiles = @(Get-ChildItem $Classes -Filter *.class | ForEach-Object FullName)   # array even for one file, so @ splats paths, not characters
    & "$Java\java.exe" -cp $R8 com.android.tools.r8.D8 --min-api 26 --output $Dex @ClassFiles
    if ($LASTEXITCODE -ne 0) { throw "D8 failed for $Name" }
    $Built = Join-Path $Out "$Name.dex"
    Move-Item (Join-Path $Dex 'classes.dex') $Built
    $Results += Compare-Artifact "device\helpers\$Name.dex" $Built (Join-Path $Device "helpers\$Name.dex")
}

# ---- modules: manifests -> deterministic ZIPs ------------------------------------------------
$ModOut = Join-Path $Out 'modules'
& $Py -I (Join-Path $Device 'modules\build_modules.py') --out $ModOut | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'build_modules.py failed' }
foreach ($Zip in Get-ChildItem $ModOut -Filter *.zip) {
    $Results += Compare-Artifact "device\modules\$($Zip.Name)" $Zip.FullName (Join-Path $Device "modules\$($Zip.Name)")
}

$Results | Format-Table Artifact, Identical -AutoSize
if ($Promote) {
    $Changed = @($Results | Where-Object { -not $_.Identical })
    foreach ($R in $Changed) { Copy-Item -LiteralPath $R.Built -Destination $R.Target -Force; Write-Host "promoted $($R.Artifact)" }
    if (-not $Changed) { Write-Host 'Nothing to promote: every artifact already matches.' }
    else { Write-Host 'Review git diff and commit the source and the artifact together.' }
}
