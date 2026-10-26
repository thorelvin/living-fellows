<!-- SPDX-License-Identifier: MIT -->

# Project A-Life adapter validation

26 October 2026. Unreleased changes on `living_fellows/0.26.69`, alongside the separately documented [human combat fixes](validation-human-combat-fixes.md). Target: Project Zomboid **42.21.0 single-player**.

## Dependency inspected

Official Workshop item **3803984183**, mod ID **ProjectALifeNPCs**, version **1.4.6**, manifest **3148591170031118480**. The selected payload is named `42.20` and declares `versionMin=42.21.0`. The earlier audit copy was 1.3.15; it was refreshed through SteamCMD before implementation. Original files are kept outside the repository under `C:/ZOMBOID/external/project-a-life-audit/` and copied unchanged only into private live-test caches.

SHA-256 fingerprints, relative to the payload's `media/lua`:

| Source | SHA-256 |
| --- | --- |
| `shared/ProjectALife/Compat/ALifeInterop.lua` | `CCA145BBD8899D81A4031211B2F0440FF538B3425E9E0793A64FA9141E39B6DF` |
| `server/ProjectALife/Senses/ALifePerception.lua` | `7E8C47E1482B371F11316DE6287E7EF50D5AFCFDFEB359D2D69C9A0C202EA298` |
| `server/ProjectALife/Decisions/ALifeRelations.lua` | `24553983F8502C2C239037677A5DAFDA885C33240E5D6B2780676B6DE93544B1` |
| `server/ProjectALife/Decisions/ALifeReputation.lua` | `6B21B539DA1B8C998E4401ABF8B39A46D39A0B15E21DE383BEA4B47079703F26` |
| `server/ProjectALife/Decisions/ALifeTargetPolicy.lua` | `FBAB4AAFC293ABA40F7CFA369F8D875E6FA50F26B898B88342B5E52968E8A60A` |
| `server/ProjectALife/Combat/ALifeCombatStrike.lua` | `204B61D42422AFDA41C498C947BB505515739DF6F3F60F08B86AA15E1EB4B9E5` |
| `server/ProjectALife/Combat/ALifeLineOfFire.lua` | `7DA2DF707F6D1FF28A2F797D712FB36F1F597027A6146FC7DB58ABEE2571C0F5` |
| `shared/ProjectALife/Shells/ALifeWounds.lua` | `57D779902B5F4B3EA790647FBDC056EC415DEF55541FEEB3E526E753927D686D` |

Fingerprints pin the inspected evidence. Runtime activation checks interfaces; it does not claim acceptance for every later upstream version.

## Automated checks

The adapter suite covers identity, reciprocal perception, independent reputation, party delegation, self-defence, player lifecycle and UI isolation, cache bounds, owner events, Off/absent/unsupported states, late availability, errors, native removal and retained callbacks.

Installed-source tests execute the unchanged A-Life player locator, reputation, relationships, target policy, Interop, perception, line walker, combat strike and wound modules. They verify actual source target discovery and storage keys, incarnation rejection and seeded wound equivalence. Synthetic native body and geometry boundaries make these deterministic; they do not establish real-world armour, animation, accuracy or window acceptance.

The source wound matrix uses 48 seeded ranged/melee and armour combinations. The wrapper preserves the original body-part outcomes and invokes native damage once. The real stock emergency fallback is checked against application-time immunity. Cache tests exercise 1, 4 and 16 LF members over 1,000 repeated reads each; these prove bounded enumeration, not a live frame-time percentage.

Reproduce:

```powershell
./tests/gameplay/run_alife_adapter_tests.ps1 -RequireALifeSource -ALifeRoot '<ProjectALifeNPCs/42.20>'
./scripts/Test-Project.ps1 -Jobs 2
```

The adapter uses Lua; the shooting follow-up also rebuilds the native bridge to keep the selected firearm target's skeleton available outside the local camera. The full gate includes normal/debug Kahlua compilation, both NPC adapters, existing ownership, combat, perception and persistence regressions, UI, installers and packaging.

The adapter-specific suites pass **54** contract checks, **35** hardening checks and **928** checks against the unchanged upstream source. The full gate includes all **215** production Lua files in normal and debug modes. A delayed perception-adapter table is treated as retryable startup, retaining identity guards until the owner finishes configuring it.

The source-generation build passed **29 of 29 project stages** in **198.6 seconds** (`build/alife-adapter/project-gate-final.log`), before the shooting follow-up below. Protocol remains `42.21-isocompanion-24`; ship the rebuilt bridge with its matching Lua.

