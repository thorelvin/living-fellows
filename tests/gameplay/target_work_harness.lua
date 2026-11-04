-- SPDX-License-Identifier: MIT
-- Distinct subject regressions retained from the former gameplay monolith.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog, squareKey = f.makeSquare, f.squares, f.movementLog, f.squareKey
local function decisionAfterDue(testActor, testPlayer, runtime, delay)
    SurvivorCompanion.Decision.update(testActor, testPlayer, runtime)
    f.clock = f.clock + (delay or 201)
    return SurvivorCompanion.Decision.update(testActor, testPlayer, runtime)
end

local function worldObjectIdentityFixture(value)
    value.modData = value.modData or {}
    function value:getModData() return self.modData end
    function value:transmitModData() self.modDataTransmitted = true end
    return value
end


function SurvivorCompanion.__testDoorTerminalOrders()
    local testPlayer = actor("door-test-player", 6, 7,
        { className = "IsoPlayer", recruited = false })
    testPlayer.modData.SC_Recruited = false
    local savedRequest = SurvivorCompanion.Navigation.request
    SurvivorCompanion.Navigation.request = function()
        return true, "door_test_approaching"
    end
    local function doorAt(targetSquare, opened, locked)
        local door = { square = targetSquare, open = opened == true, locked = locked == true }
        function door:getSquare() return self.square end
        function door:getX() return self.square.x + 0.5 end
        function door:getY() return self.square.y + 0.5 end
        function door:getZ() return self.square.z end
        function door:IsOpen() return self.open end
        function door:isLocked() return self.locked end
        function door:ToggleDoor()
            if self.locked then return false end
            self.open = not self.open
        end
        return door
    end
    local safe = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } }
    local function arriveAndPerform(subject, door)
        subject.square = door.square
        return SurvivorCompanion.Decision._doTacticalForTests(
            subject, testPlayer, { snapshot = safe },
            SurvivorCompanion.Commands.peek(subject), safe, {})
    end

    local follower = actor("sc-door-return-follow", 7, 7, {})
    local farDoor = doorAt(cell:getGridSquare(11, 7, 0), false, false)
    registry[follower.id] = follower
    check(SurvivorCompanion.Commands.issue(follower.id, "open_door",
            { object = farDoor }, testPlayer)
            and SurvivorCompanion.Commands.peek(follower).order == "interact"
            and SurvivorCompanion.Commands.peek(follower).returnOrder == "follow",
        "a distant door command records the stable return order")
    local opened, openStatus = arriveAndPerform(follower, farDoor)
    check(opened and openStatus == "done" and farDoor.open
            and SurvivorCompanion.Commands.peek(follower).order == "follow"
            and SurvivorCompanion.Commands.peek(follower).pendingInteraction == nil,
        "verified distant door completion resumes Follow")

    local closeAccepted, closeStatus = SurvivorCompanion.Commands.issue(
        follower.id, "close_door", { object = farDoor }, testPlayer)
    check(closeAccepted and closeStatus == "done" and not farDoor.open
            and SurvivorCompanion.Commands.peek(follower).order == "follow",
        "the adjacent door variant remains a one-shot action without changing order")

    follower.square = cell:getGridSquare(7, 7, 0)
    farDoor.open = true
    check(SurvivorCompanion.Commands.issue(follower.id, "open_door",
        { object = farDoor }, testPlayer),
        "an already-open distant door still stages an approach")
    local alreadyAccepted, alreadyStatus = arriveAndPerform(follower, farDoor)
    check(alreadyAccepted and alreadyStatus == "already_set"
            and SurvivorCompanion.Commands.peek(follower).order == "follow",
        "already-correct door state terminates and resumes Follow")

    follower.square = cell:getGridSquare(7, 7, 0)
    farDoor.open, farDoor.locked = false, true
    check(SurvivorCompanion.Commands.issue(follower.id, "open_door",
        { object = farDoor }, testPlayer),
        "a distant locked door can be approached before its lock is verified")
    local lockedAccepted, lockedStatus = arriveAndPerform(follower, farDoor)
    check(not lockedAccepted and lockedStatus == "locked_door"
            and SurvivorCompanion.Commands.peek(follower).order == "follow"
            and SurvivorCompanion.Commands.peek(follower).pendingInteraction == nil,
        "a locked door ends the one-shot order without stranding the follower")

    follower.square = cell:getGridSquare(7, 7, 0)
    farDoor.locked = false
    check(SurvivorCompanion.Commands.issue(follower.id, "open_door",
        { object = farDoor }, testPlayer),
        "removed-door fixture stages an approach")
    farDoor.square = nil
    local removedAccepted, removedStatus = SurvivorCompanion.Decision._doTacticalForTests(
        follower, testPlayer, { snapshot = safe },
        SurvivorCompanion.Commands.peek(follower), safe, {})
    check(not removedAccepted and removedStatus == "interaction_target_removed"
            and SurvivorCompanion.Commands.peek(follower).order == "follow",
        "a removed door terminates the one-shot order with a bounded failure")

    local interruptDoor = doorAt(cell:getGridSquare(11, 7, 0), false, false)
    check(SurvivorCompanion.Commands.issue(follower.id, "open_door",
            { object = interruptDoor }, testPlayer)
            and SurvivorCompanion.Commands.issue(follower.id, "stay", nil, testPlayer)
            and SurvivorCompanion.Commands.peek(follower).order == "stay"
            and SurvivorCompanion.Commands.peek(follower).pendingInteraction == nil
            and SurvivorCompanion.Commands.peek(follower).returnOrder == nil,
        "a new player order cleanly interrupts a pending door interaction")
    SurvivorCompanion.Navigation.request = savedRequest
    SurvivorCompanion.Navigation.reset(follower)
    SurvivorCompanion.Commands.reset(follower)
    registry[follower.id] = nil
