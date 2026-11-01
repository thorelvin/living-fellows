# Combat facing and play-session log review

The later native movement/input fixes and doorway reproduction are recorded
in [the movement follow-up](validation-movement-facing-doorway-0.26.85.md).
Results below preserve the earlier targeting-only investigation.

## Normal-play evidence

The latest normal session on this PC is **October 31, 2026, 22:29–23:44**,
Project Zomboid 42.21.0, installed LF **0.26.84**. Sources:
`<Zomboid folder>/console.txt` and
`<Zomboid folder>/Logs/2026-10-31_22-29_DebugLog.txt`.
The isolated harness sessions below do not overwrite those files.

- Neither file records a gameplay exception. The errors are startup font,
  fluid-name and vanilla map diagnostics, also seen in control runs.
- Sixteen combat approaches yielded for `single_lane`. There are also short
  bumped-state/medical ownership holds, and valid health-triggered retreats.
- Actor `sc-1.792881659967E9-1-843943` repeatedly failed to cross
  **12032,6746,0**, remaining at **12031.983,6746.482,0** from
  **23:36:42 to 23:44:17**. Twenty-six reports show replan/clearance attempts
  without net movement during that interval. The earlier report on the same
  square has a different position and is not evidence of a session-long stall.
  This remains a separate navigation issue; this combat change does not fix it.
- Fifty-three scavenge failure reports break down into 19 approach timeouts,
  13 static blocks, 13 missing interaction targets, seven dynamic blocks and
  one furniture stand-up hold.
- These normal logs do not record heading or target identity at sufficient
  frequency to prove the reported 400 ms jitter. Live instrumentation is needed.

## Reproduced targeting fault and changes

The ordinary scorer adds 30 for a rear contact, 18 for a flank and eight for
the incumbent. Turning to one equal contact therefore boosts the other.
The former 650 ms soft commitment could be bypassed by either nearby contact,
or by a score advantage. A regression using real scoring reproduced an
immediate switch on every update between two otherwise unchanged contacts.

- Keep rear/flank scoring for awareness and initial selection. Discount that
  self-induced component when comparing a still-viable incumbent with another
  contact, including the target/action pair pass.
- Use a one-second melee commitment, retaining a reduced score margin afterward.
  A rescue, player designation, higher contact danger, lost/dead/invalid target
  or an available attack replacing an unusable/non-offensive action can still
  interrupt. Two equally close contacts are not two new emergencies.
- Refresh the initial/incumbent squad lane without discarding it for a
  provisional doctrine contact before the final pair is selected.
- A guarded movement-failure hold faces the same fresh engagement unless a
  higher-tier contact intervenes, instead of taking whichever contact appears
  first in the scan.
- Add a passive native aim-target getter to distinguish the actual binding
  from the last successfully dispatched Lua combat target. No normal-play
  angle observer or background tracing service is added.

The eight-point incumbent bonus and existing target validation, native swing
ownership, hit arcs and damage callbacks remain in use. No health, hit chance,
damage or zombie targeting values are changed by this work.

## Measurement

The disposable squad probe samples every 100 ms and reports separately:
live-to-live successful combat-target changes; A→B→A returns within 800 ms;
clears/acquisitions/dead-target changes; native aim binding changes; and passive
`getAnimAngle` body rotation. Model-ready samples whose body and logical angles
differ prove actual model rotation was observed, rather than only the logical
heading fallback. Thirty-degree reversals within 450 ms are counted separately
from single-sample 30° turns. Natural attack/escape turns are not automatically
classified as bugs. Moving and stationary samples are identified in the trace.

Kahlua signed remainder needs explicit angle normalization. The initial
`SC-Harness-20261101-005136-6503bd18` trace used incorrect modulo normalization;
do not use its body-angle totals. Wrap and ±30° regression
checks cover the corrected observer.

## Completed native ring trials

`SC-Harness-20261101-010208-968ee6a8`: final targeting policy, real client,
LF alone, healthy fresh companions, real crowbars, multi-hit off, cloned save.
Three trials of two companions versus three surrounding zombies; 55-second
maximum per trial. **Six of six companions survived at 100% health; nine
zombies killed.** The timings and encounters are not a seeded performance A/B.

| Trial | Live target changes, actor 1 / 2 | Quick target returns, actor 1 / 2 | Small body reversals, actor 1 / 2 |
| --- | --- | --- | --- |
| 1 | 5 / 3 | 1 / 0 | 2 / 4 |
| 2 | 8 / 1 | 0 / 0 | 5 / 1 |
| 3 | 4 / 3 | 0 / 0 | 1 / 2 |

This is one rapid target-return event across six fighters, while small body
reversals still occur. The remaining turns must not all be called target
thrashing: some traces change between tactical movement, ordinary escape and
native attacks without changing the successful combat target. This evidence
does **not** establish that every reported visible jitter has been eliminated.

An earlier intermediate-policy 2v5 trial lost one of two companions (four
zombies killed); the original-targeting control survived with both. Different
random encounters and arena occupancy prevent a causal/balance conclusion.
Do not represent that mixed result as clean combat-balance acceptance.

## Verification and scope

### Native aim readback and front approach

`SC-Harness-20261101-010659-20dccff9`: same final Lua policy, additive passive
native aim getter, two 2v3 trials approaching from the front. Actual native aim
identity is measured independently from `Combat.peek(actor).target`, which is
the last successfully dispatched combat target. Nil aim transitions are counted
as clearing/acquiring aim, rather than live-to-live target changes.

| Trial | Combat target changes, both actors | Native live aim switches, both actors | Small body reversals, both actors | Survival |
| --- | --- | --- | --- | --- |
| 1 | 10 | 1 | 2 | 2/2, 100% health, three kills |
| 2 | 11 | 1 | 13 | 1/2, two kills |

In trial 2 the worst actor alone had **11** small body reversals, **one** native
live aim-target change and **25** aim clears plus **25** acquisitions over the
55-second observation. Its jitter samples include path, manual escape and
tactical movement owners, with unchanged successful target and unchanged aim
binding in those particular samples. This points to remaining movement/aim
transitions and path-facing behavior; it does not establish that the enemy
selector is the sole cause of the visible motion.

The fixture's `PASS` status means its combat measurements completed, not that
every fighter survived. This front-approach result is **not clean combat
acceptance**. The targeting feedback regression is fixed in source, while the
remaining visible movement-facing jitter and the loss need further hardening.

The tested getter bridge SHA-256 is
`8046e0a0ec560d93f07cd11a7f2e4feb2967db176acb5205290d18f836a1ae2b`.
Logs and result CSVs are retained under each run's
`cache/Lua/SurvivorCompanionHarness/` and `cache/console.txt`.

Regression additions cover equal-contact orientation feedback before/after the
lease, equal-range attack flags, immediate contact danger, guarded-hold focus,
unsafe grounded finishers, viable attack upgrades, and native aim readback.
The deterministic regression failed against the old selection policy and passes
with the changes. The final full project gate passed **29/29 stages** in 127
seconds: `build/combat-facing-aim-project-gate.txt`. It includes the corrected
body-angle observer, gameplay target-retention/viability cases, native aim
readback and existing combat, perception, ownership and persistence checks.

Source and rebuilt bridge are in the checkout; no local installation, commit or
push was requested for this investigation. Original saves are untouched.
