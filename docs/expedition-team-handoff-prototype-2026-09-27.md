# Expedition team and second-view handoff prototype

Private Build 42.20.4 test build, extending the actual-companion split-screen
spike. This follows the player's updated rule: a team may depart without radios.
Radio is required for *new remote commands*, not for departure. This supersedes
the radio-at-departure requirement in the attached v5 planning document.

## Behavior in the prototype

- `SCExpeditionPrototype.start(roster)` accepts an ordered roster of one to three
  living, registered companions. It does not inspect player or companion radio
  inventory. The first member becomes the actual native companion in local
  player slot 1; the main player stays in slot 0.
- The roster remains separate from the player's nearby party. Mission followers
  use the current expedition leader as their decision and formation anchor.
  Their effective order is Follow. The leader temporarily holds position at the
  mission site. Saved standing orders are not changed.
- Direct and atomic group commands to mission members are rejected with
  `expedition_leader_radio_required`. Group vehicle actions prevalidate the
  roster before moving anyone. The same lock applies after handoff. The second
  view grants observation, not direct player input.
- On a decision beat after the leader dies, the next living member in roster
  order is assigned to slot 1. The camera then follows that existing native
  companion. Remaining members follow the successor. With no living successor,
  the prototype runs stock slot-1 UI teardown, unloads the second chunk map,
  clears slot 1, and restores one local view.

## Live cloned-save result

Run `SC-Harness-20260927-005236-a0d3d849`: **44 pass, 0 fail, 0 skip**.
The harness loaded a disposable clone of the Riverside gas-station save with
four companions. Three joined the test mission and one stayed near the player.
The mission site, 512 tiles east, was loaded by the actual companion in slot 1.
The harness then placed the two existing follower actors there with the native
recovery adapter. Both were within 0.35 tiles of the leader after the initial
watch, with active AI decisions. Direct orders to the leader and a follower
were rejected.

A native fatal injury killed the first leader. The next roster member took
slot 1, the original player remained in slot 0, and a screenshot captured the
successor's view. Five seconds later the successor still passed native actor
validation, the scheduler had advanced, and the last member was 7.1 tiles from
the successor. Direct orders to the new leader were still rejected. The game
exited normally; the installed bridge and launcher JSON hashes matched their
pretest values.

Evidence: `build/team-handoff-successor-final.png` and
`build/live-sandbox-runs/SC-Harness-20260927-005236-a0d3d849/`.

## Boundaries

The start call is a harness API, not yet a player-facing expedition UI. The
512-tile transfer is test-only: routing, road travel, combat over a full journey,
return travel, and save/reload of the mission roster are still unimplemented.
The no-radio rule is enforced by having no departure gate and by blocking
remote commands; the test did not inventory-audit radios. A working native
two-way radio path and reception check are needed before any remote order is
allowed. Repeated swaps and the all-dead release were tested later as
described below.

A later private radio probe equipped the player and three mission members with
powered native two-way walkies on the `Living Fellows Team` preset at 90000.
Native signal reception at the remote leader passed, while the companion's
Lua text callback did not fire. See
`docs/expedition-native-radio-probe-2026-09-27.md`. The remote order lock is
still required until message comprehension is verified.

## All-dead release on the cloned save

Run `SC-Harness-20260927-022017-f2e97cbf` passed **45 assertions, 0 failures,
1 skip**. The harness applied native fatal injuries to all three mission
members in its disposable clone. After their native death transitions, the
second local player slot was empty, its chunk map had no loaded chunks, stock
slot-1 UI data was removed, and the primary Riverside player and square lookup
remained available. `build/team-all-dead-release-roster-final.png` shows the restored
single view. The skipped assertion was unforced health loss during the short
preinjury watch. No post-release inventory-page error appeared in the console.

The first cleanup run found that merely clearing slot 1 leaves its inventory
panel updating against a missing player. Calling the game's `destroyPlayerData`
before clearing the slot fixed this. The first release check also used map
coordinate bounds, which the game lazily recomputes after `Unload`; the final
check inspects the chunk references that `Unload` clears.

Run `SC-Harness-20260927-021849-29046963` passed **52 assertions, 0 failures,
1 skip** for two successive native deaths. Slot 1 moved from the first leader
to the second and then to the third original mission companion; the latter
still passed native actor validation and rejected a remote order. That run
exposed a roster ownership bug: the ordinary registry clears `record.actor`
on death. The mission now stores stable actor references so later handoffs do
not depend on those mutable registry records.

This covers two successive handoffs and one all-dead cleanup path. Return,
cancel, save/reload, disable, and stale chunk-load completions remain open.

## Reproduce on a disposable clone

```powershell
& .\scripts\Build-NativeBridge.ps1 -InstallIntoPayload
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -GameMode Rising -LeaderSlotOnly -LeaderRemote -TeamHandoff `
    -WatchSeconds 10 -Screenshot '.\build\team-handoff-successor.png'
```

The wrapper clones the save/cache, temporarily points the launcher at the
candidate bridge, and restores the launcher in `finally`. It does not open
the original save or change the installed bridge.

## Corpse-ready release boundary, 2026-09-28

A later all-dead clone (`SC-Harness-20260928-074048-f2a514a7`) exposed
premature second-view unload: all three mission actors were dead, but none
had finished native corpse creation, and bridge ownership remained pending
after 30 seconds. The mission now retains slot 1 and its loaded area until
every surviving roster actor reports `isCorpseReady()`. The vitals lane also
retries `retireDead` on the inactive dying record instead of skipping it.
The recheck (`SC-Harness-20260928-082005-2bd272ca`) completed all three
native corpses, cleared pending actor ownership, and then released slot 1,
its stock UI, and its chunks while preserving the primary view (49 pass,
0 fail, 2 expected skips). A Kahlua regression and the 9/9 project gate
passed. This does not cover naturally timed team deaths during a long route.

The next destructive clone (`SC-Harness-20260928-083710-ffa8d954`)
confirmed that all three exact native corpse objects inherited their actors'
original inventory containers and worn clothing objects. The game replaced
each dead actor's inventory container. This is immediate death ownership
evidence. A subsequent cloned stage/reload pair (`090120` -> `090826`)
confirmed that the remote corpse chunk persisted three exact worn-item
markers through view unload and save. When the observer visited after reload,
the three native bodies had reanimated, with one tagged item on each zombie.
The bridge now saves pre-unload corpse-chunk bytes after draining the game's
post-unload save queue, which otherwise erased those static bodies. A second
cloned pair (`091359` -> `091521`) also retained one exact test-marked native
bandage per actor in the reanimated zombies' inventories. Remaining work
includes broader inventory cases and long-route naturally timed deaths.
The `091758` -> `091919` pair repeated this with each native item ID checked
after reload.
