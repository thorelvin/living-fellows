<!-- SPDX-License-Identifier: MIT -->

# Terminal transcript boundary regression

29 October 2026, `living_fellows/0.26.75`, following the computer/logo update.

The report shows the July 1 Brooks Library entry, Summer reading, reaching or
crossing the transcript/menu separator. Wrapping previously used a character
count based on an average M glyph advance. The transcript had no right gutter
or paint clip, and its cache tracked only the integer column count.

Transcript wrapping now checks actual native font measurements at the drawing
scale, with a gutter before the divider. Complete records, partial typewriter
rows and their cursor, and thinking messages use the same pixel budget. Long
tokens split into fitting parts without discarding characters. The cache also
tracks pixel width, font, scale and character estimate, so width/focus changes
cannot reuse a stale wrap merely because the column count stayed the same.

The transcript is painted inside its own clip after the menu. The clip ends
before the separator, including the text halo, and is cleared after painting
or a renderer exception. Menu, header, hints and input retain their own areas.
Stored records and notes are not changed by wrapping.

The regression test reproduced the overflow before the fix with glyph widths
larger than the M estimate. It now covers pixel fit, long tokens, complete
archive characters, live cursor and thinking rows, subpixel width changes with
the same estimated columns, and clip cleanup after painting failures. Existing
reading tests cover menu/chat reflow, resizing, paging, incoming replies and
scrollback trimming. Reference-file scroll expectations use the new displayed
row counts while retaining their beginning-of-file assertion.

The native fixture is `artifacts/emma/terminal-wrapping-native.lua`, run by
`artifacts/emma/run-terminal-wrapping-native.ps1`. It uses the clone's real
powered desktop and the actual `brooks_irma` Summer reading record, with a
Brooks header preview and purple phosphor matching the report. It checks every
native line's pixel width and the complete archive characters, then repeats
the check after a menu/chat focus round trip. Original computer archive/theme
are restored afterward; the main game and user saves are outside the clone.

The UI regression passes 44 pixel-wrapping checks. The full project gate passes
29/29 stages with 243 Lua files compiled normally and with debug enabled;
stages took 132.3 seconds, 136 seconds overall. The bridge and save schemas
are unchanged.

The first native attempt exited at its first world frame after a stock
WeatherFxMask/shader initialization exception, before the probe opened the
terminal. A serial retry passed without changing production code. The final
Brooks record measured at most 672 pixels against a 681.10 pixel text budget;
its halo/clip ended before the divider at x=842.72. The same check passed after
the focus round trip, with all archive characters accounted for.

- [Brooks Library record](../artifacts/emma/native-acceptance/emma-wrap-brooks.png)
- [After changing focus](../artifacts/emma/native-acceptance/emma-wrap-focus-return.png)
- [Native results](../artifacts/emma/native-acceptance/terminal-wrap-evidence.log)
- [Full project gate](../artifacts/emma/native-acceptance/terminal-wrap-project-gate.log)

The tested payload was then applied to the existing local developer install,
retaining Debug. All 338 installed files match the ownership manifest and the
installed transcript code matches the tested source. Details are retained
locally in `build/local-wrapping-install-verification.json`.