Attack admission also checks the supplied source record's UID, active lifecycle and generation against the current exact shell binding. Wound application rechecks that admitted source generation, so even synchronous recycling cannot lend an older attack fresh authority. Recent attack contacts are generation-stamped. The negative control using the earlier adapter fails the intended stale-source assertion (`negative-source-generation.log`); the hardened source passes it without applying a wound.

Live household testing exposed a decision-boundary omission: a non-recruited LF person's A-Life observation was discarded after perception. The fix retains and revalidates that external threat for independent people. Integration regressions exercise the real decision update, including a later truce; a negative control removing only this condition fails at the intended household assertion (`negative-independent-threat.log`).

## Live acceptance ledger

The private `ProjectALifeAdapterProbe` uses an isolated copy of the seed save and source payload, with ordinary zombies retained. It spawns an LF actor through LF and an A-Life actor through A-Life's debug spawner. Loaded weapons and explicit native hostility setup are clone fixtures; damage and hit outcomes remain the owning mods' production behavior.

Early runs exposed fixture problems: a private probe registration mismatch, an indoor observer without an outdoor approach, camp-duty reassignment, protected firing lanes, and a selected A-Life NPC dying before completing its own attack. Those runs are not passing two-way acceptance. Native incoming LF wounds and outgoing A-Life hit events were observed independently.

Completed native combat runs:

| LF role | Run | Evidence |
| --- | --- | --- |
| Recruited companion; A-Life loaded after LF | `SC-Harness-20261026-090929-9178ca8b` | LF health 100 → 96.889; A-Life 100 → 48; one native outgoing hit and two incoming wounds. |
| Recruited companion; final source-generation guards | `SC-Harness-20261026-101758-e5ddb733` | LF 100 → 97.638; A-Life 100 → 82.667; one outgoing hit and one incoming wound. Actual native count stays 1, main stays `sp:0`, list length 4. A-Life is vulnerable, LF is a native NPC and the primary sees the target. |
| Camp resident; A-Life loaded before LF | `SC-Harness-20261026-091231-cfc99cd7` | LF 100 → 98.058; A-Life 100 → 82.667; one outgoing hit and one incoming wound. |
| Strange Folk (Corey); A-Life loaded before LF | `SC-Harness-20261026-092359-2e89f7c9` | LF 100 → 82.632; A-Life 100 → 82.667; one outgoing hit and two incoming wounds. |

Each early passing combat run checks the main actor, engine player-list length and primary reputation key remain unchanged. Their direct Lua read of the static player-count field was not informative; the final probe reads the count through the existing read-only native diagnostic instead. The fixture selects a stock armed profile and uses the owner's exact-alias HostileAct window. Initial silent contacts ten tiles away were refused as `not_noticed` by native A-Life perception; the final fixture starts two tiles apart without overriding visibility or hit outcomes. The first two passes use debug-spawner `damageOutput=30`; later role fixtures use 3 to leave more time for a response. These explicit scene settings are not production damage changes.

The first household run lost the observation. After that fix, later pistol runs fired and reloaded actual ammunition but died without a confirmed hit. The diagnostic run `SC-Harness-20261026-095424-f4d45452` retains native weapon, muzzle, aim-target and collision-receipt traces. Those observations between callbacks did not establish the cause of missed shots. These failures prompted the shooting follow-up below.

Household melee (`SC-Harness-20261026-095956-c811a317`) also reached completed native attack receipts without a confirmed outgoing hit; incoming A-Life wounds and native primary isolation passed. Early observer-relocation experiments failed to establish a valid scene (`100731-86fb6bd5`, `101037-2db0f7cb`). They remain failed experiments, not successful combat acceptance.

### Shooting blocker follow-up

Human combat treated ordinary `native_attack_active`, `native_melee_recovery` and `native_recoil_recovery` waits as failed actions. Decision's safety fallback then lowered the weapon and cleared precise aim. `SCFactionBehavior` now uses the same stationary recovery handling as ordinary companion combat. A negative control with only the old dispatch code fails the new ownership assertion (`build/alife-adapter/negative-human-recovery.log`). Failed stationary holds still report a real error.

The remaining gunfire failure was native body preparation. At the actual collision callback, the selected A-Life actor was alive, vulnerable, shootable, in the native cell and behind a clear sight line. The companion's Java reticle and muzzle context were correct, yet Bullet reported no body intersection. The distant camera had left the target without a usable animated model. A nearby observer produced native skeleton coordinates and a real pistol hit (`SC-Harness-20261026-110750-df7a4375`, LF 100 → 79.578; A-Life 100 → 48).

