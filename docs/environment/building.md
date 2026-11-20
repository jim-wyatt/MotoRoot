# Build the image

This page is the build node's side of the [change loop](index.md#the-change-loop): from a commit of this repository to a published `aospacademy_arm64` image. Setting up the build node the first time (the host, the packages, the publish folder) is in [Set up the build node](../start/build-node.md); this page assumes that is done.

Everything here runs on the build node, from the repository root, through the CLI:

| Command | Runs | What it does |
| --- | --- | --- |
| `./aosp-academy image inputs` | (Python) | Downloads the image's pinned inputs, the 16 Fossify APKs (`buildOnly` in `toolchain.json`), into `work/device-tools/` and checks each against its SHA-256. |
| `./aosp-academy image setup` | `image/build/setup.sh` | Installs AOSP's build dependencies, `repo`, `git-lfs` and JDK 21 (Ubuntu packages), sets a neutral git identity if none is set (`repo` refuses to sync without one), and creates the tree's directory. Idempotent. |
| `./aosp-academy image sync` | `image/build/sync.sh` | `repo init` at the pinned tag and `repo sync`, then `verify-tree.sh` and `apply-local.sh`. |
| `./aosp-academy image apply` | `image/build/apply-local.sh` | Puts this repository's product, APKs, trusted keys and patches into the tree. |
| `./aosp-academy image build` | `image inputs`, then `image/build/build-image.sh` | Apply, lunch, build, copy the image out, and publish it if `PUBLISH_DIR` is set. |
| `./aosp-academy image verify` | `image/build/verify-tree.sh` | Finds and repairs half-checked-out projects in the tree. |

The AOSP steps stay in bash because AOSP's own `envsetup.sh` and `lunch` are bash. The commands refuse to run on Windows: the image builds on Linux (native, WSL2, a VM or a container). `image/build/build-after-sync.sh` has no CLI wrapper; run it with `bash image/build/build-after-sync.sh` (below).

## Settings

The scripts read three settings from the environment, with defaults:

