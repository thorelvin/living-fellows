"""Printable one-page code wheel, read from the live Lua mapping."""
from pathlib import Path
import html
import json
import math
import re

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "SurvivorCompanion/42/media/lua/client/SCTerminalLockWheelData.lua"


def mapping():
    source = SOURCE.read_text(encoding="utf-8-sig")
    return {
        "outer": re.search(r'outer="([A-Z]+)"', source).group(1),
        "inner": re.search(r'inner="([A-Z]+)"', source).group(1),
        "windows": [int(x) for x in re.search(r'windows=\{([0-9,]+)\}', source).group(1).split(",")],
        "markers": [{"name": n, "position": int(p)} for n, p in re.findall(r'name="([A-Z]+)",position=(\d+)', source)],
    }


def generate():
    data = mapping()
    assert len(set(data["outer"])) == len(set(data["inner"])) == 26
    lines = ['<svg xmlns="http://www.w3.org/2000/svg" width="210mm" height="297mm" viewBox="0 0 794 1123">',
             '<title>Larchfield account recovery wheel</title>',
             '<desc>Cut out both discs, place the smaller on top and pin their centres. Align the named symbol to the outer letter, then read the inner letter at the numbered window.</desc>',
             '<metadata id="wheel-mapping">' + html.escape(json.dumps(data, sort_keys=True)) + '</metadata>',
             '<rect width="794" height="1123" fill="white"/>',
             '<g fill="black" stroke="none" font-family="monospace" text-anchor="middle">']

    def text(value, x, y, size=16):
        lines.append(f'<text x="{x:.3f}" y="{y:.3f}" font-size="{size}">{html.escape(value)}</text>')

    def circle(x, y, r, dash=""):
        style = ' stroke-dasharray="5 4"' if dash else ''
        lines.append(f'<circle cx="{x}" cy="{y}" r="{r}" fill="none" stroke="black" stroke-width="1.5"{style}/>')

    def point(cx, cy, index, r):
        a = index * math.tau / 26 - math.pi / 2
        return cx + math.cos(a) * r, cy + math.sin(a) * r

    text("LARCHFIELD / ACCOUNT RECOVERY", 397, 32, 23)
    text("1993 COUNTY EDITION - KEEP WITH YOUR MANUAL", 397, 55, 14)
    cx, cy = 397, 300
    circle(cx, cy, 220, "cut")
    circle(cx, cy, 177)
    for i, letter in enumerate(data["outer"]):
        x, y = point(cx, cy, i, 198)
        text(letter, x, y + 6, 21)
    for i, position in enumerate(data["windows"], 1):
        x, y = point(cx, cy, position, 182)
        text(str(i), x, y + 4, 13)
    circle(cx, cy, 2)
    text("OUTER DISC", cx, cy + 235, 13)
    cx, cy = 397, 790
    circle(cx, cy, 175, "cut")
    circle(cx, cy, 154)
    for i, letter in enumerate(data["inner"]):
        x, y = point(cx, cy, i, 140)
        text(letter, x, y + 6, 20)
    for marker in data["markers"]:
        x, y = point(cx, cy, marker["position"], 165)
        name = marker["name"]
        if name == "DIAMOND":
            shape = f'<polygon points="{x},{y-6} {x+6},{y} {x},{y+6} {x-6},{y}"/>'
        elif name == "CIRCLE":
            shape = f'<circle cx="{x}" cy="{y}" r="5"/>'
        elif name == "TRIANGLE":
            shape = f'<polygon points="{x},{y-6} {x+6},{y+5} {x-6},{y+5}"/>'
        else:
            shape = f'<rect x="{x-5}" y="{y-5}" width="10" height="10"/>'
        lines.append('<g fill="none" stroke="black" stroke-width="1.5">' + shape + '</g>')
    circle(cx, cy, 2)
    text("L", cx, cy + 12, 36)
    text("INNER DISC", cx, cy + 192, 13)
    example_rotation = (data["outer"].index("K") - data["markers"][0]["position"]) % 26
    example = data["inner"][(data["windows"][1] - example_rotation) % 26]
    for y, value in enumerate([
        "Cut both dashed edges. Place INNER above OUTER; pin the centres.",
        "Turn the inner disc until the named symbol points to the outer letter.",
        "Read the inner letter beside the requested numbered window.",
        f"Example: DIAMOND to K, window 2 reads {example}. All machines use this mapping.",
    ]):
        text(value, 397, 1022 + y * 22, 13)
    lines.extend(['</g>', '</svg>'])
    target = ROOT / "docs/larchfield-code-wheel.svg"
    target.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(target)


if __name__ == "__main__":
    generate()
