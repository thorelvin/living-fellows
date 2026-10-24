# Base Watch playtest

Base Watch keeps camp loaded through a real second local view while the player
travels. The chosen leader remains a base-duty companion; other residents keep
their usual jobs. It uses the same view slot as expeditions, so the two modes
cannot run together.

## In a cloned save

1. Stand inside the marked camp area with an indoor base-duty companion. Open
   **More > Base** and choose that companion under **Base Watch**. Start it and
   wait for the second view to appear.
2. Leave camp. Confirm the leader remains indoors in the second view and
   another resident continues a loaded camp job. A worker beyond the leader's
   loaded area may wait for the area to stream again.
3. Try a direct companion order and a camp policy edit from the remote UI;
   both should be refused. Equip powered two-way radios on the player and the
   leader, set the same channel, then request status and change defense policy.
   Turn one radio off or change its channel and confirm the policy stays put.
4. Save and reload while away. The cold loader should restore the camp view,
   then hand it to the exact saved leader. Check the leader's clothes, inventory,
   work order, and the one reused local-player save slot.
5. Return to camp near the leader. The second view should close once the
   primary player's map owns that area. Starting a later expedition should
   reuse the released slot. Walk behind the camp's south-facing wall and
   confirm it hides from the primary player's position. Nearby residents,
   including the former watched leader, should show their names when visible;
   names should remain visible while a companion speaks.
6. In a separate clone, move the watched leader outdoors for several seconds
   while another indoor resident is nearby. The indoor resident should take
   the view. If the leader dies, the next eligible resident should take it;
   with none available the mode should end after native corpse handling.

The automated `base-watch` core harness checks the asynchronous join, radio
acknowledgement, policy refusal, living/dead handoff, return release, and cold
restore. The native control test checks that a living handoff keeps one SQL
row and rejects a successor with a different saved local-player identity.

## Rendered wall recovery regression

With the game closed, run the disposable-save probe against the pinned game:

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -HiddenWindow -NoSteam -IsolatedSourceBridge `
    -LivingFellowsOnly -ViewCutawayProbe -ViewCutawayRestoreMode observe `
    -ViewCutawayCycles 3 -TimeoutSeconds 600
```

Repeat with restore mode `B` to test the deferred primary cutaway refresh. Mode
`C` also resets the native CPU view cache and is experimental; select it only
when the observed baseline and mode B establish a need. These modes require the
debug-only native selector and affect only the isolated test process.

The probe requires a south wall belonging to the native kitchen room, finds a
free standing position behind counters, and labels any window-wall fallback.
Its secondary east wall reports its actual room and may belong to the garage.
It first verifies native cutaway bits outside/inside/outside, then holds the
primary player inside the kitchen across Base Watch and expedition releases.
It samples completed render frames
1, 2, 3, 60 and 300, requires the wall to hide by frame 2, and requires retained
companions to keep completing native updates. It alternates watched leaders and
visits another loaded room, preferring an upstairs room with real solid floor
when available. It verifies actual height and health before accepting the
excursion; a fall, new wound or death invalidates the test. A scene without the
required kitchen wall and indoor residents fails fixture selection.

Each retained run contains `cache/Lua/SurvivorCompanionHarness/view-cutaway.log`
and native screenshots named `*-view-cutaway-*`. Inspect the screenshots against
the fresh baseline before accepting a fix; dirty flags and automatic PASS rows
alone do not prove the visible result. Pending screenshot review and the custom
stock-player teardown comparator are reported separately. The comparator uses
the stock join loader and an explicitly custom teardown; this game build has no
verified public API for a living local player to leave. Its tightly tracked
debug layout permits retained companions to keep updating during the comparison.
It never changes the production companion-leader ownership rules.

The first completed baseline (`SC-Harness-20261024-171250-8778f7b4`) passed 322
automatic checks with no failures. It covered two stock-player comparisons,
three Base Watch closes and three expedition closes, both wall directions and
continued companion updates through 300 completed solo frames. Reviewed native
screenshots matched the fresh wall baseline. This run used another ground-floor
room and checked the garage walls. The user then identified the kitchen as the
affected room, so this run does not establish the original cause. Wider loaded
upper-floor discovery is available for later runs, with explicit skipped
coverage when the scene has no suitable upper room.

The corrected kitchen baseline (`SC-Harness-20261024-173528-a0005f38`) passed 197
checks. Candidate B (`SC-Harness-20261024-174138-3e69a441`) then passed 345 checks
with the normal saved mod profile: three closes per companion-view mode, the
stock comparator, a valid upstairs excursion, unchanged crew health and native
updates through frame 300. Both opaque kitchen walls hid from the fixed aisle
position and restored outside it; the reviewed screenshots matched baseline.
The reported persistent opacity was not reproduced, so this proves the tested
reconciliation behavior rather than the original failure's cause.

## Normal expedition and kitchen screenshot

```powershell
.\scripts\Invoke-LiveSandboxTests.ps1 -HiddenWindow -NoSteam -IsolatedSourceBridge `
    -NormalExpeditionKitchenProbe -NormalExpeditionKitchenCrewSize 1 `
    -TimeoutSeconds 900
```

This separate probe uses saved companions, the existing parked car, a mapped
store, the normal search dispatch API, two useful items and the UI's one-hour
return limit. It does not move crew, insert supplies, override their decisions
or force a return. The primary player is placed in the kitchen once; its native
movement block holds that pose without repositioning after return, and the
previous input setting is restored after the screenshots complete. A complete
trip requires real outbound car movement and store entry; screenshots are
queued before dispatch and 300 solo frames after natural return. Review them
under the retained cache's `Screenshots` directory. Mission and crew details are
in `Lua/SurvivorCompanionHarness/normal-expedition-kitchen.log`.

The first two-person run (`SC-Harness-20261024-175059-1bb35974`) stalled before
departure: Scarlet boarded, while Tess's normal route made no progress near
the bathroom at `12029.42,6741.52,0`. The owned clone was stopped with the trace
preserved; this was not counted as a completed expedition. The one-person
option is an ordinary supported crew selection and isolates the return test
from that separate boarding problem.

The completed one-person run (`SC-Harness-20261024-181313-43e6358d`) passed all 62
automatic checks. Scarlet physically drove to the store, entered and collected
two requested items, then returned naturally in 229.7 seconds. The engine was
off and the same actor remained healthy. Both before/after images were reviewed:
the kitchen south wall remained cut away at the unchanged primary position,
including the capture after 300 completed solo frames. Primary frame, camera,
HUD and room ownership matched the human player, with restoration applied once.
The original intermittent wall failure remains unconfirmed.

The car stopped on the road at `12041.19,6766.49,0`, rather than its original bay.
The native return guard reported "parking bay requires a clear forward approach";
after its hold, production shut the engine off and brought Scarlet home on foot.
This establishes the fallback reason, not a specific physical obstruction.
