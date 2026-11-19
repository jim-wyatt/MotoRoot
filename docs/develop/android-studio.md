# Your first app in Android Studio

The previous pages ran code the low-level way, to show how Android works underneath. This page uses the normal, polished path most app developers live in: **Android Studio**, the official IDE, which the bootstrap installed. You'll build an app and run it on your prepared device.

!!! info "Two `adb` copies, one version"
    Android Studio uses the `adb` in the SDK's `platform-tools`; the dev shell uses the pinned copy in `work\platform-tools`. Two *different* versions fighting over one device cause dropped connections, which is why the self-test checks that both are the same build (37.0.1 today). Keep them that way: if Studio's SDK Manager offers a platform-tools update, decline it until the pin in `dev/toolchain.json` moves too. Same version, no fight, and you can use either from anywhere.

## Create the project

1. Launch **Android Studio**. On first run it finishes downloading SDK bits; it shares the same `ANDROID_HOME` the bootstrap set up, so it won't re-download the platform.
2. **New Project → Empty Views Activity** (or Empty Compose Activity for modern Kotlin UI).
3. Set a package name (e.g. `com.example.firstapp`), language **Kotlin**, and a minimum SDK of **API 26** or higher. Finish.

Gradle, Android's build system, syncs the project. This takes a minute the first time.

## Run it on the device

Your prepared device is an ordinary debuggable Android device as far as Studio is concerned — unlocking it didn't change that, it just added capability.

1. Make sure USB debugging is on and the device is connected.
2. Pick it from the device dropdown in the toolbar.
3. Click **Run** (▶). Studio builds the APK, installs it, and launches it.

```mermaid
%%{init: {"flowchart": {"wrappingWidth": 300}}}%%
flowchart LR
    SRC["Kotlin/Java + res/"] -->|Gradle| APK["app-debug.apk"]
    APK -->|"adb install"| DEV["your device"]
    DEV --> RUN["app launches, Logcat streams"]
```

That's the whole inner loop of app development: edit, Run, see it on the device. Everything from the earlier pages — DEX, the APK format, the ART runtime — is what Gradle is doing for you automatically now.

## Tools worth opening on day one

- **Logcat** (bottom of the window) — the live system log, filtered to your app. The GUI version of `adb logcat`.
- **Layout Inspector** — see your UI's view hierarchy on the running device.
- **Profilers** — CPU, memory, energy, in real time. This is where a prepared device with system access pays off: you can profile against real hardware, not a simulated emulator.
- **Device Explorer** — browse the device's filesystem from the IDE.

## How this connects to the rest of the project

| The low-level way (earlier pages) | The Android Studio way |
| --- | --- |
| `javac` + `r8d8` by hand | Gradle compiles and dexes for you |
| `app_process` with a bare DEX | ART runs your APK as a sandboxed app |
| `adb install` on the command line | Studio installs on **Run** |
| `adb logcat` in the terminal | the Logcat panel |
| NDK clang by hand | Gradle + CMake build your `.so` |

Neither way is more "real" — they're the same machinery at different altitudes. Knowing the low-level path makes you better at the high-level one, because when Gradle or the runtime does something surprising, you know what's underneath.

## Moving your projects to Android Studio

This repository is the bootstrap, the reference and the documentation; your own apps belong in their own Studio projects. What the prepared device gives Studio that a retail phone wouldn't:

| In Studio | Because |
| --- | --- |
| The device appears without a cable (`192.168.x.y:5555` in the device dropdown) | `adbwifi` from the dev shell, with the `dev_adb_tcp` module ([engineering device](../device/dev-setup.md)) |
| The profilers' heap dumps, and Perfetto heap profiling, work on apps that aren't yours | the `dev_debuggable` module makes the device report a userdebug build ([engineering device](../device/dev-setup.md)); on stock, attaching the *debugger* still needs a debuggable app |
| **Run → Attach Debugger to Android Process** lists every process, `system_server` and SystemUI included, so you can step through framework and app code you didn't write | this project's [own image](aosp-build.md#living-with-the-image) is a real userdebug build with `persist.debug.dalvik.vm.jdwp.enabled=1` (build 9 on). `adb root` works there too. `.\dev\Test-Device.ps1` reports how many processes accept a debugger |
| The CPU profiler's system trace is the same data as [Perfetto](tracing.md) | Studio drives `perfetto` on the device |
| A `Terminal` tool window with `adb`, `frida`, `r8d8` on PATH | start Studio from a dev shell, or dot-source `Enter-DevShell.ps1` in Studio's terminal |

Project settings that fit this device: `compileSdk` and `targetSdk` 36 (its Android 16), `minSdk` whatever your app needs, ABI `arm64-v8a` for anything native. The [hardware inventory](../device/hardware.md) has the screen, CPU and GPU details for performance work.

## Where to go next

- Build something that talks to the system APIs you reached in [Write a system helper](helper-programs.md) — now from a proper app, where permitted.
- Add a native library with the NDK ([native code](native-code.md)) via Gradle's `externalNativeBuild`.
- Read Google's [Android developer guides](https://developer.android.com/guide) for the app framework itself: activities, services, Jetpack, Compose.

You now have the full span: from a 15-line DEX run as root, up to a Gradle-built app in the IDE, all on a device you prepared yourself.
