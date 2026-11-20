"""aosp-academy device: settings, inventory, tracing and Frida on the connected phone."""
from __future__ import annotations

import re
import time
from collections import Counter
from datetime import datetime
from pathlib import Path

from . import adb
from .core import ROOT, WORK, Failure, file_hash, image_state, is_image_product, say, warn

# ---------------------------------------------------------------- settings
DEV_GLOBALS = {
    # Developer options shown in Settings, without the seven taps on the build number.
    "development_settings_enabled": "1",
    # Stay awake: the screen stays on while charging (AC 1 | USB 2 | wireless 4 | dock 8, as the toggle writes).
    "stay_on_while_plugged_in": "15",
    # Animations off: UI tests (Espresso) expect it, and screens settle immediately.
    "window_animation_scale": "0",
    "transition_animation_scale": "0",
    "animator_duration_scale": "0",
    # adb installs are not sent to Play Protect first: fast, never blocked by a prompt.
    "verifier_verify_adb_installs": "0",
    # An authorized PC stays authorized instead of re-confirming after seven idle days.
    "adb_allowed_connection_time": "0",
}
DEV_SYSTEM = {
    # Manual brightness at 64 of 255 (about 25 % backlight): Stay awake keeps the OLED panel on for
    # as long as the phone is on the cable, so not at full brightness. After the screen timeout it
    # still dims to the minimum on its own.
    "screen_brightness_mode": "0",
    "screen_brightness": "64",
}
LOG_SIZE = "16M"


def settings(reset: bool) -> int:
    """The development-target settings (or, with reset, the stock values). Returns how many did not stick.

    The image sets all of these itself at first boot; this is for the stock system, or to put
    them back after an experiment. persist.logd.size needs root; without it the 16 MiB log
    buffers last until the next reboot.
    """
    adb.assert_one_device()
    failed = 0
    for ns, k, v in [("global", k, v) for k, v in DEV_GLOBALS.items()] + [("system", k, v) for k, v in DEV_SYSTEM.items()]:
        if reset:
            adb.sh(f"settings delete {ns} {k}")
            want = "null"
        else:
            adb.sh(f"settings put {ns} {k} {v}")
            want = v
        got = adb.sh(f"settings get {ns} {k}")
        if got == want:
            say(f"  ok    {k} = {got}", "green")
        else:
            warn(f"{k} is '{got}', expected '{want}'")
            failed += 1
    root = adb.has_root()
    if reset:
        # Magisk's resetprop deletes the property and its persistent copy; an image built from
        # source has none, and there an empty value is the reset.
        if root:
            adb.root('if command -v resetprop >/dev/null; then resetprop -p -d persist.logd.size; else setprop persist.logd.size ""; fi')
        adb.sh("logcat -G 256K")
        say("  ok    log buffers back to 256 KiB" + ("" if root else " (no root: persist.logd.size left as it was)"), "green")
        return failed
    if root:
        adb.root(f"setprop persist.logd.size {LOG_SIZE}")
        if (p := adb.prop("persist.logd.size")) != LOG_SIZE:
            warn(f"persist.logd.size is '{p}', expected {LOG_SIZE}")
            failed += 1
    else:
        warn("No root: the 16 MiB log size lasts until the next reboot only.")
    adb.sh(f"logcat -G {LOG_SIZE}")
    g = adb.sh("logcat -g -b main")
    if "ring buffer is 16 MiB" in g:
        say("  ok    log buffers 16 MiB" + (", persistent" if root else ""), "green")
    else:
        warn(f"log buffer: {g}")
        failed += 1
    return failed


# ---------------------------------------------------------------- try
FIRSTBOOT_REPO = ROOT / "image" / "product" / "aospacademy" / "gsi" / "firstboot" / "aospacademy-firstboot.sh"
FIRSTBOOT_TARGET = "/product/bin/aospacademy-firstboot"
TRY_DIR = "/data/local/aospacademy-try"


