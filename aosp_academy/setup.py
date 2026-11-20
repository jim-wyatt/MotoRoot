"""aosp-academy setup: install and verify the workstation. Idempotent; re-run any time.

Every download is pinned in toolchain.json and verified before use. Nothing here talks to the phone.

  1. system tools: winget packages on Windows (JDK 21, Git, GitHub CLI, scrcpy, jadx, and Android
     Studio with --studio); on Linux and macOS the missing ones are listed for your package manager
  2. JDK 21, and the Android SDK (cmdline-tools, the pinned platform, build-tools, NDK)
  3. pinned JARs and archives in work/tools (R8, apktool, the jadx CLI)
  4. the device procedure's exact inputs in work/ (platform-tools, Magisk and the other APKs,
     val-protocol at its pinned commit; the Motorola driver is checked, not downloaded)
  5. device tools in work/device-tools (frida-server, the F-Droid APK); the image's own inputs
     are the build node's (aosp-academy image inputs)
  6. Python venvs in work/: .venv (val-protocol), .venv-frida (frida-tools), .venv-docs (the site)
  7. git: the pre-commit hook that keeps device data out of the repository
"""
from __future__ import annotations

import lzma
import os
import platform
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from . import tools
from .core import EXE, ROOT, WINDOWS, WORK, Failure, file_hash, get_pinned, note, ok, pins, run, step, warn

LINUX_PACKAGES = {"java": "openjdk-21-jdk", "git": "git", "gh": "gh", "scrcpy": "scrcpy"}


def host_key() -> str:
    if WINDOWS:
        return "windows"
    if sys.platform == "darwin":
        return "mac-arm64" if platform.machine() in ("arm64", "aarch64") else "mac-x64"
    return "linux"


def _set_user_env(name: str, value: str) -> None:
    """Persist a per-user environment variable (Windows registry; elsewhere, tell the user)."""
    os.environ[name] = value
    if not WINDOWS:
        return
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_READ | winreg.KEY_SET_VALUE) as k:
        try:
            if winreg.QueryValueEx(k, name)[0] == value:
                return
        except OSError:
            pass
        winreg.SetValueEx(k, name, 0, winreg.REG_SZ, value)
    note(f"set user environment variable {name}={value}")
    # Tell running programs (Explorer, new terminals) that the environment changed.
    import ctypes
    ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x1A, 0, "Environment", 2, 5000, None)


