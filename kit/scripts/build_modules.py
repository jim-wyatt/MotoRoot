"""Rebuild module ZIPs locally. Does not communicate with or modify a phone."""
from pathlib import Path
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def write_module(filename, props, dirs, extra=None):
    path = ROOT / "modules" / filename
    path.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("module.prop", props)
        for directory in sorted(set(dirs)):
            if not directory.startswith(("/product/app/", "/product/priv-app/",
                                         "/system_ext/app/", "/system_ext/priv-app/")):
                raise ValueError(f"Unexpected overlay path: {directory}")
            if ".." in Path(directory).parts:
                raise ValueError("Parent traversal in module path")
            archive.writestr("system" + directory + "/.replace", "")
        for name, data in (extra or {}).items():
            archive.writestr(name, data)
    print(path)


def main():
    write_module("wifi-ota-guard.zip", """id=wifi_ota_guard
name=Motorola automatic firmware update block
version=1.0
versionCode=1
author=Local device owner
description=Hides Motorola Software Update while enabled. Disable this module and reboot to restore the updater. Does not block Play Store app updates.
""", ["/system_ext/priv-app/3c_ota"])
    manifest = json.loads((ROOT / "carrier-debloat-manifest.json").read_text())
    if len(manifest) != 22 or len({item["package"] for item in manifest}) != 22:
        raise ValueError("Expected 22 unique carrier packages")
    write_module("wifi-carrier-debloat.zip", """id=wifi_carrier_debloat
name=Wi-Fi device carrier debloat
version=1.0
versionCode=1
author=Local device owner
description=Reversibly hides Verizon, Tracfone activation and remote-SIM-lock apps, carrier management services, and Motorola PAKS finance apps. Disable and reboot to restore.
""", [item["hidden_directory"] for item in manifest],
                 {"carrier-manifest.json": json.dumps(manifest, indent=2)})


if __name__ == "__main__":
    main()
