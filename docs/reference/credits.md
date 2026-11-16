# Credits and sources

## The device-preparation procedure

The entire procedure in `kit/` — the guide, the helper programs, the system modules, the preparation scripts — was created and tested by **[parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)**. It is included unchanged under its MIT license. See [`kit/UPSTREAM.md`](https://github.com/jim-wyatt/OtomDev/blob/main/kit/UPSTREAM.md) for the exact imported commit and how to pull updates.

These documentation pages and the `dev/` environment were built around that procedure to frame it as an Android development project. They are not the work of the upstream author.

## Upstream tools

The procedure uses these third-party projects. None are redistributed in this repo; the bootstrap downloads each from its publisher, pinned by hash in `dev/toolchain.json`. Each is under its own license.

| Tool | By | Role |
| --- | --- | --- |
| [Test DPC](https://github.com/googlesamples/android-testdpc) | Google | Sample Device Policy Controller, for [provisioning](../concepts/device-provisioning.md) |
| [DFRoot](https://github.com/diabl0w/DFRoot) | diabl0w | Temporary root on the factory kernel |
| [KernelSU](https://github.com/tiann/KernelSU) | tiann | Manager for the temporary-root stage |
| [Val Protocol](https://github.com/Maikyxd/val-protocol) | Maikyxd | Prepares LK so the standard unlock works |
| [Magisk](https://github.com/topjohnwu/Magisk) | topjohnwu | Persistent, managed [root](../concepts/system-access.md) and [modules](../concepts/magisk-modules.md) |

## Development toolchain

| Tool | By |
| --- | --- |
| [Platform Tools, SDK, NDK, Android Studio](https://developer.android.com) | Google |
| [OpenJDK](https://learn.microsoft.com/java/openjdk/) | Microsoft build |
| [R8 / D8](https://r8.googlesource.com/r8) | Google |
| [jadx](https://github.com/skylot/jadx) | skylot |
| [apktool](https://apktool.org/) | iBotPeaches, Connor Tumbleson |
| [scrcpy](https://github.com/Genymobile/scrcpy) | Genymobile |
| [7-Zip](https://www.7-zip.org/) | Igor Pavlov |
| [Motorola USB driver](https://en-us.support.motorola.com/app/usb-drivers) | Motorola Mobility |

## This site

Built with [Zensical](https://zensical.org/), the static-site generator from the Material for MkDocs team. Source in `docs/`, configuration in `zensical.toml`.

## Scope and honesty

This project documents preparing and developing on **one device model you own**, on one validated firmware build. It does not claim to work on other models or builds, it installs no attempt to hide system access from apps that check for it, and it treats the risk of an unbootable device as real. Everything about what was and wasn't tested is in [`kit/VALIDATION.md`](https://github.com/jim-wyatt/OtomDev/blob/main/kit/VALIDATION.md).
