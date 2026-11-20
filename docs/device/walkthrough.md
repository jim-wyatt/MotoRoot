# Preparation walkthrough

This is the complete device-preparation procedure, stage by stage, with every command and the reasoning behind it. It is derived from parsimo2010's tested guide ([credits](../reference/credits.md)) and has been carried out on two units; the exact configuration it applies to, both runs, and everything that was and wasn't verified are on the [validation page](index.md#validation-record). Read the [disclaimer](../reference/disclaimer.md) before you start.

Work in a [dev shell](../start/workstation.md#6-a-shell-with-the-tools-on-path) (`. .\workstation\Enter-DevShell.ps1`), which puts you at the repository root, sets `$adb`, `$fb`, `$Work`, `$Backup` and `$py`, and puts the pinned Platform Tools first on PATH. **Close Android Studio** so only the pinned `adb` is running. Keep the same window open: later stages reuse its variables.

!!! danger "Points of no return"
    Stage 6 **erases** the device and can, if LK fails, make it unbootable with no proven recovery. Do not start it until stages 1–5 are complete and you've confirmed your backups and prepared files are on the PC.

---

## Stage 1 — First setup without a cellular plan

**Goal:** finish Android's first-run setup as a Wi-Fi device, with no plan, via [enterprise provisioning](../concepts/device-provisioning.md). This is Android's own setup path, not cellular activation or SIM unlocking. It temporarily makes Google's Test DPC the device owner, which you remove straight afterwards.

1. While powered off, remove any SIM. Charge the device well first and keep it charged throughout.
2. Power on. At the Welcome screen, **tap the same blank spot six times** to open the provisioning QR scanner.
3. Scan the Test DPC QR shown on your PC (`work\testdpc-qrcode.png`: [Google's own image](https://github.com/googlesamples/android-testdpc#provisioning), hash-verified by the bootstrap). Join Wi-Fi when asked so Android can download Test DPC. Use only this QR, never one that enrols the device under an unknown administrator.
4. Choose **Use for work only**, then **Finish**. Decline Smart updates and optional apps, and **skip Google sign-in** (the unlock in stage 6 erases the device anyway). Location, number verification and diagnostics are optional and were left off.
5. **At the home screen, turn Wi-Fi off immediately.** A firmware update can download in the background regardless of the Smart updates setting (see [why a staged update matters](../concepts/partitions-and-slots.md#why-a-and-b)).
6. **Settings → About phone → Build number**, tap seven times. Then **System → Developer options → USB debugging** on. Plug in, unlock the screen, and approve **Allow USB debugging** (tick *Always allow from this computer*).

```powershell
& $adb devices -l      # exactly one line, state "device"
```

`unauthorized` means the prompt on the device still needs approving. Disconnect any other Android devices so nothing else can be targeted.

Now remove the device owner so nothing manages your dev device. Test DPC's own settings UI crashed on both units; its service interface works:

```powershell
& $adb shell dumpsys activity service com.afwsamples.testdpc/.DeviceAdminService clear-device-owner
# Device Owner and Enabled Device Admins must now be empty (wait a moment and re-check if not):
& $adb shell dumpsys device_policy
& $adb shell pm uninstall com.afwsamples.testdpc    # Success
& $adb shell svc wifi disable
# extra precaution only; it does not cancel a staged update:
& $adb shell settings put global ota_disable_automatic_update 1
```

Don't just uninstall an active device owner or factory-reset to remove it, and **don't scan the QR again** once setup is complete.

**Confirm the build matches** the [tested device](index.md#the-exact-tested-device):

```powershell
& $adb shell getprop ro.product.model                 # moto g power - 2026
& $adb shell getprop ro.boot.hardware.sku             # XT2617V
& $adb shell getprop ro.build.fingerprint
#   motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys
& $adb shell getprop ro.build.version.security_patch  # 2026-04-01
& $adb shell uname -r
#   5.15.180-android13-8-00018-g9b2308ac0ad6-ab14563692
& $adb shell getprop ro.boot.slot_suffix              # _a
```

If anything differs, **stop here**. If an update is downloading, keep Wi-Fi off. If one is already processing or asks for a restart, choose **Later**, **do not restart**, carry on only as far as stage 2, and then deal with it in stage 4.

---

## Stage 2 — Temporary system access

**Goal:** get [temporary root](../concepts/system-access.md#1-temporary-root-dfroot-kernelsu) so you can back up partitions. This is the bootstrap foothold; a reboot clears it.

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb shell am start -n df.root/.MainActivity
```

On the device:

1. In DFRoot, select **KernelSU** as the SU manager.
2. Keep **Start at Boot**, **Auto Soft Reboot** and **Disable KSU Modules** all **off**.
3. Tap **Launch Root** **once**. Don't install modules, flash a kernel, or retry a failed exploit repeatedly.
4. KernelSU should show **Working [Jailbreak mode]**.
5. In KernelSU's **Superuser** section, enable **Shell** (`com.android.shell`). Turn on *Show system apps* in the filter if it's hidden.

```powershell
& $adb shell su -c id          # uid=0(root) ... context=u:r:ksu:s0
```

The green tick alone isn't enough; `uid=0` over ADB is the test. `su: inaccessible or not found` means Shell wasn't granted. If root can't be verified, **stop**: DFRoot relies on a vulnerable kernel, can fail or crash on other firmware, and a crash reboots the device, which you must avoid while an update may be staged.

DFRoot also marks many partitions read-only. Later stages lift that flag only for the one partition they write, then put it back.

---

## Stage 3 — Back up your original partitions

**Goal:** save your own factory images. They are your only recovery path and are **private** (they contain per-unit calibration and security data). They go in `$Backup` (`work\private-backups`), which is git-ignored and blocked by the pre-commit hook.

The loop reads each partition to a temporary file on the device, pulls it, and verifies the SHA-256 on both sides. It writes no partition. Make sure the PC has a few GB free.

```powershell
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
& $adb shell su -c 'mkdir -p /data/local/tmp/moto-factory-backup'
$Parts = @(
  'lk_a','lk_b','boot_a','init_boot_a','vendor_boot_a',
  'vbmeta_a','vbmeta_system_a','misc',
  'nvram','nvdata','seccfg','persist','prodpersist',
  'proinfo','protect1','protect2','dtbo_a','preloader_raw_a'
)
foreach ($Part in $Parts) {
  $Local = Join-Path $Backup "$Part.img"
  if (Test-Path -LiteralPath $Local) { throw "Backup already exists: $Local. Do not overwrite it." }
  & $adb shell su -c "dd if=/dev/block/by-name/$Part of=/data/local/tmp/moto-factory-backup/$Part.img bs=1048576"
  if ($LASTEXITCODE -ne 0) { throw "Read failed: $Part" }
  & $adb pull "/data/local/tmp/moto-factory-backup/$Part.img" $Local
  if ($LASTEXITCODE -ne 0) { throw "Transfer failed: $Part" }
  $PhoneHash = & $adb shell su -c "sha256sum /data/local/tmp/moto-factory-backup/$Part.img"
  $PcHash = (Get-FileHash -LiteralPath $Local -Algorithm SHA256).Hash.ToLower()
  if (-not ($PhoneHash -match ('^' + $PcHash + '\s'))) { throw "Hash mismatch: $Part" }
}
Get-ChildItem -LiteralPath $Backup -Filter '*.img' | Get-FileHash -Algorithm SHA256 |
  Export-Csv -LiteralPath "$Backup\sha256.csv"
```

On both units the factory `init_boot_a.img` was 8 MiB with SHA-256 `31239df6b54fd815912ba7d0e4cc87aca3af200eed8ff315238e4178580285ea`. A different hash on a supposedly identical build is a reason to investigate, not to borrow someone else's image. If an update has staged, the slot-B backups may already hold updated components: **don't assume `lk_b` is an untouched factory fallback.**

!!! warning "Back up `$Backup` off the PC too"
    Copy `work\private-backups` to offline storage, not a public cloud share. If the device won't boot later, these files are what you flash back. Never restore another unit's `nvram`, `nvdata`, `persist`, `seccfg` or preloader images to yours.

---

## Stage 4 — If an update is staged

**Goal:** make sure the device won't reboot into newer, untested firmware. Skip this stage only after you've confirmed both the current and the next boot slot.

```powershell
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-current-slot'      # 0 = A
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot'  # must also be 0
& $adb shell su -c 'tail -n 35 /data/misc/update_engine_log/update_engine.log'
```

Both `0`, with a log that ends in cleanup and "Can't find any snapshot to merge", means nothing is staged (unit 2). On unit 1 the current slot was `0`, the next boot `1` and the state `UPDATED_NEED_REBOOT`: a completed update waiting for a restart. Turning Wi-Fi off, force-stopping the updater and the developer setting did **not** cancel it. What did was Android's own [`UpdateEngine.resetStatus()`](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/UpdateEngine.java) API, called through the included [`UpdateHelper`](helpers.md): a tiny program that exposes only inspection and that one reset, and never edits raw boot metadata.

Back up the update metadata first, then push and inspect the helper (`inspect` only prints method signatures):

```powershell
& $adb shell su -c 'tar -cf /data/local/tmp/update-engine-before-reset.tar /data/misc/update_engine/prefs /data/misc/update_engine_log /metadata/ota'
& $adb pull /data/local/tmp/update-engine-before-reset.tar "$Backup\update-engine-before-reset.tar"
& $adb push .\stock\helpers\UpdateHelper.dex /data/local/tmp/moto-update-helper.dex
& $adb shell su -c 'CLASSPATH=/data/local/tmp/moto-update-helper.dex app_process /system/bin UpdateHelper inspect'
```

For the current-A / next-B state, with `misc` already backed up in stage 3, perform the reset. `misc` must be writable for the duration; DFRoot makes it read-only, which is why the first attempt on unit 1 failed:

```powershell
try {
  & $adb shell su -c 'blockdev --setrw /dev/block/by-name/misc'
  if ($LASTEXITCODE -ne 0) { throw 'Cannot make misc writable' }
  & $adb shell su -c 'CLASSPATH=/data/local/tmp/moto-update-helper.dex app_process /system/bin UpdateHelper reset-status'
  if ($LASTEXITCODE -ne 0) { throw 'Update reset failed. Do not reboot.' }
} finally {
  & $adb shell su -c 'blockdev --setro /dev/block/by-name/misc'
}
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-current-slot'
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot'
& $adb shell su -c 'tail -n 35 /data/misc/update_engine_log/update_engine.log'
```

Both slots must now report `0`, and the log should show the slot switch cancelled and the update state and snapshots removed. If the reset fails, don't reboot, and don't hand-delete `/metadata` or the update-engine files.

Motorola's notification and its automatic-restart alarm are separate app state and can remain. Remove them with [`UpdaterCleanup`](helpers.md), run as the updater's own uid (discover it on your device; never copy one from elsewhere). The DEX is made read-only first because Android rejects a writable DEX run as an app uid:

```powershell
$OtaLine = (& $adb shell pm list packages -U com.motorola.ccc.ota) -join ''
if ($OtaLine -notmatch 'package:com\.motorola\.ccc\.ota\s+uid:(\d+)') { throw 'Cannot identify updater UID' }
$OtaUid = $Matches[1]
& $adb push .\stock\helpers\UpdaterCleanup.dex /data/local/tmp/moto-updater-cleanup.dex
& $adb shell su -c 'chmod 0444 /data/local/tmp/moto-updater-cleanup.dex'
& $adb shell su $OtaUid -c 'CLASSPATH=/data/local/tmp/moto-updater-cleanup.dex app_process /system/bin UpdaterCleanup cancel'
& $adb shell dumpsys alarm | Select-String '^\s+RTC.*com.motorola.ccc.ota'     # no matching alarm
```

A stale notification is not proof the engine is still staged, and a hidden one is not proof it was cancelled: trust the slots and the engine log. If you can't reconcile them, stop before rebooting, and never leave an automatic-restart deadline unattended. This cleanup is temporary; the `wifi_ota_guard` module in stage 8 is the durable block.

---

## Stage 5 — Prepare LK and the Magisk image

**Goal:** build the two files you'll install, entirely on the PC. Nothing is flashed yet; everything here is reversible.

**Patch LK** with [Val Protocol](../reference/credits.md) so the device accepts the standard unlock (background: [the boot chain](../concepts/boot-chain.md#why-this-model-is-extra-work-on-this-device)). The bootstrap already cloned it at its pinned commit and built `work\.venv` with its requirements plus `pyasn1`, which upstream's list omits (without it, a misleading error claims `liblk` is missing).

```powershell
& $py "$Work\val-protocol\lk_static_analyzer.py" "$Backup\lk_a.img" -o "$Work\lk-analysis" --no-full-disasm
```

Expected: AArch64, an extracted LK payload of 1,238,664 bytes, and the analyzer reporting an unlock flow, an FRP/OEM checker, a key validator, erase-permission checks, partition erase operations and the runtime serial getter. If any of those are missing, stop.

```powershell
& $py "$Work\val-protocol\lk_auto_patch.py" "$Backup\lk_a.img" -o "$Work\lk.unlock-serial.img" `
      --analysis-dir "$Work\lk-patch-analysis" --preset unlock-serial --key-token-secret Valeria --keep-workdir
```

The secret `Valeria` must match key generation in stage 6. The patcher's verifier must report `Result: VALID` (it skips comparison against the chip's trusted root; this remains an experimental bootloader modification). The `unlock-serial` preset keeps the normal unlock flow, erases included. Don't substitute FRP-erasing presets or experiment with erase targets; a new device you own needs no FRP bypass. Keep the original `lk_a.img` separate.

**Prepare the Magisk image** from *your own* `init_boot_a`. The included script runs Magisk 31.1's own patch logic on the device, writes only a file, and never flashes anything. It refuses to run unless exactly one approved device is connected, it is the tested build on slot A, root works, and the current `init_boot_a` still matches the backup you pass in:

```powershell
.\stock\Prepare-MagiskImage.ps1 -WorkDir $Work -StockImage "$Backup\init_boot_a.img"
# → work\magisk-patched-init_boot.img  (8 MiB; device and PC hashes compared)
```

Both units produced an identical image, SHA-256 `fbac252d15501e8350b65ae93a92962f93d2907144286c04abf2eeda26c246d0`. Yours may legitimately differ; what matters is that the transfer and the later write verify against *your* file's hash.

---

## Stage 6 — Flash LK and unlock

!!! danger "This is the irreversible stage"
    It erases the device and can brick it. Confirm your backups are copied off the PC and that both prepared files exist. Read [recovery](stock.md#recovery) before you start: if the modified LK fails before Fastboot starts, no vendor-independent recovery is known.

Reboot to the bootloader and verify you're on the tested device in Fastboot. If Fastboot lists nothing, install the Motorola driver before issuing any other command; ADB approval does not install it. Disconnect every other device.

```powershell
& $adb reboot bootloader
& $fb devices -l
& $fb getvar product                      # vegas
& $fb getvar current-slot                 # a
& $fb getvar version-bootloader           # MBM-3.1-vegas_og_vext-5d518d-W1WEOS36.48-22-3-3-4-2-36210f
& $fb getvar partition-size:lk_a          # 0x1000000  (16 MiB)
& $fb getvar partition-size:init_boot_a   # 0x800000   (8 MiB)
& $fb getvar securestate                  # oem_locked, for now
```

Generate unlock keys from **your own** serial and keep them private. (`work\` is git-ignored, and the hook blocks anything named like unlock keys; never use a serial or key from a screenshot or tutorial.)

```powershell
& $fb getvar serialno
$PhoneSerial = Read-Host 'Enter YOUR serial exactly as Fastboot reported it'
& $py "$Work\val-protocol\lk_keygen.py" --secret Valeria --serialno $PhoneSerial --count 5
```

The output shows a `Const` line and then five 20-character alphanumeric keys; any of the five works.

Flash the patched LK to **slot A only**, then reboot back into the bootloader:

```powershell
& $fb flash lk_a "$Work\lk.unlock-serial.img"
if ($LASTEXITCODE -ne 0) { throw 'LK flash failed. Stop without rebooting.' }
& $fb reboot bootloader
```

Wait for Fastboot to return (about 9 seconds on unit 2). The device may briefly enumerate as a MediaTek serial device first; that isn't a failure. **If it never returns, do not flash other partitions or erase anything.**

Now unlock. Hold the device: it asks you to confirm **Unlock bootloader** with the volume and power buttons, and the prompt times out quickly.

```powershell
& $fb devices -l
& $fb getvar current-slot
$UnlockKey = Read-Host 'Paste one of YOUR generated 20-character keys'
if ($UnlockKey -cnotmatch '^[A-Za-z0-9]{20}$') { throw 'Unexpected key format' }
& $fb oem unlock $UnlockKey      # approve on the device → "Bootloader is unlocked! Rebooting phone to fastboot mode"
& $fb getvar securestate         # must now read: flashing_unlocked  ("secure: yes" elsewhere is unrelated)
& $fb reboot
```

The device reboots to a fresh factory setup; the wipe is expected, and from now on every boot shows an unlocked-bootloader warning.

!!! info "Why Magisk isn't flashed in Fastboot here"
    On unit 1, `fastboot flash init_boot_a` rejected the Magisk image ("Preflash validation failed") and fastbootd couldn't open the partition. No verification partitions were altered to work around that. Instead, the image is written from *inside Android* with temporary root in stage 7, with a read-back check. Don't add vbmeta flashes, downgrade Magisk, or try another device's image because a forum suggests it.

---

## Stage 7 — Re-setup and install persistent root

The unlock wiped the device, so **repeat Stage 1** in full: QR setup, remove Test DPC, Wi-Fi off, USB debugging, and approve the PC again. Re-verify the build and slot A; if a fresh update staged, resolve it (stage 4) before any reboot. Then reinstall the tools, this time including Magisk, and get temporary root again exactly as in stage 2:

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb install "$Work\Magisk-v31.1.apk"
& $adb shell am start -n df.root/.MainActivity
# DFRoot → KernelSU → Launch Root once → grant Shell in KernelSU; then:
& $adb shell su -c id                                               # uid=0, context u:r:ksu:s0
& $adb shell getprop ro.boot.flash.locked                           # 0
& $adb shell getprop ro.boot.verifiedbootstate                      # orange (normal for an unlocked device)
& $adb shell getprop ro.boot.slot_suffix                            # _a
& $adb shell getprop ro.build.fingerprint                           # still the tested build
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot' # 0
```

Now write the Magisk-patched image to **`init_boot_a` only**. Don't change the destination, and don't write `boot_a`, `lk_b`, both slots, or any calibration or security partition as a substitute. First check that the partition still matches your backup and that the file is the right size and transfers intact:

```powershell
$OriginalHash = (Get-FileHash -LiteralPath "$Backup\init_boot_a.img" -Algorithm SHA256).Hash.ToLower()
$CurrentHash = & $adb shell su -c 'sha256sum /dev/block/by-name/init_boot_a'
if (-not ($CurrentHash -match ('^' + $OriginalHash + '\s'))) { throw 'Current init_boot differs from the original backup. Stop.' }
$RootImage = "$Work\magisk-patched-init_boot.img"
$Expected = (Get-FileHash -LiteralPath $RootImage -Algorithm SHA256).Hash.ToLower()
if ((Get-Item -LiteralPath $RootImage).Length -ne 8388608) { throw 'Unexpected image size for this tested procedure' }
& $adb push $RootImage /data/local/tmp/magisk-patched-init_boot.img
if ($LASTEXITCODE -ne 0) { throw 'Image transfer failed' }
$Transferred = & $adb shell su -c 'sha256sum /data/local/tmp/magisk-patched-init_boot.img'
if (-not ($Transferred -match ('^' + $Expected + '\s'))) { throw 'Transferred image hash mismatch' }
```

If every check passed, perform the guarded write with read-back verification. Sync and reboot **only after both succeed**:

```powershell
try {
  & $adb shell su -c 'blockdev --setrw /dev/block/by-name/init_boot_a'
  if ($LASTEXITCODE -ne 0) { throw 'Cannot make init_boot writable' }
  & $adb shell su -c 'dd if=/data/local/tmp/magisk-patched-init_boot.img of=/dev/block/by-name/init_boot_a bs=1048576 conv=fsync'
  if ($LASTEXITCODE -ne 0) { throw 'Write failed. Do not reboot.' }
  $Readback = & $adb shell su -c 'sha256sum /dev/block/by-name/init_boot_a'
  if (-not ($Readback -match ('^' + $Expected + '\s'))) { throw 'Readback mismatch. Do not reboot.' }
} finally {
  & $adb shell su -c 'blockdev --setro /dev/block/by-name/init_boot_a'
}
& $adb shell su -c sync
& $adb reboot
```

Startup can take a minute or more, including the unlocked-bootloader warning and a delayed ADB connection. Don't force-restart it repeatedly. If it loops or shows a boot error, go to [recovery](stock.md#recovery) rather than continuing.

**Finish Magisk setup:** open the **Magisk** app, not KernelSU. If it says **Requires additional setup**, tap OK and allow the reboot. Then grant **Shell** root in Magisk (the KernelSU grant doesn't carry over), and **don't launch DFRoot again**: the point is to prove Magisk starts by itself.

!!! note "Magisk 31.1 may never show the Grant pop-up"
    On unit 2, `adb shell su` was rejected instantly (`su: request rejected (2000)` in logcat) and the Superuser tab stayed empty. Motorola's background app-freezer suspends the Magisk app, so the daemon can't reach it to show the prompt and denies by default. Grant Shell **manually** instead: Magisk → **Superuser** tab → **+** → tick **Shell** (`com.android.shell`). The policy is stored, so it survives reboots. There is no "Superuser access: Apps and ADB" setting in this build.

```powershell
& $adb shell su -c id                             # uid=0(root) ... context=u:r:magisk:s0
& $adb shell su -c 'magisk -v'                    # 31.1:MAGISK:R
& $adb shell ps -A | Select-String 'magiskd|ksud' # magiskd present, no ksud
```

That's the milestone: **root that starts by itself after a normal reboot.** A green indicator, or the app merely being installed, is not enough; this check is.

---

## Stage 8 — Configure the Wi-Fi dev device

**Goal:** apply the three reversible [system modules](../concepts/magisk-modules.md), so the device doesn't auto-update its firmware and isn't cluttered with carrier, partner and telemetry apps it doesn't need.

Install the updater block first, before Wi-Fi goes back on, and verify it after the reboot. The normal package manager refuses to disable the updater even as root, so this overlay is the verified block; it hides Motorola Software Update, not Google Play's system updates.

```powershell
# Reversibly hide the Motorola updater
& $adb push .\stock\modules\wifi-ota-guard.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-ota-guard.zip'
& $adb shell settings put global ota_disable_automatic_update 1
& $adb reboot
# after reboot, all three should print nothing:
& $adb shell pm path com.motorola.ccc.ota
& $adb shell su -c 'ls -A /system_ext/priv-app/3c_ota'
& $adb shell ps -A | Select-String 'ccc.ota'
```

Then the two debloat modules. They are for a **Wi-Fi-only** device: they can break cellular setup, service management, voicemail and SIM functions. `wifi-carrier-debloat` hides the 22 Verizon/TracFone activation, remote-SIM-lock, carrier-management and PAKS finance packages. `wifi-extra-debloat` hides a further 19: AT&T, Cricket and Facebook partner stubs; Motorola telemetry (bug2go, modem and Wi-Fi statistics, the crash-log agent, lifetime data); Moto Care, MyKey, the hidden engineering menu, Ready For desktop mode, visual voicemail, carrier entitlement, and Digital Wellbeing. Each module's manifest in `stock/modules/manifests/` lists every package with its on-disk path. Neither module checks the device it's installed on, so before installing confirm every targeted package exists on your build with `& $adb shell pm path <package>`.

```powershell
# Reversibly disable the 22 carrier/activation apps
& $adb shell su -c 'pm disable-user --user 0 com.android.devicelockcontroller'
& $adb push .\stock\modules\wifi-carrier-debloat.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-carrier-debloat.zip'

# Reversibly hide the 19 partner, telemetry and extra Motorola apps
& $adb push .\stock\modules\wifi-extra-debloat.zip /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-extra-debloat.zip'
& $adb reboot
```

PAKS held Android's financed-device-controller role on unit 1. That is not proof of financing enrolment or of a scheduled lock; disabling the controller and hiding PAKS addresses the identified Android-level paths on a device you own outright. It establishes nothing about undocumented modem or firmware behaviour, and it is not a tool for evading a financing lock (see the [disclaimer](../reference/disclaimer.md)).

After the reboot, verify that root still works, all three modules are active, the device-lock controller is disabled, the financed-device role has no holder, no device administrator remains, and no carrier or updater process is running:

```powershell
& $adb shell su -c id                                   # context=u:r:magisk:s0
# all three: wifi_carrier_debloat  wifi_extra_debloat  wifi_ota_guard
& $adb shell su -c 'ls /data/adb/modules'
& $adb shell pm list packages -d | Select-String 'devicelockcontroller'
# the financed-device role must have no holder (prints nothing):
& $adb shell cmd role get-role-holders android.app.role.SYSTEM_FINANCED_DEVICE_CONTROLLER
& $adb shell dumpsys device_policy                      # no owner, no admins
& $adb shell ps -A | Select-String 'com.verizon|com.vzw|com.motorola.omadm|com.motorola.paks|com.motorola.tracfone|ccc.ota'
& $adb shell pm path com.motorola.motocare              # empty: one of the 19, hidden
```

!!! info "Why modules rather than `pm uninstall --user 0`"
    `pm uninstall --user 0 <package>` also removes a preinstalled app, reversibly (`pm install-existing <package>` brings it back). But it's per-user state kept next to the app data. A module hides the app for every user, reapplies itself on every boot regardless of package state, and is toggled in one place alongside the other two. Neither approach survives a **factory reset**, which wipes `/data` and Magisk's module store with it; reinstall the modules afterwards. Two packages on this build, `com.amazon.appmanager` and `com.motorola.ccc.devicemanagement`, are flagged non-removable by the package manager; the Amazon one ships disabled, and both were deliberately left alone rather than hidden. Android Device Policy (`com.google.android.apps.work.clouddpc`) isn't in the firmware at all — it was installed under `/data/app` during setup — so a plain uninstall removes it for good.

Finally, remove the temporary-root tools and the leftover device-policy app, re-enable Wi-Fi, and sign into Google Play to install your own development tools. Grant root only to apps you trust.

```powershell
& $adb shell pm uninstall df.root
& $adb shell pm uninstall me.weishu.kernelsu
& $adb shell pm uninstall --user 0 com.google.android.apps.work.clouddpc
& $adb shell svc wifi enable
& $adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.android.vending
```

Your development device is ready. Next: [Maintaining the device](stock.md), the optional [engineering-device setup](stock.md) (userdebug reporting, ADB over Wi-Fi, F-Droid), and then start [developing](../apps/index.md).
