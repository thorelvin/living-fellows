# Expedition v5 verification ledger

## 2026-09-28 versioned 0.26.1 playtest candidate

The versioned source, release metadata, and user instructions are now aligned
at 0.26.1 on `living_fellows/0.26.1`. `scripts/Test-Project.ps1 -Jobs 4`
passed against the pinned 42.20.4 runtime: source, core, gameplay,
navigation stability, perception topology, UI, live-harness static,
Workshop playtest packaging, and standalone packaging all passed. The
reproducible Java bridge matched the payload JAR.

The resulting playtest archives are
`build/release/LivingFellowsCompanion-0.26.1-PLAYTEST.zip` (SHA-256
`2ABD70646A16DE51B40E8BF0A604308F6FDD78523F1788C285CC62DA4A529C2D`)
and `build/release/LivingFellowsCompanion-0.26.1-STANDALONE-WINDOWS.zip`
(SHA-256 `DE2B5EE3F408CE16B83B9E1F035EA35FDA89C52245F7456CC6529DAB4A801DF3`).
The standalone installer/uninstaller passed its isolated transaction test.
The live evidence below predates the autonomous downtime change as well as
version and documentation changes. Focused UI and gameplay suites cover the
downtime change; no new game run was made for this packaging pass. This is a
playtest candidate, with the intermittent Riverside departure stall and full
distant return still open.

## 2026-09-28 autonomous downtime GUI update

The Orders tab no longer offers the Idle/Craft work-mode selector. Safe
downtime now scores available reading, repair, crafting, rest, and other
activities for the companion regardless of a legacy saved Idle/Craft value.
The normal decision owner still gates downtime against travel, danger, and
urgent needs. Scores, personality and objective modifiers, and repeat
cooldowns make the choice stable between state changes; the occasional
ambient flavor roll does not drive the main activity choice. Focused UI and
gameplay suites passed, including legacy Craft allowing reading and legacy
Idle allowing crafting. No additional live game run was made for this GUI
change.

Updated private test archive:
`build/expedition-private-patch-20260928-downtime/LivingFellows-Expeditions-PrivatePlaytest-Downtime.zip`
(SHA-256 `B7BAE0A05B497285B506233A59D4D3F4C6E230E8CEB0F1AE452BF4443E993C76`).
It contains the revised UI, downtime logic, and versioned bridge. The
intermittent Riverside departure route and the remaining v5 gates below are
still open.

## 2026-09-28 planner state and observed-information patch

The selected combat style is now a mission-local doctrine applied by the
decision and combat owners. Launch does not rewrite the squad's saved combat
commands; a save/reload retains the mission doctrine, and ending the mission
exposes the original commands again. The focused restart harness passed this
case. The active Expeditions card shows the planned destination and explicitly
marks current progress unknown. Hidden mission members are represented by
their departure names in the roster without live health, distance, position,
or death status, and do not appear as live map markers. Locally visible members
may show their observed state. Core and map tests cover these projections;
other UI surfaces and the full WP07 information boundary still need audit.

The focused expedition restart harness, gameplay suite, UI suite (85 contract
tests), and whitespace check passed. In disposable Riverside run `143318`,
the planner opened, reviewed and launched the three-member squad with equipped
top-level radios, but the leader advanced only 2.46 tiles in 30 seconds. Native
navigation reported unreachable paths from the gas-station exit. Run `143704`
sent the first radio context action at 2.07 tiles and observed no native text
event (`radio_no_ack`). The pinned Build 42 held-radio bytecode accepts a
positive-range transmission only when receiver distance exceeds three tiles;
the UI now gives a plain no-receipt hint for this case and other missed signals.
Run `144010` repeated the route with a
shorter verified waypoint and still stopped at 2.67 tiles, so that waypoint
change was reverted. All three runs used clones, restored the launcher, and
left the original save untouched. Earlier `140149` remains the successful
8.01-tile native Return immediately proof. A robust departure from this crowded
gas-station position, a full distant return, one-way radio feedback, and the
remaining v5 acceptance gates are open.

A final diagnostic clone `144830` used the unchanged waypoint policy and
**passed**: the selected leader moved 8.03 tiles, the first radio context
action received the exact native leader-side event, and Return immediately
changed the itinerary to inbound with `radio_return`. This shows the exit
failure is intermittent in this starting formation. The harness now records
the surveyed route, native status, and a screenshot if this same wait times
out; the successful run did not produce a stall screenshot. The original save
and launcher hashes remained unchanged.

A private payload was staged with `New-PrivatePlaytestPayload.ps1` at
`build/expedition-private-patch-20260928/SurvivorCompanion` and archived as
`LivingFellows-Expeditions-PrivatePlaytest.zip` (SHA-256
`13A37CC6F428B4A437EED8AC42E2048B899A968EA9CAB53047CBF5210F1DE0FA`).
The archive contains the planner and versioned bridge. It is for the isolated
single-player bridge playtest, not the Workshop release channel.

## 2026-09-28 private planner and radio MVP update

The Living Fellows panel now has an **Expeditions** tab in this test worktree.
It drafts a mission from the already configured Alpha/Bravo/Charlie squad,
selects one of its one to four members as leader, chooses Scout or Search,
time before turning home, Stealth/Close Defense/Aggressive combat doctrine,
requested supplies for Search, and a bounded nearby building candidate. The
review step is effect free; Send squad revalidates roster and place before
promoting the chosen leader. Aggressive uses the existing Weapons Free doctrine.
Map-derived places are labelled unconfirmed. The mission can depart without
radios.

Right-clicking the player's equipped portable radio during an outbound
expedition now puts **Return immediately** at the top of that item's inventory
menu. It uses the native radio text acknowledgement already used for the
private movement-order slice, then abandons the outbound leg and starts the
recorded return trail. A core harness checked the acknowledged transition,
the `radio_return` itinerary reason, and rejection of radios packed in nested
bags despite stale hand references. Cloned run `140149` opened the actual
Expeditions tab, reviewed a selected Alpha squad and loaded destination,
launched the selected companion in slot 1, confirmed both radios remained
equipped in their owners' top-level inventories, then sent **Return
immediately** from the first right-click option at 8.01 tiles. The exact
leader-side native acknowledgement changed the mission to inbound with
`radio_return`. The original save and launcher were untouched. The long remote
return stall remains open, so WP04 and the full radio/UI matrix remain partial.

The expedition decision adapter now applies a temporary follower spacing of
two tiles during travel, expanding to five only while the leader is in an
indoor Search phase. The return leg restores two-tile spacing without changing
the companions' saved Follow settings. The focused restart harness checks the
phase changes; a live formation run is still needed to judge door crowding and
whether indoor spacing is sufficient.

This ledger tracks the full attached v5 plan against the private test build.
It is a test record, not release approval. The owner's later decisions supersede
two v5 assumptions: an expedition may depart without a radio, and its **actual
companion leader** may occupy the second local player view to load the area.
Only received radio traffic may grant new remote commands. All other native
world, item, danger, communication, recovery, and UI gates remain open.

## Runtime pin

| Item | Current evidence |
| --- | --- |
| Living Fellows checkout | `10436068ca32ba953d821ba8145ba70bdbff459f`, dirty private worktree, version `0.25.30` |
| Installed Project Zomboid | Console reports `42.20.4 b0bbce05d5`; `projectzomboid.jar` SHA-256 `80E405A4BFC42F6072E75B3735F458A6514143DA011D3226007DED305A442F44` |
| Native bridge protocol | `42.20-isocompanion-12` |
| Isolation | Disposable clone of `2026-09-21_22-10-41`; launcher restored and installed bridge unchanged after each run |

## WP01-A: native world gates

`SC-Harness-20260927-010443-77ab2b95` passed **46/46** live assertions.
This run used three saved companions 512 tiles from the Riverside player. The
transfer to the fixed site was test-only; it is not route evidence. A later
25-second run, `SC-Harness-20260927-010820-0cfeb896`, measured native fatigue,
hunger, thirst, and endurance changes while the remote area was active.

