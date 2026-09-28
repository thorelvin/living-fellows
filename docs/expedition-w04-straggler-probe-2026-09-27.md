# W04 delayed follower probe, 2026-09-27

The private build now holds a staged leader waypoint when a living expedition
follower is at least 12 tiles behind or has no authoritative square. It resumes
the route only when every living follower is closer than 8 tiles and has a
square. The pause suppresses the leader's waypoint command and cancels an
existing `ordered_move` route only when no supervised action owns the leader.
Normal survival decisions continue. This is a cohesion guard for the current
test waypoint, not an area lease implementation.

All runs used disposable clones of the Riverside gas-station save. The second
local player was the original saved leader, with two original saved followers.
The test-only remote transfer placed the leader 512 tiles from the player;
followers were then placed in loaded squares. No transfer after that setup was
used to move the team. The harness held one follower through the action
supervisor and released it after observing the leader. The quiet-area variant
removed nearby native zombies only in the cloned test world. It provides no
evidence about natural threat continuity.

| Run | Result | What it established |
| --- | --- | --- |
| `SC-Harness-20260927-103515-a5ba1efd` | Failed setup | Natural zombies occupied the original remote area. The leader moved only 2.47 tiles and the delayed follower died after release. No meaningful cohesion gap formed. |
| `SC-Harness-20260927-103756-9654ca33` | Failed setup | The first quiet-area route passed through the held follower. The leader moved only 1.57 tiles before release, then completed the waypoint. This measured lane blocking, so it was not counted as a cohesion pass. |
| `SC-Harness-20260927-104114-a3e29800` | Passed focused straggler case | At the westward remote test site, the route pointed away from the held follower. The leader walked 10.50 tiles and stopped when the gap reached 12.03 tiles. Its position did not drift during the measured hold; the follower did not drift; the follower's current square and the slot-1 map still covered its tile. After release, the follower came within 8 tiles, the hold cleared, and the leader reached the 28-tile waypoint. The fixture removed zero zombies in this run. |

Static checks after the production change passed: 46/46 core cases, 35/35
installer cases, PowerShell parsing, and `git diff --check` apart from Git's
line-ending warnings. The final harness adjustment was exercised by the live
pass above.

W04 remains **partial**. The passed case did not push the loaded footprint far
enough to unload a trailing chunk, did not approach a zombie across the moving
boundary, and did not exercise the explicit recovery path for a party wider
than the allowed footprint. Those need separate live runs. The original save
and installed launcher were not changed; the launcher SHA-256 after the run
was `69E8662B0709DE7F158045D23C017D95AF648735D1EF2A862358EC9AD631FE9C`.

## Moving-area threat probe

The harness now retains exact Java `IsoZombie` actor references while the
leader walks an extended route. It samples zombie positions and native
targets, checks for a loaded current square and a normal living actor, and
rejects a sampled movement jump of 3 tiles or more. The pass boundary is one
native chunk-map shift of at least 8 tiles. This test observes the real game
world; it does not change area loading or danger simulation.

Two attempts with natural zombies at the southern site were inconclusive:
`SC-Harness-20260927-104837-b93f73e8` stalled before a map shift, with one
moving zombie that never acquired a team target; `SC-Harness-20260927-105237-058d6582`
walked farther but stopped on a later tactical waypoint, with no qualifying
zombie. A bounded test-only stalled-waypoint replan now clears that waypoint
and chooses another loaded, pathable target from the actor's actual square.
It does not override combat. Natural-population pursuit is still unproved.

The quiet westward route was first checked without a threat in
`SC-Harness-20260927-105722-1f49c5cd`. The original leader walked 100.12 tiles
through six admitted legs. Slot 1's map minimum moved from 5496 to 5600 at
the same 152-tile width; the starting square unloaded in ordinary lookup,
the current leader square remained loaded, and the two followers stayed within
11.04 tiles at completed legs. This is a completed one-way moving-footprint
test with no travel teleport after initial test setup. It does not prove a
destination task, return, or natural danger on that route.

The first native fixture behind the team in
`SC-Harness-20260927-110457-abb752d8` did **not** pass pursuit continuity.
The exact zombie remained alive and moved while the map shifted 64 tiles, but
its native target became `nil` and it wandered far from the team. The harness
correctly rejected that result. A later fixture ahead of the walking team
passed in `SC-Harness-20260927-110816-789d7447`: the same native zombie
(`ID:91`) moved from about `5620.58,5316.50` to `5620.25,5317.09`, remained
alive on a loaded square, and had a team target both before and after slot 1's
map minimum shifted from 5528 to 5544. No large sampled movement jump occurred.
The only artificial input was creating the native zombie and setting its target
once. Normal companion decisions then diverted and replanned a waypoint while
the actor remained present.

This proves a **controlled native-threat handoff across two chunk steps**. W04
remains partial: the natural-population pursuer case, a delayed member at the
trailing unload edge, bounded lease/recovery behavior, and an entire
travel-threat-task-return cycle still lack live proof.
