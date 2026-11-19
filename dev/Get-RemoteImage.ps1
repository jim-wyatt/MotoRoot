<#
.SYNOPSIS
    Copies the newest system image from the build machine to this PC, verified, ready for Install-Gsi.ps1.

.DESCRIPTION
    Images can be built on one machine (the one with the AOSP tree in WSL) and installed from
    another (the one the phone is plugged into). build-gsi.sh leaves system.img,
    system.img.sha256, build.prop and vbmeta.img in the build machine's
    work\device-tools\gsi\own\. This script fetches them over SSH (scp, Windows' built-in
    OpenSSH client) into the same folder here.

    - It compares the remote checksum with the local image first, so an unchanged image is not
      copied again.
    - It copies into a .part file and keeps the image only if its SHA-256 matches the build
      machine's checksum.
    - The image it replaces is deleted, not kept: the build machine holds every build, and the
      install PC keeps as little as possible (Deploy-Image.ps1 deletes the image after installing).

    The build machine needs an SSH server with this PC's public key authorised: either the
    Windows OpenSSH Server, or an SFTP-only server inside its WSL (for machines whose policy
    denies network logon to local accounts). See docs/develop/aosp-build.md, "Building on one
    machine, installing from another".

    Which machine to pull from is private to your network, so it isn't in the repository. Pass
    -BuildHost, -User, -RemoteRepo (and -Port, if not 22) once with -Save, and they are kept in
    work\remote-build.json (git-ignored).

.EXAMPLE
    .\dev\Get-RemoteImage.ps1 -BuildHost 192.0.2.10 -User builder -RemoteRepo C:/Users/builder/Projects/VedoTom -Save
.EXAMPLE
    .\dev\Get-RemoteImage.ps1 -BuildHost 192.0.2.10 -Port 2222 -User vedotom-xfer -RemoteRepo /repo -Save   # WSL SFTP chroot
.EXAMPLE
    .\dev\Get-RemoteImage.ps1            # uses work\remote-build.json
.EXAMPLE
    .\dev\Get-RemoteImage.ps1 -Check     # only reports whether a newer image is waiting
#>
[CmdletBinding()]
param(
    [string]$BuildHost,
    [string]$User,
    [string]$RemoteRepo,
    [ValidateRange(1, 65535)][int]$Port,
    [ValidateRange(1, 32)][int]$Streams = 8,   # parallel scp connections for the parts; try 12 or 16
    [switch]$Save,
    [switch]$Check
)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Work = Join-Path $Root 'work'
$Cfg  = Join-Path $Work 'remote-build.json'
$Dest = Join-Path $Work 'device-tools\gsi\own'

# ---- where to pull from
$conf = if (Test-Path $Cfg) { Get-Content -Raw $Cfg | ConvertFrom-Json } else { [pscustomobject]@{} }
if ($BuildHost)  { $conf | Add-Member -Force NoteProperty host $BuildHost }
if ($User)       { $conf | Add-Member -Force NoteProperty user $User }
if ($RemoteRepo) { $conf | Add-Member -Force NoteProperty repo ($RemoteRepo -replace '\\', '/') }
if ($Port)       { $conf | Add-Member -Force NoteProperty port $Port }
foreach ($k in 'host', 'user', 'repo') {
    if (-not $conf.$k) { throw "No build machine configured ($k missing). Run once with -BuildHost, -User, -RemoteRepo and -Save." }
}
if ($Save) {
    New-Item -ItemType Directory -Force -Path $Work | Out-Null
    $conf | ConvertTo-Json | Set-Content -Encoding utf8 $Cfg
    Write-Host "Saved to $Cfg"
}
$target = "$($conf.user)@$($conf.host)"
$remoteDir = "$($conf.repo.TrimEnd('/'))/work/device-tools/gsi/own"
# Keep-alives: a connection that dies silently in the VPN tunnel (no reset) would otherwise leave
# scp waiting forever (seen 2026-11-19: all 8 part streams stalled at a few MB). With these, scp
# exits after about 60 s without an answer, and Pull-Parts' retry fetches that part again.
$sshOpts = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10',
             '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4')
if ($conf.port) { $sshOpts += @('-P', "$($conf.port)") }   # scp takes the port as -P

function Pull([string]$name, [string]$to) {
    & scp.exe @sshOpts -q "${target}:$remoteDir/$name" $to
    if ($LASTEXITCODE -ne 0) { throw "scp of $name from $target failed (exit $LASTEXITCODE)." }
}

# ---- what the build machine has
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
$tmp = Join-Path $Dest 'remote.sha256'
Pull 'system.img.sha256' $tmp
$remoteHash = ((Get-Content $tmp -TotalCount 1) -split '\s+')[0].ToLower()
Remove-Item $tmp
if ($remoteHash -notmatch '^[0-9a-f]{64}$') { throw "The build machine's system.img.sha256 is not a SHA-256 line." }

$img = Join-Path $Dest 'system.img'
$localHash = if (Test-Path $img) { (Get-FileHash -Algorithm SHA256 $img).Hash.ToLower() } else { '' }
if ($localHash -eq $remoteHash) {
    Write-Host "Up to date: the local system.img is the build machine's newest ($($remoteHash.Substring(0,12))...)." -ForegroundColor Green
    return
}
if ($Check) {
    Write-Host "A different image is waiting on $($conf.host) ($($remoteHash.Substring(0,12))...). Run without -Check to fetch it." -ForegroundColor Yellow
    return
}

