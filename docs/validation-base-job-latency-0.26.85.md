# Base job latency investigation — 0.26.85

Date: 2026-10-31. Branch: `living_fellows/0.26.85`, based on
`9f49ffcc847b9674cbdffc1d59c337d98aa49ff3`, with the candidate Lua fixes in this working tree.

## Runtime and scope

All live runs use the real Project Zomboid 42.21.0 client, Living Fellows alone,
and disposable copies of `LF-Skills5-Test-2026-10-29`. The source save and
installed game payload are unchanged. Each run records its source release and
private bridge in `run-manifest.json`.

The bridge is unchanged: protocol `42.21-isocompanion-26`, SHA-256
`3890f8df4f6f48cd2c517b1a0ec1cb13164f978fa5e304b27213ff0eb023e729`.
These checks therefore exercise 0.26.85 source, rather than assuming the
installed game has already been updated from 0.26.84.

Claude's exact probe and version were unavailable. The independent fixtures
cover the reported symptoms, rather than claiming to replay those lost logs.

## Findings and changes

* Farming admitted water supplies only from marked storage. A farmer's own
  watering can could be shelved or packed before the work was considered.
  A farmer now retains one usable carried can when safely within the load
  policy. Farm admission and native watering reuse that exact item. Personal
  equipment creates no fictitious camp loan or return receipt; real borrowed
  camp supplies keep their existing exact return/recovery obligations.
* Precise farm alignment requested a 0.2-tile arrival radius, but navigation
  replaced it with the 0.35-tile moving-intercept radius. An actor could remain
  in an `arrived` loop outside actual farm interaction reach. Explicit arrival
  tolerances now survive interception.
* Optional shelving could keep both arbitration priority and a logistics action
  owner ahead of assigned work. Eligible assigned priority/production work now
  outranks optional logistics. An approach can release its owner before an item
  transfer starts; an animating/committing transfer must finish first. Medical
  emergencies, combat, real overload, order eligibility and restrictions retain
  their existing priority.
* The north-facing window at **12034,6748,0** has a kitchen counter on its inside
  tile (**12034,6747**) and a bench on its outside tile. The bench sprite is
  `furniture_seating_outdoor_01_17`; the counter is `fixtures_counters_01_73`.
  `canStandAt` accepted the bench tile, while LF topology correctly rejected
  edges into it as `furniture_occupied`. Barricade work no longer offers an
  endpoint its own pathfinder refuses. It pauses with a readable blocked-work
  reason, retries after three minutes, and retains manual Retry. Occupied work
  positions use a shorter retry.
* A verified camp job switches its actor from `base_duty` to `work`. That switch
  previously lost the existing quiet-camp 5 ms planning allowance and fell back
  to 3 ms. Live owned work now retains the allowance only with a matching,
  unexpired camp-job lease. Existing frame-pressure, fresh-senses, danger,
  player-combat and camp-boundary checks still govern every slice. Manual work,
  expired leases and another actor's job cannot claim the allowance.

The original 140-second pause **during** a drag has not been reproduced. Natural
pre-pickup delays and a front-door obstruction are recorded separately from the
native haul itself.

## Live evidence

Run roots below are under `build/live-sandbox-runs/`. Each contains the exact
private Lua payload, console, event log and manifest used for that run.

| Run | Result |
| --- | --- |
| `SC-Harness-20261031-204207-70e11a1f` | Existing bedroom-window probe: first plank at 27.108 s; all four at 292.437 s. Supply reservations and route work account for substantial intervening time. |
| `SC-Harness-20261031-205653-ce206d57` | Natural baseline with 12 dry plots and a full carried can: first water at 169.255 s; burial at 178.866 s; front window still had no plank at five minutes. Most burial delay was before pickup; the actual haul was about 20 s. |
| `SC-Harness-20261031-211033-56cf1626` | Geometry diagnostic: all tested incoming edges to the outside window tile reject its bench as furniture. The inside counter also prevents a valid work position. |
| `SC-Harness-20261031-213036-485701ec` | Controlled native work: **PASS**. First water at 5.158 s, completed burial at 37.919 s, first front-window plank at 57.840 s. The bench was cleared only in the clone at 45 s, so boarding began about 13 s after clearing access and manually retrying. |
| `SC-Harness-20261031-213415-816c3071` | Saved companion positions, no companion staging: water at 123.535 s, burial at 59.529 s. The front window still failed to receive a plank within five minutes after clearing its bench. This is a separate travel/doorway problem; the controlled pass does not certify it fixed. |
| `SC-Harness-20261031-214341-2cf6dabb` | Natural observer-only control: **PASS**, water at 93.005 s, burial at 37.018 s, first plank at 250.483 s. Only the observer moved at 120.018 s. This completed the work but did not establish acceptable window travel latency; removing the observer alone is not a complete explanation. |
| `SC-Harness-20261031-215126-91d74ffe` | Natural mode with observer clear from the start and guarded owned-work planning: water at 120.307 s, burial at 84.886 s; **FAIL** for front-window travel, with no plank by five minutes. The remaining indoor route/crowd delay is reproducible and is not certified fixed by these changes. |

