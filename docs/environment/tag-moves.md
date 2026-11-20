# Move to a new AOSP release

The image is built from one AOSP release tag, pinned as `deviceTools.aosp.tag` in `toolchain.json`. Moving it to a newer tag brings a newer Android, a newer security patch level and a newer WebView (which otherwise ages with the tag). It is also the largest change this project makes: this project's product is a set of copies of upstream files and patches against upstream code, and every one of them has to be checked against the new release.

!!! note "Release tags are rare"
    Google has published AOSP source less often since 2025: `android-17.0.0_r1` is the "26Q2" release, and Android 17's later QPR releases exist only as Google's GSI binaries, not as source. A move is usually to a new major version, not a patch bump. If a newer source drop is close, waiting for it can save a second port, but step 0 is worth doing at once either way.

## Step 0: does Google's GSI run on this vendor?

Nothing else matters until this is answered. The phone's vendor layer is **Android 13's**: `ro.vndk.version=33`, `ro.board.api_level=33`, VINTF `target-level="7"` (framework compatibility matrix level 7). An Android system runs on it only as long as the system still ships the VNDK APEX for version 33 (`com.android.vndk.v33`, the vendor's view of the system libraries) and `compatibility_matrix.7.xml`. If a new release drops either, the vendor's HALs don't start, and no amount of porting helps.

So the first step is a cheap test that changes nothing in the repository: boot **Google's own GSI** of the new release through DSU. About an hour, and reversible.

1. Keep a copy of the current validated `system.img` and its `build.prop`, as the known-good image to go back to ([Rolling back](deploying.md#rolling-back-to-an-earlier-image)). Installing another GSI discards the installed image and its data.
2. Pin the GSI zip in `toolchain.json` (`deviceTools.gsi`: name, URL, SHA-256, under Google's GSI terms) on a branch, then on the device node `./aosp-academy gsi download --accept-google-gsi-terms`, `./aosp-academy gsi install`, `./aosp-academy gsi boot`. Google's GSI is a user build with release keys: no `adb root`, every check runs as shell, and USB debugging must be switched on by hand in the GSI (its fresh data starts with it off).
3. Check what the current image is known to do: boot and time to the lock screen, SELinux enforcing, Wi-Fi validated, display modes (120 Hz), audio, both cameras, the sensor list, fingerprint, vibrator, NFC, Bluetooth, GNSS, the modem, USB debugging, the `lshal` count against the last image, `gpuservice`, SELinux denials and the crash log. For the charge-limit module, check only that `/sys/module/qpnp_adaptive_charge/parameters` **exists**: don't read the parameters ([why](image.md#the-charge-limit)). Capture an inventory with `./aosp-academy device info --label gsi<version>`.
4. **Go** if it boots and the hardware list matches the current image's. **No go:** stay on the current tag, and re-test with each new source drop.

Step 0 also tells you which of this project's patches are still needed: a bug the new GSI still shows needs its patch carried over, and one it no longer shows may be fixed upstream.

## Step 1: a second tree, on a branch

Do the move on a git branch (for example `aosp-17`), so `main` keeps building the current release for fixes until the switch-over. On the branch, set `deviceTools.aosp.tag` to the new tag and `deviceTools.aosp.treeDir` to a **new** tree directory, so the build node syncs the new release next to the current one rather than over it (an Android 17 tree uses about 335 GB). Keep the old tree until the new release has run for a while.

## Step 2: port this project's changes

Each item has its own check. Most of them can be done from upstream's source browser (android.googlesource.com), file by file, before the new tree has finished syncing. Diff each upstream file this project mirrors between the old tag and the new one.

| What | How to check it |
| --- | --- |
| **Lunch target** | The release configuration name (`trunk_staging`) can change. `lunch` with no arguments in the new tree lists the tag's targets; `deviceTools.aosp.lunch` is the one place to change. |
| **Product makefiles** | Diff upstream `aosp_arm64.mk`, `aosp_product.mk`, `handheld_product.mk` and `telephony_product.mk` between the two tags, and carry what moved into `aospacademy_*.mk`. Also read what the inherited files (`generic_system.mk`, `gsi_release.mk`, `media_product.mk`) now add or drop, especially anything this vendor relies on: HIDL packages this vendor's HALs need (the fingerprint HAL is HIDL `@2.1`; the only HIDL radio entry is `@1.2::ISap`), and new files the mirror must list. |
| **`Android.bp` mirror** | Diff `build/make/target/product/gsi/Android.bp` (`aosp_system_image`, `android_gsi_defaults`) between the tags and carry the changes into `aospacademy_system_image` and `aospacademy_gsi_defaults`. **filelistdiff** confirms it at build time: it names every module the makefiles install and the mirror lacks, or the other way round. Re-check the VNDK APEX list, and keep `v33`. |
| **Patches** | `AOSP_TAG=<new tag> bash image/build/check-patches.sh` checks every patch in `image/patches/` against the new tag without a tree. For each patch, also ask whether the bug still exists in the new tag (step 0 is evidence). Drop a patch the tag fixes upstream (it usually no longer applies); rebase the rest. `apply-local.sh` stops at any patch that doesn't apply, so a stale one can't slip through. |
| **Overlays** | Every resource name the overlays set must still exist with the same type: the framework's `frameworks/base/core/res/res/values/config.xml`, and NetworkStack's `res/values/config.xml` and `overlayable.xml` (the `NetworkStackConfig` overlayable). A renamed resource is silently ignored, so check by name. |
| **Release flags** | `PRODUCT_ADB_KEYS` and the release flag `RELEASE_BUILD_PURGE_PRODUCT_ADB_KEYS`: check its value for userdebug in the new tag, then `/product/etc/security/adb_keys` in the first build's output. Any other flag the product relies on, likewise. |
| **First-boot service** | The shell interfaces it calls (`cmd role`, `settings`, `pm enable/disable`), the Fossify alias names and the `seclabel u:r:su:s0` domain. These are not easily diffed; the first build's validation covers them. The charge-limit module is vendor-side and doesn't change with the tag. |
| **APK pins** | Check that the pinned Fossify versions install on the new release (their minimum and target SDK against the platform's minimum); bump the pins if needed. |
| **WebView** | Comes with the tag, so it updates for free. |

## Step 3: build, deploy, validate

Request a build of the branch. The first build of a new tree is a full one (about 2.5 hours on the build node, plus Soong analysis), and memory is the usual surprise: a new release's analysis can outgrow the build node ([Memory](building.md#memory)).

Deploy it and run the whole [validation checklist](validation.md#the-checklist), plus step 0's hardware list. Compare against the [current image](validation.md#current-image), item by item. Check in particular every item step 2 marked as "check on the first build" (for example `/product/etc/security/adb_keys` in the build output, and that the fingerprint HAL registers).

## Step 4: switch over

When the new image passes:

1. Merge the branch into `main`.
2. Move the pins to the new release: `deviceTools.aosp.tag`, `deviceTools.aosp.treeDir`, and `deviceTools.gsi` to the new release's GSI.
3. Update the docs that name the release: [What's in the image](image.md), [DSU](../device/dsu.md), [Pins](../reference/pins.md) and the validation page.
4. After a period without problems, delete the old tree on the build node.

**Going back** is possible at every step until the switch-over (`main` still builds the old release, and a saved `system.img` restores the current image with `deploy --no-fetch`). After it, only the saved image holds, so keep the last image of the old release until the first image of the new one has passed validation.

## Effort

Step 0 takes about an hour on the device node; step 1, a sync of a few hours; step 2, one to three working sessions; step 3, a first full build of about 2.5 hours, then deploy and validation.
