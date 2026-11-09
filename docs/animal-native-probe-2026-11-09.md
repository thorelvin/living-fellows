<!-- SPDX-License-Identifier: MIT -->
# WP02: chicken native evidence — 42.22.2

Branch: `living_fellows/0.27.7`, based on 0.27.6 (`21224392`).
Installed runtime: 42.22.2, revision 3d39148846. JAR SHA-256:
`3c4a7c5f149d784758c6fb5f8fa85f3a21d572e38bc081400e89035f8120d287`.

## Method

Ran `tools/SignatureProbe.java` against the installed game's bundled Java 25,
and inspected the installed vanilla Lua actions and targeted `javap` output.
Raw signatures and bytecode stay under ignored `build/animal-probe`; no game
implementation or assets are packaged. Existing bridge stubs cover the actor
and queue boundary; this feature adds no Java code or bridge API/protocol.

## Proven native contracts

- `DesignationZoneAnimal.getAllZones()` returns an indexed list. Inherited
  `getId/getX/getY/getZ/getW/getH/isFullyStreamed` describe each rectangle.
  `getHutchs/getTroughs` are local lists; connected variants can cross camp
  boundaries and must not be used as permission to work elsewhere.
- `IsoAnimal.getAnimalID()` is the saved integer identity used by our existing
  Strange Folk animal owner. Online IDs are transient. Types are `hen`,
  `cockerel`, `chick`; age, baby state, custom name and held state are readable.
  `getData().isFemale()` and laying-period data exist. Unknown names, identities,
  sex, age, holding/leading evidence or population completeness prohibit culling.
- Hutch `getMaxAnimals()` is roost capacity. `getMaxNestBox()` is the highest
  index, **not a count** (vanilla definition 3 means boxes 0–3).
  `getAnimalInside()` is a map, not an indexed list. Nest boxes expose exact
  `getEgg(index)/removeEgg(index)/getEggsNb`; Food exposes `isFertilized()`.
  Doors use `isDoorClosed`; floor/nest dirt are separate readings.
- Native chicken definitions enter at 20:00 and exit at 07:00. Live run
  `SC-Harness-20261109-224657-7f065d72` verified all three birds entering the
  open hutch unaided and leaving after dawn. No call to herd, carry, enter or
  move a bird was made during observation. The private fixture used a two-minute
  game day; native roost path delays do not scale with that calendar shortcut.
  This is one autonomous cycle, not acceptance of three normal days of closing.
- Trough feed is actual container inventory. Native admission accepts Food or
  drainables with `getAnimalFeedType()`. Feed quantity sums absolute food hunger
  and drainable uses times 0.1. Chickens' feed compatibility must be checked;
  ordinary human food and crop seeds are not automatically donated.
- Current troughs hold **feed or fluid**, not both. Native `checkContainer`
  removes the item container when fluid is present. Chicken care therefore
  requires separate feed and water troughs; it preserves occupied modes and
  assigns empty troughs deterministically. Pour guards reject any item-filled
  target so care cannot erase stored feed or unrelated player items.
- Live testing invalidated the old `ISAddWaterToTrough` assumption. On 42.22.2
  the action drained the exact eight-litre donor while native trough water
  stayed zero. Its server Lua object updates a legacy water field; the current
  trough getters read its FluidContainer. Use `ISFluidTransferAction` with the
  exact donor and trough fluid components, a measured amount and instance-bound
  actor/ownership checks. Do not compensate with scripted water or deductions.
- Feed uses `ISInventoryTransferAction`, not an invented add-feed command.
  Every transfer must prove native list membership and `getContainer` agree.
  Live execution exposed its UI-only `selectedContainer` binding: update and
  perform dereference `getPlayerLoot(companionPlayerNum)`. Clear that field on
  the individual action after its stock animation starts; face the exact trough
  directly. Native transfer, sounds, validation and item identity remain intact.
- `ISHutchGrabEgg` removes index zero repeatedly during update. Its unguarded
  form cannot preserve selected fertilised eggs. Limit a guarded instance to
  one exact first egg; if that egg must stay, leave the nest untouched.
- `ISToggleHutchDoor` toggles on completion; it must recheck the expected door
  state before commit to avoid undoing another actor's change.
- `ISHutchCleanFloor` consumes water and optional cleaner repeatedly; it may
  silently select replacement inventory items. Cleaning needs instance-bound
  tool/fluid guards before enabling, including no unreceipted replacements.
- `ISKillAnimal` accepts a character and animal but its native validity is only
  a short distance check. It is not a culling safety policy. Ground butchering
  uses `ISButcherAnimal`, with native body parts and native yields. Output size,
  tools, held/led exclusions and companion execution need live validation.

## Deliberate safety gates / deviations

Actual Lua exposure differs from public Java signatures. HashMap values do not
expose `iterator`; vanilla's `ArrayList.new():addAll(values)` permits a bounded
copy followed by indexed slices (reject more than 128 occupants). The hutch's
Java type field is not suitable Lua evidence; use the chicken's native
`canBePutInHutch` compatibility method instead. No bridge addition is needed.