def system_tools(studio: bool) -> None:
    step("System tools")
    if not WINDOWS:
        missing = [pkg for exe, pkg in LINUX_PACKAGES.items() if not shutil.which(exe)]
        if missing:
            warn(f"install with your package manager: {' '.join(missing)}  (and Android Studio from developer.android.com if wanted)")
        else:
            ok("java, git, gh, scrcpy")
        return
    if not shutil.which("winget"):
        raise Failure('winget is not available. Install "App Installer" from the Microsoft Store.')
    for pkg in pins()["winget"]:
        if pkg.get("optional") and not studio:
            note(f"skip {pkg['id']} (pass --studio)")
            continue
        if subprocess.run(["winget", "list", "-e", "--id", pkg["id"], "--accept-source-agreements"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            ok(pkg["id"])
            continue
        note(f"installing {pkg['id']} - {pkg['purpose']}")
        run(["winget", "install", "-e", "--id", pkg["id"], "--silent", "--accept-package-agreements", "--accept-source-agreements"])
        ok(pkg["id"])
    # winget's installs change PATH for new processes only; pick them up for this one.
    import winreg
    paths = []
    for hive, key in ((winreg.HKEY_LOCAL_MACHINE, r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"), (winreg.HKEY_CURRENT_USER, "Environment")):
        try:
            with winreg.OpenKey(hive, key) as k:
                paths.append(os.path.expandvars(winreg.QueryValueEx(k, "Path")[0]))
        except OSError:
            pass
    os.environ["PATH"] = os.pathsep.join(paths + [os.environ.get("PATH", "")])


def jdk() -> Path:
    step("JDK 21")
    j = tools.java_home()
    if not j and WINDOWS:
        found = sorted(Path(r"C:\Program Files\Microsoft").glob("jdk-21*"))
        j = found[-1] if found else None
    if not j:
        raise Failure("JDK 21 not found. Install it (setup does on Windows), or set JAVA_HOME.")
    _set_user_env("JAVA_HOME", str(j))
    v = run([j / "bin" / f"java{EXE}", "-version"], capture=True).stdout.splitlines()[0]
    if '"21.' not in v:
        warn(f"JAVA_HOME is {v}; the pins are tested with JDK 21")
    ok(v)
    return j


def android_sdk(accept_licenses: bool) -> None:
    step("Android SDK")
    sdk = tools.sdk() or (Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" if WINDOWS else Path.home() / "Android" / "Sdk")
    sdk.mkdir(parents=True, exist_ok=True)
    _set_user_env("ANDROID_HOME", str(sdk))
    latest = sdk / "cmdline-tools" / "latest"
    if not (latest / "bin").exists():
        ct = pins()["androidSdk"]["cmdlineTools"][host_key()]
        zp = tools.CACHE / ct["url"].rsplit("/", 1)[1]
        get_pinned(ct["url"], zp, ct["sha1"], "sha1")
        tmp = tools.CACHE / "cmdline-tools-extract"
        shutil.rmtree(tmp, ignore_errors=True)
        _unzip(zp, tmp)
        latest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(tmp / "cmdline-tools"), latest)
        shutil.rmtree(tmp, ignore_errors=True)
    ok(f"cmdline-tools at {latest}")
    sdkmanager = latest / "bin" / f"sdkmanager{tools.BAT}"
    lic = sdk / "licenses"
    if accept_licenses:
        note("accepting the Android SDK licenses (--accept-sdk-licenses)")
        subprocess.run([str(sdkmanager), f"--sdk_root={sdk}", "--licenses"], input="y\n" * 30, text=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif not (lic.exists() and any(lic.iterdir())):
        if not sys.stdin.isatty():
            raise Failure("Android SDK licenses not accepted yet. Run setup in an interactive terminal, or pass --accept-sdk-licenses after reviewing them.")
        note("review and accept the Android SDK licenses:")
        subprocess.run([str(sdkmanager), f"--sdk_root={sdk}", "--licenses"])
    # cmdline-tools 23+ ship the android CLI; sdkmanager is its deprecated wrapper. --no-metrics
    # opts out of the CLI's usage telemetry.
    cli = latest / "bin" / f"android{EXE}"
    for pkg in pins()["androidSdk"]["packages"]:
        note(f"installing/verifying {pkg}")
        if cli.exists():
            run([cli, "--no-metrics", f"--sdk={sdk}", "sdk", "install", pkg])
        else:
            run([sdkmanager, f"--sdk_root={sdk}", pkg.replace("/", ";")])
    for pkg in pins()["androidSdk"]["packages"]:
        if not (sdk / pkg).exists():
            raise Failure(f"SDK package {pkg} is not installed after the install step.")
    ok(f"SDK packages installed: {', '.join(pins()['androidSdk']['packages'])}")


def _unzip(zp: Path, dest: Path) -> None:
    """Extract, keeping the execute bits the archive records (zipfile drops them)."""
    with zipfile.ZipFile(zp) as z:
        for info in z.infolist():
            out = z.extract(info, dest)
            mode = info.external_attr >> 16
            if mode and not WINDOWS:
                os.chmod(out, mode & 0o777)


def jars() -> None:
    step("Pinned JARs and archives (work/tools)")
    for j in pins()["jars"]:
        algo = "sha256" if j.get("sha256") else "sha1"
        get_pinned(j["url"], tools.TOOLS / j["name"], j[algo], algo)
    for a in pins()["archives"]:
        zp = tools.CACHE / a["name"]
        get_pinned(a["url"], zp, a["sha256"])
        dest = tools.TOOLS / a["extractTo"]
        stamp = dest / ".pinned-sha256"
        if not stamp.exists() or stamp.read_text().strip() != a["sha256"]:
            shutil.rmtree(dest, ignore_errors=True)
            _unzip(zp, dest)
            stamp.write_text(a["sha256"] + "\n")
        ok(f"{a['extractTo']} extracted from {a['name']}")


def device_inputs() -> None:
    step("Device procedure inputs (the exact tested versions)")
    i = pins()["inputs"]
    pt = i["platformTools"].get(host_key())
    if not pt:
        warn(f"platform-tools {i['platformTools']['version']} isn't pinned for {host_key()} yet; device work needs it")
    else:
        zp = WORK / "platform-tools.zip"
        get_pinned(pt["url"], zp, pt["sha1"], "sha1")
        adb = WORK / "platform-tools" / f"adb{EXE}"
        version = _adb_version(adb)
        if not version.startswith(i["platformTools"]["version"] + "-"):
            if (WORK / "platform-tools").exists():
                raise Failure(f"work/platform-tools holds {version or 'something else'}, not {i['platformTools']['version']}. Stop any ADB server, remove the folder, re-run.")
            _unzip(zp, WORK)
            version = _adb_version(adb)
        ok(f"platform-tools {version}")
    for apk in i["apks"]:
        get_pinned(apk["url"], WORK / apk["name"], apk["sha256"])
    q = i["testDpcQr"]
    get_pinned(q["url"], WORK / q["name"], q["sha256"])
    vp, vdir = i["valProtocol"], WORK / "val-protocol"
    if not (vdir / ".git").exists():
        run(["git", "clone", "--quiet", vp["repo"], vdir])
        run(["git", "-C", vdir, "checkout", "--quiet", "--detach", vp["commit"]])
    head = run(["git", "-C", vdir, "rev-parse", "HEAD"], capture=True).stdout.strip()
    if head != vp["commit"]:
        warn(f"val-protocol is at {head}, not the pinned {vp['commit']}. Left untouched.")
    else:
        ok(f"val-protocol @ {vp['commit'][:12]}")
    drv = i["motorolaDriver"]
    msi = WORK / drv["name"]
    if not WINDOWS:
        note("Motorola USB driver: Windows only (Linux and macOS need none)")
    elif not msi.exists():
        warn(f"{drv['name']} not present. Download it from {drv['page']} into {WORK} and re-run to verify.")
    elif file_hash(msi) == drv["sha256"]:
        ok(f"{drv['name']} (hash matches the tested driver)")
    else:
        warn(f"{drv['name']} differs from the tested driver's hash (a newer driver?). Check it is Motorola-signed before installing.")


def _adb_version(adb: Path) -> str:
    """adb prints "Android Debug Bridge version 1.0.41" then "Version 37.0.1-<build>"."""
    if not adb.exists():
        return ""
    for line in run([adb, "version"], capture=True, check=False).stdout.splitlines():
        if line.startswith("Version "):
            return line.split()[1]
    return ""


def device_tools() -> None:
    step("Device tools (work/device-tools)")
    d = WORK / "device-tools"
    for dl in pins()["deviceTools"]["downloads"]:
        f = d / dl["name"]
        if dl.get("buildOnly"):
            # An image input: the build node fetches it (aosp-academy image inputs).
            if f.exists() and (ROOT / "image" / "build").exists() and not os.environ.get("AOSP_DIR"):
                pass
            continue
        get_pinned(dl["url"], f, dl["sha256"])
        if dl.get("extract"):
            out, stamp = d / dl["extract"], d / f"{dl['extract']}.pinned-sha256"
            if not out.exists() or not stamp.exists() or stamp.read_text().strip() != dl["sha256"]:
                with lzma.open(f) as src, open(out, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                stamp.write_text(dl["sha256"] + "\n")
            ok(f"{dl['extract']} extracted")


def _venv(name: str, requirements: list[str]) -> Path:
    vdir = WORK / name
    py = vdir / tools.VENV_BIN / f"python{EXE}"
    cfg = vdir / "pyvenv.cfg"
    if py.exists() and cfg.exists():
        # A venv's launchers embed the absolute path it was created at; after the checkout moves
        # they exit 1 with no output, so a moved venv is recreated.
        recorded = next((l.split("-m venv", 1)[1].strip() for l in cfg.read_text().splitlines() if "-m venv" in l), "")
        if recorded and Path(recorded).resolve() != vdir.resolve():
            warn(f"{vdir} was created at {recorded} (checkout moved?). Recreating it.")
            shutil.rmtree(vdir)
    if not py.exists():
        run([sys.executable, "-m", "venv", vdir])
    if requirements:
        run([py, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", *requirements])
    return py


def venvs() -> None:
    step("Python venvs (work/.venv, .venv-frida, .venv-docs)")
    # Separate on purpose: .venv runs val-protocol (bootloader patching) and stays minimal.
    req = WORK / "val-protocol" / "requirements.txt"
    py = _venv(".venv", ["-r", str(req), "pyasn1"] if req.exists() else [])
    ok(run([py, "--version"], capture=True).stdout.strip())
    fr = pins()["deviceTools"]["frida"]
    _venv(".venv-frida", [f"frida=={fr['version']}", f"frida-tools=={fr['toolsVersion']}"])
    ok("frida " + run([tools.venv_exe(".venv-frida", "frida"), "--version"], capture=True).stdout.strip())
    _venv(".venv-docs", ["-r", str(ROOT / "docs" / "requirements.txt")])
    ok(run([tools.venv_exe(".venv-docs", "zensical"), "--version"], capture=True).stdout.strip())


def git_hooks() -> None:
    step("Git hooks")
    run(["git", "-C", ROOT, "config", "core.hooksPath", ".githooks"])
    ok("core.hooksPath = .githooks (blocks images, large binaries, private folders, IMEI-like numbers)")


def setup(args) -> int:
    if str(ROOT).startswith("\\\\"):
        raise Failure(f"Run from a local folder, not a network or WSL path ({ROOT}).")
    if sys.version_info < (3, 11):
        raise Failure("Python 3.11 or newer is needed.")
    WORK.mkdir(exist_ok=True)
    tools.TOOLS.mkdir(parents=True, exist_ok=True)
    tools.CACHE.mkdir(parents=True, exist_ok=True)
    if not args.skip_system:
        system_tools(args.studio)
    jdk()
    if not args.skip_sdk:
        android_sdk(args.accept_sdk_licenses)
    jars()
    if not args.skip_inputs:
        device_inputs()
        device_tools()
    venvs()
    git_hooks()
    print("\nDone. 'aosp-academy check' tests the workstation; 'aosp-academy shell' opens a shell with the tools on PATH.")
    return 0
