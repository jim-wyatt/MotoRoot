"""aosp-academy deploy: put the newest image on the phone and check it, in one run.

1. fetch: the newest verified image from the build node (--no-fetch: the one already here)
2. stock: if the phone runs a DSU image, disable it and reboot to stock (DSU installs only from there)
3. discard; stage the Wi-Fi network (work/wifi.json) and the WireGuard tunnel (work/wireguard/
   wg0.conf, wg0.env) in /metadata for the new image's first boot, when present (all private,
   git-ignored); install (a --userdata-gib data partition); boot (persistent unless --single-boot)
4. the image's first boot joins that Wi-Fi and brings the tunnel up from the staged files and
   deletes them; if either didn't take, the deploy pushes it directly instead
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
WG_LOCAL = WORK / "wireguard"
WG_DIR = "/data/local/aospacademy-wg"
STAGE = "/metadata/aospacademy"


def _staged_files() -> dict[str, str]:
    files = {}
    if WIFI.exists():
        w = json.loads(WIFI.read_text(encoding="utf-8"))
        files["wifi.env"] = f"SSID={w['ssid']}\nSECURITY={w['security']}\nPASSPHRASE={w['passphrase']}\n"
    if (WG_LOCAL / "wg0.conf").exists() and (WG_LOCAL / "wg0.env").exists():
        for name in ("wg0.conf", "wg0.env"):
            files[name] = (WG_LOCAL / name).read_text(encoding="utf-8")
    return files


def _stage() -> bool:
    """On the stock system, leave the new image's Wi-Fi network and tunnel config in /metadata.

    The install wipes the image's data, so its first boot has no network; /metadata is shared by
    stock and the image and a DSU install leaves it alone. Root-only (700/600); the image's
    first-boot service uses the files and deletes them at once. Secrets pass through a local
    temporary file in git-ignored work/ and /data/local/tmp, both removed straight away.
    """
    files = _staged_files()
    if not files:
        return False
    step("Staging Wi-Fi and the tunnel for the new image's first boot")
    adb.root(f"rm -rf {STAGE}; umask 077; mkdir -p {STAGE}")
    tmp = WORK / ".stage"
    tmp.mkdir(exist_ok=True)
    try:
        for name, text in files.items():
            local, remote = tmp / name, f"/data/local/tmp/.aa-{name}"
            local.write_bytes(text.encode("utf-8"))
            try:
                adb.adb("push", str(local), remote)
                adb.root(f"umask 077; mv {remote} {STAGE}/{name} && chown root:root {STAGE}/{name} && chmod 600 {STAGE}/{name}")
            finally:
                local.unlink(missing_ok=True)
                adb.sh(f"rm -f {remote}")
    finally:
        tmp.rmdir()
    staged = adb.root(f"ls {STAGE}").split()
    say(f"  staged: {', '.join(sorted(staged))}")
    return set(staged) == set(files)


def _wifi_validated(seconds: int) -> bool:
    t = 0
    while not adb.sh('dumpsys connectivity | grep -E "^ *NetworkAgentInfo.*WIFI.*VALIDATED"'):
        if t >= seconds:
            return False
        time.sleep(3)
        t += 3
    return True


def _start_tunnel() -> None:
    """Push the tunnel config (its private key goes to the phone over USB only) and start wg0."""
    step("Starting the WireGuard tunnel")
    adb.root(f"umask 077; mkdir -p {WG_DIR}")
    for name in ("wg0.conf", "wg0.env"):
        tmp = f"/data/local/tmp/.{name}"
        adb.adb("push", str(WG_LOCAL / name), tmp)
        adb.root(f"umask 077; mv {tmp} {WG_DIR}/{name} && chown root:root {WG_DIR}/{name} && chmod 600 {WG_DIR}/{name}")
    adb.root(f"rm -f {WG_DIR}/status; start aospacademy_wireguard")
    t, status = 0, ""
    while t < 30 and not status:
        time.sleep(2)
        t += 2
        status = adb.root(f"cat {WG_DIR}/status 2>/dev/null")
    say(f"  {status or 'no result after 30 s'}")


def tunnel() -> str:
    """One line for the report: the tunnel's state and the age of the last handshake."""
    status = adb.root(f"cat {WG_DIR}/status 2>/dev/null")
    if not status:
        return "none (no work/wireguard config)"
    wg = "/product/bin/wg" if adb.sh("ls /product/bin/wg 2>/dev/null") else f"{WG_DIR}/wg"
    hs = adb.root(f"{wg} show wg0 latest-handshakes 2>/dev/null").split()
    if status.startswith("up") and len(hs) >= 2 and hs[1].isdigit() and int(hs[1]) > 0:
        age = int(adb.sh("date +%s") or 0) - int(hs[1])
        return f"{status}, handshake {age}s ago"
    return f"{status}, no handshake yet"


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
    while w < 60 and not adb.root(f"cat {IMAGE_STATE}/charge-limit 2>/dev/null"):
        time.sleep(5)
        w += 5
    return status, log


