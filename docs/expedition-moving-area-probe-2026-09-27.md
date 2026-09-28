# Moving remote area and native danger probe

Private test build on a disposable clone of the Riverside gas-station save.
The actual mission leader occupies local slot 1, with two original companions
following and the original player at Riverside. A test-only standing waypoint
is passed through `SCDecision` and the existing `SCNavigation` owner; ordinary
remote Orders commands remain blocked. The only long-distance transfer is the
initial test setup to the remote site, 512 tiles away. No later movement in
this probe uses teleportation.

## Findings

- Immediately after the leader's first remote square appeared, targets 12–30
  tiles away returned no ordinary grid square. The slot-1 chunk map reported
  bounds around `6520..6672,5232..5384`, but the target squares had not yet
  integrated. A ten-second wait allowed a 30-node native route to be found.
- Run `SC-Harness-20260927-014905-0b5759c4` staged a 16-tile standing
  waypoint. The leader entered a second native chunk and moved from about
  `6598.8,5310.4` to `6607.5,5317.9` while both followers stayed within 15
  tiles. Its health fell naturally from 40% to 37.6%. Combat diverted the
  leader; the waypoint was **not completed**.
- Run `SC-Harness-20260927-014557-799e0e9c` saw fourteen natural zombies at
  peak and fifteen tracked native zombies move. The leader entered a second
  chunk and died with health falling from 40% to 0 before the harness applied
  any injury. The next original companion took slot 1 and kept native AI.
  The waypoint was **not completed** in that run either.
- A nearer, reachable cross-chunk waypoint in
  `SC-Harness-20260927-015124-0f486fb2` also lost priority to normal survival
  behavior. This is a real interaction with native danger, not route proof.

W03 remains partial. These runs demonstrate area integration timing, real
actor movement into another chunk, natural threat and genuine casualty.
They do not prove continuous travel across several boundaries, safe retention
of stragglers and pursuers, building entry, or an eventual return route. The
test-only waypoint mechanism remains isolated from player-facing commands.

## Local trip without setup teleport

`SC-Harness-20260927-045924-88439481` started at the Riverside gas station
with the original player and three original companions. The leader occupied
slot 1 while the player stayed in slot 0. The test chose a loaded,
pathfinder-verified 11-node waypoint at `6095,5308` from the leader's
`6085.5,5308.5` start. The original leader walked there across a chunk edge;
both followers stayed within 15 tiles. The largest observed update step was
`0.0621` tiles. Another 11-node path brought the leader back within 2.46
tiles of the stationary player, and the joined-team release closed slot 1.
No actor was teleported in this local-trip probe. It verifies actual short
outbound/return movement through the existing navigation owner. It does not
prove a route beyond the already loaded local map or movement of the slot-1
footprint across successive streaming boundaries.

The local trip passed again using all mod entries from the original save in
`SC-Harness-20260927-050219-60befb22`. The original team reached the same
cross-chunk destination and returned, with the view released beside the
stationary Riverside player. The original save was not modified.

## Longer route attempts

The next private probe chained pathfinder-admitted waypoints and measured the
actual companion's position on each update. It did not teleport between legs.
The Riverside attempt `SC-Harness-20260927-050751-dffd52ed` walked about 42
tiles east in three legs and moved slot 1's loaded map minimum from 6008 to
6048. Combat then took priority over the fourth waypoint. The follow-up
`SC-Harness-20260927-051201-0f6e685e` reached about the same point and
again lost the route to combat.

The remote runs used one test-only transfer of the original leader and two
followers before walking. `SC-Harness-20260927-053231-d1daed38` began 1024
tiles south of Riverside with a healthy, lightly loaded leader and one
natural zombie in a 25-tile survey. Six admitted legs carried the team from
about x6084 to x6159. Slot 1's loaded map minimum moved from 6008 to 6080
while the followers stayed nearby. The leader died naturally during leg 7.