def try_firstboot(rerun: bool, undo: bool) -> int:
    """Run the repository's first-boot script on the running image, without a build.

    It bind-mounts the script over /product/bin/aospacademy-firstboot as root. Nothing is written
    to a partition and verity is untouched (unlike adb remount, which has to disable it); a reboot
    or --undo puts the built-in script back. --rerun clears the first-boot state and starts the
    service again, as on a fresh install. Only the script can be tried this way: init reads .rc
    files once at boot, and overlays and read-only properties are part of the build.
    """
    adb.assert_one_device()
    product = adb.prop("ro.product.name")
    if not (adb.gsi_running() and is_image_product(product)):
        raise Failure("device try needs the aosp-academy image running (aosp-academy gsi status).")
    if "uid=0(" not in adb.root("id"):
        raise Failure("No root on the phone: the image's su is needed for the bind mount.")
    mounted = lambda: FIRSTBOOT_TARGET in adb.root("cat /proc/1/mounts")  # init's view, not adbd's
    if undo:
        if mounted():
            adb.root(f"umount $(readlink -f {FIRSTBOOT_TARGET})")
        say("The built-in first-boot script is back." if not mounted() else "Could not unmount it; a reboot will.",
            "green" if not mounted() else "yellow")
        return 0 if not mounted() else 1
    tmp = "/data/local/tmp/aospacademy-firstboot.try"
    adb.adb("push", str(FIRSTBOOT_REPO), tmp)
    label = adb.root(f"ls -Z {FIRSTBOOT_TARGET}").split()[0]
    adb.root(f"mkdir -p {TRY_DIR} && mv {tmp} {TRY_DIR}/aospacademy-firstboot && chmod 755 {TRY_DIR}/aospacademy-firstboot"
             f" && chcon {label} {TRY_DIR}/aospacademy-firstboot")
    real = adb.root(f"readlink -f {FIRSTBOOT_TARGET}")  # /system/product/...: mount wants the real path
    if mounted():
        adb.root(f"umount {real}")
    # /data is mounted nosuid, and a bind mount keeps that flag. The kernel refuses an SELinux
    # domain change on exec from a nosuid mount, so init's start of the service (seclabel su) would
    # fail with status 127 while a root shell runs the same file fine. Remount the bind suid.
    adb.root(f"mount -o bind {TRY_DIR}/aospacademy-firstboot {real} && mount -o remount,bind,suid {real}")
    # Compare what init itself would run (/proc/1/root) with the repository's file.
    want = file_hash(FIRSTBOOT_REPO)
    got = adb.root(f"sha256sum /proc/1/root{FIRSTBOOT_TARGET}").split()[0] if mounted() else ""
    if got != want:
        raise Failure(f"The bind mount did not take (init sees {got[:12] or 'nothing'}, the repository has {want[:12]}).")
    say(f"The repository's first-boot script is live at {FIRSTBOOT_TARGET} until a reboot (or: device try --undo).", "green")
    if not rerun:
        say("It runs at the next trigger (a charge-limit change: setprop persist.aospacademy.charge_limit <n>), or now with --rerun.")
        return 0
    state = image_state(product)
    say(f"Re-running first boot: clearing {state} and starting aospacademy_firstboot ...")
    adb.root(f"rm -rf {state} && start aospacademy_firstboot")
    status, t = "", 0
    while t < 120:
        time.sleep(3)
        t += 3
        status = adb.root(f"cat {state}/status 2>/dev/null")
        if status.startswith("done"):
            break
    for line in adb.root(f"cat {state}/log 2>/dev/null").splitlines():
        say(f"  {line}")
    if not status.startswith("done"):
        warn(f"First boot had not finished after {t} s (status: '{status}').")
        return 1
    say(f"First boot: {status}", "green" if status == "done failures=0" else "yellow")
    return 0 if status == "done failures=0" else 1


# ---------------------------------------------------------------- trace
TRACE_CONFIG = """buffers: { size_kb: 65536 fill_policy: RING_BUFFER }
data_sources: {
  config {
    name: "linux.ftrace"
    ftrace_config {
      ftrace_events: "sched/sched_switch"
      ftrace_events: "sched/sched_wakeup"
      ftrace_events: "power/cpu_frequency"
      ftrace_events: "power/cpu_idle"
      atrace_categories: "am"
      atrace_categories: "binder_driver"
      atrace_categories: "gfx"
      atrace_categories: "input"
      atrace_categories: "view"
      atrace_categories: "wm"
      atrace_apps: "*"
    }
  }
}
data_sources: { config { name: "linux.process_stats" process_stats_config { scan_all_processes_on_start: true proc_stats_poll_ms: 1000 } } }
data_sources: { config { name: "android.log" } }
duration_ms: %d
"""


