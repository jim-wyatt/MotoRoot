# VedoTom

**A complete Android platform-development environment, built around one real device.**

**VedoTom is an independent, non-commercial, educational project.** It exists to teach how Android works on real hardware. It is not affiliated with Motorola, Lenovo, Google, MediaTek or any carrier, and it redistributes none of their software: everything vendor-made is downloaded by you, from its publisher, under its terms. The full statement is in the [disclaimer](reference/disclaimer.md).

Most Android learning happens on an emulator. Emulators are great, but they hide half of what makes a real device interesting: they boot differently, they already give you a root shell, and they never show you how a shipping phone is actually assembled from partitions, a boot chain, and a vendor's system image.

This project does the opposite. It sets up a full desktop toolchain and turns a **Moto G Power 2026 (XT2617V)** into a genuine **development device**: one you can read, modify, instrument, and build on at the system level, the way a platform engineer works with an AOSP engineering build.

If you have never typed `adb`, compiled a line of Java for Android, or wondered what a "bootloader" is, you are in the right place. These docs assume **no prior Android experience** and build up from there.

## What this gives you

<div class="grid cards" markdown>

-   **A reproducible toolchain**

    ---

    One script installs and hash-verifies the whole stack: JDK, Android SDK, NDK, platform-tools, Android Studio, and inspection tools.

    [Set it up](start/index.md)

-   **A real device to develop on**

    ---

    Learn how Android boots, then give your device the system-level access an emulator has by default, so you can build and test platform-level code on real hardware.

    [Prepare the device](device/index.md)

-   **The platform, explained**

    ---

    Partitions, A/B slots, the boot chain, the app sandbox, and system modules, in plain language with diagrams.

    [Android internals](concepts/index.md)

-   **Things to build**

    ---

    A small program that drives Android's own system APIs, a system module, native code compiled for the device's CPU, Frida hooks and Perfetto traces of anything running, and your first Studio app.

    [Develop](develop/index.md)

</div>

## Why a development device needs system access

When you launch an Android emulator, you can run `adb root` and immediately get a root shell. That access is what lets you read system partitions, install system-wide modules, and test privileged code. A retail phone ships locked down: it runs one vendor build and gives you only an unprivileged shell.

To use this phone as a true development target, you give it that same capability:

1. **Unlock the bootloader** — the official, vendor-supported switch (`fastboot oem unlock`) that lets a device run builds you provide instead of only the factory one. Every Pixel and most development devices support this directly; on this model it takes an extra preparation step, documented in full.
2. **Install a superuser manager (Magisk)** — so you can run privileged code and load system modules, cleanly and reversibly, without modifying the read-only system image.

This is standard platform-development practice on hardware you own. It is not a modification you make to someone else's device, and it is not about defeating protections: unlocking deliberately **erases the device** precisely so that system access always implies a clean, consenting wipe.

!!! warning "This changes real hardware"
    Unlocking erases the device, and the low-level preparation on this model can, in the worst case, leave it unbootable. The procedure has been carried out on two units of one firmware build; see the [validation notes](device/validation.md) for what that does and doesn't establish. Work through [Android internals](concepts/index.md) first, then follow the [walkthrough](device/walkthrough.md), which marks every point of no return. Use of this project is subject to the [disclaimer](reference/disclaimer.md).

## How the repository is organized

```text
VedoTom/
├── device/   Helper programs, three reversible modules, the Magisk prep script
├── dev/      One script installs and verifies every tool, pinned by hash
├── docs/     These pages, including the full device-preparation procedure
├── work/     Your downloads, backups, and build outputs (never committed)
└── .github/  CI that builds and publishes this site
```

The device-preparation procedure is the [walkthrough](device/walkthrough.md) in these pages: every command, with the reasoning, and with the [validation page](device/validation.md) recording exactly what has been tested.

## A note on the device's data

Your device's backup images and identifiers are **yours and private** — the images can contain per-unit radio calibration. This repo has a [git safety net](reference/git-workflow.md) that keeps them out of version control automatically. Keep your backups somewhere safe; they are how you restore the device.

---

*The device-preparation procedure is derived from the guide created and first tested by [parsimo2010](reference/credits.md) (MIT). This project integrated it, carried it out on a second unit, and built the development environment and these docs around it. See the [credits](reference/credits.md) and the [disclaimer](reference/disclaimer.md).*
