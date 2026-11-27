-- SPDX-License-Identifier: MIT

local SC = LivingFellows
local Factions, Oddballs, U = SC.Factions, SC.Oddballs, SC.GameplayUtil
local player = SC_TEST_PLAYER
local definition = assert(Oddballs.definition("evacuation"))
local joyPost = { x = 10, y = 10, z = 0 }
local brockPost = { x = 11, y = 10, z = 0 }
local party = { joyPost, brockPost }
local site = {
    kind = "resident", room = "storage", anchor = joyPost, spawn = joyPost,
    memberSpawns = party,
    house = {
        id = "evacuation-test-house", anchor = joyPost, interior = party, openings = {},
        bounds = { x1 = 9, y1 = 9, x2 = 12, y2 = 12, z = 0 },
    },
}

local records, nativeStarts = {}, {}
local joyLoaded, nativeRejected = true, false
local preparation, preparedCount, preparePlayer, preparingGroup = "failed", 0, nil, nil
local spawnFailures, retirements, legacyGuardCalls = 0, 0, 0
local failedWithReceipt = false
local lifecycleOwned, recovered, recoveryCalls, homeRecoveries, distanceChecks = false, false, 0, 0, 0
local pendingRestoreId

U.gridSquare = function(x, y, z)
    if y ~= 10 or z ~= 0 then return nil end
    if x == 10 and joyLoaded then return joyPost end
    if x == 11 then return brockPost end
