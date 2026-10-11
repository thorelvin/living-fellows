-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local clock = 1000
local room = { name = "bedroom" }
local hall = { name = "hall" }
local bed = { kind = "bed" }
local bedFoot = { kind = "bed_foot" }
local pillowFoot = { kind = "pillow_foot" }
local bedSprite = { kind = "bed_sprite" }
local bedFootSprite = { kind = "bed_foot_sprite" }
local pillowFootSprite = { kind = "pillow_foot_sprite" }
local bedGrid = {}
local tiles = {}
local function tile(x, y, currentRoom)
    local value = { x = x, y = y, z = 0, room = currentRoom,
        objects = {} }
    tiles[x .. ":" .. y] = value
    return value
end
local floor = tile(10, 10, room)
local bedTile = tile(11, 10, room)
local deathFloor = tile(9, 10, room)
local invalidBedEntry = tile(11, 9, hall)
bedTile.objects[1] = bed
local inside = tile(12, 10, room)
inside.objects[1], bed.square, bedFoot.square = bedFoot, bedTile, inside
local northHeadEntry = tile(12, 9, room)
local pillowFootTile = tile(11, 11, room)
pillowFoot.square = pillowFootTile
local outside = tile(30, 10, hall)
local player = { x = 30, y = 10, z = 0, square = outside }
local actor = { id = "arthur", x = 10, y = 10, z = 0,
    square = floor, inv = { items = {} }, onBed = false }
local group = { id = "arthur-group", standing = "Neutral",
    members = { { actorId = "arthur", alive = true } },
    oddball = { id = "bedridden_arthur_hale", site = {
        spawn = { x = 10, y = 10, z = 0 },
        bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
        floor = { x = 9, y = 10, z = 0 },
    } } }
