# OtomDev

**An Android platform-development environment, built around a real device.**

OtomDev sets up a complete, reproducible Windows toolchain for Android development and turns a **Moto G Power 2026 (XT2617V)** into a full development device — one you can read, instrument, and build on at the system level, the way a platform engineer works with an AOSP engineering build.

It's aimed at people learning Android development from the ground up: the docs assume **no prior Android experience** and explain `adb`, the build pipeline, how a device boots, and the platform's security model as they go.

📖 **[Read the documentation](https://jim-wyatt.github.io/OtomDev/)**

> **Before you touch a device, read [DISCLAIMER.md](DISCLAIMER.md).** This project modifies real hardware. It can erase a device, void its warranty, and in the worst case leave it unbootable with no known recovery. Use it only on a device you own outright, at your own risk, and in compliance with the laws and agreements that apply to you.

## Quick start

```powershell
git clone https://github.com/jim-wyatt/OtomDev.git $env:USERPROFILE\OtomDev
cd $env:USERPROFILE\OtomDev
# Download the Motorola USB driver into work\ (see docs: Getting started)
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1 -AndroidStudio -AcceptAndroidSdkLicenses   # installs & verifies the whole toolchain
. .\dev\Enter-DevShell.ps1                                            # in every new terminal
.\dev\Test-DevEnv.ps1                                                 # self-test: exercises every tool, exit code = failures
```

One script installs and hash-verifies the full stack: JDK, Android SDK, NDK, platform-tools, Android Studio, jadx, apktool, scrcpy, and the device-preparation inputs. Everything is pinned in [`dev/toolchain.json`](dev/toolchain.json).

## Repository layout

| Folder | What it is |
| --- | --- |
| [`device/`](device/) | What goes to the device: two helper programs, three reversible Magisk modules with the manifests and builder that generate them, and the Magisk image preparation script. |
| [`dev/`](dev/) | The PC side: bootstrap, per-shell setup, self-test, and the artifact rebuild. |
| [`docs/`](docs/) | The documentation site ([Zensical](https://zensical.org/)), published to GitHub Pages. The full device procedure lives here. |
| `work/` | Your downloads, backups, and build outputs. **Git-ignored in full.** |

## What you can do with it

- **Learn how Android really works** — partitions, A/B slots, the boot chain, the app sandbox, system modules.
- **Prepare a development device** — unlock the bootloader and add managed system-level access (the capability an emulator has by default), fully documented and reversible where possible.
- **Build things** — a program that drives Android's internal system APIs, a Magisk system module, native ARM64 code with the NDK, and a first app in Android Studio.

## Safety

This project works with real hardware you own. Unlocking a bootloader **erases the device**, and the low-level preparation on this model can, in the worst case, leave it unbootable. The procedure has been carried out on two units of one firmware build; what that does and doesn't establish is on the [validation page](https://jim-wyatt.github.io/OtomDev/device/validation/). Read the [internals](https://jim-wyatt.github.io/OtomDev/concepts/) and the [walkthrough](https://jim-wyatt.github.io/OtomDev/device/walkthrough/) before touching the device.

Device backups and identifiers are private; a [git pre-commit hook](.githooks/pre-commit) and `.gitignore` keep them out of version control automatically.

## License and credits

OtomDev is released under the [MIT License](LICENSE). The device-preparation procedure, the helper programs and the first two modules are derived from the guide by [parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide) (MIT); the original notice and the exact scope are in [NOTICE.md](NOTICE.md), and full attributions are in the [credits](https://jim-wyatt.github.io/OtomDev/reference/credits/). The project is not affiliated with Motorola, Lenovo, Google, any carrier or retailer, or the authors of the software it downloads.
