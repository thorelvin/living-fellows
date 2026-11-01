# Companion cleaning mixtures

Implementation and validation on `living_fellows/0.26.85`, based on
`9f49ffcc847b9674cbdffc1d59c337d98aa49ff3`. This work includes existing, uncommitted
base-job latency fixes; those changes are documented separately in
`validation-base-job-latency-0.26.85.md`.

## Behaviour

Floor and wall jobs first look for a usable mixture in the worker's inventory,
bags and permitted marked storage. Fluid components determine eligibility;
container names do not. Existing player mixtures keep their concentration.

Otherwise, a compatible bucket receives one cleaner type at 5% with 95% water,
normally two litres. Tainted water takes priority, then nearer compatible water
sources. Stock, container capacity and combined native encumbrance can reduce
the batch. Unknown contents, two different cleaners and ordinary soap bars are
excluded. No liquid is discarded to make room. Undiluted cleaner remains an
explicitly announced fallback when a usable batch cannot be prepared.

The native `ISFluidTransferAction` and capped `ISTakeWaterAction` perform all
fluid transfers. Native `ISCleanBlood` removes stains and consumes the mixture.
There are no additional scripted ingredient or cleaning deductions. Every
transfer instance validates the exact living, registered LF body, donor and
receiving bucket. There are no global action wrappers or player-slot changes.

The existing job saves optional preparation stages, fluid checkpoints and exact
item loans. Reload compares current quantities against those checkpoints;
ambiguous quantities stop for review. Borrowed items return to their permitted
source; personal equipment stays with its owner. Cancellation and retirement
cover all four receipt kinds. Genuine supply shortages retry after three minutes
and retain manual Retry. A water approach with no positional progress for thirty
seconds settles its loans and tries another source or the allowed fallback.

Discovery retains its cursor across calls, shares a camp allowance of 64 items
and four containers per 100 ms work slice, checks the maintenance budget and
uses a further one-millisecond deadline. Fixed-source searches retain bounded
32-square slices. Exact live loan identities are cached so native validity
polling does not repeatedly search whole shelves. The module installs no events
or background service.

Cleaner-containing fluids are excluded before water/name heuristics in needs,
hydration refills, farming, cooking and vehicle upkeep. Vehicle washing itself
still uses water only.

## Automated verification

- `tests/core/cleaning_mixtures_harness.lua`: **369 checks pass** in the pinned
  Kahlua runtime. The harness exercises real BaseLife/BaseWork admission, claims,
  receipts, save restoration and cancellation, with explicit fluid/native-action
  fixtures.
- Coverage includes both cleaners and both water types, late stored mixtures,
  partial/full buckets, incompatible and locked containers, protected stock,
  disabled withdrawals, combined carry limits, competing workers, partial pour
  and fixed-source fill reload, contradictory debits, retirement, repeated
  cleanup and no-progress water approaches. Native-adapter tests check exact actor/donor/bucket guards,
  capped fill quantities and duration, mid-action contamination by a second
  cleaner, and hand restoration.
- A 13-shelf fixture instruments actual inventory reads and storage access:
  every discovery slice remains within 64 items/four containers and eventually
  finds the last-shelf mixture. An exhausted maintenance budget performs no
  item discovery.
- Decision arbitration covers cleaning settlement versus optional loadout work,
  overload, danger, bleeding and a new Follow order. Queued cleaning bypasses
  ambient frequency limits; opportunistic downtime cleaning keeps its cooldown.
- The downtime candidate checks for a stain before discovering supplies. A clean
  tile triggers no supply lookup.
- `scripts/Test-Project.ps1 -Jobs 6`: **29/29 stages pass**. This includes
  cleaning, persistence, ownership, farming, vehicle upkeep, performance,
  gameplay, UI, source compilation and both release packages. Final gate log:
  `build/cleaning-project-gate-final-5.txt` (`PROJECT_TEST_PASS`, 123 seconds).

## Native acceptance

Disposable PZ 42.21.0 single-player clients use the unchanged native bridge and
only LF. The seed is the retained four-companion clone
`build/live-sandbox-runs/SC-Harness-20261031-213036-485701ec/cache/Saves/Rising/SC-Harness-20261031-213036-485701ec`.
The original player save is not edited.

