# Expedition save and restart probe

Private Build 42.20.4 tests on disposable Riverside save clones. The
installed launcher and original save were restored/unchanged after each run.

## Extra local-player rows

The original save's `players.db` had only local player ID 1, Hollis Britt.
After the no-teleport local out-and-back trip
`SC-Harness-20260927-045924-88439481`, the team view had been released in
memory, but `players.db` also held local player ID 2, Steve Walker. Restarting
that released clone in `SC-Harness-20260927-060451-e4d0bfc9` left slot 1
idle at startup and restored the four native companions; a new promotion
worked. On exit its cloned database held a further local player ID 3, Sam
Ellis. Thus releasing the view does not remove the companion's saved
local-player row, and repeated promotions accumulate rows even when the
active runtime appears healthy.

Inspection of the installed `PlayerDB` bytecode shows that
`savePlayersAsync()` iterates every occupied slot below
`IsoPlayer.numPlayers` and calls `savePlayerAsync()` for each. The public
`PlayerDBHelper.removePlayer()` method deletes from `networkPlayers`, not
`localPlayers`; it is not a cleanup method for this case. The test build does
not edit the game's database to hide this result.

## Active remote mission restart

`SC-Harness-20260927-055757-9ba26f67` saved a clone after the original
leader and two followers had moved through the remote area. Its database
held Hollis plus two companion local-player rows. The focused restart
`SC-Harness-20260927-060959-7a325dbf` waited ten seconds after LF restore.
The player remained alive in slot 0 and slot 1 was idle. LF had retained
snapshots for the two distant living companions at about `6160,6358` and
`6177,6362`, but neither had an active actor; both pending entries said
`saved square is not currently loaded`. The expedition mission was `nil`.
The first audit sampled too early in the restore cycle and is not used for
the companion count conclusion; the corrected run above is authoritative.

**W08 fails for the current prototype.** It does not restore an active remote
mission or its distant actors, and it leaves extra local-player records in
the game save. A persistent implementation must establish an authoritative
restart bootstrap for the actual companion leader and a safe native-player
save policy before expeditions can leave disposable test saves.

## Durable mission marker and local restart

The private build now stores a small expedition descriptor through the LF
persistence scheduler: roster and surviving companion IDs, leader ID, and
radio session/sequence. It does not serialize actor references or native
chunk maps. On load, it waits for the exact saved actors and then reacquires
slot 1; when actors are missing, it keeps the mission in an explicit
technical pause instead of silently dropping the assignment.

The remote checkpoint `SC-Harness-20260927-062009-46ce1221` saved a descriptor
for three living team members, though that short run's unrelated natural
zombie-motion assertion failed. Restart
`SC-Harness-20260927-062131-3cf37b7b` found all three snapshots pending at
unloaded remote squares, slot 1 empty, and the mission retained in technical
pause. A second restart `SC-Harness-20260927-062318-6975dae8` kept the same
descriptor and pending snapshots. This is a durable failure marker, not remote
mission recovery.

The local checkpoint `SC-Harness-20260927-062721-4e579229` saved a mission
with the original three companions. Reload
`SC-Harness-20260927-063558-8339eea9` passed: the same three actors were
active, the saved leader occupied slot 1, and direct Orders remained blocked.
With no equipped player radio, the remote radio order also stayed blocked.
The initial local audit `SC-Harness-20260927-062831-7dbe0968` used
`getPlayer()` as a slot-0 identity check, which is unreliable in splitscreen;
the corrected audit checked `getSpecificPlayer(0)` and passed. This proves
short local resume only. Native extra local-player rows and distant bootstrap
still keep W08 failing for release.

## Handoff save-identity check

The installed `PlayerDB.savePlayerAsync()` allocates a new SQL ID when a
slot-1 successor has `sqlId == -1`. The private bridge now carries the
departing slot-1 leader's existing SQL ID into an unsaved successor, after
checking neither identity overlaps the primary player's ID. This should
prevent one new local-player row per death handoff. The bridge compiles, the
focused Kahlua restart/casualty-return harness passes, and the full core gate
passes 46/46 with the new test included. The live cloned run
`SC-Harness-20260927-071012-38a9cd57` passed two successive death handoffs.
Its `players.db` held ID 1 Hollis Britt and only one companion row, ID 2
Rochelle Carter. The earlier `SC-Harness-20260927-055757-9ba26f67` had IDs
1, 2, and 3 after successive leaders. This is a row-growth fix for handoff,
not proof of reload or removal of the slot-1 row after a returned mission.

