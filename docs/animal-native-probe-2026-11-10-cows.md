<!-- SPDX-License-Identifier: MIT -->
# WP03 cattle: native evidence on 42.22.2

Base: `living_fellows/0.27.7` at `e356777b`; implementation branch
`living_fellows/0.27.8`. The pinned game JAR is SHA-256
`3c4a7c5f149d784758c6fb5f8fa85f3a21d572e38bc081400e89035f8120d287`.
Chicken zone enumeration, native identity, trough mode separation, fluid
transfer and exact farm receipts reuse the WP02 evidence. This package adds
no role, area, storage category, production event callback or bridge protocol.

## Phase 0: installed contracts

Inspected the installed `CowDefinitions.lua`, `ISMilkAnimal.lua`, animal
context menu, feeding definitions and targeted native bytecode. Ran the
repository's `tools/SignatureProbe.java` with Java 25 against the pinned JAR.
Raw signatures/bytecode remain in ignored `build/animal-probe`; proprietary
code is not packaged. The WP02 work order was read from the supplied attachment
because `docs/WP02-ANIMAL-HANDLING-CHICKENS.md` is absent in this checkout.

Critical installed-source fingerprints:

| Source | SHA-256 |
| --- | --- |
| `shared/TimedActions/Animals/ISMilkAnimal.lua` | `ffafa34e76fd2ed00aa5149b8c91a85a0361d7123c235fe8061aa2e1b03a19a3` |
| `shared/Definitions/animal/CowDefinitions.lua` | `44490403f449d1875210587e4c5f5a86c64cff0496d45a155fc32eac9577e116` |

- Native kinds are `cow`, `bull`, `cowcalf`; breeds include Angus, Holstein
  **and Simmental**, all producing `CowMilk`. Calves grow at 180 days by
  default. Pregnancy is 280 days before the native sandbox modifier.
- Readable getters cover stable ID, type, age, baby state, sex, stress,
  mother reference, pregnancy, lactation, current milk, genetic maximum and
  current capacity. Use `getData():canHaveMilk()`, `getMilkQuantity()` and
  `getMaxMilkActual()`; Java public fields are not proof of Lua exposure.
  `IsoAnimal.getMother()` supplies an exact mother when loaded; missing or
  unreadable identity must conservatively reserve milk for any local calf.
- `canBeMilked()` is only the species-definition flag. `readyToBeMilked()`
  additionally requires more than one litre. The vanilla context menu accepts
  more than 0.1 litres. Neither replaces checking sex, adult state, lactation,
  welfare, ownership, capacity, zone, stress and the per-day policy.
- `ISMilkAnimal:new(character, animal, bucket, right, all)` accepts an
  `IsoGameCharacter`. It uses that character's inventory and Husbandry skill;
  single-player milk/XP effects do not route through `getPlayer()`. The action
  is indefinite, plays the native milking animation/sound and blocks animal
  movement until its native stop/complete cleanup releases it.
- Each native `milkAnimal(character, bucket)` call transfers at most **0.1 L**,
  capped by actual carrying room. It measures what the real fluid container
  accepted and subtracts that amount from the udder; there is no additional
  scripted deduction. It awards native Animal Care XP. Normal completion
  leaves the native sub-0.1-litre remainder rather than forcing an empty udder.
- A measured reserve can be enforced *before* each native increment. Validate
  the exact actor, cow, bucket, receipt and current reserve, and stop before
  the next increment could cross it. Verify synchronous per-increment changes:
  whole-session udder subtraction would include natural production/nursing.
  Current capacity may increase during milking, so reserve guards must also
  account conservatively for that increase.
- The stock action may select another same-type container even with `all=false`.
  A guarded instance must finish before substitution becomes possible and
  validate the bucket again at every effect boundary. Containers start empty,
  must accept the native milk fluid and may not be input-locked. Existing
  mixtures or partly filled containers are not milk buckets for this package.
- With stress above 40 and Husbandry at most 7, the installed Lua overwrites
  its calculated spill chance with 120, guaranteeing that branch. It empties
  the bucket, drops that exact item to the world and makes the cow flee.
  Normal policy therefore stops before a stressed increment. Any observed
  spill/drop still needs receipt reconciliation, never replacement milk/items.
- Native lactation expires after 21 days without milking when neither pregnant
  nor nursing; daily output depends on genes, age and native settings. Do not
  substitute a fixed breed yield. Native overfull-udder damage checks quantity
  against 115% of the genetic maximum, not 80% of current capacity. The planned
  80% priority is an earlier precaution, not a native damage threshold.
