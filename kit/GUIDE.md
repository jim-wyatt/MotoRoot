# Moto G Power 2026 Straight Talk WiFi and persistent root guide

Tested November 14, 2026, on one Walmart Straight Talk **XT2617V** running **Android 16, build W1WEOS36.48-22-3-3-4-2, April 1 2026 security patch**.

# Overview

Start with this exact phone and firmware, a Windows PC, a USB data cable, Wi-Fi, and the tools below. The successful process produced a stock Android Wi-Fi device with Google Play, an unlocked bootloader, Magisk root that survives ordinary restarts, and reversible carrier/update app blocking. No Straight Talk plan was purchased or activated.

There are four separate operations:

1. Google Test DPC provisioning provides an alternate Android setup path around the carrier activation screen.
2. DFRoot and KernelSU provide **temporary** root on the tested factory kernel.
3. Val Protocol modifies the phone's own LK bootloader so its bootloader can be unlocked. Unlocking erases Android user data.
4. With the bootloader unlocked, temporary root writes a Magisk-patched copy of the phone's original `init_boot` image. Magisk then supplies persistent root.

Google Play remains available. Some games, banking apps, or streaming apps may reject an unlocked/rooted device. No Play Integrity bypass was installed or tested.

## Compatibility and risk checkpoints

Compare your phone with the [tested hardware and firmware table](README.md#exact-tested-phone). The bootloader screen calls this product `vegas`; Android reports `vegas26`. Do not confuse it with earlier Power models.

**Stop if the model, build, patch, kernel, or active slot differs from the tested configuration.** A tool recognizing a kernel family or returning `VALID` for a file is not proof that your phone will accept or boot that file. Newer patches can close the vulnerabilities used here.

The highest-risk operation is replacing LK and rebooting into it. If the modified LK fails before Fastboot starts, a stock LK backup may be impossible to restore without a vendor-authorized MediaTek recovery method. **No reliable emergency recovery procedure was established or tested for this exact unit.** Do not proceed unless you accept that possibility. A normal stock image restore command is not a guaranteed unbrick tool.

Keep the original backups private. They can contain device-specific calibration and security data. Never restore another person's `nvram`, `nvdata`, `persist`, `seccfg`, or preloader images. Never publish your IMEI, serial number, raw logs, or generated unlock keys.

# Computer preparation

## Tools and exact versions used

| Tool | Tested version or source |
| --- | --- |
| Windows PowerShell | Windows PC, native PowerShell |
| ADB and Fastboot | Google Platform Tools 37.0.1-15733141 |
| Motorola Windows USB driver | Official signed 64-bit installer |
| Python | 3.14 on the reference PC; Val Protocol recommends Python 3.11 or newer |
| Git | Needed to obtain the pinned Val Protocol source |
| Test DPC | 9.0.16 during the reference provisioning |
| DFRoot | 4.7 |
| KernelSU manager | 3.3.1, version code 32680 |
| Magisk | 31.1 |
| Val Protocol | Commit `dc7f41f9b1a32da1a78ef327bb62d2bef17d7bd0` |

Sources: [Platform Tools](https://developer.android.com/tools/releases/platform-tools), [Motorola USB drivers](https://en-us.support.motorola.com/app/usb-drivers), [Python](https://www.python.org/downloads/windows/), [Git for Windows](https://git-scm.com/downloads/win), [DFRoot 4.7](https://github.com/diabl0w/DFRoot/releases/tag/v4.7), [KernelSU 3.3.1](https://github.com/tiann/KernelSU/releases/tag/v3.3.1), [Magisk 31.1](https://github.com/topjohnwu/Magisk/releases/tag/v31.1), [Val Protocol](https://github.com/Maikyxd/val-protocol).

Download the guide kit from this repository's release and extract it to a folder called `guide-kit` inside your work folder. Inspect its source before running anything. No third-party installers or firmware are included.

## Make a work folder and install Platform Tools

Use a PowerShell window for the commands below. Keep the same window open: later sections reuse its variables. If you close it, rerun this variable block.

```powershell
$Work = Join-Path $env:USERPROFILE 'MotoRoot'
$Kit = Join-Path $Work 'guide-kit'
$adb = Join-Path $Work 'platform-tools\adb.exe'
$fb = Join-Path $Work 'platform-tools\fastboot.exe'
$Backup = Join-Path $Work 'private-backups'
New-Item -ItemType Directory -Force -Path $Work | Out-Null
Set-Location $Work
```

Extract the release ZIP so that `$Kit\GUIDE.md`, `$Kit\modules`, and `$Kit\helpers` exist. GitHub's automatically generated source ZIP has a repository-name parent folder; rename/move that folder to `guide-kit` if using it.

```powershell
Invoke-WebRequest 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile "$Work\platform-tools.zip"
Expand-Archive -LiteralPath "$Work\platform-tools.zip" -DestinationPath $Work -Force
& $adb version
```

The download URL supplies the current Platform Tools, which may be newer than the version tested. Do not confuse Platform Tools with an entire Android Studio install; Android Studio is not required.

Download and install the signed Motorola 64-bit USB driver **before** entering Fastboot. In the reference session, ADB worked without it but Fastboot did not; Windows showed error 28 until the driver was installed. The installer may need Windows administrator approval. Do not disable driver-signature enforcement.

## Download and verify the APKs

Run these in the work folder. The pinned hashes identify the exact files used in the successful session.

```powershell
$Downloads = @(
  @{
    Name='DFRoot_4.7.apk'
    Url='https://github.com/diabl0w/DFRoot/releases/download/v4.7/DFRoot_4.7.apk'
    Hash='9e193ffdaada8577e14a04fb19403256b3fa4991fae1331c7956e083c098a7b1'
  },
  @{
    Name='KernelSU_v3.3.1_32680-release.apk'
    Url='https://github.com/tiann/KernelSU/releases/download/v3.3.1/KernelSU_v3.3.1_32680-release.apk'
    Hash='b4a059ace71de2fa65cc7f12b1c58d55fc23ab25e057ee4230ce779742abe450'
  },
  @{
    Name='Magisk-v31.1.apk'
    Url='https://github.com/topjohnwu/Magisk/releases/download/v31.1/Magisk-v31.1.apk'
    Hash='89cefac0a318afa39fb3880c45c87b036c05bc1ebf02a7a715b7f8d7c26ac6e7'
  }
)
foreach ($Item in $Downloads) {
  $Path = Join-Path $Work $Item.Name
  Invoke-WebRequest $Item.Url -OutFile $Path
  $Actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
  if ($Actual -ne $Item.Hash) { throw "Hash mismatch: $($Item.Name). Stop." }
}
```

Do not substitute random APK mirrors or paid unlock utilities. The upstream versions may eventually disappear or change availability; a missing file is a reason to investigate, not ignore a hash mismatch.

# First Android setup without a carrier plan

1. While powered off, remove the physical SIM. Charge the phone sufficiently; keep it charged throughout. A wall charger is fine before USB work begins.
2. Start the phone. At the first Welcome/Hello screen, tap the **same blank spot six times** to open Android's enterprise-provisioning QR scanner.
3. On the PC, open [Google's official Test DPC QR image](https://raw.githubusercontent.com/googlesamples/android-testdpc/master/qrcode.png), linked from the [Test DPC instructions](https://github.com/googlesamples/android-testdpc#provisioning).
4. Scan that QR. Connect to Wi-Fi when prompted so Android can download Test DPC.
5. Choose **Use for work only**. At **Finish Setup**, tap **Finish**.
6. Disable optional Motorola features, particularly **Smart updates**. Decline optional app installs. Location, phone-number verification, and diagnostic sharing are optional; they were turned off in the successful session.
7. Skip Google account sign-in for now. Unlocking later erases user data.
8. Once the home screen appears, **turn Wi-Fi off immediately**. A firmware update downloaded during the reference session despite declining optional features; Smart updates being off is not a reliable block.
9. Open Settings, find **Build number**, and tap it seven times. Enable **USB debugging** in Developer options.
10. Connect the USB data cable to the PC, unlock the screen, and approve **Allow USB debugging**. You can choose Always allow for your own trusted PC. No special USB file-transfer mode was needed for ADB in this session.

This is Android setup provisioning, not cellular activation or SIM unlocking. It temporarily makes Test DPC the device owner. Use the Google QR, not a QR that enrolls your phone under an unknown administrator.

```powershell
& $adb devices -l
```

Proceed only if **exactly your intended phone** is listed as `device`. `unauthorized` means you still need to approve the phone prompt. Disconnect other Android devices to avoid targeting the wrong phone.

## Remove Test DPC management

The Test DPC UI repeatedly crashed on the reference phone. Its service command interface worked:

```powershell
& $adb shell dumpsys activity service com.afwsamples.testdpc/.DeviceAdminService clear-device-owner
& $adb shell dumpsys device_policy
```

The second command should show no Device Owner or Profile Owner. Its Enabled Device Admins section should become empty; allow a moment for cleanup and check again if necessary.

```powershell
& $adb shell pm uninstall com.afwsamples.testdpc
& $adb shell svc wifi disable
& $adb shell settings put global ota_disable_automatic_update 1
```

Uninstall should return `Success`. Do not simply uninstall an active device owner or factory-reset to remove it. **Do not scan the QR again once setup is complete.** The automatic-update setting above is only an extra precaution; it does not cancel a staged update.

## Confirm the factory build

```powershell
& $adb shell getprop ro.product.model
& $adb shell getprop ro.boot.hardware.sku
& $adb shell getprop ro.build.fingerprint
& $adb shell getprop ro.build.version.security_patch
& $adb shell uname -r
& $adb shell getprop ro.boot.slot_suffix
```

The tested fingerprint was:

```text
motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys
```

Patch: `2026-04-01`. Kernel: `5.15.180-android13-8-00018-g9b2308ac0ad6-ab14563692`. Slot: `_a`.

If an update is downloading, turn Wi-Fi off. If it is already processing or asks for a restart, **do not restart**. Continue only as far as obtaining temporary root and then follow the staged-update section below. The reference procedure successfully cancelled a completed update before rebooting, but that requires root and successful verification of the slot state.

# Obtain temporary root

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb shell am start -n df.root/.MainActivity
```

On the phone:

1. In DFRoot, select **KernelSU** as the SU manager.
2. Keep **Start at Boot OFF**, **Auto Soft Reboot OFF**, and **Disable KSU Modules OFF**.
3. Tap **Launch Root once**. Do not install modules, flash a kernel, or repeatedly retry a failed exploit.
4. KernelSU should show **Working [Jailbreak mode]**.
5. In KernelSU's **Superuser** section, enable **Shell**, package `com.android.shell`. It may appear directly; otherwise enable Show system apps in the filter.

```powershell
& $adb shell su -c id
```

Required result: `uid=0(root)`, with a KernelSU context such as `u:r:ksu:s0`.

The green checkmark alone is not sufficient. If ADB says `su: inaccessible or not found`, check Shell's permission in KernelSU. If root cannot be verified, stop. DFRoot relies on a vulnerable kernel and can fail or crash on other firmware. A crash can reboot the phone, so avoid an intentional attempt while knowingly accepting a staged update on next boot.

**This root is temporary.** Rebooting loses it. DFRoot also made many partitions read-only on the tested phone. Later steps deliberately lift that flag only for the partition they need to write, then restore it.

# Back up your own original images

Do this before any bootloader or root-image modification. The script below reads the selected partitions to temporary files, pulls them to the PC, and verifies every hash. It does not write a firmware partition. Ensure the PC has several GB free and the phone has room for the temporary copies. These are targeted recovery backups, not a full-device or full-OS image.

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
Get-ChildItem -LiteralPath $Backup -Filter '*.img' |
  Get-FileHash -Algorithm SHA256 |
  Export-Csv -LiteralPath "$Backup\sha256.csv" -NoTypeInformation
```

The active factory `init_boot_a.img` in the reference session was 8 MiB and had SHA-256:

```text
31239df6b54fd815912ba7d0e4cc87aca3af200eed8ff315238e4178580285ea
```

Treat a differing hash on an allegedly identical build as a reason to investigate. Do not replace it with a download from another user. If an update has staged, the inactive-slot backup can already contain updated components; **do not assume `lk_b` is an untouched factory fallback**.

# If an update is staged before the first unlock

Skip this section only if no update is pending and you have verified the current and next boot slots. Choose **Later** on a restart prompt. Force-stopping the updater, turning off Wi-Fi, or setting the Developer option did **not** cancel a fully downloaded update in the reference session.

With temporary root, inspect the boot state:

```powershell
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-current-slot'
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot'
& $adb shell su -c 'tail -n 35 /data/misc/update_engine_log/update_engine.log'
```

On the tested phone, current slot was `0` (A), next boot was `1` (B), and the update was `UPDATED_NEED_REBOOT`. The successful fix called Android's [UpdateEngine resetStatus API](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/UpdateEngine.java), which cancels the completed update before reboot and cleans up its snapshots.

The kit's [UpdateHelper.java](helpers/UpdateHelper.java) exposes only API inspection and that reset. Its [compiled helper](helpers/UpdateHelper.dex) is included with source and [rebuild instructions](helpers/BUILD.md). It does not choose slots by editing raw boot metadata.

Back up update metadata first, then push and inspect the helper:

```powershell
& $adb shell su -c 'tar -cf /data/local/tmp/update-engine-before-reset.tar /data/misc/update_engine/prefs /data/misc/update_engine_log /metadata/ota'
& $adb pull /data/local/tmp/update-engine-before-reset.tar "$Backup\update-engine-before-reset.tar"
& $adb push "$Kit\helpers\UpdateHelper.dex" /data/local/tmp/moto-update-helper.dex
& $adb shell su -c 'CLASSPATH=/data/local/tmp/moto-update-helper.dex app_process /system/bin UpdateHelper inspect'
```

For the tested **current A / next B** state, after backing up `misc`, execute:

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

Both slots must report **0**, and the log should show the slot switch cancelled and update state/snapshots removed. If reset fails, do not reboot or manually erase `/metadata` or update-engine files. The first reference attempt failed because DFRoot had made `misc` read-only; temporarily allowing that one partition to be written resolved it.

Motorola's notification and automatic-restart alarm can remain after the engine reset. They are separate app state. After confirming the engine reset, the successful session removed the updater's existing alarms and notification using [UpdaterCleanup.java](helpers/UpdaterCleanup.java). Discover the updater's UID on your own phone; do not copy a UID from another device:

```powershell
$OtaLine = (& $adb shell pm list packages -U com.motorola.ccc.ota) -join ''
if ($OtaLine -notmatch 'package:com\.motorola\.ccc\.ota\s+uid:(\d+)') { throw 'Cannot identify updater UID' }
$OtaUid = $Matches[1]
& $adb push "$Kit\helpers\UpdaterCleanup.dex" /data/local/tmp/moto-updater-cleanup.dex
& $adb shell su -c 'chmod 0444 /data/local/tmp/moto-updater-cleanup.dex'
& $adb shell su $OtaUid -c 'CLASSPATH=/data/local/tmp/moto-updater-cleanup.dex app_process /system/bin UpdaterCleanup cancel'
& $adb shell dumpsys alarm | Select-String '^\s+RTC.*com.motorola.ccc.ota'
```

The helper should report that updater alarms and notifications were removed; the last command should show no matching scheduled RTC alarm. Making the DEX read-only avoids an Android runtime rejection encountered in the session. This is a temporary cleanup of scheduled app work, not permanent updater removal. The later Magisk module is the durable updater block.

**Do not interpret a stale notification as proof that the engine is still staged, or a hidden notification as proof it was cancelled.** Verify slots and engine logs. If you cannot confidently reconcile them, stop before rebooting. Do not leave an automatic-restart deadline unattended.

# Prepare the bootloader and persistent root files

## Analyze and patch your own LK with Val Protocol

On the PC:

```powershell
Set-Location $Work
git clone https://github.com/Maikyxd/val-protocol.git
git -C "$Work\val-protocol" checkout dc7f41f9b1a32da1a78ef327bb62d2bef17d7bd0
python -m venv "$Work\.venv"
$py = "$Work\.venv\Scripts\python.exe"
& $py -m pip install -r "$Work\val-protocol\requirements.txt"
& $py -m pip install pyasn1
& $py "$Work\val-protocol\lk_static_analyzer.py" "$Backup\lk_a.img" -o "$Work\lk-analysis" --no-full-disasm
```

`pyasn1` was missing from the upstream requirements used in the session; without it, a misleading error suggested `liblk` was absent. Do not install an unrelated package merely because of that message.

Inspect the analysis. The reference image was AArch64, with an extracted LK payload of 1,238,664 bytes. The analyzer found unlock flow, FRP/OEM checks, a key validator, partition erase operations, and the runtime serial getter. If those are missing, stop.

```powershell
& $py "$Work\val-protocol\lk_auto_patch.py" "$Backup\lk_a.img" -o "$Work\lk.unlock-serial.img" --analysis-dir "$Work\lk-patch-analysis" --preset unlock-serial --key-token-secret Valeria --keep-workdir
```

The tested secret was `Valeria`; it must match key generation later. Keep the **original** image separate. The patcher must complete successfully and its verifier must report `Result: VALID`. The tested output changed LK and its certificate metadata while preserving the other subimages' payloads and certificates. The verifier skipped comparison against the chip's trusted root. This remains an experimental bootloader modification.

The `unlock-serial` preset retains the normal unlock flow, which includes erases. Do not substitute FRP-erasing presets or experiment with erase targets. No FRP bypass is needed for a new phone you own.

## Prepare Magisk from the original init_boot

The successful session used Magisk 31.1's own patch script and binaries, extracted from the verified APK, running on the target phone. The supplied [Prepare-MagiskImage.ps1](scripts/Prepare-MagiskImage.ps1) reproduces that file-only preparation. It does **not** flash a partition.

```powershell
& "$Kit\scripts\Prepare-MagiskImage.ps1" -WorkDir $Work -GuideKit $Kit -StockImage "$Backup\init_boot_a.img"
```

If your PowerShell execution policy prevents running a reviewed script, you can allow it for this terminal only with `Set-ExecutionPolicy -Scope Process Bypass`. This does not require disabling Windows protections permanently. Review the script first.

Required input is your original factory `init_boot_a.img`, not `boot_a.img`, another phone's image, or an already patched image. The script preserves verity/encryption settings, sets `PATCHVBMETAFLAG=false`, uses Magisk's patch/repack logic, and pulls the output to:

```text
MotoRoot\magisk-patched-init_boot.img
```

It must be 8 MiB or less and have matching PC/phone hashes. The output from the reference run was 8 MiB with SHA-256 `fbac252d15501e8350b65ae93a92962f93d2907144286c04abf2eeda26c246d0`; a freshly produced image can differ, so verify **your own output's** transfer and write hashes rather than blindly expecting that hash.

# Flash LK and unlock the bootloader

**This is the point at which the phone can become unrecoverable. Unlocking also erases user data.** Read the recovery section before proceeding. Confirm that backups and both prepared files are on the PC, because the phone's temporary files and apps will be erased.

```powershell
& $adb reboot bootloader
```

Wait for the bootloader screen, then:

```powershell
& $fb devices -l
& $fb getvar product
& $fb getvar current-slot
& $fb getvar version-bootloader
& $fb getvar partition-size:lk_a
& $fb getvar partition-size:init_boot_a
```

Required reference values: product `vegas`, slot `a`, original `4-2` bootloader; `lk_a` size `0x1000000` (16 MiB), `init_boot_a` size `0x800000` (8 MiB). If Fastboot lists nothing, fix the signed Motorola driver before issuing more commands. ADB approval does not install the Fastboot driver. If more than one device is connected, disconnect the others.

Generate keys using **your** Fastboot serial, not someone else's:

```powershell
& $fb getvar serialno
$PhoneSerial = Read-Host 'Enter YOUR serial exactly as Fastboot reported it'
& $py "$Work\val-protocol\lk_keygen.py" --secret Valeria --serialno $PhoneSerial --count 5
```

Save the generated 20-character alphanumeric keys privately. Do not use a serial or key from a screenshot or tutorial.

For verified slot A only:

```powershell
& $fb flash lk_a "$Work\lk.unlock-serial.img"
if ($LASTEXITCODE -ne 0) { throw 'LK flash failed. Stop without rebooting.' }
& $fb reboot bootloader
```

Wait for Fastboot to return. The reference phone briefly enumerated as a MediaTek serial device before returning to Motorola Fastboot; that transient appearance was not a failure. **If it never returns, do not flash other partitions or erase anything.**

```powershell
& $fb devices -l
& $fb getvar current-slot
$UnlockKey = Read-Host 'Paste one of YOUR generated 20-character keys'
if ($UnlockKey -cnotmatch '^[A-Za-z0-9]{20}$') { throw 'Unexpected key format' }
& $fb oem unlock $UnlockKey
```

Watch the phone immediately and approve **Unlock bootloader** using its displayed button instructions. The confirmation may time out quickly. The successful command returned `Bootloader is unlocked!`.

```powershell
& $fb getvar securestate
```

Required result: **`flashing_unlocked`**. The reference phone also reported warranty-void state. Do not confuse `secure: yes` with still being locked; the securestate field is the relevant result here.

## Why this guide does not flash Magisk through Fastboot

On the reference phone, `fastboot flash init_boot_a` rejected the Magisk 31.1 image with **Preflash validation failed**, despite the unlocked state. Entering `fastbootd` confirmed userspace Fastboot and `unlocked: yes`, but it could not open `init_boot_a` and reported no slotted `init_boot` access. No verification partitions were altered to work around that.

The successful route was to boot the original Android system, obtain temporary root again, and write the prepared image from Android. Similar preflash failures are documented in [Magisk's issue tracker](https://github.com/topjohnwu/Magisk/issues/8718), but that does not establish an identical cause for this phone. Do not add random vbmeta flashes, downgrade Magisk, or try an unrelated boot image simply because a forum suggests it.

```powershell
& $fb reboot
```

# Repeat setup after the unlock wipe

The reference phone returned to Android's initial setup screen. Repeat the Test DPC QR setup from the beginning:

1. Six taps on Welcome, scan Google's QR, and connect to Wi-Fi.
2. **Use for work only**, finish, decline Smart updates and optional installs, skip Google sign-in.
3. At the home screen, turn Wi-Fi off immediately.
4. Enable Developer options and USB debugging again; approve your PC again.
5. Run the **Remove Test DPC management** commands again and verify no management role remains.
6. Verify the same factory build and slot A. If a fresh update staged, resolve it before another reboot.

Install the tools again:

```powershell
& $adb install "$Work\KernelSU_v3.3.1_32680-release.apk"
& $adb install "$Work\DFRoot_4.7.apk"
& $adb install "$Work\Magisk-v31.1.apk"
& $adb shell am start -n df.root/.MainActivity
```

Repeat **Obtain temporary root**, including granting Shell root in KernelSU. Verify:

```powershell
& $adb shell su -c id
& $adb shell getprop ro.boot.flash.locked
& $adb shell getprop ro.boot.slot_suffix
& $adb shell getprop ro.build.fingerprint
& $adb shell su -c '/data/adb/ksu/bin/bootctl get-active-boot-slot'
```

Required: root works, `ro.boot.flash.locked` is **0**, current suffix is **_a**, next boot is **0**, and the build is still the tested factory build.

# Install persistent Magisk root

This writes **only `init_boot_a`**. Do not change the `dd` destination. Do not write `boot_a`, `lk_b`, both slots, or any calibration/security partition as a substitute.

First check that the partition still matches your original backup:

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

If all checks pass and you accept the write:

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
```

**Only after the write and readback both succeed**, run:

```powershell
& $adb shell su -c sync
& $adb reboot
```

Wait for Android to reach the home screen. Startup can take around a minute or more, including the unlocked-bootloader warning and delayed ADB connection. Do not repeatedly force-restart it. If it loops or displays a boot error, use the recovery section rather than continuing.

## Finish Magisk setup and prove root survives a reboot

1. Open **Magisk**, not KernelSU.
2. If it says **Requires additional setup**, tap OK and allow its requested reboot. This happened on the reference phone.
3. After Android returns, grant **Shell** superuser access in **Magisk**. The old KernelSU permission does not carry over. If needed, check Magisk's Superuser access setting includes ADB.
4. Do **not** launch DFRoot again. The purpose of this test is to establish that Magisk starts by itself.

```powershell
& $adb shell su -c id
& $adb shell su -c 'magisk -v'
& $adb shell ps -A | Select-String 'magiskd|ksud'
```

The reference result was `uid=0(root)` with **`context=u:r:magisk:s0`**, version **`31.1:MAGISK:R`**, Magisk processes running, and no KernelSU daemon. That is the persistent-root checkpoint. A green app indicator or the mere presence of the Magisk app is not enough.

# Block automatic firmware updates

Install the supplied reversible module **before** turning Wi-Fi on for regular use:

```powershell
& $adb push "$Kit\modules\wifi-ota-guard.zip" /data/local/tmp/wifi-ota-guard.zip
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-ota-guard.zip'
if ($LASTEXITCODE -ne 0) { throw 'Module install failed' }
& $adb shell settings put global ota_disable_automatic_update 1
& $adb reboot
```

After the home screen and ADB return:

```powershell
& $adb shell su -c id
& $adb shell pm path com.motorola.ccc.ota
& $adb shell su -c 'ls -la /system_ext/priv-app/3c_ota'
& $adb shell ps -A | Select-String 'ccc.ota'
```

Required result: root works, `pm path` prints no updater APK, its overlaid directory is empty, and no updater process runs. The module uses [Magisk's documented system folder overlay](https://topjohnwu.github.io/Magisk/guides.html); the original updater APK is not deleted from the firmware partition.

The normal package manager refused to disable the updater, even with root/system identity, on this phone. Do not assume `pm disable-user` or a Developer option is equivalent to this verified block. This module covers **Motorola Software Update**, not every update delivered by Google or every future update path.

# Optional carrier and finance app debloat

This section is for a **Wi-Fi-only device**. It can break cellular setup, service management, voicemail, and SIM-related functions. It deliberately retains common Wi-Fi, Google, and hardware-security services. Static carrier overlays can remain because they contain resources rather than runnable carrier services.

Inspect [carrier-debloat-manifest.json](carrier-debloat-manifest.json) first. It lists the exact 22 packages and APK directories verified on the tested build. If your package paths differ, do not install it unchanged. The module has no general-purpose device detection or automatic safety check.

```powershell
& $adb shell su -c 'pm disable-user --user 0 com.android.devicelockcontroller'
& $adb push "$Kit\modules\wifi-carrier-debloat.zip" /data/local/tmp/wifi-carrier-debloat.zip
& $adb shell su -c 'magisk --install-module /data/local/tmp/wifi-carrier-debloat.zip'
if ($LASTEXITCODE -ne 0) { throw 'Carrier module install failed' }
& $adb reboot
```

The module hides:

```text
com.motorola.setupwizard.phoneservice
com.mediatek.rsu.tfn
com.verizon.remoteSimlock
com.motorola.tracfone.setup
com.motorola.vzw.cloudsetup
com.motorola.setupwizard.devicesetup
com.motorola.omadm.vzw
com.motorola.vzw.pco.extensions.pcoreceiver
com.motorola.paks.notification
com.motorola.tracfone.rsu
com.verizon.mips.services
com.vzw.hss.myverizon
com.vzw.ecid
com.vzw.apnlib
com.motorola.paks
com.motorola.extensions.tracfone
com.motorola.vzw.provider
com.motorola.vzw.phone.extensions
com.motorola.omadm.service
com.motorola.vzw.settings.extensions
com.motorola.vzw.voicemail.extensions
com.motorola.setupwizard.controller
```

PAKS held Android's financed-device-controller role on the reference phone. This was **not proof of active financing enrollment or proof a nonpayment lock was scheduled**. Android's [DeviceLockManager](https://developer.android.com/reference/android/devicelock/DeviceLockManager) supports financed-device restrictions, so disabling these identified app-level paths addressed that concern. It does not establish control over every undocumented modem, trusted-execution-environment, or firmware behavior.

## Verify debloat and normal app use

After reboot:

```powershell
& $adb shell su -c id
& $adb shell pm list packages -d | Select-String 'devicelockcontroller'
& $adb shell cmd role get-role-holders android.app.role.SYSTEM_FINANCED_DEVICE_CONTROLLER
& $adb shell dumpsys device_policy
& $adb shell ps -A | Select-String 'com.verizon|com.vzw|com.motorola.omadm|com.motorola.paks|com.motorola.tracfone|ccc.ota'
```

On the reference unit, the controller stayed disabled, the financed-controller role had no holder, device administrators were absent, all 22 targeted APK packages were absent from the installed list, and no targeted carrier/updater processes or restart alarms remained. Root still worked.

Remove the temporary-root tools only after persistent root has been verified:

```powershell
& $adb shell pm uninstall df.root
& $adb shell pm uninstall me.weishu.kernelsu
& $adb shell svc wifi enable
& $adb shell am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p com.android.vending
```

Sign into Google on the phone. In the reference session, sign-in, Play Store launch, and Wi-Fi internet worked; a specific game's installation or compatibility was not independently tested. Install your chosen apps normally and grant root only to apps you trust.

# Safe and risky actions afterward

These categories concern preserving this working root/update-block configuration. Installing an untrusted app is not made safe merely because it came from an app store.

| Action | Guidance |
| --- | --- |
| Install ordinary apps or games from Google Play | Normally fine for root persistence. An app can still refuse rooted devices or fail its own integrity checks. |
| Update an ordinary Play Store app | Normally fine. This does not ordinarily replace `init_boot` or the bootloader. |
| Allow normal automatic Play Store app updates | Normally fine; separate from firmware OTA updates. |
| Sign into Google, browse, use Wi-Fi/Bluetooth, change ordinary app settings | Normally fine. Play Store and Wi-Fi were verified on the reference phone. |
| Reboot or shut down normally | Root and the two modules survived normal reboots in this session. Keep backups and USB recovery access available. |
| Grant a new app root | High trust decision. Root can change firmware, security policy, or data. Deny requests from games or apps that do not need it. |
| Update just the Magisk manager APK | Usually does not itself replace the boot image, but it is a root-management tool. Review its release notes and compatibility rather than treating it like an ordinary game update. |
| Use Magisk Direct Install or update the Magisk root framework | Writes boot-related state and can break startup or root. Back up and plan recovery first; no future version upgrade is validated here. |
| Install or update Magisk modules | Can affect boot, security, and app behavior. Do not install random performance, integrity-bypass, or kernel modules without a recovery plan. |
| Disable/remove either blocking module | Restores the respective carrier apps or Motorola updater on reboot. This removes that part of the protection. |
| Accept Motorola firmware/security/Android OS updates | Risk of overwriting root, changing the bootloader, or closing the exploit used to recover. Do not install casually. Plan an intentional update and reroot procedure first. |
| Google Play system updates | Separate from ordinary Play Store app updates. They can update system/APEX components and require reboot; they are not blocked by the Motorola updater module. Treat as untested for this configuration, not guaranteed root loss or guaranteed safety. |
| Factory reset | Erases user data, root permissions, and module/configuration files. Patched boot state may remain, but the complete setup is not guaranteed to survive. Carrier setup and updater apps can return. |
| Motorola Software Fix/Rescue or a stock firmware flash | Can erase data and replace rooted images. Not a routine debloat or update action. |
| Relock the bootloader | **Do not relock with modified LK/init_boot or unmatched firmware.** A rejected boot chain can leave the phone unusable. |
| Change active slot or flash both slots | Untested and hazardous here. Slot B is not a validated fallback OS, particularly after cancellation of its staged update. |
| Delete system APKs, edit raw security/calibration partitions, erase metadata | Not part of normal use. Prefer the reversible modules; do not experiment with partition erases. |
| Expect all games/banking apps to pass device integrity | Not guaranteed. Neither root hiding nor Play Integrity bypass was installed or tested. |

Keeping April 2026 firmware also means retaining its known security weaknesses. Blocking updates preserves this tested setup at the cost of firmware security fixes. Choose future updates deliberately; the block is reversible.

# Recovery and undo instructions

## Restore the hidden apps

In Magisk Modules, disable **Wi-Fi device carrier debloat** and/or **Motorola automatic firmware update block**, then reboot. Re-enable the device-lock controller separately if undoing the carrier changes:

```powershell
& $adb shell su -c 'pm default-state --user 0 com.android.devicelockcontroller'
```

Alternatively, while ADB root still works:

```powershell
& $adb shell su -c 'touch /data/adb/modules/wifi_carrier_debloat/disable'
& $adb shell su -c 'touch /data/adb/modules/wifi_ota_guard/disable'
& $adb reboot
```

Use only the disable commands for modules you actually want to undo. Restoring the updater allows it to offer firmware updates again. Disabling a module is reversible; physically removing its directory or modifying the original system partition is unnecessary.

## If the Magisk root image does not boot

If normal bootloader Fastboot remains accessible and unlocked, an intended recovery is restoring **your original** image to the exact affected slot:

```powershell
& $fb flash init_boot_a "$Backup\init_boot_a.img"
```

Check the write result before rebooting. The reference session did not need or test this restore; it is a conditional recovery path, not a guarantee. Returning to stock `init_boot` removes boot-time Magisk root and therefore its module overlays.

## If the modified LK fails

If Fastboot is still accessible, restoring the original active-slot LK is the intended rollback:

```powershell
& $fb flash lk_a "$Backup\lk_a.img"
```

That restore was not tested in this session. If Fastboot cannot start, these commands cannot run. Do not assume the other slot, MediaTek COM-port appearance, a generic BROM utility, or a random download agent guarantees recovery. No vendor-independent emergency recovery procedure was established for this exact model.

## What failed during the reference session

- Test DPC's settings UI crashed; its ADB service interface successfully cleared device ownership.
- Turning off Wi-Fi and disabling Smart updates did not stop an already-downloaded OTA from finishing its processing.
- Ordinary updater disable and clear-data commands were rejected as protected operations, even with root/system identity.
- UpdateEngine reset initially failed while `misc` was read-only; its supported API succeeded when that one partition was temporarily writable.
- Fastboot rejected the patched Magisk image; fastbootd did not expose `init_boot`.
- Rooted Android writing the exact prepared `init_boot_a` image, with readback verification, succeeded after bootloader unlock.

# Credits and sharing

Credit belongs to the upstream authors of [Test DPC](https://github.com/googlesamples/android-testdpc), [DFRoot](https://github.com/diabl0w/DFRoot), [KernelSU](https://github.com/tiann/KernelSU), [Val Protocol](https://github.com/Maikyxd/val-protocol), and [Magisk](https://github.com/topjohnwu/Magisk). Google provides Platform Tools; Motorola provides the signed Windows driver.

This repository contains a sanitized procedure and original small helper/module files. It does not redistribute upstream APKs or device firmware. Preserve upstream attribution and licenses when redistributing their own code. Never add your phone's backups or raw session logs to a public issue or repository.

When reporting a different result, share the model, build, security patch, kernel family, step, and error text. Redact serial numbers, IMEIs, account names, network identifiers, and unlock keys. A successful attempt on another build should be reported as a new compatibility result, not assumed from this one.
