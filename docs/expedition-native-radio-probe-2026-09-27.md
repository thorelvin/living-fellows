# Native expedition radio playtest kit

This is a private Build 42.20.4 test feature for the cloned Riverside save.
`SCExpeditionPrototype.provisionTestRadios(player, roster)` gives the player and
each selected mission companion a real `Base.WalkieTalkie2`, inserts a native
`Base.Battery`, equips it in the secondary hand, powers it on, tunes channel
`90000`, and stores a native preset named `Living Fellows Team`. Each radio's
native two-way transmit range is 2000 tiles. The kit is explicit; expedition
departure still works without any radios.

## Live evidence

Run `SC-Harness-20260927-012500-4a20c2a3` on an isolated clone of the save:
**57 pass, 0 fail, 2 skip**. The skips are the known companion text callback
limit and an unforced injury that did not occur during the sample.
The latest cloned regression, `SC-Harness-20260927-022407-10d064f3`, passed
**59 assertions, 0 failures, 2 skips** with the current stable mission roster
and all three negative receiver checks. The kit and installed launcher were
restored after the run.

- The player and three selected companions each held the exact spawned radio
  recognized by native `getEquipedRadio()`. All four devices had power 1,
  batteries, channel 90000, and the named preset.
- A native transmission from the Riverside player reached the leader radio
  about 512 tiles away. `DeviceData.getLastRecordedDistance()` changed from
  `-1` to `512`; it stayed `-1` when the leader was tuned to `90001`.
- A native reply from the leader reached the player at the same distance and
  produced a matching `OnDeviceText` event on the player's radio.
- A follow-up cloned run, `SC-Harness-20260927-013020-ce041656`, passed
  negative receiver checks: channel 90001, powered off, and volume zero each
  left the leader's native signal distance at `-1`; restoring normal settings
  delivered the next transmission at distance `512`.
- An unwrapped player-to-leader signal did **not** produce `OnDeviceText` on
  the leader's radio. The native text path returns early for a non-local
  companion, even while its actual actor occupies slot 1. A private scoped
  native bridge now permits that callback only during the synchronous test
  transmission and restores the companion's non-local identity afterward.

The harness uses `ZomboidRadio.SendTransmission` with the verified equipped
devices. This proves a native signal path and frequency gate. The command
slice below proves one received text command; a player-operated transmit UI,
placed radios, HAM sets, power depletion, interference, and moving-range
boundaries remain open.

Evidence: `build/live-sandbox-runs/SC-Harness-20260927-012500-4a20c2a3/` and
`build/team-working-radios-final.png`.

## Five-radio Riverside kit and reload

The kit-only cloned run `SC-Harness-20260927-025846-5163cfdd` equipped the
Riverside player and **all four** saved companions. It saved each companion's
exact native `Base.WalkieTalkie2` as an equipped inventory item. A first reload
of an earlier kit exposed that the existing companion inventory persistence
recreated radio items without their `DeviceData`; battery, charge, channel and
preset therefore returned to defaults. The private build now captures and
restores those native fields through the existing item snapshot path.

Run `SC-Harness-20260927-030001-2e2cf655` reloaded the stateful cloned save
and passed **19 assertions, 0 failures**. All five exact radios remained
equipped, powered, battery-backed, tuned to 90000, and carrying the native
`Living Fellows Team` preset. The game's ordinary Device Options panel was
also captured at `build/riverside-five-radios-stateful.png`.

The verified save remains under
`build/live-sandbox-runs/SC-Harness-20260927-025846-5163cfdd/cache/Saves/Rising/`.
It is an isolated Living Fellows test save. The original Riverside save was
not changed; it has a different mod list, so this clone has not been installed
as its replacement. The native signal probe still covers the player and three
mission members; the fourth companion's radio was checked for operational
state and reload, not a distant request/reply.

The same five-radio kit was also run on a clone that retained the original
save's four mod entries, including PZRadioLink. Provisioning passed in
`SC-Harness-20260927-033535-25734d5a`; reload passed in
`SC-Harness-20260927-033651-3d280e28`. All five radios remained equipped,
powered, battery-backed, tuned to 90000, and preset after the reload. This
checks coexistence for kit and save restoration. The radio command probe has
only run with the isolated Living Fellows mod list.

## Scoped native text and first command

In `SC-Harness-20260927-032505-d675de57`, the cloned live run passed **67
assertions, 0 failures, 2 skips**. The scoped wrapper delivered the exact
`OnDeviceText` payload on the leader's actual equipped radio at 512 tiles.
The companion remained non-local after the callback. Mistuned, powered-off,
and muted receiver cases generated neither distance nor text.

The harness then sent `set_move_mode walk` with a per-mission correlation
token. The native text callback matched the pending radio and token, and the
ordinary Commands owner changed the leader's effective mode from `copy` to
`walk`. A direct Orders call was rejected. Attempts to change the mode again
while the receiver was mistuned, off, or muted returned `radio_no_ack` and
left it at `walk`. The command gate accepts only this one command and only
after the exact synchronous native receive event. This is a private harness
entry point; there is still no player-facing radio command control.

