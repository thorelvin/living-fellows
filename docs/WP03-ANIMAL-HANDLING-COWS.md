<!-- SPDX-License-Identifier: MIT -->

# WP03 — automatic animal handling: cows

## Handoff

**To:** Codex. **From:** Thor. **Base:** Living Fellows 0.27.7, Project Zomboid
42.22.2.

**Goal.** A resident with the Farmer role looks after the camp's cattle with
no player setup beyond a vanilla animal zone and marked storage: feed, water
and daily milking, with the milk delivered to food storage. This extends the
chicken work shipped in 0.27.7; it does not replace or loosen any of it.

**How to run this.**

1. Read, in this order: `docs/WP02-ANIMAL-HANDLING-CHICKENS.md`,
   `docs/animal-native-probe-2026-11-09.md`, `SCAnimalWork.lua`, then the
   animal sections of `SCFarmWork.lua` and `ARCHITECTURE.md`. Everything WP02
   says about conventions, ownership, scheduling and persistence still applies
   and is not repeated here.
2. Work on a new branch `living_fellows/<next version>`; bump `VERSION.txt`
   and add the changelog entry as part of the last phase.
3. Implement Phases 0–4 in order, in one run. Do not wait for review between
   phases. One commit per phase, with `scripts/Test-Project.ps1` green before
   each commit.
4. Use the live harness whenever a native fact needs it, as in WP02. Ask Thor
   only for what the harness cannot settle, in the LIVE TEST form from WP02.
5. Finish with the final report described in WP02, plus the cow-specific items
   under "Final report additions".

**Rules that override everything else here.**

- Phase 0 decides what is real. The cow facts below come from public guides
  and the wiki, not from the installed game. Where 42.22.2 differs, follow the
  game and record the deviation in the probe doc.
- Unproven means off. Each phase has its own config key and ships disabled if
  its native calls or live acceptance are missing.
- Chickens must not regress. Every existing chicken test stays green, chicken
  defaults stay unchanged, and chicken-only zones behave exactly as in 0.27.7.
- Reuse before adding. Cows are a second entry in `A.species` plus one new
  chore. No new role, area type, storage category, UI screen, `OnTick`
  callback or bridge protocol change.
- Nothing irreversible. This package never kills, butchers, moves, leads,
  ropes, picks up, spawns or modifies an animal.

**Definition of done.** Every phase's "Done when" holds, the five essential
checks pass, `docs/animal-native-probe-<date>-cows.md` exists, docs are
updated, and any phase left disabled is named in the final report.

## Scope

Shipped 0.27.8 refinement: chicken and cattle pens may extend up to 30 tiles
beyond camp, using the same bounded work reach as crop fields. The complete
enclosure, devices and interaction sides must remain in reach. This supersedes
the original inside-camp-only requirement below; supplies still come from
permitted marked storage.

- Build 42 single-player, pinned game version from `tests/core/pz-runtime.json`.
- Species: cattle — cow, bull and calf of every vanilla breed.
- In: feed troughs, water troughs, milking, milk delivery, herd census.
- Out: culling and butchering, butter and any milk processing, breeding
  management, moving or leading animals, trailers, petting, manure, sheep and
  other milkable species, multiplayer.

## Background (to verify in Phase 0)

Public sources for Build 42.20–42.22 report the following. Treat each as a
hypothesis until proven on the installed build.

- Calves become adults at 180 days. Pregnancy is 280 days by default and
  scales with a sandbox setting. Cattle breed without a mating season when a
  bull shares the connected zone. Breeding needs no player action.
- A cow lactates around pregnancy and birth. Milking needs a compatible fluid
  container (bucket, pot or similar) in the milker's inventory.
- Daily yield and udder capacity depend on breed genes: roughly 6–7.5 L a day
  for a Holstein, 0.5–2 L for an Angus.
- A cow that is neither milked nor nursed stops producing after some days.
  Regular milking raises capacity; a persistently full udder harms the cow.
- Stress can interrupt milking and spill the container. Animal Care skill
  reduces the chance.
- A calf nurses only inside its mother's zone.
- Cattle eat from troughs (hay, cut grass, animal feed, vegetables, fruit) and
  also graze. An adult needs 80 tiles of connected zone, a calf 40.
- An unverified older guide says two bulls in one zone fight.

## Player contract

The player draws a vanilla animal zone around the pasture, places one feed
trough and one water trough, keeps cattle feed and an empty milk container in
marked `farming` storage, has a food storage with deposits enabled, and has a
Farmer. From then on a Farmer will:

- keep the feed and water troughs supplied;
- milk every lactating cow about once a day and carry the milk to food
  storage;
