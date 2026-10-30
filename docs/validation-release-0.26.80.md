<!-- SPDX-License-Identifier: MIT -->

# Release 0.26.80 checkpoint

30 October 2026. Branch `living_fellows/0.26.80`, based on `d08b5a4c`.

This release makes camp barricades work and fixes the findings from the 0.26.79
review. The native bridge remains at protocol `42.21-isocompanion-24` for Project
Zomboid 42.21.0, and the bridge binary is unchanged. Saved jobs from the old shape
repair on load; no save schema changed.

## Why barricades did not work

A playtest log showed job 245 failing six times with `barricade_target_unloaded`.
Replaying that save in the real game exposed these causes, one behind the other.
Each was found by the live probe and not by a harness.

1. The maintenance audit queued the job with coordinates but no object identity,
   so it could never resolve. The failure was reported as "unloaded".
2. Workers walked to the window first, and only there checked for materials. A
   worker sent to storage was called straight back to the window, and the two
   routes cancelled each other until the work timed out.
3. A shelf in use by another worker, or more than six tiles from the window, read
   as "missing", and that ended the attempt. Missing materials also parked the
   job for good, even after restocking.
4. Logistics returned a just-fetched hammer to storage when the worker was
   overloaded, because it counted as surplus.
5. A barricade order did not renew its job's 45-second lease, so a second worker
   could claim the same job.
6. Navigation called half a tile from the centre "arrived". That is the tile's
   edge, which is the neighbouring square, so the worker was sent again forever.
7. Build 42.21's `ISBarricadeAction:isValid` tests
   `hasEquippedTag(ItemType.HAMMER)`, and `ItemType` has no such field, so it
   refuses everyone. Vanilla players now board through the `BarricadePlanks` build
   recipe, and only vanilla's own tests still reach this action. Its `complete()`
   is intact, so companions keep it with the validity check corrected.

## Live result

`Invoke-LiveSandboxTests.ps1 -BarricadeProbe -LivingFellowsOnly -NoSteam
-IsolatedSourceBridge` on a clone of the save that reported the bug: exit 0, run
`SC-Harness-20261030-141203-301559f1`, no failures.

- The saved job repaired itself on load (`job:245`, `object:27`, attempts 0).
- A worker fetched a hammer, planks and nails from marked camp storage.
- The first plank went up after 56 seconds, and the window was full with 4 planks
  after 131 seconds. The job then completed.

The original save's `global_mod_data.bin` kept its hash.

## Gate and controls

**All 29 project stages passed in 95 seconds.** Each fix also has a negative
control: 38 deliberate breaks of production code, all caught by a test. Three new
harnesses cover what fakes could not reach before: `barricade_action_harness.lua`,
`camp_supply_search_harness.lua` and `bed_segments_harness.lua`.

## Not verified live

- One north-facing window in one save. Doors, west-facing windows and the "same"
  and "opposite" sides of a planned barricade were not run live.
- Boarding from a tile with passable furniture, on one side or both, is covered by
  a harness only. The tested window had a bush outside and a curtain inside, which
  already counted as clear. A tile that passes the check but has collision would
  time out and retry rather than board.
- "Remove this barricade" and the one-shot "Barricade this with a plank" order share
  the corrected approach. The first does not use the corrected validity check.
- One bed per companion, shelf artwork and the radio save changes are covered by
  harnesses and native API contracts, not by a live run.
- Two raw shelf paths in `SCNativeActions` (building materials taken and returned)
  repaint the shelf with no test of their own.
- The raw logs removed from `artifacts/` in this release stay in git history, as do
  the earlier artifacts, which were not touched.

This Git release is not installed locally or published to Steam Workshop.
