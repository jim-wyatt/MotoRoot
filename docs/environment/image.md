# What's in the image

`aospacademy_arm64` is AOSP's own arm64 Generic System Image (GSI) with a short list of changes on top. This page goes through the list, item by item, and says why each item is there. The product tree `image/product/aospacademy/gsi/` in the repository is the whole description; nothing about the image lives only on the build node.

If you are developing apps and want to know what the image gives you (root, JDWP, logs, defaults), [The image for app developers](../apps/the-image.md) is the shorter version. The decisions behind the bigger choices are in [Decisions](../reference/decisions.md).

## What you can change, and what you can't

The image replaces the phone's **system** side: the framework, the system services, the launcher, Settings, the system apps, the system half of the SELinux policy, and the build type. It is a `userdebug` build, the engineering build type, where `adb root` works and a debugger can attach to any process.

It does not replace the **vendor** side: the kernel, the vendor HALs (hardware abstraction layers: the vendor's drivers for the camera, radio, sensors and so on), the firmware and the modem. They stay Motorola's, behind the Treble interface, the fixed boundary between system and vendor that lets a generic system run on this phone at all (see [Partitions and slots](../concepts/partitions-and-slots.md)). The GSI's hardware gaps, such as two cameras of three, are limits of that interface rather than of this build. A full device port would be a different and much larger project.

The vendor layer on this phone is Android 13's (`ro.vndk.version=33`, VINTF target level 7), under an Android 17 system. That gap is what makes every [tag move](tag-moves.md) start with a test.

## The base: AOSP's arm64 GSI

The image is built from the AOSP release tag pinned in `toolchain.json` (`deviceTools.aosp.tag`), now **`android-17.0.0_r1`** (build `CP2A.260605.016`, security patch 2026-06-05). That is the same Android 17 release as Google's GSI binary `CP2A.260605.012`, pinned as `deviceTools.gsi`, which was booted on this phone first. So the starting point of every build is a system that was already shown to run on this vendor. Builds 1 to 9 came from `android-16.0.0_r4` (`BP4A.251205.006`); Android 16 was dropped on 2026-11-19 ([the move](tag-moves.md#worked-example-android-16-to-17-2026-11-19)).

The lunch target is **`aospacademy_arm64-trunk_staging-userdebug`** (`deviceTools.aosp.lunch`): the product `aospacademy_arm64`, the release configuration `trunk_staging`, the build type `userdebug`. `AndroidProducts.mk` also offers an `-eng` variant.

The image is signed with AOSP's public test keys, not Google's. On this unlocked phone the DSU installer accepts a test-keyed image, because `gsid` does not enforce trusted keys in the `orange` (unlocked) boot state. Never ship or publish a test-keyed image as if it were a release. AOSP is Apache-2.0; Google's GSI terms apply to Google's binary, not to your own build, and nothing from Motorola's vendor partition is part of what is built or distributed. The image is about 1.8 GB.

## The product makefiles

AOSP describes what goes into an image with *product makefiles*: `.mk` files that set variables (`PRODUCT_PACKAGES`, properties, files to copy) and inherit other makefiles. This project has four, in `image/product/aospacademy/gsi/`:

| File | What it is |
| --- | --- |
| `AndroidProducts.mk` | Registers the product and its lunch choices. |
| `aospacademy_arm64.mk` | Upstream's `build/make/target/product/aosp_arm64.mk`, with three changes: the product-partition app set comes from `aospacademy_product.mk` instead of `aosp_product.mk`; the Virtualization (AVF) product packages are not inherited; and the settings `aosp_arm64.mk` keeps behind its `ifeq (aosp_arm64,$(TARGET_PRODUCT))` guard are applied unconditionally (a derived product has a different name, so it must repeat them, as AOSP's own `aosp_arm64_fullmte.mk` does). Below that come this project's own settings, each with a comment. |
| `aospacademy_product.mk` | Upstream's `aosp_product.mk`, kept line for line except for what the Fossify suite replaces: it inherits `aospacademy_handheld_product.mk`, inlines `telephony_product.mk` without Dialer, drops `messaging`, and leaves out PhotoTable. |
| `aospacademy_handheld_product.mk` | Upstream's `handheld_product.mk` without Calendar, Camera2, Contacts, DeskClock, Gallery2, Music, QuickSearchBox and Browser2. LatinIME stays. |

