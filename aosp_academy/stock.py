"""aosp-academy stock: the stock-system preparation's artifacts.

  build          rebuild the two helper DEX files and the Magisk module ZIPs into work/build and
                 compare them with the committed copies in stock/ (--promote copies changed ones over)
  magisk-image   make a Magisk-patched init_boot image FILE from your own init_boot_a backup
                 (walkthrough stage 5; stage 7 writes it; this never flashes anything)

Helpers: javac --release 8, then D8 from the pinned R8. Compared byte for byte; a mismatch
usually means another javac build changed the debug line tables, not the bytecode. Modules:
stock/modules/build_modules.py, deterministic (fixed timestamps), compared by hash.
"""
from __future__ import annotations

import shutil
import sys
import zipfile
from pathlib import Path

from . import adb, tools
from .core import EXE, ROOT, WORK, Failure, file_hash, pins, run, say

STOCK = ROOT / "stock"
OUT = WORK / "build" / "stock"


def build(promote: bool = False, quiet: bool = False) -> list[tuple[str, bool, Path, Path]]:
    jh = tools.java_home()
    r8 = tools.jar("r8-")
    if not jh:
        raise Failure("No JDK found (JAVA_HOME). Run: aosp-academy setup")
    if not r8.exists():
        raise Failure("The R8 jar is missing. Run: aosp-academy setup")
    shutil.rmtree(OUT, ignore_errors=True)
    OUT.mkdir(parents=True)
    results = []
    for src in sorted((STOCK / "helpers").glob("*.java")):
        classes, dex = OUT / "classes" / src.stem, OUT / "dex" / src.stem
        classes.mkdir(parents=True)
        dex.mkdir(parents=True)
        run([jh / "bin" / f"javac{EXE}", "--release", "8", "-nowarn", "-Xlint:-options", "-d", classes, src], capture=True)
        run([jh / "bin" / f"java{EXE}", "-cp", r8, "com.android.tools.r8.D8", "--min-api", "26", "--output", dex,
             *sorted(classes.glob("*.class"))], capture=True)
        built = OUT / f"{src.stem}.dex"
        (dex / "classes.dex").replace(built)
        target = STOCK / "helpers" / built.name
        results.append((f"stock/helpers/{built.name}", target.exists() and file_hash(built) == file_hash(target), built, target))
    mods = OUT / "modules"
    run([sys.executable, "-I", STOCK / "modules" / "build_modules.py", "--out", mods], capture=True)
    for z in sorted(mods.glob("*.zip")):
        target = STOCK / "modules" / z.name
        results.append((f"stock/modules/{z.name}", target.exists() and file_hash(z) == file_hash(target), z, target))
    if not quiet:
        for name, same, _, _ in results:
            say(f"  {'identical' if same else 'DIFFERS  '}  {name}", "green" if same else "yellow")
    if promote:
        changed = [r for r in results if not r[1]]
        for name, _, built, target in changed:
            shutil.copy2(built, target)
            say(f"promoted {name}")
        say("Review git diff and commit the source and the artifact together." if changed else "Nothing to promote: every artifact already matches.")
    return results


# ---------------------------------------------------------------- Magisk image
MAGISK_APK = "Magisk-v31.1.apk"
SKU, SLOT = "XT2617V", "_a"
STOCK_FINGERPRINT = "motorola/vegas_og_sys/vegas26:16/W1WEOS36.48-22-3-3-4-2/36210f-81d7a:user/release-keys"
INIT_BOOT_SIZE = 8 << 20
DEVICE_STAGE = "/data/local/tmp/magisk-patch-files"
# Magisk's own patch script with the settings used on both tested units: keep verity and forced
# encryption, leave the vbmeta flag alone, patch a normal (non-recovery) boot image.
PATCH_ENV = "KEEPVERITY=true KEEPFORCEENCRYPT=true PATCHVBMETAFLAG=false RECOVERYMODE=false BOOTMODE=true"