`setMaxWater` writes the old field, not fluid capacity. The disposable trough
fixture sets its native FluidContainer capacity. `createSurroundingFence` is a
native no-op in this build and is not evidence that the fixture has fences.

No guessed daily feed rate: hunger depends on native animal data and settings.
Without a proven three-day feed estimate, breeding retention and culling stay
off. When retention is enabled later, a retained first egg blocks that nest's
collection rather than rearranging or copying eggs.

Evening closing and culling remain disabled pending their full live acceptance.
Cleaning was enabled after the native test below. Opening an
already-open hutch is never queued. Unloaded or over-budget evidence is pending,
never proof of an empty flock. No animal is spawned, moved or reconstructed.

## Live acceptance status

1. Open hutch: unaided entry and departure passed in the cloned native run above.
2. Farmer care passed in `SC-Harness-20261109-230253-04a108a9`: 1.8 litres in the
   water trough, exact donor reduced from 8 to 6.2 litres, a whole feed bag
   delivered to the separate feeder (10 native feed units), exact egg
   `1273695898` delivered to permitted `storage:3`. This run accelerated only
   the private discovery cadence; the normal BaseWork controller owned claims,
   travel and actions. A caught empty-nest index read was found and corrected;
   the clean rerun must contain no gameplay exceptions. Unmarked feed,
   cancellation and receipt recovery also have automated gameplay coverage.
3. Three day/night cycles with no early lockout; guarded cleaning with no
   replacement of borrowed resources. Cleaning passed in
   `SC-Harness-20261109-231551-a41572e4`: floor and nest dirt both reached zero,
   and exact mop and cleaner ownership returned to source storage. Ordinary
   automatic house maintenance was disabled only in this clone so an unrelated
   old-house cleaning route could not monopolize the worker. This does not
   count as a three-day automatic-closing acceptance. Its later open-pen
   roost repeat recorded at most two birds inside at once and ended blocked;
   the third bird's location/health was not captured. Therefore the overall
   run is not a full pass and automatic closing stays off. Earlier autonomous
   cycles did record all three entering and leaving.
4. Natural breeding to the computed target with measured feed-horizon evidence.
5. Before enabling culling: a full day/night cycle above target, named/held/led
   and Strange Folk birds untouched, exact native butcher output delivered.

## Performance

The care run above sampled whole farm audits: active median 0.5303 ms,
p95 0.9835 ms, maximum 1.8605 ms across 103 calls. The disabled baseline had
only one sample (0.4572 ms), so it is insufficient for a performance regression
claim. These are audit timings, not total frame times; navigation and other
systems still contribute to frame spikes. No production tick callback was added.

The next exception-free care run (`230751-d61e633a`) measured median 0.5087 ms,
p95 1.0228 ms, max 1.1842 ms over 142 calls; its one disabled baseline sample
was 0.2516 ms. Reclaimed unused square quotas prevent a yielded animal slice
from keeping work units it did not actually use.

The final care/cleaning run (`231551-a41572e4`) measured 0.5212 ms median,
1.0093 ms p95 and 1.2926 ms maximum across 102 care audits; baseline remains
only one sample (0.4230 ms). Exact feed item `1876301458` reached the feeder;
egg `865506577` reached permitted food storage. Native hutch-floor cleaning
used another approximately 0.15 litres of the same donor and returned its loans.

Phase 3's five essential checks passed at
`build/test-results/20261109-232415-f3e435` (109.9 seconds, serial). The private
probe and its screenshots remain separate from the production package.

## Phase 4: flock policy and its gate

Implemented and automatically tested capacity/reserve maths, feed-horizon
admission, chick headroom, deterministic egg-ID retention and incomplete-census
refusal. A 20-slot hutch reserves two slots and two roosters, leaving 16 hens.
At the ambiguous 16-slot boundary, the decision uses the provisional hen count
to reserve the second rooster, leaving 12 hens; it never overbooks a slot.
Hutches with fewer than four slots cannot prove both the minimum flock and a
free reserve. Unknown chick sex conservatively reserves potential hen capacity.

The live controller deliberately supplies no guessed daily feed forecast or
unverified egg census. `animalBreedingEnabled` stays 0, and fertilised eggs
remain untouched. Pure policy coverage is not acceptance of natural growth to
target. Verified animal-action failures now hand their 15/30/60-second pause to
the existing BaseLife retry mechanism rather than conflicting with its generic
delay. A new complete audit wakes dormant candidates.

Phase 4's five essential checks passed at
`build/test-results/20261109-232842-29178b` (110.3 seconds, serial).

## Phase 5: irreversible work remains disabled