Copies rather than edits, because neither make nor Soong can subtract a package another makefile adds: the only way to leave out an app is to not inherit the file that adds it, and to repeat the rest. The copies are kept line for line with upstream so a diff shows exactly what changed, which is what a [tag move](tag-moves.md) checks.

The **system partition** is otherwise the stock GSI's, from upstream's `generic_system.mk` and the files it inherits, unchanged except for the patches below. One rule follows from that: the GSI forbids adding properties to the system partition (its artifact-path requirement, in `generic_system.mk`), so every property this project sets goes in `PRODUCT_PRODUCT_PROPERTIES`. That lands in the product partition's `build.prop` (under `/system/product/etc/` in a GSI), which init reads just the same, and last, so its values win.

## The Android.bp mirror

Since Android 16, AOSP builds the GSI's `system.img` from a Soong module (`android_system_image`), and a check called **filelistdiff** (`build/make/tools/filelistdiff`) stops the build if that module's dependency list differs from what the product makefiles install. Upstream's module, `aosp_system_image`, and its defaults, `android_gsi_defaults` (both in `build/make/target/product/gsi/Android.bp`), name the AOSP apps the Fossify suite replaces. Soong lists cannot be subtracted from either.

So `image/product/aospacademy/gsi/Android.bp` **mirrors** them: `aospacademy_gsi_defaults` is `android_gsi_defaults` without Browser2, Camera2, Dialer and messaging, and `aospacademy_system_image` is `aosp_system_image` without Calendar, Contacts, DeskClock, Gallery2, Music, QuickSearchBox and PhotoTable, plus this project's modules (the overlays, the Fossify apps, the first-boot service and its init file). `aospacademy_arm64.mk` points the build at it with `PRODUCT_SOONG_DEFINED_SYSTEM_IMAGE := aospacademy_system_image`.

The mirror is the part most likely to drift when the tag moves, and filelistdiff is what tells you: it names every module that is in one list and not the other. On Android 17 it gained seven entries (`preinstalled-packages-gsi-system-ext.xml`, `preinstalled-packages-base-product.xml`, `wificond`, `hwservicemanager`, `android.hidl.allocator@1.0-service`, `preinstalled-packages-platform-telephony-system-ext.xml`, `preinstalled-packages-telephony-system-ext.xml`) and `AvatarPicker` moved group; each is marked in the file. The VNDK APEXes `com.android.vndk.v31` to `v34` stay, and `v33` is the one this vendor needs.

To build its product and system_ext `build.prop` files the same way the GSI does, the mirror needs a Soong module that upstream makes visible only to the GSI's own directory. That is the reason for the `build/soong` patch below.

## The Fossify suite and the roles

The **Fossify** apps (GPL-3.0, the maintained successor of Simple Mobile Tools, built and signed by Fossify and distributed by F-Droid) are the only apps added on top of AOSP. They replace the AOSP apps one for one, and add a few:

| Fossify app | Replaces |
| --- | --- |
| Launcher | Launcher3's home screen (Launcher3QuickStep stays, below) |
| Gallery | Gallery2 |
| Calendar | Calendar |
| Contacts | Contacts |
| Clock | DeskClock |
| Phone | Dialer |
| Messages | messaging |
| Music Player | Music |
| Camera | Camera2 |
| Calculator, File Manager, Documents, Notes, Voice Recorder, Paint, Keyboard | nothing: added (the makefiles remove no other AOSP app for them) |

QuickSearchBox is left out too, because nothing needs it.

Every APK is pinned in `toolchain.json` by SHA-256 and signing certificate, checked against F-Droid's signed index when it was pinned, and downloaded on the build node by `./aosp-academy image inputs`. `apply-local.sh` copies them into the tree from the list in `prebuilt/apks.txt`; no APK is ever committed. `prebuilt/Android.bp` imports each one with `preprocessed: true` and dex pre-optimisation off, so Soong checks the alignment and copies the APK unmodified, with the publisher's signature intact.

Nothing updates the apps on the device: there is no app store in the image, so a new version means a new pin and a new image. There is also **no web browser**, by design: Browser2, AOSP's WebView test shell, stays out, and WebView still renders web content inside apps (it is AOSP's, from the tag, and ages with it). Links to `https://` pages resolve to nothing. The F-Droid client is not in the image either; it stays pinned for the stock system.

Some AOSP apps stay on purpose:

