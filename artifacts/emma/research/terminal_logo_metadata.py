# SPDX-License-Identifier: MIT
"""Read alpha/hue metadata only; never modify or export image pixels."""
import argparse
import colorsys
import json
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args()
    media = args.project_root / "SurvivorCompanion/42/media"
    sources = {p.stem: p for p in sorted(
        (args.game_root / "media/textures/printMedia/logos").glob("*.png"))}
    for p in (media / "textures/Terminal").glob("*.png"):
        if p.stem == "camp-purple":
            continue  # A phosphor variant, not another business identity.
        key = p.stem if p.stem[0].isupper() else "_" + p.stem
        sources[key] = p
    camp_art = json.loads((args.project_root / "docs/terminal-camp-logo-colours.json").read_text(encoding="utf-8"))
    sources["_camp"] = args.project_root / camp_art["source_asset"]
    # Authored transparent headers have no backing to key out. Broad pale
    # lettering can otherwise look like an opaque page to the stock heuristic.
    transparent_headers = set()
    manifest_path = args.project_root / "docs/terminal-community-art-manifest.json"
    if manifest_path.exists():
        for entry in json.loads(manifest_path.read_text(encoding="utf-8"))["entries"]:
            path = args.project_root / entry["file"]
            if entry.get("transparent_background") is True and sources.get(entry["id"]) == path:
                transparent_headers.add(entry["id"])
    bounds, palettes, backings, dark_ink = {}, {}, {}, {}
    for name, path in sorted(sources.items()):
        with Image.open(path) as image:
            image = image.convert("RGBA")
            if name == "_camp":
                # A single neutral source serves every camp phosphor theme.
                x, y, width, height = camp_art["crop"]
            else:
                alpha = image.getchannel("A")
                box = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
                if box is None:
                    raise ValueError(f"Empty logo: {name}")
                x, y, right, bottom = box
                width, height = right - x, bottom - y
            bounds[name] = [x, y, width, height]
            # Read-only background detection. A mostly opaque rectangular
            # source with a repeated flat fill is keyed by the UI shader; no
            # bitmap pixels are rewritten or copied out of the game.
            region = image.crop((x, y, x + width, y + height))
            step_bg = max(1, max(width, height) // 128)
            samples = [region.getpixel((px, py)) for py in range(0, height, step_bg)
                       for px in range(0, width, step_bg)]
            opaque = [p for p in samples if p[3] > 192]
            if name not in transparent_headers and len(opaque) > len(samples) * .72:
                from collections import Counter
                buckets = Counter(tuple(c//8 for c in p[:3]) for p in opaque)
                common, count = buckets.most_common(1)[0]
                if count > len(opaque) * .28:
                    pixels = [p for p in opaque if tuple(c//8 for c in p[:3]) == common]
                    backings[name] = [round(sum(p[c] for p in pixels)/len(pixels)/255, 6) for c in range(3)]
            key = backings.get(name)
            ink = [p for p in opaque if key is None or sum((p[c]/255-key[c])**2 for c in range(3)) > .01]
            if ink:
                mean_luma = sum((.2126*p[0]+.7152*p[1]+.0722*p[2])/255 for p in ink)/len(ink)
                if mean_luma < .35:
                    dark_ink[name] = True
            weights = {"green": 0.0, "sand": 0.0, "aqua": 0.0}
            # Sample in a bounded grid, ignoring neutral lettering and black.
            step = max(1, max(width, height) // 128)
            for py in range(y, y + height, step):
                for px in range(x, x + width, step):
                    r, g, b, a = image.getpixel((px, py))
                    high, low = max(r, g, b) / 255, min(r, g, b) / 255
                    chroma = high - low
                    if a < 32 or high < 0.18 or chroma < 0.18:
                        continue
                    hue = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0] * 360
                    theme = "green" if 65 <= hue < 165 else "aqua" if 165 <= hue < 305 else "sand"
                    weights[theme] += a / 255 * chroma * high
            if sum(weights.values()) > 0:
                palettes[name] = max(weights, key=weights.get)
    # Explicit visual pairing: blue/ivory/orange Fossoil suits aquamarine.
    palettes["Fossoil"] = palettes["FossoilField"] = "aqua"
    # Preserve the existing default pairing; saved screen colours are separate.
    palettes["_camp"] = "green"
    for name in ("OptimaEyes", "PalettePop", "TheExquisitePearl", "TheSlugger"):
        dark_ink[name] = True
    rows = ["-- SPDX-License-Identifier: MIT",
            "-- Alpha bounds and brand colour pairings; PNG pixels are unchanged.",
            "-- Generated by artifacts/emma/research/terminal_logo_metadata.py.",
            'if type(require) == "function" then require "SCTerminalBrands" end', "local B = SurvivorCompanion.TerminalBrands", "B.CROPS = {"]
    for name, box in bounds.items():
        rows.append(f"    [{json.dumps(name)}] = {{ {', '.join(map(str, box))} }},")
    rows += ["}", "B.PALETTES = {"]
    for name, theme in sorted(palettes.items()):
        rows.append(f"    [{json.dumps(name)}] = {json.dumps(theme)},")
    rows += ["}", "B.BACKINGS = {"]
    for name, rgb in sorted(backings.items()):
        rows.append(f"    [{json.dumps(name)}] = {{ {', '.join(map(str, rgb))} }},")
    rows += ["}", "B.DARK_INK = {"]
    for name in sorted(dark_ink):
        rows.append(f"    [{json.dumps(name)}] = true,")
    rows += ["}", ""]
    (media / "lua/client/SCTerminalArtBounds.lua").write_text("\n".join(rows), encoding="utf-8")
    print(f"Logo metadata: {len(bounds)} source rectangles, {len(palettes)} colour pairings")
    print("Fossoil: aquamarine; neutral marks retain seeded theme; purple remains rare")


if __name__ == "__main__":
    main()
