# SPDX-License-Identifier: MIT
"""Cheap content references; production UI behavior is exercised in Lua."""

import json
from pathlib import Path
import re
import unittest

PROJECT = Path(__file__).resolve().parents[2]
PAYLOAD = PROJECT / "SurvivorCompanion"
TRANSLATE = PAYLOAD / "42/media/lua/shared/Translate"


class TranslationReferences(unittest.TestCase):
    def test_payload_literal_keys_have_english_text(self):
        english = json.loads((TRANSLATE / "EN/UI.json").read_text(encoding="utf-8"))
        literals, prefixes = set(), set()
        for path in PAYLOAD.rglob("*.lua"):
            source = path.read_text(encoding="utf-8-sig")
            literals.update(re.findall(
                r"\b(?:getText|getTextOrNull)\s*\(\s*[\"']([^\"']+)[\"']\s*(?=[,)])", source))
            literals.update(re.findall(
                r"\bpcall\s*\(\s*(?:getText|getTextOrNull)\s*,\s*[\"']([^\"']+)[\"']\s*(?=[,)])", source))
            literals.update(re.findall(r"[\"']((?:UI|IGUI)_SC_[A-Za-z0-9_]+)[\"']", source))
            prefixes.update(re.findall(r"[\"']((?:UI|IGUI)_SC_[A-Za-z0-9_]+)[\"']\s*\.\.", source))
        required = literals - prefixes
        self.assertFalse(required - english.keys(), f"Missing English keys: {sorted(required - english.keys())}")
        for key in required:
            self.assertTrue(english[key].strip() and english[key] != key, key)

    def test_home_trip_percent_placeholders_are_valid(self):
        english = json.loads((TRANSLATE / "EN/UI.json").read_text(encoding="utf-8"))
        for key in ("UI_SC_HomeTrip_CarChoice", "UI_SC_HomeTrip_FuelCheck", "UI_SC_HomeTrip_FuelKnown"):
            self.assertNotIn("%", re.sub(r"%%|%[1-9]", "", english[key]), key)


if __name__ == "__main__":
    unittest.main()
