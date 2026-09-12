# Combat and navigation corrections

Implementation plan for the 9 September 2026 playtest, audited against 0.22.8 installed and source `1b89592`.

1. Make stationary combat phases release previous translation. Respect native melee/recoil recovery and native impact ownership, including the decision loop after the last target dies; retain player combat-speed calculation.
2. Separate hit tolerance from defensive spacing. Stop approach at useful weapon reach and account for a closing zombie without preventing short-weapon attacks.
3. Correct stomp fallback damage, with range/floor/obstruction checks at the impact event and no duplicate damage.
4. Bound retained manual movement by an endpoint and expiry. Precise door/fence alignment must converge even when decisions are delayed. Reject nonfinite movement before native physics can corrupt coordinates or square membership.
5. Retain ownership while a native climb request is starting. Verify entry asynchronously, suspend competing path advancement during active traversal, and bound cancellation/recovery.
6. Distinguish a pending path request from a ready route and actual movement. Discard stale continuation when replacing a route without deadlocking animation-driven movement.
7. Ignore noncolliding debris and use physical traffic clearance. Keep portal identity separate from evidence of an obstruction; record actual actor/path/animation state on failures.
8. Integrate regression tests with the game Kahlua runtime and native bridge tests, run the complete project checks, and prepare focused live validation on an isolated save.

The exact initiating cause of the recorded native door stalls at 6764,5265,0 is not established by the old log. The alignment loop and premature climb rejection are reproducible independent defects. Improved failure evidence and a live test must distinguish remaining native stalls from these corrected control errors.

Production install/save and Git publication are separate from implementing and testing this package.

The native bridge protocol first advanced to `42.20-isocompanion-6` for bounded movement and traversal cancellation, then to `42.20-isocompanion-7` for target-specific native combat-collision evidence. The current protocol 8 adds main-thread bulk item, topology and perception reads without changing the save schema. Old launchers must be rejected at startup, not discovered through failed movement or combat in a save. Install the matching Lua and JAR together, then restart the game. This section records the earlier 0.22.10 candidate.

## Validation notes

