<!-- SPDX-License-Identifier: MIT -->

# Native bed sleep acceptance

`run-native.ps1` stages a fresh cache and the current payload under
`build/native-probes/`, then launches a hidden test process against that cache.
Use `-HistoricalRunRoot` if the prepared camp fixture has moved. The runner
reads the retained run and game installation and writes only to the staged
cache and capture directories.

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

`run-exhaustion-native.ps1` stages the same historical fixture and runs
`exhaustion-native.lua`. It exercises automatic chair-to-bed recovery at 100%
fatigue in a marked Rest bedroom and verifies native lying sleep, fatigue
recovery and alarm wake.
It also places the observer on the target pillow, waits for native tile
membership to settle, and checks that alignment rejects the occupied tile
without moving the sleeper. After the observer leaves, normal bed entry resumes.
Captures and evidence go to `build/exhaustion-sleep/native`.
