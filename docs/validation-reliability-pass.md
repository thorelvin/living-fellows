<!-- SPDX-License-Identifier: MIT -->

# Expedition and camp reliability pass

Reliability work on `living_fellows/0.26.98`, based on `ff2378ff`.
The installed mod and original saves have not changed. Work now includes a
rebuilt source bridge with the existing protocol. All live runs use
disposable clones, a 30 FPS cap, a 3 GB Java heap and BelowNormal priority.
Live timing samples and automated checks run separately.

Current acceptance: all three parts have verified outcomes: the complete wood
drive and kitchen return, the clean four-worker camp measurement, and packing UI.
The final project gate passes. The evidence and limits below distinguish the
complete trip from earlier failed attempts and later reload observations.

## Completed trip and return review

`SC-Harness-20261105-060957-70443979` exited 0 with `LIVE_SANDBOX_PASS`.
Original saved Scarlet and car46 completed ordinary preparation, boarding,
driving, native chopping, physical log pickup, trunk loading, parking and
delivery. One mature native tree was removed and four raw log drops were
observed; only the two requested logs were collected. Both original item IDs
were observed physically in the trunk and then verified in permitted `zone:18`
storage:

- `lf-item:1793855959900:1:827662174`
- `lf-item:1793855959900:2:1516369436`

The borrowed axe was returned, the original crew member remained at 100% health,
the engine was off, secondary slot 1 was empty and ViewSession had no owner.
The complete trip took 1,080 seconds. Tool-return navigation was slow; this is
a successful bounded delivery result, not a claim that all routing delays are
fixed. The explicit work-site fixture removed 19 zombies around the forest
sites; road traffic and obstacles remained active. This is not combat acceptance.

After delivery, the same primary player walked normally into the actual kitchen
at `12035.5,6746.5,0`. Native screenshots at frames 2, 12, 120 and settled were
visually reviewed: the south wall is cut away and the player remains visible.
Scarlet's overhead name is visible in frames 2 and 12 and in the post-solo
capture. No player teleport, camera, wall-cache or alpha correction was used.

The black parked pickup car5 is visibly rendered before and after solo return,
with the same primary pose and identical recorded car coordinates
`12032.8671875,6754.3984375,0`. Both cars have alpha/targetAlpha 1 and rendering
enabled immediately after solo return. The stricter continuous stationary
comparison was SKIP because its historical motion flag was set; its cause was
not logged, so no continuous-stationarity automated pass is claimed. Manual
before/after visibility review is the evidence for the parked pickup.

Final-source reload observation `SC-Harness-20261105-063807-1258c8fc` exited 0.
The player walked normally to the garage frontage, both saved cars stayed at
their initial observation positions for 30 seconds, with engines off,
alpha/targetAlpha 1 and rendering enabled. Its PNG visibly shows the pickup;
the expedition car is behind the garage wall. This supports persistence and
normal occlusion, and does not replace the direct-return screenshots. The
preceding photo-only run `063538-fc09b723` failed on an incorrect diagnostic
method name; it is excluded from acceptance and no production code was affected.

A separate arbitration defect explained the earlier sit-related delivery stall:
owned casual sit/read could prevent a ready delivery reaching decision selection.
Ready cargo now cancels only those casual pauses and returns to ordinary scored
selection. Sleep, cleaning transfers and rollback obligations retain ownership.
The compact regression fails on the retained pre-fix Decision source and passes
on current source, including sleep/cleaning protection and subsequent delivery
selection. The full native trip preceded this final Lua correction; the final
five-check gate and the reload observation use the correction.

## Camp CPU measurements

Rosewood firestation: 24 marked containers across two floors, four local recruited
actors plus surviving original actors, normal decisions and surrounding
zombies. Each mode runs for 45 seconds, excluding eight seconds of warmup.
Per-system percentiles cover the latest 120 samples; maxima cover the phase.

Baseline: `build/live-sandbox-runs/SC-Harness-20261105-002935-c2fc2bbe`.
The Base phase recorded base-maintenance p95 115.33 ms, maximum 116.70 ms.
The sorting selector traversed every marked source in one callback.

