"""Paths, pins, output and small helpers every command shares."""
from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
PINS_FILE = ROOT / "toolchain.json"
WINDOWS = os.name == "nt"
# The image's own names: the product (ro.product.name starts with it), its property prefix and the
# first-boot service's state directory on the phone. Kept here so a rename touches one line each.
PRODUCT = "aospacademy"
# Images built before the rename (build 10 and older) still use the old names. Remove once every
# image in use is an aospacademy one.
LEGACY_PRODUCTS = ("vedotom",)


def image_state(product_name: str) -> str:
    """The first-boot service's state directory for the image whose ro.product.name is given."""
    for p in (PRODUCT, *LEGACY_PRODUCTS):
        if product_name.startswith(p):
            return f"/data/local/{p}-firstboot"
    return f"/data/local/{PRODUCT}-firstboot"


def is_image_product(product_name: str) -> bool:
    return product_name.startswith((PRODUCT, *LEGACY_PRODUCTS))
EXE = ".exe" if WINDOWS else ""


class Failure(Exception):
    """A step failed in a way the user has to act on. The CLI prints the message, no traceback."""


# ---------------------------------------------------------------- output
_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") is None
if WINDOWS and _COLOR:
    os.system("")  # enables ANSI escape handling in the Windows console


def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _COLOR else text


def step(text: str) -> None:
    print(_c("36", f"== {text}"), flush=True)


def ok(text: str) -> None:
    print(_c("32", f"   OK  {text}"), flush=True)


def note(text: str) -> None:
    print(f"   ..  {text}", flush=True)


def warn(text: str) -> None:
    print(_c("33", f"   !!  {text}"), flush=True)


def say(text: str, color: str | None = None) -> None:
    print(_c({"green": "32", "yellow": "33", "cyan": "36", "red": "31"}[color], text) if color else text, flush=True)


# ---------------------------------------------------------------- pins
_pins: dict | None = None


def pins() -> dict:
    global _pins
    if _pins is None:
        _pins = json.loads(PINS_FILE.read_text(encoding="utf-8"))
    return _pins


# ---------------------------------------------------------------- files
def file_hash(path: Path, algorithm: str = "sha256") -> str:
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def first_hash(path: Path) -> str:
    """The hash at the start of a `sha256sum`-style line ('' when the file is missing)."""
    try:
        return path.read_text(encoding="utf-8").split()[0].lower()
    except (OSError, IndexError):
        return ""


def download(url: str, dest: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "aosp-academy"})
    with urllib.request.urlopen(req, timeout=60) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)


def get_pinned(url: str, dest: Path, expected: str, algorithm: str = "sha256") -> None:
    """Download url to dest unless dest already matches; verify before moving into place.

    A file that is present but doesn't match is never overwritten: someone has to look at it.
    """
    name = dest.name
    if dest.exists():
        if file_hash(dest, algorithm) == expected.lower():
            ok(f"{name} (hash verified)")
            return
        raise Failure(f"{dest} exists but its {algorithm} does not match the pin. Inspect or delete it; not overwriting.")
    dest.parent.mkdir(parents=True, exist_ok=True)
    partial = dest.with_name(name + ".partial")
    note(f"downloading {name}")
    download(url, partial)
    if file_hash(partial, algorithm) != expected.lower():
        partial.unlink()
        raise Failure(f"Hash mismatch for {name} from {url}. Stop: do not substitute another source.")
    partial.replace(dest)
    ok(f"{name} (downloaded, hash verified)")


# ---------------------------------------------------------------- processes
def run(args: list, check: bool = True, capture: bool = False, **kw) -> subprocess.CompletedProcess:
    """Run a program. With capture, stdout and stderr come back as text (stderr merged)."""
    if capture:
        kw.setdefault("stdout", subprocess.PIPE)
        kw.setdefault("stderr", subprocess.STDOUT)
        kw.setdefault("text", True)
        kw.setdefault("encoding", "utf-8")
        kw.setdefault("errors", "replace")
    p = subprocess.run([str(a) for a in args], **kw)
    if check and p.returncode != 0:
        raise Failure(f"{Path(str(args[0])).name} {' '.join(str(a) for a in args[1:3])} ... failed (exit {p.returncode})"
                      + (f":\n{p.stdout.strip()}" if capture and p.stdout else ""))
    return p


def which(name: str) -> str | None:
    return shutil.which(name)


def sleep(seconds: float) -> None:
    time.sleep(seconds)


def host() -> str:
    return f"{platform.system()} {platform.machine()}"
