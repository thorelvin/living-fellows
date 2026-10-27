<!-- SPDX-License-Identifier: MIT -->

# EMMA building controls and expedition station

27 October 2026, Project Zomboid 42.21.0 single-player, working continuation
developed on `living_fellows/0.26.71` after `0d8791e6`, included in the
`living_fellows/0.26.72` checkpoint. Source and rebuilt bridge are in the
repository. Bridge SHA-256:
`26b1c9eafafcbdbf8c7f772cb6ffcabebf6d9dfc997bbf2c653c54d4528a7de8`.
The implementation was installed locally before the release-number bump.
Steam Workshop publication is a separate step.

## Implemented

- Building-scoped connections and a separate persistent access password.
  Computer access and claiming a bank as camp cannot bypass its security.
  Existing map locks remain unchanged until a confirmed command.
- Native doors and grouped shutters, fitted motors/relays, live obstruction
  checks, lighting groups and constructed floodlights. Physical installations
  revalidate tools, skill, parts, reach and the exact device at completion.
- Native generator start/stop/repair services, existing camp refuelling,
  cancellation, automatic retries and removable remote-start batteries.
- Exact serialized radio/UPS hardware, native world-radio reception at the PC,
  six-hour healthy-battery backup, portable assembly ownership and recovery
  of actual mounted parts after a native furniture pickup break.
- Mission review/launch, real two-way station reports and recall, route orders,
  and Marcus booking through the existing service. Confirmation pins the crew,
  mission, selected car and installed hardware. Search/fishing keep their
  existing 1-8 item limit; wood retains its independent 256-receipt ceiling.
- Native alarm flags and building-specific silence, siren/PA audio with zombie
  noise, contacts, motion detection, bounded history and opt-in routines.
  Moving the authorizing PC suspends its routines. Return-garage closure waits
  for the actual stopped car inside and a clear crew/door footprint.
- Adaptive numbered service menus, visible confirmation/review text, readable
  component condition/charge labels, and an original separate antenna overlay.
  The enlarged radio is bolted low on the right bezel with its antenna rising
  above it; responsive clearance keeps the hardware away from live text.

No power mod is required. LF's own circuits control lighting relays and the
generator supply through their native actions. Individual refrigeration
isolation is **not implemented**. The inspected engine delegates fridge power
to `ItemContainer.isPowered -> IsoObject.checkObjectPowered ->
ItemContainer.isObjectPowered`; there is no per-fridge on/off setter.
`IsoGridSquare.setHaveElectricity` merely refreshes light switches, and a
`NoPower` zone does not disconnect generator supply. A future extension must
cover native cooling, hum, generator load, persistence and unloading together,
while preserving every container/item identity. This change does not rewrite
food temperatures, container types, native player lists or camera ownership.

## Automated verification

The full project gate passed **29/29 stages**, including normal and debug
compilation of all 236 Lua files, native API/ownership contracts, gameplay,
navigation, combat adapters, UI, installer transactions and both packages.
The UI suite and native installation scenario were also rerun after the final
physical-reach check, including refusal to fit hardware through a wall.

The new production-module fixture covers independent building access and keys,
never-opened PC identity, live-session identity retention, stale/expired/replayed
consent, moves, obstruction and actuator power, native light idempotence,
constructed lights, bounded history, supply changes, routines, actual hardware
ownership and original battery isolation, UPS drain, full-inventory removal,
forged/changed endpoints, three-coordinate station origin, LF circuit membership,
normal search quotas, native integer place queries, changed mission/car refusal,
local generator command ownership and timed retries. Expedition regressions
cover an exact station return receiver and reject a report reaching another
receiver without revealing a fresh count.

Gate evidence: [computer-controls-gate.log](../artifacts/emma/native-acceptance/computer-controls-gate.log).

EMMA job-advice regressions also cover interrupted pickup wording, unknown
diagnostics, real retry countdowns, due retries and manual-only cargo recovery.
The full gate passed again after these changes. Pre-transfer pickup animation
failures can retry after the normal pause; unconfirmed transfers remain parked.

## Completed native scenarios

All native runs use a new disposable copy of the existing Rising save. The
original office PC at `12035,6739,0` is map furniture. Test hardware, tools,
Electrical levels and one generator are explicit fixture supplies. Game
interfaces, native transfers, power queries and radio receipts are not mocked.

