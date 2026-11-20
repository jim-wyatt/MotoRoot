"""aosp-academy device test: exercise every development workflow on the connected phone.

'check' proves the workstation's tools work and never touches the phone; this is the other half.
It runs each workflow the docs teach, end to end, on whatever system the phone is running (stock
with Magisk, or an aosp-academy image), and leaves nothing behind.

  device   identity, build type, SELinux, which system is running
  root     a root shell (Magisk's su on stock, AOSP's su 0 in an image)
  logs     logcat reads, the buffer size, dumpsys
  native   an aarch64 binary built with the pinned NDK, run on the phone, removed
  app      an APK built with the pinned SDK tools (no Gradle): installed, launched, its log line
           read back, uninstalled
  debug    adb root and back (userdebug images), and how many processes accept a debugger (JDWP)
  trace    a 2-second Perfetto trace, pulled and checked, deleted
  frida    frida-server, frida-ps over USB, stopped (needs root)
  mirror   scrcpy reaches the device (lists its displays; opens no window)

The exit code is the number of failed checks.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import time
import zipfile
from pathlib import Path

from . import adb, device, tools
from .core import EXE, WORK, Failure, run, say

TMP = WORK / "build" / "device-test"
PKG = "dev.aospacademy.probe"


class Checks:
    def __init__(self, skip: set[str]):
        self.skip, self.rows = skip, []

    def __call__(self, area: str, name: str, fn) -> None:
        if area in self.skip:
            self.rows.append(("SKIP", area, name, "--skip"))
            return
        try:
            r = fn()
            status, detail = ("PASS" if r else "FAIL"), ("" if isinstance(r, bool) else str(r))
        except Exception as e:  # noqa: BLE001 - each check reports its own failure and the run goes on
            status, detail = "FAIL", str(e).strip().splitlines()[0] if str(e).strip() else type(e).__name__
        self.rows.append((status, area, name, detail))

    def report(self) -> int:
        w = [max(len(r[i]) for r in self.rows) for i in range(3)]
        for r in self.rows:
            color = {"PASS": "green", "FAIL": "red"}.get(r[0], "yellow")
            say(f"{r[0]:<{w[0]}}  {r[1]:<{w[1]}}  {r[2]:<{w[2]}}  {r[3]}", color)
        n = {s: sum(1 for r in self.rows if r[0] == s) for s in ("PASS", "FAIL", "SKIP", "WARN")}
        say(f"{len(self.rows)} checks: {n['PASS']} passed, {n['FAIL']} failed, {n['SKIP'] + n['WARN']} skipped or warned", "red" if n["FAIL"] else "green")
        return n["FAIL"]


def _native() -> str:
    api = 26
    cc = tools.ndk_clang(api)
    if not cc or not cc.exists():
        raise Failure("NDK clang not found (aosp-academy setup)")
    src, binary = TMP / "probe.c", TMP / "aospacademy-probe"
    src.write_text('#include <stdio.h>\n#include <sys/utsname.h>\n'
                   'int main(void) { struct utsname u; uname(&u); printf("probe ok on %s %s\\n", u.machine, u.release); return 0; }\n')
    run([cc, "-O2", "-o", binary, src], capture=True)
    adb.adb("push", binary, "/data/local/tmp/aospacademy-probe")
    try:
        out = adb.sh("chmod 755 /data/local/tmp/aospacademy-probe && /data/local/tmp/aospacademy-probe")
    finally:
        adb.sh("rm -f /data/local/tmp/aospacademy-probe")
    if not out.startswith("probe ok on aarch64"):
        raise Failure(out)
    return out


def _app() -> str:
    """The everyday loop with the pinned SDK tools alone: javac, d8, aapt2, zipalign, apksigner."""
    bt, jar, jh = tools.pinned_dir("build-tools", quiet=True), tools.platform_jar(), tools.java_home()
    if not (bt and jar and jh):
        raise Failure("build-tools, a platform or the JDK is missing (aosp-academy setup)")
    target = tools.platform_api(jar.parent.name)
    d = TMP / "app"
    src = d / "src" / "dev" / "aospacademy" / "probe"
    for p in (src, d / "classes", d / "dex"):
        p.mkdir(parents=True, exist_ok=True)
    (d / "AndroidManifest.xml").write_text(f"""<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{PKG}">
  <application android:label="aosp-academy probe" android:hasCode="true">
    <activity android:name=".Main" android:exported="true" />
  </application>