| Gate | Status | Evidence still needed |
| --- | --- | --- |
| W01 remote authoritative lookup | Partial | Ordinary square lookup and render work with the actual companion in slot 1; inspect rooms, collision, containers, and overlap. The second slot is the owner's newer design. |
| W02 natural population | Partial | Fourteen natural zombies were present at peak in a later run; ten tracked native zombies moved without fixtures. A separate waypoint probe observed unforced leader damage and death with fourteen natural zombies active. A specific pursuer crossing the streaming boundary remains unproved. |
| W03 moving footprint | Partial | The actual leader and two original followers completed a 99-tile outbound and 98-tile return walk through loaded, pathfinder-admitted legs in one cloned run (`111423`). Slot 1's 152-tile-wide map shifted 96 tiles east and then 96 west; the original remote square unloaded outbound and reloaded on return, while the far endpoint unloaded. Largest observed leader step was 0.097 tiles, and both followers remained on loaded squares within 12 tiles. The initial transfer to the remote test site was the only teleport. A separate Riverside run started beside the player and walked across a chunk edge and back without any setup teleport. Quiet fixture runs verified native room entry and exit through an ordinary route (`114707`), a locked window the leader smashed and cleared (`121604`), and an ordinary locked door opened from inside without a key (`125212`); slot 0 did not cover the rooms, and two followers stayed loaded nearby. A further test-only transfer beside a locked door proved a native axe action destroying that door and the leader walking through the resulting breach (`132429`). A current-build inside-unlock recheck passed (`134205`). A separate cloned sealed-room fixture (`141738`) proved automatic last-resort bash selection, native axe damage and door destruction, and entry by the actual leader; the harness transferred the team beside the door and placed native barricades at alternate exits. A current-build window run (`142129`) still used a locked window and cleared its glass. A joined Riverside probe (`145358`) walked the saved leader and two followers from the player to a native stocked cupboard across a chunk boundary, looted one exact item, walked home, and released slot 1 without any setup transfer. An autonomous no-transfer scout (`171240`) then took the actual leader and two followers about 84.5 tiles east and back with bounded local planning and no harness waypoints. A no-transfer Search entered a previously unvisited building and returned the whole saved team in cloned run `215129`, after two earlier regroup failures (`212857`, `214058`); no requested items were present. A complete long remote journey, natural danger during long travel, and a bounded multi-member lease remain unproved. |
| W04 straggler and pursuing threat | Partial | A focused cloned-save run (`104114`) held one original follower while the real leader walked 10.50 tiles away, then stopped at a 12.03-tile gap. The follower's authoritative tile remained loaded in slot 1's map. After release, the follower rejoined and the leader completed its waypoint. A separate native-zombie fixture run (`110816`) kept the same alive, loaded zombie targeting a team member while slot 1 shifted 16 tiles; its sampled step stayed below 3 tiles. The natural-zombie attempt did not reach a useful handoff. Full streaming-tail cap/recovery behavior and natural pursuer continuity remain unproved. |
| W05 exact native loot | Pass for fixed-site and one controlled local Search reload | An original saved companion used the existing encounter/search owner to move `Base.WeldingMask` (native ID `2090704567`) out of a stocked native container at `6580,5328`. The source lost that exact object and the companion held it. After saving and reloading a clone, its serialized marker appeared once in the same companion's snapshot; a player visit loaded 3,721 remote squares and 54 containers, found one marked item on the restored companion and none in world containers. The fixed-site relocation was test-only. Joined Riverside runs (`145358`, `175330`) walked to a native cupboard and returned with the same exact `Base.FiberglassTape` item (ID `1367551867`), with the latter applying a construction-category request. Autonomous local Search runs (`182810`, `183706`) independently chose that native cupboard, debited it from 14 to 13, and returned with one exact requested item. An active inbound Search checkpoint (`184941`) saved one matching receipt and inventory marker; replays (`190015`, `190158`) restored exactly one stable item on the leader, found none left in the depleted 13-item source, and carried it home with one returned ID. Long remote travel with cargo and multi-category reconciliation remain unproved. |
| W06 player/party area overlap | Partial | In cloned live runs, both local slot chunk maps covered the remote source during player arrival. Ordinary lookup returned the same Java square, world object (one occurrence), and container; slot 0 stayed the player and slot 1 the original companion. After player departure, slot 0 no longer covered the source while slot 1 did. A joined-team release cleared slot 1 without unloading the player-owned square or changing any original actor, and a second departure reused the same leader and world object. A separate short local out-and-back trip also released slot 1 after the team walked back to the stationary player. A joined local loot trip (`145358`) also returned beside the player and released slot 1 with the exact native item still carried. Overlap update counts and longer travel/cleanup paths remain unproved. |
| W07 native survival and lethality | Partial | Native endurance, fatigue, hunger, and thirst changed during a 25-second remote watch. Separate waypoint runs showed unforced health loss (40% to 32.3%, 37.6%, and 12.8%) and one unforced death (40% to 0) before harness injury; the actual successor took slot 1. Exact native corpse inventory and worn-gear transfer passed in an all-dead clone. Stage/reload pairs preserved three exact tagged worn items and, later, one exact tagged carried bandage per actor through corpse creation, view unload, and native reanimation. A native 103-tile route, slot-0 visit, and process-restart visit preserved one follower's inventory-owned worn item and exact marked bandage after the slot-1 footprint moved beyond the death site (see below). Infection, device upkeep, broader inventory cases, and longer survival remain open. |
| W08 interruption and restart | Partial; mixed-save and one active-cargo checkpoint passed | A local reload reacquired the original three companions and slot-1 leader. The ordinary mission pulse now starts the cold loader and hands its view to the exact saved leader after normal persistence restores all three remote actors. Cloned runs `080214` and `080441` passed without row growth. A forced native-row-first crash recovered in `081356`; a later LF-newer checkpoint with a stale temporary native row recovered in `082200`. Both restarts restored the clothed originals and reused slot ID 3. The inbound Search checkpoint (`184941`) restored one exact requested item and mission receipt; two replays (`190015`, `190158`) returned it home and released slot 1. One intermediate replay (`185357`) restored cargo but failed the route because the stall counter accumulated across progress; the consecutive-stall fix passed the later replays. Crash checkpoints carrying requested cargo, death checkpoints, other interruption points, and old ghost-row cleanup remain open. |
| W09 bounded cost | Partial; base 4/8/16 pilots and walking-route windows recorded | Three same-build 30-second cloned-save base samples (`064445` four, `064047` eight, `063849` sixteen) retained the exact living native population and passed panel cadence. Whole-mod p95 was 6.478/6.493/7.901 ms, respectively, above the approximately 2 ms target. The newer same-source-save comparison measured no expedition (`105917`: 6.924 ms p95), a walking four-member expedition (`104948`: 9.324 ms; repeat `110212`: 7.946 ms), and the walking expedition during 11 native player hits (`105439`: 9.326 ms). Each walking run completed about 103 tiles and shifted slot 1's native map 104 tiles; the 30-second timing windows included a real 8-tile map shift. UI cadence passed in all four windows; see `docs/frame-timing-review-2026-09-28.md` for scene and sample limits. One fixed-site transition (`102413`) measured 424 ms for slot admission and 176 ms for remote area load, pending queue peak one. Fixed release limits, controlled repeated cost attribution, long-route loading and cleanup cost, longer memory observation, and an actual larger expedition squad remain open. |
| W10 resource cleanup | Partial; direct menu handler passed for active and idle states | In memory, all-dead and joined return released the second view and its chunks while preserving slot 0. Death handoffs and remote restarts reused a slot row. Joined return reused ID 2 in session (`083139`) and after reload (`084042`). All-dead reuse passed in session (`085148`) and after reload (`090103`); native row 2 was marked dead before release (`085938`). A direct live call to the main-menu handler during an active remote mission released LF's slot 1, UI, chunk map, actors and callback (`091001`). The handler now saves and flushes active and idle LF descriptors before teardown. An active run without harness presave (`091758`) reloaded all three dressed mission actors and the exact leader/slot ID (`091917`). An all-dead idle menu run (`092221`) reloaded its one survivor and reused ID 2 (`092341`). The native row remains dormant when released. Actual UI menu order, older ghost-row removal, cancellation, disable, repeated cycles and stale load completion remain open. |

The 2026-09-28 review of `FRAME-TIME-FIXES.md` confirmed that the older LF
2 ms scheduler report excluded pre-scheduler `productionTick` work. Whole-tick
duration metrics and a precise bridge clock are now implemented. The first
four-companion base-scene live baseline (`002620`) recorded a whole-tick
recent-120-sample p50/p95 of 3.647/14.222 ms, a since-reset maximum of
34.166 ms, and pre-scheduler recent p95 of 0.054 ms;
the scheduler exceeded its 2 ms budget in 1,466 of 2,633 ticks. Earlier
scheduler p95 values cannot be read as whole-mod tick p95. This single scene
does not establish 8- or 16-companion cost. See
`docs/frame-timing-review-2026-09-28.md`.

