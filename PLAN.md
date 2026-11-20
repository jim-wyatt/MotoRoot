# Plan: the environment project, refactored (2026-11-19)

This file is the working plan and the hand-off between the two nodes while the refactor runs. It is deleted when phase 5 is done; what stays true moves into the docs.

## What this project is now

VedoTom is **the one project that bootstraps and maintains the Moto device** (a Moto G Power 2026, XT2617V) as a development device. Apps are built in other projects. This one holds everything that makes the device and the PCs a development environment, end to end:

- **bootstrap**: from a factory phone and a bare PC to the development baseline (workstation set up, bootloader unlocked, root, stock trimmed, the VedoTom image built, deployed and verified);
- **maintain**: change the image, move the AOSP tag, update pins, re-verify, recover or go back to stock.

It's made of:

- the **workstation** toolchain (Windows: SDK, NDK, platform-tools, Studio, analysis tools), pinned and self-tested;
- the **image**: `vedotom_arm64`, an AOSP system image on top of the phone's stock vendor layer, booted through DSU;
- the **build node** (the Legion T5), which syncs AOSP, builds and tests the image, and publishes it;
- the **device node** (the PC the phone is plugged into), which fetches, deploys and verifies images;
- the **stock preparation** (bootloader unlock, Magisk, modules), the first half of the bootstrap. It runs once per device but must stay runnable from this repo, for a second unit or a full reset.

The change loop: edit the image on a branch → the build node builds and tests → the device node deploys and verifies → merge.

## Name: aosp-academy (the user, 2026-11-19)

The project is renamed from VedoTom to **aosp-academy** everywhere.

| Where | Name |
| --- | --- |
| The project, the docs, the GitHub repo | `aosp-academy` |
| The CLI | `aosp-academy` |
| The Python package | `aosp_academy` |
| The image product | `aospacademy_arm64`: no underscore after `aosp`, so it can't be mistaken for Google's `aosp_*` products |
| Properties, device dirs, overlay and module names | `aospacademy` |

The GitHub repo was renamed on 2026-11-19, at the user's request (`jim-wyatt/VedoTom` to `jim-wyatt/aosp-academy`). Git URLs redirect; the Pages site moved to jim-wyatt.github.io/aosp-academy. The local folder `C:\Users\Jim\MotoDev` stays as it is. The trademark rule is the user's: no "Android", "Moto", "droid" or other marks in the name.

## Portability (the user, 2026-11-19)

