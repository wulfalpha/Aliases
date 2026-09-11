#!/usr/bin/env python3
"""Compatibility launcher for running ``uv run makewindow.py``."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))

from pane.makewindow import main


if __name__ == "__main__":
    raise SystemExit(main())
