# Your first session

First a tour of the repository, so you know where things are. Then a first session with `adb`, the tool you'll use for nearly everything on the phone, using only commands that change nothing.

## Tour the repository

```text
aosp-academy/
├── aosp-academy            launcher for Linux and macOS (./aosp-academy <command>)
├── aosp-academy.cmd        launcher for Windows (.\aosp-academy <command>)
├── aosp_academy/           the command line, one module per area
│   ├── cli.py                every command and option
│   ├── setup.py check.py     the workstation: install, and test end to end
│   ├── env.py tools.py       the shell, env, docs, apktool, d8, adb-wifi; where each tool is
│   ├── fetch.py deploy.py    the device node: fetch an image, deploy and report
│   ├── gsi.py                DSU: install, boot, back to stock, discard
│   ├── device.py devtest.py  the phone: settings, inventory, traces, Frida; the device test
│   ├── adb.py core.py        the rules for talking to the phone; paths, pins, downloads
│   ├── stock.py              the stock system's artifacts
│   └── image.py              the build node: inputs, setup, sync, apply, build
├── toolchain.json          every pin, in one place
├── image/                  the system image (the build node's side)
│   ├── product/aospacademy/gsi/   the aospacademy_arm64 product: makefiles, overlays, first-boot service, prebuilt app list
│   ├── patches/                   our diffs against upstream AOSP projects
│   └── build/                     bash wrappers around AOSP (setup, sync, verify, apply, build) and the Containerfile
├── stock/                  the stock system's preparation (the device node's side)
│   ├── helpers/              two small Java programs and their compiled .dex files
│   └── modules/              seven Magisk module ZIPs, their manifests and scripts, the builder and its test
├── tests/                  unit tests for the command line (no phone, no network)
├── docs/                   this site; zensical.toml at the root configures it
├── .githooks/              the pre-commit hook that keeps device data out, and its test
├── .github/workflows/      CI: the fast checks, and building and publishing this site
├── .vscode/                terminal profile, tasks, recommended extensions
├── LICENSE  NOTICE.md  DISCLAIMER.md  README.md  DEVELOPMENT.md
└── work/                   YOURS: everything downloaded, generated or private. Git-ignored in full.
    ├── platform-tools/       the pinned adb and fastboot
    ├── tools/ cache/         pinned JARs (R8, apktool), jadx; downloads in progress
    ├── .venv/ .venv-frida/ .venv-docs/   Python for Val Protocol, Frida's PC tools, this site
    ├── *.apk val-protocol/   the device procedure's inputs
    ├── device-tools/         frida-server, the F-Droid APK; on the build node, the Fossify APKs
    │   └── gsi/own/            the newest image (fetched here on the device node; built here on the build node)
    ├── private-backups/      your phone's original partition images, made in walkthrough stage 3
    ├── device-info/ traces/  hardware inventories and Perfetto traces (private)
    ├── remote-build.json     where the build node is (fetch --save)
    ├── wifi.json             the Wi-Fi network deploy joins (optional, you write it)
    └── adb_keys              on the build node: the PCs the image trusts (optional)
```

### The folders that matter

**`image/`** is where the environment changes. Everything that makes `aospacademy_arm64` differ from AOSP's own `aosp_arm64` is here and nowhere else: the product definition, a handful of patches, and the list of prebuilt apps (the APKs themselves are pinned in `toolchain.json` and downloaded, never committed). The build node copies it into its AOSP tree before every build. [What's in the image](../environment/image.md) goes through it.

**`stock/`** belongs to the first half of the bootstrap: the stock system's preparation. Everything here is generic to the model, never to your unit, which is why it can be committed. The helpers are a few lines of Java each ([system helpers](../device/helpers.md)). The modules are generated from their JSON manifests, so to change what one hides you edit a manifest and rebuild ([system modules](../device/modules.md)).

**`work/`** is yours, and private. Every download and every file the commands and the device procedure create goes here. Git ignores the folder in its entirety, and the pre-commit hook blocks it as a second line of defence. **Back up `work/private-backups/` somewhere safe that isn't a public cloud share**: it is the only way to restore the phone's own system if something goes wrong.

**`toolchain.json`** pins every version and hash. This matters more here than in most projects: the device procedure was validated with specific versions, and a newer Magisk or `adb` might behave differently in ways nobody has tested on this model. Pinning means your environment matches the one the procedure was proven on, and that someone else can reproduce yours exactly. [Pins](../reference/pins.md) explains each section.

**`aosp_academy/`** is the code behind every command. The [command reference](../reference/cli.md) lists them all, and `aosp-academy --help` (or `aosp-academy <command> --help`) prints the same from the code.

## Your first ADB session

Everything below is **read-only**: nothing here changes the phone. Its purpose is to get you comfortable with the tool you'll use for everything else. Run it in the shell from `aosp-academy shell`, so that `adb` is the pinned, tested version.

!!! note "Not got the phone yet?"
    You can still read through this part, and come back when it arrives. If you have any other Android phone lying around, most of it works on that too.

