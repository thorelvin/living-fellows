# SPDX-License-Identifier: MIT
"""Read-only branding coverage report from installed stock data and map census."""
import argparse
import collections
import csv
import hashlib
import json
from pathlib import Path
import re


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(text, name):
    return text.split("D." + name + " = {", 1)[1].split("}", 1)[0]


def pairs(text):
    return dict(re.findall(r'(\w+)\s*=\s*"([^\"]+)"', text))


def rectangles(text, key):
    start = re.search(r"\b" + re.escape(key) + r"\s*=\s*\{\s*location1\s*=\s*\{", text)
    if not start:
        raise ValueError("Missing native advert definition: " + key)
    begin = text.index("{", start.start())
    depth = 0
    for end in range(begin, len(text)):
        depth += (text[end] == "{") - (text[end] == "}")
        if not depth:
            break
    return [tuple(map(int, match)) for match in re.findall(
        r"x1\s*=\s*(\d+),\s*y1\s*=\s*(\d+),\s*x2\s*=\s*(\d+),\s*y2\s*=\s*(\d+)", text[begin:end])]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--game-root", type=Path, required=True)
    parser.add_argument("--project-root", type=Path, required=True)
    args = parser.parse_args()
    project = args.project_root.resolve()
    output = project / "artifacts/emma/research"
    data = project / "SurvivorCompanion/42/media/lua/client/SCTerminalBusinessData.lua"
    native = args.game_root / "media/lua/shared/PrintMedia/PrintMediaDefinitions.lua"
    census = output / "computer-census.csv"
    source = data.read_text(encoding="utf-8")
    brands = pairs(table(source, "POI_BRANDS"))
    rooms = pairs(table(source, "ROOM_BRANDS"))
    native_text = native.read_text(encoding="utf-8-sig")
    sites = [(brand, rect) for key, brand in brands.items() for rect in rectangles(native_text, key)]
    with census.open(newline="", encoding="utf-8-sig") as file:
        computers = list(csv.DictReader(file))
    candidates = collections.Counter()
    direct = collections.Counter()
    conflicts, private = 0, 0
    for computer in computers:
        x, y = int(computer["x"]), int(computer["y"])
        room = computer["room"]
        if room in rooms:
            direct[rooms[room]] += 1
        found = {brand for brand, (x1, y1, x2, y2) in sites if x1 <= x <= x2 and y1 <= y <= y2}
        home = "bedroom" in room or room in ("livingroom", "kitchen", "attic")
        if found and home:
            private += 1
        elif len(found) == 1:
            candidates[next(iter(found))] += 1
        elif found:
            conflicts += 1
    report = {"runtime": "42.21.0", "desktop_objects": len(computers),
              "curated_advert_keys": len(brands), "native_rectangles": len(sites),
              "exact_room_candidates": dict(sorted(direct.items())),
              "unambiguous_rectangle_candidates": dict(sorted(candidates.items())),
              "private_room_rectangle_matches_excluded": private,
              "conflicting_rectangle_candidates": conflicts,
              "limits": ["Counts are evidence candidates, not a running-save assignment census.",
                         "Same-room sign and unique-building checks are exercised separately.",
                         "Generic offices and mixed tenants can retain sector emblems."],
              "sha256": {str(p): digest(p) for p in (data, native, census)}}
    (output / "terminal-coverage.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("Coverage audit:", len(computers), "desktops;", len(brands), "verified advert keys;",
          len(sites), "rectangles;", sum(direct.values()), "exact room candidates;",
          sum(candidates.values()), "unambiguous rectangle candidates")


if __name__ == "__main__":
    main()
