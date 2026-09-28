# Expedition road routing playtest

The expedition planner now lists every eligible building within 200 straight-line tiles of the selected leader, 32 per page. Dispatch rechecks the selected building by ID instead of assuming it remains on the first page. The GUI defaults to **Follow roads** and also offers **Head straight for target**.

Road travel builds a local graph from the active map's street polylines. It splits bends and geometric junctions, attaches the leader and destination to candidate segments, and reports a disconnected or incomplete map instead of inventing a link. The graph supplies street targets only. Existing Navigation still owns each loaded movement leg, including doors, windows, collision, follower cohesion, and the final building approach. Return plans a new road route from the leader's actual position. A versioned save descriptor stores no native graph; restart rebuilds the route after the leader reclaims the second view.

Straight travel uses the existing loaded-leg planner up to the 200-tile target. If no outbound leg can be found for 30 seconds, the team turns home with `straight_path_unreachable`. A failed inbound path becomes a visible technical hold rather than a fabricated return.

## Evidence

- `scripts/Test-Project.ps1`: all 9 stages passed, including 49 core harnesses, native route geometry, place pagination, expedition restart, gameplay, and installer gates.
- Live cloned save `SC-Harness-20260928-213624-8d4400d1`: the four original companions walked to a site 180 tiles east, made a complete observation, and returned to the original player. Maximum follower gap was 12.34 tiles and maximum sampled leader step was 0.106 tile. The original save and game launcher were restored.
- Live stage `SC-Harness-20260928-214711-b3728cb4`: saved a schema-5 road mission during the inbound walk with four roster members and flushed the second local slot.
- Live reload `SC-Harness-20260928-215208-39b83c15`: restored the same leader and mission in slot 1, replanned from the saved inbound position, and returned to the original player. The launcher was restored.

The road graph is computed only at review, dispatch, return, or restart, never on a movement frame. A future profiling pass should record its actual `elapsedMs` on dense modded street files. Geometric street crossings are provisional until loaded local navigation verifies a traversable path. The current acceptance run used the installed Riverside map and a quiet four-person fixture; other maps and danger conditions still need playtesting.