local retired = 0
local retiredReasons = {}
local ended = 0
local spoken = {}
local coughMoves = 0
local restCalls = 0
SCBridge = { setOnBedRenderLift = function(_, milliTiles)
    return milliTiles == 180 or milliTiles == 0
end }
local coughMode = "normal"
local endLifeShouldFail = false
local routeShouldFailPrimary = false
local rejectOccupiedStart = false
SC.UserOptions = { get = function(key)
    return key == "coughSneezes" and coughMode or nil
end }
SC.NativeList = {
    get = function(list, index) return list[index + 1] end,
    size = function(list) return #list end,
}
SC.GameplayUtil = {
    nowMs = function() return clock end,
    idOf = function(value) return value and value.id end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function(value) return value and value.dead == true end,
    gridSquare = function(x, y) return tiles[x .. ":" .. y] end,
    isClearActorSpawnSquare = function(value)
        return value == floor or value == deathFloor
            or value == northHeadEntry
    end,
    squareOf = function(value) return value and value.square end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    call = function(value, method, ...)
        if value == nil then return nil, false end
        if method == "getRoom" then return value.room, true end
        if method == "getObjects" then return value.objects, true end
        if method == "getName" and (value == bed or value == bedFoot
            or value == pillowFoot) then
            return "Bed", true end
        if method == "getSprite" and value == bed then
            return bedSprite, true end
        if method == "getSprite" and value == bedFoot then
            return bedFootSprite, true end
        if method == "getSprite" and value == pillowFoot then
            return pillowFootSprite, true end
        if method == "getSpriteGrid" and (value == bedSprite
            or value == bedFootSprite or value == pillowFootSprite) then
            return bedGrid, true end
        if method == "getSpriteGridPosX" and value == bedGrid then
            return (...) == bedFootSprite and 1 or 0, true end
        if method == "getSpriteGridPosY" and value == bedGrid then
            return (...) == pillowFootSprite and 1 or 0, true end
        if method == "getWidth" and value == bedGrid then return 2, true end
        if method == "getHeight" and value == bedGrid then return 1, true end
        if method == "isZombiesDontAttack" then
            return value.zombieIgnored == true, true end
        if method == "isOnBed" then return value.onBed == true, true end
        if method == "isCollidable" then
            return value.collidable == true, true end
        if method == "setCollidable" then
            value.collidable = (...) == true
            return nil, true end
        if method == "getCompanionMovementOwner" then
            return value.movementOwner or "none", true end
        if method == "getAnimAngleRadians" then
            return value.animAngle, value.animAngle ~= nil end
        if method == "getDir" then
            return value.dir or "E", true end
        if method == "getVariableBoolean" then
            return value.onBedStarted == true, true end
        if method == "setVariable" then
            local key, setting = ...
            value.variables = value.variables or {}
            value.variables[key] = setting
            return nil, true
        end
        if method == "setX" or method == "setY"
            or method == "setNextX" or method == "setNextY" then
            local field = method:sub(4, 4):lower() .. method:sub(5)
            value[field] = (...)
            return nil, true
        end
        if method == "isSittingOnFurniture" then
            return value.seated == true, true end
        if method == "getSitOnFurnitureObject" then
            return value.seatObject, true end
        if method == "isSitOnGround" then return false, true end
        if method == "setAsleep" then value.asleep = (...) return true, true end
        if method == "setName" then value.name = (...) return true, true end
        return nil, false
    end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(inv) return inv.items end,
    modData = function(value)
        value.modData = value.modData or {}
        return value.modData
    end,
    addItem = function(inv, kind)
        local item = { kind = kind, modData = {} }
        inv.items[#inv.items + 1] = item
        return item
    end,
    directInteractionAccess = function() return true, {} end,
    move = function(value, _, intent)
        assert(intent.action == "rest_bed")
        restCalls = restCalls + 1
        -- Vanilla ISRestAction on a bed uses the furniture seated pose.
        value.seated, value.seatObject, value.bedStatus = true, bed, "entered"
        value.x, value.y, value.square = 11, 10, bedTile
        return true, "resting"
    end,
    say = function(_, line)
        spoken[#spoken + 1] = line
        return true
    end,
}
SC.Registry = { byId = function(id)
    return id == "arthur" and { actor = actor } or nil
end }
SC.Actor = {
    setMovement = function(_, _, intent)
        assert(intent.action == "ext_gesture")
        coughMoves = coughMoves + 1
        return true
    end,
    endLife = function(value)
        assert(value == actor)
        if endLifeShouldFail then return false, "native_refused" end
        ended = ended + 1
        value.dead = true
        -- The real OnCharacterDeath event can fire inside the native call.
        assert(SC.OddballBedridden.onKeeperDeath(value, group))
        return true
    end,
    recover = function(value, target)
        assert(value == actor and (target == floor or target == deathFloor))
        value.x, value.y, value.square = target.x, target.y, target
        return true
    end,
}
SC.NativeActions = {
    bedStatus = function(value) return value.bedStatus or "none" end,
    leaveSeating = function(value)
        value.onBed, value.seated, value.seatObject = false, false, nil
        value.bedStatus = "none"
        return true
    end,
}
SC.Navigation = {
    request = function(value, target, _, intent)
        assert(intent.action == "oddball_arthur_floor")
        assert(not rejectOccupiedStart or value.square ~= bedTile,
            "native navigation cannot start inside an occupied bed")
        if routeShouldFailPrimary and target == deathFloor then
            return false, "route_blocked"
        end
        value.x, value.y, value.square = target.x, target.y, target
        return true, "floor_reached"
    end,
    requestAny = function() error("Arthur starts next to his bed") end,
}
SC.Oddballs = SC.Oddballs or {}
SC.Oddballs.setZombieShelter = function(value, enabled)
    value.zombieIgnored = enabled
    return true
end
SC.Oddballs.retire = function(value, reason)
    assert(value == group)
    retired = retired + 1
    retiredReasons[#retiredReasons + 1] = reason
    value.oddball.stage = reason
    return true
end
SC.OddballRoomGuard = { release = function() return true end }

local Bedridden = SC.OddballBedridden
assert(Bedridden.onSpawn(group, actor))
assert(actor.inv.items[1].kind == "Base.LetterHandwritten")
assert(actor.inv.items[1].name == "Arthur's unsent letter to Evelyn")
assert(Bedridden.onSpawn(group, actor))
assert(#actor.inv.items == 1, "save/load initialization does not copy the letter")
assert(actor.zombieIgnored == true)
group.oddball.roomGuardDone = true
assert(Bedridden.zombiesIgnore(actor, group) == true,
    "opening protection may expire while Arthur remains sheltered")
assert(Bedridden.intentFor(actor, player, nil, group).mode == "bedridden_arthur")
actor.bedStatus = "entering"
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(restCalls == 0, "pending native bed entry is not queued twice")
actor.bedStatus = "none" -- action record may be absent after reload
actor.onBed, actor.onBedStarted = true, true
actor.x, actor.y, actor.square = 11.5, 10.5, bedTile
actor.movementOwner, actor.collidable = "seating", false
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.variables.OnBedAnim == "Asleep" and restCalls == 0,
    "native lying pose survives missing bed action record")

player.x, player.square = 12, inside
clock = 2000
assert(Bedridden.pulse(group, player, clock))
assert(group.oddball.stage == "pleading")
assert(#Bedridden.menuOptions(group, player) == 3)
assert(Bedridden.action(group, "hurt", player))
assert(group.standing == "Neutral" and ended == 0)
group.oddball.nextCoughAt = clock
coughMode = "off"
assert(Bedridden.pulse(group, player, clock))
assert(coughMoves == 0, "the player's symptom toggle suppresses coughing")
coughMode = "normal"
player.x, player.square = 30, outside
clock = 3000
assert(Bedridden.pulse(group, player, clock))
assert(group.oddball.stage == "left_alone")
assert(actor.zombieIgnored == true,
    "zombies cannot interrupt his authored floor death after departure")
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.onBed and ended == 0, "short absence does not kill")
player.x, player.square = 12, inside
clock = 5000
assert(Bedridden.pulse(group, player, clock))
assert(group.oddball.stage == "pleading",
    "quick return cancels unattended death")
player.x, player.square = 30, outside
clock = 6000
assert(Bedridden.pulse(group, player, clock))
clock = 13000
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.onBed and actor.variables.forceGetUp == true and ended == 0,
    "Arthur keeps the native on-bed flag through the get-up clip")
actor.onBed, actor.onBedStarted = false, false
actor.movementOwner = "none"
rejectOccupiedStart = true
clock = 14000
player.x, player.square = 12, inside
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_waiting_for_private_bed_exit"
    and actor.square == bedTile and actor.collidable == true,
    "a returning player never sees Arthur relocate off the mattress")
player.x, player.square = 30, outside
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_stepped_clear_of_bed"
    and actor.square == deathFloor and actor.collidable == true and ended == 0,
    "native get-up restores collision and clears the blocked bed tile")