# ---- fetch, verify, swap in
# In parts over parallel streams when the build machine published them (system.img.parts lists
# each part with its SHA-256): the VPN path limits each connection, not the total. Otherwise the
# single file. Either way the joined image must match system.img.sha256.
function Pull-Parts([string]$to) {
    $list = Join-Path $Dest 'remote.parts'
    & scp.exe @sshOpts -q "${target}:$remoteDir/system.img.parts" $list 2>$null
    if ($LASTEXITCODE -ne 0) { Remove-Item -Force -ErrorAction SilentlyContinue $list; return $false }
    $parts = Get-Content $list | Where-Object { $_ -match '^[0-9a-f]{64}\s+\*?system\.img\.part\d+$' } | ForEach-Object {
        $h, $n = $_ -split '\s+\*?', 2; [pscustomobject]@{ Name = $n; Hash = $h; File = Join-Path $Dest ".$n" }
    }
    Remove-Item $list
    if (-not $parts) { return $false }
    Write-Host "  $(@($parts).Count) parts, $Streams streams"
    $scpArgs = { param($p) (@($sshOpts) + @('-q', "${target}:$remoteDir/$($p.Name)", "`"$($p.File)`"")) }
    foreach ($attempt in 1, 2) {
        $todo = @($parts | Where-Object { -not (Test-Path $_.File) -or (Get-FileHash -Algorithm SHA256 $_.File).Hash.ToLower() -ne $_.Hash })
        if (-not $todo) { break }
        if ($attempt -gt 1) { Write-Warning "$($todo.Count) part(s) failed or mismatched; fetching them again" }
        $running = @()
        foreach ($p in $todo) {
            while (@($running | Where-Object { -not $_.HasExited }).Count -ge $Streams) { Start-Sleep -Milliseconds 200 }
            $running += Start-Process scp.exe -ArgumentList (& $scpArgs $p) -NoNewWindow -PassThru
        }
        $running | ForEach-Object { $_.WaitForExit() }
    }
    $bad = @($parts | Where-Object { -not (Test-Path $_.File) -or (Get-FileHash -Algorithm SHA256 $_.File).Hash.ToLower() -ne $_.Hash })
    if ($bad) {
        $parts | ForEach-Object { Remove-Item -Force -ErrorAction SilentlyContinue $_.File }
        throw "Parts still missing or mismatched after a retry: $($bad.Name -join ', '). Nothing was replaced."
    }
    # Each part goes as soon as it is joined, so the parts and the joined image never both sit on disk
    # in full. A failed join leaves nothing: the full SHA-256 check would reject it anyway.
    $out = [IO.File]::Create($to)
    try {
        foreach ($p in $parts) {
            $in = [IO.File]::OpenRead($p.File); try { $in.CopyTo($out) } finally { $in.Dispose() }
            Remove-Item -Force $p.File
        }
    } catch {
        $out.Dispose(); Remove-Item -Force -ErrorAction SilentlyContinue $to
        $parts | ForEach-Object { Remove-Item -Force -ErrorAction SilentlyContinue $_.File }
        throw
    } finally { $out.Dispose() }
    return $true
}

$part = "$img.part"
Write-Host "Fetching system.img from $($conf.host) ..."
$t = [Diagnostics.Stopwatch]::StartNew()
if (-not (Pull-Parts $part)) { Write-Host '  no parts published; fetching the single file'; Pull 'system.img' $part }
$got = (Get-FileHash -Algorithm SHA256 $part).Hash.ToLower()
if ($got -ne $remoteHash) { Remove-Item -Force $part; throw "Checksum mismatch: got $got, expected $remoteHash. Nothing was replaced." }
# The sidecars come before the swap, and the previous build's copies go, so Install-Gsi.ps1 -Image
# never packs an old build.prop or vbmeta.img with the new image. build.prop is required;
# vbmeta.img is published only when the build made one.
$propPart = Join-Path $Dest 'build.prop.part'; $vbPart = Join-Path $Dest 'vbmeta.img.part'
try { Pull 'build.prop' $propPart } catch { Remove-Item -Force $part; throw "build.prop not fetched; nothing was replaced. $_" }
& scp.exe @sshOpts -q "${target}:$remoteDir/vbmeta.img" $vbPart 2>$null
$haveVb = $LASTEXITCODE -eq 0
foreach ($f in 'build.prop', 'vbmeta.img') { Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $Dest $f) }
# No system.prev.img: the install PC only installs and validates, and every image stays on the build
# machine, so the old one is simply replaced (and an old system.prev.img removed).
Remove-Item -Force -ErrorAction SilentlyContinue $img, (Join-Path $Dest 'system.prev.img')
Move-Item -Force $part $img
Move-Item -Force $propPart (Join-Path $Dest 'build.prop')
if ($haveVb) { Move-Item -Force $vbPart (Join-Path $Dest 'vbmeta.img') } else { Remove-Item -Force -ErrorAction SilentlyContinue $vbPart; Write-Host '  (no vbmeta.img published)' }
Set-Content -Encoding ascii (Join-Path $Dest 'system.img.sha256') "$remoteHash  system.img"

$fp = (Select-String -Path (Join-Path $Dest 'build.prop') -Pattern '^ro.system.build.fingerprint=' -ErrorAction SilentlyContinue).Line -replace '^[^=]*=', ''
$mb = [math]::Round((Get-Item $img).Length / 1MB)
Write-Host "Fetched and verified: $mb MB in $([math]::Round($t.Elapsed.TotalSeconds)) s, fingerprint $fp" -ForegroundColor Green
Write-Host @"
Next, .\dev\Deploy-Image.ps1 -NoFetch does the rest. By hand, from the stock system (reboot first if the
phone is in a DSU image); installing replaces the image's data:
  .\dev\Install-Gsi.ps1 -Action Discard
  .\dev\Install-Gsi.ps1 -Action Install -Image "$img" -UserdataGiB 24
  .\dev\Install-Gsi.ps1 -Action Boot
"@
