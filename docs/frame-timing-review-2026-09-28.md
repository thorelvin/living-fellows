# Frame timing review, 2026-09-28

Source: `C:\Users\thore\Downloads\FRAME-TIME-FIXES.md`, revision 2. It is an analysis and proposed fix plan against older 0.25.26 code, not an instruction source for this build. The private checkout was 0.25.30 when this review began.

## Confirmed finding

The existing `SCScheduler.tick()` budget and `SCPerformance` frame p95 exclude the beginning of `SCRuntime.productionTick()`. That beginning includes a full `Registry.records()` roster read, zombie attack sustain, view update, and steering. Therefore the old 2 ms scheduler number cannot establish a 2 ms whole-mod tick. Earlier W09 pilot samples already had many scheduler overruns; the unmeasured pre-scheduler work makes the total at least as large.

`getTimestampMs()` is used for existing scheduler elapsed checks and measurements. The prior live report `SC-Harness-20260927-102059-b8b49004/cache/Lua/SurvivorCompanionHarness/performance-lf.txt` shows whole-millisecond p50/p95/max values throughout (`3.00 / 14.00 / 17.00 ms` for scheduler frames); that is consistent with the download's clock-resolution warning, though the report alone cannot prove the underlying API's resolution. The precise Java clock is now available for durations, while scheduler due times, saved cooldowns, and cache expiry retain wall-clock time.

## Implemented P0 measurement

- `SCBridge.nowMsPrecise()` returns `System.nanoTime() / 1_000_000.0`.
- `SCPerformance.preciseNowMs()` uses the bridge when exposed and falls back to the prior clock in fixtures or older installations.
- Scheduler budget checks, callback and per-actor durations, the decision service estimate, perception/topology and UI slice deadlines, and `Performance.measure()` use the duration clock. Their saved/cadence timestamps remain on the wall clock.
- `productionTick` records `tick.pre-scheduler` and `tick.total` each frame. Both are exposed directly in the performance snapshot and text report, independent of the top-system truncation. The previous scheduler frame metrics remain separately named and keep their original scope.

Core 47/47 and gameplay harnesses passed after these changes. A 30-second
cloned-save base-scene baseline then passed in `SC-Harness-20260928-002620-80410143`:
four saved companions, player in slot 0, slot 1 absent, and the companion UI
open. The new report recorded 2,633 mod ticks, with `tick.total` p50/p95/max
of **3.647 / 14.222 / 34.166 ms**. The pre-scheduler portion was
**0.046 / 0.054 / 0.274 ms**. Percentiles use the latest 120 samples
per metric; per-system maxima cover all recorded samples since reset.
The old scheduler-only frame was
**3.56 / 14.12 / 16.57 ms**, and 1,466 of 2,633 ticks exceeded its 2 ms
budget. Decision work had p95 13.66 ms and UI refresh p95 15.96 ms. The
separate render sample measured 1,796 frames with 16.484 ms p50 and
28.544 ms p95; its frame intervals include the whole game, so they cannot
be attributed solely to Living Fellows. The report's mod metrics span the
game's warmup plus the 30-second sample; treat this as one scene baseline,
not a population-wide estimate. The launcher was restored and the source
save was untouched.

The previously missed pre-scheduler section is real but small in this base
scene. The main measured problem is scheduled decision/UI work, including
non-preemptible callbacks that can overrun the 2 ms budget. A new first-step
gate skips `rescueNeed` when `immediateCount > 0`, where its result could
never add a rescue candidate. The gameplay harness passed after this change;
its savings have not yet been measured live. The decision-only medical cache
from the downloaded proposal remains unimplemented pending profiling and
freshness checks around treatment.

A second 30-second cloned-save sample put the actual saved leader in slot 1
with the other three companions following in a separately loaded area
(`SC-Harness-20260928-003008-3a3af353`). This was a test-only remote
transfer, with natural remote zombies present and updating. The full mod
tick's recent-120-sample p50/p95 was **9.717 / 18.797 ms**; its
since-reset maximum was **25.655 ms**. Pre-scheduler recent p95 was
**0.097 ms**. Scheduler decisions had recent p95 18.58 ms and UI refresh
callbacks 16.39 ms. In the separate whole-client render sample, p50/p95
was **18.777 / 28.277 ms**. The UI panel refreshed only 12 times in 30
seconds, with a longest gap of 8,180 ms; the cadence assertion failed.
The sample data and local-player/roster checks passed. A second failure was
an outdated harness assertion expecting the fourth companion to remain in
Riverside; all four were correctly assigned to the remote team. That
assertion has been updated. This run is recorded as a failed performance
gate, not as a passing live test. The launcher was restored.