BATTERY_STATUS = {"1": "unknown", "2": "charging", "3": "discharging", "4": "not charging", "5": "full"}
BATTERY_HEALTH = {"1": "unknown", "2": "good", "3": "overheat", "4": "dead", "5": "over voltage", "6": "failure", "7": "cold"}


def battery(dump: str) -> str:
    """One line from dumpsys battery: level, status, health, temperature and the power source."""
    v = dict(re.findall(r"^\s*([A-Za-z ]+): (.+)$", dump, re.M))
    temp = f"{int(v['temperature']) / 10:.1f} C" if v.get("temperature", "").lstrip("-").isdigit() else "?"
    source = next((s for s in ("AC", "USB", "Wireless", "Dock") if v.get(f"{s} powered") == "true"), "none")
    return (f"{v.get('level', '?')}%, {BATTERY_STATUS.get(v.get('status', ''), v.get('status', '?'))}, "
            f"health {BATTERY_HEALTH.get(v.get('health', ''), v.get('health', '?'))}, {temp}, power {source}")


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
    cl = adb.root(f"cat {IMAGE_STATE}/charge-limit 2>/dev/null")
    rows = {
        "Fingerprint": adb.prop("ro.build.fingerprint"),
        "Home": sh("cmd role get-role-holders android.app.role.HOME"),
        "FirstBoot": f"{status}; {sum(1 for l in log if l.startswith('icon colour '))} icons set",
        "Bluetooth": f"{'on' if sh('settings get global bluetooth_on') == '1' else 'off'}, "
                     f"scanning {'on' if sh('settings get global ble_scan_always_enabled') == '1' else 'off'}",
        "DevOptions": f"shown={sh('settings get global development_settings_enabled')} stay_awake={sh('settings get global stay_on_while_plugged_in')} "
                      f"brightness={sh('settings get system screen_brightness')} (want 1, 15, 64)",
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
        "Battery": battery(sh("dumpsys battery")),
        "Tunnel": tunnel(),
        "AdbTcp": f"listening on {port}" if (port := adb.prop("persist.adb.tcp.port") or adb.prop("service.adb.tcp.port")) not in ("", "0", "-1")
                  else "USB only",
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
    staged = _stage()
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
    tunnel_wanted = (WG_LOCAL / "wg0.conf").exists() and (WG_LOCAL / "wg0.env").exists()
    if staged:
        # The first-boot service joins the staged Wi-Fi and brings the tunnel up; check both took.
        status, log = _first_boot()
        if adb.root(f"ls -d {STAGE} 2>/dev/null"):
            warn(f"{STAGE} is still on the phone; removing it.")
            adb.root(f"rm -rf {STAGE}")
        if WIFI.exists():
            if _wifi_validated(60):
                say("  Wi-Fi from the staged network: validated")
            else:
                warn("The staged Wi-Fi network did not validate; joining it directly.")
                _join_wifi()
        if tunnel_wanted and not adb.root(f"cat {WG_DIR}/status 2>/dev/null").startswith("up"):
            warn("The staged tunnel did not come up; pushing it directly.")
            _start_tunnel()
    else:
        if WIFI.exists():
            _join_wifi()
        if tunnel_wanted:
            _start_tunnel()
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