- Adult cattle accept `AnimalFeed,Grass,Hay,Vegetables,Fruits` at troughs;
  calves inherit compatible trough behavior and also nurse. Native feed bags
  (`Base.AnimalFeedBag`) and grass bags (`Base.GrassBag`) expose those feed tags.
  Automatic cattle supplies remain confined to marked Farming storage; human
  food stores are not a source. Mixed-species feed must suit every consumer.
- Trough contents are shared native inventory/fluid; they are not partitioned
  by species. Preserve their occupied modes and the WP02 separate feed/water
  allocation. A cattle job yields after its configured donor-trip limit.
- `getFullZoneSize()` returns the sum of native connected rectangles. The
  installed small-enclosure check compares that total with **80 for an adult
  or 40 for a calf**, without multiplying by headcount. Report the proven
  individual threshold; do not invent a per-head density calculation.
- Bulls are configured to attack when stressed, retaliate, knock down and
  cause lacerations. Native attack entry accepts `IsoGameCharacter`; male
  fighting also inspects connected zones. A companion must not be assumed
  immune. Cow stress/active animal aggression must block admission. Live
  companion-target risk remains to be measured below.

## Gates and remaining live proof

At Phase 0 no cattle behavior is enabled. Subsequent phases must prove Lua
getter exposure, companion animation/cleanup, real container identity and
volume accounting in a clone before enabling milking. A calf reserve requires
three supported-calendar days of native nursing with healthy animals; an
unproven bounded transfer leaves nursing-cow milking disabled. Feeding/watering
requires its own complete receipt-closing live acceptance. Dry cows, bulls,
held/led animals and Strange Folk remain excluded.

Pastures above 256 tiles will retain the existing per-slice square/animal and
time budgets. A 1,024-tile ceiling is a resumable frontier, not permission for
an eager scan or an unloaded census. Mixed and chicken-only audit timings will
be recorded after the implementation exists; no timing improvement is claimed
from signatures alone.

Each phase records its automated gate and native results below. Original saves
remain inputs only, one low-impact game runs at a time, no gate/compilers overlap
it, and blockers receive zoomed-out native screenshots.

Phase 0 gate: all five essential checks passed in 102.5 seconds at
`build/test-results/20261110-160523-3c2ead`. No cattle gameplay is enabled by
this documentation phase. Companion-specific native action exposure, live
milk quantities and welfare acceptance remain explicit implementation gates.

## Phase 1: species census

Cattle now have their own species entry and cow/bull/calf counts alongside
the unchanged hen/rooster/chick census. Retained hutch identities contain
chickens only; cattle in the native registration set cannot prevent a sheltered
flock from closing. Missing chickens still prevent closing. Unsupported
species do not authorize irreversible policy and cannot become milk targets.
Strange Folk evidence still protects the zone.

Large cattle pastures can retain a frontier up to 1,024 tiles while each call
keeps its previous square and animal budgets. Larger chicken-only zones do
not gain cattle permission. The native individual enclosure minimum is an
informational blocker, never a request to move or modify cattle. Additive
census data stays inside the existing version-1 animal document; its bounded
save-copy allowance now accommodates the cattle records without dropping an
older or unknown future document.

`animalCattleEnabled=0` remains deliberate pending Phase 2 live care proof;
`animalCattleZoneMaxTiles=1024` defines the retained frontier. All existing
chicken tests passed unmodified, plus mixed census, shared hutch safety,
unsupported species, disabled cattle and 1,024-tile slice regressions. The
five-check gate passed in 103.3 seconds at
`build/test-results/20261110-161532-52b892`.

## Phase 2: shared trough care

Cattle use the existing exact-item Farming loans and native fluid transfers.
Automatic cattle donations accept only the proven `AnimalFeed`, `Grass` and
`Hay` feed tags; native compatibility with fruit/vegetables does not authorize
donating human food. Mixed pens require feed compatible with both species.
Chicken-only feed selection is unchanged. Nearby stressed/attacking bulls
stop admission. A cattle water job counts started donor trips conservatively
in its persisted target, yields after two, and retains its high-water intent
so another audit continues even when the trough has passed the low mark.

Two disposable native runs passed feed/water and exact loan return checks:

