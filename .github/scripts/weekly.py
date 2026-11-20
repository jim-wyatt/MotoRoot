"""Weekly checks of what drifts without a commit here (.github/workflows/weekly.yml runs them).

    python .github/scripts/weekly.py pins                 every pinned URL in toolchain.json still resolves;
                                                          files up to 150 MB still match their checksum
    python .github/scripts/weekly.py upstream [--out F]   newer upstream releases than the pins (a Markdown list;
                                                          empty when everything is current)

Standard library only, so it runs on a bare runner or any workstation. Exit status: pins fails on
any problem; upstream always exits 0 and only reports.
"""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PINS = json.loads((ROOT / "toolchain.json").read_text(encoding="utf-8"))
UA = {"User-Agent": "aosp-academy-weekly-check"}
VERIFY_LIMIT = 150 * 1024 * 1024


def _open(url: str, method: str = "GET", tries: int = 3):
    for n in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, method=method, headers=UA), timeout=60)
        except urllib.error.HTTPError as e:
            if e.code in (403, 405) and method == "HEAD":   # some hosts refuse HEAD: fall back to GET
                return _open(url, "GET", tries)
            if e.code < 500 or n == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError):
            if n == tries - 1:
                raise
        time.sleep(5 * (n + 1))


def pinned_urls(o, path=""):
    if isinstance(o, dict):
        if "url" in o and any(k in o for k in ("sha256", "sha1")):
            yield path, o
        for k, v in o.items():
            yield from pinned_urls(v, f"{path}.{k}")
    elif isinstance(o, list):
        for i, v in enumerate(o):
            yield from pinned_urls(v, f"{path}[{i}]")


def pins() -> int:
    problems, seen = [], set()
    for path, o in pinned_urls(PINS):
        url = o["url"]
        if url in seen:
            continue
        seen.add(url)
        algo = "sha256" if "sha256" in o else "sha1"
        try:
            if "terms" in o:   # behind the publisher's terms (the Google GSI): only check that it's there
                with _open(url, "HEAD") as r:
                    print(f"ok    {path}: {r.status}, not downloaded (terms)")
                continue
            with _open(url) as r:
                size = int(r.headers.get("Content-Length") or 0)
                if size > VERIFY_LIMIT:
                    print(f"ok    {path}: {r.status}, {size >> 20} MB, checksum not re-verified (large)")
                    continue
                h = hashlib.new(algo)
                for block in iter(lambda: r.read(1 << 20), b""):
                    h.update(block)
            if h.hexdigest() != o[algo].lower():
                problems.append(f"{path}: {url} no longer matches its pinned {algo} (got {h.hexdigest()[:16]}...)")
                print(f"FAIL  {path}: checksum changed")
            else:
                print(f"ok    {path}: {algo} matches")
        except Exception as e:  # noqa: BLE001 - report every kind of failure the same way
            problems.append(f"{path}: {url}: {e}")
            print(f"FAIL  {path}: {e}")
    print(f"\n{len(seen)} pinned URLs, {len(problems)} problems")
    for p in problems:
        print(f"- {p}")
    return 1 if problems else 0


def _ver(s: str) -> tuple:
    return tuple(int(x) for x in re.findall(r"\d+", s))


def _aosp_tags() -> list[str]:
    out = subprocess.run(["git", "ls-remote", "--tags", "https://android.googlesource.com/platform/manifest"],
                         capture_output=True, text=True, check=True, timeout=300).stdout
    return sorted({m for m in re.findall(r"refs/tags/(android-\d+\.\d+\.\d+_r\d+)$", out, re.M)}, key=_ver)


def _sdk_repository() -> ET.Element:
    with _open("https://dl.google.com/android/repository/repository2-3.xml") as r:
        return ET.fromstring(r.read())


def _maven_latest(group_path: str) -> str:
    with _open(f"https://dl.google.com/dl/android/maven2/{group_path}/maven-metadata.xml") as r:
        versions = re.findall(r"<version>(\d+\.\d+\.\d+)</version>", r.read().decode())
    return max(versions, key=_ver)


def upstream(out: str | None) -> int:
    found = []
    pkgs = PINS["androidSdk"]["packages"]
    pinned = {p.split("/", 1)[0]: p.split("/", 1)[1] for p in pkgs if "/" in p}

    tag = PINS["deviceTools"]["aosp"]["tag"]
    newer = [t for t in _aosp_tags() if _ver(t) > _ver(tag)]
    if newer:
        found.append(f"AOSP tags newer than `{tag}`: {', '.join(f'`{t}`' for t in newer[-5:])}"
                     " (check the patches first: `AOSP_TAG=<tag> bash image/build/check-patches.sh`)")

    repo = _sdk_repository()
    stable = [p.get("path") for p in repo.iter("remotePackage")
              if (p.find("channelRef") is None or p.find("channelRef").get("ref") == "channel-0")]
    for kind in ("platforms", "build-tools", "ndk"):
        cur = pinned.get(kind)
        if not cur:
            continue
        avail = [p.split(";", 1)[1] for p in stable if p.startswith(kind + ";")]
        avail = [v for v in avail if re.fullmatch(r"(android-)?[\d.]+", v)]
        best = max(avail, key=_ver, default=None)
        # A newer minor platform of the same API (android-37.2 over 37.0) offers APIs the image's
        # release doesn't have; it matters only when the AOSP tag moves, so only a new API is news.
        if kind == "platforms" and best and _ver(best)[:1] == _ver(cur)[:1]:
            continue
        if best and _ver(best) > _ver(cur):
            found.append(f"SDK `{kind};{best}` (pinned: `{cur}`)")
    pt = PINS["inputs"]["platformTools"]["version"]
    pt_avail = [p.find("revision") for p in repo.iter("remotePackage") if p.get("path") == "platform-tools"]
    if pt_avail:
        r = pt_avail[0]
        best = ".".join(r.findtext(x, "0") for x in ("major", "minor", "micro"))
        if _ver(best) > _ver(pt):
            found.append(f"platform-tools `{best}` (pinned: `{pt}`; the flashing stages ran with the pinned one)")

    t = PINS["appTemplate"]
    agp = _maven_latest("com/android/tools/build/gradle")
    if _ver(agp) > _ver(t["agp"]):
        found.append(f"Android Gradle Plugin `{agp}` (new-app template: `{t['agp']}`)")
    with _open("https://services.gradle.org/versions/current") as r:
        gradle = json.load(r)["version"]
    if _ver(gradle) > _ver(t["gradle"]):
        found.append(f"Gradle `{gradle}` (new-app template and archive pin: `{t['gradle']}`)")

    text = "".join(f"- {f}\n" for f in found)
    print(text or "Everything is current.")
    if out:
        Path(out).write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "pins":
        sys.exit(pins())
    if cmd == "upstream":
        sys.exit(upstream(sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == "--out" else None))
    sys.exit(__doc__)
