# Build your own system image

[Running a GSI through DSU](../device/gsi.md) proved that this device's vendor layer will run a system it has never seen. That system is what AOSP builds from source as the `aosp_arm64` target, the very same target behind Google's image. Build it yourself and you have a system image you can change anything in, booted on the phone the same safe way. This page sets that up.

## What you get, and what you don't

Yours to change: the framework, system services, the launcher, Settings, system apps, SELinux policy for the system side, and the build type: a `userdebug` build is the real engineering build this project has been approximating, with `adb root` that works and debuggers that attach to anything. Also yours: fixing what the stock GSI gets wrong on this hardware, such as the `gpuservice` crash loop, with the source in front of you.

Not yours: the kernel, the vendor HALs, firmware and the modem. They stay Motorola's, under the Treble interface, and the GSI's hardware gaps (two of three cameras, for example) are limits of that interface rather than of your build. A full device port is a different, much larger project.

## Where the build lives

The AOSP tree is 300–400 GB with its output, needs a case-sensitive Linux filesystem, and builds very slowly across WSL's `/mnt/c` boundary, so it lives on **WSL's own disk** (`~/aosp` in the Ubuntu instance), not in this repository and not on a Windows path. This repository drives it: the scripts in `dev/aosp/` run inside WSL, and the finished image comes back to `work\device-tools\gsi\own\`, where `Install-Gsi.ps1` boots it.

Requirements that matter: 16 cores and 32 GB of RAM make the first build a matter of hours rather than a day; WSL's default memory cap is half of RAM, which gets the big link steps killed, so `%UserProfile%\.wslconfig` sets `memory=26GB` and `swap=32GB` under `[wsl2]` (apply with `wsl --shutdown`); on another machine, set `memory` to the RAM less about 6 GB. Swap started at 16 GB and was doubled after `soong_build` itself was OOM-killed during analysis. Disk: the WSL instance here has a 1 TB virtual disk.

Even so, the first build on this machine was killed by the kernel's out-of-memory handler at 76 %: the C++ phase is fine on all 32 cores, but the later phase runs R8 (dex optimisation) as one multi-gigabyte JVM per job, and 32 of them filled the 16 GB of swap. `build-gsi.sh` takes a `JOBS` override for that: `wsl -- env JOBS=12 bash dev/aosp/build-gsi.sh` (or the same for `build-after-sync.sh`) resumes the build with 12 jobs and stays inside memory. Nothing is lost by the kill; ninja continues from the steps already done.

## The pin

`deviceTools.aosp` in `dev/toolchain.json` names the release tag **`android-16.0.0_r4`**, the AOSP release that produced the GSI binary `BP4A.251205.006` validated on this device, so what you build is what was tested, before you change anything. The lunch target is `vedotom_arm64-trunk_staging-userdebug`, this project's product on top of `aosp_arm64` (see *Changing something*).

## Steps

From a dev shell (each script runs inside WSL and is safe to re-run). `wsl --` runs in your default distribution, whatever its name (`Ubuntu`, `Ubuntu-26.04`, ...); `wsl -l -v` marks it with `*`, and `wsl -d <name> --` picks another:

```powershell
wsl -- bash dev/aosp/setup.sh       # build dependencies, repo, git-lfs, JDK (minutes)
wsl -- bash dev/aosp/sync.sh        # repo init at the tag + partial-clone sync (hours, ~120 GB)
wsl -- bash dev/aosp/build-gsi.sh   # lunch + m; copies system.img back (hours the first time)
```

Or chain the two long steps and walk away:

```powershell
wsl -- bash dev/aosp/build-after-sync.sh   # waits for a running sync, or runs one; then builds
Get-Content $Work\aosp-sync.log -Tail 5; Get-Content $Work\aosp-build.log -Tail 5   # progress
```

`sync.sh` logs to `work\aosp-sync.log` and ends with a `sync exit:` line; `build-after-sync.sh` waits for that line (it recognises a sync already running in another window and never starts a second one into the same tree), re-runs a failed sync once, and then runs `build-gsi.sh` with its output in `work\aosp-build.log`. Both logs are inside `work\`, so they are never committed.

`sync.sh` uses a partial clone (`--partial-clone --clone-filter=blob:limit=10M --depth=1`), which keeps the first download to roughly a quarter of a full checkout and is resumable: re-run it after an interruption. After every sync it runs `verify-tree.sh`, because an interruption *during a checkout* leaves a project with the right HEAD and a half-written work tree, which the next `repo sync` reports as fine; the first build then fails far from the cause (`unrecognized module type "llvm_prebuilt_library_static"` was `prebuilts/clang/host/linux-x86` missing its `soong/` directory and 38,979 other files). The verifier finds projects whose only differences from HEAD are missing files and resets them; a project with any edit of yours is listed and left alone. It refuses to start without `git-lfs`: several prebuilts projects (`prebuilts/jdk/jdk8`, `prebuilts/tools`, `prebuilts/bundletool`, `prebuilts/bazel/common`) store their binaries in Git LFS, and without the filter they fail with `Cannot initialize work tree` while the rest of the sync continues. `build-gsi.sh` sources `build/envsetup.sh`, runs `lunch` with the pinned target and `m` with all cores, and copies `system.img` (plus `vbmeta.img` and `build.prop`) to `work\device-tools\gsi\own\`. A second build after a change is incremental: minutes, not hours.

Then boot your build exactly like Google's, one-shot, nothing flashed:

```powershell
.\dev\Install-Gsi.ps1 -Action Install -Image "$Work\device-tools\gsi\own\system.img"   # wraps it in a zip for the DSU installer; confirm on the phone
.\dev\Install-Gsi.ps1 -Action Boot
& $adb shell getprop ro.build.fingerprint     # yours, with test-keys
& $adb root                                   # works on a userdebug build
```

## What the first build established

On the validated device (2026-11-16): the image built from the pinned tag reproduces Google's GSI build id `BP4A.251205.006`, the DSU installer accepts a test-keyed image on this unlocked device, and `adb root` works in the resulting `userdebug` system. Hardware support is identical to Google's binary, which is expected: it is the same source. The one visible defect is also shared, and now explained: `gpuservice` aborts every 30 seconds in `GpuWork::initialize()` because the Motorola kernel does not carry the GPU-work BPF program that AOSP's GPU service expects. That is a system-side crash in code you now have, so it is the natural first patch. Timing on a 32-core, 32 GB machine: 2 h 35 min including a restart; see the memory note above.

## What's in the image

The product tree `dev/aosp/product/vedotom/gsi/` is the whole description. `vedotom_arm64.mk` is upstream's `aosp_arm64.mk` with one substitution: the product-partition app list comes from `vedotom_product.mk` and `vedotom_handheld_product.mk`, copies of the upstream `aosp_product.mk` and `handheld_product.mk` with the apps the Fossify suite replaces removed. The system partition is the stock GSI's, unchanged except for the patches.

**The Fossify suite** (GPL-3.0, the maintained successor of Simple Mobile Tools, built and signed by Fossify and distributed by F-Droid) is the only thing added on top of AOSP. It replaces the AOSP apps one for one: Launcher for Launcher3's home screen, Gallery for Gallery2, Calendar, Contacts, Clock for DeskClock, Phone for Dialer, Messages for `messaging`, Music Player for Music, Camera for Camera2, Calculator; and adds File Manager, Documents, Notes, Voice Recorder, Paint and Keyboard. Every APK is pinned in `dev/toolchain.json` by SHA-256 and signing certificate, verified against F-Droid's signed index when pinned, downloaded by the bootstrap into `work\device-tools\`, and copied into the tree by `apply-local.sh` from the list in `prebuilt/apks.txt`; no APK is ever committed. `prebuilt/Android.bp` imports them `preprocessed`, so Soong checks alignment and copies them unmodified, with the publisher's signature intact. Nothing updates them on the device: there is no app store in the image, so a new version means a new pin and a new image.

There is **no web browser** in the image, by design. Browser2, AOSP's WebView test shell, is left out, and WebView still renders web content inside apps. The F-Droid client is not in the image either; it stays pinned in `dev/toolchain.json` for the stock system.

What stays from AOSP, deliberately: Launcher3QuickStep (SystemUI binds its quickstep service for gesture navigation and recents; Fossify Launcher is made the home screen by the first-boot service assigning it the HOME role: both answer HOME with equal priority, so Android would otherwise ask, and a `preferred-apps` file turned out not to be honoured reliably), LatinIME beside Fossify Keyboard (a working keyboard must never depend on a prebuilt), DocumentsUI (the system file picker; only its launcher icon is hidden, below), Settings, and everything delivered as a Mainline module. The framework overlay names Fossify Phone and Messages as the default dialer and SMS app through `config_defaultDialer` and `config_defaultSms`.

**Defaults the image sets.** Dark theme and gesture navigation (the framework overlay), no boot animation, and the time zone `America/New_York` (`persist.sys.timezone` in the product `build.prop`). Without a SIM the telephony suggestion isn't applied, and AOSP without GMS has no location time-zone provider, so the device would otherwise start in GMT. A zone chosen later in Settings is stored in `/data` and wins; change the default in `vedotom_arm64.mk` for another region.

**The first-boot service.** `vedotom-firstboot` is a `sh_binary` that `init.vedotom.rc` starts once `sys.boot_completed` is set, as root in the userdebug-only `su` domain. It does four things, each once, with a marker in `/data/local/vedotom-firstboot/` so later boots do nothing and a later choice of yours is kept:

1. It gives Fossify Launcher the HOME role.
2. It applies the development settings that `dev\Set-DevSettings.ps1` applies on the stock system: window, transition and animator scales 0, `verifier_verify_adb_installs` 0 and `adb_allowed_connection_time` 0. SettingsProvider has resource defaults for only the first two in this tag, so all five are set here.
3. It hides the AOSP Files icon by disabling DocumentsUI's launcher alias, `com.android.documentsui/.LauncherActivity`, which this tag doesn't gate on any resource. Fossify File Manager is the file app. DocumentsUI itself stays, because its picker is behind every open, get-content and save dialog; `pm enable` on the same component brings the icon back.
4. It sets the Fossify launcher icons to teal, to match the wallpaper. Inside the apps Fossify already uses the system's Material You colours on Android 12 and later; the icon colour is a separate per-app choice, stored as one enabled `SplashActivity.<Colour>` alias plus two preferences the app reconciles on every start. The service sets all three.

It records what it did where the log buffers can't lose it: every line goes to `/data/local/vedotom-firstboot/log` with a time, and `status` holds `running` and then `done failures=<n>`. `Deploy-Image.ps1` reads those two files.

**Log buffers** are 16 MiB on every boot, not logd's 256 KiB, which the vendor's log spam rolls over within minutes. A property can't do it: logd in this tag reads `ro.logd.size` and `persist.logd.size` at start only on automotive and desktop hardware types (`system/logging/logd/LogSize.cpp`). So `init.vedotom.rc` runs `logcat -G 16M` as soon as logd sets `logd.ready`, which also re-applies it after a logd restart. `adb logcat -g` shows the size.


## Changing something

Changes live in this repository, not only in the tree, and `apply-local.sh` (run by `sync.sh` and `build-gsi.sh`, safe to re-run) puts them into the tree:

- **`dev/aosp/product/vedotom/gsi/`** is copied to `device/vedotom/gsi/` and defines the lunch target **`vedotom_arm64`**: AOSP's `aosp_arm64` with this project's settings layered on top. `aosp_arm64.mk` hides its GSI-specific settings behind a check on the product name, so the derived product repeats them, the same way AOSP's own `aosp_arm64_fullmte.mk` does. This is where product-level changes go: properties, packages, files copied into the image. The first one is `debug.sf.nobootanimation=1`, which removes the boot animation (the screen stays on the bootloader's splash until the lock screen); the makefile shows the one-line alternative for shipping your own `bootanimation.zip` instead.
- **`dev/aosp/patches/`** holds unified diffs against upstream projects, one project per file, named `<project-path-with-dashes>-NNNN-<what>.patch`. They are applied with `git apply` and skipped when the tree already has them; a patch that no longer applies after a tag change stops the script so you rebase it deliberately. The first one fixes the `gpuservice` crash loop: `BpfMap`'s path constructor aborts the process when a pinned BPF map is missing, so the `isValid()` check in `GpuWork::getBpfMap` never ran on a kernel without the `gpu_work_period` tracepoint; the patch uses `init()`, which reports the failure, and GPU-work tracking is simply disabled.

`verify-tree.sh` lists `frameworks/native` as a project with local changes and leaves it alone; that is the patch.

Both changes were confirmed on the device the same evening: the image boots with no animation and `gpuservice` stays up, logging one warning instead of dying every 30 seconds. The rebuild after switching products took 15 minutes, most of it Soong re-analysing the tree for the new product name. One rule to know: the GSI forbids `PRODUCT_SYSTEM_PROPERTIES` (its artifact-path requirement), so properties go in `PRODUCT_PRODUCT_PROPERTIES`, which lands in the product partition's `build.prop` (under `/system/product/etc/` in a GSI) and is read just the same.

The inner loop is: edit under `~/aosp` (in WSL; a VS Code *WSL* window is handy for that), `build-gsi.sh` again, `Install-Gsi.ps1 -Action Discard` then `-Action Install -Image …` and `-Action Boot`. Good first targets: `frameworks/base` for the framework, `packages/apps/Settings`, `packages/apps/Launcher3`, `system/sepolicy` for policy; `build/make/target/product/gsi_release.mk` and `aosp_arm64.mk` for what goes into the image. `m <module>` builds one module; `m` builds the image.

## Building on one machine, installing from another

The machine that builds and the machine the phone is plugged into don't have to be the same. The project's own setup builds on a desktop in another office and installs from the PC beside the phone; the two reach each other over a site-to-site VPN. The build machine runs the AOSP tree as described above. The install machine needs only the Windows bootstrap, not WSL or the tree.

`build-gsi.sh` writes `system.img.sha256` beside the image. On the install machine, `dev\Get-RemoteImage.ps1` copies the newest image from the build machine over SSH, using Windows' built-in OpenSSH client:

1. It reads the remote checksum first and stops if the local image already matches.
2. It copies into a `.part` file and keeps it only when its SHA-256 matches.
3. It keeps the image it replaces as `system.prev.img`.

Then install as usual from the stock system.

One-time setup on the **build machine**, in an elevated PowerShell:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic; Start-Service sshd
# Authorise the install machine's public key (~\.ssh\id_ed25519.pub there). For an account in
# Administrators, Windows' sshd reads this one file, which must be readable by admins and SYSTEM only:
Add-Content C:\ProgramData\ssh\administrators_authorized_keys '<the install machine''s public key line>'
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant '*S-1-5-32-544:F' /grant 'SYSTEM:F'
```