The same focused harness found and fixed a return edge: after a restart,
a companion already recorded as dead has no actor, so it must not be required
to assemble at the player. Living saved members still must be present and
within the normal return distance.

## Distant bootstrap seam

The installed Build 42.20.4 `AddCoopPlayer.update()` bytecode starts map
loading from the candidate player's X/Y coordinates, then calls
`setCurrentSquareFromPosition()` in its later add-to-world stage. This makes
an unloaded-square construction of the **actual saved companion leader** a
testable path to loading its area. It does not prove that constructing a
`SCNativeCompanion` without a square is safe or that the actor can be hydrated
and registered in place; both require live cloned-save tests.

`SCPersistence.pendingBootstrap(id)` now returns only a detached, validated
tile and survivor name/sex from a pending snapshot. It does not expose or
consume inventory, vitals, or the saved record, and a caller cannot mutate
the pending entry through the returned table. The transaction harness checks
the extracted data and this isolation. At that stage the native loader and
in-place actor adoption still needed implementation, followed by crash,
duplicate-actor and exact-item checks. W08 was failed.

`SCExpeditionPrototype.restartBootstrapCandidate()` narrows that read to the
saved surviving leader while the mission is paused. It returns no candidate
after a local mission has already reacquired its leader. The focused restart
harness verifies both sides of that ownership gate. No loader is attached to
the candidate yet.

The private bridge and cloned-save harness ran a **cold companion loader
probe**. It constructed an `SCNativeCompanion` at a verified unloaded tile and
asked the stock co-op loader to stream around it. The corrected live run
`SC-Harness-20260927-070854-319b29e0` passed: the actor acquired its remote
square in slot 1, the second viewport rendered, natural zombies moved, and
the distant square remained loaded for eight seconds. The first run proved
loading but failed two inherited observer assertions that expected a regular
player's singleton and bridge state; the harness now checks the companion
case and primary `OnTick` context explicitly. The probe actor is deliberately
unregistered and cannot count as a restored mission member. This proves the
native loader seam, not saved-actor hydration, inventory conservation, or W08.
The guarded-constructor rerun `SC-Harness-20260927-071653-31fc2732` also
passed after the probe adopted the production event mute. A separate original
leader run `SC-Harness-20260927-071419-4d70fe48` checked 21 worn items in
the second view; the underwear seen during the cold probe belongs to its
temporary undressed actor, not that saved companion.

The targeted checkpoint run `SC-Harness-20260927-072218-43f4de5a` loaded the
saved leader tile at `6084,6331` rather than the earlier generic test tile.
Normal persistence then restored all three original living companions within
1.1 tiles of their saved positions. The leader had 22 worn items. Slot 1 still
held the temporary loader actor, so the mission remained in technical pause.

The follow-up `SC-Harness-20260927-072529-f68b5ab9` replaced that temporary
actor with the exact registered saved leader. The temporary actor was removed
from native world membership, the slot-1 map stayed loaded, the leader passed
native validation, and the mission resumed. This handoff is explicitly driven
by the disposable test harness; production restart does not yet initiate it.
The resulting `players.db` held IDs 1, 2, and 3: the pre-existing companion
row at ID 2 remained and the newly restored leader received ID 3. Persistent
native player-row conservation therefore still fails W08/W10.

The second cloned restart `SC-Harness-20260927-073135-2b99e267` restored the
team and handoff again, but produced another native row because the temporary
slot-1 map loader was saved before handoff. The first attempt to persist the
slot ID also exposed that Kahlua does not read `IsoPlayer.sqlId` as a Lua
field; it wrote no `slotSqlId` key even though the native database assigned
ID 3. The private bridge now exposes the validated slot ID through a method,
and the handoff forces a native local-player save before the LF descriptor is
exported. The next checkpoint `SC-Harness-20260927-074627-d62f31c7` recorded
`slotSqlId` and a native leader ID of 3.

