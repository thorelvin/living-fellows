# W09 three-scenario cost pilot, 2026-09-27

This is a measurement pilot on the installed Project Zomboid 42.20.4 client,
not a W09 release pass. The runs used separate disposable clones of the same
Riverside gas-station save, the same mod list, four restored companion records,
and a 30-second measured window after warm-up. The primary player remained at
the gas station. In the remote run, the actual saved companion leader occupied
local slot 1, two saved companions followed at a test-only location 512 tiles
east, and a fourth stayed by the player. The remote leader's area and its
natural zombies were active. A third run added a local player encounter while
the remote team remained loaded. The encounter used one ordinary native zombie
with test-only high health so it could sustain attacks without in-window spawns;
this is a combat workload fixture, not natural-population evidence.

| Measurement | Base save, slot 0 only | Remote expedition | Remote plus player encounter |
| --- | ---: | ---: | ---: |
| Render intervals | 1,792 | 1,705 | 1,520 |
| Frame interval p50 / p95 / p99 | 16.13 / 29.02 / 33.10 ms | 17.42 / 26.48 / 30.25 ms | 18.97 / 30.36 / 35.67 ms |
| Worst interval; intervals over 50 ms | 49.69 ms; 0 | 42.15 ms; 0 | 45.73 ms; 0 |
| Game process CPU over sample | 47.77 CPU seconds / 29.68 wall seconds (1.61 cores) | 61.11 / 29.68 (2.06 cores) | 61.39 / 28.68 (2.14 cores) |
| Private bytes at start / end | 4,355 / 4,364 MiB | 5,886 / 5,975 MiB | 5,631 / 5,760 MiB |
| Working set at start / end | 8,163 / 8,172 MiB | 9,189 / 9,296 MiB | 9,179 / 9,236 MiB |
| Native loaded chunks, slot 0 / slot 1 | 361 / 0 | 361 / 361 | 361 / 361 |
| Native zombie list, start / end | 4 / 4 | 78 / 70 | 85 / 91 |
| Pending co-op area loads during sample | 0 | 0 | 0 |
| LF scheduler over-budget frames / LF frames | 1,349 / 1,793 | 1,587 / 1,706 | 1,422 / 1,521 |

The remote run used about 0.45 more CPU cores and started about 1.5 GiB higher
in process private bytes than the base run. This is an observed difference,
not a clean estimate of the second view alone: the second area also loaded
361 chunks and roughly 70 more zombies. The remote p50 interval rose by
1.29 ms, while its p95 and worst interval were lower. Those mixed results
need repeated runs before a stable frame-cost claim. The large LF scheduler
over-budget counts in both conditions warrant investigation; its separate
rolling p95 is not the whole-game frame p95. JVM heap samples moved sharply
during both windows and cannot establish a leak from this short pilot.
In the stable encounter run (`100451`), the player made 29 native attack
requests and landed 11 native weapon-hit events on the local target, which
lost its 100 health and died. The original remote leader remained in slot 1,
all four companion records remained, and the primary player survived. Combat
coincided with about 0.53 more process CPU cores than the base sample and a
2.85 ms higher frame p50. These are single-window observations, not accepted
release deltas.

Two further base/remote samples (`100943` and `101204`) confirmed that the
LF scheduler often exceeded its configured 2 ms frame budget even without
local combat. Its cumulative reports identified `scheduler.ui-refresh`
(p95 16–17 ms) and `scheduler.decision` (p95 8–12 ms in those runs) as major
jobs. `navigation.first-motion` appears in the same report, but it records
elapsed first-motion latency rather than callback CPU time and must not be
ranked as a CPU cost. An open roster was confirmed in later samples.

The roster scheduled refresh code promised two completed updates per second,
but it started a new update at each 50 ms scheduler beat. The private build
now waits 500 ms after a completed refresh before starting another, while
continuing in-progress slices at the existing beat. Core harnesses passed
46/46 and installer cases passed 35/35 after the change. A live base-save run
`102059` with the roster open completed 46 refreshes over 30 seconds, with
582–718 ms between completions. Its LF over-budget count was 1,153/1,798
frames; the earlier base run `100943` was 1,335/1,796. Whole-game p95 was
28.80 vs 29.63 ms. A remote run after the change, `101810`, retained four
companions and both views, but its LF decision p95 rose to 24 ms under a
different natural encounter. These stochastic runs cannot isolate the UI
change's exact frame benefit, and decision work still exceeds the target.

The fixed-site remote load transition was timed separately in `102413`.
Admission from queueing the original companion to seeing that same actor in
slot 1 took 424 ms. The test-only transfer from Riverside to a previously
unloaded square 512 tiles east took 176 ms until ordinary world lookup saw
the square with the leader present. End-to-end queue-to-remote-ready was
600 ms. The native pending co-op queue peaked at one and had drained by the
30-second sample. This is one controlled transition, not long-route loading
latency. The same run retained four companions and measured 36 completed
roster refreshes in 30 seconds, at gaps of 593 to 1,558 ms while the UI was open.

The harness reads `System.nanoTime()` on each `OnRenderTick`, records one native
counter row per second, and the runner samples the owned game process once per
second. The profiler itself adds work to both conditions. Raw frame, native,
process and summary samples are retained under these run directories:

- Base: `build/live-sandbox-runs/SC-Harness-20260927-094006-13f00fb2/cache/Lua/SurvivorCompanionHarness/`
- Remote: `build/live-sandbox-runs/SC-Harness-20260927-094147-02ee95f8/cache/Lua/SurvivorCompanionHarness/`
- Remote with player encounter: `build/live-sandbox-runs/SC-Harness-20260927-100451-babb4fd0/cache/Lua/SurvivorCompanionHarness/`
- Post-cadence base: `build/live-sandbox-runs/SC-Harness-20260927-102059-b8b49004/cache/Lua/SurvivorCompanionHarness/`
- Post-cadence remote: `build/live-sandbox-runs/SC-Harness-20260927-101810-576e3d71/cache/Lua/SurvivorCompanionHarness/`
- Timed fixed-site remote load: `build/live-sandbox-runs/SC-Harness-20260927-102413-d0a5097b/cache/Lua/SurvivorCompanionHarness/`

The three tabulated runs passed their setup and sample-coverage checks. Earlier setup runs
`093223` and `093629` exposed a Kahlua upvalue limit and an overly early
population check; `093755` captured samples but failed to write `.csv` files
through the game API. The corrected harness uses the existing text writer.
The first encounter run (`095015`) spawned a zombie outside the equipped
Katana's native 1.4-tile maximum range; it correctly failed the real-hit gate.
The subsequent diagnostic run (`095651`) confirmed that attacks animated but
missed. A revised fixture at the weapon-derived 1.055-tile distance landed
hits. Run `095925` landed 15 hits but synchronously respawned test targets
inside the sample, coinciding with two roughly 675 ms stalls; those are fixture
contamination and excluded from the comparison. Run `100236` used one durable
target and landed 14 hits, but a remote companion died naturally, changing
the active population from four to three; it is retained as a stress trace,
not a steady-population comparison.
The native bridge built successfully, the core suite passed 46/46 and the
installer suite passed 35/35. The launcher JSON and original save `players.db`
retained their pre-run SHA-256 hashes, and no game process remained after the
tests.

W09 remains partial. Before a release decision, lock acceptable p95/worst
frame intervals, incremental CPU and memory, loading latency, and population
limits; repeat the same routes and all three workload conditions; separate
native simulation/streaming cost where possible; and test travel/load
transitions and cleanup. These limits must be fixed before the confirmatory
runs.