The UI gap is consistent with the current scheduler order: `decision` is a
priority-100 task due every tick, while `ui-refresh` is priority 20. The
scheduler checks its 2 ms limit between callbacks. A decision callback whose
recent p95 is 18.58 ms can exhaust the budget before UI refresh gets a turn.
The panel refresh callback itself also has a 16.39 ms recent p95, so both
decision cost and UI work need profiling before changing task priority.

Focused timing in `SC-Harness-20260928-003829-b72d91b2` counted 11,951
fresh medical assessments since reset (0.523 ms recent p95 each) and timed
rescue evaluation at 2.286 ms recent p95. Describing one UI row took
13.129 ms recent p95. Its 30-second remote sample again failed the panel
cadence gate (22 completions; 9,326 ms longest gap). This establishes a
repeated medical scan as a measured contributor rather than relying on the
download's estimated native-call count.

An opt-in `Medical.assessCached` now serves decision, combat, and summary
reads. `Medical.assess` remains fresh for treatment and verification. Health
bucket and infection state changes refresh the cache; bandage and mod-owned
zombie wound mutations invalidate it; release/reset drop retained entries.
Gameplay checks cover repeated-read reuse, bucket and explicit invalidation,
terminal Knox precedence, and cache freshness after treatment. The first
same-scene cloned run with this cache (`SC-Harness-20260928-005814-cb6bb651`)
passed the split-screen performance sample and UI cadence gate. Fresh
assessments fell to 1,921 since reset; whole-tick recent p50/p95 fell to
5.493/10.377 ms, and the panel completed 41 refreshes in 30 seconds with a
920 ms longest gap. Render p50/p95 was 15.949/25.444 ms. Natural zombies
and four remote team members were active in both scenes; their exact actions
varied, so this is evidence of improvement in this fixture, not a controlled
estimate of cache savings in every situation. The 2 ms whole-tick target is
still missed.

The UI load-summary shortcut was measured in two more four-member remote
samples. It reuses the medical assessment for status text and reads only the
load fields needed by the panel, leaving `Logistics.audit` for actual work.
The UI row's recent p95 fell from 12.335 ms (`005814`) to 1.110 ms
(`010254`) and 1.005 ms (`010631`); `ui.logistics-audit` was only
0.040 ms recent p95 in the latter run. The live panel cadence was not
reliably fixed: `010254` completed one refresh in 30 seconds and failed,
while `010631` completed 30 but had a 3,400 ms longest gap. The old harness
passed the latter because it did not cap the maximum gap. It now rejects
gaps above 2,000 ms.

Counters in `010631` recorded 65 refresh jobs started and 64 completed
since reset, with no interaction-block or root-replacement events. The
visible work is cheap when it runs; the decision task's repeated 2 ms
overruns can defer the background UI task. The scheduler now gives a UI
slice that is 150 ms overdue one turn before other lanes. A deterministic
scheduler check passed. The next four-member remote run
(`SC-Harness-20260928-011131-24cc1767`) passed the tighter live cadence
gate: 40 panel completions in 30 seconds, 599 ms minimum gap, and 868 ms
maximum gap. All three followers stayed with the slot-1 leader while natural
zombies moved in the remote area. The UI task's recent p95 was 2.13 ms and
the whole-mod tick's recent p95 was 13.173 ms. This verifies the panel's
opportunity to run in this scene; it does not meet the 2 ms whole-tick
budget or prove 8/16-companion scaling.

Per-kind delegation timing in a further four-member remote sample
(`SC-Harness-20260928-012938-c3d0f198`) located most decision time in
medical and combat: `decision.delegate.medical` recent p95 was 8.320 ms
(368 calls), combat was 5.801 ms (1,390 calls), and whole-mod tick p95 was
12.571 ms. This run counted 3,417 fresh medical assessments since reset.
`Medical.update` was still ranking every potential rescue patient with a
fresh full-body scan; that ranking now uses the 100 ms decision assessment
cache, while treatment and post-treatment verification remain fresh. The
same remote fixture (`SC-Harness-20260928-013218-d93f83ce`) passed the UI
cadence gate with 39 completions and a 916 ms longest gap. It counted 1,607
fresh assessments, a whole-mod tick recent p95 of 11.809 ms, and combat
delegation recent p95 of 5.985 ms. Natural activity and candidate mix varied;
the assessment-count reduction is direct, while the 0.762 ms p95 change is
only a directional comparison. Combat phase timing is being sampled next.

## Next measurements

Capture comparable untraced milliseconds and traced native-call counts for four
companions idle, eight in combat, and sixteen moving through woods. Use
`tick.total` recent p95 for the mod tick and `OnRenderTick` intervals for the
whole client frame. The downloaded plan's savings for later steps remain
estimates until measured. Treatment verification must keep a fresh medical
assessment.

