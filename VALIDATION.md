# Validation and limits

## Reference device results

Performed on one owner-authorized phone with the exact configuration in README.md:

- Test DPC setup reached Android's home screen without a purchased carrier plan. Its device ownership was cleared through its service interface and the app removed.
- DFRoot 4.7 and KernelSU 3.3.1 produced ADB root on the original kernel.
- Eighteen private backup image hashes matched their phone copies.
- A completed slot B OTA was cancelled through UpdateEngine resetStatus. Next boot returned to A and update snapshots were removed.
- Val Protocol at commit dc7f41f9b1a32da1a78ef327bb62d2bef17d7bd0 produced a patched LK passing static verification. Other subimage payloads and certificates remained unchanged.
- Modified LK flashed to lk_a and booted into Fastboot. After owner confirmation, securestate was flashing_unlocked.
- Bootloader Fastboot rejected the Magisk image. Fastbootd could not open init_boot_a.
- After another setup and temporary-root pass, rooted Android wrote the prepared init_boot_a image and its readback hash matched.
- Magisk additional setup and multiple full reboots completed. ADB returned uid=0(root) in u:r:magisk:s0, Magisk 31.1 ran, and no KernelSU daemon was present.
- After reboot, the updater module removed Motorola Software Update from the package list; the carrier module removed all 22 targeted APK packages. DeviceLockController stayed disabled, the finance-controller role had no holder, and no device administrator remained.
- Google sign-in, Play Store launch, and validated Wi-Fi internet worked. No specific game installation or benchmark was independently performed.

## What has not been established

- Other models, builds, patches, kernels, or slot configurations.
- Guaranteed emergency recovery if LK fails before Fastboot starts.
- Tested stock-image restore after boot failure or a full OS backup.
- A reliable fallback OS on slot B, cellular network unlocking, or carrier connectivity after debloat.
- Defeat of every undocumented hardware or firmware restriction.
- Measured speed improvement, universal game compatibility, or Play Integrity compliance.
- Behavior of future OTA/Google Play system updates, Magisk upgrades, or factory resets.

## Publication artifacts

The phone operations above were tested in the reference session. The newly packaged preparation script is a parameterized adaptation of the successful commands; its syntax was checked without reinstalling root on the already-configured phone. It is not a separately validated second-phone procedure.

The release contains the same module contents tested on the phone, a generator, helper sources, and compiled helper DEX files. It excludes device images, keys, third-party APKs, personal data, and raw logs. SHA256SUMS.txt identifies kit files; publisher-provided hashes are not an independent guarantee of safety.
