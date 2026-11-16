# Maintaining the device

Once the device is prepared, the job is to keep that working state while you develop on it. This page covers what's safe, what isn't, and how to recover.

## Safe vs. risky

| Action | Verdict |
| --- | --- |
| Install apps and tools from Google Play | Fine. Some apps refuse rooted/unlocked devices; that's their choice. |
| Normal Play Store app updates | Fine — separate from firmware. |
| Reboot / shut down | Fine. Root and all three modules survive normal reboots. |
| Grant a new app root in Magisk | High-trust decision. Grant only to dev tools you trust; deny games and random apps. |
| Enable/disable a system module | Fine and reversible — that's the point of [modules](../concepts/magisk-modules.md). |
| Update the Magisk app | Usually fine, but it's your root manager — read its release notes, don't treat it like a game update. |
| **Magisk Direct Install / framework upgrade** | Writes boot state; can break startup. Back up and plan recovery first. |
| **Accept a Motorola firmware/OS update** | Can overwrite root, change the bootloader, or close the path used to prepare the device. Don't accept casually — plan it. |
| Google Play *system* updates | Different from app updates; can touch system components. Untested here. |
| **Relock the bootloader** | Don't, with modified LK/`init_boot`. A rejected boot chain can brick the device. |
| **Change active slot / flash both slots** | Untested and hazardous. Slot B isn't a validated fallback. |
| Factory reset | Erases `/data`, which holds your apps, Magisk's root grants **and the three modules** (`/data/adb/modules`). The prepared boot state may remain, but expect to re-grant Shell and reinstall the modules; the full setup isn't guaranteed. |

The theme: **ordinary app-level use is fine; anything that writes the boot chain or firmware needs a plan and a backup.**

## Keeping firmware updates off

The `wifi-ota-guard` [module](../concepts/magisk-modules.md#wifi-ota-guard-hide-a-system-app-by-overlaying-nothing) keeps the Motorola updater from running, so the device stays on its tested build. Keeping that build means keeping its known issues too — that's the deliberate trade for a stable, prepared development baseline. The block is reversible whenever you choose to plan an update.

## Undoing the system modules

To bring back the carrier apps, the extra hidden apps, or the updater, disable that module and reboot. Use only the line for the module you actually want to undo:

```powershell
& $adb shell su -c 'touch /data/adb/modules/wifi_carrier_debloat/disable'   # 22 Verizon/TracFone packages
& $adb shell su -c 'touch /data/adb/modules/wifi_extra_debloat/disable'     # 19 partner, telemetry, Moto extras
& $adb shell su -c 'touch /data/adb/modules/wifi_ota_guard/disable'         # Motorola updater
& $adb reboot
# if undoing the carrier module, also re-enable the device-lock controller:
& $adb shell su -c 'pm default-state --user 0 com.android.devicelockcontroller'
```

The same toggles are in the Magisk app under **Modules**. Nothing was deleted from the firmware; disabling the overlay is all it takes. To bring back one app without disabling a whole module, remove it from the module's manifest in `device/modules/manifests/`, rebuild the ZIP with `.\dev\Build-Device.ps1 -Promote`, and reinstall it.

## Recovery

If a prepared image stops the device booting and **Fastboot is still reachable**, restore your own backup to the exact slot:

```powershell
# Root image won't boot — restore original init_boot:
& $fb flash init_boot_a "$Backup\init_boot_a.img"

# Modified LK misbehaving — restore original LK:
& $fb flash lk_a "$Backup\lk_a.img"
```

!!! danger "If Fastboot won't start"
    These commands need Fastboot. If a bad LK prevents Fastboot from starting, there is **no vendor-independent recovery proven for this model**. This is the risk accepted in [Stage 6](walkthrough.md#stage-6-flash-lk-and-unlock). Don't assume the other slot, a MediaTek COM-port tool, or a random download agent will save it.

## When you report a problem

If you share results (an issue, a forum post), include the model, build, security patch, kernel, the stage, and the exact error text. **Redact** your serial, IMEI, account names, network identifiers, and unlock keys — and never attach your backup images or raw logs. The [git safety net](../reference/git-workflow.md) keeps those out of commits, but a manual paste is on you.
