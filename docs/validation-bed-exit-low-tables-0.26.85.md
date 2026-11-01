# Bed exits beside low tables — 0.26.85

## Change

Native get-up can finish just beyond the mattress edge, with the companion's
physical tile overlapping a bedside/foot-end table. The former exit corridor
rejected all furniture at that source, so it could wait indefinitely even when
adjacent standing floor was clear. Removing the table removed that rejection.
Separately, another-tile exit used the new-actor spawn rule, which requires more
connected floor than an existing companion needs to stand in a narrow aisle.

Bed exits now use a dedicated native recovery adapter. It verifies the exact
placed mattress, bounded local corridor, same room/floor, loaded solid floor,
empty destination, structural edges and movement ownership at application time.
An actor already overlapping adjacent furniture may leave it only for a
cardinal neighbour within 1.25 tiles whose native movement/standing check passes.
The exception cannot enter or cross another table, bed, wall, door or fence.
Fully blocked exits keep their automatic retry. Application-time rejection tries
the remaining verified candidates instead of hiding another usable side.

The actor, inventory and relocation rollback transaction are retained. Generic
unloaded-actor recovery and new spawning retain their existing safety rules.
Providers without the additive API retain conservative generic recovery.
Discovery/retries remain local and bounded; there is no new background service.

## Automated verification

- Bed-exit harness: **95 checks passed**, including table-overlap clearance,
  rejected native clearance, narrow aisles, alternate candidates, blocked edges,
  other bodies/furniture, room boundaries, distance limits, all-blocked retry,
  action ownership and exact actor/inventory preservation.
- Bed-segment and hospital-axis harnesses: **20 + 56 checks passed**.
- Native bridge exposure test covers the new API and its nil/ownership guard.
- Full project gate: **29/29 stages passed** (123 seconds), including the
  71-check bed harness snapshot. The eight additional obstruction cases were
  added during that run and passed in the final 95-check focused run.
  See `build/bed-exit-project-gate-final.txt` and `build/bedExitFiles.txt`.

## Native cloned-save acceptance

Run: `SC-Harness-20261101-003131-eb2ed308`, Project Zomboid **42.21.0**,
Living Fellows alone, a disposable copy of the retained four-companion save.
Result: **PASS, 18 checks, zero failures**.

- Stock bed sprites: `furniture_bedding_01_67` (N), `_8` (S), `_36` (E), `_65` (W).
- Actual low table: `furniture_tables_low_01_0`, placed beside each bed's foot.
- N/S/W: real bed entry, observed get-up animation, normal exit controller.
- All four directions: explicitly staged post-get-up overlap on the table tile;
  production geometry and native bed-exit adapter released the same actor to
  empty floor, with the table still present and exact carried items retained.
- The inspected E fixture has no stock native entry positions; its overlap
  recovery was tested, not a native entry/get-up animation.
- Table objects were removed only after each successful assertion, as fixture
  cleanup. Removing furniture was never used to make an exit succeed.

Evidence: `build/bed-exit-tables-live-2.txt` and the run's
`cache/Lua/SurvivorCompanionHarness/events.log` and `summary.txt`.
The live-tested and payload bridge SHA-256 both equal
`55507c1024018175f586bb1e9e17ddc3c88b654df0a81618c3a5401f1bd669fd`.
The native fixture uses loaded clear ground; the blocked-room/floor and crowded
aisle cases are automated regressions, not additional live upstairs scenarios.
Vanilla startup diagnostics and the disposable cache's exit-time ZipLogs error
were present; no bed/adapter exception occurred.

Source changes and the rebuilt bridge are in the checkout. This request did not
install, commit or push them, and did not alter the original save.
