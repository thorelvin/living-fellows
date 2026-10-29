# Combat investigation: 0.26.75

29 October 2026. Source base: `6863ee42`, branch `living_fellows/0.26.75`.
Pinned game: Project Zomboid 42.21.0, native protocol `42.21-isocompanion-24`.

## Finding

A complete failure of companion fighting or zombie damage was not reproduced.
The tester's short melee coordination holds were reproduced, and fights were
substantially less effective under the logged tiredness/equipment conditions.
Those observations do not establish a new .75 defect or identify which condition
causes the difference. Subsequent hardening reproduced and fixed the separate
logic faults described below; it does not establish that every reported symptom
has the same cause.

The combat, zombie targeting and zombie attack Lua modules have no changes
between release .72 (`170f2312`) and this source base. Other systems changed,
including rest and runtime recovery, so this does not exclude an indirect
regression.

## Supplied playtester evidence

The attachment set ending `5637795b-bb96-44e4-a75b-17fcad89c655` contains one
console log and two Support snapshots. These describe a different world from
the local cloned-save fixtures.

- The console confirms release .75 and native protocol 24 loaded successfully.
  Support's `Bridge protocol: unavailable` is inconsistent diagnostic reporting,
  not proof of an old native bridge.
- Bandits2 and A-Life are absent. Approximately 56 mods are loaded overall,
  including `pzopt` with four workers. There is no comparison establishing that
  any other mod causes the combat complaint.
- Multi-hit is disabled. The two fighting companions use a wooden mallet
  (reported reach 0.46–1.08) and wrench (0.46–1.18), with Follow/Regroup orders
  and `close_defense`. The Support snapshots show fatigue around 0.84–0.85,
  despite endurance around 0.98–1.0. Stamina and tiredness are separate values.
- `approach_yielded:single_lane` recurs at roughly 1.4–1.7 tiles, followed by
  stationary safety holds. Attacks also occur. The log does not demonstrate
  that every such hold is permanent or erroneous.
- The first snapshot has AI frame p95 63.79 ms; the later snapshot has 8.78 ms.
  Recorded long tails include base-work delegation up to 236 ms, decision
  processing up to 259 ms and total ticks up to 278 ms. The scheduler reports
  over 22,000 deferred frames and zero exceptions. These are observed delays,
  not a measured causal explanation of the combat complaint.
- The exhausted companions report `no_available_bed`. That is worth checking
  against the tester's actual bed placements and access paths; these logs alone
  cannot establish why the beds were unavailable.
- No LF Lua exception is evident in the supplied errors. There are separate
  startup/map errors, including an unrelated posters mod error.

## Native trials before hardening

Seventeen trials across six disposable cloned worlds used the real game and
this checkout's native bridge. Only LF and the private harness were enabled.
The original save, main mod profile and installed mod were not modified.

Fresh fixture actors were used rather than the tester's saved actors. The
arena was open outdoor ground. Kill counts use newly created physical corpses
as well as dead actor observations, since killed zombies can return to the
native object pool and their old references can later report reset states.
Post-removal target-state traces must therefore not be read as living zombies
stuck in `GenericDefaultState`.

All active trials below ran for up to 55 real seconds. All companions survived.
These are small diagnostic samples, not a balanced survival benchmark.

| Setup | 2 vs 3 kills | 2 vs 4 kills | 2 vs 5 kills | Lowest companion health |
| --- | --- | --- | --- | --- |
| Fresh, crowbars, Stay, inherited multi-hit enabled; two trials each | 3/3, 3/3 | 4/4, 4/4 | 5/5, 5/5 | 100% |
| Fresh crowbars, natural acquisition, no harness sighting/target calls; one each | 3/3 | 4/4 | 5/5 | 100% |
| Mallet/wrench, initial fatigue 0.85, multi-hit off, Follow, natural acquisition; one each | 2/3 | 3/4 | 5/5 | 93.9% |
| Mallet/wrench, initial fatigue 0.85, multi-hit off, Stay, player distant; one each | 1/3 | 2/4 | 2/5 | 94.6% |

The Follow fixture places a vulnerable, stationary player about three tiles
behind the companions. Some zombies attacked and injured that player. It is
a following/defence scenario, not a pure two-character damage benchmark.
The last row removes that diversion and seeds native sightings on companions.
Brief lane yields occurred in both tool-equipped runs; many retreat decisions
also occurred. These runs changed several conditions together, so they do not
isolate fatigue, weapon choice, multi-hit or orders individually.

Additional controls:

- One fresh crowbar companion killed one zombie and remained at 100% health.
- A 30-second incoming-attack control held two companions passive against
  three zombies. Actual native attack states and successful outcomes occurred,
  and companion health fell to 27.3%, with wound indicators. The harness did
  not force successful outcomes or subtract health. It manually serviced the
  production targeting and damage resolver while its exclusive passive lease
  suppressed retaliation, so this control proves incoming capability rather
  than the whole normal decision loop. Injuries in the active trials provide
  separate evidence that ordinary combat can also damage companions.

No combat exception was captured. Stock startup/map warnings and a shutdown
log-archiving `ReadOnlyFileSystemException` remain in raw consoles; a passing
combat trial does not mean the entire console is error-free. The harness PASS
criterion is survival plus offensive activity, not a guarantee of killing
every zombie within the time limit. Counts above retain partial outcomes.

## Automated checks and retained evidence

- Strike barrier regression: 35 checks passed.
- Perception topology regression: 414 checks passed.
- Gameplay regression suite: passed, including 922 static assertions and the
  existing combat, human-threat, targeting and damage regressions.