The fixture stages a worker once at a clear, shared access tile beside a real
water fixture and native storage. Existing gear and stock are retained in a
native holder. Ordinary hunger/thirst/fatigue values are set at case setup;
health and damage remain active. The observer's pre-existing heavy load lowers
its health to approximately 75. During the measured cases, the harness holds
unrelated decisions and services the real BaseWork controller. Navigation,
storage transfers, native timed actions, stain removal and fluid accounting
are not replaced. This is controlled controller acceptance, not an autonomous
camp-wide routing benchmark.

`SC-Harness-20261031-234157-4b955375` completed eight stored-mixture cleaning
actions, returned the same native items, released their markers and left the
control concentrate untouched. Its subsequent fixed-source case failed because
the initial classifier used the inventory-item water API for a world object.
That classifier now uses native `IsoObject.hasWater()` with component checks.

`SC-Harness-20261031-235012-ce72f061` then recognized a real bathroom water
fixture, but hit the previously documented indoor route stall before filling.
This led to the bounded no-progress fallback and an adjacent native fixture for
the remaining action acceptance. The separate natural indoor routing failure
remains open; automated passes do not certify that route.

Final native run: **`SC-Harness-20261031-235510-c6d1d500`**, **PASS**, 146 checks,
zero failures or skips. It completed 25 native stain-removal actions.

| Case | Native cleans | Concentrate spent | Water spent | Final mixture |
| --- | ---: | ---: | ---: | ---: |
| Automatic bleach batch from real sink `fixtures_sinks_01_4` | 8 | 0.100000024 L | 1.9 L fill | Empty |
| Cleaning Liquid plus stored tainted water | 8 | 0.099999994 L | 1.899999976 L | Empty |
| Stored 5% mixture | 8 | 0 L added | 0 L added | Empty |
| Undiluted fallback | 1 | 0.249989986 L | 0 L | No prepared bucket |

Both prepared batches measured two litres with approximately 0.1 L cleaner
before use. The same native containers returned to the marked source and all
their receipt markers were released. The stored-mixture control bottle remained
untouched. No native cleaning dose was supplemented by a scripted deduction.

Evidence: `build/cleaning-live-acceptance-14.txt` and the retained run's
`cache/Lua/SurvivorCompanionHarness/events.log` and `summary.txt`. The native
payload differs from the final source only in two subsequent negative guards:
skip discovery for an unstained tile, and reject contamination by a second
cleaner during an action. Those guards are covered by the final automated gate;
they do not change the valid one-cleaner cases measured above.

Installed vanilla source SHA256 fingerprints:

- `TimedActions/ISCleanBlood.lua`:
  `794436d74b88f4fe6d231b8e00befd27c3f22485ec650b9767e0760712fea3aa`
- `Fluids/ISFluidTransferAction.lua`:
  `9534d2a46ff06d425a0aa89f63c776f118bcdd36a39905748b7c7dfd1f771190`
- `TimedActions/ISTakeWaterAction.lua`:
  `48aa88c32d2e387897ea7a7696d410ae33517bcf75f2edec3837e090cb3a3456`

## Scope and reproduction

```powershell
& ./scripts/Invoke-LiveSandboxTests.ps1 `
  -ProjectRoot <worktree> `
  -SeedSave <worktree>/build/live-sandbox-runs/SC-Harness-20261031-213036-485701ec/cache/Saves/Rising/SC-Harness-20261031-213036-485701ec `
  -GameMode Rising -LivingFellowsOnly -CleaningMixturesProbe `
  -EngineSound -NoSteam -IsolatedSourceBridge -HiddenWindow -TimeoutSeconds 1500
```

The runner requires accounting proofs for all four cases before accepting a
PASS. A bootstrap-only success cannot stand in for cleaning acceptance.

This is a Lua change. The bridge remains protocol `42.21-isocompanion-26`,
SHA256 `3890f8df4f6f48cd2c517b1a0ec1cb13164f978fa5e304b27213ff0eb023e729`.
No commit, push, version bump or local installation was requested for this work.