The first combat-phase sample (`SC-Harness-20260928-013507-578b20af`)
passed the live roster and UI cadence gates, but its whole-mod recent p95
was 17.230 ms. Within combat delegation, bounded target/action pair
selection accounted for 6.895 ms recent p95, compared with 0.924 ms for
initial responsive weapon choice, 0.689 ms for target scoring, and 0.310 ms
for tactical assessment. This was a busier combat scene than `013218` and
the extra counters have profiling cost, so the whole-tick p95 values are not
a controlled before/after comparison. The next sample separates weapon,
readiness, and per-target action scoring inside pair selection.

That pair breakdown in `SC-Harness-20260928-013751-a9f013eb` measured
1.630 ms recent p95 for action utilities, 0.851 ms for weapon choice,
and 0.185 ms for readiness. The whole-mod recent p95 was 11.493 ms and
the UI cadence gate passed. A separate scene `015218` found the reflex
perception pass at 6.14 ms recent p95: escape candidate work was 3.878 ms,
visual validation 1.057 ms, native discovery 0.780 ms, nearby-square
inspection 0.493 ms, and final derivation 0.126 ms. The same scene's
whole-mod recent p95 was 19.592 ms. The escape phase is now split further
between scoring and validation before changing its safety rules.

The split in `SC-Harness-20260928-015448-3e9917d6` measured escape
candidate scoring at 1.993 ms recent p95 and route validation at 0.629 ms;
the whole-mod recent p95 was 11.515 ms. Scoring was rereading each corridor
node once per threat and the cohesion anchor once per candidate. It now
walks each candidate's parent chain once, marks which threats intersect the
corridor, and reads the anchor once per scoring pass. The existing corridor
regression and a new two-threat count/ranking check passed. A live remote
sample with four saved companions and natural zombies
(`SC-Harness-20260928-015830-0fd24f67`) passed roster and UI gates:
scoring recent p95 was 1.254 ms, reflex escape 2.502 ms, and reflex total
4.63 ms. Its whole-mod recent p95 was 12.880 ms, so this local improvement
does not close the 2 ms budget. Scene activity and new instrumentation vary
between samples; the cost direction is evidence, not an isolated causal
estimate.

The downloaded plan's P2 profiler review found that every timing record
shifted a 120-entry Lua sample array. The profiler now overwrites the oldest
sample in a bounded ring, while preserving contiguous values for percentile
calculation and reading the newest slot for `lastFrameMs`. Scheduler metric
names are also prepared at task registration. A 200-frame regression checks
the newest 120 samples, p50, p95, and last value after wraparound. Core
47/47 and installer 35/35 passed. A subsequent four-member remote split-view
run (`SC-Harness-20260928-022429-abd6ffe3`) passed native roster, all four
exact outfit identities, all three follower positions, natural-zombie update,
and UI cadence (36 completions in 30 seconds, longest gap 867 ms). Its
whole-mod tick recent p50/p95 was 6.197/10.272 ms. This is one variable
combat scene and does not isolate the ring-buffer saving or meet the 2 ms
target; 8- and 16-companion measurements remain open.

The P3 roster pass now publishes a sorted, read-only snapshot keyed by
registry membership version. Decision, vitals, banter, gestures, and the
per-frame native membership repair key reuse it; senses and UI share a living
list only within an active production tick. The old fresh `records()` and
`living()` APIs remain for cold paths. Registration, rollback, unregister,
and reset invalidate the cache, including a partial quarantined rollback.
Kahlua checks cover sorted reuse, mutation, death across frame tokens,
out-of-tick freshness, and token cleanup on callback failure. All 47 core
harnesses and the full 9/9 project gate passed after two test-infrastructure
fixes: Workshop's version regex now accepts CRLF metadata, and the live
static check recognizes the runner's splatted `Start-Process` options.

A four-companion base-scene clone (`SC-Harness-20260928-033110-c08b3a12`)
passed its 30-second population, slot, sample coverage, and panel cadence
checks. Whole-mod tick recent p50/p95 was **2.066/6.647 ms**, pre-scheduler
p95 was **0.046 ms**, and 48 panel refreshes had a 716 ms longest gap.
The earlier `002620` base sample measured 3.647/14.222 ms, but it predates
medical, UI, perception, and profiler changes, and companion actions varied.
This is a current-build baseline, not an isolated estimate of P3 saving.

The current remote run `SC-Harness-20260928-032636-fafb6c0a` retained all
four original expedition members at start and saw all three followers near
the leader, natural zombies, and 41 panel refreshes with a 903 ms longest
gap. During its measurement window the original leader died of native Knox
infection, a successor took slot 1, and production spawned a fifth companion.
Its 14.978 ms whole-tick p95 is a real stress observation, but the fixed
four-companion population gate correctly failed; do not compare it as an
equal-roster P3 before/after sample. The 2 ms target and 8/16-companion
measurements remain open.

