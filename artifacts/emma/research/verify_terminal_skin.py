# SPDX-License-Identifier: MIT
"""Read-only checks for the generated CRT skin's native rendering contract."""
import hashlib
import json
import re
from pathlib import Path

from PIL import Image


def main():
    root = Path(__file__).resolve().parents[3]
    media = root / "SurvivorCompanion/42/media"
    source = (media / "lua/client/SCTerminalPresentation.lua").read_text(encoding="utf-8")
    match = re.search(r"P\.SKIN = \{ width = (\d+), height = (\d+)", source)
    assert match, "Missing frame geometry"
    dimensions = tuple(map(int, match.groups()))
    bounds = re.search(r"screenBounds = \{ ([\d, ]+) \}", source)
    assert bounds, "Missing measured screen opening"
    opening = tuple(map(int, bounds.group(1).split(",")))
    report = {}
    for name in ("frame", "glass"):
        path = media / f"textures/Terminal/Skin/crt-{name}.png"
        with Image.open(path) as image:
            assert image.size == dimensions, f"{name} dimensions do not match the UI source"
            item = {"dimensions": image.size, "mode": image.mode,
                    "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            if name == "frame":
                assert image.mode == "RGBA", "Frame must retain alpha"
                alpha = image.getchannel("A")
                hole = alpha.crop(opening)
                low, high = hole.getextrema()
                # Generated alpha has a few 1/255 fringe pixels; no visible fill.
                assert high <= 2, "Casing obscures the live display"
                assert alpha.getpixel((100, 496)) >= 250, "Missing physical bezel"
                item["opening_alpha_range"] = [low, high]
                item["zero_alpha_percent"] = hole.histogram()[0] / (hole.width * hole.height) * 100
            else:
                assert image.mode == "RGB", "Glass must be opaque"
                red, green, blue = image.split()
                spread = [max(pixel) - min(pixel) for pixel in image.getdata()]
                coloured = sum(value > 3 for value in spread) / len(spread)
                # Generated neutral artwork may have imperceptible RGB noise.
                assert max(spread) <= 8 and coloured < 0.001, "Glass must remain neutral under every phosphor tint"
                assert red.getextrema()[0] == 0 and red.getextrema()[1] < 100, "Glass obscures bright text"
                item["brightness_range"] = red.getextrema()
                item["maximum_channel_spread"] = max(spread)
                item["non_neutral_pixel_fraction"] = coloured
            report[name] = item
    print("TERMINAL_SKIN_ASSETS_PASS")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
