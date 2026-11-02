"""Audit of every persona line: voice rules, fit on the real screen, holes on key beats, duplicates, forbidden text."""
import collections
import re
import sys
import textwrap
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "SurvivorCompanion/42/media/lua/client"
RULE = re.compile(r'\{ id = "([a-z0-9_]+)"')
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
FORBIDDEN = re.compile(
    r"minion|the cake|still alive|aperture|glados|wheatley|claptrap|pandora|vault hunter|robco|termlink|vault-tec|"
    r"\b(fuck|fucking|shit|bitch|cunt|nigg|fag|retard|rape|whore|slut)\b", re.I)
# Words that break the fiction, and things that did not exist yet in July 1993.
IMMERSION = re.compile(
    r"\btiles?\b|\bmoodles?\b|\bgame\b|\bgames\b|\bplayers?\b|\bmod\b|\bsandbox\b|\bxp\b|\bnpcs?\b|\bsave file\b|\breload\b|\brespawn|"
    r"\bspawn|\bquest\b|\bonline\b|\binternet\b|\be-?mails?\b|\bwebsite\b|\bwifi\b|\bcell ?phone\b|\bsmartphone\b|\btext message\b|\bdownload\b|"
    r"\bupload\b|\btrained on\b|\bnews feed\b|\bcoupon code\b|\bon-brand\b|\bAI\b|\blol\b|\bgoogle\b|\bapp\b", re.I)
SELF_HARM = re.compile(
    r"kill yourself|you should die|you should end|end it all|give up\b|no point in|nobody would miss|you are worthless|you're worthless|"
    r"better off dead|you deserve to die|nobody cares about you|you are nothing|you're nothing|should have died|it would be easier if you", re.I)
errors, notes = [], []
all_lines = collections.defaultdict(set)


def field_lines(chunk):
    """Only text the player sees: skip words, phrases, ids, sets and everything before lines =."""
    out = []
    for match in re.finditer(r"(?:lines|plain) = \{", chunk):
        depth, i = 1, match.end()
        in_string = False
        while depth and i < len(chunk):
            ch = chunk[i]
            if ch == '"' and chunk[i - 1] != "\\":
                in_string = not in_string
            elif not in_string and ch == "{":
                depth += 1
            elif not in_string and ch == "}":
                depth -= 1
            i += 1
        out.extend(STRING.findall(chunk[match.end():i]))
    return out


def dark_lines(source):
    match = re.search(r"\n\s*dark = \{(.*)\Z", source, re.S)
    return STRING.findall(match.group(1)) if match else []


for name in ("spiffy", "ellis", "duty"):
    source = (ROOT / f"SCTerminalPersona{name.title()}.lua").read_text(encoding="utf-8")
    head = source.split("dark = {")[0]
    lines = field_lines(head)
    dark = dark_lines(source)
    every = lines + dark
    ids = RULE.findall(source)
    for rule_id, count in collections.Counter(ids).items():
        if count > 1:
            errors.append(f"{name}: duplicate rule id {rule_id}")
    for text in every:
        plain = text.lstrip("~")
        if plain in all_lines and name not in all_lines[plain] and len(plain) > 30:
            errors.append(f"{name}: line also used by {all_lines[plain]}: {plain[:60]}")
        all_lines[plain].add(name)
        if not text.isascii():
            errors.append(f"{name}: not ascii: {text[:60]}")
        if FORBIDDEN.search(text):
            errors.append(f"{name}: forbidden word: {text[:70]}")
        if IMMERSION.search(text):
            errors.append(f"{name}: breaks the fiction: {text[:80]}")
        if SELF_HARM.search(text):
            errors.append(f"{name}: self-harm wording: {text[:70]}")
        if len(plain) > 240:
            errors.append(f"{name}: row over 240 chars ({len(plain)}): {plain[:60]}")
        if text.startswith("~") and len(plain) > 90:
            notes.append(f"{name}: slow row is long ({len(plain)}): {plain[:70]}")
    if name == "ellis":
        for text in every:
            if "!" in text:
                errors.append(f"ellis never exclaims: {text[:70]}")
    if name == "duty":
        for text in every:
            if "!" in text:
                errors.append(f"duty never exclaims: {text[:70]}")
            if re.search(r"[a-z]{3,}", re.sub(r"\{[A-Z]+\}", "", text)) and text == text.lower():
                notes.append(f"duty in lower case (engine uppercases it): {text[:50]}")
    bang = sum(t.count("!") for t in lines) / max(1, len(lines))
    print(f"{name}: rules {len(ids)}, base lines {len(lines)}, dark lines {len(dark)}, exclamations per base line {bang:.2f}")
    # Words the player sees most often.
    words = collections.Counter(w.lower() for t in every for w in re.findall(r"[A-Za-z']{5,}", t))
    print("   most used:", ", ".join(f"{w} {c}" for w, c in words.most_common(10)))

# Real screen fit: 70 columns by about 14 rows without the header and hints, and a smaller compact layout.
for name in ("spiffy", "ellis", "duty"):
    source = (ROOT / f"SCTerminalPersona{name.title()}.lua").read_text(encoding="utf-8")
    worst = []
    visible = re.sub(r"(?:phrases|words|all) = \{[^{}]*\}", "", source)
    for block in re.findall(r"\{ (\"(?:[^\"\\]|\\.)*\"(?:,\s*\"(?:[^\"\\]|\\.)*\")+) \}", visible):
        rows = STRING.findall(block)
        if not any(" " in row for row in rows):
            continue
        wrapped = sum(max(1, len(textwrap.wrap(row.lstrip("~"), 70))) for row in rows)
        worst.append((wrapped, rows[0][:60]))
    worst.sort(reverse=True)
    print(name, "tallest replies at 70 columns:", worst[:3])
    if worst and worst[0][0] > 14:
        notes.append(f"{name}: a reply is {worst[0][0]} rows at 70 columns: {worst[0][1]}")

for note in notes:
    print("NOTE ", note)
for error in errors:
    print("ERROR", error)
print("errors", len(errors), "notes", len(notes))
sys.exit(1 if errors else 0)
