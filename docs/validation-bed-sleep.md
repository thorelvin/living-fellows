<!-- SPDX-License-Identifier: MIT -->

# Bed sleep animation validation

28 October 2026. Working changes on `living_fellows/0.26.74` after `ebea218d`.
The native bridge is rebuilt with the existing `42.21-isocompanion-24` protocol.
Save schemas are unchanged.

Normal bed rest already used `ISGetOnBedAction`, but never selected the settled
`OnBedAnim` state. The installed 42.21.0 animation graph selects `Bob_Awake` for
`Awake`, `Bob_Asleep` for `Asleep`, and supplies both transition clips. The
game's own bed menu uses this same variable.

Entry initializes `Awake`. After native bed entry and real sleep begin,
downtime selects `Asleep`. Normal completion and cancellation restore `Awake`
before the existing get-up and bed-clearance sequence. Single-tile cots that
use furniture seating retain that supported pose.

The initial live screenshot exposed the stock sprite-segment alignment problem:
the body extended past the bed. Ordinary sleep now shares the existing
bedridden-character entry geometry, extracted unchanged into `SCBedGeometry`.
Candidate selection and final native entry use the same safe approach. Blocked
or incomplete mattresses are skipped rather than admitted through chair access.
The south-facing double-bed adjustment verifies the same complete bed grid and
native square membership before aligning to its pillow lane and lifting only
the model for rendering.

A second live failure identified a right-side bridge correction crossing into
the next column. The correction now mirrors its half-tile X adjustment while
requiring the same target column. Tests retain the measured left and right
coordinates and reject non-finite or unrelated sources. No actor is recreated,
and the bridge retains its existing ownership, membership and rollback checks.

The gameplay suite covers sleep entry, ordinary completion, interrupted sleep,
cot fallback, fatigue recovery and existing alarm wake-up behavior. The core
suite verifies awake initialization, precise entry, movement-input handoff,
one-time mattress alignment, blocked entries and native get-up. Existing Strange
Folk geometry and bedridden-character regressions also pass. The final full
project gate passed all 29 stages in 142 seconds, including normal and debug
compilation of 240 Lua files, native bridge exposure and installer checks. The
rebuilt payload bridge has SHA-256
`86891ec178bac535617edcb4b135fda26247f01cdd71bc6fe5ea8d3d51ab84a7`.

A follow-up sleeping-speech report exposed a gap in the previous Lua-only
guard. The real-JAR regression failed before the fix because an awake speech
bubble and its native refresh lease survived `setAsleep(true)`. Sleep now clears
both at that transition. Native chat rejects sleeping actors, and the native
refresh loop also retires stale speech instead of extending it. Waking allows
fresh speech without replaying discarded lines.

The shared Lua guard also recognizes an active bed-sleep activity or a settled
sleeping bed pose when the native flag has not caught up. Dialogue rejects both
selected and resolved replies before creating history or transcript receipts.
Awake bed reading and get-up remain able to speak. Nickname acknowledgement no
longer falls back through the player's `Say` path; it uses the same guarded,
actor-local executor. The gameplay and UI regressions cover those cases.

The disposable native camp run reached `Bob_AwakeToAsleep`, then an active
`Bob_Asleep` track with `isAsleep=true`, `isOnBed=true` and health 100. Speech was
rejected during sleep; no secondary player or view was created. The ordinary
alarm wake restored `Awake`, cleared sleep and completed get-up with health 100
and verified native actor validity. The speech follow-up seeds a visible awake
line before bed, verifies it disappears at sleep, rejects new Lua, resolved and
direct native lines, and waits to confirm the refresh loop does not revive them.
After get-up, a fresh line succeeds without replaying sleeping dialogue.
The follow-up bed-edge check issues an ordinary `move_to` after native get-up.
Tess walked 2.38 tiles to clear floor with `Bob_WalkBat` contributing, normal
collision and health 100. No actor recovery occurred during that walk. The
accepted awake image is taken after walking, rather than holding the actor at
the first standing frame beside the mattress. The screenshots were checked
visually for mattress alignment, movement and the final clear floor position.

The visual fixture suspends this actor's background decisions during staged
sleep, then restores normal decisions for the walk. Existing work is cleared
at setup, as in the previous bed-exit acceptance fixture. An uncontrolled run
also exposed a separate `action_owned:encounter:scavenge:approaching` refusal
when a new move order met active scavenging. This pass does not change or claim
to validate busy-job order preemption.