The first command also creates a firewall rule that opens port 22 to any address. Narrow it to the addresses the install machine connects from, with `Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress ...`. Once key login works, set `PasswordAuthentication no` in `C:\ProgramData\ssh\sshd_config` and restart `sshd`, so the server accepts keys only.

**If Windows' sshd resets every login.** A hardened Windows (the STIG setting *Deny access to this computer from the network* including **Local account**, `S-1-5-113`) refuses the network logon Windows' sshd needs for a local account. sshd then drops the connection right after `SERVICE_ACCEPT`, with no `Permission denied` and nothing in its log. Instead of weakening that policy, run the server inside the build machine's WSL, where Linux does the login. The tested setup is a read-only SFTP chroot that holds only the published image, with its own user, so the key can't reach your home folder, your keys or `/mnt/c`:

```bash
sudo apt-get install -y openssh-server
sudo useradd --system --no-create-home --home-dir / --shell /usr/sbin/nologin vedotom-xfer
sudo install -d -m 755 /srv/vedotomxfer/repo/work/device-tools/gsi          # root-owned: required for a chroot
sudo install -d -o "$USER" -m 755 /srv/vedotomxfer/repo/work/device-tools/gsi/own
sudo install -d -m 755 /etc/ssh/authorized_keys
echo "<the install machine's public key line>" | sudo tee /etc/ssh/authorized_keys/vedotom-xfer
sudo tee /etc/ssh/sshd_config.d/10-vedotom-xfer.conf <<'EOF'
Port 2222
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers vedotom-xfer
Match User vedotom-xfer
    AuthorizedKeysFile /etc/ssh/authorized_keys/%u
    ChrootDirectory /srv/vedotomxfer
    ForceCommand internal-sftp -R
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
EOF
sudo sshd -t && sudo systemctl daemon-reload && sudo systemctl enable --now ssh.socket
```

