# SPDX-License-Identifier: MIT
"""On-demand Kahlua boundary and release-data guards; behavior runs in Lua."""

from __future__ import annotations

import json
import re
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
PAYLOAD = PROJECT / "SurvivorCompanion"
LUA = PAYLOAD / "42" / "media" / "lua"
CLIENT = LUA / "client"
SHARED = LUA / "shared"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


lua_files = sorted(LUA.rglob("*.lua"))
all_lua = "\n".join(path.read_text(encoding="utf-8") for path in lua_files)
require(re.search(r"tonumber\s*\(\s*select\s*\(", all_lua) is None,
        "tonumber(select(...)) forwards utility.call's success flag as a numeric base in Kahlua")
# Build 42's Kahlua does not reliably publish the global next(). The call only
# fails on the branch that reaches it, which can stay hidden until a live save
# (a Gravekeeper's blocked order with a borrowed shovel did in 0.26.54).
bare_next = [
    f"{path.name}:{text.count(chr(10), 0, match.start()) + 1}"
    for path in lua_files
    for text in (path.read_text(encoding="utf-8"),)
    for match in re.finditer(r"(?<![\w.:])next\s*\(", text)
    if not text[text.rfind("\n", 0, match.start()) + 1:match.start()].lstrip().startswith("--")
]
require(not bare_next, f"bare next() is not reliable in Build 42 Kahlua; probe with pairs: {bare_next}")
tick_adds = [
    (path, match.start())
    for path in lua_files
    for match in re.finditer(r"(?:Events\.OnTick\.Add\s*\(|pcall\(Events\.OnTick\.Add\s*,)",
                             path.read_text(encoding="utf-8"))
]
require(len(tick_adds) == 1 and tick_adds[0][0].name == "SCRuntime.lua",
        f"expected one central OnTick attachment, got {tick_adds}")

config = (SHARED / "SCConfig.lua").read_text(encoding="utf-8")
require(re.search(r"(?m)^\s*experimentalNpcPlayerActor\s*=\s*false,\s*$", config) is not None,
        "release experimental actor provider must be OFF")
require(re.search(r"(?m)^\s*debugSpawnEnabled\s*=\s*false,\s*$", config) is not None,
        "release debug spawn must be OFF")
require(re.search(r"(?m)^\s*vitalsStatTrace\s*=\s*false,\s*$", config) is not None,
        "release native-vitals probe must be OFF")
require(re.search(r"(?m)^\s*productionEncounterEnabled\s*=\s*true,\s*$", config) is not None,
        "normal production encounter cadence must remain enabled")
require(re.search(r"(?m)^\s*debugSpawnIntervalMs\s*=\s*60000,\s*$", config) is not None,
        "debug spawn interval must be 60 seconds")
roster_limit = re.search(r"(?m)^\s*maxCompanions\s*=\s*(\d+),\s*$", config)
require(roster_limit is not None and 10 <= int(roster_limit.group(1)) <= 16,
        "release roster must support ten companions while remaining bounded to sixteen")

spawn = (CLIENT / "SCSpawn.lua").read_text(encoding="utf-8")
name_entries = re.findall(r'\{ name = "([^"]+)", gender = "(?:female|male)" \}', spawn)
require(len(name_entries) >= 100 and len(name_entries) == len(set(name_entries)),
        "expanded genre first-name pool must contain at least 100 unique names")
for expected_name in (
    "Rick", "Michonne", "Daryl", "Maggie", "Negan",
    "Joel", "Ellie", "Abby", "Dina", "Tess",
    "Shaun", "Ed", "Liz", "Dianne", "Yvonne",
    "Jim", "Selena", "Ana", "Zoey", "Leon", "Seokwoo",
):
    require(expected_name in name_entries,
            f"requested genre first name missing: {expected_name}")
def lua_block(source: str, start: str) -> str:
    begin = source.index(start)
    return source[begin:source.index("}", begin)]


# A generated companion must never share a surname with a Strange Folk
# character, or a random recruit could read as Milli's or Elias's kin.
generated_surnames = set(re.findall(r'"([^"]+)"', lua_block(spawn, "local surnames = {")))
generated_surnames |= set(re.findall(r'"([^"]+)"', lua_block(spawn, "local koreanSurnames = {")))
reserved_surnames = set(re.findall(r"(\w+) = true", lua_block(spawn, "local reservedSurnames = {")))
oddball_source = (CLIENT / "SCOddballs.lua").read_text(encoding="utf-8")
oddball_surnames = set(re.findall(r'forename = "[^"]+", surname = "([^"]+)"', oddball_source))
require(len(oddball_surnames) >= 40, "Strange Folk identities were not found in SCOddballs.lua")
unreserved = sorted(oddball_surnames & generated_surnames - reserved_surnames)
require(not unreserved,
        f"Strange Folk surnames can still be generated for companions: {unreserved}")

sandbox_options = PAYLOAD / "42" / "media" / "sandbox-options.txt"
sandbox_translation = SHARED / "Translate" / "EN" / "Sandbox.json"
require(sandbox_options.is_file() and sandbox_translation.is_file(),
        "Living Fellows sandbox options or English labels are missing")
sandbox_text = sandbox_options.read_text(encoding="utf-8")
for option in ("EncountersEnabled", "EncounterFrequency", "MaxCompanions",
               "CompanionNeedsRate", "HouseholdSpawnsEnabled", "HouseholdDailyChance",
               "MaxHouseholds", "UIOpacity", "ShowCompanionNames",
               "ExpeditionDestinationScope"):
    require(f"option LivingFellows.{option}" in sandbox_text,
            f"sandbox option missing: {option}")
require("debugSpawnEnabled" not in sandbox_text and "Debug" not in sandbox_text,
        "release sandbox UI must not expose private debug spawning")

for translation in (SHARED / "Translate").rglob("*.json"):
    json.loads(translation.read_text(encoding="utf-8-sig"))
for source in lua_files:
    data = source.read_bytes()
    require(not data.startswith(b"\xef\xbb\xbf") and b"\x00" not in data,
            f"Lua payload has BOM or NUL bytes: {source}")
print(f"CORE_DATA_PASS lua_files={len(lua_files)}")
