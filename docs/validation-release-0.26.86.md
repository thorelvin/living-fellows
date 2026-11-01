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