### What ADB is

**ADB** (Android Debug Bridge) is a client/server program. On your PC, `adb` starts a small background server; on the phone, a daemon called `adbd` listens over USB. Every `adb` command you type is a message sent through that pair. [ADB and Fastboot](../concepts/adb-and-fastboot.md) goes deeper; for now, think of it as "a terminal into the phone".

### Enable USB debugging

The phone won't accept ADB until you turn it on. On the stock system, after first setup:

1. **Settings → About phone**, tap **Build number** seven times. A message says you're now a developer.
2. **Settings → System → Developer options**, turn on **USB debugging**.
3. Plug in the USB cable and unlock the screen. A dialog asks **Allow USB debugging?** Tick *Always allow from this computer* and tap **Allow**.

If the phone is still on its very first setup screen, the [walkthrough](../device/walkthrough.md) covers how to get past it without a cellular plan. This project's image has USB debugging on already; a PC whose key isn't built into the image gets the same **Allow** prompt after each deploy.

### List connected devices

```text
adb devices -l
```

```text
List of devices attached
ZY22XXXXXX   device product:vegas_og_sys model:moto_g_power_2026 device:vegas26 transport_id:1
```

The first column is the serial number (yours is private: don't paste it anywhere public). The second is the state. You want exactly one line, and it must say **`device`**: every `aosp-academy` command that talks to the phone checks for exactly one authorized device and stops otherwise.

| State | Meaning |
| --- | --- |
| `device` | Connected and authorized. |
| `unauthorized` | The phone is waiting for you to tap **Allow** on its screen. |
| `offline` | A USB connection exists but ADB isn't responding. Replug the cable, or try another port. |
| (nothing) | The PC doesn't see the phone. Check that the cable is a data cable; try another port. |

### Ask the phone about itself

Android exposes hundreds of **system properties**: key/value pairs, most of them set at boot and read-only. `getprop` reads them.

```text
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.fingerprint
adb shell getprop ro.build.version.security_patch
adb shell getprop ro.boot.slot_suffix
```

`adb shell <command>` runs one command on the phone and prints its output. On the stock system you'll see something like `moto g power 2026`, `16`, a long fingerprint string, a date, and `_a`. In this project's image, the release is `17` and the fingerprint names `aospacademy_arm64`.

These are the values the preparation procedure checks before every low-level step, and `stock magisk-image` refuses to run if they differ from the tested device's. [The device](../device/index.md) lists what they must be.

### Open an interactive shell

```text
adb shell
```

Now you're in the phone's shell, and the prompt changes to something like `vegas26:/ $`. Try:

```sh
id
uname -a
ls /system
head /proc/cpuinfo
exit
```

`id` prints `uid=2000(shell)`. That's the **shell user**: a limited, unprivileged account. A development device lets you become `uid=0` (root) when you need to, instead of being stuck as `shell`. On the stock system that goes through Magisk (`su -c '<command>'`); in this project's image, which is a `userdebug` build, AOSP's own `su 0 <command>` works, and so does `adb root`. [System-level access](../concepts/system-access.md) explains the difference.

### See the screen on your PC

```text
aosp-academy device mirror
```

[scrcpy](https://github.com/Genymobile/scrcpy) mirrors the phone's screen in a window and lets you control it with your mouse and keyboard, through the pinned `adb`. Anything after `mirror` is passed to scrcpy (for example `aosp-academy device mirror --turn-screen-off`). It's invaluable during the walkthrough, when you need to tap something on the phone while reading instructions on the PC. Close the window, or press ++ctrl+c++ in the terminal, to stop.

### Read the log

Android writes a continuous system log. Watching it is how developers debug almost everything.

```text
adb logcat -t 30
```

`-t 30` prints the last 30 lines and exits; `adb logcat` alone streams forever (stop it with ++ctrl+c++). Each line has a timestamp, a process id, a priority letter (V/D/I/W/E/F) and a *tag*. `adb logcat -b crash` shows only the crash buffer, which on a healthy system is empty. You'll use `logcat` later to see your own programs' output.

### Install an app

```text
adb install work/Magisk-v31.1.apk
```

Don't actually run this one unless you're following the walkthrough. But that is all an APK install is from the command line: one command. `adb uninstall <package.name>` removes it.

### Stop the ADB server

```text
adb kill-server
```

Not required, but good hygiene before you hand the phone to another program that wants its own server.

### What you learned

- `adb devices` tells you whether you can talk to the phone, and the state column tells you what's wrong when you can't.
- `adb shell` runs commands on the phone as the limited `shell` user; root takes `su`, in the form the running system has.
- `getprop` reads system properties; the walkthrough uses them to verify the phone before anything risky.
- `logcat` is the system log.
- `aosp-academy device mirror` shows and controls the screen.

From here: [how Android works](../concepts/index.md) explains what you just looked at, the [walkthrough](../device/walkthrough.md) prepares the phone, and [develop apps](../apps/index.md) shows what the finished device offers your own projects.
