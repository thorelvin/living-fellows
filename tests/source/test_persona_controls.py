"""Negative controls: break the engine on purpose and prove the harness notices. Exit status is the only verdict.

Usage: python codex-handoff-persona-controls.py [--harness-only]
Set PZ_GAME_ROOT, LF_REPO or JAVAC if yours differ. Once the files are in the repo, point the four paths below at them.
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GAME = Path(os.environ.get("PZ_GAME_ROOT", r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"))
REPO = HERE.parents[1]
JAVAC = os.environ.get("JAVAC", r"C:\Program Files\Java\jdk-17\bin\javac.exe")
CLIENT = REPO / "SurvivorCompanion/42/media/lua/client"
ENGINE = (CLIENT / "SCTerminalPersona.lua").read_text(encoding="utf-8")
DATA = [str(CLIENT / f"SCTerminalPersona{name.title()}.lua") for name in ("spiffy", "ellis", "duty")]
HARNESS = str(REPO / "tests/gameplay/persona_harness.lua")
temporary = tempfile.TemporaryDirectory(prefix="persona-controls-")
WORK = Path(temporary.name)
built = subprocess.run([JAVAC, "-d", str(WORK), str(REPO / "tests" / "gameplay" / "KahluaTestRunner.java")], capture_output=True, text=True)
if built.returncode != 0:
    raise SystemExit("could not compile KahluaTestRunner: " + built.stderr)
MUTATIONS = {
    "no break: control must pass": (None, None),
    "lines with missing facts print anyway": ("    if missing then return nil end\n    return text", "    return text"),
    "blocked words get echoed": ('    if #words == 0 or #words > P.REFLECT_WORDS or blocked(words) then return nil end', '    if #words == 0 or #words > P.REFLECT_WORDS then return nil end'),
    "the story never moves on": ('local function nextBeat(ctx)\n', 'local function nextBeat(ctx)\n    do return nil end\n'),
    "same line twice running": ('if said == session.lastSaid and fireId(ctx, "repeated") then', 'if false then'),
    "drawer state ignored": ('    if rule.drawer and (ctx.facts.drawer or "closed") ~= rule.drawer then return false end\n', ''),
    "punctuation reaches the reply": ('    lower = string.gsub(lower, "[^%w%s]", " ")\n', ''),
    "Director ignores the tour": ('if level == 1 or not hasDrawer or book.boots <= rules.tour then return nil end', 'if level == 1 or not hasDrawer then return nil end'),
    "personas can repeat in a world": ('        book.met[chosen] = true\n        book.lastAt = book.boots\n    end\n    return chosen', '        book.lastAt = book.boots\n    end\n    return chosen'),
    "deep post not guaranteed": ('    if deepPost and level ~= 1 and hasDrawer and not book.met.duty and SC.TerminalPersonaData.duty then', '    if false then'),
    "talking never deepens it": ('    if ctx.norm ~= session.lastNorm and not looksMashed(tokens) then state.spoken = (state.spoken or 0) + 1 end\n', ''),
    "repeats and mashing deepen it": ('    if ctx.norm ~= session.lastNorm and not looksMashed(tokens) then state.spoken', '    if true then state.spoken'),
    "dark lines never used": ('    for tier = math.min(ctx.depth or 0, 3), 1, -1 do', '    for tier = 0, 1, -1 do'),
    "serious does not stop the descent": ('    if state.gentleUntil and (not hours or hours < state.gentleUntil) then return 0 end\n', ''),
    "a key beat needs a fact": (' or pickFrom(ctx, rule, rule.plain or {}, v, 0)', ''),
    "delivery ignores depth": ('        speed = D.speeds and D.speeds[depth + 1] or D.speed,', '        speed = D.speed,'),
    "one guests": ('v.GUESTS = count == 1 and "1 guest" or tostring(count) .. " guests"', 'v.GUESTS = tostring(count) .. " guests"'),
    "zero days": ('    if facts.days and facts.days >= 2 then v.DAYS = facts.days end', '    v.DAYS = facts.days'),
    "hour beats ignore the clock": ('    if rule.hour and ctx.facts.hour ~= rule.hour then return false end\n', ''),
    "follow-ups pull nothing": ('        if rule.pull then\n', '        if false then\n'),
    "one meters": ('v.METERS = whole == 1 and "1 meter" or tostring(whole) .. " meters"', 'v.METERS = tostring(whole) .. " meters"'),
    "clock without its zeros": ('v.HHMM = string.format("%02d%02d", math.floor(facts.hour), math.floor(facts.minute or 0))', 'v.HHMM = tostring(math.floor(facts.hour)) .. tostring(math.floor(facts.minute or 0))'),
    "machines before their dates": ('    if days and days < rules.firstDay then return nil end\n', ''),
    "spiffy anywhere": ('            if not D.brandOnly then wanting[#wanting + 1] = id end\n', '            wanting[#wanting + 1] = id\n'),
    "the chair ignores the player": ('    if rule.sitting ~= nil and (ctx.facts.sitting == true) ~= rule.sitting then return false end\n', ''),
    "memory survives a blocked word": ('local mirrored = fragment and P.reflect("my " .. fragment)', 'local mirrored = fragment and ("your " .. fragment)'),
}
java = GAME / "jre64/bin/java.exe"
classpath = f"{WORK};projectzomboid.jar"
failures = 0
only_harness = "--harness-only" in sys.argv
for label, (old, new) in MUTATIONS.items():
    if only_harness and old is not None:
        continue
    source = ENGINE
    if old is not None:
        if source.count(old) != 1:
            print("BAD MUTATION", label, source.count(old))
            failures += 1
            continue
        source = source.replace(old, new)
    path = WORK / "persona_engine_under_test.lua"
    path.write_text(source, encoding="utf-8", newline="\n")
    run = subprocess.run([str(java), "-cp", classpath, "KahluaTestRunner", str(path), *DATA, HARNESS],
                         cwd=GAME, capture_output=True, text=True, timeout=180)
    failed = run.returncode != 0
    reason = next((line for line in (run.stdout + run.stderr).splitlines() if "AssertionError" in line or "KahluaException" in line), "")
    reason = reason.split("persona_harness.lua:")[-1].strip()[:110]
    wanted = old is not None
    verdict = "ok" if failed == wanted else "WRONG"
    if failed != wanted:
        failures += 1
    print(f"{verdict:6} {'fails' if failed else 'passes':7} {label}{' -> ' + reason if failed else ''}")
    if old is None:
        for line in run.stdout.splitlines():
            if "corpus layers" in line or "all checks" in line or " misses: " in line or " descent: " in line:
                print("       ", line)
print("controls wrong:", failures)
sys.exit(1 if failures else 0)
