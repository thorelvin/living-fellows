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

## Original live scope and remaining limits

- The initial replay covered one north-facing window in one save. The follow-up
  below adds west-facing windows, doors, explicit plan sides and removal.
- Boarding from a tile with passable furniture, on one side or both, is covered by
  a harness only. The tested window had a bush outside and a curtain inside, which
  already counted as clear. A tile that passes the check but has collision would
  time out and retry rather than board.
- One bed per companion, shelf artwork and the radio save changes are covered by
  harnesses and native API contracts, not by a live run.
- Two raw shelf paths in `SCNativeActions` (building materials taken and returned)
  repaint the shelf with no test of their own.
- The raw logs removed from `artifacts/` in this release stay in git history, as do
  the earlier artifacts, which were not touched.

At the original handoff, this build had not been installed locally or published
to Steam Workshop. The follow-up installation is recorded below.

## Follow-up barricade hardening

Cancelling a barricade job now retires its exact loaded work orders and native
action before deleting the queue row. Disabling or removing a maintenance mark
uses that same cleanup; separate player plans are preserved. A refused cleanup
retains the mark and outstanding job. The saved job normalizer also discards
rows tied to disabled, removed or replaced maintenance targets.

Both the decision controller and the native plank action check the current job,
worker and target identity. A later command invalidates an older queued plank.
Temporary interruptions release native work and its reservations while retaining
the same order's timeout and fetch budget. A genuinely new order gets a new
budget, and verified plank progress retains the existing per-plank renewal.

The cancellation tests first failed on the unpatched cleanup path. Repeated
preemption reproduced 60 fetches with no timeout; native validity also failed
to notice lost job authority. The focused production, gameplay and native-action
regressions now pass. The native-action harness has 23 checks.

The replay also exposed an open-target bug in the copied validity check:
`ISBaseTimedAction.isStarted` is an inherited function until the door action
overwrites it with `true`. Treating the function as a started flag refused open
doors before native start could close them. That check was also incorrectly
applied to windows. The adapter now checks the explicit boolean and applies the
open-state rule only to native doors and player-built doors, preserving native
door-start behavior.
The open-window regression failed before this correction and passes after it.

The full follow-up gate passed **29 of 29 stages in 171 seconds**. The final
live-harness edits also passed its static, clone-isolation and process-ownership
checks. No native bridge changes were needed.

The first extended run cancelled an active action without changing any carried
item identity, observed no late plank, and resumed to four planks in 342 seconds.
Its extra matrix failed at fixture discovery, which required closed doors and
used narrower reach rules. Discovery now uses production camp reach and allows
an open door fixture. The next run reproduced the open-target rejection and was stopped after
diagnosis. A subsequent run reached three planks with the fourth action active
at the old seven-minute harness deadline; a real 90-second worker timeout and
automatic retry had consumed part of that budget. The extended harness now has
a bounded 12-minute main scenario; the production timeout remains unchanged.

Run `SC-Harness-20261030-161547-d1b9cfc0` completed cancellation and resumption
to four planks in 278 seconds, with no blocked-job attempts in that main scenario.
Its west-window plan placed one plank but then timed out during repeated supply
trips through the busy camp. Those general route delays remain unresolved.

The matrix was therefore separated from camp fetching. It places real physical
materials in the cloned worker's inventory or existing bag once its work order
is assigned; the earlier main scenario remains the evidence for shelf fetching.
Run `SC-Harness-20261030-163149-30483592` with `-BarricadeMatrixOnly` passed
**15 checks, zero failures and zero skips**, exiting with `LIVE_SANDBOX_PASS`:

- A west-facing window received four native planks on its same-square face and
  the planned job completed.
- A door was closed for planning, then reopened. The first native action accepted
  it open, closed it, and the opposite-square face reached four planks. The job
  completed; all later plank actions saw the door closed.
- A one-shot order put one plank on the west window's opposite face.
- Native removal took that face from one plank to zero.
- The worker finished with its initial health retained and no active work action.

An earlier matrix attempt correctly refused to queue an already-open door plan;
that fixture was corrected to reopen the door after planning, rather than bypass
the production precondition. The final run produced no Lua exceptions. The save's
pre-existing `map_meta.bin` room warnings and the overloaded observer's damage
messages were present and unrelated to the worker checks.

All **3,430 original save files (22,837,814 bytes)** were compared by SHA-256
before and after the runs: zero additions, removals or content changes. The
isolated client exited and no Project Zomboid process was left running.

## Local installation

On 30 October 2026, the requested local installation completed through
`Install-Local.ps1 -NativeBridge` using the tested bridge JAR. The installed
manifest identifies `0.26.80-private-native`; all 341 payload file hashes were
verified, along with the launcher configuration and matching launcher bridge.
The bridge SHA-256 is
`1ba2d37fda616995fec3cb45cbe71bdef2bf0292ed9350dafce3c28aa45b413c`.
The existing local debug configuration and enabled mod profile were retained.
