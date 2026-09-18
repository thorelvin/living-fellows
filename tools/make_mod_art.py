"""Generate the in-game mod poster and icon.

Committed so the art is reproducible rather than a binary someone has to trust.
Run it after changing the palette:

    python tools/make_mod_art.py

Design note: the Living Fellows poster is painted scene art. Imitating that with
drawing primitives would look worse than not trying, so this uses the mod's own
visual language instead -- the faceplate palette taken from the game's
ISSineWaveDisplay: black CRT, green phosphor, amber accent, dark metal case.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "PZRadioLink"

CASE = (43, 46, 52)
CASE_DARK = (22, 24, 28)
EDGE = (58, 62, 70)
CRT = (3, 7, 5)
PHOSPHOR = (0, 255, 65)
PHOSPHOR_DIM = (10, 122, 40)
ACCENT = (208, 138, 60)
BG_TOP = (26, 29, 34)
BG_BOTTOM = (13, 14, 17)


def font(name: str, size: int) -> ImageFont.ImageFont:
    for candidate in (rf"C:\Windows\Fonts\{name}", rf"C:\Windows\Fonts\consola.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def wave_points(width: int, amplitude: float, cycles: float, phase: float = 0.0):
    """The faceplate's scope, flattened to a single clean trace for artwork."""
    return [(x, amplitude * math.sin(phase + (x / width) * cycles * 2 * math.pi))
            for x in range(width)]


def draw_glow(base: Image.Image, layer: Image.Image, radius: int) -> Image.Image:
    glow = layer.filter(ImageFilter.GaussianBlur(radius))
    return Image.alpha_composite(base, glow)