- Live harness static regression: passed, including custom squad sizes and
  native fixture isolation/membership checks (150 static assertions).
- `git diff --check`: passed; existing line-ending notices are informational.

CSV results, bounded combat traces, exact run IDs and fixture settings are in
[`artifacts/combat-regression-02675`](../artifacts/combat-regression-02675/).
`collect-evidence.ps1` recreates these from the completed raw runs retained
under ignored `build/live-sandbox-runs/`.

## Hardening after the initial investigation

Three production Lua modules changed, without a native bridge or save-schema
change:

1. **Keep the flank already proved safe.** Approach execution used to call
   `engagementAim` inside its yield check and then call it again to get the
   destination. With one of the shared eight path proofs left, the first call
   could prove the flank and consume the budget; the second returned no flank,
   leaving the old centre-directed vector in use. The new `engagementPlan`
   returns the flank and yield decision together. Execution uses that result
   once. Collision checks, blocked lanes and the eight-proof limit remain.
2. **Distinguish pending sleep discovery from no bed.** A camp-bed scan yields
   after 320 tiles. Its `searching` result was discarded, so an idle base worker
   could claim another moving job, reset the scan origin and never reach a
   distant bed. Pending searches now propagate as `bed_searching`. Idle workers
   stop and let the finite scan finish, clearing only their own guard-patrol
   route. Workers finishing an owned job keep their survey's original ring
   centres/order while it is pending, so walking no longer restarts it at every
   tile. A completed search without a usable bed still allows work to resume.
3. **Skip unrelated chores for explicit sleep queries.** The bed capability
   check and bed update previously collected washing, showering, reading,
   repair and other candidates before discarding them in the kind filter.
   Explicit `rest_bed` requests now perform only furniture/bed discovery. This
   removes redundant survey work; it is not proof that all of the tester's
   recorded performance spikes are eliminated.

Regression tests first failed against the old logic for the exhausted-proof
approach and the lost pending-bed status. They now pass, including actual
approach execution with a precomputed vector, the eight-proof ceiling, the
bed-only query avoiding inventory audits, and the idle-worker pause. Existing
blocked-lane, bed access, ongoing-job, sleep eligibility and cancellation checks
also pass.

All **29 project gate stages passed**, including 244 Lua files in normal and
debug compilation, gameplay, perception, strike barriers, navigation, UI,
compatibility adapters, native ownership and packaging checks. After adding
further live-bed probe assertions, the live-harness static suite passed again.

A further three native trials used the hardened payload with the mallet/wrench,
0.85 initial fatigue, multi-hit disabled, Stay, and distant player:

| Encounter | Survivors | Kills in 55 seconds | Lowest companion health |
| --- | --- | --- | --- |
| 2 vs 3 | 2/2 | 1/3 | 100% |
| 2 vs 4 | 2/2 | 2/4 | 91.9% |
| 2 vs 5 | 2/2 | 2/5 | 99.7% |

These runs confirm continued attacks, survival and real incoming damage. They
do not show higher kill counts than the initial tool-equipped controls. Actor
rolls and native randomness are not held constant, so the results do not
quantify a change in overall combat effectiveness. The deterministic regression
case, rather than these small samples, proves the lost-flank correction.

The retained results now include all **20 combat trials**, with payload hashes
distinguishing original and hardened Lua. New target traces include world-list
membership and health to distinguish active zombies from recycled references.

### Native bed checks and remaining limitation

The existing chair-to-bed exhaustion acceptance passed with these exact three
production module hashes. Tess left a real chair, found the marked bedroom bed,
entered native sleep with `Bob_Asleep`, retained health 100 and recovered fatigue.
The occupied-pillow safety rejection also passed. The resulting screenshot was
visually checked: her body lies on the mattress. This validates the existing
companion route, not all entry conditions or bed models.

The generic fresh-actor sleep probe remains **failed**. Early runs exposed and
corrected missing native safe-spawn checks and incomplete fixture setup. Its
final run, `SC-Harness-20261029-223103-b2054c3e`, cleared prior work, released base
duty after the in-camp Stay command, and found an eligible bed. It then reached
`OnBedStarted` but failed mattress alignment: the settled anchor lay beyond the
bridge's permitted adjacent-pillow correction. The bridge rejected the larger
move; no unsafe repositioning was enabled.

A temporary 250 ms walk-to-bed settling change did not solve this discrepancy
and was removed, together with its temporary test expectation. `SCNativeActions`
and the native bridge are unchanged. There is no controlled old/new comparison
establishing whether the remaining failure is an actor-lifecycle issue, a generic
probe limitation or an existing entry defect. **Fresh-actor bed entry/get-up
acceptance is not claimed complete.** Keep this case open alongside the passing
existing-companion control.

The retained bed control evidence and failed fresh-actor diagnostics are in the
same investigation artifact directory. No local installation or release push
was performed.

## Remaining follow-up priority

1. Inspect any prolonged reserve-lane holds remaining with a live immediate attacker. A safe
   fallback should preserve self-defence and avoid shoulder collisions; simply
   disabling spacing would undo earlier coordination fixes. The current tests
   reproduce brief holds, not a persistent deadlock.
2. Profile the remaining expensive base-work/downtime searches seen in Support,
   preserving responsiveness to incoming combat. Reproduce with the tester's
   world before assigning their spikes to a particular operation or mod.
3. Resolve the remaining fresh-actor mattress-alignment discrepancy without
   widening the bridge's safe correction bounds. Compare its initial native
   transform/action state with the successful existing-companion control. Then
   compare the tester's same crew, equipment, sandbox settings and encounter
   geometry on .72 and .75; the current trials are not that version-controlled A/B.