clock = 15000
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.dead and ended == 1 and actor.square == deathFloor,
    "native death occurs on clear bedroom floor")
rejectOccupiedStart = false
assert(actor.zombieIgnored == false
    and Bedridden.zombiesIgnore(actor, group) == false,
    "native death confirmation releases Arthur's zombie shelter")
assert(retiredReasons[1] == "died_alone"
    and group.oddball.stage == "died_alone",
    "synchronous callback sees unattended outcome")
assert(Bedridden.pulse(group, player, clock))
assert(retired == 1 and group.oddball.deathConfirmed == true)
assert(Bedridden.pulse(group, player, clock + 1000))
assert(retired == 1, "death retirement runs only once")
assert(#Bedridden.menuOptions(group, player) == 0)

-- The explicit mercy choice takes the same native death path without
-- requiring that the player leave, and an unarmed accidental hit does not.
actor = { id = "arthur", x = 10, y = 10, z = 0,
    square = floor, inv = { items = {} }, onBed = false }
group.oddball = { id = "bedridden_arthur_hale", site = {
    spawn = { x = 10, y = 10, z = 0 },
    bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
    floor = { x = 9, y = 10, z = 0 } } }
player.x, player.square = 12, inside
clock = 20000
assert(Bedridden.onSpawn(group, actor))
endLifeShouldFail = true
assert(not Bedridden.action(group, "mercy_arthur", player))
assert(group.oddball.outcome == nil and actor.dead ~= true,
    "failed native mercy attempt restores outcome")
endLifeShouldFail = false
assert(Bedridden.action(group, "mercy_arthur", player))
assert(actor.dead and group.oddball.outcome == "mercy")
assert(Bedridden.onKeeperDeath(actor, group))
assert(not Bedridden.onKeeperDeath({ id = "stranger" }, group))
assert(Bedridden.pulse(group, player, clock))
assert(retired == 2 and group.oddball.deathConfirmed == true)
assert(retiredReasons[2] == "mercy_granted"
    and group.oddball.stage == "mercy_granted",
    "synchronous callback sees mercy outcome")

-- If the preferred clear tile becomes unreachable, the already verified
-- clear spawn tile is a nonteleport fallback in the same bedroom.
actor = { id = "arthur", x = 11, y = 10, z = 0,
    square = bedTile, inv = { items = {} }, onBed = false }
group.oddball = { id = "bedridden_arthur_hale", stage = "left_alone",
    leftAt = 20000, site = {
        spawn = { x = 10, y = 10, z = 0 },
        bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
        floor = { x = 9, y = 10, z = 0 } } }
clock = 30000
assert(Bedridden.onSpawn(group, actor))
routeShouldFailPrimary = true
for _ = 1, 2 do
    assert(not Bedridden.update(actor, player, nil,
        { mode = "bedridden_arthur" }, group))
end
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(group.oddball.floorFallback == true)
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.square == floor and actor.dead ~= true)
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.dead and actor.square == floor)
assert(retiredReasons[3] == "died_alone")