A separate two-view remote sample (`003008`) with the saved four-member team
and natural remote zombies recorded whole-tick recent p50/p95 of
9.717/18.797 ms and pre-scheduler p95 of 0.097 ms. Its UI panel completed
only 12 refreshes in 30 seconds, with an 8,180 ms longest gap, failing the
existing cadence gate. The same run hit an obsolete test assertion that
expected the fourth companion to stay at Riverside; it was correctly with
the leader, and the assertion is corrected. The data is useful but the run
failed. This strengthens the W09 cost finding and leaves its performance
gate open.

The focused medical profile (`003829`) counted 11,951 fresh assessments,
with 0.523 ms recent p95 per call, while a UI row description took
13.129 ms recent p95. An opt-in decision-level assessment cache, with fresh
treatment verification and mutation invalidation, cut the fresh count to
1,921 in the next comparable four-member remote fixture (`005814`). That
live run passed its sample and UI cadence checks: whole-tick recent p95
10.377 ms, 41 panel refreshes in 30 seconds, and a 920 ms longest gap.
The 2 ms whole-tick budget still fails, and the source-only UI load-summary
shortcut made after this sample needed a live recheck. It reduced UI row
description to about 1 ms recent p95, but one run (`010254`) still finished
only one panel refresh and a repeat (`010631`) had a 3,400 ms longest gap.
The live cadence gate now rejects gaps over 2,000 ms. A bounded 150 ms
overdue slot for the UI background task passed a scheduler regression and
the next four-member remote live run (`011131`): 40 completions in 30
seconds, maximum gap 868 ms, all three followers near the slot-1 leader,
and natural remote zombies updating. Whole-tick recent p95 was still
13.173 ms. The panel responsiveness gate is supported for this scene;
W09's 2 ms and 8/16-companion cost gates remain open.

Follow-up W09 profiling separated delegation by decision kind in remote
four-member run `012938`: medical p95 8.320 ms, combat p95 5.801 ms, and
3,417 full medical scans since reset. Using the short lived decision cache
for rescue-candidate ranking cut those full scans to 1,607 in the next
same-fixture run `013218`; it passed the UI cadence check, with a whole-mod
recent p95 of 11.809 ms versus 12.571 ms previously. Different natural
activity prevents attributing that p95 change solely to the cache. A busier
combat sample `013507` measured target/action pair selection at 6.895 ms
recent p95 within combat delegation, confirming an additional cost path.
The 2 ms cost gate is still open.

Follow-up perception profiling located a second W09 cost: reflex escape
planning took 3.878 ms recent p95 in run `015218`, and the next run
`015448` attributed 1.993 ms to scoring candidate corridors. Scoring now
reads each route node once for all threats; a two-threat ranking regression
and the current four-member remote sample `015830` passed. That sample
measured 1.254 ms recent p95 for scoring and 4.63 ms for the whole reflex
pass, while the whole-mod tick still measured 12.880 ms recent p95. These
are live scene measurements with variable danger, not a 2 ms acceptance.

A later profiler-ring and scheduler-name change passed the rolling-sample
regression, core 47/47, and installer 35/35. Four-member remote run
`SC-Harness-20260928-022429-abd6ffe3` passed three-follower proximity,
exact saved outfit identity for all four, natural zombie movement, and UI
cadence (36 refreshes in 30 seconds; longest gap 867 ms). Its whole-mod
recent p95 was 10.272 ms. Variable natural activity prevents assigning the
change in p95 to the profiler alone; W09 remains partial.

The versioned-roster P3 pass then passed the full 9/9 project gate. A fresh
four-companion base clone (`SC-Harness-20260928-033110-c08b3a12`) kept its
population and slot stable, passed UI cadence (48 refreshes, 716 ms longest
gap), and measured whole-tick p50/p95 **2.066/6.647 ms**. It is a
current-build base reference, not an isolated P3 saving against `002620`,
which predates several other changes. Remote run `032636` observed the
original leader die of Knox infection, a successor take slot 1, and a
production fifth companion spawn during sampling. Its fixed-four population
gate failed, so its 14.978 ms p95 is stress data rather than a comparable
four-member timing result. W09's 2 ms and 8/16-member gates remain open.

The later P4.1–P4.6 call-layer pass passed the full 9/9 project gate and two
stable four-companion base samples (whole-tick p95 6.289 and 7.120 ms).
Its fixed-roster remote fixture selected the healthiest original saved
companion and capped only the disposable test clone at four, after earlier
attempts ended in native leader death or a fifth production spawn. Run
`SC-Harness-20260928-040309-406525db` then passed the 4/4 roster, second
local view, three follower positions, natural zombie update and UI cadence;
whole-tick p95 was 15.519 ms. The changed actors and natural activity prevent
a controlled P4 speed claim. W09 remains partial; see the frame timing review.

The P5 combat inventory index passed the full 9/9 project gate and a
four-original-member remote clone (`SC-Harness-20260928-041758-2d204f51`)
with a slot-1 leader, three followers, natural zombie updates, and UI
cadence. Its whole-mod p95 was 12.154 ms, still above budget. A second run
recorded 4,147 index hits and 632 builds, but one original follower died and
a fifth production companion appeared, invalidating the fixed-four timing
comparison. W09's 2 ms and 8/16-member gates remain open.

The P6/P7 shared zombie and per-frame actor fact passes cleared 9/9 project
tests. Two further four-member remote clones (`043514` and `044258`) passed
the original team, actual split-screen leader, follower, natural-zombie and
UI gates. Their whole-mod p95 values were 13.308 and 13.349 ms. Zombie fact
hits were counted directly, but variable activity prevents attributing a
timing change to either pass. W09 remains partial; bridge bulk facts and
8/16-member acceptance are still open.

The P1b native body-facts bridge cleared the 9/9 project gate. Initial live
sampling found a wounded-part `NoSuchMethodError` caused by a compile-only
stub's wrong `getType()` return type; the exact installed-game signature is
now pinned. Corrected remote samples recorded 3,496/3,496 and 5,450/5,450
medical assessments through the bridge, including natural wounds, with no
Lua fallback. Assessment p95 was 0.069 and 0.066 ms; earlier mixed-path runs
were near 0.58 ms. A follower died naturally during the 30-second windows,
so neither sample is an equal-four-living-member whole-tick comparison. The
disposable fixture now prevents replacement encounters and fails when living
population changes. The last sample retained four records, passed leader,
follower, native-zombie, and UI checks, and failed only its new living-roster
gate (4 to 3). W09's 2 ms and 8/16-member gates remain open.

The first P8 navigation pass moved tree and vehicle clearance into a bounded
navigation cache and gave A* private numeric node keys. Navigation regressions
and the full 9/9 project gate passed. Two cloned autonomous Scout runs
(`052256` and `052942`) each walked the actual leader and saved followers
about 85 tiles to a chosen site, observed nine visible squares, and returned
to the original player without a setup transfer. The next P8 pass skipped
key construction for empty blocked-edge, blocked-square and route memories;
regressions checked empty and populated gates. A cloned Scout (`053841`)
replanned and returned, and a native door fixture (`054246`) entered and
exited a remote building through a door unlocked from inside. Both passed.
These runs verify routing behavior; they do not establish a timing saving.
Static-edge reuse, the 2 ms budget, and 8/16-member cost gates remain open.

P8 neighbor expansion now supplies numeric keys from its already known
coordinates, and the path search falls back to its key callback for adapters
that do not supply them. Navigation stability passed 958 checks and the full
project gate passed 9/9. A further cloned Scout (`054950`) completed the
81-tile round trip with the actual leader and three followers. A remote
interior run (`055343`) planned loaded approaches, entered through an ordinary
door, and left through a door unlocked from inside. Both restored the
launcher. The runs verify behavior; timed pathing comparison remains open.

The next W09 remote sample (`055811`) recorded whole-mod p95 8.885 ms and
combat pair-action p95 5.189 ms, but a natural zombie killed one follower;
the equal-roster gate correctly failed. Needs assessment now reuses the rate
sample until an eat/drink action finishes, and combat steering reuses each
threat's life/floor/position facts across candidate headings. Focused tests
and the full 9/9 project gate passed. The repeat remote sample (`060554`)
passed with all four original companions living, natural zombies active,
whole-mod p95 7.504 ms, combat pair-action p95 1.150 ms, and 42 UI refreshes
in 30 seconds. Zombie counts and action mix differed, so this is not a
controlled speed claim or a 2 ms acceptance. W09 8/16-member scaling and
release limits remain open.

