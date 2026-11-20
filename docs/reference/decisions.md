# Decisions

The decisions that shape the image and the project, with the reasons behind them. The reasons are the point: before reversing a decision, read why it was made. The open work is in the [backlog](../environment/backlog.md), and what the current image was checked against is on the [validation page](../environment/validation.md).

"The user" is the project's owner, who decides anything that changes policy.

## The image

### Android 17 only

**Decided** (the user): the image is built from **`android-17.0.0_r1`** (`CP2A.260605.016`), and the pinned Google GSI is the Android 17 `CP2A.260605.012`. No other release is built.

**Why:** the risk that matters is the vendor layer, which is Android 13 (VNDK 33, VINTF target level 7). Google's Android 17 GSI boots on this vendor with the full hardware list, so Android 17 is known to run here. Keeping a second tree and a second branch for an older release costs more than it protects. How to move to a later release is in [move to a new AOSP release](../environment/tag-moves.md).

### The image carries only the Fossify suite on top of AOSP

**Decided:** on top of AOSP the image carries only the Fossify apps (Launcher, Gallery, Calendar, Contacts, Clock, Phone, Messages, Music Player, Camera, Calculator, File Manager, Documents, Notes, Voice Recorder, Paint, Keyboard), which replace the AOSP apps one for one or add what AOSP lacks. No maps app, browser or app store.

**Why:** the image matches the clean development baseline of the stock system. A development device needs a working set of everyday apps, not a curated app collection.

**What follows:**

- The image has **no web browser**. Browser2, AOSP's WebView test shell, stays out. WebView still renders web content inside apps, and links (`https://...`) resolve to nothing, as intended.
- **Nothing updates the Fossify apps on the device.** There is no app store in the image: a new version means a new pin and a new image.
- The F-Droid pin stays in `toolchain.json`, because the stock baseline has the F-Droid client installed.
- Fossify Keyboard stays, and AOSP's LatinIME stays as the default and fallback keyboard: a working keyboard must never depend on a prebuilt.

### Development settings and log size come from the image itself

**Decided:** the image applies the development-target settings (animation scales 0, `verifier_verify_adb_installs` 0, `adb_allowed_connection_time` 0, Developer options shown, Stay awake on) in its first-boot service, and sets 16 MiB log buffers with an init rule that runs `logcat -G 16M` when logd reports ready.

**Why:** a resource overlay on SettingsProvider would survive a discard and need no PC, but SettingsProvider has resource defaults for only two of these settings in this release. A property can't set the log size: logd reads `ro.logd.size` and `persist.logd.size` at start only on automotive and desktop hardware types, not on a phone. With logd's default 256 KiB, vendor log spam rolls the first-boot service's own lines out of every buffer within minutes.

### Hide two AOSP icons, keep their apps

**Decided:** the first-boot service hides the launcher icons of DocumentsUI ("Files") and LatinIME's settings ("Android Keyboard settings") with `pm disable` on those two components only.

**Why:** DocumentsUI is the system file picker behind every open, get-content and save dialog, Fossify's apps included, so it can't be removed; Fossify File Manager is the file app. LatinIME stays as the fallback keyboard, and its settings stay under Settings, System, Keyboard. Neither icon is gated on a resource in this release, so an overlay can't hide it. `pm enable` on the same component brings an icon back.

### No mirroring of the system partition to remove the last unused apps

**Decided** (the user): BasicDreams, `com.android.egg`, Bips (printing), PrintSpooler, HtmlViewer, BookmarkProvider, CallLogBackup and WallpaperBackup stay in the image.

**Why:** they come from upstream's system-image definitions (`base_system.mk`, `handheld_system.mk`, `telephony_system.mk`, `media_system.mk`, and about 600 lines of `system_image_defaults` in `build/make/target/product/generic/Android.bp`). Neither make nor Soong can subtract a package, so removing them means mirroring all of that and re-checking it on every release move, which costs more upkeep than the space is worth. PhotoTable is out, because it lives in the product makefiles this project already mirrors. Traceur stays on purpose: it's useful for development.

### WebView ages with the AOSP release

**Decided** (the user): the image's WebView is the one in the AOSP release and isn't updated in between.

**Why:** nothing in the image updates it, and keeping it current separately would mean another pinned, signed input and its upkeep. With no browser in the image, WebView is the only web engine on the device, so revisit this if an app needs a newer one. Moving to a new release refreshes it.

### Charge limit 80 %, and no `-1` write

**Decided** (the user): the image keeps the charge limit at **80 %** (`persist.aospacademy.charge_limit`, 50 to 100 accepted) and never writes the module's off value `-1`.

**Why 80:** the phone lives on its charger, as on stock with Moto's battery protection on. The image makes the same single write to the vendor module `qpnp_adaptive_charge` that stock's chain ends in.

**Why no `-1`:** from Motorola's source for the module and a test on the device, at exactly the limit the module keeps its current state, so with the limit at 100 a hold that is already in place at 100 % lasts until the level falls to 99. Clearing it at once would need `upper_limit` `-1`, a new kind of write to a vendor module, and the rule on this phone is no new kinds of write without the user. The service writes `upper_limit` and checks the result only through the read-only `blocking` parameter, and never reads `upper_limit` or `lower_limit` back: reading module parameters in bulk on this phone panics its kernel. [What's in the image](../environment/image.md) describes how the module decides.

### Every process is debuggable on the image

**Decided:** the image sets `persist.debug.dalvik.vm.jdwp.enabled=1`.

