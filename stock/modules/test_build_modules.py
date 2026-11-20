"""Tests for build_modules.py. Standard library only, so they run anywhere, CI included:

    python -m unittest discover -s stock/modules -p "test_*.py" -v
"""
from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import build_modules as bm


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def entries(path: Path) -> list:
    """What a ZIP holds, independent of the compressor: deflate output differs between zlib builds
    (Windows' Python and a Linux runner's), so archives built on two platforms can differ in bytes
    while every entry is identical. Names, order, timestamps, permissions and contents all count."""
    with zipfile.ZipFile(path) as z:
        return [(i.filename, i.date_time, i.external_attr, z.read(i)) for i in z.infolist()]


class CommittedModules(unittest.TestCase):
    """The ZIPs in stock/modules must hold exactly what their manifests build."""

    def test_every_manifest_rebuilds_its_committed_zip(self):
        manifests = sorted(bm.MANIFEST_DIR.glob("*.json"))
        self.assertTrue(manifests, "no manifests found")
        with tempfile.TemporaryDirectory() as tmp:
            for manifest in manifests:
                built = bm.build_module(manifest, Path(tmp))
                committed = bm.HERE / built.name
                with self.subTest(module=built.name):
                    self.assertTrue(committed.exists(), f"{built.name} is not committed")
                    self.assertEqual(entries(built), entries(committed),
                                     f"{built.name} is stale: rebuild with stock\\Build-StockArtifacts.ps1 -Promote")

    def test_no_committed_zip_without_a_manifest(self):
        ids = {bm.load_manifest(m)["id"].replace("_", "-") + ".zip" for m in bm.MANIFEST_DIR.glob("*.json")}
        orphans = sorted(z.name for z in bm.HERE.glob("*.zip") if z.name not in ids)
        self.assertEqual(orphans, [], "ZIPs with no manifest")

    def test_build_is_deterministic(self):
        manifest = next(iter(sorted(bm.MANIFEST_DIR.glob("*.json"))))
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            self.assertEqual(sha256(bm.build_module(manifest, Path(a))), sha256(bm.build_module(manifest, Path(b))))

    def test_scripts_are_lf_executable_and_packages_are_replace_markers(self):
        with tempfile.TemporaryDirectory() as tmp:
            for manifest in sorted(bm.MANIFEST_DIR.glob("*.json")):
                data = bm.load_manifest(manifest)
                with zipfile.ZipFile(bm.build_module(manifest, Path(tmp))) as z:
                    names = z.namelist()
                    self.assertIn("module.prop", names)
                    self.assertIn("manifest.json", names)
                    for script in (data.get("scripts") or {}):
                        info = z.getinfo(script)
                        self.assertEqual((info.external_attr >> 16) & 0o777, 0o755, script)
                        self.assertNotIn(b"\r", z.read(script), script)
                        self.assertFalse(z.read(script).startswith(b"\xef\xbb\xbf"), script)
                    for item in data.get("packages") or []:
                        self.assertIn("system" + item["hidden_directory"] + "/.replace", names)


class Validation(unittest.TestCase):
    """Malformed manifests are refused with a ManifestError, never packaged or crashed on."""

    BASE = {"id": "test_module", "name": "Test", "version": "1.0", "versionCode": 1, "description": "A test."}
    PKG = {"package": "com.example.app", "label": "Example", "hidden_directory": "/product/app/Example"}

    def load(self, data) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "t.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            return bm.load_manifest(path)

    def refuses(self, **changes):
        data = {**self.BASE, "packages": [dict(self.PKG)], **changes}
        with self.assertRaises(bm.ManifestError):
            self.load(data)

    def test_a_valid_overlay_manifest_loads(self):
        self.assertEqual(self.load({**self.BASE, "packages": [self.PKG]})["id"], "test_module")

    def test_bad_ids(self):
        for bad in ("", "A", "has-dash", "../x", "a/b", "1abc", "x" * 65, 5):
            with self.subTest(id=bad):
                self.refuses(id=bad)

    def test_line_breaks_in_module_prop_fields(self):
        for key in ("name", "version", "description"):
            with self.subTest(key=key):
                self.refuses(**{key: "line one\nid=evil"})

    def test_version_code_must_be_an_int(self):
        for bad in ("1", 1.5, True):
            with self.subTest(versionCode=bad):
                self.refuses(versionCode=bad)

    def test_package_entries(self):
        self.refuses(packages=["com.example.app"])
        self.refuses(packages=[])
        self.refuses(packages=[{"package": "x", "label": "y"}])
        self.refuses(packages=[self.PKG, dict(self.PKG)])
        for bad in ("/system/app/X", "/data/app/X", "/product/app/../../data", "/product/app/X/"):
            with self.subTest(hidden_directory=bad):
                self.refuses(packages=[{**self.PKG, "hidden_directory": bad}])
        self.refuses(packages=[{**self.PKG, "apk": "/product/app/Other/Other.apk"}])

    def test_scripts(self):
        base = {**self.BASE}
        with self.assertRaises(bm.ManifestError):
            self.load({**base, "scripts": {"boot.sh": "dev_adb_tcp/post-fs-data.sh"}})
        with self.assertRaises(bm.ManifestError):
            self.load({**base, "scripts": {"service.sh": "../build_modules.py"}})
        with self.assertRaises(bm.ManifestError):
            self.load({**base, "scripts": {"service.sh": "does/not/exist.sh"}})
        with self.assertRaises(bm.ManifestError):
            self.load({**base})  # neither packages nor scripts
        self.assertIn("scripts", self.load({**base, "scripts": {"post-fs-data.sh": "dev_adb_tcp/post-fs-data.sh"}}))


if __name__ == "__main__":
    unittest.main()