`SC-Harness-20260927-054340-665de78a` began at the same southern site with
zero natural zombies in the initial survey. Four full legs took the leader
from x6084 to x6133; the loaded map minimum shifted from 6008 to 6056 while
its width stayed 152 tiles. Native tactical movement carried the leader past
leg 5's target, so the harness explicitly abandoned that waypoint and staged
a new path from the real position. During leg 6 the leader reached x6178,
more than 90 tiles east of the original remote square, then died in combat.
The harness recorded failure because the target was not reached alive. It
did not run the final direct check that the original remote square had
unloaded. These attempts demonstrate successive moving slot-1 map bounds and
real walking with followers; W03 still lacks a complete long route and a
verified old-square unload/return cycle under native danger.

## Live old-square unload observation

The harness now checks the old square **during** each walking leg, before a
later tactical diversion or death can prevent a final arrival assertion.
`SC-Harness-20260927-055757-9ba26f67` retained the same original leader and
two followers. Native navigation carried the living leader 85.04 tiles east
from the test-only remote start. Slot 1's map minimum moved from 6008 to 6096
while its width stayed 152 tiles; neither local map covered the starting
square. Ordinary `getGridSquare` returned `nil` for that square while the
leader's current square remained loaded. Both followers were within 10.58
tiles and the largest measured update step was 0.152 tiles. This is direct
evidence that the old remote square unloaded as the second view moved.

The run still failed its complete-route assertion: combat carried the leader
past leg 6's waypoint, and the original leader died before another waypoint
could be admitted. No long return or building-entry leg was completed.

## Completed quiet-area long walk

`SC-Harness-20260927-105722-1f49c5cd` repeated the remote route after adding
the prototype cohesion guard. In a quiet area 512 tiles west of Riverside, the
original leader completed six loaded, pathfinder-admitted legs and walked
100.12 tiles east with two original followers. Slot 1's map minimum moved from
5496 to 5600 while its width stayed 152 tiles. At 85.03 tiles of progress,
ordinary lookup no longer returned the starting square and the current leader
square remained loaded. Both followers were within 11.04 tiles at completed
legs, with a maximum observed leader update step of 0.102 tiles. A final check
five seconds after arrival again found the source unloaded and the current
square loaded. The test-only setup transfer was the only teleport.

This closes the narrow one-way movement and old-square unload probe. W03 still
needs real destination/building entry and a long route home with the whole
team under normal danger.

## Completed remote-site round trip

`SC-Harness-20260927-111423-69eb1385` used the same quiet westward site and
kept the original leader and two followers in slot 1's world. The leader
completed five outbound legs after the first cross-chunk step, walking 99.32
tiles east. The starting remote square was absent from ordinary lookup while
the far leader square remained loaded. After a five-second verification, the
harness admitted five westbound waypoints using the existing pathfinder and
normal navigation owner. The leader returned to x5573.72, 97.60 tiles from
the far endpoint and within two tiles of the original remote x coordinate.
The first remote square at x5572,5307 was loaded again; the far endpoint at
x5671,5312 was no longer loaded. Slot 1's map minimum moved from 5496 to 5592
outbound and back to 5496, retaining its 152-tile width. Both original
followers remained active on loaded squares and were within 11.58 tiles at
completed legs; the largest observed leader update step was 0.097 tiles.
No travel teleport followed the initial test-only transfer from Riverside.

This proves bidirectional native streaming on a remote-site round trip. It is
still a test route rather than a player-facing expedition: the team did not
depart from and return to the Riverside player across 512 tiles, enter a new
building, search a task site, or face natural danger on this quiet route.

## Building entry under investigation

The first four isolated building-entry runs (`112149`, `112353`, `112749`,
`113530`) did not show the leader entering a room. The fourth run selected
a loaded room square at `6617,5298` and a pathfinder-admitted exterior square
at `6618,5298`, both outside the player's chunk map. The actual leader walked
from `6596,5307` to `6613.51,5302.50`, then remained roughly six tiles from
that exterior approach until the 80-second probe limit; navigation still
reported `moving`. This is a route or obstacle failure, not evidence of
successful entry. The next isolated run, `SC-Harness-20260927-113941-dfcc0ac2`,
selected a different room and verified the actual leader walking from outside
`6574.87,5306.50` into that room at `6574.00,5305.50`. The leader's largest
sampled update step was 0.095 tiles, the room remained outside slot 0's map,
and the saved leader stayed in slot 1. The run failed its exit check: the
probe asked for the distant original start square and timed out while the
leader was still indoors. A revised probe targets the adjacent exterior
square to isolate that crossing. The fixture removes nearby zombies, so these
runs provide no natural-danger evidence.