A separate quiet four-member Riverside Search (`20260928-001825-93d92ed5`)
admitted the saved leader to slot 1 and assigned all three other saved
companions to that leader. It entered a previously unvisited office, debited
one exact native `Base.DentalFloss` item (ID `1968202274`) from a source
container (1 to 0), and returned that same item with a quantity-met debrief.
The route visited 18 chunks; the largest sampled leader step was 0.1709
tiles. The production return guard required all living followers on the
leader's floor and within 12 tiles before mission completion, and the last
trace showed all three within 10 tiles. Slot 1 was released while the player
kept slot 0. The test-only fixture cleared natural zombies near the start and
destination, so natural danger and a county-scale trip remain open. This adds
four-member Search/return evidence to W03 and W05 without closing their other
gates.

The current timing/cache build repeated that quiet four-member Search in
`SC-Harness-20260928-011418-f72cb503`. The saved slot-1 leader entered the
unvisited office, considered two native sources, took the same exact native
`Base.DentalFloss` ID `1968202274` from a 1-item source (now 0), and
returned it with `outcome=returned`, `end=quantity_met`, `acquired=1`,
`returned=1`. The route covered 18 chunks with maximum sampled leader step
0.0982 tiles. All three followers repeatedly regrouped and satisfied the
production return guard. Slot 1 was released and the original launcher was
restored. This verifies the performance scheduler changes did not break
this quiet local Search; natural danger on the route remains open.

A four-member known-place Scout (`SC-Harness-20260928-012452-61837866`)
used the player-seen fire station target and walked from the Riverside player
to its exterior approach at `(6114,5257)` without a setup transfer. The
leader observed six visible squares, retained a complete debrief, and
returned to the original player. The harness measured 58.3 tiles of maximum
displacement, eight outbound legs, a largest sampled leader step of 0.0732
tiles, and a largest follower gap of 12.05 tiles; the mission still returned
successfully with all four saved members. This Scout run did not enable the
Search zombie-clearing fixture, but it did not assert a natural zombie
engagement or boundary-crossing pursuer. It adds a current-build local
route check, not proof of W02/W04 natural threat continuity.

The generic recruited-follower recovery previously had a path that would
reattach a missing remote member beside the Riverside player. The private build
now retains an expedition member's identity and position on that failure and
records a technical issue. This prevents a false successful transfer; it is
not a working moving-area retention system. The new recovery branch has not
yet had a destructive live fault-injection test.

The W03 probe is test-only: it stages a standing waypoint through the existing
navigation owner after remote chunks integrate. It never changes the player's
position or issues a remote Orders command. Its failing arrival assertions are
retained as evidence, not treated as completed travel. See
`docs/expedition-moving-area-probe-2026-09-27.md`.

The W04 delayed-follower probe and its two failed setup runs are documented in
`docs/expedition-w04-straggler-probe-2026-09-27.md`. The prototype now pauses
the leader's staged waypoint when any living follower is at least 12 tiles away
or lacks an authoritative square, and resumes at less than 8 tiles. It cancels
only its owned `ordered_move` route when no supervised action is active; combat
and other survival decisions remain scheduled. This guard is limited to the
prototype waypoint owner. It does not implement a bounded multi-member area
lease or validate pursuer continuity.

The W04 native threat fixture later passed a separate leading-edge handoff
(`SC-Harness-20260927-110816-789d7447`): one real `IsoZombie` was spawned
ahead of the walking team in a disposable clone, targeted the actual leader
once, then remained the same living, loaded actor with a team target after
slot 1's map minimum moved from 5528 to 5544. Two unforced natural-threat
attempts (`104837`, `105237`) did not get far enough along the southern route
to observe a pursuer crossing the boundary; they are inconclusive for natural
population. A fixture run (`110457`) showed why the probe must check target
continuity: a zombie behind the team moved but dropped its target. See the
W04 probe note for limits. The fixture result does not close W04.

A later local trip in `SC-Harness-20260927-045924-88439481` had no setup
teleport. The original leader walked an 11-node route from `6085.5,5308.5`
to `6095,5308`, crossing a native chunk edge in ordinary navigation. The
largest observed per-update movement was `0.0621` tiles, and both followers
remained within 15 tiles at arrival. A second 11-node route returned the
leader to within 2.46 tiles of the stationary player, where the joined-team
release succeeded. This establishes a small actual out-and-back trip, not
long-distance streaming or a complete task/search/debrief lifecycle.
The same trip passed again with the original save's full mod list in
`SC-Harness-20260927-050219-60befb22`: 11 loaded outbound route nodes, 10
return route nodes, two native chunks visited, followers near the leader,
and joined-view release within 2.36 tiles of the Riverside player.

Longer test-only waypoint runs then showed the slot-1 map move as the original
leader walked with two followers. The far-south run
`SC-Harness-20260927-053231-d1daed38` shifted its map minimum 72 tiles east
before natural combat killed the leader on leg 7. In
`SC-Harness-20260927-054340-665de78a`, a zero-zombie initial survey was
followed by more than 90 tiles of actual eastward leader movement; the leader
died during leg 6. That run failed its arrival assertion and did not perform
the old-square unload check. W03 remains partial. See the moving-area probe
for all admitted legs and the separate Riverside attempts.

`SC-Harness-20260927-055757-9ba26f67` checked the old square during the
walk. At 85.04 tiles of eastward progress, the living leader's current square
was loaded, the original remote square was absent from ordinary lookup, slot
1's map minimum had shifted from 6008 to 6096 at the same 152-tile width,
and both followers were within 10.58 tiles. Its largest measured update step
was 0.152 tiles. The original leader later died before a complete route or
return, so W03 remains partial despite the direct unload evidence.

The W05 source survey ran in
`build/live-sandbox-runs/SC-Harness-20260927-035622-b52c8447/`.
It inspected 3,721 loaded squares through ordinary world lookups after slot 1
chunk integration. The exact transfer and native source debit passed in
`SC-Harness-20260927-041413-1811a3c0`. Reloading that disposable save in
`SC-Harness-20260927-043509-89581eb9` preserved exactly one marked item on
the same companion; after player visitation, the marker and original native
item ID were absent from all 54 loaded world containers. The saved companion's
native ID was regenerated by normal restoration, so conservation is tracked
by the unique saved marker, type, and companion identity across reload.

The W06 merge/split probe passed in
`SC-Harness-20260927-044630-c6e7f103`. The first attempt never entered play
because adding three local probe callbacks exceeded Kahlua's 60-upvalue
limit; the harness was refactored to store them on its existing table. The
successful rerun passed the live identity checks and the live harness static
suite passed. This is shared-world overlap evidence, not a return/cancel
release proof.

The joined-team release ran in `SC-Harness-20260927-045209-41e1a5f9` and the
guard/restart regression in `SC-Harness-20260927-045414-d301bed0`. The latter
rejected release while the player remained 512 tiles away. Once the player
arrived beside all surviving members, it released the companion's second
chunk map and UI, kept the player-owned square and single native container,
and retained all original companion actors. A duplicate return was rejected.
Starting a second expedition then restored the same leader to slot 1 and
resolved the same world object. These are joined-site lifecycle checks using
test-only travel to the site, not proof of a complete return route.

The W08 restart audit found a concrete failure. A released local team view
left an extra native local-player row in `players.db`; restarting and promoting
another original companion added a third row. In the corrected active-remote
restart `SC-Harness-20260927-060959-7a325dbf`, the primary player was alive
but the mission was absent and two distant companion snapshots remained
pending on unloaded squares. The new durable descriptor now retains that
mission as a technical pause across repeated remote restarts
(`SC-Harness-20260927-062318-6975dae8`). A local mission reload
(`SC-Harness-20260927-063558-8339eea9`) successfully reacquired the exact
three companions and slot-1 leader; direct Orders and unequipped-radio
commands remained blocked. See
`docs/expedition-restart-probe-2026-09-27.md`. Persistent remote missions
remain disabled outside disposable test saves.
The isolated W08 cold-loader run `SC-Harness-20260927-070854-319b29e0`
passed. An unregistered `SCNativeCompanion` constructed at an unloaded tile
acquired that distant square through the native co-op loader; the second view
rendered and natural zombies moved. A separate saved-leader run
`SC-Harness-20260927-071419-4d70fe48` confirmed the actual companion retained
21 worn items in slot 1. A later targeted saved-tile run restored all three
remote actors and handed the view to the original leader; the undressed
temporary loader is now hidden until it is removed. The harness drove those
earlier runs. A persisted slot SQL ID prevented row growth on a second
repeat restart, while an older row remained. See the restart probe record for
the exact runs and limits. The later `080214` run exercised the new automatic
mission-pulse loader and handoff on a cloned remote checkpoint. All three exact
survivors restored, slot 1 became the saved leader, and `players.db` kept the
same IDs 1, 2, and 3. A second automatic restart, `080441`, repeated those
checks without row growth. A native-row-first forced crash also recovered in
`081356`; an LF-newer checkpoint also recovered in `082200`. Ghost-row
cleanup and several recovery cases have not passed. A later joined-return
probe persisted an idle slot ID and reused it with a different leader, both
before and after reload (`083139` and `084042`); each result had only IDs 1
and 2 in `players.db`.

