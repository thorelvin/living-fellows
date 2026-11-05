<!-- SPDX-License-Identifier: MIT -->

# Rosewood firehouse wood expedition follow-up

Working on `living_fellows/0.26.98`. This follows the tester's report of a short
drive followed by returning without wood, plus start/end stutter. The native
Rosewood station is used in cloned saves; the tester's furnished save is not
available. Only one capped, low-priority native client runs at a time.

Current result: a native firehouse trip parked and stored its real partial
timber load. Near-home obstacle buffers and diagonal vehicle exits have been
corrected; all five checks pass, and the final native exit sweep passes both
front seats at eight measured headings plus a path from a diagonal exit toward
camp. Quiet final reunion/solo-view release remains unverified because the full
trip's return encountered a camp alert. A combined full trip with an intentionally
forced roadside failure has not been rerun. This evidence accompanies the
0.26.98 release commit.

## Confirmed preparation defects and corrections

- A stale routine `encounter:scavenge` action could retain the leader while
  departure packing repeatedly failed with `actor_owned_by:encounter:scavenge`.
  Packing transactions now use travel priority. Other logistics stays at work
  priority; medical, survival and external ownership remains higher.
- Optional surplus staging could remain in `storage_route_pending` indefinitely
  before creating a movement transaction. The existing 15-second escape limit
  covered the later approach only. Pure destination selection now gets 15 seconds
  per item, then retains that exact item and proceeds to the capacity check with
  an existing storage-unreachable warning. Mandatory cargo space still gates
  departure. No item is dropped, recreated or transferred on timeout.

The ownership regression failed on the old code at
`build/test-results/20261105-075256-9891ea/Cargo-lua.log`. The revised Cargo check
also verifies that higher-priority medical care keeps its owner and inventory.
The route-selection regression gives the survey its initial opportunity, then
advances beyond the deadline. It fails on the retained pre-timeout source in
`C:/ZOMBOID/outputs/expedition-parking-02696/firehouse-packing-before.log`.
Cargo with both corrections passes in
`build/test-results/20261105-081943-2d3b21`.

## Reproduced empty woodland selection

`SC-Harness-20261105-084717-da516e5f` started two healthy equipped workers in the
actual native `firegarage`, left the saved parked cars in place, and dispatched
through the public wood expedition API. The crew boarded, drove out and returned
without collecting wood. Arrival checks found zero mature trees in both fully
loaded 72-square patches: `forest:8160:11735:Forest` and
`forest:8184:11735:Forest`. Both returned `forest_no_mature_trees`.

Discovery now checks at most 48 loaded squares per call and skips a patch only
when its entire area is loaded and contains no mature tree outside camp.
Unloaded or partly loaded patches remain provisional. The existing bounded
metadata search resumes for another candidate; native arrival verification,
tree claims, chopping and pickup accounting remain unchanged. There is no
background scan or extra trip attempt allowance.

The forest regression fails on the previous source in
`build/test-results/20261105-090209-b34094/Cargo-lua.log`, then passes with the
bounded check in `build/test-results/20261105-090301-53fa66`. It also verifies the
48-square call limit and that unloaded woodland is not rejected as empty.
All five project checks pass in `build/test-results/20261105-090323-208eb4`
(44.6 seconds, serial). These automated results do not establish native delivery.

The reproduced native run recorded normal-driving p95 frame gaps of 36 ms under
the 30 FPS cap, but maxima of approximately 1.9–2.4 seconds around transitions.
The cause of those isolated gaps is not established. Return parking also used
the stopped roadside fallback after `road_access_blocked`; this is not a clean
return-parking pass.

## Native observations and test limits

- The station's saved vehicle row is around `8130–8139,11768`. A van placed
  behind it at `8134,11756` correctly refused departure with
  `road_access_vehicle_blocked`. The existing fire pickup also had seat cargo;
  physically moving those exact items into its trunk exposed a separate solid
  exit refusal. These cases do not prove a usable crowded-forecourt exit.
- The positive forest-finding fixture uses a native van at the production road
  planner's checked clear point `8134,11777`, with a marked departure apron.
  Existing parked cars are retained in place. Real axes, worn hiking bags,
  drinking water, food and dressings are supplied to two saved workers, matching
  the equipped-companion case rather than depending on locker retrieval.
- Hostiles are cleared around the cloned base during preparation and at the
  work site to isolate discovery from combat. Original crew stats and native
  trees are unchanged. This is not combat acceptance.