`SC-Harness-20260927-114707-489cd3f1` passed the short-crossing revision.
After two exterior routes stalled and were abandoned, the original saved
leader reached `6569.95,5306.50` outside a third room, walked into its native
room at `6569.53,5305.94`, then walked back outside to
`6569.50,5306.44`. The exit route was two loaded path nodes. The leader's
largest sampled update step was 0.077 tiles, both followers remained loaded,
and their largest exit gap was 7.79 tiles. Slot 0 never covered the selected
room. This proves actual interior entry and exit at the remote site through
the normal navigation owner, including a bounded alternate-route retry. It
does not prove that every doorway is usable, that a window was smashed, that
a locked door was bashed, or that the team performed a task inside.

The owner specified that a team may break a window, and may bash down a door
as a last resort. The existing traversal owner already supports opening or
smashing a window, clearing glass, and climbing through it. An ordinary
locked door can now open without a key from its interior side; locked outside
entry still needs a key or another route. Entry selection should prefer a
normal entrance, retry another path when blocked, then use a breakable
window; door bashing requires a native action with noise, durability, injury,
and threat consequences before it can be considered working. The forced door
entry sequence remains an open test.

## Verified locked-window entry

`SC-Harness-20260927-121038-3fd02f49` first found 28 intact windows but
could not route directly through any of them. Inspection of the installed
Build 42 `IsoWindow.canClimbThrough()` bytecode showed why: it returns false
while an intact window is closed, before a character has an opportunity to
open or smash it. The path classifier had treated that current-state answer
as a permanent obstacle. It now admits concrete, intact, breakable
`IsoWindow` edges for native preparation, while keeping unsupported window
objects and frames rejected. The gameplay suite passed after that change.

`SC-Harness-20260927-121604-13b0d917` then passed in a disposable clone.
The harness locked an intact native window at the remote site. The original
saved companion leader walked to its exterior square at `6577.52,5297.88`,
then entered the room at `6576.83,5297.50`. The **same native window object**
was smashed and its glass removed. The leader exited through the two-node
window route to `6577.19,5297.50`; both followers remained loaded within
5.98 tiles and the leader's largest sampled update step was 0.099 tiles.
The original player did not cover this room. This proves a locked-window
fallback in the isolated test build. It does not prove the window choice in
a full task itinerary or the danger/noise consequences under live zombies.
After the production path-classification change, the core suite passed
46/46 and the installer transaction suite passed 35/35.

## Native axe door bash prototype

The installed Build 42 `IsoDoor.WeaponHit(IsoGameCharacter, HandWeapon)` method
uses native door damage, hit sounds, and `WorldSoundManager` noise; it delegates
to a barricade's native hit handler when one blocks the door. The current LF
planner excludes a locked outside entry without a key, and native traversal
returns `locked_door` there. The private `bash_door` action now uses the stock
`ISChopTreeAction` animation and its repeated `ChopTree` event against a native
`IsoDoor`. The action requires an intact, locked, unbarricaded door that the
companion cannot open normally, plus an unbroken axe. It uses the existing
tracked-work queue and restores prior hand equipment on completion.

`SC-Harness-20260927-131454-4ab9e45d` passed with the original saved leader
in local slot 1. The fixture placed the leader beside a native exterior door
in a disposable clone, locked the door, and supplied a test axe. The guarded
`bash_door` action entered the native timed-action queue. Door health fell from
500 to 430 on the first observed hit and to -60 before the door's native world
index became -1. The action finished in about 6.1 seconds, restored the
leader's prior hand equipment, and reduced native endurance from 1.0 to 0.931.
The axe condition stayed at 13 in this run, so a condition-loss event was not
observed. The runner restored the installed launcher and the source save was
untouched. The later cloned run `SC-Harness-20260927-132429-191bfaed` repeated
the native action with two original followers placed nearby, then found a
direct two-node route through the destroyed door and a three-node route to a
free square deeper in the same room. The leader walked to that interior square
through normal navigation, while the original player remained in slot 0 and
the leader in slot 1. This proves the native axe door-damage action and route
retry through the breach. Automatic last-resort door choice, threat
interruption, sound radius, and a full expedition remain unproved. The initial
placement beside the door and follower placements were test-only transfers.

