# Development environment

A reproducible Windows setup for working on this kit and building Android software for the rooted XT2617V. Every version and download is pinned, with hashes, in [dev/toolchain.json](dev/toolchain.json).

## Quick start

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1 -AndroidStudio      # idempotent; re-run any time
. .\dev\Enter-DevShell.ps1                      # in every new window
.\dev\Build-Kit.ps1                             # rebuild helpers + modules (kit\ and dev\modules), compare with committed copies
.\dev\Test-DevEnv.ps1                           # end-to-end self-test (36 checks; exit code = failures)
```

`Test-DevEnv.ps1` exercises every tool, not just its version. It compiles and dexes the helpers, decompiles with jadx, cross-compiles an aarch64 Android 16 binary with the NDK, builds the docs site, imports val-protocol, re-verifies every kit pin, and checks the git safety settings (hook active, private paths ignored, upstream fetch-only). It reports `origin`'s visibility but doesn't require it to be private: the repository is public by design, and the ignore rules plus the hook are what keep device data out of it. It never talks to the phone and never starts an ADB server.

In VS Code, the default terminal profile **OtomDev dev shell** dot-sources `Enter-DevShell.ps1` for you. The tasks in `.vscode/tasks.json` run the bootstrap, the rebuild (the default build task, Ctrl+Shift+B) and scrcpy.

Add `-AcceptAndroidSdkLicenses` only after reading Google's Android SDK terms. Without it, the script asks you to accept them interactively.

## What you get

| Area | Tools |
| --- | --- |
| Java and DEX | Microsoft OpenJDK 21; pinned R8 8.3.37 (`r8d8` function), the version used for the reference helper build |
| Android SDK | cmdline-tools, platform-tools, `platforms;android-36` (Android 16, the phone's OS), build-tools 36.1.0, NDK |
| IDE | Android Studio (optional), and VS Code with recommended extensions |
| Device | Kit platform-tools **37.0.1** (the tested version, first on PATH), scrcpy for mirroring and control |
| Reverse engineering | jadx (DEX/APK decompiler), apktool (`apktool` function), 7-Zip |
| Guide inputs | DFRoot 4.7, KernelSU 3.3.1, Magisk 31.1, Test DPC QR, val-protocol at its pinned commit, all hash-checked; Motorola driver verified by signature and hash |
| Python | `.venv` with val-protocol's requirements and pyasn1 |
| Safety | `.githooks/pre-commit` blocks device images, keys, logs, files over 1 MiB, the private working folders, and lines that look like IMEIs or serials |

`Enter-DevShell.ps1` sets the same variables as GUIDE.md's "Make a work folder" block (`$Work`, `$Kit`, `$adb`, `$fb`, `$Backup`, `$py`). This repository's root acts as both the work folder and the kit.

## Rules for phone work

- **Close Android Studio while following GUIDE.md.** Studio runs its own, newer ADB server, and two server versions fighting over one phone can drop the connection mid-operation.
- Always call `$adb` and `$fb`. They point to the tested 37.0.1 binaries.
- `private-backups/`, `lk-analysis/`, `lk-patch-analysis/` and `magisk-patch-files/` are git-ignored and blocked by the hook. Keep them off any cloud-synced folder as well.

## Changing pinned versions

1. Edit `dev/toolchain.json` with the new URL and hash, taken from the publisher (for SDK packages, Google's `repository2-3.xml`).
2. Re-run the bootstrap. A file that is present but doesn't match its pin is never silently overwritten.
3. **Don't change the `kit` section's pins** unless you are deliberately re-validating the phone procedure. Those are the exact inputs from the tested session.

## Rebuilding release artifacts

`Build-Kit.ps1` writes to `dev/build/` and reports whether each rebuilt artifact matches the committed copy: the two kit helpers, the two kit modules, and `dev/modules/wifi-extra-debloat.zip`. Module ZIPs are compared by their entries' contents, because the generator stamps the current time on each entry. `-Promote` copies the rebuilt files over the committed ones. For kit files, then regenerate `kit/SHA256SUMS.txt`; in all cases review `git diff`.

## This fork's own module

`dev/modules/wifi-extra-debloat.zip` reversibly hides 19 more preinstalled packages on top of the kit's carrier module: AT&T, Cricket and Facebook partner stubs, Motorola telemetry and support apps, Ready For desktop mode, visual voicemail and Digital Wellbeing. It is generated from `dev/modules/wifi-extra-debloat-manifest.json` by `dev/modules/build_extra_module.py`, with the same overlay-path validation as the kit's builder, and `Build-Kit.ps1` checks that it reproduces. It lives in `dev/` rather than `kit/` so the upstream kit stays byte-for-byte unchanged. The walkthrough's Stage 8 installs it.