`SC-Harness-20260927-074816-94e74ce6` then resumed from that checkpoint with
the saved ID 3, but the temporary slot-1 loader still created row 4. The
loader now uses the saved slot ID while it streams the distant area; after
handoff the restored leader overwrites the same native row. The repeat run
`SC-Harness-20260927-075209-61fdbfa0` passed all saved-team, exact-leader,
native-validity and cleanup assertions, and `players.db` contained only IDs
1, 2, and 3. This proves no **additional** row on that repeat; the old ID 2
row remains. At that stage crash/mixed-save behavior during a temporary row
overwrite had not been verified, and the test harness still initiated the
remote loader and handoff.

The user's observed underwear was the temporary loader actor in the viewport.
That placeholder is now scene-culled during loading, and post-handoff capture
`build/remote-restart-dressed-team.png` shows the saved team. The live run
`SC-Harness-20260927-073930-b625a15e` counted 21, 10, and 21 worn items on
the three restored survivors; the before capture shows only saved members
while the temporary loader is hidden. This is visual proof for that scene,
not exhaustive appearance validation across every outfit.

## Automatic remote restart in the private test build

The ordinary `SCExpeditionPrototype.pulse()` now reads the pending saved-leader
tile, queues one hidden native co-op loader when that tile is unloaded, and
waits for normal LF persistence to restore the original surviving actors. It
then replaces the loader in slot 1 with the exact registered leader. The
loader is not an expedition member, does not receive commands, and is removed
from native world membership after handoff. The transient mission retains its
actor reference only for the disposable live harness cleanup assertion.

`SC-Harness-20260927-080214-839ee8a6` started from a clone of the saved remote
checkpoint `SC-Harness-20260927-074627-d62f31c7`. The harness observed normal
startup; it did not invoke either native loader or handoff. All three original
survivors restored within 0.71 tiles of their saved positions and wore 22, 10,
and 21 items. The exact saved leader occupied slot 1, was native-valid, and
kept SQL ID 3. The disposed loader had no current square or world membership.
The second chunk map still owned the remote square. Both captured viewports
showed the clothed team. The source and result `players.db` each held IDs 1,
2, and 3, so this run added no row. Core tests passed 46/46, and the live
harness passed every assertion in this focused run. The launcher was restored
to its original SHA-256 `69E8662B0709DE7F158045D23C017D95AF648735D1EF2A862358EC9AD631FE9C`.

The first run verifies an unattended normal reload from a clean checkpoint. It does
not prove a crash between native player-row save and LF descriptor save,
recovery when the saved leader is dead or quarantined, ghost-row removal after
mission release, or exact cargo conservation during an interrupted handoff.
The private expedition build remains limited to disposable cloned saves.

A second automatic reload, `SC-Harness-20260927-080441-a5c8600c`, started
from the first result and passed the same saved-team, outfit, native leader,
loader cleanup, and screenshot checks. Its `players.db` still contained only
IDs 1, 2, and 3. This checks repeat startup without another native player row;
it does not exercise a crash inside either save transaction.

## Forced crash after the temporary player row saves

The disposable harness can hold the exact moment after all saved companions
have restored but before slot 1 changes from the hidden loader to the saved
leader. In `SC-Harness-20260927-081214-58c92173`, it forced the native
`PlayerDB.saveLocalPlayersForce()` call on that temporary slot, captured the
view, then killed only the cloned game process. The harness confirmed three
survivors were restored and slot 1 was still the cold loader. The cloned
`players.db` kept IDs 1, 2, and 3, but ID 3's name changed from saved leader
Sam Ellis to temporary loader Marion Randall. `global_mod_data.bin` stayed
byte-identical to the source checkpoint (SHA-256
`98622466702CD70C15038527F14CBB05FEC7C105E076FCE5848FFC450D4AB1B9`).
This establishes a deliberately mixed native-player/LF-save state, rather
than only killing the client at an arbitrary time.

Restarting that crashed clone in `SC-Harness-20260927-081356-f36a53fc`
passed the automatic recovery checks. The three original survivors restored
within 0.71 tiles of their snapshots with 22, 10, and 21 worn items; the
saved leader resumed slot 1 with native SQL ID 3; and the temporary loader
left native world membership. The resulting `players.db` still had only IDs
1, 2, and 3, with ID 3 back to Sam Ellis. This proves recovery for the tested
ordering. A crash during in-flight loot and release-time ghost-row cleanup
remain open.

