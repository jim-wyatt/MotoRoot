"""aosp-academy image: the build node's side (any x86-64 Linux host: native, WSL2, VM or container).

  inputs   download and verify the image's pinned inputs (the Fossify APKs) into work/device-tools
  setup    install AOSP's build dependencies, repo and git-lfs on this host (image/build/setup.sh)
  sync     check out the pinned AOSP tag into $AOSP_DIR (image/build/sync.sh)
  apply    put this project's product, patches and APKs into the tree (image/build/apply-local.sh)
  build    apply, lunch, build, and publish to $PUBLISH_DIR if set (image/build/build-image.sh)

The AOSP steps stay bash: envsetup.sh and lunch are bash. Settings come from the environment:
AOSP_DIR (default: deviceTools.aosp.treeDir), JOBS, PUBLISH_DIR, PARTS.
"""
from __future__ import annotations

import subprocess
import sys

from .core import ROOT, WINDOWS, WORK, Failure, get_pinned, note, pins, step

SCRIPTS = {"setup": "setup.sh", "sync": "sync.sh", "apply": "apply-local.sh", "build": "build-image.sh", "verify": "verify-tree.sh"}


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
    note(f"{n} pinned inputs verified")
    return 0


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