The next P4 call-layer pass uses the registry's Lua actor-ID map before native
ModData access, forwards arguments through `safeSubsystem` without a fresh
closure in the decision path, and skips diagnostic key recovery bookkeeping
when no failure or circuit exists. It also exposes cached method resolution,
caches successful Java-method misses until bridge generation changes, lets
native-list iteration call the resolved `get` method directly, and reuses the
cell lookup within a decision spatial-read batch. The full project gate passed
9/9 after these changes; the existing circuit half-open/recovery and
native-list fixtures passed. Enum lookup caching (P4.7) remains open.

The staged clone `SC-Harness-20260928-035018-ddb1c175` included the first
actor-ID, closure and diagnostic changes. Its stable four-companion base
sample passed with whole-mod tick recent p50/p95 **2.020/6.289 ms**, and 49
UI refreshes with a 685 ms longest gap. The current full P4.1–P4.6 source
then passed another stable four-companion base sample in
`SC-Harness-20260928-035354-5a98b3c4`: **2.197/7.120 ms**, 47 UI refreshes,
717 ms longest gap. Both are above the 2 ms target. The decision activity
mix and native conditions differed across samples; these figures verify
functionality and expose timing, but do not establish a saving or regression
caused by P4. They should not be averaged into a claimed P4 benefit.

The first current-source remote sample (`SC-Harness-20260928-035607-8e3ac677`)
could not start its timing window: the original saved leader began at about 40
health and died of native head/neck wounds with a Knox flag before warmup
ended. The fixture now selects the healthiest original companion for a
performance run, leaving native injury and death enabled. That leader began
at 100 health and survived the next 30-second run (`035947`), but ordinary
production spawned a fifth companion during the sample, correctly failing
the fixed-four roster check. These are fixture failures, not passing
equal-roster comparisons.

The disposable remote performance fixture now sets its companion cap to four
before starting the mission. It does not change the product default, alter
native damage, or replace the original saved actors. In
`SC-Harness-20260928-040309-406525db`, the healthiest saved companion took
slot 1 with the other three following; natural zombies updated, all four
original actors stayed in the remote team, and the roster remained 4/4 for
the full 30-second sample. The UI completed 41 refreshes with a longest gap
of 907 ms. Whole-mod tick recent p50/p95 was **4.216/15.519 ms**;
pre-scheduler p95 was 0.050 ms. Medical delegation p95 was 10.95 ms,
combat delegation 3.98 ms, and the reflex perception pass 3.78 ms in this
scene. These are overlapping task measurements under natural activity, not
additive parts of the whole tick. The 2 ms target is still missed, and 8/16
companion scaling still needs separate native scenes. A setup-only duplicate
fixture event was removed after this run; it did not occur in the measured
window.

The P5 combat pass now builds a bounded inventory index per actor and reuses
weapon references and ammunition type maps. It invalidates on the mod's
inventory mutations, equipment changes, personal-item marking, and actor
release; root and nested container counts/weights catch outside changes, and
a 250 ms maximum age bounds same-count/same-weight replacements. Ammunition,
condition, and jams remain live reads. The gameplay tests cover a loaded
nested magazine, outside removal and replacement, ammo depletion, personal
writing-implement exclusion, and release. The full project gate passed 9/9.
Other inventory consumers and the optional bridge bulk item-facts path in
the downloaded P5 proposal remain open.

The first P5 live clone (`SC-Harness-20260928-041758-2d204f51`) passed the
four-original-member remote roster, slot-1 leader, three followers, natural
zombie update, and 39 UI refreshes with an 880 ms longest gap. Whole-mod
tick p50/p95 was **7.305/12.154 ms**, and combat responsive-weapon p95 was
0.976 ms. This scene had 2,359 responsive-weapon calls versus 1,674 in the
prior P4 sample, so the numbers do not isolate an inventory-index saving or
regression. The second clone (`SC-Harness-20260928-042122-aeaaa0d4`)
measured 4,147 index hits and 632 builds (627 from age expiry, one from an
outside fingerprint change). An original wounded follower died during setup;
production later spawned a fifth companion, so the fixed-four end gate
failed. Its timing is stress data only. The hit/build counts show reuse, but
the 2 ms target remains unmet and a controlled cost comparison is still open.

The P6 pass now shares zombie identity, liveness, location, posture, attack
state, climb state and target for one production frame. Perception uses those
facts for candidate filtering and threat records; combat uses them for
current zombie geometry; the attack resolver keeps one live target read before
damage so a same-frame target switch cannot wound the wrong companion. A
native attack-start request invalidates the cached zombie and grapple facts.
Kahlua tests check same-frame reuse, explicit invalidation, next-frame
refresh, out-of-tick freshness, and nil candidates. The full 9/9 project
gate passed. In the four-member remote clone
`SC-Harness-20260928-043514-2a58dee0`, all original team, follower, native
zombie and UI cadence gates passed. The report counted 66,710 fact hits and
41,800 builds across the run, with whole-mod p50/p95 **6.770/13.308 ms**.
The counters prove reuse, not a causal saving; bridge bulk zombie capture
remains open.