## Forced crash after an LF-first checkpoint

The second controlled ordering began from the native-row-first crash clone,
which already held a temporary name at SQL ID 3. The ordinary automatic
restart restored the saved team and handed slot 1 to Sam Ellis. The harness
then called `SC.Runtime.save()` and flushed only native `GlobalModData`, before
terminating the cloned client. Run `SC-Harness-20260927-082034-7b068c96`
recorded LF `savedAt` advancing from `1790488049341` to `1790490088604`.
`global_mod_data.bin` changed from SHA-256
`98622466702CD70C15038527F14CBB05FEC7C105E076FCE5848FFC450D4AB1B9`
to `FC119C40BFF8EA056EE6F17C4B75B548A6B97C9C410CA3D644B87E219089238C`.
The game had also saved the native slot during startup, changing its temporary
name to Bobbi Wilder; that `players.db` file was last written five seconds
before the LF file. Thus the LF checkpoint was newer, while native SQL ID 3
still described a temporary actor.

Restart `SC-Harness-20260927-082200-b081a11b` passed the saved-team,
clothing, exact slot-1 leader, native validity, loader-removal and retained
remote-area checks. Its `players.db` still held IDs 1, 2, and 3, with ID 3
back to Sam Ellis. This covers one LF-newer/native-older mixed checkpoint;
it does not prove atomicity across every interruption point, in-flight loot,
or cleanup of older companion rows.

## Reusing the native slot after a joined return

The original row-growth repro showed that native slot release leaves its
`localPlayers` row. The private build now saves the live slot ID before joined
release and exports a small `schema=2, state=idle` descriptor after the mission
ends. The next expedition passes that ID into native promotion; a reload
restores the idle marker without inventing an active mission. A malformed idle
ID such as 1 is rejected before it can claim the primary player's row.

`SC-Harness-20260927-083139-b26d6f91` ran a joined return from a fresh
original-save clone, then started a second expedition under a different saved
companion. Both leaders used native SQL ID 2. The result `players.db` held
only ID 1 Hollis Britt and ID 2 Sam Ellis, with no third row. This proves
same-session reuse after a return, not persistence through reload.

`SC-Harness-20260927-083916-4c4c3bc3` then staged a returned idle mission,
verified its LF descriptor held slot ID 2, and exited normally. Its database
held ID 1 Hollis Britt and ID 2 Steve Walker. Reload
`SC-Harness-20260927-084042-132579c6` restored the idle descriptor with
slot 1 empty, then started a new mission with Sam Ellis as leader. Slot 1
and the resulting database both used ID 2; the database still had exactly
two rows. This proves one persisted idle-slot reuse path. It does not remove
rows already left by older prototypes or prove cancellation, all-dead reuse,
disable, and failure rollback.

The all-dead lifecycle was then corrected: once every mission actor reaches
native death, the released view leaves an idle expedition descriptor instead
of a terminal mission that blocks future departures. A previously saved
casualty absent from the live roster no longer stalls this cleanup. Cloned
live run `SC-Harness-20260927-085148-837d40db` killed the three mission
members, released slot 1 and its UI, preserved the Riverside player, then
started a follow-on mission with the fourth original saved companion. The
follow-on view reused SQL ID 2, and `players.db` contained only ID 1 Hollis
Britt and ID 2 Steve Walker after exit. The focused core suite passed 46/46.
This proves same-session all-dead reuse. The first all-dead stage save
(`085503`) exposed a stale native row: slot ID 2 still named the dead leader
Sam Ellis but had `isDead=0`. The private bridge now forces a native player
save while that dead actor still owns slot 1, before UI and chunk release.
In cloned stage run `SC-Harness-20260927-085938-2f9aa3de`, row 2 was Sam
Ellis with `isDead=1` and the idle LF descriptor retained ID 2. Reload
`SC-Harness-20260927-090103-bc18208b` restored the one living original
companion, started a new expedition and reused ID 2; after exit row 2 named
Steve Walker with `isDead=0`. Both databases held exactly IDs 1 and 2. The
focused core suite passed 46/46 after the native save change. This proves
the all-dead idle reload path; removal of dormant or older ghost rows,
cancellation, disable and failure rollback remain open.

