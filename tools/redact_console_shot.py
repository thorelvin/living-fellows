"""Redact the pairing key out of a host-console screenshot before publishing it.

The console prints a scannable QR and the same URL in plain text, both of which
carry the live pairing key. The key is persistent, so a screenshot committed to
a public repository would publish a working credential for anyone on that LAN.

This replaces the QR with one encoding a placeholder URL and paints the plain
text line over with the same placeholder, leaving the rest of the capture as it
was. Run it on any new console screenshot before adding it to the docs.

    python tools/redact_console_shot.py <input.png> <output.png>
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "host"))

import pzrl_qr  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402

PLACEHOLDER = "http://192.168.1.50:8777/?t=xxxxxxxxxxxxxxxx"
BRIGHT = 600  # sum of RGB above which a console pixel counts as "lit"


def find_qr_box(image: Image.Image) -> tuple[int, int, int, int]:
    """The QR is the one large solid-bright rectangle in the capture."""
    width, height = image.size
    px = image.load()

    # Measured on a real capture: rows inside the QR block have roughly 60-180
    # lit samples out of 545, while the brightest text row has 17. Anything well
    # above the text band and well below the minimum QR row separates them.
    samples = len(range(0, width, 2))
    threshold = samples * 0.06

    rows = [sum(1 for x in range(0, width, 2) if sum(px[x, y]) > BRIGHT)
            for y in range(height)]

    best = run_start = None
    start = None
    for y, lit in enumerate(rows + [0]):
        if lit > threshold:
            if start is None:
                start = y
        elif start is not None:
            if best is None or (y - start) > best:
                best, run_start = y - start, start
            start = None
    if best is None or best < 40:
        raise SystemExit("no QR block found in this image")
    top, bottom = run_start, run_start + best

    col_samples = len(range(top, bottom, 2))
    col_threshold = col_samples * 0.06
    cols = [sum(1 for y in range(top, bottom, 2) if sum(px[x, y]) > BRIGHT)
            for x in range(width)]
    left = next(x for x, lit in enumerate(cols) if lit > col_threshold)
    right = len(cols) - next(i for i, lit in enumerate(reversed(cols))
                             if lit > col_threshold)
    return left, top, right, bottom


def render_qr(size: int) -> Image.Image:
    matrix = pzrl_qr.encode(PLACEHOLDER)
    modules = len(matrix)
    quiet = 4
    total = modules + quiet * 2
    scale = max(1, size // total)
    img = Image.new("RGB", (total * scale, total * scale), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    for r in range(modules):
        for c in range(modules):
            if matrix[r][c]:
                x0 = (c + quiet) * scale
                y0 = (r + quiet) * scale
                draw.rectangle([x0, y0, x0 + scale - 1, y0 + scale - 1], fill=(0, 0, 0))
    return img.resize((size, size), Image.NEAREST)


def mono_font(size: int) -> ImageFont.ImageFont:
    for candidate in (r"C:\Windows\Fonts\consola.ttf", r"C:\Windows\Fonts\cour.ttf"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    source, target = Path(sys.argv[1]), Path(sys.argv[2])
    image = Image.open(source).convert("RGB")

    left, top, right, bottom = find_qr_box(image)
    side = min(right - left, bottom - top)
    print(f"QR block at ({left},{top})-({right},{bottom}), pasting {side}px replacement")
    # Clear the whole original block first: the replacement is square but the
    # captured block may not be, and any uncovered strip keeps original pixels.
    ImageDraw.Draw(image).rectangle([left, top, right, bottom], fill=(255, 255, 255))
    image.paste(render_qr(side), (left + (right - left - side) // 2, top))

    # The three banner lines sit directly under the QR. Paint that block out and
    # rewrite it, so the plaintext copy of the key goes with it.
    draw = ImageDraw.Draw(image)
    width, height = image.size
    font = mono_font(15)

    lines = [
        "  Scan with your phone's camera, on the same Wi-Fi.",
        "  Then use your browser's Add to Home Screen for a full-screen app.",
        f"  {PLACEHOLDER}",
    ]
    block_top = bottom + 16
    block_bottom = block_top + len(lines) * 19 + 8
    draw.rectangle([0, block_top, width, block_bottom], fill=(12, 12, 12))
    for i, text in enumerate(lines):
        draw.text((8, block_top + 6 + i * 19), text, font=font, fill=(204, 204, 204))
    replaced = len(lines)

    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target)
    print(f"rewrote {replaced} banner lines -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
