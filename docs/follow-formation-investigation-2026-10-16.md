# Fan-out Follow baseline and pathing investigation

## Reproducible road baseline

Cloned save `2026-09-21_22-10-41`; Riverside street from `(6100.5, 5400.5)` east for 50 tiles. The player used a real path action and covered 49 tiles in 23.0 seconds (about 2.17 tiles/s). The diagnostic cleared zombies from the corridor, turned team fan-out on, gave the same three recruits Follow, and ordered unrelated recruits to Stay at a safe point away from the route. It did not change production formation, speed, or search logic. The source save was untouched.

| Measured companion | Committed 0.26.43 peak gap | Current working tree peak gap | Current mean gap during seconds 5–22 | Current mean distance behind player during seconds 5–22 |
| --- | ---: | ---: | ---: | ---: |
| Maria Carter | 5.34 tiles | 5.32 tiles | 4.65 tiles | 4.00 tiles |
| Lydia Reed | 6.43 tiles | 6.83 tiles | 5.96 tiles | 5.96 tiles |
| Judith Cole | 4.96 tiles | 4.76 tiles | 4.19 tiles | 3.56 tiles |

Committed run `SC-Harness-20261016-112328-e6483d76` and current run `SC-Harness-20261016-112600-758689d9` both passed. Each measured companion stayed in `open` formation for all 23 running samples, with zero medical decisions and zero planning samples. No measured follower entered native Running during seconds 5–22. Each moved about 2.09–2.10 tiles/s, slightly below the player's speed, so the trailing gap grew slowly. Lydia's rear slot drifted from 5.38 tiles behind at second 5 to 6.79 tiles behind at second 22. The player stopped, and the followers settled back to roughly 2–3 tiles after 12 seconds.

Raw per-second [committed trace](follow-road-50-fanout-isolated-baseline-2026-10-16.tsv), [current trace](follow-road-50-fanout-isolated-current-2026-10-16.tsv), and their [committed](follow-road-50-fanout-isolated-baseline-perf-2026-10-16.tsv) and [current](follow-road-50-fanout-isolated-current-perf-2026-10-16.tsv) scheduler traces are retained. The diagnostic runner's `-FollowRoadFanOut -FollowRoadIsolated` switches reproduce the setup. `-FollowRoadBaseline` restores the committed Decision, Medical, and Positioning modules only in the disposable test mod.

## Column versus fan-out traffic

The same cloned-save road test was repeated on the current working tree at 250 ms sample intervals. The probe explicitly set either Follow column or fan-out, healed old wounds, cancelled old care claims, and disabled cross-companion rescue only in the disposable game process. No measured follower entered medical behavior in either final run. The player covered 49 tiles in 23.03–23.04 seconds. These paired runs were `SC-Harness-20261016-115106-da3336a7` (column) and `SC-Harness-20261016-115335-ab06bb2b` (fan-out).

| Follower | Column mean / peak gap while player moved | Fan-out mean / peak gap | Column planning samples | Column traffic-wait samples | Fan-out planning / traffic-wait samples |
| --- | ---: | ---: | ---: | ---: | ---: |
| Maria | 6.00 / 7.00 tiles | 4.54 / 5.50 tiles | 2 | 0 | 0 / 0 |
| Lydia | 9.72 / 13.46 tiles | 5.82 / 6.87 tiles | 8 | 1 | 0 / 0 |
| Judith | 13.57 / 21.99 tiles | 4.05 / 4.78 tiles | 41 | 7 | 0 / 0 |

The 41 planning samples represent about ten seconds of sampled time, not 41 distinct searches. Judith's pending search reached 2055 ms and yielded on the `navigationSliceBudgetMs` deadline; her target changed among trail squares during the run. The column trace also shows `holding_personal_space` against the companion ahead and `yielding_right_of_way` early in the run. Thus the player's suspicion is supported: following in a single file creates some direct traffic waits, and the rear follower suffers much more route churn and search time. The trace does **not** prove that every search was caused by another companion; it does show that fan-out avoided both the traffic events and A* planning on the same clear road.

The [column trace](follow-road-50-line-final-2026-10-16.tsv) and [fan-out trace](follow-road-50-fanout-final-2026-10-16.tsv) retain the decision, blocker, yield age, formation target, and search reason for each sample. `SCNavigation.allyFlowsAhead` already exempts a sufficiently distant, recently moving teammate ahead from personal-space blocking. The remaining waits occurred when that exemption was not satisfied. `SCPositioning.trailTarget` also backs up to an earlier breadcrumb when the selected one is occupied or reserved. That is safe at doors, but on a clear street it can move a column goal backward and make the rear member replan. A focused implementation should use stable, spaced longitudinal slots and the direct open route on verified open ground, retain exact breadcrumb navigation at portals and obstacles, and measure blocker identity and goal changes after each adjustment. Raising the global scheduler budget alone would not fix these target and traffic effects.