Added a read-only cull proposal policy with conservative native ownership and
laying evidence, complete/current population proof, daylight/threat/tool/output
capacity gates, deterministic surplus-rooster/old-hen order and a persisted
daily-limit reader. Unknown, future or malformed counters refuse admission.
Named, held, led, wild, chick and Strange Folk candidates are excluded. Automated
tests exercise these outcomes and minimum flock protection. Removed native
devices also invalidate retained work references before any action may commit.
An expired action retains its worker, receipts and claim while native removal
is pending; it reports failure only after cancellation settles. The owning
behaviour check reproduces that pending-cleanup boundary.

This is not a kill implementation: there is no production kill/butcher dispatcher
or counter writer. Signatures alone do not prove exact corpse attribution,
butcher output capacity, or cancellation/reload reconciliation. These remain
prerequisites for implementing and enabling the irreversible chain. No birds
were killed by this feature during acceptance.

## Delivered scope and defaults

Phases 0–2 provide native evidence, feed/water care and exact egg delivery.
Phase 3 provides dawn opening and verified cleaning; dusk closing is gated.
Phase 4 provides tested policy but no unverified feed forecast or egg-census
producer. Phase 5 provides exclusion/admission policy only; execution is off.
The latter two are deliberately disabled parts of WP02, not finished live
acceptance. No new Java implementation, bridge API, scheduler or background
service was added. The rebuilt existing bridge changes release metadata only.

`animalWorkEnabled=1`, low/high thresholds 25/90%, reserve 10%, second-rooster
threshold 12 hens, feed horizon three days, dusk grace 60 game minutes, one
cull per zone/day, eight zones and 32 animals/slice retain the proposed defaults.
`animalCleanEnabled=1` follows exact native cleaning proof.
`animalCloseEnabled=0` is an additional gate for inconsistent roosting evidence.
`animalBreedingEnabled=0` and `animalCullEnabled=0` override the draft's enabled
defaults because their required evidence is unproven. Even manually changing
the latter switches cannot invent the missing evidence or enable a kill path.

The player contract needs **two troughs**, because native 42.22.2 troughs cannot
hold feed and water together. Whole feed bags may fill above the 90% target,
up to native capacity; they are never silently split or copied. A fertilised
first egg blocks collection from that nest rather than rearranging native eggs.

For the next species, retain the same farm scheduler, claims and receipts.
Extend the species table only after proving its native feed types, housing,
action compatibility and output ownership. Avoid borrowing chicken hunger
rates or roost assumptions for another animal.

## Remaining live acceptance setups

These are queued harness scenarios, not requests for the player to run them.
Use a cloned save, one game client, and a zoomed-out screenshot at every block.

**LIVE TEST 3 — Three normal days of hutch door safety**
Setup: a physically fenced camp animal zone, native hutch, two hens and one
rooster; feed/water supplied, one Farmer.
Steps: 1. Observe three ordinary dusk/dawn cycles with automatic closing still
off. 2. Verify every bird's native identity, location and health. 3. Only then
enable closing in the private clone and repeat.
Expect: no early close, no bird trapped outside, native opening after dawn.
Send: door/occupant/time logs and blocker/recovery screenshots.
Blocks: `animalCloseEnabled` default remains 0.

**LIVE TEST 4 — Natural growth stops at the supported target**
Setup: the proven pen above with a measured native feed forecast and complete
fertile-egg census producer implemented first.
Steps: 1. Start with two hens and one rooster. 2. Observe hatching and maturity.
3. Reduce marked feed below the horizon.
Expect: exact retained eggs respect capacity/feed headroom; no spawned animals.
Send: target, forecast, egg IDs, chick/adult census and feed quantities.
Blocks: `animalBreedingEnabled` default remains 0.

**LIVE TEST 5 — Surplus culling preserves owners and output**
Setup: implement and separately prove the native kill/corpse/butcher receipt
chain first, then use an over-target flock with named/held/led exclusions and
permitted food storage in a clone.
Steps: 1. Observe a full day/night cycle. 2. Interrupt/reload at each irreversible
boundary. 3. Check exact animals and native output at storage.
Expect: at most one eligible surplus bird per day; protected birds untouched,
exact output once, ambiguous absence never reconstructed.
Send: animal/corpse/item identities, receipts and screenshots.
Blocks: `animalCullEnabled` default remains 0; execution remains unimplemented.

## Final validation

All five essential checks passed for the final 0.27.7 source and payload at
`build/test-results/20261109-234152-659a7f`: Build 13.7 s, Lifecycle 26.9 s,
Behaviour 3.0 s, Cargo 2.9 s, Interface 57.1 s; total 103.5 s. This is automated
validation, separate from the partial live acceptance above. Tests ran serially
with 256 MB heaps and two processors; no live game ran alongside the gate.

The base and rebuilt JARs were compared entry by entry: only
`META-INF/MANIFEST.MF` changed. All native class bytes remain identical; protocol
`42.22-isocompanion-31` is unchanged. Source, shipped metadata and Support report
0.27.7. No install or publication was performed by this work package.
