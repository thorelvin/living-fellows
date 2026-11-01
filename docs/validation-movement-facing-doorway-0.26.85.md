# Movement-facing and doorway follow-up

## Normal-play evidence

The latest normal-play files remain the October 31, 2026, 22:29–23:44 session,
installed LF **0.26.84**, Project Zomboid **42.21.0**. The original console's
last modification remains 23:44:40; isolated clients use private caches.
Actor `sc-1.792881659967E9-1-843943` stays at
**12031.983,6746.482,0**, attempting the **12032,6746,0** edge toward
**12028,6729,0** for 7 minutes 35 seconds. There are no gameplay exceptions.
The original session has no frame-level input-consumption or facing trace, so
it cannot by itself establish one exclusive cause of that entire stall.

## Changes retained

- Backstep and kite requests retain their real native aim target and weapon
  readiness. Previously they lowered the weapon, cleared that binding, then
  requested aimed movement with only a one-shot Lua facing vector.
- Unarmed tactical movement also retains its look target. Coordinate-only
  tactical movement keeps its requested heading between Lua pulses. Native
  attack and reaction ownership still take priority.
- Apply movement facing before the native animation post-update as well as
  afterward, so the animation consumes the intended heading.
- After a forward escape, retain the forward gait for ordinary repositioning
  until there has been a 650 ms quiet interval. Keep the selected action and
  exact movement vector, allow moving turns, and immediately release this
  facing preference for an attack/counter or another target. Unlike the rejected
  stride experiment below, this does not force another retreat or defer an
  available attack. A breaching/rescue rush also no longer supplies an explicit
  enemy-facing override while requesting a forward run.
- Issue one precise forward turn, observe actual model alignment and bound
  waiting to 1.6 seconds. A stale `isTurning` flag cannot block an aligned body;
  a failed turn stays failed for that heading instead of renewing a successful
  wait forever. Existing navigation recovery receives `movement_turn_timeout`.
- Preserve one **unconsumed** manual input for at most one second when a long
  main-thread frame exhausts its ordinary 250 ms lifetime. Late consumption is
  capped at **0.1 tile**, collision checked and consumed once. Cancellation,
  native body ownership, attacks, vehicles and path takeover keep their stops.
  Already consumed expired input cannot replay.
  Explicit endpoint deadlines remain authoritative and cannot be extended by
  this grace; the native regression checks their expiry before first use too.

These are actor-local operations on existing update paths. There is no new
normal-play polling service, target-angle observer, teleport recovery, health
deduction, damage multiplier or change to engine player ownership.

## Doorway reproduction and native acceptance

The clone fixture uses the restored original actor, the recorded starting
position and goal. Placement happens only before measurement. All measured
motion uses production navigation and native collision; actor and inventory
identity remain unchanged.

- `SC-Harness-20261101-013433-e9bf7bbd`: a **0.26.84 Lua control** with the
  newer isolated bridge reaches the destination in 34.253 seconds. This is not
  an exact full-0.26.84 binary replay, and does not reproduce the original
  multi-minute failure merely by requesting the same destination.
- `SC-Harness-20261101-014119-1be41e36`: before the input-consumption fix,
  delay each accepted request by 350 ms before the actor's native update.
  **23 accepted inputs produce zero movement**, matching the log's accepted
  movement/no-physics symptom. The fixture correctly fails.
- `SC-Harness-20261101-014401-bf466c69`: the same delayed-input fixture crosses
  in **four bounded native steps**, then reaches the original goal in
  **34.791 seconds** without another placement.
- Final bridge: `SC-Harness-20261101-015945-880c1799`, **60 checks passed,
  zero failures**. The delayed crossing again takes four inputs, each measured
  native displacement at most 0.1 tile. The continued route arrives in
  **36.731 seconds**. N/S/W native bed get-up and all four bed/table overlap
  recovery fixtures then pass with tables present and exact items retained.
  The E bed fixture has no stock entry positions; only its overlap recovery
  is exercised.
- Explicit-deadline final build: `SC-Harness-20261101-022223-cff1c79a`,
  **PASS, 60 checks, zero failures**. Four delayed first inputs cross the
  threshold; the continued route arrives in **36.263 seconds**. All bed/table
  checks pass again. Its private bridge hash equals the final payload hash.

Final doorway evidence: `build/movement-doorway-bed-recheck.txt` and the final
run's `cache/console.txt`, `cache/Lua/SurvivorCompanionHarness/events.log` and
`summary.txt`. The normal-play seven-minute session was not rerun verbatim;
the controlled failure and its bounded fix are established separately.

## Combat acceptance and rejected experiments

