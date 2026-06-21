#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "TokenStepIcon.iconset"
PNG = ASSETS / "TokenStepIcon.png"
ICNS = ASSETS / "TokenStepIcon.icns"
SOURCE_SVG = REPO_ROOT / "brand/logo-concepts/final-candidates/svg/07-step-arc-app-icon.svg"


def render_png(width: int, height: int, output: Path) -> None:
    subprocess.run(
        [
            "rsvg-convert",
            "-w",
            str(width),
            "-h",
            str(height),
            str(SOURCE_SVG),
            "-o",
            str(output),
        ],
        check=True,
    )


def save_iconset() -> None:
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True, exist_ok=True)

    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]

    for size, name in sizes:
        render_png(size, size, ICONSET / name)


def main() -> None:
    if not SOURCE_SVG.exists():
        raise FileNotFoundError(SOURCE_SVG)

    ASSETS.mkdir(parents=True, exist_ok=True)
    render_png(1024, 1024, PNG)
    save_iconset()

    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(PNG)
    print(ICNS)


if __name__ == "__main__":
    main()
