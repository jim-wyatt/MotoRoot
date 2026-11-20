"""aosp-academy check: verify the workstation end to end. Never talks to the phone.

It checks pins and versions, and it also exercises each tool: rebuilds the stock artifacts and
compares them with the committed copies, decompiles a DEX with jadx, cross-compiles with the NDK,
compiles against the pinned platform, builds the docs site, runs the unit tests, imports
val-protocol, re-verifies every pinned input and the APK signing certificates, and checks the git
safety settings. Scratch output goes to work/build/check. The exit code is the number of failures.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from . import stock, tools
from .core import EXE, ROOT, WINDOWS, WORK, file_hash, pins, run, say
from .devtest import Checks

TMP = WORK / "build" / "check"


def _out(args: list, **kw) -> str:
    p = run(args, check=False, capture=True, **kw)
    if p.returncode != 0:
        raise RuntimeError(p.stdout.strip()[-400:] or f"exit {p.returncode}")
    return p.stdout.strip()


def run_checks() -> int:
    shutil.rmtree(TMP, ignore_errors=True)
    TMP.mkdir(parents=True)
    spec = pins()
    c = Checks(set())
    warns: list[tuple[str, str, str]] = []
    sdk, jh = tools.sdk(), tools.java_home()
    bt, ndk, jar = tools.pinned_dir("build-tools", quiet=True), tools.pinned_dir("ndk", quiet=True), tools.platform_jar()
    pkgs = spec["androidSdk"]["packages"]

    # ---------------- environment and SDK
    c("env", "JDK 21 (JAVA_HOME)", lambda: '"21.' in _out([jh / "bin" / f"java{EXE}", "-version"]) and str(jh))
    c("env", "ANDROID_HOME", lambda: sdk and sdk.exists() and str(sdk))
    for p in pkgs:
        c("sdk", p, lambda p=p: (sdk / p).exists())
    c("sdk", "build-tools d8", lambda: _out([bt / f"d8{tools.BAT}", "--version"]).splitlines()[0])
    c("sdk", "build-tools aapt2", lambda: _out([bt / f"aapt2{EXE}", "version"]).splitlines()[0])

    # ---------------- pinned tools
    for j in spec["jars"]:
        algo = "sha256" if j.get("sha256") else "sha1"
        c("tools", j["name"], lambda j=j, a=algo: file_hash(tools.TOOLS / j["name"], a) == j[a])
    c("tools", "apktool runs", lambda: _out([jh / "bin" / f"java{EXE}", "-jar", tools.jar("apktool"), "--version"]))
    jadx_pin = next(a["sha256"] for a in spec["archives"] if a["extractTo"] == "jadx")
    c("tools", "jadx CLI pinned", lambda: (tools.TOOLS / "jadx" / ".pinned-sha256").read_text().strip() == jadx_pin)
    pinned_adb = WORK / "platform-tools" / f"adb{EXE}"
    adb_version = lambda a: next((l for l in _out([a, "version"]).splitlines() if l.startswith("Version ")), "?")  # noqa: E731

    def _sdk_adb():
        s, p = adb_version(sdk / "platform-tools" / f"adb{EXE}"), adb_version(pinned_adb)
        # Android Studio uses the SDK's adb; two server versions fight over the device.
        if s != p:
            raise RuntimeError(f"SDK {s} vs pinned {p}: decline the platform-tools update in Studio, or move the pin")
        return s
    c("tools", "SDK platform-tools adb = pinned adb", _sdk_adb)
    for exe in ("git", "gh", "scrcpy"):
        c("tools", exe, lambda exe=exe: shutil.which(exe) or False)
    studio = Path(r"C:\Program Files\Android\Android Studio\bin\studio64.exe") if WINDOWS else None
    if not (studio and studio.exists()) and not shutil.which("studio"):
        warns.append(("tools", "Android Studio", "not installed (optional: aosp-academy setup --studio)"))

    # ---------------- functional builds
    def _stock():
        r = stock.build(quiet=True)
        bad = [n for n, same, _, _ in r if not same]
        if bad:
            raise RuntimeError("differs: " + ", ".join(bad))
        return f"{len(r)} artifacts identical"
    c("build", "stock helpers + modules reproduce committed copies", _stock)

    def _module_scripts():
        for zp in sorted((ROOT / "stock" / "modules").glob("*.zip")):
            with zipfile.ZipFile(zp) as z:
                for i in z.infolist():
                    if not i.filename.endswith(".sh"):
                        continue
                    b = z.read(i)
                    if b.startswith(b"\xef\xbb\xbf"):
                        raise RuntimeError(f"{zp.name}:{i.filename} has a BOM")
                    if b"\r" in b:
                        raise RuntimeError(f"{zp.name}:{i.filename} has CR line endings")
                    if not (i.external_attr >> 16) & 0o111:
                        raise RuntimeError(f"{zp.name}:{i.filename} is not executable")
        return True
    c("build", "module scripts are LF, no BOM, executable in the ZIPs", _module_scripts)

    def _unittests():
        ran = []
        for d in (ROOT / "tests", ROOT / "stock" / "modules"):
            out = _out([sys.executable, "-I", "-m", "unittest", "discover", "-s", d, "-p", "test_*.py"], cwd=ROOT)
            n = re.search(r"Ran (\d+) tests?", out)[1]
            ran.append(f"{d.relative_to(ROOT).as_posix()}: {n}")
        return ", ".join(ran)
    c("build", "unit tests (tests/, stock/modules/)", _unittests)

    def _jadx():
        j = tools.TOOLS / "jadx" / "bin" / ("jadx.bat" if WINDOWS else "jadx")
        _out([j, "--quiet", "-d", TMP / "jadx", ROOT / "stock" / "helpers" / "UpdateHelper.dex"], env={**os.environ, "JAVA_HOME": str(jh)})
        return any("class UpdateHelper" in f.read_text(errors="replace") for f in (TMP / "jadx").rglob("UpdateHelper.java"))
    c("build", "jadx decompiles UpdateHelper.dex", _jadx)

    def _ndk():
        src, out = TMP / "hello.c", TMP / "hello"
        src.write_text('#include <stdio.h>\nint main(void) { puts("hello from XT2617V"); return 0; }\n')
        _out([tools.ndk_clang(26), "-O2", "-o", out, src])
        b = out.read_bytes()
        return b[:4] == b"\x7fELF" and b[4] == 2 and b[18] == 0xB7  # 64-bit, e_machine AArch64
    c("build", "NDK cross-compiles an aarch64 Android binary", _ndk)

    def _javac():
        j = TMP / "Probe.java"
        j.write_text("public class Probe { public static String v() { return android.os.Build.VERSION.RELEASE; } }\n")
        _out([jh / "bin" / f"javac{EXE}", "--release", "8", "-nowarn", "-Xlint:-options", "-cp", jar, "-d", TMP / "probe", j])
        return jar.parent.name
    c("build", "javac against the pinned platform's android.jar", _javac)

    def _docs():
        _out([tools.venv_exe(".venv-docs", "zensical"), "build", "--strict", "--clean", "-f", ROOT / "zensical.toml"], cwd=ROOT)
        return (ROOT / "site" / "index.html").exists()
    c("build", "docs site builds (zensical --strict)", _docs)

    def _bash():
        bash = shutil.which("bash")
        if WINDOWS:
            # Git Bash, not WSL's bash.exe (which can't read Windows paths).
            git = shutil.which("git")
            gb = Path(git).resolve().parent.parent / "bin" / "bash.exe" if git else None
            bash = str(gb) if gb and gb.exists() else None
        if not bash:
            raise RuntimeError("no bash on PATH (Git Bash on Windows)")
        files = [*sorted((ROOT / "image" / "build").glob("*.sh")), *sorted((ROOT / "stock" / "modules" / "scripts").rglob("*.sh")),
                 ROOT / "image" / "product" / "aospacademy" / "gsi" / "firstboot" / "aospacademy-firstboot.sh", ROOT / ".githooks" / "pre-commit"]
        files = [f for f in files if f.exists()]
        for f in files:
            if b"\r" in f.read_bytes():
                raise RuntimeError(f"{f.name} has CRLF line endings")
            _out([bash, "-n", f.as_posix()])
        return f"{len(files)} scripts"
    c("build", "shell scripts are LF and valid bash", _bash)

    # ---------------- device procedure inputs
    i = spec["inputs"]
    c("inputs", f"platform-tools {i['platformTools']['version']}", lambda: adb_version(pinned_adb).startswith(f"Version {i['platformTools']['version']}-"))
    for apk in i["apks"]:
        c("inputs", apk["name"], lambda a=apk: file_hash(WORK / a["name"]) == a["sha256"])
    c("inputs", "Test DPC QR", lambda: file_hash(WORK / i["testDpcQr"]["name"]) == i["testDpcQr"]["sha256"])
    vp = WORK / "val-protocol"
    c("inputs", "val-protocol pinned commit, clean tree",
      lambda: _out(["git", "-C", vp, "rev-parse", "HEAD"]) == i["valProtocol"]["commit"] and not _out(["git", "-C", vp, "status", "--porcelain", "--untracked-files=no"]))
    c("inputs", "val-protocol imports in work/.venv", lambda: _out([tools.venv_exe(".venv", "python"), "-c",
      "import sys; sys.path.insert(0, 'work/val-protocol'); import capstone, pyasn1, liblk, lk_static_analyzer, lk_auto_patch, lk_patch_partition, lk_repack_signed; print('ok')"],
      cwd=ROOT) == "ok")
    if WINDOWS:
        drv = i["motorolaDriver"]
        c("inputs", "Motorola driver installer pinned", lambda: file_hash(WORK / drv["name"]) == drv["sha256"])

    # ---------------- device tools
    dt = WORK / "device-tools"
    for dl in spec["deviceTools"]["downloads"]:
        if dl.get("buildOnly"):
            continue
        c("devtools", f"{dl['name']} pin", lambda d=dl: file_hash(dt / d["name"]) == d["sha256"])
        if dl.get("signerSha256"):
            # The hash pins the bytes; this pins the publisher, so re-pinning a newer version can't
            # silently accept a differently signed build.
            def _signer(d=dl):
                o = _out([bt / f"apksigner{tools.BAT}", "verify", "--print-certs", dt / d["name"]], env={**os.environ, "JAVA_HOME": str(jh)})
                m = re.search(r"certificate SHA-256 digest: ([0-9a-f]{64})", o)
                return bool(m) and m[1] == d["signerSha256"] and m[1][:16] + "..."
            c("devtools", f"{dl['name']} signing certificate", _signer)
    fr = next(d for d in spec["deviceTools"]["downloads"] if d.get("extract") == "frida-server")
    c("devtools", "frida-server extracted from the pinned archive",
      lambda: (dt / "frida-server").exists() and (dt / "frida-server.pinned-sha256").read_text().strip() == fr["sha256"])
    fv = spec["deviceTools"]["frida"]["version"]
    c("devtools", f"frida-tools venv = server {fv}", lambda: _out([tools.venv_exe(".venv-frida", "frida"), "--version"]) == fv)
    g = spec["deviceTools"]["gsi"]
    c("devtools", "GSI pin is complete", lambda: bool(g["name"] and re.fullmatch(r"[0-9a-f]{64}", g["sha256"]) and g["url"].endswith(g["name"])) and g["build"])
    a = spec["deviceTools"]["aosp"]
    c("devtools", "AOSP pin is complete", lambda: bool(re.match(r"android-\d+", a["tag"]) and a["lunch"] and a["manifest"]) and a["tag"])

    # ---------------- git safety
    c("git", "pre-commit hook active", lambda: _out(["git", "-C", ROOT, "config", "core.hooksPath"]) == ".githooks")
    paths = ["private-backups/lk_a.img", "lk-analysis/x.txt", "lk-patch-analysis/x.txt", "magisk-patch-files/init_boot.img", "unlock-keys.txt",
             "work/tools/x", "key.pem", "release.jks", "app/local.properties", "site/index.html", "app/build/x", "work/anything.txt",
             "traces/x.pftrace", "blobs/vendor.so", "extracted/x", "x.pftrace", "x.perfetto-trace", "adb_keys", "wifi.json"]

    def _ignored():
        p = subprocess.run(["git", "-C", str(ROOT), "check-ignore", *paths], capture_output=True, text=True)
        missing = set(paths) - set(p.stdout.split())
        if missing:
            raise RuntimeError("not ignored: " + ", ".join(sorted(missing)))
        return True
    c("git", "private paths ignored", _ignored)
    c("git", "commit email is a GitHub no-reply address", lambda: _out(["git", "-C", ROOT, "config", "user.email"]).endswith("@users.noreply.github.com"))

    shutil.rmtree(TMP, ignore_errors=True)
    for w in warns:
        c.rows.append(("WARN", *w))
    fails = c.report()
    return fails
