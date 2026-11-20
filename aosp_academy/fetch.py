"""aosp-academy fetch: copy the newest image from the build node, verified.

The build node publishes system.img, system.img.sha256, build.prop, vbmeta.img (when the build
made one) and the image in parts (system.img.partNN, listed with their SHA-256 in system.img.parts)
under <repo>/work/device-tools/gsi/own. This pulls them over scp (OpenSSH, built into Windows 10+,
Linux and macOS) into work/device-tools/gsi/own here.

- An image that matches the remote checksum is not copied again.
- The parts come over parallel connections: the VPN path to the device node limits each
  connection, not the total (8 streams: 1.8 GB in about 4.5 minutes instead of 13).
- The joined image is kept only if its SHA-256 matches the build node's checksum. Parts that
  verified are kept on failure, so the next run resumes.
- The image it replaces is deleted. The publish folder holds only the newest build; keep your own
  copy (or ask the build node to) before a risky change.

Which machine to pull from is private to your network, so it isn't in the repository: pass
--host, --user, --repo (and --port) once with --save, and they're kept in work/remote-build.json.
"""
from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path

from .core import WORK, Failure, file_hash, first_hash, say, sleep, warn

CONFIG = WORK / "remote-build.json"
OWN = WORK / "device-tools" / "gsi" / "own"
IMG = OWN / "system.img"
DEPLOYED = OWN / "deployed.sha256"