end
SurvivorCompanion.__testDoorTerminalOrders()
SurvivorCompanion.__testDoorTerminalOrders = nil

function SurvivorCompanion.__testRoomCoverageClaims()
    local subject = actor("sc-room-coverage-claim", 6, 6, {})
    local room = { name = "coverage-room" }
    subject.square.room = room
    local savedSay = SurvivorCompanion.Dialogue.say
    local spoken
    SurvivorCompanion.Dialogue.say = function(_, topic) spoken = topic return true end
    local complete = {
        time = f.clock, origin = { square = subject.square }, threats = {},
        heardThreatCount = 0, scanComplete = true,
        scanDiscoveryComplete = true, scanVisualComplete = true,
    }
    SurvivorCompanion.Decision._reportRoomCheckForTests(subject, subject.square, complete)
    check(spoken == "tactical.room_clear",
        "fresh complete discovery and LOS at the actor's room may report Room clear")
    local cases = {
        { field = "scanDiscoveryComplete", value = false },
        { field = "scanVisualComplete", value = false },
        { field = "time", value = f.clock - 5000 },
        { field = "origin", value = { square = cell:getGridSquare(5, 6, 0) } },
    }
    for _, case in ipairs(cases) do
        local snapshot = SurvivorCompanion.GameplayUtil.copyShallow(complete)
        snapshot[case.field] = case.value
        spoken = nil
        SurvivorCompanion.Decision._reportRoomCheckForTests(subject, subject.square, snapshot)
        check(spoken == "tactical.room_uncertain",
            "unfinished, deferred, stale, or displaced coverage cannot claim Room clear")
    end
    local contact = zombie(6, 6, {})
    contact.square.room = room
    local contactSnapshot = SurvivorCompanion.GameplayUtil.copyShallow(complete)
    contactSnapshot.scanDiscoveryComplete = false
    contactSnapshot.threats = { { actor = contact, square = contact.square,
        visible = true, obstructed = false } }
    spoken = nil
    SurvivorCompanion.Decision._reportRoomCheckForTests(
        subject, subject.square, contactSnapshot)
    check(spoken == "tactical.room_one",
        "an observed contact is still reported while negative room coverage remains incomplete")
    SurvivorCompanion.Dialogue.say = savedSay