## Other plan gates

| Plan area | Status | What is proved and what remains |
| --- | --- | --- |
| WP01-B and WP02 native radio, R01–R29 | Partial | The private kit spawned five genuine powered `Base.WalkieTalkie2` items for the player and four saved companions, with batteries and native `Living Fellows Team` presets at 90000. A cloned-save reload preserved their battery, power, channel, preset, and equipped state after a fix to companion item persistence. A separate mission test proved native signal to the remote leader at 512 tiles and a reply heard by the player. Retuning the leader to 90001, turning it off, or setting receive volume to zero prevented native signal receipt. A scoped native callback delivered text on the leader's exact radio and authorized one `set_move_mode` order; direct Orders and failed-receiver attempts stayed blocked. Focused cloned runs then registered exact placed walkie/HAM world items and proved native reception and `OnDeviceText` both ways at 512 tiles, plus HAM-outward-only contact at 2,047 tiles with a 2,000-tile field walkie. The pinned engine skipped placed receivers on the sender's same X or Y tile coordinate. An ordinary cloned-save reload preserved each placed device's native item ID, matching world proxy, powered state, and fresh receive function exactly once. A later cloned stage completed the game's timed walkie and HAM placement actions; fresh reload retained their exact item/proxy pairs and receive function. A further cloned run completed the game's timed grab on the placed walkie: the exact native item moved to inventory, its proxy and registration were removed, and its channel and power survived. The saved player was 97/12 overloaded, so this pickup required a disposable capacity override. Player-operated transmission, 3D cursor input, destruction, interference, depleted battery, full acknowledgement protocol and broader command language remain open. R17's departure block is superseded by the owner's no-radio rule. |
| WP03 assignment and context | Partial | One transient roster, leader-based follower formation, two successive death handoffs, and all-dead view release work. Roster persistence, admission rollback and doctrine independence are unproved. |
| WP04 local trip, UI and observed knowledge | Partial | A no-transfer Riverside run walked the actual team about 87 tiles out and back, shifted slot 1's footprint off the player-owned start, then released the second view beside the player. An autonomous scout accepts a bounded destination and returns to its saved rally (`171240`); run `173950` retained a bounded exterior observation. An autonomous local Search mission (`182810`) took one requested native construction item and returned with an internal exact-item debrief. A bounded place query (`192948`) found native police, fire and gas buildings and excluded a basement-only footprint from surface approach. A player-seen interior projection (`195536`) showed 15 of 27 metadata candidates and classified them only from seen rooms, without raw room names. An actual three-member quiet Scout trip (`195658`) selected the fire station from that known-place list, observed six visible squares, returned to the player and released slot 1. The new sandbox destination-scope option defaults to all nearby; a cloned-save run (`200519`) offered 22 ground-floor map-derived targets versus 15 with known-only, with both lists omitting raw room names. Run `140149` operated the actual Expeditions tab through squad, leader, destination, review and launch, then used the first right-click radio option to turn the mission inbound. Broader knowledge sources, interior entrance check, radio-delivered reports, accessible full planner controls, and natural-danger place trip remain unproved. |
| WP05 remote execution | Partial | A quiet, no-transfer Riverside probe walked the actual leader and two followers about 87 tiles out and back, shifted slot 1's map across several boundaries, then released the view beside the player. An autonomous scout (`173950`) chose and retraced local legs, observed nine visible exterior squares about 82.75 tiles east, and returned with the recorded result. A targeted local cupboard trip (`175330`) obeyed an explicit construction-supply category. Autonomous local Search trips (`182810`, `183706`) accepted a one-item request, chose a native cupboard inside a bounded two-tile site, verified the exact source debit, returned with that same item, and released slot 1. Search deadline and schema-4 restart cases passed in the focused Kahlua harness. A controlled active-cargo reload (`184941` to `190015`/`190158`) carried the same exact item home twice in independent clones after a consecutive-stall fix. Persisted no-useful visits, multiple categories, natural-danger travel, and county-scale road planning remain open. |
| WP06 recovery and conservation | Partial; cleanup and transaction gates remain open | Automatic remote restart restored the exact team, leader view and outfit in two cloned runs; a persisted slot ID avoided another row. Controlled native-row-first and LF-newer checkpoints both recovered without another row. Joined return now persists an idle slot ID that a later mission reused both in-session and after reload. One controlled active Search checkpoint restored a requested cargo item and returned it home in two cloned replays. Older ghost rows remain in previous experimental saves; mixed-save crashes with cargo, command deduplication, cancellation and disable cases remain untested. |
| WP07 incidents and rescue | Partial | Two successive native companion deaths moved slot 1 to the next original team member; a separate cloned run killed all three mission members and restored the primary view. Unscripted distress and rescue are unproved. |
| WP08 release validation | NOT RUN | Test build stays private and disabled outside cloned-save harness. |
| M01–M16 mission matrix | Partial | M07 local formation/combat decisions and M13 one death handoff have direct evidence. All other mission gates, and full M07/M13 acceptance, remain open. |

The later map-derived destination probe adds WP04 and W03 evidence without
closing either gate. In `SC-Harness-20260927-201116-b31ad2dc`, the original
three-member team walked from the Riverside player to the exterior of a
building absent from the player's seen-interior list, observed five visible
squares, returned without setup transfer, and released slot 1. The same route
passed with the quiet zombie fixture off in
`SC-Harness-20260927-201548-cbd0382a`, observing six squares. The team did
not enter the building or demonstrate a natural zombie encounter on this
route; a previously unvisited **interior** and W03's full moving-area proof
remain open.
| R01–R29 radio matrix | Partial | Genuine walkies, frequency-gated signal and scoped native text passed. One received command changed leader mode; ordinary direct orders and mistuned/off/muted receive attempts stayed blocked. Placed devices received natively at 512 tiles, a 2,047-tile HAM transmission had no field-radio return, and both exact placed item/proxy pairs stayed functional across an ordinary reload. The game's timed placement actions produced exact walkie/HAM pairs that survived reload; a native timed grab moved the exact placed walkie into inventory and removed its proxy after a disposable capacity override for the overloaded saved player. Run `140149` verified player and leader walkies equipped in top-level inventory and received a native return acknowledgement from the actual leader at 8.01 tiles; a core harness rejects packed radios even with stale hand references. Longer-range Return immediately, player controls, 3D cursor input, radio destruction, and most protocol scenarios remain untested. |
| UI/lifecycle/showcase | Partial | The visible second view is captured. Run `140149` rendered the actual Expeditions tab, reviewed and launched the selected squad and destination, and used the radio context option to begin return. Full planner control coverage and the clinic showcase remain open. |

## Evidence and next dependency

An unvisited-building interior Search from the original Riverside team is
still open. In cloned run `SC-Harness-20260927-205832-6d2439d8`, the actual
leader walked from `(6085.5,5308.5)` to the previously unknown `post`
building and two saved followers remained nearby. With the entire target
footprint loaded, a read-only native object survey found **zero barricades**
among 33 doors and 18 windows. A direct path query from the exterior found a
21-node route to the free interior search tile `(6165,5253)`, yet the leader
repeated exterior legs around the west and south sides and timed out in the
outbound phase without entering a room or acquiring cargo. The waypoint
planner repeatedly reported `planning`; the test has not established which
portal or route operation prevents entry. The screenshot at
`build/live-sandbox-runs/SC-Harness-20260927-205832-6d2439d8/near-entrance-circling.png`
shows the two local views during the loop. This is a failed interior-entry
gate, not evidence of a successful Search. A separate clone
`SC-Harness-20260927-204304-b531fd0f` held for minutes 65 tiles before the
same building on a 12-tile straggler gap; that earlier pause cannot have been
caused by a barricade at the target. The source save was not modified and the
launcher was restored after each run.

