# Move to a new AOSP release

The image is built from one AOSP release tag, pinned as `deviceTools.aosp.tag` in `toolchain.json`. Moving it to a newer tag brings a newer Android, a newer security patch level and a newer WebView (which otherwise ages with the tag). It is also the largest change this project makes: this project's product is a set of copies of upstream files and patches against upstream code, and every one of them has to be checked against the new release.

This page is the procedure, generalised from the move from Android 16 to Android 17 on 2026-11-19, which follows as the worked example.

!!! note "Release tags are rare"
    Google has published AOSP source less often since 2025: `android-17.0.0_r1` is the "26Q2" release, and Android 17's later QPR releases exist only as Google's GSI binaries, not as source. A move is usually to a new major version, not a patch bump. If a newer source drop is close, waiting for it can save a second port, but step 0 is worth doing at once either way.

## Step 0: does Google's GSI run on this vendor?

Nothing else matters until this is answered. The phone's vendor layer is **Android 13's**: `ro.vndk.version=33`, `ro.board.api_level=33`, VINTF `target-level="7"` (framework compatibility matrix level 7). An Android system runs on it only as long as the system still ships the VNDK APEX for version 33 (`com.android.vndk.v33`, the vendor's view of the system libraries) and `compatibility_matrix.7.xml`. If a new release drops either, the vendor's HALs don't start, and no amount of porting helps.

So the first step is a cheap test that changes nothing in the repository: boot **Google's own GSI** of the new release through DSU. About an hour, and reversible.

1. Keep a copy of the current validated `system.img` and its `build.prop`, as the known-good image to go back to ([Rolling back](deploying.md#rolling-back-to-an-earlier-image)). Installing another GSI discards the installed image and its data.
2. Pin the GSI zip in `toolchain.json` (`deviceTools.gsi`: name, URL, SHA-256, under Google's GSI terms) on a branch, then on the device node `./aosp-academy gsi download --accept-google-gsi-terms`, `./aosp-academy gsi install`, `./aosp-academy gsi boot`. Google's GSI is a user build with release keys: no `adb root`, every check runs as shell, and USB debugging must be switched on by hand in the GSI (its fresh data starts with it off).
3. Check what the current image is known to do: boot and time to the lock screen, SELinux enforcing, Wi-Fi validated, display modes (120 Hz), audio, both cameras, the sensor list, fingerprint, vibrator, NFC, Bluetooth, GNSS, the modem, USB debugging, the `lshal` count against the last image, `gpuservice`, SELinux denials and the crash log. For the charge-limit module, check only that `/sys/module/qpnp_adaptive_charge/parameters` **exists**: don't read the parameters ([why](image.md#the-charge-limit)). Capture an inventory with `./aosp-academy device info --label gsi<version>`.
4. **Go** if it boots and the hardware list matches the current image's. **No go:** stay on the current tag, and re-test with each new source drop.

Step 0 also tells you which of this project's patches are still needed: a bug the new GSI still shows needs its patch carried over, and one it no longer shows may be fixed upstream.

## Step 1: a second tree, on a branch

Do the move on a git branch (for example `aosp-17`), so `main` keeps building the current release for fixes until the switch-over. On the branch, set `deviceTools.aosp.tag` to the new tag and `deviceTools.aosp.treeDir` to a **new** tree directory, so the build node syncs the new release next to the current one rather than over it (the Android 17 tree used about 335 GB). Keep the old tree until the new release has run for a while.

## Step 2: port this project's changes

Each item has its own check. Most of them can be done from upstream's source browser (android.googlesource.com), file by file, before the new tree has finished syncing.

| What | How to check it |
| --- | --- |
| **Lunch target** | The release configuration name (`trunk_staging`) can change. `lunch` with no arguments in the new tree lists the tag's targets; `deviceTools.aosp.lunch` is the one place to change. |
| **Product makefiles** | Diff upstream `aosp_arm64.mk`, `aosp_product.mk`, `handheld_product.mk` and `telephony_product.mk` between the two tags, and carry what moved into `aospacademy_*.mk`. Also read what the inherited files (`generic_system.mk`, `gsi_release.mk`, `media_product.mk`) now add or drop, especially anything this vendor relies on. |
| **`Android.bp` mirror** | Diff `build/make/target/product/gsi/Android.bp` (`aosp_system_image`, `android_gsi_defaults`) between the tags and carry the changes into `aospacademy_system_image` and `aospacademy_gsi_defaults`. **filelistdiff** confirms it at build time: it names every module the makefiles install and the mirror lacks, or the other way round. Re-check the VNDK APEX list, and keep `v33`. |
| **Patches** | For each patch in `image/patches/`: does the bug still exist in the new tag (step 0 is evidence), and does the patch apply (`git apply --check` in the project)? Drop a patch the tag fixes upstream; rebase the rest. `apply-local.sh` stops at any patch that doesn't apply, so a stale one can't slip through. |
| **Overlays** | Every resource name the overlays set must still exist with the same type: the framework's `frameworks/base/core/res/res/values/config.xml`, and NetworkStack's `res/values/config.xml` and `overlayable.xml` (the `NetworkStackConfig` overlayable). A renamed resource is silently ignored, so check by name. |
| **Release flags** | `PRODUCT_ADB_KEYS` and the release flag `RELEASE_BUILD_PURGE_PRODUCT_ADB_KEYS`: check its value for userdebug in the new tag, then `/product/etc/security/adb_keys` in the first build's output. Any other flag the product relies on, likewise. |
| **First-boot service** | The shell interfaces it calls (`cmd role`, `settings`, `pm enable/disable`), the Fossify alias names and the `seclabel u:r:su:s0` domain. These are not easily diffed; the first build's validation covers them. The charge-limit module is vendor-side and doesn't change with the tag. |
| **APK pins** | Check that the pinned Fossify versions install on the new release (their minimum and target SDK against the platform's minimum); bump the pins if needed. |
| **WebView** | Comes with the tag, so it updates for free. |

## Step 3: build, deploy, validate

Request a build of the branch. The first build of a new tree is a full one (about 2.5 hours on the build node, plus Soong analysis), and memory is the usual surprise: a new release's analysis can outgrow the build node, as Android 17's did ([Memory](building.md#memory)).

Deploy it and run the whole [validation checklist](validation.md#the-checklist), plus step 0's hardware list. Compare against the last validated build, item by item, and record the result as a validation row.

## Step 4: switch over

When the new image passes:

1. Merge the branch into `main`.
2. Move the pins to the new release: `deviceTools.aosp.tag`, `deviceTools.aosp.treeDir`, and `deviceTools.gsi` to the new release's GSI.
3. Update the docs that name the release: [What's in the image](image.md), [DSU](../device/dsu.md), [Pins](../reference/pins.md) and the validation page.
4. After a period without problems, delete the old tree on the build node.

**Going back** is possible at every step until the switch-over (`main` still builds the old release, and a saved `system.img` restores the current image with `deploy --no-fetch`). After it, only the saved image holds, so keep the last image of the old release until the first image of the new one has passed validation.

## Worked example: Android 16 to 17 (2026-11-19)

**Where things stood.** The image was built from `android-16.0.0_r4` (`BP4A.251205.006`, security patch 2025-12-05). The AOSP manifest had no later Android 16 tag: the only newer one was **`android-17.0.0_r1`** (`CP2A.260605.016`, Android 17, security patch 2026-06-05). So moving the tag meant moving to Android 17, a major version.

**Step 0: go.** Google's Android 17 GSI, `aosp_arm64-exp-CP2A.260605.012-15430684-8e545e1e.zip` (SHA-256 `8e545e1e1e977c3b43b4e54a3af463f3e7d1c3177b120e772138334e15f48f75`, from `https://dl.google.com/developers/android/cinnamonbun/images/gsi/`, the stable Android 17 GSI of the same release as the tag), booted on this Android 13 vendor and the hardware matched Android 16's (the [validation row](validation.md#history) has the full list). Two findings for step 2: the vibrator amplitude error recurred (11 times), so that patch stays; and `gpuservice` stayed up with no GpuWork abort, so that patch could go.

**Step 1.** The move ran on the branch `aosp-17`. The build node synced the new tag into a separate tree, `~/aosp17` (about 335 GB used, 622 GB free on its disk), with `sync.sh` reading the branch's `toolchain.json`, and kept `~/aosp` for Android 16.

**Step 2: the checklist.** The upstream diff, `android-16.0.0_r4` against `android-17.0.0_r1`, read file by file from android.googlesource.com on 2026-11-19, with no tree needed. The file names are as they were then; the product was renamed from `vedotom` to `aospacademy` afterwards.

| What we carry | Android 17 | Action on `aosp-17` |
| --- | --- | --- |
| `vedotom_product.mk`, `vedotom_handheld_product.mk` (mirrors of `aosp_product.mk`, `handheld_product.mk`, `telephony_product.mk`); `vedotom_arm64.mk` (from `aosp_arm64.mk`) | all four upstream files **unchanged** | none |
| `media_product.mk` (inherited) | adds `preinstalled-packages-media-product.xml` | nothing in the makefiles; add it to the `Android.bp` mirror if filelistdiff asks |
| `gsi_release.mk` (inherited) | `PRODUCT_SHIPPING_API_LEVEL` follows the platform; 16 KB `PRODUCT_MAX_PAGE_SIZE_SUPPORTED`; adds `hwservicemanager`, `android.hidl.allocator@1.0-service`, `android.hidl.memory@1.0-impl`, `wificond` for devices that shipped at API 34 or older (this one: vendor API 33) | inherited, nothing to port; keep `PRODUCT_NO_BIONIC_PAGE_SIZE_MACRO` (now also set upstream) |
| `generic_system.mk` (inherited) | drops the HIDL `android.hardware.radio@1.0`-`1.4`, `radio.config@1.0`, `radio.deprecated@1.0` and `biometrics.fingerprint@2.1` packages; `ro.product.system.name`/`model` become `generic_system` / `Generic System` | inherited. On this vendor, calls, data, SMS and SIM are AIDL (`radio.voice/.data/.messaging/.modem/.network/.sim`, plus MediaTek's `mtkradioex`); the only HIDL radio entry is `@1.2::ISap` (Bluetooth SIM Access), so at most SAP is lost. Fingerprint is HIDL `@2.1`: Google's 17 GSI still found it (`FingerprintProvider/defaultHIDL`), but **check it on our first build** |
| `Android.bp`: the mirror of `android_gsi_defaults` and `aosp_system_image` | `android_gsi_defaults` adds `preinstalled-packages-gsi-system-ext.xml`, `preinstalled-packages-base-product.xml`, `wificond`, `hwservicemanager`, `android.hidl.allocator@1.0-service`; `aosp_system_image` moves `AvatarPicker` from handheld_product to the handheld_system_ext group, and adds `preinstalled-packages-platform-telephony-system-ext.xml` and `preinstalled-packages-telephony-system-ext.xml`. VNDK `v31`-`v34` stay (this vendor needs `v33`); `com.android.compos` and `android.hidl.memory@1.0-impl` are where they were | **add all seven** to `vedotom_gsi_defaults` / `vedotom_system_image`; filelistdiff confirms |
| `build-soong-0001-build-prop-visibility-for-device-vedotom.patch` | `system_ext-build.prop` and `product-build.prop` keep the same visibility lists | **keep**: `git apply --check` passes on 17 |
| `frameworks-base-0001-vibrator-no-unknown-amplitude-to-hal.patch` | `VintfHalVibrator.java` changed in 54 lines elsewhere; the bug is still there (Google's 17 GSI logged 11 `setAmplitude` IllegalArgumentExceptions) | **keep**: applies cleanly on 17 |
| `frameworks-native-0001-gpuservice-no-abort-without-gpuwork-bpf.patch` | **fixed upstream**: `getBpfMap()` now uses `map.init()` ("BpfMap ctor calls abort() on failure"), which is why the 17 GSI's gpuservice stayed up | **delete** on `aosp-17`: it no longer applies, and `apply-local.sh` stops at a patch that doesn't apply |
| `VedoTomFrameworkOverlay`: `config_defaultNightMode`, `config_navBarInteractionMode`, `config_defaultDialer`, `config_defaultSms`, `config_ntpServers` | all five present, same types | none |
| `VedoTomNetworkStackOverlay`: the probe URLs and `NetworkStackConfig` overlayable | NetworkStack `config.xml` and `overlayable.xml` **unchanged** | none |
| Lunch target `vedotom_arm64-trunk_staging-userdebug` | the `trunk_staging` release config still exists | expected to carry over; `lunch` confirms |
| `PRODUCT_ADB_KEYS` (build 8 on) | the `adb_keys` module and the `RELEASE_BUILD_PURGE_PRODUCT_ADB_KEYS` declaration (MANUAL_BUILD_VARIANT) are identical | expected to carry over; **check** `/product/etc/security/adb_keys` in the first build's output |
| Fossify APK pins (minimum SDK 21-26, target 34-36) | installs on 17 (target SDK floor is far below) | none; revisit if a pin's target falls behind the platform's minimum |
| First-boot service (`cmd role`, `settings`, `pm`, `seclabel u:r:su:s0`) | not diffed (shell interfaces); the 17 GSI's `cmd wifi`, `settings` and `pm` behaved normally | covered by the first build's validation |

**Step 3.** The first build started on the build node the same day and never left Soong analysis: Android 17's `soong_build` outgrew the 26 GB WSL instance and filled its 32 GB of swap, where Android 16's analysis had fitted. It was fixed the same evening with a new patch, `build-blueprint-0001-soong-heap-limit-80-percent-of-ram.patch` ([Memory](building.md#memory)), and the build restarted with it. The resulting image is build 10, the first Android 17 build; its validation is still open ([Backlog](backlog.md)).

**Step 4, ahead of schedule.** The plan was to switch over after a week. Android 16 was instead dropped for good the same evening: the pins moved (`deviceTools.gsi` to `CP2A.260605.012`; `deviceTools.aosp.tag` was already `android-17.0.0_r1`), the docs moved to Android 17, the scripts began defaulting `AOSP_DIR` to `deviceTools.aosp.treeDir` (`~/aosp17`), and `main` was fast-forwarded to `aosp-17` while the first Android 17 build was still compiling. Since then, going back means build 9's `system.img` (Android 16, SHA-256 `53c37cd8…`), kept on the build node until the first Android 17 image passes validation. Deleting the old `~/aosp` tree (135 GB) is left to the owner.

**Effort.** Step 0 took about an hour on the device node; step 1, a sync of a few hours; step 2, one to three working sessions; step 3, a first full build of about 2.5 hours plus the memory fix, then deploy and validation.