| Pen | Run | Audit median / p95 / maximum (ms) |
| --- | --- | --- |
| Hens + Holstein, Angus, Simmental | `SC-Harness-20261110-163033-a3335947` | 0.650 / 1.338 / 2.950 (65 samples) |
| Holstein, Angus, Simmental | `SC-Harness-20261110-163338-bb21c3a6` | 0.604 / 1.824 / 2.382 (37 samples) |
| Hens only | `SC-Harness-20261110-163631-ea08c3c5` | 0.613 / 1.341 / 1.451 (60 samples) |

The ordinary Farmer refilled the real water trough to 1.8 L, reducing the
exact 8 L water can to 6.2 L, returned it to Farming with its receipt closed,
and moved the exact feed bag into the feed trough (10 native feed units).
The mixed run also delivered the exact native egg. Cows retained health 1.0.
The injected fixture only supplies initial animals/storage; production never
creates or moves cattle. No animal was teleported during observation.

These measurements include the entire `FarmWork.audit`, including retained
crop/storage work, at one audit per second under the low-impact client. Their
p95 is below the 2 ms target, but occasional complete calls exceed it; this
is not a worst-frame guarantee. Large 1,024-tile continuation and the
two-trip/high-water continuation are exercised by compact automated checks.
The native trough test is deliberately small and completes in one pour.

Native getters were readable from Lua for all three breeds: adult female,
age 180, `CowMilk`, stress and Husbandry level 0. Freshly created cows are
**dry with zero current capacity**, so milk acceptance needs explicitly
lactating initial fixture animals; it must not infer lactation from species.

The chicken-only run passed the same trough, exact egg and returned-can
checks. Cattle care is now enabled by default. Milking remains gated separately.
All five essential checks passed in 103.7 seconds at
`build/test-results/20261110-163932-d92e03` before the Phase 2 commit.

## Phase 3: exact native milking

Milking is one farm chore with an animal-ID claim. Its native action is bound
to the real Farmer, cow, borrowed empty container and existing farm receipt.
Each stock 0.1 L increment is guarded before execution and measured afterward
(5 ml tolerance). Native animations, sound, stress, Animal Care XP and fluid
accounting remain in charge. No scripted milk or compensating deductions are
added. Guard failure stops the stock action and its normal movement/hand
cleanup. The live mother-child list also protects a newborn between zone audits.

One daily job may borrow/deliver several containers, as Thor selected. The
largest safe load is preferred through the retained bounded supply scan; a
held-bag weight discount is not assumed available while using the bucket.
Daily cow/job evidence and one-attempt-per-hour admission are additive fields
in the existing animal document. Exact container identity, source, cow/day,
fluid, measured litres and any observed loss survive ordinary farm receipt
normalization. Interruption/reload reads actual contents before continuing;
unreadable or missing ownership pauses rather than recreating cargo. A dropped
receipted container can only be recovered by its exact native/world identity.

Native run `SC-Harness-20261110-170212-d59f78bf` passed three breeds at
Animal Care level 0, delivering three exact milk containers and closing all
receipts: Holstein **4.8 L**, Angus **5.0 L**, Simmental **5.1 L**, 14.8 L
total. Every synchronous transfer matched udder loss and no spill was observed.
These are controlled starting udders (current capacity capped at 5 L, filled
to 90% initially), with native production/capacity growth afterward. They are
**not natural 24-hour breed yields**. Post-milking production explains milk
reappearing before the end-of-run check; emptiness is an action-stop condition,
not a requirement that the cow remain empty while the other cows are milked.

The first milk run (`SC-Harness-20261110-165157-0526d09e`) collected 9.9 L
correctly but failed delivery: a milk bucket inherited shelf-food classification
and selected a store outside the deliberately fenced pen. A native blocker
screenshot is retained. Filled pure cow milk now classifies as Fresh food;
the rerun above delivered to permitted storage inside the pen. This early
classification fix is required for the native milk acceptance, while Phase 4
finishes destination fallback, urgent staging and reload delivery.

Two disposable fixture errors were corrected: cattle-only setup must never
index an empty egg nest, and 42.22.2 observer needs use `CharacterStat`, not the
removed `Stats:getHunger`. Neither is production animal behavior. The failed
calf fixture `SC-Harness-20261110-170613-d0e83281` stopped and captured its
native screenshot rather than being counted as acceptance.

Live observation also exposed a moving-cow census gap: tile traversal can miss
an animal crossing into a tile already scanned. A bounded continuation over
the zone's registered animals now reconciles cattle still physically inside;
it shares the existing animal budget and leaves chicken census rules intact.
Milking uses native left/right attachment points. Urgent milk work participates
in the existing camp priority hint and outranks a nearer water job, without
interrupting survival treatment or changing the job priority range.

