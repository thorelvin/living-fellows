# Living Fellows project rule

Never override zombie pathing. The sole exception is letting zombies detect and
target companions as normal players.

Do not issue zombie paths or waypoints, set zombie movement/pathfinding flags,
or force zombie navigation states. This also applies to recovery, stair, combat
and compatibility helpers. Keep companion-targeting support separate from
navigation. Resolve companion positioning, holding and withdrawal on the LF side.

# Shared roadmap

Codex and Claude share a roadmap outside this repository, at
`C:\ZOMBOID\ROADMAP.md` in the local workspace. Read it before starting work,
claim the item and the next free version number there, and move the item to
Recently shipped when it ships.
