# Troubleshooting

Common failures and their fixes. If `aosp-academy check` passes but something still misbehaves, start here. The commands assume a shell opened with `aosp-academy shell`.

## Environment

??? failure "`python` opens the Microsoft Store instead of running"
    Windows ships a placeholder `python` that opens the Store. Install real Python (`winget install Python.Python.3.12`), open a **new** terminal so PATH updates, and run the command again.

??? failure "`aosp-academy needs Python 3.11 or newer`"
    The launcher found an older Python first on PATH. Install 3.11 or newer and make sure it comes first (`python --version` on Windows, `python3 --version` elsewhere).

??? failure "`JAVA_HOME` or the SDK not found in a new terminal"
    On Windows, `setup` saves `JAVA_HOME` and `ANDROID_HOME` as user environment variables, but terminals and VS Code that were already open don't see them until restarted. Open a new terminal, or restart VS Code. On Linux and macOS, `setup` doesn't edit your shell profile: use `aosp-academy shell`, or load `aosp-academy env` into your shell.

??? failure "`setup` stops on `... exists but its sha256 does not match the pin`"
    A file in `work/` has the name of a pinned download but different contents: a partial download from another tool, an older version, or a file put there by hand. `setup` never overwrites it, because someone has to look at it. Check what it is, delete it, and run `setup` again. If you changed the pin yourself, see [changing a pin](pins.md#changing-a-pin).

??? failure "`setup` stops on `work/platform-tools holds ..., not 37.0.3`"
    A different `adb` version is in `work/platform-tools`. Stop any running server (`adb kill-server`), delete `work/platform-tools/` (and `work/platform-tools.zip` if its hash doesn't match either), and run `setup` again to unpack the pinned copy.

??? failure "`check` fails on `SDK platform-tools adb = pinned adb`"
    Android Studio, or the SDK manager, updated the SDK's platform-tools, so Studio's `adb` and the project's are different versions again, and two server versions fight over the phone. Either put the SDK's platform-tools back to the pinned version (decline the update in Studio), or move the pin deliberately ([pins](pins.md#the-platform-tools-move-3701-to-3703)).

??? failure "`check` fails on `docs site builds` with no error text, or `zensical` exits 1 silently"
    A Python virtual environment records the absolute path it was created at, and its launchers embed it. If the repository folder has been moved or renamed since `setup` ran, those launchers exit with code 1 and print nothing. Run `aosp-academy setup` again: it compares each venv's `pyvenv.cfg` with the current path and recreates a moved one. Deleting the venv folder by hand and re-running has the same effect.

??? failure "`check` fails on `shell scripts are LF and valid bash`"
    A script has CRLF line endings, usually because a Windows editor or a tool rewrote it. bash reads the `\r` as part of each command. Repair it with `sed -i 's/\r$//' <file>` (Git Bash on Windows), and set your editor to LF for this repository; `.gitattributes` asks git for LF on every file except `.cmd`.

??? failure "SDK license errors during `setup`"
    The licenses haven't been accepted yet, and `setup` isn't running in an interactive terminal (a VS Code task, a pipe) where it could ask. Run it in a normal terminal, or pass `--accept-sdk-licenses` after reading [the terms](https://developer.android.com/studio/terms).

## The build node

??? failure "`The image builds on a Linux host`"
    `aosp-academy image setup|sync|apply|build|verify` refuses to run on Windows. Run it on the build node, or in WSL2 on the same PC, from a checkout inside the Linux filesystem.

??? failure "`git-lfs is not installed`, or a sync ends with `Cannot initialize work tree`"
    Several prebuilts projects keep their binaries in Git LFS. Run `aosp-academy image setup` (it installs `git-lfs`), then `aosp-academy image sync` again: the sync is resumable.

??? failure "The first build fails far from the cause, for example `unrecognized module type \"llvm_prebuilt_library_static\"`"
    An interrupted sync left a project with the right commit but a half-written work tree, which the next `repo sync` reports as fine; that example was `prebuilts/clang/host/linux-x86` missing its `soong/` directory and 38,979 other files. `aosp-academy image verify` finds such projects and resets them; `sync` runs it every time.

??? failure "`... missing from work/device-tools; run ./aosp-academy image inputs`"
    The step that applies this project's changes to the tree copies the pinned Fossify APKs, and one isn't downloaded. Run `aosp-academy image inputs`, then the step again.

??? failure "A patch no longer applies"
    `apply` stops at a patch that doesn't apply, rather than half-applying it. That happens after a move to a new AOSP release: rebase the patch against the new tree, or delete it if the release already fixes the problem upstream ([move to a new AOSP release](../environment/tag-moves.md)).

??? failure "`lunch failed`"
    The release may have renamed its release configurations. In the tree, `source build/envsetup.sh` and then `lunch` with no arguments lists the targets it offers; change `deviceTools.aosp.lunch` in `toolchain.json`.

??? failure "The build is killed (out of memory), or Soong analysis never finishes"
    See [memory](../start/build-node.md#memory). Killed during the R8 phase: run again with `JOBS=12`; ninja continues where it stopped. Analysis swapping for many minutes: check that the Blueprint heap-limit patch is applied, and on WSL2 that `.wslconfig` gives the instance enough memory and swap.

??? failure "`Read-only file system` from ccache"
    Don't enable ccache: AOSP's build sandbox mounts only `out/` and `/tmp` writable. Remove any `USE_CCACHE` export from your shell profile (`image setup` removes the one an older version of this project added).

## Fetching and deploying

??? failure "`No build node configured (host missing)`"
    `fetch` and `deploy` don't know where the build node is. Run once with `aosp-academy fetch --host <address> --user <account> --repo <path> [--port N] --save`; the values go into `work/remote-build.json`.

??? failure "`scp of system.img.sha256 ... failed`"
    The device node can't log in to the build node, or the file isn't where `fetch` looks (`<repo>/work/device-tools/gsi/own/`). Try `ssh -p <port> <user>@<host>` by hand: `fetch` uses batch mode, so a key that needs a passphrase, a password login or an unknown network stops it. Check that a build has been published and that `--repo` matches how the build node exposes it ([publishing](../start/build-node.md#publishing-and-how-the-device-node-reaches-it)).

??? failure "`Parts still missing or mismatched after 3 retries`"
    The link dropped too many parts. Nothing was replaced, and the verified parts are kept, so running `fetch` again resumes. A congested link (another big download, a sync on the build node) is the usual cause; fewer streams (`--streams 4`) can help on a weak link.

??? failure "`Checksum mismatch ... Nothing was replaced`"
    The joined image doesn't match the build node's checksum, usually because a build published a new image during the fetch. Run `fetch` again.

??? failure "`deploy` waits after the reboot, saying `Tap \"Allow\" on the phone`"
    The image requires USB-debugging authorization and starts with empty data, and this PC's key isn't built into it. Tap **Allow** (tick *Always allow from this computer*), and the deploy carries on. To skip the tap in future, build this PC's public key into the image ([trusted PCs](../start/build-node.md#trusted-pcs-optional)).

??? failure "`DSU state is '...', not 'normal'`, or `A DSU image is running right now`"
    `gsi install` needs the stock system with nothing installed. `aosp-academy gsi status` shows the state; `gsi stock` leaves a running image, and `gsi discard` (from stock) removes an installed one. `deploy` does both for you.

??? failure "`Installation did not complete`"
    Look at the phone: the DSU installer shows a notification, and a phone with a secure lock screen asks for the PIN before it starts. `aosp-academy gsi discard` cleans up a half-finished install; then deploy again.

??? failure "The image never reaches the home screen"
    After a failed boot the DSU loader falls back to the phone's own system. From there, `aosp-academy gsi discard` removes the image, and a deploy of a working one puts it back. With `--single-boot`, holding Power for a restart is enough: the next boot is stock.

## Device connection

??? failure "`Connect exactly one authorized device (found 0)`, or `adb devices` shows nothing"
    - Use a **data** cable, not a charge-only one. Try another port.
    - USB debugging on, and the **Allow** prompt approved on the phone.
    - Another `adb` server may be interfering: `adb kill-server`, then retry.

??? failure "`adb devices` shows `unauthorized`"
    Look at the phone and tap **Allow** on the USB-debugging prompt. If it never appears, revoke the authorizations in Developer options and replug.

??? failure "The device goes `offline` mid-command"
    Almost always two `adb` versions fighting. Use the shell's `adb` (the pinned one), check that `aosp-academy check` passes the `SDK platform-tools adb = pinned adb` line, `adb kill-server`, and reconnect.

??? failure "`fastboot devices` is empty but the phone is in the bootloader"
    On Windows, the Motorola USB driver isn't installed (Device Manager shows error 28). Install `work\Motorola_Mobile_Drivers_64bit.msi`. ADB working does **not** mean the Fastboot driver is present.

## Device preparation

??? failure "`su` not found, or root can't be verified (stage 2)"
    Grant **Shell** superuser in KernelSU (enable *Show system apps* if it's hidden). If it still fails, the temporary-root step didn't take: don't retry an exploit repeatedly, and don't reboot into a staged update. Confirm your build matches the [tested device](../device/index.md).

??? failure "`getprop` values don't match the tested device"
    **Stop.** The low-level stages are validated only for the exact build in the tested table. A different model, build, patch or slot is untested and may be unsafe. `aosp-academy stock magisk-image` refuses to run for the same reason.

??? failure "The LK patch verifier doesn't say `Result: VALID` (stage 5)"
    Don't flash it. Re-run the analyzer and patcher on *your own* backed-up `lk_a.img`, confirm the analysis found the expected structures, and check that you used the pinned Val Protocol commit (`aosp-academy check` verifies it).

??? failure "`fastboot flash` or `oem unlock` rejected (stage 6)"
    Confirm `fastboot getvar product` is `vegas` and you're on slot A. The unlock key must be a 20-character key generated from **your** serial. Approve the unlock prompt **on the phone** quickly: it times out.

??? failure "`su` says `Permission denied` after installing Magisk, and its Superuser tab is empty (stage 7)"
    Magisk is rejecting Shell before it can show the Grant pop-up: `adb logcat -d | grep "request rejected"` (`Select-String` in PowerShell) shows `su: request rejected (2000)`, and nothing appears in the Superuser tab. On the unit these docs were written with, Motorola's background freezer suspended the Magisk app, so the daemon couldn't reach it and denied by default. Grant Shell by hand: Magisk → **Superuser** tab → **+** (bottom right) → tick **Shell** (`com.android.shell`). The policy is stored, so it survives reboots. Then `adb shell su -c id` should report `context=u:r:magisk:s0`. Magisk 31.1 has no "Superuser access: Apps and ADB" setting to change, so don't go looking for one.

??? failure "The phone won't boot after writing a prepared image"
    If Fastboot is reachable, restore your backup to that slot ([the stock system](../device/stock.md)). If Fastboot won't start, there's no proven recovery for this model: this is the accepted risk of stage 6.

## Tools on the phone

??? failure "On the stock system, `adb root` says `restarting adbd as root`, the phone drops off ADB for a moment, and the shell is still `uid=2000`"
    Expected on the stock build, and the reason the docs say not to run it there: the shipped `adbd` is compiled to drop root, so the request makes it abort (one `adbd` crash in `logcat -b crash`) and restart as `shell`. The `dev_debuggable` module doesn't change this. Use `adb shell su -c '<command>'` for root on stock. In this project's image, a `userdebug` build, `adb root` works.

??? failure "`su -c` fails with `invalid uid/gid '-c'`"
    You're in the image, whose `su` is AOSP's: it takes `su 0 <command>`, not Magisk's `su -c`. The `aosp-academy` commands handle both.

??? failure "`adb-wifi` says the phone and the PC are on different networks"
    They are, and a connection would only time out. Two routers, a guest Wi-Fi, or a wired PC on a different subnet from the Wi-Fi are the usual causes. Put the PC and the phone on the same network and run `aosp-academy adb-wifi` again. On the stock system, the `dev_adb_tcp` module is working if `adb shell su -c 'ss -ltn | grep :5555'` shows the listener.

??? failure "`perfetto` can't read its config, or the trace is tiny and `logcat` says `not profileable`"
    Two different things. A config under `/data/local/tmp` is refused by SELinux: it must be in `/data/misc/perfetto-configs/`, which `aosp-academy device trace` does for you. `not profileable` means a heap profiler was pointed at an app that isn't yours on a system that reports a `user` build. On the stock system, the `dev_debuggable` module makes it report `userdebug` ([system modules](../device/modules.md)); the image is `userdebug` already.

??? failure "`simpleperf record` fails with `Event type 'cpu-cycles' is not supported on the device`"
    The MediaTek kernel exposes no perf events to it (`-e cpu-clock` fails the same way), so sampled CPU profiling isn't available on this device, in Android Studio either. Use Perfetto's system trace for scheduling and slices, and [Frida](../apps/instrumentation.md) for call-level timing.

??? failure "`frida-ps` prints `Unable to start idund: idund did not start listening`"
    Harmless. Recent `frida-tools` first try to deploy their own helper over ADB, fail because the pinned `frida-server` already answers, and use it. If `frida-ps -U` lists nothing at all, run `aosp-academy device frida start`.

??? failure "The stock system won't boot with a module enabled"
    Hold **Volume Down** while it boots: Magisk's safe mode starts with every module disabled. Then `adb shell su -c 'touch /data/adb/modules/<id>/disable'` for the module you suspect, and reboot normally. None of the project's modules has needed this on the two tested units.

??? failure "Never read `/sys/module/*/parameters` in bulk"
    Reading sysfs runs driver code, and one of this phone's vendor charger modules has a broken parameter: on 2026-11-17 a loop over the charger modules' parameters hit a NULL dereference in `param_get_int` and panicked the kernel (boot reason `kernel_panic,null`). It is in the stock kernel too. The phone came back on its own, but read one named file at a time, only one you already know is safe.

## Docs site

??? failure "`zensical build --strict` fails on a nav entry or a link"
    A nav path in `zensical.toml` points to a file that doesn't exist, or a page links to a missing file or anchor. Create the file or fix the link: strict mode treats warnings as errors, which is what keeps the published site clean.

??? failure "`The docs venv is missing`"
    `aosp-academy docs` needs `work/.venv-docs`, which `aosp-academy setup` creates.