The final Phase 3 five-check gate passed in 104.8 seconds at
`build/test-results/20261110-182754-e2607d`. It includes native action identity,
measured increments, reserve and mismatch guards, largest safe container
selection, daily-limit repair, real save-normalizer round trips, and a queued
urgent milk job releasing an optional activity through its cleanup owner.

The longer calf fixture needed corrections to its pen setup: retain ordinary
ground tiles while clearing decorative clutter, and remove storage registrations
belonging to the replaced camp footprint. Otherwise the largest-container rule
correctly tried to fetch an old bucket through the closed test fence. These
failed fixtures are not welfare acceptance; their logs and blocker screenshots
remain under the disposable run directories.

The native calf run `SC-Harness-20261110-184216-6d7e070f` passed after
**98.367 game hours**, covering three distinct daily milk jobs. Its mother,
calf, dry cow and bull all retained health **1.0**. The linked calf was detected
through its actual mother identity; neither the bull nor dry cow started a
milking action. Measured mother-udder stops were:

| Daily milking | Remaining milk (L) | Required calf reserve (L) |
| --- | --- | --- |
| 1 | 2.256817 | 2.195032 |
| 2 | 2.487582 | 2.450267 |
| 3 | 2.748541 | 2.699277 |

This longer welfare fixture used a real fenced pasture, an Animal Care 8
Farmer and the ordinary 60-minute-day calendar at fast-forward. Initial
fixture setup supplied the animals and lactation; observation never reset
their health, moved them or changed their milk. Level 0 milking is separately
proven by the three-breed run above. Zoomed-out native screenshots and logs
are retained in that run's `cache/Screenshots` and `cache/console.txt`.

The welfare run used the Phase 4 native-style approach hold. It exposed two
additional scheduling issues: a trough could be selected as its own refill
donor, and an ordinary milk job could retain its old priority after the cow
became urgent. Troughs are now excluded as water donors; bounded cattle audits
promote the existing job at the live urgent threshold. A full-storage wait is
reconsidered immediately on that transition. Other shortages retain their
normal retry delay. Automated regressions cover both corrections; the later
delivery run uses the corrected source.

## Phase 4: delivery, interruption and ownership

Milk destinations are checked Fresh food first, then Regular food, with
deposits enabled and room revalidated before milking and each increment.
Pure milk in a water bottle or other compatible fluid container is food,
rather than farming water. Empty compatible containers return to the Farming
classification only while milking is enabled. No decanting, combining,
synthetic milk items or extra fluid deductions are performed.

Ordinary full storage pauses before withdrawal. An urgent load may instead
return to its exact Farming source, still carrying its receipt marker, and
retry delivery after three real minutes or manual Retry. Cancellation or a
lost carrier releases an exact, verified staged container already at source;
unloaded or ambiguous ownership remains pending. A persisted expected food
destination lets recovery recognize a physical deposit completed before its
receipt commit without replaying a transfer.

The cow approach matches vanilla's movement hold before walking to its milk
attachment. The exact claim releases it on navigation failure, cancellation,
reset or a 15-second approach deadline. Once the native action starts, its own
stop/complete cleanup owns the hold. This changes no animal coordinates,
health or production quantities.

The first combined full-storage scenario was not counted as acceptance: it
stalled before milking while nighttime work, approach and water-refill chores
interleaved. Follow-up instrumentation isolated an ownership bug: a small empty
milk vessel could trigger hydration refill, changing its contents before
milking. `Needs` now excludes protected farm vessels from refill selection and
revalidates through the same selector at action time. The close-flank admission
uses the same unobstructed adjacent-square interaction check as the other
animal chores, instead of chasing a sub-tile point inside the cow's collision
body. The stock action still independently validates distance. This requires
no actor or animal teleport. A regression checks the public refill decision with and
without the same vessel's receipt marker.

Ordinary full-storage refusal was observed in the earlier full-storage runs;
it never started a native milking action. Corrected run
`SC-Harness-20261110-192713-57b93fde` separately tested an initially urgent cow:
the exact container **244189304** gained **2.0 L**, was physically staged in
its original Farming source with its marker intact, and was withdrawn after
Regular food space was opened while Fresh food remained full. The clone then
saved and quit normally with that same 2.0 L container carried, before deposit.
Its `animal-care.txt` records the checkpoint PASS; it is not yet a reload PASS.
The native run also recovered from an initial static-route blocker. Distinct
blocker and checkpoint screenshots are retained.

