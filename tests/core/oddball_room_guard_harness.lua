-- SPDX-License-Identifier: MIT

local F = RoomGuardFixture
local Guard = SurvivorCompanion.OddballRoomGuard
local room = {}
local inside = F.square(10, 10, 0, room)
local sameRoom = F.square(10, 11, 0, room)
F.square(10, 9, 0, nil)
F.square(9, 10, 0, nil)

local northDoor = F.opening("IsoDoor", inside, true, "door")
local westDoor = F.opening("IsoDoor", inside, false, "door")
local westWindow = F.opening("IsoWindow", inside, false, "window")
local northThumpWindow = F.opening("IsoThumpable", inside, true, "windowN")
local westThumpWindow = F.opening("IsoThumpable", inside, false, "windowW")
local furniture = F.opening("IsoThumpable", inside, true, "furniture")
local sameRoomDoor = F.opening("IsoDoor", sameRoom, true, "door")
inside.objects = { northDoor, westDoor, westWindow, furniture }
inside.specialObjects = { northThumpWindow, westThumpWindow }
sameRoom.objects = { sameRoomDoor }

local group = F.group("room", { x = 10, y = 10, z = 0 })
local far = { x = 100, y = 100, z = 0 }
local near = { x = 10.5, y = 10.5, z = 0 }
local zombie = F.zombie()
zombie.target = northDoor
assert(Guard.onZombieUpdate(zombie) == false and zombie.thumpReads == 0,
    "idle zombie updates do not read thump target")

assert(Guard.install() == true and Guard.isInstalled())
assert(Guard.install() == true and #Events.OnZombieUpdate.callbacks == 0
    and not Guard.isAttached(),
    "install must be idempotent and leave zombie updates alone while no room is guarded")
assert(Guard.register(group, far, 0) == true, "resident room registration")
assert(Guard.register(group, far, 0) == true
    and #Events.OnZombieUpdate.callbacks == 1 and Guard.isAttached(),
    "register must be idempotent and attach the zombie hook once")

for _, opening in ipairs({ northDoor, westDoor, westWindow,
    northThumpWindow, westThumpWindow }) do
    assert(opening.getOppositeSquare == nil, "fixture must use B42 orientation")
    zombie.target = opening
    assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil,
        "north/west opening must be protected")
    assert(opening.health == 42 and opening.sprite == "untouched",
        "guard must not alter world object state")
end
for _, object in ipairs({ furniture, sameRoomDoor }) do
    zombie.target = object
    assert(Guard.onZombieUpdate(zombie) == false and zombie.target == object,
        "furniture and same-room edges must stay unprotected")
end
zombie.target = northDoor
zombie.alife = true
assert(Guard.onZombieUpdate(zombie) == false and zombie.target == northDoor,
    "A-Life shells are not ordinary zombies")
zombie.alife = false

inside.objects = { westDoor, westWindow, furniture }
assert(Guard.pulse(group, far, 30000) == true, "rescan")
zombie.target = northDoor
assert(Guard.onZombieUpdate(zombie) == false and zombie.target == northDoor,
    "rescan must drop removed object references")
zombie.target = westDoor
assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil,
    "rescan retains live opening references")
local overlap = F.group("overlap", { x = 10, y = 10, z = 0 })
assert(Guard.register(overlap, far, 30000) == true)
assert(Guard.release(group.id) == true)
zombie.target = westDoor
assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil,
    "shared opening remains protected by another active scene")
assert(Guard.release(overlap.id) == true)
local readsAfterOverlap = zombie.thumpReads
assert(Guard.onZombieUpdate(zombie) == false
    and zombie.thumpReads == readsAfterOverlap,
    "last owner removal clears zombie hot path")
assert(#Events.OnZombieUpdate.callbacks == 0 and not Guard.isAttached(),
    "last owner removal detaches the zombie hook")

Guard.reset()
local timed = F.group("timed", { x = 10, y = 10, z = 0 })
assert(Guard.register(timed, far, 0) == true)
assert(timed.oddball.roomGuardElapsedMs == 0
    and timed.oddball.roomGuardDone == false,
    "legacy grace state initializes on registration")
