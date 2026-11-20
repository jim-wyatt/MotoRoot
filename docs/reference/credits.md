# Credits and sources

## The device-preparation procedure

The procedure in [the device](../device/index.md), the helper programs in `stock/helpers/`, the `wifi-ota-guard` and `wifi-carrier-debloat` modules, and the Magisk image preparation (now `aosp-academy stock magisk-image`) are derived from the **Moto G Power 2026 Straight Talk WiFi and persistent root guide** by **[parsimo2010](https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide)**, who worked out and tested the procedure on the first unit on 2026-11-14 and published it under the MIT license. This project imported that guide at commit `9526ee08`, carried the procedure out on a second unit, and then restructured the material: the guide's commands and checkpoints became the [walkthrough](../device/walkthrough.md), its tested-device table and validation notes became the [validation record](../device/index.md#validation-record), its helpers and modules were documented and given a single manifest-driven builder, and further modules were added. The project was called VedoTom until 2026-11-19.

The original license text, and exactly which parts it covers, are in [`NOTICE.md`](https://github.com/jim-wyatt/aosp-academy/blob/main/NOTICE.md). The project as a whole is under the [MIT License](https://github.com/jim-wyatt/aosp-academy/blob/main/LICENSE), and its use is subject to the [disclaimer](disclaimer.md).

## Software the procedure uses

None of these is redistributed here; `aosp-academy setup` downloads each from its publisher, pinned by hash in `toolchain.json`, and each is under its own license (listed in `NOTICE.md`).

| Tool | By | Role |
| --- | --- | --- |
| [Test DPC](https://github.com/googlesamples/android-testdpc) | Google | Sample Device Policy Controller, for [provisioning](../concepts/device-provisioning.md) |
| [DFRoot](https://github.com/diabl0w/DFRoot) | diabl0w | Temporary root on the factory kernel |
| [KernelSU](https://github.com/tiann/KernelSU) | tiann | Manager for the temporary-root stage |
| [Val Protocol](https://github.com/Maikyxd/val-protocol) | Maikyxd | Prepares LK so the standard unlock works |
| [Magisk](https://github.com/topjohnwu/Magisk) | topjohnwu | Persistent, managed [root](../concepts/system-access.md) and [modules](../concepts/magisk-modules.md) on the stock system |

## The image

The image is built on the build node from source and inputs fetched there; none of it is in this repository, and the built image isn't published.

| Project | By | Role |
| --- | --- | --- |
| [Android Open Source Project](https://source.android.com/) | Google and the AOSP contributors | The source the image is built from (`android-17.0.0_r1`), under Apache-2.0 |
| [Generic System Images](https://developer.android.com/topic/generic-system-image/releases) | Google | The pinned GSI, booted first to test a release on this device before building it |
| [Fossify](https://github.com/FossifyOrg) | Fossify | The 16 apps built into the image (GPL-3.0), the maintained successor of Simple Mobile Tools |
| [F-Droid](https://f-droid.org/) | F-Droid | Distributes the Fossify APKs and their signed index; the F-Droid client is pinned for the stock system |
| [GrapheneOS](https://grapheneos.org/) | GrapheneOS | The public captive-portal endpoints the image's network checks use |
| [NTP Pool Project](https://www.ntppool.org/) | NTP Pool volunteers | `pool.ntp.org`, the image's time source |
| [Motorola kernel modules](https://github.com/MotorolaMobilityLLC/motorola-kernel-modules) | Motorola Mobility | The published source of `qpnp_adaptive_charge`, which explained the charge limit's behaviour |

## Development toolchain

| Tool | By |
| --- | --- |
| [Python](https://www.python.org/) | Python Software Foundation (the `aosp-academy` command) |
| [Platform Tools, SDK, NDK, Android Studio](https://developer.android.com) | Google |
| [OpenJDK](https://learn.microsoft.com/java/openjdk/) | Microsoft build |
| [R8 / D8](https://r8.googlesource.com/r8) | Google |
| [jadx](https://github.com/skylot/jadx) | skylot |
| [apktool](https://apktool.org/) | iBotPeaches, Connor Tumbleson |
| [scrcpy](https://github.com/Genymobile/scrcpy) | Genymobile |
| [7-Zip](https://www.7-zip.org/) | Igor Pavlov |
| [Git](https://git-scm.com/), [GitHub CLI](https://cli.github.com/) | Git project, GitHub |
| [Motorola USB driver](https://en-us.support.motorola.com/app/usb-drivers) | Motorola Mobility |
| [Frida](https://frida.re/) | Ole André Vadla Ravnås and contributors |
| [Perfetto](https://perfetto.dev/) | Google (ships in Android) |

## This site

Built with [Zensical](https://zensical.org/), the static-site generator from the Material for MkDocs team. Source in `docs/`, configuration in `zensical.toml`.

## Scope and honesty

This project documents preparing and developing on **one device model you own**, on one validated firmware build, carried out on two units. It does not claim to work on other models or builds, it installs no attempt to hide system access from apps that check for it, and it treats the risk of an unbootable device as real. Everything about what was and wasn't tested is in the [validation record](../environment/validation.md); the legal position is in the [disclaimer](disclaimer.md).
