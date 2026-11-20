# Glossary

Every term the docs use, in plain language.

### This project

**Workstation / device node**
: The PC you work at, with the phone plugged into it. It runs `aosp-academy setup` and `check`, and fetches, deploys and verifies images. It never builds the image. [Set up a workstation](../start/workstation.md).

**Build node**
: Any x86-64 Linux host (native, WSL2, a VM or a container) that syncs AOSP, builds the image and publishes it. [Set up a build node](../start/build-node.md).

**The change loop**
: How every change to the environment is made: edit on a branch, the build node builds, the device node deploys and verifies, merge. [Change the environment](../environment/index.md).

**`aospacademy_arm64`**
: This project's system image: AOSP's `aosp_arm64` with this project's product settings, patches and the Fossify apps on top. Images built before the rename (builds 1 to 10) were called `vedotom_arm64`. [What's in the image](../environment/image.md).

**Pin**
: A download recorded with its exact URL and hash in `toolchain.json`, so it is fetched only from there, used only if it matches, and never silently replaced. [Pins](pins.md).

**Stock system**
: The phone's own Motorola software, as it came from the factory (plus root and this project's modules after preparation). It stays on the phone, untouched, while the image runs beside it. [The stock system](../device/stock.md).

### Tools and the environment

**ADB (Android Debug Bridge)**
: The tool for talking to a device while Android is running: shell, file transfer, app install, logs. [More](../concepts/adb-and-fastboot.md).

**Fastboot**
: The tool for talking to the **bootloader** (the phone in bootloader mode): read variables, flash partitions, unlock. Needs the Motorola driver on Windows.

**fastbootd**
: A second, userspace Fastboot inside Android's recovery, able to flash dynamic partitions the bootloader can't.

