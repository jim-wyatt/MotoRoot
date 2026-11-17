# Validation and limits

What was actually tested, on which hardware, and what remains unverified. The low-level stages of the [walkthrough](walkthrough.md) are **firmware-specific**: they are known to work only on the configuration below, and only as far as this page says. Read the [disclaimer](../reference/disclaimer.md) too.

## The exact tested device

| Item | Tested value |
| --- | --- |
| Retail model | Moto G Power 2026, Straight Talk, Walmart |
| Hardware model | **XT2617V** |
| Part number | XT2617VSS1PP |
| Box product code | STMXT2617VSSPWP |
| Bootloader product | vegas XT2617V 128 GB PVT (Fastboot reports `vegas`; Android reports `vegas26`) |
| Android | 16 |
| Build | `W1WEOS36.48-22-3-3-4-2` |
| Fingerprint | `motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys` |
| Security patch | 2026-04-01 |
| Kernel | `5.15.180-android13-8-00018-g9b2308ac0ad6-ab14563692` |
| Bootloader | `MBM-3.1-vegas_og_vext-5d518d-W1WEOS36.48-22-3-3-4-2-36210f` |
| CID | 0x0033 (decimal 51) |
| Active slot | `a` |
| `lk_a` / `init_boot_a` partition sizes | 16 MiB (`0x1000000`) / 8 MiB (`0x800000`) |

**Stop if your device differs** in model, build, security patch, kernel or active slot. Don't substitute the Moto G Play, the regular Moto G, the Power 2025, a retail XT2617-1, or any other firmware build. A tool recognising a kernel family, or a verifier reporting `VALID` for a file, is not proof that your device will accept or boot that file. Newer patches can close the vulnerabilities the procedure depends on.

## Runs on record

The procedure has been carried out twice, on two units of the configuration above, with the same pinned tool versions:

| | Unit 1 | Unit 2 |
| --- | --- | --- |
| Date | 2026-11-14 | 2026-11-16 |
| Carried out by | parsimo2010, the procedure's original author ([credits](../reference/credits.md)) | this project, following the walkthrough |
| Update staged before the unlock | Yes: current slot A, next boot B, `UPDATED_NEED_REBOOT`. Cancelled with `UpdateHelper`; both slots then reported 0 | No: both slots 0, engine log showed nothing to merge |
| Factory `init_boot_a` SHA-256 | `31239df6b54fd815912ba7d0e4cc87aca3af200eed8ff315238e4178580285ea` | identical |
| Backups | 18 partition images, device and PC hashes matched | same |
| LK analysis | AArch64; payload 1,238,664 bytes; unlock flow, FRP/OEM checker, key validator, erase-permission checks, partition erase ops and runtime serial getter all found | identical |
| Patched LK | verifier `Result: VALID`; other subimages' payloads and certificates unchanged | same |
| Prepared Magisk image SHA-256 | `fbac252d15501e8350b65ae93a92962f93d2907144286c04abf2eeda26c246d0` | identical, byte for byte |
| Patched LK on slot A | booted; Fastboot returned (briefly enumerated as a MediaTek serial device first) | booted; Fastboot returned in about 9 s |
| Unlock | `Bootloader is unlocked!`; `securestate: flashing_unlocked` | same |
| `fastboot flash init_boot_a` | rejected, "Preflash validation failed"; fastbootd could not open `init_boot_a` | not attempted; written from rooted Android as documented |
| Magisk write | read-back hash matched | same |
| Magisk Shell grant | granted through the app's prompt | prompt never appeared (`su: request rejected (2000)`); granted manually from the Superuser tab, see [Stage 7](walkthrough.md#stage-7-re-setup-and-install-persistent-root) |
| Persistent root | `uid=0`, `u:r:magisk:s0`, `31.1:MAGISK:R`, no KernelSU daemon, across multiple full reboots | same, across five reboots |
| Modules | `wifi_ota_guard`, `wifi_carrier_debloat` | the same two plus `wifi_extra_debloat` (19 more packages) |
| Afterwards | Google sign-in, Play Store and Wi-Fi internet worked; DFRoot and KernelSU removed | same |

Both runs retained stock Motorola Android: no custom ROM, no cellular network unlock, no root-hiding or Play Integrity bypass, and no claim of a performance change.

## What has not been established