class Remote:
    def __init__(self, conf: dict):
        for k in ("host", "user", "repo"):
            if not conf.get(k):
                raise Failure(f"No build node configured ({k} missing). Run once with --host, --user, --repo and --save.")
        self.conf = conf
        self.target = f"{conf['user']}@{conf['host']}"
        self.dir = conf["repo"].rstrip("/") + "/work/device-tools/gsi/own"
        # Keep-alives: a connection that dies silently in the tunnel (no reset) would otherwise
        # leave scp waiting forever (seen 2026-11-19); with these, scp exits after about 60 s.
        self.opts = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=10",
                     "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=4", "-q"]
        if conf.get("port"):
            self.opts += ["-P", str(conf["port"])]

    def scp_args(self, name: str, to: Path) -> list[str]:
        return ["scp", *self.opts, f"{self.target}:{self.dir}/{name}", str(to)]

    def pull(self, name: str, to: Path, required: bool = True) -> bool:
        p = subprocess.run(self.scp_args(name, to), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if p.returncode != 0:
            to.unlink(missing_ok=True)
            if required:
                raise Failure(f"scp of {name} from {self.target} failed (exit {p.returncode}).")
            return False
        return True


def load_config(args) -> dict:
    conf = json.loads(CONFIG.read_text(encoding="utf-8")) if CONFIG.exists() else {}
    for k in ("host", "user", "repo", "port"):
        v = getattr(args, k, None)
        if v:
            conf[k] = v.replace("\\", "/") if k == "repo" else v
    if getattr(args, "save", False):
        WORK.mkdir(exist_ok=True)
        CONFIG.write_text(json.dumps(conf, indent=2) + "\n", encoding="utf-8")
        say(f"Saved to {CONFIG}")
    return conf


def remote_configured(args) -> bool:
    """Whether there is a build node to fetch from: --host on the command line, or a saved
    work/remote-build.json with a host. Without one, this machine is its own build node."""
    if getattr(args, "host", None):
        return True
    if not CONFIG.exists():
        return False
    return bool(json.loads(CONFIG.read_text(encoding="utf-8")).get("host"))


def remote_hash(r: Remote) -> str:
    OWN.mkdir(parents=True, exist_ok=True)
    tmp = OWN / "remote.sha256"
    r.pull("system.img.sha256", tmp)
    h = first_hash(tmp)
    tmp.unlink()
    if not re.fullmatch(r"[0-9a-f]{64}", h):
        raise Failure("The build node's system.img.sha256 is not a SHA-256 line.")
    return h


def _pull_parts(r: Remote, to: Path, streams: int) -> bool:
    lst = OWN / "remote.parts"
    if not r.pull("system.img.parts", lst, required=False):
        return False
    parts = []
    for line in lst.read_text(encoding="utf-8").splitlines():
        m = re.fullmatch(r"([0-9a-f]{64})\s+\*?(system\.img\.part\d+)", line.strip())
        if m:
            parts.append({"hash": m[1], "name": m[2], "file": OWN / f".{m[2]}"})
    lst.unlink()
    if not parts:
        return False
    say(f"  {len(parts)} parts, {streams} streams")

    def bad() -> list[dict]:
        return [p for p in parts if not p["file"].exists() or file_hash(p["file"]) != p["hash"]]

    # Up to three retries of whatever failed, with a pause that grows each time: on a congested
    # link parts fail in bursts, and an immediate retry often fails the same way.
    for attempt in range(1, 5):
        todo = bad()
        if not todo:
            break
        if attempt > 1:
            warn(f"{len(todo)} part(s) failed or mismatched; fetching them again in {15 * (attempt - 1)} s (retry {attempt - 1} of 3)")
            sleep(15 * (attempt - 1))
        running: list[subprocess.Popen] = []
        for p in todo:
            while sum(1 for x in running if x.poll() is None) >= streams:
                time.sleep(0.2)
            running.append(subprocess.Popen(r.scp_args(p["name"], p["file"]), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        for x in running:
            x.wait()
    failed = bad()
    if failed:
        for p in failed:
            p["file"].unlink(missing_ok=True)
        raise Failure(f"Parts still missing or mismatched after 3 retries: {', '.join(p['name'] for p in failed)}. "
                      f"Nothing was replaced; the {len(parts) - len(failed)} verified parts are kept, so running again resumes.")
    # Each part goes as soon as it's joined, so the parts and the image never both sit on disk in full.
    try:
        with open(to, "wb") as out:
            for p in parts:
                with open(p["file"], "rb") as f:
                    while block := f.read(1 << 22):
                        out.write(block)
                p["file"].unlink()
    except OSError:
        to.unlink(missing_ok=True)
        for p in parts:
            p["file"].unlink(missing_ok=True)
        raise
    return True


def fetch(args) -> int:
    r = Remote(load_config(args))
    want = remote_hash(r)
    have = file_hash(IMG) if IMG.exists() else ""
    if have == want:
        say(f"Up to date: the local system.img is the build node's newest ({want[:12]}...).", "green")
        return 0
    if args.check:
        # deploy deletes the local copy after installing and keeps its hash in deployed.sha256,
        # so "no local image" usually means "already on the phone", not "something new".
        deployed = first_hash(DEPLOYED)
        if deployed == want:
            say(f"Nothing new: the build node's newest ({want[:12]}...) is the image last deployed to the phone.", "green")
        else:
            say(f"A new image is waiting on {r.conf['host']} ({want[:12]}...; last deployed: "
                f"{deployed[:12] + '...' if deployed else 'none recorded'}). Run without --check to fetch it.", "yellow")
        return 0

    part = OWN / "system.img.part"
    say(f"Fetching system.img from {r.conf['host']} ...")
    t0 = time.monotonic()
    if not _pull_parts(r, part, args.streams):
        say("  no parts published; fetching the single file")
        r.pull("system.img", part)
    got = file_hash(part)
    if got != want:
        part.unlink()
        raise Failure(f"Checksum mismatch: got {got}, expected {want}. Nothing was replaced.")
    # The sidecars come before the swap, and the previous build's copies go, so the DSU zip never
    # carries an old build.prop or vbmeta.img with the new image. build.prop is required.
    prop_part, vb_part = OWN / "build.prop.part", OWN / "vbmeta.img.part"
    try:
        r.pull("build.prop", prop_part)
    except Failure as e:
        part.unlink()
        raise Failure(f"build.prop not fetched; nothing was replaced. {e}") from None
    have_vb = r.pull("vbmeta.img", vb_part, required=False)
    for f in ("build.prop", "vbmeta.img", "system.img", "system.prev.img"):
        (OWN / f).unlink(missing_ok=True)
    part.replace(IMG)
    prop_part.replace(OWN / "build.prop")
    if have_vb:
        vb_part.replace(OWN / "vbmeta.img")
    else:
        say("  (no vbmeta.img published)")
    (OWN / "system.img.sha256").write_text(f"{want}  system.img\n", encoding="ascii")
    fp = next((l.split("=", 1)[1] for l in (OWN / "build.prop").read_text(encoding="utf-8", errors="replace").splitlines()
               if l.startswith("ro.system.build.fingerprint=")), "?")
    say(f"Fetched and verified: {IMG.stat().st_size >> 20} MB in {round(time.monotonic() - t0)} s, fingerprint {fp}", "green")
    say("Next: aosp-academy deploy --no-fetch")
    return 0
