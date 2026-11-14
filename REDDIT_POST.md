# Rooted a Walmart Straight Talk Moto G Power 2026 without buying a plan — exact XT2617V guide and files

I set up a brand-new **Walmart Straight Talk Moto G Power 2026 (XT2617V)** as a Wi-Fi-only device without buying a Straight Talk plan. It now has stock Android, Google Play sign-in, an unlocked bootloader, and **Magisk root verified after multiple full reboots**. The temporary-root tools were removed afterward.

**Full instructions, source, and files:** https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide

**Downloadable guide kit:** https://github.com/parsimo2010/moto-g-power-2026-straight-talk-wifi-root-guide/releases/latest

The guide includes all stages, commands, checkpoints, recovery limits, and a safe/risky actions table. The ZIP contains the small helper/source and two reversible Magisk modules, not firmware, rooted images, APK mirrors, identifiers, or unlock keys.

## Exact tested configuration

- Model **XT2617V**, part number **XT2617VSS1PP**, box **STMXT2617VSSPWP**.
- Bootloader product **vegas XT2617V 128 GB PVT**; Android device name **vegas26**.
- Android **16**, build **W1WEOS36.48-22-3-3-4-2**.
- Patch **April 1, 2026**; kernel **5.15.180-android13-8-00018-g9b2308ac0ad6-ab14563692**.
- CID **0x0033**, active slot **A**. Completed **November 14, 2026**, on one phone.

**Do not assume this works on a newer patch, another XT variant, an older Power, a regular Moto G, or a Moto G Play.** Bootloader modification can prevent Fastboot from starting. No guaranteed emergency unbrick method was established, and unlocking wipes user data.

## What actually worked

1. At Welcome, tap the same blank spot six times and scan **Google's Test DPC QR**. Choose **Use for work only**. Complete setup, skip Google sign-in, decline optional features/Smart updates, then switch Wi-Fi off immediately.
2. Enable USB debugging, approve the PC, clear Test DPC device ownership through its ADB service, then uninstall it. Its settings UI crashed, but the service command worked.
3. Use **DFRoot 4.7 and KernelSU 3.3.1** for temporary root. Keep automatic start/soft reboot off. Grant Shell root and verify uid=0 through ADB.
4. Back up the phone's original images and device-specific partitions. Keep backups private.
5. If an OTA already staged, cancel it using Android's UpdateEngine API **before rebooting**, then verify next boot stays A. Merely turning Wi-Fi off was insufficient.
6. Use pinned **Val Protocol** source to patch **your own lk_a backup**, generate a key from **your own serial**, flash the prepared LK, reboot into the bootloader, send the unlock command, and approve the phone's confirmation.
7. After the wipe, repeat setup/USB debugging and obtain temporary root again.
8. Prepare **Magisk 31.1** from the original **init_boot_a**, then write the verified patched image from rooted Android after checking the unlocked state. Verify its readback hash before rebooting.
9. Let Magisk finish additional setup and reboot. Grant Shell root in **Magisk**, not KernelSU. Verify persistent root without running DFRoot.
10. Install the reversible blocking modules, reboot, verify, and remove DFRoot/KernelSU. Sign into Google Play for normal Wi-Fi use.

This is an outline. Read the complete guide before any write command.

## Gotchas

- An update downloaded during setup despite declining optional features. Do not restart into newer firmware. The guide describes the completed-update cancellation used while temporary root was still available.
- DFRoot made boot partitions read-only; only the partition needed for a write was temporarily made writable.
- **Fastboot rejected Magisk with Preflash validation failed.** Fastbootd did not expose init_boot. The successful path was a verified write from temporarily rooted Android, not random vbmeta flashes or another model's image.
- Unlocking wipes setup/apps, so there are two setup passes. Magisk needs its own Shell permission and requested additional setup/reboot.
- No custom ROM or cellular network unlock was performed.

## Carrier apps and updates

One module hides Motorola Software Update. The other hides 22 carrier APK packages: Verizon management, My Verizon, Tracfone activation/remote-SIM-lock apps, and Motorola PAKS finance apps. Android's device-lock controller is disabled separately. Original system files are not deleted.

After reboot, all targeted packages were absent, no finance-controller role holder or device administrator remained, targeted processes/restart alarms were absent, and Wi-Fi/Play Store/Magisk still worked. This disables identified Android-level paths, not every undocumented firmware mechanism. No performance benchmark was run.

## Safe and risky afterward

- **Normally fine:** ordinary Play Store installs/updates and app auto-updates, Google sign-in, Wi-Fi/Bluetooth, and normal reboots. Some games can reject root or an unlocked bootloader.
- **Plan first:** Magisk framework upgrades, new modules, custom kernels, and Google Play **system** updates. Play system updates are not ordinary app updates and are not blocked by the Motorola updater module.
- **Avoid casually:** Motorola firmware/security/Android updates, Software Fix/Rescue, factory resets, slot changes, or disabling the blocking modules. These can erase configuration or replace root/boot components.
- **Do not relock with modified images.** Never restore another phone's calibration/security partitions.

Keeping old firmware retains its security weaknesses. Persistent root means normal reboot persistence, not survival of every reset or update.

Credit to Test DPC, DFRoot, KernelSU, Val Protocol, and Magisk authors. For reports, include model/build/patch/kernel/error text, with identifiers and keys redacted.