`SC-Harness-20261101-014707-127f3d4c`: retained targeting and native facing
fixes, three front-approach **2 vs 3** trials, real crowbars, multi-hit off,
healthy crew, LF alone. **6/6 companions survive at 100% health, 9/9 zombies
killed, zero A→B→A target returns within 800 ms.** Small body reversals per
fighter are **2/0, 7/0, 1/1**. One fighter still alternates escape and aimed
movement; zero target returns alone is not proof that all motion is stable.

A subsequent 650 ms retreat-stride experiment was rejected and removed.
`SC-Harness-20261101-020307-3897e66d` ends with **4/6 survivors, 6/9 kills**
and continued movement reversals. Encounters are not seeded A/B comparisons,
so the deaths cannot establish causation, but the result does not justify
retaining that behaviour change. No retreat delay/stride setting ships.

An extra global standing-endpoint restriction was also removed after the
continued-route fixture timed out at 90 seconds. Existing native swept
collision and the bed-specific overlap recovery remain in use.

The bounded harness now distinguishes enemy switches, aim binding changes,
forward/aimed locomotion handoffs, actual body rotation and body reversals
while logical heading, aim identity and native movement owner stay stable.
Attack and genuine route turns must not automatically be labelled jitter.

`SC-Harness-20261101-020727-b307c63c`, before the final gait handoff: **6/6
survivors, 8/9 kills**. The first pair's lowest health is 37.7%; the other two
pairs remain at 100%. Actual body reversals occur **11/5, 3/0, 3/3** times;
**none** occurs while logical heading, aim binding and movement owner all stay
stable across the sampled 450 ms window. The first pair changes between
forward/aimed movement **47/27** times, with **33/19** quick returns. This
separates the remaining command handoff problem from an unchanging heading
that the renderer independently reverses. It does not excuse the visible
handoff oscillation, and is the reason for the final facing-only preference.

### Final facing-only handoff trials

`SC-Harness-20261101-021649-ef7023ef`: final Lua including moving-turn
continuity, bridge `69cb4b15…`, LF alone, stay order, three front-approach
trials, 55-second maximum, multi-hit off. The tested `SCCombat.lua` SHA-256
matches the checkout exactly:
`414b26e245671413a4306e08962fc3109ed20d7d3aba24626a5fc9914d51e5cb`.

| Trial | Live target changes A/B | Quick target returns A/B | Body reversals A/B | Quick movement-mode returns A/B | Outcome |
| --- | --- | --- | --- | --- | --- |
| 1 | 8/0 | 0/0 | 13/0 | 6/0 | 2/2 alive, 100% health, 1/3 kills |
| 2 | 5/6 | 0/0 | 2/5 | 2/18 | 2/2 alive, 98.1% lowest health, 3/3 kills in 31.053 s |
| 3 | 13/28 | 0/8 | 1/6 | 0/31 | 1/2 alive, 3/3 kills |

**5/6 survivors and 7/9 kills are mixed results, not clean combat acceptance.**
Trial 1's second companion records no active combat samples after separation;
the stay-order fixture must not be described as both fighters continuously
engaging. No body reversal occurs while heading, aim identity and native
movement owner all remain stable across the sampled window. However, the
remaining target/movement handoffs are visibly frequent in the pressured
third trial. The same-target gait preference does not prove the original
whole-group jitter resolved. Contact urgency, viable-action upgrades and
escape-route changes remain investigation areas; no blanket target lock or
attack delay was added to hide their effects.

The last native bridge adjustment only clamps first-input grace to explicitly
requested endpoint deadlines. Its new hash and dedicated native/doorway checks
are recorded below; these combat trials used the preceding bridge hash.

## Build and scope

Final payload bridge SHA-256:
`994e76205dac4234a09c06d1fc7938ca017086ef941026c8610c88960ad468de`.
Protocol remains 26. Core suites pass **92/92**, including explicit-deadline
expiry: `build/movement-final-deadline-core.txt`.
The final full project gate passes **29/29 stages** in 162 seconds:
`build/movement-final-project-gate-complete.txt`. The final doorway and bed
evidence is `build/movement-deadline-doorway-bed-final.txt` plus that run's
private console, events and summary. Its diagnostic helper no longer probes
door-only getters on generic floor/furniture objects; the final run has no
probe/gameplay exception. The disposable cache's known exit-time ZipLogs
read-only error remains unrelated to movement.
Automated coverage includes native aim readback, armed/unarmed tactical
facing, native attack ownership, cancelled/expired/unconsumed input, retained
turn requests, rendered alignment, timeout liveness and existing field-work,
bed-exit, inventory and persistence regressions.

Source and rebuilt bundled bridge are in the checkout. No local install,
commit or push was requested; original saves and installed files are untouched.