def magisk_image(stock_image: str) -> Path:
    """Run Magisk 31.1's boot_patch.sh on the phone (temporary root) on your own init_boot_a backup.

    Writes only work/magisk-patched-init_boot.img: never flashes, never changes a slot, never
    reboots. Every check runs before the phone is touched. Derived from parsimo2010's guide (MIT).
    """
    img = Path(stock_image).resolve()
    apk = WORK / MAGISK_APK
    out = WORK / "magisk-patched-init_boot.img"
    stage = WORK / "magisk-patch-files"
    if out.exists():
        raise Failure(f"Output exists: {out}. Keep it or move it aside; this never overwrites it.")
    if stage.exists():
        raise Failure(f"Staging directory exists: {stage}. Review it and remove it before re-running.")
    if not img.exists() or img.stat().st_size != INIT_BOOT_SIZE:
        raise Failure(f"Expected an 8 MiB init_boot image: {img}")
    pin = next(a["sha256"] for a in pins()["inputs"]["apks"] if a["name"] == MAGISK_APK)
    if not apk.exists() or file_hash(apk) != pin:
        raise Failure(f"{MAGISK_APK} is not the pinned 31.1 release. Stop and investigate.")
    rows = adb.devices()
    if sum(1 for _, s in rows if s == "device") != 1 or any(s in ("unauthorized", "offline", "recovery", "sideload") for _, s in rows):
        raise Failure("Connect exactly one authorized Android device and nothing else.")
    sku, fp, slot = adb.prop("ro.boot.hardware.sku"), adb.prop("ro.build.fingerprint"), adb.prop("ro.boot.slot_suffix")
    if (sku, fp, slot) != (SKU, STOCK_FINGERPRINT, SLOT):
        raise Failure(f"Model, firmware or slot differs from the tested configuration (sku={sku} slot={slot} fingerprint={fp}).")
    # Magisk's su form on purpose: this runs on the stock system only.
    if "uid=0(root)" not in adb.sh("su -c id"):
        raise Failure("Temporary root with Shell granted is required (walkthrough, stage 2).")
    if not adb.sh("su -c 'sha256sum /dev/block/by-name/init_boot_a'").startswith(file_hash(img) + " "):
        raise Failure("The stock image you gave does not match the current init_boot_a partition on this phone.")
    stage.mkdir()
    with zipfile.ZipFile(apk) as z:
        for e in z.namelist():
            if e in ("assets/boot_patch.sh", "assets/util_functions.sh") or (e.startswith("lib/arm64-v8a/") and e.endswith(".so")):
                (stage / Path(e).name).write_bytes(z.read(e))
    # The APK ships the native tools as lib<name>.so; boot_patch.sh expects them by bare name.
    for name in ("magisk", "magiskboot", "magiskinit", "init-ld", "busybox", "magiskpolicy"):
        shutil.copyfile(stage / f"lib{name}.so", stage / name)
    adb.adb("push", stage, "/data/local/tmp/")
    adb.adb("push", img, f"{DEVICE_STAGE}/stock-init_boot.img")
    say(adb.adb("shell", "su", "-c", f"{PATCH_ENV} sh {DEVICE_STAGE}/boot_patch.sh {DEVICE_STAGE}/stock-init_boot.img"))
    adb.adb("pull", f"{DEVICE_STAGE}/new-boot.img", out)
    h = file_hash(out)
    if not adb.sh(f"su -c 'sha256sum {DEVICE_STAGE}/new-boot.img'").startswith(h + " "):
        raise Failure("Output transfer hash mismatch. Do not flash.")
    if out.stat().st_size != INIT_BOOT_SIZE:
        raise Failure("Unexpected output size. Do not flash.")
    say(f"Prepared file: {out}\nSHA256: {h}\nNo firmware partition was written. No reboot was performed.", "green")
    return out
