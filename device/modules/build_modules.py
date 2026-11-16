"""Build the project's Magisk modules from their manifests.

Usage, from the repository root (dev/Build-Device.ps1 normally drives this):

    python device/modules/build_modules.py              # every manifest in manifests/
    python device/modules/build_modules.py --out DIR    # write the ZIPs somewhere else
    python device/modules/build_modules.py manifests/wifi-ota-guard.json

Each manifests/*.json describes one module. Two kinds exist, and a manifest may use both:

    {
      "id": "wifi_ota_guard",             # module.prop id; the ZIP is named id with - for _
      "name": "...",                      # module.prop name
      "version": "1.0",
      "versionCode": 1,
      "description": "...",
      "packages": [                       # OVERLAY module: the apps this module hides
        {
          "package": "com.example.app",
          "label": "what it is, for humans",
          "hidden_directory": "/product/priv-app/ExampleApp",
          "apk": "/product/priv-app/ExampleApp/ExampleApp.apk"   # optional, informational
        }
      ],
      "scripts": {                        # SCRIPT module: Magisk lifecycle scripts
        "post-fs-data.sh": "dev_debuggable/post-fs-data.sh"      # path under scripts/
      }
    }

Overlay modules: for every package the ZIP contains an empty
``system<hidden_directory>/.replace`` marker, which tells Magisk to mount that directory as
empty at boot, so the APK inside is not there while the module is enabled. Nothing on the
firmware partitions is modified; disable the module and reboot to undo.

Script modules: the named lifecycle scripts (customize.sh at install; post-fs-data.sh early
in boot, blocking; service.sh late in boot; uninstall.sh at removal) are copied from
scripts/ into the ZIP root. Scripts run as root, so they are normalised to LF line endings
and no BOM regardless of how git checked them out on Windows, and stored executable.

In both cases the manifest travels inside the ZIP as manifest.json, so a module found later
is self-describing.

Builds are deterministic: entry order and timestamps are fixed, so the same manifest and
scripts always produce a byte-identical ZIP and the committed ZIPs can be verified by hash.

This script runs on the PC only. It never communicates with or modifies a phone.
"""
from __future__ import annotations

import argparse
import json
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MANIFEST_DIR = HERE / "manifests"
SCRIPTS_DIR = HERE / "scripts"

# Magisk overlays these partitions through its /system mount. Anything else would be a mistake
# in a manifest, so it is rejected rather than silently packaged.
ALLOWED_PREFIXES = (
    "/product/app/",
    "/product/priv-app/",
    "/system_ext/app/",
    "/system_ext/priv-app/",
)

# The lifecycle scripts Magisk runs from a module's root, and nothing else.
ALLOWED_SCRIPTS = ("customize.sh", "post-fs-data.sh", "service.sh", "uninstall.sh")

# One fixed timestamp for every entry (the ZIP format cannot represent dates before 1980).
FIXED_DATE_TIME = (1980, 1, 1, 0, 0, 0)

REQUIRED_MODULE_KEYS = {"id", "name", "version", "versionCode", "description"}
REQUIRED_PACKAGE_KEYS = {"package", "label", "hidden_directory"}


class ManifestError(ValueError):
    """A manifest is malformed, or asks for something the module format cannot do safely."""


def _validate_packages(name: str, packages: list) -> None:
    seen_packages: set[str] = set()
    seen_dirs: set[str] = set()
    for item in packages:
        missing = REQUIRED_PACKAGE_KEYS - item.keys()
        if missing:
            raise ManifestError(f"{name}: package entry missing {sorted(missing)}: {item}")
        pkg, directory = item["package"], item["hidden_directory"]
        if pkg in seen_packages:
            raise ManifestError(f"{name}: duplicate package {pkg}")
        if directory in seen_dirs:
            raise ManifestError(f"{name}: duplicate hidden_directory {directory}")
        if not directory.startswith(ALLOWED_PREFIXES):
            raise ManifestError(f"{name}: {pkg}: unexpected overlay path {directory}")
        if ".." in Path(directory).parts or directory.endswith("/"):
            raise ManifestError(f"{name}: {pkg}: malformed hidden_directory {directory}")
        apk = item.get("apk")
        if apk is not None and not apk.startswith(directory + "/"):
            raise ManifestError(f"{name}: {pkg}: apk {apk} is not inside {directory}")
        seen_packages.add(pkg)
        seen_dirs.add(directory)


