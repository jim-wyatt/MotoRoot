# VedoTom image: review findings and backlog

Review of the image built on the Legion T5 on 2026-11-17 at 11:59 EST:
`Android/vedotom_arm64/generic_arm64:Baklava/BP4A.251205.006/eng.sysadm:userdebug/test-keys`.
It was installed by DSU on the XT2617V (24 GB data partition, Wi-Fi, no SIM) and checked from
adb about four minutes after first boot. The stock system is not affected by anything here.

Work these on the Legion.

## What works

- It boots: about 37 s to the lock screen, with no boot animation as intended. SELinux is enforcing. The crash log, tombstones and ANRs are all empty.
- The first-boot service finished in 11.6 s. Fennec and Organic Maps are installed with F-Droid as installer. HOME, BROWSER, DIALER and SMS go to Fossify Launcher, Fennec, Fossify Phone and Fossify Messages. All 16 Fossify apps have the teal icon.
- `gpuservice` stays up, so the BpfMap patch holds.
- Hardware works: Wi-Fi (5 GHz, validated), Bluetooth, NFC, GNSS, 2 cameras, the full sensor list (including the Motorola gestures), fingerprint HAL, audio, thermal and 120 Hz display modes. Cellular is untested because there's no SIM.
- The only SELinux denials are 34 from the vendor's `batt_health` reading `default_prop`, plus one `statsbootstrap` lookup.

## 1. Make it match the clean development baseline (priority)

