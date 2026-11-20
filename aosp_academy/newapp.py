"""aosp-academy new-app: a new Android app project, set up for this phone.

The template (aosp_academy/templates/app) is a minimal Kotlin app with one instrumented test,
on the versions toolchain.json pins under appTemplate: compileSdk/targetSdk, the build-tools,
the Android Gradle Plugin and Gradle. The new project gets its own Gradle wrapper, pinned to the
same Gradle with its SHA-256, so from then on it builds anywhere with ANDROID_HOME and a JDK, with
or without this repository.

    aosp-academy new-app ../my-app --package com.example.myapp
    aosp-academy new-app ../my-app --package com.example.myapp --test    (also builds and runs the test on the phone)
"""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

from . import tools
from .core import WINDOWS, Failure, get_pinned, ok, pins, run, say, step

TEMPLATE = Path(__file__).resolve().parent / "templates" / "app"
PACKAGE = re.compile(r"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$")
# Kotlin keywords can't be package segments without backticks; refuse them rather than generate broken code.
KEYWORDS = {"as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if", "in", "interface", "is",
            "null", "object", "package", "return", "super", "this", "throw", "true", "try", "typealias", "typeof",
            "val", "var", "when", "while"}


def gradle() -> Path:
    """The pinned Gradle distribution (work/tools/gradle), downloaded and checked on first use."""
    t = pins()["appTemplate"]
    a = next(a for a in pins()["archives"] if a["extractTo"] == "gradle")
    exe = tools.TOOLS / "gradle" / f"gradle-{t['gradle']}" / "bin" / ("gradle.bat" if WINDOWS else "gradle")
    stamp = tools.TOOLS / "gradle" / ".pinned-sha256"
    if not (exe.exists() and stamp.exists() and stamp.read_text().strip() == a["sha256"]):
        from .setup import _unzip
        zp = tools.CACHE / a["name"]
        get_pinned(a["url"], zp, a["sha256"])
        shutil.rmtree(tools.TOOLS / "gradle", ignore_errors=True)
        _unzip(zp, tools.TOOLS / "gradle")
        stamp.write_text(a["sha256"] + "\n")
    if not WINDOWS:
        exe.chmod(0o755)
    return exe


def render(dest: Path, package: str, name: str) -> list[Path]:
    """Copy the template into dest, filling in the placeholders. Returns the files written."""
    values = {**{k: str(v) for k, v in pins()["appTemplate"].items() if not k.startswith("_")}, "package": package, "name": name}
    written = []
    for src in sorted(p for p in TEMPLATE.rglob("*") if p.is_file()):
        rel = src.relative_to(TEMPLATE).as_posix()
        rel = rel.replace("PACKAGE", package.replace(".", "/"))
        if rel == "gitignore":
            rel = ".gitignore"  # stored without the dot, so this repository's own ignore rules don't apply to it
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        text = src.read_text(encoding="utf-8")
        for k, v in values.items():
            text = text.replace("{{" + k + "}}", v)
        if "{{" in text:
            raise Failure(f"template {rel}: an unfilled placeholder ({text[text.index('{{'):][:30]})")
        out.write_bytes(text.encode("utf-8"))
        written.append(out)
    return written


def new_app(dest: str, package: str, name: str | None, build: bool, test: bool) -> int:
    target = Path(dest).expanduser().resolve()
    if not PACKAGE.match(package) or any(seg in KEYWORDS for seg in package.split(".")):
        raise Failure(f"'{package}' isn't a usable package name: lower-case segments separated by dots, "
                      "at least two, none a Kotlin keyword (e.g. com.example.myapp)")
    if target.exists() and any(target.iterdir()):
        raise Failure(f"{target} exists and isn't empty; give a new folder.")
    name = name or target.name
    env = {**os.environ, **tools.environment()}
    if "ANDROID_HOME" not in env or "JAVA_HOME" not in env:
        raise Failure("No Android SDK or JDK found; run aosp-academy setup first.")

    step(f"New app {package} in {target}")
    files = render(target, package, name)
    ok(f"{len(files)} files from the template")

    t = pins()["appTemplate"]
    g = gradle()
    run([g, "--quiet", "wrapper", "--gradle-version", t["gradle"], "--distribution-type", "bin",
         "--gradle-distribution-sha256-sum", t["gradleSha256"]], cwd=target, env=env, capture=True)
    ok(f"Gradle wrapper {t['gradle']} (distribution SHA-256 pinned in gradle/wrapper/gradle-wrapper.properties)")

    gradlew = target / ("gradlew.bat" if WINDOWS else "gradlew")
    if build or test:
        step("Building (./gradlew assembleDebug)")
        run([gradlew, "assembleDebug"], cwd=target, env=env)
        ok(f"{target / 'app/build/outputs/apk/debug/app-debug.apk'}")
    if test:
        from . import adb
        adb.assert_one_device()
        step("Instrumented test on the phone (./gradlew connectedDebugAndroidTest)")
        # The test task installs the app and its test APK, runs them, then uninstalls both.
        run([gradlew, "connectedDebugAndroidTest"], cwd=target, env=env)
        ok("The test passed on the phone (both APKs uninstalled again)")

    say(f"\nNext: cd {target}; git init; open the folder in Android Studio, or ./gradlew installDebug", "cyan")
    return 0
