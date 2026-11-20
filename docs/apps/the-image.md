# What the image gives you

The phone runs **the aosp-academy image**: an Android system built by this project from AOSP's source, booted through DSU (Dynamic System Updates, Android's way of running a second system image from a file, without flashing anything) on top of the phone's own vendor layer. This page lists what that image sets and leaves out, from the point of view of someone testing an app on it. How it's built and why each choice was made is in [the image](../environment/image.md); going back to the phone's own system is in [DSU](../device/dsu.md).

`./aosp-academy device report` prints most of what this page describes, read back from the phone: the fingerprint, the home app, animation scales, log buffer size, time zone, charge limit, network checks, built-in adb keys, the crash log and free space.

!!! info "Which build these numbers come from"
    The image moved to Android 17 on 2026-11-19. The measurements quoted below (process counts, boot times) were taken on builds 7 to 9, the last Android 16 builds, which carried the same settings under the old product name `vedotom_arm64`. The first Android 17 build is being validated as this is written; [validation](../environment/validation.md) has the current record.

## The system

| | |
| --- | --- |
| Android | **17**, API level **37**, built from the AOSP tag `android-17.0.0_r1` (build id CP2A.260605.016, security patch 2026-06-05) |
| Product | `aospacademy_arm64` (lunch target `aospacademy_arm64-trunk_staging-userdebug`); `ro.product.model` reads `aosp-academy on ARM64` |
| Build type | **`userdebug`**, signed with AOSP's public test keys (`test-keys` in the fingerprint) |
| ABI | `arm64-v8a` only (64-bit ARM) |
| Underneath | the phone's own Motorola vendor partition, kernel and firmware, unchanged: an Android 13 vendor layer (`ro.vndk.version=33`) running a newer system through Treble's stable interface |
| SELinux | enforcing |

A `userdebug` build is the engineering build type: the same code as a retail (`user`) build, with root, debugging and profiling switched on. For an app developer that means the device behaves like a normal Android 17 phone towards your app, and gives you more access around it. For the hardware itself (screen, CPU, GPU, cameras, sensors), see [the hardware inventory](../device/hardware.md).

## Root

- **`adb root`** restarts the phone's adb daemon as root, so every later `adb shell` is a root shell; `adb unroot` goes back. This works only on a userdebug build, so it works here and not on the phone's stock system.
- **`su 0 <command>`** runs one command as root from an ordinary shell: `adb shell su 0 id`. For several commands, `adb shell su 0 sh -c '<commands>'`. This is AOSP's own `su`; it takes a user id first and rejects Magisk's `su -c`, which only the stock system has. Root shells run in the `su` SELinux domain (`u:r:su:s0`).

[System access](../concepts/system-access.md) explains what root and the SELinux domains mean.

## Debugging and profiling any process

- **JDWP for every process.** The image sets `persist.debug.dalvik.vm.jdwp.enabled=1` (from build 9). Zygote, the process every app starts from, reads it once when it starts and, on a userdebug build only, opens the Java debugging protocol (JDWP) in every app process, not only in apps marked debuggable. On build 9, `adb jdwp` listed 24 processes at idle: `system_server`, SystemUI, Settings, the phone and Bluetooth processes, the network stack and every running app. Build 8 without the property listed none. The property also allows `ptrace`, so native debuggers can attach the same way. It gives nothing beyond what `adb root` already gives an authorised PC. To turn it off: `adb shell su 0 setprop persist.debug.dalvik.vm.jdwp.enabled 0` and reboot. [Debugging](debugging.md) shows how to use it.
- **Profiling other apps.** Perfetto's heap profilers and Android Studio's heap dumps work on apps that aren't debuggable or profileable on a `userdebug` build (`ro.build.type=userdebug`). This was established on the stock system with a module that makes it report userdebug; the image is a real userdebug build. See [tracing](tracing.md).

## Logs

The log buffers are **16 MiB** each (main, system, crash, events, radio and kernel), not logd's default of 256 KiB, which the vendor's log spam rolls over within minutes. A property can't set this on a phone, so an init rule in the image runs `logcat -G 16M` as soon as logd is ready, on every boot and again if logd restarts. `adb logcat -g` shows the size. See [debugging](debugging.md#logs).

## Settings for a test device

At first boot the image applies the development-target settings, the same seven that `aosp-academy device settings` applies on the stock system:

