"""aosp-academy env / shell / docs / apktool / d8 / adb-wifi: the workstation's tools at hand.

  env [--shell pwsh|cmd|bash]   print the statements that put the pinned tools on a shell's PATH
                                (pwsh:  aosp-academy env | Invoke-Expression;
                                 bash:  eval "$(./aosp-academy env --shell bash)")
  shell                         open a shell with that environment, at the repository root
  docs [serve|build]            preview or build the documentation site
  apktool ... / d8 ...          the pinned apktool and R8's D8
  adb-wifi                      connect adb over Wi-Fi (reads the phone's address over USB)

The pinned platform-tools come first on PATH, so a bare `adb` is the tested version. Close Android
Studio during device work: it runs its own, newer adb server, and two versions fight over the phone.
"""
from __future__ import annotations

import ipaddress
import os
import re
import shutil
import socket
import subprocess
import sys

from . import adb, tools
from .core import ROOT, WINDOWS, Failure, run, say, warn


def default_shell() -> str:
    if WINDOWS:
        return "pwsh" if shutil.which("pwsh") else "cmd"
    return "bash"


def env(shell: str | None) -> int:
    shell = shell or default_shell()
    for k, v in tools.environment().items():
        if shell == "pwsh":
            print(f"$env:{k} = '{v.replace(chr(39), chr(39) * 2)}'")
        elif shell == "cmd":
            print(f'set "{k}={v}"')
        else:
            print(f"export {k}='{v.replace(chr(39), chr(39) + chr(92) + chr(39) + chr(39))}'")
    return 0


def open_shell() -> int:
    e = {**os.environ, **tools.environment(), "AOSP_ACADEMY_SHELL": "1"}
    sh = default_shell()
    say("aosp-academy shell: pinned adb, SDK, NDK, JDK, jadx and frida on PATH. 'exit' leaves it.", "cyan")
    if WINDOWS:
        args = ["pwsh", "-NoLogo"] if sh == "pwsh" else ["cmd", "/k", "prompt (aosp-academy) $P$G"]
    else:
        args = [os.environ.get("SHELL", "bash")]
    return subprocess.call(args, env=e, cwd=ROOT)


def docs(action: str) -> int:
    z = tools.venv_exe(".venv-docs", "zensical")
    if not z.exists():
        raise Failure("The docs venv is missing. Run: aosp-academy setup")
    args = [z, "serve", "-f", ROOT / "zensical.toml"] if action == "serve" else [z, "build", "--strict", "--clean", "-f", ROOT / "zensical.toml"]
    return subprocess.call([str(a) for a in args], cwd=ROOT)


def java_tool(kind: str, rest: list[str]) -> int:
    jh = tools.java_home()
    if not jh:
        raise Failure("No JDK found. Run: aosp-academy setup")
    java = jh / "bin" / ("java.exe" if WINDOWS else "java")
    if kind == "apktool":
        return subprocess.call([str(java), "-jar", str(tools.jar("apktool")), *rest])
    return subprocess.call([str(java), "-cp", str(tools.jar("r8-")), "com.android.tools.r8.D8", *rest])


def adb_wifi() -> int:
    """Connect adb to the phone's Wi-Fi address, port 5555 (dev_adb_tcp on stock, or 'adb tcpip 5555')."""
    adb.assert_one_device()
    m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)/(\d+)", adb.sh("ip -4 -o addr show wlan0"))
    if not m:
        raise Failure("Could not read the phone's Wi-Fi address over USB (cable in, Wi-Fi on?).")
    phone = ipaddress.ip_interface(f"{m[1]}/{m[2]}")
    # A PC on another subnet is the usual reason for a silent timeout, so say so instead of waiting.
    mine = {ai[4][0] for ai in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)}
    if not any(ipaddress.ip_address(a) in phone.network for a in mine):
        warn(f"The phone is on {phone.network}, this PC on {', '.join(sorted(mine))}: different networks. Join the same Wi-Fi and retry.")
        return 1
    print(adb.adb("connect", f"{phone.ip}:5555", check=False))
    return 0
