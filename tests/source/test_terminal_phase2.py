"""Printable mappings and offline-lock content contracts."""
import importlib.util
import json
import hashlib
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "SurvivorCompanion/42/media/lua/client"


class PhaseTwoSources(unittest.TestCase):
    def test_supplied_dialogue_only_changes_distance_units(self):
        content = (CLIENT / "SCTerminalLockEmmaData.lua").read_bytes().replace(b"\r\n", b"\n")
        # Phase A changes this one measurement; retain the supplied dialogue's
        # original checksum for every other word, rule and ordering decision.
        self.assertEqual(content.count(b"There is. {D} meters,"), 1)
        self.assertNotIn(b"{D} tiles", content)
        original = content.replace(b"There is. {D} meters,", b"There is. {D} tiles,")
        self.assertEqual(hashlib.sha256(original).hexdigest(), "f9e576bcf56f5713db22e47d50875b0d117fd210f47ad95f5485775d67171c9e")

    def test_printable_is_the_live_mapping(self):
        spec = importlib.util.spec_from_file_location("wheel", ROOT / "tools/generate_larchfield_wheel.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        tree = ET.parse(ROOT / "docs/larchfield-code-wheel.svg")
        metadata = tree.find("{http://www.w3.org/2000/svg}metadata")
        self.assertEqual(json.loads(metadata.text), module.mapping())
        self.assertEqual(tree.getroot().get("viewBox"), "0 0 794 1123")

    def test_emma_draw_does_not_read_the_world(self):
        source = (CLIENT / "SCTerminalLockEmma.lua").read_text(encoding="utf-8-sig")
        draw = source.split("function Emma.lines(w)", 1)[1].split("function Emma.onVisit", 1)[0]
        self.assertNotIn("Emma.facts(", draw)
        self.assertNotIn("Emma.offers(", draw)
        self.assertNotIn("nearestThreat", draw)

    def test_manual_has_native_ordinary_item_and_book_models(self):
        source = (ROOT / "SurvivorCompanion/42/media/scripts/LivingFellows_Manual.txt").read_text()
        for expected in ("item LarchfieldManual", "ItemType = base:normal", "Weight = 0.3", "WorldStaticModel = BookClosedGround"):
            self.assertIn(expected, source)


if __name__ == "__main__":
    unittest.main()
