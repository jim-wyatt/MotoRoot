"""aosp-academy gsi: run a system image on the phone through DSU (Dynamic System Updates).

DSU boots a Generic System Image from a file in /data, on top of the phone's own vendor partition.
Nothing is flashed: the slots and boot images are untouched.

  download   Google's pinned GSI (toolchain.json deviceTools.gsi), after you accept its terms
  install    push the zip (or your own system.img, wrapped in one) to Android's DSU installer
  boot       enable the installed image and reboot into it; persistent unless --single-boot
  stock      from a running image: disable it (it stays installed) and reboot to stock
  status     the DSU state and what is running
  discard    remove the installed image and its userdata (from the stock system)
"""
from __future__ import annotations

import re
import time
import urllib.request
import zipfile
from pathlib import Path

from . import adb
from .core import WORK, Failure, file_hash, pins, say

DIR = WORK / "device-tools" / "gsi"


def _spec(image: str | None) -> tuple[dict, Path]:
    """The pinned GSI, or your own image wrapped in a zip next to it (no pin applies)."""
    if not image:
        spec = pins()["deviceTools"]["gsi"]
        return spec, DIR / spec["name"]
    img = Path(image).resolve()
    if not img.exists():
        raise Failure(f"No image at {img}.")
    if img.suffix == ".zip":
        return {"name": img.name, "own": True}, img
    zp = img.with_name("own-gsi.zip")
    zp.unlink(missing_ok=True)
    # The DSU installer wants a zip with system.img (sparse or raw) inside, like Google's;
    # vbmeta.img and build.prop beside the image are packed too.
    with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED, compresslevel=1) as z:
        z.write(img, "system.img")
        for extra in ("vbmeta.img", "build.prop"):
            p = img.with_name(extra)
            if p.exists():
                z.write(p, extra)
    return {"name": zp.name, "own": True, "carrier": True}, zp


def download(args) -> int:
    spec = pins()["deviceTools"]["gsi"]
    zp = DIR / spec["name"]
    if zp.exists():
        if file_hash(zp) == spec["sha256"]:
            say(f"Already present and verified: {zp}", "green")
            return 0
        raise Failure(f"{zp} exists but does not match the pinned SHA-256. Delete it and retry.")
    say(f"Google publishes this image under its GSI terms: {spec['terms']}")
    if not args.accept_google_gsi_terms:
        raise Failure("Read the terms, then re-run with --accept-google-gsi-terms to download.")
    DIR.mkdir(parents=True, exist_ok=True)
    partial = zp.with_name(zp.name + ".partial")
    say(f"Downloading {spec['name']} ...")
    with urllib.request.urlopen(urllib.request.Request(spec["url"], headers={"User-Agent": "aosp-academy"}), timeout=60) as r, open(partial, "wb") as f:
        while block := r.read(1 << 22):
            f.write(block)
    if file_hash(partial) != spec["sha256"]:
        partial.unlink()
        raise Failure("SHA-256 mismatch after download. Not keeping the file.")
    partial.replace(zp)
    say(f"Verified: {zp}", "green")
    return 0


