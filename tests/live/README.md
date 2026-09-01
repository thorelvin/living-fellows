<!-- SPDX-License-Identifier: MIT -->

# Real sandbox harness

This is a private in-game integration harness for the real Project Zomboid
42.20.4 single-player client. It is deliberately outside `SurvivorCompanion`
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
