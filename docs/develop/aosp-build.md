# Build your own system image

[Running a GSI through DSU](../device/gsi.md) proved that this device's vendor layer will run a system it has never seen. That system is what AOSP builds from source as the `aosp_arm64` target, the very same target behind Google's image. Build it yourself and you have a system image you can change anything in, booted on the phone the same safe way. This page sets that up.

## What you get, and what you don't

Yours to change: the framework, system services, the launcher, Settings, system apps, SELinux policy for the system side, and the build type: a `userdebug` build is the real engineering build this project has been approximating, with `adb root` that works and debuggers that attach to anything. Also yours: fixing what the stock GSI gets wrong on this hardware, such as the `gpuservice` crash loop, with the source in front of you.

Not yours: the kernel, the vendor HALs, firmware and the modem. They stay Motorola's, under the Treble interface, and the GSI's hardware gaps (two of three cameras, for example) are limits of that interface rather than of your build. A full device port is a different, much larger project.

## Where the build lives

The AOSP tree is 300–400 GB with its output, needs a case-sensitive Linux filesystem, and builds very slowly across WSL's `/mnt/c` boundary, so it lives on **WSL's own disk** (`~/aosp` in the Ubuntu instance), not in this repository and not on a Windows path. This repository drives it: the scripts in `dev/aosp/` run inside WSL, and the finished image comes back to `work\device-tools\gsi\own\`, where `Install-Gsi.ps1` boots it.

Requirements that matter: 16 cores and 32 GB of RAM make the first build a matter of hours rather than a day; WSL's default memory cap is half of RAM, which gets the big link steps killed, so `%UserProfile%\.wslconfig` sets `memory=26GB` and `swap=32GB` under `[wsl2]` (apply with `wsl --shutdown`); on another machine, set `memory` to the RAM less about 6 GB. Swap started at 16 GB and was doubled after `soong_build` itself was OOM-killed during analysis. Disk: the WSL instance here has a 1 TB virtual disk.

Even so, the first build on this machine was killed by the kernel's out-of-memory handler at 76 %: the C++ phase is fine on all 32 cores, but the later phase runs R8 (dex optimisation) as one multi-gigabyte JVM per job, and 32 of them filled the 16 GB of swap. `build-gsi.sh` takes a `JOBS` override for that: `wsl -- env JOBS=12 bash dev/aosp/build-gsi.sh` (or the same for `build-after-sync.sh`) resumes the build with 12 jobs and stays inside memory. Nothing is lost by the kill; ninja continues from the steps already done.

## The pin

`deviceTools.aosp` in `dev/toolchain.json` names the release tag **`android-16.0.0_r4`**, the AOSP release that produced the GSI binary `BP4A.251205.006` validated on this device, so what you build is what was tested, before you change anything. The lunch target is `vedotom_arm64-trunk_staging-userdebug`, this project's product on top of `aosp_arm64` (see *Changing something*).

## Steps

From a dev shell (each script runs inside WSL and is safe to re-run). `wsl --` runs in your default distribution, whatever its name (`Ubuntu`, `Ubuntu-26.04`, ...); `wsl -l -v` marks it with `*`, and `wsl -d <name> --` picks another:

```powershell
wsl -- bash dev/aosp/setup.sh       # build dependencies, repo, git-lfs, JDK (minutes)
wsl -- bash dev/aosp/sync.sh        # repo init at the tag + partial-clone sync (hours, ~120 GB)
wsl -- bash dev/aosp/build-gsi.sh   # lunch + m; copies system.img back (hours the first time)
```

Or chain the two long steps and walk away:

```powershell
wsl -- bash dev/aosp/build-after-sync.sh   # waits for a running sync, or runs one; then builds
Get-Content $Work\aosp-sync.log -Tail 5; Get-Content $Work\aosp-build.log -Tail 5   # progress
```

`sync.sh` logs to `work\aosp-sync.log` and ends with a `sync exit:` line; `build-after-sync.sh` waits for that line (it recognises a sync already running in another window and never starts a second one into the same tree), re-runs a failed sync once, and then runs `build-gsi.sh` with its output in `work\aosp-build.log`. Both logs are inside `work\`, so they are never committed.

`sync.sh` uses a partial clone (`--partial-clone --clone-filter=blob:limit=10M --depth=1`), which keeps the first download to roughly a quarter of a full checkout and is resumable: re-run it after an interruption. After every sync it runs `verify-tree.sh`, because an interruption *during a checkout* leaves a project with the right HEAD and a half-written work tree, which the next `repo sync` reports as fine; the first build then fails far from the cause (`unrecognized module type "llvm_prebuilt_library_static"` was `prebuilts/clang/host/linux-x86` missing its `soong/` directory and 38,979 other files). The verifier finds projects whose only differences from HEAD are missing files and resets them; a project with any edit of yours is listed and left alone. It refuses to start without `git-lfs`: several prebuilts projects (`prebuilts/jdk/jdk8`, `prebuilts/tools`, `prebuilts/bundletool`, `prebuilts/bazel/common`) store their binaries in Git LFS, and without the filter they fail with `Cannot initialize work tree` while the rest of the sync continues. `build-gsi.sh` sources `build/envsetup.sh`, runs `lunch` with the pinned target and `m` with all cores, and copies `system.img` (plus `vbmeta.img` and `build.prop`) to `work\device-tools\gsi\own\`. A second build after a change is incremental: minutes, not hours.

Then boot your build exactly like Google's, one-shot, nothing flashed:

```powershell
.\dev\Install-Gsi.ps1 -Action Install -Image "$Work\device-tools\gsi\own\system.img"   # wraps it in a zip for the DSU installer; confirm on the phone
.\dev\Install-Gsi.ps1 -Action Boot
& $adb shell getprop ro.build.fingerprint     # yours, with test-keys
& $adb root                                   # works on a userdebug build
```

## What the first build established

On the validated device (2026-11-16): the image built from the pinned tag reproduces Google's GSI build id `BP4A.251205.006`, the DSU installer accepts a test-keyed image on this unlocked device, and `adb root` works in the resulting `userdebug` system. Hardware support is identical to Google's binary, which is expected: it is the same source. The one visible defect is also shared, and now explained: `gpuservice` aborts every 30 seconds in `GpuWork::initialize()` because the Motorola kernel does not carry the GPU-work BPF program that AOSP's GPU service expects. That is a system-side crash in code you now have, so it is the natural first patch. Timing on a 32-core, 32 GB machine: 2 h 35 min including a restart; see the memory note above.

## What's in the image

The product tree `dev/aosp/product/vedotom/gsi/` is the whole description. `vedotom_arm64.mk` is upstream's `aosp_arm64.mk` with one substitution: the product-partition app list comes from `vedotom_product.mk` and `vedotom_handheld_product.mk`, copies of the upstream `aosp_product.mk` and `handheld_product.mk` with the apps the Fossify suite replaces removed. The system partition is the stock GSI's, unchanged except for the patches.

**The Fossify suite** (GPL-3.0, the maintained successor of Simple Mobile Tools, built and signed by Fossify and distributed by F-Droid) replaces the AOSP apps one for one: Launcher for Launcher3's home screen, Gallery for Gallery2, Calendar, Contacts, Clock for DeskClock, Phone for Dialer, Messages for `messaging`, Music Player for Music, Camera for Camera2, Calculator; and adds File Manager, Documents, Notes, Voice Recorder, Paint and Keyboard. **F-Droid** itself is in the image, and **Organic Maps** and **Fennec F-Droid** (F-Droid's build of Firefox for Android, MPL-2.0) ride along as preloads (below). Fennec replaces Browser2, AOSP's WebView test shell, as the browser. Every APK is pinned in `dev/toolchain.json` by SHA-256 and signing certificate, verified against F-Droid's signed index when pinned, downloaded by the bootstrap into `work\device-tools\`, and copied into the tree by `apply-local.sh` from the list in `prebuilt/apks.txt`; no APK is ever committed. `prebuilt/Android.bp` imports them `preprocessed`, so Soong checks alignment and copies them unmodified and the publisher's signature survives, which is what lets F-Droid update them afterwards.

What stays from AOSP, deliberately: Launcher3QuickStep (SystemUI binds its quickstep service for gesture navigation and recents; Fossify Launcher is made the home screen by the first-boot service assigning it the HOME role: both answer HOME with equal priority, so Android would otherwise ask, and a `preferred-apps` file turned out not to be honoured reliably), LatinIME beside Fossify Keyboard (a working keyboard must never depend on a prebuilt), DocumentsUI (the system file picker), Settings, and everything delivered as a Mainline module. The framework overlay names Fossify Phone and Messages as the default dialer and SMS app through `config_defaultDialer` and `config_defaultSms`.

**Preloads and the first-boot service.** Organic Maps and Fennec ship their native libraries compressed, which a system-image prebuilt cannot keep without rewriting the APK, and a rewritten APK would need our signature, after which F-Droid could no longer update it. So they travel in `/product/etc/preload/`, and `vedotom-firstboot` (a `sh_binary` started by `init.vedotom.rc` once `sys.boot_completed` is set, as root in the userdebug-only `su` domain) installs them as ordinary apps with F-Droid as the installer, keeping a marker in `/data/local/vedotom-firstboot/` so later boots do nothing. It then gives Fennec the BROWSER role, once, so links from other apps open in it without a chooser. The same service sets the Fossify launcher icons to teal, to match the wallpaper. Inside the apps Fossify already uses the system's Material You colours on Android 12 and later; the icon colour is a separate per-app choice, stored as one enabled `SplashActivity.<Colour>` alias plus two preferences the app reconciles on every start. The service sets all three, once per app, so a colour chosen later in an app's settings is kept.

**Fennec and the MessageQueue flag.** Fennec's engine, Gecko, calls the hidden framework method `MessageQueue.next()` from native code. The `trunk_staging` release configuration this project builds selects an experimental queue, `CombinedDeliMessageQueue`, in which that method carries no `@UnsupportedAppUsage` mark, so Android blocks it and Gecko crashes on its first start (a null-pointer write in `libxul.so`, preceded by `hiddenapi: Accessing hidden method Landroid/os/MessageQueue;->next() ... denied`). The release configuration Android 16 actually ships for this tag, `bp4a`, uses `LegacyMessageQueue`, where the method stays reachable. `dev/aosp/product/vedotom/gsi/release/` contributes that one value to `trunk_staging`: the build discovers `device/*/*/release/release_config_map.textproto` by itself, and `get_build_var RELEASE_PACKAGE_MESSAGEQUEUE_IMPLEMENTATION` shows the result. On an image built before the fix, the same method can be exempted at runtime with `settings put global hidden_api_blacklist_exemptions 'Landroid/os/MessageQueue;->next'`.

F-Droid flags Fennec with the *Tracking* anti-feature: it can contact Mozilla services, and its first-run screen says it sends diagnostic and interaction data. Turn that off under *Manage settings* on the welcome screen, or later in Settings, Data collection.

**Offline maps** are not in the image. The US set alone is 15.5 GB, more than doubling the image and every push of it, and a DSU image's data partition defaults to 8 GB. Install with a larger one and push the maps from the PC copy after the first boot:

```powershell
.\dev\Install-Gsi.ps1 -Action Install -Image "$Work\device-tools\gsi\own\system.img" -UserdataGiB 24
.\dev\Install-Gsi.ps1 -Action Boot
.\dev\Push-OfflineMaps.ps1 -Region 'United States of America'
```

## Changing something

Changes live in this repository, not only in the tree, and `apply-local.sh` (run by `sync.sh` and `build-gsi.sh`, safe to re-run) puts them into the tree:

- **`dev/aosp/product/vedotom/gsi/`** is copied to `device/vedotom/gsi/` and defines the lunch target **`vedotom_arm64`**: AOSP's `aosp_arm64` with this project's settings layered on top. `aosp_arm64.mk` hides its GSI-specific settings behind a check on the product name, so the derived product repeats them, the same way AOSP's own `aosp_arm64_fullmte.mk` does. This is where product-level changes go: properties, packages, files copied into the image. The first one is `debug.sf.nobootanimation=1`, which removes the boot animation (the screen stays on the bootloader's splash until the lock screen); the makefile shows the one-line alternative for shipping your own `bootanimation.zip` instead.
- **`dev/aosp/patches/`** holds unified diffs against upstream projects, one project per file, named `<project-path-with-dashes>-NNNN-<what>.patch`. They are applied with `git apply` and skipped when the tree already has them; a patch that no longer applies after a tag change stops the script so you rebase it deliberately. The first one fixes the `gpuservice` crash loop: `BpfMap`'s path constructor aborts the process when a pinned BPF map is missing, so the `isValid()` check in `GpuWork::getBpfMap` never ran on a kernel without the `gpu_work_period` tracepoint; the patch uses `init()`, which reports the failure, and GPU-work tracking is simply disabled.

`verify-tree.sh` lists `frameworks/native` as a project with local changes and leaves it alone; that is the patch.

Both changes were confirmed on the device the same evening: the image boots with no animation and `gpuservice` stays up, logging one warning instead of dying every 30 seconds. The rebuild after switching products took 15 minutes, most of it Soong re-analysing the tree for the new product name. One rule to know: the GSI forbids `PRODUCT_SYSTEM_PROPERTIES` (its artifact-path requirement), so properties go in `PRODUCT_PRODUCT_PROPERTIES`, which lands in the product partition's `build.prop` (under `/system/product/etc/` in a GSI) and is read just the same.

The inner loop is: edit under `~/aosp` (in WSL; a VS Code *WSL* window is handy for that), `build-gsi.sh` again, `Install-Gsi.ps1 -Action Discard` then `-Action Install -Image …` and `-Action Boot`. Good first targets: `frameworks/base` for the framework, `packages/apps/Settings`, `packages/apps/Launcher3`, `system/sepolicy` for policy; `build/make/target/product/gsi_release.mk` and `aosp_arm64.mk` for what goes into the image. `m <module>` builds one module; `m` builds the image.

## Things to know

- **Signing.** Your image is signed with AOSP's public test keys, not Google's. On this unlocked device the DSU installer accepted Google's image while unable to extract a trusted key, and `gsid` doesn't enforce trusted keys in the `orange` boot state, so a test-keyed image is expected to install; the first `-Action Install` confirms it. Never ship or publish a test-keyed image as if it were a release.
- **Licensing.** AOSP is Apache-2.0 (with GPL kernel sources you aren't building). Google's GSI terms apply to Google's binary, not to your own build. Nothing from Motorola's vendor partition is part of what you build or distribute.
- **Size.** Google's GSI unsparsed to 1.8 GB; `aosp_arm64` with `userdebug` is similar. The DSU installer handles sparse images.
- **The scripts are plain bash, on purpose.** `build-gsi.sh` does not use `set -e` or `set -u`: AOSP's `envsetup.sh` reads unset variables (`TOP`) and `lunch` returns non-zero on its way to success, so strict mode aborts the build in its first second. Failures are checked explicitly instead. The scripts must also keep **LF line endings**: WSL's bash reads a `\r` at the end of every line as part of the command (`set: pipefail\r: invalid option name`, `cd: ...\r: No such file`). `.gitattributes` normalises them on commit, but a Windows editor or a tool that rewrites the file can hand WSL a CRLF copy; `sed -i 's/\r$//' dev/aosp/*.sh` repairs it, and the self-test parses each script with `bash -n`.
- **No ccache.** Every build rule runs in AOSP's sandbox (nsjail), which mounts only `out/` and `/tmp` writable, so ccache fails with `Read-only file system` on its first write and the build stops. AOSP's own notes (`build/make/core/ccache.mk`) say it adds little over incremental builds, which is what you get anyway.
- **Lunch names.** Release tags occasionally rename release configurations; if `lunch` rejects the pinned target after a sync, `lunch` with no arguments lists what the tag offers, and the pin in `toolchain.json` is the one place to change it.

Next: [Your first app in Android Studio](android-studio.md).
