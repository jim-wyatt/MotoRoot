# Third-party notices

OtomDev is licensed under the [MIT License](LICENSE). It incorporates and builds on the work listed here. Nothing in this file changes those works' licenses; it records them.

## Device-preparation procedure, helpers and modules (parsimo2010, MIT)

The following parts of this repository are derived from the **Moto G Power 2026 Straight Talk WiFi and persistent root guide** by **parsimo2010**, imported from <https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide> at commit `9526ee0805a4c4a76ddb86908ae2c5599f32107c` ("guide kit version 1", 2026-11-14), and since restructured, documented and extended by this project:

- the device-preparation procedure in `docs/device/` (walkthrough, maintenance, validation), which absorbs the original `GUIDE.md`, `README.md` and `VALIDATION.md`;
- the helper programs in `device/helpers/` (`UpdateHelper.java`, `UpdaterCleanup.java`);
- the `wifi-ota-guard` and `wifi-carrier-debloat` modules and the carrier package manifest in `device/modules/`, and the module builder they are generated with;
- `device/scripts/Prepare-MagiskImage.ps1`.

The original author's license follows and continues to apply to those portions:

```text
MIT License

Copyright (c) 2026 parsimo2010

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

This license covers original documentation, helpers, and module packaging.
Referenced third-party projects retain their own licenses. Their firmware,
APKs, and source implementations are not bundled.
```

The `wifi-extra-debloat` module, the development environment in `dev/`, and the rest of the documentation were written for this project.

## Software the procedure downloads (not redistributed)

`dev/Bootstrap-DevEnv.ps1` downloads each of these from its publisher and verifies it against the hash recorded in `dev/toolchain.json`. None of them is included in this repository, none is modified, and none of their authors is affiliated with or endorses this project. Each is governed by its own license and terms; check the linked project for the current text.

| Project | Author / publisher | License (as published by the project) | Used for |
| --- | --- | --- | --- |
| [Magisk](https://github.com/topjohnwu/Magisk) | topjohnwu | GPL-3.0 | Persistent, managed root; system modules |
| [KernelSU](https://github.com/tiann/KernelSU) | tiann | GPL-3.0 | Manager for the temporary-root stage |
| [DFRoot](https://github.com/diabl0w/DFRoot) | diabl0w | See the project | Temporary root on the factory kernel |
| [Val Protocol](https://github.com/Maikyxd/val-protocol) | Maikyxd | See the project | Analysing and patching the device's own LK image |
| [Test DPC](https://github.com/googlesamples/android-testdpc) | Google | Apache-2.0 | Enterprise provisioning QR for first setup |
| [Android Platform Tools](https://developer.android.com/tools/releases/platform-tools), SDK, NDK, command-line tools | Google | Android SDK license terms; component licenses in the SDK's NOTICE files | `adb`, `fastboot`, building for the device |
| [Motorola USB driver](https://en-us.support.motorola.com/app/usb-drivers) | Motorola Mobility | Proprietary; Motorola's terms | Fastboot connectivity on Windows |
| [Frida](https://github.com/frida/frida) (server for the device, `frida-tools` for the PC) | Ole André Vadla Ravnås and contributors | wxWindows Library Licence 3.1 | Hooking and tracing processes on the device |
| [Termux](https://github.com/termux/termux-app) | the Termux project | GPL-3.0 | Terminal and package manager on the device; Debian via `proot-distro` |

## Development toolchain

Installed by the bootstrap through winget or as pinned downloads; also not redistributed.

| Project | Author / publisher | License |
| --- | --- | --- |
| [Microsoft Build of OpenJDK 21](https://learn.microsoft.com/java/openjdk/) | Microsoft | GPL-2.0 with Classpath Exception |
| [R8 / D8](https://r8.googlesource.com/r8) | Google | BSD-3-Clause |
| [jadx](https://github.com/skylot/jadx) | skylot | Apache-2.0 |
| [Apktool](https://apktool.org/) | iBotPeaches, Connor Tumbleson | Apache-2.0 |
| [scrcpy](https://github.com/Genymobile/scrcpy) | Genymobile | Apache-2.0 |
| [7-Zip](https://www.7-zip.org/) | Igor Pavlov | LGPL-2.1 (with unRAR restriction) |
| [Git](https://git-scm.com/), [GitHub CLI](https://cli.github.com/) | Git project, GitHub | GPL-2.0, MIT |
| [Zensical](https://zensical.org/) | Zensical | MIT |

## Trademarks

Motorola, Moto, Lenovo, Google, Android, Verizon, TracFone, Straight Talk, Walmart, MediaTek and other names are trademarks of their respective owners, used here only to identify the products the project works with. Their use does not imply any affiliation with or endorsement by those owners.
