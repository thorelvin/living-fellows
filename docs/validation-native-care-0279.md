# Native companion care — 0.27.9

Validated on Project Zomboid 42.22.2, 12 November 2026. Base commit:
`4817fcc7` on `living_fellows/0.27.9`. This is a Lua change; the native bridge
is unchanged.

## Behaviour

Downtime now queues stock timed actions for equipment repairs, cleaning dirty
bandages, washing people and clothing, and making splints and sheet ropes.
`SCNativeCareActions` selects and validates the inputs; `SCNativeActions` owns
the action and inventory cleanup. The game applies the effects, costs, sounds,
animations, repair rolls and recipe outputs.

- Legacy repairs use `ISFixAction` and `FixingManager`. Build 42.22 melee
  repair recipes use `ISHandcraftAction`, including their work-surface and
  material requirements. A failed repair roll does not receive a scripted
  condition bonus. Unsupported equipment is skipped: vanilla `Base.Pan`, for
  example, has no repair path in the inspected build.
- Dirty dressings use `ISCleanBandage`, with the native clothing-cleaning
  replacement path available where supported. The exact replacement returns
  to the original bag; missing or ambiguous outputs are never recreated.
- Body washing, including the shower's washing step, uses `ISWashYourself`.
  Clothing uses `ISWashClothing`. Existing shower outfit handling remains.
- Splints and sheet ropes use the installed `Base.MakeSplint` and
  `Base.CraftSheetRope` recipes through `ISHandcraftAction`.

Protected supplies stay protected. Claims cover the exact inputs, soap and
work surface, and renew during long actions. Cancellation waits for the
matching action's inventory cleanup. Ordinary save snapshots do not cancel
these chores; native inventory changes occur synchronously on the game thread.
No new background service or global action wrapper was introduced.

## Automated verification

The existing Behaviour check includes one native-care group, running the
installed stock Lua actions against controlled engine boundaries. It covers
repair successes and failures, protected supplies, cancellation, duplicate and
late callbacks, finite-water and soap use, bagged dressing replacement, blocked
bag returns, native crafting outputs, snapshots during work, long reservations
and delayed result cleanup.

Final full gate: **5 checks passed** in 103.6 seconds.
Evidence: `build/test-results/20261112-015553-6ba42b/summary.json`.

## Live verification

Run `SC-Harness-20261112-014757-37d0dbbc`: **31 checks passed, 0 failed** across
six scenarios in a cloned save:

1. Real damaged axe and repair supplies: native completion and material use.
   A failed native repair roll is a valid completed attempt.
2. Dirty bandage inside a schoolbag: native replacement in the same bag.
3. Body wash: actual actor blood and dirt removed.
4. Clothing wash: the same shirt cleaned and made wet.
5. Splint: exact inputs consumed and native output recorded.
6. Sheet rope: exact sheet consumed and native output recorded.

Every scenario released its work ownership; the worker remained alive.
Screenshots and logs are under
`build/live-sandbox-runs/SC-Harness-20261112-014757-37d0dbbc/cache`.
The original save was not changed. The municipal sink retained its displayed
water level; finite-water consumption is covered by automated stock-action
tests, not claimed as demonstrated by this live run. Legacy firearm repair,
shower outfit restoration and save/reload during each chore were not separate
live scenarios.

Development runs exposed the melee-repair recipe migration, the instance-only
surface lookup, the native handcraft constructor's surface argument, and an
overbroad save-time cancellation. These were corrected before the passing run.
The final reservation and delayed-result guards passed the full gate afterward.

Reproduce from the repository in PowerShell:

```powershell
.\scripts\Test-Project.ps1 -Serial
.\scripts\Invoke-LiveSandboxTests.ps1 -NativeCareProbe -LivingFellowsOnly -NoSteam -IsolatedSourceBridge -LowImpact -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-11-08_00-37-04' -TimeoutSeconds 330
```
