# The stock system

The [preparation walkthrough](walkthrough.md) ends with Motorola's own Android 16 system, rooted with Magisk, with the bootloader unlocked. This page is about that **prepared stock system** as a development baseline: what is installed on it and why, the settings that make it a better test target, and how to keep it working. It is the system underneath the [aosp-academy image](dsu.md), and the one the phone returns to whenever the image is switched off.

No custom ROM is involved. The firmware partitions hold the factory build; every change here is a Magisk module in `/data`, an ordinary Android setting, or an app install, and each one is reversible.

!!! warning "The preparation stages are never re-run"
    The walkthrough's stages run **once per phone**. Don't repeat any of them on a phone that is already prepared: the low-level ones write the boot chain, and re-running them gains nothing and risks the device. Everything on this page is done on the prepared system as it stands. If you are preparing a second unit, or resetting one completely, follow the [preparation walkthrough](walkthrough.md) itself from the start.

The commands on this page run in a shell opened with `aosp-academy shell` (from the repository root: `./aosp-academy shell`, or `.\aosp-academy shell` on Windows), which puts the pinned `adb` first on PATH. Root commands use Magisk's `su -c '<command>'`, the form the stock system understands; they are quoted so that they work the same in bash, PowerShell and cmd.

## Two kinds of root

Root on the stock system is **Magisk**: it is installed in `init_boot_a`, starts on every boot, and grants root per app through the Magisk app. Grant it only to development tools you trust and deny it to everything else ([System-level access](../concepts/system-access.md) explains why). Inside an aosp-academy image, root is AOSP's own userdebug `su` (`su 0 <command>`) instead, and Magisk's grants and modules don't apply there, because they live in the stock system's `/data`, which the image doesn't see.

## The seven modules

Seven [Magisk modules](../concepts/magisk-modules.md) make the stock system a Wi-Fi-only development device. Five are **overlay modules**: each one hides a set of preinstalled apps by mounting an empty directory over each app's directory at boot, so the app isn't there while the module is enabled and nothing on the firmware partitions changes. Two are **script modules** that set properties early in boot. All seven live in `stock/modules/`, each generated from a manifest in `stock/modules/manifests/`; [The Magisk modules](modules.md) explains how they are built and verified.

