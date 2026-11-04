"""Packaged lock pictures preserve their complete source geometry and budget."""
import hashlib
import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]


class TerminalLockAssets(unittest.TestCase):
    def test_generated_manifest_and_texture_partitions(self):
        entries = json.loads((ROOT / "docs/terminal-lock-art.json").read_text(encoding="utf-8-sig"))
        self.assertEqual({e["id"] for e in entries}, {"AccessGranted", "Case486", "CrackTitle", "Padlock",
            "UndeleteTitle", "ManualCover", "ManualPower", "ManualFiles", "ManualWarranty", "WheelCentre",
            "DialBackTitle", "CountyKeyEscrow", "User2Sign", "StoryTitle", "StoryClasses", "StoryScenes", "StoryEndings"})
        total = 0
        named = set()
        for entry in entries:
            if entry.get("view"):
                x, y, width, height = entry["view"]
                self.assertGreater(width, 0)
                self.assertGreater(height, 0)
                self.assertGreaterEqual(x, 0)
                self.assertGreaterEqual(y, 0)
                self.assertLessEqual(x + width, entry["width"])
                self.assertLessEqual(y + height, entry["height"])
            for rect in entry.get("views", {}).values():
                x, y, width, height = rect
                self.assertGreater(width, 0)
                self.assertGreater(height, 0)
                self.assertGreaterEqual(x, 0)
                self.assertGreaterEqual(y, 0)
                self.assertLessEqual(x + width, entry["width"])
                self.assertLessEqual(y + height, entry["height"])
            self.assertEqual(entry["tool"], "Built-in image_gen")
            self.assertTrue(entry["prompt"])
            self.assertRegex(entry["source_sha256"], r"^[a-f0-9]{64}$")
            self.assertRegex(entry["decoded_rgb_sha256"], r"^[a-f0-9]{64}$")
            xs, ys = {0, entry["width"]}, {0, entry["height"]}
            for tile in entry["files"]:
                path = (ROOT / tile["file"]).resolve()
                self.assertTrue(path.is_relative_to(ROOT.resolve()))
                named.add(path)
                data = path.read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack(">II", data[16:24]), (tile["width"], tile["height"]))
                self.assertEqual(hashlib.sha256(data).hexdigest(), tile["sha256"])
                self.assertEqual(len(data), tile["bytes"])
                self.assertLessEqual(len(data), 300 * 1024)
                total += len(data)
                x, y, width, height = tile["clip"]
                self.assertGreater(width, 0)
                self.assertGreater(height, 0)
                self.assertGreaterEqual(x, tile["x"])
                self.assertGreaterEqual(y, tile["y"])
                self.assertLessEqual(x + width, tile["x"] + tile["width"])
                self.assertLessEqual(y + height, tile["y"] + tile["height"])
                xs.update((x, x + width))
                ys.update((y, y + height))
            xs, ys = sorted(xs), sorted(ys)
            for x0, x1 in zip(xs, xs[1:]):
                for y0, y1 in zip(ys, ys[1:]):
                    covering = [p for p in entry["files"] if p["clip"][0] <= x0 and p["clip"][1] <= y0
                                and p["clip"][0] + p["clip"][2] >= x1 and p["clip"][1] + p["clip"][3] >= y1]
                    self.assertEqual(len(covering), 1, f"{entry['id']} has a missing or overlapping source rectangle")
        self.assertLessEqual(total, 10 * 1024 * 1024)
        actual = set((ROOT / "SurvivorCompanion/42/media/textures/Terminal/Locks").glob("*.png"))
        self.assertEqual(named, {p.resolve() for p in actual})


if __name__ == "__main__":
    unittest.main()
