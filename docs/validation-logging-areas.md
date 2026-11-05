# Map-selected logging areas: acceptance

Checked on `living_fellows/0.26.98`, based on `6c2e66f4`, against installed Project Zomboid 42.21.0. Shipping on `living_fellows/0.26.99`; release metadata was updated after live acceptance.

**Outcome:** walking delivery and three complete driving deliveries passed. The latest driving run used the original south firehouse departure, detoured through town in both directions, and delivered its exact log. Two runs also passed the upstairs kitchen check immediately after return to solo view. This establishes the tested town route, not every possible traffic arrangement.

## Automated results

- All five essential checks: PASS, 45.4 seconds, serial. Evidence: `build/test-results/20261105-200945-5fd9f0` and `build/driving-reliability/final-gate.log`.
- Existing native road-router specialist: 50 checks passed, including connected road endpoints, blocked destinations, checked verges and street-constrained escape from avoidance buffers. Evidence: `build/driving-reliability/router-regression.log`.
- Native road follower: 91 checks passed, including a staggered parked-car/roadside-obstacle pass. The same new scenario failed against the earlier bridge. The Cargo check also verifies that blocker coordinates and obstacle kind describe the same hit.
- Existing navigation-liveness specialist: 121 checks passed, including the finite camp delivery allowance and missing camp-work proofs. Evidence: `build/logging-area/navigation-liveness.log`.
- Existing map-target specialist: 400 checks passed, including all 64 cells, 128-by-128 bounds, interior knowledge gaps, camp protection, cancellation and legacy targets. Evidence: `build/map-area-final.log`.
- Cargo includes compact regressions for streamed-out car approaches, leader escort, exact transfer after reload, bounded recall recovery, manual logging stops and area progress/reload. No new test runner was added.

## Fixes established during acceptance

1. Wood storage navigation omitted the existing 75-second camp-storage allowance. A reachable native route needed about 589 expansions; the old 30-second hard limit closed its live search after about 370. The wood action now receives the existing allowance only with both camp-work proofs. Idle leases, frame quotas and node ceilings remain enforced.
2. Parked-vehicle avoidance formerly grew to a whole-road closure away from the destination. Its local buffer now stays at 4/6/8 tiles throughout the trip, without shrinking existing broad hazard buffers or removing native collision checks.
3. The road router could replace an approved road endpoint with a cheaper walking connector to another street. Road endpoints now stay attached to their street; off-road walking connectors and outward source escape remain supported. Manual logging also omits the old ten-tile stop setback, which could invalidate its hauling circle.
4. The actual parked point is used for area validation even after the car streams out. Missing vehicle data cannot grant permission to cut outside hauling reach.
5. A hauler previously waited indefinitely for an unloaded car. It now walks toward the saved actual stop, then re-resolves the native car and trunk. The view-owning leader escorts the final hauler when streaming is needed. Recall can likewise approach the saved car with a finite 90-second streaming recovery before existing missing-car handling. Neither path invents a vehicle, container or cargo receipt.

The native bridge was rebuilt with the router and follower fixes; the protocol is unchanged. Lua and this bridge must ship together. Native acceptance payload SHA-256: `2db345476b370e210f9516717302aaab3dc184eea13779c81eb3935e5e274761`, before the 0.26.99 manifest update. The release payload hash is recorded in `docs/validation-release-02699.txt`. The earlier west-road runs used `d293cb456b4b2ef370de0cd4bb6a4aeff45c1257192a890e91826acd71ba12af`.

## Native passes

One low-priority native client ran at a time, using disposable cloned saves and the existing low-impact settings. Fixtures initially supplied real axes, bags, essentials and a fueled native van. Original saves and the installed game were unchanged. Trees, physical log drops, AI navigation, trunk transfers and final storage were production behavior. Threat clearing isolated logging from combat; these are not combat or general frame-rate benchmarks.

### Walking, including reload and delivery

- Harvest/return: `SC-Harness-20261105-163331-1de30556`.
- Successful delivery continuation: `SC-Harness-20261105-173100-e9014f65`.
- Same trip: `1793892908858:672566233`.
- Same native log: `lf-item:1793893072225:3:1058281502`.
- The exact log was physically found in the permitted Log Yard, marked stored, with no secondary player remaining. The initial fixture had mislabeled its yard as standing lumber; the continuation registered a proper Log Yard and exposed/fixed the real delivery timeout.

### Driving: complete harvest, trunk and home storage

`SC-Harness-20261105-185157-0e384034` completed from the firehouse's verified clear west-road parking position. Other parked cars remained. The crew selected the rectangle `8158,11701` through `8166,11709` using the map component and its confirmation control.

- Native mature tree at `8159,11704` existed before chopping and was physically removed.
- Exact log `lf-item:1793901417171:3:1211678390` was observed in the actual van trunk, then physically in the Log Yard.
- Collected 1; stored 1; pending 0. Both crew returned at 100% health.
- Engine stopped, secondary slot empty and ViewSession ownership released.
- Completed in about 350 seconds, with no post-dispatch actor relocation or manufactured cargo.

