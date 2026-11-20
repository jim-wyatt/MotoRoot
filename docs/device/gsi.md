# Run vanilla Android with a GSI

Android is built in two halves: the **system** (the framework, the apps, everything Google and the vendor layer on top) and the **vendor** partition (the hardware support for this exact device). Since Treble, those halves meet at a defined interface, which is why a **Generic System Image** (GSI), Google's own build of plain AOSP, can run on a device with Motorola's vendor partition underneath. This page boots one on this device.

## DSU: try it without flashing anything

**Dynamic System Updates** (DSU) is Android's built-in way to boot a second system from image files in `/data`, on top of the device's own vendor partition and boot images. Nothing is flashed, the slots are untouched, and the GSI gets its own separate userdata. It's the right first experiment: it answers "does this hardware run non-Motorola Android" with the lowest possible risk, and it needs none of the `super`-partition surgery that flashing a GSI can.

What stays the same while the GSI runs: the bootloader, the kernel and vendor modules, `init_boot` (so Magisk is still in the boot chain), and your real `/data`. What changes: the whole system partition, so expect an AOSP launcher, no Motorola apps, no Google apps (this is the plain AOSP image, not the "+GMS" one), and rough edges wherever the generic image has no tuning for MediaTek hardware (camera quality, fingerprint, maybe audio routing). Wi-Fi normally works, because it's a vendor-side service.

!!! warning "Experimental on this device"
    DSU was designed for exactly this, but this unit is the first time it's been tried on this model; the [validation page](validation.md) records the outcome. The [disclaimer](../reference/disclaimer.md) applies. `Install-Gsi.ps1 -Action Boot` boots the GSI for **one boot only**: whatever happens, the next reboot (even a forced one by holding Power) returns to the installed system. This project's own images are the exception: `Deploy-Image.ps1` boots them with `-Persistent`, so the image stays the phone's system across reboots, and `.\dev\Install-Gsi.ps1 -Action Stock` disables it (still installed) and reboots to the stock system on slot A, which DSU never touches. Use `Deploy-Image.ps1 -SingleBoot` for a one-boot trial of an untested image.

## The image

The pinned image is Google's official **AOSP arm64 GSI for Android 17** (`CP2A.260605.012`), the stable release of the same Android 17 drop as the source tag this project builds from (`deviceTools.gsi` in `dev/toolchain.json` has the build id, URL and SHA-256). It is one generation above the stock Android 16 system and three above the Android 13 vendor layer, and it booted and ran the hardware on this device on 2026-11-19 (the [validation page](validation.md)). Until that day the pin was the Android 16 GSI `BP4A.251205.006`, which the sections below were written against; the procedure is the same. Google publishes it under [its GSI terms](https://developer.android.com/topic/generic-system-image/releases); the download step asks you to accept them explicitly, the same way the bootstrap does for the SDK.

## Steps

All from the dev shell, phone connected over USB, Magisk root working:

```powershell
.\dev\Install-Gsi.ps1 -Action Download -AcceptGoogleGsiTerms   # ~1 GB, verified against the pinned SHA-256
.\dev\Install-Gsi.ps1 -Action Install                           # pushes the zip; waits for the install (enter the PIN on the phone if it asks)
.\dev\Install-Gsi.ps1 -Action Boot                              # one-shot boot into the GSI
```

`Install` hands the zip to Android's own DSU installer (the same one behind *Developer options → DSU loader* on Pixels), which unpacks `system.img` into `/data/gsi/` and creates an 8 GiB userdata image (`-UserdataGiB` to change). A notification shows progress; `gsi_tool status` goes `normal → installing → installed`, and the script waits for it.

`Boot` enables the GSI for a single boot and reboots. The first boot takes several minutes (the GSI sets itself up). Once up, `ro.gsid.image_running` is `1` and `ro.build.fingerprint` is Google's, not Motorola's:

```powershell
.\dev\Install-Gsi.ps1 -Action Status
& $adb shell getprop ro.build.fingerprint          # google/aosp_arm64/...
& $adb shell su -c id                              # does Magisk still answer? (recorded on the validation page)
```