- **Launcher3QuickStep**: SystemUI binds its quickstep service for gesture navigation and recents. Fossify Launcher is made the home screen by the first-boot service assigning it the HOME role. Both answer HOME with equal priority, so Android would otherwise show a chooser, and a `preferred-apps` file was tried first and was not reliably honoured.
- **LatinIME** beside Fossify Keyboard: a working keyboard must never depend on a prebuilt.
- **DocumentsUI**: the system file picker behind every open, get-content and save dialog, Fossify's included. Only its launcher icon is hidden.
- **Settings**, and everything delivered as a Mainline module.

The **DIALER** and **SMS** roles go to Fossify Phone and Fossify Messages through the framework overlay (below); the **HOME** role, through the first-boot service.

## Removed: PhotoTable and AVF

- **PhotoTable** (a photo screensaver) is left out of the product makefiles and the mirror, which this project already maintains.
- **The Virtualization (AVF) product packages** are not inherited (`packages/modules/Virtualization/apex/product_packages.mk`), and `com.android.compos` is out of the image's dependencies. This SoC has no pKVM, the hypervisor AVF needs (no `/dev/kvm`, no `ro.boot.hypervisor.*`), so CompOS, the virtualization feature file and the AVF properties would be dead weight. `com.android.virt` itself stays, because `base_system.mk` installs it and its `framework-virtualization` jar is on the classpath; without `PRODUCT_AVF_ENABLED` it builds its variant for devices without AVF.

The other unused system apps (BasicDreams, `com.android.egg`, Bips, PrintSpooler, HtmlViewer, BookmarkProvider, CallLogBackup, WallpaperBackup) stay. They live on the system partition, and removing them would mean mirroring about 600 lines of upstream system-image definitions and re-checking them on every tag move, which costs more than the space is worth ([Decisions](../reference/decisions.md)).

## The overlays

An **overlay** (a runtime resource overlay, RRO) is a small package with no code that replaces resource values of another package at runtime, so a default can change without patching the package itself. The image has two, both static (enabled at boot, not switchable in Settings) and both on the product partition at priority 201.

**`AospAcademyFrameworkOverlay`** (`overlay/`) targets the framework (package `android`):

| Resource | Value | Effect |
| --- | --- | --- |
| `config_defaultNightMode` | `2` | Dark theme by default. |
| `config_navBarInteractionMode` | `2` | Gesture navigation by default. |
| `config_defaultDialer` | `org.fossify.phone` | Fossify Phone holds the DIALER role. |
| `config_defaultSms` | `org.fossify.messages` | Fossify Messages holds the SMS role. |
| `config_ntpServers` | `ntp://pool.ntp.org` | Network time from the NTP Pool Project instead of `time.android.com`. |
| `default_wallpaper` (drawable) | the project's wallpaper | Material You derives the system colours from it. |

**`AospAcademyNetworkStackOverlay`** (`overlay/networkstack/`) targets the `NetworkStackConfig` overlayable of `com.android.networkstack`. It sends the **captive-portal probes** (the HTTP requests Android makes to decide whether a network really reaches the internet) to GrapheneOS's public endpoints, which answer the same `204` as Google's for any client:

| Resource | Value |
| --- | --- |
| `config_captive_portal_http_url` and `config_captive_portal_http_urls` | `http://connectivitycheck.grapheneos.network/generate_204` |
| `config_captive_portal_https_url` and `config_captive_portal_https_urls` | `https://connectivitycheck.grapheneos.network/generate_204` |
| `config_captive_portal_fallback_urls` | `http://grapheneos.online/gen_204` |

Both the single URLs and the arrays are set because NetworkMonitor reads the arrays first, and the phone's vendor overlay (`NetworkStackResOverlay`, priority 7) fills them with Google's hosts. Build 6 set only the single URLs and still probed Google; build 7 set the arrays too and was the first to probe only GrapheneOS. The reason for leaving Google's endpoints is the project's policy of avoiding Google services in the image as far as practical ([Decisions](../reference/decisions.md)).

## Properties the image sets

All in `PRODUCT_PRODUCT_PROPERTIES` in `aospacademy_arm64.mk`:

