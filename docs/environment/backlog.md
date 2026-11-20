# Backlog

What is still open about the image and its build, with what is known about each item. Items that are done are not kept here: what they established is in [What's in the image](image.md) and the [validation history](validation.md#history), and the policy choices behind them (adb authorisation, no Google endpoints, WebView, which system apps stay) are in [Decisions](../reference/decisions.md).

The list started as the review of the first image built on the build node (2026-11-17) and has been worked down since. Nothing here affects the stock system.

## Validate the first Android 17 image

**Build 10**, the first image from `android-17.0.0_r1`, is built from `main` and still has the old `vedotom_arm64` names. It is the first image to go through `aosp-academy deploy`. It is checked against build 9 with the full [checklist](validation.md#the-checklist), plus four points the [tag move](tag-moves.md#worked-example-android-16-to-17-2026-11-19) left for the first build:

- **Fingerprint HIDL 2.1.** Android 17's `generic_system.mk` no longer installs the HIDL `android.hardware.biometrics.fingerprint@2.1` package, and this phone's fingerprint HAL is HIDL `@2.1`. Google's 17 GSI still found it (`FingerprintProvider/defaultHIDL`), but our build has to show the same: enrol a finger and unlock with it.
- **`adb_keys`.** `/product/etc/security/adb_keys` in the build output and on the phone, and a deploy with no Allow tap.
- **`gpuservice` without the patch.** The `frameworks/native` patch was deleted because Android 17 fixes the abort upstream; check that `gpuservice` stays up with no GpuWork abort.
- **The 17 GSI's hardware list** ([its validation row](validation.md#history)): display modes, cameras, sensors, NFC, Bluetooth, GNSS, Wi-Fi, audio, the modem, the HAL count.

Then the **first `aospacademy_arm64` build** (from `restructure`) is deployed and should match build 10 apart from the names. Its build node first has to remove `device/vedotom` and revert the old `build/soong` patch ([Build the image](building.md#a-tree-that-had-the-pre-rename-product)).

## Watch the SystemUI crash

Seen once, 7 s into build 4's first boot: SIGSEGV with pc `0x0011c70000000000`, from `nterp_helper` in `androidx.compose.runtime.SnapshotStateKt` (a `snapshotFlow` lambda), then `SnapshotKt.advanceGlobalSnapshot`, then `Recomposer.composeInitial`, then a LazyLayout subcompose. SystemUI restarted and stayed up. It wasn't seen on earlier images and hasn't been reproduced (builds 5 to 9 had empty crash logs).

If it comes back: check the dalvik-cache and `odrefresh` status for system_ext apps (CompOS is out of the image since build 4, so SystemUI may run interpreted at first boot), and look at the tagged-address setting in the crash (`tagged_addr_ctrl: PR_TAGGED_ADDR_ENABLE`). Keep an eye on the crash buffer on every first boot (`adb logcat -d -b crash`).

## Vendor noise

Log spam from the vendor side, which the image can't fix and which is why the log buffers are 16 MiB ([the log size rule](image.md#the-log-size-rule)):

- `MotWlc_AIDL` logged 499 errors in four minutes, polling a missing `wireless/device/wlc_st_changed` node (the wireless-charging service, on a phone without that node).
- `mtkpower@impl: [setMode] unknown type` logged 87, because the GSI's PowerHAL modes don't match MediaTek's.
- SELinux denials: about 34 per boot from the vendor's `batt_health` reading `default_prop` (it reads a battery first-use-date property; unrelated to the charge limit), plus `statsbootstrap` lookups and `vendor_init`.
- Two FLAG_ONEWAY stack traces at boot from `system_server` calls on oneway-only threads (`IVibrator.getCapabilities` at vibrator init, `IBluetooth.getProfile` when Bluetooth turns on), and `WifiService: Attempt to retrieve passpoint with invalid scanResult List` when the Wi-Fi picker opens. Harmless.

Missing from the VINTF manifest and harmless here: dumpstate, IRadioIms, weaver, oemlock, power.stats, BootControl (AIDL).

Only worth more work if one of them starts to cost something (a battery drain, a crash): the fix would be on the vendor side, outside the image.

## Cellular and VoLTE untested

The phone has no SIM, so calls, SMS, mobile data and carrier features have never been tested on the image. What is known:

- The modem comes up, and on this vendor calls, data, SMS and SIM use AIDL HALs (`radio.voice`, `.data`, `.messaging`, `.modem`, `.network`, `.sim`, plus MediaTek's `mtkradioex`), which Android 17 still supports.
- **VoLTE is doubtful:** `IRadioIms` is missing from the VINTF manifest, so voice over LTE may not work in the image. Only a SIM test will tell.
- Android 17 drops the HIDL radio packages. The only HIDL radio entry on this vendor is `@1.2::ISap` (Bluetooth SIM Access), so at most SAP is lost.
- Fossify Phone and Fossify Messages hold the DIALER and SMS roles, but have never placed a call or sent a message on this phone.

## Build memory headroom

Android 17's Soong analysis fits a 26 GB build node only with the heap-limit patch, at 24 GB resident ([Memory](building.md#memory)). A later tag may not fit. Two levers are known and untried: a `zram` swap device in the build node's guest, and pruning unused trees with `PRODUCT_SOURCE_ROOT_DIRS` (about 3,000 of Android 17's 15,600 `Android.bp` files are under `cts`, `platform_testing`, `development`, `test` and `tools`).

## Smaller items

- **Delete the Android 16 tree.** `~/aosp` (135 GB) on the build node is no longer needed since the switch to Android 17, but keep build 9's `system.img` until an Android 17 image passes validation. The owner runs the `rm`.
- **Patch names with dashes.** `apply-local.sh` maps every dash in a patch's project part to a slash, so a project with a dash in its path (`prebuilts/build-tools`) can't be patched. No current patch needs one; fix the naming before one does.
- **`JOBS` from one place.** `sync.sh` and `build-image.sh` each default `JOBS` themselves (half the cores and all cores). The tree directory already comes from one place (`deviceTools.aosp.treeDir`).
- **Fetch streams.** 8 parallel streams had not levelled off in the benchmark (1 stream 2.2 MB/s, 4 streams 5.3 MB/s, 8 streams 6.6 MB/s); `--streams 12` and `16` are untried.
- **Magisk inside the image.** Magisk's `init_boot` patch runs inside the DSU image too: `magisk --service` and `--boot-complete` run at boot. With no `/data/adb` in the image's data it does nothing, but it is there. Nothing to do unless it starts to matter.
