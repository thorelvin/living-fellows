<!-- SPDX-License-Identifier: MIT -->

# 0.26.85 bed-exit and Follow validation

Based on `c8601157` (the current `living_fellows/0.26.84` tip), released on
`living_fellows/0.26.85` for Project Zomboid 42.21.0 single-player.
The implementation and live runs below were completed before the release-label
bump. Release verification and the versioned bridge hash are recorded separately
at the end; save schema `SC_WorldV1`/3 remains unchanged.

## Bed-exit follow-up

Julie's report showed `standing_from_bed_exit_blocked` after getting up in the
Rosewood firestation. The local user console predates that report and contains
no Julie entry, so it was not treated as evidence of her exact episode.

The native get-up can leave a companion only 0.05 tiles beyond solid furniture.
Recovery now checks its collision body against every segment of the same placed
bed and selects supported, clear floor in the same room and on the same level.
It can cross the verified mattress seam, or take one checked cardinal step away
from a crowded aisle tile. Native wall, door, window and fence edges, stairs,
unloaded floor, unrelated furniture, vehicles and other destination occupants
remain excluded. The native spawn test's eight-connected-tiles requirement is
not applied when recentering an existing companion on its own physical tile.
Moves onto another square retain the original native spawn-safety checks.

The entered bed retains ownership throughout get-up instead of being replaced
by another object underfoot. A bedding texture prefix alone cannot classify a
bedside table as a bed. Collision checks use fresh actor coordinates rather
than a decision batch's cached position. A failed recovery stays gated and
retries at one-second intervals; there is no new world survey or idle service.
Recovery retains the same actor and inventory and yields to native attack,
grapple, traversal and corpse-drag ownership.

The focused Kahlua bed-exit harness passes **61 checks**, including the solid
seam, cramped aisle, crowded shared tile, stale position, original-bed identity,
bedside-table avoidance, false bedding graphics, missing coordinates, blocked
floor, native ownership, automatic retry and a provider returning success
without moving the actor. A narrow other-tile target rejected by the bridge
cannot hide a usable exit later in the candidate list; only recentering the
actor's own tile bypasses the spawning-neighbourhood rule.

Native evidence uses disposable copies of the Skills5 save, LF alone,
`-NoSteam`, the real sound/ambient engine and isolated source bridges.
The first diagnostic runs used protocol 25; the native fix uses protocol 26.
Sleep fatigue is seeded to enter the bed reliably; wake-up is requested
through ordinary downtime cancellation. These are controlled sleep/get-up
scenarios, not an unattended natural sleep-cycle observation.

| Run | Result | Finding |
| --- | --- | --- |
| `SC-Harness-20261031-150121-a7c10494` | 43 pass, 1 fail | The smaller three-bed room reproduced a blocked wake-up. |
| `SC-Harness-20261031-150841-6cbe588a` | 26 pass, 1 fail | Two sleepers ended on the same aisle tile; one still touched its bed edge while the other blocked recentering. |
| `SC-Harness-20261031-151331-a68b1a50` | 82 pass, 0 fail | The aisle fix cleared both three-person groups; bag, bunk and couch trials also walked away after getting up. |
| `SC-Harness-20261031-151932-2eed71a3` | 20 pass, 1 fail | An individual hospital-bed exit had a valid original-bed target while cleanup was gated against the object underfoot. |
| `SC-Harness-20261031-152626-eec6262e` | 72 pass, 0 fail | Retaining bed identity passed both individual hospital beds and bag/bunk/couch walk-outs, with real movement to a separate floor tile. |
| `SC-Harness-20261031-153233-228e2c40` | 26 pass, 1 fail | A repeat found clear carpet but native recovery rejected recentering because its spawning check counted the actor itself and required eight connected tiles. This prompted the native fix below. |
| `SC-Harness-20261031-155841-4aeaec36` | 82 pass, 0 fail | Protocol 26 cleared both three-sleeper hospital rooms, with original bedside tables in place. Sleeping bag, couch and bunk trials also got up and resumed normal walking. |
| `SC-Harness-20261031-160402-43776f22` | 72 pass, 0 fail | Protocol 26 passed both individual hospital-bed exits and all three backup surfaces, including normal walking to a separate floor tile. Engine screenshots show the actor clear of the mattress and bedside tables. |
| `SC-Harness-20261031-160852-cca52a6e` | 65 pass, 0 fail | Final Lua candidate filtering repeated the cramped room with three sleepers and then bag/couch/bunk sleep, full-body exits and normal walk-outs. All cleared. |

Bridge protocol **26** adds a narrow exception for an owned, living companion
already present in the world, idle and off its bed: it can recenter its own
physical floor tile. Loaded support, static clearance, absence of furniture,
vehicles, stairs, fire and other moving bodies are checked again natively.
No actor is spawned, and the existing recovery transaction preserves player
slots and actor identity. Other-tile and distant recovery keep their original
spawn checks. The real-JAR cleanup regression covers the positive narrow-floor
case and rejects bed ownership, unsupported/unloaded floor, another body,
a different physical tile or level, and missing world membership. Existing
recovery rollback checks also pass.

