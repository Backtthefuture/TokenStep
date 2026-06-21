#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
ASSETS = ROOT / "assets"
ICONSET = ASSETS / "TokenStepIcon.iconset"
PNG = ASSETS / "TokenStepIcon.png"
ICNS = ASSETS / "TokenStepIcon.icns"
SOURCE_ICON = ASSETS / "TokenStepIconSource.png"


def selected_icon_source() -> Image.Image:
    if not SOURCE_ICON.exists():
        raise FileNotFoundError(SOURCE_ICON)
    return Image.open(SOURCE_ICON).convert("RGBA")


def render_png(width: int, height: int, output: Path) -> None:
    icon = selected_icon_source()
    icon.resize((width, height), Image.Resampling.LANCZOS).save(output)


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
