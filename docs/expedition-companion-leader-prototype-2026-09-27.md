# Actual companion in the second local-player slot

Private feasibility prototype for Project Zomboid 42.20.4 and Living Fellows
0.25.30. This extends the earlier split-screen loader spike in this detached
worktree. It is not a release build or a completed expedition feature.

## What the build does

On a disposable clone of the owner's Riverside gas station save, the harness
waits for all four saved companions to restore and selects one registered native
companion. The test-only `SCSplitScreenProbe.promote` queues that exact
`SCNativeCompanion` through the game's `AddCoopPlayer` loader in local player
slot 1. No new observer body or joypad is created. `SCNativeCompanion` keeps its
generic AI update and NPC ownership; the test performs no actor replacement or
inventory copy. The pinned
bridge's local-player isolation rules are relaxed only for this one owned
actor. The regular player remains in slot 0.

For the distant-area proof, the harness teleports the selected companion 512
tiles east **on the cloned save only**. The teleport isolates streaming from
route navigation. The companion's existing Follow/scavenge state then continues.
The test-only Orders gate rejects new direct commands, including group orders,
for the promoted leader with `expedition_leader_radio_required`. This prevents
the visible second pane from becoming a control channel. No native radio
transmission or reception has been implemented by this prototype, so the
leader's standing order continues without new remote instructions.

## Live evidence

Final run: `SC-Harness-20260927-003500-d9030e91`, 29 pass, 0 fail,
0 skipped. Retained evidence is under `build/live-sandbox-runs/` with that ID.

| Gate | Result |
| --- | --- |
| Real companion identity | Slot 1 held the same object and registry ID selected from the four restored companions; no extra observer was created. |
| Player identity and input | The Riverside player remained in slot 0; leader joypad binding was `-1`. The bridge accepted the scoped two-player layout. |
| Remote world | The target `(6596,5307)` was initially absent from ordinary square lookup, then loaded with the leader in slot 1. |
| Native actor and AI | The leader validated immediately after loading and after a 12-second watch. Its registry ID persisted, the scheduler advanced from frame 882 to 1502, and the actor moved from `(6596,5307)` to approximately `(6590.24,5307.61)` after remote load. The leader remained alive. |
| World conservation check | The actor was absent from its former Riverside square's moving-object list after transfer. The other three saved companions remained healthy within 40 tiles of the main player. |
| Control boundary | `SC.Commands.issue(leaderId, "stay", ..., player)` returned `false, expedition_leader_radio_required`. |
| Split view | The captured client showed Riverside and the distant companion simultaneously: `build/leader-slot-remote-conservation.png`. |
| Environment | No uncaught Java exception or bridge isolation failure appeared in the final console. The original launcher JSON and installed bridge were restored/unchanged. |

## What is still unproven

- **Radio:** The leader has not been checked for an operational two-way radio.
  Native walkie/HAM delivery, two-way range, received-order authorization, and
  truthful replies need a separate live gate. Until then, no new remote orders
  are permitted.
- **Journey:** The 512-tile transfer used a test-only teleport. Road routing,
  continuous area handoff, combat, loot, needs and return travel were not proven.
- **Persistence and cleanup:** Saving/reloading while the companion owns slot 1,
  promotion reversal, death, overlap with the Riverside area, and recovery after
  interrupted loading were not tested. The test clone is discarded after each
  run.
- **Viewing:** Stock 42.20.4 splits the 2560-pixel client into two 1280-pixel
  views while two players are active. A hidden second pane that restores a
  full-width first view still needs renderer work or a different loader.
- **Authority:** The test gates the ordinary `SC.Commands` path. A complete
  expedition implementation needs a full audit of every UI and script entry
  point so no direct remote action bypasses radio reception.

## Run it on a disposable clone

From this detached worktree:

```powershell
& .\scripts\Build-NativeBridge.ps1 -InstallIntoPayload
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -GameMode Rising -LeaderSlotOnly -LeaderRemote -WatchSeconds 60
```

The wrapper creates its own save/cache, briefly switches only the game
launcher's bridge classpath, and restores the launcher JSON in `finally`.
`-WatchSeconds` keeps the split view open after capture for manual observation;
the game then exits. The original save and regular Living Fellows installation
remain untouched. This build lives only in
`C:\ZOMBOID\work\expedition-splitscreen-spike`.
