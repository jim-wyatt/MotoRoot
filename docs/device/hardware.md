# Hardware inventory

What the device actually is, as it reports itself: the SoC and cores, the GPU, memory and storage, the display, the partition map, the sensors and the HALs. Useful for performance work in Android Studio, for knowing which partition is which before any low-level step, and for checking that another unit is the same hardware.

Everything here was produced by the inventory command, `aosp-academy device info`, on unit 2 on the stock system (the build in the [validation record](index.md#validation-record)). The command's raw dumps contain identifiers (serial, IMEI, MAC addresses, installed apps) and stay in `work/device-info/`, which is git-ignored; this page is the curated, identifier-free summary.

## Identity

| Item | Value |
| --- | --- |
| Model | moto g power - 2026, SKU **XT2617V** (Straight Talk / Walmart), product `vegas26` |
| SoC | MediaTek **MT6835** (the kernel reports only the part number; the device tree is `mediatek,MT6835`) |
| Android | 16 (API 36), build `W1WEOS36.48-22-3-3-4-2`, security patch 2026-04-01 |
| Kernel | `5.15.180-android13-8-00018-g9b2308ac0ad6-ab14563692` (GKI 5.15, `android13-5.15` branch) |
| Bootloader | `MBM-3.1-vegas_og_vext-5d518d-W1WEOS36.48-22-3-3-4-2-36210f` (MediaTek LK) |
| Treble | VNDK 33, `ro.product.first_api_level` 36 (launched on Android 16) |
| Verified boot, as prepared | `orange` (unlocked), `ro.boot.flash.locked=0`, active slot `_a` |

## Compute

| | |
| --- | --- |
| CPU | 8 cores: **6 × Cortex-A55 @ 2.0 GHz** (cpu0–5) and **2 × Cortex-A76 @ 2.4 GHz** (cpu6–7). ARM part ids 0xd05 / 0xd0b. Big-core work lands on cpu6–7, which is what to look for in a [Perfetto trace](../apps/tracing.md). |
| GPU | ARM **Mali-G57 MC2**, OpenGL ES 3.2 (driver r38p1) |
| RAM | 7.5 GiB visible to the kernel (an 8 GB part) |
| Virtualization | **Not available.** No `ro.boot.hypervisor.*` properties, no `/dev/kvm`, no `com.android.virt` APEX, so Android 16's built-in Linux Terminal can't run; see [Linux on the device](stock.md#linux-on-the-device). |

## Storage and partitions

One 128 GB UFS device (`sdc`, 122,032 MiB) holds every partition; two small LUNs (`sda`, `sdb`, 4 MiB each) hold the preloader boot copies. `userdata` is 109,232 MiB, of which `/data` reports 107 GB usable.

The device uses **A/B slots** with **dynamic partitions**: the bootable images (`boot`, `init_boot`, `vendor_boot`, `dtbo`, `vbmeta*`, `lk`, and the MediaTek firmware blobs) exist twice, `_a` and `_b`, as physical partitions, while the big Android partitions live inside one 10,944 MiB `super` partition and are mapped at boot. These are the ones the [walkthrough](walkthrough.md) backs up, patches and writes:

| Partition | Size | Role |
| --- | --- | --- |
| `lk_a` / `lk_b` | 16 MiB | The bootloader. The patched copy goes to `lk_a` only. |
| `init_boot_a` / `_b` | 8 MiB | The ramdisk with `init`; where Magisk is installed. |
| `boot_a` / `_b` | 64 MiB | The kernel. |
| `vendor_boot_a` / `_b` | 64 MiB | Vendor ramdisk and kernel modules. |
| `dtbo_a` / `_b` | 8 MiB | Device-tree overlays. |
| `vbmeta_a`, `vbmeta_system_a` (and `_b`) | 8 MiB each | Verified-boot metadata. |
| `misc` | 0.5 MiB | Boot-control and update-engine state (slot selection lives here). |
| `nvram`, `nvdata`, `nvcfg` | 64 / 64 / 32 MiB | Radio calibration and per-unit data: **private, never restore from another unit**. |
| `persist`, `prodpersist`, `proinfo`, `protect1`, `protect2`, `seccfg` | 48 / 8 / 3 / 8 / 8 / 0.5 MiB | Per-unit configuration and security state (`seccfg` holds the lock state). |
| `md1img_a` / `_b` | 200 MiB | Modem firmware. |
| `super` | 10,944 MiB | Container for the dynamic partitions below. |

Dynamic partitions mapped on the active slot:

| Logical partition | Size |
| --- | --- |
| `product_a` | 4,020 MiB |
| `system_ext_a` | 777 MiB |
| `system_a` | 655 MiB |
| `vendor_a` | 590 MiB |
| `vendor_dlkm_a` | 14 MiB |
| `system_dlkm_a` | 0.3 MiB |
| `system_b` (mapped but inactive) | 529 MiB |

Those add up to roughly 6.6 GB of the 10.9 GB `super`, leaving about **4 GB unallocated** by this reckoning. That matters for running a GSI from the other slot (a reported problem on the sibling Moto G 2026 was a full `super`); confirm with `lpdump` before relying on it.

??? note "Every physical partition (96), with sizes"
    ```text
    boot_a            64     boot_b            64     boot_para          1     carrier           16
    cid              0.1     connsys_bt_a/b     8     connsys_gnss_a/b   8     connsys_wifi_a/b   8
    dpm_a/b            4     dram_para         25     dtbo_a/b           8     efuse              8
    efuseBackup        8     expdb            128     flashinfo         16     frp                1
    gz_a/b            32     hw                 8     init_boot_a/b      8     kpan               8
    lk_a/b            16     logks             64     logo_a/b          16     logs               8
    mcf_ota_a/b       32     mcupm_a/b          1     md1img_a/b       200     metadata          64
    misc             0.5     nvcfg             32     nvdata            64     nvram             64
    otp               43     pad0..pad5     5-8      para             0.5     persist           48
    pi_img_a/b         1     preloader_a/b  (UFS boot LUNs)              prodpersist        8
    proinfo            3     protect1           8     protect2           8     pstore           128
    scp_a/b            6     sec1               2     seccfg           0.5     sp                 8
    spmfw_a/b          1     sspm_a/b           1     super          10944     tee_a/b            5
    tzapp_a/b         16     userdata      109232     utags            0.5     utagsBackup      0.5
    vbmeta_a/b         8     vbmeta_system_a/b  8     vcp_a/b            6     vendor_boot_a/b   64
    ```
    Sizes in MiB. `preloader_*` entries are aliases of the two UFS boot LUNs rather than `sdc` partitions. The full table with block-device names is in `work/device-info/<run>/partitions-byname.txt` and `partitions-proc.txt` after running the inventory.

## Display

| | |
| --- | --- |
| Panel | 1080 × 2388, density 390 dpi (2.4375×), punch-hole cutout at the top centre |
| Refresh rates | **120, 90, 60, 30 Hz** modes; the system renders at 60 by default and the panel reports no HDR types |
| Brightness | SDR only (max luminance 500 nits reported) |

## Battery

The kernel reports a design capacity of **5,130 mAh** (`charge_full_design`). That is the fuel gauge's figure; the retail spec sheet is the authority for the marketed number.

## Cameras and sensors

- **3 camera devices** registered with the camera service (camera provider HAL 2.6).
- **49 sensors** registered, covering these Android sensor types: accelerometer, gyroscope, magnetic field (each also uncalibrated), gravity, linear acceleration, rotation vectors (game, geomagnetic, full), orientation, pressure, light, proximity, flicker, significant motion, step counter and detector, tilt detector, gyro temperature, device orientation. The physical parts behind them: ST **LSM6DSO** accelerometer/gyroscope, MEMSIC **MMC56xx** magnetometer, Bosch **BMP580** barometer, Sensortek **STK3A5x** light/proximity and **STK6A2x** light/flicker sensors, plus Motorola's gesture and CapSense virtual sensors (chop, flip, tap, glance, stowed).

## Connectivity

| | |
| --- | --- |
| Wi-Fi | 802.11ax (Wi-Fi 6) enabled in the Wi-Fi service; Wi-Fi HAL 1.0–1.2 (HIDL) from MediaTek's connsys firmware |
| Bluetooth | Bluetooth HAL 1.1 and Bluetooth audio HAL 2.0/2.1 |
| NFC | NFC HAL 1.0/1.1 present |
| GNSS | GNSS HAL 1.0–2.1 (MediaTek AGPS services alongside) |
| Cellular | Radio HAL present with two SIM slots; unused on this Wi-Fi device, and the carrier apps are hidden by the modules |

## Platform services

`lshal` lists **89 HAL interfaces**. Beyond the ones above: audio 6.0/7.x, boot control 1.0–1.2 (what `bootctl` talks to in [the preparation walkthrough](walkthrough.md)), gatekeeper, graphics allocator/mapper 4.0, thermal 1.0/2.0, sound trigger 2.x, and the usual `android.hidl.*` plumbing. The vendor's own `vendor.mediatek.*` interfaces sit alongside. `lshal` as root on the device prints the live list.

## Re-generate this page

```sh
aosp-academy device info                 # writes work/device-info/<timestamp>/ and prints the summary
aosp-academy device info --label gsi     # the same, with a label in the folder name
aosp-academy device info --bugreport     # adds a full adb bugreport (several minutes)
```

Run it on a new unit to check it matches, or after a firmware change. It is read-only, and it needs root on the phone for the device tree, the partition lists and `lshal` (without root those files say `(no root)`). The printed summary is also saved as `summary.txt` next to the raw dumps. Copy facts from the summary, never from the raw files, and keep serial numbers, IMEIs, MAC addresses and display unique ids out of the docs; the pre-commit hook blocks the obvious ones but not all.