Things worth checking while you're there, and noting if they fail: Wi-Fi, the display at 120 Hz, audio, the cameras, the fingerprint reader, USB debugging, and whether `scrcpy` connects. The AOSP image has a persistent notification offering to **Keep** the DSU across reboots or **Discard** it; you don't need either.

## Coming back

Reboot. The one-shot boot is over and the Motorola system comes back with everything as it was. (This project's own images are booted persistently and switched with `-Action Stock` and `-Action Boot -Persistent`; see [Living with the image](../develop/aosp-build.md#living-with-the-image).) The GSI's images stay in `/data` (about 3 GB plus the userdata) until you remove them:

```powershell
& $adb reboot                                      # back to the installed system
.\dev\Install-Gsi.ps1 -Action Discard             # removes the GSI and its userdata
```

If the GSI never reaches the home screen, hold **Power** until the phone restarts; because the boot was one-shot, it comes back to the normal system, and `Discard` cleans up.

## What happened on this device

Tried on unit 2 on 2026-11-16 with the pinned `BP4A.251205.006` image, exactly as above. The [validation page](validation.md#engineering-device-tooling-unit-2-2026-11-16) has the table; the short version:

- **It boots.** The DSU installer accepted the zip (the device has no `/avb` key set; `system_gsi` still carried Google's AVB key and the install reported `READY`). The one-shot boot reached the AOSP home screen in well under the ten-minute allowance, `ro.build.fingerprint` was `Android/aosp_arm64/generic_arm64:16/BP4A.251205.006/...`, and Developer options showed *DSU Loader: DSU is running*.
- **Working:** display in its 120 Hz mode, Mali GPU (OpenGL ES 3.2), Wi-Fi (HAL up, 27 networks in the first scan), audio (the primary output thread exists), 53 sensors registered, the fingerprint HAL registered, USB debugging after enabling it once in the fresh userdata.
- **Partly:** cameras: AOSP sees 2 of the 3 camera devices.
- **Noisy:** `gpuservice` crashes and restarts every 30 seconds (`SIGABRT`), a mismatch between the generic image and the Mali vendor libraries. The UI doesn't depend on it, but it's a steady drip of crash logs and a little CPU.
- **Magisk:** `magiskd` runs and `/debug_ramdisk/magisk -v` answers `31.1:MAGISK:R`, so the boot chain is intact underneath. `su` is denied, because the Magisk app and its grant database live in the real `/data`, which the GSI doesn't see; expect no root inside the GSI, and no modules applied.

One script bug surfaced and is fixed: `gsi_tool status` reports partitions as installed the moment they're created, so the install step now waits for the installer's own `READY` status instead.

**Capture the session before you leave it.** Two things exist only while the GSI runs: its boot log (which HALs registered, every SELinux denial, the `gpuservice` tombstones) and the vendor interface as the generic system negotiated it. `.\dev\Dump-DeviceInfo.ps1 -Label gsi-BP4A -Bugreport` records both, plus a full `adb bugreport`, into `work\device-info\` (private). On unit 2 that showed 17 `gpuservice` restarts in ten minutes, denials dominated by the vendor's `batt_health` domain, and the camera service registering only two devices. The drivers themselves are on the vendor partition and identical under stock, so dump those from stock, with root, when you need them.

## If it doesn't boot

Three things are untested going in: whether the DSU installer on this firmware accepts an image it can't verify against Google's key (the device has no `/avb` key set, and the bootloader is unlocked, which is the condition DSU documents for unverified images); whether Magisk in `init_boot` is happy underneath a foreign system; and the MediaTek vendor interface itself. The order to investigate is the installer's logcat (`& $adb logcat -d | Select-String dynsystem`), then a boot with Magisk's modules disabled (safe mode: hold Volume Down during the GSI boot), then `gsi_tool install` with a raw image, which bypasses the installer app. None of that touches the installed system.

## And after that

If the GSI runs well, the next step up is flashing it to the inactive slot so it's a real second system rather than a one-shot; the [hardware inventory](hardware.md) shows `super` has the room. That's a different risk class (slot B's bootloader is stock and untested, and `system` is only flashable from fastbootd) and gets its own page when it's tried. A full LineageOS-style port, with a device tree and extracted vendor blobs, is further again: there is no official or community LineageOS build for this model, so a LineageOS *GSI* through the same DSU route is the realistic way to run it here.