After bounded sorting: `build/live-sandbox-runs/SC-Harness-20261105-004737-202cc44b`.
All four probe phases completed. Sorting selection p95 was 1.03–1.17 ms;
maximum 5.04 ms. Both closed phases made zero building-discovery calls.
Closed computer-service callbacks stayed below 0.03 ms maximum.
Other base-work and decision spikes remain, so this does not establish that
all sources of camp stutter are fixed. The world behind the camp UI rendered
black in the native captures; render-gap figures do not prove normal-world FPS.

Current-source repeat `SC-Harness-20261105-044655-941da112` completed all four
45-second phases at noon. Sorting p95 was 1.045/1.127/1.056/0.974 ms and maximum
2.259 ms across closed/Base/EMMA/closed. Computer-service maxima were
0.022/0.019/0.106/0.017 ms; both closed phases again made zero discovery calls.
The main-world captures remained black, so the noon adjustment did not resolve
the visual fixture issue. These are CPU results only, not normal-world FPS
acceptance; observer and camera inspection remains required.

Read-only observer inspection `SC-Harness-20261105-045307-b8e925d8` found the
observer awake, alpha/targetAlpha 1, and all singleton, camera and render-frame
ownership checks on primary slot 0. The fresh-seed comparison
`SC-Harness-20261105-045711-0ee68062` rendered the original camp normally, then
became black after the observer-only teleport to Rosewood. Slot 0, current
square, canSee/couldSee/seen and primary camera ownership remained correct.
No companion view was opened. This isolates the failure to the teleported
scene, but its rendering cause remains unresolved. No forced visibility or
camera reset was applied to make a performance capture pass.

Lighting comparison `SC-Harness-20261105-053403-09bdda95` found normal primary
player state and sight at all three locations, but native light level was 0.898
at the original camp, 0 inside the station, and 1 outside. The exterior PNG
renders the native player and parking apron. Ordinary native player walking
in `SC-Harness-20261105-053805-fa6592f8` completed without changing the interior's
zero lighting; the room was already explored. A native generator/switch fixture
was checked before changing the benchmark setup. In
`SC-Harness-20261105-054236-5fb8931e`, a real outdoor generator and the native
room switch raised light from 0 to 0.898 at the unchanged observer position.
The powered PNG renders the room and player normally. This identifies the
black fixture as an unpowered interior, rather than a lost camera. No renderer
override was used. The revised camp run `SC-Harness-20261105-054709-4b43b56d`
uses that native power setup, normal switches, and a clear observer tile in the
largest retained ground-floor room. It completed with visible world captures,
but its roster exposed extra fixture companions retained from earlier clones,
so it is not the final four-worker comparison. Fixture reuse now checks saved
registry identities, waits for deferred actor restoration and rejects excess
test workers. Clean-seed verification
`SC-Harness-20261105-055717-0db86e3d` completed all four phases, with four local
workers and the original companions retained far away. Native captures show the
powered world, Base and EMMA. Normal decisions, surrounding zombies and alerts
remained active. The performance report now always includes base maintenance.

| Phase | Render gap median / p95 / max (ms) | Base maintenance p95 / max (ms) | Computer-service max (ms) |
| --- | --- | --- | --- |
| Closed | 33 / 41 / 53 | 1.471 / 22.687 | 0.022 |
| Base | 33 / 41 / 64 | 1.172 / 2.126 | 0.018 |
| EMMA | 33 / 42 / 68 | 1.267 / 1.732 | 0.328 |
| Closed again | 33 / 42 / 58 | 1.238 / 2.672 | 0.022 |

Both closed phases made zero building-discovery calls. The sorting selector's
p95 was 1.098/1.194/1.108 ms in Base/EMMA/closed-again; maximum 2.606 ms. Base
maintenance's earlier Base-phase p95 was 115.33 ms, versus 1.172 ms in this
clean powered fixture. This is a short sequential measurement at a 30 FPS cap,
not a general FPS guarantee: NPC behaviour changes between phases, the old
capture was unpowered, and other AI/rendering spikes remain. In particular,
first-phase base maintenance still peaked at 22.687 ms.