This checks one existing bed and an alarm interruption in a prepared clone.
Every bed facing, modded furniture and a full native overnight sleep are not
claimed. The existing expedition-return lighting failure is unaffected.

Evidence:

- [Lying on the bed](../artifacts/bed-sleep/acceptance/bed-sleep-lying.png)
- [Standing after wake-up](../artifacts/bed-sleep/acceptance/bed-sleep-awake.png)
- [Walking away from the bed](../artifacts/bed-sleep/acceptance/bed-walking-away.png)
- [Native state and animation results](../artifacts/bed-sleep/acceptance/evidence.txt)
- [Sleeping-speech regression before and after](../artifacts/bed-sleep/acceptance/sleep-speech-regression.txt)
- [Full project gate](../artifacts/bed-sleep/acceptance/project-gate.txt)
- [Fixture scope and runner](../artifacts/bed-sleep/README.md)

Local installation is outside this validation run.

## Exhaustion regression, 29 October

A 0.26.74 support report showed a base resident at fatigue 1.0 in a long
`sit/waiting` action, with endurance 1.0. Another resident repeatedly chose
reading. The bedrooms were on the same floor and marked Rest; the tester
reported that sleep worked in 0.26.72.

Comparison with 0.26.72 found two regressions in the newer bed-entry path:

- `BedGeometry.entry` used actor-spawn safety for bedside walking positions.
  The installed 42.21.0 `IsoGridSquare.isSafeToSpawn()` requires more than
  seven connected squares. A cramped but walkable bedroom can fail that test.
  Bed entry now accepts that specific failure after loaded-floor/static
  obstruction checks have passed, provided no furniture or other moving actor
  occupies the entry. Strict construction/spawning checks are unchanged.
- Double-bed alignment handled only the approach lane and a northward shift.
  The real right-side entry left its settled anchor half a tile outside the
  mattress, producing `bed_mattress_alignment_failed` followed by reading.
  Geometry now supplies both pillow positions. The bridge also accepts a
  bounded half-tile side correction after verifying the selected complete
  south-facing mattress, native bed flags, loaded same-room membership, empty
  target and an edge without walls, doors or windows. It preserves native
  posture and atomically updates square/interpolation references. Unrelated
  positions and corrections exceeding half a tile remain rejected.

The report also exposed a pre-existing chair trap: the bed capability probe
rejected all seated actors, while chair completion intentionally retained a
passive posture. Bed-only discovery now works while seated. A tired passive
sitter, or an exhausted resident doing a long sit/read/listen/computer action,
first finds an eligible available bed, then cancels through the existing
rollback and native get-up path. Discovery retries are bounded to five-second
intervals. Panic, danger, orders, medical ownership, vehicle travel and bed
occupancy retain their checks. Support reports include the last sleep check.

Regression tests cover cramped entry, actor occupancy, missing/solid floor,
both pillow lanes, bounded east/west corrections, active and passive chairs,
panic and deferred native get-up.
The native fixture `artifacts/bed-sleep/exhaustion-native.lua` uses an existing
bedroom, marks it Rest through BaseLife, starts a real chair action, raises
fatigue to 100%, and thereafter calls the ordinary automatic downtime path.
It checks the lying sleep animation, falling fatigue and ordinary alarm wake.

The final paired Lua/native payload passed the full project gate: 29/29 stages,
243 Lua files compiled in normal and debug modes, 154 seconds overall. Native
bridge protocol remains `42.21-isocompanion-24`; the rebuilt payload SHA-256 is
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.

The final native run passed in the disposable clone. At fatigue 1.0 the
companion left the occupied chair, used the marked bedroom's double bed and
entered `Bob_Asleep`. An occupied pillow rejected the native correction
without changing the sleeper's coordinates; clearing the tile allowed normal
entry to resume. Fatigue fell to 0.995379 with health 100. The alarm cleared
sleep normally, and no secondary view was created. The renderer capture shows
the body lying on the mattress.

- [Exhausted in the chair](../artifacts/bed-sleep/exhaustion-acceptance/exhaustion-chair.png)
- [Automatic sleep on the mattress](../artifacts/bed-sleep/exhaustion-acceptance/exhaustion-sleeping.png)
- [Native results](../artifacts/bed-sleep/exhaustion-acceptance/evidence.txt)
- [Final full gate](../artifacts/bed-sleep/exhaustion-acceptance/project-gate.txt)

This live pass covers one marked Rest bedroom and its right-side double-bed
entry, a blocked pillow, early fatigue recovery and alarm wake. It does not
claim every furniture facing or a full overnight sleep. The main game profile
and the user's saves were not changed.