end
U.position = function(object) return object and object.x, object and object.y, object and object.z end
U.isSafeSpawnSquare = function(square) return square ~= nil end
U.idOf = function(actor) return actor and actor.id end
U.canSee = function() return true end
U.distance = function() distanceChecks = distanceChecks + 1; return 200 end
U.inventory = function(actor) return actor.inventory end
U.inventoryItemsDeep = function(inventory) return inventory end
U.itemType = function(item) return item.kind end
U.addItem = function(inventory, kind)
    local item = { kind = kind }
    inventory[#inventory + 1] = item
    return item
end
SC.Registry.byId = function(id) return records[id] end
SC.Registry.isValidId = function(id) return type(id) == "string" and #id > 0 end
SC.Persistence.isPending = function(id) return id == pendingRestoreId end
SC.Config.testSet("oddballsEnabled", false)
SC.Config.testSet("factionsEnabled", false)

SC.Actor.beginSpawn = function(square, profile)
    local entry = { square = square, profile = profile,
        secured = preparingGroup and preparingGroup.oddball.sceneSecured == true }
    nativeStarts[#nativeStarts + 1] = entry
    if nativeRejected then return nil, "native_refused" end
    return entry, "spawn_pending"
end
SC.Actor.pollSpawn = function(ticket)
    local actor = { id = "evacuation-" .. ticket.profile.identity.forename, inventory = {} }
    function actor:setPrimaryHandItem(item) self.primary = item end
    function actor:getPrimaryHandItem() return self.primary end
    local record = { id = actor.id, actor = actor }
    assert(ticket.profile.initialize(actor, record))
    records[actor.id] = record
    return actor
end
SC.Actor.recover = function()
    homeRecoveries = homeRecoveries + 1
    return true
end

local function legacyGuard()
    legacyGuardCalls = legacyGuardCalls + 1
    return true
end
SC.OddballRoomGuard = { register = legacyGuard, pulse = legacyGuard,
    abort = legacyGuard, release = legacyGuard }
SC.OddballEvacuation = {
    storyRules = {
        prepareFirstSpawn = function(group, currentPlayer)
            preparedCount = preparedCount + 1
            preparePlayer = currentPlayer
            preparingGroup = group
            if preparation == "ready" then group.oddball.sceneSecured = true end
            if preparation == "missing_receipt" then return "ready" end
            return preparation, "prepare_" .. preparation
        end,
        ownsLifecycle = function() return lifecycleOwned end,
        recoverMember = function(group, record, currentPlayer)
            assert(group.oddball.id == "evacuation" and record.actor and currentPlayer == player)
            recoveryCalls = recoveryCalls + 1
            return recovered, recovered and "vehicle_recovered" or nil
        end,
    },
    onSpawn = function() return true end,
    onSpawnFailed = function(group)
        spawnFailures = spawnFailures + 1
        failedWithReceipt = group.oddball.sceneSecured == true
    end,
    onRetire = function() retirements = retirements + 1 end,
    menuOptions = function(_, _, sourceActor) return { sourceActor } end,
}

local function createGroup()
    return assert(Factions.createOddballGroup(site, definition, true))
end

local function pulse(current)
    SC_TEST_CLOCK = current
    Factions.pulse(player, current)
end

local group = createGroup()
assert(Factions._beginNextSpawnForTests(player) == false and #nativeStarts == 0
    and spawnFailures == 1 and Factions.group(group.id) == nil,
    "failed scene preparation cancels the group before native spawn")

preparation = "missing_receipt"
group = createGroup()
assert(Factions._beginNextSpawnForTests(player) == false and #nativeStarts == 0
    and spawnFailures == 2 and Factions.group(group.id) == nil,
    "ready without a durable receipt also cancels the untouched scene")

preparation, nativeRejected = "ready", true
group = createGroup()
assert(Factions._beginNextSpawnForTests(player) == false and #nativeStarts == 1
    and spawnFailures == 3 and failedWithReceipt and Factions.group(group.id) == nil,
    "rejected native injection calls scene cleanup and frees the unique encounter")

preparation, nativeRejected = "pending", false
group = createGroup()
local before = preparedCount
joyLoaded = false
pulse(1000)
pulse(2000)
assert(preparedCount == before and #nativeStarts == 1
    and Factions.group(group.id) == group and group.members[1].spawnQueued == true,
    "an unloaded first post defers both actors without calling scene preparation")

joyLoaded = true
pulse(3000)
pulse(4000)
assert(preparedCount == before + 1 and preparePlayer == player and #nativeStarts == 1
    and group.oddball.spawned == false and group.oddball.sceneSecured == nil,
    "the real player reaches pending preparation before either native injection")

preparation = "ready"
pulse(5000)
assert(#nativeStarts == 2 and nativeStarts[2].square == joyPost
    and nativeStarts[2].profile.identity.forename == "Joy" and nativeStarts[2].secured,
    "the first ready spawn is Joy at her own fresh post after the scene receipt")
pulse(6000)
pulse(7000)
pulse(8000)
assert(#nativeStarts == 3 and nativeStarts[3].square == brockPost
    and nativeStarts[3].profile.identity.forename == "Brock" and preparedCount == before + 2,
    "Brock uses his own authored post without replaying preparation")
local joy, brock = records[group.members[1].actorId], records[group.members[2].actorId]
assert(joy.actor.primary.kind == "Base.Crowbar" and #brock.actor.inventory == 0,
    "the generic kit belongs to Joy")
assert(Oddballs.menuOptions(group, player, joy.actor)[1] == joy.actor,
    "the faction story forwards the selected actor to its conversation")

lifecycleOwned = true
distanceChecks = 0
pulse(9000)
assert(distanceChecks == 0, "an active authored journey skips house-based faction lifecycle")
local handled, reason = Factions.handleMissingSquare(joy, player)
assert(handled and reason == "authored_recovery_deferred" and recoveryCalls == 1 and homeRecoveries == 0,
    "an unavailable vehicle recovery defers without home relocation")
recovered = true
handled, reason = Factions.handleMissingSquare(joy, player)
assert(handled and reason == "vehicle_recovered" and recoveryCalls == 2 and homeRecoveries == 0,
    "a successful story recovery forwards its verified result")
lifecycleOwned = false
handled, reason = Factions.handleMissingSquare(joy, player)
assert(handled and reason == "recovered_at_territory" and homeRecoveries == 1,
    "ordinary resident square recovery remains available outside the journey")

assert(Factions.retireOddballMembers(group) == false and group.lifecycle ~= "destroyed",
    "retirement waits for active native actors to be removed")
records[joy.id], records[brock.id] = nil, nil
pendingRestoreId = joy.id
assert(Factions.retireOddballMembers(group) == false and group.lifecycle ~= "destroyed",
    "retirement waits for any in-flight actor restoration")
pendingRestoreId = nil
assert(Factions.retireOddballMembers(group) == true and group.lifecycle == "destroyed"
    and group.oddball.stage == "evacuated" and Factions.presentCount(group) == 0
    and retirements == 1 and legacyGuardCalls == 0,
    "retirement closes once and the encounter never enters the legacy zombie room guard")
assert(Factions.retireOddballMembers(group) == true and retirements == 1,
    "retirement replay does not repeat cleanup")

local document = assert(Factions.export())
assert(Factions.restore(document))
local saved = assert(Factions.group(group.id))
assert(saved.lifecycle == "destroyed" and #saved.members == 2
    and saved.members[1].alive == true and saved.members[2].alive == true
    and saved.members[1].actorId == nil and saved.members[2].actorId == nil
    and Factions.presentCount(saved) == 0, "retired members survive restore without becoming deaths or respawning")
