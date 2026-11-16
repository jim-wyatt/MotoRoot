# Preparation walkthrough

This is the full device-preparation sequence, stage by stage, with the reasoning for each step. The **authoritative command reference** is [`kit/GUIDE.md`](https://github.com/jim-wyatt/OtomDev/blob/main/kit/GUIDE.md); the commands here match it, and where they differ, the kit wins.

Work in a [dev shell](../start/setup.md#4-open-the-dev-shell) (`. .\dev\Enter-DevShell.ps1`) so `$adb`, `$fb`, `$Work`, `$Kit`, `$Backup` and `$py` are set. **Close Android Studio** so only the pinned `adb` is running.

!!! danger "Points of no return"
    Stage 6 **erases** the device and can, if LK fails, make it unbootable with no proven recovery. Do not start it until stages 1–5 are complete and you've confirmed your backups and prepared files are on the PC.

---

## Stage 1 — First setup without a cellular plan

**Goal:** finish Android's first-run setup as a Wi-Fi device, with no plan, via [enterprise provisioning](../concepts/device-provisioning.md).

1. Power on with **no SIM**. Charge it well first.
2. At the Welcome screen, **tap the same spot six times** to open the provisioning QR scanner.
3. Scan the Test DPC QR shown on your PC (`work\testdpc-qrcode.png`). Join Wi-Fi when asked.
4. Choose **Use for work only**, finish, decline Smart updates and optional apps, **skip Google sign-in** (the unlock in stage 6 erases the device anyway).
5. **At the home screen, turn Wi-Fi off immediately** — this stops a firmware update downloading behind your back (see [why a staged update matters](../concepts/partitions-and-slots.md#why-a-and-b)).
6. Enable **Developer options** (tap Build number 7×) and **USB debugging**; plug in and approve the prompt.

Then remove the device owner so nothing manages your dev device:

```powershell
& $adb shell dumpsys activity service com.afwsamples.testdpc/.DeviceAdminService clear-device-owner
& $adb shell dumpsys device_policy          # should show NO device/profile owner
& $adb shell pm uninstall com.afwsamples.testdpc
& $adb shell svc wifi disable
```

**Confirm the build matches** the [tested device](index.md#the-exact-tested-device):

```powershell
& $adb shell getprop ro.product.model
& $adb shell getprop ro.build.fingerprint
& $adb shell getprop ro.boot.slot_suffix     # must be _a
```

If anything differs from the tested values, **stop here**.

---

## Stage 2 — Temporary system access

**Goal:** get [temporary root](../concepts/system-access.md#1-temporary-root-dfroot-kernelsu) so you can back up partitions. This is the bootstrap foothold; a reboot clears it.

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb shell am start -n df.root/.MainActivity
```

On the device: in DFRoot pick **KernelSU** as the manager, keep boot options **off**, tap **Launch Root once**. In KernelSU's Superuser list, grant **Shell** (`com.android.shell`). Verify:

```powershell
& $adb shell su -c id          # must show uid=0(root), context u:r:ksu:s0
```

If root can't be verified, **stop** — don't retry an exploit repeatedly, and don't reboot into a staged update.

---

## Stage 3 — Back up your original partitions

**Goal:** save your own factory images. These are your only recovery path and are **private** (they contain per-unit calibration). They go in `$Backup` (`work\private-backups`), which is git-ignored.

The guide's script reads each partition to a file, pulls it, and verifies the hash. Key partitions: `lk_a`, `boot_a`, `init_boot_a`, `vbmeta_*`, `misc`, and the per-unit ones (`nvram`, `nvdata`, `persist`, `seccfg`, …). See the full loop in [`kit/GUIDE.md` → "Back up your own original images"](https://github.com/jim-wyatt/OtomDev/blob/main/kit/GUIDE.md).

```powershell
# Abbreviated; the kit script backs up all partitions and checks every hash.
& $adb shell su -c 'dd if=/dev/block/by-name/init_boot_a of=/data/local/tmp/init_boot_a.img bs=1048576'
& $adb pull /data/local/tmp/init_boot_a.img "$Backup\init_boot_a.img"
```

!!! warning "Back up `$Backup` off the PC too"
    Copy `work\private-backups` to safe offline storage — not a public cloud share. If the device won't boot later, these files are what you flash back.

---

## Stage 4 — If an update is staged

**Goal:** make sure the device won't reboot into newer, untested firmware. Skip only if you've confirmed no update is pending and both slots are the tested build.

With temporary root, inspect the boot state:

```powershell
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-current-slot'
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot'
```

If an update is staged (current slot A, next boot B, state `UPDATED_NEED_REBOOT`), the procedure cancels it with Android's own `UpdateEngine.resetStatus`, driven by the included [`UpdateHelper`](../develop/helper-programs.md) — a tiny program that calls that one public API. The full sequence, including backing up the update metadata first, is in [`kit/GUIDE.md` → "If an update is staged before the first unlock"](https://github.com/jim-wyatt/OtomDev/blob/main/kit/GUIDE.md). Do **not** reboot until both slots report the same, un-staged state.

---

## Stage 5 — Prepare LK and the Magisk image

**Goal:** build the two files you'll install — all on the PC, nothing flashed yet, fully reversible.

**Patch LK** with [Val Protocol](../reference/credits.md) so the device accepts the standard unlock (background: [the boot chain](../concepts/boot-chain.md#why-this-model-is-extra-work-on-this-device)):

```powershell
& $py "$Work\val-protocol\lk_static_analyzer.py" "$Backup\lk_a.img" -o "$Work\lk-analysis" --no-full-disasm
& $py "$Work\val-protocol\lk_auto_patch.py" "$Backup\lk_a.img" -o "$Work\lk.unlock-serial.img" `
      --analysis-dir "$Work\lk-patch-analysis" --preset unlock-serial --key-token-secret Valeria --keep-workdir
```

The patcher's verifier must report `Result: VALID`. Keep the original `lk_a.img` separate.

**Prepare the Magisk image** from *your own* `init_boot_a` (the included script checks the device matches and writes only a file — it never flashes):

```powershell
& "$Kit\scripts\Prepare-MagiskImage.ps1" -WorkDir $Work -GuideKit $Kit -StockImage "$Backup\init_boot_a.img"
# → work\magisk-patched-init_boot.img  (8 MiB; verify its hash)
```

---

## Stage 6 — Flash LK and unlock

!!! danger "This is the irreversible stage"
    It erases the device and can brick it. Confirm your backups and both prepared files are on the PC first. Read [If the modified LK fails](maintenance.md#recovery) before you start.

Reboot to the bootloader and verify you're on the tested device in Fastboot:

```powershell
& $adb reboot bootloader
& $fb getvar product            # vegas
& $fb getvar current-slot       # a
& $fb getvar securestate        # locked, for now
```

Generate unlock keys from **your own** serial, flash the patched LK to **slot A**, and unlock:

```powershell
& $fb getvar serialno
$PhoneSerial = Read-Host 'Enter YOUR serial exactly as Fastboot reported it'
& $py "$Work\val-protocol\lk_keygen.py" --secret Valeria --serialno $PhoneSerial --count 5

& $fb flash lk_a "$Work\lk.unlock-serial.img"
& $fb reboot bootloader
$UnlockKey = Read-Host 'Paste one of YOUR generated 20-character keys'
& $fb oem unlock $UnlockKey      # approve "Unlock bootloader" ON THE DEVICE, quickly
& $fb getvar securestate         # must now read: flashing_unlocked
& $fb reboot
```

Keep your keys private. The device reboots to a fresh factory setup — the wipe is expected.

!!! info "Why Magisk isn't flashed in Fastboot here"
    On the tested unit, `fastboot flash init_boot_a` rejected the Magisk image ("preflash validation failed") and fastbootd couldn't open the partition. So the image is written from *inside Android* with root instead (stage 7). This is a device quirk, documented in the kit.

---

## Stage 7 — Re-setup and install persistent root

The unlock wiped the device, so **repeat Stage 1** (QR setup, remove Test DPC, Wi-Fi off, USB debugging) and re-verify the build and slot A. Then reinstall the tools and get temporary root again:

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb install "$Work\Magisk-v31.1.apk"
# repeat DFRoot → KernelSU → grant Shell → verify uid=0, and confirm ro.boot.flash.locked = 0
```

Now write the Magisk-patched image to **`init_boot_a` only**, after checking the current partition still matches your backup and the file is the right size. The guarded write (with read-back verification) is in [`kit/GUIDE.md` → "Install persistent Magisk root"](https://github.com/jim-wyatt/OtomDev/blob/main/kit/GUIDE.md):

```powershell
& $adb push "$Work\magisk-patched-init_boot.img" /data/local/tmp/
& $adb shell su -c 'blockdev --setrw /dev/block/by-name/init_boot_a'
& $adb shell su -c 'dd if=/data/local/tmp/magisk-patched-init_boot.img of=/dev/block/by-name/init_boot_a bs=1048576 conv=fsync'
# verify read-back hash matches, then:
& $adb reboot
```

**Finish Magisk setup:** open the **Magisk** app, allow "additional setup" and the reboot it asks for, then confirm root is now persistent and managed by Magisk (not KernelSU):

```powershell
& $adb shell su -c id             # uid=0, context u:r:magisk:s0
& $adb shell su -c 'magisk -v'    # 31.1:MAGISK:R
```

That's the milestone: **root that starts by itself after a normal reboot.**

---

## Stage 8 — Configure the Wi-Fi dev device

**Goal:** apply the two reversible [system modules](../concepts/magisk-modules.md), so the device doesn't auto-update its firmware and isn't cluttered with carrier apps it doesn't need.

```powershell
# Reversibly hide the Motorola updater
& $adb push "$Kit\modules\wifi-ota-guard.zip" /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-ota-guard.zip'

# Reversibly disable the 22 carrier/activation apps (optional; Wi-Fi-only devices)
& $adb shell su -c 'pm disable-user --user 0 com.android.devicelockcontroller'
& $adb push "$Kit\modules\wifi-carrier-debloat.zip" /data/local/tmp/
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-carrier-debloat.zip'
& $adb reboot
```

After reboot, verify (updater gone, carrier apps absent, root still works) with the checks in [`kit/GUIDE.md`](https://github.com/jim-wyatt/OtomDev/blob/main/kit/GUIDE.md). Finally, remove the temporary-root tools, re-enable Wi-Fi, and sign into Google Play to install your own development tools:

```powershell
& $adb shell pm uninstall df.root
& $adb shell pm uninstall me.weishu.kernelsu
& $adb shell svc wifi enable
```

Your development device is ready. Next: [Maintaining the device](maintenance.md), then start [developing](../develop/index.md).
