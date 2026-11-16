# Troubleshooting

Common failures and their fixes. If the [self-test](environment.md) passes but something still misbehaves, start here.

## Environment

??? failure "`python` opens the Microsoft Store instead of running"
    Windows ships a stub that launches the Store. Install real Python (`winget install -e --id Python.Python.3.12`), open a **new** terminal so PATH updates, and re-run the bootstrap.

??? failure "`JAVA_HOME` / Android not found in a new terminal"
    The bootstrap sets user environment variables, but already-open terminals and VS Code don't see them until restarted. Open a new terminal, or restart VS Code.

??? failure "Self-test fails on `platform-tools\ holds 1.0.41, not 37.0.1`"
    A different `adb` version got into `work\platform-tools`. Close any running server (`& $adb kill-server`), delete the folder, and re-run the bootstrap to re-extract the pinned copy.

??? failure "Self-test fails on `docs site builds` with no error text, or `zensical` exits 1 silently"
    A Python venv records the absolute path it was created at, and its `Scripts\*.exe` launchers embed it. If the repository folder has been moved or renamed since the bootstrap ran, those launchers exit with code 1 and print nothing. Re-run `.\dev\Bootstrap-DevEnv.ps1`: it compares `pyvenv.cfg` with the current path and recreates a moved venv (`dev\.venv-docs` and `work\.venv` both). Deleting the venv folder by hand and re-running has the same effect.

??? failure "SDK license / `android.exe` errors during bootstrap"
    The SDK uses the newer `android` CLI with slash-style package names. If licenses weren't accepted, re-run the bootstrap in an interactive window, or pass `-AcceptAndroidSdkLicenses` after reading [the terms](https://developer.android.com/studio/terms).

## Device connection

??? failure "`adb devices` shows nothing"
    - Use a **data** cable, not charge-only. Try another port.
    - USB debugging on, and the **Allow** prompt approved on the device.
    - Another `adb` server may be interfering — close Android Studio, `& $adb kill-server`, retry.

??? failure "`adb devices` shows `unauthorized`"
    Look at the device: tap **Allow** on the USB-debugging prompt. If it never appears, revoke authorizations in Developer options and replug.

??? failure "Device goes `offline` mid-command"
    Almost always two `adb` versions fighting. Use only the dev shell's `$adb`, close Android Studio, `& $adb kill-server`, reconnect.

??? failure "`fastboot devices` is empty but the device is in the bootloader"
    The Motorola USB driver isn't installed (Windows shows error 28). Install `work\Motorola_Mobile_Drivers_64bit.msi`. ADB working does **not** mean the Fastboot driver is present.

## Device preparation

??? failure "`su` not found, or root can't be verified (Stage 2)"
    Grant **Shell** superuser in KernelSU (enable *Show system apps* if it's hidden). If it still fails, the temporary-root step didn't take — don't retry an exploit repeatedly, and don't reboot into a staged update. Confirm your build matches the [tested device](../device/index.md#the-exact-tested-device).

??? failure "`getprop` values don't match the tested device"
    **Stop.** The low-level stages are validated only for the exact build in the tested table. A different model, build, patch, or slot is untested and may be unsafe.

??? failure "LK patch verifier doesn't say `Result: VALID` (Stage 5)"
    Don't flash it. Re-run the analyzer and patcher on *your own* backed-up `lk_a.img`, confirm the analysis found the expected structures, and check you used the pinned Val Protocol commit (the self-test verifies this).

??? failure "`fastboot flash` or `oem unlock` rejected (Stage 6)"
    Confirm `$fb getvar product` is `vegas` and you're on slot A. The unlock key must be a 20-char key generated from **your** serial. Approve the unlock prompt **on the device** quickly — it times out.

??? failure "`su` says `Permission denied` after installing Magisk, and its Superuser tab is empty (Stage 7)"
    Magisk is rejecting Shell before it can show the Grant pop-up: `& $adb logcat -d | Select-String 'request rejected'` shows `su: request rejected (2000)`, and nothing appears in the Superuser tab. On the unit these docs were written with, Motorola's background freezer suspended the Magisk app, so the daemon couldn't reach it and denied by default. Grant Shell manually: Magisk → **Superuser** tab → **+** (bottom right) → tick **Shell** (`com.android.shell`). The policy is stored, so it survives reboots. Then `& $adb shell su -c id` should report `context=u:r:magisk:s0`. Magisk 31.1 has no "Superuser access: Apps and ADB" setting to change, so don't go looking for one.

??? failure "Device won't boot after writing a prepared image"
    If Fastboot is reachable, restore your backup to that slot ([recovery](../device/maintenance.md#recovery)). If Fastboot won't start, there's no proven recovery for this model — this is the accepted risk of Stage 6.

## Engineering device and tooling

??? failure "`adb root` says `restarting adbd as root`, the device drops off ADB for a moment, and the shell is still `uid=2000`"
    Expected on this build, and the reason the docs say not to run it: the shipped `adbd` is compiled to drop root, so the request makes it abort (one `adbd` crash in `logcat -b crash`) and restart as `shell`. The `dev_debuggable` module doesn't change this. Use `& $adb shell su -c '<command>'` for root.

??? failure "`adbwifi` says the phone and the PC are on different networks"
    They are, and a `connect` would only time out. Two routers, a guest Wi-Fi, or a wired PC on a different subnet from the Wi-Fi are the usual causes. Join the PC to the phone's Wi-Fi (or the phone to the PC's network) and run `adbwifi` again. The `dev_adb_tcp` module is working if `& $adb shell su -c 'ss -ltn | grep :5555'` shows the listener.

??? failure "`perfetto` fails to read the config, or the trace is tiny and `logcat` says `not profileable`"
    Two different things. A config under `/data/local/tmp` is refused by SELinux: it must live in `/data/misc/perfetto-configs/`, which `Trace-Device.ps1` does for you. `not profileable` means a heap profiler was pointed at an app that isn't yours on a device that reports a `user` build; install the `dev_debuggable` module ([engineering device](../device/dev-setup.md)), which reports `userdebug`, and it works.

??? failure "`simpleperf record` fails with `Event type 'cpu-cycles' is not supported on the device`"
    The MediaTek kernel exposes no perf events to it (`-e cpu-clock` fails the same way), so sampled CPU profiling isn't available on this device, in Android Studio either. Use Perfetto's system trace for scheduling and slices, and [Frida](../develop/instrumentation.md) for call-level timing.

??? failure "`frida-ps` prints `Unable to start idund: idund did not start listening`"
    Harmless. Recent `frida-tools` first try to auto-deploy their own helper over ADB, fail because the pinned `frida-server` already answers, and use it. If `frida-ps -U` lists nothing at all, run `Start-Frida`.

??? failure "The device won't boot with a module enabled"
    Hold **Volume Down** while it boots: Magisk's safe mode starts with every module disabled. Then `& $adb shell su -c 'touch /data/adb/modules/<id>/disable'` for the module you suspect and reboot normally. None of the project's modules has needed this on the two tested units.

## Docs site

??? failure "`zensical build --strict` fails on a nav entry"
    A nav path in `zensical.toml` points to a file that doesn't exist, or a page links to a missing file. Create the file or fix the link; strict mode treats warnings as errors (which is what keeps the published site clean).

??? failure "The `docs` command isn't found"
    Dot-source the dev shell first (`. .\dev\Enter-DevShell.ps1`), which defines it. It needs the docs venv, created by the bootstrap.
