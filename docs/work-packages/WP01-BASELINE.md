<!-- SPDX-License-Identifier: MIT -->

# WP01 baseline — dependable gathering and delivery

## Frozen starting point

- Commit: `11625c06050a4ed8d24ba02598c380bc61b5d039`
- Release metadata: `0.22.18`
- Game contract: Project Zomboid `42.20.4`
- Working tree at intake: clean
- Full deterministic project gate at the same revision: `PROJECT_TEST_PASS`

This record describes the code before WP01 changes. It is evidence for the
work-package comparison, not a release claim for the resulting dirty tree.

## Existing reusable boundaries

- `SCBaseLife` already persisted camp-area and work zones, exact registered
  storage object references, residents, duty state, finite jobs and completed
  job history.
- `SCBaseObjectRef` already resolved storage through a persistent object ID and
  rejected unloaded, missing and ambiguous native objects.
- `SCBaseWork` already dispatched camp jobs and could haul, sort and fetch real
  items between registered containers and a worker inventory.
- `SCGameplayUtil.transferItemVerified` and `takeWorldItemVerified` already used
  exact list membership as the success receipt for container and floor moves.
- `SCPersistence` already owned world-scoped Global ModData and an exact item
  snapshot/reconstruction codec used by trade recovery.
- The scheduler already provided bounded base-maintenance pulses, and the Base
  view already exposed zones, storage, duty and ordinary job management.

## Missing behavior

There was no finite player-created gathering order and no `gather_materials`
dispatcher path. A companion could not scan a selected camp work zone for
existing floor logs or planks, reserve one exact wrapper, visibly collect it,
and deliver it to one selected registered container.

Ordinary hauling also used the general verified transfer helper directly. It
did not have a durable cargo receipt spanning selection, world removal,
carrying, destination insertion, save/restart, cancellation and actor
retirement. Existing destination stock was therefore unsuitable as proof of
new work completion, and ambiguous mid-transfer ownership had no work-specific
quarantine record.

## Baseline performance controls

The starting configuration bounded camp storage scans to 220 squares and 80
items, base job state to 64 records, and base job retry to 10 seconds. The core
response harness covered 1, 4, 8 and 16 actors, but there was no gathering scan
frontier, per-slice gathering budget, persistent recovery cursor or gathering
throughput diagnostic.

## Verified integration contracts

- Base jobs enter through `enqueueJob`/`claimJob`, renew through `touchJob`, and
  leave through `releaseJob`, `cancelJob` or `completeJob`; BaseWork is the sole
  production dispatcher. Duty-off releases a claimed job before normal control
  resumes.
- For floor items, `SCGameplayUtil.takeWorldItemVerified` owns the mutation and
  verifies the exact wrapper/link/placement. For container moves,
  `transferItemVerified` owns removal, insertion and rollback. WP01 places an
  effect-free owned loot visual before exactly one such mutation.
- The supported 42.20.4 JAR exposes
  `ItemContainer.hasRoomFor(IsoGameCharacter, InventoryItem): boolean`, plus
  `AddItem(InventoryItem): InventoryItem` and `Remove(InventoryItem): void`.
  These signatures are reflected by the core native contract gate.
- The existing persistence codec captures a bounded inventory schema and can
  reconstruct one detached root with build/identity markers. The live native ID
  is supporting evidence; a persistent logical receipt token is the restart
  identity. Trade marker names remain private to trade.
- Production loads through `SCBootstrap.lua` and `SCRuntime.lua`. The gameplay
  and core runners enumerate their Lua inputs; the new coupled work fixture must
  therefore be added explicitly rather than relying on a global test import.

## Baseline commands and evidence

- `scripts/Test-Project.ps1`: `PROJECT_TEST_PASS` at the pinned clean baseline.
- Installed script inspection: `Base.Log` has weight 9 and `Base.Plank` has
  weight 3; both exact full types exist in the supported game data.
- The first implementation core run reflected the capacity/add/remove
  signatures above against the same pinned 42.20.4 runtime. System `javap` could
  not read class-file version 69, so no result was inferred from that failed
  tool; the repository's game-runtime Java gate supplied the native evidence.

## Scope accepted for WP01

WP01 adds physical gathering only for installed script types `Base.Log` and
`Base.Plank`, only from existing world items inside an approved camp work zone,
only to an exact registered deposit container, and only for a finite requested
quantity. It does not add remote work, synthetic output, corpse/container
omniscience, broad production chains, multiplayer authority or a new release.