-- A failed native lie can leave the physical body in a wall/outside square.
-- Only then may Arthur use the bridge's checked recovery transaction; this
-- restores the clear spawn post so his floor ending remains reachable.
actor = { id = "arthur", x = 11, y = 9, z = 0,
    square = invalidBedEntry, inv = { items = {} }, onBed = false }
group.oddball = { id = "bedridden_arthur_hale", stage = "left_alone",
    leftAt = 10000, lieFallback = true, lieRecovery = true, site = {
        spawn = { x = 10, y = 10, z = 0 },
        bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
        floor = { x = 9, y = 10, z = 0 } } }
clock = 50000
player.x, player.square = 30, outside
assert(Bedridden.onSpawn(group, actor))
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_recovered_failed_bed_entry"
    and actor.square == floor and group.oddball.lieCorrected == true,
    "confirmed failed lie recovers to a clear bedroom post")
routeShouldFailPrimary = false
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.dead and retiredReasons[#retiredReasons] == "died_alone",
    "recovered Arthur still completes his floor ending")

-- Native Get Up can instead carry him one tile through the north wall. The
-- same one-time verified recovery takes him to the selected bedroom floor.
actor = { id = "arthur", x = 11.5, y = 9.5, z = 0,
    square = invalidBedEntry, inv = { items = {} }, onBed = false,
    collidable = true, movementOwner = "none" }
group.oddball = { id = "bedridden_arthur_hale", stage = "left_alone",
    leftAt = 10000, nativeBedExited = true, site = {
        spawn = { x = 10, y = 10, z = 0 },
        bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
        floor = { x = 9, y = 10, z = 0 } } }