Native radio evidence is at
`build/live-sandbox-runs/SC-Harness-20260927-022407-10d064f3/cache/Lua/SurvivorCompanionHarness/events.log`
(59 pass, 0 fail, 2 skip). The radio screenshot is
`build/team-working-radios-current.png`. The separate native
survival run is at
`build/live-sandbox-runs/SC-Harness-20260927-010820-0cfeb896/`.
The five-radio Riverside kit and full reload are recorded at
`build/live-sandbox-runs/SC-Harness-20260927-025846-5163cfdd/` and
`build/live-sandbox-runs/SC-Harness-20260927-030001-2e2cf655/`.
All five native devices retained their battery, charge, 90000 channel,
`Living Fellows Team` preset and equipped state after reload. This required
capturing and restoring radio `DeviceData` in the existing companion item
snapshot. The original save remains untouched.
An isolated interactive playtest launcher now prepares a fresh copy from
the verified five-radio reload save and points the client at the private
payload only while that client is running. Its prepare-only and main-menu
smoke checks passed; the new copy has not had a separate in-game load test.
See `scripts/Start-ExpeditionRadioPlaytest.ps1` and the native radio probe.
The same kit and reload passed again with the original save's four mod entries
in cloned runs `SC-Harness-20260927-033535-25734d5a` and
`SC-Harness-20260927-033651-3d280e28`; command delivery with those extra
mods has not been tested.
The radio command runs are at
`build/live-sandbox-runs/SC-Harness-20260927-032505-d675de57/` (67 pass, 0
fail, 2 skip) and `build/live-sandbox-runs/SC-Harness-20260927-033203-763363f9/`
(68 pass, 0 fail, 2 skip, including command receipt on the successor after
death handoff). The full-mod command run
`build/live-sandbox-runs/SC-Harness-20260927-034628-3bd9b0c4/` passed 74,
failed 0 and skipped 2. It verified player off, retuned, microphone muted,
flat and unequipped cases, plus immediate leader unequip. A native
`getEquipedRadio()` cache lag found by the first run was fixed with a current
slot check. Next, expose a player-controlled command path and verify range
boundaries. Continuous boundary crossing under natural danger and exact item
conservation over a long route still block promotion from this test-only prototype.

## No-transfer route update

`SC-Harness-20260927-161216-c4b6e22c` passed a controlled long walk from
the Riverside gas-station save without a setup transfer. The saved leader in
slot 1 and two original followers moved about 87 tiles east while the player
stayed in slot 0. Slot 1's 152-tile footprint shifted from minimum x6008 to
x6096, releasing the player-owned start from its own map. It then shifted back
to x6008 while the far square unloaded. The followers remained loaded and
nearby; a final 13-node walk ended 2.35 tiles from the player and
`finishAtPlayer` released slot 1. The maximum observed leader step was 0.114
tiles. The harness removed nearby zombies during this specific run to isolate
movement and streaming. Natural combat interrupted an unquiet exterior-route
attempt (`160303`), so continuous travel with live threat remains partial.

The route probe now passes the actual actor to path searches, allowing the
same ordinary inside-unlock rule that native traversal uses. It also favors
exterior waypoints for travel. A locked door discovered by a follower clears
its stale leader-trail route, and mission travel gets a bounded search for an
alternate entrance before accepting room-level lock memory. Cohesion holds
ask lagging followers to regroup beside the stationary leader, avoiding a
deadlock at an older breadcrumb. These are prototype route and formation
changes; the road-scale itinerary and several v5 gates remain open. Full
evidence and failed precursor runs are in
`docs/expedition-moving-area-probe-2026-09-27.md`.

## Previously unvisited building Search

The no-transfer Search in cloned run `SC-Harness-20260927-212857-f63e95c4`
entered the previously unvisited `post` building with the actual saved leader
in slot 1 and two saved followers. The 805 loaded footprint squares contained
33 doors, 18 windows, and no barricades. Search considered two native sources,
then its deadline sent the team inbound. Steve stayed beside a locked interior
door he could unlock while the container approach exhausted its path budget.
He also selected a seat when that approach timed out. The leader escaped the
building after the indoor inbound route fix, but the team remained on a
straggler hold as a follower's return route repeatedly failed.

In `SC-Harness-20260927-214058-22ec9871`, the leader smashed and cleared
window `(6156,5251)` without climbing it, then replanned to `(6156,5248)`,
smashed and cleared that window, and climbed through. Native glass removal
ran a `Loot` / `Mid` timed visual action before the glass effect was verified;
the trace shows both the active visual and the later native postcondition.
Search considered four native sources, and Steve later unlocked an interior
door from the inside and walked beyond it. He also logged two `unknown`
movement recoveries while aiming near another interior door, then recovered.
No requested cargo was found. The inbound leg again stopped at a 12-tile
straggler gap while both followers' indoor routes kept searching; the run
timed out, with no completion or debrief claim. The screenshot is
`build/live-sandbox-runs/SC-Harness-20260927-214058-22ec9871/door-return-hold.png`.

The next private build retained an active window traversal through the scout
stall interval, suppressed voluntary seating during Search, and gave held
followers short verified regroup legs. Its full core and installer suites
passed. The live rerun `SC-Harness-20260927-215129-6f1d00ff` entered the
unvisited building, considered five native sources, and returned the actual
leader and two saved followers to the player. The Search deadline ended with
zero acquired and returned items because no requested supply was available;
the inventory reconciliation passed. The leader crossed 18 loaded chunks,
with a maximum sampled step of 0.293 tiles. This is a complete no-transfer
building Search and return, but not evidence of requested cargo retrieval.
It still smashed and cleared first window `(6156,5251)` without entering;
the leader entered through a second window `(6156,5248)`. The first-window
route choice and `unknown` movement blockers remain open.

After that successful run, the user observed stepwise scavenging movement and
rapid flashing of the numbered slot-1 weapons bar. The current build removes
Search-specific and regroup-specific short movement legs. Both now submit
their destinations to `SCNavigation`, which establishes an optional full
verified route and owns the normal movement, portal, and recovery sequence.
The AI hotbar is removed from the UI manager when slot 1 is active. Core and
installer gates passed after this refactor. Hidden-window run `221040`
confirmed the slot-1 hotbar was created, invisible and absent from the UI
manager. It entered the building and returned the leader to the player, but
timed out at `awaiting_player` before the followers assembled. During Search,
it repeatedly reported `unknown` recovery with `PlayerAimState` and no native
collision beside the interior door. The `222208` hidden run entered through
the first cleared exterior window and returned the whole team, but room-entry
sweeps still interrupted the indoor Search with `PlayerAimState` and repeated
unknown recovery. Nearby ground-item counts at its sampled corridor tile were
zero; the Garbage inventory screenshot does not establish a collision cause.

Navigation now lowers the weapon before a quiet continuous approach and skips
its stop-and-sweep room and blind-corner phases while that approach owns travel.
The `223058` hidden cloned-save run entered through the first cleared window,
approached multiple native sources without that Search room-entry loop, and
returned the actual leader and followers. It selected one Dental Floss item,
verified a native source count of 1 to 0, and returned exactly that item. The
leader crossed 17 loaded chunks, with maximum sampled step 0.180 tiles. This
is the first full unvisited-building Search that returned verified cargo. The
user confirmed door movement looked correct in the second view but reported
that scavenging still looked choppy, and that the leader broke two windows
before later using a door. A global window-cost increase in hidden run
`224057` made the scout stall at the exterior entry and fail its bounded
replan limit. An interior-only cost increase in `224641` also failed: Steve
cleared two exterior windows, changed route before climbing, and reached the
same replan limit. Both cost changes were reverted to the last complete-run
route policy. The half-second Search motion trace remains ready for the next
run. The source world remains unchanged and the launcher configuration was
restored after completed runs.

The leader-only `225807` trace isolated the remaining Search cadence fault.
Across actual container approaches, status kept `decision=scavenge/moving`
and the same verified route while the native actor alternated between
`PlayerMovementState` and `IdleState`, sometimes with zero movement for a
half-second sample. Scavenge selection was gated at 1000 ms, but direct native
movement input expires after 250 ms. The private build now retains the selected
Scavenge goal in Navigation and renews the same request on the 100 ms movement
beat; item discovery and transfer remain on the work cadence. Its core suite
passed 47/47, installer passed 35/35, and gameplay static passed 910 assertions.
The first live rerun, `230851`, failed during scout entry before reaching
Scavenge: after clearing exterior windows, it ended at
`scout_stall_replan_limit`. It is not movement-fix verification. The launcher
was restored. The second rerun, `231242`, reproduced the same exterior stall.
Its trace showed the actual cause: a completed window smash or glass removal
did not reset Navigation's movement-progress clock. The actor was classified
as stuck immediately after finishing the portal action, so the scout changed
to another window. Completed effect-only traversal now resets route progress;
the next request keeps the prepared edge and climbs it.