Build with `PUBLISH_DIR` set, and `build-gsi.sh` copies the image, its checksum and `build.prop` into the chroot as well (written under temporary names and renamed, checksum last): `wsl -- env JOBS=16 PUBLISH_DIR=/srv/vedotomxfer/repo/work/device-tools/gsi/own bash dev/aosp/build-after-sync.sh`. For the install machine to reach WSL, set `networkingMode=mirrored` in `.wslconfig` (WSL then shares the Windows address) and allow the port through the Hyper-V firewall, which filters WSL's inbound traffic, in an elevated PowerShell: `New-NetFirewallHyperVRule -Name VedoTom-SFTP-In -DisplayName 'VedoTom image SFTP (WSL)' -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts 2222 -RemoteAddresses <install machine's subnets>`. WSL stops when nothing runs in it, so the server is reachable while a build or a WSL window is open. On the install machine, pass `-Port 2222 -User vedotom-xfer -RemoteRepo /repo`.

Then, once, on the **install machine**:

```powershell
.\dev\Get-RemoteImage.ps1 -BuildHost <address> -User <account> -RemoteRepo C:/path/to/VedoTom -Save
```

The address, account and path are saved in `work\remote-build.json`, which is git-ignored, because they describe your network rather than the project. After that, `.\dev\Get-RemoteImage.ps1` fetches and `-Check` only reports whether a new image is waiting. Images are test-keyed builds: copy them only between your own machines, never through a public service.

To take a delivered image all the way onto the phone, run this on the install machine:

```powershell
.\dev\Deploy-Image.ps1
```

It fetches the newest image and reboots the phone to the stock system if a VedoTom image is running. Then it discards the installed image, installs and boots the new one, and waits for the first-boot service's `status` file. It ends with the fingerprint, the HOME role holder, what the first-boot service did, the defaults it checks (animation scales, log buffer size, time zone, the hidden Files icon) and the crash log. It asks before starting, because the install deletes the old image's data. `-NoFetch` installs the image already on this PC.

## Open work

[The image backlog](image-backlog.md) lists what the 2026-11-17 review of the image found, and which items are done.

## Things to know

- **Signing.** Your image is signed with AOSP's public test keys, not Google's. On this unlocked device the DSU installer accepted Google's image while unable to extract a trusted key, and `gsid` doesn't enforce trusted keys in the `orange` boot state, so a test-keyed image is expected to install; the first `-Action Install` confirms it. Never ship or publish a test-keyed image as if it were a release.
- **Licensing.** AOSP is Apache-2.0 (with GPL kernel sources you aren't building). Google's GSI terms apply to Google's binary, not to your own build. Nothing from Motorola's vendor partition is part of what you build or distribute.
- **Size.** Google's GSI unsparsed to 1.8 GB; `aosp_arm64` with `userdebug` is similar. The DSU installer handles sparse images.
- **The scripts are plain bash, on purpose.** `build-gsi.sh` does not use `set -e` or `set -u`: AOSP's `envsetup.sh` reads unset variables (`TOP`) and `lunch` returns non-zero on its way to success, so strict mode aborts the build in its first second. Failures are checked explicitly instead. The scripts must also keep **LF line endings**: WSL's bash reads a `\r` at the end of every line as part of the command (`set: pipefail\r: invalid option name`, `cd: ...\r: No such file`). `.gitattributes` normalises them on commit, but a Windows editor or a tool that rewrites the file can hand WSL a CRLF copy; `sed -i 's/\r$//' dev/aosp/*.sh` repairs it, and the self-test parses each script with `bash -n`.
- **No ccache.** Every build rule runs in AOSP's sandbox (nsjail), which mounts only `out/` and `/tmp` writable, so ccache fails with `Read-only file system` on its first write and the build stops. AOSP's own notes (`build/make/core/ccache.mk`) say it adds little over incremental builds, which is what you get anyway.
- **Lunch names.** Release tags occasionally rename release configurations; if `lunch` rejects the pinned target after a sync, `lunch` with no arguments lists what the tag offers, and the pin in `toolchain.json` is the one place to change it.

Next: [Your first app in Android Studio](android-studio.md).