clock = 50000
player.x, player.square = 30, outside
assert(Bedridden.onSpawn(group, actor))
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_stepped_clear_of_bed"
    and actor.square == deathFloor and group.oddball.nativeBedExited == nil,
    "native get-up displacement through wall receives checked floor recovery: "
        .. tostring(accepted) .. "/" .. tostring(reason) .. " at "
        .. tostring(actor.square and actor.square.x) .. ","
        .. tostring(actor.square and actor.square.y))
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(actor.dead and retiredReasons[#retiredReasons] == "died_alone")

-- The native Rest record is not sufficient evidence on its own: another
-- furniture action can leave him seated in a nearby chair.
local chair = { kind = "chair" }
actor = { id = "arthur", x = 10, y = 10, z = 0,
    square = floor, inv = { items = {} }, onBed = false,
    seated = true, seatObject = chair, bedStatus = "entered" }
group.oddball = { id = "bedridden_arthur_hale", site = {
    spawn = { x = 10, y = 10, z = 0 },
    bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
    floor = { x = 9, y = 10, z = 0 } } }
clock = 40000
assert(Bedridden.onSpawn(group, actor))
local accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_recovering_from_lie_entry"
    and actor.seated == false and actor.seatObject == nil,
    "a chair does not satisfy Arthur's native bed entry")

-- Arthur uses the stock actions from a clear head-side entry post.
local lieCalls, queueResets, chosenFoot = 0, 0, nil
local nativeWaitCalls, nativeBeforeCalls, nativeWhileCalls = 0, 0, 0
local lieQueue = { queue = {}, current = nil }
function lieQueue:resetQueue()
    queueResets = queueResets + 1
    self.queue, self.current = {}, nil
end
ISTimedActionQueue = { getTimedActionQueue = function(value)
    assert(value == actor)
    return lieQueue
end }
function ISTimedActionQueue.add(action)
    lieQueue.queue[#lieQueue.queue + 1] = action
    lieQueue.current = lieQueue.current or action
end
local nativeWaitToStart = function(self)
    nativeWaitCalls = nativeWaitCalls + 1
    self:setBeforeSitDirection()
    return self.nativeWait == true
end
local nativeBefore = function()
    nativeBeforeCalls = nativeBeforeCalls + 1
end
local nativeWhile = function()
    nativeWhileCalls = nativeWhileCalls + 1
end
ISGetOnBedAction = { new = function(_, value, chosenBed)
    assert(value == actor and chosenBed == bedFoot)
    lieCalls = lieCalls + 1
    return { character = value, bed = chosenBed,
        waitToStart = nativeWaitToStart,
        setBeforeSitDirection = nativeBefore,
        setWhileSittingDirection = nativeWhile }
end }
ISPathFindAction = { pathToLocationF = function(_, value, x, y, z)
    assert(value == actor)
    chosenFoot = { x, y, z }
    return { character = value, goal = chosenFoot,
        forceCancel = function() return true end }
end }
ISWorldObjectContextMenu = { onGetOnBed = function()
    error("the context menu can choose an unsafe side entry")
end }
SeatingManager = { getInstance = function() return {} end }
local oldCall = SC.GameplayUtil.call
SC.GameplayUtil.call = function(value, method, ...)
    if method == "getFacingDirection" then return "W", true end
    return oldCall(value, method, ...)
end
local function resetForLie()
    actor = { id = "arthur", x = 10, y = 10, z = 0,
        square = floor, inv = { items = {} }, onBed = false }
    group.oddball = { id = "bedridden_arthur_hale", site = {
        spawn = { x = 10, y = 10, z = 0 },
        bed = { x = 11, y = 10, z = 0, objectIndex = 0 },
        floor = { x = 9, y = 10, z = 0 } } }
    lieQueue.queue, lieQueue.current = {}, nil
    chosenFoot = nil
    assert(Bedridden.onSpawn(group, actor))
end
clock = 50000
resetForLie()
local restBeforeLie = restCalls
local entryBed, entryPoint, entryKind =
    SC.Oddballs.nativeBedFootEntry(bed)
assert(entryBed == bedFoot and entryKind == "entry"
    and entryPoint.x == 12.5
    and math.abs(entryPoint.y - 9.7) < 0.001
    and entryPoint.facing == "W"
    and entryPoint.entryKind == "HeadRight",
    "shared resolver normalizes the bed to its stock head-side entry")
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_getting_on_bed"
    and lieCalls == 1 and group.oddball.lieApproach == "HeadRight"
    and chosenFoot and chosenFoot[1] == 12.5
    and math.abs(chosenFoot[2] - 9.7) < 0.001
    and lieQueue.queue[2].bed == bedFoot,
    "native get-on-bed action takes the clear stock head-side post")
local firstBedAction = lieQueue.queue[2]
assert(firstBedAction.waitToStart ~= nativeWaitToStart
    and firstBedAction.setBeforeSitDirection == nativeBefore
    and firstBedAction.setWhileSittingDirection == nativeWhile,
    "exact-entry guard keeps stock directional callbacks")
assert(firstBedAction:waitToStart() and nativeWaitCalls == 0,
    "bed action waits without turning until actor reaches exact entry")
actor.x, actor.y = 12.5, 9.7
assert(not firstBedAction:waitToStart()
    and nativeWaitCalls == 1 and nativeBeforeCalls == 1,
    "stock wait and facing resume at the selected entry point")
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_lie_pose"
    and lieCalls == 1 and restCalls == restBeforeLie,
    "native get-on-bed action is not queued twice")
actor.onBed = true
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_lie_pose",
    "isOnBed before OnBedStarted is still an entry animation")
actor.onBedStarted = true
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_lie_pose",
    "native bed flags alone do not prove the body reached the mattress")
actor.x, actor.y, actor.square = 11, 10, bedTile
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_lying_on_bed"
    and group.oddball.lieFallback ~= true
    and actor.variables.OnBedAnim == "Asleep"
    and restCalls == restBeforeLie,
    "only settled native OnBedStarted accepts the lying pose")

-- Native flags can arrive before the actor reaches the mattress. Wait for the
-- stock action or its timeout; never reposition the sprite while it is lying.
clock = 51000
resetForLie()
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
actor.onBed, actor.onBedStarted, actor.movementOwner = true, true, "seating"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_lie_pose")
clock = 52001
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_lie_pose"
    and actor.x == 10 and actor.y == 10
    and actor.nextX == nil and actor.nextY == nil
    and group.oddball.liePlacementAttempted ~= true,
    "an off-mattress native pose is never manually repositioned")

-- Every stock entry post must be blocked before the bed is rejected.
local originalClear = SC.GameplayUtil.isClearActorSpawnSquare
SC.GameplayUtil.isClearActorSpawnSquare = function(square)
    return square == deathFloor
