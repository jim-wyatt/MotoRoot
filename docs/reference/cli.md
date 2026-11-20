# Commands

Everything in this project runs through one command, `aosp-academy`. It is a Python 3 program that uses only the standard library, in `aosp_academy/`, and it works on Windows, Linux and macOS. From the repository folder, run it as:

| Where | How |
| --- | --- |
| Windows | `.\aosp-academy <command>` (the launcher `aosp-academy.cmd`) |
| Linux, macOS | `./aosp-academy <command>` |
| anywhere | `python -m aosp_academy <command>` with the repository folder as the current directory |

`aosp-academy --help` lists the commands and `aosp-academy <command> --help` the options of one; both come straight from `aosp_academy/cli.py`, which is the authority if this page and the code ever disagree.

A command that fails on something you have to act on prints `error: <what to do>` and exits with code 2. ++ctrl+c++ exits with 130. Commands that run checks (`check`, `device test`, `stock build`) exit with the number of failures.

Every command that talks to the phone uses the pinned `adb` in `work/platform-tools`, requires **exactly one authorized device**, and gets root with whichever `su` the running system has: Magisk's `su -c` on the stock system, AOSP's `su 0` inside an image built from source.

## The workstation

### `setup`

Installs and verifies the workstation. Idempotent: re-run it any time. Nothing in it talks to the phone. [Set up a workstation](../start/workstation.md#4-run-the-setup) has the full list of what it installs and where.

| Option | |
| --- | --- |
| `--studio` | also install Android Studio (Windows, through winget) |
| `--accept-sdk-licenses` | accept the Android SDK licenses non-interactively, after reading them |
| `--skip-system` | leave out winget (Windows) or the system package check (Linux, macOS) |
| `--skip-sdk` | leave out the Android SDK step |
| `--skip-inputs` | leave out the device procedure's inputs and the device tools |

It refuses to run from a network path, and stops on any download that doesn't match its pin, or on an existing file that doesn't.

### `check`

Tests the workstation end to end and never touches the phone: the JDK and SDK packages, the pinned tools, the stock artifacts rebuilt and compared, the module scripts, the unit tests, jadx, the NDK, `javac` against the pinned platform, the docs site, every shell script, every pinned input and APK signing certificate, and the git safety settings. Scratch output goes to `work/build/check` and is removed. Exit code: the number of failures.

### `shell`

Opens a shell at the repository root with the pinned tools first on PATH (`adb`, `fastboot`, the JDK, the SDK's command-line tools, the pinned build-tools and NDK, jadx, the Val Protocol and Frida environments, 7-Zip on Windows) and `ANDROID_HOME`, `JAVA_HOME`, `ANDROID_NDK_HOME` and `ADB` set. PowerShell 7 or `cmd` on Windows, `$SHELL` elsewhere. `exit` leaves it.

### `env [--shell pwsh|cmd|bash]`

Prints the same environment as statements for a shell, so you can load it into one you already have: `.\aosp-academy env | Invoke-Expression` in PowerShell, `eval "$(./aosp-academy env --shell bash)"` in bash. Default: `pwsh` (or `cmd` without PowerShell 7) on Windows, `bash` elsewhere.

### `docs [serve|build]`

`serve` (the default) previews this site with live reload at <http://localhost:8000>. `build` builds it into `site/` with `--strict --clean`, as CI does. Both use `work/.venv-docs`.

### `apktool ...` and `d8 ...`

Run the pinned apktool 3.0.3 and the pinned R8's D8 with the JDK from `JAVA_HOME`; every argument after the command name is passed through. [Inspect app packages](../apps/inspecting-apps.md) and [system helpers](../device/helpers.md) use them.

### `new-app <folder> --package <id> [--name N] [--build] [--test]`

Creates an Android app project set up for this phone, from `aosp_academy/templates/app`: a minimal Kotlin app and one instrumented test, on the `appTemplate` versions in `toolchain.json` (compileSdk and targetSdk 37, minSdk 26, the pinned build-tools, the Android Gradle Plugin and Gradle). It writes the project's Gradle wrapper with the pinned Gradle (downloaded into `work/tools/gradle` and checked on first use), with the distribution's SHA-256 in `gradle-wrapper.properties`. The folder must be new or empty; the package needs at least two lower-case segments. `--build` also builds the debug APK; `--test` also runs the instrumented test on the phone, which installs and then uninstalls the app and its test APK. See [Android Studio](../apps/android-studio.md#create-a-project).

### `adb-wifi`

Connects `adb` to the phone over Wi-Fi on port 5555. It reads the phone's Wi-Fi address over USB first, so the cable must be in, and it stops with a clear message, rather than timing out, when the phone and the PC are on different networks. Something on the phone must be listening on 5555: the image does from the first boot, the stock system does with the `dev_adb_tcp` module ([system modules](../device/modules.md)), and otherwise `adb tcpip 5555` over USB.

## The device node

### `fetch`

Copies the newest verified image from the build node into `work/device-tools/gsi/own/`, over `scp`.

| Option | |
| --- | --- |
| `--host`, `--user`, `--repo`, `--port` | the build node's address, SSH account, the repository's path there, and the SSH port if not 22 |
| `--save` | keep those in `work/remote-build.json` (git-ignored), so later runs need none of them |
| `--streams N` | parallel connections for the parts, 1 to 32 (default 8) |
| `--check` | only report whether a newer image is waiting; copy nothing |

It reads `<repo>/work/device-tools/gsi/own/system.img.sha256` on the build node first and does nothing if the local image already matches. Otherwise it pulls the published parts in parallel (or the single `system.img` when no parts are published), retries failed or mismatched parts up to three times with a growing pause, keeps the joined image only if its SHA-256 matches, then fetches `build.prop` (required) and `vbmeta.img` (if published) before replacing the previous image. Verified parts are kept on failure, so the next run resumes. `--check` knows the image last deployed (`deployed.sha256`), so "no local image" doesn't read as "something new". [Set up a build node](../start/build-node.md#publishing-and-how-the-device-node-reaches-it) covers how the build node publishes.

### `deploy`

Fetches, installs, boots and verifies the newest image on the phone, in one run. It takes the `fetch` options above, plus:

| Option | |
| --- | --- |
| `--no-fetch` | install the image already in `work/device-tools/gsi/own` |
| `--single-boot` | boot it once only (default: persistent, until `gsi stock`) |
| `--keep-image` | keep the local copy after installing |
| `--skip-device-test` | leave out the device test at the end |
| `--userdata-gib N` | the image's data partition, in GiB (default 24) |
| `-y`, `--yes` | don't ask before replacing the installed image |

The steps: fetch (unless `--no-fetch`); if the phone runs a DSU image, back to stock (DSU installs only from there); discard the installed image, install the new one and boot it; join the Wi-Fi network in `work/wifi.json` if that file exists; wait for the image's first-boot service; report what the image sets; run `device test`. Installing deletes the installed image's data, so it asks first. After the install the local copy is deleted and its hash kept in `deployed.sha256`: the build node keeps every build. Exit code 1 if you decline or if the device test fails. [Deploy and verify](../environment/deploying.md) explains each step and the report.

`work/wifi.json` is yours to write, and private (git-ignored, blocked by the hook): `{"ssid": "...", "security": "wpa2", "passphrase": "..."}`. The passphrase goes to the phone over USB only.

### `gsi <action>`

Runs a system image on the phone through DSU (Dynamic System Updates): it boots from a file in `/data`, on top of the phone's own vendor partition, and nothing is flashed. All actions except `download` need root on the phone.

| Action | |
| --- | --- |
| `status` | the DSU state, whether an image is running, which build is running, and whether Google's pinned GSI is downloaded and verified |
| `download` | Google's pinned GSI (`deviceTools.gsi`), into `work/device-tools/gsi/`, after you accept its terms with `--accept-google-gsi-terms` |
| `install` | push the zip (or your own `system.img`, wrapped in one, with `--image`) to Android's DSU installer and wait for it, up to 30 minutes; a phone with a secure lock screen asks for the PIN first |
| `boot` | enable the installed image and reboot into it; persistent unless `--single-boot` |
| `stock` | from a running image: disable it (it stays installed, with its data) and reboot to the phone's own system |
| `discard` | from the stock system: remove the installed image and its data |

| Option | |
| --- | --- |
| `--image PATH` | your own `system.img`, or a zip with one, instead of Google's GSI; `vbmeta.img` and `build.prop` beside it are packed too |
| `--userdata-gib N` | the image's data partition for `install` (default 8) |
| `--single-boot` | `boot` once only |
| `--accept-google-gsi-terms` | for `download`, after reading [Google's GSI terms](https://developer.android.com/topic/generic-system-image/releases) |

[DSU, GSIs and going back to stock](../device/dsu.md) explains when to use each.

### `device <what>`

Works with the connected phone.

| Command | |
| --- | --- |
| `device test [--skip AREAS]` | exercises every development workflow on whatever system is running, and leaves nothing behind. Areas: `device` (identity, build type, SELinux), `root`, `logs` (logcat, buffer size, dumpsys), `native` (an NDK binary built here, run there), `app` (an APK built with the SDK tools alone: installed, launched, its log line read back, uninstalled), `debug` (`adb root` on images, how many processes accept a debugger), `trace` (a 2-second Perfetto trace), `frida`, `mirror` (scrcpy reaches the device; no window). `--skip frida,mirror` leaves areas out. Exit code: the number of failures. |
| `device settings [--reset]` | the development-target settings on the stock system: Developer options shown, Stay awake, manual brightness at 64/255, animations off, adb installs not sent to Play Protect, no expiry of adb authorizations, 16 MiB log buffers (persistent with root). `--reset` puts the stock values back. The image sets these itself at first boot. |
| `device try [--rerun] [--undo]` | runs the repository's first-boot script on the running image without a build: bind-mounts `image/product/aospacademy/gsi/firstboot/aospacademy-firstboot.sh` over `/product/bin/aospacademy-firstboot` as root, and checks that init sees it. Nothing is written to a partition and verity is untouched; a reboot or `--undo` restores the built-in script. `--rerun` clears the first-boot state and runs the service again, as on a fresh install. Only the script can be tried this way: `.rc` files, overlays and read-only properties need a build. |
| `device report` | what the running image sets, as at the end of `deploy`: fingerprint, home app, first-boot result, development settings, animations, log buffer, time zone, hidden icons, charge limit, network and time servers, built-in adb keys, Bluetooth, battery, the WireGuard tunnel, adb over TCP, crash log, free space |
| `device info [--label X] [--bugreport]` | a read-only hardware and software inventory into `work/device-info/<timestamp>[-label]/`. The raw dumps are **private** (serial, IMEI, MAC addresses, app list); `summary.txt` leaves identifiers out. `--bugreport` adds a full bugreport (several minutes). |
| `device trace [--seconds N] [--name X] [--config FILE]` | records a Perfetto system trace into `work/traces/<name>.pftrace` (default 10 s, 1 to 600; the name defaults to a timestamp). `--config` uses your own Perfetto text config. No root needed. Open it at <https://ui.perfetto.dev>. |
| `device frida start\|stop` | starts frida-server on the phone as root (idempotent), or stops it |
| `device mirror ...` | mirrors and controls the phone with scrcpy, through the pinned `adb`; everything after `mirror` goes to scrcpy |

The pages under [Develop apps](../apps/index.md) use these: [tracing](../apps/tracing.md), [instrumentation](../apps/instrumentation.md), [debugging](../apps/debugging.md).

### `stock <what>`

The stock system's preparation artifacts.

| Command | |
| --- | --- |
| `stock build [--promote]` | rebuilds the two helper DEX files (`javac --release 8`, then the pinned D8) and the seven Magisk module ZIPs into `work/build/stock` and compares them with the committed copies in `stock/`: helpers byte for byte, modules by content (their builds are deterministic). `--promote` copies changed artifacts over the committed ones. Exit code without `--promote`: the number that differ. |
| `stock magisk-image <backup>` | makes a Magisk-patched `init_boot` image **file** from your own `init_boot_a` backup (walkthrough stage 5): runs Magisk 31.1's patch script on the phone under temporary root and writes `work/magisk-patched-init_boot.img`. It never flashes, never changes a slot and never reboots, and every check (the pinned Magisk APK, exactly one device, the tested model, firmware and slot, root, your backup matching the phone's partition) runs before the phone is touched. |

## The build node

### `image <action>`

The build node's side, on any x86-64 Linux host. Every action except `inputs` refuses to run on Windows (run it inside WSL there). The AOSP steps are bash scripts in `image/build/`, because AOSP's `envsetup.sh` and `lunch` are bash.

| Action | Does | Script |
| --- | --- | --- |
| `inputs` | downloads and verifies the image's pinned inputs (the Fossify APKs, `buildOnly` in `toolchain.json`) into `work/device-tools` | |
| `setup` | installs AOSP's build dependencies, `repo` and `git-lfs` on this host (Debian or Ubuntu, with `sudo`) | `setup.sh` |
| `sync` | checks out the pinned AOSP tag into `$AOSP_DIR`, verifies the tree, applies this project's changes | `sync.sh` |
| `apply` | puts this project's product, patches, APKs and trusted adb keys into the tree | `apply-local.sh` |
| `build` | `inputs`, then apply, `lunch`, build, copy the image to `work/device-tools/gsi/own`, and publish to `$PUBLISH_DIR` if set | `build-image.sh` |
| `verify` | finds and resets projects that an interrupted checkout left with missing files | `verify-tree.sh` |

Settings come from the environment: `AOSP_DIR` (default `deviceTools.aosp.treeDir`), `JOBS`, `PUBLISH_DIR` and `PARTS` (default 16). `image/build/build-after-sync.sh` (run with `bash`, not through the CLI) chains a sync and a build for overnight runs. [Set up a build node](../start/build-node.md) and [build the image](../environment/building.md) cover them.
