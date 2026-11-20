"""aosp-academy deploy: put the newest image on the phone and check it, in one run.

1. fetch: the newest verified image from the build node (--no-fetch: the one already here)
2. stock: if the phone runs a DSU image, disable it and reboot to stock (DSU installs only from there)
3. discard, install (a --userdata-gib data partition), boot (persistent unless --single-boot)
4. Wi-Fi: join the network in work/wifi.json (private, git-ignored), when present
5. wait for the image's first-boot service (its status and log files, read as root)
6. report what the image sets, then run 'device test' (--skip-device-test leaves it out)

Step 3 deletes the installed image's data, so it asks first (--yes skips the question). After the
install the local copy of the image is deleted (--keep-image keeps it); its hash stays in
work/device-tools/gsi/own/deployed.sha256.
"""
from __future__ import annotations

import json
import re
import time

from . import adb, fetch, gsi
from .core import PRODUCT, WORK, Failure, file_hash, first_hash, image_state, is_image_product, say, step, warn

WIFI = WORK / "wifi.json"


def _join_wifi() -> None:
    w = json.loads(WIFI.read_text(encoding="utf-8"))
    step(f"Joining Wi-Fi {w['ssid']}")
    adb.root("cmd wifi set-wifi-enabled enabled")
    time.sleep(3)
    # The passphrase goes to the phone over USB only, never into a log here.
    adb.root(f"cmd wifi connect-network {adb.quote(w['ssid'])} {w['security']} {adb.quote(w['passphrase'])}")
    t = 0
    while t < 60 and not adb.sh('dumpsys connectivity | grep -E "^ *NetworkAgentInfo.*WIFI.*VALIDATED"'):
        time.sleep(3)
        t += 3
    if t >= 60:
        warn(f"Wi-Fi {w['ssid']} did not validate within 60 s.")
    else:
        say(f"  connected and validated after ~{t}s")


def _first_boot() -> tuple[str, list[str]]:
    IMAGE_STATE = image_state(adb.prop("ro.product.name"))
    step("Waiting for the first-boot service")
    t = 0
    while t < 300 and not adb.root(f"cat {IMAGE_STATE}/status").startswith("done"):
        time.sleep(5)
        t += 5
    status = adb.root(f"cat {IMAGE_STATE}/status")
    log = [l.split(" ", 2)[2] for l in adb.root(f"cat {IMAGE_STATE}/log").splitlines() if l.count(" ") >= 2]
    if not status.startswith("done"):
        warn(f"The first-boot service had not finished after {t} s (status: '{status}').")
    for l in log:
        if "failed" in l or "did not stick" in l:
            warn(f"first boot: {l}")
    # The charge-limit service writes its result 30 s after boot completes; wait up to 60 s for it.
    w = 0
    while w < 60 and not adb.root(f"cat {IMAGE_STATE}/charge-limit"):
        time.sleep(5)
        w += 5
    return status, log


