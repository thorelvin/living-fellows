<!-- SPDX-License-Identifier: MIT -->

# Companion bed exits

27 October 2026. Working continuation after `73560fe6` on
`living_fellows/0.26.71`, targeting Project Zomboid 42.21.0 single-player.
This is a Lua-only fix; the native bridge and save schemas are unchanged.

## Report and cause

The supplied report shows two upstairs companions standing idle inside beds,
repeatedly searching for routes to camp storage. A restart may explain why
their temporary bed-action records were absent; the report does not establish
whether a restart occurred.

`SCNativeActions.leaveSeating` cleared `onBed` and the furniture reference
immediately. The stock `PlayerGetUpState.exit` needs that reference to eject
the actor from solid furniture. Clearing it early bypassed native get-up and
its ejection, leaving the body inside the mattress. Non-local companions also
need collision restored after their native bed pose finishes.

The revised exit retains the native bed reference throughout get-up and gates
ordinary movement until it finishes. A bounded watchdog handles stalled clips.
Collision and movement flags are restored afterward. Ground rest and furniture
seating retain their existing paths.

An actor already standing inside a confirmed solid bed can recover to one
clear cardinal neighbour. The check uses the actor's physical coordinates,
not a potentially stale current-square pointer. It considers at most 16
objects on that square, caches probes for one second, and retries blocked
exits no more than once per second. Recovery requires the same floor and
room, a clear collision edge and a clear, unoccupied destination. It uses the
existing recovery path on the same actor; inventory items are not recreated.
Native grapple, traversal, attack, corpse-drag and unrelated reaction owners
prevent recovery. Removed actors release the temporary bookkeeping.

## Automated verification

- All 228 payload Lua files compile in normal and debug modes, including the
  debug-limit fixture.
- All 84 core harnesses pass. Bed regressions cover retained native references,
  movement gating, saved standing positions, blocked and occupied exits,
  walls, room boundaries, stale square pointers, native ownership and removal
  of the bed. Existing actor and inventory ownership checks remain active.
- Gameplay regressions pass.
- The complete project gate passes all 29 stages in 144 seconds, including
  native contracts, navigation, gameplay, UI, compatibility and packaging.

Detailed gate logs are under `build/larchos-validation/bed-exit-*.log`.

## Cloned-world native acceptance

The disposable Rising-world clone uses a real recruited companion and stock
two-tile bed objects in all four orientations. The fixture temporarily takes
that actor off duty and drives its bed requests directly; native physics,
animations, the supervisor and other actors continue running. Temporary beds
are placed on verified clear loaded floor, including outdoor floor when the
house is too cramped. This is not the upstairs room from the supplied report.

North, south and west beds have native seating entries in the inspected stock
catalog. Each completes actual bed entry and get-up, retains its bed reference
during get-up, restores collision and finishes outside the mattress. The south
case also cancels a sleeping companion through `SCDowntime` after a new order.
The selected east-facing stock bed has no native seating entry data; full
entry/get-up is not claimed for that orientation.

All four orientations additionally exercise the reported saved-position
signature: the same standing actor is placed physically inside a real bed
with no remembered bed action or posture flags. Recovery must leave it on the
same floor and in the same room, outside the mattress and collidable. Exact
inventory item identities and the registered native actor identity are checked
after every case. This emulates the post-load signature; an actual save/reload
cycle and autonomous overnight scheduling are not part of this acceptance.

Native assertion evidence is recorded in
`artifacts/bed-exit/native-acceptance/bed-exit-evidence.log`; the repeatable
test-only probe and launcher are in its parent folder. The main camera does
not follow the fixture actor, so this is instrumented native acceptance,
not a visual inspection of every bed orientation.
The source save, installed mod and installed game files are untouched.
