# Build your own system image

[Running a GSI through DSU](../device/gsi.md) proved that this device's vendor layer will run a system it has never seen. That system is what AOSP builds from source as the `aosp_arm64` target, the very same target behind Google's image. Build it yourself and you have a system image you can change anything in, booted on the phone the same safe way. This page sets that up.

## What you get, and what you don't

Yours to change: the framework, system services, the launcher, Settings, system apps, SELinux policy for the system side, and the build type: a `userdebug` build is the real engineering build this project has been approximating, with `adb root` that works and debuggers that attach to anything. Also yours: fixing what the stock GSI gets wrong on this hardware, such as the `gpuservice` crash loop, with the source in front of you.

Not yours: the kernel, the vendor HALs, firmware and the modem. They stay Motorola's, under the Treble interface, and the GSI's hardware gaps (two of three cameras, for example) are limits of that interface rather than of your build. A full device port is a different, much larger project.

## Where the build lives

The AOSP tree is 300–400 GB with its output, needs a case-sensitive Linux filesystem, and builds very slowly across WSL's `/mnt/c` boundary, so it lives on **WSL's own disk** (`~/aosp` in the Ubuntu instance), not in this repository and not on a Windows path. This repository drives it: the scripts in `dev/aosp/` run inside WSL, and the finished image comes back to `work\device-tools\gsi\own\`, where `Install-Gsi.ps1` boots it.

Requirements that matter: 16 cores and 32 GB of RAM make the first build a matter of hours rather than a day; WSL's default memory cap is half of RAM, which gets the big link steps killed, so `%UserProfile%\.wslconfig` sets `memory=26GB` and `swap=16GB` under `[wsl2]` (apply with `wsl --shutdown`). Disk: the WSL instance here has a 1 TB virtual disk.

## The pin

`deviceTools.aosp` in `dev/toolchain.json` names the release tag **`android-16.0.0_r4`**, the AOSP release that produced the GSI binary `BP4A.251205.006` validated on this device, so what you build is what was tested, before you change anything. The lunch target is `aosp_arm64-trunk_staging-userdebug`.

## Steps

From a dev shell (each script runs inside WSL and is safe to re-run):

```powershell
wsl -d Ubuntu -- bash dev/aosp/setup.sh       # build dependencies, repo, git-lfs, JDK (minutes)
wsl -d Ubuntu -- bash dev/aosp/sync.sh        # repo init at the tag + partial-clone sync (hours, ~120 GB)
wsl -d Ubuntu -- bash dev/aosp/build-gsi.sh   # lunch + m; copies system.img back (hours the first time)
```

Or chain the two long steps and walk away:

```powershell
wsl -d Ubuntu -- bash dev/aosp/build-after-sync.sh   # waits for a running sync, or runs one; then builds
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

## Changing something

The inner loop is: edit under `~/aosp` (in WSL; a VS Code *WSL* window is handy for that), `build-gsi.sh` again, `Install-Gsi.ps1 -Action Discard` then `-Action Install -Image …` and `-Action Boot`. Good first targets: `frameworks/base` for the framework, `packages/apps/Settings`, `packages/apps/Launcher3`, `system/sepolicy` for policy; `build/make/target/product/gsi_release.mk` and `aosp_arm64.mk` for what goes into the image. `m <module>` builds one module; `m` builds the image.

## Things to know

- **Signing.** Your image is signed with AOSP's public test keys, not Google's. On this unlocked device the DSU installer accepted Google's image while unable to extract a trusted key, and `gsid` doesn't enforce trusted keys in the `orange` boot state, so a test-keyed image is expected to install; the first `-Action Install` confirms it. Never ship or publish a test-keyed image as if it were a release.
- **Licensing.** AOSP is Apache-2.0 (with GPL kernel sources you aren't building). Google's GSI terms apply to Google's binary, not to your own build. Nothing from Motorola's vendor partition is part of what you build or distribute.
- **Size.** Google's GSI unsparsed to 1.8 GB; `aosp_arm64` with `userdebug` is similar. The DSU installer handles sparse images.
- **The scripts are plain bash, on purpose.** `build-gsi.sh` does not use `set -e` or `set -u`: AOSP's `envsetup.sh` reads unset variables (`TOP`) and `lunch` returns non-zero on its way to success, so strict mode aborts the build in its first second. Failures are checked explicitly instead. The scripts must also keep **LF line endings**: WSL's bash reads a `\r` at the end of every line as part of the command (`set: pipefail\r: invalid option name`, `cd: ...\r: No such file`). `.gitattributes` normalises them on commit, but a Windows editor or a tool that rewrites the file can hand WSL a CRLF copy; `sed -i 's/\r$//' dev/aosp/*.sh` repairs it, and the self-test parses each script with `bash -n`.
- **No ccache.** Every build rule runs in AOSP's sandbox (nsjail), which mounts only `out/` and `/tmp` writable, so ccache fails with `Read-only file system` on its first write and the build stops. AOSP's own notes (`build/make/core/ccache.mk`) say it adds little over incremental builds, which is what you get anyway.
- **Lunch names.** Release tags occasionally rename release configurations; if `lunch` rejects the pinned target after a sync, `lunch` with no arguments lists what the tag offers, and the pin in `toolchain.json` is the one place to change it.

Next: [Your first app in Android Studio](android-studio.md).