An active-remote menu-teardown probe found that the runtime previously
disposed actors while the expedition still owned the second local view. The
private bridge now unloads only LF's slot-1 chunk map and clears that slot
before actor disposal; the expedition removes its radio callback and clears
its old-world state after teardown. The first cloned run (`090741`) released
the view but exposed a pre-existing runtime reset order conflict: actor reset
rejected four registry records even after successful native disposal. The
runtime now allows that final actor reset only after `disposeAll` succeeds,
then clears the registry. Run `SC-Harness-20260927-091001-0c516821`
passed the direct `onMainMenuEnter` cleanup check with slot 0 preserved,
slot 1 empty, no old mission and zero registry records. A fresh clone of
its save (`SC-Harness-20260927-091346-19812d0a`) restored the exact three
dressed remote actors within 1.5 tiles of their snapshots and returned
slot 1 to the saved leader with SQL ID 2. The ten-second general audit
`SC-Harness-20260927-091520-424e7728` passed after its position tolerance
was corrected for normal post-reload movement. The core suite passed 46/46.
This directly invokes the menu handler inside a live cloned game; actual
menu UI event ordering, repeated exits and late native load completions
remain open.

The handler now performs a synchronous LF save and native GlobalModData flush
before it releases slot 1 and resets the runtime. A second cloned live run
`SC-Harness-20260927-091758-c8b14414` invoked the handler with **no harness
presave** and passed the owned-view, UI and actor cleanup checks. Its later
ordinary OnSave callback was correctly rejected after reset, leaving the
already flushed document intact. Reload
`SC-Harness-20260927-091917-8c381a8c` restored all three original remote
companions with worn counts 21/10/21, reacquired the exact saved leader and
reused slot ID 2 without row growth. This verifies the direct handler's
save-before-teardown ordering; the actual game UI event sequence is still
untested.

The save-before-teardown path also handles a released, idle slot. A cloned
all-dead run `SC-Harness-20260927-092221-5108560b` killed the three mission
members, released slot 1, then called the menu handler without a harness
presave. The handler flushed the idle descriptor and cleared runtime state.
Reload `SC-Harness-20260927-092341-d824b949` restored exactly one living
companion and the idle SQL ID 2; that companion started a new mission in slot
1 using ID 2. Both the active and idle checks invoke the handler directly
inside the live engine. They do not yet prove the timing of the game's actual
Quit to Main Menu UI event.

Reproduce the automatic restart from the retained remote checkpoint:

```powershell
& .\scripts\Build-NativeBridge.ps1 -InstallIntoPayload
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave '.\build\live-sandbox-runs\SC-Harness-20260927-074627-d62f31c7\cache\Saves\Rising\SC-Harness-20260927-074627-d62f31c7' `
    -GameMode Rising -ColdCompanionProbe -ColdRestartProbe `
    -ColdRestartHandoff -TimeoutSeconds 300
```

Reproduce the forced native-row-first crash on another clone of that
checkpoint, then use the emitted `save=` path as the seed for the normal
automatic restart command above:

```powershell
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave '.\build\live-sandbox-runs\SC-Harness-20260927-074627-d62f31c7\cache\Saves\Rising\SC-Harness-20260927-074627-d62f31c7' `
    -GameMode Rising -ColdCompanionProbe -ColdRestartProbe `
    -ColdRestartCrashProbe -TimeoutSeconds 300
```

To create an LF-newer checkpoint, use the emitted crash `save=` path as
`-SeedSave` and run the same command with
`-ColdRestartLfFirstCrashProbe` in place of `-ColdRestartCrashProbe`.

Reproduce the generic cold-loader seam on an isolated save:

```powershell
& .\scripts\Invoke-SplitScreenSpike.ps1 `
    -SeedSave 'C:\Users\thore\Zomboid\Saves\Rising\2026-09-21_22-10-41' `
    -GameMode Rising -ColdCompanionProbe -TimeoutSeconds 300 `
    -Screenshot '.\build\cold-companion-loader-probe.png'
```
