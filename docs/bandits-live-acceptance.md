<!-- SPDX-License-Identifier: MIT -->

# Bandits2 live combat acceptance

Goal: complete the live acceptance from the Bandits2 adapter plan on Project
Zomboid 42.21.0 single-player, using the inspected official 42.21 payload.
Automated source tests supplement these checks; they do not replace them.
Historical evidence and dependency fingerprints are in
[validation-bandits2.md](validation-bandits2.md).

The 0.26.69 release gate passes all 28 stages in 190 seconds. Its native class
bytes match the `82AC1A73…` live-tested candidate; only the release manifest
changed. This does not close any remaining live acceptance row. See
[release validation](validation-0.26.69.md).

## Requirements and evidence ledger

| ID | Required live evidence | Current status |
| --- | --- | --- |
| LC01 | Natural two-way melee encounter on the current candidate; exact LF victims, native hit events and unchanged primary identity/slots. Cover recruited companion, camp resident, independent household and Strange Folk across the scenarios. | Passed across all four roles on `82AC1A73…`: recruited `212313-ce892b49`, household `222613-684743fa`, resident `223607-238e14e4`, Strange Folk/Corey `225607-cceed4fc`. Exact personal hit events and native LF wounds were observed. Resident/Corey also have exact native collision damage receipts; player identity/slots/count stayed unchanged. |
| LC02 | Natural firearms in both directions: real equipped guns, consumed ammunition/projectiles, native hits and stock bullet wounds against the intended actor. | Passed on `82AC1A73…` in `SC-Harness-20261025-215549-34ad93fd`: two LF pistol hits from six rounds and three Bandits rounds in the same fight. The exact LF body-part health drop was observed inside the original native Shoot callback, with a matching adapter BulletHit receipt. Primary identity/slots/count unchanged. |
| LC03 | Native shove/unarmed actions in both directions, including actual target reaction and no extra damage. | Passed on `82AC1A73…` in `SC-Harness-20261025-214800-57ec8485`: native Bandits Push caused LF stagger with unchanged health, two stock BareHandHit wounds reached LF, and LF shoved a Bandit with an actual reaction and unchanged target health. LF survived; primary identity/slots/count unchanged. |
| LC04 | Native infected Bandit bite against LF; ordinary zombies remain active; Bandits never enter LF's zombie bite-assistance path. LF human combat must not gain an invented bite attack. | Passed on `82AC1A73…` in `SC-Harness-20261025-220045-a52ea492`: stock Bite created an actual bitten LF body part while ordinary-zombie and human threat lanes stayed active. Every Bandit was excluded by `ZombieFacts`, the production bite-assistance gate, as well as the undead threat list. LF survived; primary identity/slots/count unchanged. LF retains its existing shove/melee actions. |
| LC05 | Real armor in rendered combat on both sides, preserving the native armor/wound path and item condition/identity. | Rendered armor passed in `SC-Harness-20261025-222935-4bf9ee07`: an exact native Bandits shot made a vest hole and lowered LF vest condition 10→7 without health loss; another caused a normal wound. The LF item identity stayed fixed. Three LF torso hits retained Bandits' original armor visuals and native defense 100. Stock Bandits uses visual gear before death; its corpse item identities remain part of LC10. |
| LC06 | Solid walls and stopped vehicles: blocked fire, closed/intact versus open/broken windows, then valid exposed attacks; original Bandits protection behavior retained. | Vehicle melee protection passed in `SC-Harness-20261025-234942-af1e09d8`: three native impacts damaged closed intact glass without a wound, then wounds through open and broken glass. Solid-wall case passed in `SC-Harness-20261026-004012-75e40d2f`: 20 native blocked LOS samples, followed by a verified LF pistol hit after LOS opened; primary identity/slots/count held. Car bullet blocking observed in `002954-dc0a274a` (19 blocks) and `004246-104b086c` (57), but the latter LF kept using the car as cover. The vehicle bullet-to-exposed-wound transition remains open. |
| LC07 | Friendly/neutral bystanders in actual firing lanes; no party conversion, unwanted attack or collateral damage. | Passed in `SC-Harness-20261026-001931-78209fb0` on `82AC1A73…`: 24 actual production vetoes each for a neutral Bandit and a stock loyal Companion, both external protected humans rather than allies. After a normal public flank order, 11 consumed rounds had clear native aim lanes. One exact LF native hit lowered an ordinary zombie's health 1→0.702065, with the same completed attack receipt and LF as its native attacker. Neither bystander was hit, recruited or escalated; main identity/slots/count held. |
| LC08 | Confirmed LF aggression triggers Bandits' native shared hostility, witnessed retaliation and native synchronization, with no independent diplomacy state. | Partial; native retaliation passed, witness scene remains. |
| LC09 | Mixed ordinary zombies and hostile Bandits: live observations/attacks retain both threat lanes; no Bandits steering, undead counts or bite assistance. Sustained base-defense scenario. | Partial: `SC-Harness-20261025-213821-614667ff` observed both production threat lanes; `220045-a52ea492` also verified native-facts/bite-assistance exclusion. Sustained mixed-threat base defense remains open. |
| LC10 | Save/reload during/after combat and native LF/Bandits deaths, preserving exact inventories and corpse contents without duplicated or recreated missing cargo. | Partial; UUID/foreign ownership reload passed, content proof remains. |
| LC11 | Both game load orders, repeated initialization, Off/on, absent/disabled/unsupported dependency and despawn in real clients, preserving ownership. | Native lifecycle sequence passed in `SC-Harness-20261025-215332-8c120f02` with Bandits first: repeated init, actual Mods Off/on, readable missing-interface diagnostic/recovery, reset/reinit, retired aliases and native despawn before registry cleanup. Main identity/slots/count and command binding stayed unchanged. Activation/targeting also observed with LF first; remaining final-candidate reload and death/reanimation coverage stays open. |
| LC12 | Base Watch and expedition return to solo: main player/camera slots, kitchen/garage walls, visible parked vehicles and overhead names inspected after release. | Base Watch component passed native checks in `SC-Harness-20261025-231320-208f3bd1`; manual pixel review confirms the kitchen south cutaway, full solo view and both parked cars. Fifty-two Bandits identity samples retained main ID 1, a unique LF leader and no duplicate list entries. Nearby Scarlet's name is visible. Watched Jill stayed outside primary LOS, so her returned name is unverified. Expedition return and remaining name/garage coverage stay open. |
| LC13 | Walking and driving expeditions with Bandits active, including combat and safe return. Existing driving return-safety failures are prerequisites, not waived by adapter checks. | Open |
| LC14 | Current candidate performance at 1, 4 and 16 LF actors with active Bandits; existing combat/perception/ownership/persistence regressions and full project gate. | Passed: native benchmark `SC-Harness-20261025-224106-18d0c5f4` passes all 15 checks on `82AC1A73…` at 1/4/16 actors. Mean frame intervals without/with integration: 16.633/16.650, 16.667/16.641 and 24.992/26.465 ms. This controlled query workload does not establish battle FPS. Latest full gate passes all 28 stages in 121 seconds, including the human Hold Fire correction; subsequent focused fixture checks pass too. |