## Locked door opened from inside

Build 42's `IsoDoor.ToggleDoorActual` clears an ordinary lock when an
`IsoPlayer` opens the door from an interior room on either side, unless the
door is `forceLocked`. The companion leader is an `IsoPlayer` subclass. The
path classifier, native lookahead, explicit interaction, and traversal guard
now accept this inside exit without a key. They still reject a locked outside
entry without a key. Permanent, code, custom, force-locked, and
`IsoThumpable` doors are excluded from this exception.

The focused cloned-save run `SC-Harness-20260927-125212-3144f048` took the
original saved leader and two followers into a remote native room. The harness
closed and locked its actual `IsoDoor` behind the leader. With the leader's
actor supplied to the route query, the exit was a direct two-node path. The
leader walked back outside; the same door object changed from locked/closed
to unlocked/open. Both followers remained loaded within 8.60 tiles. The
player in slot 0 never covered that room, and the largest sampled leader step
was 0.116 tiles. This proves the ordinary inside-unlock route and native
interaction in the isolated test build. It does not cover all door sprites,
special locks, danger during exit, or a complete expedition journey. The
gameplay, core 46/46, and installer 35/35 suites passed for this change.

The current test build was rechecked in cloned-save run
`SC-Harness-20260927-134205-5553f7b1`. The saved leader entered a room,
the harness closed and locked its ordinary `IsoDoor`, and the companion
planned a direct two-node exit. Native traversal left that same door open
and unlocked. Both followers remained loaded within 5.42 tiles; the
gameplay suite also passed with the inside-door regression checks.

## Automatic locked-door last resort

The earlier direct axe test proved the native action but did not prove route
selection. The first automatic attempts found ordinary window detours. A later
fixture could barricade those exits, but the normal A-star search repeatedly
reached its node or time budget while exploring the large loaded outdoor area.
The companion then remained in planning. A direct bash-capable query needed
1,122 node expansions for a four-node path because the destructive edge had a
high route cost.

The planner now first inspects the nearby target room's loaded boundary when
an expedition test waypoint permits last-resort bashing. It rejects this
shortcut if any ordinary entry, stair, unloaded boundary, or room larger than
its bounded scan remains. With a sealed room and a usable axe, it admits only
locked doors entering that target room and uses a local planning cost so the
short route finishes within the decision budget. The native axe action still
does the actual damage; traversal rechecks the door and tool. Ordinary route
search keeps its separate fallback for a fully exhausted, unreachable graph.

Cloned-save run `SC-Harness-20260927-141738-8c46a8f0` passed the full
sequence. The harness made a disposable quiet fixture with native metal
barricades on alternate room exits and transferred the original saved leader
and two followers beside one exterior locked door. The bash-enabled route had
three nodes. Without a command from the player, the leader selected
`bash_door`, reduced that door's health from 500 to 220, destroyed it
(object index `-1`), and walked into the target room. The player remained in
slot 0 at Riverside and the original leader remained in slot 1. This is a
native action and automatic local route choice, not a complete expedition
journey or proof of natural population at the destination.

A current-build preference run, `SC-Harness-20260927-142129-082d3a12`,
reached a different room through a locked native window, smashed it, cleared
the glass, and returned outside. Gameplay regression checks cover ordinary
unlocked-door priority, a longer breakable-window detour before any bash
search, target-room-only bash admission, and a remembered locked edge that
blocks ordinary travel while allowing the certified bash search. Gameplay,
core 46/46, and installer 35/35 checks passed after this change.

## Joined Riverside travel, loot, and return

