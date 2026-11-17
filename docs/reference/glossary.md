# Glossary

Every term the docs use, in plain language.

### Tools and the environment

**ADB (Android Debug Bridge)**
: The tool for talking to a device while Android is running: shell, file transfer, app install, logs. [More](../concepts/adb-and-fastboot.md).

**Fastboot**
: The tool for talking to the **bootloader** (device in bootloader mode): read variables, flash partitions, unlock. Needs the Motorola driver on Windows.

**fastbootd**
: A second, userspace Fastboot inside Android's recovery, able to flash dynamic partitions the bootloader can't.

**SDK / NDK**
: Software Development Kit (Java/Kotlin app tools and libraries) and Native Development Kit (C/C++ cross-compilers for the device's CPU).

**Platform Tools**
: Google's package containing `adb` and `fastboot`. Pinned here to 37.0.1.

**Magisk**
: A superuser manager that provides persistent, managed [root](../concepts/system-access.md) by modifying `init_boot`, and supports [modules](../concepts/magisk-modules.md).

**Val Protocol**
: The tool that prepares this model's LK so the standard unlock works. [Credits](credits.md).

**DFRoot / KernelSU**
: The tools that give *temporary* root on the factory kernel, used to bootstrap before unlocking.

**jadx / apktool / aapt2**
: APK inspection tools: DEX→Java, resource/manifest decode, and quick package facts. [More](../develop/inspecting-apps.md).

**R8 / D8**
: Google's compiler; D8 converts `.class` → **DEX**. Exposed as `r8d8` in the dev shell.

**Frida**
: Dynamic instrumentation: a server on the device (run as root by `Start-Frida`) lets the PC hook and trace any function in any process. [More](../develop/instrumentation.md).

**Perfetto**
: Android's built-in system tracer (`perfetto`, `traced`): CPU scheduling, memory, framework events and logs on one timeline, viewed at ui.perfetto.dev. Recorded here by `Trace-Device.ps1`. [More](../develop/tracing.md).

### How Android is built

**Partition**
: A fixed named region of storage with one job. [More](../concepts/partitions-and-slots.md).

**A/B slots**
: Two copies of the boot partitions (`_a`/`_b`) for seamless updates. This device runs slot **A**.

**Boot chain**
: BootROM → preloader → LK → kernel → init → Android. Each link verifies the next. [More](../concepts/boot-chain.md).

**LK ("Little Kernel")**
: MediaTek's bootloader (partition `lk_a`): draws Fastboot, enforces the lock, loads the kernel.

**init_boot**
: The ramdisk partition holding `init`, the first userspace process. Where Magisk installs persistent root.

**vbmeta / AVB (Android Verified Boot)**
: Signatures and the verification that each boot-chain link checks the next, guaranteeing integrity.

**Bootloader lock**
: Locked = runs only the signed factory build. Unlocked = runs images you provide (needed for a dev device). Switching erases the device.

**Build type: `user` / `userdebug` / `eng`**
: What `ro.build.type` reports. Retail devices are `user` builds; Google's engineers use `userdebug`, which tooling such as Perfetto's heap profilers checks before touching apps that aren't profileable. The `dev_debuggable` module makes this device report `userdebug`. [More](../device/dev-setup.md).

**JDWP**
: The Java debug protocol a debugger uses to attach to an app. ART enables it only for apps built debuggable; on this build, reporting a `userdebug` build does not extend that to other apps.

**System image**
: The read-only `system`/`vendor`/`product` partitions holding Android itself. Changed via [modules](../concepts/magisk-modules.md), not edited.

### The runtime and security model

**uid (user id)**
: Every process runs as a numbered Linux user. `shell`=2000, each app gets its own, `root`=0. [More](../concepts/system-access.md).

**Root / superuser (uid 0)**
: The privileged user exempt from permission checks. An emulator gives it freely; a dev device gets it via Magisk.

**App sandbox**
: The kernel keeping each app's uid from touching another's files. The foundation of Android security.

**ART**
: The Android Runtime that executes **DEX** bytecode — what runs your app's code.

**DEX**
: Dalvik Executable — the bytecode format ART runs, produced from `.class` by D8.

**APK**
: An app package: a ZIP of DEX, resources, manifest, native libs, signatures. [More](../develop/inspecting-apps.md).

**app_process**
: The launcher that starts the ART runtime; can run a bare DEX with no APK. How the [helper programs](../develop/helper-programs.md) run.

**JNI**
: Java Native Interface — how Java/Kotlin calls native `.so` code.

### Device setup and management

**Provisioning**
: Finishing a device's first-run setup. Here via Android's [enterprise path](../concepts/device-provisioning.md) for a Wi-Fi-only device.

**Test DPC**
: Google's sample Device Policy Controller, used to provision then removed, leaving an unmanaged device.

**Device owner / admin / role holder**
: Android device-management roles. The procedure removes all of them so nothing manages your dev device.

**OTA**
: Over-the-air firmware update. Reversibly suppressed on this dev device to keep a stable, tested baseline.

**Magisk module**
: A ZIP that overlays changes onto the system at boot, reversibly, without editing the real partition.
