<!-- SPDX-License-Identifier: MIT -->

# Driving expedition investigation — 25 October 2026

The apparent forest stall is reproducible after the car parks: the expedition's eight-second movement watchdog can cancel a still-running navigation search. A local fix preserves that search within the existing thirty-second waypoint limit. Further live runs collected and trunk-loaded the requested wood, but driving acceptance still fails on the return journey.

## Method

Project Zomboid 42.21.0 ran offline against separate clones of the same saved world. The baseline was release commit `18a47a199fb05c7276d205d603fdfab86c2662e6` on `living_fellows/0.26.67`. All runs used saved car 46, existing permitted camp equipment, actual mature trees, native log identities and production expedition controllers. No replacement axe or bag was needed. The native bridge was unchanged: SHA-256 `d7ac97d30782bc52b2e61df36bf0a43d248e16b3c10ab9f8a4ee3b7d525ea6b2`.

The explicit quiet-site fixture removed zombies around forest work and the parked site, with totals recorded below. It did not clear the return road. Nobody was healed, rescued or repositioned to complete a trip. Three-person runs enabled the game's debug mode; the solo pilot did not. The three-person baseline and candidate both used passive action-history sampling. The solo pilot used the earlier observer, so it is supporting evidence rather than a controlled crew-size comparison.

## Live results

Times are wall-clock observations at normal game speed, rounded to seconds. Every driving trip requested two logs.

| Run | Source / crew | First forest approach after parking | Result |
| --- | --- | --- | --- |
| `SC-Harness-20261025-103611-2b39ceb4` | Release / three | 565 seconds | First two sites had no mature trees. Chopping began at the third shortly before the original 780-second test deadline. Failed deadline; no log pickups yet. Quiet fixture removed 19 zombies. |
| `SC-Harness-20261025-110615-3f3dd653` | Release / solo pilot | About 60 seconds | Felled a tree, picked up two native logs and physically loaded both into the saved trunk. Return used roadside fallback because the original bay lacked a clear forward approach. Delivery reported two stored, but the axe remained pending at the 780-second deadline; final completed-trip storage assertions were not reached. Quiet fixture removed 22 zombies. |
| `SC-Harness-20261025-112218-aee0cd35` | Release / three, passive diagnostics | 295 seconds | Felled a tree and trunk-loaded both logs. Homeward driving failed against a wall after three recovery attempts. Engine stopped; the crew left on foot while both logs remained in the remote trunk. Repeated walking replans continued. Intentionally stopped at about 1,161 seconds after preserving the evidence. Quiet fixture removed 22 zombies. |
| `SC-Harness-20261025-114530-489df0d8` | Local watchdog fix / three | 171 seconds | Reached actual chopping at 402 seconds, versus 514 in the preceding baseline. Felled a tree and trunk-loaded both logs. A `survival_priority` interruption then ended the return drive and unloaded the crew near zombies. All three died; neither log reached home storage. Intentionally stopped after confirming the deaths. Quiet fixture removed 21 zombies. |

Neither intentionally stopped run is an acceptance pass. The solo pilot also failed its completion deadline. The earlier three-person walking expedition remains a separate successful one-log delivery; it does not establish driving acceptance.

## Causes

### Forest approach: competing timeouts

`SCExpeditionPrototype.pulseScout()` treats eight seconds without sufficient physical movement as a stalled waypoint. `SCNavigation` deliberately holds an actor still while its bounded incremental search runs; its ordinary search can use up to thirty seconds while making progress. The trace caught searches still planning shortly before the expedition cancelled and restaged their waypoint. That discards the search frontier and repeats work.

The passive three-person baseline spent 293 sampled beats approaching its first site, with a squad cohesion hold in only two of them. Persistent regroup waiting does not explain that delay. Two mapped forest patches without mature trees added travel before real work could begin. The original 780-second failure therefore combined slow approach, site retries and a short observation budget; it was not proof of a permanent deadlock.

The local patch retains an active `ordered_move` search while its age and the staged waypoint's age remain below thirty seconds. Ordinary movement with no progress still uses the eight-second recovery, and unrelated planners receive no exemption. The candidate's shorter live approach supports the diagnosis, but a single repeat does not establish a general performance guarantee or solve every navigation delay.

### Return: blocked route and unsafe fallback

The passive baseline logged `road_failed reason=route_blocked` at `11863.664,6668.430`, after three attempts, with `obstacle=wall`. The recorded route crossed that blocked approach. `SCExpeditionCar` then stopped the engine, exited the crew and changed to walking fallback. This explains why a car and its cargo can be left away from home; the logs correctly remained associated with the trunk instead of counting as delivered.

The candidate took a different return outcome: `road_unload_fallback reason=survival_priority`. `SCDecision.ownerNeedsImmediatePreemption("drive", ...)` allows medical emergencies, including any bleeding, to stop driving. The expedition car controller treats a failed drive as fallback unloading. Shortly after the stop, the driver was recorded bleeding from the left forearm with health 89, followed by unsafe medical-care holds near zombies and the deaths of all three crew. The generic stop reason does not prove the exact initiating assessment, but the source and nearby medical evidence identify a medical interruption as the likely trigger. This is a separate safety failure from the forest watchdog.

Further return work should validate or replan the blocked road connection and distinguish a temporary medical stop from abandoning the car. Crew exits need a safe recovery decision, with cargo preserved and any pending delivery visible. Those changes are not included in the local watchdog patch.

## Verification and status

- The new production-controller regression fails against the released controller at “a live ordered-move search survives the eight-second movement watchdog” and passes with the patch. It also covers the thirty-second ceiling, ordinary eight-second recovery and an unrelated planner.
- The full project gate passed all 27 stages in 206 seconds with the production fix. After the final private-observer changes, live harness checks passed again: 1,104 wood ownership/orchestration checks, 149 static assertions, door/combat fixtures and process-ownership checks.
- The private observer now records search age, staged waypoints, recovery attempts, car failure details and crew health. Reading action history does not advance the action supervisor. Crew death fails future runs immediately instead of waiting for impossible delivery.
- All isolated clients are stopped. The source world's player, vehicle and global data hashes, plus the normal latest-save setting, match the pre-test fingerprints.
- The watchdog patch and private observer changes are included in the 0.26.68 source update. Its native bridge is rebuilt with the new version metadata and the same protocol. The already-published 0.26.67 release assets retain their original contents. **Full driving acceptance remains failed.**

## Evidence

Raw per-run logs and native screenshots are retained under `build/live-sandbox-runs/<run>/cache/`. The main traces are `Lua/SurvivorCompanionHarness/wood-expedition.log` and `console.txt`.

Focused baseline/fixed regression outputs, the complete project gate, source-save fingerprints, observer checks and explicit diagnostic-stop records are under `build/driving-stall-0.26.67/`. Publication and overall scenario status are recorded in `build/release-0.26.67/acceptance-record.md`.
