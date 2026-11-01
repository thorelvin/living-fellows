<!-- SPDX-License-Identifier: MIT -->

# 0.26.86 validation record

Prepared on `living_fellows/0.26.86` from the synchronized 0.26.85 tip
`9f49ffcc847b9674cbdffc1d59c337d98aa49ff3`, for Project Zomboid 42.21.0
single-player. The investigation records retain their 0.26.85 filenames and
run identities because testing preceded the release-label change.

## Included work and evidence

- [Cleaning mixtures](validation-cleaning-mixtures-0.26.85.md): stored mixture
  reuse, measured native preparation, exact loans, interrupted-transfer
  reconciliation and cleaner exclusion from other water uses. Final native
  acceptance passes 146 checks with 25 stain removals across stored mixture,
  sink preparation, tainted-water preparation and undiluted fallback cases.
- [Base job latency](validation-base-job-latency-0.26.85.md): retained carried
  watering cans, exact interaction tolerances, assigned-work arbitration and
  furniture-aware barricade work positions. Controlled watering, burial and
  barricading pass; natural indoor route delays remain separately documented.
- [Low-table bed exits](validation-bed-exit-low-tables-0.26.85.md): verified
  same-room exits, original actor/items retained and furniture left present.
- [Combat targeting investigation](validation-combat-facing-0.26.85.md) and
  [movement follow-up](validation-movement-facing-doorway-0.26.85.md): retained
  native aim, facing before animation, bounded turn waits and first-input
  consumption under delayed frames. The final doorway/bed run passes 60 checks:
  four bounded steps cross the recorded threshold under simulated 350 ms
  delay, then normal navigation reaches the original goal in 36.263 seconds.
- Terminal expedition station menus, launch preparation and stale map/menu
  callbacks require a computer inside the active camp. UI regressions cover
  both camp and outside terminals.

The latest normal-play log remains installed 0.26.84. Its entire 7 minute
35 second doorway episode was not replayed verbatim; controlled delay matching
its accepted-input/no-motion symptom fails before the consumption fix and
passes afterward. Original saves and installed game files are unchanged.

## Known limits

Combat-facing jitter is **not fully resolved**. The final three front-approach
2-vs-3 trials, with multi-hit off, produce **5/6 survivors and 7/9 kills**.
The pressured final trial still has frequent target and movement-owner
handoffs. A separated stay-order fighter in the first trial records no active
combat samples. These are mixed live results, not clean combat acceptance.
No blanket target lock, damage change or attack delay was added to conceal it.

The controlled doorway pass does not certify every natural multi-room camp
route fixed. The earlier front-window travel and during-drag reports retain
their stated reproduction limits. Cleaning action acceptance uses adjacent
native supplies and is not a camp-wide unattended routing benchmark.

## Payload and release verification

- Bridge protocol remains `42.21-isocompanion-26`.
- Native bridge SHA-256:
  `994e76205dac4234a09c06d1fc7938ca017086ef941026c8610c88960ad468de`.
- The final native doorway/bed run uses that exact bridge. Combat handoff
  trials use the preceding bridge; the last bridge adjustment only enforces
  explicit endpoint deadlines, covered by native regressions and the final
  doorway run. Exact run hashes and distinctions remain in the linked records.
- Stable world key/schema remain `SC_WorldV1` / 3. Cleaning progress uses
  optional existing job data and retains older loans/saves.
- Before the label change: **92/92 core suites** and **29/29 full project
  stages** pass, including source compilation, ownership, persistence,
  gameplay, UI, installer transactions and both package formats.

- Release-label verification: `scripts/Test-Project.ps1 -Jobs 4` passes
  **29/29 stages** after the version bump (`PROJECT_TEST_PASS`, 149 seconds).
  Log: `build/release-0.26.86-project-gate.txt`. Both Workshop and standalone
  packages validate as 0.26.86; release identity, normal/debug Lua compilation,
  native bridge reproducibility and installer transactions pass.
- Standalone package SHA-256:
  `7aed3429cd85cce8e5f4990416ea22eeae77cf660e24137d02ac6324dd85490f`.

This request covers a Git commit and branch push; it does not install locally
or upload the Steam Workshop item.

## Review fixes, 1 November 2026

A review of the record above found the following before any upload, so the
version stays 0.26.86. The bridge's code did not change, but the protocol moves
to `42.21-isocompanion-27` because the 0.26.85 and first 0.26.86 bridges share
protocol 26 and differ in behaviour: a stale copy would otherwise load silently.
Its manifest also read 0.26.85.