| Setting (global) | Value | Why |
| --- | --- | --- |
| `development_settings_enabled` | 1 | Developer options shown in Settings, without tapping the build number seven times |
| `stay_on_while_plugged_in` | 15 | Stay awake: the screen stays on while the phone charges (AC, USB, wireless or dock), so it never locks under a test run |
| `window_animation_scale`, `transition_animation_scale`, `animator_duration_scale` | 0 | Animations off: UI tests such as Espresso expect it, and screens settle at once |
| `verifier_verify_adb_installs` | 0 | `adb install` is not sent to a package verifier first: fast, and never held up by a prompt |
| `adb_allowed_connection_time` | 0 | An authorised PC stays authorised, instead of having to re-confirm after seven idle days |

They are set once, as defaults. A value you change later in Developer options is kept.

## USB debugging and adb authorisation

The image sets `ro.adb.secure=1`, as on a retail phone: a PC has to be authorised before adb works. Two cases:

- **The project's own PCs** (the device node and the build node) are trusted from the first boot: their public adb keys were built into the image at `/product/etc/security/adb_keys`. The keys come from a git-ignored file on the build node and are never in the repository, so an image built with them belongs to those machines and isn't passed on.
- **Any other PC** gets Android's *Allow USB debugging?* prompt on the phone the first time it connects. Tick *Always allow from this computer*. Each deploy starts with empty data, so the prompt comes back once after every deploy. While adb shows the phone as `unauthorized`, `aosp-academy` commands that wait for the phone say so and keep waiting.

## Apps and default roles

On top of AOSP the image carries one thing: the **Fossify** suite, 16 open-source apps (GPL-3.0, signed by Fossify, distributed by F-Droid, each pinned in `toolchain.json` by hash and signing certificate). They replace the AOSP apps one for one and fill the default roles, which matters when your app hands off to another app with an intent:

| Role or job | App | Package |
| --- | --- | --- |
| Home screen (HOME) | Fossify Launcher | `org.fossify.home` |
| Phone (DIALER) | Fossify Phone | `org.fossify.phone` |
| SMS | Fossify Messages | `org.fossify.messages` |
| Contacts, calendar, gallery, camera, clock, calculator | Fossify Contacts, Calendar, Gallery, Camera, Clock, Calculator | `org.fossify.contacts`, `.calendar`, `.gallery`, `.camera`, `.clock`, `.math` |
| Files, documents, notes, music, voice recorder, paint, keyboard | Fossify File Manager, Documents, Notes, Music Player, Voice Recorder, Paint, Keyboard | `org.fossify.filemanager`, `.documents`, `.notes`, `.musicplayer`, `.voicerecorder`, `.paint`, `.keyboard` |

The dialer and SMS defaults come from the image's framework overlay; the first-boot service gives Fossify Launcher the HOME role. Some AOSP apps stay on purpose:

- **DocumentsUI** is the system file picker behind every `ACTION_OPEN_DOCUMENT`, `ACTION_GET_CONTENT` and `ACTION_CREATE_DOCUMENT`, so your app's pickers work as on any phone. Only its *Files* icon is hidden from the app drawer (`pm enable com.android.documentsui/.LauncherActivity` brings it back).
- **LatinIME**, the AOSP keyboard, stays as the fallback keyboard; its app-drawer icon is hidden too. Its settings are under Settings, System, Keyboard.
- **Launcher3QuickStep** stays because SystemUI uses it for gesture navigation and recents.
- **Settings**, and everything Android delivers as a Mainline module.

There is **no app store** in the image, so nothing updates these apps; a new version means a new pin and a new image. Install your own apps with adb or Studio.

## No browser; WebView from the tag

There is **no web browser** in the image, by design. An `ACTION_VIEW` intent for an `https://` link has no app to go to, so `startActivity` with it throws `ActivityNotFoundException`. That makes the image a good place to check that your app handles the case; if your test needs a browser, install one with `adb install`.

**WebView** is there, so web content inside apps renders. It is AOSP's WebView built from the same tag, and nothing updates it: it ages with the tag and is refreshed when the image moves to a newer one. If your app depends on a recent WebView feature, check the version first: `adb shell dumpsys webviewupdate` names the WebView package in use and its version.

## Look, time zone and network

