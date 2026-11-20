"""Unit tests for the aosp_academy package: no phone, no network.

    python -m unittest discover -s tests        (aosp-academy check runs them too)
"""
import argparse
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from aosp_academy import adb, cli, core, tools  # noqa: E402


class Pins(unittest.TestCase):
    def test_every_download_is_pinned(self):
        p = core.pins()
        for dl in p["deviceTools"]["downloads"]:
            self.assertRegex(dl["sha256"], r"^[0-9a-f]{64}$", dl["name"])
            self.assertTrue(dl["url"].startswith("https://"), dl["name"])
        for host, ct in p["androidSdk"]["cmdlineTools"].items():
            if isinstance(ct, dict):
                self.assertRegex(ct["sha1"], r"^[0-9a-f]{40}$", host)
        self.assertIn("windows", p["inputs"]["platformTools"])

    def test_aosp_pin(self):
        a = core.pins()["deviceTools"]["aosp"]
        self.assertRegex(a["tag"], r"^android-\d+\.\d+\.\d+_r\d+$")
        self.assertRegex(a["lunch"], r"^\w+-\w+-(user|userdebug|eng)$")

    def test_platform_api(self):
        self.assertEqual(tools.platform_api("android-36"), 36)
        self.assertEqual(tools.platform_api("android-37.0"), 37)


class Shell(unittest.TestCase):
    def test_quote_survives_single_quotes(self):
        self.assertEqual(adb.quote("it's"), "'it'\\''s'")
        self.assertEqual(adb.quote("a b"), "'a b'")


class Images(unittest.TestCase):
    def test_image_state_follows_the_product(self):
        self.assertEqual(core.image_state("aospacademy_arm64"), "/data/local/aospacademy-firstboot")
        self.assertTrue(core.is_image_product("aospacademy_arm64"))
        self.assertFalse(core.is_image_product("aosp_arm64"))


class Report(unittest.TestCase):
    def test_battery_line(self):
        from aosp_academy import deploy
        dump = "\n".join(["  AC powered: false", "  USB powered: true", "  status: 4", "  health: 2", "  level: 86", "  temperature: 260"])
        self.assertEqual(deploy.battery(dump), "86%, not charging, health good, 26.0 C, power USB")
        self.assertIn("health ?", deploy.battery(""))


class NewApp(unittest.TestCase):
    def test_template_renders_completely(self):
        from aosp_academy import newapp
        with tempfile.TemporaryDirectory() as d:
            files = newapp.render(Path(d), "com.example.demo", "Demo")
            rel = {f.relative_to(d).as_posix() for f in files}
            self.assertIn("app/src/main/kotlin/com/example/demo/MainActivity.kt", rel)
            self.assertIn(".gitignore", rel)
            for f in files:
                self.assertNotIn("{{", f.read_text(encoding="utf-8"), f)
            gradle = (Path(d) / "app" / "build.gradle.kts").read_text(encoding="utf-8")
            self.assertIn(f"compileSdk = {core.pins()['appTemplate']['compileSdk']}", gradle)

    def test_template_gradle_matches_the_archive_pin(self):
        t = core.pins()["appTemplate"]
        a = next(a for a in core.pins()["archives"] if a["extractTo"] == "gradle")
        self.assertEqual(a["sha256"], t["gradleSha256"])
        self.assertIn(f"gradle-{t['gradle']}-bin.zip", a["url"])

    def test_bad_package_is_refused(self):
        from aosp_academy import newapp
        for bad in ("demo", "Com.Example", "com.example.class", "com..x"):
            with self.assertRaises(core.Failure, msg=bad):
                newapp.new_app(tempfile.mkdtemp(), bad, None, False, False)


class Files(unittest.TestCase):
    def test_get_pinned_refuses_a_mismatched_file(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "x.bin"
            f.write_bytes(b"not the pinned bytes")
            with self.assertRaises(core.Failure):
                core.get_pinned("https://example.invalid/x.bin", f, "0" * 64)

    def test_first_hash(self):
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "x.sha256"
            f.write_text("ABCDEF  system.img\n")
            self.assertEqual(core.first_hash(f), "abcdef")
            self.assertEqual(core.first_hash(Path(d) / "missing"), "")


class Cli(unittest.TestCase):
    def test_every_command_parses(self):
        p = cli.parser()
        for argv in (["fetch", "--check"], ["deploy", "--no-fetch", "-y"], ["gsi", "status"], ["device", "test", "--skip", "frida"],
                     ["device", "trace", "--seconds", "2"], ["setup", "--skip-system"], ["check"], ["env", "--shell", "bash"],
                     ["stock", "build"], ["image", "inputs"], ["new-app", "x", "--package", "com.example.x", "--test"]):
            self.assertIsInstance(p.parse_args(argv), argparse.Namespace, argv)

    def test_no_powershell_left(self):
        root = Path(__file__).resolve().parent.parent
        left = {p.relative_to(root).as_posix() for p in root.rglob("*.ps*1") if "work" not in p.parts and ".git" not in p.parts}
        self.assertEqual(left, set(), "PowerShell scripts remain")


if __name__ == "__main__":
    unittest.main()
