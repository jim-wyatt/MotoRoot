<#
.SYNOPSIS
Device helpers shared by the dev\ scripts and the dev shell. Import-Module .\dev\VedoTom.psm1

.DESCRIPTION
Every function talks to the phone through the pinned adb in work\platform-tools.

  Assert-OneDevice   throws unless exactly one authorized device is connected
  Invoke-RootShell   runs a shell command as root, with whichever su the running system has
  Test-DeviceRoot    $true if Invoke-RootShell gets uid 0
  Wait-DeviceBoot    waits for sys.boot_completed; -AfterReboot first waits for the old system
                     to drop off USB, so the old system's "booted" isn't taken for the new one's
  Get-GsiStatus      gsi_tool status (as root), trimmed
  Test-GsiRunning    $true while a DSU image (Google's GSI or your own) is the running system.
                     ro.gsid.image_running reads empty on this phone; gsi_tool's first line says
                     "running" instead.
#>
$script:Adb = Join-Path (Split-Path -Parent $PSScriptRoot) 'work\platform-tools\adb.exe'

function Assert-OneDevice {
    if (-not (Test-Path -LiteralPath $script:Adb)) { throw 'platform-tools missing. Run .\dev\Bootstrap-DevEnv.ps1.' }
    $d = @(& $script:Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\sdevice$' })
    if ($d.Count -ne 1) { throw "Connect exactly one authorized device (found $($d.Count))." }
}

# Two su flavours. Magisk's (the stock system) takes -c. AOSP's userdebug su (any DSU image built
# from source, this project's included) takes "su 0 <command>" and rejects -c with
# "invalid uid/gid '-c'". Magisk's form is tried first and AOSP's on that exact refusal; nothing is
# cached, because the phone can reboot between stock and an image while a dev shell stays open.
# The command reaches the device's sh inside single quotes, so its own single quotes are escaped.
function Invoke-RootShell([Parameter(Mandatory)][string]$Command) {
    $q = "'" + ($Command -replace "'", "'\''") + "'"
    $out = (& $script:Adb shell "su -c $q" 2>&1) -join "`n"
    if ($out -notmatch "invalid uid/gid") { return $out }
    (& $script:Adb shell "su 0 sh -c $q" 2>&1) -join "`n"
}

function Test-DeviceRoot { (Invoke-RootShell 'id') -match 'uid=0\(' }

function Wait-DeviceBoot([int]$TimeoutSec = 600, [switch]$AfterReboot) {
    if ($AfterReboot) { & $script:Adb wait-for-disconnect }
    & $script:Adb wait-for-device
    $t = 0
    while ($t -lt $TimeoutSec) {
        if (((& $script:Adb shell getprop sys.boot_completed 2>$null) -join '').Trim() -eq '1') { return $t }
        Start-Sleep 5; $t += 5
    }
    throw "The phone did not finish booting within $TimeoutSec s."
}

function Get-GsiStatus { (Invoke-RootShell 'gsi_tool status').Trim() }

function Test-GsiRunning { ((Get-GsiStatus) -split "`r?`n")[0].Trim() -eq 'running' }

Export-ModuleMember -Function Assert-OneDevice, Invoke-RootShell, Test-DeviceRoot, Wait-DeviceBoot, Get-GsiStatus, Test-GsiRunning