- `SC-Harness-20261105-074209-0d0438a9` exposed the stale-action problem. Its
  unmaintained quiet setup later admitted incoming zombies and the mission ended
  `all_dead`, with zero logs. It is a failed expedition, despite the surrounding
  observation runner exiting 0.
- `SC-Harness-20261105-075559-40e95459` removed the ownership block but encountered
  a blocked locker route. The run was stopped after sustained lack of progress.
- Equipped run `SC-Harness-20261105-080904-137121da` made the leader ready, while
  the other worker remained in optional destination selection. It was stopped
  after that separate stall was established. Dispatch took 161 ms and admission's
  largest render gap was 260 ms at the test's 30 FPS cap. This is a measured
  start spike, not proof of the tester's exact start/end stutter cause.

Fixture setup failures (an invalid render event, native collection indexing,
and a Build 42 body-location argument) are excluded from gameplay evidence.
No temporary `zz_*` fixture files remain in source after private payload copying.

## Current replay

`SC-Harness-20261105-091304-03a2b1d1` selected a farther site, drove there, rejected
one empty patch, then verified mature timber at `forest:8375:11536:Forest`.
Native work collected one log before that patch was exhausted. The crew then
stalled: the passenger's decision stayed `vehicle/expedition_car_seat`, while the
wood phase waited for every worker to finish. This is a failed delivery run,
stopped after sustained lack of progress, not a native acceptance pass.

Further replay `SC-Harness-20261105-100706-20c1c174` identified the reason for
boarding: the hauler deliberately enters to unlock the trunk through
`FieldWork.unlockTrunkFor`. The owned-seat guard then prevents the wood controller
from performing its next latch/exit step. A blanket parked-car exit interrupted
that intended transaction and was removed; that replay is also failed delivery.

The decision loop now services the exact loading worker's wood controller while
seated in the mission's identified car. Travel seats and other cars keep their
existing guard. Cargo access also retains the unlock transaction after the latch
opens until the safe exit completes, including reconciliation from an actual seat
after reload. It uses the existing native unlock/exit and exact-item transfer
paths. It does not force an exit, unlock remotely, or create missing cargo.

Regressions reproduce the seat guard blocking continuation in
`build/test-results/20261105-102208-24de24` and premature unlock-state removal in
`build/test-results/20261105-102300-8eb987`. The final five-check run includes
both corrections and passes in `build/test-results/20261105-102428-fac995`
(44.5 seconds, serial).

The two fixture workers are held through admission with the existing
inventory-inspection hold API, released on public dispatch. Ordinary Stay inside
camp deliberately joins base duty and did not hold the earlier admission-only
attempts: their leader climbed onto stairs, making the ground-floor query invalid.
Those attempts never departed and are not wood-trip results. All post-dispatch
travel, trees, pickup and return use production code.

## Earlier native outcome: delivery failed

`SC-Harness-20261105-102617-118308e9` used the final fixes. It departed with both
workers, rejected an empty arrival patch, verified mature timber at the second
site, chopped and picked up one native log, unlocked the trunk, physically loaded
the log, boarded both crew and drove home. Trunk weight rose from 0.5 to 9.5;
the native lock changed from true to false. The patch was exhausted below the
two-log quota, so this was a partial return, not a full-load collection pass.

Return driving fell back with `no_route` near `8115,11778`, outside the firehouse.
The car stopped and the crew disembarked, but inbound walking repeatedly failed
with `scout_no_exterior_path:55`. The leader remained at `8115.5,11778.5` without
a waypoint or native navigation action. The log remained in the car. The exact
owned cloned client was stopped after sustained lack of progress; the original
save and installed mod were untouched.

**That run failed delivery acceptance.** The cargo unlock deadlock no longer
reproduces, but the exterior return route and start/end hitches remain unresolved.
The automatic site also yielded only one log; a dense-woodland/full-quota run has
not passed here. The observer's planned debrief walk and final storage screenshot
were never reached. The five automated checks above pass; they do not replace
this failed native result.

The six-minute diagnostic recording from the earlier cargo-stall run is retained
at `C:/ZOMBOID/outputs/firehouse-091304.jfr`. Its largest recorded GC pause was
0.02 ms. Java sampling shows substantial Lua-interpreter execution, but cannot
identify the Lua callback responsible for the transition gaps. It does not
establish a stutter root cause or a performance fix.

## Roadside-stop and delivery follow-up

