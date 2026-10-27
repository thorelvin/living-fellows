"""Read-only stock-map desktop census; format checked against the installed JAR.

No game/save writes. Outputs research JSON/CSV beside this script.
"""
from pathlib import Path
from collections import Counter
from bisect import bisect_right
import csv
import json
import struct

GAME = Path(r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid")
OUT = Path(__file__).resolve().parent
COMPUTERS = {f"appliances_com_01_{i}" for i in range(72, 76)}


class Reader:
    def __init__(self, data):
        self.data, self.at = data, 0

    def integer(self):
        value = struct.unpack_from("<i", self.data, self.at)[0]
        self.at += 4
        return value

    def line(self):
        end = self.data.index(b"\n", self.at)
        value = self.data[self.at:end].decode("utf-8").strip()
        self.at = end + 1
        return value


def header(path, require_computer=True):
    r = Reader(path.read_bytes())
    assert r.data[:4] == b"LOTH", path
    r.at = 4
    assert r.integer() == 1, path
    tiles = [r.line() for _ in range(r.integer())]
    if require_computer and not COMPUTERS.intersection(tiles):
        return None
    assert (r.integer(), r.integer()) == (8, 8), path
    lo, hi = r.integer(), r.integer()
    assert -32 <= lo <= hi <= 31, path
    rooms = []
    for _ in range(r.integer()):
        name, level = r.line(), r.integer()
        rects = [tuple(r.integer() for _ in range(4)) for _ in range(r.integer())]
        objects = r.integer()
        r.at += objects * 12  # Native meta-object type, x, y.
        rooms.append({"name": name, "level": level, "rects": rects})
    for building in range(r.integer()):
        indices = [r.integer() for _ in range(r.integer())]
        names = sorted({rooms[i]["name"] for i in indices})
        for i in indices:
            rooms[i]["building"] = building
            rooms[i]["building_rooms"] = names
    assert len(r.data) - r.at == 1024, (path, len(r.data) - r.at)
    return tiles, lo, hi, rooms


def desktops(path, info):
    tiles, lo, hi, rooms = info
    cx, cy = map(int, path.stem.split("_"))
    pack = path.with_name(f"world_{path.stem}.lotpack")
    data = pack.read_bytes()
    assert data[:4] == b"LOTP" and struct.unpack_from("<2i", data, 4) == (1, 1024), pack
    offsets = [struct.unpack_from("<q", data, 12 + i * 8)[0] for i in range(1024)]
    ordered = sorted((offset, i) for i, offset in enumerate(offsets) if offset > 0)
    starts = [offset for offset, _ in ordered]
    assert starts and starts[0] >= 8204 and starts[-1] < len(data), pack
    wanted = {i for i, tile in enumerate(tiles) if tile in COMPUTERS}
    candidates = set()
    for tile in wanted:
        needle, at = struct.pack("<i", tile), 8204
        while True:
            at = data.find(needle, at)
            if at < 0:
                break
            if at % 4 == 0:
                which = bisect_right(starts, at) - 1
                if which >= 0:
                    candidates.add(ordered[which][1])
            at += 1
    found = []
    for chunk in sorted(candidates):
        r = Reader(data)
        r.at, skip = offsets[chunk], 0
        chunk_x, chunk_y = divmod(chunk, 32)
        for slot in range((hi - lo + 1) * 64):
            if skip:
                skip -= 1
                continue
            count = r.integer()
            if count == -1:
                skip = r.integer() - 1
                assert skip >= 0, (pack, chunk, slot)
                continue
            assert 0 <= count <= 4096, (pack, chunk, slot, count)
            if count <= 1:
                continue
            room_id = r.integer()
            square_tiles = [r.integer() for _ in range(count - 1)]
            assert all(0 <= i < len(tiles) for i in square_tiles), (pack, chunk, slot)
            matches = wanted.intersection(square_tiles)
            if not matches:
                continue
            level, local = divmod(slot, 64)
            local_x, local_y = divmod(local, 8)
            x = cx * 256 + chunk_x * 8 + local_x
            y = cy * 256 + chunk_y * 8 + local_y
            z = lo + level
            # Verify the coordinate orientation against room rectangles, not
            # just an in-range numeric room index.
            matching_rooms = [room for room in rooms if room["level"] == z
                and any(rx <= x - cx * 256 < rx + w and ry <= y - cy * 256 < ry + h
                    for rx, ry, w, h in room["rects"])]
            room = matching_rooms[0] if len(matching_rooms) == 1 else {}
            for tile in sorted(matches):
                found.append({"cell": path.stem, "x": x, "y": y, "z": z,
                    "sprite": tiles[tile], "room": room.get("name", "<unresolved>"),
                    "building_rooms": room.get("building_rooms", []),
                    "encoded_room_id": room_id})
    return found


def main():
    roots = GAME / "media/maps/Muldraugh, KY"
    headers = sorted(roots.glob("*.lotheader"))
    found, candidate_cells, errors = [], 0, []
    for path in headers:
        try:
            info = header(path)
            if info:
                candidate_cells += 1
                found.extend(desktops(path, info))
        except Exception as error:
            errors.append({"file": path.name, "error": repr(error)})
    # Header rooms may belong to a building whose anchor is in another cell.
    # Build a rectangle index from every header instead of guessing a business
    # for otherwise unresolved desks near cell boundaries.
    room_index = {}
    for path in headers:
        try:
            info = header(path, require_computer=False)
            cx, cy = map(int, path.stem.split("_"))
            for room in info[3]:
                for rx, ry, w, h in room["rects"]:
                    left, top = cx * 256 + rx, cy * 256 + ry
                    for cell_x in range(left // 256, (left + w - 1) // 256 + 1):
                        for cell_y in range(top // 256, (top + h - 1) // 256 + 1):
                            room_index.setdefault((cell_x, cell_y, room["level"]), []).append(
                                (left, top, w, h, path.stem, room))
        except Exception as error:
            errors.append({"room_header": path.name, "error": repr(error)})
    for item in found:
        if item["room"] != "<unresolved>":
            continue
        x, y, z = item["x"], item["y"], item["z"]
        matches = {(anchor, id(room)): room for left, top, w, h, anchor, room in
            room_index.get((x // 256, y // 256, z), []) if left <= x < left + w and top <= y < top + h}
        if len(matches) == 1:
            room = next(iter(matches.values()))
            item["room"] = room["name"]
            item["building_rooms"] = room.get("building_rooms", [])
    summary = {"runtime": "42.21.0", "headers": len(headers),
        "desktop_cells": candidate_cells, "desktop_objects": len(found),
        "rooms": dict(Counter(item["room"] for item in found).most_common()),
        "errors": errors}
    (OUT / "computer-census-summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    with (OUT / "computer-census.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=["cell", "x", "y", "z", "sprite", "room",
            "building_rooms", "encoded_room_id"])
        writer.writeheader()
        for item in found:
            writer.writerow({**item, "building_rooms": ";".join(item["building_rooms"])})
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
