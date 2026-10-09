# SPDX-License-Identifier: MIT
"""Every Kahlua harness on disk must be reached from the project gate.

A harness only proves something while a gate stage runs it. Twenty-five
Strange Folk encounter suites, the strike barrier regression and the grave
marker harness were written, passed when run by hand, and were never run by
Test-Project.ps1 -- so a regression in any of them would have shipped green.

This follows script references from scripts/Test-Project.ps1 and requires
each tests/**/*_harness.lua file name to appear in a script it reaches.
Names must be written literally; a runner that builds harness names from a
pattern would hide them from this check.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "tests"
SCRIPTS = ROOT / "scripts"
ENTRY = SCRIPTS / "Test-Project.ps1"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


scripts_by_name: dict[str, list[Path]] = {}
for folder in (SCRIPTS, TESTS):
    for script in folder.rglob("*.ps1"):
        scripts_by_name.setdefault(script.name, []).append(script)

reached: set[Path] = set()
pending = [ENTRY]
while pending:
    script = pending.pop()
    if script in reached:
        continue
    reached.add(script)
    text = script.read_text(encoding="utf-8")
    for name in set(re.findall(r"[\w.-]+\.ps1", text)):
        for target in scripts_by_name.get(name, []):
            if target not in reached:
                pending.append(target)

reached_text = "\n".join(path.read_text(encoding="utf-8") for path in reached)
harnesses = sorted(TESTS.rglob("*_harness.lua"))
require(len(harnesses) >= 40, f"expected the harness tree under {TESTS}")
unreached = [path.relative_to(ROOT).as_posix() for path in harnesses
             if path.name not in reached_text]
require(not unreached,
        "harnesses no project gate stage runs:\n  " + "\n  ".join(unreached))

print(f"HARNESS_WIRING_PASS harnesses={len(harnesses)} scripts={len(reached)}")