The native companion now asks the stock model manager to keep its one living, loaded, in-range firearm target prepared while aiming, cancelling a pending camera-cull removal when needed. It does not set visibility alpha, replace foreign AI, create an actor or alter health. Once aim ends, ordinary engine culling owns the model again. The actual weapon range and native floor limit bound preparation; invalid coordinates and ranges are rejected. The stock collision runs once, retaining accuracy, armour, ammunition and damage.

The probe now uses the exact UID from A-Life's completed spawn request. A combat pass requires both the owner hit event and the exact native `OnHitZombie` attacker, victim and requested weapon, together with actual owner-health loss. A later knife fallback cannot pass pistol acceptance. The earlier warmup-only run `SC-Harness-20261026-111210-f9372036` hit with a kitchen knife after exhausting its pistol; it is **not** firearm acceptance.

| Distant-observer household pistol | Run | Native evidence |
| --- | --- | --- |
| A-Life before LF; model residency fix | `SC-Harness-20261026-111502-156ae072` | Exact `Base.Pistol` head hit; A-Life 100 → 48, LF 100 → 94.141, one incoming wound. |
| A-Life after LF; target model preparation | `SC-Harness-20261026-111812-c9a48301` | Exact `Base.Pistol` hit; A-Life 100 → 48, LF 100 → 96.739, one incoming wound. |

Both runs retain a real player who cannot see the target, native player count 1, engine-list length 4 and main reputation key `sp:0`. They close the household pistol blocker without forced hit probabilities or replayed damage. The source suites still pass 54 + 35 + 928 checks (`build/alife-adapter/blocker-source-tests.log`).

Melee exposed a separate spacing error: human combat committed at the outer tolerant acceptance band and stopped approaching, while native melee requires a point strictly inside real reach. It now uses the existing `SC.Combat.meleeSpacing().desired` stance. The regression uses exact fractional positions; substituting only the old spacing code fails the intended range assertion (`build/alife-adapter/negative-human-spacing.log`), while the production gameplay suite passes (`blocker-gameplay-final.log`). The earlier integer-only fixture could not distinguish these distances and was corrected.

Reciprocal household bat combat passes in `SC-Harness-20261026-112535-dcaddfa2`: exact `Base.BaseballBat` hit, A-Life 100 → 71.400, LF 100 → 98.185, one incoming native wound, native count 1 and main key `sp:0`. The fixture starts with Hold Fire on a real pistol, then equips its real carried bat after the first incoming wound. This prevents a fast outgoing kill from precluding the reciprocal check; it changes no health or hit outcomes. The preceding run `111955-c4cf7020`, before the spacing fix, died after repeated zero-hit bat receipts and remains a failure.

The rebuilt bridge SHA-256 is `7263D3BC06E81B9856F1EAF4C56F4B43FFED0A44009619B2D30CAE623DE884D3`. All **29 project stages pass** in **197.1 seconds** (`build/alife-adapter/blocker-project-gate-final.log`), including native isolation controls, range/floor/invalid-coordinate guards, both adapters, UI, both distributions and installer transactions. The strengthened fractional-position gameplay fixture was also rerun separately after that gate and passes, with its old-code negative control failing as intended. Protocol remains `42.21-isocompanion-24`.

### Ordinary LF firearm regression

A-Life and Bandits were absent in `SC-Harness-20261026-113252-4512c6e4`. The fresh regular companion consumed 15 real rounds without a confirmed pistol hit. This longer-range result exposed another input gap: the stock `updateBallistics()` reset the non-local actor's controller to a camera reticle between shots. Supplying the selected aim point only during impact did not keep the preceding physics simulation aimed at that target.

`SCNativeCompanion.updateBallistics()` now performs the stock update, then supplies the selected world-space input to its own controller during aiming. Impact still executes the original collision once with its scoped scratch/input cleanup. No player cursor, camera, slot, hit list, accuracy roll or damage value is changed.

The repeat `SC-Harness-20261026-113701-64549c0a` passes: **six exact-companion `Base.Pistol` hits**, **19 rounds**, and **two tracked zombie deaths** in **21.048 seconds**, with the companion alive. It began with native Aiming **0**, two ordinary zombies around 10/12 tiles, and real pistol/magazines. Both tracked zombies have this companion's firearm-hit evidence; the test retains other camp defenders and makes no exclusive kill-credit claim. Player slots and identity remain unchanged. These individual scenes prove functioning native shooting, not an average hit-rate estimate.

