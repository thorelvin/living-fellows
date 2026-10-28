<!-- SPDX-License-Identifier: MIT -->

# Companion speech bubble spacing

28 October 2026. Working changes on `living_fellows/0.26.74` after `ebea218d`.
The native bridge retains protocol `42.21-isocompanion-24` and existing saves.

The previous nameplate spacing prepended a newline to every actor-owned spoken
line. The native backdrop includes the resulting empty row. The refresh then
sent the unpadded line through `SayDebug`; the text mismatch made the engine
reparse the newest row with debug settings instead of only extending its clock.
The former test asserted that the newline existed, without checking its visual
effect.

The bridge now creates a companion-only `ChatElement` subclass at actor
construction, retaining the stock maximum history rows and talker type. It
delegates all native chat behavior and offsets only the final four-argument
`renderBatched` call. The stock three-argument path dispatches through that same
override. X, player index and radio filtering pass through unchanged. Clearance
uses the Small UI font height plus eight screen pixels, with a 22-pixel minimum;
camera zoom is not applied a second time. Player and other-mod chat elements are
unchanged.

Displayed, retained and refreshed text are identical. Only authored line breaks
remain. The subsequent [speaker colour implementation](validation-speech-colors.md)
replaces `SayDebug` with clock-only refresh of each emission's existing newest
viewport rows. It preserves their RGB, font and formatting without creating a
row in another viewport. Sleep clears the replacement chat element through the
existing guarded native cleanup.

`SCSpeechNameplateLiftTest` now observes the render arguments, normal and larger
font metrics, missing metrics, both render overloads and a separate ordinary
chat element. It also checks single- and multiline text through emission and
refresh. The real-game-JAR cleanup test confirms construction uses the new
renderer and retains sleep suppression, wake, ownership and teardown behavior.

Live acceptance uses the prepared disposable camp and production speech, rest,
get-up and walking paths. All seven enabled zoom levels (50, 75, 100, 125, 150,
175 and 200 percent) were captured with short, authored multiline and naturally
wrapped dialogue: 21 cases. The unscaled crops were reviewed for the extra
empty row and nameplate separation. All remain readable without overlap. Other
camp speech and ordinary history are allowed; they are not placeholder rows.

The actor first completes a genuine walk away from the bed, without recovery,
before movement is held for the comparison. The real player moves to a nearby
clear observer tile so the closest zoom keeps the speaker within the viewport.
Background decisions are suspended for staged sleep and the static comparison,
then restored for the walk. This validates layout and physical bed clearance,
not autonomous activity selection or busy-job command preemption.

The full project gate passed all 29 stages in 142 seconds, including native
cleanup and exposure, UI and gameplay regressions, and normal/debug compilation
of 240 Lua files. Payload bridge SHA-256:
`86891ec178bac535617edcb4b135fda26247f01cdd71bc6fe5ea8d3d51ab84a7`.

Representative original game screenshots and logs:

- [50 percent, wrapped](../artifacts/bed-sleep/acceptance/speech-zoom-050-wrapped.png)
- [100 percent, multiline](../artifacts/bed-sleep/acceptance/speech-zoom-100-multiline.png)
- [200 percent, wrapped](../artifacts/bed-sleep/acceptance/speech-zoom-200-wrapped.png)
- [Walking clear after sleep](../artifacts/bed-sleep/acceptance/bed-sleep-awake.png)
- [Native evidence](../artifacts/bed-sleep/acceptance/evidence.txt)
- [Full project gate](../artifacts/bed-sleep/acceptance/project-gate.txt)

All 21 full captures and the labelled, unscaled review crops remain in
`build/bed-sleep/native` and `build/speech-layout` respectively. The nine
representative captures at 50, 100 and 200 percent are retained with the fixture.
Actual enlarged UI fonts and an active secondary viewport were not live-tested;
font metrics and player-index isolation have automated coverage.

Local installation is outside this validation run.