The P7 pass caches native-grapple reads by actor and frame, validates each
victim once per pair-sustain pulse, and runs the production tick inside one
spatial read batch. Cheap cached emergency flags now precede the grab probe.
The whole-tick timer starts before batch creation and records after batch
cleanup. Gameplay and scheduler tests cover frame changes, invalidation,
shared eligibility and cleanup after callback failure; the full project gate
passed 9/9. Clone `SC-Harness-20260928-044258-bfe111ad` passed its fixed
four-original-member roster, slot-1 leader, three follower positions, natural
zombies and 44 UI refreshes (longest gap 836 ms). Whole-mod p50/p95 was
**6.309/13.349 ms**, and pre-scheduler p95 was 0.081 ms. Natural activity
and call mix differed from the P6 run, so these values do not establish a
P7 speed gain. The 2 ms budget and 8/16-companion live gates remain open.

The P1b medical pass adds `SCBridge.fillBodyFacts`, which captures current
body health, real infection timing, and flagged body parts in one main-thread
call. `Medical.assess` still reads afresh after treatment; a missing or refused
bridge call falls back to the existing Lua walk. Gameplay tests compare wound
identity, severity, counts, a fresh post-bandage read, and refusal fallback.
The bridge protocol is now `42.20-isocompanion-12`. An initial live run showed
only 193 bridge successes against 2,337 fallbacks. A sampled native failure
identified the compile-only `BodyPart.getType()` stub returning `Object`
instead of the installed game's `BodyPartType`. The stub and exact runtime
signature gate were corrected, the payload JAR rebuilt, and all 9 project
gate stages passed. Two corrected remote clones then recorded **3,496/3,496**
and **5,450/5,450** assessments through the bridge, including naturally
wounded companions, with zero fallbacks. Assessment p95 was **0.069 ms** and
**0.066 ms**, versus 0.58 ms in the earlier mixed-path runs. These are
scene-dependent live measurements, not a controlled whole-tick speed claim.

The corrected remote samples did not pass an equal-team comparison. A saved
follower died from natural zombie wounds in each; production spawned a fifth
record after the first death. The disposable performance fixture now disables
replacement encounters and checks living population at the end, while leaving
native danger and damage active. A subsequent run kept four records and the
bridge served **5,450/5,450** assessments, but one original died, so the new
living-roster gate correctly failed. Its whole-mod p95 was **8.990 ms** and
the UI, slot-1 leader, natural-zombie and follower checks passed. The 2 ms
budget, stable four-person comparison on this corrected bridge, and 8/16
companion acceptance remain open.

The first P8 navigation pass now keeps tree and vehicle clearance in a
bounded 2,048-square navigation cache, separate from the shared performance
cache. Ordinary in-bounds squares use exact numeric keys; entries expire
under the existing 500 ms setting, and an out-of-bounds key keeps the old
coordinate string form. A* uses those numeric identities privately for
nodes, closed sets, heap entries and alternative-route penalties. Route
signatures, obstacle memory, and diagnostics keep their string keys. The
navigation regression suite checks expiry after tree/vehicle changes,
shared-cache independence, cache bounds, floor separation, and penalty-key
agreement. The full project gate passed 9/9 after the final change.

Two cloned-save autonomous Scout runs exercised these changes. With the
dedicated cache (`SC-Harness-20260928-052256-6f6e2612`) and then numeric
A* keys (`SC-Harness-20260928-052942-71a9b5b5`), the actual slot-1 leader
and saved followers walked about 85 tiles to a chosen site, observed nine
visible squares, and returned to the original player without a setup
transfer. Both runs passed and restored the launcher. They prove route
behavior, not a navigation timing saving. Static-edge reuse and a comparable
timed pathing sample remain open.

The P8 empty-memory gates now maintain separate entry counts beside blocked
edges, blocked squares, and route memory. The ordinary edge classifier skips
their string keys while the corresponding table is empty; additions,
expiry, invalidated doors, sweeps, and bounded evictions update the counts.
Ad hoc caller tables without an owned count still take the original lookup.
The navigation regression proves zero key builds through the production edge
adapter when all three memories are empty, then proves a remembered blocker
still rejects the same edge. The full project gate passed 9/9. A cloned Scout
run (`SC-Harness-20260928-053841-be01ee0d`) reached the site, observed nine
squares, replanned during return, and finished beside the original player.
A separate native door run (`SC-Harness-20260928-054246-a82753d6`) entered
the remote building, crossed back through the locked door after unlocking it
from inside, and returned to the exterior. Both runs passed and restored the
launcher. These are behavior checks; the 2 ms budget still needs measured
pathing evidence.

