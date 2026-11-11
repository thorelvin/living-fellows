<!-- SPDX-License-Identifier: MIT -->
# WP04 sheep: native evidence on 42.22.2

Implementation: `living_fellows/0.27.9`, based on 0.27.8 `7c3f2d21`.
Pinned game JAR SHA-256:
`3c4a7c5f149d784758c6fb5f8fa85f3a21d572e38bc081400e89035f8120d287`.

## Installed contracts

Inspected installed SheepDefinitions, the stock shearing/milking actions and
targeted IsoAnimal/AnimalData/behavior bytecode, using Java 25 for the game's
class-file version. No proprietary implementation is packaged.

- Ewes, rams and lambs use Suffolk, Rambouillet and Friesian breeds. SheepMilk
  and Base.WoolRaw are the native outputs. Adult enclosure minimum is 40 tiles;
  lamb minimum is 20. Animal feed, grass and hay are suitable donations.
- `ISShearAnimal` owns animation, sound, elapsed increments and the sheep's
  movement hold. Each native `shearAnimal` call debits one fleece unit and
  drops a real item on the animal's square, applying native wear/charge/XP.
- A non-debug `setWoolQuantity` refuses updates below age 200 even when an
  animal reports adult. Production refuses those young animals rather than
  relying on an unsafe debit. Native genetic maximum and eligibility are used.
- The stock force-stop path can leave sound running. Instance-owned cleanup
  releases sound, pose and movement on completion, error, cancellation and
  claim retirement. Another worker's claim is never cleared by stale cleanup.
- Electric shears are explicitly identified by native item type/class; the
  legacy `IsDrainable` probe alone is insufficient on this runtime.

Installed source fingerprints:

| Source | SHA-256 |
| --- | --- |
| `TimedActions/Animals/ISShearAnimal.lua` | `d13bb4e84c831e4e408730904a5d2df05317612549b59da4e54264a3852a3997` |
| `Definitions/animal/SheepDefinitions.lua` | `03ebdb608d6347811d11ee3bc19ec62a9d63ecd75811250c3dde2b8b58109b27` |

## Implementation and automated checks

Sheep reuse the existing farm pulse, bounded audit, device claims, supply loans
and 128-receipt ledger. There is no new service, role, area, storage category,
schema version or bridge protocol. The native JAR rebuild changes release
metadata only; protocol remains `42.22-isocompanion-31`.

Essential Behaviour extends the existing animal/receipt fixtures: sheep kinds,
young/held/story/stressed animals, daylight/full-fleece thresholds, native tags,
broken/depleted tools, ewe reserves and daily limits, exact floor item receipts,
ambiguous-output refusal, carry/storage/ledger limits, competing claims and
storage reservations, cancellation return, dead-carrier floor preservation,
progress counts and save normalization. Existing cattle/chicken groups remain.
The focused run `20261111-095736-6d067b` passed before final polish; the release
gate below is authoritative for the finished tree.

## Real cloned-save runs

One isolated, low-priority game was run at a time. Original saves and the
installed launcher were untouched. Starting fleece, lactation and test supplies
were controlled fixture inputs, not claims about natural daily breed yields.

- `SC-Harness-20261111-092623-8ce7413f`: mixed chicken/sheep pasture extending
  five tiles beyond camp. Native water reached approximately 1.8 L and feed 10;
  an exact egg was delivered. A Friesian ewe delivered SheepMilk container
  **1575078999**, **1.700000286 L**, to Fresh food with no remaining marker.
  Manual shearing produced **9** verified raw-wool items, delivered them and
  returned the borrowed shears. A pickup interruption recovered after retry;
  it motivated a bounded animation-retirement grace and owned visual tokens.
- `SC-Harness-20261111-093845-64e83c9b`: three breeds in a real grass pasture
  with wooden fencing and mixed chickens. A native lamb/mother association
  confirmed the **0.8 L reserve in a 2 L udder**. At Husbandry 0, electric
  shearing saved with wool **738846923** carried and **five** exact pending
  wool receipts, including four floor drops. Battery charge was **0.990000069**.
- `SC-Harness-20261111-094639-c52b8fba`: actual restart of that checkpoint.
  All five saved native IDs reached storage exactly once. All three shearing
  jobs completed; **13** wool items were stored in General while Crafting was
  full. The exact electric tool returned unprotected with charge **0.974000037**.
  No sheep-work exception or unexpected animal-job blocker occurred.

Every detected blocker has a zoomed-out framebuffer capture in its
run's `cache/Screenshots` folder.

## Corrections found during acceptance

The first sheep fixture used age 180 and correctly could not set fleece; the
production age guard now prevents an un-debited native drop. General fallback
initially used the wrong category key and was corrected to `general`.
Cancellation exposed a missing normal-work state; it now uses the existing
exact cancellation-return helper. The final manual/electric comparison exposed
the runtime's missing legacy drainable probe, corrected with explicit type/class
classification. Private fixture failures (collection iteration and premature
lighting probes) are not counted as passed gameplay scenarios.

The cloned source save also emits pre-existing map-meta/basement warnings during
loading. Those are separate from LF gameplay exceptions. Live death/corpse
recovery at every possible frame, natural seasonal fleece growth, third-party
animal definitions and long-duration herd simulation are not claimed here.

## Final release verification

- `SC-Harness-20261111-100827-bf719209` passed on the finished 0.27.9 Lua
  worker/action/receipt tree. Full Crafting and General storage produced the
  expected blocker with **no fleece debit**. Manual Retry then used native
  `Base.SheepShears` **97805213**, preferred over available electric shears.
  Cancellation occurred while the native action was active, after **one** real
  drop; fleece remained **3.808640957**. The exact borrowed tool returned to
  its source, all output reservations closed, the pose/action cleared, and
  the sheep stayed healthy. The expected storage blocker was photographed.
  No LF gameplay exception occurred. SHA-256 comparisons confirm this run's
  SCAnimalShearing, SCAnimalWork, SCFarmWork, SCNativeActions and SCBaseLife
  exactly match the final source files.
- `scripts/Test-Project.ps1 -Serial -Release`: **5/5 PASS**, **254.9 seconds**,
  **23** serial JVM launches, 256 MB heaps/two processors. Evidence:
  `build/test-results/20261111-101118-14bb5d/summary.json`.
  All **16/16** installer ownership/rollback transactions passed.
- Standalone packaging validated **0.27.9**, **debug=false**, **dependency=false**.
  Archive `build/release/LivingFellowsCompanion-0.27.9-STANDALONE-WINDOWS.zip`,
  SHA-256 `ba56e9c45e592f85319741c1bb78aa46aae6cfafef06c55bf3f1e153e8c4278f`.
  Bridge SHA-256 `8c85cd9a5d3a2b1ff8f2953360853c33f237d63a287e3732f57f08c630a7b9e8`.
- Sheep care, shearing and ewe milk defaults are enabled after native acceptance.
  The Field Guide and quick reference were rebuilt at 0.27.9, including
  `ch15_sheep` and a real wooden-fenced grass-pasture photo. The 600×380 image
  is a lossless crop of this passing run's native shearing frame, without
  repainting. Original PNG SHA-256:
  `6daa1cdff428729122a184fc2db2e64364facb5fa895a423f4747c3caab5e75e`.
  Guide sources remain in `C:/ZOMBOID/field-manual-src`; local HTML and web
  staging validate 118 images and 93 IDs. Publication is a separate operation.

All owned native game and gate processes exited. The user's installed game and
original saves were not modified by these acceptance runs.