for second = 1, 299 do
    assert(Guard.pulse(timed, far, second * 1000) == true,
        "five real minutes cannot end early: second " .. second)
end
local active, reason = Guard.pulse(timed, far, 300000)
assert(active == false and reason == "time_elapsed", tostring(reason))
assert(timed.oddball.roomGuardElapsedMs == 300000
    and timed.oddball.roomGuardDone == true,
    "expiry persists completion and elapsed time")
zombie.target = westDoor
assert(Guard.onZombieUpdate(zombie) == false and zombie.target == westDoor,
    "expiry removes protection")
assert(Guard.pulse(timed, far, 301000) == false,
    "completed group cannot rearm in the same session")

Guard.reset()
local expiredCopy = F.group("timed", { x = 10, y = 10, z = 0 })
expiredCopy.oddball.roomGuardElapsedMs = timed.oddball.roomGuardElapsedMs
expiredCopy.oddball.roomGuardDone = timed.oddball.roomGuardDone
local expiredActive, expiredReason = Guard.pulse(expiredCopy, far, 0)
assert(expiredActive == false and expiredReason == "already_finished",
    "expired group cannot rearm after reload")
local paused = F.group("paused", { x = 10, y = 10, z = 0 })
assert(Guard.register(paused, far, 0) == true)
F.multiplier = 0
assert(Guard.pulse(paused, far, 200000) == true, "pause does not expire guard")
F.multiplier = 1
assert(Guard.pulse(paused, far, 201000) == true, "resume counts active time")
assert(Guard.pulse(paused, far, 401000) == true,
    "long scheduler gaps are capped")
F.localPlayers = { far, near }
local nearActive, nearReason = Guard.pulse(paused, far, 402000)
assert(nearActive == false and nearReason == "player_near_room",
    "second local player releases guard: " .. tostring(nearReason))
assert(paused.oddball.roomGuardDone == true
    and paused.oddball.roomGuardElapsedMs < 300000,
    "approach persists completion without exhausting timer")
F.localPlayers = {}

Guard.reset()
local approachedCopy = F.group("paused", { x = 10, y = 10, z = 0 })
approachedCopy.oddball.roomGuardElapsedMs = paused.oddball.roomGuardElapsedMs
approachedCopy.oddball.roomGuardDone = paused.oddball.roomGuardDone
assert(Guard.pulse(approachedCopy, far, 0) == false,
    "approached group cannot rearm after reload")
local restored = F.group("restored", { x = 10, y = 10, z = 0 })
assert(Guard.register(restored, far, 0) == true)
assert(Guard.pulse(restored, far, 1000) == true)
assert(restored.oddball.roomGuardElapsedMs == 1000)
local restoredCopy = F.group("restored", { x = 10, y = 10, z = 0 })
restoredCopy.oddball.roomGuardElapsedMs = restored.oddball.roomGuardElapsedMs
restoredCopy.oddball.roomGuardDone = restored.oddball.roomGuardDone
Guard.reset()
assert(Guard.pulse(restoredCopy, far, 10000) == true,
    "spawned resident resumes its remaining grace after restore")
assert(restoredCopy.oddball.roomGuardElapsedMs == 1000,
    "restore does not reset elapsed grace")
assert(Guard.pulse(restoredCopy, far, 11000) == true
    and restoredCopy.oddball.roomGuardElapsedMs == 2000)
assert(Guard.abort(restoredCopy.id) == true)
assert(Guard.register(restoredCopy, far, 12000) == true,
    "retryable spawn abort does not finish group")
assert(restoredCopy.oddball.roomGuardElapsedMs == 2000,
    "abort preserves elapsed grace")
assert(Guard.release(restoredCopy.id) == true)
assert(Guard.register(restoredCopy, far, 0) == false,
    "terminal release prevents another grace period")
local readsAfterRelease = zombie.thumpReads
assert(Guard.onZombieUpdate(zombie) == false
    and zombie.thumpReads == readsAfterRelease,
    "released guard leaves no zombie hot-path lookup")