- **Look:** dark theme, gesture navigation, the project's wallpaper (Material You derives the system colours from it), teal launcher icons for the Fossify apps, and no boot animation (the screen stays on the bootloader's splash until the lock screen).
- **Time zone:** `America/New_York` by default (`persist.sys.timezone`). Without a SIM the phone gets no time-zone suggestion from the network, and AOSP without Google's services has no location-based time-zone provider, so it would otherwise start in GMT. A zone you choose in Settings is stored and wins.
- **No Google endpoints for connectivity checks or time.** Android checks each new network for a captive portal by fetching a test URL. On the image those probes go to GrapheneOS's public endpoints (`connectivitycheck.grapheneos.network/generate_204` over HTTP and HTTPS, `grapheneos.online/gen_204` as the fallback), which answer for any client, and network time comes from `pool.ntp.org` instead of `time.android.com`. Validated on build 7: the network is `VALIDATED` and no log line names a Google host. Wi-Fi joins automatically after a deploy when the device node has its private network file.

## The 80% charge limit

The phone lives on its charger, so the image stops charging at about **80%**, as the stock system does with Motorola's battery protection on. A service in the image writes the limit to the vendor's charging module after boot and whenever the property `persist.aospacademy.charge_limit` changes (default 80, values 50 to 100 accepted):

```sh
adb shell su 0 setprop persist.aospacademy.charge_limit 100   # charge to full
adb shell su 0 setprop persist.aospacademy.charge_limit 80    # back to the default
```

Two things an app developer may notice:

- The level settles between the limit minus 1 and plus 2, so with 80 the phone sits at about 84%.
- While the limit holds, the battery reports **"Not charging"** with the charger plugged in (`BatteryManager.BATTERY_STATUS_NOT_CHARGING`), and the phone runs from the charger or the battery as the module decides. An app that reacts to charging state sees that, not "Charging" or "Full".

With 100, charging resumes at once from any lower level; if charging is held off at exactly 100%, it stays off until the level falls to 99. [The image](../environment/image.md) explains how the module decides.

## What a deploy wipes

The image's data partition (24 GB by default) belongs to the image, separate from the phone's own system and its data.

| Action | Your apps and their data on the image |
| --- | --- |
| `adb reboot` | kept: the phone comes back into the image (about 45 s) |
| `aosp-academy gsi stock`, then `aosp-academy gsi boot` | kept: the image stays installed while the phone runs its own system, and comes back as you left it |
| `aosp-academy deploy` (a new image) | **wiped**: the old image is discarded with its data, and the new one starts empty |
| `aosp-academy gsi discard` | **wiped** |

After a deploy the image is a fresh install: first boot sets the defaults above again, your apps are gone, and any PC whose key isn't built in gets the Allow prompt again. Keep everything you need in your app project, and treat the device as a test target, not a store. The phone's own system on slot A is never touched by any of this. [Deploying](../environment/deploying.md) describes a deploy step by step.

## Limits

- **No Google Play services.** Nothing from Google's proprietary layer is in the image: no Play Store, no Firebase Cloud Messaging, Google sign-in, Maps SDK, Play Billing or Play Integrity. An app that needs them fails or degrades here exactly as on any device without them, which is useful to test but is not the retail experience. For that, the phone's stock system (Motorola's, with Google's apps) is still on slot A: see [DSU](../device/dsu.md) for switching to it and [the stock baseline](../device/stock.md) for what it offers.
- **No SIM tested.** The project's phone has no SIM. Cellular data, calls, SMS and anything carrier-related are untested on the image, and VoLTE is doubtful: the vendor layer doesn't declare the IMS radio interface the system expects.
- **No virtualization (AVF).** This SoC has no protected KVM: no `/dev/kvm`, no Android Virtualization Framework, so no Microdroid or `VirtualMachineManager` and no Terminal app. The image leaves the AVF packages out.
- **simpleperf is unusable.** The vendor kernel exposes no CPU performance counters (`simpleperf record` fails with "Event type 'cpu-cycles' is not supported on the device", and `cpu-clock` the same). That also rules out Android Studio's *Callstack Sample* CPU recording, which is simpleperf underneath; Perfetto and Studio's system trace work. See [tracing](tracing.md#the-simpleperf-gap).
- **Two of three cameras.** The system reaches the hardware only through Treble's vendor interface, and two of the phone's three cameras are exposed through it, as with Google's own generic image.
- **Test-keyed.** The image is signed with AOSP's public test keys. It is a development system, not one to put on a phone you rely on.

The open work on the image is in [the backlog](../environment/backlog.md).