| Module (id) | Kind | What it does |
| --- | --- | --- |
| `wifi_ota_guard` | overlay, 1 package | Hides Motorola Software Update, so the phone stays on its tested build. Doesn't block Play Store app updates. |
| `wifi_carrier_debloat` | overlay, 22 packages | Hides the Verizon and Tracfone activation and remote-SIM-lock apps, the carrier management services, and Motorola's PAKS finance apps. |
| `wifi_extra_debloat` | overlay, 19 packages | Hides the AT&T, Cricket and Facebook partner stubs, Motorola's telemetry and support apps, Ready For desktop mode, visual voicemail and Digital Wellbeing. |
| `google_debloat` | overlay, 27 packages | Hides the Google layer a development device doesn't need (see [below](#hiding-the-google-apps)). |
| `vendor_extras_debloat` | overlay, 58 packages | Hides the remaining carrier, partner and Motorola consumer apps, plus Motorola's device-management and enterprise agents and Google's Mainline telemetry (see [below](#the-rest-of-the-vendor-layer)). |
| `dev_debuggable` | script | Makes the system report itself as an engineering (`userdebug`) build, and keeps the larger log buffers across reboots (see [below](#the-two-development-modules)). |
| `dev_adb_tcp` | script | Makes `adbd` listen on TCP port 5555 from boot, for ADB over Wi-Fi. |

The walkthrough installs the three `wifi_*` modules as part of its last stage. The other four are optional and installed on the prepared system, as below. Each manifest lists every package it hides with the package's on-disk directory and a one-line description of what it is.

Any module installs the same way, then takes effect at the next reboot:

```sh
adb push stock/modules/<module>.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/<module>.zip'"
adb reboot
```

The ZIP names use dashes (`dev-debuggable.zip`); the module ids use underscores (`dev_debuggable`).

!!! note "If the phone won't boot with a module enabled"
    Hold **Volume Down** while it boots. Magisk's safe mode starts with every module disabled, so you can disable the culprit (`adb shell "su -c 'touch /data/adb/modules/<id>/disable'"`) and reboot normally. None of the seven modules has needed that, but it's the escape hatch for any module.

### The two development modules

Google's own engineers don't work on retail (`user`) builds; they use `userdebug` builds, which report themselves as debuggable and let tooling attach to anything. These two small modules close most of that gap. Both are [script modules](../concepts/magisk-modules.md#script-modules): a `post-fs-data.sh` that sets system properties early in boot, before `zygote`, `system_server` and `adbd` start. Every claim in this table was checked on unit 2; the [validation record](index.md#validation-record) has the measurements.

| Module | Sets | What you get | Mind |
| --- | --- | --- | --- |
| `dev_debuggable` | `ro.debuggable=1` and `ro.build.type=userdebug` | The system reports itself as an engineering build. Verified effect: Perfetto's heap profilers (Java heap dumps, native `heapprofd`) and other tooling that checks the build type can target **any** app, not only profileable ones; on stock they refuse with `not profileable`. Tools that gate on `ro.debuggable` behave as on a userdebug build. | Some apps refuse to run on a debuggable or userdebug system. Verified **not** to change on the stock Android 16: the debugger still attaches only to debuggable apps (no JDWP for the rest), `run-as` still checks the app's own flag, and `adb root` still fails (it makes `adbd` abort and restart as `shell`; don't run it). Use `su -c`. The module also carries a `sepolicy.rule` granting Settings the one userdebug-only permission Developer options needs (writing `logd.logpersistd*`); without it, Developer options crashes on open. Version 1.3 adds a `service.sh` that re-applies the stored log size once boot completes (see [the settings](#development-target-settings)). |
| `dev_adb_tcp` | `service.adb.tcp.port=5555` | `adbd` listens on TCP from boot, so `adb connect <phone-ip>:5555` works with no cable and no pairing dialog. | Only PCs whose ADB key you've approved on the phone get a shell, but the port is reachable by anyone on the network. Keep it disabled on networks you don't control. |

After installing them and rebooting, check:

```sh
adb shell getprop ro.debuggable               # 1
adb shell getprop ro.build.type               # userdebug
adb shell getprop service.adb.tcp.port        # 5555
adb shell "su -c 'ss -ltn | grep :5555'"      # adbd listening on TCP
```

The proof that the userdebug report does something useful is a heap dump of an app that isn't yours, which stock refuses. Save this Perfetto config as `work/hprof.pbtxt`:

```text
buffers: { size_kb: 32768 }
data_sources: { config { name: "android.java_hprof" java_hprof_config { process_cmdline: "com.android.settings" } } }
duration_ms: 3000
```

and record it:

```sh
aosp-academy device trace --config work/hprof.pbtxt --name settings-heap   # ~25 MB trace in work/traces/; open it at ui.perfetto.dev
```

### ADB over Wi-Fi

With `dev_adb_tcp` installed, `aosp-academy adb-wifi` reads the phone's Wi-Fi address over USB, then connects to it:

```sh
aosp-academy adb-wifi        # connected to <phone-ip>:5555
adb devices -l               # the phone now appears twice: USB and TCP; unplug and the TCP one stays
```

`adb-wifi` first checks that the PC has an address on the phone's network and says so if not; two routers, a guest Wi-Fi, or a wired PC on a different subnet from the Wi-Fi are the usual reasons a connect would otherwise just time out. Android Studio lists the TCP device like any other. Without the module, Android's own path is **Developer options → Wireless debugging → Pair device with pairing code** and `adb pair`, which has to be repeated after each reboot; or `adb tcpip 5555` over USB, which lasts until the next reboot.

## Apps without Google: F-Droid

A development device is a good place to stay out of Google's ecosystem as far as the hardware allows. The phone ships with Play services and the Play Store in the system image, and this project keeps them: too much of the stock system expects them. But nothing requires you to sign in to a Google account, and installing apps doesn't need the Store at all.

**F-Droid** is the free-software app store: a catalogue of open-source apps built from source on F-Droid's own build servers, with no account, no tracking and no proprietary dependencies. The F-Droid client is **pinned** in `toolchain.json`: `aosp-academy setup` downloads it into `work/device-tools/`, hash-checked like everything else, and `aosp-academy check` also verifies the APK's signing certificate against the fingerprint F-Droid publishes (`43238d51…ccab`, on [its signing-keys page](https://f-droid.org/docs/Release_Channels_and_Signing_Keys/)). The PGP signature F-Droid ships for the same file (`F-Droid.apk.asc`, key `37D2 C987 89D8 3119 4839 4E3E 41E7 044E 1DBA 2E89`) was verified when the pin was recorded.

```sh
adb install work/device-tools/org.fdroid.fdroid_2000053.apk
adb shell am start -n org.fdroid.fdroid/org.fdroid.IconActivity   # first launch fetches the catalogue (needs Wi-Fi)
```

Open it, let it download the repository index, and install apps from there. From then on F-Droid updates itself and the apps it installed. **Android's "install unknown apps" prompt** appears the first time F-Droid installs something. That is the per-app permission F-Droid needs in order to act as an installer; granting it to F-Droid is the point.

??? note "Installing from F-Droid without touching the screen"
    F-Droid has no command line, but its repository is verifiable by hand, which is how this project pins the apps it takes from F-Droid (the client itself and the Fossify suite in `toolchain.json`): download `https://f-droid.org/repo/entry.jar`, check its signature with `jarsigner -verify` and `keytool -printcert -jarfile` against F-Droid's certificate (the same `43238d51…` as the client), download `index-v2.json` and check it against the SHA-256 the signed entry names, then take the package's APK hash and signer from the index and compare them with the downloaded APK (`sha256sum`, `apksigner verify --print-certs`). Install with `adb install -i org.fdroid.fdroid <apk>` so F-Droid records itself as the installer and keeps the app updated.

### The Play Store, signed out

The Play Store stays on the phone (`google_debloat` hid it up to version 1.0 and restored it in 1.1), and on this baseline it is run **signed out**. Signed out, it can be browsed but installs and updates nothing, so the Google system apps that remain stay at their factory versions and F-Droid is the update path. Sign in if you want Play installs and updates; nothing else on the baseline depends on either choice.

### Hiding the Google apps

With F-Droid in place, `google_debloat` hides the Google layer that a development device doesn't need, the same reversible way the carrier modules work. `stock/modules/manifests/google-debloat.json` lists all 27 packages in four groups:

| Group | What goes |
| --- | --- |
| store | the two Play auto-install hooks that pull carrier apps in at setup (the Play Store itself stays) |
| search-assistant | the Google app (search bar, Assistant, Circle to Search), both hotword enrolment services, Gemini |
| consumer-apps | Chrome, Gmail, YouTube, YouTube Music, Maps, Photos, Drive, Meet, Google TV, Google Home, Calendar, Google Fi |
| account-extras | account restore at setup, partner setup, Location History, Family Link, the feedback reporter, Android Auto, cross-device streaming, Google's carrier Wi-Fi, ARCore |

What stays, deliberately: the Play Store, Play services and the services framework (too much of the stock system binds to them), WebView and its shared Trichrome library, Gboard (the only keyboard), Contacts, Messages, Files, the Google dialer, speech services, TalkBack and Switch Access, the eSIM manager, Device Health Services, the wallpaper picker, and everything delivered as a Mainline APEX. Nothing in this module needs a Google account, and nothing left behind asks for one.

One detail matters for seven of these apps: the Play Store had updated them, so a newer copy lived in `/data/app` beside the system one. Hide only the system copy and Android keeps the update as an ordinary app. `pm uninstall-system-updates` drops the update first, so the hidden copy is the only copy. Install the module, then run this once for each of the seven packages, then reboot:

```sh
adb push stock/modules/google-debloat.zip /data/local/tmp/
adb shell "su -c 'magisk --install-module /data/local/tmp/google-debloat.zip'"
adb shell pm uninstall-system-updates <package>
adb reboot
```

The seven packages are `com.google.android.googlequicksearchbox`, `com.google.android.projection.gearhead`, `com.google.ambient.streaming`, `com.google.android.apps.carrier.carrierwifi`, `com.google.android.apps.restore`, `com.google.android.partnersetup` and `com.google.ar.core`.

What you'll notice afterwards: the launcher's search bar goes inert (it was the Google app), and there is no browser until you install one from F-Droid (Fennec is Firefox; WebView still renders in-app pages). Disable the module and reboot to get all of it back; a signed-in Store then re-applies its updates on its own.

### The rest of the vendor layer

`vendor_extras_debloat` finishes the job on the Motorola side: 58 packages in `stock/modules/manifests/vendor-extras-debloat.json`, most of them already uninstalled for the first user by the carrier variant and therefore invisible, but still on the partitions and ready to return for a new user or after a reset.

| Group | What goes |
| --- | --- |
| carrier-partner | AT&T, Cricket, Tracfone, Verizon, T-Mobile, Spectrum and Comcast leftovers: device help, voicemail, cloud, account apps, feeds, carrier config and settings extensions, OMA provisioning, call redirection, the AT&T Wi-Fi calling helper |
| partner-stubs | the Facebook and Amazon installers, Glance lock-screen content, two weather stubs, the app-cloud setup stub |
| motorola-apps | Game Mode, Moto, Spaces, Smart Feed, Guide Me, Help and Feedback Assistant, Battery Care, FM Radio, Audio Recorder, the Time & Weather widget, live wallpapers, Personalize, Secure Vault, Security Hub, FreeForm, demo mode, the factory test app, and a few regional and cloud adapters |
| telemetry-enterprise | Motorola's 3c device-management agent (sibling of the updater that `wifi_ota_guard` hides), the ThinkShield enterprise services, Google's Mainline telemetry |

What stays: the camera, Dolby and aptX audio, face unlock, the launcher and its config, Moto Secure core and the Security Hub extension, gesture and display services, the MediaTek telephony, IMS and location services, the Trustonic TEE bridge, thermal, and the settings providers. Motorola's AI services and Android System Intelligence are left installed as well; hide them with a manifest of your own if you don't want them.

## Linux on the device

Android 16 ships a built-in Linux Terminal (a Debian VM on the Android Virtualization Framework), but this SoC doesn't have the framework: no hypervisor properties, no `/dev/kvm`, no `com.android.virt` APEX, no Terminal app. The [hardware inventory](hardware.md) records the check. This project keeps the phone to a stock development baseline and installs no Linux userland on it; work that needs a Linux box belongs on a PC, and root shells on the phone come from `su` over ADB.

## Development-target settings

Five ordinary Android settings and one property make the phone a better target for building and testing apps. `aosp-academy device settings` applies them, checks each one, and exits with the number that didn't stick; `--reset` returns every one to stock. The aosp-academy image sets the same values itself at first boot, so this command is for the stock system, or to put them back after an experiment.

| Setting | Value | Why |
| --- | --- | --- |
| `window_animation_scale`, `transition_animation_scale`, `animator_duration_scale` | 0 (off) | Espresso and other UI tests expect animations off, and screens settle at once |
| `verifier_verify_adb_installs` | 0 | `adb install` no longer waits for Play Protect to verify the app first |
| `adb_allowed_connection_time` | 0 | an authorized PC stays authorized, instead of re-confirming its key after seven days without connecting (matters for ADB over Wi-Fi) |
| `persist.logd.size` | 16M | log buffers of 16 MiB instead of the stock 256 KiB, so the log from before a crash is still there |

```sh
aosp-academy device settings            # apply and verify
aosp-academy device settings --reset    # back to stock
```

The log size needs two things on this build. Setting `persist.logd.size` takes root (the command uses `su`; without root it warns that the size lasts until the next reboot), and logd ignores the property at boot and on `logd --reinit`: the buffers came up at 256 KiB with it set. `logcat -G` does apply it, until the next reboot, which is why the command also runs `logcat -G 16M` and why `dev_debuggable` 1.3 re-applies the stored size once boot completes. Without that module the size lasts until the next reboot. `--reset` deletes the property and sets the buffers back to 256 KiB.

## Living on the charger: the 80% cap

A development phone spends most of its life plugged in, and a lithium battery held at 100% ages fastest. Motorola's battery protection caps charging at 80%: **Settings → Battery → Battery protection**, switch on **Use Battery protection**, choose **Manual schedule** and set its run time to **Always**. *Smart schedule* is the wrong choice here: it learns when you unplug and tops up to 100% an hour before, which a phone that never leaves the desk doesn't need. The setting belongs to Moto Actions (`com.motorola.actions`), which no module hides; Battery Care, which `vendor_extras_debloat` does hide, only manages background apps.

To check it from the PC:

```sh
adb shell "dumpsys battery | grep AdaptiveCharging"   # mUpperLimit:80; mChargingDisabled:true while above it
```

Above 80% the phone stops charging and runs from the charger while the level drifts down to the cap, so a battery that was full when protection went on takes a while to settle at 80%. The setting belongs to the stock system; the aosp-academy image sets its own 80% cap at boot from the property `persist.aospacademy.charge_limit` ([The image](../apps/the-image.md) describes what the image sets).

## Routine maintenance

The job, once the phone is prepared, is to keep that working state while you develop on it.

### Safe and risky

| Action | Verdict |
| --- | --- |
| Install apps and tools (F-Droid, `adb install`, Play when signed in) | Fine. Some apps refuse rooted or unlocked devices; that's their choice. |
| Normal app updates | Fine: separate from firmware. |
| Reboot or shut down | Fine. Root and every module survive normal reboots. |
| Grant a new app root in Magisk | High-trust decision. Grant only to development tools you trust; deny games and random apps. |
| Enable or disable a module | Fine and reversible: that's the point of [modules](../concepts/magisk-modules.md). |
| Install, boot or discard a DSU image | Fine: DSU writes only `/data`, never the slots ([DSU on this phone](dsu.md)). |
| Update the Magisk app | Usually fine, but it's your root manager: read its release notes, don't treat it like a game update. |
| **Magisk Direct Install / framework upgrade** | Writes boot state; can break startup. Back up and plan recovery first. |
| **Accept a Motorola firmware or OS update** | Can overwrite root, change the bootloader, or close the path used to prepare the phone. Don't accept casually; plan it. |
| Google Play *system* updates | Different from app updates; can touch system components. Untested here. |
| **Relock the bootloader** | Don't, with a modified boot chain. A rejected boot chain can brick the phone. |
| **Change the active slot or flash both slots** | Untested and hazardous. Slot B isn't a validated fallback. |
| Factory reset | Erases `/data`, which holds your apps, Magisk's root grants, **every module** (`/data/adb/modules`) and any DSU image. The prepared boot state may remain, but expect to re-grant Shell and reinstall the modules; the full setup isn't guaranteed. |
| Re-run a preparation stage | Don't. The stages run once per phone (see the warning at the top of this page). |

The theme: **ordinary app-level use is fine; anything that writes the boot chain or firmware needs a plan and a backup.**

### Keeping firmware updates off

`wifi_ota_guard` keeps the Motorola updater from running, so the phone stays on its tested build. Keeping that build means keeping its known issues too: that's the deliberate trade for a stable, prepared development baseline. The block is reversible whenever you choose to plan an update.

### Undoing a module

To bring back the carrier apps, the other hidden apps, or the updater, or to turn off a development module, disable that module and reboot. Run only the line for the module you want to undo:

```sh
adb shell "su -c 'touch /data/adb/modules/wifi_carrier_debloat/disable'"    # 22 Verizon/Tracfone packages
adb shell "su -c 'touch /data/adb/modules/wifi_extra_debloat/disable'"      # 19 partner, telemetry, Moto extras
adb shell "su -c 'touch /data/adb/modules/wifi_ota_guard/disable'"          # Motorola updater
adb shell "su -c 'touch /data/adb/modules/google_debloat/disable'"          # the hidden Google apps
adb shell "su -c 'touch /data/adb/modules/vendor_extras_debloat/disable'"   # carrier, partner and Motorola extras
adb shell "su -c 'touch /data/adb/modules/dev_debuggable/disable'"          # back to ro.debuggable=0
adb shell "su -c 'touch /data/adb/modules/dev_adb_tcp/disable'"             # ADB over USB only
adb reboot
```

Undoing `wifi_carrier_debloat` needs one more step after the reboot, which belongs to the preparation procedure; see the [preparation walkthrough](walkthrough.md). F-Droid is removed like any app (`adb uninstall org.fdroid.fdroid`; the apps it installed stay).

The same toggles are in the Magisk app under **Modules**. Nothing was deleted from the firmware; disabling the overlay is all it takes. To bring back one app without disabling a whole module, remove it from the module's manifest in `stock/modules/manifests/`, rebuild with `aosp-academy stock build --promote` ([The Magisk modules](modules.md)), and reinstall the ZIP.

### If the boot chain breaks

The modules can always be turned off with safe mode, as above. A boot problem in the boot chain itself (the bootloader or the Magisk image in `init_boot_a`) is a different matter: recovering from it means restoring your own backup of that partition from Fastboot, and the [preparation walkthrough](walkthrough.md) is the reference for the backups and the boot chain. If a bad bootloader stops Fastboot from starting, there is **no vendor-independent recovery proven for this model**. Don't assume the other slot, a MediaTek COM-port tool or a random download agent will save it.

### When you report a problem

If you share results (an issue, a forum post), include the model, build, security patch, kernel, what you were doing, and the exact error text. **Redact** your serial, IMEI, account names, network identifiers and unlock keys, and never attach your backup images or raw logs. The [git safety net](../reference/git-workflow.md) keeps those out of commits, but a manual paste is on you.

## Moving on

Day-to-day app work belongs in Android Studio, in your own projects; this repository stays the bootstrap, the reference and the documentation. [Developing apps](../apps/index.md) covers that, including [Android Studio](../apps/android-studio.md), [Frida](../apps/instrumentation.md) and [Perfetto](../apps/tracing.md) against this phone.
