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
            if c == "info":
                device.info(args.label, args.bugreport)
            elif c == "trace":
                device.trace(args.seconds, args.name, args.config)
            elif c == "frida":
                device.frida_start() if args.action == "start" else device.frida_stop()
            elif c == "report":
                from . import adb, deploy
                adb.assert_one_device()
                deploy.report()
            return 0
    except Failure as e:
        say(f"error: {e}", "red")
        return 2
    except KeyboardInterrupt:
        say("interrupted", "yellow")
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
