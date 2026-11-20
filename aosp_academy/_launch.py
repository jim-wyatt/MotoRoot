"""Launcher target: puts this checkout on sys.path and runs the CLI.

The launchers run Python isolated (-I), so a stray module in the current directory or PYTHONPATH
can't shadow the standard library or this package.
"""
import sys
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit("aosp-academy needs Python 3.11 or newer.")
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from aosp_academy.cli import main  # noqa: E402

sys.exit(main())