## Driving and preparation

The real blocked-connector run `SC-Harness-20261105-000748-d335c231`
verified an alternate road entry, completed packing and boarded the saved car.
It then abandoned the car with `route_blocked`. Both driveway endpoints now
use width 5: the native follower uses the wider endpoint, and the previous
wide road endpoint incorrectly applied a street lane offset to the driveway.
The next run, `SC-Harness-20261105-005237-3be72b91`, passed that driveway,
reached the forest, stopped its engine, skipped two sites without mature trees
and felled a native tree at the third. Four native logs dropped; the first was
physically picked up and loaded into the trunk. The trip then stalled and
failed its 1,000-second deadline. This is a failed full-trip acceptance.

The unchanged-save observation `SC-Harness-20261105-011111-c709d3be` confirmed
the worker's reason was `wood_ground_unloaded`. Ground-log discovery returned
without scheduling movement after the stump's grid squares unloaded during a
trunk shuttle. The worker now uses the existing bounded scout waypoint planner
to approach that recorded source, then revalidates the exact log before pickup.
The pending receipt and ground item remain unchanged during travel.
`SC-Harness-20261105-011527-141d8351` resumed that same stalled save with the
correction: native navigation reached the log source, a second cargo shuttle
completed, and the crew boarded and entered `driving_home`. This observation
verifies recovery, not final delivery; a fresh complete expedition is pending.

Fresh run `SC-Harness-20261105-012312-495a9553` passed the driveway but later
abandoned its car at 12046.04,6777.54 with `no_route` and a tree obstruction.
It was stopped after that failure; no full-trip pass is claimed. Tree avoidance
used a 12-tile blockade buffer, potentially excluding both lanes for a roadside
tree. The native handoff already clears the departure attachment; an additional
retirement guard was unnecessary and removed. A tree now starts with a four-tile
buffer, growing by two on a repeated
block; other blockades retain their previous buffers. Native physical scans
remain mandatory. Live verification of these changes is pending.
Further fresh verification: `SC-Harness-20261105-014012-ec3f91d2`, original
walking seed, saved Scarlet and car46, real blocked connector, two-log driving
request, 1,300-second trip deadline. No original save or installed mod is changed.
It collected and loaded both exact log IDs and returned to the camp edge, but
the home road leg failed with `NO_SAFE_ROAD_DETOUR` (wall) near the saved entry.
That `no_route` result skipped existing checked near-home parking recovery;
the same stopped/distance guards now admit it. One log was stored, while the
second repeatedly exceeded the short search deadline; the run failed at 1,300 s.
Parked witness car5 retained alpha/targetAlpha 1 and native rendering after
solo restore. Kitchen visual acceptance was not reached.

The delivery's trunk action was `wood_car_cargo`, missing the existing longer
camp-car search lease for `move_to_car_trunk`. Delivery now uses that same camp
trunk intent with unchanged area/reach restrictions. Observation
`SC-Harness-20261105-021106-14a79bd0` resumed the exact saved pending delivery:
the search completed at 306 nodes, the worker walked to the stopped car, and
the report reached stored=2/pending=0 with the same two log IDs. This establishes
delivery recovery, not a fresh final-source trip pass.

Final-source fresh attempt `SC-Harness-20261105-022548-64a96516` completed
packing, boarded and cleared the alternate parking connector. It subsequently
abandoned the outbound road leg at 12108.45,6775.29 with `no_route`,
`NO_SAFE_ROAD_DETOUR`, and a vehicle obstruction after three replans. The owned
test client was stopped after that failure; no full-trip pass is claimed.
The vehicle obstruction and detour need investigation before driving acceptance.

