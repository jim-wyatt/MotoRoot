# Development environment

A reproducible Windows setup for working on this project and building Android software for the prepared XT2617V. Every version and download is pinned, with hashes, in [dev/toolchain.json](dev/toolchain.json). The user-facing documentation is the site built from `docs/`; this file is the short reference for people working on the repository itself.

## Quick start

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1 -AndroidStudio      # idempotent; re-run any time
. .\dev\Enter-DevShell.ps1                      # in every new window
.\dev\Build-Device.ps1                          # rebuild helpers + modules, compare with the committed copies
.\dev\Test-DevEnv.ps1                           # end-to-end self-test; exit code = failures
```

`Test-DevEnv.ps1` exercises every tool, not just its version. It compiles and dexes the helpers, decompiles with jadx, cross-compiles an aarch64 Android 16 binary with the NDK, builds the docs site, imports val-protocol, re-verifies every pinned input, and checks the git safety settings (hook active, private paths ignored, no-reply commit email). It reports `origin`'s visibility but doesn't require it to be private: the repository is public by design, and the ignore rules plus the hook are what keep device data out of it. It never talks to the phone and never starts an ADB server.

In VS Code, the default terminal profile **OtomDev dev shell** dot-sources `Enter-DevShell.ps1` for you. The tasks in `.vscode/tasks.json` run the bootstrap, the rebuild (the default build task, Ctrl+Shift+B), the self-test and scrcpy.

Add `-AcceptAndroidSdkLicenses` only after reading Google's Android SDK terms. Without it, the script asks you to accept them interactively.

## Layout

| Folder | Contents |
| --- | --- |
| `device/` | Files the procedure sends to the device: `helpers/` (two `app_process` programs, source and DEX), `modules/` (three Magisk modules, their manifests, and `build_modules.py`), `scripts/Prepare-MagiskImage.ps1`. Generic to the model, never to a unit. |
| `dev/` | The PC side: `toolchain.json`, bootstrap, dev shell, self-test, `Build-Device.ps1`. Generated tool folders inside it are git-ignored. |
| `docs/` | The documentation site. `docs/device/` is the authoritative procedure. |
| `work/` | Downloads, venvs, backups, outputs. Git-ignored in full and blocked by the hook. |

## What you get

| Area | Tools |
| --- | --- |
| Java and DEX | Microsoft OpenJDK 21; pinned R8 8.3.37 (`r8d8` function), the version the helpers are built with |
| Android SDK | cmdline-tools, platform-tools, `platforms;android-36` (Android 16, the device's OS), build-tools 36.1.0, NDK |
| IDE | Android Studio (optional), and VS Code with recommended extensions |
| Device | Pinned platform-tools **37.0.1** (the tested version, first on PATH), scrcpy for mirroring and control |
| Reverse engineering | jadx (DEX/APK decompiler), apktool (`apktool` function), 7-Zip |
| Device inputs | DFRoot 4.7, KernelSU 3.3.1, Magisk 31.1, Test DPC QR, val-protocol at its pinned commit, all hash-checked; Motorola driver verified by signature and hash |
| Device tools | `work\device-tools\`: Frida server (hash-pinned, must match the PC `frida` version) and the Termux APK (hash-pinned against the release's checksums) |
| Python | `work\.venv` with val-protocol's requirements and pyasn1; `work\.venv-frida` with `frida`/`frida-tools`; `dev\.venv-docs` for the site |
| Safety | `.githooks/pre-commit` blocks device images, keys, logs, files over 1 MiB, the private working folders, and lines that look like IMEIs or serials |

`Enter-DevShell.ps1` puts you at the repository root and sets `$Work`, `$adb`, `$fb`, `$Backup` and `$py`, which the walkthrough's commands use directly. Device-side files are referenced relative to the root (`.\device\...`). It also defines `adbwifi` (connect over Wi-Fi), `Start-Frida` and `Connect-Debian` (SSH into Termux's Debian over the cable); `dev\Trace-Device.ps1` records a Perfetto trace, `dev\Dump-DeviceInfo.ps1` writes a hardware inventory to `work\device-info\` (private: it contains identifiers), and `dev\Install-Gsi.ps1` downloads (after you accept Google's terms), installs, boots once and discards the pinned AOSP GSI through DSU, or your own build with `-Image`. `dev\aosp\*.sh` run inside WSL to set up, sync (`android-16.0.0_r4`, the tag behind the validated GSI) and build AOSP's `aosp_arm64` target (`build-after-sync.sh` chains the two, logging to `work\aosp-*.log`); the tree lives on WSL's disk, never in this repo. Keep those scripts LF: WSL's bash chokes on CRLF.

## Rules for phone work

- **Close Android Studio while following the walkthrough.** Studio runs its own, newer ADB server, and two server versions fighting over one device can drop the connection mid-operation.
- Always call `$adb` and `$fb`. They point to the tested 37.0.1 binaries.
- `work\private-backups\`, `work\lk-analysis\`, `work\lk-patch-analysis\` and `work\magisk-patch-files\` hold per-unit data. They are git-ignored and blocked by the hook; keep them off any cloud-synced folder as well.

## Changing pinned versions

1. Edit `dev/toolchain.json` with the new URL and hash, taken from the publisher (for SDK packages, Google's `repository2-3.xml`).
2. Re-run the bootstrap. A file that is present but doesn't match its pin is never silently overwritten.
3. **Don't change the `inputs` section's pins** unless you are deliberately re-validating the device procedure. Those are the exact inputs from the tested runs; record a re-validation on `docs/device/validation.md`.

## Rebuilding the device artifacts

`Build-Device.ps1` rebuilds the two helper DEX files and the three module ZIPs into `dev/build/` and reports whether each matches the committed copy in `device/`. Module builds are deterministic (fixed entry order and timestamps), so they are compared by hash; helpers are compared byte for byte, and a mismatch there usually means a different `javac` build changed the debug line tables, not the behaviour. `-Promote` copies the rebuilt files over the committed ones; review `git diff` and commit the source and artifact together.

## The modules

All five modules are generated from `device/modules/manifests/*.json` by `device/modules/build_modules.py`. Two kinds: **overlay** modules list `packages` (the builder validates every path and refuses anything outside `/product` and `/system_ext` app directories), and **script** modules name Magisk lifecycle scripts under `device/modules/scripts/` (packed as LF, no BOM, mode 755 regardless of how git checked them out; the self-test verifies that). To hide a different set of apps, add a manifest: find each package's APK with `& $adb shell pm path <package>`, record its directory as `hidden_directory`, rebuild, and reinstall. Each ZIP carries its manifest as `manifest.json`, so a module found later is self-describing. The two development modules (`dev_debuggable`, `dev_adb_tcp`) are documented in `docs/device/dev-setup.md`.

## Legal

- `LICENSE`: MIT, for the project.
- `NOTICE.md`: the original MIT notice for the parts derived from parsimo2010's guide, and the licenses of the third-party software the bootstrap downloads.
- `DISCLAIMER.md`: the terms of use. Keep `docs/reference/disclaimer.md` identical to it.
