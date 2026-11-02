"""Lossless PNG texture packaging. No resampling or colour modification.

Split large generated bitmaps into bounded texture files, retaining every
decoded RGB pixel. One-pixel sampling gutters prevent seams at scaled edges.
The generated originals remain untouched. A reconstruction assertion verifies
the complete picture before writing the asset manifest and Lua rectangles.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "SurvivorCompanion/42/media/textures/Terminal/Locks"
LIMIT = 300 * 1024


def digest(data):
    return hashlib.sha256(data).hexdigest()


def png_bytes(image):
    out = io.BytesIO()
    image.save(out, format="PNG", optimize=True, compress_level=9)
    return out.getvalue()


def package(source):
    path = Path(source["source"])
    original = Image.open(path)
    if "A" in original.getbands():
        assert original.getchannel("A").getextrema() == (255, 255), "Opaque art required"
    image = original.convert("RGB")
    pieces = []

    def split(x, y, width, height):
        left, top = max(0, x - 1), max(0, y - 1)
        right, bottom = min(image.width, x + width + 1), min(image.height, y + height + 1)
        tile = image.crop((left, top, right, bottom))
        encoded = png_bytes(tile)
        if len(encoded) > LIMIT:
            if width >= height:
                half = width // 2
                split(x, y, half, height)
                split(x + half, y, width - half, height)
            else:
                half = height // 2
                split(x, y, width, half)
                split(x, y + half, width, height - half)
            return
        assert len(pieces) < 16, "Unexpectedly complex art"
        name = source["id"] + "-" + str(len(pieces) + 1).zfill(2) + ".png"
        target = DEST / name
        target.write_bytes(encoded)
        pieces.append({"file": str(target.relative_to(ROOT)).replace("\\", "/"),
                       "x": left, "y": top, "width": right - left, "height": bottom - top,
                       "clip": [x, y, width, height], "bytes": len(encoded), "sha256": digest(encoded)})

    split(0, 0, image.width, image.height)
    reconstructed = Image.new("RGB", image.size)
    for piece in pieces:
        tile = Image.open(ROOT / piece["file"]).convert("RGB")
        x, y, width, height = piece["clip"]
        core = tile.crop((x - piece["x"], y - piece["y"], x - piece["x"] + width, y - piece["y"] + height))
        reconstructed.paste(core, (x, y))
    assert reconstructed.tobytes() == image.tobytes(), "Packaging changed pixels"
    entry = {"id": source["id"], "width": image.width, "height": image.height,
            "source_file": path.name, "source_sha256": digest(path.read_bytes()),
            "decoded_rgb_sha256": digest(image.tobytes()), "tool": "Built-in image_gen",
            "prompt": source["prompt"], "reference_source": source.get("reference_source"),
            "treatment": "Lossless RGB PNG partitioning only; original pixels reconstructed exactly. One-pixel sampling gutters are clipped by the live renderer. No resizing, quantization or visual edits.",
            "files": pieces}
    if source.get("trim_view"):
        # Display geometry only. Packaged RGB pixels remain untouched.
        box = image.convert("L").point(lambda value: 255 if value > 48 else 0).getbbox()
        assert box, "Artwork has no visible ink"
        left, top = max(0, box[0] - 8), max(0, box[1] - 8)
        right, bottom = min(image.width, box[2] + 8), min(image.height, box[3] + 8)
        entry["view"] = [left, top, right - left, bottom - top]
    if source.get("views"):
        entry["views"] = {}
        for name, (column, row, columns, rows) in source["views"].items():
            # UV display windows only. Source and packaged RGB pixels stay exact.
            region = (round(column*image.width/columns), round(row*image.height/rows),
                      round((column+1)*image.width/columns), round((row+1)*image.height/rows))
            box = image.crop(region).convert("L").point(lambda v: 255 if v > 48 else 0).getbbox()
            assert box, name + " has no visible ink"
            left, top = max(region[0], region[0]+box[0]-8), max(region[1], region[1]+box[1]-8)
            right, bottom = min(region[2], region[0]+box[2]+8), min(region[3], region[1]+box[3]+8)
            entry["views"][name] = [left, top, right-left, bottom-top]
    return entry


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("sources", type=Path)
    parser.add_argument("--append", action="store_true", help="Retain other already packaged artwork.")
    args = parser.parse_args()
    sources = json.loads(args.sources.read_text(encoding="utf-8-sig"))
    DEST.mkdir(parents=True, exist_ok=True)
    entries = [package(source) for source in sources]
    if args.append:
        previous = json.loads((ROOT / "docs/terminal-lock-art.json").read_text(encoding="utf-8-sig"))
        replaced = {entry["id"] for entry in entries}
        entries = [entry for entry in previous if entry["id"] not in replaced] + entries
    assert sum(p["bytes"] for e in entries for p in e["files"]) <= 10 * 1024 * 1024
    (ROOT / "docs/terminal-lock-art.json").write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
    lines = ["-- SPDX-License-Identifier: MIT", "-- Generated by tools/package_terminal_lock_art.py. Lossless source rectangles.",
             "SurvivorCompanion=SurvivorCompanion or {}", "SurvivorCompanion.TerminalLockArt={"]
    for entry in entries:
        view = ',view={' + ','.join(map(str, entry["view"])) + '}' if entry.get("view") else ''
        lines.append('    ["' + entry["id"] + '"]={width=' + str(entry["width"]) + ',height=' + str(entry["height"]) + view + ',tiles={')
        for piece in entry["files"]:
            path = piece["file"].split("/42/", 1)[1]
            lines.append('        {file="' + path + '",x=' + str(piece["x"]) + ',y=' + str(piece["y"]) + ',width=' + str(piece["width"]) + ',height=' + str(piece["height"]) + ',clip={' + ','.join(map(str, piece["clip"])) + '}},')
        lines.append("    }},")
    lines.append("}")
    for entry in entries:
        for name, rect in entry.get("views", {}).items():
            lines.append('SurvivorCompanion.TerminalLockArt["' + name + '"]={width=' + str(entry["width"]) +
                         ',height=' + str(entry["height"]) + ',view={' + ','.join(map(str, rect)) +
                         '},tiles=SurvivorCompanion.TerminalLockArt["' + entry["id"] + '"].tiles}')
    (ROOT / "SurvivorCompanion/42/media/lua/client/SCTerminalLockArt.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"assets": len(entries), "files": sum(len(e["files"]) for e in entries),
                      "bytes": sum(p["bytes"] for e in entries for p in e["files"]),
                      "max_file_bytes": max(p["bytes"] for e in entries for p in e["files"])}))


if __name__ == "__main__":
    main()