The stopped car could select a clear passing strip while its actual bumper
remained inside the normal three-tile stopping gap. Its existing backoff logic
explicitly refused visible obstructions. A native regression reproduced no
movement for 60 simulated seconds. The follower now allows a bounded, straight
reverse for that case when the bumper obstruction is a vehicle and the selected
passing strip is clear. It checks the rear continuously, retains the three-attempt
budget, and leaves fully blocked roads, pedestrians and precise parking unchanged.
The regression now passes without collision, including refusal with a car behind.
Current bridge SHA256: `8012a5d676a4d31dceba79cdf3390e5b8cf7d597d1809cc9409aa403aa4f7012`.
Fresh attempt `SC-Harness-20261105-025010-e7d2ec64` failed earlier, at the
driveway's fence/verge, with `no_route` and a tree obstruction after three
replans. It was stopped; the passing recovery has not yet received live proof.

The short mechanics diagnostic `SC-Harness-20261105-030710-b51ce053` kept the
saved car pose, placed Scarlet at its real driver door, added a diagnostic key
and parked connector obstacle, and paused decisions. Native control then
stalled for 90 seconds near 12045.9,6766.1, using all three existing backoffs.
This is a failed mechanics case, not normal-AI expedition acceptance.
`SC-Harness-20261105-031210-bf88d1f2` inspected that saved position: no nearby
trees or solid squares, but fence edges nearby. The closer native image from
`SC-Harness-20261105-033849-dca88124` instead showed the front of the car on a
utility pole. Metadata inspection `SC-Harness-20261105-034425-be05c117` confirmed
the exact object at 12045,6768 is `appliances_com_01_94`, with `StopCar=true` and
`PhysicsShape=Tree`, while `HasTree` and solid-square tests were false. Both native
driving and Lua access checks omitted these vehicle-only physics properties.
The old three-ray access strip also skipped that tile between its rays.

Both scans now recognise those properties; departure uses five closely spaced
rays and explicitly checks real trees too. Native and Lua regressions cover
vehicle-only poles, shape-only fixtures, removal and the skipped diagonal tile.
The speculative rotating-clearance preference was removed after the actual
obstacle was identified. Fresh full verification
`SC-Harness-20261105-035516-79e96c62` passed the blocked-lot refusal and normal
departure, reached woodland, felled a tree and loaded two exact native log IDs.
It failed turning home beside parked car47 near 11848.5,6639. The crew walked
home healthy, but the car and logs remained outside camp work reach. Pending
delivery was therefore correct; this is a failed complete-trip acceptance.

The follower now backs straight out before its initial turn when another car
occupies its turning space and the rear scan permits it. This is limited to one
attempt, eight tiles or twelve seconds, with continuous rear checks and braking
before the original turn. Cargo checks pass in
`build/test-results/20261105-042802-e2c4d8`, including a full simulated return turn,
rear-obstacle refusal and bounded backout beside a long row of cars. Native
verification of a complete trip is pending. The mechanics-only observation
`SC-Harness-20261105-043907-834dd2ee` retained the already-wedged failed pose:
both exact logs remained in the trunk, the front scan saw a car at zero tiles,
and the rear scan saw a solid obstacle at two tiles. Backout correctly refused;
the diagnostic result was false. Its observation wrapper exiting successfully
is not driving acceptance. The earlier setup-only run `043640-98626e8f` was
stopped after a diagnostic driver-selection error, before any driving test.

The initial alignment now also checks a neighbouring car when the front bumper
is clear. Previously a 60–120-degree departure could begin ordinary pursuit,
then use up the room needed to turn. The angled-departure regression now passes
without collision, alongside blocked-rear and bounded-backout cases:
`build/test-results/20261105-044605-fab039`. Current bridge SHA256:
`5cf4754d3de50c09617da0da35e2e6aa414ebc900248d2445be7995893e938de`.
Ordinary turn failures now retain the native turn reason in the driving detail.
Fresh trip `SC-Harness-20261105-050319-6a8fbd33` used the original crew, saved
car and ordinary production AI, with the same explicit blocked-lot and quiet
work-site fixtures. The initial forest backout succeeded, and the car drove
home with both exact logs. Parking then fell back with `parking_not_stationary`;
the verified stopped car was within camp work reach. One log was stored, but
the other remained pending until the 1,300-second deadline. Scarlet remained
healthy, and the unchanged parked witness car5 rendered after solo restoration.
This is a failed delivery acceptance; kitchen checks were not reached.

