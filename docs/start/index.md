# Getting started

This section takes you from "I have a Windows PC and a device in a box" to "I have a working Android development environment and I can talk to the device from a terminal."

Follow the three pages in order:

1. **[Set up the dev environment](setup.md)** — run one script that installs and verifies the whole toolchain. About 20 minutes, mostly downloads.
2. **[Tour the repository](repo-tour.md)** — what each folder is for, and which files you'll actually touch.
3. **[Your first ADB session](first-adb-session.md)** — connect the device and run harmless, read-only commands to get comfortable with the main tool.

## What you need

| Item | Notes |
| --- | --- |
| Windows 10 or 11 PC | 64-bit. About 15 GB free for the full toolchain. |
| The device | Moto G Power 2026, **XT2617V** (the Walmart Straight Talk variant). The low-level preparation is firmware-specific; see [the exact tested device](../device/index.md#the-exact-tested-device). |
| A USB **data** cable | Some cables only charge. The one in the box works. |
| Administrator rights | The USB driver, JDK and Android Studio installers ask for them. |
| No cellular plan required | This is a Wi-Fi development device. You don't need a SIM or an activated plan. |

## What "beginner" means here

You should be comfortable opening PowerShell, running commands you're given, and reading an error message. Everything else is explained as it comes up. Unfamiliar term? The [glossary](../reference/glossary.md) has it.

You do **not** need to know Java, Kotlin, Linux, or anything about Android yet. That's what the rest of the site is for.