def trace(seconds: int = 10, name: str | None = None, config: str | None = None, quiet: bool = False) -> Path:
    """Record a Perfetto system trace into work/traces/<name>.pftrace. No root needed.

    Open it at https://ui.perfetto.dev (the UI runs in the browser; the trace isn't uploaded).
    """
    if not 1 <= seconds <= 600:
        raise Failure("seconds must be between 1 and 600.")
    name = name or datetime.now().strftime("%Y%m%d-%H%M%S")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
        raise Failure("The name may contain only letters, digits, dot, underscore and dash.")
    adb.assert_one_device()
    out = WORK / "traces"
    out.mkdir(parents=True, exist_ok=True)
    local = out / f"{name}.pftrace"
    if local.exists():
        raise Failure(f"Trace already exists: {local}")
    # SELinux lets perfetto read configs only from /data/misc/perfetto-configs.
    # A staging copy with its own name, so a --config file kept in work/traces is never overwritten or deleted.
    cfg_local = out / f".staging-{name}.pbtxt"
    cfg_local.write_text(Path(config).read_text(encoding="utf-8") if config else TRACE_CONFIG % (seconds * 1000), encoding="ascii", newline="\n")
    cfg_remote, remote = f"/data/misc/perfetto-configs/{name}.pbtxt", f"/data/misc/perfetto-traces/{name}.pftrace"
    try:
        adb.adb("push", cfg_local, cfg_remote)
        if not quiet:
            say(f"Recording {'for the duration in the config' if config else f'for {seconds} s'} ... reproduce what you want to see on the phone now.", "cyan")
        adb.adb("shell", "perfetto", "--txt", "-c", cfg_remote, "-o", remote)
        adb.adb("pull", remote, local)
    finally:
        adb.sh(f"rm -f {cfg_remote} {remote}")
        cfg_local.unlink(missing_ok=True)
    if not quiet:
        say(f"Saved {local} ({local.stat().st_size / 1e6:.1f} MB). Open https://ui.perfetto.dev and drag the file onto the page.", "green")
    return local


# ---------------------------------------------------------------- frida
def frida_start() -> None:
    """frida-server on the phone as root (idempotent), so frida-ps and frida-trace work from this PC."""
    binary = WORK / "device-tools" / "frida-server"
    if not binary.exists():
        raise Failure("frida-server not downloaded. Run: aosp-academy setup")
    # As root: a server started as shell can list processes but not inject into most of them.
    running = adb.root("ps -A -o USER,NAME | grep -w frida-server")
    if running.startswith("root"):
        say("frida-server already running as root")
        return
    if running:
        frida_stop()
    adb.adb("push", binary, "/data/local/tmp/frida-server")
    adb.root("chmod 755 /data/local/tmp/frida-server; nohup /data/local/tmp/frida-server >/dev/null 2>&1 &")
    time.sleep(1)
    say("frida-server: " + adb.root("ps -A -o USER,PID,NAME | grep -w frida-server"))


def frida_stop() -> None:
    adb.root("pkill -x frida-server")
    time.sleep(1)


# ---------------------------------------------------------------- inventory
ARM_PARTS = {"0xd03": "Cortex-A53", "0xd05": "Cortex-A55", "0xd0a": "Cortex-A75", "0xd0b": "Cortex-A76", "0xd0d": "Cortex-A77",
             "0xd41": "Cortex-A78", "0xd46": "Cortex-A510", "0xd47": "Cortex-A710", "0xd4d": "Cortex-A715", "0xd80": "Cortex-A520",
             "0xd81": "Cortex-A720"}