The home parking settling clock was starting during an owned, moving driveway
leg. A regression reproduced the false hold after eleven seconds. Settling now
starts only with no owned approach or an arrived approach; active approaches
retain their existing bounded deadline. The regression and four related driving,
preflight, home-car and interface groups pass in
`C:/ZOMBOID/outputs/expedition-parking-02696/scenarios.log`.
Read-only observation `SC-Harness-20261105-052742-2f5b66af` confirmed the second
exact log remained carried by Scarlet. After reload, ordinary delivery resumed
and native navigation was moving toward storage at the 45-second observation
end. No Retry, receipt reset, item recreation or crew relocation was used. This
does not establish completed delivery or isolate the pre-reload runtime stall.
The kitchen fixture now closes the panel it opened, and its existing waiting
trace includes the first pending receipt reason. No movement or camera override
was added.

The blocked-lot fixture now distinguishes a genuine mapped alternative from a
correct refusal. If every checked exit is blocked, it must refuse with the
saved car stationary and engine off. Only then is the probe-created blocker
removed and normal access rechecked before the positive expedition. Saved cars
are never moved. No detour pass is claimed from that refusal/cleanup case.

Optional surplus deposits now stop retrying a particular storage after 15
seconds without physical movement. Required supplies and cargo capacity still
gate departure. Preparation shows the current item, selected cargo container,
supply deficits and readable waiting reasons using existing assessments.

## Packing UI

`SC-Harness-20261105-032852-749e42c0` used an observer-only adjacent kitchen
placement and ordinary public walking dispatch, without changing crew items or
stats. The native `-preparation-ui` capture visibly shows handling Copper
Saucepan, carry load 12.1/17.0, one usable bag, Military Backpack load 13.6/28.0,
and that same bag selected for cargo. No raw preparation code is displayed.
The observation ended with its disposable mission still active; the attempted
early `finishAtPlayer` was correctly refused as `return_route_not_finished`.
No cancellation or complete-trip pass is claimed from this UI run.

The image also exposed a stale generic travel-phase line during packing and an
old trip's outcome appearing before its heading. The current UI suppresses
that phase line during preparation and labels the old report first as
"Last expedition debrief". Focused assertions and the full gate cover both.
The reliability flag now includes the kitchen walk/cutaway check for one-person
trips too; previously that part ran only for a three-person crew.

## Automated checks

Cargo and Interface: PASS, `build/test-results/20261105-020958-7c7403`, including
unloaded-source recovery, roadside cargo delivery and unmarking a storage during
a yielded sorting scan. Focused driving/preflight/UI checks also passed, including
checked near-home parking recovery after a late `no_route` result. Roadside-tree
buffer cases are retained.
Full five-check gate including native passing recovery, pole/tree recognition,
denser strip coverage and final UI labels: PASS,
`build/test-results/20261105-035311-2339fa`, 44.2 s.
Current gate including the initial backout, angled-departure regression and
turn-failure detail: PASS, `build/test-results/20261105-050155-d793d7`, 44.5 s.
Gate after the parking-settle correction and clearer waiting trace: PASS,
`build/test-results/20261105-053247-74cd93`, 46.7 s.
Gate after powered-fixture verification and the focused base-maintenance metric:
PASS, `build/test-results/20261105-060625-6c1edc`, 47.8 s. The parking regression
is now selected by the existing essential Cargo check; extended Cargo PASS,
`build/test-results/20261105-060915-df135b`, 6.1 s. There are still five top-level
essential checks.
Final gate including casual-pause delivery arbitration: PASS,
`build/test-results/20261105-063155-e2fac3`, 44.4 s, all five checks. The targeted
red/green evidence is `C:/ZOMBOID/outputs/expedition-parking-02696/delivery-before.log`
and `delivery-after.log`; the former fails specifically at the owned sit case.
Existing floor cargo, stock batches, four reload cycles, storage policy and
route-yield regressions: PASS, `build/reliability-sorting-regressions.log` and
`build/reliability-storage-routes.log`. The two older shelf-selection cases
now await scan slices while retaining their exact-item and reservation checks.
