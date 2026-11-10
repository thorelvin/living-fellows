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