The final per-frame aiming build also passes reciprocal household pistol combat with A-Life loaded after LF in `SC-Harness-20261026-113932-2f7db969`: A-Life 100 → 82.667, LF 100 → 95.140, one exact pistol hit and one incoming wound. The observer remains outside sight, native count remains 1 and main key remains `sp:0`. Final bridge SHA-256: `3FDB349FE251BB5C183F8D4FB70120E0CBE33EBB69284397398EC710F2143253`.

The final build passes **29 of 29 project stages** in **199.4 seconds** (`build/alife-adapter/blocker-project-gate-complete.log`; 202 seconds including runtime preparation). This gate includes the strengthened fractional-position fixture, native isolation and cleanup controls, 215 Lua files in both compilation modes, both adapters, UI, both distributions and installer transactions. `git diff --check` passes, and the built and payload bridge hashes match.

Cold reload passes in `SC-Harness-20261026-095311-36651411`, from stage `SC-Harness-20261026-095209-f771e1ae`. All 11 stable item identities/types match exactly; the saved LF UUID resolves to the restored body once, and A-Life restores its own UID/shell. The primary remains unregistered as LF, key `sp:0`, native count 1, engine-list length 4. Primitive clone-only proof data uses a separate test ModData key, with no production save-schema change.

Base Watch return passes in `SC-Harness-20261026-095721-27d0682e`. Public watch opening/closing, normal kitchen/outdoor walking, advancing primary visibility counters and the kitchen south cutaway pass. All five eligible LF bodies occur once in A-Life perception after release; the actual primary and native count return to solo. Manual review of that run's kitchen/car PNGs confirms the cutaway, both parked cars and nearby Scarlet's overhead name.

The first performance runs had 2/5/17 registered LF actors because moving the observer loaded one more saved companion after initial cohort cleanup. They are not exact 1/4/16 acceptance. The corrected fixture settles that restore queue and removes non-cohort actors through LF's owner before timing, while retaining ordinary zombies and active A-Life.

Exact-cohort performance passes in `SC-Harness-20261026-100137-2da8013f`. Each four-second sample calls the real perception provider 100 times per rendered frame, a deliberate stress workload. A-Life remains active; the native main actor, count 1, engine-list length 4 and `sp:0` key remain unchanged. Adapter On rebuilds the roster 19–20 times per sample, including warmup. Off performs no extra LF roster builds.

| Native LF bodies | Off query time / call | On query time / call | Off / On mean frame time |
| --- | --- | --- | --- |
| 1 | 8.3 µs | 22.5 µs | 16.66 / 16.69 ms |
| 4 | 8.0 µs | 61.7 µs | 16.68 / 16.67 ms |
| 16 | 7.6 µs | 214.3 µs | 16.67 / 35.23 ms |

These are measured totals divided by call counts, with millisecond timer resolution. The 16-body stress case increases frame time under 100 provider calls every frame; this is not a normal-play FPS guarantee or evidence of zero overhead.

Those timings precede the shooting model-preparation fix. Sustained multi-actor gunfight rendering costs have not been re-benchmarked.

`SC-Harness-20261026-093655-4de9663f` completed a normal walking wood expedition with A-Life active and ordinary zombies retained. It tried three forest sites, felled one mature tree, observed seven actual native log drops, picked up one original log and verified that exact item in permitted storage. The original Scarlet returned healthy; the saved car's engine was off and the expedition released solo view. The trip took 551 seconds. Native primary visibility for the previously visible black car stayed valid. Screenshot review shows that car, Scarlet's body and overhead name. The yellow taxi was outside the primary visibility baseline and is not claimed by this trip.

The wood trip and the earlier Base Watch component (`SC-Harness-20261026-093419-59475c2b`) encountered a private completion-audit error after their gameplay checks. The runner's view-focused fixture filter had removed the new audit module; it now retains that dependency. These are component evidence, not successful overall harness verdicts. The Base Watch PNGs show the actual kitchen south wall cut away after a normal walk, both parked cars outdoors, and nearby Scarlet's name. Expedition-return kitchen pixels remain separate from that Base Watch evidence.

Full native armour/window and protected-bystander matrices, prolonged mixed zombie/A-Life base defence, exhaustive authored Strange Folk protection cases and driving-with-A-Life acceptance remain open. Existing driving-return safety remains its own prerequisite. Source wound equivalence and the completed walking trip do not close those scenarios.

Validation was completed before local installation or publication. The player's normal preset and original save were not the live-test execution targets. SHA-256 checks after the shooting follow-up match the original `latestSave.ini`, `players.db`, `vehicles.db` and `global_mod_data.bin` baseline (`build/alife-adapter/blocker-original-save-integrity.json`).
