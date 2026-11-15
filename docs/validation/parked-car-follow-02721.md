# Parked-car follow routing, 2026-11-15

The user confirms ordinary following after loading and combat, but reports that
companions stop behind the three parked vehicles in the supplied road screenshot
instead of walking around them. The latest available play log ends before an
explicit parked-car blocker report, so it does not establish an exact failing
edge for that scene.

The existing short-range follow planner rejects whole vehicle-occupied tiles.
When these footprints close the tile graph, the failed search is classified as
`blocked_static`, and it does not dispatch native pathfinding. The existing
native outdoor vehicle route was available only to a verified recent passenger;
ordinary walkers could not request the same polygon detour.

`Navigation._followUsesEngine` now also admits normal outdoor followers when
their source or goal is next to a parked vehicle. The native companion pathfinder
receives the complete formation goal, rather than the adjacent obstructed tile.
The existing native lease continues checking doors, hazards, crowds and progress.
The change does not issue any zombie paths or alter zombie state.

The existing camp-work, stealth, body-dragging and preferred verified-route
boundaries remain. The new vehicle admission requires positively known outdoor
source and destination rooms on the same floor. Ordinary short open-ground
following keeps its existing planner.

## Verification

- A real-Kahlua navigation request fixture models three companions behind coarse
  vehicle footprints, with their leader inside the ordinary short-follow range.
  With the old production file, it exits **1** on
  `path_blocked:blocked_static`; see `build/parked-car-before.log`.
- With the change, the same fixture exits **0**, **134 liveness checks** pass,
  and all three companions dispatch native paths to their complete goals. The
  fixture also checks the policy boundaries and ordinary open-ground control;
  see `build/parked-car-after.log`.
- The separate navigation stability suite passes **1,098 checks**;
  see `build/parked-car-stability.log`.
- The Behaviour gate passes in **67.5 seconds**, three JVM launches, in
  `build/test-results/20261115-185615-dfdd94`.

This regression proves route admission and dispatch using the real Lua planner;
it does not simulate the engine's continuous vehicle collision geometry. The
reported road scene still needs the user's live retest after installing this
local patch. No new game client was launched during the user's test.