| Property | Value | Why |
| --- | --- | --- |
| `debug.sf.nobootanimation` | `1` | No boot animation: SurfaceFlinger never starts the `bootanim` service, and the screen stays on the bootloader's splash until the lock screen. The makefile shows the one-line alternative for shipping your own `bootanimation.zip`. |
| `persist.sys.timezone` | `America/New_York` | Without a SIM, the telephony time-zone suggestion isn't applied (the US has several offsets), and AOSP without Google's services has no location time-zone provider, so the phone would otherwise start in GMT. A zone chosen later in Settings is stored in `/data` and wins. Change the default here for another region. |
| `persist.aospacademy.charge_limit` | `80` | The charge limit, below. |
| `persist.debug.dalvik.vm.jdwp.enabled` | `1` | JDWP for every app, below. |
| `ro.adb.secure` | `1` | adb authorisation on, below. |

## ADB authorisation and the trusted keys

**`ro.adb.secure=1`** turns adb authorisation on, as on a user build: a PC must be allowed on the phone's screen ("Allow USB debugging?") before adb works. Without it, any USB host would get a root-capable shell on this userdebug image. The GSI's system_ext `build.prop` sets `ro.adb.secure=0` (`build/make/target/board/gsi_system_ext.prop`); init loads the product partition's `build.prop` last, so the product value wins. That was checked on build 6.

Every DSU install starts with empty userdata and so with no `/data/misc/adb/adb_keys`: without help, each deploy would need a tap. The help is **`PRODUCT_ADB_KEYS`**. On the build node, a git-ignored file **`work/adb_keys`** holds the public keys of this project's own PCs, one `adbkey.pub` line each (`QAAAA... user@host`; never the private `adbkey`). `apply-local.sh` checks its format and copies it to `device/aospacademy/gsi/adb_keys` in the tree, and the makefile sets `PRODUCT_ADB_KEYS := $(wildcard device/aospacademy/gsi/adb_keys)`. The keys are installed at `/product/etc/security/adb_keys` (which `/adb_keys` links to), and adbd trusts that list alongside `/data/misc/adb/adb_keys`, so those PCs need no tap after a deploy. AOSP keeps the file for userdebug builds (the release flag `RELEASE_BUILD_PURGE_PRODUCT_ADB_KEYS` is false there).

Without `work/adb_keys` the image trusts no PC in advance, as before build 8. No key is ever in the repository, which is public. An image built with keys is specific to those machines: don't pass it on.

## JDWP for every app

`persist.debug.dalvik.vm.jdwp.enabled=1` makes every app process open JDWP (the Java Debug Wire Protocol), so Android Studio's *Attach debugger to Android process* and `adb jdwp` reach any process, `system_server` and SystemUI included, without a debuggable APK. Zygote reads the property once at start, and only on a userdebug build; a user build ignores it. It is a `persist.*` default, so setting it to `0` on the phone and rebooting turns it off. It gives no access beyond what `adb root` already gives an authorised PC. On build 9, the first with it, `adb jdwp` listed 24 processes at idle (build 8: none). [Debugging](../apps/debugging.md) shows how to use it.

## The first-boot service

Some things can't be set from a read-only partition: a role holder, a global setting, an app's icon colour. The **first-boot service** sets them on the phone. It is `aospacademy-firstboot`, a shell script (`firstboot/aospacademy-firstboot.sh`, built as an `sh_binary` into `/product/bin/`), which `init.aospacademy.rc` starts once `sys.boot_completed` is set, as root, in the `su` SELinux domain (`seclabel u:r:su:s0`), which exists only on userdebug builds.

It runs on every boot, but each step checks a marker file in its **state directory, `/data/local/aospacademy-firstboot/`**, before it acts. So each step happens once, later boots cost about a second, and a choice you make later (another launcher, another icon colour) is kept. A step that fails is logged and retried on the next boot.

