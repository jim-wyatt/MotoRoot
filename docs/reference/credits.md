# Credits and sources

## The device-preparation procedure

The procedure in [Prepare the device](../device/index.md), the helper programs in `device/helpers/`, the `wifi-ota-guard` and `wifi-carrier-debloat` modules, and the Magisk image preparation script are derived from the **Moto G Power 2026 Straight Talk WiFi and persistent root guide** by **[parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)**, who worked out and tested the procedure on the first unit on 2026-11-14 and published it under the MIT license. This project imported that guide at commit `9526ee08`, carried the procedure out on a second unit, and then restructured the material: the guide's commands and checkpoints became the [walkthrough](../device/walkthrough.md), its tested-device table and validation notes became the [validation page](../device/validation.md), its helpers and modules were documented and given a single manifest-driven builder, and a third module was added.

The original license text, and exactly which parts it covers, are in [`NOTICE.md`](https://github.com/jim-wyatt/VedoTom/blob/main/NOTICE.md). The project as a whole is under the [MIT License](https://github.com/jim-wyatt/VedoTom/blob/main/LICENSE), and its use is subject to the [disclaimer](disclaimer.md).

## Software the procedure uses

None of these is redistributed here; the bootstrap downloads each from its publisher, pinned by hash in `dev/toolchain.json`, and each is under its own license (listed in `NOTICE.md`).

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
| [Frida](https://frida.re/) | Ole André Vadla Ravnås and contributors |
| [Perfetto](https://perfetto.dev/) | Google (ships in Android) |
| [Termux](https://termux.dev/) and `proot-distro` | the Termux project |

## This site

Built with [Zensical](https://zensical.org/), the static-site generator from the Material for MkDocs team. Source in `docs/`, configuration in `zensical.toml`.

## Scope and honesty

This project documents preparing and developing on **one device model you own**, on one validated firmware build, carried out on two units. It does not claim to work on other models or builds, it installs no attempt to hide system access from apps that check for it, and it treats the risk of an unbootable device as real. Everything about what was and wasn't tested is on the [validation page](../device/validation.md); the legal position is in the [disclaimer](disclaimer.md).
