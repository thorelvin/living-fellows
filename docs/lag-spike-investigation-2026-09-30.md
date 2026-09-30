# Expedition render pauses, 2026-09-30

The user's approximately 400 ms animation freezes match three prior live
four-member moving-expedition samples. Their single longest `OnRenderTick`
intervals were 472.240, 450.135, and 464.680 ms. In each run, the interval
landed on the exact game frame that staged the second route leg:

| Run | Sample start frame | Spike sample frame | Stage log frame | Gap |
| --- | ---: | ---: | ---: | ---: |
| `20260928-110212-1b5c1368` | 1360 | 663 | 2023 | 472.240 ms |
| `20260928-105439-fcb35f1b` | 1347 | 719 | 2066 | 450.135 ms |
| `20260928-104948-6b3f3474` | 1377 | 310 | 1687 | 464.680 ms |

The fixture's leg survey called `SC.Navigation.findPath` synchronously for
multiple candidate squares in one frame. The production `nextScoutLeg` survey
used the same pattern with up to 55 candidates and node budgets of 1,800 or
2,500 each. It ran outside the scheduler's per-frame admission budget.
Whole-mod `OnTick` maxima in these samples were only 23-27 ms, which also
shows why the older tick report could not explain the render gap by itself:
the harness survey ran in its own event callback.

Both surveys now retain a route-search job and advance at most one 96-node,
time-bounded slice per update. A rejected candidate is remembered so the next
update proceeds to the next square. The production scout retains its planning
state while no waypoint exists; a changed source or destination resets it.
The movement owner still receives only a verified short waypoint and remains
responsible for actual traversal.

A new live sample on a cloned current save, with the leader transferred to
the same open road area, passed the extended route and streaming checks:
`20260930-200356-69f60311`. Its 30-second window included the second-leg
transition and 1,781 rendered frames. Render p50/p95/p99/max was
16.231/27.243/37.959/44.151 ms, with zero frames above 50 ms. Whole-mod
`OnTick` max was 38.734 ms. Five native companions were loaded in this new
run because an unrelated household companion spawned before sampling; the
moving expedition still had four members. This is a targeted route comparison,
not a claim that every kind of game pause is eliminated.

A separate production road-scout probe on the cloned current save
(`20260930-200847-184d735a`) used the new planner and reached its target
80 tiles away, observed the site, and began returning. The runner timed out
before the team reached the original player. The console contains follower
navigation blocker reports during that return, so this run does not verify a
complete round trip or assign the return delay to the new planner.

The user's latest normal-play console also reports repeated scheduled-save
capture deadlines. Those aborts retain the previous complete document, and
the capture lane is sliced at 0.75 ms per 50 ms pulse. The log does not time
the abort frames, so it is not evidence that these save failures caused the
measured 450 ms render pauses. The save reliability issue remains separate.