end
clock = 55000
resetForLie()
local callsBeforeBlocked = lieCalls
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_retrying_native_bed_entry"
    and group.oddball.lieFailureReason == "bed_entry_blocked"
    and group.oddball.lieApproach == "native"
    and lieCalls == callsBeforeBlocked and chosenFoot == nil
    and #lieQueue.queue == 0,
    "no native bed action queues when every entry post is blocked")
SC.GameplayUtil.isClearActorSpawnSquare = originalClear

-- One timed-out native entry may retry from the same clear head-side post.
clock = 60000
resetForLie()
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
clock = 105001
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_waiting_to_retry_bed"
    and queueResets == 1
    and restCalls == restBeforeLie,
    "unsettled Get On Bed action times out without stacking a second action")
clock = 108000
assert(Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group))
assert(lieCalls >= 2 and group.oddball.lieApproach == "HeadRight"
    and chosenFoot and chosenFoot[1] == 12.5
    and math.abs(chosenFoot[2] - 9.7) < 0.001
    and restCalls == restBeforeLie,
    "Arthur's bounded retry still uses the stock head-side post")
clock = 153001
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(not accepted and reason == "arthur_sleep_entry_failed"
    and group.oddball.lieFailed == true and restCalls == restBeforeLie,
    "failed native lie is never treated as successful furniture Rest")

-- The saved attempt count survives reload; the final attempt still targets
-- the selected native entry rather than furniture Rest.
clock = 160000
resetForLie()
group.oddball.lieAttempts = 1
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_getting_on_bed"
    and group.oddball.lieAttempts == 2
    and group.oddball.lieApproach == "HeadRight"
    and restCalls == restBeforeLie,
    "loaded Arthur resumes bounded native entry without furniture Rest")

-- An entry whose tile metadata differs from SeatingManager still leaves the
-- game's Get On Bed direction callbacks unchanged. The native animation
-- chooses the actual clip at the selected head-side post.
local originalResolver = SC.Oddballs.nativeBedFootEntry
SC.Oddballs.nativeBedFootEntry = function(selected, occupant)
    local entryObject, point, why = originalResolver(selected, occupant)
    if not point then return entryObject, point, why end
    return entryObject, { x = 12.5, y = 9.7, z = 0,
        facing = "S", entryKind = "HeadLeft" }, why
end
clock = 161000
resetForLie()
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
local metadataAction = lieQueue.queue[2]
assert(accepted and reason == "arthur_getting_on_bed"
    and chosenFoot[1] == 12.5 and chosenFoot[2] == 9.7
    and group.oddball.lieApproach == "HeadLeft"
    and metadataAction.setBeforeSitDirection == nativeBefore
    and metadataAction.setWhileSittingDirection == nativeWhile,
    "bed action retains stock callbacks despite differing tile metadata")
local beforeWait, beforeTurn = nativeWaitCalls, nativeBeforeCalls
assert(metadataAction:waitToStart() and nativeWaitCalls == beforeWait,
    "stock action does not turn before reaching the exact entry")
actor.x, actor.y = 12.5, 9.7
assert(not metadataAction:waitToStart()
    and nativeWaitCalls == beforeWait + 1
    and nativeBeforeCalls == beforeTurn + 1,
    "stock wait chooses direction after the actor arrives")
local beforeWhile = nativeWhileCalls
metadataAction:setWhileSittingDirection()
assert(nativeWhileCalls == beforeWhile + 1,
    "stock start remains responsible for the on-bed facing")
-- On a four-sprite S-facing bed, the native foot action owns the animation.
-- The bridge moves only the settled anchor onto its matching pillow tile.
local southCall = SC.GameplayUtil.call
local southRightFootTile = tile(12, 11, room)
local southRightFootSprite = { kind = "south_right_foot_sprite" }
local southRightFoot = { kind = "south_right_foot",
    square = southRightFootTile }
local southProperties = {}
pillowFootTile.objects[1] = pillowFoot
southRightFootTile.objects[1] = southRightFoot
SC.GameplayUtil.call = function(value, method, ...)
    if value == southRightFoot and method == "getName" then
        return "Bed", true
    end
    if value == southRightFoot and method == "getSprite" then
        return southRightFootSprite, true
    end
    if value == southRightFootSprite and method == "getSpriteGrid" then
        return bedGrid, true
    end
    if value == bedGrid and method == "getSpriteGridPosX"
        and (...) == southRightFootSprite then return 1, true end
    if value == bedGrid and method == "getSpriteGridPosY"
        and (...) == southRightFootSprite then return 1, true end
    if value == bedGrid and method == "getWidth" then return 2, true end
    if value == bedGrid and method == "getHeight" then return 2, true end
    if method == "getProperties" and (value == bed or value == bedFoot
        or value == pillowFoot or value == southRightFoot) then
        return southProperties, true
    end
    if value == southProperties and method == "get" then
        return (...) == "Facing" and "S" or nil, true
    end
    return southCall(value, method, ...)