- leave milk for nursing calves.

A Farmer will never:

- take supplies from, or deposit into, a container that is not marked camp
  storage, or work in a zone outside the union of camp areas;
- touch a Strange Folk or Wendell animal (`lfOddballGroupId`,
  `lfWendellGroupId`), or an animal the player is holding or leading;
- pour milk into a container that already holds anything, or mix it with
  another fluid;
- milk a stressed cow, or work near a threat;
- harm, move or modify any animal.

Missing requirements (no empty container, no cattle feed, no food storage with
room, no water trough, zone too small for the herd) appear as blockers in the
Base view through the existing farm blocker path, with speech at most once per
cooldown.

## Milking policy (automatic)

No player input. Decided per cow on each complete audit, from native readings
only. Percentages are of that cow's current udder capacity.

- **No nursing calf in the zone:** open a milking job at or above
  `animalMilkStartPercent` (default 50) and milk the udder empty.
- **Nursing calf in the zone:** the calf comes first, because a calf that
  starves is a lost animal while lost milk is only lost milk. Open a job only
  at or above `animalMilkCalfStartPercent` (default 70) and stop when the
  udder is down to `animalMilkCalfReservePercent` (default 40). If the native
  action cannot stop at a measured amount, do not milk cows with nursing
  calves at all, and say so in the final report.
- **Welfare override:** at or above `animalMilkUrgentPercent` (default 80) a
  milking job outranks feed and water for that zone, with or without a calf,
  so a full udder never sits long enough to harm the cow.
- At most one milking per cow per game day, and one Farmer per cow.
- Skip a cow whose stress is above `animalMilkMaxStressPercent` (default 40),
  retry on the normal cooldown, and never queue a second attempt the same hour.
- Daylight only. A bull, a calf or a non-lactating cow is never a milking
  candidate.
- "Nursing calf" means a baby of the same species in the same native zone
  whose mother identity matches when readable; if mother identity is not
  readable, any calf in the zone counts for every lactating cow there.

## Work selection

Unchanged from WP02: Farmer role, shared candidate pool with crop work chosen
by the existing deterministic random helper. Within animal work the order
becomes: urgent milking, water, feed, chicken door jobs, ordinary milking, egg
collection, cleaning. Chicken door timing keeps its existing precedence over
optional downtime.

## Phase 0 — native probe

Record results in `docs/animal-native-probe-<date>-cows.md`, using the same
method as the chicken probe. Reuse everything already proven there (zones,
identity, trough feed and fluid transfer) without re-deriving it. Establish:

- cattle type strings for cow, bull and calf across breeds, and readable
  sex, age, baby state, pregnancy, lactation, mother identity and stress;
- udder readings: current milk, capacity, and whether "can be milked now" is
  exposed; the fluid type produced;
- the vanilla milking timed action: its name, arguments, whether it accepts a
  non-player character, which container it selects and how, how much it takes
  per cycle, whether it can be bounded to a measured amount, and what happens
  on interruption (spill, partial fill, stress);
- whether it silently substitutes another inventory container, as hutch
  cleaning did; if so, add the same instance-bound guards;
- which items count as cattle feed (`getAnimalFeedType` values for hay, cut
  grass, animal feed, produce) and whether trough admission differs by species;
- how a zone shared by chickens and cattle allocates troughs, and whether a
  trough's feed is visible to both;
- whether bulls or stressed cattle attack or knock down a nearby character,
  and whether the companion actor can be a target;
- whether the companion has a readable Animal Care skill, and what milking
  does at level 0;
- zone geometry for pastures larger than 256 tiles, and the cost of auditing
  them inside the existing square and animal budgets.

## Phase 1 — species generalisation

Make `SCAnimalWork` species-aware without changing chicken behaviour:

- add `A.species.cattle` with kinds, feeds and policy fields; replace direct
  `A.species.chicken` reads with a lookup by the animal's species;
- a zone may hold more than one supported species. Replace the single `mixed`
  flag with a per-species census; an unsupported species in a zone is ignored
  for work but still makes that zone's census incomplete for any irreversible
  decision. Hutch, egg and flock logic stays chicken-only;
- raise the zone tile cap for cattle zones to `animalCattleZoneMaxTiles`
  (default 1024) while keeping the per-decision square and animal budgets, so
  a larger pasture takes more slices rather than more time per slice;
- report "zone too small for herd" as an informational blocker when connected
  zone area is below the proven per-animal minimum. Do not act on it.

Done when: every 0.27.7 chicken test passes unmodified, and a zone holding
both hens and cows produces a correct census for each.