- Deterministic regression coverage exercises retained translation after holds/swings, rejected stops, native recovery, weapon reach, bounded diagonal approach, impact-time contact loss and native `Hit` damage semantics. The original mock incorrectly ignored `bIgnoreDamage`; it now reproduces the real contract.
- Traversal tests cover all cardinal alignments, delayed event entry, animation tails after window effects, cancellation failure, missed-between-polls arrival, body clearance, debris, uncertain open-door evidence and nearby-threat steering.
- Real-JAR tests cover two native companions, per-frame endpoint convergence, input expiry, pending/ready/moving/stopping transitions, path cancellation, duplicate impact ownership and native traversal-state observation.
- The first isolated run (`SC-Harness-20260910-155915-189c430e`) passed 70 checks, failed one sustained-run-clip check and skipped medical treatment for lack of a suitable wound. The run probe sent a single input instead of refreshing it; it now models sustained input every 100 ms and retains strict clip/facing checks.
- That live run also revealed an important native API trap: `isClimbing()` does not track normal player fence/wall/window states. Their real state-machine ownership is now observed instead, preventing a valid vault from being cancelled as a startup timeout. A physical door round trip was added because the old room test only proved the entry-facing sequence.
- The first live melee probe observed one accepted impact event over a 601 ms swing and rejected a subsequent attack with native melee delay still at 11.5. The grounded probe reduced health from 1 to about 0.978 without killing the zombie. These are individual observations, not aggregate attack-speed or balance measurements.
- The second isolated run (`SC-Harness-20260910-161049-719aeea3`) used the final production bridge and passed 71 checks, failed two and skipped none. Forward escape and backward strafe both passed clip/facing checks, and the premature fence-start cancellation no longer appeared. The new door probe chose a landing occupied by the player and could not drive its own recovery; the grounded probe still placed its target blindly east of the actor. These fixtures were corrected without relaxing collision, actual plane-crossing or damage requirements. Grounded impacts now record the rejection reason and contact geometry.
- The complete project suite passed with the protocol-6 bridge: 50 combat recovery checks, 62 navigation/traversal checks, real-game-JAR controls and API checks, gameplay, UI, source and packaging checks. Synthetic response checks cover 1/4/8/16 companions; their timings are not live game FPS measurements.
- The third isolated run (`SC-Harness-20260910-161956-c0e6a768`) reproduced the real doorway stall at 6764,5265. It also verified grounded damage on the first contact (health 1 to 0.984205, one collision, zombie survived). Its recorded 71 passes/3 failures/1 skip includes two diagnostic rows mistakenly counted as failures; those now use ordinary logging. The doorway failure is genuine and is being investigated rather than removed from the test.
- The apparent vehicle collision at that door was not evidence of a car. In 42.20.4, `IsoMovingObject.postupdate()` sets `collidedWithVehicle` whenever the polygon resolver corrects a character's position, including walls and doors. Vehicle classification now requires an actual vehicle object. Failure reporting retains pre-cancellation path state, and native diagnostic snapshots retain attempted versus resolved movement without allocating strings in the per-frame capture.
- The focused fourth run (`SC-Harness-20260910-162825-e4763795`, 26 passes/1 failure) exposed the actual failure mechanism: native physics received `NaN/NaN` intended coordinates while the open-door segment tested clear. The resolver snapped the actor back to the tile centre, repeatedly. This is invalid movement, not insufficient doorway clearance; it also warrants checking world-square membership after the correction.
- The fifth focused run (`SC-Harness-20260910-163505-274f1253`, 26 passes/1 failure) verified that invalid-input guards prevent the snap and preserve finite world placement, but the door still stalled: the animation's deferred movement was already nonfinite before the pathfinder consumed it. A guard alone is therefore not a complete fix. Inspection then found the bridge omitted the normal player's per-frame consumption/reset of accumulated animation movement. A separate real-JAR regression also reproduced native pathfinding's zero-distance/zero-speed division at an intermediate waypoint; invalid movement must never reach physics even if native code produces it.
- A real decision-loop regression reproduced premature combat-pose cleanup after the last target died. Native swing ownership now precedes ordinary follow/stay selection, but yields to terminal, critical medical, knockdown, hit-reaction and grapple safety handling.
- The sixth focused run (`SC-Harness-20260910-164026-1a5e9070`) passed all 27 checks, with no failures or skips. The exact failing door was crossed both ways after restoring per-frame native animation-accumulator consumption: 202 observed frames retained finite coordinates and correct square membership, maximum observed step 0.062 tiles, and zero invalid movement requests. This validates the operative cause of that reproduced stall; it is not a claim that every possible map obstacle has been live-tested.
- The seventh full run (`SC-Harness-20260910-164650-763cabc5`) passed 70 checks and failed three, with no skips. Door passage passed again (198 finite/member frames, maximum step 0.052), but eight valid grounded contacts produced no native damage. Two faction probes also remained in medical safety holds. Those failures are not being counted as successes; follow-up diagnostics now include the native damage return, impact stance/weapon/avoidance and medical decision identity.

## Final automated verification

`scripts/Test-Project.ps1` completed successfully against the final protocol-6 bridge and decision/impact fixes. Coverage includes 50 combat recovery checks, 66 navigation/traversal checks, 14 new real decision-loop checks, 14 door-fixture checks, 121 live static assertions, 597 gameplay static assertions, 78 UI tests, synthetic 1/4/8/16-companion response checks, and native bridge/animation/API/installer/packaging gates. Native regressions reproduce the intermediate-waypoint zero division and verify 50 frames of accumulator consumption without erasing the current animation snapshot.

Final bridge SHA-256: `0a2c7439839a34a94c2e45fb3c718a53878959a7f04446388add1c29e117286b`.

The isolated client uses a cloned save, separate cache and source bridge. It never updates the normal installation, original save or original launcher. Native asset/map warnings and a caught, pre-existing faction street-lookup warning are distinct from the combat/pathing assertions.

## Final live validation - 10 September 2026

Full isolated run `SC-Harness-20260910-184512-b4cb5c52` completed with **82 PASS / 0 FAIL / 1 SKIP**; the client exited normally. The tested final candidate bridge SHA-256 is `542c1a55d0152adf35b3366a40b29d9454eb66f7b570e8eaa7d79bdf2ba20726` (superseding the intermediate bridge hash above).