end
local previousBridge = SCBridge
local pillowShifts = 0
local renderLifts = {}
SCBridge = { shiftOnBedPoseTowardPillow = function(value, x, y, z)
    pillowShifts = pillowShifts + 1
    assert(value == actor and x == 11 and y == 10 and z == 0,
        "only Arthur's selected pillow lane is corrected")
    value.x, value.y, value.z = 11.6875, 10.8618, 0
    value.square = bedTile
    return true
end, setOnBedRenderLift = function(value, milliTiles)
    assert(value == actor and (milliTiles == 180 or milliTiles == 0),
        "Arthur alone owns the guarded bed render lift")
    renderLifts[#renderLifts + 1] = milliTiles
    return true
end }
SC.Oddballs.nativeBedFootEntry = function()
    return bedFoot, { x = 12.5, y = 9.7, z = 0,
        facing = "S", entryKind = "HeadRight",
        pillow = { x = 11, y = 10, z = 0 } }, "entry"
end
clock = 169000
resetForLie()
actor.x, actor.y, actor.square = 11.5, 10.5, bedTile
actor.onBed, actor.onBedStarted, actor.dir = true, true, "E"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_bed",
    "a south-facing double bed rejects a sideways east-facing pose")
resetForLie()
southRightFootTile.objects[1] = nil
actor.x, actor.y, actor.square = 11.5, 10.5, bedTile
actor.onBed, actor.onBedStarted, actor.dir = true, true, "S"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_entering_bed",
    "an incomplete double bed cannot validate the full body footprint")
southRightFootTile.objects[1] = southRightFoot
clock = 170000
resetForLie()
actor.dir = "S"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_getting_on_bed",
    "lengthwise bed action is queued before any anchor adjustment")
actor.x, actor.y, actor.square = 11.1875, 11.3618,
    pillowFootTile
actor.onBed, actor.onBedStarted = true, true
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_lying_on_bed"
    and pillowShifts == 1 and actor.square == bedTile
    and actor.variables.OnBedAnim == "Asleep"
    and renderLifts[#renderLifts] == 180,
    "the completed native entry aligns before the first sleeping frame")
clock = 171100
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_bedridden"
    and pillowShifts == 1 and actor.square == bedTile
    and actor.variables.OnBedAnim == "Asleep"
    and actor.onBed == true and #renderLifts == 1,
    "half-tile aligned native pose stays on the pillow tile")
group.oddball.stage = "left_alone"
group.oddball.leftAt = clock - 6000
clock = clock + 6100
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_leaving_bed"
    and renderLifts[#renderLifts] == 0,
    "native bed exit clears the render-only lift")
SCBridge.shiftOnBedPoseTowardPillow = function()
    pillowShifts = pillowShifts + 1
    return false
end
clock = 180000
resetForLie()
actor.dir = "S"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
actor.x, actor.y, actor.square = 11.1875, 11.3618,
    pillowFootTile
actor.onBed, actor.onBedStarted = true, true
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_settling_on_bed"
    and group.oddball.nativeBedPoseStarted ~= true
    and pillowShifts == 2,
    "an early bridge failure waits for a settled fallback attempt")
clock = 181100
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_recovering_from_lie_entry"
    and group.oddball.lieFailureReason
        == "native_pillow_alignment_failed",
    "failed alignment gives bounded native entry recovery")
clock = 190000
resetForLie()
actor.dir = "S"
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
actor.x, actor.y, actor.square = 10.53, 10.84, floor
actor.onBed, actor.onBedStarted = true, true
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_settling_on_bed",
    "native motion is allowed to settle before judging an off-bed anchor")
local beforeUnsupported = pillowShifts
clock = 191100
accepted, reason = Bedridden.update(actor, player, nil,
    { mode = "bedridden_arthur" }, group)
assert(accepted and reason == "arthur_recovering_from_lie_entry"
    and group.oddball.lieFailureReason
        == "native_pillow_alignment_unsupported"
    and group.oddball.lieFailed == true
    and pillowShifts == beforeUnsupported,
    "stable lateral drift fails once without an unsafe bridge move")