def report(status: str = "", log: list[str] | None = None) -> None:
    """What the image sets, read back from the phone."""
    log = log or []
    sh = adb.sh
    IMAGE_STATE = image_state(adb.prop("ro.product.name"))
    crashes = sum(1 for l in adb.adb("logcat", "-d", "-b", "crash", check=False).splitlines() if " F libc" in l or "FATAL EXCEPTION" in l)
    scales = "/".join(sh(f"settings get global {k}") for k in ("window_animation_scale", "transition_animation_scale", "animator_duration_scale"))
    aosp_icons = sh("pm query-activities -a android.intent.action.MAIN -c android.intent.category.LAUNCHER --components"
                    " | grep -E 'com.android.documentsui|com.android.inputmethod.latin'")
    validated = bool(sh('dumpsys connectivity | grep -E "^ *NetworkAgentInfo.*VALIDATED"'))
    probes = ", ".join(sorted(set(re.findall(r"PROBE_HTTPS? https?://([^/\s]+)", sh('dumpsys network_stack | grep -E "PROBE_HTTPS? "')))))
    ntp = re.search(r"mLastSuccessfulNtpServerUri=(\S+)", sh("dumpsys network_time_update_service"))
    cl = adb.root(f"cat {IMAGE_STATE}/charge-limit")
    rows = {
        "Fingerprint": adb.prop("ro.build.fingerprint"),
        "Home": sh("cmd role get-role-holders android.app.role.HOME"),
        "FirstBoot": f"{status}; {sum(1 for l in log if l.startswith('icon colour '))} icons set",
        "Animations": f"{scales} (want 0/0/0)",
        "LogBuffer": sh("logcat -g -b main"),
        "TimeZone": adb.prop("persist.sys.timezone"),
        "AospIcons": f"still in the launcher: {aosp_icons}" if aosp_icons else "hidden (Files, keyboard)",
        # Only the named files: never bulk-read /sys/module/*/parameters on this phone (it panics the kernel).
        "ChargeLimit": (f"{cl}; now blocking={adb.root('cat /sys/module/qpnp_adaptive_charge/parameters/blocking')}, "
                        f"battery {sh('cat /sys/class/power_supply/battery/capacity')}%") if cl else "not applied yet (no charge-limit file)",
        "Network": (f"validated; probes to {probes or '?'}; NTP {ntp[1] if ntp else 'not synced yet'}") if validated
                   else "no validated network (no work/wifi.json, or not joined)",
        # As root: the shell user may not list /product/etc/security.
        "AdbKeys": (f"built in ({n} keys)" if (n := adb.root("grep -c . /product/etc/security/adb_keys 2>/dev/null")).isdigit() and n != "0"
                    else "none (each PC needs the Allow tap)"),
        "CrashLog": f"{crashes} entries: check adb logcat -b crash" if crashes else "empty",
        "DataFree": (sh("df -h /data | tail -1").split() + ["?"] * 4)[3],
    }
    width = max(map(len, rows))
    for k, v in rows.items():
        say(f"{k.ljust(width)} : {v}")


def deploy(args) -> int:
    adb.assert_one_device()
    if not args.no_fetch:
        step("Fetching the newest image from the build node")
        fetch.fetch(args)
    img = fetch.IMG
    if not img.exists():
        raise Failure(f"No image at {img}.")
    h = file_hash(img)
    sidecar = fetch.OWN / "system.img.sha256"
    if sidecar.exists() and first_hash(sidecar) != h:
        raise Failure(f"{img} does not match its system.img.sha256. Fetch it again.")
    if not args.yes:
        a = input(f"Replace the installed image and its data with {h[:12]}... ({args.userdata_gib} GB data partition)? [y/N] ")
        if a.strip().lower() not in ("y", "yes"):
            say("Nothing changed.")
            return 1

    if adb.gsi_running():
        step(f"The phone is in a DSU image ({adb.prop('ro.product.name')}): back to the stock system")
        gsi.stock()
    step("Discarding the installed image")
    gsi.discard()
    step("Installing the new image")
    gsi.install(str(img), args.userdata_gib)
    step("Booting it")
    gsi.boot(args.single_boot)
    product = adb.prop("ro.product.name")
    if not is_image_product(product):
        raise Failure(f"The phone did not come up in the {PRODUCT} image (product {product}).")
    if not args.keep_image:
        # The image is on the phone, so this PC drops its copy (--keep-image keeps it for a re-install).
        for f in ("system.img", "system.prev.img", "build.prop", "vbmeta.img", "own-gsi.zip"):
            (fetch.OWN / f).unlink(missing_ok=True)
        if sidecar.exists():
            sidecar.replace(fetch.DEPLOYED)
        say(f"  local image removed (deployed: {h[:12]}..., in {fetch.DEPLOYED})")
    if WIFI.exists():
        _join_wifi()
    status, log = _first_boot()
    step("Result")
    report(status, log)
    if not args.skip_device_test:
        from . import devtest
        step("Development workflows (device test)")
        failed = devtest.run_tests()
        if failed:
            warn(f"device test: {failed} check(s) failed (see the table above).")
            return 1
    return 0
