"""Story data, art completeness, budgets and absence of a background service."""
from pathlib import Path
import hashlib
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "SurvivorCompanion/42/media/lua/client"


class Phase4(unittest.TestCase):
    def test_supplied_story_is_unchanged(self):
        data = (CLIENT / "SCTerminalLockStoryData.lua").read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(data).hexdigest(), "eb40c7c07514081bf1ef97c011b99a6bb850960490c1930001270999a536fe39")
        self.assertTrue(all(n < 128 for n in data))

    def test_all_story_pictures_are_packaged(self):
        entries = json.loads((ROOT / "docs/terminal-lock-art.json").read_text())
        names = {e["id"] for e in entries}
        names.update(name for e in entries for name in e.get("views", {}))
        required = set(re.findall(r'art="([^"]+)"', (CLIENT / "SCTerminalLockStoryData.lua").read_text()))
        required.update(("StoryTitle", "StoryOwner", "StoryGhost", "StoryGameOver", "RecoveryLicense", "StoryDice"))
        self.assertTrue(required.issubset(names), required - names)

    def test_dice_is_original_and_registered(self):
        import wave
        sound = ROOT / "SurvivorCompanion/42/media/sound/LFDiceRoll.wav"
        self.assertIn(hashlib.sha256(sound.read_bytes()).hexdigest(), (ROOT / "ASSET-MANIFEST.md").read_text())
        self.assertIn("sound LFDiceRoll", (ROOT / "SurvivorCompanion/42/media/scripts/sounds_LivingFellowsLocks.txt").read_text())
        with wave.open(str(sound)) as audio:
            self.assertAlmostEqual(audio.getnframes() / audio.getframerate(), .65, places=3)

    def test_story_has_no_world_mutations_or_background_service(self):
        source = (CLIENT / "SCTerminalLockStory.lua").read_text()
        for name in ("Events.", "setHealth", "AddDamage", "Commands.issue", "AddItem", "getGridSquare", "getSpecificPlayer"):
            self.assertNotIn(name, source)
        self.assertIn('g.pending.roll=ZombRand(20)+1', source)
        bootstrap = (CLIENT / "SCBootstrap.lua").read_text(encoding="utf-8-sig")
        self.assertIn('require "SCTerminalLockStoryData"', bootstrap)
        self.assertIn('require "SCTerminalLockStory"', bootstrap)
        runtime = (CLIENT / "SCRuntime.lua").read_text(encoding="utf-8-sig")
        self.assertNotIn("TerminalLockStory", runtime)


if __name__ == "__main__":
    unittest.main()
