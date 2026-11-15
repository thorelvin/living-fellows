# SPDX-License-Identifier: MIT
"""Raise public development-set floors from a passing Kahlua report.

Never deletes a passing row or lowers a floor. Does not read the sealed holdout.
"""
import argparse
import json
import re
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument("--report", type=Path, required=True)
p.add_argument("--checkpoint", required=True)
args = p.parse_args()
root = Path(__file__).resolve().parent.parent
path = root / "tests/fixtures/emma-talk-polish/baseline.json"
data = json.loads(path.read_text(encoding="utf-8"))
report = args.report.read_text(encoding="utf-8-sig")
if "previously passing rows regressed" in report or "Exception in thread" in report:
    raise SystemExit("Cannot checkpoint a failing report")
scores = {name: int(score) for name, score in re.findall(r"^POLISH_SCORE (\S+) (\d+)/\d+", report, re.M)}
required = {"real", "real-variants", "predicted", "persona", "chains", "locks"}
if set(scores) != required:
    raise SystemExit("The report must contain all six public suites")
for name, score in scores.items():
    if score < data["floor"].get(name, 0):
        raise SystemExit("A checkpoint cannot lower a floor: " + name)
passed = set(re.findall(r"^PASS ((?:real-|pred-|chain-|lock-)[\w-]+)(?: \||\s*$)", report, re.M))
old = set(data["passed"])
if old - passed:
    raise SystemExit("A checkpoint cannot lose passing rows: " + ", ".join(sorted(old - passed)))
data["floor"].update(scores)
data["passed"] = {key: True for key in sorted(old | passed)}
data["checkpoint"] = args.checkpoint
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
print("CHECKPOINT_PASS rows=" + str(len(data["passed"])))