| Scenario | Result |
| --- | --- |
| Real Use computer and queued radio/UPS installation | Passed |
| Native item serialization, same IDs and custom mod data | Passed |
| World receiver at the real PC, actual native text event | Passed |
| Original handset battery/channel isolation | Passed |
| Real door: occupied footprint, unlock, move, exact-once confirmation | Passed |
| Complete furniture pickup/place with hardware and OS memory | Passed |
| Capacity-respecting unmount, exactly one returned handset | Passed |
| Forced native pickup break, exactly one original battery world drop | Passed |
| Full native world save and second-process reload of fitted station | Passed |
| Reloaded PC identity, building connection/history, original parts and reconstructed receiver | Passed |
| Remote generator start/stop, exact starter battery and 1% drain | Passed |
| Companion native start, stop and repair using bagged scrap | Passed |
| Actual grid/generator outage with UPS-powered PC only | Passed |
| Native PA, alarm arm/disarm, two simultaneous building alarms | Passed |
| Native walking launch, two-way report and recall from station | Passed |
| Walking solo return with terminal manually closed beforehand, then native reopen | One completed run |
| Walking solo return with station kept open / briefly paused at teardown | Native lighting crash |
| Native driving launch, report while driving and recall | Passed up to parking/reunion |

Station reports were verified against an equipped real crew radio, the mounted
native PC receiver and the existing leader text context. Player 0 remained the
main player throughout the completed hardware/power scenarios. The game uses
a native world-radio quirk that excludes a sender sharing either receiver axis;
the reception fixture uses distinct physical X and Y source coordinates.

Hardware evidence: [terminal-controls-evidence.log](../artifacts/emma/native-acceptance/terminal-controls-evidence.log).
Power evidence: [terminal-controls-power-evidence.log](../artifacts/emma/native-acceptance/terminal-controls-power-evidence.log).
Save/reload evidence: [native world save](../artifacts/emma/native-acceptance/terminal-controls-savesetup-evidence.log),
[second-process reload](../artifacts/emma/native-acceptance/terminal-controls-saveverify-evidence.log).
The second process loads the saved disposable world without copying the seed
again. It verifies exact radio/battery IDs and custom mod data, battery charge,
computer identity, building connection/history, reconstructed station authority
and absence of duplicate mounted items in the player's inventory.

## Acceptance remains incomplete

The walking expedition reached home and entered the existing primary-view
restore path (`generation=2 mode=B`). The process then crashed in
`Lighting64.dll+0x23fd`, native access violation `0xc0000005`, before a solo-return
screenshot could be accepted. This establishes the observed failure and call
boundary; it does not establish the root cause or prove a baseline comparison.

The driving run used a loaded native `Base.CarTaxi` as an explicitly serviced
fixture with a newly marked parking area. It drove and answered real radio
orders. On return it stopped its engine and chose `road_unload_fallback` with
`parking_footprint_outside_area`. The crew then remained in `awaiting_player`
until the bounded acceptance run timed out. Complete garage parking and solo
return are therefore **not passed**. The car was not removed or respawned.

Evidence: [native return crash](../artifacts/emma/native-acceptance/terminal-station-return-crash.log),
[driving fallback](../artifacts/emma/native-acceptance/terminal-station-drive-fallback.log).
Checked-in console transcripts normalize trailing whitespace; the local run
captures retain the original output.
A repeat with the terminal manually closed before arrival completed solo
return, retained a living crew member and reopened the station. Evidence:
[closed-terminal walking return](../artifacts/emma/native-acceptance/terminal-station-walk-closed-evidence.log).
A later experiment closed the screen immediately before native teardown and
planned to reopen after the primary renderer settled. It still crashed in the
same native lighting function, so that speculative handoff was removed. No
terminal/view teardown workaround is shipped or claimed here. The checked-in
repeat harness can meet the crew in the kitchen while preserving the native
return preconditions; it must not force demotion or silently accept a fallback.

Large-business profiling, live bank/police access, native shutter obstructions,
and long-running routines
remain additional acceptance coverage. Native serialization/assembly transfer
and full native world save/reload are completed; they are not substitutes for
those remaining scenarios. The existing expedition return-safety prerequisite and
the new individual-fridge extension remain outside a completed release claim.

## Assets

The antenna uses built-in image generation with transparency and an original
1993 radio/CRT treatment. The revised mounting rail puts both bolt tabs on the
solid right bezel, above and below the radio, while retaining the approved
radio/antenna size and position. Saved prompts and references:
[station-antenna-v2.prompt.txt](../artifacts/emma/station-antenna-v2.prompt.txt).
Production asset: `SurvivorCompanion/42/media/textures/Terminal/Skin/crt-radio-antenna-v2.png`.
The original asset and its prompt remain available for comparison.
The siren is original deterministic waveform synthesis; the announcement uses
local Windows Microsoft Zira Desktop speech. Both are reproduced by
[generate-building-audio.ps1](../artifacts/emma/generate-building-audio.ps1).
No audio service, network call or hosted language model is used in game.