The first actual reload (`SC-Harness-20261110-192955-b3366a27`) failed closed:
the milk receipt survived, but ordinary companion inventory reconstruction had
assigned a new native item ID. Its blocker screenshot is retained. The fix
reuses the existing exact-ID inventory snapshot/restore path already used by
pending Home deliveries. An outstanding milk receipt requests that existing
flag for its own actor only; verified delivery clears the requirement. No
save schema or bridge change is needed, and missing old identities are never
rebound by item type or replaced with new cargo. Automated receipt checks cover
owner isolation, reload and release of the requirement.

The corrected snapshot run `SC-Harness-20261110-193504-8826fe3f` staged and
saved **2131359551**, containing **2.0 L**, with exact native inventory IDs
enabled. Reload `SC-Harness-20261110-193725-f40b7276` verified that same ID,
unchanged amount, one physical item, a permitted Regular food deposit and a
closed receipt. Its extended probe then stopped on an incorrect assumption
that terminal receipts remain in the ledger; allocation deliberately compacts
them. That probe failure is not a failed physical delivery. It also motivated
clearing a milk job's terminal receipt pointer immediately on verified deposit,
before another worker can compact it. A focused regression covers that race.

Final reload `SC-Harness-20261110-194425-4ecc3602` **passed**. It found the
saved bucket ID **2131359551** exactly once, preserved its **2.0 L** and
physically delivered it to permitted Regular food storage while Fresh food
remained full. The same daily **job:2 / day 0** then delivered native containers
**978555045** (2.0 L) and **570674682** (1.4000002 L), completing normally.
Total delivered was **5.4 L in three loads**, including native production
during the trip; none was scripted in. Each transfer closed its receipt after
the physical postcondition. The final `animal-care.txt` reports:
`PASS exact milk delivery after real save/load; multiple loads in one daily job; fallback food store`.
The zoomed-out native screenshot is
`build/live-sandbox-runs/SC-Harness-20261110-194425-4ecc3602/cache/Screenshots/SC-Harness-20261110-194425-4ecc3602-animal-delivery-reload-passed.png`.

Live probes used explicit private config overrides while the shipping milk
gate remained off. After these results, cattle care and milking are both
enabled in the 0.27.8 defaults. Chicken-only tests and defaults are retained.
Gameplay implementation is Lua only. The rebuilt payload JAR changes release
metadata, not Java source or protocol; SHA-256 is
`4e96b6cc9ba4e40b8ebfe95d790cb1c5b9d1ac3d00e04400a87baa5fc3dec71f`.

## Defaults and limits

| Key | Shipped default |
| --- | --- |
| `animalCattleEnabled` | 1 |
| `animalMilkEnabled` | 1 |
| `animalMilkStartPercent` | 50 |
| `animalMilkCalfStartPercent` | 70 |
| `animalMilkCalfReservePercent` | 40 |
| `animalMilkUrgentPercent` | 80 |
| `animalMilkMaxStressPercent` | 40 (never above the proven safe native boundary) |
| `animalCattleZoneMaxTiles` | 1024 |
| `animalWaterTripsPerJob` | 2 |

No WP03 phase remains disabled. Existing breeding management and irreversible
culling remain **off**. Calm bulls coexisted in the welfare run; native
aggressive-bull attacks against a companion were not forced in live acceptance.
Their native attack contract can target `IsoGameCharacter`, and admission
checks treat their stress/aggression as a reason to stop work. Do not infer
companion immunity from the calm test.

Interruption, substitution, measurement mismatch, cancellation, staged-carrier
loss and ownership normalization have automated coverage. Native forced spills,
death and player interruption at every boundary have **not** all been completed;
the checklist deliberately leaves those live scenarios open. Queued ordinary
milk promotion is automated; the accepted urgent-delivery run starts with an
urgent fixture rather than claiming an overnight end-to-end promotion pass.

Butter needs a separately verified vanilla processing recipe and exact fluid
ingredient accounting. Sheep need their own species, milk/shearing contracts,
young-animal reserve and native acceptance. Safe culling needs proven corpse,
butchering, authorization and death-attribution ownership before any irreversible
dispatcher can be enabled. None is part of this release.

## Final verification and handoff

