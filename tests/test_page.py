"""Structural checks on the faceplate page.

There is no browser or JS runtime in this project's toolchain, so a syntax error
in index.html would ship as a blank page with no warning. These checks are not a
parser -- they catch the failure modes that actually happen when hand-editing a
single-file UI: unbalanced brackets, an unterminated string or comment, a
function that is called but never defined, a getElementById with no matching
element, and malformed CSS colours.

    python tests/test_page.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

PAGE = Path(__file__).resolve().parent.parent / "host" / "web" / "index.html"

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)
    print(f"  FAIL {message}")


def ok(message: str) -> None:
    print(f"  ok   {message}")


source = PAGE.read_text(encoding="utf-8")

for tag in ("<style>", "</style>", "<script>", "</script>"):
    if source.count(tag) != 1:
        fail(f"expected exactly one {tag}, found {source.count(tag)}")

script = source.split("<script>", 1)[1].split("</script>", 1)[0]
style = source.split("<style>", 1)[1].split("</style>", 1)[0]

# ---------------------------------------------------------------- brackets

PAIRS = {"(": ")", "[": "]", "{": "}"}
CLOSERS = set(PAIRS.values())

stack: list[tuple[str, int]] = []
line = 1
in_string: str | None = None
in_comment: str | None = None
escaped = False
index = 0
broken = False

while index < len(script):
    char = script[index]
    if char == "\n":
        line += 1

    if in_comment:
        if in_comment == "//" and char == "\n":
            in_comment = None
        elif in_comment == "/*" and script[index:index + 2] == "*/":
            in_comment = None
            index += 1
    elif in_string:
        if escaped:
            escaped = False
        elif char == chr(92):          # backslash
            escaped = True
        elif char == in_string:
            in_string = None
    elif script[index:index + 2] == "//":
        in_comment = "//"
        index += 1
    elif script[index:index + 2] == "/*":
        in_comment = "/*"
        index += 1
    elif char in ('"', "'", "`"):
        in_string = char
    elif char in PAIRS:
        stack.append((char, line))
    elif char in CLOSERS:
        if not stack:
            fail(f"unmatched {char!r} near line {line}")
            broken = True
            break
        opener, opened_at = stack.pop()
        if PAIRS[opener] != char:
            fail(f"{opener!r} (line {opened_at}) closed by {char!r} (line {line})")
            broken = True
            break
    index += 1

if not broken:
    if stack:
        fail(f"unclosed {[(c, ln) for c, ln in stack][:5]}")
    elif in_string:
        fail("unterminated string literal")
    elif in_comment == "/*":
        fail("unterminated block comment")
    else:
        ok("script brackets balanced, strings and comments terminated")

# --------------------------------------------------------------- functions

missing = [name for name in
           ("drawScope", "drawDial", "renderPresets", "renderResults",
            "send", "poll", "jolt", "liveNow", "escapeHtml", "setStatus",
            "disableAll", "waveData", "fitCanvas", "dialFromDrag", "render")
           if f"function {name}" not in script and f"const {name}" not in script]
if missing:
    fail(f"referenced but never defined: {', '.join(missing)}")
else:
    ok("all referenced helpers are defined")

# ------------------------------------------------------------------- DOM

orphans = sorted({node for node in re.findall(r'el\("([A-Za-z0-9_]+)"\)', script)
                  if f'id="{node}"' not in source})
if orphans:
    fail(f"el() targets with no element: {', '.join(orphans)}")
else:
    ok("every el() target exists in the markup")

for node in ("dial", "scope", "expand"):
    if f'id="{node}"' not in source:
        fail(f"missing #{node}")

# ------------------------------------------------------------------- CSS

# Catches the autocomplete-style corruption that produced "#b93career".
malformed = sorted(set(re.findall(r"#[0-9a-fA-F]{2,}[g-zG-Z][0-9a-zA-Z]*", style)))
if malformed:
    fail(f"malformed colour literals: {', '.join(malformed)}")
else:
    ok("no malformed colour literals")

for prop in ("--phosphor", "--grid", "--crt", "--accent"):
    if prop not in style:
        fail(f"missing custom property {prop}")

if style.count("{") != style.count("}"):
    fail(f"CSS braces unbalanced: {style.count('{')} open, {style.count('}')} close")
else:
    ok("CSS braces balanced")

# ------------------------------------------------- honesty about the data

# The scope must only agitate on a confirmed result, never on a bare timer:
# an animation implying reception we cannot observe would be a lie.
stray = []
for match in re.finditer(r"jolt\(\)", script):
    if script[max(0, match.start() - 9):match.start()] == "function ":
        continue  # the definition itself
    window = script[max(0, match.start() - 300):match.start()]
    if "applied" not in window:
        stray.append(script.count("\n", 0, match.start()) + 1)
if stray:
    fail(f"jolt() called outside a confirmed-result path, line(s) {stray}")
else:
    ok("scope only reacts to confirmed results")

print()
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("PAGE STRUCTURE OK")
