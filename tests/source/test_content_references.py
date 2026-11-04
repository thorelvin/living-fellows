# SPDX-License-Identifier: MIT
"""Validate packaged content references without inspecting implementation shape."""

import hashlib
import importlib.util
import json
from pathlib import Path
import re
import unittest
import wave
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "SurvivorCompanion/42/media/lua/client"


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TranslationReferences = load_module("ui_content_references", ROOT / "tests/ui/test_ui_contract.py").TranslationReferences


class ContentReferences(unittest.TestCase):
    def test_story_art_references_are_packaged(self):
        entries = json.loads((ROOT / "docs/terminal-lock-art.json").read_text(encoding="utf-8-sig"))
        names = {entry["id"] for entry in entries}
        names.update(name for entry in entries for name in entry.get("views", {}))
        required = set(re.findall(r'art="([^"]+)"', (CLIENT / "SCTerminalLockStoryData.lua").read_text(encoding="utf-8-sig")))
        required.update(("StoryTitle", "StoryOwner", "StoryGhost", "StoryGameOver", "RecoveryLicense", "StoryDice"))
        self.assertTrue(required.issubset(names), required - names)

    def test_printable_wheel_matches_content_mapping(self):
        wheel = load_module("larchfield_wheel", ROOT / "tools/generate_larchfield_wheel.py")
        tree = ET.parse(ROOT / "docs/larchfield-code-wheel.svg")
        metadata = tree.find("{http://www.w3.org/2000/svg}metadata")
        self.assertEqual(json.loads(metadata.text), wheel.mapping())

    def test_registered_audio_payloads_are_valid(self):
        manifest = (ROOT / "ASSET-MANIFEST.md").read_text(encoding="utf-8-sig")
        script = (ROOT / "SurvivorCompanion/42/media/scripts/sounds_LivingFellowsLocks.txt").read_text(encoding="utf-8-sig")
        for name in ("LFPhoneRing", "LFPhoneAnswer", "LFNumbersTune", "LFDiceRoll", "LFSpiffyJingle"):
            path = ROOT / f"SurvivorCompanion/42/media/sound/{name}.wav"
            self.assertRegex(script, rf"\bsound\s+{name}\b")
            self.assertIn(hashlib.sha256(path.read_bytes()).hexdigest(), manifest)
            with wave.open(str(path)) as audio:
                self.assertEqual((audio.getnchannels(), audio.getsampwidth()), (1, 2))
                self.assertGreater(audio.getframerate(), 0)
                self.assertGreater(audio.getnframes(), 0)


if __name__ == "__main__":
    unittest.main()