- The exact doorway passed a physical round trip: far side `6764.88,5265.50`, return `6762.95,5264.91`; 201 observed frames retained finite coordinates and world membership, with maximum step 0.049 tiles. Forward escape and backward strafe passed native clip/facing checks.
- A real `Bob_AttackFloorStamp` reduced grounded-zombie health from 1 to 0.975835 on the first stomp; the zombie survived. No damage occurred before the collision event.
- The Katana hit at 1.05518 tiles using native `Bob_AttackBat01_Hit`/`HitB` clips and weapon stance, killing its target. One swing produced exactly one collision serial increment over 620 ms; native melee delay 11.49997 blocked the next attack. These are individual observations, not aggregate balance measurements.
- The hostile pack produced real companion wounds and grapple/knockdown. A loaded, clear 5x5 test arena 16 tiles from the passive observer prevented cross-test attacks; fixture cleanup restored current, render and moving-square references and list membership. The observer remained alive at 100 health, without wounds or infection, and was visible before faction targeting.
- Faction contracts, household lifecycle, persistence and native hostile-human targeting passed. The only skip was `medical_treat_probe`: no restored companion had both a treatable wound and usable supplies; medical state checks still passed.

The final arena, observer checks and precise melee placement were test-only corrections; they did not modify production combat or grant damage immunity. Their focused gates passed 38 combat-fixture checks, 14 doorway-fixture checks and 130 static assertions. No original save, normal installation or launcher was changed, and nothing was pushed or installed by this validation run.

## Post-playtest responsiveness, sight and grounded-combat plan

The 10 September multi-companion profile exposed five follow-up defects. Build 42's
`IsoGameCharacter.CanSee` and `LosUtil.lineClear` do not impose the observed
approximately ten-tile cutoff; discovery was delayed by Living Fellows' empty-square
coverage scan, especially after load shedding and moving-origin restarts. Build 42 also
ships distinct player floor-melee animations for one-handed, knife, two-handed, spear
and heavy weapons in addition to its stomp family. The implementation therefore keeps
native LOS and native player attacks authoritative instead of inventing parallel
visibility or animation rules.

1. Repair moving formation routes by trimming to an existing unconsumed goal, compact
   consumed prefixes, cap retained repair growth, and cover alternating nearby goals.
2. Give every incremental route-search slice both a node quota and a monotonic elapsed
   deadline. Preserve unfinished edge expansion across yields so responsiveness does
   not trade away correctness.
3. Deduplicate topology reads only inside one synchronous search slice. Door, vehicle,
   hazard and moving-body facts must be read again after every yield.
4. Make escape-topology discovery resumable and demand-driven. Calm perception must
   not pay for a 64-node flood fill, while a new immediate threat can still pre-empt
   ordinary work.
5. Reset no-effect collision history on every landed hit, including a different
   target, so stale evidence cannot authorize support attacks or break attack-anchor
   spacing.
6. Acquire active zombie candidates with a bounded cursor out to 24 tiles, then apply
   strict same-floor and native LOS checks. Retain the square-coverage scanner as a
   compatibility fallback and keep hearing separate from visual targeting.
7. Commit one grounded-finisher preference per target instead of rerolling each AI
   tick. A healthy compatible held melee weapon should usually use its native floor
   attack; stomp remains a plausible choice based on weapon condition, footwear,
   endurance, panic and personality.
8. Validate isolated regressions first, then the complete source/gameplay/core/UI,
   bridge, packaging and live-static suite. Install only the fully green candidate;
   publication remains a separate user-authorized step.

## Post-playtest implementation result

All eight steps above are implemented in the 0.22.10 candidate. The five reported
performance/correctness faults now have deterministic regressions: moving route
repair remains bounded, search slices honor elapsed time as well as quotas, topology
facts are not retained across yields, escape topology is demand-driven and resumable,
and every confirmed collision clears stale no-effect history.

Visual acquisition now reaches 24 tiles through a squad-shared native zombie roster.
Each observer still performs its own range, floor, and native LOS proof, and hearing
cannot supply an actor target. The focused harness acquires a clear 20-tile contact in
100 ms and keeps four companions to one 64-entry native-list chunk per pulse.

Grounded combat uses target-specific native collision evidence introduced under bridge
protocol `42.20-isocompanion-7`; current protocol 8 retains it and adds bulk reads.
Synthetic stomp damage has been removed. The companion keeps
one bounded weapon/stomp preference while approaching or waiting. Healthy held melee
weapons normally use their native floor clips, with situational stomp variation and a
safer weapon-range override when stepping into foot range would be unnecessary.

Final automated verification passed source, core, gameplay, navigation stability
(847 checks), perception/topology (62 checks), UI (78 tests), live-static (130
assertions), native bridge, installer, Workshop, and standalone packaging. The built
bridge SHA-256 is
`f3143a0bbbcfe1acb44cbe6ac36f3eb069cd9568117de40d1a67992941850181`.
The matching private debug build was installed locally for playtesting; nothing was
published by this task.
