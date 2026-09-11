#!/usr/bin/env python3
"""Compatibility launcher for running ``uv run pane.py``."""

import sys
from pathlib import Path

_PACKAGE_DIR = Path(__file__).resolve().parent / "src" / "pane"
if __name__ == "pane":
    # Keep this legacy launcher importable when the repository root is first on
    # sys.path; otherwise it would shadow the real src/pane package.
    __path__ = [str(_PACKAGE_DIR)]
else:
    sys.path.insert(0, str(_PACKAGE_DIR.parent))

from pane.app import main

__all__ = ["main"]


if __name__ == "__main__":
    main()
