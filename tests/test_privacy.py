"""Nothing private in the tracked files: the whole tree, not only what a commit adds.

The pre-commit hook checks each commit's staged changes, but it can be skipped (--no-verify) and
a CI run can't. This scans every tracked file for private network addresses, private key
material, device identifiers and the project's own private values. Those values are never
written down in the repository. They come from:

  - work/wifi.json (the SSID and passphrase) and work/remote-build.json (the build node's host
    and user) on a set-up workstation. Both are git-ignored.
  - work/private-terms.txt, one term per line (device serials, names). Also git-ignored.
  - AOSP_ACADEMY_PRIVATE_TERMS, newline-separated: the CI secret of the same name.

A failure names the file, the line and the kind of match, never the private value itself.

    python -m unittest discover -s tests -p test_privacy.py
"""
import ipaddress
import json
import os
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
BINARY = {".zip", ".dex", ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".woff", ".woff2", ".pdf"}

IPV4 = re.compile(r"(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])")
CHECKS = {
    "private key": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    # adbkey.pub lines start QAAAA; a whole one in a tracked file is a machine's identity.
    "adb public key": re.compile(r"\bQAAAA[A-Za-z0-9+/]{300,}"),
    "IMEI-like number": re.compile(r"(?<![0-9a-fA-F])(35|86|99)\d{13}(?![0-9a-fA-F])"),
    "serial assignment": re.compile(r"(?i)\b(ro\.serialno|serialno|serial_number|imei|meid)\s*[:=]\s*['\"]?[A-Z0-9]{8,}"),
}


def tracked() -> list[Path]:
    out = subprocess.run(["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True).stdout
    return [ROOT / f for f in out.decode("utf-8").split("\0") if f]


def private_terms() -> list[str]:
    terms: list[str] = []
    for name, keys in (("wifi.json", ("ssid", "passphrase")), ("remote-build.json", ("host", "user"))):
        try:
            data = json.loads((WORK / name).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        terms += [str(data[k]) for k in keys if data.get(k)]
    try:
        terms += (WORK / "private-terms.txt").read_text(encoding="utf-8").splitlines()
    except OSError:
        pass
    terms += os.environ.get("AOSP_ACADEMY_PRIVATE_TERMS", "").splitlines()
    # Short or generic values (a user called "root", a port) would match everywhere: skip them.
    return sorted({t.strip() for t in terms if len(t.strip()) >= 5})


def is_private(octets: tuple[str, ...]) -> bool:
    if any(int(o) > 255 for o in octets):
        return False
    ip = ipaddress.IPv4Address(".".join(octets))
    # RFC 1918 and carrier-grade NAT. Loopback, 0.0.0.0 and the documentation ranges (192.0.2.0/24
    # and friends, which the docs use for examples) are fine.
    return any(ip in ipaddress.IPv4Network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10"))


class Privacy(unittest.TestCase):
    def test_tree_holds_nothing_private(self):
        terms = private_terms()
        lowered = [t.lower() for t in terms]
        hits = []
        for f in tracked():
            if f.suffix.lower() in BINARY or not f.is_file() or f == Path(__file__).resolve():
                continue
            try:
                text = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            rel = f.relative_to(ROOT).as_posix()
            for n, line in enumerate(text.splitlines(), 1):
                if any(is_private(m.groups()) for m in IPV4.finditer(line)):
                    hits.append(f"{rel}:{n}: private network address")
                for kind, rx in CHECKS.items():
                    if rx.search(line):
                        hits.append(f"{rel}:{n}: {kind}")
                low = line.lower()
                for i, t in enumerate(lowered, 1):
                    if t in low:
                        hits.append(f"{rel}:{n}: private term #{i} of {len(terms)}")
        self.assertEqual(hits, [], "private data in tracked files:\n" + "\n".join(hits))

    def test_scanner_catches_what_it_should(self):
        self.assertTrue(is_private(("192", "168", "1", "20")))
        self.assertTrue(is_private(("10", "0", "0", "5")))
        self.assertFalse(is_private(("192", "0", "2", "10")))   # documentation range
        self.assertFalse(is_private(("8", "8", "8", "8")))
        self.assertFalse(is_private(("300", "1", "1", "1")))
        self.assertTrue(CHECKS["private key"].search("-----BEGIN RSA PRIVATE KEY-----"))
        # Built from parts so this file doesn't itself look like a serial to the pre-commit hook.
        self.assertTrue(CHECKS["serial assignment"].search("ro.serialno" + "=" + "ZY22ABCDEF"))
        self.assertFalse(CHECKS["IMEI-like number"].search("sha 1795190721350000"))


if __name__ == "__main__":
    unittest.main()
