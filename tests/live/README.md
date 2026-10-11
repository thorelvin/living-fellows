<!-- SPDX-License-Identifier: MIT -->

# Real sandbox harness

This is a private in-game integration harness for the real Project Zomboid
42.21.0 single-player client. It is deliberately outside `SurvivorCompanion`
and is not copied into Workshop staging or release archives.

The runner creates a unique directory under `build/live-sandbox-runs`, clones a
seed save into that directory, copies the current source mod and harness mod,
and starts Project Zomboid with `-cachedir` pointed at the clone. The original
save, real `latestSave.ini`, real mod list, logs, and user database are never
opened by the test client. Local/Vortex mod payloads are made visible through
junctions inside the retained run; the runner does not automatically delete a
tree that contains junctions.

The test mod automatically continues the cloned save and runs a bounded state
machine against real engine objects. The smoke suite verifies:

- exact single-player and native-bridge readiness;
- deferred `SCNativeCompanion extends IsoPlayer` construction;
- registry/native ownership and local-player slot isolation;
- bounded route evaluation on loaded `IsoGridSquare` objects;
- generation of alternative follow paths when the loaded geometry permits it;
- observable follow progress through the production decision loop;
- threshold pause plus left/right room sweep when a loaded room is nearby;
- native rear-facing and formation-facing restoration;
- unchanged player-0 singleton and coordinates throughout companion actions.

Run the static contract first:

```powershell
.\tests\live\run_live_harness_static.ps1
```

Then close Project Zomboid and run the real client test. With no arguments it
uses the save named by the real `latestSave.ini`, but only as read-only input:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1
```

For the release-isolation run, add `-LivingFellowsOnly`. The cloned world is
still used as read-only input, but only Living Fellows and the private harness
are placed in its isolated mod list; no local/Vortex mod junctions are created:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -LivingFellowsOnly
```

To verify the faction overlay visually, provide a PNG destination. The runner
waits for a discovered test faction, focuses the real client, presses `M`, waits
for the in-game world-map draw assertion, captures the client area, then presses
`M` again so the remaining live assertions can finish:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -LivingFellowsOnly `
    -FactionMapScreenshot .\build\faction-map.png
```

Add `-FactionMapOnly` for a fast visual check that skips unrelated movement and
combat probes. If the cloned save is already at its faction cap, this mode uses
an existing living faction as the disposable map fixture.

When a seed needs its map mods but an unrelated gameplay mod interferes with a
focused diagnostic, exclude only that mod from the disposable clone:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -ExcludeModId ExampleModId
```

Use `-PrepareOnly` to inspect the clone without launching the game. Every run is
retained with a manifest, isolated console, event log, and terminal summary.
`PASS` means every applicable assertion passed; environment-dependent geometry
may produce an explicit `SKIP`, never a false pass.

The runner copies Build 42's `reset-mods-42_00.txt` marker before writing the
isolated mod list. Without that marker the first boot of a fresh cachedir clears
`default.txt`, which would leave the harness waiting harmlessly at the main menu.

Build 42 also pauses at a mouse-only click-to-start gate after an existing world
has loaded. The runner waits for the engine's completed-load marker and posts a
left click to the exact game window it started. GLFW requires real mouse state,
so the cursor is placed briefly and restored immediately; retries stop as soon
as the harness writes its first live assertion.

## Companion driving probe

`-DrivingProbe` checks real car mechanics with a companion at the wheel. It looks
for a straight Nav-zone road within about 66 tiles of the observer, moves the
observer to the roadside, spawns a `Base.CarNormal`, and spawns a companion at
the driver's door. The companion boards seat 0 through `SC.Vehicle.boardDriver`,
holds the car's key, and drives through `SC.Driving`. The probe checks that the
engine starts, which way positive steering turns the car, a 10 km/h cruise with
heading hold, stopping on request, the lane scan seeing a parked car placed
16 tiles ahead, braking by itself for that car without touching it, a real crash
into a parked car 20 tiles on at 20 km/h with obstacle braking switched off (the
car must take vanilla crash damage), and letting go and getting out.
`SC_REAL_SANDBOX|DRIVE` lines trace speed, pedals, steering, engine state and the
lane scan every 250 ms. Add `-DrivingScreenshotDirectory` to capture
`driving-cruise.png` at cruising speed and `driving-crash.png` after the crash.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -LivingFellowsOnly -TimeoutSeconds 600 `
    -DrivingScreenshotDirectory .uild\driving-shots
```

Add `-DrivingRoute` to drive a route instead. The probe asks the expedition road
planner for a route 70 tiles down the same road and parks a car in the
companion's lane 18 tiles on, with two still zombies 36 and 40 tiles on. The
companion follows the route, slides round the parked car without touching it,
runs the zombies down (a companion's car kills zombies it touches), and stops at
the end. It then turns round with a three-point turn and drives the route back
round two parked cars waiting in its new lane. Screenshots, when asked for, are
`driving-swerve.png`, `driving-turn.png` and `driving-return.png`.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingRoute -LivingFellowsOnly `
    -TimeoutSeconds 900 -DrivingScreenshotDirectory .\build\route-shots
```

The run needs the branch's bridge on the game's classpath, so install it first
with `.\scripts\Install-NativeBridge.ps1`.