RAW = {
    "getprop.txt": "getprop", "cpuinfo.txt": "cat /proc/cpuinfo", "meminfo.txt": "cat /proc/meminfo",
    "version.txt": "cat /proc/version", "df.txt": "df -h", "features.txt": "pm list features",
    "packages.txt": "pm list packages -f", "display.txt": "dumpsys display", "battery.txt": "dumpsys battery",
    "sensors.txt": "dumpsys sensorservice", "camera.txt": "dumpsys media.camera", "surfaceflinger.txt": "dumpsys SurfaceFlinger",
    "cpufreq.txt": "for c in /sys/devices/system/cpu/cpu[0-9]*; do echo $c $(cat $c/cpufreq/cpuinfo_min_freq 2>/dev/null) $(cat $c/cpufreq/cpuinfo_max_freq 2>/dev/null); done",
    "mounts.txt": "cat /proc/mounts",
    # The vendor interface: what the vendor offers (VINTF manifests) and what the system requires.
    "vintf-vendor-manifest.txt": 'for f in /vendor/etc/vintf/manifest.xml /vendor/etc/vintf/manifest/*.xml /odm/etc/vintf/manifest.xml /odm/etc/vintf/manifest/*.xml; do [ -f "$f" ] && echo "== $f" && cat "$f"; done 2>&1',
    "vintf-system-matrix.txt": 'for f in /system/etc/vintf/compatibility_matrix*.xml /system/etc/vintf/manifest.xml; do [ -f "$f" ] && echo "== $f" && cat "$f"; done 2>&1',
    "kernel-modules.txt": "cat /proc/modules 2>&1", "services.txt": "dumpsys -l 2>&1",
    "vendor-hal-files.txt": "ls -lR /vendor/bin/hw /vendor/lib64/hw /vendor/etc/init /vendor/firmware 2>&1",
}
RAW_ROOT = {
    "devicetree.txt": r"cat /proc/device-tree/model; echo; tr '\000' '\n' < /proc/device-tree/compatible",
    "partitions-byname.txt": "ls -l /dev/block/by-name", "partitions-proc.txt": "cat /proc/partitions",
    "partitions-mapper.txt": "ls -l /dev/block/mapper", "lshal.txt": "lshal 2>/dev/null",
}


