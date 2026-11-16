# Prepare the device

This section turns a factory XT2617V into a development device: bootloader unlocked, persistent system access installed, set up as a Wi-Fi-only unit. The [walkthrough](walkthrough.md) is the complete tested procedure with the *why* behind each stage, and it marks every irreversible step. Read the [disclaimer](../reference/disclaimer.md) first.

Read [Android internals](../concepts/index.md) first. Every stage here assumes you know what a partition, a slot, and the boot chain are.

## The exact tested device

The low-level stages are **firmware-specific**. They have been carried out on two units with exactly these values. If yours differ, the procedure is not known to work for you — stop and don't treat it as validated.

| Item | Tested value |
| --- | --- |
| Model | Moto G Power 2026, Straight Talk, Walmart |
| Hardware model | **XT2617V** |
| Product (bootloader) | vegas / vegas26 |
| Android | 16 |
| Build | `W1WEOS36.48-22-3-3-4-2` |
| Security patch | 2026-04-01 |
| Kernel | `5.15.180-android13-8-...-ab14563692` |
| Active slot | `a` |

Verify with `getprop` ([first ADB session](../start/first-adb-session.md#ask-the-phone-about-itself)) before you start. The full table, both runs on record, and everything that has *not* been established are on the [validation page](validation.md).

## What you'll end up with

- An unlocked bootloader (`securestate: flashing_unlocked`), so the device runs builds and code you provide.
- Magisk persistent root, verified to survive reboots.
- A Wi-Fi-only setup with the carrier, partner-stub, telemetry and auto-update apps reversibly hidden by three system modules.
- Google Play available for installing your own tools.

Stock Motorola Android is kept throughout — no custom ROM. This is a factory build with system access added, which is exactly what you want as a development baseline.

## The risk, stated plainly

!!! danger "One step can brick the device"
    Preparing and flashing **LK** (the bootloader) is the high-risk step. If a bad LK stops the device reaching Fastboot, there is **no vendor-independent recovery** proven for this model. Unlocking also **erases** the device. Backups reduce risk but are not a guaranteed un-brick. Proceed only if you accept that a development device can, in the worst case, be lost.

## The stages

| # | Stage | Reversible? |
| --- | --- | --- |
| 1 | [First setup without a cellular plan](walkthrough.md#stage-1-first-setup-without-a-cellular-plan) | Yes |
| 2 | [Temporary system access](walkthrough.md#stage-2-temporary-system-access) | Yes (reboot clears it) |
| 3 | [Back up your original partitions](walkthrough.md#stage-3-back-up-your-original-partitions) | — (read only) |
| 4 | [If an update is staged](walkthrough.md#stage-4-if-an-update-is-staged) | Yes |
| 5 | [Prepare LK and the Magisk image](walkthrough.md#stage-5-prepare-lk-and-the-magisk-image) | Yes (files on PC only) |
| 6 | [Flash LK and unlock](walkthrough.md#stage-6-flash-lk-and-unlock) | **No — erases, can brick** |
| 7 | [Re-setup and install persistent root](walkthrough.md#stage-7-re-setup-and-install-persistent-root) | Mostly |
| 8 | [Configure the Wi-Fi dev device](walkthrough.md#stage-8-configure-the-wi-fi-dev-device) | Yes (modules) |

Start the [walkthrough](walkthrough.md).