## Phase 2 — cattle feed and water

Extend the Phase 1 chicken trough work to cattle zones: same 25%/90% marks,
same borrow/receipt path, same separate feed and water troughs, same
`ISFluidTransferAction` water path. Cattle feed comes only from marked
`farming` storage and only from items Phase 0 proved compatible; human food is
not donated. A cattle water trough is large, so cap one job at
`animalWaterTripsPerJob` (default 2) donor trips and let the next audit
continue. No daily feed-rate guessing, as in WP02.

Done when: empty cattle troughs are refilled from marked storage with receipts
closed, and chicken troughs in the same camp are still served.

## Phase 3 — milking

- Borrow one empty, compatible fluid container from marked `farming` storage
  through the existing receipt path. Extend `FarmWork.isFarmingSupply` so an
  empty milk-compatible container deposited by logistics lands there. Prefer
  the largest container the actor can carry that the udder will not overfill.
- Follow the convention: select, reserve cow by stable animal id, approach,
  settle, animate with the native action, commit, verify, resume.
- Verify by measurement: litres gained in the exact container must match
  litres lost from the udder within the proven tolerance. A mismatch, a
  substitute container or an unreadable reading fails closed and pauses that
  cow until the next complete audit.
- On interruption or spill, keep the receipt on the container, record what
  was lost, and return the container (empty or part-filled) through the normal
  path. Never script milk in or out to compensate.
- Apply the milking policy above, including the calf reserve.

Done when, in the live harness: a lactating cow without a calf is milked once
a day into a borrowed container; a cow with a calf keeps its reserve and the
calf stays healthy across three days; a bull and a dry cow are never
approached for milking.

## Phase 4 — milk delivery

- Deliver the filled container to food storage with deposits enabled, using
  the WP01 transport postcondition. Use the existing fresh-food preference
  (`fresh_food` before `food`) so milk goes to refrigeration when the camp
  has it.
- The container stays in food storage with the milk; the player returns
  empties to `farming` storage, or logistics does once they are empty. Do not
  decant, combine or pour away milk.
- With no destination that has room, do not start milking unless the udder is
  at the urgent mark; in that case milk, keep the container on the receipt in
  `farming` storage, and raise the blocker.
- Cooks and other consumers treat delivered milk like any stored food; the
  work receipt is closed on verified deposit, as for eggs.

Done when: each milking ends with exactly one container in permitted food
storage and a closed receipt, including after a save/load mid-carry.

## Config keys

Add to the WP02 table. Defaults are starting guesses; tune from live play.

| Key | Default | Meaning |
| --- | --- | --- |
| `animalCattleEnabled` | 1 | Master switch for cattle work |
| `animalMilkEnabled` | 1 | Phase 3–4 switch |
| `animalMilkStartPercent` | 50 | Milk at or above this, no calf |
| `animalMilkCalfStartPercent` | 70 | Milk at or above this, calf nursing |
| `animalMilkCalfReservePercent` | 40 | Stop here when a calf is nursing |
| `animalMilkUrgentPercent` | 80 | Outranks feed and water |
| `animalMilkMaxStressPercent` | 40 | Skip the cow above this |
| `animalCattleZoneMaxTiles` | 1024 | Audited tiles per cattle zone |
| `animalWaterTripsPerJob` | 2 | Donor trips before yielding |

## Ownership, scheduling, persistence

As WP02, with these additions:

- the milk receipt records container identity, fluid type, litres before and
  after, cow stable id and game day; fluid is tracked by measurement on the
  receipted container, never as a separate item;
- per-cow last-milked day and per-zone census summary persist in the existing
  versioned `animals` section, additively; a missing field normalises to
  "never milked";
- cattle audits share the existing farm lane and the 2 ms frame target. Record
  audit timings for a chicken-only camp, a cattle-only camp and a mixed camp
  in the probe doc.

## Tests and documentation

- Automated coverage for: milking policy at every threshold with and without
  a calf, calf detection fallback, stress skip, one-per-day limit, container
  selection, measurement mismatch, spill recovery, mixed-zone census, the
  raised tile cap under budget, and receipt recovery after save/load.
- Live acceptance in the harness for Phases 2–4 as listed in each "Done when".
- Update `ARCHITECTURE.md`, `CHANGELOG.md`, `PLAYTEST-CHECKLIST.md` and the
  README. Shipped text and dialogue stay in English.

## Final report additions

- whether milking could be bounded to a measured amount, and what the calf
  rule became if not;
- measured litres per milking by breed in the test herd;
- whether bulls or stressed cattle posed any risk to a companion;
- what would be needed next for butter, sheep, and safe culling.
