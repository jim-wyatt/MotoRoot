# Tour the repository

```text
VedoTom/
├── device/              What goes to the device
│   ├── helpers/           two tiny Java programs + their compiled .dex files
│   ├── modules/           seven module ZIPs, their manifests, and the builder
│   │   ├── manifests/       one JSON per module: what it hides or runs, and why
│   │   ├── scripts/         the post-fs-data.sh of the two development modules
│   │   └── build_modules.py builds the ZIPs from the manifests
│   └── scripts/           Prepare-MagiskImage.ps1: file-only, never flashes
├── dev/                 The development environment (PC side)
│   ├── toolchain.json     every version and hash, in one place
│   ├── Bootstrap-DevEnv.ps1   installs everything
│   ├── Enter-DevShell.ps1     per-terminal setup (dot-source it)
│   ├── VedoTom.psm1           device helpers the phone scripts share (root with either su, boot waits)
│   ├── Build-Device.ps1       rebuilds and compares the device artifacts
│   ├── Test-DevEnv.ps1        the self-test (PC side; never touches the phone)
│   ├── Test-Device.ps1        the phone-side smoke test: root, logs, NDK, Perfetto, Frida, scrcpy
│   ├── Set-DevSettings.ps1    development-target settings on the phone (animations, ADB, logs)
│   ├── Trace-Device.ps1       records a Perfetto trace into work\traces
│   ├── Dump-DeviceInfo.ps1    hardware inventory into work\device-info (private)
│   ├── Install-Gsi.ps1        boots Google's AOSP GSI (or your own) through DSU
│   ├── Get-RemoteImage.ps1    fetch a verified image from a separate build machine over SSH
│   ├── Deploy-Image.ps1       fetch, install and boot an image, then report
│   ├── aosp/                  AOSP in WSL: setup, sync, verify-tree, apply-local, build-gsi, build-after-sync
│   │   ├── product/vedotom/gsi/   the vedotom_arm64 product: makefiles, framework overlay, prebuilt app list,
│   │   │                          first-boot service (APKs come from work/, never
│   │   │                          committed)
│   │   └── patches/               our diffs against upstream projects
│   └── .tools/ .cache/ build/ .venv-docs/    generated; git-ignored
├── docs/                These pages, including the full device procedure
├── work/                YOUR files. Git-ignored in full.
│   ├── platform-tools/    adb and fastboot 37.0.1
│   ├── *.apk, *.msi       the procedure's downloads
│   ├── val-protocol/      bootloader patching tool, at its pinned commit
│   ├── device-tools/      frida-server and the pinned APKs (F-Droid, and the image's apps)
│   ├── .venv/ .venv-frida/  Python for val-protocol; Frida's PC tools
│   ├── traces/ device-info/ Perfetto traces and hardware dumps (private)
│   ├── aosp-sync.log aosp-build.log   the AOSP scripts' logs
│   └── private-backups/   your device's original images, made in Stage 3
├── .githooks/pre-commit The safety net
├── .github/workflows/   Builds and publishes this site
├── .vscode/             Terminal profile, tasks, recommended extensions
├── LICENSE  NOTICE.md  DISCLAIMER.md
└── zensical.toml        Site configuration
```

## The three folders that matter

### `device/`: what the procedure sends to the device

Everything here is generic to the model, never to your unit, which is why it can be committed. The helpers are a few lines of Java each; you'll read and rebuild them in [Write a system helper](../develop/helper-programs.md). The modules are generated from their manifests, so to change what one hides you edit a JSON file and rebuild ([Build a system module](../develop/magisk-modules.md)). The preparation script is the one piece of the procedure that is a script rather than a sequence of commands, because it has enough guards that running them by hand would be error-prone.

### `work/`: yours, and private

Every download and every file the device procedure creates goes here. The folder is ignored by Git in its entirety, and the pre-commit hook blocks it as a second line of defence. Your device's backup images live in `work/private-backups/`. **Back that folder up somewhere safe that isn't a public cloud share**: it is the only way to restore the device if something goes wrong.

### `dev/`: the tooling you'll use every day

The dev shell puts you at the repository root and gives you these variables, which the walkthrough's commands use directly:

| Variable | Points to | Used for |
| --- | --- | --- |
| `$Work` | `work\` | downloads, generated images |
| `$Backup` | `work\private-backups` | your original partition images |
| `$adb` | `work\platform-tools\adb.exe` | every ADB command |
| `$fb` | `work\platform-tools\fastboot.exe` | bootloader-mode commands |
| `$py` | `work\.venv\Scripts\python.exe` | the Val Protocol scripts |

Device-side files are referenced relative to the root: `.\device\modules\wifi-ota-guard.zip`, `.\device\scripts\Prepare-MagiskImage.ps1`.

And these commands:

| Command | What it does |
| --- | --- |
| `docs` | Serves this documentation at <http://localhost:8000> with live reload |
| `apktool ...` | Decode or rebuild an APK's resources |
| `r8d8 ...` | Google's D8 compiler: `.class` → `.dex` (the exact version the helpers were built with) |
| `.\dev\Build-Device.ps1` | Rebuild the helpers and modules and compare with the committed copies |
| `.\dev\Test-DevEnv.ps1` | Self-test everything on the PC |
| `.\dev\Test-Device.ps1` | Check every development workflow against the connected phone |
| `adbwifi` | Connect ADB to the phone over Wi-Fi ([engineering device](../device/dev-setup.md)) |
| `Start-Frida` | Start Frida's agent on the device as root ([instrumentation](../develop/instrumentation.md)) |
| `.\dev\Set-DevSettings.ps1` | Apply (or `-Reset`) the development-target settings ([engineering device](../device/dev-setup.md#development-target-settings)) |
| `.\dev\Trace-Device.ps1` | Record a Perfetto system trace ([tracing](../develop/tracing.md)) |
| `.\dev\Dump-DeviceInfo.ps1` | Dump the hardware inventory ([hardware](../device/hardware.md)) |
| `.\dev\Install-Gsi.ps1` | Download, install, boot once and discard a GSI via DSU ([GSI](../device/gsi.md)) |

## Why pin everything?

Open `dev/toolchain.json`. Every tool has a version and a hash. This matters more here than in most projects: the device procedure was validated with *specific* versions, and a newer Magisk or a newer `adb` might behave differently in ways nobody has tested on this model. Pinning means your environment matches the one the procedure was proven on, and that someone else can reproduce yours exactly.

Next: [Your first ADB session](first-adb-session.md).
