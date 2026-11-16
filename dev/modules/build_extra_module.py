"""Build dev/modules/wifi-extra-debloat.zip from wifi-extra-debloat-manifest.json.

Same technique as kit/scripts/build_modules.py: for every package in the manifest, the
module places an empty ".replace" marker over the APK's directory, so Magisk's systemless
overlay hides that directory at boot. Nothing on the firmware partition is modified.
Disable the module in Magisk and reboot to bring every app back.

Runs on the PC only. Does not communicate with or modify a phone.
"""
from pathlib import Path
import json
import zipfile

HERE = Path(__file__).resolve().parent
MANIFEST = HERE / "wifi-extra-debloat-manifest.json"
OUTPUT = HERE / "wifi-extra-debloat.zip"
EXPECTED_PACKAGES = 19
ALLOWED_PREFIXES = ("/product/app/", "/product/priv-app/",
                    "/system_ext/app/", "/system_ext/priv-app/")

MODULE_PROP = """id=wifi_extra_debloat
name=Wi-Fi device extra debloat
version=1.0
versionCode=1
author=Local device owner
description=Reversibly hides AT&T, Cricket and Facebook partner stubs, Motorola telemetry and support apps, Ready For desktop mode, visual voicemail and Digital Wellbeing. Complements wifi_carrier_debloat. Disable and reboot to restore.
"""


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    packages = {item["package"] for item in manifest}
    if len(manifest) != EXPECTED_PACKAGES or len(packages) != EXPECTED_PACKAGES:
        raise ValueError(f"Expected {EXPECTED_PACKAGES} unique packages, got {len(manifest)}")
    dirs = sorted({item["hidden_directory"] for item in manifest})
    for item in manifest:
        if not item["apk"].startswith(item["hidden_directory"] + "/"):
            raise ValueError(f"APK is not inside its hidden_directory: {item['package']}")
    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("module.prop", MODULE_PROP)
        for directory in dirs:
            if not directory.startswith(ALLOWED_PREFIXES):
                raise ValueError(f"Unexpected overlay path: {directory}")
            if ".." in Path(directory).parts:
                raise ValueError("Parent traversal in module path")
            archive.writestr("system" + directory + "/.replace", "")
        archive.writestr("extra-manifest.json", json.dumps(manifest, indent=2) + "\n")
    print(OUTPUT)


if __name__ == "__main__":
    main()