The follow-up run `SC-Harness-20260927-033203-763363f9` passed **68
assertions, 0 failures, 2 skips**. After the first leader died and the second
original team member took slot 1, the player transmitted another correlated
order. The successor's own mode changed from `copy` to `walk`; direct Orders
remained blocked. Screenshot: `build/team-radio-command-handoff.png`.

The runs retained events and consoles under
`build/live-sandbox-runs/SC-Harness-20260927-032505-d675de57/` and
`build/live-sandbox-runs/SC-Harness-20260927-033203-763363f9/`.

## Sender gates and full saved mod list

`SC-Harness-20260927-034628-3bd9b0c4` passed **74 assertions, 0 failures,
2 skips** on a cloned save using the original four mod entries. The first
accepted command and the successor command after handoff still changed the
appropriate leader's mode. Player radio off, wrong channel, microphone mute,
zero charge, and immediate unequip could not change the standing mode. An
immediately unequipped leader radio also returned no acknowledgement.

The first full-mod run exposed a native cache edge: `getEquipedRadio()` kept
the previous radio until the character update after a hand change. The
command path now confirms that the native cached radio is still in the
actor's current hand or back slot. This check applies to both endpoints.
It is an equipment-state fix, not proof of placed-device behavior or all
native operating configurations.

## Placed walkie and HAM native transport, 2026-09-28

The disposable `-TeamRadioPlacedProbe` builds each placed station with the
same world-item and `IsoRadio` proxy pattern as Build 42's
`ISDropWorldItemAction`. The exact `Base.WalkieTalkie2` and `Base.HamRadio1`
items remain on the Riverside square; each proxy shares its item's native
`DeviceData` and is registered in `ZomboidRadio.getDevices()`. The pinned
item scripts report native transmit ranges of 2,000 and 7,500 tiles,
respectively. The test reads those properties at runtime.

With the actual companion leader 512 tiles away and offset on **both** axes,
`SC-Harness-20260928-023833-0b725163` passed native receipt and exact
`OnDeviceText` identity in both directions for both placed stations. The
leader's field radio remained a native `Base.WalkieTalkie2`; all three other
saved companions followed him, natural zombies moved in the remote area,
and the original launcher was restored.

At 2,047 tiles, `SC-Harness-20260928-024304-e7ee8957` passed the focused
asymmetric case: the placed HAM reached the leader, the placed walkie did
not, and the 2,000-tile field walkie reached neither placed station on the
return leg. The player-held walkie also had no return receipt. The result
proves that a stronger base station does not strengthen the field
transmitter. The remote radio site happened to have no natural zombies;
population and danger were deliberately skipped for this radio-only run,
not counted as W02 evidence.

An initial run at 512 tiles with the leader shifted only east
(`SC-Harness-20260928-023546-cd7d31f5`) failed both placed-radio receive
checks while the held player radio received the same transmission. Reading
the pinned `ZomboidRadio.DistributeTransmission` bytecode showed that its
placed-device branch admits a transmission only when **both** source tile
coordinates differ from the device coordinates. The successful two-axis
repeat isolates this native same-row limitation. The prototype has not
altered native delivery to hide it; a mission whose endpoints share a row
or column remains a compatibility concern.

The test driver calls native `SendTransmission` with each actual station's
position and measured range after checking native power, channel, battery,
and local placement. It does not yet use the game's player-operated mic or
Device Options action to originate the message. The later timed-placement
probe below covers the game's placement action, but 3D cursor input,
player-away gating, interference, and command/acknowledgement behavior with a
selected placed station remain open. These transport probes do not close
WP01-B or WP02.

The placed-device save/reload probe staged a five-walkie kit plus the exact
placed walkie and HAM in `SC-Harness-20260928-024933-9fd45456`. A fresh
clone of that staged save (`SC-Harness-20260928-025059-bd97e45f`) restored
native item IDs `1059513303` and `1808929110` with one world item and one
matching `IsoRadio` proxy per ID, no matching carried copies, and one native
radio-manager registration each. Both retained power, battery, channel
90000, and model transmit range; each received a new `OnDeviceText` event
after reload. The five equipped radios also passed their existing reload
checks. This proves placed-item and proxy continuity across this ordinary
save boundary. Destruction and mixed-save crash boundaries remain open for
R26.