P8 neighbor expansion now returns the already known coordinate keys beside
each looked-up square. `SCPathSearch` uses those keys when provided and keeps
its prior square-key callback for other adapters. This avoids rereading every
neighbor's coordinates during A* expansion without changing the route-memory
or diagnostics formats. The navigation stability regression passed 958 checks,
including an adapter that supplies precomputed keys and verifies the same
optimal route with no per-neighbor key callback. The full project gate passed
9/9. A cloned quiet Scout run (`SC-Harness-20260928-054950-69460379`) moved
the actual slot-1 leader and three saved followers about 81 tiles, observed
nine visible squares, and returned without transfer. A separate remote
interior run (`SC-Harness-20260928-055343-14811bd4`) planned loaded approach
paths, crossed an ordinary door, and exited through a previously locked door
which the native actor unlocked from inside. Both passed and restored the
launcher. These checks establish route behavior, not a timed saving or the
2 ms whole-tick target. Cross-slice static-edge caching remains deferred
until its invalidation can account for construction, moving occupancy,
actor permission, hazards, and live door state.

A new 30-second remote performance sample on the P8 build
(`SC-Harness-20260928-055811-0d1bc095`) kept four records but lost one living
follower to natural zombies, so its equal-roster gate failed. It still wrote
1,783 render frames and 30 native samples. The whole-mod recent p50/p95 was
3.916/8.885 ms; combat pair-actions p95 was 5.189 ms, pair selection p95
5.612 ms, and reflex perception p95 4.19 ms. Natural zombie peak was 14;
the UI completed 41 refreshes with an 899 ms longest gap. This sample points
to combat steering as a measured next cost, but it is not an acceptance run.

The next pass uses the existing one-second Needs rate sample in ordinary
`Needs.assess` calls, while a completed eat/drink action forces a fresh native
read and makes the next rate sample due. In combat micro-steering, threat
life/floor/position facts are now read once per vector decision and passed to
the same coordinate-only body-clearance formula for each candidate heading.
A direct heading with the minimum possible danger score ends the search early.
The navigation stability regression passed 960 checks, including multiple
headings with one threat read and old/new body-clearance equivalence; gameplay
checks cover cached needs and a fresh post-eat read. The full project gate
passed 9/9.

The same remote performance fixture then passed in
`SC-Harness-20260928-060554-2e9b3ee1`: four living companions at start and
end, actual slot-1 leader, natural zombie peak 11, 30 native samples, 1,798
render frames, and 42 panel refreshes with an 816 ms longest gap. Whole-mod
recent p50/p95 was **3.506/7.504 ms**; combat pair-actions p95 was **1.150
ms**, pair selection 1.402 ms, and reflex perception 3.69 ms. The scene had
fewer natural zombies and a different mix of combat/medical actions than the
failed pre-change sample, so these figures do not isolate the code's speed
gain. The 2 ms whole-tick limit and 8/16-member scaling remain open.

The paired samples give direct evidence of fewer operations in the changed
paths, but not an isolated whole-mod speed percentage. The needs regression
shows ordinary assessments make zero native stat reads after a rate sample
instead of three; the steering regression shows one life-state read per threat
across multiple headings, with the same body-clearance answer. The two live
windows differed in zombie peak (14 versus 11), combat-call count (1,560
versus 1,295 pair evaluations), and living roster at the end (3 versus 4).
Their 8.885-to-7.504 ms p95 change is therefore observational.

The 2 ms figure remains an approximately shared LF overhead target from the
expedition plan. It is not an observed hard cap: even the successful
four-companion scene had a 3.506 ms median and 7.504 ms p95, while the
scheduler checks its limit between non-preemptible callbacks. A proposed P12
deadline that merely skips optional observers whenever the budget is gone
would starve lighting, relationship, and ambient upkeep during sustained
overload; any implementation needs a bounded deferral or separate fair lane.
Keep the 2 ms number as a stretch optimization target until 8/16-companion
live response, render, CPU, and memory measurements support explicit release
limits. Render p95 (22.833 ms in the successful scene) includes the game and
native streaming, not just LF Lua work.

## Native population scale pilot

The isolated base-scene harness now accepts an exact 4, 8, or 16 member
population. For 8 and 16, it spawns additional recruited native `IsoCompanion`
actors into distinct loaded squares beside the four saved companions, then
warms up for five seconds before sampling. It checks both registry count and
living native actors at the start and end. This is a real actor load test in the
cloned Riverside save, not a synthetic loop or remote expedition test.

