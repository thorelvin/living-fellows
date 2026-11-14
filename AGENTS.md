# Living Fellows project rule

Never override zombie pathing. The sole exception is letting zombies detect and
target companions as normal players.

Do not issue zombie paths or waypoints, set zombie movement/pathfinding flags,
or force zombie navigation states. This also applies to recovery, stair, combat
and compatibility helpers. Keep companion-targeting support separate from
navigation. Resolve companion positioning, holding and withdrawal on the LF side.
