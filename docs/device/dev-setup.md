# Make it an engineering device

The [walkthrough](walkthrough.md) ends with a rooted retail build. Google's own engineers don't work on retail (`user`) builds; they use `userdebug` builds, which report themselves as debuggable and let tooling attach to anything. This page closes most of that gap with two small, reversible modules, adds ADB over Wi-Fi, and puts a Linux userland on the device. Everything here is optional and undone by disabling a module and rebooting.

## The two development modules

Both are [script modules](../concepts/magisk-modules.md#script-modules): a `post-fs-data.sh` that sets system properties early in boot, before `zygote`, `system_server` and `adbd` start. They live in `device/modules/` next to the three Wi-Fi modules and are built the same way. Every claim in this table was checked on unit 2; the [validation page](validation.md#engineering-device-tooling-unit-2-2026-11-16) has the measurements.

| Module | Sets | What you get | Mind |
| --- | --- | --- | --- |
| `dev_debuggable` | `ro.debuggable=1` and `ro.build.type=userdebug` | The system reports itself as an engineering build. Verified effect: Perfetto's heap profilers (Java heap dumps, native `heapprofd`) and other tooling that checks the build type can target **any** app, not only profileable ones; on stock they refuse with `not profileable`. Tools that gate on `ro.debuggable` behave as on a userdebug build. | Some apps refuse to run on a debuggable or userdebug system. Verified **not** to change on Android 16: the debugger still attaches only to debuggable apps (no JDWP for the rest), `run-as` still checks the app's own flag, and `adb root` still fails (it makes `adbd` abort and restart as `shell`; don't run it). Use `su -c`. |
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
& $adb shell getprop ro.build.type               # userdebug
& $adb shell getprop service.adb.tcp.port        # 5555
& $adb shell su -c 'ss -ltn | grep :5555'        # adbd listening on TCP
```

The proof that the userdebug report does something useful is a heap dump of an app that isn't yours, which stock refuses:

```powershell
'buffers: { size_kb: 32768 }
data_sources: { config { name: "android.java_hprof" java_hprof_config { process_cmdline: "com.android.settings" } } }
duration_ms: 3000' | Set-Content "$Work\traces\hprof.pbtxt" -Encoding ascii
.\dev\Trace-Device.ps1 -Config "$Work\traces\hprof.pbtxt" -Name settings-heap   # ~25 MB trace; open it at ui.perfetto.dev
```

!!! note "If the device won't boot with a module enabled"
    Hold **Volume Down** while it boots. Magisk's safe mode starts with every module disabled, so you can remove the culprit (`su -c 'touch /data/adb/modules/<id>/disable'`) and reboot normally. Neither of these modules has needed that, but it's the escape hatch for any module.

## ADB over Wi-Fi

With `dev_adb_tcp` installed, the dev shell's `adbwifi` command reads the phone's Wi-Fi address over USB, then connects to it:

```powershell
adbwifi                      # → connected to 192.168.x.y:5555
& $adb devices -l            # the phone now appears twice: USB and TCP; unplug and the TCP one stays
```

`adbwifi` first checks that the PC has an address on the phone's network and says so if not; two routers, a guest Wi-Fi, or a wired PC on a different subnet from the Wi-Fi are the usual reasons a connect would otherwise just time out. Android Studio lists the TCP device like any other. If you'd rather not run the module, Android's own path is **Developer options → Wireless debugging → Pair device with pairing code** and `adb pair`, which has to be repeated after each reboot; or `& $adb tcpip 5555` over USB, which lasts until the next reboot.

## Linux on the device

Android 16 ships a built-in Linux Terminal (a Debian VM on the Android Virtualization Framework), but this SoC doesn't have the framework: no hypervisor properties, no `/dev/kvm`, no `com.android.virt` APEX, no Terminal app. The [hardware inventory](hardware.md) records the check.

The route that works everywhere is **Termux**, a terminal and package manager that runs as an ordinary app, plus `proot-distro`, which runs a real Debian userland inside it with no root required. The bootstrap downloads the Termux APK from its GitHub release, pinned by hash (the Play Store build has lagged for years). Install it, open it once (the first launch unpacks its base system), then set everything up from inside the app:

```powershell
& $adb install "$Work\device-tools\termux-app_v0.118.3+github-debug_universal.apk"
& $adb shell am start -n com.termux/.app.TermuxActivity
```

```sh
pkg update && pkg upgrade -y
pkg install -y proot-distro openssh
proot-distro install debian        # ~100 MB download
passwd                             # a password for SSH logins (or add your key; below)
sshd                               # Termux's SSH server, port 8022; rerun after a reboot
proot-distro login debian          # a Debian shell; exit returns to Termux
```

Inside Debian, `apt update && apt install -y build-essential python3 git` gives you a normal development box on the phone. `termux-setup-storage` grants Termux access to shared storage if you want it. Don't mix in Termux add-ons from the Play Store or F-Droid: they must match this GitHub build's signing key.

Termux deliberately refuses package operations from a root shell, and this project doesn't work around that: the setup above is typed in the app, and the PC side only forwards a port.

### From the PC, over the cable

Termux's `sshd` listens on port 8022. Forwarded through ADB, it is reachable as `localhost:8022` from the PC whatever network either side is on, so the dev shell's `Connect-Debian` opens an SSH session that lands straight in Debian (`Connect-Debian -Termux` stops at the Termux shell):

```powershell
Connect-Debian               # = adb forward tcp:8022 tcp:8022; ssh -p 8022 localhost 'proot-distro login debian'
```

The username doesn't matter to Termux's `sshd`; the password is the one from `passwd`. To log in with your key instead, put the PC's public key into Termux: `& $adb push "$env:USERPROFILE\.ssh\id_ed25519.pub" /sdcard/pc.pub`, then in Termux `termux-setup-storage` once, and `mkdir -p ~/.ssh && cat ~/storage/shared/pc.pub >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`. `sshd` stops when Termux is closed or the phone reboots; run it again in the app (the Termux:Boot add-on from the same GitHub release can start it automatically). With root, a full chroot rather than proot is possible and faster; it's a later project.

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
