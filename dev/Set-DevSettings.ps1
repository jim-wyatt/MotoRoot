<#
.SYNOPSIS
Applies the development-target settings to the connected device, or puts them back to stock.

.DESCRIPTION
Four settings that make a phone a better development and test target. Each is an ordinary
Android setting (the same switches as in Developer options), so nothing on the firmware changes
and -Reset returns every one to the stock value.

  Animations off      window, transition and animator duration scales 0. Espresso and other UI
                      tests expect it, and screens settle immediately.
  No ADB install scan verifier_verify_adb_installs 0: apps installed with adb install are not
                      sent to Play Protect for verification first, so installs are fast and
                      never blocked by a verification prompt.
  No ADB auth timeout adb_allowed_connection_time 0: an authorized PC stays authorized instead
                      of having to re-confirm the key after seven days without connecting, which
                      matters for ADB over Wi-Fi.
  16 MB log buffers   persist.logd.size 16M (stock is 256 KiB per buffer), applied immediately
                      with logcat -G, so the log from before a crash is still there to read.
                      logd on this build ignores the property at boot, so the dev_debuggable
                      module (1.3 or later) re-applies it once boot completes. Setting the
                      property needs root (su); without root, or without the module, the size
                      lasts until the next reboot only.

The script checks every value after setting it and exits with the number that did not stick.
Run it again any time; it is idempotent.

.PARAMETER Reset
Put every setting back to its stock value instead.

.EXAMPLE
.\dev\Set-DevSettings.ps1

.EXAMPLE
.\dev\Set-DevSettings.ps1 -Reset
#>
[CmdletBinding()]
param([switch]$Reset)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Adb  = Join-Path $Root 'work\platform-tools\adb.exe'
Import-Module (Join-Path $PSScriptRoot 'VedoTom.psm1')   # Assert-OneDevice, Invoke-RootShell (Magisk or AOSP su)
Assert-OneDevice

function Sh([string]$Cmd) { ((& $Adb shell $Cmd) -join "`n").Trim() }

# name = development value; -Reset deletes the key, which restores the stock default.
$Global = [ordered]@{
    window_animation_scale       = '0'
    transition_animation_scale   = '0'
    animator_duration_scale      = '0'
    verifier_verify_adb_installs = '0'
    adb_allowed_connection_time  = '0'
}
$LogSize = '16M'

$failed = 0
foreach ($k in $Global.Keys) {
    if ($Reset) { Sh "settings delete global $k" | Out-Null; $want = 'null' }
    else        { Sh "settings put global $k $($Global[$k])" | Out-Null; $want = $Global[$k] }
    $got = Sh "settings get global $k"
    if ($got -eq $want) { Write-Host "  ok    $k = $got" -ForegroundColor Green }
    else { Write-Warning "$k is '$got', expected '$want'"; $failed++ }
}

$haveRoot = Test-DeviceRoot
if ($Reset) {
    # Magisk's resetprop deletes the property and its persistent copy. A DSU image built from
    # source has no resetprop; there an empty value is the reset (and init.vedotom.rc sets 16 MiB
    # at every boot regardless).
    if ($haveRoot) { Invoke-RootShell 'if command -v resetprop >/dev/null; then resetprop -p -d persist.logd.size; else setprop persist.logd.size ""; fi' | Out-Null }
    Sh 'logcat -G 256K' | Out-Null
    Write-Host "  ok    log buffers back to 256 KiB$(if (-not $haveRoot) { ' (no root: persist.logd.size left as it was)' })" -ForegroundColor Green
} else {
    if ($haveRoot) {
        Invoke-RootShell "setprop persist.logd.size $LogSize" | Out-Null
        $p = Sh 'getprop persist.logd.size'
        if ($p -ne $LogSize) { Write-Warning "persist.logd.size is '$p', expected $LogSize"; $failed++ }
    } else {
        Write-Warning 'No root: the 16 MB log size lasts until the next reboot only.'
    }
    Sh "logcat -G $LogSize" | Out-Null
    $g = Sh 'logcat -g -b main'
    if ($g -match 'ring buffer is 16 MiB') { Write-Host "  ok    log buffers 16 MiB$(if ($haveRoot) { ', persistent' })" -ForegroundColor Green }
    else { Write-Warning "log buffer: $g"; $failed++ }
}
exit $failed
