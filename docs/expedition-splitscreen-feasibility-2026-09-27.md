# Expedition split-screen test build — 27 September 2026

## Scope and safety

This is an isolated feasibility build for Project Zomboid 42.20.4 and Living
Fellows 0.25.30. It is not an expedition implementation. It gives no orders
to the extra player, does not implement radio command delivery, and never opens
the owner's original save in the game. The native probe class and its build JAR
belong only to this detached test worktree. Do not copy this payload into a
release or the normal local mod installation.

`scripts/Invoke-SplitScreenSpike.ps1` temporarily points the local game
launcher at the test bridge JAR, runs `Invoke-LiveSandboxTests.ps1` against a
cloned save and isolated `-cachedir`, and restores the original launcher JSON
in `finally`. The final run restored launcher SHA-256
`69E8662B0709DE7F158045D23C017D95AF648735D1EF2A862358EC9AD631FE9C`.
The regular bridge JAR was not replaced.

## Final live run

Run `SC-Harness-20260927-001504-513d1ae2` on the Riverside gas station save:

| Gate | Observation |
| --- | --- |
| Distant native area | `(6596,5307)` was initially unavailable through ordinary `IsoCell.getGridSquare` while the main player was at `(6084,5307)`. After a genuine slot-1 co-op player joined, the square resolved and remained available eight seconds later. |
| Native activity | Nine remote zombies were tracked by object identity; three moved during the eight-second interval. This proves at least native zombie updates in the second area, not full expedition behavior. |
| Visible split view | Both locations rendered simultaneously. At a 2560-pixel client width, `IsoCamera.getScreenWidth(0/1)` returned 1280 and the second viewport began at x=1280. See `build/split-screen-final.png`. |
| Primary player slot | Slot 0 still held the original Riverside player. |
| Player singleton | `IsoPlayer.getInstance()` and `getPlayer()` resolved to the remote slot-1 player during both render and ordinary tick callbacks. The test intentionally fails this identity gate. |
| Living Fellows | The native actor bridge explicitly rejected two local players. All four saved companion restore records were quarantined in the clone. The current mod therefore cannot run an expedition in this mode. |
| Co-op join without controller | The final test used the native `AddCoopPlayer` loading path directly. No joypad join exception occurred. The earlier `setPlayerJoypad` attempt without a connected joypad logged a `JoypadManager.assignJoypad` null error and is not a usable approach. |

The final harness result is **FAIL: 17 pass, 1 fail**. The failure is the
singleton identity change, in addition to Living Fellows' expected rejection.
This is a successful distant loading and zombie update proof, not a passing
companion integration or radio proof.

## Can the second screen be hidden?

There is no supported per-player hide switch in the installed 42.20.4
`IsoCamera` API. The installed `IsoCamera.getScreenWidth` bytecode returns half
the screen width whenever `IsoPlayer.numPlayers > 1`; `getScreenLeft(1)` begins
at half width. Covering the second pane with UI would leave the main view at
half width and would not establish a render-cost saving. Lowering `numPlayers`
to 1 to regain full width would also remove slot 1 from the ordinary chunk-map
lookup and loaded-area loops. A full-width main view while a remote local-player
area remains active needs an engine render hook or a different loading design.

## Design implication

If permanent side-by-side viewing is acceptable, the next prototype should
make the **actual expedition leader** the second local player, with AI control
and no player input path. A separate invisible observer is useful only as a
loading probe: it would introduce a phantom survivor, zombie target, save
identity and inventory into the game. Living Fellows would need a new actor
ownership contract that handles multiple local players and the changing
singleton, plus slot-aware UI, save/load, camera and AI verification. Commands
and fresh reports would still be tied to verified native radio reception.

Multiplayer is a separate port. The current `SCNet` is inert and runtime/actor
code fails closed in client or server mode. A real MP design needs server
ownership of companions and simulation, network replication of their state and
actions, connection and save identity rules, radio authority, and tests with
multiple human clients. Registering a companion as a fake network player would
add the network-player protocol and session lifecycle without removing those
requirements. It is a larger path than the split-screen prototype.

## Re-run

Build the test bridge in this detached worktree, then run on a disposable clone:

```powershell
& .\scripts\Build-NativeBridge.ps1 -InstallIntoPayload
& .\scripts\Invoke-SplitScreenSpike.ps1 -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' -GameMode Rising
```

The wrapper restores the launcher after success or failure. Check its printed
restored SHA-256 and retained run folder before interpreting a result. The
ordinary installed Living Fellows mod and the owner's save are unchanged.