SCBridge = previousBridge
SC.Oddballs.nativeBedFootEntry = originalResolver
SC.GameplayUtil.call = oldCall

local function verifyCardinalBedLengths()
    local normalCall = SC.GameplayUtil.call
    local unexpectedLifts = 0
    SCBridge = { setOnBedRenderLift = function(_, milliTiles)
        if milliTiles == 180 then unexpectedLifts = unexpectedLifts + 1 end
        return milliTiles == 0
    end }
    SC.GameplayUtil.call = function(value, method, ...)
        if method == "getName" and value and value.sprite then
            return "Bed", true
        end
        if method == "getSprite" and value and value.sprite then
            return value.sprite, true
        end
        if method == "getSpriteGrid" and value and value.grid then
            return value.grid, true
        end
        if method == "getSpriteGridPosX" and value and value.testGrid then
            return (...).gx, true
        end
        if method == "getSpriteGridPosY" and value and value.testGrid then
            return (...).gy, true
        end
        if method == "getWidth" and value and value.testGrid then
            return value.width, true
        end
        if method == "getHeight" and value and value.testGrid then
            return value.height, true
        end
        return normalCall(value, method, ...)
    end
    local steps = { N = { 0, -1 }, S = { 0, 1 },
        E = { 1, 0 }, W = { -1, 0 } }
    local lastGrid
    for index, direction in ipairs({ "N", "S", "E", "W" }) do
        local x, y = 40 + index * 4, 20
        local step = steps[direction]
        local anchor = tile(x, y, room)
        local partner = tile(x + step[1], y + step[2], room)
        local grid = { testGrid = true,
            width = step[1] ~= 0 and 2 or 1,
            height = step[2] ~= 0 and 2 or 1 }
        lastGrid = grid
        local firstSprite = { grid = grid, gx = step[1] < 0 and 1 or 0,
            gy = step[2] < 0 and 1 or 0 }
        local secondSprite = { grid = grid,
            gx = firstSprite.gx + step[1],
            gy = firstSprite.gy + step[2] }
        local first = { sprite = firstSprite, square = anchor }
        local second = { sprite = secondSprite, square = partner }
        anchor.objects[1], partner.objects[1] = first, second
        actor = { id = "arthur", x = x + 0.5, y = y + 0.5, z = 0,
            square = anchor, dir = direction, onBed = true,
            onBedStarted = true, inv = { items = {} } }
        group.oddball = { id = "bedridden_arthur_hale", site = {
            spawn = { x = x, y = y, z = 0 },
            bed = { x = x, y = y, z = 0, objectIndex = 0 },
            floor = { x = x, y = y, z = 0 } },
            bedPoseNeedsLift = false }
        local handled, reason = Bedridden.update(actor, player, nil,
            { mode = "bedridden_arthur" }, group)
        assert(handled and reason == "arthur_bedridden"
            and actor.variables.OnBedAnim == "Asleep"
            and group.oddball.nativeBedPoseStarted == true
            and unexpectedLifts == 0,
            direction .. " bed accepts stock lying pose without S-only lift")
        handled, reason = Bedridden.update(actor, player, nil,
            { mode = "bedridden_arthur" }, group)
        assert(handled and reason == "arthur_bedridden",
            direction .. " bed survives another decision beat")
    end
    lastGrid.width = nil
    local handled, reason = Bedridden.update(actor, player, nil,
        { mode = "bedridden_arthur" }, group)
    assert(handled and reason == "arthur_entering_bed",
        "a modded bed without grid dimensions fails closed")
    lastGrid.width = 2
    -- A native flag on one bed tile cannot justify a pose when the body
    -- points off the shared grid. Let the bounded entry timeout recover it.
    actor.dir = "N"
    handled, reason = Bedridden.update(actor, player, nil,
        { mode = "bedridden_arthur" }, group)
    assert(handled and reason == "arthur_entering_bed"
        and group.oddball.nativeBedPoseStarted == true,
        "off-grid bed pose is not accepted as a fresh settled pose")
    clock = clock + 50000
    handled, reason = Bedridden.update(actor, player, nil,
        { mode = "bedridden_arthur" }, group)
    assert(handled and reason == "arthur_recovering_from_lie_entry",
        "off-grid bed pose has bounded recovery")
    SC.GameplayUtil.call = normalCall
end
verifyCardinalBedLengths()
print("Bedridden PASS: native bed entry, guarded pillow alignment, death")
