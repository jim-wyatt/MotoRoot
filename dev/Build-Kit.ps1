<#
.SYNOPSIS
Rebuilds the kit's helpers and modules into dev\build\ and compares them with the committed copies.

.DESCRIPTION
Does not overwrite helpers\*.dex or modules\*.zip, and does not talk to the phone.
  - Helpers: javac --release 8, then D8 from the pinned R8 8.3.37 (same as helpers/BUILD.md).
    The DEX is compared byte for byte. A mismatch usually means a different javac build;
    it is reported, not treated as a failure.
  - Modules: scripts\build_modules.py runs in a staging copy. Its ZIP timestamps change on
    every run, so entries and contents are compared, not the ZIP hash.
Pass -Promote to copy the rebuilt files over the committed ones once you have reviewed the differences.
#>
[CmdletBinding()]
param([switch]$Promote)
$ErrorActionPreference = 'Stop'
$Root  = Split-Path -Parent $PSScriptRoot
$Out   = Join-Path $PSScriptRoot 'build'
$R8    = Join-Path $PSScriptRoot '.tools\r8-8.3.37.jar'
$Java  = if ($env:JAVA_HOME) { Join-Path $env:JAVA_HOME 'bin' } else { throw 'JAVA_HOME not set. Run . .\dev\Enter-DevShell.ps1 first.' }
$Py    = Join-Path $Root '.venv\Scripts\python.exe'
if (-not (Test-Path $R8)) { throw 'R8 jar missing. Run .\dev\Bootstrap-DevEnv.ps1.' }
Remove-Item -Recurse -Force $Out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $Out | Out-Null
$Results = @()

foreach ($Name in 'UpdateHelper', 'UpdaterCleanup') {
    $Classes = Join-Path $Out "classes\$Name"
    $Dex     = Join-Path $Out "dex\$Name"
    New-Item -ItemType Directory -Force $Classes, $Dex | Out-Null
    & "$Java\javac.exe" --release 8 -nowarn -Xlint:-options -d $Classes (Join-Path $Root "helpers\$Name.java")
    if ($LASTEXITCODE -ne 0) { throw "javac failed for $Name" }
    [string[]]$ClassFiles = @(Get-ChildItem $Classes -Filter *.class | ForEach-Object FullName)   # array even for one file, so @ splats paths, not characters
    & "$Java\java.exe" -cp $R8 com.android.tools.r8.D8 --min-api 26 --output $Dex @ClassFiles
    if ($LASTEXITCODE -ne 0) { throw "D8 failed for $Name" }
    $Built = Join-Path $Out "$Name.dex"
    Move-Item (Join-Path $Dex 'classes.dex') $Built
    $Same = (Get-FileHash $Built).Hash -eq (Get-FileHash (Join-Path $Root "helpers\$Name.dex")).Hash
    $Results += [pscustomobject]@{ Artifact = "helpers\$Name.dex"; Identical = $Same; Built = $Built }
}

$Stage = Join-Path $Out 'stage'
New-Item -ItemType Directory -Force (Join-Path $Stage 'scripts') | Out-Null
Copy-Item (Join-Path $Root 'scripts\build_modules.py') (Join-Path $Stage 'scripts')
Copy-Item (Join-Path $Root 'carrier-debloat-manifest.json') $Stage
& $Py -I (Join-Path $Stage 'scripts\build_modules.py') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'build_modules.py failed' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-ZipManifest([string]$Path) {
    $Zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $Zip.Entries | Sort-Object FullName | ForEach-Object {
            $S = $_.Open(); $M = [IO.MemoryStream]::new(); $S.CopyTo($M); $S.Dispose()
            $H = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($M.ToArray()))
            "$($_.FullName) $H"
        }
    } finally { $Zip.Dispose() }
}
foreach ($Zip in 'wifi-ota-guard.zip', 'wifi-carrier-debloat.zip') {
    $Built = Join-Path $Stage "modules\$Zip"
    $Same = -not (Compare-Object (Get-ZipManifest $Built) (Get-ZipManifest (Join-Path $Root "modules\$Zip")))
    $Results += [pscustomobject]@{ Artifact = "modules\$Zip"; Identical = $Same; Built = $Built }
}

$Results | Format-Table Artifact, Identical -AutoSize
if ($Promote) {
    foreach ($R in $Results) { Copy-Item $R.Built (Join-Path $Root $R.Artifact) -Force }
    Write-Host 'Promoted rebuilt artifacts. Update SHA256SUMS.txt and review git diff before committing.'
}