The first 8-member run (`SC-Harness-20260928-061649-5bbb6ccf`) passed with
whole-mod tick p50/p95 **3.742/6.108 ms**. The first 16-member run (`062021`)
kept all 16 alive and measured **4.689/7.758 ms**, but failed panel cadence:
14 completed refreshes in 30 seconds, with a 2,152 ms longest gap. Its
8-member precursor used a 150 ms maximum scheduler delay for UI slices.
Reducing that delay to 50 ms produced 22 refreshes and a 1,370 ms gap in
`062729`, still below the fixture's minimum 30 completions. A 1 ms overdue
threshold for the existing 50 ms UI slice task gives its next slice a prompt
turn after it becomes due. It does not change the roster's 500 ms freshness
cadence or the per-slice work limit.

Three same-build 30-second base-scene samples with that UI schedule passed:

| Native companions | Run suffix | Whole-mod tick p50/p95 | Render p95 | UI completions / longest gap | LF ticks over 2 ms |
| --- | --- | --- | --- | --- | --- |
| 4 | `064445-eebb818c` | 1.638 / 6.478 ms | 26.809 ms | 50 / 634 ms | 682 / 1,798 |
| 8 | `064047-87ffc671` | 3.216 / 6.493 ms | 24.828 ms | 42 / 767 ms | 1,564 / 1,798 |
| 16 | `063849-8dd4a8b4` | 4.726 / 7.901 ms | 23.749 ms | 30 / 1,034 ms | 1,779 / 1,793 |

Each had 361 slot-0 chunks, no slot-1 chunks, four sampled zombies, and 30
native samples. The 16-member panel responsiveness improved from a 2,152 ms
to a 1,034 ms longest gap (about 52% shorter), while whole-mod p95 remained
around 8 ms; these separate runs cannot isolate a code-level CPU saving.
Process CPU grew by about 46.6, 46.3, and 48.0 CPU seconds across the three
roughly 29-second process sampling spans, respectively, and working sets at
the end were about 8.05, 7.96, and 8.04 GiB. These process totals include the
whole game and are too noisy to attribute to LF. The Java heap grew during
each short sample; retained-memory and garbage-collection conclusions need
longer runs.

This pilot establishes that 2 ms is below even the measured p95 of the quiet
four-member base scene. It remains a stretch target for shared LF overhead,
not a proven safe hard cap at 8 or 16 members. The next W09 evidence must use
the same build and route for no expedition, one expedition, and concurrent
player danger; repeat samples and measure streamed chunks, native simulation,
movement responsiveness, and cleanup before setting release limits.

## Two-view expedition population pilot

The remote performance fixture now accepts total populations of 8 and 16.
The four original saved companions form the actual expedition: their leader
occupies local slot 1, and all three followers are transferred to the remote
area. The additional native companions spawn near the original player in
slot 0's area and remain independent of the mission. The fixture checks this
distribution, exact living population, both slots, and panel cadence. It
therefore measures one four-member expedition **plus** local population,
not an eight- or sixteen-member expedition squad. The fixed-site transfer is
test-only; none of these samples proves a long walking route.

| Scene and total companions | Run suffix | Whole-mod tick p50/p95 | Render p95 | Sampled zombies | UI refreshes / longest gap | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Remote, 4 | `065542-75cf6e76` | 6.956 / 11.306 ms | 23.704 ms | 75–78 | 50 / 635 ms | Pass, 4 alive |
| Remote plus local player combat, 4 | `065941-5214f4ab` | 5.151 / 9.076 ms | 22.769 ms | 70–73 | 49 / 1,127 ms | Pass, 12 native player hits, 4 alive |
| Remote, 8 | `070354-af9b12eb` | 9.508 / 21.468 ms | 29.119 ms | 75–80 | 42 / 791 ms | Pass, 8 alive |
| Remote, 16 | `070621-3212e61f` | 8.104 / 11.654 ms | 23.670 ms | 78–81 | 31 / 995 ms | Pass, 16 alive |
| Remote, 8 repeat | `071327-39962f36` | 5.385 / 10.689 ms | 25.059 ms | 67–73 at end | 41 / 773 ms | Fail, 7 alive at end |

The repeated eight-person run is a failed acceptance case. An original
expedition follower died during the timed window with two bleeding bites and
terminal Knox infection; the console records native health reaching zero.
The 30-second sample and panel remained measurable, but its unequal living
roster prevents a clean eight-person timing comparison. The first eight-person
sample's high p95 coincided with heavier medical delegation (8.67 ms recent
p95 versus 3.32 ms in the sixteen-person sample) and decision work. Comparable
sampled zombie counts did not make actor wounds, positions, or work mix equal.
The lower p95 in the player-combat fixture likewise does not mean local combat
reduces cost.