## Test rules

- Use disposable clones; keep the original save, normal preset and installed
  Bandits files unchanged. Retain per-run manifests, logs and screenshots.
- Scene setup may place native actors, set a documented time/location and
  provide real equipment. It must not manufacture hit results, heal actors
  during an encounter, replace native attack decisions or clear normal zombies
  to manufacture a combat pass.
- Record controlled callbacks separately from natural AI attacks. An attack
  task or animation alone is not proof of a hit. A routed request alone is not
  proof of the intended native wound or item transfer.
- Record incomplete/failed scenes honestly. Do not rename a narrower result as
  full acceptance or count two separate one-way fights as LC01's same-encounter
  proof. Valid directional evidence may satisfy the matching directional item.
- Complete acceptance requires direct evidence for every row and a final audit
  against the current candidate. The goal remains open until that audit passes.

## Current work

Daylight/ranged scenes exposed and corrected a broader LF firearm input issue.
The native bridge now scopes the companion's own reticle and muzzle context
around the original collision callback. Ordinary LF verification with Bandits
absent also exposed physical aim at walking targets' feet. Native chest aim
improved that control from 0/28 rounds (original bridge), through 2/17 (scoped
floor aim), to 7/8 (chest aim), with actual hit events and health loss. A normal
Unemployed actor with native Aiming 0 also landed 4/5 rounds. These are
individual observations, not average accuracy estimates. A further Aiming 0
run against four ordinary zombies, with Bandits absent, confirmed five native
pistol hits from sixteen rounds in thirty seconds; LF survived and player
identity/slots/count were unchanged (`SC-Harness-20261026-012111-effa470c`). Prone
targets retain low aim. Current bridge is `82AC1A73…`; all 28 project gates
pass. Repeat the remaining Bandits scenes on that build, then continue every
open row. Detailed failures and source/runtime evidence are retained in the
validation report.