The leader-only `231744` rerun passed. Steve smashed and cleared exterior
window `(6156,5251)`, climbed that same first window, searched the actual
previously unvisited interior, selected one `Base.DentalFloss`, verified its
native source count changed from 1 to 0, and returned exactly one item to the
player. The route crossed 17 loaded chunks with maximum sampled step 0.1803
tiles. Among half-second samples on ordinary direct Scavenge route edges,
`225807` had 38 zero-distance samples of 157; `231744` had zero of 28. One
idle sample coincided with a native door/path handoff and still moved 0.875
tiles during that half-second. This verifies the cadence fix in the actual
slot-1 leader view, not merely in a Lua fixture. The launcher was restored.

A code audit found analogous timing exposure in other approaches: Logistics
750 ms, infection crisis 500 ms, and base work, needs, and faction 250 ms
against the 250 ms native input lifetime. Curtain approaches can run on the
1500 ms downtime selector. Active supervised downtime activities are polled
on the ordinary decision beat, while follow, tactical, and combat use 167 ms
or faster selection. Navigation now retains and renews the selected approach
on ordinary fast decision beats for the exposed actions, with gameplay checks
for the retained kinds, owner change, and arrival. Each individual action's
approach still needs a live visual check before its case can be closed.

An earlier full-team recheck `232434` did not reach the building. Steve and one
follower progressed, but the other follower stopped at `(6147.955,5267.586)`
after an engine path failed on a vegetation edge. The status continued to say
`native_path/.../follow/moving` toward `(6153,5256)` while the coordinates
remained unchanged across multiple progress logs. The leader held at the
11.36-tile straggler gap. The isolated client was stopped and the original
launcher restored. This is a separate follow/native path lease issue; it does
not negate the leader-only Scavenge movement proof, and it prevents a claim of
final team verification on that build. A later quiet four-member run
`20260928-001825-93d92ed5` entered the previously unvisited office, took
one exact native item, and returned the leader plus three followers. The
vegetation failure still needs a natural-danger recheck.

## Split-screen labels, departure speech, and current gates

The private UI renderer now projects each recruited companion's first name
through the explicit local-player camera, clips it to that view's rectangle,
and omits the viewer's own name. The UI fixture covers both local views, a
companion leader in slot 1, and a projected label outside slot 0's viewport.
Successful new mission starts select one of 20 distinct departure lines through
the existing dialogue owner; restore does not replay it. The `SC-Harness-
20260927-234118-cde4897a` cloned-save run captured the actual leader saying
"Gather up, people. We're heading out." in `build/split-screen-nameplate-
departure-20260927.png`. The three companion names appeared beside their
characters in both views. The right-hand companion panel overlapped part of
that view, so this is a positional smoke check rather than UI layout approval.
That run also passed an 11-node local outbound route, an 11-node return, close
followers at arrival, and joined-view release beside the original player. The
save source was untouched and the original launcher hash restored.

The gameplay suite now passes after its room-entry fixture released the first
actor before testing a second at the same tile, its optional native traversal
stub was supplied, and its Scavenge assertion checked the current continuous
movement contract. The UI suite passed (including 85 Python contract tests),
core passed 47/47 harnesses, installer passed 35/35 cases, and gameplay static
passed 910 assertions. These checks do not close the v5 mission/radio matrix;
the W03 full-team distant route and most UI, radio, recovery, and release gates
remain open above.

## W09 native population scale follow-up

The cloned base-scene harness now supports exact 4, 8, and 16 native actor
populations. It spawned four or twelve additional recruited `IsoCompanion`
actors for the larger fixtures, kept all actors alive through a 30-second
sample, and checked the original player remained in slot 0 with slot 1 unused.
The first 16-member pilot (`062021`) failed UI cadence at 14 refreshes and a
2,152 ms longest gap. The next (`062729`) improved to 22 refreshes and a
1,370 ms gap but still failed the 30-refresh minimum. The UI scheduler now
promotes a due 50 ms slice after 1 ms overdue; the subsequent 16-member run
`SC-Harness-20260928-063849-8dd4a8b4` passed with 30 refreshes and a 1,034 ms
longest gap. Same-build 8-member (`064047`) and 4-member (`064445`) runs also
passed. Their whole-mod p95 values were 7.901, 6.493, and 6.478 ms,
respectively, so the 2 ms target is still missed. The full 9/9 project gate
passed after the harness and initial UI scheduling changes; the final 1 ms
schedule also passed live with 4/8/16. The source save was untouched and the
launcher restored after each run. See `docs/frame-timing-review-2026-09-28.md`
for render, CPU, memory, and sample limitations.

The two-view W09 fixture was then extended to 8 and 16 total native
companions while retaining the four saved expedition members together in
slot 1's remote area; the added actors stayed independent near the player.
`SC-Harness-20260928-070354-af9b12eb` (8) and
`SC-Harness-20260928-070621-3212e61f` (16) passed exact start/end living
counts, second-view ownership, remote follower checks, and UI cadence. Their
whole-mod recent p95 values were 21.468 and 11.654 ms. A repeated 8-member
run (`071327`) failed its living-roster gate when an original follower died
from native wounds and terminal Knox infection; its measured p95 was 10.689
ms. The large p95 spread prevents a population-only cost inference. A
current-build 4-member remote run (`065542`) and a separate remote plus local
player encounter (`065941`, 12 native hits) both passed, with recent whole-mod
p95 values 11.306 and 9.076 ms. The user-approved 2 ms figure remains an
unmet shared-overhead target. None of these fixed-site transfers proves a
long route, an 8/16-member squad, or a release FPS limit.

## All-dead native corpse cleanup recheck

The repeated 8-member performance run exposed a separate death cleanup
failure. `SCRuntime.vitalsTask` skipped an inactive record after the first
`SC.Actor.retireDead` attempt, even though native corpse creation was still
pending. The vitals lane now revisits that exact dying record until the
provider verifies cleanup; a focused Kahlua regression covers the retry.

An all-dead cloned-save check (`SC-Harness-20260928-074048-f2a514a7`)
then showed a second boundary: the mission unloaded slot 1 when all three
actors reported dead, before any of their corpses were ready. After 30
seconds, zero of three corpses were ready and bridge ownership still had
three pending actor cleanups. The expedition now keeps the remote map and
view loaded until each roster survivor's native corpse callback completes.

The same all-dead fixture, run as `SC-Harness-20260928-082005-2bd272ca`,
passed 49 checks with zero failures and two expected skips. All three native
corpses became ready, pending actor cleanups reached zero, stock slot-1 UI
was removed, slot 1 and its chunks released, and the primary Riverside view
remained live. The test also retained the slot SQL identity for reuse. The
full project gate passed 9/9 after the fix. Both live runs used disposable
save clones; the launcher was restored and the source save was untouched.

A follow-up destructive clone (`SC-Harness-20260928-083710-ffa8d954`)
passed the narrower W07 corpse-and-possessions check. For each of the three
original mission members, the exact `IsoDeadBody` returned by the game's
death listener held the actor's pre-death native inventory container, the
actor had received a different container, and the corpse's worn-items list
retained its pre-death count and an exact pre-death clothing object. All three
corpse callbacks and zero pending bridge cleanups also passed. The project
gate passed 9/9 before the run; the original `players.db` hash remained
`4A40E904F5262EE9FDB427EC2C13C1397D564E4D30F11ABB69AB5D35C293F3DE`.
This proves the immediate native handoff of inventory and worn gear. A later
reload probe below covers the native corpse-to-zombie lifecycle and one exact
worn item per companion. Dropped hand-item preservation remains untested.