</manifest>
""")
    (src / "Main.java").write_text("""package dev.aospacademy.probe;
public class Main extends android.app.Activity {
    @Override protected void onCreate(android.os.Bundle b) {
        super.onCreate(b);
        android.util.Log.i("AospAcademyProbe", "app probe ok on sdk " + android.os.Build.VERSION.SDK_INT);
        finish();
    }
}
""")
    jbin = jh / "bin"
    run([jbin / f"javac{EXE}", "--release", "11", "-nowarn", "-Xlint:-options", "-cp", jar, "-d", d / "classes", src / "Main.java"], capture=True)
    classes = [str(p) for p in (d / "classes").rglob("*.class")]
    run([bt / f"d8{tools.BAT}", "--min-api", "26", "--lib", jar, "--output", d / "dex", *classes], capture=True)
    unsigned, aligned, apk, ks = d / "unsigned.apk", d / "aligned.apk", d / "probe.apk", d / "probe.jks"
    run([bt / f"aapt2{EXE}", "link", "-o", unsigned, "-I", jar, "--manifest", d / "AndroidManifest.xml",
         "--min-sdk-version", "26", "--target-sdk-version", str(target)], capture=True)
    with zipfile.ZipFile(unsigned, "a") as z:
        z.write(d / "dex" / "classes.dex", "classes.dex")
    run([bt / f"zipalign{EXE}", "-f", "-p", "4", unsigned, aligned], capture=True)
    run([jbin / f"keytool{EXE}", "-genkeypair", "-keystore", ks, "-storepass", "probepass", "-keypass", "probepass", "-alias", "probe",
         "-keyalg", "RSA", "-keysize", "2048", "-validity", "1", "-dname", "CN=aosp-academy probe"], capture=True)
    run([bt / f"apksigner{tools.BAT}", "sign", "--ks", ks, "--ks-pass", "pass:probepass", "--out", apk, aligned], capture=True,
        env={**os.environ, "JAVA_HOME": str(jh)})
    since = adb.sh("date '+%m-%d %H:%M:%S.000'")
    try:
        i = adb.adb("install", "-r", "-t", apk, check=False)
        if "Success" not in i:
            raise Failure(f"install: {i}")
        adb.sh(f"am start -W -n {PKG}/.Main")
        time.sleep(2)
        hits = [l for l in adb.adb("logcat", "-d", "-T", since, "-s", "AospAcademyProbe", check=False).splitlines() if "app probe ok" in l]
        if not hits:
            raise Failure("installed, but the activity did not log")
        return re.sub(r"^.*AospAcademyProbe\s*:\s*", "", hits[-1])
    finally:
        adb.adb("uninstall", PKG, check=False)


def _adb_root() -> str:
    try:
        adb.adb("root", check=False)
        adb.adb("wait-for-device", check=False)
        time.sleep(2)
        uid = adb.sh("id -u")
        if uid != "0":
            raise Failure(f"adb root gave uid {uid}")
        return "uid 0 under adb root"
    finally:
        adb.adb("unroot", check=False)
        adb.adb("wait-for-device", check=False)
        time.sleep(2)


def _jdwp() -> str:
    # adb jdwp keeps running; four seconds is enough for the list.
    p = subprocess.Popen([str(adb.ADB), "jdwp"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        out, _ = p.communicate(timeout=4)
    except subprocess.TimeoutExpired:
        p.kill()
        out, _ = p.communicate()
    n = sum(1 for l in out.splitlines() if l.strip().isdigit())
    prop = adb.prop("persist.debug.dalvik.vm.jdwp.enabled")
    # Informational: 0 is right on a system that opens JDWP only for debuggable apps.
    return f"{n} (persist.debug.dalvik.vm.jdwp.enabled='{prop}')" if n else \
        "0: only debuggable apps (all apps: persist.debug.dalvik.vm.jdwp.enabled=1 on a userdebug build, then reboot)"


def _trace() -> str:
    f = device.trace(2, "device-test-" + time.strftime("%Y%m%d-%H%M%S"), quiet=True)
    try:
        if f.stat().st_size <= 10_000:
            raise Failure("empty trace")
        return f"{f.stat().st_size // 1024:,} KB"
    finally:
        f.unlink(missing_ok=True)


def _frida(have_root: bool) -> str:
    if not have_root:
        raise Failure("needs root")
    ps = tools.venv_exe(".venv-frida", "frida-ps")
    device.frida_start()
    try:
        out = run([ps, "-U"], check=False, capture=True).stdout
        n = sum(1 for l in out.splitlines() if re.match(r"^\s*\d+\s+\S", l))
        if n <= 20:
            raise Failure(f"frida-ps saw {n} processes")
        return f"{n} processes visible"
    finally:
        device.frida_stop()


def _mirror() -> str:
    exe = shutil.which("scrcpy")
    if not exe:
        raise Failure("scrcpy not on PATH")
    out = run([exe, "--list-displays"], check=False, capture=True, env={**os.environ, "ADB": str(adb.ADB)}).stdout
    if "--display-id=0" not in out:
        raise Failure(out[:200])
    return "display 0 listed"


def run_tests(skip: set[str] | None = None) -> int:
    adb.assert_one_device()
    shutil.rmtree(TMP, ignore_errors=True)
    TMP.mkdir(parents=True)
    c = Checks(skip or set())
    p = adb.prop
    in_image = adb.gsi_running()
    c("device", "identity", lambda: f"{p('ro.product.model')} / {p('ro.product.name')} / {p('ro.build.type')} / Android {p('ro.build.version.release')}")
    c("device", "system running", lambda: ("DSU image: " if in_image else "phone's own system: ") + p("ro.build.display.id"))
    c("device", "SELinux enforcing", lambda: adb.sh("getenforce") == "Enforcing")
    c("device", "boot completed", lambda: p("sys.boot_completed") == "1")
    have_root = adb.has_root()

    def _root():
        if not have_root:
            raise Failure("no root: Magisk Shell grant on stock, or su 0 in a userdebug image")
        return adb.root("id -Z")
    c("root", "root shell", _root)

    def _logcat():
        n = len(adb.adb("logcat", "-d", "-t", "200", check=False).splitlines())
        if n <= 50:
            raise Failure(f"only {n} lines")
        return f"{n} lines"

    def _bufsize():
        m = re.search(r"ring buffer is (\S+ \S+)", g := adb.sh("logcat -g -b main"))
        if not m:
            raise Failure(g)
        return m[1]

    def _dumpsys():
        n = len(adb.sh("dumpsys -l").splitlines())
        if n <= 100:
            raise Failure(f"{n} services")
        return f"{n} services"
    c("logs", "logcat reads", _logcat)
    c("logs", "log buffer size", _bufsize)
    c("logs", "dumpsys", _dumpsys)
    c("native", "NDK binary runs on the phone", _native)
    c("app", "build, install, launch and uninstall an app", _app)
    # adb root works only on a real userdebug build (an image), not on stock: its adbd stays
    # unprivileged even with dev_debuggable's ro.debuggable=1.
    if in_image and p("ro.build.type") == "userdebug":
        c("debug", "adb root, then back to unprivileged adbd", _adb_root)
    c("debug", "processes a debugger can attach to (JDWP)", _jdwp)
    c("trace", "Perfetto 2 s trace", _trace)
    c("frida", "frida-server + frida-ps -U", lambda: _frida(have_root))
    c("mirror", "scrcpy reaches the device", _mirror)
    shutil.rmtree(TMP, ignore_errors=True)
    return c.report()