end
SurvivorCompanion.__testRoomCoverageClaims()
SurvivorCompanion.__testRoomCoverageClaims = nil

function SurvivorCompanion.__testDestructiveTargetWork()
local removeActor = actor("sc-remove-work", -8, -4, {})
registry[removeActor.id] = removeActor
local removeBarricade = {
    planks = 2,
    square = removeActor.square,
    objectIndex = #removeActor.square.objects,
}
worldObjectIdentityFixture(removeBarricade)
local barricade = { getNumPlanks = function() return removeBarricade.planks end }
function removeBarricade:getSquare() return self.square end
function removeBarricade:getX() return self.square.x + 0.5 end
function removeBarricade:getY() return self.square.y + 0.5 end
function removeBarricade:getZ() return self.square.z end
function removeBarricade:getObjectIndex() return self.objectIndex end
function removeBarricade:isBarricaded() return self.planks > 0 end
function removeBarricade:getBarricadeForCharacter() return self.planks > 0 and barricade or nil end
function removeBarricade:getBarricadeOnSameSquare() return self.planks > 0 and barricade or nil end
function removeBarricade:getBarricadeOnOppositeSquare() return nil end
function removeBarricade:getNorth() return true end
removeActor.square.objects[#removeActor.square.objects + 1] = removeBarricade
check(SurvivorCompanion.Commands.issue(removeActor.id, "remove_barricade", {
        object = removeBarricade, barricadeSide = "same",
    }, guardTestPlayer),
    "targeted remove-barricade command enters one-shot work")
check(SurvivorCompanion.Commands.peek(removeActor).workTarget.kind == "remove_barricade"
        and SurvivorCompanion.Commands.peek(removeActor).workTarget.barricadeSide == "same",
    "remove-barricade work retains the player-selected side")
check(decisionAfterDue(removeActor, guardTestPlayer, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and removeActor.lastIntent and removeActor.lastIntent.action == "remove_barricade",
    "remove-barricade decision starts the real destructive work intent")

local dismantleActor = actor("sc-dismantle-work", -9, -4, {})
registry[dismantleActor.id] = dismantleActor
local dismantleObject = {
    __class = "IsoThumpable",
    square = dismantleActor.square,
    objectIndex = #dismantleActor.square.objects,
}
worldObjectIdentityFixture(dismantleObject)
function dismantleObject:getSquare() return self.square end
function dismantleObject:getX() return self.square.x + 0.5 end
function dismantleObject:getY() return self.square.y + 0.5 end
function dismantleObject:getZ() return self.square.z end
function dismantleObject:getObjectIndex() return self.objectIndex end
function dismantleObject:isDismantable() return true end
dismantleActor.square.objects[#dismantleActor.square.objects + 1] = dismantleObject
check(SurvivorCompanion.Commands.issue(dismantleActor.id, "dismantle", {
        object = dismantleObject,
    }, guardTestPlayer),
    "targeted dismantle command enters one-shot work")
check(decisionAfterDue(dismantleActor, guardTestPlayer, {
    snapshot = { threats = {}, threatCount = 0, immediateCount = 0,
        escapeSquares = {}, allies = {}, player = { danger = 0 } },
}, 201) and dismantleActor.lastIntent and dismantleActor.lastIntent.action == "dismantle",
    "dismantle decision starts the real destructive work intent")

local swapActor = actor("sc-dismantle-identity-swap", -10, -4, {})
registry[swapActor.id] = swapActor
local originalObject = worldObjectIdentityFixture({
    __class = "IsoThumpable", square = swapActor.square,
    objectIndex = #swapActor.square.objects,
})
function originalObject:getSquare() return self.square end
function originalObject:getX() return self.square.x + 0.5 end
function originalObject:getY() return self.square.y + 0.5 end
function originalObject:getZ() return self.square.z end
function originalObject:getObjectIndex() return self.objectIndex end
function originalObject:isDismantable() return true end
swapActor.square.objects[#swapActor.square.objects + 1] = originalObject
check(SurvivorCompanion.Commands.issue(swapActor.id, "dismantle",
        { object = originalObject }, guardTestPlayer),
    "identity-swap fixture accepts an exact direct-work target")
local issuedWork = SurvivorCompanion.Commands.peek(swapActor).workTarget
local originalId = issuedWork and issuedWork.objectId
local replacement = worldObjectIdentityFixture({
    __class = "IsoThumpable", square = swapActor.square,
    objectIndex = originalObject.objectIndex,
})
function replacement:getSquare() return self.square end
function replacement:getX() return self.square.x + 0.5 end
function replacement:getY() return self.square.y + 0.5 end
function replacement:getZ() return self.square.z end
function replacement:getObjectIndex() return self.objectIndex end
function replacement:isDismantable() return true end
swapActor.square.objects[originalObject.objectIndex + 1] = replacement
originalObject.square, originalObject.objectIndex = nil, -1
local liveResolved, _, liveResolveReason =
    SurvivorCompanion.Decision._resolveWorkObjectForTests(
        SurvivorCompanion.Commands.peek(swapActor))
check(type(originalId) == "string" and liveResolved == nil
        and string.find(tostring(liveResolveReason), "work_target_changed", 1, true)
        and replacement.modData.LF_BaseObjectId == nil,
    "a live work reference never rebinds to a lookalike inserted at the old index")
SurvivorCompanion.Commands.reset(swapActor)
local restoredWork = SurvivorCompanion.Commands.peek(swapActor).workTarget
local restoredResolved, _, restoredReason =
    SurvivorCompanion.Decision._resolveWorkObjectForTests(
        SurvivorCompanion.Commands.peek(swapActor))
check(restoredWork and restoredWork.object == nil and restoredWork.objectId == originalId
        and restoredResolved == nil
        and string.find(tostring(restoredReason), "work_target_changed", 1, true)
        and replacement.modData.LF_BaseObjectId == nil,
    "save/load preserves exact work identity and conservatively rejects an index replacement")
registry[swapActor.id] = nil
registry[removeActor.id], registry[dismantleActor.id] = nil, nil
end
SurvivorCompanion.__testDestructiveTargetWork()
SurvivorCompanion.__testDestructiveTargetWork = nil

function SurvivorCompanion.__testExclusiveWorkReservation()
local reserveActorOne = actor("sc-build-reserve-one", -10, -7, { inventory = inventory(buildKit()) })
local reserveActorTwo = actor("sc-build-reserve-two", -11, -7, { inventory = inventory(buildKit()) })
registry[reserveActorOne.id] = reserveActorOne
registry[reserveActorTwo.id] = reserveActorTwo
local sharedBuildObject = {
    square = reserveActorOne.square,
    objectIndex = #reserveActorOne.square.objects,
}
worldObjectIdentityFixture(sharedBuildObject)
function sharedBuildObject:getSquare() return self.square end
function sharedBuildObject:getX() return self.square.x + 0.5 end
function sharedBuildObject:getY() return self.square.y + 0.5 end
function sharedBuildObject:getZ() return self.square.z end
function sharedBuildObject:getObjectIndex() return self.objectIndex end
function sharedBuildObject:isBarricadeAllowed() return true end
function sharedBuildObject:getBarricadeForCharacter() return nil end
reserveActorOne.square.objects[#reserveActorOne.square.objects + 1] = sharedBuildObject
check(SurvivorCompanion.Commands.issue(
        reserveActorOne.id, "barricade", { object = sharedBuildObject }, guardTestPlayer)
    and SurvivorCompanion.Commands.issue(
        reserveActorTwo.id, "barricade", { object = sharedBuildObject }, guardTestPlayer),
    "two companions may queue sequential work on one stable target")
local sharedWorkSnapshot = { threats = {}, threatCount = 0, immediateCount = 0,
    escapeSquares = {}, allies = {}, player = { danger = 0 } }
local sharedWorkRuntimeOne = { snapshot = sharedWorkSnapshot }
local sharedWorkRuntimeTwo = { snapshot = sharedWorkSnapshot }
SurvivorCompanion.GameplayUtil.actorState(reserveActorOne).timers = {
    perception = f.clock + 1000000,
}
SurvivorCompanion.GameplayUtil.actorState(reserveActorTwo).timers = {
    perception = f.clock + 1000000,
}
for _ = 1, 5 do
    f.clock = f.clock + 201
    SurvivorCompanion.Decision.update(reserveActorOne, guardTestPlayer, sharedWorkRuntimeOne)
    if reserveActorOne.lastIntent then break end
end
check(reserveActorOne.lastIntent and reserveActorOne.lastIntent.action == "barricade",
    "first companion acquires the exclusive target reservation: intent="
        .. tostring(SurvivorCompanion.Decision.peek(reserveActorOne).intent)
        .. " action=" .. tostring(reserveActorOne.lastIntent and reserveActorOne.lastIntent.action))
reserveActorTwo.lastIntent = nil
for _ = 1, 4 do
    f.clock = f.clock + 201
    SurvivorCompanion.Decision.update(reserveActorTwo, guardTestPlayer, sharedWorkRuntimeTwo)
    if SurvivorCompanion.Decision.peek(reserveActorTwo).intent == "work_reserved_by_companion" then break end
end
check(reserveActorTwo.lastIntent == nil
    and SurvivorCompanion.Decision.peek(reserveActorTwo).intent == "work_reserved_by_companion",
    "second companion waits without starting a conflicting native work action: intent="
        .. tostring(SurvivorCompanion.Decision.peek(reserveActorTwo).intent)
        .. " action=" .. tostring(reserveActorTwo.lastIntent and reserveActorTwo.lastIntent.action))
local cancelledBuildActions = 0
SurvivorCompanion.NativeActions = {
    cancelWork = function(targetActor)
        if targetActor == reserveActorOne then cancelledBuildActions = cancelledBuildActions + 1 end
        return true, "cancelled"
    end,
}
check(SurvivorCompanion.Commands.issue(reserveActorOne.id, "stay", nil, guardTestPlayer)
    and cancelledBuildActions == 1,
    "a new command cancels the previous native build action before role transition")
-- The first worker leaves the work side; the waiting worker reaches it.
for index = #reserveActorOne.square.moving, 1, -1 do
    if reserveActorOne.square.moving[index] == reserveActorOne then
        table.remove(reserveActorOne.square.moving, index)
    end
end
for index = #reserveActorTwo.square.moving, 1, -1 do
    if reserveActorTwo.square.moving[index] == reserveActorTwo then
        table.remove(reserveActorTwo.square.moving, index)
    end
end
reserveActorTwo.square = sharedBuildObject.square
reserveActorTwo.square.moving[#reserveActorTwo.square.moving + 1] = reserveActorTwo
reserveActorTwo.lastIntent = nil
for _ = 1, 5 do
    f.clock = f.clock + 201
    SurvivorCompanion.Decision.update(reserveActorTwo, guardTestPlayer, sharedWorkRuntimeTwo)
    if reserveActorTwo.lastIntent then break end
end
check(reserveActorTwo.lastIntent and reserveActorTwo.lastIntent.action == "barricade",
    "released work reservation lets the waiting companion continue")
SurvivorCompanion.Decision.reset(reserveActorOne)
SurvivorCompanion.Decision.reset(reserveActorTwo)
SurvivorCompanion.NativeActions = nil
end
SurvivorCompanion.__testExclusiveWorkReservation()
SurvivorCompanion.__testExclusiveWorkReservation = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