def install(image: str | None, userdata_gib: int) -> None:
    adb.require_root_device()
    spec, zp = _spec(image)
    if not spec.get("own") and not (zp.exists() and file_hash(zp) == spec["sha256"]):
        raise Failure(f"Run 'aosp-academy gsi download' first (missing or unverified: {zp}).")
    if adb.gsi_running():
        raise Failure("A DSU image is running right now. Run 'aosp-academy gsi stock' first.")
    st = adb.gsi_status()
    if st != "normal":
        raise Failure(f"DSU state is '{st}', not 'normal'. Use 'gsi status' / 'gsi discard' first.")
    if adb.prop("ro.boot.dynamic_partitions") != "true":
        raise Failure("ro.boot.dynamic_partitions is not true; DSU needs dynamic partitions.")
    remote = f"/storage/emulated/0/Download/{spec['name']}"
    say(f"Pushing {spec['name']} to the phone (this takes a minute) ...")
    try:
        adb.adb("push", zp, remote)
    finally:
        # The zip around your own image is only a carrier for the push: drop it at once, so the
        # device node doesn't keep a second copy of the image.
        if spec.get("carrier"):
            zp.unlink(missing_ok=True)
    # Android's own DSU installer reads system.img out of the zip and creates the images in /data.
    # It asks for the screen-lock credential first only when the phone has a secure lock screen.
    # gsi_tool lists partitions as "installed" as soon as they're created, while the installer is
    # still writing them, so the installer's own status in logcat is what to wait for:
    # NOT_STARTED -> IN_PROGRESS -> READY, or an error cause. logcat -T reads from the phone's clock
    # at the start, so older installs' lines don't count and the log buffers aren't cleared.
    since = adb.sh("date '+%m-%d %H:%M:%S.000'")
    adb.sh("am start-activity -n com.android.dynsystem/com.android.dynsystem.VerificationActivity "
           f"-a android.os.image.action.START_INSTALL -d file://{remote} --el KEY_USERDATA_SIZE {userdata_gib << 30}")
    say("Installing (a phone with a secure lock screen asks for the PIN first). Waiting up to 30 min ...", "cyan")
    t, state, shown = 0, "NOT_STARTED", ""
    pat = re.compile(r"DynamicSystemInstallationService: status: (\w+), cause: (\w+)")
    while t < 1800:
        time.sleep(10)
        t += 10
        hits = [l for l in adb.adb("logcat", "-d", "-T", since, check=False).splitlines() if pat.search(l)]
        if not hits:
            continue
        m = pat.search(hits[-1])
        state, cause = m[1], m[2]
        progress = re.search(r"total_progress: (\d+%)", hits[-1])
        line = f"{state} {progress[1] if progress else ''} {cause}"
        if line != shown:
            say(f"  {t}s: {line}")
            shown = line
        if state == "READY" or cause not in ("CAUSE_NOT_SPECIFIED", "CAUSE_INSTALL_COMPLETED"):
            break
    adb.sh(f"rm -f {remote}")
    st = adb.gsi_status()
    if state != "READY":
        raise Failure(f"Installation did not complete (installer state '{state}', gsi_tool status '{st}'). "
                      "Check the notification on the phone; 'aosp-academy gsi discard' cleans up.")
    say(f"Installed (gsi_tool: {' '.join(st.split())}).", "green")


def boot(single_boot: bool) -> None:
    adb.require_root_device()
    st = adb.gsi_status()
    if not re.search("installed|enabled", st):
        raise Failure(f"No installed image (status '{st}'). Run 'aosp-academy gsi install' first.")
    if single_boot:
        say(adb.root("gsi_tool enable --single-boot"))
        say("Rebooting into the image for ONE boot. If it never reaches the home screen, hold Power: the next boot is stock.", "cyan")
    else:
        say(adb.root("gsi_tool enable"))
        say("Rebooting into the image; it stays enabled across reboots until 'aosp-academy gsi stock'.", "cyan")
    adb.reboot()
    t = adb.wait_boot(after_reboot=True)
    time.sleep(5)
    say(f"booted after ~{t}s: image running={adb.gsi_running()} build={adb.prop('ro.build.display.id')}")


def stock() -> None:
    adb.require_root_device()
    if not adb.gsi_running():
        say(f"Already on the phone's own system ({adb.prop('ro.build.display.id')}).")
        return
    # disable keeps the image installed but stops init from booting it; 'gsi boot' enables it again.
    say(adb.root("gsi_tool disable"))
    adb.reboot()
    t = adb.wait_boot(after_reboot=True)
    if adb.gsi_running():
        raise Failure(f"Still in the image after the reboot (status '{adb.gsi_status()}').")
    say(f"Stock system up after ~{t}s ({adb.prop('ro.build.display.id')}); the image is still installed: "
        f"{' '.join(adb.gsi_status().split())}", "green")


def status() -> None:
    adb.require_root_device()
    spec = pins()["deviceTools"]["gsi"]
    zp = DIR / spec["name"]
    say(f"gsi_tool status:  {' '.join(adb.gsi_status().split())}")
    say(f"image running:    {adb.gsi_running()}   (gsi_tool's first line; ro.gsid.image_running is empty on this phone)")
    say(f"build running:    {adb.prop('ro.build.display.id')}")
    say(f"Google GSI here:  {('present, verified' if file_hash(zp) == spec['sha256'] else 'present, HASH MISMATCH') if zp.exists() else 'not downloaded'}")


def discard() -> None:
    adb.require_root_device()
    if adb.gsi_running():
        raise Failure("A DSU image is running. Run 'aosp-academy gsi stock' first, then discard.")
    if adb.gsi_status() == "normal":
        say("Nothing installed.")
        return
    say(adb.root("gsi_tool disable"))
    say(adb.root("gsi_tool wipe"))
    say(f"DSU status: {adb.gsi_status()}", "green")


def main(args) -> int:
    a = args.action
    if a == "download":
        return download(args)
    if a == "install":
        install(args.image, args.userdata_gib)
    elif a == "boot":
        boot(args.single_boot)
    elif a == "stock":
        stock()
    elif a == "discard":
        discard()
    else:
        status()
    return 0
