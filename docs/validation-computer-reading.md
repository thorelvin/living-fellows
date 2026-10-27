<!-- SPDX-License-Identifier: MIT -->

# Computer reading and password recovery

27 October 2026. Working continuation after `0d8791e6` on
`living_fellows/0.26.71`, included in `living_fellows/0.26.72`, for
Project Zomboid 42.21.0 single-player.
The native bridge, computer save data and security rules are unchanged.

## Changes

Actual 720p game captures showed password recovery opening at the bottom of
the board, hiding instructions and remaining attempts. Long camp replies
also opened at their tail, cutting off the question and first people.

Recovery now opens at the first candidates. Attempts, the latest result and
the game-time lockout remain above the independently scrolling board and
guess history. Page changes invalidate old click targets. Lockout exposes no
actionable words, and expiry clears stale failure feedback without rerolling
the puzzle or restoring spent bracket bonuses.

Completed replies open at their question and first answer. A row and wrapped
line identify the current reading position while output arrives or the view
resizes. Going to the newest output restores normal following. Transcript
retention remains capped at 400 rows. The footer describes paging and the
visible range without covering the final line or a clickable word. Power
failure clears the reading anchor so its warning remains visible.

## Automated verification

The focused UI suite passes with 377 recovery/reading checks, including actual
painting bounds at 480x480, 480x540, 640x480, 1280x720, 1920x1080 and 3840x2160.
Cases cover first and last puzzle pages, word click targets, one wrong
guess, pinned feedback, lockout and expiry, unchanged puzzle words, wrapped
guess history, long roster replies through the real terminal logic, scrolling during typing,
completion, reflow, bounded history and power loss. Portable identity,
archive, notes and visit count remain intact. Existing UI regressions remain
active, including confirmed medic requests and infection-crisis refresh.

The new recovery regression fails against the preceding terminal source at
its first-candidate/visible-attempt assertion. The full project gate passes
all 29 stages in 152 seconds, including normal and debug compilation of all
228 payload Lua files, native contracts, gameplay, adapters and packaging.
Logs are under `build/computer-reading/`; the earlier focused UI output is
`build/review-four-commits/computer-reading-ui.log`.

## Existing-world native verification

The cloned Rising world used the original office desktop at `12035,6739,0`
and a naturally locked GigaMart office desktop at `12028,6849,1`. Naturally
unlocked pharmacy and office machines were inspected and skipped while
looking for a locked machine. No desktops were spawned and no power, lock
or colour overrides were applied. The GigaMart machine naturally selected
the rare purple palette.

Both screens opened through the normal native Use computer timed action.
The camp query used actual crew records: its completed reply began at
`who is here`, and native Page Down advanced the view. On the locked store
computer, native Page Down advanced the recovery board. Entering the visible
incorrect word MARGIN produced 0/6 likeness and spent exactly one attempt,
from four to three, without losing the page. The pinned status and feedback
were visually checked in the resulting native game screenshots at 1280x720.

The test relocates the observer for setup and uses the real native keyboard
callbacks. It does not validate walking between the buildings, physical key
injection, autonomous companion visits or native rendering at every tested
resolution. Other crew and game physics continue running. The source save
and installed game are untouched; the wrong guess changes only the clone.

The repeatable probe and launcher are
`artifacts/emma/terminal-reading-native.lua` and
`artifacts/emma/run-terminal-reading-native.ps1`. The launcher requires the
existing disposable harness cache and writes temporary captures under
`build/computer-reading/native/`. Compact evidence and selected game captures
are retained in `artifacts/emma/native-acceptance/` with reading labels.