The process sampler recorded about 59–69 CPU seconds over each roughly
29-second sampling span, with final working sets of 8.90–9.13 GiB. These
figures include the whole game. The two-view chunk samples held 361 slot-0
chunks and 342–361 slot-1 chunks; at the start of each measured window both
slots reported 361. Slot admission took 296–412 ms and the fixed-site remote
area became ready 171–344 ms later across the passing runs. Those one-off
transition times do not describe continuous route streaming.

These runs establish that the second view, two loaded 361-chunk maps, a
four-member remote team, and total native populations of 8 and 16 can remain
active for a 30-second window with the panel responding. They do not set a
release FPS or 2 ms pass claim. More repeated route-matched windows, longer
memory observation, native streaming attribution, and an actual larger squad
are still required.

## Walking-route comparison with a local encounter

The live timing harness can now sample a 30-second window while the actual
four-member expedition walks its native waypoint route. It records the
leader's measured displacement and slot-1 map shift, then continues the
route to its ordinary endpoint. The same fixture can run a native melee
encounter at the Riverside player in slot 0. The process sampler now stops
at the end of the timed window; earlier route artifacts contain later
process rows, so their first 30 rows are used for the comparison below.

All runs used the same 42.20.4 client, 0.25.30 test build, and disposable
copies of the same source save. The remote fixture made one test-only
transfer to the fixed distant area before walking. The quiet fixture
cleared nearby remote zombies, including during the initial outbound leg;
the local encounter spawned one native zombie only beside the player.
All three passing walking runs followed the eastward path near
`(6601,5306)` through `(6700,5306)`, moved slot 1's map origin 104 tiles,
and finished roughly 103 tiles from the remote start with followers loaded.
The exact initial actor position and 30-second movement distance varied.

| Scene / run suffix | Whole-mod recent p50/p95 | Render p95 | Route distance in window / slot-1 shift | UI completions / longest gap | Process CPU over first ~30 s |
| --- | --- | --- | --- | --- | --- |
| No expedition, `105917-cd0c6522` | 1.726 / 6.924 ms | 26.772 ms | no slot 1 | 50 / 630 ms | 47.688 s |
| Walking expedition, `104948-6b3f3474` | 1.979 / 9.324 ms | 25.818 ms | 9.31 / 8 tiles | 49 / 831 ms | 59.922 s |
| Walking expedition plus player combat, `105439-fcb35f1b` | 2.162 / 9.326 ms | 25.949 ms | 5.67 / 8 tiles | 48 / 1,253 ms | 63.719 s |
| Walking expedition repeat, `110212-1b5c1368` | 2.042 / 7.946 ms | 25.638 ms | 5.26 / 8 tiles | 50 / 756 ms | 60.047 s |

The combat window recorded 11 native player hits, with the player and all
four companions alive at sample end. The quiet and combat routes also passed
their full 103-tile native-footprint checks after the sample. Slot 0 held
361 chunks throughout; slot 1 held 361 in the timed walking windows,
versus zero in the base window. Native zombie counts were 4 in the base
window, around 9-10 in the walking windows, and the combat fixture changed
the local zombie population. These differences, varying decision work, and
different distance covered prevent a causal per-expedition or per-combat
cost estimate from these small samples. The whole-mod percentiles cover
the latest 120 ticks at report time, not every tick in the 30-second window.
CPU and render figures include the whole game, not just Living Fellows.

An initial walking run (`104539-1f42c565`) produced a valid 30-second
sample but failed the later outbound waypoint: medical work diverted the
leader because the quiet fixture omitted that first route phase. The
fixture now covers it; the failed route is excluded from the table. The
repeat run proved the corrected process sampler stops at exactly 30 rows
while the route continues. This gives an actual movement-and-streaming
cost pilot, but no release FPS or 2 ms pass claim. Repeated windows under
matched actor wounds and work mix, longer memory observation, return and
cleanup timing, and a larger actual expedition squad remain open.

## Working frame-time threshold

The 2 ms whole-mod target is retired as a pass/fail criterion for the current
split-view prototype. Use **12 ms p95 for the whole-mod tick** as a provisional
review threshold while developing the four-member expedition with up to 16
native companions loaded in total. The quiet 16-member pilot measured 7.901 ms
p95, the two-view 16-member pilot measured 11.654 ms, and the walking four-member
samples measured 7.946-9.326 ms. One two-view eight-member pilot measured
21.468 ms, so the new threshold is not yet a release pass. Keep checking panel
cadence, actor movement, render intervals, and memory alongside tick cost.

The runtime `frameBudgetMs=2` is a scheduler callback-admission threshold, not
an enforced whole-mod cap. Raising it changes adaptive load and decision
cadence. Leave that runtime value in place until an expedition behavior change
requires a targeted comparison. The 12 ms number is a working review threshold,
not a reason to cut off movement, follower upkeep, or room entry.