**Why:** this project's image is a development target, and the apps under development aren't the only processes worth a debugger. With it, `adb jdwp` lists `system_server`, SystemUI, Settings and every running app, so Android Studio can attach to any of them. [Debug any process](../apps/debugging.md) uses it.

## adb and the network

### USB debugging requires authorization: `ro.adb.secure=1`

**Decided** (the user): the image sets `ro.adb.secure=1`, as a product property, because the GSI's artifact rules forbid system properties.

**Why:** with `ro.adb.secure=0`, any USB host gets a root-capable shell on this `userdebug` image without asking. That's convenient on a desk, but it should be a deliberate choice.

### The project's own PCs are trusted from the first boot

**Decided** (the user): the image trusts the project's own PCs, the device node and the build node, without the Allow tap, so deploys run unattended. Any other PC needs the tap.

**How:** their **public** adb keys (one `adbkey.pub` line each) live in `work/adb_keys` on the build node, which is git-ignored and blocked by the hook, never in the repository. `image apply` copies the file into the tree and the product sets `PRODUCT_ADB_KEYS` to it, which installs `/product/etc/security/adb_keys`. Without the file, the image trusts no PC: every deploy installs the image with fresh data, so the first connection shows *Allow USB debugging?* on the phone, and `deploy` says "tap Allow on the phone" while it waits.

**Why the keys stay out of the repository:** the repository is public, and a key belongs to a machine, not to the project. An image built with keys belongs to those machines: don't pass it on.

### No Google endpoints for connectivity checks or time

**Decided** (the user): the image's captive-portal checks use GrapheneOS's public endpoints, and its time comes from `pool.ntp.org`.

| What | Upstream AOSP | The image |
| --- | --- | --- |
| Captive portal, HTTPS | `connectivitycheck.gstatic.com` | `https://connectivitycheck.grapheneos.network/generate_204` |
| Captive portal, HTTP | `connectivitycheck.gstatic.com` | `http://connectivitycheck.grapheneos.network/generate_204` |
| Captive portal, fallback | `www.google.com` | `http://grapheneos.online/gen_204` |
| Time (`config_ntpServers`) | `ntp://time.android.com` | `pool.ntp.org` |

**Why:** to avoid Google as far as practical, in the image as on the stock baseline. GrapheneOS runs these endpoints for any client, and they return the same HTTP 204 as Google's, so Android's network validation works unchanged.

**How:** resource overlays on the framework and on the NetworkStack module. NetworkMonitor reads the `config_captive_portal_http[s]_urls` arrays before the single `config_captive_portal_http[s]_url` values, so the overlay sets both.

## The project

### Android Studio's `adb` and ours are the same version

**Decided:** the pinned platform-tools are **37.0.3**, the version the SDK installs.

**Why:** Android Studio runs the SDK's `adb` server, the project runs the pinned one, and two server versions fight over one phone. With the same version they share a server. `check` fails if they drift apart. See [pins](pins.md#platform-tools-and-the-flashing-stages).

### A separate build node

**Decided:** the image is built on a dedicated build node, not on the PC beside the phone. The device node keeps no AOSP tree.

**Why:** the tree is 300 to 400 GB with its output and a build needs 32 GB of RAM or more, while the PC beside the phone needs neither. Separating them also separates the work.

**The rule:** the build node only builds and tests; the device node only fetches, deploys and verifies. Every build request names a branch and a commit, so the image on the phone can always be traced to the source it came from. Each deploy wipes the image's data: the phone is a test target, not a store.

### A portable Linux build node

**Decided** (the user): the build doesn't need Windows or WSL. The build node is any x86-64 Linux host: native, WSL2, a cloud VM or a container.

**How:** build settings come from the environment, with defaults (`AOSP_DIR`, `JOBS`, `PUBLISH_DIR`, `PARTS`); nothing assumes `/mnt/c`, WSL or a particular user. The image's inputs are fetched on the build node itself (`aosp-academy image inputs`). `image/build/Containerfile` gives an optional reproducible host. Publishing writes a folder (the image in parts, the checksums and `build.prop`); how another machine reaches that folder is the host's own setup, documented in [set up a build node](../start/build-node.md) but not coded into the build.

### One Python command

**Decided** (the user): the project's tooling is one command, `aosp-academy`, written in Python 3 with the standard library only.

**Why:** it runs the same on Windows, Linux and macOS, which the portable build node needs and which lets the device node be any PC. Python is also what Android's own tooling uses (`repo`, the AOSP build scripts, `acloud`). Standard library only means the only prerequisites are Python 3.11+ and git: nothing to `pip install` before the first command.

**What stays bash:** the wrappers around AOSP in `image/build/`, because AOSP's `envsetup.sh` and `lunch` are bash, and the scripts that run on the phone (`sh`). Platform-specific steps (winget and the Motorola driver on Windows, a package list on Linux) stay inside the commands, chosen by OS.

### The name: aosp-academy

**Decided** (the user): the project, the docs, the GitHub repository (`jim-wyatt/aosp-academy`, site `https://jim-wyatt.github.io/aosp-academy/`) and the command are **aosp-academy**. The Python package is `aosp_academy`; the image product is `aospacademy_arm64`; properties, directories on the phone, overlays and module names use `aospacademy`.

**Why:** the project is about learning AOSP on a real device. The rule is the user's: **no trademarks in the name**, so no "Android", "Moto", "droid" or other marks. The product has no underscore after `aosp` so that it can't be mistaken for one of Google's own `aosp_*` products.