- **The build doesn't need Windows or WSL.** The build node is any x86-64 Linux host: native Linux, WSL2, a cloud VM or a container.
- **No PowerShell.** All tooling is **Python 3, standard library only**, run as one command, `vedotom` (`python -m vedotom`). It works on Windows, Linux and macOS. That's what Android's own tooling uses (`repo`, the AOSP build scripts, `acloud`). Bash stays only where it has to: the AOSP wrappers (`envsetup.sh` and `lunch` are bash) and the scripts that run on the phone (`sh`).
- **Before the first `vedotom` command:** a Python 3.11+ and git. On Windows that's `winget install Python.Python.3.12 Git.Git`.
- **Platform-specific steps stay inside the command**, chosen by OS: winget packages and the Motorola driver's Authenticode check on Windows, a package list to install on Linux. The Android SDK, platform-tools, NDK, JARs and APKs install the same way everywhere, from the pins.
- **Build settings come from the environment** with defaults: `AOSP_DIR` (the tree), `JOBS` and `PUBLISH_DIR`. Nothing assumes `/mnt/c`, WSL or a Windows user. The image inputs (the Fossify APKs) are fetched by `vedotom image inputs` on the build node itself.
- **`image/build/Containerfile`** gives a reproducible build host (Ubuntu LTS plus AOSP's packages and `repo`). It's optional.
- **Publishing writes an output directory**: the image, its parts, the checksums and `build.prop`. How another machine reaches it (the Legion's SFTP chroot, HTTP, a copy) is that host's own setup, documented but not coded into the build.

## Target layout

| Path | Holds | Runs on |
| --- | --- | --- |
| `toolchain.json` | every pin: SDK, tools, device inputs, APKs, the AOSP tag and lunch target | all |
| `vedotom/` | the Python package: CLI, pins, downloads, adb helpers, workstation setup and check, image fetch and deploy, DSU, device test, settings, inventory, tracing, stock artifacts | all |
| `vedotom`, `vedotom.cmd` | launchers at the root (`./vedotom deploy`, `.\vedotom deploy`) | all |
| `image/product/` | the `vedotom_arm64` product (makefiles, `Android.bp` mirror, overlays, first boot, prebuilts) | build node |
| `image/patches/` | patches to AOSP projects | build node |
| `image/build/` | the bash wrappers around AOSP (host setup, sync, verify, apply, build, publish) and the Containerfile | build node (Linux) |
| `stock/` | stock-system preparation sources: helpers (Java), module manifests and on-phone scripts, the built artifacts | device node |
| `tests/` | `unittest` tests for the package (no device, no network) | all, and CI |
| `docs/` | the site, rewritten around the loop (below) | |
| `work/` | everything generated or downloaded: tools, caches, venvs, images, private data (git-ignored) | all |

`dev/` and `device/` go away, and so does every `.ps1`.

### Commands

| Command | Replaces |
| --- | --- |
| `aosp-academy setup [--studio] [--accept-sdk-licenses]` | `Bootstrap-DevEnv.ps1` |
| `aosp-academy check` | `Test-DevEnv.ps1` |
| `aosp-academy env [--shell pwsh\|cmd\|bash]` / `aosp-academy shell` | `Enter-DevShell.ps1` (environment for a shell, or a subshell with it) |
| `aosp-academy image inputs\|setup\|sync\|build` | the input download, `setup.sh`, `sync.sh`, `build-gsi.sh` (build node) |
| `aosp-academy fetch [--check] [--streams N]` | `Get-RemoteImage.ps1` |
| `aosp-academy deploy [--no-fetch] [--single-boot] [--keep-image] [--yes]` | `Deploy-Image.ps1` |
| `aosp-academy gsi install\|boot\|stock\|discard\|status` | `Install-Gsi.ps1` |
| `aosp-academy device test\|settings\|info\|trace\|frida` | `Test-Device`, `Set-DevSettings`, `Dump-DeviceInfo`, `Trace-Device`, `Start-Frida` |
| `aosp-academy stock build [--promote]` / `aosp-academy stock magisk-image` | `Build-Device.ps1`, `Prepare-MagiskImage.ps1` |

## Target docs

1. **Home**: what the project is, the two nodes, the change loop as one diagram, the educational and vendor-neutral framing.
2. **Set up**: the workstation, the build node, connecting the device.
3. **Develop apps against the device** (for the other projects): an Android Studio project on this device, debugging any process (JDWP), logs, Perfetto, Frida, the NDK, inspecting APKs, what the image sets by default, limits.
4. **Change the environment**: what's in the image and why, the change loop step by step, patches, moving the AOSP tag, the validation checklist, the backlog.
5. **The device**: hardware inventory, how it was prepared (the walkthrough, kept as reference), the stock baseline, going back to stock, recovery.
6. **How Android works**: the existing concept pages, trimmed to what this project uses.
7. **Reference**: scripts, pins, troubleshooting, decisions log (from backlog section 6), validation history, glossary, credits, disclaimer.

`image-backlog.md` is split three ways: open backlog, decisions log and validation history.

## Phases

0. **Android 17** (in progress). Build 10 from `aosp-17` (ed7e8f4) on the build node, then the device node deploys it and verifies it against build 9, plus fingerprint HIDL 2.1, `adb_keys`, gpuservice without the patch, and the 17 GSI hardware list. Pass: merge `aosp-17` into `main`. Fail: fix on `aosp-17`, rebuild.
1. **Plan** (this file), on branch `restructure`, cut from `aosp-17`.
2. **Code restructure** on `restructure`.
   - a. The layout move (done as WIP).
   - b. The `vedotom` package, ported script by script. The PowerShell scripts stay until their port is checked, then each is deleted. Order: the core (pins, downloads, adb) → fetch, gsi and deploy → device test, settings, info and trace → setup, env and check → stock → image.
   - c. CI, the hook and the VS Code tasks are moved to Python too. Remove dead code: `su -c` leftovers, references to removed apps.
   - d. The **build node builds from `restructure`**. Its scripts move and its publish path doesn't. Then the device node deploys with `vedotom deploy` and verifies that the image matches build 10: same inputs, so the same package set and settings.
3. **Environment for app projects.** SDK platform `android-37` for Android 17 next to 36; a machine-wide setup that any project picks up (`ANDROID_HOME`, `adb` on PATH, Studio on the pinned SDK); `Test-Device` covering what an app project needs (install, debug, profile); a small sample project kept out of this repo's build, only as a test fixture if it pays for itself.
4. **Docs rewrite** to the structure above. Every page is checked against the code it describes, `zensical build --strict` passes, and the hook and checks stay green.
5. **Baseline.** Merge to `main`. A final build from `main`, deployed and fully validated, recorded as baseline 1 (git tag `baseline-1`). Delete this file.

## Rules while this runs

- The build node only builds and tests, the device node only deploys and verifies. Builds are requested by message, and every request names a branch and commit.
- `main` keeps building Android 16 until phase 0 merges.
- Nothing private enters the repo or messages (Wi-Fi, keys, identifiers).
- Each deploy wipes the image's userdata. The device is a test target, not a store.
