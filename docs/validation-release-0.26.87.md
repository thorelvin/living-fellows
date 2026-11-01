<!-- SPDX-License-Identifier: MIT -->

# 0.26.87 validation record

Implemented on `living_fellows/0.26.87`, based on synchronized 0.26.86 commit
`d26b1480`. Target: Project Zomboid 42.21.0, single player. Bridge protocol
remains `42.21-isocompanion-27`; only the bridge release metadata changes.

## Scope

Building discovery is explicit and interaction-bound. Connect, Equipment,
opening a computer and the ordinary service pulse do not start it. A separate
100 ms scheduler task grants 64–128 tiles per real second, carries fractions,
caps a slice at 32 tiles and obeys the scheduler deadline. Closed, paused or
powerless intervals cannot become catch-up credit. A retired window or old
computer cannot stop a new owner's scan.

Separate saved collections retain up to 256 controls and 256 read-only finds.
Passive finds receive no object ModData or command identity. Only finds on
covered tiles can be pruned; unavailable controls remain for existing routines.
Existing schema-1 panels gain optional fields without changing save schemas.
Closing pauses, Abort ends, and reload retains records without retaining the
runtime cursor. XP is marked before its native callback to prevent replay.

The display uses cached snapshots at most five times per second. Status reads
touch visible controls at most once per second. Drawing makes no world reads.
The layout keeps numbered rows and footer actions within the screen at 3, 6
and 10 rows in green, sand, aqua and purple. Modal prompts block hidden clicks
and paging. Keyboard Up wraps correctly under Kahlua's signed remainder rules.
The original three UI sounds have deterministic sources and hashes in the
asset manifest; they emit no world noise.

## Automated checks

The real-JAR Kahlua UI suite passes. It exercises rate limits, per-floor and
unloaded accounting, negative floors, empty extra camp levels, pause/resume,
Abort/restart, old panels/reload, stale window/abort ownership, independent
ceilings, passive isolation, pruning, XP, power and budget loss. UI tests cover
selection across page boundaries, input, measured clipping, visible status
polls, confirmations, reports and feedback throttling.

Negative controls run modified copies in temporary test directories and
require a nonzero process exit from an intended assertion. Production files
are hashed before and after; they are never modified by the mutation tests.
All 26 negative controls fail their intended assertions, including retired
window/abort ownership, modal input, keyboard wrapping and the reduced-height
floor layout. The full UI runner also passes its 93 Python contract tests.

`scripts/Test-Project.ps1 -Jobs 4` passes **29/29 stages** in 159 seconds
(`PROJECT_TEST_PASS`). Log: `build/release-0.26.87-project-gate-final.txt`.
Workshop and standalone packaging pass as 0.26.87. The reproducible Java 17
bridge has SHA-256
`6ec71f11b65199bfec786cf54e0954b5c8d433593de27bed58317feca062e68d`.

## Native acceptance

Run `SC-Harness-20261101-115459-d63b4fba` passes the full building-scan probe
against a disposable copy of the Skills5 Rising save, with Living Fellows
alone, real engine sound and an isolated source bridge. It uses real
computers, native charged battery backups, normal installation/connection
APIs and successful native password actions. It does not spoof power, scan
results, clocks, security checks, device rows or floor bars. The source save
and installed game files remain unchanged.

| Native site | Tiles | Observed / expected time | Controls / read-only | Result |
| --- | ---: | --- | --- | --- |
| Saved camp building | 2,244 | 23.899 / 23.375 s | 24 / 5 | Complete; empty extra camp levels hidden |
| Rosewood fire station | 9,310 | 97.199 / 96.979 s | 111 / 6 | Complete; native definition spans levels 0–4 |
| Large native building | 33,975 | 357.600 / 353.906 s | 143 / 3 | Partial; 13,950 tiles out of range |

All use Electrical 5 and the real 96 tiles/second rate. Controls were found on
each level of the fire station's native definition. These level numbers come
from the game, not an architectural interpretation of its storeys. The probe
also opens a device during discovery and returns to the radar, then verifies
closing holds the cursor and reopening requires explicit Resume.

CPU drawing measurements decorate the original draw function without changing
its output. They use the native millisecond clock and report means across many
frames, not GPU time or a high-resolution benchmark:

| Site | Idle / scanning mean draw time | Idle frame p50 / p95 | Scanning frame p50 / p95 |
| --- | --- | --- | --- |
| Camp | 0.256 / 0.291 ms | 17 / 29 ms | 16 / 26 ms |
| Fire station | 0.110 / 0.355 ms | 17 / 18 ms | 17 / 19 ms |
| Large building | 0.144 / 0.433 ms | 17 / 18 ms | 17 / 22 ms |