The failed drive reported `obstacle=vehicle`, three replans and
`detail=NO_SAFE_ROAD_DETOUR` near `8114,11780`. Native probes
`SC-Harness-20261105-114002-01916990` and
`SC-Harness-20261105-114422-a8afa070` reproduced routing from that location:
4/6/8/12/20-tile buffers retained a route; 28 tiles removed it. The repeated
parked-vehicle buffer had grown large enough to exclude the nearby road goal.

Vehicle obstructions within 32 tiles of the road endpoint now use 4/6/8-tile
buffers. Native collision checks, the three-replan limit and existing handling
of distant obstructions remain active. Established larger road/horde avoidance
areas are never shrunk by a subsequent vehicle obstruction. The regression fails in
`build/test-results/20261105-114857-972c87` and passes with the correction in
`build/test-results/20261105-114951-5ac06c`. The complete existing driving
ownership/replanning harness is reused under Cargo. All five checks pass in
`build/test-results/20261105-115122-611000` (48.3 seconds).

The isolated foot searches found real 18–23-node paths around the parked row.
A recreated stopped van's selected exit was outside its square footprint and
also admitted those paths. Neither experiment reproduced the full expedition's
55 rejected candidates, so no speculative walking or exit-placement change was
made. Replay `SC-Harness-20261105-115242-181e754b` includes path-rejection details
if the original inbound failure recurs.

## Current native outcome: cargo delivered

Replay `SC-Harness-20261105-115242-181e754b` chopped and collected one native log,
completed the trunk unlock/load transaction, drove home, parked in the assigned
bay, stopped the engine and unloaded the crew. It did not abandon the car or
enter the failing roadside walking state. Delivery receipt
`lf-item:1792868982084:22:919146324` became `stored=true` in log-yard `zone:18`;
the debrief reports `stored=1, pending=0`. Both expedition workers remained at
100 health in the observed return. This is a verified partial-cargo delivery,
not a full two-log quota pass.

No vehicle replan was needed on this positive drive. The tightened buffer branch
is covered by the regression and native route queries, while this replay proves
the actual collection, parking and storage path. It does not prove physical
circumvention of every parked obstruction, or repair of the earlier on-foot
fallback failure. Walking and exit-placement code was deliberately left unchanged
because the isolated path searches succeeded.

After storage completed, camp combat/alert handling held the crew's assembly
(`combat/safety_guarded_hold:combat`, `move_to_alert_fallback`). New hostiles
were not continuously cleared at home while the crew was away. Consequently,
this run does not establish the quiet final reunion or release-to-solo-view
acceptance; the stored cargo result remains independently verified. No immunity,
healing, remote item transfer or teleport after dispatch was used.

## Diagonal roadside exit defect and correction

Native geometry probe `SC-Harness-20261105-121758-094a1309` measured eight actual
horizontal headings. At 45/135/225/315 degrees, both front seats selected a first
exit square whose `getVehicleContainer()` was the van itself. Vanilla `isFree`
had accepted those squares. This establishes an unsafe exit selection that the
foot planner subsequently treats as a vehicle footprint; the earlier straight
van probe did not exercise it.

`SCVehicle.safeSquare` now requires a readable, empty vehicle footprint as well
as its existing floor, solidity and occupancy checks. Both the owned car and
neighboring cars are excluded. A fully blocked door returns no candidate and
waits; it never places an actor inside a car. Native entry/exit, seat ownership
and inventory transfer code is unchanged.

The existing Lifecycle check now loads the production vehicle adapter and checks
own-car overlap, neighboring-car overlap and a completely blocked door. It fails
on the earlier code in `build/test-results/20261105-122221-4f8db7`. All five checks
with both final corrections pass in `build/test-results/20261105-122456-f17cac`
(44.4 seconds). No production walking-planner changes were necessary.

Post-fix native probe `SC-Harness-20261105-122637-7ba794c1` selected clear exits at
45 degrees and recovered the test actor onto the selected native square. The
real bounded pathfinder found an 18-node route toward camp from that exit. Its
later requested rotations were overwritten by awakened physics, so they are
excluded as independent heading coverage. Final sweep
`SC-Harness-20261105-123038-e61cc706` holds the pose using vanilla's vehicle-angle
debug pattern and checks the measured heading before inspecting each exit.
The final sweep passes: all 16 selected exits are outside vehicle footprints,
every requested heading is confirmed by the native forward vector, and the
recovered 45-degree exit admits an 18-node path toward camp. The client completed
and closed normally. No native test client or temporary `zz_*` probe remains.

The positive full expedition above preceded this final exit-square filter.
Combined validation consists of that physical collection/parking/storage run,
the final automated gate, and the separate native diagonal-exit regression;
it is not a second full expedition with a forced roadside failure.
