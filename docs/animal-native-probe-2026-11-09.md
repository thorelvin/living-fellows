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
and queue boundary; this Lua feature adds no Java calls or bridge protocol.

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
- Native chicken definitions enter at 20:00 and exit at 07:00. Autonomous
  roosting and companion animation remain live acceptance questions.
- Trough feed is actual container inventory. Native admission accepts Food or
  drainables with `getAnimalFeedType()`. Feed quantity sums absolute food hunger
  and drainable uses times 0.1. Chickens' feed compatibility must be checked;
  ordinary human food and crop seeds are not automatically donated.
- `ISAddWaterToTrough` pours in one-litre native increments, changes the donor
  and server trough, and can relaunch against other actor inventory when `all`
  is true. Use `all=false`, per-instance validation and bounded stopping.
- Feed uses `ISInventoryTransferAction`, not an invented add-feed command.
  Every transfer must prove native list membership and `getContainer` agree.
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

No guessed daily feed rate: hunger depends on native animal data and settings.
Without a proven three-day feed estimate, breeding retention and culling stay
off. When retention is enabled later, a retained first egg blocks that nest's
collection rather than rearranging or copying eggs.

Evening closing, cleaning and culling are independently disabled until their
native postconditions and live acceptance have been demonstrated. Opening an
already-open hutch is never queued. Unloaded or over-budget evidence is pending,
never proof of an empty flock. No animal is spawned, moved or reconstructed.

## Live acceptance still required

1. Open hutch: observe unaided roosting around 20:00 and departure after 07:00.
2. Farmer: native pour/transfer and one-egg animation, exact donor/egg ownership,
   interrupted and reloaded jobs, unmarked feed left alone.
3. Three day/night cycles with no early lockout; guarded cleaning with no
   replacement of borrowed resources.
4. Natural breeding to the computed target with measured feed-horizon evidence.
5. Before enabling culling: a full day/night cycle above target, named/held/led
   and Strange Folk birds untouched, exact native butcher output delivered.

## Performance

No live before/after measurement yet. Acceptance must report the existing farm
lane timing against the shared 2 ms frame target; bounded headless checks alone
are not a claim of live performance. No additional tick callback is allowed.
