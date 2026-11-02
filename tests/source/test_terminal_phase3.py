"""Phase 3 payload, event ownership and original audio acceptance."""
import hashlib
from pathlib import Path
import unittest
import wave

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "SurvivorCompanion/42/media/lua/client"


class Phase3(unittest.TestCase):
    def test_original_audio_payloads(self):
        manifest = (ROOT / "ASSET-MANIFEST.md").read_text(encoding="utf-8-sig")
        script = (ROOT / "SurvivorCompanion/42/media/scripts/sounds_LivingFellowsLocks.txt").read_text()
        for name, seconds in (("LFPhoneRing", 2), ("LFPhoneAnswer", .22), ("LFNumbersTune", 1.5)):
            path = ROOT / f"SurvivorCompanion/42/media/sound/{name}.wav"
            self.assertIn(hashlib.sha256(path.read_bytes()).hexdigest(), manifest)
            self.assertIn(f"sound {name}", script)
            with wave.open(str(path)) as audio:
                self.assertEqual((audio.getnchannels(), audio.getsampwidth(), audio.getframerate()), (1, 2, 22050))
                self.assertAlmostEqual(audio.getnframes() / 22050, seconds, places=4)

    def test_hooks_have_a_bootstrap_owner(self):
        bootstrap = (CLIENT / "SCBootstrap.lua").read_text(encoding="utf-8-sig")
        for name in ("SCTerminalLockPhone", "SCTerminalLockRadio"):
            self.assertIn(f'require "{name}"', bootstrap)
            self.assertIn(f"SC.{name[2:]} end", bootstrap)
            source = (CLIENT / (name + ".lua")).read_text()
            self.assertNotIn("Events.OnTick", source)
            for method in ("install", "remove", "isInstalled", "reset"):
                self.assertIn(f"function {'P' if name.endswith('Phone') else 'R'}.{method}", source)

    def test_closed_service_does_not_scan_buildings(self):
        runtime = (CLIENT / "SCRuntime.lua").read_text(encoding="utf-8-sig")
        task = runtime.split('{ "terminal-callback",', 1)[1].split('end, "background"', 1)[0]
        self.assertNotIn(".search", task)
        self.assertNotIn("getGridSquare", task)
        self.assertNotIn("candidates", task)
        phone = (CLIENT / "SCTerminalLockPhone.lua").read_text()
        radio = (CLIENT / "SCTerminalLockRadio.lua").read_text()
        self.assertIn("if not active then return end", phone.split("function P.pulse", 1)[1])
        self.assertIn("#ledger.pending==0 and not broadcast", radio)


if __name__ == "__main__":
    unittest.main()