The protocol-26 bridge used for these pre-release live runs has SHA-256
`2be7761f460433937c43e463f5bfb84deb362e45d082235625077e35639704b3`.

The final project gate passes **29 of 29 stages** (176 seconds overall,
172.8 seconds in stages, eight workers), including the 61-check bed-exit
regression, real-JAR recovery/rollback, view ownership, existing sleep and
navigation checks, packaging and installer transactions. Release/protocol
synchronization and `git diff --check` pass. The built and shipped bridge
payloads have identical hashes.

The attempted external desktop-control run
`SC-Harness-20261031-145618-02c57b26` was stopped at the loading gate after its
desktop capture stayed blank. It is not an acceptance result; subsequent runs
used the existing test-only loading-gate agent and engine screenshots.

## Follow spacing, obstacles and vehicle exits

The report of followers hanging behind cars/walls and pausing after getting
out was checked against the current Lua and native bridge, preserving the
bed-exit changes above. The user's local console predates this report, so
controlled cloned-save runs supplied the live evidence.

Four code paths contributed:

- A formation hold used distance alone. It could cancel a valid detour while
  a wall or parked car still separated the actor from its nearby slot. A hold
  on another tile now requires a bounded, clear two-step route proof.
- Moving trail followers could keep holding until the leader was seven tiles
  away. They now release the hold beyond the selected Follow distance plus
  half a tile; saved spacing choices are retained.
- A failed Follow delegate could fall back to a new scavenging search while
  the leader was moving. New opportunistic searches now require a nearby,
  settled leader on the same floor. Existing commit/rollback ownership remains
  authoritative, and looting beside a settled leader is still tested.
- Native exits retained old formation state, and a tile search beside the car
  could consume the five-second Follow planning allowance. Verified exits now
  release old holds and expose their exact stopped car for at most eight
  seconds while the actor remains within six tiles. Outdoor Follow can use the
  existing native polygon pathfinder immediately when the open route fails.
  Indoor, cross-floor, stealth, restricted work and required verified routes
  keep their normal path policy. There is no background service or new save
  data, and reboarding, departure, expiry, death or a moving car clear the hint.

The new wall-hold assertion failed on the previous implementation before the
fix. Gameplay integration now passes, including wall/car hold rejection,
release of an existing hold, earlier trail movement, verified-exit cleanup,
hint expiry and the native-routing policy guards. The separate arbitration
harness passes **121 checks**. Existing medical, transfer, sleep and navigation
checks remain part of the full gate.

| Run | Result | Evidence |
| --- | --- | --- |
| `SC-Harness-20261031-175048-7e3f8091` | Road baseline | A 50-tile player jog took 22.97 seconds. Tess reached an 11.87-tile gap and a 2.6-second pause; the trace showed false holds, crowd waits and scavenging after blocked Follow. |
| `SC-Harness-20261031-180307-5b3ce36a` | Intermediate: 26 pass, 2 fail | Three real passengers boarded and exited. Two needed 4,659 and 5,569 ms to translate 0.35 tiles after exit; traces showed `path_searching`. This geometry run overlapped the project gate, so it is not an uncontended timing comparison. |
| `SC-Harness-20261031-181157-23c929ee` | 28 pass, 0 fail | Final code, no concurrent gate. Player jog: 22.98 seconds; maximum observed follower gap 8.05 tiles. Three distinct native passengers exited in 24–83 ms, then translated 0.35 tiles in 645, 678 and 1,916 ms. The stock player exit action and normal player/follower paths were used. |

These are controlled LF-only outdoor scenarios in copies of the Skills5 save,
with medical distractions isolated. They do not establish a population-wide
performance average or cover an indoor garage exit; indoor routes deliberately
retain their existing verification policy. No user save was modified.

The final combined gate passes **29 of 29 stages** in 168 seconds overall
(165.6 seconds in stages, eight workers), including the bed-exit changes,
gameplay and ownership regressions, native runtime checks, packaging and
installer transactions. Release synchronization and whitespace checks pass.
These Follow changes are Lua-only; the pre-release protocol-26 bridge hash stays
as recorded in the bed-exit section.

## 0.26.85 release verification

All release labels and packaged metadata now identify **0.26.85**, including
the bridge's implementation version. Its non-manifest JAR entries are byte for
byte identical to the bridge used by the final live scenarios above.
The versioned bridge has SHA-256
`3890f8df4f6f48cd2c517b1a0ec1cb13164f978fa5e304b27213ff0eb023e729`.

The full gate passes **29 of 29 stages** in **167 seconds** overall
(164.8 seconds in stages, eight workers). Workshop and standalone packaging,
native runtime/ownership, the 61 bed-exit checks, 121 arbitration checks,
existing gameplay regressions and installer transactions all pass.
Evidence: `build/release-0.26.85/project-gate.txt`. Release synchronization and
`git diff --check` also pass. This records Git release preparation; no Workshop
upload or local game installation is part of this release step.