| Problem | Fix |
| --- | --- |
| Assigned work (78) and cleaning with borrowed supplies (86) carried none of the danger checks `settlement` has. A worker kept working with a zombie inside 4.5 tiles (combat 72) and ignored the camp alarm (64-70) until something was in attack reach. The record above says combat kept its priority; its tests only tried a zombie already attacking. | Both now need a quiet camp and no alarm. Assigned work moves to 76, above routine shelving (74) and below the lowest rescue (78). |
| A worker lost while mixing left the old batch on the job with no receipts. The next worker failed it with `cleaning_loan_missing` every time, and `auditCleaning` queues nothing while a cleaning job is open, so automatic cleaning stopped for the whole camp until the player cancelled. | Recovery forgets the batch, and a batch nobody holds a receipt for is planned again, which also frees a save already stuck. |
| A water job named for the farmer carrying the can could outlive that farmer. Nobody else may claim a named job and `openJobAt` refuses a second job on the plot, so those crops stayed dry until the farmer came back. | The farm audit reopens the job if that farmer leaves duty or camp, changes role, dies or loses the can. |
| Removing the passable-furniture path left a window with furniture on both sides unboardable. Its controlled pass deleted the bench from the clone. `canStand()` accepts solid-transparent furniture beside a window, so it proved nothing. | The worker stands beside the furniture or one tile back and reaches across, on the same side. `ISBarricadeAction` has no reach limit, the stock `AdjacentFreeTileFinder.FindWindowOrDoor` falls back to neighbouring tiles the same way, and `IsoBarricade.GetBarricadeForCharacter` reads the side from the worker's row or column. Full-height furniture and walls are still refused, and the readable pause remains when no tile qualifies. |
| A work order scores 62, below routine shelving at 74. A barricade worker with the job in hand shelved logs, pasta and a pillow for minutes. This, not indoor routing, was the "shuffling around 12031-12032,6746" and the "no plank by five minutes" recorded above and in the [base job record](validation-base-job-latency-0.26.85.md). | Routine shelving no longer interrupts a work order, as it already could not interrupt Stay or Guard. Real overload still does. |

Local paths in the 0.26.85 records were replaced with placeholders.

Each fix has a regression test, and each was reverted in turn to confirm its test
fails (14 controls, all red, files restored by hash).

Live evidence uses clones of the Rising save at the reported window 12034,6748,
with the counter inside and the outdoor seat left in place (the base job record
calls it a bench; the screenshots show a white garden chair). The save moved on
since the runs above: Sanghwa is now on infection watch and takes no jobs, so the
probe picks a free resident instead, here Xian. The probe no longer expects the
window to block.

| Run | Source | Result |
| --- | --- | --- |
| `SC-Harness-20261101-091547-a2184be3` | Unfixed 0.26.86, natural (worker Sanghwa, who takes no jobs) | No plank in five minutes. First water 27.9 s. |
| `SC-Harness-20261101-090010-17c77e65` | Reach only, natural | First plank 246.8 s, after the shelving trips. |
| `SC-Harness-20261101-090906-80feed87` | All fixes, natural | **First plank 13.8 s**, from the kitchen tile 12034,6746 behind the counter, all four planks on, no furniture moved. First water 107.5 s. |
| `SC-Harness-20261101-085247-f600b7f1` | Reach only, staged | First plank 245.3 s from the same tile, all four within about 20 s of it. |

Engine screenshots from the natural and staged runs show the worker behind the
counter at the window, with the chair still outside. The planks are on the inside
face, so they do not show from the outdoor camera.

These are not a clean probe pass. `latency_burial_progress` still fails in all of
them, unfixed 0.26.86 included: Jill is tired in this save and sleeps through the
run, so no burial is attempted. First water is slower in the fixed runs, most
likely because Xian is now boarding the window instead of being free to water,
and Tess rests first; that difference was not isolated. The worker did not walk
outdoors, so the outside reach tile is covered by regression tests only.

Still open: routine shelving also outranks a camp alarm at contact level (74
against 70) for a resident with surplus to shelve. That predates this release.

`scripts/Test-Project.ps1 -Jobs 6` passes **29/29 stages** in 142 seconds
(`PROJECT_TEST_PASS`). The protocol-27 bridge has SHA-256
`fcf624cb4220d6806229e504a46e93a37a6d128d76f6cdcccd7e5e942568ac4c`; the live runs
above use it through an isolated source bridge, except the unfixed baseline. Not
installed locally or uploaded to the Workshop as part of this work.