## Why the squad does not flank close enough

`SCPositioning.formationTarget` already assigns stable wedge slots around the player: point and assault about 2.3 tiles to either side and 0.8 behind; rear guard 3 behind. In open ground it predicts the leader by up to 1.25 tiles and uses a fast direct route. The traced formation mode stayed `open`; navigation was `fast_open_route`. Thus lack of a wedge target or a slow A* search did not cause the clean-road trailing gap.

`SCPositioning.followMode` chooses catch-up speed from distance to the *player*, with a minimum threshold of 7 tiles at the normal 3-tile Follow distance. A follower 4–6 tiles behind can therefore move at roughly the player's road speed while remaining several tiles behind its moving slot. The existing Copy-player policy can trigger jog sooner, but the live trace showed no catch-up commitment and no Running for these saved recruits. Their saved move-mode value should be logged in the next probe before changing this policy.

The route goal moves every time the player moves. Target-square hysteresis and moving-route repair already limit unnecessary replans. A redesign should drive speed from error to the assigned moving slot, not just distance to the player: use a short jog burst if the slot is more than about one tile ahead, release it once close, and retain the slot for a stable interval through heading jitter. Keep the fast direct route on proved open ground and the existing pathfinder/portal column for obstacles. Stealth and combat must still override this catch-up rule.

## 2 ms limits and long searches

There are two separate settings: `frameBudgetMs = 2` controls the scheduler, and `navigationSliceBudgetMs = 2` bounds one Lua path-search slice. Navigation also shares a quota of 64 node expansions per frame; load level 3 scales the ordinary quota to about 22. Long searches may therefore span many decision pulses. The scheduler places the decision task in its highest priority lane, so later background work can be deferred without withholding the first Follow decision.

In the two isolated road runs, zero follower samples were in planning despite the scheduler exceeding its 2 ms budget on 2035/2042 and 2043/2045 measured frames respectively. Almost every frame deferred at least one later task. The diagnostic itself adds work, and these figures describe the Living Fellows scheduler, not total game frame time. They prove the 2 ms limit is tight on this cloned save, while the 4–6 tile open-road gap occurred *without* an A* search.

An earlier **unisolated** current-code run (`SC-Harness-20261016-111927-f41fa368`) had all three followers divert to treat a fourth recruit. Judith reached 18.42 tiles behind; after she rejoined, four per-second samples were `planning`, with a pending search observed at 1325 ms and 11 expanded nodes. The search followed the medical detour and trail fallback, so it does not isolate a search-budget cause. Raising the global frame budget alone would also leave the separate 2 ms slice and node quota intact. Test a controlled obstacle route with per-search yield reasons, goal-reset counts, first-motion delay, and a 2/4 ms budget A/B before changing limits.

## Implemented result

The moving line now sorts followers by their position behind the leader, uses a close column on verified open ground, and falls back to the breadcrumb trail at portals and obstacles. An occupied square containing a living teammate is dynamic traffic rather than a static wall. Followers use short jog bursts when more than one tile behind their assigned slot. The scheduler and path-search slice budgets are both 3 ms.

In the isolated 50-tile road run `SC-Harness-20261016-135238-1661ba4a`, the three followers had mean/peak gaps during seconds 5–22 of 6.38/7.94, 2.96/4.24, and 4.68/5.80 tiles. None entered path planning during that interval. The worst gap was about 8 tiles, versus 22 in the comparable column baseline above. The [line trace](follow-road-50-line-3ms-2026-10-16.tsv) records each 250 ms sample.

With fan-out enabled in run `SC-Harness-20261016-134229-63febe2a`, the three mean/peak gaps were 2.93/3.77, 4.08/4.79, and 2.90/3.52 tiles, also with no planning samples. The [fan-out trace](follow-road-50-fanout-3ms-2026-10-16.tsv) records the same fields.

The full project gate passed 25/25 stages. An isolated live pathing run, `SC-Harness-20261016-141103-0518cd24`, passed room entry and door crossing. Its staircase check skipped because no clear three-tread staircase was loaded near the test area. A longer observation window for its aimed-escape animation probe captured the completed turn and the forward walking and running clips. The test-only loading-gate agent advanced the cloned game without a user click.

These are single cloned-save road runs. They show improvement for this squad and route, not a general survival or performance guarantee.