`scripts/Test-Project.ps1 -Serial -Release` passed all five checks in
**248.2 seconds**, with 23 serial JVM launches, 256 MB heaps and two processors.
Evidence: `build/test-results/20261110-194735-abef8e/summary.json`. This gate
does not claim live gameplay; the native runs above provide that evidence.
Normal/debug Lua compilation, native contracts, lifecycle, behaviour, cargo
and interface/content passed. The release profile also passed **16/16 installer
transactions** and built both Workshop review staging and a standalone archive.
Standalone validation confirms `debug=false`, `dependency=false`; its SHA-256 is
`c376e9424a7308948bafe23b4294f0dfa95f7b5f0d899546047fc56da28e05e6`.
No installation, upload or push is part of this work package.

One local commit was made per phase, each after a green five-check gate:

| Phase | Commit / gate evidence |
| --- | --- |
| 0: native contracts | `7d868e1d` / `20261110-160523-3c2ead` |
| 1: species census | `2e20b859` / `20261110-161532-52b892` |
| 2: cattle trough care | `1227fdd2` / `20261110-163932-d92e03` |
| 3: guarded native milking | `ad3458ad` / `20261110-182754-e2607d` |
| 4: delivery and release | final phase commit / `20261110-194735-abef8e` |

## Final 0.27.8 work-reach acceptance — 2026-11-11

The post-package refinement allows chicken and cattle pens within the existing
30-tile camp work reach. The entire enclosure, its devices, milking sides and
interrupted-item recovery must stay within that bound. Automated cases cover
tile 30, refusal of tile 31 and invalidation after camp edits. The native runs
below exercise a mixed pen extending five tiles beyond its camp area; they do
not claim a native test at the exact 30-tile limit.

The private fixtures used one real 42.22.2 client at a time, below-normal CPU
priority, four processors, 1280×720 rendering capped at 30 FPS, and a cloned
save. The ordinary Farmer scheduler and native actions performed all work.
Fixtures placed the animals and supplies and set initial lactation; they did
not script successful item transfers. The production harness was unchanged.

- `SC-Harness-20261111-013917-acffe76f` passed mixed chicken/cattle care beyond
  camp: native opening, water, feed, nest access and egg collection, followed
  by native milking and physical deposit into Fresh food storage. Water reached
  1.7999996 L, feed reached 10 native units, egg **1104764880** was delivered,
  and container **410166449** held **1.700000286 L** of milk. Delivered items
  had no active loan marker; birds and cow retained full health. The world was
  saved normally. Screenshot:
  `build/live-sandbox-runs/SC-Harness-20261111-013917-acffe76f/cache/Screenshots/SC-Harness-20261111-013917-acffe76f-animal-mixed-milk-saved.png`.
- `SC-Harness-20261111-014234-b2a19e8b` restarted that saved world and passed.
  Both exact native item IDs occurred once across registered storage and loaded
  companion inventories; the milk remained in Fresh food with the same measured
  quantity and no loan marker. The original cow and loaded birds were healthy.
  Screenshot:
  `build/live-sandbox-runs/SC-Harness-20261111-014234-b2a19e8b/cache/Screenshots/SC-Harness-20261111-014234-b2a19e8b-animal-mixed-reload-passed.png`.

Both runners exited 0 with `LIVE_SANDBOX_PASS`. Console inspection found no
new LF gameplay exception or animal-work blocker. The vanilla map warning
about a mannequin zone at `(13583,1299)` is unchanged and unrelated to these
fixtures. This focused pass required no further gameplay change. The remaining
unexecuted spill/death/interruption scenarios listed above are still unclaimed.

The final `scripts/Test-Project.ps1 -Serial -Release` passed all five checks
in **258.9 seconds**, using 23 serial JVM launches with 256 MB heaps and two
processors. Evidence: `build/test-results/20261111-014443-b415ec/summary.json`.
All **16/16** installer transactions passed. The standalone package validated
`debug=false`, `dependency=false`; its SHA-256 is
`b7c19c168b4f03008352fed074f7cb69d59ebd1e25f046beb78e9a59431846b1`.

The public standalone was installed locally after both game clients exited.
Both installed metadata files report 0.27.8 without a ZombieBuddy requirement;
debug spawn and the movement recorder are off. Installed payload and launcher
bridge hashes match the committed 0.27.8 bridge. The previous 0.27.5 Workshop
staging folder was preserved under `build/retired-workshop-staging` outside
the game's mod search path, leaving one local LF installation.
