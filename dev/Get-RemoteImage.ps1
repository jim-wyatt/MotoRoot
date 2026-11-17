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
    - The image it replaces is kept as system.prev.img.

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
$sshOpts = @('-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=accept-new', '-o', 'ConnectTimeout=10')
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
$part = "$img.part"
Write-Host "Fetching system.img from $($conf.host) ..."
$t = [Diagnostics.Stopwatch]::StartNew()
Pull 'system.img' $part
$got = (Get-FileHash -Algorithm SHA256 $part).Hash.ToLower()
if ($got -ne $remoteHash) { Remove-Item -Force $part; throw "Checksum mismatch: got $got, expected $remoteHash. Nothing was replaced." }
if (Test-Path $img) { Move-Item -Force $img (Join-Path $Dest 'system.prev.img') }
Move-Item -Force $part $img
Set-Content -Encoding ascii (Join-Path $Dest 'system.img.sha256') "$remoteHash  system.img"
foreach ($f in 'build.prop', 'vbmeta.img') { try { Pull $f (Join-Path $Dest $f) } catch { Write-Warning "$f not fetched: $_" } }

$fp = (Select-String -Path (Join-Path $Dest 'build.prop') -Pattern '^ro.system.build.fingerprint=' -ErrorAction SilentlyContinue).Line -replace '^[^=]*=', ''
$mb = [math]::Round((Get-Item $img).Length / 1MB)
Write-Host "Fetched and verified: $mb MB in $([math]::Round($t.Elapsed.TotalSeconds)) s, fingerprint $fp" -ForegroundColor Green
Write-Host @"
Next, from the stock system (reboot first if the phone is in a DSU image). Installing replaces the image's data:
  .\dev\Install-Gsi.ps1 -Action Discard
  .\dev\Install-Gsi.ps1 -Action Install -Image "$img" -UserdataGiB 24
  .\dev\Install-Gsi.ps1 -Action Boot
  .\dev\Push-OfflineMaps.ps1 -Region 'United States of America'
"@
