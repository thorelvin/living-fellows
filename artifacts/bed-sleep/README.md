<!-- SPDX-License-Identifier: MIT -->

# Native bed sleep acceptance

`run-native.ps1` uses the prepared disposable camp clone named in the script.
It copies the current payload only into that clone and launches an owned hidden
process. It does not install into the player's game or alter the original save.

The fixture places a recruited companion beside an existing sprite-grid bed
with an available native entry, seeds fatigue, hunger and thirst, and leaves
bed selection, entry and exit to
the production downtime and native furniture actions. Midday lighting and hidden
info/map panels make screenshots readable. The initial placement does not test a
long approach route.

The selected actor's existing work is cleared and its background decisions are
held during staged sleep. Native actions and the production downtime module
still own bed selection, entry, sleep and get-up. Normal decisions are restored
for a real `move_to` afterward. The probe requires at least 1.5 tiles of travel
without actor recovery, normal collision and a clear floor position. Only then
is movement held for the static zoom comparison.

The probe requires a visibly contributing `Bob_Asleep` animation track, native
sleep and bed flags, suppressed speech and unchanged solo ownership. It seeds
an awake speech bubble before bed, verifies its retirement at sleep, and checks
Lua dialogue, transcript and direct native chat rejection while sleeping. It then
wakes through the ordinary camp-alarm path and requires a standing, healthy,
valid native actor with fresh speech restored and no replay of suppressed lines.
Screenshots are captured by the game's own renderer and
inspected for mattress alignment. Geometry traces also record nearby blocked or
incomplete beds; instrumentation preserves the production movement results.

The same fixture captures short and authored multiline speech before bed. The
native renderer lifts the complete bubble above the name; its text remains
unchanged across refreshes. Existing dialogue history and other camp speakers
may remain visible. Fresh speech after waking is allowed; the replay assertion
specifically rejects the old fixture and suppressed sleeping lines.

After waking, the zoom matrix uses every enabled native zoom level, with short,
authored multiline and naturally wrapped dialogue at each. Native zoom scrolling
and settling are used. This actor's movement and ambient dialogue are held only
for those controlled samples; rendering, speech emission and refresh stay on
production paths. Auto-zoom and the prior camera target are restored afterward.

Local captures are in `build/bed-sleep/native`; retained evidence and exact
coverage are linked from [validation](../../docs/validation-bed-sleep.md).