-- Lonnie's church and vestry are two protected room identities. The door
-- between them remains a boundary of each, despite both rooms being tracked.
Guard.reset()
local church, vestry = {}, {}
local churchSquare = F.square(12, 10, 0, church)
local vestrySquare = F.square(13, 10, 0, vestry)
local vestryDoor = F.opening("IsoDoor", vestrySquare, false, "door")
vestrySquare.objects = { vestryDoor }
local lonnie = F.group("lonnie", { x = 12, y = 10, z = 0 },
    { x = 13, y = 10, z = 0 })
assert(churchSquare:getRoom() ~= vestrySquare:getRoom())
assert(Guard.register(lonnie, far, 0) == true)
zombie.target = vestryDoor
assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil,
    "Lonnie's vestry door is protected")

-- A resident scene also protects the rooms occupied by other members and
-- Deputy's captives, without pulling in unrelated destination props.
Guard.reset()
local memberRoom, captiveRoom, destinationRoom = {}, {}, {}
local memberSquare = F.square(11, 12, 1, memberRoom)
local captiveSquare = F.square(12, 12, 0, captiveRoom)
local destinationSquare = F.square(13, 12, 0, destinationRoom)
F.square(11, 11, 1, nil)
F.square(12, 11, 0, nil)
F.square(13, 11, 0, nil)
local memberDoor = F.opening("IsoDoor", memberSquare, true, "door")
local captiveDoor = F.opening("IsoDoor", captiveSquare, true, "door")
local destinationDoor = F.opening("IsoDoor", destinationSquare, true, "door")
memberSquare.objects = { memberDoor }
captiveSquare.objects = { captiveDoor }
destinationSquare.objects = { destinationDoor }
local ensemble = F.group("ensemble", { x = 10, y = 10, z = 0 })
ensemble.oddball.site.memberSpawns = { { x = 11, y = 12, z = 1 } }
ensemble.oddball.site.captiveSpawns = { { x = 12, y = 12, z = 0 } }
ensemble.oddball.site.homeZombie = { x = 13, y = 12, z = 0 }
assert(Guard.register(ensemble, far, 0) == true)
for _, opening in ipairs({ memberDoor, captiveDoor }) do
    zombie.target = opening
    assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil,
        "occupied member or captive room boundary")
end
zombie.target = destinationDoor
assert(Guard.onZombieUpdate(zombie) == false and zombie.target == destinationDoor,
    "destination prop room is outside encounter scope")

