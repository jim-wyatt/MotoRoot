# Make it an engineering device

The [walkthrough](walkthrough.md) ends with a rooted retail build. Google's own engineers don't work on retail (`user`) builds; they use `userdebug` builds, which report themselves as debuggable and let tooling attach to anything. This page closes most of that gap with two small, reversible modules, adds ADB over Wi-Fi, and puts a Linux userland on the device. Everything here is optional and undone by disabling a module and rebooting.

## The two development modules

Both are [script modules](../concepts/magisk-modules.md#script-modules): a `post-fs-data.sh` that sets one system property early in boot, before `zygote` and `adbd` start. They live in `device/modules/` next to the three Wi-Fi modules and are built the same way.

| Module | Sets | What you get | Mind |
| --- | --- | --- | --- |
| `dev_debuggable` | `ro.debuggable=1` | Every app is debuggable: Android Studio can attach to any process, `run-as <package>` works for every package, `am set-debug-app` accepts anything, profilers and Frida treat the device as an engineering build | A few apps refuse to run on debuggable systems. `adb root` still does **not** work: the shipped `adbd` is compiled to drop root on a user build, and this module doesn't replace it. Use `su -c`. |
| `dev_adb_tcp` | `service.adb.tcp.port=5555` | `adbd` listens on TCP from boot, so `adb connect <phone-ip>:5555` works with no cable and no pairing dialog | Only PCs whose ADB key you've approved on the phone get a shell, but the port is reachable by anyone on the network. Keep it disabled on networks you don't control. |

Install both (or either) from the repository root, then reboot:

```powershell
& $adb push .\device\modules\dev-debuggable.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/dev-debuggable.zip'
& $adb push .\device\modules\dev-adb-tcp.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/dev-adb-tcp.zip'
& $adb reboot
```

After the reboot, verify:

```powershell
& $adb shell getprop ro.debuggable               # 1
& $adb shell getprop service.adb.tcp.port        # 5555
& $adb shell run-as com.android.vending id       # works on any package now; it would refuse on stock
& $adb root                                      # still "adbd cannot run as root in production builds": expected
```

!!! note "If the device won't boot with a module enabled"
    Hold **Volume Down** while it boots. Magisk's safe mode starts with every module disabled, so you can remove the culprit (`su -c 'touch /data/adb/modules/<id>/disable'`) and reboot normally. Neither of these modules has needed that, but it's the escape hatch for any module.

## ADB over Wi-Fi

With `dev_adb_tcp` installed, the dev shell's `adbwifi` command reads the phone's Wi-Fi address over USB, then connects to it:

```powershell
adbwifi                      # → connected to 192.168.x.y:5555
& $adb devices -l            # the phone now appears twice: USB and TCP; unplug and the TCP one stays
```

Android Studio lists the TCP device like any other. If you'd rather not run the module, Android's own path is **Developer options → Wireless debugging → Pair device with pairing code** and `adb pair`, which has to be repeated after each reboot; or `& $adb tcpip 5555` over USB, which lasts until the next reboot.

## Linux on the device

Android 16 ships a built-in Linux Terminal (a Debian VM on the Android Virtualization Framework), but this SoC doesn't have the framework: no hypervisor properties, no `/dev/kvm`, no `com.android.virt` APEX, no Terminal app. The [hardware inventory](hardware.md) records the check.

The route that works everywhere is **Termux**, a terminal and package manager that runs as an ordinary app, plus `proot-distro`, which runs a real Debian userland inside it with no root required. The bootstrap downloads the Termux APK from its GitHub release, pinned by hash (the Play Store build has lagged for years); install it, then set up Debian from inside Termux:

```powershell
& $adb install "$Work\device-tools\termux-app_v0.118.3+github-debug_universal.apk"
```

```sh
pkg update && pkg upgrade -y
pkg install -y proot-distro
proot-distro install debian        # ~100 MB download
proot-distro login debian          # a Debian shell; exit returns to Termux
```

Inside Debian, `apt update && apt install -y build-essential python3 git` gives you a normal development box on the phone. `termux-setup-storage` grants Termux access to shared storage if you want it. Don't mix in Termux add-ons from the Play Store or F-Droid: they must match this GitHub build's signing key. With root, a full chroot (rather than proot) is possible and faster; it's a later project.

## Instrumentation and tracing

The device is now ready for the two tools that make a rooted phone worth having: [Frida](../develop/instrumentation.md) to hook and trace any process, and [Perfetto](../develop/tracing.md) for system-wide traces. Both are set up by the bootstrap and driven from the dev shell.

## Moving to Android Studio

Once this page is done, day-to-day app work belongs in Android Studio; this repository stays the bootstrap, the reference and the documentation. [Your first app in Android Studio](../develop/android-studio.md) has the hand-off details: the two `adb` copies are kept at the same version so they never fight, the Wi-Fi device shows up in Studio's device list, and with `dev_debuggable` Studio's *Attach Debugger to Android Process* lists everything.

## Undoing any of it

```powershell
& $adb shell su -c 'touch /data/adb/modules/dev_debuggable/disable'   # back to ro.debuggable=0
& $adb shell su -c 'touch /data/adb/modules/dev_adb_tcp/disable'      # USB only
& $adb reboot
& $adb uninstall com.termux                                           # removes Termux and its Debian
```
