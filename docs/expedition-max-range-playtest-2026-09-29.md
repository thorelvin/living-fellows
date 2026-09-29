# Maximum-range expedition playtest — 2026-09-29

The current place search is capped at 200 straight-line tiles. I ran the four saved Riverside companions toward a road destination at that limit with naturally spawned zombies, a real second local player as leader, and the normal loaded movement and squad formation. Both runs used disposable clones of `C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41`; the personal save and launcher configuration were restored.

Command:

```powershell
.\scripts\Invoke-SplitScreenSpike.ps1 -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' -GameMode Rising -LeaderSlotOnly -TeamHandoff -TeamAutonomousScoutProbe -TeamRoadRouteProbe -TeamRoadDistanceTiles 200 -TimeoutSeconds 900 -HiddenWindow
```

| Run | Outbound | Return | Result |
| --- | --- | --- | --- |
| `SC-Harness-20260929-154004-83d0e898` | Reached `(6235.26, 5280.50)`, about 153 tiles east of departure after 26 loaded legs | Not started | Leader held for a straggler for 180 seconds; that follower stayed near `(6225.66, 5274.16)` in `planning/combat`, roughly 11 tiles behind. Harness stopped on no progress. |
| `SC-Harness-20260929-154722-d9379e44` | Reached `(6281.44, 5294.32)`, approximately 200 tiles from `(6082.5, 5298.5)` after 36 loaded legs; completed an eight-square site observation | Started and moved west to about `(6223, 5275)` | Combat near the Riverside Suites junction repeatedly interrupted movement. The road return fell back to the reached outbound trail at index 24; six more replans ended in `scout_stall_replan_limit` at `(6235.69, 5275.09)`. The squad did not return. |

The second run selected a side lane and used the shared wedge formation. At site arrival the measured follower gap was 8.28 tiles, and at the start of return it was 6.98. The log records six nearby threats during one follower's single-lane combat yield, an upper-arm bite on a follower whose health fell from 53% to 3%, one companion death with five bites, another follower at 21% with bleeding, and a new bite on the leader before the harness stopped. The screenshot shows the leader and another companion engaged near the fence and a green car. It is a useful stop capture, but it does not establish the exact number of zombies killed.

The failure is repeatable around this junction, but the two runs failed by different mechanisms: follower cohesion outbound, then combat and return route exhaustion inbound. The road-to-trail fallback did activate in the second run, yet the leader moved east from roughly `(6223, 5275)` to `(6235, 5275)` while the staged return waypoint remained southwest. The log does not prove whether that waypoint was impassable or whether combat repeatedly took movement ownership. A shorter 180-tile natural-danger trip previously returned; that result does not extend to this 200-tile run.

Artifacts:

- [Second-run stop screenshot](../build/live-sandbox-runs/SC-Harness-20260929-154722-d9379e44/cache/Screenshots/SC-Harness-20260929-154722-d9379e44-scout-stall.png)
- [Second-run harness events](../build/live-sandbox-runs/SC-Harness-20260929-154722-d9379e44/cache/Lua/SurvivorCompanionHarness/events.log) and [console](../build/live-sandbox-runs/SC-Harness-20260929-154722-d9379e44/cache/console.txt)
- [First-run harness events](../build/live-sandbox-runs/SC-Harness-20260929-154004-83d0e898/cache/Lua/SurvivorCompanionHarness/events.log)

The harness now accepts a bounded `-TeamRoadDistanceTiles` option and requests a full screenshot when its progress timeout fires. Its static checks passed with 137 assertions. These are test harness changes only; expedition gameplay was not changed by this playtest.

## Follow-up: keep road combat discipline on trail return

The second run exposed a specific transition bug: `roadCombatFor` returned no combat policy as soon as the mapped road route was discarded. Its verified outbound trail still represented road travel, but the selected aggressive doctrine could then pursue beyond the 2.5-tile squad defense leash. A failed combat detour also dropped its newly observed avoidance area when switching to the trail. The fallback now retains both the combat leash and any observed hazard. The core suite passed 49 of 49 harnesses, including focused checks for these transitions.

One fresh natural-danger 200-tile cloned run, `SC-Harness-20260929-161711-43c248b6`, travelled 207.39 tiles from departure and returned to the original player at `(6090.02, 5300.50)`. Maximum sampled leader step was 0.18 tile and maximum follower gap was 13.36 tiles. No companion death was logged. Side-lane and wedge checks passed, and the return continued after the mapped road route gave way to reached trail legs.

This was a **safe-return pass, not a full mission pass**. The leader fought near the far end and then encountered a window and vegetation around `(6285-6288,5293-5294)` while approaching the destination. After five stalled outbound replans, the safety rule ordered the squad home without an observation. The harness therefore failed `autonomous_scout_actual_site_observed` and `autonomous_scout_debrief_retained`; destination-distance and return checks passed. The next distinct issue is choosing a reachable, visible observation position near a blocked target, then retaining a real observation before return. Do not mark this run as a completed scouting mission.

- [Follow-up harness events](../build/live-sandbox-runs/SC-Harness-20260929-161711-43c248b6/cache/Lua/SurvivorCompanionHarness/events.log) and [console](../build/live-sandbox-runs/SC-Harness-20260929-161711-43c248b6/cache/console.txt)