### Driving repeat and kitchen immediately after solo restoration

`SC-Harness-20261105-190704-6800f040` repeated that physical round trip, then the real player walked upstairs into the kitchen without reloading the world.

- Trip: `1793902114336:2037048250`.
- Exact log: `lf-item:1793902265622:3:928433058`, verified through the real trunk and final yard.
- Actual stopped car: approximately `8109.52,11706.48`, covering the entire selected rectangle.
- Both crew: 100% health; engine off; secondary slot and owner released.
- Player reached native room `kitchen` at `8132,11739,1` after return. The inspected native screenshot shows the player and kitchen interior clearly, with the foreground walls cut away. The return image also shows the van and returned companions' overhead labels, although the open panel partly covers one companion.
- About 332 seconds including the kitchen walk. Feature assertions and the harness both passed.

Images, copied byte-for-byte from the native screenshots:

- `build/logging-area/kitchen-after-return.png`
- `build/logging-area/returned-crew-and-van.png`

## Blocker evidence and remaining limitation

The final run captured four distinct navigation blocks as `*-logging-area-block-1-navigation-blocker` through `*-logging-area-block-4-navigation-blocker`, paired with `SC_LOGAREA|block_capture` records identifying actor, position and reason. The crew recovered and completed delivery. Some captures show the primary viewport rather than a close view of the off-screen actor; do not infer unseen geometry from those images. Desktop-controller capture returned a white game surface and was excluded from visual proof.

The screenshot requirement is now recorded in `docs/testing.md`: capture each distinct block and its recovery with its log context, framing the actor/obstacle where possible.

Earlier town runs failed. `SC-Harness-20261105-184355-12cc7b89` stopped near `8262.82,11678.64` after a solid obstacle, returning `NO_SAFE_ROAD_DETOUR` / `no_route`. Those historical runs remain failed; the follow-up below establishes the corrected route. Collision checks were not bypassed and obstructing cars were not removed to force a pass.

Earlier diagnostic runs also exposed the streamed-car stall and an expired return timer. Their generic observe-only PASS was not counted as physical delivery acceptance. The streamed-car and bounded-recall changes have compact automated coverage; the successful west-road trips establish the complete production effect chain, not exhaustive streaming or traffic coverage.

The final successful log contains the cloned save's existing frame-zero map/room metadata diagnostics. No unhandled gameplay Lua exception occurred in that run.

## Town-driving follow-up

Read-only inspection `SC-Harness-20261105-192911-d568ee8f` found a parked car in the six-tile Cartwheel Street lane and a solid roadside appliance farther along its passing side. A two-tile checked verge, instead of one, lets the follower choose a clear passing line early. Passing remains capped at 8 km/h with the existing body, bumper, rear, wall, person and unloaded-ground checks.

The first live rerun, `SC-Harness-20261105-194802-62cbe3f1`, still failed: escaping a parked-car buffer could select an unrelated street through an unchecked connector across the firehouse. The router now constrains both ordinary road attachments and outward escapes to the current street, including its checked verge. It retains genuine off-road connectors. Blocker position and kind now come from the same actual scan hit, rather than mixing the route strip with the bumper scan.

`SC-Harness-20261105-195723-053447af` passed from the original departure at `8134,11777`:

- After meeting the wreck at `8118.5,11778.5`, the van took the connected town loop, passed the earlier Cartwheel failure point, and reached the selected woodland. It replanned once outbound and once homeward for parked cars; no abandonment or roadside fallback occurred.
- The mature tree at `8159,11704` was physically removed. Exact log `lf-item:1793905461850:3:1355282410` passed through the native trunk and was then physically verified in the permitted Log Yard. Trip: `1793905133111:1597227729`.
- Both crew returned at 100% health; engine off; secondary player slot empty; view owner released. The player then walked into the upstairs kitchen without reloading; the inspected screenshot shows normal wall cutaways.
- About 612 seconds from fixture preparation through the kitchen check. Road-phase frame-gap samples had p95 36 ms and maxima 150/148 ms under the 30-FPS low-impact cap. This controlled run cleared zombies to isolate driving and is not a general combat or performance benchmark.

Evidence is in `build/driving-reliability/town-anchored.log` and that run's `cache/console.txt`. Native screenshots include the road blocker, three distinct navigation blocks, woodland arrival, returned van/crew and solo kitchen. The road screenshot name was reused on the home leg, overwriting the outbound copy; the failed diagnostic run retains the same departure wreck, and future probe captures now include the leg and timestamp. Panels obscure part of some captures, so physical delivery is established by the exact native receipt, not the panel text. Stable image copies are in `build/driving-reliability/`.

## Documentation and cleanup

`docs/map-expeditions.md` and the local Field Guide already describe selection, range, hauling limits, persistence and actual storage delivery. The guide contains the real map-picker image at `web/lf_logging_area.webp`; its self-contained manual and quick reference were rebuilt. No further website publication was performed.

No live test client or temporary acceptance module remains. Local installation was not part of this release request. See `docs/validation-release-02699.txt` for packaging and release verification.
