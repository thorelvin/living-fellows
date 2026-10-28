# SPDX-License-Identifier: MIT
"""Offline QA contact sheets; original in-game screenshots remain untouched.

Pillow/numpy are development dependencies, never part of the game payload.
Machado et al. (2009), severity 100, linear RGB; supplementary matrices checked
against the authors' implementation in colorspacious:
https://raw.githubusercontent.com/njsmith/colorspacious/master/colorspacious/cvd.py
https://doi.org/10.1109/TVCG.2009.113
"""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image, ImageDraw

MATRICES = {
    "protanopia": [[.152286, 1.052583, -.204868], [.114503, .786281, .099216],
                   [-.003882, -.048116, 1.051998]],
    "deuteranopia": [[.367322, .860646, -.227968], [.280085, .672501, .047413],
                     [-.011820, .042940, .968881]],
    "tritanopia": [[1.255528, -.076749, -.178779], [-.078411, .930809, .147602],
                   [.004733, .691367, .303900]],
}
PALETTE = ["F2B8B8", "F2D0AE", "E6DCA3", "CFDFA4", "B9DFAF", "AEE0CA",
           "A9DDE0", "B5D6F2", "C0C9F2", "D3C2EF", "E0BCE4", "EDBED4"]


def linear(rgb):
    return np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)


def simulate(image, matrix):
    values = linear(np.asarray(image.convert("RGB")) / 255.) @ np.asarray(matrix).T
    values = np.clip(values, 0, 1)
    encoded = np.where(values <= .0031308, 12.92 * values, 1.055 * values ** (1 / 2.4) - .055)
    return Image.fromarray(np.round(np.clip(encoded, 0, 1) * 255).astype("uint8"))


def caption(image):
    # The fixture's first person is Tess, automatically assigned mint. This
    # detects native glyph pixels rather than redrawing/recolouring the text.
    rgb = np.asarray(image.convert("RGB")).astype(int)
    mask = np.max(np.abs(rgb - [174, 224, 202]), axis=2) <= 1
    mask[:70] = False
    mask[-80:] = False
    mask[:, :180] = False
    yy, xx = np.where(mask)
    assert len(xx) >= 25, "native mint caption pixels missing"
    box = (max(0, int(xx.min()) - 12), max(0, int(yy.min()) - 20),
           min(image.width, int(xx.max()) + 12), min(image.height, int(yy.max()) + 70))
    return image.crop(box), len(xx)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("captures", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    audit = {}
    for kind in ("short", "multiline", "wrapped"):
        sheet = Image.new("RGB", (740 * 2, 260 * 4), "#202020")
        draw = ImageDraw.Draw(sheet)
        for index, zoom in enumerate((50, 75, 100, 125, 150, 175, 200)):
            path = args.captures / f"colour-zoom-{zoom:03d}-{kind}.png"
            crop, count = caption(Image.open(path))
            assert crop.width <= 720 and crop.height <= 220, "unscaled crop exceeds its cell"
            x, y = index % 2 * 740, index // 2 * 260
            draw.text((x + 12, y + 4), f"{zoom}% / {kind} / unscaled native crop", fill="white")
            sheet.paste(crop, (x + 12, y + 26))
            audit[path.name] = {"native_mint_pixels": count, "crop_size": crop.size}
        sheet.save(args.output / f"zoom-{kind}.png")
    for when in ("early", "late"):
        _, count = caption(Image.open(args.captures / f"colour-retained-{when}.png"))
        audit[when] = {"native_mint_pixels": count}

    for name in ("colour-night", "colour-bright-floor"):
        # Native hearing/room attenuation may deliberately grey these captions.
        # Retain that behaviour and inspect the complete originals visually.
        rgb = np.asarray(Image.open(args.captures / (name + ".png")).convert("RGB")).astype(int)
        count = int((np.max(np.abs(rgb - [174, 224, 202]), axis=2) <= 1).sum())
        audit[name] = {"native_mint_pixels": count, "review": "complete original; native attenuation retained"}
    four = np.asarray(Image.open(args.captures / "colour-four-speakers.png").convert("RGB")).astype(int)
    counts = {}
    for key, colour in {"mint": [174, 224, 202], "pink": [237, 190, 212],
                        "sand": [230, 220, 163], "periwinkle": [192, 201, 242]}.items():
        mask = np.max(np.abs(four - colour), axis=2) <= 1
        mask[:70] = False
        mask[-80:] = False
        counts[key] = int(mask.sum())
        assert counts[key] >= 25, "four-speaker native colour missing: " + key
    audit["four_speakers"] = counts

    original = Image.open(args.captures / "colour-four-speakers.png").convert("RGB")
    original = original.crop((250, 100, 1200, 650))
    sheet = Image.new("RGB", (original.width * 2, (original.height + 28) * 2), "#202020")
    draw = ImageDraw.Draw(sheet)
    variants = [("original", original)] + [(name, simulate(original, matrix))
                                             for name, matrix in MATRICES.items()]
    for i, (name, image) in enumerate(variants):
        x, y = i % 2 * original.width, i // 2 * (original.height + 28)
        draw.text((x + 10, y + 5), name + " (simulation)" if i else name, fill="white")
        sheet.paste(image, (x, y + 28))
    sheet.save(args.output / "colour-vision-review.png")
    palette = np.asarray([[int(value[i:i+2], 16) / 255 for i in (0, 2, 4)] for value in PALETTE])
    audit["minimum_contrast_against_black"] = float(((linear(palette) @ [.2126, .7152, .0722]) + .05).min() / .05)
    audit["limits"] = "CVD simulations aid review, not clinical/user validation. Hues can converge; names/position and White text remain available."
    (args.output / "audit.json").write_text(json.dumps(audit, indent=2) + "\n", encoding="utf-8")
    print("SPEECH_COLOUR_VISUAL_AUDIT_PASS zoom_samples=21 native_early_late=true simulations=3")


if __name__ == "__main__":
    main()