- Any other model, build, security patch, kernel or slot configuration.
- Guaranteed emergency recovery if the modified LK fails before Fastboot starts. No vendor-independent recovery method was established or tested for this model.
- Restoring a stock image after a boot failure. The `fastboot flash lk_a` / `init_boot_a` rollback in [recovery](maintenance.md#recovery) is the intended path, but neither run needed it, so it is untested.
- A full OS backup, or a reliable fallback OS on slot B (particularly after a staged update was cancelled there).
- Cellular service, SIM unlock, or carrier features after the carrier debloat.
- Defeat of every undocumented hardware or firmware restriction, including modem or trusted-execution-environment behaviour.
- Universal app or game compatibility, Play Integrity results, or any speed difference.
- Behaviour across future Motorola OTAs, Google Play system updates, Magisk upgrades, or a factory reset (which removes the modules and root grants; see [maintenance](maintenance.md)).

## What failed along the way, and what the fix was

| Problem | What worked |
| --- | --- |
| Test DPC's settings UI crashed (both units) | Its ADB service interface cleared device ownership cleanly |
| Turning Wi-Fi off and disabling Smart updates did not stop an already-downloaded OTA from staging (unit 1) | `UpdateEngine.resetStatus()` via `UpdateHelper`, with `misc` temporarily writable |
| `UpdateEngine` reset failed at first (unit 1) | DFRoot had made `misc` read-only; `blockdev --setrw` for that one partition fixed it |
| Ordinary `pm disable` / clear-data on the updater was rejected as a protected operation even as root | The `wifi_ota_guard` overlay module |
| Fastboot rejected the Magisk image; fastbootd did not expose `init_boot` (unit 1) | Writing the verified image from rooted Android, with read-back |
| Magisk never showed the Grant prompt; `su` from ADB was denied instantly (unit 2) | Motorola's background freezer was suspending the Magisk app. Granting Shell manually from the Superuser tab (**+**) stored the policy |
| `pm uninstall --user 0` refused two packages as "non-disable" (unit 2) | Left alone deliberately (`com.amazon.appmanager` ships disabled; `com.motorola.ccc.devicemanagement` is protected) rather than forced through an overlay |

## Engineering-device tooling (unit 2, 2026-11-16)

Added after the preparation runs, all on unit 2, all reversible, as described in [Make it an engineering device](dev-setup.md):

| Item | Result |
| --- | --- |
| `dev_debuggable` module (`ro.debuggable=1`, `ro.build.type=userdebug`) | Installed; clean boot, no crashes, Play Store and launcher unaffected. Perfetto Java heap dump of Settings, a non-debuggable app: refused on stock (`not profileable` in logcat), a 24 MB dump with the module. With `ro.debuggable=1` alone it was still refused; `ro.build.type` is the property Perfetto checks. Not changed by either property: no JDWP for non-debuggable apps (only `adbd` on `@jdwp-control`), `run-as` still per-app, and `adb root` makes `adbd` abort (SIGABRT) and restart as `shell`. |
| `dev_adb_tcp` module | Installed; `adbd` listening on `*:5555` after boot. A Wi-Fi connection from the PC was not exercised: the PC and phone sat on different subnets, which `adbwifi` now detects and reports. |
| Termux 0.118.3 (GitHub build, hash-pinned) | Installed over ADB; `openssh` and `proot-distro` installed in the app; Debian 13 (trixie) via `proot-distro`. SSH over the ADB forward (`Connect-Debian`) verified from the PC: a session lands in Debian with the phone's `/data` free space available. `sshd` must be started in Termux after each reboot. |
| F-Droid 2.0.3 (hash-pinned; signing certificate and PGP signature verified against f-droid.org) | Installed over ADB (`versionCode` 2000053, installer none); launched. |
| `google_debloat` module (28 Google packages hidden; 8 Play updates removed first with `pm uninstall-system-updates`) | Installed; after the reboot none of the 28 packages is listed, Play services, GSF, WebView, Gboard, Contacts, Messages, Files, F-Droid and Termux remain, no crash in the crash log, launcher and root unaffected. |
| `vendor_extras_debloat` module (58 carrier, partner, Motorola and telemetry packages hidden) | Installed; after the reboot none of the 58 is listed (only two Battery Care resource overlays remain, which are not apps), camera, launcher, face unlock, Dolby, Moto Secure core, Play services, F-Droid and Termux remain, no crash in the crash log, root unaffected. |
| Organic Maps 2026.09.29-32 from F-Droid (index signature, APK hash and signer verified by hand) | Installed with F-Droid as installer; all 154 United States map files (15.5 GB, data version 260928) pushed over ADB into the app's data folder and listed as downloaded. |
| Frida 17.26.3 | `Start-Frida` pushes and starts the server; `frida-ps -Ua` lists the running apps. |
| Perfetto | `Trace-Device.ps1` records and pulls traces. The config file must live in `/data/misc/perfetto-configs/`; `/data/local/tmp` is refused by SELinux. |
| simpleperf | Unusable on this device: no perf events (`cpu-cycles` and `cpu-clock` both "not supported on the device"). |
| GSI via DSU (`Install-Gsi.ps1`, Google AOSP arm64 Android 16 `BP4A.251205.006`) | Installed through Android's DSU installer (status `READY`, `system_gsi` with Google's AVB key) and booted one-shot to the AOSP home screen; fingerprint `Android/aosp_arm64/generic_arm64:16/BP4A.251205.006`. Working: 120 Hz display, Mali GPU, Wi-Fi (27 networks scanned), audio output, 53 sensors, fingerprint HAL, ADB. 2 of 3 cameras exposed. `gpuservice` restarts every 30 s (SIGABRT). `magiskd` runs but `su` is denied inside the GSI (no Magisk app or grant database in the GSI's userdata). Reboot returned to the Motorola system as designed. |
| Android Virtualization Framework | Absent: no `ro.boot.hypervisor.*`, no `/dev/kvm`, no `com.android.virt` APEX, no Terminal app. |
| SDK `adb` vs pinned `adb` | Both 37.0.1-15733141, so Android Studio and the dev shell share one server; the self-test enforces equality. |

## About the committed artifacts

The helper DEX files and the module ZIPs in `device/` are rebuilt by this project from the sources beside them, and `.\dev\Build-Device.ps1` verifies that they reproduce. Relative to the files that ran on unit 1:

- **Helpers** (`UpdateHelper.dex`, `UpdaterCleanup.dex`): the Java logic is unchanged; the sources gained documentation comments, which shifts the debug line-number tables in the DEX but not the bytecode that executes.
- **Modules**: each ZIP contains the same `module.prop` and the same set of `.replace` markers as before, now built deterministically from a manifest (fixed entry order and timestamps) and carrying that manifest as `manifest.json` instead of the earlier `carrier-manifest.json` / `extra-manifest.json` name. Magisk ignores the extra file.

## Reporting a result

If you share results, include the model, build, security patch, kernel, the stage, and the exact error text, and **redact** serial numbers, IMEIs, account names, network identifiers and unlock keys. Never attach your backup images or raw logs. A success on another build is a new compatibility result to report, not something to assume from this one.
