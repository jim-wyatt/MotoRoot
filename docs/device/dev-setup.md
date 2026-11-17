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

## Apps without Google: F-Droid

A development device is a good place to stay out of Google's ecosystem as far as the hardware allows. The device ships with Play services and the Play Store in the system image (this project does not remove them: too much of the stock system expects them), but nothing requires you to sign in to a Google account, and installing apps doesn't need the Store at all.

**F-Droid** is the free-software app store: a catalogue of open-source apps built from source on F-Droid's own build servers, with no account, no tracking and no proprietary dependencies. The bootstrap downloads the pinned client APK into `work\device-tools\`, hash-checked like everything else, and the self-test additionally verifies the APK's signing certificate against the fingerprint F-Droid publishes (`43238d51…ccab`, on [its signing-keys page](https://f-droid.org/docs/Release_Channels_and_Signing_Keys/)). The PGP signature F-Droid ships for the same file (`F-Droid.apk.asc`, key `37D2 C987 89D8 3119 4839 4E3E 41E7 044E 1DBA 2E89`) was verified when the pin was recorded.

```powershell
& $adb install "$Work\device-tools\org.fdroid.fdroid_2000053.apk"
& $adb shell am start -n org.fdroid.fdroid/org.fdroid.IconActivity   # first launch fetches the catalogue (needs Wi-Fi)
```

Open it, let it download the repository index, and install apps from there. From then on F-Droid updates itself and the apps it installed. Two cautions:

- **Leave Termux alone.** The Termux in this project is the GitHub build, signed with a different key from F-Droid's build; F-Droid will offer its own Termux and add-ons, and Android refuses to update an app across signing keys. Keep installing Termux and its add-ons from the GitHub release, or uninstall it first and switch wholesale to F-Droid's builds.
- **Android's "install unknown apps" prompt** appears the first time F-Droid installs something. That is the per-app permission F-Droid needs in order to act as an installer; granting it to F-Droid is the point.

#### Installing from F-Droid without touching the screen, and offline maps over ADB

F-Droid has no command line, but its repository is verifiable by hand, which is how Organic Maps (offline OpenStreetMap maps, Apache-2.0) went onto the validated device: download `https://f-droid.org/repo/entry.jar`, check its signature with `jarsigner -verify` and `keytool -printcert -jarfile` against F-Droid's certificate (the same `43238d51…` as the client), download `index-v2.json` and check it against the SHA-256 the signed entry names, then take the package's APK hash and signer from the index and compare them with the downloaded APK (`sha256sum`, `apksigner verify --print-certs`). Install with `& $adb install -i org.fdroid.fdroid <apk>` so F-Droid records itself as the installer and keeps the app updated.

Organic Maps keeps its region catalogue in the APK (`assets/countries.json`: ids, sizes, and the data version `v`) and serves the files from `https://cdn.organicmaps.app/maps/<v>/<id>.mwm`; they belong in `/sdcard/Android/data/app.organicmaps/files/<v>/`. Three things bite when pushing a whole country over ADB: region ids can contain spaces (`US_West Virginia`), `adb` reads standard input and empties a `while read` loop unless every call gets `</dev/null`, and the ADB shell user cannot write into another app's `Android/data` folder on Android 16, so push to `/data/local/tmp` and let root `mv` the file in and `chown` it to the app's uid with group `ext_data_rw`. The 154-file United States set (15.5 GB) went on that way in about 25 minutes; keep the downloaded files in `work\` so a second device is a push, not a download.

### Hiding the Google apps

With F-Droid in place, the sixth module, `google-debloat`, hides the Google layer that a development device doesn't need, the same reversible way the carrier modules work (an empty overlay over each app's directory; nothing on the firmware partitions changes). `manifests/google-debloat.json` lists all 28 packages in four groups:

| Group | What goes |
| --- | --- |
| store | Play Store, and the two Play auto-install hooks that pull carrier apps in at setup |
| search-assistant | the Google app (search bar, Assistant, Circle to Search), both hotword enrolment services, Gemini |
| consumer-apps | Chrome, Gmail, YouTube, YouTube Music, Maps, Photos, Drive, Meet, Google TV, Google Home, Calendar, Google Fi |
| account-extras | account restore at setup, partner setup, Location History, Family Link, the feedback reporter, Android Auto, cross-device streaming, Google's carrier Wi-Fi, ARCore |

What stays, deliberately: Play services and the services framework (too much of the stock system binds to them), WebView and its shared Trichrome library, Gboard (the only keyboard), Contacts, Messages, Files, the Google dialer, speech services, TalkBack and Switch Access, the eSIM manager, Device Health Services, the wallpaper picker, and everything delivered as a Mainline APEX. Nothing in this module needs a Google account, and nothing left behind asks for one.

One detail matters for eight of these apps: the Play Store had updated them, so a newer copy lived in `/data/app` beside the system one. Hide only the system copy and Android keeps the update as an ordinary app. `pm uninstall-system-updates` drops the update first, so the hidden copy is the only copy:

```powershell
& $adb push .\device\modules\google-debloat.zip /data/local/tmp/google-debloat.zip
& $adb shell su -c 'magisk --install-module /data/local/tmp/google-debloat.zip'
foreach ($p in 'com.android.vending','com.google.android.googlequicksearchbox','com.google.android.projection.gearhead',
               'com.google.ambient.streaming','com.google.android.apps.carrier.carrierwifi','com.google.android.apps.restore',
               'com.google.android.partnersetup','com.google.ar.core') { & $adb shell "pm uninstall-system-updates $p" }
& $adb reboot
```

What you'll notice afterwards: the launcher's search bar goes inert (it was the Google app), there is no browser until you install one from F-Droid (Fennec is Firefox; WebView still renders in-app pages), and the Google system apps that remain stay at their factory versions, since the Store that updated them is gone. Disable the module and reboot to get all of it back; the Store then re-applies its updates on its own.


### The rest of the vendor layer

The seventh module, `vendor-extras-debloat`, finishes the job on the Motorola side: 58 packages in `manifests/vendor-extras-debloat.json`, most of them already uninstalled for the first user by the carrier variant and therefore invisible, but still on the partitions and ready to return for a new user or after a reset.

| Group | What goes |
| --- | --- |
| carrier-partner | AT&T, Cricket, Tracfone, Verizon, T-Mobile, Spectrum and Comcast leftovers: device help, voicemail, cloud, account apps, feeds, carrier config and settings extensions, OMA provisioning, call redirection, the AT&T Wi-Fi calling helper |
| partner-stubs | the Facebook and Amazon installers, Glance lock-screen content, two weather stubs, the app-cloud setup stub |
| motorola-apps | Game Mode, Moto, Spaces, Smart Feed, Guide Me, Help and Feedback Assistant, Battery Care, FM Radio, Audio Recorder, the Time & Weather widget, live wallpapers, Personalize, Secure Vault, Security Hub, FreeForm, demo mode, the factory test app, and a few regional and cloud adapters |
| telemetry-enterprise | Motorola's 3c device-management agent (sibling of the updater that `wifi-ota-guard` hides), the ThinkShield enterprise services, Google's Mainline telemetry |

What stays: the camera, Dolby and aptX audio, face unlock, the launcher and its config, Moto Secure core and the Security Hub extension, gesture and display services, the MediaTek telephony, IMS and location services, the Trustonic TEE bridge, thermal, and the settings providers. Motorola's AI services and Android System Intelligence are left installed as well; hide them with a manifest of your own if you don't want them.

```powershell
& $adb push .\device\modules\vendor-extras-debloat.zip /data/local/tmp/vendor-extras-debloat.zip
& $adb shell su -c 'magisk --install-module /data/local/tmp/vendor-extras-debloat.zip'
& $adb reboot
```

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
& $adb uninstall org.fdroid.fdroid                                    # removes F-Droid (apps it installed stay)
& $adb shell su -c 'touch /data/adb/modules/google_debloat/disable'   # Google apps and the Play Store return after a reboot
& $adb shell su -c 'touch /data/adb/modules/vendor_extras_debloat/disable'   # carrier, partner and Motorola extras return after a reboot
```