-- An empty scan must not claim a grace period. The spawned-group pulse retries
-- after a cooldown, then starts protection once a live door is available.
Guard.reset()
local emptyRoom = {}
local emptySquare = F.square(9, 13, 0, emptyRoom)
F.square(9, 12, 0, nil)
local emptyGroup = F.group("empty", { x = 9, y = 13, z = 0 })
local reports = {}
SurvivorCompanion.Diagnostics = { report = function(_, _, _, reason)
    reports[#reports + 1] = reason
end }
local registered, emptyReason = Guard.register(emptyGroup, far, 0)
assert(registered == false and emptyReason == "room_openings_unavailable",
    tostring(emptyReason))
assert(#reports == 1 and reports[1] == "room_openings_unavailable",
    "missing native openings produce one diagnostic")
local readsAfterEmpty = F.gridReads
local retry, retryReason = Guard.pulse(emptyGroup, far, 1000)
assert(retry == false and retryReason == "room_openings_retry_wait",
    tostring(retryReason))
assert(F.gridReads == readsAfterEmpty and #reports == 1,
    "cooldown avoids another scan or diagnostic")
local newDoor = F.opening("IsoDoor", emptySquare, true, "door")
emptySquare.objects = { newDoor }
assert(Guard.pulse(emptyGroup, far, 10000) == true,
    "cooldown retry discovers a live opening")
zombie.target = newDoor
assert(Guard.onZombieUpdate(zombie) == true and zombie.target == nil)

-- The locked horde room does not expire merely because the player approaches;
-- Vera's bedroom stays safe until the player enters or confronts her.
Guard.reset()
inside.objects = { westDoor }
local sealed = F.group("sealed", { x = 9, y = 10, z = 0 })
sealed.oddball.id = "survivalist_locked_horde"
sealed.oddball.site.sealedRoom = { x = 10, y = 10, z = 0 }
local outsidePlayer = { x = 9.5, y = 10.5, z = 0 }
assert(Guard.register(sealed, outsidePlayer, 0) == true)
assert(Guard.pulse(sealed, outsidePlayer, 400000) == true,
    "sealed horde is protected past the ordinary five-minute grace")
sealed.oddball.sealBroken = true
assert(Guard.pulse(sealed, outsidePlayer, 401000) == false,
    "breaking the seal releases the horde")
Guard.reset()
local opened = F.group("opened", { x = 9, y = 10, z = 0 })
opened.oddball.id = "survivalist_locked_horde"
opened.oddball.site.sealedRoom = { x = 10, y = 10, z = 0 }
assert(Guard.register(opened, outsidePlayer, 0) == true)
function westDoor:IsOpen() return true end
local protected, breachedReason = Guard.pulse(opened, outsidePlayer, 1000)
assert(protected == false and breachedReason == "room_opening_breached",
    "an opened sealed-room boundary releases the real horde")
function westDoor:IsOpen() return false end

Guard.reset()
SurvivorCompanion.GameplayUtil.squareOf = function(player)
    return F.squares[F.key(math.floor(player.x), math.floor(player.y), 0)]
end
local voice = F.group("voice", { x = 10, y = 10, z = 0 })
voice.oddball.id = "voice_actor_vera_quill"
assert(Guard.register(voice, outsidePlayer, 0) == true,
    "nearby player does not discard Vera's bedroom protection")
assert(Guard.pulse(voice, outsidePlayer, 400000) == true,
    "voice actor's closed bedroom persists past ordinary grace")
voice.oddball.confronted = true
assert(Guard.pulse(voice, outsidePlayer, 401000) == false,
    "confronting Vera releases room protection")
Guard.reset()
local enteredVoice = F.group("entered-voice", { x = 10, y = 10, z = 0 })
enteredVoice.oddball.id = "voice_actor_vera_quill"
assert(Guard.register(enteredVoice, outsidePlayer, 0) == true)
assert(Guard.pulse(enteredVoice, near, 1000) == false,
    "entering Vera's room releases its opening protection")

-- Milli keeps the room closed while the player is still beyond her shorter
-- approach radius, including the 12..18 tile range of ordinary residents.
Guard.reset()
local milliBuilding = {}
function inside:getBuilding() return milliBuilding end
local milli = F.group("milli", { x = 10, y = 10, z = 0 })
milli.oddball.id = "milli_tea_and_trouble"
local outsideFifteen = { x = 25.5, y = 10.5, z = 0 }
local outsideTen = { x = 20.5, y = 10.5, z = 0 }
assert(Guard.register(milli, outsideFifteen, 0) == true)
assert(Guard.pulse(milli, outsideFifteen, 1000) == true,
    "Milli guard remains active beyond twelve tiles")
assert(Guard.pulse(milli, outsideTen, 2000) == false,
    "Milli guard releases inside twelve tiles")

Guard.reset()
SurvivorCompanion.Config = { get = function(key)
    if key == "oddballMilliGuardReleaseTiles" then return 1 end
end }
local entrySquare = F.square(13, 13, 0, nil)
function entrySquare:getBuilding() return milliBuilding end
local enteredHouse = { x = 13.2, y = 13.2, z = 0 }
local milliHouse = F.group("milli-house", { x = 10, y = 10, z = 0 })
milliHouse.oddball.id = "milli_tea_and_trouble"
assert(Guard.register(milliHouse, outsideFifteen, 0) == true)
assert(Guard.pulse(milliHouse, enteredHouse, 1000) == false,
    "entering Milli's building releases the room even outside approach radius")
SurvivorCompanion.Config = nil

-- A player directly below an upstairs bedroom is neither in the room nor
-- inside its building, so horizontal proximity alone must not end the guard.
Guard.reset()
local upperRoom, upperBuilding = {}, {}
local upperSquare = F.square(12, 10, 1, upperRoom)
F.square(12, 9, 1, nil)
F.square(12, 10, 0, nil)
function upperSquare:getBuilding() return upperBuilding end
local upperDoor = F.opening("IsoDoor", upperSquare, true, "door")
upperSquare.objects = { upperDoor }
local upperMilli = F.group("upper-milli", { x = 12, y = 10, z = 1 })
upperMilli.oddball.id = "milli_tea_and_trouble"
local directlyBelow = { x = 12.5, y = 10.5, z = 0 }
local inUpperRoom = { x = 12.5, y = 10.5, z = 1 }
assert(Guard.register(upperMilli, directlyBelow, 0) == true)
assert(Guard.pulse(upperMilli, directlyBelow, 1000) == true,
    "player below upstairs room does not release its guard")
assert(Guard.pulse(upperMilli, inUpperRoom, 2000) == false,
    "player on upstairs room floor releases its guard")

-- A failed attach leaves the scene registered and is retried by the next
-- rescan rather than every pulse.
Guard.reset()
local retryRoom = {}
local retrySquare = F.square(11, 9, 2, retryRoom)
F.square(11, 8, 2, nil)
retrySquare.objects = { F.opening("IsoDoor", retrySquare, true, "door") }
local retried = F.group("retried", { x = 11, y = 9, z = 2 })
local addZombieHook = Events.OnZombieUpdate.Add
Events.OnZombieUpdate.Add = function() error("event list busy") end
assert(Guard.register(retried, far, 0) == true and not Guard.isAttached()
    and #Events.OnZombieUpdate.callbacks == 0,
    "a failed attach keeps the scene registered without a hook")
Events.OnZombieUpdate.Add = addZombieHook
assert(Guard.pulse(retried, far, 1000) == true and not Guard.isAttached(),
    "the attach is not retried on every pulse")
assert(Guard.pulse(retried, far, 30000) == true and Guard.isAttached()
    and #Events.OnZombieUpdate.callbacks == 1,
    "the next rescan attaches the zombie hook")

assert(Guard.remove() == true and not Guard.isInstalled()
    and not Guard.isAttached() and #Events.OnZombieUpdate.callbacks == 0,
    "remove detaches the native event")
assert(Guard.register(F.group("after-remove", { x = 11, y = 9, z = 2 }), far, 40000)
    == true and #Events.OnZombieUpdate.callbacks == 0,
    "a scene registered after teardown never attaches the hook")
assert(Guard.install() == true and Guard.isAttached()
    and #Events.OnZombieUpdate.callbacks == 1,
    "reinstalling with a guarded scene attaches the hook")
assert(Guard.remove() == true and #Events.OnZombieUpdate.callbacks == 0,
    "second teardown detaches again")

for _, id in ipairs({ "garage_rescue_eli_rourke",
    "radio_rescue_nate_duvall" }) do
    Guard.reset()
    assert(Guard.install() == true)
    local rescueRoom = {}
    local rescueSquare = F.square(10, 10, 0, rescueRoom)
    F.square(10, 9, 0, nil)
    local rescueDoor = F.opening("IsoDoor", rescueSquare, true, "door")
    function rescueDoor:IsOpen() return self.open == true end
    rescueSquare.objects = { rescueDoor }
    local rescue = F.group("guard-" .. id,
        { x = 10, y = 10, z = 0 })
    rescue.oddball.id = id
    rescue.oddball.roomGuardElapsedMs = 300000
    assert(Guard.register(rescue, near, 0) == true
        and Guard.pulse(rescue, near, 1000) == true,
        "rescue room remains guarded past five minutes and player approach")
    rescueDoor.open = true
    assert(Guard.pulse(rescue, near, 2000) == false
        and rescue.oddball.roomGuardDone == true,
        "opening the rescue door releases the protected room")
    Guard.remove()
end
SC_TEST_REPORT = "Oddball room guard oriented boundary and active-play regression PASS"