| Variable | Default | Meaning |
| --- | --- | --- |
| `AOSP_DIR` | `deviceTools.aosp.treeDir` in `toolchain.json` (`~/aosp17`) | The AOSP tree. |
| `JOBS` | all cores (`nproc`) for the build; half of them for the sync | Parallel jobs. See [Memory](#memory). |
| `PUBLISH_DIR` | unset | Where to publish the finished image for the device node. Unset: the image is only copied to `work/device-tools/gsi/own/`. |
| `PARTS` | `16` | How many parts the published image is split into. |

The tag (`deviceTools.aosp.tag`), the manifest URL and the lunch target (`deviceTools.aosp.lunch`) come from `toolchain.json`, so a branch that changes them changes what is built. [Pins](../reference/pins.md) lists them.

For a reproducible host, `image/build/Containerfile` describes one (Ubuntu with AOSP's packages, `repo`, `git-lfs` and JDK 21, building as an ordinary user because AOSP refuses to build as root). The tree stays outside the container on a case-sensitive filesystem, mounted at `/aosp`; the file's header shows the `podman run` line.

## Where the tree lives

The AOSP tree is 300 to 400 GB with its build output and needs a case-sensitive Linux filesystem. It is never in this repository. On a WSL2 build node it lives on WSL's own disk, not on a Windows path: building across the `/mnt/c` boundary is unsupported and very slow.

`sync.sh` uses a partial clone (`--partial-clone --clone-filter=blob:limit=10M --depth=1`), which keeps the first download to roughly a quarter of a full checkout (about 120 GB; the Android 17 tree uses about 335 GB with its output) and is resumable: re-run it after an interruption. It runs `repo init` every time, not only on a new tree, because on an existing tree that is what moves the manifest to a new tag after `deviceTools.aosp.tag` is bumped. It refuses to start without `git-lfs`: several prebuilts projects (`prebuilts/jdk/jdk8`, `prebuilts/tools`, `prebuilts/bundletool`, `prebuilts/bazel/common`) keep their binaries in Git LFS and otherwise fail with `Cannot initialize work tree` while the rest of the sync carries on.

To sync and build in one go and walk away, run `bash image/build/build-after-sync.sh` in the background. It waits for a `sync.sh` already running (it recognises one by its `repo` process and never starts a second into the same tree), or runs one; re-runs a failed sync once (repo sync only redoes what failed); then runs `build-image.sh`. Its logs are `work/aosp-sync.log` (ending in a `sync exit: N` line) and `work/aosp-build.log`. The sync log is appended across runs, so the script records its size at start and judges only the last `sync exit:` line written after that.

## What apply-local.sh does

`apply-local.sh` puts this repository's changes into the tree. `sync.sh` and `build-image.sh` both run it, it is safe to re-run, and it exits non-zero on the first failure, which stops the build. It works in four steps:

1. **Products.** Each directory under `image/product/` is copied with `rsync -a --delete` to `device/<name>/` in the tree: `image/product/aospacademy/` becomes `device/aospacademy/`, and `device/aospacademy/gsi/` defines the `aospacademy_arm64` lunch target. `--delete` keeps the tree's copy identical to the repository's, removed files included; the APKs and the keys file are the only things the tree has that the repository doesn't.
2. **Prebuilt APKs.** For each line of `prebuilt/apks.txt` (`<module APK name> <pinned file>`), the pinned file is copied from `work/device-tools/` into the tree's `prebuilt/` directory, only when it differs. A missing file stops the script with "run `./aosp-academy image inputs`".
3. **Trusted adb keys.** If `work/adb_keys` exists (git-ignored; one `adbkey.pub` line per PC, see [What's in the image](image.md#adb-authorisation-and-the-trusted-keys)), it is stripped of CRs and blank lines, checked (every line must look like `QAAAA... user@host`), and copied to `device/aospacademy/gsi/adb_keys`. If it doesn't exist, the tree's copy is removed, and the image trusts no PC in advance.
4. **Patches**, below.

### Patches

Each file in `image/patches/` is a unified diff against **one** upstream project, named

```text
<project-path-with-dashes>-NNNN-<what>.patch
```

The project path is everything before `-NNNN-`, with every dash turned back into a slash: `frameworks-base-0001-vibrator-....patch` is applied inside `frameworks/base`, `build-blueprint-0001-....patch` inside `build/blueprint`. That mapping breaks for a project with a dash in its own path (`prebuilts/build-tools`, for example); no current patch needs one.

For each patch, `apply-local.sh`:

- skips it if `git apply --reverse --check` passes (the tree already has it);
- applies it with `git apply` if `git apply --check` passes;
- otherwise **stops** with "does not apply ... rebase it against this tag". A patch is never half-applied: after a tag move you rebase it deliberately, or delete it if upstream now has the fix (as happened to the `gpuservice` patch on Android 17).

[What's in the image](image.md#the-patches) gives the reason for each patch. To make a new one, edit the project in the tree, then `git -C <project> diff > image/patches/<project-with-dashes>-NNNN-<what>.patch` from the tree root, and keep one project per file.

## Lunch and the build

`build-image.sh` then sources `build/envsetup.sh`, runs `lunch` with the pinned target (`aospacademy_arm64-trunk_staging-userdebug`) and `m -j$JOBS`. If `lunch` rejects the target (release tags occasionally rename release configurations), `lunch` with no arguments in the tree lists what the tag offers, and `deviceTools.aosp.lunch` in `toolchain.json` is the one place to change it.

Between `lunch` and `m`, the script deletes the generated `build.prop` files under `out/soong/.intermediates` (`system-build.prop`, `system_ext-build.prop`, `product-build.prop`), so that **every build carries its own build date**. `soong_ui` writes the current time to `out/build_date.txt` on every run, but the `build_prop` module reads that file as an order-only input, deliberately (`build/soong/android/build_prop.go`: "shouldn't depend on BUILD_DATETIME_FILE to prevent from rebuilding on every incremental build"). So an incremental build in which nothing else feeding `build.prop` changed kept the previous build's `ro.build.date`: builds 11, 12 and 14 all read *Thu Nov 19 23:22:22 EST 2026*, and only their SHA-256s told them apart. With the generated files gone, ninja runs the generator again and it reads the new date. It costs the property files, the system image staging and the image, about two minutes on a no-change build; the fingerprint stays the same, because the build number (`eng.<user>`) is written only when it changes.

The script deliberately does not use `set -e` or `set -u`: `envsetup.sh` reads unset variables (`TOP`) and `lunch` returns non-zero on its way to success, so strict mode aborts the build in its first second. Every step is checked explicitly instead. The scripts must keep **LF line endings**: bash reads a `\r` at the end of a line as part of the command (`set: pipefail\r: invalid option name`). `.gitattributes` normalises them on commit, but a Windows editor or a tool that rewrites a file can produce a CRLF copy; `sed -i 's/\r$//' image/build/*.sh` repairs it, and `aosp-academy check` parses each script with `bash -n`.

There is **no ccache**. Every build rule runs in AOSP's sandbox (nsjail), which mounts only `out/` and `/tmp` writable, so ccache fails with `Read-only file system` on its first write. AOSP's own notes (`build/make/core/ccache.mk`) say it adds little over incremental builds, which you get anyway.

### Memory

A first build wants 16 cores and 32 GB of RAM to finish in hours rather than a day. Two phases are memory peaks, and they need different fixes.

**The R8 phase: lower `JOBS`.** The C++ phase is fine on all cores, but a later phase runs R8 (dex optimisation) as one multi-gigabyte JVM per job. On the build node's first build (32 cores, WSL capped at 26 GB), 32 of them filled the swap and the kernel's out-of-memory handler killed the build at 76 %. `JOBS=12 ./aosp-academy image build` resumed it inside memory; nothing is lost by the kill, because ninja continues from the steps already done. That first build took 2 h 35 min including the restart (12, then 22 jobs).

**Soong analysis: the heap limit.** Before anything compiles, `soong_build` analyses the whole product in one Go process, so `JOBS` can't help. Go's collector by default lets the heap grow to twice the live data before it runs. On `android-16.0.0_r4` that peaked at 23 GB resident and fitted. On `android-17.0.0_r1` it did not: on 2026-11-19 `soong_build` sat at 24 GB resident with 33 GB allocated, filled 32 GB of swap within minutes, stalled on memory for more than half of every second, and had not finished after 50 minutes, while the Windows host was down to 0.6 GB free. The fix is the `build/blueprint` patch, which sets a soft memory limit of 80 % of RAM (from `/proc/meminfo`), so the collector runs before the heap leaves RAM, at a CPU cost only once the heap gets there. An environment variable can't do the same, because the bootstrap ninja starts `soong_build` with `env -i`, so `GOMEMLIMIT` never reaches it. The limit follows the machine, not the tag, so the patch is harmless on a bigger builder. With it, the same analysis finished in 6 min 36 s, at 24 GB resident with swap peaking at 9 GB for a minute: a fit, not a comfortable one.

On a WSL2 build node, WSL's default memory cap (half of RAM) is too low. The build node here sets `memory=26GB` and `swap=32GB` under `[wsl2]` in `%UserProfile%\.wslconfig` (applied with `wsl --shutdown`); on another machine, set `memory` to the RAM less about 6 GB. Swap started at 16 GB and was doubled after `soong_build` was OOM-killed during analysis.

If a later tag outgrows this too, two levers are known and untried: a compressed swap device in the guest (the WSL kernel has `zram`: `zramctl --find --size 12G`, `mkswap`, `swapon -p 10`), which takes the swapping off the disk; and `PRODUCT_SOURCE_ROOT_DIRS`, which can prune trees the image never uses from the module graph (of the 15,600 `Android.bp` files Soong parses on `android-17.0.0_r1`, about 3,000 are under `cts`, `platform_testing`, `development`, `test` and `tools`), at the risk of a missing-namespace error for anything the product still references.

## Outputs and publishing

When `m` succeeds, `build-image.sh` checks that `system.img` and `system/build.prop` exist in the product output directory, then:

1. removes the previous build's `system.img`, `vbmeta.img`, `build.prop` and `system.img.sha256` from `work/device-tools/gsi/own/`, so no file of an older build stays beside the new image (where `gsi install --image` would pack it into the DSU zip);
2. copies `system.img`, `build.prop` and, when the build made one, `vbmeta.img` there, and writes `system.img.sha256`;
3. if **`PUBLISH_DIR`** is set, publishes the image there for the device node.

Publishing is written so that a device node pulling at the same moment never pairs a half-written image with a new checksum:

- First the old checksum, parts list, parts, `vbmeta.img` and `build.prop` are removed, so a puller sees no image at all rather than a mismatched one.
- Each file (`system.img`, `vbmeta.img` if any, `build.prop`) is copied under a temporary dot-name, made readable (`chmod 644`) and **renamed** into place. A rename within one filesystem is atomic: a reader sees the old name or the new file, never half of it.
- `system.img` is split into `PARTS` pieces (`system.img.part00` to `part15`), each renamed into place, and their SHA-256s are written to `system.img.parts`, also renamed into place. The parts exist because the VPN path to the device node limits each connection, not the total: `aosp-academy fetch` pulls them over 8 parallel streams (1.8 GB in about 4.5 minutes instead of 13). The whole `system.img` stays published for a puller that doesn't use parts.
- **`system.img.sha256` goes last.** It is what `fetch` reads first, so an image is visible to the device node only once everything else is complete.

The script ends by printing the image's size and its fingerprint (`ro.system.build.fingerprint` from `build.prop`). Only the newest image is kept, in `work/device-tools/gsi/own/` and in `PUBLISH_DIR`; to keep an earlier build for a [rollback](index.md#rolling-back), copy it somewhere else first.

!!! warning "Test-keyed images stay private"
    The image is signed with AOSP's public test keys, and one built with `work/adb_keys` trusts your own PCs. Move it only between your own machines, never through a public service.

## Incremental builds

A second build after a change is incremental: minutes, not hours. Ninja rebuilds only what changed. A change of product name makes Soong re-analyse the whole tree (the switch from `aosp_arm64` to the project's own product took 15 minutes, most of it analysis); a change in one makefile or overlay is quicker. `m <module>` builds one module, `m` builds the image. Even a build with no change produces a new image, because `build-image.sh` regenerates `build.prop` with the build's own date ([above](#lunch-and-the-build)); `ro.build.date` in the published `build.prop` therefore says when an image was built, and two builds of the same commit differ in SHA-256.

## verify-tree.sh

A sync interrupted during checkout (Ctrl-C, a killed process, WSL shut down) can leave a project with the right HEAD but a half-written work tree. The next `repo sync` sees the right HEAD and reports success, and the build then fails far from the cause: once, `unrecognized module type "llvm_prebuilt_library_static"` was `prebuilts/clang/host/linux-x86` missing its `soong/` directory and 38,979 other files.

`verify-tree.sh` (run by `sync.sh` after every sync, or `./aosp-academy image verify`) checks every project's `git status`. A project whose only differences from HEAD are missing files (staged deletions, `D `, which no hand edit produces) is reset to HEAD. A project with any other change is **listed and left alone**. After `apply-local.sh` has run, it lists `frameworks/base`, `build/soong` and `build/blueprint`: those are the patches. It exits non-zero if a reset failed.

## Changing something in the tree or in the repository

There are two places to edit, and only one of them lasts.

**The repository** is the source of truth. A change to the image is a change to `image/product/`, `image/patches/`, `image/build/` or `toolchain.json`, on a branch, built by the build node from a named commit. `apply-local.sh` copies it into the tree at every build, and `--delete` removes from the tree what the repository no longer has.

**The tree** is where you try things. To change the framework, a system app or the policy, edit it in place (good first targets: `frameworks/base`, `packages/apps/Settings`, `packages/apps/Launcher3`, `system/sepolicy`; `build/make/target/product/gsi_release.mk` and `aosp_arm64.mk` show what goes into a GSI), rebuild with `m`, and test it on the phone with `aosp-academy gsi install --image` on the device node. Don't edit `device/aospacademy/` in the tree: the next apply overwrites it from the repository.

Before a tree experiment counts as a change, move it into the repository: product-level changes (properties, packages, files copied into the image) into `image/product/aospacademy/gsi/`, source changes into a patch in `image/patches/`. Then build that commit, deploy and validate as usual. A change made only in the tree is lost at the next sync, and nobody else can build it.

## A tree that had the pre-rename product

Images up to build 10 were the product `vedotom_arm64`, from `device/vedotom/gsi/` in the tree, with the `build/soong` patch naming `//device/vedotom/gsi`. The renamed patch adds different lines, so on such a tree `apply-local.sh` finds that the new patch neither is applied nor applies, and stops. And the old product directory would still be in the tree, defining a second product whose visibility no longer exists. Clean both up once, before the first `aospacademy_arm64` build:

```bash
cd "${AOSP_DIR:-$HOME/aosp17}"
rm -rf device/vedotom
git -C build/soong status --short          # expect only Android.bp: the old visibility patch
git -C build/soong checkout -- Android.bp  # revert it; apply-local.sh then applies the new one
```

Then `./aosp-academy image build` as usual. Soong re-analyses the tree for the new product name.