def info(label: str | None = None, bugreport: bool = False) -> Path:
    """A hardware and software inventory into work/device-info/<timestamp>[-label]/. Read-only.

    The raw dumps are PRIVATE (serial, IMEI, MACs, app list); summary.txt leaves identifiers out
    and is the source for the hardware page of the docs.
    """
    adb.assert_one_device()
    out = WORK / "device-info" / (datetime.now().strftime("%Y%m%d-%H%M%S") + (f"-{label}" if label else ""))
    out.mkdir(parents=True)
    root = adb.has_root()
    raw: dict[str, str] = {}
    for f, cmd in RAW.items():
        raw[f] = adb.sh(cmd)
    for f, cmd in RAW_ROOT.items():
        raw[f] = adb.root(cmd) if root else "(no root)"
    raw["logcat-all.txt"] = adb.adb("logcat", "-d", "-b", "all", check=False)
    raw["logcat-crash.txt"] = adb.adb("logcat", "-d", "-b", "crash", check=False)
    for f, text in raw.items():
        (out / f).write_text(text, encoding="utf-8")
    if bugreport:
        say("Taking a full bugreport (several minutes) ...", "cyan")
        adb.adb("bugreport", out / "bugreport.zip")

    p = adb.prop
    blocks = {m[2]: int(m[1]) for m in re.finditer(r"(?m)^\s*\d+\s+\d+\s+(\d+)\s+(\S+)$", raw["partitions-proc.txt"])}

    def table(listing: str) -> list[str]:
        rows = []
        for m in re.finditer(r"\s(\S+) -> /dev/block/(\S+)$", listing, re.M):
            kb = blocks.get(m[2])
            rows.append(f"{m[1]:<24} {round(kb / 1024, 1) if kb else '?':>10} {m[2]}")
        return sorted(rows)

    physical, dynamic = table(raw["partitions-byname.txt"]), table(raw["partitions-mapper.txt"])
    (out / "partitions.txt").write_text("name                       size MiB  device\n" + "\n".join(physical)
                                        + "\n\ndynamic (in super):\n" + "\n".join(dynamic) + "\n", encoding="utf-8")

    def rx(f: str, pat: str) -> list[str]:
        return [m.strip() for m in re.findall(pat, raw.get(f, ""))]

    cpu = raw["cpuinfo.txt"]
    cores = len(re.findall(r"(?m)^processor", cpu))
    parts = Counter(re.findall(r"(?m)^CPU part\s*:\s*(\S+)", cpu))
    part_text = ", ".join(f"{n}x {ARM_PARTS.get(k, k)} ({k})" for k, n in parts.items())
    freqs = "; ".join(f"cpu{m[1]}: {int(m[3]) / 1e6:.2f} GHz" for m in re.finditer(r"cpu(\d+)\s+(\d+)\s+(\d+)", raw["cpufreq.txt"]))
    mem = int((rx("meminfo.txt", r"(?m)^MemTotal:\s+(\d+)") or ["0"])[0])
    refresh = ", ".join(f"{r} Hz" for r in sorted({round(float(x)) for x in ",".join(rx("display.txt", r"mSupportedRefreshRates=\[([^\]]+)\]")[:1]).split(",") if x.strip()}, reverse=True))
    sensors = sorted(set(rx("sensors.txt", r"(?m)^0x[0-9a-fA-F]+\)\s+([^|\r\n]+?)\s*\|")))
    sensor_types = sorted(set(rx("sensors.txt", r"type:\s*android\.sensor\.([a-z_]+)")))
    hals = sorted(set(rx("lshal.txt", r"(?m)^[A-Z ]+\s+[YN?]\s+((?:android|vendor|mediatek)[\w.]+(?:@[\d.]+)?(?:::\w+)?)")))
    crashers = ", ".join(f"{k} x{n}" for k, n in Counter(rx("logcat-crash.txt", r"(?m)>>> (\S+) <<<")).most_common())
    denials = ", ".join(f"{k} x{n}" for k, n in Counter(rx("logcat-all.txt", r"avc:\s+denied\s+\{[^}]+\}\s+for\s+.*?scontext=u:r:(\w+)")).most_common(8))
    data_total = next((l.split()[1] for l in raw["df.txt"].splitlines() if l.rstrip().endswith(" /data")), "?")
    summary = f"""Device inventory (identifiers omitted). Raw dumps are beside this file and are private.

Session          build {p('ro.build.display.id')} ({p('ro.build.type')}); root over adb: {root}; crashes since boot: {crashers}
SELinux denials  {denials or 'none in logcat'}
Model            {p('ro.product.model')}  (SKU {p('ro.boot.hardware.sku')}; product {p('ro.product.device')} / bootloader {p('ro.boot.hardware')})
Android          {p('ro.build.version.release')} (SDK {p('ro.build.version.sdk')}), build {p('ro.build.id')}, patch {p('ro.build.version.security_patch')}
Fingerprint      {p('ro.build.fingerprint')}
Kernel           {adb.sh('uname -r')}
Bootloader       {p('ro.bootloader')}
Verified boot    state={p('ro.boot.verifiedbootstate')} flash.locked={p('ro.boot.flash.locked')} slot={p('ro.boot.slot_suffix')}
SoC              {p('ro.soc.manufacturer')} {p('ro.soc.model')}  (ro.hardware={p('ro.hardware')}, platform={p('ro.board.platform')}, mediatek.platform={p('ro.vendor.mediatek.platform')})
Device tree      {raw['devicetree.txt'].splitlines()[0] if raw['devicetree.txt'] else ''}
CPU              {cores} cores: {part_text} (ARM part ids); {freqs}
GPU              {(rx('surfaceflinger.txt', r'(?m)^\s*(GLES:.*)$') or [''])[0]}
RAM              {mem / 1048576:.1f} GiB visible to the kernel
Storage          /data {data_total} total; UFS/eMMC: {p('ro.boot.boot_devices')}
Display          {adb.sh('wm size')}; {adb.sh('wm density')}; refresh rates: {refresh}; HDR types: [{(rx('display.txt', r'mSupportedHdrTypes=\[([^\]]*)\]') or [''])[0]}]
Battery          design capacity {adb.sh('cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null')} uAh (charge_full_design)
Cameras          {(rx('camera.txt', r'Number of camera devices:\s*(\d+)') or ['?'])[0]} camera devices (dumpsys media.camera)
Sensors          {len(sensors)} hardware/virtual sensors: {', '.join(sensors)}
Sensor types     {', '.join(sensor_types)}
Partitions       {len(physical)} physical ({sum(1 for r in physical if re.match(r'^\S+_a\s', r))} slot-A, {sum(1 for r in physical if re.match(r'^\S+_b\s', r))} slot-B), {len(dynamic)} dynamic in super; table in partitions.txt
HALs             {len(hals)} HAL interfaces registered (lshal)
Virtualization   AVF/pKVM: hypervisor.vm.supported='{p('ro.boot.hypervisor.vm.supported')}' (empty = not supported)
Treble           vndk={p('ro.vndk.version')} first_api={p('ro.product.first_api_level')} gki={p('ro.boot.gki')}
"""
    (out / "summary.txt").write_text(summary, encoding="utf-8")
    say(summary)
    say(f"Raw dumps (private, do not commit): {out}", "yellow")
    return out