Run `SC-Harness-20260927-145358-d8448d70` started beside the saved Riverside
player. The original leader occupied slot 1 and walked a 28-node, cross-chunk
route with two original followers to a stocked native cupboard at `6077,5302`.
The harness used a quiet fixture that removed three nearby native zombies; no
actor or item was transferred to the site. The existing Encounter owner opened
the surveyed cupboard, selected `Base.FiberglassTape` (native ID `1367551867`),
performed its native loot action, and verified the source count changed from
14 to 13 while the same item entered the leader's inventory.

The leader then walked an admitted 11-node return route. `finishAtPlayer`
released slot 1 at a 1.94-tile player gap, and the same native item ID remained
in the leader's inventory with no copy in the source. The largest sampled
leader step on the outbound leg was 0.102 tiles. Two earlier joined attempts
established the outbound and loot legs but stopped at a 60-second return watch;
the passing run allowed 120 seconds for the route around the gas station.
The test uses a transient, exact container target to keep this fixture
deterministic; item choice, movement, action, transfer, and verification remain
owned by the normal Encounter code. A long remote journey, natural danger,
and a previously unvisited destination remain open.

## No-transfer Riverside long route and joined release

The later long-route probe starts from the original gas-station save without
any setup transfer. Slot 0 stays with the player; the saved, clothed leader
occupies slot 1 and two original companions follow. The first attempts found
three distinct route problems. Mission departure could leave an owned chair
action running, so staging now cancels that downtime action and suppresses
idle work during the waypoint. A follower who discovered a locked door could
retain an old leader-trail route through it; the native door check now clears
that route, and mission members may try a bounded alternate-entrance search.
Finally, the long-distance test itinerary preferred a short line through a
building, leaving outdoor followers at an entrance locked from their side.
It now chooses exterior squares along a path that stays outdoors after exit.
This route choice is still test-only; it is not a player-facing expedition
planner.

`SC-Harness-20260927-160700-4fcdfca9` passed the full no-transfer outbound
and return footprint probe with a quiet fixture removing nearby zombies. The
team walked about 87 tiles east through five admitted legs. Slot 1's map
minimum moved from 6008 to 6096 while the player-owned starting square
remained loaded in slot 0 and left slot 1. Six westbound legs brought slot 1
back to map minimum 6008; the far square unloaded, both followers remained
loaded and near the leader, and the largest sampled leader step was 0.108
tiles. The test stopped at the starting footprint, about ten tiles from the
player, so it did not prove joined release.

`SC-Harness-20260927-161216-c4b6e22c` repeated the quiet no-transfer route
and added the final player approach. The leader walked about 87 tiles east,
slot 1 left the player-owned start, then returned through westbound map shifts
with both followers. A final 13-node route ended 2.35 tiles from the player;
`finishAtPlayer` returned `returned`, released slot 1, and preserved slot 0.
The largest sampled leader step was 0.114 tiles. Gameplay, core 46/46, and
installer 35/35 checks passed after these changes. The source save and
installed launcher retained their original hashes.

Unquiet reruns remain important. One exterior-route attempt
(`SC-Harness-20260927-160303-32ca700c`) diverted into natural combat on leg
3 and failed arrival. Earlier inside-building runs could complete the outward
footprint but trapped followers or the returning leader at a locked entrance.
The quiet run proves navigation and streaming with the actual team; it does
not prove this long journey under sustained natural danger, a mission task or
loot at the far site, or a production itinerary over roads.

## Autonomous scout itinerary

The prototype now accepts a bounded `scout` plan with a destination 20 to 120
tiles from the saved leader. It records the player's departure rally, promotes
the actual companion leader, and chooses short loaded outdoor path segments
itself. The follower cohesion hold still governs movement. At the site it
observes briefly, then retraces its saved outbound checkpoints in reverse and
releases slot 1 only when the team reunites with the original player. An
active descriptor saves the destination, rally, phase, and reverse checkpoints;
the focused core harness restores it both before arrival and during return.

The first live scout attempts exposed a follower hold near a building, a
waypoint that made little progress, and a return path that cut across a
different corridor. The planner now uses nearby nodes of a verified outdoor
path, abandons a stalled waypoint with a bounded retry, and retraces its own
checkpoints on return. These were actual failed cloned-save runs; they are not
counted as completed trips.