def make_poster(size: int = 256) -> Image.Image:
    img = Image.new("RGBA", (size, size), BG_BOTTOM + (255,))
    draw = ImageDraw.Draw(img)

    # Background gradient.
    for y in range(size):
        t = y / size
        col = tuple(int(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3))
        draw.line([(0, y), (size, y)], fill=col + (255,))

    # Faint vertical grain. ImageDraw REPLACES pixels on an RGBA image rather
    # than blending, so drawing a low-alpha colour directly leaves transparent
    # pixels that turn into hard white stripes on convert("RGB"). It has to go
    # through a separate layer and be composited.
    grain = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(grain)
    for x in range(0, size, 3):
        gd.line([(x, 0), (x, size)], fill=(255, 255, 255, 6))
    img = Image.alpha_composite(img, grain)
    draw = ImageDraw.Draw(img)

    # --- the handset: a rounded case with a CRT window ----------------------
    pw, ph = 128, 172
    px, py = (size - pw) // 2, 16
    draw.rounded_rectangle([px, py, px + pw, py + ph], radius=16,
                           fill=CASE, outline=EDGE, width=2)
    draw.rounded_rectangle([px + 3, py + 3, px + pw - 3, py + 40], radius=7,
                           fill=(30, 33, 38))  # speaker area

    # speaker grille
    for row in range(4):
        for col in range(14):
            cx = px + 12 + col * 8
            cy = py + 12 + row * 7
            draw.ellipse([cx, cy, cx + 3, cy + 3], fill=(18, 20, 23))

    # CRT window
    sx0, sy0 = px + 11, py + 46
    sx1, sy1 = px + pw - 11, py + 112
    draw.rounded_rectangle([sx0, sy0, sx1, sy1], radius=5, fill=CRT,
                           outline=(11, 15, 12), width=1)

    screen = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(screen)

    # grid, as the game draws it
    for i in range(1, 8):
        x = sx0 + (sx1 - sx0) * i // 8
        sd.line([(x, sy0 + 2), (x, sy1 - 2)], fill=(0, 77, 0, 255))
    sd.line([(sx0 + 2, (sy0 + sy1) // 2 + 14), (sx1 - 2, (sy0 + sy1) // 2 + 14)],
            fill=(0, 77, 0, 255))

    readout = font("consolab.ttf", 27)
    sd.text((sx0 + 7, sy0 + 6), "101.2", font=readout, fill=PHOSPHOR + (255,))
    label = font("consola.ttf", 10)
    label_x = sx0 + 7 + sd.textlength("101.2", font=readout) + 4
    sd.text((label_x, sy0 + 17), "MHz", font=label, fill=PHOSPHOR_DIM + (255,))

    mid = sy1 - 18
    for x, y in wave_points(sx1 - sx0 - 8, 9.0, 3.2):
        sd.ellipse([sx0 + 4 + x - 1, mid + y - 1, sx0 + 4 + x + 1, mid + y + 1],
                   fill=PHOSPHOR + (255,))

    img = draw_glow(img, screen, 3)
    img.alpha_composite(screen)
    draw = ImageDraw.Draw(img)

    # --- tuning dial, then the knob below it (they must not overlap) --------
    dy = py + 120
    draw.rounded_rectangle([px + 11, dy, px + pw - 11, dy + 20], radius=4,
                           fill=(16, 18, 22), outline=(12, 14, 17))
    for i in range(21):
        x = px + 16 + i * 5
        tall = i % 5 == 0
        draw.line([(x, dy + 16), (x, dy + (5 if tall else 10))],
                  fill=(120, 128, 138) if tall else (70, 76, 84))
    draw.line([(px + pw // 2, dy + 3), (px + pw // 2, dy + 17)],
              fill=(255, 122, 85), width=2)

    kx, ky, kr = px + pw // 2, py + 152, 10
    draw.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=ACCENT,
                 outline=(120, 78, 32), width=1)
    draw.ellipse([kx - 4, ky - 5, kx + 1, ky], fill=(233, 176, 115))
    draw.line([(kx, ky - kr + 2), (kx, ky - kr + 5)], fill=(60, 38, 16), width=2)

    # --- signal arcs, kept clear of the image edge --------------------------
    arcs = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ad = ImageDraw.Draw(arcs)
    ox, oy = px + pw - 10, py + 12
    for i, r in enumerate((17, 29, 41)):
        alpha = 230 - i * 62
        ad.arc([ox - r, oy - r, ox + r, oy + r], start=282, end=350,
               fill=ACCENT + (alpha,), width=3)
    img = draw_glow(img, arcs, 2)
    img.alpha_composite(arcs)
    draw = ImageDraw.Draw(img)

    # --- title, in the gap left below the handset ---------------------------
    title = font("seguisb.ttf", 16)
    text = "PZ RADIO LINK"
    tw = draw.textlength(text, font=title)
    draw.text(((size - tw) / 2, py + ph + 12), text, font=title,
              fill=(214, 219, 226, 255))

    sub = font("segoeui.ttf", 10)
    text2 = "your radio, on your phone"
    tw2 = draw.textlength(text2, font=sub)
    draw.text(((size - tw2) / 2, py + ph + 33), text2, font=sub,
              fill=(125, 132, 143, 255))

    return img.convert("RGB")


def make_icon(size: int = 64) -> Image.Image:
    """Readable at 64px means three shapes, not a scene."""
    scale = 8
    big = size * scale
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    draw.rounded_rectangle([0, 0, big - 1, big - 1], radius=12 * scale,
                           fill=CASE, outline=EDGE, width=1 * scale)

    # screen
    m = 9 * scale
    draw.rounded_rectangle([m, 11 * scale, big - m, 34 * scale],
                           radius=3 * scale, fill=CRT)
    bar = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(bar)
    bd.rounded_rectangle([13 * scale, 18 * scale, big - 17 * scale, 26 * scale],
                         radius=1 * scale, fill=PHOSPHOR + (255,))
    img = Image.alpha_composite(img, bar.filter(ImageFilter.GaussianBlur(2 * scale)))
    img.alpha_composite(bar)
    draw = ImageDraw.Draw(img)

    # knob
    cx, cy, r = big // 2, 47 * scale, 8 * scale
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT)

    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    poster = make_poster()
    icon = make_icon()
    for folder in (MOD, MOD / "42"):
        folder.mkdir(parents=True, exist_ok=True)
        poster.save(folder / "poster.png")
        icon.save(folder / "icon.png")
        print(f"wrote {folder / 'poster.png'} and {folder / 'icon.png'}")


if __name__ == "__main__":
    main()