The first destructive reload fixture (`084516`, repeated `084802`) found that
all three corpses disappeared after slot-1 chunk unload. The game's chunk-map
code clears static bodies before queuing its save. At the native death callback,
each corpse was on its square; after unload, none remained there. The bridge
now snapshots only corpse-bearing native chunks before unload, drains those
chunks' queued post-unload saves, and restores the pre-unload bytes. Staging
run `SC-Harness-20260928-090120-0c26e572` passed the all-dead cleanup and
native corpse/gear checks; the saved corpse chunk held all three test-only
worn-item markers. On a clone of that staged save, reload run
`SC-Harness-20260928-090826-3b4d078b` loaded the remote site and found one
reanimated native zombie carrying the exact marked clothing item for each of
the three companions (12 pass, 0 fail). The bodies had followed the game's
reanimation lifecycle before the observer arrived. This proves persistence
of those three native outcomes and worn items through unload and reload. It
does not yet prove the rest of each inventory or dropped hand items after
reload, and it is one destructive fixture rather than a long-route death test.
The full project gate passed 9/9 after the fix. Both runs used disposable
save clones, and the launcher returned to its original hash.

A second stage/reload pair extended the possession check. In disposable
stage `SC-Harness-20260928-091359-a02b038a`, the fixture added and marked
one native `Base.Bandage` in each companion inventory before fatal injury.
Each exact item object was found in its native corpse inventory before view
release. Reload `SC-Harness-20260928-091521-b7f0f10b` found exactly one
marked bandage in each of the three reanimated zombies' inventories, along
with their tagged worn clothing (13 pass, 0 fail). This proves one ordinary
carried item survives the complete native death/unload/reload/reanimation
path per actor. Other inventory types, nested containers, and dropped hand
items still need their own tests. Both runs restored the launcher and left
the original save untouched. The full project gate passed 9/9 after the
fixture change.

The stronger native-ID recheck used stage `SC-Harness-20260928-091758-30269c6f`
and reload `SC-Harness-20260928-091919-458825a6`. Each reanimated zombie
carried exactly one marked `Base.Bandage` whose post-reload native item ID
matched the ID recorded on that exact item before death (13 pass, 0 fail).
The full project gate again passed 9/9, and the original `players.db` and
installed launcher hashes remained unchanged.

## Follower death during ordinary remote chunk streaming

A new W07 clone test killed one mission follower while the leader and two
survivors continued on an ordinary waypoint route. The immediate native
`IsoDeadBody` contained the exact test-only `Base.Bandage` and its native ID.
In baseline run `SC-Harness-20260928-093822-95555546`, the leader walked
about 102 tiles and slot 1 released the death site. A test-only slot-0
visitor then loaded that site and found neither the marked corpse nor its
reanimated zombie, and zero marked bandages. The earlier all-dead save fix
does not cover ordinary map shifts. The installed game's chunk-shift path
calls `removeFromWorld` before queuing `ChunkSaveWorker.Add`, clearing the
corpse from the square before its save. There is no installed Lua unload
event at that boundary.

The bridge now retains at most eight corpse-bearing native chunks with a
separate chunk-map reference while the expedition runs. It releases that
reference at view teardown, saving native chunk bytes immediately before
the engine clears the last reference. The first retention run (`095001`)
exposed a lifecycle bug in the repeated staging check: once the corpse
reanimated, its detached square made the check fail and stopped movement.
The check now recognizes an already retained actor. In `095354`, the real
leader and two surviving followers walked 103.47 tiles while slot 1 moved
past the death site. The test-only visitor found exactly one native outcome
with the exact marked bandage (`outcomes=1`, `exact_cargo=1`). One generic
harness assertion still failed because ordinary `cell:getGridSquare` is nil
outside both player views even while a chunk remains retained; that assertion
was corrected. The clean rerun `SC-Harness-20260928-095821-0e8d5f05`
passed every live check after a 103.48-tile native walk: slot 1 no longer
covered the death site, and a slot-0 visitor found exactly one native outcome
and the exact marked bandage. The full project gate passed 9/9 afterward,
the launcher and original `players.db` retained their baseline hashes, and
the game process exited. This proved the in-process visitor case in two
clones. A later restart probe found the exact marked bandage but no marked
worn item. The fixture had tagged a visual `Bandage_Abdomen` that the actor
did not actually own in inventory. Native `IsoDeadBody` serializes worn
slots as indices into its saved inventory, so that unowned visual does not
reload as a worn item. The fixture now selects and checks an inventory-owned
worn item before death and checks that same object in the native corpse
container. This avoids manufacturing a loot item from an unowned visual.

With the corrected fixture, staged run
`SC-Harness-20260928-103305-adaac136` passed the full 103.85-tile native
route. The corpse site at `(6597,5305,0)` was outside slot 1's view, and the
slot-0 visitor found one native outcome with the exact marked bandage and
marked worn item. A fresh game process loaded a clone of that staged save in
`SC-Harness-20260928-103821-1181ec99`; its visitor found one native body,
one marked worn item, and one marked `Base.Bandage` with the pre-death native
item ID (`outcomes=1`, `exact_cargo=1`). The saved native chunk contained
both marker strings. The bridge retains no more than eight corpse chunks,
writes their native snapshots at the game save boundary, and releases a
chunk after its final live view goes away. This proves this one-follower
ordinary route and clean process restart. Crash recovery, broader inventory
types, multiple death sites, and longer-term memory cost remain untested.
After this probe, `Test-Project.ps1` passed all 9 stages, `git diff --check`
found no whitespace errors, no Project Zomboid process remained, and the
original save `players.db` and installed launcher kept their baseline hashes.

## 2026-09-28 return-route and timing decision

An additional quiet four-member outbound run (`111253`) moved the leader about
104 tiles east and shifted slot 1's loaded map; the westward return stalled
near a vegetation edge. A game screenshot and actor/path telemetry were saved.
A resume from that cloned far-end checkpoint (`113815`) completed four 20-tile
westward legs with the followers within 12 tiles, then made only a few tiles of
progress across repeated final waypoints and failed its bounded-leg check.
Navigation now detects recent direct requests with no net actor translation,
including provider acknowledgements of `path_started`. The focused navigation
suite passed 965 checks and the full project gate passed 9/9. The broadened
guard has no completed live return verdict; W03 stays partial.

For W09, 12 ms p95 whole-mod tick is the provisional split-view review
threshold. The old 2 ms whole-mod acceptance target is retired because even
the quiet four-member pilot measured 6.478 ms p95. The runtime 2 ms scheduler
admission value remains unchanged; changing it also changes adaptive AI load
and requires a targeted comparison. The 12 ms review threshold is not a W09
release pass: the two-view eight-member pilot reached 21.468 ms p95, and
long-route responsiveness and cleanup cost remain open. The original save and
installed launcher retained their baseline hashes after this work.

## Timed turn-home rule in the private trip prototype

Scout and Search now accept `turnHomeAfterHours` (0.25-24 in-game hours) at
departure. The mission stores its absolute world-hour cutoff, including across
save/restart. When the cutoff arrives during outbound travel, observation or
search, it clears the outbound waypoint and starts the ordinary inbound route.
An early Scout debrief has no invented site observation; an early Search debrief
has no invented acquisition. Existing untimed trips and saved itineraries still
load. The expedition restart Kahlua harness passed in the 47/47 core suite.
This is a **turn-home time**, not a promise of arrival by that hour. A travel
reserve estimate and player-facing time selector remain WP04 work; the new
rule has not yet had a dedicated live-game run.

The prototype also accepts an absolute `arriveByHour` for Scout or Search.
During outbound travel, observation and search it estimates the reverse route
from reached trail waypoints, actual leader position and elapsed in-game time.
It turns home when the time remaining reaches the estimated trip back plus a
margin. Before enough movement has been observed, it uses a conservative
fallback; all estimates keep at least 0.25 in-game hours. The absolute due time,
departure time and return decision survive save/restart. Core tests cover an
early Scout return and a Search that turns around before opening any container;
both debriefs retain only observed or acquired facts. This improves the
player-selected arrival goal but cannot guarantee punctuality when danger,
new obstacles or follower delays change the route. The player-facing selector
and live-game timing evidence remain open.

The deadline estimate runs at most once per real second while the trip is
outbound or at its site, so route measurement is not added to every frame.

## Selected building to mission seam

The private mission prototype can list the current `SCExpeditionPlaces`
destination choices without assigning an actor or changing world state.
`startAtPlace` re-queries the selected sandbox knowledge policy by footprint ID
and verifies a loaded exterior approach from the chosen leader immediately
before mission admission. A stale candidate, a place removed by Known only,
or a failed exterior path leaves the team unassigned. A successful Scout or
Search stores the selected place label, street and knowledge qualifier in its
mission descriptor and debrief. The core restart suite covers draft purity,
policy changes, failed approach, start, save/reload and debrief; 47/47 core
harnesses passed. This does not prove an open entrance or accessible interior
loot, and no player-facing planner has been enabled.
