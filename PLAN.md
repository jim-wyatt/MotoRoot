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
- **Platform-specific steps stay inside the command**, chosen by OS: winget packages and the Motorola driver's hash check on Windows (installing the driver stays a manual step), a package list to install on Linux. The Android SDK, platform-tools, NDK, JARs and APKs install the same way everywhere, from the pins.
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

0. **Android 17.** **Done 2026-11-20:** build 10 deployed and validated (validation row on `main`). Android 16 was dropped on 2026-11-19, and `main` is the Android 17 line. Build 10 is built from `main` on the build node (the last build with the old `vedotom_arm64` names), deployed by the device node with `aosp-academy deploy` (which still accepts pre-rename images), and checked against build 9, plus fingerprint HIDL 2.1, `adb_keys`, gpuservice without the patch, and the 17 GSI hardware list. The validation rows go on `main`.
1. **Plan** (this file), on branch `restructure`. **Done.**
2. **Code restructure** on `restructure`.
   - a. The layout move. **Done.**
   - b. The `aosp_academy` package. **Done.** Build 10 was the first full install through the deploy, fetch and gsi ports (2026-11-20, unattended, report green, device test 15/15); the PowerShell fallback (`deploy/*.ps1`, `workstation/VedoTom.psm1`) is deleted.
   - c. CI, the hook and the VS Code tasks use the CLI. **Done.** The SDK moved to `android-37.0` and build-tools 37.0.0, and platform-tools moved to 37.0.3 for every host OS.
   - d. The rename to `aospacademy_arm64` in the product, patches and properties. **Done.** Next, the **build node builds from `restructure`**: it removes `device/vedotom` from its tree and reverts the old soong patch first, then runs `image/build/build-image.sh`. The device node then deploys with `aosp-academy deploy` and checks that the image matches build 10, apart from the names.
3. **Environment for app projects.** The SDK platform for Android 17 (`android-37.0`) is the pinned platform. `ANDROID_HOME` and `JAVA_HOME` are set per user by `setup`, so any project and Android Studio pick them up. The SDK's adb is the same version as the project's (37.0.3), so the two servers don't fight. `device test` covers install, launch, debug (JDWP and `adb root`), trace, Frida and mirror. Still open: whether a sample app project pays for itself as a fixture.
4. **Docs rewrite** to the structure above. **In progress**, by section. Every page is checked against the code it describes, `zensical build --strict` passes, and the hook and checks stay green.
5. **Baseline.** Merge `restructure` to `main`. A final build from `main`, deployed and fully validated, is recorded as baseline 1 (git tag `baseline-1`). Then this file is deleted.

## Rules while this runs

- The build node only builds and tests, the device node only deploys and verifies. Builds are requested by message, and every request names a branch and commit.
- `main` takes only image, pin and patch changes until `restructure` merges. The build node keeps to that, and `main` is merged into `restructure` as it moves.
- Nothing private enters the repo or messages (Wi-Fi, keys, identifiers).
- Each deploy wipes the image's userdata. The device is a test target, not a store.
