<#
.SYNOPSIS
    Puts Organic Maps offline map files onto the phone over ADB, from a verified local copy.

.DESCRIPTION
    Organic Maps lists every downloadable region, with its file size, in the catalogue it ships
    inside its APK (assets/countries.json, data version "v"). This script reads that catalogue from
    the pinned APK in work\device-tools, downloads the files for the regions you name from
    Organic Maps' own server into work\organicmaps\<v>\ (git-ignored; resumable, and a file is
    kept only when its size matches the catalogue), then pushes them into the app's data folder:

        /sdcard/Android/data/app.organicmaps/files/<v>/<region>.mwm

    Android 16 does not let the ADB shell user write into another app's Android/data folder, so
    each file goes to /data/local/tmp first and root moves it in and gives it to the app. Works on
    the stock system (Magisk's su) and on this project's own image (userdebug su). The app is
    stopped while files land and restarted afterwards; it shows the regions as downloaded.

    Regions are catalogue ids: a country ("Germany"), a country group ("United States of
    America"), or a single file ("US_Oregon_Portland"). -List prints the top-level ids with sizes.

.EXAMPLE
    .\dev\Push-OfflineMaps.ps1 -Region 'United States of America'
.EXAMPLE
    .\dev\Push-OfflineMaps.ps1 -Region Iceland,Norway -DownloadOnly
.EXAMPLE
    .\dev\Push-OfflineMaps.ps1 -List
#>
[CmdletBinding()]
param(
    [string[]]$Region = @('United States of America'),
    [switch]$List,
    [switch]$DownloadOnly,
    [int]$Parallel = 6
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Adb  = Join-Path $Work 'platform-tools\adb.exe'
$Spec = Get-Content -Raw (Join-Path $PSScriptRoot 'toolchain.json') | ConvertFrom-Json
$ApkPin = $Spec.deviceTools.downloads | Where-Object { $_.name -like 'app.organicmaps_*.apk' } | Select-Object -First 1
if (-not $ApkPin) { throw 'No Organic Maps APK pinned in dev\toolchain.json.' }
$Apk = Join-Path $Work "device-tools\$($ApkPin.name)"
if (-not (Test-Path $Apk)) { throw "$Apk missing. Run .\dev\Bootstrap-DevEnv.ps1." }

# ---- catalogue from the APK
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($Apk)
try {
    $entry = $zip.GetEntry('assets/countries.json')
    $reader = New-Object System.IO.StreamReader($entry.Open())
    $cat = $reader.ReadToEnd() | ConvertFrom-Json
    $reader.Dispose()
} finally { $zip.Dispose() }
$Ver = $cat.v

function Get-Leaves($node) {
    if ($node.g) { foreach ($c in $node.g) { Get-Leaves $c } }
    else { [pscustomobject]@{ Id = $node.id; Size = [long]$node.s } }
}
function Find-Node($node, [string]$id) {
    if ($node.id -eq $id) { return $node }
    foreach ($c in @($node.g)) { if ($c) { $r = Find-Node $c $id; if ($r) { return $r } } }
}

if ($List) {
    $cat.g | ForEach-Object { $l = @(Get-Leaves $_); [pscustomobject]@{ Region = $_.id; Files = $l.Count; GB = [math]::Round(($l | Measure-Object Size -Sum).Sum / 1e9, 2) } } |
        Sort-Object Region | Format-Table -AutoSize
    return
}

$files = foreach ($r in $Region) {
    $n = Find-Node $cat $r
    if (-not $n) { throw "Region '$r' is not in the catalogue (data version $Ver). Use -List." }
    Get-Leaves $n
}
$files = $files | Sort-Object Id -Unique
$totalGB = [math]::Round(($files | Measure-Object Size -Sum).Sum / 1e9, 2)
Write-Host "Organic Maps data $Ver : $($files.Count) files, $totalGB GB for $($Region -join ', ')" -ForegroundColor Cyan

# ---- download (resumable, size-checked)
$Dest = Join-Path $Work "organicmaps\$Ver"
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$todo = $files | Where-Object { $f = Join-Path $Dest "$($_.Id).mwm"; -not ((Test-Path $f) -and (Get-Item $f).Length -eq $_.Size) }
if ($todo) {
    Write-Host "Downloading $(@($todo).Count) files into $Dest ..."
    $todo | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        $f = Join-Path $using:Dest "$($_.Id).mwm"
        $url = "https://cdn.organicmaps.app/maps/$($using:Ver)/$([uri]::EscapeDataString($_.Id)).mwm"
        for ($i = 1; $i -le 3; $i++) {
            try { Invoke-WebRequest -Uri $url -OutFile $f -UseBasicParsing -ErrorAction Stop } catch { }
            if ((Test-Path $f) -and (Get-Item $f).Length -eq $_.Size) { return }
            Remove-Item -Force -ErrorAction SilentlyContinue $f
        }
        Write-Warning "FAILED $($_.Id)"
    }
}
$bad = $files | Where-Object { $f = Join-Path $Dest "$($_.Id).mwm"; -not ((Test-Path $f) -and (Get-Item $f).Length -eq $_.Size) }
if ($bad) { throw "$(@($bad).Count) files did not download correctly; re-run to resume." }
Write-Host "All $($files.Count) files present and size-checked." -ForegroundColor Green
if ($DownloadOnly) { return }

# ---- push
function Sh([string]$cmd) { (& $Adb shell $cmd 2>&1 | Out-String).Trim() }
$devs = @(& $Adb devices | Select-String "`tdevice$")
if ($devs.Count -ne 1) { throw "Connect exactly one authorized device (found $($devs.Count))." }
# Magisk's su takes -c; AOSP's userdebug su takes the uid first.
$su = if ((Sh "su 0 id") -match 'uid=0') { 'su 0' } elseif ((Sh "su -c id") -match 'uid=0') { 'su -c' } else { throw 'Root (su) is required on the device.' }
function Root([string]$cmd) { if ($su -eq 'su 0') { Sh "su 0 sh -c `"$cmd`"" } else { Sh "su -c `"$cmd`"" } }

if (-not (Sh 'pm path app.organicmaps')) { throw 'Organic Maps is not installed on the device.' }
$Remote = "/sdcard/Android/data/app.organicmaps/files/$Ver"
$freeKB = [long]((Sh "df -k /data | tail -1") -split '\s+')[3]
$needKB = [long](($files | Measure-Object Size -Sum).Sum / 1KB)
if ($freeKB -lt $needKB + 1GB / 1KB) { throw "Not enough space on the device: $([math]::Round($freeKB/1MB,1)) GB free, $totalGB GB needed." }

Sh 'am force-stop app.organicmaps' | Out-Null
# Starting the app once creates its data folder and owner; then stop it again.
if (-not (Sh "ls -d /sdcard/Android/data/app.organicmaps/files 2>/dev/null")) {
    Sh 'monkey -p app.organicmaps -c android.intent.category.LAUNCHER 1' | Out-Null; Start-Sleep 5; Sh 'am force-stop app.organicmaps' | Out-Null
}
$owner = Sh "stat -c %u /sdcard/Android/data/app.organicmaps/files"
Root "mkdir -p '$Remote'" | Out-Null
Sh 'mkdir -p /data/local/tmp/om' | Out-Null
$pushed = 0; $skipped = 0
foreach ($f in $files) {
    $target = "$Remote/$($f.Id).mwm"
    if ((Sh "stat -c %s '$target' 2>/dev/null") -eq "$($f.Size)") { $skipped++; continue }
    & $Adb push (Join-Path $Dest "$($f.Id).mwm") "/data/local/tmp/om/$($f.Id).mwm" 2>&1 | Out-Null
    Root "mv '/data/local/tmp/om/$($f.Id).mwm' '$target'" | Out-Null
    if ((Sh "stat -c %s '$target'") -ne "$($f.Size)") { throw "Push of $($f.Id) failed." }
    $pushed++
    if ($pushed % 20 -eq 0) { Write-Host "  pushed $pushed ..." }
}
Root "chown -R ${owner}:ext_data_rw '$Remote'; chmod 660 '$Remote'/*.mwm" | Out-Null
Sh 'rm -rf /data/local/tmp/om' | Out-Null
Sh 'monkey -p app.organicmaps -c android.intent.category.LAUNCHER 1' | Out-Null
Write-Host "Done: $pushed pushed, $skipped already on the device ($(Sh "du -sh '$Remote' | cut -f1") in $Remote)." -ForegroundColor Green