def _validate_scripts(name: str, scripts: dict) -> None:
    if not isinstance(scripts, dict) or not scripts:
        raise ManifestError(f"{name}: scripts must be a non-empty object")
    for script_name, rel in scripts.items():
        if script_name not in ALLOWED_SCRIPTS:
            raise ManifestError(f"{name}: {script_name} is not a Magisk lifecycle script {ALLOWED_SCRIPTS}")
        if not isinstance(rel, str) or ".." in Path(rel).parts or Path(rel).is_absolute():
            raise ManifestError(f"{name}: {script_name}: malformed path {rel!r}")
        if not (SCRIPTS_DIR / rel).is_file():
            raise ManifestError(f"{name}: {script_name}: scripts/{rel} does not exist")


def load_manifest(path: Path) -> dict:
    """Read and validate one manifest. Every error names the manifest and the offending item."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ManifestError(f"{path.name}: not valid JSON ({exc})") from exc
    if not isinstance(data, dict):
        raise ManifestError(f"{path.name}: top level must be an object")
    missing = REQUIRED_MODULE_KEYS - data.keys()
    if missing:
        raise ManifestError(f"{path.name}: missing keys {sorted(missing)}")
    if not isinstance(data["versionCode"], int):
        raise ManifestError(f"{path.name}: versionCode must be an integer")
    packages = data.get("packages")
    scripts = data.get("scripts")
    if not packages and not scripts:
        raise ManifestError(f"{path.name}: a module needs packages to hide, scripts to run, or both")
    if packages is not None:
        if not isinstance(packages, list) or not packages:
            raise ManifestError(f"{path.name}: packages must be a non-empty list")
        _validate_packages(path.name, packages)
    if scripts is not None:
        _validate_scripts(path.name, scripts)
    return data


def module_prop(manifest: dict) -> str:
    """The module.prop text Magisk reads: id, name, version, author, description."""
    return (
        f"id={manifest['id']}\n"
        f"name={manifest['name']}\n"
        f"version={manifest['version']}\n"
        f"versionCode={manifest['versionCode']}\n"
        "author=Local device owner\n"
        f"description={manifest['description']}\n"
    )


def script_bytes(rel: str) -> bytes:
    """A lifecycle script as it must reach the device: UTF-8, no BOM, LF line endings."""
    text = (SCRIPTS_DIR / rel).read_text(encoding="utf-8-sig")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if not text.endswith("\n"):
        text += "\n"
    return text.encode("utf-8")


def write_entry(archive: zipfile.ZipFile, name: str, data: bytes | str, mode: int = 0o644) -> None:
    """Add one entry with the fixed timestamp and the given Unix permissions."""
    info = zipfile.ZipInfo(name, date_time=FIXED_DATE_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = mode << 16
    archive.writestr(info, data)


def build_module(manifest_path: Path, out_dir: Path) -> Path:
    """Validate one manifest and write its ZIP into out_dir. Returns the ZIP path."""
    manifest = load_manifest(manifest_path)
    out = out_dir / (manifest["id"].replace("_", "-") + ".zip")
    with zipfile.ZipFile(out, "w") as archive:
        write_entry(archive, "module.prop", module_prop(manifest))
        for script_name in ALLOWED_SCRIPTS:                      # fixed order for determinism
            rel = (manifest.get("scripts") or {}).get(script_name)
            if rel:
                write_entry(archive, script_name, script_bytes(rel), mode=0o755)
        for directory in sorted(item["hidden_directory"] for item in manifest.get("packages") or []):
            write_entry(archive, "system" + directory + "/.replace", b"")
        write_entry(archive, "manifest.json", json.dumps(manifest, indent=2) + "\n")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Build Magisk module ZIPs from manifests.")
    parser.add_argument("--out", type=Path, default=HERE,
                        help="directory for the ZIPs (default: next to this script)")
    parser.add_argument("manifests", nargs="*", type=Path,
                        help="specific manifest files (default: every *.json in manifests/)")
    args = parser.parse_args(argv)
    manifests = args.manifests or sorted(MANIFEST_DIR.glob("*.json"))
    if not manifests:
        print(f"error: no manifests found in {MANIFEST_DIR}", file=sys.stderr)
        return 1
    args.out.mkdir(parents=True, exist_ok=True)
    try:
        for path in manifests:
            print(build_module(path, args.out))
    except ManifestError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
