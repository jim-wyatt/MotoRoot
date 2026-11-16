# Your first ADB session

Everything on this page is **read-only**. Nothing here changes the phone. Its purpose is to get you comfortable with the tool you'll use for everything else.

!!! note "Not got the phone yet?"
    You can still read through this page. Come back and run the commands when it arrives. If you have *any* other Android phone lying around, most of this works on it too.

## What ADB is

**ADB** (Android Debug Bridge) is a client/server program. On your PC, `adb.exe` starts a small background server; on the phone, a daemon called `adbd` listens over USB. Every `adb` command you type is a message sent through that pair. The [concepts page](../concepts/adb-and-fastboot.md) goes deeper; for now, think of it as "a terminal into the phone".

## Enable USB debugging on the phone

The phone won't accept ADB until you turn it on. On a phone that has already been through setup:

1. **Settings → About phone**, tap **Build number** seven times. A toast says you're now a developer.
2. **Settings → System → Developer options**, turn on **USB debugging**.
3. Plug in the USB cable. Unlock the screen. A dialog asks **Allow USB debugging?** Tick *Always allow from this computer* and tap **Allow**.

(If the phone is still on its very first setup screen, the [walkthrough](../device/walkthrough.md#stage-1-first-setup-without-a-cellular-plan) covers how to get past it.)

## List connected devices

In the dev shell:

```powershell
& $adb devices -l
```

```text
List of devices attached
ZY22XXXXXX   device product:vegas_og_sys model:moto_g_power_2026 device:vegas26 transport_id:1
```

The second column is the state. You want exactly one line, and it must say **`device`**.

| State | Meaning |
| --- | --- |
| `device` | Connected and authorized. |
| `unauthorized` | The phone is waiting for you to tap **Allow** on its screen. |
| `offline` | USB connection exists but ADB isn't responding. Replug the cable, or try another port. |
| (nothing) | Windows doesn't see the phone. Check the cable is a data cable; try another port. |

!!! tip "The `&` and `$adb`"
    `$adb` holds the full path to the pinned `adb.exe`. In PowerShell, running a command from a variable needs the call operator `&` in front. That's all `& $adb` means. The guide uses this form everywhere so that you always run the *tested* version, not some other `adb` that happens to be on your PATH.

## Ask the phone about itself

Android exposes hundreds of **system properties**: read-only key/value pairs set at boot. `getprop` reads them.

```powershell
& $adb shell getprop ro.product.model
& $adb shell getprop ro.build.version.release
& $adb shell getprop ro.build.fingerprint
& $adb shell getprop ro.build.version.security_patch
& $adb shell getprop ro.boot.slot_suffix
```

`adb shell <command>` runs one command on the phone and prints its output. You should see something like `moto g power 2026`, `16`, a long fingerprint string, a date, and `_a`.

These exact values are what the preparation procedure checks before any low-level step. The [tested phone table](../device/index.md#the-exact-tested-device) lists what they must be.

## Open an interactive shell

```powershell
& $adb shell
```

Now you're *in* the phone's shell. The prompt changes to something like `vegas26:/ $`. Try:

```sh
id
uname -a
ls /system
cat /proc/cpuinfo | head
exit
```

`id` prints `uid=2000(shell)`. That's the **shell user**: a limited, unprivileged account. Remember this number; a development device lets you become `uid=0` when you need to, instead of being stuck as `shell`. (More in [System-level access](../concepts/system-access.md).)

## See the screen on your PC

```powershell
scrcpy
```

[scrcpy](https://github.com/Genymobile/scrcpy) mirrors the phone's screen in a window and lets you control it with your mouse and keyboard. It's invaluable during the root procedure when you need to tap something on the phone while reading instructions on the PC. Close it with ++ctrl+c++ in the terminal or by closing the window.

## Read the log

Android writes a continuous system log. Watching it is how developers debug almost everything.

```powershell
& $adb logcat -d | Select-Object -Last 30
```

`-d` dumps what's buffered and exits; without it, `logcat` streams forever (stop with ++ctrl+c++). Each line has a timestamp, process id, priority letter (V/D/I/W/E/F) and a *tag*. You'll use `logcat` later to see your own programs' output.

## Install an app

```powershell
& $adb install "$Work\Magisk-v31.1.apk"
```

Don't actually run this yet unless you're following the walkthrough. But that's all an APK install is from the command line: one command. `adb uninstall <package.name>` removes it.

## Stop the ADB server

```powershell
& $adb kill-server
```

Not required, but good hygiene before you plug the phone into another program (Android Studio, for example) that wants its own server.

## What you learned

- `adb devices` tells you whether you can talk to the phone, and the state column tells you what's wrong when you can't.
- `adb shell` runs commands on the phone as the limited `shell` user.
- `getprop` reads system properties; the guide uses them to verify the phone before anything risky.
- `logcat` is the system log.
- `scrcpy` mirrors the screen.

You're ready to read about [how the phone is put together](../concepts/index.md), or move on to [preparing the device](../device/index.md).
