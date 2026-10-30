# Rosewood firestation rest and sleep

Behaviour validation for 0.26.82, following `d8e44533`. Live runs used the code
before the release metadata bump, on `living_fellows/0.26.81`.
Project Zomboid 42.21.0 single-player; Living Fellows alone with its rebuilt
native bridge. Final release checks are in [0.26.82 validation](validation-release-0.26.82.md).

## Findings and changes

- The original beds exist in both west upstairs bedrooms. Their hospital-bed
  sprites have complete two-tile mattresses, but SeatingManager reports `W`
  against a one-by-two grid whose tile Facing is `S`, or `N` against a
  two-by-one grid whose Facing is `E`. The previous normalization searched the
  wrong adjacent square and rejected every segment as a missing bed half.
- Entry now reconciles those verified physical grids with their tile Facing,
  using an adjustment scoped to the one native bed action. Missing halves and
  blocked entries remain invalid.
- An upstairs bunk exposed a second problem: the stock head-side entry clip
  could step beyond the floor and drop the actor downstairs. A head boundary
  now requires a clear foot entry. Unsafe head clips are not used as fallback.
- Deployed sleeping bags are recognized. Sleep selection prefers ordinary
  beds, then sleeping bags, then native sleep-capable couches. Ordinary chairs
  remain seats. Couch occupancy and whole-furniture claims remain protected.
- Backup receipts come from the existing bounded discovery passes, rather
  than separate scans for each tier. Cached receipts are revalidated and expire
  normally; occupied or removed objects cannot remain permanent choices.
- Native lying poses on these two-tile surfaces also required visual alignment.
  The bridge validates the exact owned sleeping actor, selected object and
  complete loaded mattress, then centers the rendered pelvis on that mattress.
  Physical coordinates, square membership, path ownership and player slots
  remain unchanged. The render adjustment is thread-scoped and clears on exit.
  The existing double-bed pillow handling is retained.

## Catalogue audit

The live audit examined 61,319 loaded sprite definitions. All 316 semantic
sleep-surface tiles were accounted for:

| Category | Tile variants | Result |
| --- | ---: | --- |
| Beds, including bunk, twin, hospital, stretcher and large beds | 108 | Recognized |
| Deployed sleeping bags, 11 styles and their facings | 88 | Recognized |
| Couches, 15 styles and their facings | 120 | Remain seats; eligible as sleep backups |

This is classification coverage, not live animation acceptance for every
individual variant. Packed sleeping bags are inventory items, not deployed beds.
One placed bunk unit retains one furniture claim; separate upper/lower bunk
occupancy was not added.

## Native acceptance

Run: `SC-Harness-20261030-200616-940e22c3`.
The canonical Rosewood building was loaded near `(8140,11738)`, with native bounds
`8122,11726` to `8158,11751`. Its walls, stairs and portals were retained.
Each companion spawned downstairs at `(8156.5,11737.5,0)` with native fatigue 1.0.
All 36 ordinary door objects in this instance were confirmed closed before
each trial. The two original upstairs bedrooms were tested first; only then
were bed pieces changed in the disposable clone to force backup-surface use.

| Trial | Arrival and sleep | Native pose |
| --- | ---: | --- |
| Inner west bedroom, original hospital bed | 31 s | OnBed / asleep |
| Other west bedroom, original hospital bed | 28 s | OnBed / asleep |
| Deployed sleeping bag | 31 s | OnBed / asleep |
| Backup couch | 32 s | Sitting on furniture / asleep |
| Bunk bed at an upstairs exterior boundary | 30 s | FootLeft entry, OnBed / asleep |

All five reached the intended upstairs room, retained health through entry,
and recovered fatigue during six seconds of observed sleep. The lying models
were checked in native screenshots after settling; the couch retained its
supported seated pose. Each trial then cancelled sleep through normal cleanup,
verified awake/standing state, and removed its fixture actor. Natural overnight
waking was not simulated in this pass.

The engine selected an available stair route and opened one recorded door on
each measured trip. This does not prove the tester's exact three/four-door
sequence: their save, placed objects and lock states were unavailable. A separate
production-Lua diagnostic passed a six-door route search and a simulated
two-floor native-lease progression lasting 64 seconds; native stair motion was
simulated in that diagnostic, unlike the real-world acceptance above.

Logs, catalogue output and original screenshots are retained under the ignored
`build/live-sandbox-runs/` and `build/firestation-route/` directories.
The source save's 3,430 files match their recorded pre-run SHA-256 hashes.

## Regression checks

- Four-direction hospital normalization, missing halves, model direction
  isolation, upstairs head boundaries and blocked foot entries.
- Bed/bag/couch preference, occupied fallback replacement, bounded empty surveys,
  native numeric seat counts and couch occupancy.
- Native render offsets remain isolated from physics, concurrent reads and
  other actors; the bridge rejects missing or unowned actors.
- Strange Folk head-entry fixtures now explicitly supply the loaded room floor
  required for their expected safe head clips. Their asserted entry coordinates
  and authored behaviour are retained.

The pre-version-bump project gate passed **29/29 stages in 162.7 seconds**. Log:
`build/firestation-route/project-gate-clean.txt`. The bridge used for live acceptance
SHA-256 is `0e4b3dedabf510f5530a8d10e5d03f4565d928db5b6592524df064ff6f033907`;
its existing protocol remains `42.21-isocompanion-24` with a guarded optional
sleep-model alignment method. Lua and the rebuilt native payload must ship together.