1. **HOME role.** If Fossify Launcher is installed, `cmd role add-role-holder android.app.role.HOME org.fossify.home 0`, so it is the home screen without a chooser. Marker: `home-role`.
2. **Development settings.** The same values `aosp-academy device settings` applies on the stock system: `development_settings_enabled` 1 (Developer options shown), `stay_on_while_plugged_in` 15 (Stay awake while charging), `window_animation_scale`, `transition_animation_scale` and `animator_duration_scale` 0 (UI tests expect it, and screens settle at once), `verifier_verify_adb_installs` 0 (no verification scan of adb installs), and `adb_allowed_connection_time` 0 (an authorised PC's key never expires). Each is read back after it is set. SettingsProvider has resource defaults for only some of the seven in this tag, so all seven are set here, in one place. Marker: `dev-settings`.
3. **Hidden icons.** Two AOSP launcher entries are disabled with `pm disable`, because their apps stay for what they do in the background and a Fossify app is the one to open: **Files** (`com.android.documentsui/.LauncherActivity`; DocumentsUI's picker stays) and **Keyboard** (`com.android.inputmethod.latin/.setup.SetupActivity`; LatinIME stays as the fallback, and its settings remain under Settings, System, Keyboard). Neither entry is gated on a resource in this tag, so an overlay can't do it. `pm enable` on the same component brings an icon back. Markers: `files-icon`, `keyboard-icon`.
4. **Teal icons.** Every `org.fossify.*` app gets the teal launcher icon, to match the wallpaper. Inside the apps Fossify already follows the system's Material You colours; the icon colour is a separate per-app choice, stored as one enabled activity alias (`SplashActivity.Teal`, with `.Green` disabled) plus two preferences the app reconciles on every start (`app_icon_color` and `last_icon_color` in `shared_prefs/Prefs.xml`). The service sets all three, as the app's own Customize screen does. Markers: `<package>.icon`.

If anything changed in steps 3 and 4, it force-stops Fossify Launcher so the icons refresh.

It reports where the log buffers can't lose it, because the first boot's log lines can roll out of logcat within minutes:

| File in `/data/local/aospacademy-firstboot/` | Content |
| --- | --- |
| `status` | `running` while it works, then `done failures=<n>`. |
| `log` | Every line it logs, with a date and time. The same lines go to logcat under the tag `aospacademy-firstboot`. |
| `charge-limit` | The charge-limit result (below). |

`aosp-academy deploy` reads all three as root (`su 0 cat ...`).

## The log size rule

logd's default buffer is 256 KiB per log, which this phone's vendor log noise (see the [backlog](backlog.md#vendor-noise)) rolls over within minutes. The image makes every buffer **16 MiB** on every boot.

A property can't do it: logd in this tag reads `ro.logd.size` and `persist.logd.size` at start only on automotive and desktop hardware types (`system/logging/logd/LogSize.cpp`). So `init.aospacademy.rc` has a service, `aospacademy_logsize`, that runs `logcat -b main,system,crash,events,radio,kernel -G 16M` as root, started when logd sets `logd.ready=true`. logd clears that property when it restarts, so the rule also re-applies the size after a logd restart. `adb logcat -g` shows the size.

## The charge limit

The phone lives on its charger, so the image caps the charge at **80 %**, as the stock system does with Motorola's Battery protection on.

**How stock does it.** Moto Actions passes the limit through a Motorola service in `system_server` to the vendor health HAL (`motorola.hardware.health-service`), which writes it to a parameter of the vendor kernel module `qpnp_adaptive_charge`: `upper_limit` 80, with `lower_limit` -1, meaning auto mode. Stock's `dumpsys battery` shows `AdaptiveCharging ... mUpperLimit:80, mLowerLimit:-1`. The image has the module and the HAL, but not Motorola's client.

**How the image does it.** `init.aospacademy.rc` starts the service `aospacademy_chargelimit` (the first-boot script with the argument `charge-limit`) after boot and whenever **`persist.aospacademy.charge_limit`** changes. The default is 80 from the product `build.prop`; values from 50 to 100 are accepted, and anything else is logged and left unchanged. The service:

1. removes the previous result file (it lives in `/data` and outlasts reboots, so a deploy must not read the last boot's result as this one's);
2. writes the value to `/sys/module/qpnp_adaptive_charge/parameters/upper_limit`, the same single write the HAL makes on stock;
3. waits 30 s, because the module re-evaluates on its next battery update;
4. reads the property again, and applies it in turn if it changed during the wait (init's `start` does nothing for a oneshot service that is still running, so a second `setprop` within 30 s would otherwise be lost);
5. records `upper_limit=<n>, blocking=<0|1> (1 = holding charge off)` in `charge-limit` and the log.

To set another limit: `adb shell su 0 setprop persist.aospacademy.charge_limit 85`. The value is stored in `/data` and wins over the default until the next deploy.

**How the module decides.** From Motorola's source for the module (`drivers/power/qpnp_adaptive_charge/qpnp_adaptive_charge.c` in [motorola-kernel-modules](https://github.com/MotorolaMobilityLLC/motorola-kernel-modules)), confirmed on the device on 2026-11-19. It re-checks the level whenever the battery reports a change and whenever the limit is written. With L the limit:

| Battery level | What the module does |
| --- | --- |
| above L+1 | Suspends charging and holds the charge current at 0; the phone runs from the battery (status "Not charging"). |
| exactly L+1 | Lets the charger power the phone, but still holds the battery current at 0. |
| exactly L | Changes nothing: this is the hysteresis. |
| below L | Charges. |

So the level settles between L-1 and L+2, and with the limit at 80 the phone sits at about 84 % after charging past it (builds 8 and 9: holding at 86 %).

**100 means charge to full,** with one edge. If charging is already held off and the level is exactly 100 %, it stays held off until the level falls to 99, because at the limit the module keeps its state. From any lower level, 100 resumes charging at once: tested at 84 %, the status was "Charging" within 5 s and `blocking` went from 1 to 0, and back to 1 within seconds of setting 80 again. The module's own off value, `upper_limit` -1, would clear a hold even at 100 %, but the service accepts only 50 to 100 and never writes it: the decision (2026-11-19) is to keep the limit at 80 and make no new kind of write.

!!! danger "Never read the limits back, and never bulk-read module parameters"
    The service **writes** `upper_limit` and never reads it or `lower_limit` back. It checks the result through **`blocking`** only, a read-only parameter with its own getter that reads 1 while the module holds charging off. Do the same by hand.

    **Never read `/sys/module/*/parameters/*` in bulk on this phone.** Reading sysfs runs driver code, and one of the vendor charger modules has a broken int parameter. On 2026-11-17 a loop that read the parameters of the charger-related modules (`bq25980_mmi`, `mt6375_battery`, `mtk_charger_*`, `qpnp_adaptive_charge` and others) hit a NULL dereference in `param_get_int` and panicked the kernel (boot reason `kernel_panic,null`). The bug is in the stock kernel too, so it isn't the image's doing. The phone came back on its own. Read one named node at a time, only one you already know is safe, and look for nodes in static sources first (the vendor's init `.rc` files, `strings` on its binaries).

## The patches

`image/patches/` holds unified diffs against upstream AOSP projects, one project per file, applied by `apply-local.sh` ([Build the image](building.md#patches) explains the mechanics and the naming). There are three:

| Patch | Project | Why |
| --- | --- | --- |
| `build-soong-0001-build-prop-visibility-for-device-aospacademy.patch` | `build/soong` | Adds `//device/aospacademy/gsi` to the visibility lists of the `system_ext-build.prop` and `product-build.prop` modules, which upstream makes visible only to the GSI's own directory. The [Android.bp mirror](#the-androidbp-mirror) builds those `build.prop` files the same way the GSI does, so it needs them. |
| `build-blueprint-0001-soong-heap-limit-80-percent-of-ram.patch` | `build/blueprint` | Sets the Go runtime's soft memory limit (`debug.SetMemoryLimit`) for `soong_build` to 80 % of the machine's RAM, read from `/proc/meminfo`, so its garbage collector runs before the heap leaves RAM. On Android 17 the analysis otherwise swapped for more than 50 minutes without finishing on a 32 GB builder. It is the only patch that changes the build system rather than the image. [Build the image](building.md#memory) has the measurements. |
| `frameworks-base-0001-vibrator-no-unknown-amplitude-to-hal.patch` | `frameworks/base` | Stops `Error setting amplitude to -1.0` failures. The framework records amplitude -1, meaning "unknown", when the vibrator turns on, and `SetAmplitudeVibratorStep.turnVibratorBackOn` can pass that value back to `setAmplitude`. This phone's HAL (`android.hardware.vibrator-service.mediatek`, capability `AMPLITUDE_CONTROL` only) rejects -1 with `IllegalArgumentException`. The patch makes `VintfHalVibrator.setAmplitude` skip negative values, so the vibrator keeps its current strength. Android 17 still has the bug: Google's 17 GSI logged 11 of these errors. |

A fourth patch, against `frameworks/native`, fixed a **`gpuservice` crash loop** on Android 16: `gpuservice` aborted every 30 s in `GpuWork::initialize()`, because `BpfMap`'s path constructor aborts when a pinned BPF map is missing, and the Motorola kernel doesn't carry the GPU-work BPF program (the `gpu_work_period` tracepoint), so `GpuWork::getBpfMap`'s `isValid()` check never ran. `android-17.0.0_r1` makes the same fix upstream (`map.init()`, "BpfMap ctor calls abort() on failure"), so the patch was deleted with the move to Android 17. Google's 17 GSI kept `gpuservice` up on this phone.
