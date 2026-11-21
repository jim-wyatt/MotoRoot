# Set up a build node

The **build node** turns this repository into a system image. It downloads the AOSP source at the pinned release, adds this project's product and patches, builds `aospacademy_arm64`, and publishes the result to a folder that the device node fetches from. It never needs the phone, unless it is the device node too ([One machine for both](#one-machine-for-both)).

Any x86-64 Linux host can be the build node: a Linux desktop, WSL2 on a Windows PC, a cloud VM, or a container on any of those. The project's own build node is a Lenovo Legion T5 desktop running the build in WSL2; nothing in the code assumes that.

This page sets the build node up. [Build the image](../environment/building.md) covers what happens inside a build and how to change what it builds.

## What the host needs

| Need | Why |
| --- | --- |
| x86-64 Linux, Debian or Ubuntu for `image setup` | AOSP builds only on x86-64 Linux. `image setup` installs packages with `apt-get`; on another distribution, install the same packages yourself (the list is in `image/build/setup.sh`). |
| A case-sensitive filesystem with about 400 GB free | The AOSP tree is 300 to 400 GB once it holds a build (the Android 17 tree on the project's build node used about 335 GB). It must not be on a Windows drive: in WSL2, keep it on WSL's own disk, never under `/mnt/c`, where the build is unsupported and very slow. |
| 16 cores and 32 GB of RAM | They make the first build a matter of hours rather than a day. Memory is the real limit; see [memory](#memory) below. |
| Python 3.11+, git, bash | The `aosp-academy` command, and the bash wrappers around AOSP's own scripts. |
| A network connection that can move a lot | The first sync downloads roughly 60 to 120 GB, even as a partial clone. |

On **WSL2**, raise the memory cap before the first build. WSL's default is half the machine's RAM, which gets the big link steps killed. In `%UserProfile%\.wslconfig` on the Windows side:

```ini
[wsl2]
memory=26GB
swap=32GB
```

Then `wsl --shutdown` to apply it. Those are the values for a 32 GB machine; on another, set `memory` to the RAM less about 6 GB. Swap started at 16 GB and was doubled after `soong_build` itself was killed for lack of memory.

## Get the repository

On the build node, clone the repository like on the workstation, into the Linux filesystem:

```bash
git clone https://github.com/jim-wyatt/aosp-academy.git
cd aosp-academy
```

The build node doesn't need `aosp-academy setup`: that sets up a workstation (SDK, phone tools, Python environments), and the image build uses AOSP's own toolchain from the tree instead. Builds are requested by branch and commit, so before each one `git switch` to the branch to build and `git pull`.

## The commands

All of these run from the repository folder and are safe to re-run. `image` refuses to run on Windows; on a Windows PC, run it inside WSL.

```bash
./aosp-academy image setup     # AOSP's build packages, repo, git-lfs, JDK 21 (minutes; uses sudo)
./aosp-academy image inputs    # the pinned Fossify APKs into work/device-tools (a minute)
./aosp-academy image sync      # the pinned AOSP release into $AOSP_DIR (hours the first time)
./aosp-academy image build     # inputs, apply, lunch, m, publish (hours the first time)
```

`image inputs` comes before the first sync because the sync ends by applying this project's changes to the tree, and that step stops if an APK it copies is missing.

| Command | What it does | Script |
| --- | --- | --- |
| `image setup` | Installs the build dependencies Google lists for AOSP, `repo` and `git-lfs`, sets a git identity if there is none (`repo` refuses to sync without one), and creates the tree's folder. | `image/build/setup.sh` |
| `image sync` | Runs `repo init` at the tag in `toolchain.json` (every time, so a moved tag takes effect on an existing tree) and `repo sync` as a partial clone, then checks the tree for projects an interrupted checkout left half-written and resets them, then applies this project's changes. Resumable: re-run it after an interruption. | `sync.sh`, `verify-tree.sh`, `apply-local.sh` |
| `image inputs` | Downloads the image's own inputs, the 16 Fossify APKs, into `work/device-tools/` and verifies each against its pinned SHA-256. | (Python) |
| `image apply` | Copies `image/product/aospacademy/` into the tree as `device/aospacademy/`, copies the APKs, applies the patches in `image/patches/` (skipping those already applied, stopping at one that no longer applies), and installs the trusted-PC keys if there are any (below). | `apply-local.sh` |
| `image build` | `image inputs`, then apply, `lunch aospacademy_arm64-trunk_staging-userdebug`, `m` (with the generated `build.prop` files removed first, so the image carries its own build date), and copies `system.img`, `build.prop` and `vbmeta.img` (when the build makes one) to `work/device-tools/gsi/own/` with a `system.img.sha256`. With `PUBLISH_DIR` set, it publishes as well. | `build-image.sh` |
| `image verify` | Only the tree check that `sync` runs: lists projects whose sole difference from their checked-out commit is missing files, and resets them. A project with edits of yours is listed and left alone. | `verify-tree.sh` |

To start a sync and the build after it and walk away, run the chaining script directly; it waits for a sync that is already running (and never starts a second one into the same tree), re-runs a failed sync once, then runs `build-image.sh` (which, unlike `aosp-academy image build`, doesn't fetch the inputs, so run `image inputs` first):

```bash
nohup bash image/build/build-after-sync.sh >/dev/null 2>&1 &
tail -n 5 work/aosp-sync.log work/aosp-build.log     # progress
```

Both logs are in `work/`, so they are never committed.

### Settings

The scripts take their settings from the environment, with defaults, so nothing assumes a particular user, path or machine:

| Variable | Default | Meaning |
| --- | --- | --- |
| `AOSP_DIR` | `deviceTools.aosp.treeDir` in `toolchain.json` (`~/aosp17`) | Where the AOSP tree lives. |
| `JOBS` | all cores for the build; half of them for the sync | Parallel jobs. Lower it if the build runs out of memory. |
| `PUBLISH_DIR` | unset: nothing is published | A folder to publish each finished image to, for the device node to fetch. |
| `PARTS` | `16` | How many pieces the published image is split into. |

For example: `JOBS=12 PUBLISH_DIR=/srv/images ./aosp-academy image build`.

### Trusted PCs (optional)

The image requires USB-debugging authorization (`ro.adb.secure=1`), and every deploy starts the image with empty data, so each new image would normally show *Allow USB debugging?* on the phone and wait for a tap. To skip that for your own PCs, put their **public** adb keys in `work/adb_keys` on the build node, one line each, copied from `adbkey.pub` in each PC's `~/.android/` folder (never the private `adbkey`). `image apply` builds them into the image as `/product/etc/security/adb_keys`. Without the file, the image trusts no PC in advance. The file is git-ignored and the hook blocks it, and an image built with it belongs to those machines: don't pass it on. The [decisions log](../reference/decisions.md) has the reasons.

## A build host in a container

`image/build/Containerfile` describes a reproducible build host: Ubuntu 26.04 with the packages AOSP lists, `repo`, `git-lfs` and JDK 21, building as an ordinary user (AOSP refuses to build as root). It is optional; the scripts run the same on any prepared host. The tree stays outside the container, on a case-sensitive filesystem, mounted at `/aosp`:

```bash
podman build -t aosp-academy-build -f image/build/Containerfile .      # or docker build
podman run --rm -it \
  -v "$PWD":/repo -v "$HOME/aosp17":/aosp -e AOSP_DIR=/aosp \
  -e PUBLISH_DIR=/repo/work/publish -e JOBS=16 \
  aosp-academy-build ./aosp-academy image build
```

Run `./aosp-academy image sync` the same way for the first sync.

## Memory

Memory, not CPU, is the limit, at two points.

**The R8 phase.** The C++ phase is fine on all cores, but the later phase runs R8 (Java bytecode optimisation) as one multi-gigabyte JVM per job. On the project's build node (32 cores, WSL capped at 26 GB), 32 of them fill the swap and the kernel's out-of-memory handler kills the build. `JOBS=12` keeps that phase inside memory. Nothing is lost by the kill: run the build again and ninja continues from the steps already done.

**Analysis.** Before compiling anything, `soong_build` analyses the whole product in one Go process, so `JOBS` can't help. Go's collector by default lets the heap grow to twice the live data before it runs. On `android-17.0.0_r1` that doesn't fit a 26 GB instance: unpatched, `soong_build` sits at 24 GB resident with 33 GB allocated, fills 32 GB of swap within minutes, stalls on memory for more than half of every second, and doesn't finish in 50 minutes.

The image carries a fix, `image/patches/build-blueprint-0001-soong-heap-limit-80-percent-of-ram.patch`: Blueprint sets the Go runtime's soft memory limit (`debug.SetMemoryLimit`) to 80 % of the machine's RAM, read from `/proc/meminfo`, so the collector runs before the heap leaves RAM, at a CPU cost only once the heap gets there. An environment variable can't do the same, because the bootstrap ninja starts `soong_build` with `env -i`, so `GOMEMLIMIT` never reaches it. The limit follows the machine, not the release, so the patch is harmless on a 64 GB host. With it, the analysis takes about 6.5 minutes. The live graph is still close to the whole instance (24 GB resident, swap peaking at 9 GB for a minute), so it is a fit, not a comfortable one.

If a later release outgrows this too, two levers are known and untried: a compressed swap device in the guest (the WSL kernel has `zram`: `zramctl --find --size 12G`, `mkswap`, `swapon -p 10`) would take the swapping off the disk; and `PRODUCT_SOURCE_ROOT_DIRS` can prune the module graph of trees the image never uses (of the 15,600 `Android.bp` files Soong parses on `android-17.0.0_r1`, about 3,000 are under `cts`, `platform_testing`, `development`, `test` and `tools`), at the risk of a missing-namespace error for anything the product still references.

## How long it takes

| Step | Time on the project's build node (32 cores, 32 GB) |
| --- | --- |
| First sync | a few hours, depending on the connection |
| First full build | about 2.5 hours |
| Soong analysis, with the heap patch | about 6.5 minutes |
| A rebuild after a change | minutes (incremental); about 15 minutes when Soong has to re-analyse the tree |

There is no ccache, on purpose: every build rule runs in AOSP's sandbox, which mounts only `out/` and `/tmp` writable, so ccache fails on its first write, and AOSP's own notes (`build/make/core/ccache.mk`) say it adds little over incremental builds.

## One machine for both

A build node that can reach the phone can also be the device node. The image then never leaves the machine: no `PUBLISH_DIR`, no SFTP account, nothing to fetch.

**What makes it work.** `image build` always leaves its image, `build.prop` and `vbmeta.img` in `work/device-tools/gsi/own/`, the folder `fetch` would fill on a device node. When no build node is configured (no `work/remote-build.json`, no `--host`), `aosp-academy deploy` installs the image in that folder and says so, instead of fetching. `--no-fetch` does the same explicitly.

**One checkout, two sides on Windows.** On a Windows PC with WSL2, keep a single checkout on the Windows drive. Build from WSL, and set up, deploy and work with the phone from Windows. Both sides see the same `work/` folder.

```bash
./aosp-academy image build          # in WSL, from /mnt/c/<path to the checkout>
```

```powershell
.\aosp-academy setup                # on Windows, once: adb, the SDK and NDK, the venvs
.\aosp-academy deploy               # installs the image WSL just built
```

Run `setup` and `check` on the Windows side only. The virtual environments in `work/` are made for the platform that ran `setup`, and the `image` commands don't use them. On a native Linux host there is only one side, and every command runs from the same shell.

**What the machine needs, besides a build node's needs:**

- **Its adb key built in.** Its `adbkey.pub` line goes in `work/adb_keys` before the build ([Trusted PCs](#trusted-pcs-optional)), so the phone authorises it from the first boot with no tap.
- **The private files a device node keeps:** `work/wifi.json` and, for the tunnel, `work/wireguard/wg0.conf` and `wg0.env` ([Deploy and verify](../environment/deploying.md#wifijson)). The tunnel config holds the phone's private key. Move it only between your own machines, over a channel you trust, and delete the old copy once the new machine deploys.
- **A network path the phone answers on.** Over USB there is nothing to arrange. Over the network, replies follow the phone's routes, not the machine's. The phone sends only the destinations in `ROUTES4` (in `wg0.env`) and its peer's `AllowedIPs` (in `wg0.conf`) into the tunnel. A machine that reaches the hub from another subnet gets no reply unless that subnet is in both, and the hub routes to it. The other way is for the machine to join the tunnel as a peer of its own.

**After a deploy** the local copy of the image is deleted, as on any device node (`--keep-image` keeps it). The next `image build` writes a new one. Since every build carries its own build date, a rebuild with no change still makes a new image with a new SHA-256.

## Publishing, and how the device node reaches it

A build with `PUBLISH_DIR` set writes, into that folder:

| File | What |
| --- | --- |
| `system.img.part00` ... `system.img.part15` | the image in `PARTS` pieces |
| `system.img.parts` | the SHA-256 of each piece |
| `system.img` | the whole image, for a puller that doesn't use parts |
| `system.img.sha256` | the whole image's SHA-256 |
| `build.prop` | the system build properties, including the fingerprint |
| `vbmeta.img` | when the build made one |

Each file is written under a temporary name and renamed, the old build's files go first, and the checksum is written last, so a fetch that overlaps a build never pairs a half-written image with the new checksum.

On the device node, `aosp-academy fetch` pulls these over `scp` (the OpenSSH client built into Windows 10 and later, Linux and macOS). It reads `system.img.sha256` first and stops if the local image already matches, pulls the parts over 8 parallel connections (`--streams N`, 1 to 32), checks each part and the joined image, retries failed parts up to three times, and fetches `build.prop` and `vbmeta.img` before replacing anything. On the project's two nodes, which reach each other through a VPN that limits each connection rather than the total, 8 streams bring 1.8 GB over in about 4.5 minutes instead of 13. [Deploy and verify](../environment/deploying.md) covers the rest of the loop.

`fetch` looks for the files in `<repo>/work/device-tools/gsi/own/` on the build node, where `<repo>` is the `--repo` you give it. There are two ways to arrange that:

- **Simple:** the device node logs in as your user on the build node, and `--repo` is the build node's checkout. `image build` always copies the image there. Without `PUBLISH_DIR`, though, nothing is split into parts, so `fetch` pulls the single file over one connection.
- **Separate and read-only (recommended):** set `PUBLISH_DIR` to a folder that a dedicated, key-only, read-only SFTP account sees as `<repo>/work/device-tools/gsi/own`, and give `fetch` that `<repo>`. The project's build node did this until it became its own device node ([One machine for both](#one-machine-for-both)).

How the build node is reached (SSH, a VPN, a firewall rule) is that host's own setup, not part of the project, and its address and account are private to your network.

### A read-only SFTP chroot

This is the tested setup, written generically: a system user with no shell and no home, chrooted into a folder that holds only the published image, allowed only read-only SFTP, with its own key. Pick your own user name, folder and port.

```bash
sudo apt-get install -y openssh-server
sudo useradd --system --no-create-home --home-dir / --shell /usr/sbin/nologin imgxfer
sudo install -d -m 755 /srv/imgxfer/repo/work/device-tools/gsi           # root-owned: required for a chroot
sudo install -d -o "$USER" -m 755 /srv/imgxfer/repo/work/device-tools/gsi/own
sudo install -d -m 755 /etc/ssh/authorized_keys
echo "<the device node's public SSH key line>" | sudo tee /etc/ssh/authorized_keys/imgxfer
sudo tee /etc/ssh/sshd_config.d/10-imgxfer.conf <<'EOF'
Port <port>
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers imgxfer
Match User imgxfer
    AuthorizedKeysFile /etc/ssh/authorized_keys/%u
    ChrootDirectory /srv/imgxfer
    ForceCommand internal-sftp -R
    AllowTcpForwarding no
    AllowAgentForwarding no
    X11Forwarding no
    PermitTTY no
EOF
sudo sshd -t && sudo systemctl daemon-reload && sudo systemctl enable --now ssh.socket
```

The key can't reach your home folder, your other keys or the Windows drives. Build with `PUBLISH_DIR=/srv/imgxfer/repo/work/device-tools/gsi/own`. On the device node, once:

```text
aosp-academy fetch --host <address> --user imgxfer --port <port> --repo /repo --save
```

`--save` keeps the address, account, port and path in `work/remote-build.json`, which is git-ignored, because they describe your network rather than the project. After that, `aosp-academy fetch` fetches and `aosp-academy fetch --check` only reports whether a new image is waiting.

??? note "If the build node is WSL2 on Windows"
    - For the device node to reach a server inside WSL, set `networkingMode=mirrored` under `[wsl2]` in `.wslconfig`, so WSL shares the Windows address, and allow the port through the Hyper-V firewall, which filters WSL's inbound traffic. In an elevated PowerShell: `New-NetFirewallHyperVRule -Name ImageSFTP-In -DisplayName 'Image SFTP (WSL)' -Direction Inbound -VMCreatorId '{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}' -Protocol TCP -LocalPorts <port> -RemoteAddresses <the device node's subnets>`.
    - WSL stops when nothing runs in it, so the server is reachable only while a build or a WSL window is open.
    - Why not Windows' own OpenSSH server: on a hardened Windows (the STIG setting *Deny access to this computer from the network* including **Local account**, `S-1-5-113`), Windows' sshd can't perform the network logon a local account needs. It drops the connection right after `SERVICE_ACCEPT`, with no `Permission denied` and nothing in its log. Running the server inside WSL, where Linux does the login, avoids weakening that policy.

!!! warning "Test-keyed images stay on your own machines"
    The image is signed with AOSP's public test keys, not a release key, and may carry your PCs' adb keys. Copy it only between your own machines, never through a public service.

## Things to know

- **The scripts are plain bash, on purpose.** `build-image.sh` doesn't use `set -e` or `set -u`: AOSP's `envsetup.sh` reads unset variables and `lunch` returns non-zero on its way to success, so strict mode would abort the build in its first second. Failures are checked explicitly instead.
- **Keep them LF.** bash reads a `\r` at the end of a line as part of the command (`set: pipefail\r: invalid option name`). `.gitattributes` normalises line endings on commit, but a Windows editor can still hand a CRLF copy to WSL; `sed -i 's/\r$//' image/build/*.sh` repairs it, and `aosp-academy check` and CI parse every script.
- **`git-lfs` is required.** Several prebuilts projects keep their files in Git LFS; without it their checkout fails with `Cannot initialize work tree` while the rest of the sync carries on. `image setup` installs it, and `sync` refuses to start without it.
- **Lunch names.** If `lunch` rejects the pinned target after a sync, `lunch` with no arguments (in the tree, after `source build/envsetup.sh`) lists what the release offers, and `deviceTools.aosp.lunch` in `toolchain.json` is the one place to change it.

Next: [prepare the phone](../device/walkthrough.md), then deploy, or [your first session](first-session.md).