Engine PNGs are retained with the run ID under the harness screenshot folder.
An early running-screen image was shown before final polish. The initial run
`SC-Harness-20261101-114452-3b9519dc` was not a pass: its test omitted hidden
empty-roof accounting, and fixture installation ran before teleport settled.
Both were corrected before the passing full run. Initial colour captures were
one rendered frame behind their labels; the probe now reopens through native
theme setup and waits before capture.

Final short run `SC-Harness-20261101-121333-33fcae93` passes with the latest
source, including another real 2,244-tile scan, device open/return and explicit
pause/resume. All four engine captures were inspected: green, sand, aqua and
purple have matching glass, text and EMMA artwork, with no separator/footer
overlap. Native captures use the full-size layout; reduced-height layouts and
modal/keyboard edge cases are verified by the automated UI tests.

## Review fixes

Review of `a3f32838` found the survey engine sound and the screen unfinished.
The sections above describe that first push; this one supersedes them where they
differ. No Java changed, so the bridge SHA-256 above still stands.

- Nothing overlaps in the list column. The "no equipment" message shows only when
  no scan exists, so a running scan or a rescan no longer denies its saved rows.
- EMMA's whole report wraps under the list and stays until something replaces it.
  Short notices fade after eight seconds and sit below the probe line, which no
  longer disappears for a whole scan. A finished scan shows no stale probe line.
- Counts are singular or plural as they should be, in the header and the report.
- A camp's levels above the building's plan no longer take the player's time.
  They sweep on the frame budget alone, stay out of the bars, the floor count and
  the out-of-range total unless something answers there, and progress counts the
  planned levels. The one-storey camp at Electrical 5 went from 24.35 s to 10.65 s
  against 7.79 s for its planned level.
- The radar returns to the sweep when its chosen level leaves the list, and a new
  scan always follows the sweep.
- The wheel pages in the direction it turns, on this page and on the older grid
  and radio reading pages.
- Esc from a device prompt cancels the request and says so, rather than carrying
  a live Y/N to a page that cannot show its question.
- The computer doing the scan no longer lists itself, so read-only counts are one
  lower than the table above and EMMA's "nothing answered" line can fire.
- The rain is brighter while a scan runs and fainter when idle.

`tests/ui/SCBuildingScanScreenTests.lua` drives the real terminal, engine, services
and page together, which the stubbed page test could not. All 49 negative controls
fail their intended assertions: the original 26 and 23 new ones for these fixes.
`scripts/Test-Project.ps1 -Jobs 4` passes 29/29 stages.

Run `SC-Harness-20261101-144938-5288a6d5` repeats the full native acceptance: 24
pass, 0 fail, basement skipped, no Lua errors. Rosewood took 97.283 s against
96.979 s with 111 controls on 5 levels. The large building took 355.782 s against
353.906 s with 13,950 tiles out of range. Mean scan draw was 0.25 to 0.42 ms and
frame p95 stayed between 19 and 27 ms.

A throwaway probe, run `SC-Harness-20261101-145916-037fc015`, started the scan from
the real Local services menu and captured the start of a scan, the empty Equipment
page, the finished report, Esc from a live device prompt and a restart. All were
inspected. The one-time XP award added 1.25 real points from the granted 5, and
all three new sounds returned real handles. Power circuits with 70 lights costs
about 1 ms more per frame than the services page, with no change in frame time.

Not proven live: a real basement, as above. Wheel direction comes from the vanilla
list box, where a negative delta scrolls up, and the terminal's own transcript;
the harness cannot turn a physical wheel. Sound handles show a cue started, not
how it sounds.

## Limits and documentation

No suitable bounded basement candidate was found in native building metadata;
the live basement case is explicitly skipped. Basement discovery passes
deterministic engine tests but remains unproven in a real basement. This work
does not certify the separately documented combat-facing and camp navigation
limitations of 0.26.86.

The repository computer guide and the separately maintained Field Guide now
explain Discover, Equipment, Resume, Abort, controls, read-only finds and limits.
The Field Guide's Twenty-Third Printing updates the EMMA quick card and adds a
pixel-identical lossless scanner image from the passing Rosewood run, linked at
full size. Its web and self-contained builds pass anchor and HTML checks.

The release follow-up covers committing and pushing 0.26.87 and publishing
the Field Guide on `gh-pages`. Local installation and Workshop upload are
separate actions.