**SDK / NDK**
: Software Development Kit (the tools and libraries for Java and Kotlin apps) and Native Development Kit (C and C++ cross-compilers for the device's CPU).

**Platform Tools**
: Google's package containing `adb` and `fastboot`. Pinned here to 37.0.3, the same version the SDK installs, so Android Studio's `adb` and the project's match.

**API level**
: The number that identifies an Android version to apps and tools: Android 17 is API 37. The SDK's `platforms/android-37.0` is what you compile against for it.

**Magisk**
: A superuser manager that provides persistent, managed [root](../concepts/system-access.md) on the stock system by modifying `init_boot`, and supports [modules](../concepts/magisk-modules.md).

**Val Protocol**
: The tool that prepares this model's LK so the standard unlock works. [Credits](credits.md).

**DFRoot / KernelSU**
: The tools that give *temporary* root on the factory kernel, used to bootstrap before unlocking.

**jadx / apktool / aapt2**
: APK inspection tools: DEX to Java, resource and manifest decoding, and quick package facts. [More](../apps/inspecting-apps.md).

**R8 / D8**
: Google's compiler; D8 converts `.class` files to **DEX**. Run as `aosp-academy d8`.

**Frida**
: Dynamic instrumentation: a server on the device (run as root by `aosp-academy device frida start`) lets the PC hook and trace any function in any process. [More](../apps/instrumentation.md).

**Perfetto**
: Android's built-in system tracer (`perfetto`, `traced`): CPU scheduling, memory, framework events and logs on one timeline, viewed at ui.perfetto.dev. Recorded here by `aosp-academy device trace`. [More](../apps/tracing.md).

**scrcpy**
: A program that mirrors the phone's screen on the PC and lets you control it with mouse and keyboard. Run as `aosp-academy device mirror`.

### Building Android

**AOSP (Android Open Source Project)**
: The open-source code of Android itself, published by Google: the framework, system services, system apps and build system. This project builds its image from AOSP release `android-17.0.0_r1`.

**Release tag**
: A named snapshot of the whole AOSP source, such as `android-17.0.0_r1`. Moving the image to a newer one is a project of its own. [More](../environment/tag-moves.md).

**`repo`**
: Google's tool for checking out AOSP, which is hundreds of git repositories (projects) described by one manifest.

**`lunch` / `m`**
: `lunch` picks what to build (product, release configuration, build type: here `aospacademy_arm64-trunk_staging-userdebug`); `m` builds it. Both come from AOSP's `build/envsetup.sh`, which is bash.

**Soong / Blueprint**
: AOSP's build system. Blueprint reads the `Android.bp` files; Soong turns them into build steps for ninja. Its analysis of the whole tree is the build's first memory peak.

**Product**
: The build system's description of one image: which packages, settings and files go in. This project's lives in `image/product/aospacademy/gsi/`.

**Overlay (resource overlay)**
: A package that replaces resource values (a setting, a string, a URL) of another package without changing its code. The image uses overlays on the framework and on NetworkStack.

**GSI (Generic System Image)**
: A system image built to run on any Treble-compliant device, on top of that device's own vendor software. Google publishes GSIs; this project's image is one too.

**Treble / vendor layer**
: The split, since Android 8, between the system (Android itself) and the vendor partitions (the manufacturer's drivers and hardware services, HALs), with a fixed interface between them. It is what lets a system image built from AOSP run on this phone's Motorola vendor software, which is Android 13's.

**HAL (Hardware Abstraction Layer)**
: A vendor service that drives one piece of hardware (camera, fingerprint, vibrator) behind a standard interface the system calls.

**DSU (Dynamic System Updates)**
: Android's way of booting a system image from a file in `/data` instead of a partition. Nothing is flashed, the phone's own system stays intact, and switching back is one command. [More](../device/dsu.md).

**Test keys**
: AOSP's public signing keys, used for any build that isn't an official release. This project's image is signed with them, so it must never be passed off as a release.

### How Android is built on the device

**Partition**
: A fixed named region of storage with one job. [More](../concepts/partitions-and-slots.md).

**A/B slots**
: Two copies of the boot partitions (`_a` and `_b`) for seamless updates. This device runs slot **A**.

**Boot chain**
: BootROM → preloader → LK → kernel → init → Android. Each link verifies the next. [More](../concepts/boot-chain.md).

**LK ("Little Kernel")**
: MediaTek's bootloader (partition `lk_a`): draws Fastboot, enforces the lock, loads the kernel.

**init_boot**
: The ramdisk partition holding `init`, the first userspace process. Where Magisk installs persistent root.

**vbmeta / AVB (Android Verified Boot)**
: Signatures, and the verification by which each boot-chain link checks the next, guaranteeing integrity.

**Bootloader lock**
: Locked: runs only the signed factory build. Unlocked: runs images you provide (needed for a development device). Switching erases the device.

**Build type: `user` / `userdebug` / `eng`**
: What `ro.build.type` reports. Retail devices are `user` builds. `userdebug` is the engineering build Google's own developers use: `adb root` works, and tools such as Perfetto's heap profilers reach apps that aren't marked profileable. This project's image is `userdebug`; on the stock system the `dev_debuggable` module makes it *report* `userdebug`. [System modules](../device/modules.md).

**JDWP**
: The Java debug protocol a debugger uses to attach to an app. ART normally enables it only for apps built debuggable; this project's image enables it for every process. [Debug any process](../apps/debugging.md).

**System image**
: The read-only `system`, `vendor` and `product` partitions holding Android itself. On the stock system they are changed through [modules](../concepts/magisk-modules.md), not edited.

### The runtime and security model

**uid (user id)**
: Every process runs as a numbered Linux user. `shell` is 2000, each app gets its own, `root` is 0. [More](../concepts/system-access.md).

**Root / superuser (uid 0)**
: The privileged user exempt from permission checks. An emulator gives it freely; this device gets it through Magisk on the stock system and through AOSP's own `su` in the image.

**SELinux**
: The kernel's mandatory access control: rules that confine every process, root included, to what its role needs. This project's image keeps it enforcing.

**App sandbox**
: The kernel keeping each app's uid from touching another's files. The foundation of Android security.

**ART**
: The Android Runtime that executes **DEX** bytecode: what runs your app's code.

**DEX**
: Dalvik Executable, the bytecode format ART runs, produced from `.class` files by D8.

**APK**
: An app package: a ZIP of DEX, resources, the manifest, native libraries and signatures. [More](../apps/inspecting-apps.md).

**app_process**
: The launcher that starts the ART runtime; it can run a bare DEX with no APK. How the [system helpers](../device/helpers.md) run.

**JNI**
: Java Native Interface: how Java and Kotlin call native `.so` code.

**system_server**
: The process that hosts most of Android's system services (activities, packages, power, Wi-Fi). Most of what "the framework" does at runtime happens in it.

### Device setup and management

**Provisioning**
: Finishing a device's first-run setup. Here through Android's [enterprise path](../concepts/device-provisioning.md), for a Wi-Fi-only device.

**Test DPC**
: Google's sample Device Policy Controller, used to provision the phone and then removed, leaving an unmanaged device.

**Device owner / admin / role holder**
: Android's device-management roles. The procedure removes all of them, so nothing manages your development device.

**OTA**
: Over-the-air firmware update. Reversibly suppressed on the stock system, to keep a stable, tested baseline.

**Magisk module**
: A ZIP that overlays changes onto the system at boot, reversibly, without editing the real partition.

**First-boot service**
: The image's own one-time setup, run as root after its first boot: home app, development settings, hidden icons, icon colours. `deploy` reads its result. [What's in the image](../environment/image.md).
