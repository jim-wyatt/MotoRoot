"""aosp-academy image: the build node's side (any x86-64 Linux host: native, WSL2, VM or container).

  inputs   download and verify the image's pinned inputs (the Fossify APKs) into work/device-tools
  setup    install AOSP's build dependencies, repo and git-lfs on this host (image/build/setup.sh)
  sync     check out the pinned AOSP tag into $AOSP_DIR (image/build/sync.sh)
  apply    put this project's product, patches and APKs into the tree (image/build/apply-local.sh)
  build    apply, lunch, build, and publish to $PUBLISH_DIR if set (image/build/build-image.sh)
  verify   find and repair half-checked-out projects in the tree (image/build/verify-tree.sh)
  after-sync  wait for a running sync, then build (overnight runs; image/build/build-after-sync.sh)

The AOSP steps stay bash: envsetup.sh and lunch are bash. Settings come from the environment:
AOSP_DIR (default: deviceTools.aosp.treeDir), JOBS, PUBLISH_DIR, PARTS.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from .core import ROOT, WINDOWS, WORK, Failure, get_pinned, note, pins, step

SCRIPTS = {"setup": "setup.sh", "sync": "sync.sh", "apply": "apply-local.sh", "build": "build-image.sh", "verify": "verify-tree.sh",
           "after-sync": "build-after-sync.sh"}


def inputs() -> int:
    step("Image inputs (work/device-tools)")
    d = WORK / "device-tools"
    n = 0
    for dl in pins()["deviceTools"]["downloads"]:
        if dl.get("buildOnly"):
            get_pinned(dl["url"], d / dl["name"], dl["sha256"])
            n += 1
    # The signing certificates (signerSha256) are checked when a pin changes, by 'aosp-academy check'
    # on a workstation with build-tools; the SHA-256 above already fixes every byte.
    wireguard_tools(d)
    note(f"{n} pinned inputs verified, and wireguard-tools at its pinned commit")
    return 0


def wireguard_tools(d: Path) -> None:
    """wireguard-tools at the pinned tag, its commit checked (the source of the image's wg)."""
    w = pins()["deviceTools"]["wireguardTools"]
    dest = d / "wireguard-tools"
    head = lambda: subprocess.run(["git", "-C", str(dest), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if not (dest / ".git").exists() or head() != w["commit"]:
        shutil.rmtree(dest, ignore_errors=True)
        subprocess.run(["git", "clone", "-q", "--depth", "1", "--branch", w["tag"], w["repo"], str(dest)], check=True)
    if head() != w["commit"]:
        raise Failure(f"wireguard-tools {w['tag']} is commit {head()[:12]}, not the pinned {w['commit'][:12]}: the tag moved upstream.")


def script(name: str) -> int:
    if WINDOWS:
        raise Failure("The image builds on a Linux host (native, WSL2, VM or container). Run this there.")
    path = ROOT / "image" / "build" / SCRIPTS[name]
    return subprocess.call(["bash", str(path)], cwd=ROOT)


def main(action: str) -> int:
    if action == "inputs":
        return inputs()
    if action == "build":
        inputs()
    return script(action)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
