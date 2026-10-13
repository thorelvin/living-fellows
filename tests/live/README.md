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

If a direct executable launch reports `SteamAPI_Init() failed` while the
desktop Steam shortcut works, add `-SteamLaunch`. This sends the same isolated
`-cachedir` and test arguments through Steam app 108600. The runner waits for a
new Project Zomboid process tied to the cloned cache before it controls or
stops that process; it never treats the Steam process as the game. Steam and the
harness must run in the same Windows user context. This option does not change
the user's persistent Steam launch options.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -SteamLaunch
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

The focused Arthur and Spiffo Pack probes each use a separate cloned-save run.
They scan a loaded 81 by 81 area for an eligible real bedroom or living room,
then create the authored encounter there. Arthur's probe waits for the native
bed pose, checks his bedside menu and dialogue, leaves him alone, then returns
to verify a native corpse on the bedroom floor. The Pack probe checks all
four native costumes and empty hands, then enters the den and checks the spoken
invitation, hostile reveal, and four equipped shivs. A seed near suitable
houses can use its current location; use `-OddballSiteX` and `-OddballSiteY`
together to search around another loaded map point. The screenshot option
captures the bed scene or the four costumes before the Pack reveal:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -LivingFellowsOnly -OddballArthurProbe `
    -OddballSceneScreenshot .\build\arthur-live.png
.\scripts\Invoke-LiveSandboxTests.ps1 -LivingFellowsOnly -OddballPackProbe `
    -OddballSceneScreenshot .\build\spiffo-pack-live.png
```

For a targeted Arthur bed pose diagnostic, pair `-OddballBedX` and
`-OddballBedY` with `-OddballPoseOnly`. The probe records native on-bed flags,
physical bed occupancy, entry geometry, and the fallback reason, then captures
the scene and stops before the bedside story.

The runner copies Build 42's `reset-mods-42_00.txt` marker before writing the
isolated mod list. Without that marker the first boot of a fresh cachedir clears
`default.txt`, which would leave the harness waiting harmlessly at the main menu.

Build 42 also pauses at a mouse-only click-to-start gate after an existing world
has loaded. The runner waits for the engine's completed-load marker and posts a
left click to the exact game window it started. GLFW requires real mouse state,
so the cursor is placed briefly and restored immediately; retries stop as soon
as the harness writes its first live assertion.

## Companion driving probe

The Markus passenger proof uses the same isolated driving fixture with the
real player in native seat 1. It verifies that ordinary driving still refuses
the passenger, the service-only bridge entry drives a short straight leg with
player slot 0 unchanged, and both occupants can exit after stopping. It also
claims a native taxi, checks its real part containers, settles the first free
ride, and pays the second fare with an exact loose jewelry item:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -TaxiPassengerProbe `
    -LivingFellowsOnly -NoSteam -TimeoutSeconds 300
```

The runner prints a retained **Taxi recovery seed** path. Reload that clone in
a new game process to verify the same native vehicle SQL ID and paid item ID:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -TaxiRecoveryResume `
    -SeedSave '<Taxi recovery seed path>' `
    -LivingFellowsOnly -NoSteam -TimeoutSeconds 300
```

This proves the fare and cab recovery layer. Public radio dispatch, pickup,
route service and vehicle retirement remain behind the booking gate.

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
    -DrivingScreenshotDirectory .\build\driving-shots
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

Add `-DrivingTurn` instead to drive street to street. The probe finds a side
street that meets the test road, starts the car 28 tiles before the junction,
and asks the planner for a route 26 tiles up the side street. It checks that the
route turns at least 60 degrees and that the car takes the corner, arrives
within 4 tiles of the route end, and keeps to the right-hand lane of the new
street. The screenshot, when asked for, is `driving-corner.png`.