**Done for the next image (2026-11-17), awaiting validation on the device.** All four points below are in place. Two details differ from the suggestions: the development settings are set by the first-boot service, not a SettingsProvider overlay, because SettingsProvider has resource defaults for only two of the five in this tag; and the log size is set by an init rule running `logcat -G 16M` on `logd.ready`, because logd ignores `ro.logd.size` and `persist.logd.size` at start on a phone (it reads them only on automotive and desktop hardware types). [What's in the image](aosp-build.md#whats-in-the-image) describes the result.

The stock system was reduced to a clean development baseline on 2026-11-17 (commits 5300f04 and f895d9b). The image and the deploy loop haven't caught up yet.

- **Decided 2026-11-17: the image keeps only the Fossify suite on top of AOSP.** Organic Maps, Fennec F-Droid and the F-Droid client come out. That means removing:
  - their modules: `OrganicMapsPreload`, `FennecPreload` and `FDroid`, from `vedotom_arm64.mk`, `prebuilt/Android.bp`, `prebuilt/apks.txt` and the `vedotom_system_image` deps in `Android.bp`
  - the preload machinery: step 1 (preload install) and step 2b (BROWSER role) of `vedotom-firstboot.sh`. Steps 2 (HOME role) and 3 (icon colour) stay.
  - the release-config override in `release/`. It exists only because Gecko calls `MessageQueue.next()`, so `trunk_staging`'s default queue is fine again.
  - the Organic Maps and Fennec pins in `dev/toolchain.json`. **Keep the F-Droid pin**, because the stock baseline still has the F-Droid client installed.
  - the maps step from `Deploy-Image.ps1` (`-NoMaps`, `-Region`), and `Push-OfflineMaps.ps1` with the `work\organicmaps` copy it reads
  - the matching text in `aosp-build.md` ("What's in the image", "Fennec and the MessageQueue flag", "Offline maps", the Deploy-Image description), and anywhere else these apps are mentioned (credits, NOTICE, README, validation)

  What follows from this: the image has no web browser (Browser2 was removed for Fennec and stays out), and nothing updates the Fossify apps on the device. They're updated by re-pinning them and shipping a new image. Fossify Keyboard stays, and LatinIME stays the default and fallback.
- **Hide the AOSP Files icon; Fossify File Manager replaces it.** DocumentsUI can't be removed: it's the system file picker behind every open, get-content and save dialog (`.picker.PickActivity`), Fossify apps included. Only its launcher entry, `com.android.documentsui/.LauncherActivity`, needs to go. Tested on this image: after `pm disable com.android.documentsui/.LauncherActivity` the icon is gone, and OPEN_DOCUMENT, GET_CONTENT and CREATE_DOCUMENT still resolve to DocumentsUI's picker. Add it to `vedotom-firstboot.sh` as a once-only step with a marker, like the HOME role, then force-stop `org.fossify.home`. If DocumentsUI's manifest gates that alias on a resource flag in this tag, an overlay value is cleaner than first boot doing it. Check `packages/apps/DocumentsUI/AndroidManifest.xml` in the tree.
- **The development settings aren't in the image.** The animation scales are 1.0, and `verifier_verify_adb_installs` and `adb_allowed_connection_time` are unset. Either set their defaults in the image (a SettingsProvider overlay: `def_window_animation_scale`, `def_transition_animation_scale`, plus the global settings) or run `Set-DevSettings.ps1` as a Deploy-Image step. The overlay is better: it survives a Discard and needs no PC.
- **Log buffers are 256 KiB.** On the stock system they're 16 MiB. In the image, the first-boot service's log lines had already rotated out of every buffer four minutes after boot. Set `ro.logd.size=16M` (or `persist.logd.size`) in `PRODUCT_PRODUCT_PROPERTIES`, and check with `logcat -g` that this logd honours it. On stock it didn't, which is why `dev_debuggable` 1.3 re-applies it.

## 2. Correctness

**Done for the next image, awaiting validation:** the time zone (`persist.sys.timezone=America/New_York` as the product default) and the first-boot result (a `log` and a `status` file in `/data/local/vedotom-firstboot/`, which `Deploy-Image.ps1` now reads instead of logcat). The other three points are open.

- **The time zone is GMT.** Auto time zone is on, but with no SIM the telephony suggestion (MCC 310, `America/New_York`, match type 2: the US has several offsets) isn't applied, and there's no location time-zone provider (`mGeoDetectionSupported=false`). Ship a default `persist.sys.timezone` (product property) or let first boot set it. Location time-zone detection needs a provider, which AOSP doesn't ship without GMS.
- **The first-boot result relies on logcat.** `Deploy-Image.ps1` waits for `vedotom-firstboot: done` in logcat, and its report counts preloads and icons from logcat too. With 256 KiB buffers and vendor log spam (below), those lines can roll out within minutes: here they already had. Have the script also append to `/data/local/vedotom-firstboot/log` and set a property when it's done, then make Deploy-Image read those.
- **Vibration amplitude errors.** There were 17 `DefaultHalVibrator: Error setting amplitude to -1.0` failures (IllegalArgumentException from `IVibrator.setAmplitude`). The framework sends the "default amplitude" sentinel to a HAL that rejects it. Check `config_vibratorSupportsAmplitudeControl` and the HAL capabilities. The fix is probably a framework overlay value or a small patch in `VintfHalVibrator`.
- **Wi-Fi binder errors.** 34 `FAILED BINDER TRANSACTION` and 15 `Outgoing transactions from this process must be FLAG_ONEWAY` stack traces in `IWifiManager.onTransact`, from `ParceledListSlice`. Find the caller (probably the Settings Wi-Fi picker or the passpoint lookup; `WifiService: Attempt to retrieve passpoint with invalid scanResult List`) before deciding whether it matters.
- **Charge cap.** The phone lives on the charger, and the stock system caps at 80% through Moto Actions, which the image doesn't have. It was charging at 93% here. There's no `charge_control_limit` node. Look at the MediaTek and Motorola charger sysfs (`mtk-master-charger`, `/sys/module/mmi_*`) for a stop or limit control that the first-boot service or an init rule could set. The `batt_health` denials above may be related.

## 3. Trim and harden (lower priority)

- **ADB needs no authorisation:** `ro.adb.secure=0`. Any USB host gets a root-capable shell on this userdebug image. That's convenient on a desk, but it should be a deliberate choice, and `ro.adb.secure=1` costs one tap per new PC. adb isn't listening on TCP.
- **Remove the Virtualization packages.** `vedotom_arm64.mk` inherits `packages/modules/Virtualization/apex/product_packages.mk`, and `com.android.compos` is in the image deps, but this SoC has no AVF (`com.android.virtualization.terminal` is disabled). That's dead weight in a full system partition.
- **Unneeded AOSP apps:** PhotoTable and BasicDreams, `com.android.egg`, Bips (print), PrintSpooler, HtmlViewer, BookmarkProvider, CallLogBackup, WallpaperBackup. Keep Traceur: it's useful for development. Each one has to come out of the makefiles and the `Android.bp` mirror together.
- **Google endpoints still in use:** captive-portal checks (`connectivitycheck.gstatic.com`, `www.google.com`) and NTP (`time.android.com`). If avoiding Google as far as practical applies to the image too, set `captive_portal_*_url` and `config_ntpServer` in the overlay, for example to a self-hosted or neutral endpoint and `pool.ntp.org`.
- **WebView is AOSP's 140.0.7339.4 from the tag.** Nothing updates it in this image, so it ages with the tag. With Fennec gone, it's the only web engine on the device.
- **Security patch level 2025-11-05** (tag android-16.0.0_r4) under a 2026-04-01 vendor patch level. Move the tag when a newer Android 16 QPR release is out, and expect the `Android.bp` mirror and the patches to need rebasing.

## Vendor noise (only fixable outside the image)

- `MotWlc_AIDL` logged 499 errors in four minutes, polling a missing `wireless/device/wlc_st_changed` node. `mtkpower@impl: [setMode] unknown type` logged 87, because the GSI's PowerHAL modes don't match MediaTek's. These two are the main reason a 256 KiB buffer rolls over so fast. A bigger buffer makes it bearable.
- Missing from the VINTF manifest and harmless here: dumpstate, IRadioIms (so VoLTE in the image is doubtful until a SIM test), weaver, oemlock, power.stats, BootControl (AIDL).

## Also noticed

- Magisk's `init_boot` patch runs inside the DSU image too: `magisk --service` and `--boot-complete` run at boot. With no `/data/adb` in the image's data it does nothing, but it's there.
- `/data` in the image: 22 GB free after the maps were removed again (they were pushed by mistake during this deploy).
