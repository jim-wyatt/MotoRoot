# aosp-academy

[![Checks](https://github.com/jim-wyatt/aosp-academy/actions/workflows/checks.yml/badge.svg?branch=main)](https://github.com/jim-wyatt/aosp-academy/actions/workflows/checks.yml)
[![Documentation](https://github.com/jim-wyatt/aosp-academy/actions/workflows/docs.yml/badge.svg?branch=main)](https://jim-wyatt.github.io/aosp-academy/)
[![Weekly](https://github.com/jim-wyatt/aosp-academy/actions/workflows/weekly.yml/badge.svg)](https://github.com/jim-wyatt/aosp-academy/actions/workflows/weekly.yml)
[![Android 17](https://img.shields.io/badge/image-Android%2017%20(API%2037)-3ddc84)](https://jim-wyatt.github.io/aosp-academy/environment/validation/#current-image)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**One project that bootstraps and maintains a real phone, a Moto G Power 2026 (XT2617V), as an AOSP development device.**

**aosp-academy is an independent, non-commercial, educational project.** It exists to teach how Android works on real hardware. It is not affiliated with Motorola, Lenovo, Google, MediaTek or any carrier, and it redistributes none of their software: everything vendor-made is downloaded by you, from its publisher, under its terms. The full statement is in the [disclaimer](DISCLAIMER.md).

It takes a factory phone and a bare PC to a development environment, and keeps it there: a pinned, self-tested workstation toolchain; the phone unlocked and rooted on its own system; and this project's own system image, `aospacademy_arm64`, built from AOSP source on a Linux build node and booted on the phone through DSU, beside the untouched stock system. Apps are developed in other projects, against the device this one maintains. The docs assume **no prior Android experience**.

**[Read the documentation](https://jim-wyatt.github.io/aosp-academy/)**

> **Before you touch a device, read [DISCLAIMER.md](DISCLAIMER.md).** This project modifies real hardware. It can erase a device, void its warranty, and in the worst case leave it unbootable with no known recovery. Use it only on a device you own outright, at your own risk, and in compliance with the laws and agreements that apply to you.

## Quick start

You need Python 3.11+ and git (on Windows: `winget install Python.Python.3.12 Git.Git`). Everything else is one command, `aosp-academy`, in Python with the standard library only, on Windows, Linux and macOS (`.\aosp-academy` on Windows, `./aosp-academy` elsewhere).

On the workstation, the PC the phone is plugged into:

```text
git clone https://github.com/jim-wyatt/aosp-academy.git
cd aosp-academy
aosp-academy setup --studio --accept-sdk-licenses   # installs and verifies the toolchain (read the SDK terms first)
aosp-academy check                                  # exercises every tool; exit code = failures
aosp-academy shell                                  # a shell with the pinned adb, SDK and NDK on PATH
```

On the build node, any x86-64 Linux host:

```bash
./aosp-academy image setup && ./aosp-academy image inputs && ./aosp-academy image sync
PUBLISH_DIR=/path/to/publish ./aosp-academy image build
```

Then, on the workstation, once the phone is prepared ([walkthrough](https://jim-wyatt.github.io/aosp-academy/device/walkthrough/)):

```text
aosp-academy deploy --host <build node> --user <account> --repo <path> --save   # fetch, install, boot, verify
```

`aosp-academy --help` lists every command; the [command reference](https://jim-wyatt.github.io/aosp-academy/reference/cli/) explains them.

## Repository layout

| Path | What it is |
| --- | --- |
| [`aosp_academy/`](aosp_academy/) | The command line: workstation setup and check, fetch and deploy, DSU, the phone's tools, the stock artifacts, the build node's side. |
| [`toolchain.json`](toolchain.json) | Every pin: SDK, tools, device inputs, APKs, the AOSP release and lunch target. |
| [`image/`](image/) | The `aospacademy_arm64` image: its AOSP product, patches, and the bash wrappers and Containerfile the build node uses. |
| [`stock/`](stock/) | The stock system's preparation: two helper programs and seven reversible Magisk modules, with the manifests and builder that generate them. |
| [`tests/`](tests/) | Unit tests for the command line (no phone, no network). |
| [`docs/`](docs/) | The documentation site ([Zensical](https://zensical.org/)), published to GitHub Pages. The full device procedure lives here. |
| `work/` | Downloads, backups, build outputs and private settings. **Git-ignored in full.** |

## Safety

This project works with real hardware you own. Unlocking a bootloader **erases the device**, and the low-level preparation on this model can, in the worst case, leave it unbootable. The procedure has been carried out on two units of one firmware build; what that does and doesn't establish is in the [validation record](https://jim-wyatt.github.io/aosp-academy/device/#validation-record). Read [how Android works](https://jim-wyatt.github.io/aosp-academy/concepts/) and the [walkthrough](https://jim-wyatt.github.io/aosp-academy/device/walkthrough/) before touching the device.

Device backups, identifiers and network details are private; a [git pre-commit hook](.githooks/pre-commit) and `.gitignore` keep them out of version control automatically.

## License and credits

aosp-academy is released under the [MIT License](LICENSE). The device-preparation procedure, the helper programs and the first two modules are derived from the guide by [parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide) (MIT); the original notice and the exact scope are in [NOTICE.md](NOTICE.md), and full attributions are in the [credits](https://jim-wyatt.github.io/aosp-academy/reference/credits/). The project is not affiliated with Motorola, Lenovo, Google, any carrier or retailer, or the authors of the software it downloads. Working on this repository: [DEVELOPMENT.md](DEVELOPMENT.md).
