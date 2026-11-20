# Backlog

What is still open about the image and its build, with what is known about each item. Items that are done are not kept here: what they established is in [What's in the image](image.md) and on the [validation page](validation.md), and the policy choices behind them (adb authorisation, no Google endpoints, WebView, which system apps stay) are in [Decisions](../reference/decisions.md).

Nothing here affects the stock system.

## Enrol a fingerprint on Android 17

Android 17's `generic_system.mk` doesn't install the HIDL `android.hardware.biometrics.fingerprint@2.1` package, and this phone's fingerprint HAL is HIDL `@2.1`. On the current image the HAL is registered and `android.hardware.fingerprint` is listed ([validation](validation.md#current-image)), but nobody has yet enrolled a finger and unlocked with it. That needs a person at the phone and a screen lock; do it once on the current image.

## Watch the SystemUI crash

Seen once, 7 s into a first boot: SIGSEGV with pc `0x0011c70000000000`, from `nterp_helper` in `androidx.compose.runtime.SnapshotStateKt` (a `snapshotFlow` lambda), then `SnapshotKt.advanceGlobalSnapshot`, then `Recomposer.composeInitial`, then a LazyLayout subcompose. SystemUI restarted and stayed up. It hasn't been reproduced since.

If it comes back: check the dalvik-cache and `odrefresh` status for system_ext apps (CompOS is not in the image, so SystemUI may run interpreted at first boot), and look at the tagged-address setting in the crash (`tagged_addr_ctrl: PR_TAGGED_ADDR_ENABLE`). Keep an eye on the crash buffer on every first boot (`adb logcat -d -b crash`).

## Vendor noise

Log spam from the vendor side, which the image can't fix and which is why the log buffers are 16 MiB ([the log size rule](image.md#the-log-size-rule)):

- `MotWlc_AIDL` logs about 500 errors in four minutes, polling a missing `wireless/device/wlc_st_changed` node (the wireless-charging service, on a phone without that node).
- `mtkpower@impl: [setMode] unknown type` logs about 90 in the same time, because the GSI's PowerHAL modes don't match MediaTek's.
- SELinux denials: about 34 per boot from the vendor's `batt_health` reading `default_prop` (it reads a battery first-use-date property; unrelated to the charge limit), plus `statsbootstrap` lookups and `vendor_init`.
- Two FLAG_ONEWAY stack traces at boot from `system_server` calls on oneway-only threads (`IVibrator.getCapabilities` at vibrator init, `IBluetooth.getProfile` when Bluetooth turns on), and `WifiService: Attempt to retrieve passpoint with invalid scanResult List` when the Wi-Fi picker opens. Harmless.

Missing from the VINTF manifest and harmless here: dumpstate, IRadioIms, weaver, oemlock, power.stats, BootControl (AIDL).

Only worth more work if one of them starts to cost something (a battery drain, a crash): the fix would be on the vendor side, outside the image.

## Cellular and VoLTE untested

The phone has no SIM, so calls, SMS, mobile data and carrier features have never been tested on the image. What is known:

- The modem comes up, and on this vendor calls, data, SMS and SIM use AIDL HALs (`radio.voice`, `.data`, `.messaging`, `.modem`, `.network`, `.sim`, plus MediaTek's `mtkradioex`), which Android 17 still supports.
- **VoLTE is doubtful:** `IRadioIms` is missing from the VINTF manifest, so voice over LTE may not work in the image. Only a SIM test will tell.
- Android 17's system image doesn't include the HIDL radio packages. The only HIDL radio entry on this vendor is `@1.2::ISap` (Bluetooth SIM Access), so at most SAP is lost.
- Fossify Phone and Fossify Messages hold the DIALER and SMS roles, but have never placed a call or sent a message on this phone.

## Build memory headroom

Android 17's Soong analysis fits a 26 GB build node only with the heap-limit patch, at 24 GB resident ([Memory](building.md#memory)). A later tag may not fit. Two levers are known and untried: a `zram` swap device in the build node's guest, and pruning unused trees with `PRODUCT_SOURCE_ROOT_DIRS` (about 3,000 of Android 17's 15,600 `Android.bp` files are under `cts`, `platform_testing`, `development`, `test` and `tools`).

## Smaller items

- **Delete the old tree.** The build node still holds an older AOSP tree, `~/aosp` (135 GB), which nothing uses. The owner runs the `rm`.
- **Patch names with dashes.** `apply-local.sh` maps every dash in a patch's project part to a slash, so a project with a dash in its path (`prebuilts/build-tools`) can't be patched. No current patch needs one; fix the naming before one does.
- **`JOBS` from one place.** `sync.sh` and `build-image.sh` each default `JOBS` themselves (half the cores and all cores). The tree directory already comes from one place (`deviceTools.aosp.treeDir`).
- **Fetch streams.** 8 parallel streams had not levelled off in the benchmark (1 stream 2.2 MB/s, 4 streams 5.3 MB/s, 8 streams 6.6 MB/s); `--streams 12` and `16` are untried.
- **Magisk inside the image.** Magisk's `init_boot` patch runs inside the DSU image too: `magisk --service` and `--boot-complete` run at boot. With no `/data/adb` in the image's data it does nothing, but it is there. Nothing to do unless it starts to matter.