WP5 verifies normal companion AI without unregistering Decision. The route
holds at the outbound wreck for 2.5 real seconds, then checks seat zero again
through the turn and after arrival. Decision must continue ticking throughout.
Ambient foot threats must not pull a healthy driver from the wheel, including
zombie pressure, player danger, and nearby hostile humans. Medical emergencies,
urgent needs, an explicit retreat order, a faction emergency, or a native grab
still preempt the drive.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingRoute -DrivingWithAi `
    -LivingFellowsOnly -ExternalUiControl -TimeoutSeconds 900
```

The negative control disables only the cached copy of Decision's driving gate.
It must fail at the stopped-driver seat check and exit nonzero; a PASS would
show that the positive probe did not actually depend on the gate.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingRoute -DrivingWithAi `
    -DrivingGateNegativeControl -LivingFellowsOnly -ExternalUiControl `
    -TimeoutSeconds 900
```

The full-road block mode first asks for an alternate route and samples every
segment in the loaded world. If no loaded alternate exists, it reports
`LIVE_SANDBOX_SKIP`, never `LIVE_SANDBOX_PASS`. If one exists, parked cars span
the road; the production drive job must block, replan around an avoidance
circle, arrive without contact, and stay in the driver's seat.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingBlocked `
    -LivingFellowsOnly -ExternalUiControl -TimeoutSeconds 900
```

The save test uses two successive disposable clones. Stage saves while the
companion is moving in seat zero with the exact key verified in its inventory
or the car's ignition. The observer stands on a clear roadside tile within
12 tiles of the moving car so the car loads again with the save. Stage then
waits for the game's normal save and exit. Its
output prints the **Driving resume seed** path. Use that
exact retained clone as the second run's `-SeedSave`; Resume creates another
clone and checks the saved seat record, driver-door placement, key, parked car,
and absence of an automatic drive after five seconds.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingSaveStage `
    -LivingFellowsOnly -ExternalUiControl -TimeoutSeconds 600
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -DrivingSaveResume `
    -SeedSave 'PATH PRINTED AS DRIVING RESUME SEED' `
    -LivingFellowsOnly -ExternalUiControl -TimeoutSeconds 600
```

The run needs the branch's bridge on the game's classpath, so install it first
with `.\scripts\Install-NativeBridge.ps1`. Before replacing the installed
bridge, preserve both its JAR and the installer script from that same version.
After all clones exit, run the saved installer with
`-PrebuiltBridgeJar <saved-jar>` to restore the original installation. The
current branch's installer checks its own protocol and rejects an older JAR;
it cannot restore a bridge from an earlier version. The click-to-start helper
targets only the client process it
started, waits for the world-load log, and stops clicking once live results
begin; the in-game harness separately checks that game time runs.
With `-ExternalUiControl`, the runner never sends a click or key to the game
window and never captures its pixels. A separate UI controller must click the
Build 42 start gate after the runner prints the world-load message.

## Expedition car probe

`-DrivingProbe -TeamDriveProbe` uses a disposable save clone to mark a parking
area, select its car, board a three-person squad into native seats, drive to a
site, leave the car, return, park within the marked area, and get everyone out.
The car uses a real key and measured fuel. `-DrivingRemote` first checks physical
driving beyond player 0's loaded area. These probes need the matching branch
bridge; preserve and restore the installed bridge as described above.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -TeamDriveProbe `
    -LivingFellowsOnly -ExternalUiControl -NoSteam -TimeoutSeconds 900
```

The restart probe takes two runs. Stage saves a cloned world mid-drive and
prints its retained save path. Resume clones that stage save, verifies the
restored car and team, then checks automatic fresh boarding and the return to
the marked parking area. Pass the exact stage path to `-SeedSave`; the runner
also requires its stage proof file. Never use an active playtest save as seed.

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -TeamDriveProbe `
    -TeamDriveRestartStage -LivingFellowsOnly -ExternalUiControl -NoSteam `
    -TimeoutSeconds 900
.\scripts\Invoke-LiveSandboxTests.ps1 -DrivingProbe -TeamDriveProbe `
    -TeamDriveRestartResume -SeedSave 'PATH PRINTED BY STAGE' `
    -LivingFellowsOnly -ExternalUiControl -NoSteam -TimeoutSeconds 900
```