`SC-Harness-20260927-171240-da19bc86` passed the autonomous, no-transfer
scout with a quiet fixture. The original leader and two followers departed
from the Riverside player without a radio, reached about 84.5 tiles east,
observed the site, and returned to within 12 tiles of the player. Two
bounded waypoint retries occurred during tactical decisions. The largest
sampled leader step was 0.144 tiles and the largest follower gap was 12.07
tiles. The mission reported `returned`, released slot 1, and preserved slot
0. Core 46/46 and installer 35/35 passed, including outbound and inbound
itinerary reload checks. The source save `players.db` and installed launcher
hashes matched their pre-run values.

This scout has no player-facing assignment UI or far-site search/loot action.
The quiet fixture removes nearby zombies, so natural danger, interrupted
combat, exact cargo conservation on this route, and production road planning
remain open. Its 120-tile admission limit is a test-build bound, not a county
distance expedition.

## Verified site observation

The first scout observation implementation incorrectly read the fallback
actor-state cache and therefore found no perception snapshot in the live
mission. The decision owner receives the saved registry record's runtime; the
scout now reads that same runtime. Build 42's native candidate scan may report
zero grid squares even when it completes, so a separate nine-point sample
uses loaded squares and the companion's actual line of sight. The durable
record identifies its tile and world hour, the completed or partial native
perception status, the count of sampled squares actually visible, and the
number of visible threats. It makes no claim about rooms or squares not seen.

`SC-Harness-20260927-173950-f10df1fb` passed the full no-transfer quiet scout
with that gate. The saved leader reached about 82.75 tiles east, completed its
native perception scan, saw all nine sampled squares at the exterior site,
and returned with two original followers. The finished debrief retained that
bounded observation, slot 1 was released, and slot 0 remained the Riverside
player. The largest sampled leader step was 0.207 tiles and the largest
follower gap was 13.21 tiles. A scout-specific eleven-tile cohesion release
margin kept the returning party moving through a corner while the ordinary
twelve-tile hold trigger remained active. Earlier live runs with the stricter
release margin could remain held near the site; those failures are retained.

The observation is internal mission/debrief data. It is not yet a received
radio report or a player-facing expedition panel. This test is quiet and at
an exterior route target; it does not prove a room sweep, a supply search,
natural danger at the site, or a radio-delivered report.

## Requested-category native loot

The existing scavenging owner can now take an explicit supply category during
the private expedition search probe. It ranks unopened containers from their
location without reading hidden contents, then accepts only the requested
category after opening one. A request may exceed the leader's personal stock
target, but it still obeys native carrying capacity and the existing source
permission check at selection and transfer. A changed request cancels an
in-flight selection. A verified requested transfer records the item's existing
stable identity and the source object's tile/index for later mission receipts.

`SC-Harness-20260927-175330-349f6ee5` passed a cloned Riverside trip with
the original leader and two followers. The harness selected a loaded cupboard
as the destination and staged a `construction` request. The leader walked
across a chunk boundary, opened that cupboard, and transferred the exact
`Base.FiberglassTape` item (native ID `1367551867`). Its native source count
fell from 14 to 13; the returned companion still carried the same item and
slot 1 was released beside the player. The new receipt check confirmed that
the item held the stable identity reported by Encounter. The source save
`players.db` retained SHA-256
`4A40E904F5262EE9FDB427EC2C13C1397D564E4D30F11ABB69AB5D35C293F3DE`.
The gameplay, core 46/46, and installer 35/35 suites passed.

This is a targeted native-loot probe. An autonomous Search mission still needs
a requested quantity, destination sweep, bounded exhaustion/return decision,
persisted progress, and reconciliation of items used or lost before debrief.

## Autonomous local supply search

