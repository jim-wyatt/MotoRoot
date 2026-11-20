"""The aosp-academy command line: aosp-academy <command> [options]   (aosp-academy --help)."""
from __future__ import annotations

import argparse
import sys

from .core import Failure, say


def _fetch_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--host", help="build node address (saved with --save)")
    p.add_argument("--user", help="build node SSH user")
    p.add_argument("--repo", help="the repository's path on the build node")
    p.add_argument("--port", type=int, help="SSH port, if not 22")
    p.add_argument("--save", action="store_true", help="keep these in work/remote-build.json")
    p.add_argument("--streams", type=int, default=8, choices=range(1, 33), metavar="N", help="parallel connections for the parts (default 8)")


def parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="aosp-academy", description="Bootstrap and maintain the XT2617V development device.")
    sub = ap.add_subparsers(dest="command", required=True, metavar="<command>")

    p = sub.add_parser("fetch", help="copy the newest verified image from the build node")
    _fetch_args(p)
    p.add_argument("--check", action="store_true", help="only report whether a newer image is waiting")

    p = sub.add_parser("deploy", help="fetch, install, boot and verify the newest image on the phone")
    _fetch_args(p)
    p.add_argument("--no-fetch", action="store_true", help="install the image already in work/device-tools/gsi/own")
    p.add_argument("--single-boot", action="store_true", help="boot it once only (default: persistent)")
    p.add_argument("--keep-image", action="store_true", help="keep the local copy after installing")
    p.add_argument("--skip-device-test", action="store_true", help="leave out the device test at the end")
    p.add_argument("--userdata-gib", type=int, default=24, help="the image's data partition (default 24)")
    p.add_argument("-y", "--yes", action="store_true", help="don't ask before replacing the installed image")
    p.check = False

    p = sub.add_parser("gsi", help="DSU: install, boot, go back to stock, discard, status")
    p.add_argument("action", choices=["status", "download", "install", "boot", "stock", "discard"])
    p.add_argument("--image", help="your own system.img (or a zip with one) instead of Google's pinned GSI")
    p.add_argument("--userdata-gib", type=int, default=8)
    p.add_argument("--single-boot", action="store_true", help="boot: once only (default: persistent)")
    p.add_argument("--accept-google-gsi-terms", action="store_true", help="download: after reading Google's GSI terms")

    p = sub.add_parser("device", help="work with the connected phone")
    dsub = p.add_subparsers(dest="device_command", required=True, metavar="<what>")
    t = dsub.add_parser("test", help="exercise every development workflow on the phone")
    t.add_argument("--skip", default="", help="areas to leave out, comma-separated (e.g. frida,mirror)")
    s = dsub.add_parser("settings", help="the development-target settings (stock system)")
    s.add_argument("--reset", action="store_true", help="put the stock values back")
    i = dsub.add_parser("info", help="hardware and software inventory into work/device-info")
    i.add_argument("--label")
    i.add_argument("--bugreport", action="store_true")
    r = dsub.add_parser("trace", help="record a Perfetto trace into work/traces")
    r.add_argument("--seconds", type=int, default=10)
    r.add_argument("--name")
    r.add_argument("--config", help="your own Perfetto text config")
    f = dsub.add_parser("frida", help="start or stop frida-server on the phone (root)")
    f.add_argument("action", choices=["start", "stop"])
    dsub.add_parser("report", help="what the running image sets (as at the end of deploy)")
    lg = dsub.add_parser("logs", help="logcat into work/logs, everything or one app")
    lg.add_argument("--package", help="only this app (by its UID, so restarts are followed)")
    lg.add_argument("--follow", action="store_true", help="stream until Ctrl-C (default: dump what the buffers hold)")
    lg.add_argument("--clear", action="store_true", help="clear the buffers first")
    lg.add_argument("--buffers", default="main,system,crash", help="logcat buffers (default main,system,crash)")
    lg.add_argument("--name", help="a label for the file name")
    br = dsub.add_parser("bugreport", help="a full Android bug report into work/bugreports")
    br.add_argument("--name", help="a label for the file name")
    tr = dsub.add_parser("try", help="run the repository's first-boot script on the running image, without a build")
    tr.add_argument("--rerun", action="store_true", help="clear the first-boot state and run it now, as on a fresh install")
    tr.add_argument("--undo", action="store_true", help="put the built-in script back (a reboot does too)")
    mi = dsub.add_parser("mirror", help="mirror and control the phone with scrcpy", add_help=False)
    mi.add_argument("rest", nargs=argparse.REMAINDER, help="passed to scrcpy")

    p = sub.add_parser("setup", help="install and verify the workstation (idempotent)")
    p.add_argument("--studio", action="store_true", help="also install Android Studio (Windows)")
    p.add_argument("--accept-sdk-licenses", action="store_true", help="accept the Android SDK licenses non-interactively, after reading them")
    p.add_argument("--skip-system", action="store_true", help="leave out winget / the system package check")
    p.add_argument("--skip-sdk", action="store_true")
    p.add_argument("--skip-inputs", action="store_true", help="leave out the device procedure inputs and device tools")
    sub.add_parser("check", help="test the workstation end to end (never touches the phone)")
    p = sub.add_parser("new-app", help="create an Android app project set up for this phone")
    p.add_argument("dest", help="the new project's folder (must not exist, or be empty)")
    p.add_argument("--package", required=True, help="application id and Kotlin package, e.g. com.example.myapp")
    p.add_argument("--name", help="the app's name (default: the folder name)")
    p.add_argument("--build", action="store_true", help="also build the debug APK")
    p.add_argument("--test", action="store_true", help="also build and run the instrumented test on the phone")
    p = sub.add_parser("env", help="print the environment for a shell (pwsh: aosp-academy env | iex)")
    p.add_argument("--shell", choices=["pwsh", "cmd", "bash"])
    sub.add_parser("shell", help="open a shell with the pinned tools on PATH")
    p = sub.add_parser("docs", help="preview (serve) or build the documentation site")
    p.add_argument("action", nargs="?", default="serve", choices=["serve", "build"])
    for name, what in (("apktool", "the pinned apktool"), ("d8", "the pinned R8's D8")):
        p = sub.add_parser(name, help=f"run {what}", add_help=False)
        p.add_argument("rest", nargs=argparse.REMAINDER)
    sub.add_parser("adb-wifi", help="connect adb over Wi-Fi")

    p = sub.add_parser("stock", help="stock-system preparation artifacts")
    ssub = p.add_subparsers(dest="stock_command", required=True, metavar="<what>")
    b = ssub.add_parser("build", help="rebuild the helpers and modules and compare them with stock/")
    b.add_argument("--promote", action="store_true", help="copy changed artifacts over the committed ones")
    m = ssub.add_parser("magisk-image", help="make a Magisk-patched init_boot image file (never flashes)")
    m.add_argument("stock_image", help="your own init_boot_a backup (work/private-backups/...)")

    p = sub.add_parser("image", help="build node: inputs, setup, sync, apply, build (Linux)")
    p.add_argument("action", choices=["inputs", "setup", "sync", "apply", "build", "verify", "after-sync"])
    return ap


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.command == "fetch":
            from . import fetch
            return fetch.fetch(args)
        if args.command == "deploy":
            from . import deploy
            args.check = False
            return deploy.deploy(args)
        if args.command == "gsi":
            from . import gsi
            return gsi.main(args)
        if args.command == "device":
            from . import device
            c = args.device_command
            if c == "test":
                from . import devtest
                return devtest.run_tests({s.strip() for s in args.skip.split(",") if s.strip()})
            if c == "settings":
                return device.settings(args.reset)
            if c == "logs":
                device.logs(args.package, args.follow, args.clear, args.buffers, args.name)
                return 0
            if c == "bugreport":
                device.bugreport(args.name)
                return 0
            if c == "try":
                return device.try_firstboot(args.rerun, args.undo)
            if c == "info":
                device.info(args.label, args.bugreport)
            elif c == "trace":
                device.trace(args.seconds, args.name, args.config)
            elif c == "frida":
                device.frida_start() if args.action == "start" else device.frida_stop()
            elif c == "mirror":
                import os
                import subprocess
                from . import tools
                return subprocess.call(["scrcpy", *args.rest], env={**os.environ, **tools.environment()})
            elif c == "report":
                from . import adb, deploy
                adb.assert_one_device()
                deploy.report()
            return 0
        if args.command == "setup":
            from . import setup
            return setup.setup(args)
        if args.command == "new-app":
            from . import newapp
            return newapp.new_app(args.dest, args.package, args.name, args.build, args.test)
        if args.command == "check":
            from . import check
            return check.run_checks()
        if args.command in ("env", "shell", "docs", "apktool", "d8", "adb-wifi"):
            from . import env
            if args.command == "env":
                return env.env(args.shell)
            if args.command == "shell":
                return env.open_shell()
            if args.command == "docs":
                return env.docs(args.action)
            if args.command == "adb-wifi":
                return env.adb_wifi()
            return env.java_tool(args.command, args.rest)
        if args.command == "stock":
            from . import stock
            if args.stock_command == "build":
                r = stock.build(args.promote)
                return 0 if args.promote else sum(1 for x in r if not x[1])
            stock.magisk_image(args.stock_image)
            return 0
        if args.command == "image":
            from . import image
            return image.main(args.action)
    except Failure as e:
        say(f"error: {e}", "red")
        return 2
    except KeyboardInterrupt:
        say("interrupted", "yellow")
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
