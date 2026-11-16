# MotoRoot

**An Android platform-development environment, built around a real device.**

MotoRoot sets up a complete, reproducible Windows toolchain for Android development and turns a **Moto G Power 2026 (XT2617V)** into a full development device — one you can read, instrument, and build on at the system level, the way a platform engineer works with an AOSP engineering build.

It's aimed at people learning Android development from the ground up: the docs assume **no prior Android experience** and explain `adb`, the build pipeline, how a device boots, and the platform's security model as they go.

📖 **[Read the documentation](https://jim-wyatt.github.io/MotoRoot/)**

## Quick start

```powershell
git clone https://github.com/jim-wyatt/MotoRoot.git $env:USERPROFILE\MotoRoot
cd $env:USERPROFILE\MotoRoot
# Download the Motorola USB driver into work\ (see docs: Getting started)
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1 -AndroidStudio -AcceptAndroidSdkLicenses   # installs & verifies the whole toolchain
. .\dev\Enter-DevShell.ps1                                            # in every new terminal
.\dev\Test-DevEnv.ps1                                                 # 35-check self-test
```

One script installs and hash-verifies the full stack: JDK, Android SDK, NDK, platform-tools, Android Studio, jadx, apktool, scrcpy, and the device-preparation inputs. Everything is pinned in [`dev/toolchain.json`](dev/toolchain.json).

## Repository layout

| Folder | What it is |
| --- | --- |
| [`kit/`](kit/) | The tested device-preparation procedure by **[parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)**, included unchanged (MIT). See [`kit/UPSTREAM.md`](kit/UPSTREAM.md). |
| [`dev/`](dev/) | The development environment: bootstrap, per-shell setup, self-test, build scripts. |
| [`docs/`](docs/) | The documentation site ([Zensical](https://zensical.org/)), published to GitHub Pages. |
| `work/` | Your downloads, backups, and build outputs. **Git-ignored in full.** |

## What you can do with it

- **Learn how Android really works** — partitions, A/B slots, the boot chain, the app sandbox, system modules.
- **Prepare a development device** — unlock the bootloader and add managed system-level access (the capability an emulator has by default), fully documented and reversible where possible.
- **Build things** — a program that drives Android's internal system APIs, a Magisk system module, native ARM64 code with the NDK, and a first app in Android Studio.

## Safety

This project works with real hardware you own. Unlocking a bootloader **erases the device**, and the low-level preparation on this model can, in the worst case, leave it unbootable. It was validated on one unit and one firmware build. Read the [internals](https://jim-wyatt.github.io/MotoRoot/concepts/) and the [walkthrough](https://jim-wyatt.github.io/MotoRoot/device/walkthrough/) before touching the device.

Device backups and identifiers are private; a [git pre-commit hook](.githooks/pre-commit) and `.gitignore` keep them out of version control automatically.

## Credits

Device-preparation procedure © parsimo2010 (MIT). Development environment and documentation built around it. Full attributions in the [credits](https://jim-wyatt.github.io/MotoRoot/reference/credits/).
