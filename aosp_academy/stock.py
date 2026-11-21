"""aosp-academy stock: the stock-system preparation's artifacts.

  build          rebuild the two helper DEX files and the Magisk module ZIPs into work/build and
                 compare them with the committed copies in stock/ (--promote copies changed ones over)
  magisk-image   make a Magisk-patched init_boot image FILE from your own init_boot_a backup
                 (walkthrough stage 5; stage 7 writes it; this never flashes anything)
  tunnel         the WireGuard tunnel on the stock system: wg (built here from the pinned
                 wireguard-tools with the NDK) and work/wireguard's config into
                 /data/adb/aospacademy-wg, and the dev_wireguard module that brings it up at boot

Helpers: javac --release 8, then D8 from the pinned R8. Compared byte for byte; a mismatch
usually means another javac build changed the debug line tables, not the bytecode. Modules:
stock/modules/build_modules.py, deterministic (fixed timestamps), compared by hash.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import sys
import time
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


WG_BUILD = OUT.parent / "wg"
STOCK_WG = "/data/adb/aospacademy-wg"


def build_wg() -> Path:
    """wg for arm64 Android from the pinned wireguard-tools, with the pinned NDK (static, so it
    runs on the stock system and the image alike). Rebuilt when the pinned commit changes."""
    from .image import wireguard_tools
    w = pins()["deviceTools"]["wireguardTools"]
    out, stamp = WG_BUILD / "wg", WG_BUILD / ".commit"
    if out.exists() and stamp.exists() and stamp.read_text().strip() == w["commit"]:
        return out
    src = WORK / "device-tools"
    wireguard_tools(src)
    ndk = tools.pinned_dir("ndk", quiet=True)
    if not ndk:
        raise Failure("The pinned NDK is missing. Run: aosp-academy setup")
    host = "windows-x86_64" if EXE else ("darwin-x86_64" if sys.platform == "darwin" else "linux-x86_64")
    clang = ndk / "toolchains" / "llvm" / "prebuilt" / host / "bin" / f"clang{EXE}"
    s = src / "wireguard-tools" / "src"
    files = ["wg.c", "config.c", "curve25519.c", "encoding.c", "genkey.c", "ipc.c", "pubkey.c",
             "set.c", "setconf.c", "show.c", "showconf.c", "terminal.c"]
    WG_BUILD.mkdir(parents=True, exist_ok=True)
    run([clang, "--target=aarch64-linux-android33", "-O2", "-std=gnu11", "-D_GNU_SOURCE",
         '-DRUNSTATEDIR="/data/local/tmp"', f"-I{s / 'uapi' / 'linux'}", f"-I{s}", "-static", "-s",
         "-o", out, *[s / f for f in files]], capture=True)
    stamp.write_text(w["commit"] + "\n")
    return out


STOCK_ADB_KEYS = "/data/misc/adb/adb_keys"


def missing_keys(wanted: list[str], have: str) -> list[str]:
    """The adbkey.pub lines in wanted whose key isn't in have (an adb_keys file's text), in order,
    each once. Keys are compared by their base64 blob, not the comment after it."""
    present = {line.split()[0] for line in have.splitlines() if line.split()}
    out, seen = [], set()
    for line in wanted:
        parts = line.split()
        if parts and parts[0] not in present and parts[0] not in seen:
            seen.add(parts[0])
            out.append(line.strip())
    return out


def trust_keys(quiet: bool = False) -> int:
    """Make the stock system trust the PCs the image trusts, and this PC.

    The image builds work/adb_keys in, so every PC listed there gets adb on it with no tap. The
    stock system keeps its own list (/data/misc/adb/adb_keys, filled by tapping Allow), so a build
    node that only ever reached the phone over the network was refused on stock until its key was
    added by hand. This appends the missing keys (work/adb_keys and this PC's ~/.android/adbkey.pub),
    keeps the ones already there, and sets the owner, mode and label adbd expects. adbd reads the
    file at each new connection, so nothing restarts. Needs root on stock (Magisk). Returns the
    number of keys added."""
    wanted = []
    listed = WORK / "adb_keys"
    if listed.exists():
        wanted += listed.read_text(encoding="utf-8").splitlines()
    own = Path.home() / ".android" / "adbkey.pub"
    if own.exists():
        wanted.append(own.read_text(encoding="utf-8").strip())
    add = missing_keys(wanted, adb.root(f"cat {STOCK_ADB_KEYS} 2>/dev/null"))
    if not add:
        if not quiet:
            say("  stock adb keys: all trusted already", "green")
        return 0
    tmp_local = WORK / "build" / "adb_keys.add"
    tmp_local.parent.mkdir(parents=True, exist_ok=True)
    tmp_local.write_text("\n".join(add) + "\n", encoding="utf-8", newline="\n")
    tmp = "/data/local/tmp/.aa-adb_keys.add"
    try:
        adb.adb("push", str(tmp_local), tmp)
        adb.root(f"touch {STOCK_ADB_KEYS} && cat {tmp} >> {STOCK_ADB_KEYS} && chown system:shell {STOCK_ADB_KEYS} "
                 f"&& chmod 640 {STOCK_ADB_KEYS} && restorecon {STOCK_ADB_KEYS}")
    finally:
        adb.sh(f"rm -f {tmp}")
        tmp_local.unlink(missing_ok=True)
    left = missing_keys(add, adb.root(f"cat {STOCK_ADB_KEYS} 2>/dev/null"))
    if left:
        raise Failure(f"{len(left)} key(s) did not reach {STOCK_ADB_KEYS} on the stock system.")
    say(f"  stock adb keys: {len(add)} added ({', '.join(l.split()[1] if len(l.split()) > 1 else 'no comment' for l in add)})", "green")
    return len(add)


def tunnel(quiet: bool = False) -> bool:
    """Set up the tunnel on the stock system (Magisk root). Idempotent: pushes only what changed.
    Returns True when wg0 is up. Needs work/wireguard/wg0.conf and wg0.env (private)."""
    conf, env = WORK / "wireguard" / "wg0.conf", WORK / "wireguard" / "wg0.env"
    if not (conf.exists() and env.exists()):
        if not quiet:
            say("No work/wireguard/wg0.conf and wg0.env: no tunnel to set up.", "yellow")
        return False
    adb.assert_one_device()
    if adb.gsi_running():
        raise Failure("The phone runs the image; stock tunnel is for the stock system (aosp-academy gsi stock).")
    if "uid=0(" not in adb.root("id"):
        raise Failure("No root on the stock system (Magisk).")
    changed = False
    adb.root(f"umask 077; mkdir -p {STOCK_WG}")
    for local, name, mode in ((build_wg(), "wg", "700"), (conf, "wg0.conf", "600"), (env, "wg0.env", "600")):
        if adb.root(f"sha256sum {STOCK_WG}/{name} 2>/dev/null").split()[:1] == [file_hash(local)]:
            continue
        tmp = f"/data/local/tmp/.aa-{name}"
        try:
            adb.adb("push", str(local), tmp)
            adb.root(f"umask 077; mv {tmp} {STOCK_WG}/{name} && chown root:root {STOCK_WG}/{name} && chmod {mode} {STOCK_WG}/{name}")
        finally:
            adb.sh(f"rm -f {tmp}")
        changed = True
    zp = STOCK / "modules" / "dev-wireguard.zip"
    with zipfile.ZipFile(zp) as z:
        want_prop = z.read("module.prop").decode().strip()
        want_script = hashlib.sha256(z.read("service.sh")).hexdigest()

    def live() -> str:
        # Magisk installs into modules_update and moves it into modules at the next boot, so until
        # then the modules_update copy is the current one; modules/ still holds the previous version.
        upd = "/data/adb/modules_update/dev_wireguard"
        return upd if adb.root(f"ls -d {upd} 2>/dev/null") else "/data/adb/modules/dev_wireguard"

    d = live()
    # The script's hash as well as module.prop: a module once carried version 1.2 with the 1.1
    # script (built before the script changed), and comparing module.prop alone kept it.
    have_prop = adb.root(f"cat {d}/module.prop 2>/dev/null").strip()
    have_script = adb.root(f"sha256sum {d}/service.sh 2>/dev/null").split()[:1]
    if have_prop != want_prop or have_script != [want_script]:
        adb.adb("push", str(zp), "/data/local/tmp/dev-wireguard.zip")
        out = adb.root("magisk --install-module /data/local/tmp/dev-wireguard.zip; rm -f /data/local/tmp/dev-wireguard.zip")
        d = live()
        if adb.root(f"sha256sum {d}/service.sh 2>/dev/null").split()[:1] != [want_script]:
            raise Failure(f"Magisk didn't install dev_wireguard: {out[-300:]}")
        changed = True
    up = adb.root(f"cat {STOCK_WG}/status 2>/dev/null").startswith("up")
    if changed or not up:
        # Bring it up now with the module's current script; at the next boot Magisk runs it itself.
        # The script deletes and recreates wg0, which cuts an adb connection that runs over the
        # tunnel (a deploy from a build node did exactly that, and stopped at "device offline").
        # So it runs detached, and adb reconnects before reading the result.
        adb.root(f"rm -f {STOCK_WG}/status; nohup sh {d}/service.sh >/dev/null 2>&1 &")
        serial = os.environ.get("ANDROID_SERIAL", "")
        for _ in range(30):
            time.sleep(2)
            if adb.is_tcp(serial):
                adb.adb("connect", serial, check=False, timeout=15)
            # adb returns its own errors as output ("device offline"), so only a real status counts.
            got = adb.adb("shell", f"su -c 'cat {STOCK_WG}/status 2>/dev/null'", check=False, timeout=20)
            if got.startswith(("up", "failed")):
                break
        adb.wait_authorized()
    status = adb.root(f"cat {STOCK_WG}/status 2>/dev/null")
    if not quiet or not status.startswith("up"):
        say(f"  stock tunnel: {status or 'no status'}", "green" if status.startswith("up") else "yellow")
    return status.startswith("up")


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