Controlled setup moves companions only before timing, validates their native
physical squares, gives the maintainer actual materials, and then leaves the
ordinary decision, navigation and native action controllers in charge. Natural
mode retains the companions' saved positions and gathers building supplies
from permitted storage. These are different tests; their timings are not an
equivalent before/after benchmark.

The combined probe's pass criteria are the first verified crop-water increase,
the first added window plank, and a completed burial. It does not certify that
all 12 plots were watered or the window was fully boarded. A full can is also
added to permitted storage at 45 seconds as a supply control. The controlled
five-second watering result precedes that control; later natural watering
results do not by themselves distinguish carried from stored water supplies.

The saved observer is at approximately **12032.65,6748.94**, outside the front
door. The further natural run starts with the observer away from that entrance
and exercises the owned-work planning allowance. Its remaining route stall
shows that personal-space avoidance alone does not explain the doorway delay.
The maintainer repeatedly shuffles/replans around **12031–12032,6746** before
timing out. That remaining interior route needs separate investigation.
The larger planning slice is withdrawn under load or when its other safety
conditions are absent; it is not a guaranteed latency improvement.

The fixtures use native crop globals, a real `Base.WateredCan`, real hammer,
planks and nails, a native corpse and native empty graves. The corpse is placed
on clear indoor floor with a verified accessible pickup side; other corpse
sources are temporarily excluded in the clone. No native damage immunity,
synthetic watering, invented cargo, or companion teleports during work are used.

## Regression coverage

Added checks cover carried-can job admission and assignment, exact native item
selection, completion and cancellation without storage loans, missing tools
without recreation, protected foreign farm receipts, precise arrival tolerance,
assigned-work arbitration, continued medical/combat/overload priority, and
logistics ownership during transfers. Barricade geometry tests now require the
same furniture admission as topology. Existing loan/harvest recovery tests remain
in place.

Focused farming lifecycle and decision arbitration checks pass (127 arbitration
checks). The full gameplay rerun passes, including exact-transfer ownership and
the precise-arrival regression. Both normal and debug Kahlua compilation pass
for the modified production modules and the new probe.

`scripts/Test-Project.ps1 -Jobs 8` completed successfully: **29/29 stages pass**,
`PROJECT_TEST_PASS`, approximately 169 seconds. The complete log is
`build/base-job-latency/project-gate-final.txt`; the focused gameplay rerun is
`build/base-job-latency/gameplay-recheck.txt`. An earlier full-gate attempt found
an out-of-bounds mock square in the new arrival test; the fixture was corrected
and both gameplay and the entire gate rerun successfully. No production code
changed after the final natural live run.

These automated passes do not override the unresolved natural front-window
travel failure recorded above. Live acceptance for that route remains failed.

## Reproduction

Use `scripts/Invoke-LiveSandboxTests.ps1` with the source clone and these common
options:

```powershell
-ProjectRoot C:/ZOMBOID/work/grid `
-SeedSave C:/Users/thore/Zomboid/Saves/Rising/LF-Skills5-Test-2026-10-29 `
-GameMode Rising -LivingFellowsOnly -BaseJobLatencyProbe `
-BaseJobLatencyClearWindow -EngineSound -NoSteam -IsolatedSourceBridge `
-HiddenWindow -TimeoutSeconds 510
```

Default mode validates staged native work. Add `-BaseJobLatencyNatural` for saved
companion positions, and `-BaseJobLatencyMoveObserver` for the observer-only
doorway control. Add `-BaseJobLatencyObserverMoveSeconds 0` to keep the observer
clear from the start. `-BaseJobLatencySeconds` sets the bounded in-game deadline.

No commit, push or local installation is part of this investigation.