The native pickup follow-up ran on a fresh clone of that staged save in
`SC-Harness-20260928-031251-7c9a4843`. The saved player carried 97.38
weight against a 12-weight limit, so vanilla `ISGrabItemAction:isValid()`
rejected the first normal context-menu grab (`030531`). The probe temporarily
lifted the capacity gate in its disposable copy, then used
`ISWorldObjectContextMenu.onGrabWItem` to queue the real timed action. It
completed with the **same** walkie ID `1059513303` in inventory exactly once,
zero matching floor items, zero matching `IsoRadio` proxies or native manager
registrations, and channel 90000 plus battery/power retained. The probe
restored its capacity settings afterward. This closes the native pickup
identity and proxy-cleanup check for the loaded clone; the heavily overloaded
original player would need to make room before a normal pickup.

The next stage used the **game's own timed placement action** rather than the
test helper's direct world placement. In
`SC-Harness-20260928-033947-a66624d3`, the harness put a genuine walkie and
HAM in the player's inventory and queued `ISDropWorldItemAction` with
`isPlaceItem=true`, as the game's 3D placement cursor does. Both actions
completed on separate adjacent squares. Each exact native item moved out of
inventory and had one matching `IsoRadio` proxy with the same `DeviceData` and
one radio-manager registration. The walkie ID was `585586791`; the HAM ID was
`1421120772`. A fresh clone of that saved state,
`SC-Harness-20260928-034132-be9cb03f`, restored both IDs, one item/proxy pair
per ID, power and channel 90000, and fresh native `OnDeviceText` reception.
The game's timed context-menu grab then moved the same walkie ID into inventory
and removed its world item, proxy and registration; power and channel survived.
That pickup again required a temporary capacity override in the disposable
clone because the saved player carried about 97 weight against a limit of 12.
The live action, reload and pickup runs all passed with zero harness failures.
The 3D cursor's player input was not clicked in this automated run, and
destruction remains open for R26.

To repeat the focused checks on disposable clones:

```powershell
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -LeaderSlotOnly -LeaderRemote -LeaderRemoteOffsetY 16 `
    -TeamHandoff -TeamRadioFixture -TeamRadioTextProbe -TeamRadioPlacedProbe

& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -LeaderSlotOnly -LeaderRemote -LeaderRemoteOffsetX 2048 `
    -LeaderRemoteOffsetY 16 -TeamHandoff -TeamRadioFixture -TeamRadioPlacedProbe

# After staging a placed-radio kit, replay its saved clone with the exact
# native item IDs reported by placed_kit_staged_ids:
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -LeaderSlotOnly -TeamRadioKitOnly -TeamRadioPlacedProbe `
    -TeamRadioTimedPlacementProbe

& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave '<staged-clone-save-directory>' -LeaderSlotOnly `
    -TeamRadioKitVerifyOnly -TeamRadioPlacedProbe -TeamRadioPlacedPickupProbe `
    -TeamRadioPlacedExpectedWalkieId 1059513303 `
    -TeamRadioPlacedExpectedHamId 1808929110
```

## Reproduce

```powershell
& .\scripts\Build-NativeBridge.ps1 -InstallIntoPayload
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -GameMode Rising -LeaderSlotOnly -LeaderRemote -TeamHandoff `
    -TeamRadioFixture -TeamRadioTextProbe -TeamRadioCommandProbe `
    -WatchSeconds 25 -Screenshot '.\build\team-radio-command-transition.png'
```

The wrapper clones the save, runs the candidate payload, and restores the
installed launcher. It does not alter the original Riverside save.

## Interactive playtest copy

`scripts/Start-ExpeditionRadioPlaytest.ps1` creates a fresh isolated game
cache from the verified five-radio reload save. It removes the harness mod,
keeps the original save's four mod entries, adds the current private Living
Fellows payload, and selects the copy for Continue. While the interactive
client runs, the script points the game launcher at the matching private
native bridge. On exit it restores the exact original launcher JSON.

```powershell
& .\scripts\Start-ExpeditionRadioPlaytest.ps1
```

The script must remain running until the game closes so its `finally` block
can restore the launcher. The original Riverside save, installed Living
Fellows mod, and source verified radio save remain unchanged. A prepare-only
check produced
`build/radio-playtest-saves/LF-RadioTest-20260927-055459-f7ac882c/`:
its save lists the four original mods, contains no harness mod or config, and
the installed launcher retained SHA-256
`69E8662B0709DE7F158045D23C017D95AF648735D1EF2A862358EC9AD631FE9C`.
An interactive launch reached the main menu; the smoke client was then
closed and the same launcher hash was restored. The specific newly prepared
copy has not yet been loaded into gameplay, but the source five-radio save
passed the separate live reload assertions above.

A later fresh prepared copy
`LF-RadioTest-20260927-063749-6d21ce93` passed a focused live reload in
`SC-Harness-20260927-063805-ded6d3ea`: the player and all four saved
companions each held a powered, equipped native radio with the team preset
and channel 90000. The source copy was unchanged by this harness run. An
interactive copy `LF-RadioTest-20260927-063929-9bd1fcb0` was then launched
for the owner's in-game inspection; closing that client restores the original
launcher through the playtest script's `finally` block.
