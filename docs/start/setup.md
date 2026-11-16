# Set up your PC

One script installs everything. It is safe to run more than once: each step checks whether its work is already done and skips it.

## 1. Get the repository

If you don't have Git yet, download the repository as a ZIP from GitHub and extract it to a folder on a **local drive** (not a network share or a WSL path; Python virtual environments break on those). The conventional location is `C:\Users\<you>\OtomDev`.

If you do have Git:

```powershell
git clone https://github.com/jim-wyatt/OtomDev.git $env:USERPROFILE\OtomDev
cd $env:USERPROFILE\OtomDev
```

## 2. Download the Motorola USB driver

This is the one download the script can't do for you, because Motorola's site has no stable direct link. Go to [Motorola's USB driver page](https://en-us.support.motorola.com/app/usb-drivers), download the **64-bit Windows** installer, and save it as:

```text
OtomDev\work\Motorola_Mobile_Drivers_64bit.msi
```

Create the `work` folder if it doesn't exist. The script checks that the file is genuinely signed by Motorola Mobility before it trusts it.

!!! info "Why a driver at all?"
    Windows can talk ADB to the phone without it, but **Fastboot** (the bootloader mode you'll use to unlock) needs Motorola's driver. Without it you get "error 28" and an empty device list at the worst possible moment. Install it now.

## 3. Run the bootstrap

Open PowerShell **as yourself** (not as administrator; installers will ask for elevation when they need it) in the repository folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\dev\Bootstrap-DevEnv.ps1 -AndroidStudio -AcceptAndroidSdkLicenses
```

- `-AndroidStudio` also installs the full IDE (about 1.5 GB). Leave it off if you only want the command-line tools; you can add it later.
- `-AcceptAndroidSdkLicenses` accepts [Google's Android SDK terms](https://developer.android.com/studio/terms) for you. Read them first. Without the flag, the script asks you to review them interactively.

Expect a few Windows **User Account Control** prompts as the JDK, the USB driver, 7-Zip and Android Studio install. The whole run takes 10–30 minutes depending on your connection; the NDK download is the slow part.

??? note "What the script installs, exactly"
    Everything is pinned to a specific version in `dev/toolchain.json`, and every download is hash-checked before it's used.

    | Category | Tools |
    | --- | --- |
    | Java | Microsoft OpenJDK 21 |
    | Android SDK | Command-line tools, Platform Tools, the Android 16 platform (API 36), Build Tools 36.1, NDK 30 |
    | IDE | Android Studio (optional), VS Code configuration |
    | Phone tools | Google Platform Tools **37.0.1** (the exact version the procedure was tested with), scrcpy |
    | Inspection | jadx, apktool, 7-Zip |
    | Device inputs | The exact DFRoot, KernelSU and Magisk APKs the procedure uses, Google's Test DPC QR image, Val Protocol at its tested commit |
    | Python | Two virtual environments: `work\.venv` for the bootloader tooling, `dev\.venv-docs` for this site |
    | Safety | A Git pre-commit hook that blocks device images and identifiers |

    Nothing in this step talks to a phone.

## 4. Open the dev shell

From now on, every terminal you use for this project starts with one line:

```powershell
. .\dev\Enter-DevShell.ps1
```

(That's a dot, a space, then the path. "Dot-sourcing" runs the script *in your current window* so the variables it sets stay available.)

It prints a status block like this:

```text
OtomDev dev shell
adb (pinned)   Version 37.0.1-15733141
java           openjdk version "21.0.13.0.2" 2026-10-22 LTS
android cli    1.1.16919734
build-tools    36.1.0
ndk            30.0.16248370
python         Python 3.12.10
scrcpy         scrcpy 5.0.1
jadx           1.5.6
gh             gh version 2.104.0
Device inputs: verified
Variables: $Work $adb $fb $Backup $py   Commands: docs, apktool, r8d8, ...
```

If you use **VS Code**, open the repository folder and a new terminal (++ctrl+shift+grave++) does this automatically; the project configures a "OtomDev dev shell" terminal profile.

## 5. Prove it works

```powershell
.\dev\Test-DevEnv.ps1
```

This runs a few dozen checks that actually *use* each tool: it compiles Java, produces Android bytecode, decompiles it again, cross-compiles a C program for the phone's CPU, and re-verifies every pinned download. The last line should read `0 failed`. If anything fails, the [troubleshooting page](../reference/troubleshooting.md) covers the common causes.

!!! tip "Keep Android Studio closed when working with the phone"
    Android Studio starts its own, newer `adb` server in the background. Two different `adb` versions fighting over one phone can drop the connection in the middle of an operation. Use the dev shell's `$adb` for phone work, and open Studio only for app development.

Next: [Tour the repository](repo-tour.md).