The private mission now accepts `kind="search"` with one requested category
and quantity (one to eight) at a destination 8 to 120 tiles away. It reuses
the actual leader's loaded local itinerary. A pathfinder-admitted final leg
may enter the destination building; ordinary scouting still uses outdoor
legs. At the site, Encounter searches native containers within the plan's
bounded two-to-eight-tile radius around its fixed destination, without
receiving a container identity or hidden item
list from the mission. Existing permissions, capacity, timed action, and
verified transfer rules continue to own each pickup. The mission records
only verified requested-item receipts. Quantity met, carrying capacity, or
an absolute in-world search deadline starts the reverse route. On return,
the debrief checks which acquired stable item identities are still in the
living team's real inventories. A bounded inventory scan reports whether that
check was complete.

The first cloned run (`181004`) exposed two defects: outdoor-only short legs
could circle an indoor destination, and a 26-point trail exceeded the
expedition save copy's 128-value allowance. The final loaded approach now
admits an interior path, and the expedition copy budget is 8 levels/1,024
values. The next runs (`181715`, `182224`) reached the site and returned with
an honest zero-item `search_deadline` result, but spent the search window on
unhelpful cupboards outside the intended small site. Those failed runs remain
in the audit record; they are not counted as successful loot trips.

`SC-Harness-20260927-182810-7cd85eab` passed the corrected no-transfer
trip. The original saved leader started beside the Riverside player with two
followers, walked to `(6077,5303)`, and searched the two-tile site without a
test-staged waypoint or target container. The harness independently verified
that the native cupboard at `(6077,5302)` was loaded, stocked, permitted, and
not behind a remembered locked door. Encounter chose it and transferred the
exact `Base.FiberglassTape` item (native ID `1367551867`); source count fell
from 14 to 13. The requested construction receipt carried the same stable
identity as the native item. The mission returned `quantity_met` with one
acquisition and one exact item still carried, released slot 1, and kept the
player in slot 0. The leader crossed four chunks with a largest sampled step
of 0.085 tiles. The quiet fixture removed three native zombies near departure.

After the site radius became a saved plan field and scan invalidation was
scoped to that field, `SC-Harness-20260927-183706-1dfb20f6` repeated the
same exact-item trip on the current build. It again selected the native
cupboard, debited 14 to 13, returned the single requested item, and released
slot 1. The largest sampled leader step was 0.087 tiles. This run used a
two-tile radius; the wider admitted radii still need live coverage.

The focused Kahlua harness also passed outbound and inbound schema-4 reloads,
receipt/session validation, and an unfilled request returning at its world-time
deadline with zero acquisitions. Gameplay, core 46/46, and installer 35/35
passed after these changes.

An active-cargo checkpoint in cloned run
`SC-Harness-20260927-184941-14ec5f4e` saved during the inbound phase, after
Encounter removed one exact `Base.FiberglassTape` from the native cupboard
(14 to 13 items). The leader carried its stable identity exactly once, the
schema-4 mission held one matching acquisition receipt, the companion
inventory snapshot held one matching item, and the menu handler flushed the
native slot and LF document before releasing the second view. A first reload
check (`185216`) ran before Build 42 had finished filling slot 1; the harness
was corrected to wait for the actual native handoff. The next reload
(`185357`) restored the same stable item identity on a newly created native
item, and the cupboard still had 13 items, but the return hit
`scout_stall_replan_limit`. This was a real failed return, not a cargo loss.
The planner had accumulated stall attempts across completed waypoints and
measurable progress. It now clears consecutive stall count on either event.

Reloads `SC-Harness-20260927-190015-3a9c42fd` and
`SC-Harness-20260927-190158-26810964` both reacquired the original leader in
slot 1 with one exact stable item, found no matching item left in the
13-item cupboard, walked home with no sampled step over 0.087 tiles, and
returned a `quantity_met` debrief with one acquisition and one returned ID.
Slot 1 released beside the original player. The focused core and installer
suites, gameplay suite, and static live-harness checks passed after the stall
counter change. This proves one controlled live reload with requested cargo
and two successful return replays from that checkpoint. The earlier failed
route also shows that transient pathing can vary; longer and more obstructed
returns still need trials. The staged and both returned native `players.db`
files retained exactly local player rows 1 and 2, with no row growth.
Persisted no-useful-container visits, multiple
requested categories, deeper site sweeps, natural-danger travel,
player-facing debrief, radio reports, and long road routing remain open.
