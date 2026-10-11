-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local U = SC.GameplayUtil
local checks = 0
local function check(condition, message)
    checks = checks + 1
    assert(condition, "oddball foundation check " .. checks .. ": " .. message)
end

local actor = { id = "odd-red-actor", x = 10, y = 10, z = 0 }
local player = { x = 11, y = 10, z = 0 }
local record = { id = actor.id, actor = actor, recruited = false }
U.position = function(object)
    return object and object.x, object and object.y, object and object.z or 0
end
U.gridSquare = function(x, y, z)
    if ((x >= 9 and x <= 12 and y >= 9 and y <= 12)
        or (x == 70 and y == 10)) and z == 0 then
        return { x = x, y = y, z = z }
    end
end
U.isSafeSpawnSquare = function(square)
    return square ~= nil, square and "safe" or "unloaded"
end
U.distance = function(left, right)
    local ax, ay = U.position(left)
    local bx, by = U.position(right)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
U.canSee = function() return true end
U.idOf = function(value) return value and value.id end
U.text = function(_, fallback) return fallback end
U.say = function() return true end
U.isALifeNpc = function() return false end
U.isALifeHostileToParty = function() return false end
SC.Allegiance = { isHostile = function() return false end }
SC.Registry.byId = function(id) return id == actor.id and record or nil end
SC.Registry.isValidId = function(id) return type(id) == "string" and #id > 1 end
SC.Registry.living = function() return {} end
SC.Vehicle.storedCount = function() return 0 end
SC.Commands = {
    beginFactionTrial = function() return true end,
    completeFactionTrial = function()
        record.recruited = true
        return true
    end,
    returnFactionTrial = function() return true end,
    peek = function() return {} end,
}
SC.OddballRed = {
    canRecruit = function() return true end,
    zombiesIgnore = function() return true, "actor_gore_cloaked" end,
    pulseRecruited = function(group, joinedActor)
        check(group.oddball.id == "gut_cloaked_red" and joinedActor == actor,
            "joined actor keeps the authored oddball link")
        return true
    end,
}
SC.Config.testSet("factionRecruitmentEnabled", true)
SC.Config.testSet("factionTradeDistance", 6)

-- The bakery trio stands on free kitchen floor beside work surfaces. Modded
-- kitchens without recognizable counters still use safe separated floor posts.
do
    local originalGrid, originalObjects, originalInstanceOf =
        U.gridSquare, U.squareObjects, U.instanceOf
    local kitchen = { getName = function() return "kitchen" end }
    local secondKitchen = { getName = function() return "kitchen" end }
    local tiles = {}
    local function tile(x, y, objects, z, room)
        local square = { x = x, y = y, z = z or 0,
            objects = objects or {},
            getRoom = function() return room or kitchen end }
        tiles[x .. ":" .. y .. ":" .. (z or 0)] = square
        return square
    end
    local function fixture(kind)
        return { getContainer = function()
            return { getType = function() return kind end }
        end }
    end
    tile(1, 1); tile(3, 1); tile(1, 3)
    tile(1, 0, { fixture("counter") })
    tile(4, 1, { fixture("stove") })
    tile(0, 3, { fixture("counter") })
    tile(5, 1, nil, 0, secondKitchen)
    tile(7, 1, nil, 0, secondKitchen)
    tile(5, 3, nil, 0, secondKitchen)
    tile(5, 0, { fixture("stove") }, 0, secondKitchen)
    tile(7, 0, { fixture("stove") }, 0, secondKitchen)
    tile(5, 4, { fixture("stove") }, 0, secondKitchen)
    tile(1, 1, nil, 1, kitchen)
    tile(3, 1, nil, 1, kitchen)
    tile(1, 0, { fixture("stove") }, 1, kitchen)
    tile(3, 0, { fixture("stove") }, 1, kitchen)
    U.gridSquare = function(x, y, z)
        return tiles[x .. ":" .. y .. ":" .. (z or 0)]
    end
    U.squareObjects = function(square, callback)
        for _, object in ipairs(square.objects) do callback(object) end
    end
    U.instanceOf = function() return false end
    local bakery = { interior = { { x = 5, y = 1, z = 0 },
        { x = 7, y = 1, z = 0 }, { x = 5, y = 3, z = 0 },
        { x = 1, y = 1, z = 1 }, { x = 3, y = 1, z = 1 },
        { x = 1, y = 1, z = 0 }, { x = 3, y = 1, z = 0 },
        { x = 1, y = 3, z = 0 } } }
    local posts = SC.Oddballs._auxiliaryKitchenPositionsForTests(
        bakery, player, true, { x = 1, y = 1, z = 0 })
    check(posts and #posts == 3 and posts[1].x == 3
            and posts[2].x == 1 and posts[3].y == 3
            and posts[1].z == 0 and posts[2].z == 0
            and posts[3].z == 0,
        "bakery work posts favor fixtures in only the origin kitchen/floor")
    for _, square in pairs(tiles) do square.objects = {} end
    posts = SC.Oddballs._auxiliaryKitchenPositionsForTests(
        bakery, player, true, { x = 1, y = 1, z = 0 })
    check(posts and #posts == 3 and posts[1].x == 1,
        "unfurnished kitchens keep the safe separated spawn fallback")
    local tooSmall = { interior = { { x = 1, y = 1, z = 0 },
        { x = 3, y = 1, z = 0 }, { x = 5, y = 1, z = 0 },
        { x = 1, y = 1, z = 1 } } }
    check(SC.Oddballs._auxiliaryKitchenPositionsForTests(
        tooSmall, player, true, { x = 1, y = 1, z = 0 }) == nil,
        "fallback refuses to borrow a third post from another kitchen or floor")
    U.gridSquare, U.squareObjects, U.instanceOf =
        originalGrid, originalObjects, originalInstanceOf
end

-- The native B42 opening objects expose north/west orientation, not an
-- instance getOppositeSquare(). Only an opening with a loaded outside square
-- may make a building eligible as an encounter site.
do
    local originalGridSquare, originalSquareOf = U.gridSquare, U.squareOf
    local originalInstanceof = instanceof
    local building = {}
    function building:getDef()
        return {
            getX = function() return 300 end, getY = function() return 300 end,
            getX2 = function() return 304 end, getY2 = function() return 304 end,
        }
    end
    local squares = {}
    local function key(x, y, z)
        return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    end
    local function square(x, y, inside)
        local value = { x = x, y = y, z = 0, objects = {},
            building = inside and building or nil }
        function value:getBuilding() return self.building end
        function value:getObjects() return self.objects end
        function value:getRoom() return nil end
        function value:isSeen() return false end
        function value:isBurntOut() return false end
        squares[key(x, y, 0)] = value
        return value
    end
    for x = 300, 304 do
        for y = 300, 304 do square(x, y, true) end
    end
    square(300, 299, false)
    square(299, 302, false)
    square(302, 299, false)
    local function opening(kind, north)
        local value = { kind = kind, north = north }
        function value:getNorth() return self.north end
        function value:isDoor() return self.kind == "IsoDoor" end
        function value:isWindowN()
            return self.kind == "IsoThumpable" and self.north == true
        end
        function value:isWindowW()
            return self.kind == "IsoThumpable" and self.north == false
        end
        return value
    end
    local exteriorDoor = opening("IsoDoor", true)
    local exteriorWindow = opening("IsoWindow", false)
    local interiorDoor = opening("IsoDoor", true)
    local missingOrientation = { kind = "IsoDoor" }
    local missingNeighbor = opening("IsoDoor", false)
    local thumpWindow = opening("IsoThumpable", false)
    local exteriorThumpWindow = opening("IsoThumpable", true)
    squares[key(300, 300, 0)].objects = { exteriorDoor }
    squares[key(300, 302, 0)].objects = { exteriorWindow }
    squares[key(300, 303, 0)].objects = { missingNeighbor }
    squares[key(301, 302, 0)].objects = { interiorDoor }
    squares[key(302, 302, 0)].objects = { missingOrientation, thumpWindow }
    squares[key(302, 300, 0)].objects = { exteriorThumpWindow }
    U.gridSquare = function(x, y, z) return squares[key(x, y, z)] end
    U.squareOf = function() return nil end
    instanceof = function(value, class) return value.kind == class end
    local houseDescriptor, houseReason = SC.Factions.oddballHouseAt(
        squares[key(300, 300, 0)], player, true)
    check(houseDescriptor ~= nil,
        "loaded exterior opening makes house eligible: " .. tostring(houseReason))
    local recognized = {}
    for _, entry in ipairs(houseDescriptor.openings) do
        recognized[entry.x .. ":" .. entry.y .. ":" .. entry.objectIndex] = true
    end
    check(recognized["300:300:0"] and recognized["300:302:0"]
            and recognized["302:300:0"]
            and not recognized["300:303:0"]
            and not recognized["301:302:0"]
            and not recognized["302:302:0"]
            and not recognized["302:302:1"],
        "only real loaded exterior north/west openings qualify")
    squares[key(300, 300, 0)].objects = {}
    squares[key(300, 302, 0)].objects = {}
    squares[key(302, 300, 0)].objects = {}
    local noExterior, noExteriorReason = SC.Factions.oddballHouseAt(
        squares[key(300, 300, 0)], player, true)
    check(noExterior == nil and noExteriorReason == "house_has_no_exterior_openings",
        "interior and unresolvable openings cannot qualify a building")
    U.gridSquare, U.squareOf, instanceof = originalGridSquare,
        originalSquareOf, originalInstanceof
end

local house = {
    id = "odd-house", anchor = { x = 10, y = 10, z = 0 },
    bounds = { x1 = 9, y1 = 9, x2 = 12, y2 = 12, z = 0 },
    interior = { { x = 10, y = 10, z = 0 } }, openings = {},
}
getCell = function()
    return { getVehicles = function()
        return {
            { x = 11, y = 10, z = 0,
                getScriptName = function() return "Base.Sedan" end },
            { x = 12, y = 10, z = 0,
                getScriptName = function() return "Base.PickUpTruck" end },
        }
    end }
end
local truck = SC.Oddballs._nearbyTruckForTests(house)
check(truck and truck.x == 12 and truck.y == 10,
    "only a real loaded nearby truck becomes a property marker")
local site = { kind = "roamer", room = "barn", house = house,
    anchor = { x = 10, y = 10, z = 0 },
    spawn = { x = 10, y = 10, z = 0 },
    coop = { x = 10, y = 10, z = 0, enclosed = true }, truck = truck }
local definition = SC.Oddballs.definition("gut_cloaked_red")
check(definition.identity.outfit == "Young"
    and definition.identity.gore == 1,
    "Red starts in civilian clothes with maximum blood coverage")
local group, reason = SC.Factions.createOddballGroup(site, definition)
check(group ~= nil, "fixed character creates one faction: " .. tostring(reason))
check(group.oddball.stage == "unmet" and #group.members == 1
    and #group.jobs == 0 and group.request == nil,
    "character group omits household chores and generic trade request")
check(SC.Factions.supports(group, "recruitment") == true,
    "the original oddball stories retain archetype recruitment")
check(group.oddball.site.coop.enclosed == true
    and group.oddball.site.truck.x == 12,
    "bounded property landmarks copy into durable story state")
check(SC.Factions.createOddballGroup(site, definition) == nil,
    "unique character cannot be created twice")
group.members[1].actorId = actor.id
group.members[1].spawnQueued = false
local nativeAffiliation = SC.Factions.affiliation
SC.Factions.affiliation = function(value)
    if value == actor and group.members[1].actorId == actor.id
        and group.members[1].away == nil and group.members[1].departed ~= true then
        return { group = group, member = group.members[1] }
    end
    return nativeAffiliation(value)
end
SC.Oddballs.spawned(group, actor)
-- Loading a save clears the initial spawn ticket and recreates the member map.
local beforeTravel = SC.Factions.export()
check(beforeTravel ~= nil and SC.Factions.restore(beforeTravel) == true,
    "the active roamer survives a save/load before moving")
group = SC.Factions.group(group.id)
local captures = 0
SC.Persistence.captureRecord = function()
    captures = captures + 1
    return { id = actor.id, identity = { forename = "Red" } }
end
SC.Actor.remove = function()
    record.actor = nil
    return true
end
SC.Config.testSet("factionHibernationDistance", 50)
SC.Config.testSet("factionWakeDistance", 45)
actor.x, player.x = 70, 72
U.canSee = function() return false end
SC.Factions.pulse(player, 1000)
check(captures == 0 and group.members[1].hibernated ~= true,
    "roamer stays present near player even when his barn is far away")
player.x = 190
SC.Factions.pulse(player, 2000)
check(captures == 1 and group.members[1].hibernated == true
    and group.oddball.site.wake.x == 70,
    "hidden roamer sleeps at his last actual road position")
player.x = 10
SC.Factions.pulse(player, 3000)
check(group.members[1].waking ~= true,
    "approaching the barn does not wake a distant road roamer")
player.x = 72
U.canSee = function() return true end
SC.Factions.pulse(player, 4000)
check(group.members[1].waking ~= true,
    "roamer does not respawn on a visible road tile")
U.canSee = function() return false end
SC.Factions.pulse(player, 5000)
check(group.members[1].waking == true,
    "hidden last road tile permits a safe wake")
record.actor = actor
group.members[1].hibernated = false
group.members[1].snapshot = nil
group.members[1].waking = false
group.members[1].spawnQueued = false
actor.x, player.x = 10, 11
U.canSee = function() return true end
check(SC.Oddballs.groupForActor(actor) == group,
    "active oddball actor resolves to its faction")
local ignored, ignoreReason = SC.Oddballs.isZombieIgnored(actor)
check(ignored and ignoreReason == "actor_gore_cloaked",
    "zombie targeting preserves the authored ignore reason")

do
    -- The vanilla setter is a no-op for companions, so the shelter belongs
    -- to the bridge and only counts once the native getter agrees.
    local oldBridge = rawget(_G, "SCBridge")
    local sheltered = { flag = false }
    function sheltered:setZombiesDontAttack() self.vanillaFlag = false end
    function sheltered:isZombiesDontAttack() return self.flag end
    SCBridge = nil
    local applied, why = SC.Oddballs.setZombieShelter(sheltered, true)
    check(applied == false and why == "bridge_unavailable"
        and sheltered.flag == false,
        "zombie shelter fails closed without the native bridge: " .. tostring(why))
    SCBridge = { setStoryZombieIgnored = function(target, enabled)
        target.flag = enabled
        return true
    end }
    applied, why = SC.Oddballs.setZombieShelter(sheltered, true)
    check(applied == true and sheltered.flag == true,
        "zombie shelter applies through the bridge: " .. tostring(why))
    applied, why = SC.Oddballs.setZombieShelter(sheltered, false)
    check(applied == true and sheltered.flag == false,
        "zombie shelter clears through the bridge: " .. tostring(why))
    SCBridge.setStoryZombieIgnored = function() return false end
    applied, why = SC.Oddballs.setZombieShelter(sheltered, true)
    check(applied == false and why == "bridge_refused",
        "a refused zombie shelter is reported: " .. tostring(why))
    SCBridge.setStoryZombieIgnored = function() return true end
    applied, why = SC.Oddballs.setZombieShelter(sheltered, true)
    check(applied == false and why == "shelter_not_applied",
        "an accepted shelter the native getter denies is not trusted: "
            .. tostring(why))
    SCBridge = oldBridge
end

local asked, askReason = SC.FactionRecruitment.ask(group, player)
check(asked == true, "lone oddball can be asked: " .. tostring(askReason))
local started, startReason = SC.FactionRecruitment.startTrial(group, player)
check(started == true and group.members[1].away == "recruitment_trial",
    "lone oddball starts the regular recruitment trial: " .. tostring(startReason))
local decided, decisionReason = SC.FactionRecruitment.decide(group, player, "join")
check(decided == true and group.lifecycle == "destroyed"
    and group.members[1].departed == true,
    "joined oddball retires the encounter: " .. tostring(decisionReason))
check(SC.Factions.atPosition({ x = 10, y = 10, z = 0 }) == nil,
    "a retired oddball no longer claims territory for container interactions")
check(SC.Oddballs.groupForActor(actor) == group,
    "joined actor still resolves to its original story")

local factionSave, factionReason = SC.Factions.export()
local oddballSave, oddballReason = SC.Oddballs.export()
check(factionSave ~= nil and oddballSave ~= nil,
    "faction and oddball ledgers export: " .. tostring(factionReason or oddballReason))
check(oddballSave.retired[definition.id] == "recruited",
    "recruitment permanently marks the unique character resolved")
SC.Factions.reset()
check(SC.Factions.group(group.id) == nil, "faction reset clears the group")
local restored, restoreReason = SC.Factions.restore(factionSave)
check(restored == true, "joined group restores: " .. tostring(restoreReason))
restored, restoreReason = SC.Oddballs.restore(oddballSave)
check(restored == true, "oddball ledger restores: " .. tostring(restoreReason))
local restoredGroup = SC.Factions.group(group.id)
check(restoredGroup and restoredGroup.oddball.id == definition.id
    and SC.Oddballs.export().retired[definition.id] == "recruited",
    "save/load preserves the story and prevents reseeding")
local lorettaSave = SC.StableValue.copyStrict(factionSave,
    { maxDepth = 16, maxEntries = 131072 })
local lorettaStory = lorettaSave.groups[group.id].oddball
lorettaStory.id = "loretta_ten_and_two"
lorettaStory.site.kind = "resident"
lorettaStory.site.vehicle = { sqlId = 8, seat = 2,
    door = { x = 10, y = 10, z = 0 } }
lorettaStory.carSqlId = 8
lorettaStory.seat = 2
lorettaStory.carPrepared = true
lorettaStory.darrenSpawned = true
local lorettaRestored, lorettaReason = SC.Factions.restore(lorettaSave)
check(lorettaRestored == true,
    "Loretta's resident car site passes faction restore: "
        .. tostring(lorettaReason))
local carStory = SC.Factions.group(group.id).oddball
check(carStory.id == "loretta_ten_and_two"
    and carStory.site.vehicle.sqlId == 8
    and carStory.site.vehicle.seat == 2
    and carStory.carSqlId == 8 and carStory.carPrepared == true,
    "Loretta's SQL car identity and setup state survive faction restore")
check(SC.Factions.restore(factionSave) == true,
    "the original oddball group restores after the Loretta contract")
restoredGroup = SC.Factions.group(group.id)
for _, field in ipairs({ "wake", "coop", "truck" }) do
    local invalid = SC.StableValue.copyStrict(factionSave,
        { maxDepth = 16, maxEntries = 131072 })
    invalid.groups[group.id].oddball.site[field] = { x = "bad", y = 10, z = 0 }
    local accepted = SC.Factions.restore(invalid)
    check(accepted == false and SC.Factions.group(group.id) == restoredGroup,
        "malformed " .. field .. " coordinate cannot replace saved faction state")
end
for _, case in ipairs({
    { "roomGuardElapsedMs", -1 }, { "roomGuardElapsedMs", 300001 },
    { "roomGuardElapsedMs", math.huge }, { "roomGuardDone", "yes" },
}) do
    local invalid = SC.StableValue.copyStrict(factionSave,
        { maxDepth = 16, maxEntries = 131072 })
    invalid.groups[group.id].oddball[case[1]] = case[2]
    local accepted = SC.Factions.restore(invalid)
    check(accepted == false and SC.Factions.group(group.id) == restoredGroup,
        "invalid " .. case[1] .. " cannot replace saved faction state")
end
local guardedSave = SC.StableValue.copyStrict(factionSave,
    { maxDepth = 16, maxEntries = 131072 })
guardedSave.groups[group.id].oddball.roomGuardElapsedMs = 300000
guardedSave.groups[group.id].oddball.roomGuardDone = true
check(SC.Factions.restore(guardedSave) == true,
    "bounded completed room-guard state survives faction restore")
restoredGroup = SC.Factions.group(group.id)
check(restoredGroup.oddball.roomGuardElapsedMs == 300000
        and restoredGroup.oddball.roomGuardDone == true,
    "completed guard state remains explicit after save/load")
check(SC.Oddballs.groupForActor(actor) == restoredGroup,
    "joined actor resolves through saved recruitment provenance")
SC.Oddballs.pulse(player, U.nowMs())

local deputy = SC.Oddballs.definition("checkpoint_deputy_rhonda")
check(deputy and deputy.archetype == "oddball_psycho"
    and deputy.identity.outfit == "Sheriff_Deputy"
    and deputy.captives == true and deputy.recruitment == true,
    "the deputy is a unique police-station checkpoint with recruitable captives")
local oldGridSquare, oldOddballHouseAt = U.gridSquare, SC.Factions.oddballHouseAt
local stationBuilding = {}
local locker = { getName = function() return "policelocker" end }
local cellA = { getName = function() return "cells" end }
local cellB = { getName = function() return "prisoncells" end }
local stationSquares = {
    ["20:20"] = locker, ["21:20"] = cellA, ["22:20"] = cellB,
    ["23:20"] = locker, ["24:20"] = locker,
}
U.gridSquare = function(x, y, z)
    local room = z == 0 and stationSquares[tostring(x) .. ":" .. tostring(y)] or nil
    if room then
        return { x = x, y = y, z = z,
            getRoom = function() return room end,
            getBuilding = function() return stationBuilding end }
    end
end
local stationHouse = { id = "station-20", anchor = { x = 20, y = 20, z = 0 },
    bounds = { x1 = 20, y1 = 20, x2 = 24, y2 = 20 },
    interior = { { x = 20, y = 20, z = 0 },
        { x = 21, y = 20, z = 0 }, { x = 22, y = 20, z = 0 },
        { x = 23, y = 20, z = 0 }, { x = 24, y = 20, z = 0 } },
    openings = {} }
SC.Factions.oddballHouseAt = function() return stationHouse end
local deputySite = SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, deputy, "policelocker", true)
check(deputySite and deputySite.spawn.x == 20
    and #deputySite.captiveSpawns >= 1
    and deputySite.captiveSpawns[1].x ~= deputySite.spawn.x,
    "deputy stands at the checkpoint while captives begin in distinct cells")
local originalOccupyingObject = U.squareOccupyingObject
U.squareOccupyingObject = function(square)
    if square and (square.x == 20 or square.x == 21) then
        return { name = "partial chair" }
    end
    return nil
end
local clearDeputySite = SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, deputy, "policelocker", true)
check(clearDeputySite and clearDeputySite.spawn.x == 23
        and clearDeputySite.captiveSpawns[1].x == 22,
    "scripted residents and captives skip furniture even on native-safe tiles")
local stagedDeputy = { id = "furniture-test", house = stationHouse,
    members = { { key = "leader" } },
    oddball = { site = { spawn = { x = 20, y = 20, z = 0 } } } }
local wakeSquare = SC.Factions._chooseMemberSquareForTests(stagedDeputy, 1)
check(wakeSquare and wakeSquare.x == 23,
    "restored scripted actor moves to clear floor when saved spawn has furniture")
U.squareOccupyingObject = function(square)
    return square and square.x == 23 and { name = "partial chair" } or nil
end
local room12Coop = SC.Oddballs._otherRoomTileForTests(stationHouse,
    { x = 20, y = 20, z = 0 })
check(room12Coop and room12Coop.x == 24,
    "Room 12 animal post skips the first furnished same-room tile")
U.squareOccupyingObject = originalOccupyingObject
local deputyGroup, deputyReason = SC.Factions.createOddballGroup(deputySite,
    deputy, true)
check(deputyGroup and #deputyGroup.members == 1 + #deputySite.captiveSpawns
    and deputyGroup.members[1].role == "leader"
    and deputyGroup.members[2].role == "captive",
    "police encounter queues one deputy and its ordinary captive members: "
        .. tostring(deputyReason))
check(SC.Factions.supports(deputyGroup, "recruitment") == true
    and deputyGroup.oddball.site.captiveSpawns[1].x
        == deputySite.captiveSpawns[1].x,
    "the authored deputy recruitment flag and cell locations persist in the group")
local deputySave = SC.Factions.export()
check(deputySave and SC.Factions.restore(deputySave) == true,
    "a deputy with captive members survives a save/load")
deputyGroup = SC.Factions.group(deputyGroup.id)
check(deputyGroup and deputyGroup.members[2].captive == true,
    "a restored captive remains marked as a captive")
local malformed = SC.StableValue.copyStrict(deputySave,
    { maxDepth = 16, maxEntries = 131072 })
malformed.groups[deputyGroup.id].oddball.site.captiveSpawns[1].x = "bad"
check(SC.Factions.restore(malformed) == false
    and SC.Factions.group(deputyGroup.id) == deputyGroup,
    "a corrupt saved cell is rejected without replacing the live group")
local captiveMember = deputyGroup.members[2]
local captiveActor = { id = "deputy-captive-actor", x = 21, y = 20, z = 0 }
local captiveRecord = { id = captiveActor.id, actor = captiveActor,
    factionId = deputyGroup.id, factionRole = "captive", recruited = false }
captiveMember.actorId = captiveActor.id
captiveMember.spawnQueued = false
local priorById = SC.Registry.byId
SC.Registry.byId = function(id)
    return id == captiveActor.id and captiveRecord or priorById(id)
end
local priorRelease = SC.Commands.releaseFactionCaptive
SC.Commands.releaseFactionCaptive = function(value, id)
    check(value == captiveActor and id == deputyGroup.id,
        "captive release uses the exact loaded faction member")
    captiveRecord.factionId, captiveRecord.factionRole = nil, nil
    return true, "captive_released"
end
local freed, freedId = SC.Factions.releaseCaptiveMember(
    deputyGroup.id, captiveMember.key)
check(freed == true and freedId == captiveActor.id
    and captiveMember.departed == true and captiveMember.actorId == nil
    and captiveRecord.factionId == nil and captiveRecord.recruited == false,
    "badge release detaches the captive as an ordinary recruitable survivor")
SC.Registry.byId, SC.Commands.releaseFactionCaptive = priorById, priorRelease
local silas = SC.Oddballs.definition("cult_brother_silas")
local purdy = SC.Oddballs.definition("sniper_purdy_clan")
check(silas and purdy and silas.memberCountMin == 3
    and purdy.memberCountMax == 3 and SC.Oddballs.definition(
        "wedding_lonnie_tackett") ~= nil,
    "the next six authored encounters are registered with group counts")
local cultSite = { kind = "resident", room = "church", house = stationHouse,
    anchor = { x = 20, y = 20, z = 0 },
    spawn = { x = 20, y = 20, z = 0 },
    memberSpawns = { { x = 20, y = 20, z = 0 },
        { x = 21, y = 20, z = 0 }, { x = 22, y = 20, z = 0 } },
    altar = { x = 20, y = 20, z = 0 } }
local cultGroup, cultReason = SC.Factions.createOddballGroup(cultSite,
    silas, true)
check(cultGroup and #cultGroup.members == 3
    and cultGroup.members[2].role == "cultist"
    and cultGroup.members[2].identity.outfit == "Cultist",
    "multi-member encounter keeps authored roles and clothing: "
        .. tostring(cultReason))
check(cultGroup.oddball.site.memberSpawns[3].x == 22
    and SC.Factions.supports(cultGroup, "trade") == false
    and SC.Factions.supports(cultGroup, "recruitment") == false,
    "the cult confession remains a story action rather than generic barter")
check(SC.Factions.summary(cultGroup.id).capabilities.trade == false,
    "UI summary keeps custom confession separate from generic barter")
cultGroup.oddball.trade = true
check(SC.Factions.summary(cultGroup.id).capabilities.trade == true,
    "UI summary reflects an authored faction trade capability")
cultGroup.oddball.trade = nil
local cultSave = SC.Factions.export()
check(cultSave and SC.Factions.restore(cultSave) == true,
    "the three-member scene survives save/load")
cultGroup = SC.Factions.group(cultGroup.id)
local badCultSave = SC.StableValue.copyStrict(cultSave,
    { maxDepth = 16, maxEntries = 131072 })
badCultSave.groups[cultGroup.id].oddball.site.memberSpawns[2].x = 20
check(SC.Factions.restore(badCultSave) == false
    and SC.Factions.group(cultGroup.id) == cultGroup,
    "duplicate saved member posts are rejected atomically")
local cultMember = cultGroup.members[2]
local cultActor = { id = "cult-survivor", x = 21, y = 20, z = 0 }
local cultRecord = { id = cultActor.id, actor = cultActor,
    factionId = cultGroup.id, factionRole = "cultist", recruited = false }
cultMember.actorId, cultMember.spawnQueued = cultActor.id, false
local cultById = SC.Registry.byId
SC.Registry.byId = function(id)
    return id == cultActor.id and cultRecord or cultById(id)
end
local cultRelease = SC.Commands.releaseOddballMember
SC.Commands.releaseOddballMember = function(value, id, role, order)
    check(value == cultActor and id == cultGroup.id
        and role == "cultist" and order == "stay",
        "leader-death survivor is released through command ownership")
    cultRecord.factionId, cultRecord.factionRole = nil, nil
    return true, "oddball_member_released"
end
local neutral, neutralId = SC.Factions.releaseOddballMember(
    cultGroup.id, cultMember.key, "stay")
check(neutral and neutralId == cultActor.id and cultMember.departed == true
    and cultRecord.factionId == nil,
    "cult aftermath detaches a living neutral survivor without stale faction state")
SC.Registry.byId, SC.Commands.releaseOddballMember = cultById, cultRelease
local partyDefinition = SC.Oddballs.definition("party_room12_delbert")
local partySite = { kind = "resident", room = "motelroom", house = stationHouse,
    anchor = { x = 20, y = 20, z = 0 },
    spawn = { x = 20, y = 20, z = 0 },
    coop = { x = 21, y = 20, z = 0, enclosed = true },
    partyDoor = { x = 20, y = 20, z = 0, objectIndex = 2, kind = "door" },
    partyWindow = { x = 22, y = 20, z = 0, objectIndex = 3, kind = "window" } }
local partyGroup = SC.Factions.createOddballGroup(partySite, partyDefinition, true)
check(partyGroup and partyGroup.oddball.site.partyDoor.objectIndex == 2,
    "Room 12 persists exact openings for real barricade jobs")
local rabbitSpawns = {}
local rabbitInterior = {}
for index = 1, 10 do
    local position = { x = 20 + (index - 1) % 4,
        y = 20 + math.floor((index - 1) / 4), z = 0 }
    rabbitSpawns[index], rabbitInterior[index] = position, position
end
local rabbitHouse = { id = "june-house", anchor = { x = 20, y = 20, z = 0 },
    bounds = { x1 = 20, x2 = 23, y1 = 20, y2 = 22, z = 0 },
    interior = rabbitInterior, openings = {} }
local juneSite = { kind = "resident", room = "rangerhall", house = rabbitHouse,
    anchor = { x = 20, y = 20, z = 0 },
    spawn = { x = 20, y = 20, z = 0 }, animalSpawns = rabbitSpawns }
local juneGroup = SC.Factions.createOddballGroup(juneSite,
    SC.Oddballs.definition("ranger_june_whitlock"), true)
check(juneGroup and #juneGroup.oddball.site.animalSpawns == 10,
    "June keeps ten distinct rabbit sites in durable story state")
juneGroup.oddball.animals = { slots = {} }
for index = 1, 10 do
    juneGroup.oddball.animals.slots[index] = { id = 4000 + index,
        name = "Rabbit " .. tostring(index), kind = "rabdoe",
        breed = "swamp", x = rabbitSpawns[index].x,
        y = rabbitSpawns[index].y, z = 0, spawned = true }
end
partyGroup.oddball.supplies = 4
partyGroup.oddball.tradeCount = 1
local phaseTwoSave = SC.Factions.export()
check(phaseTwoSave and SC.Factions.restore(phaseTwoSave) == true,
    "Room 12 openings and June's rabbit sites survive save/load")
check(SC.Factions.group(juneGroup.id).oddball.animals.slots[7].id == 4007
    and SC.Factions.group(partyGroup.id).oddball.tradeCount == 1,
    "native animal IDs and party trade progress persist without respawning")
local badRabbitSave = SC.StableValue.copyStrict(phaseTwoSave,
    { maxDepth = 16, maxEntries = 131072 })
badRabbitSave.groups[juneGroup.id].oddball.site.animalSpawns[2].x =
    badRabbitSave.groups[juneGroup.id].oddball.site.animalSpawns[1].x
badRabbitSave.groups[juneGroup.id].oddball.site.animalSpawns[2].y =
    badRabbitSave.groups[juneGroup.id].oddball.site.animalSpawns[1].y
check(SC.Factions.restore(badRabbitSave) == false,
    "duplicate rabbit tiles are rejected without corrupting the save")
local sharedAnimalIdSave = SC.StableValue.copyStrict(phaseTwoSave,
    { maxDepth = 16, maxEntries = 131072 })
sharedAnimalIdSave.groups[juneGroup.id].oddball.animals.slots[2].id = 4001
check(SC.Factions.restore(sharedAnimalIdSave) == true,
    "randomized native animal IDs may coincide across distinct tagged slots")
local wrappedAnimalOnlineIdSave = SC.StableValue.copyStrict(phaseTwoSave,
    { maxDepth = 16, maxEntries = 131072 })
wrappedAnimalOnlineIdSave.groups[juneGroup.id].oddball.animals.slots[2].onlineId = -2
check(SC.Factions.restore(wrappedAnimalOnlineIdSave) == true,
    "wrapped signed-short online IDs are valid native lookup keys")
local badAnimalOnlineIdSave = SC.StableValue.copyStrict(phaseTwoSave,
    { maxDepth = 16, maxEntries = 131072 })
badAnimalOnlineIdSave.groups[juneGroup.id].oddball.animals.slots[2].onlineId = 40000
check(SC.Factions.restore(badAnimalOnlineIdSave) == false,
    "online lookup IDs outside native short range are rejected")
local pyro = SC.Oddballs.definition("pyromaniac_earl_kessler")
check(pyro and pyro.recruitment == true and pyro.kind == "resident",
    "Earl's recruitable resident encounter is registered")
local previousFree = U.isSquareFree
U.isSquareFree = function(square) return square ~= nil end
stationSquares["21:20"], stationSquares["22:20"] = locker, locker
local pyroSite = SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, pyro, "policelocker", true)
check(pyroSite and #pyroSite.fuelPosts == 2
    and pyroSite.fuelPosts[1].x ~= pyroSite.spawn.x
    and (pyroSite.fuelPosts[1].x - pyroSite.fuelPosts[2].x) ^ 2
        + (pyroSite.fuelPosts[1].y - pyroSite.fuelPosts[2].y) ^ 2 >= 4,
    "eligible room spreads fuel cans at least two tiles apart")
local pyroGroup, pyroReason = SC.Factions.createOddballGroup(
    pyroSite, pyro, true)
check(pyroGroup and #pyroGroup.oddball.site.fuelPosts == 2,
    "fuel posts enter the persistent encounter site: " .. tostring(pyroReason))
local priorInventory, priorDeep = U.inventory, U.inventoryItemsDeep
local priorItemType, priorAddItem = U.itemType, U.addItem
U.inventory = function(subject) return subject.inventory end
U.inventoryItemsDeep = function(inventory) return inventory or {} end
U.itemType = function(item) return item.kind end
U.addItem = function(inventory, kind)
    local item = { kind = kind }
    inventory[#inventory + 1] = item
    return item
end
for _, entry in ipairs({
    { id = "survivalist_locked_horde", count = 7,
        weapon = "Base.HuntingKnife" },
    { id = "voice_actor_vera_quill", count = 6,
        weapon = nil },
    { id = "pyromaniac_earl_kessler", count = 5,
        weapon = "Base.PipeWrench" },
    { id = "shotgun_farmer_wendell", count = 3, weapon = nil },
    { id = "ringmaster_rusty_pell", count = 2, weapon = nil },
    { id = "dewey_prentice_hollowell", count = 3, weapon = nil },
    { id = "werewolf_dalton_reese", count = 3, weapon = nil },
    { id = "man_in_the_chair", count = 3, weapon = nil },
}) do
    local subject = { inventory = {} }
    function subject:setPrimaryHandItem(item) self.primary = item end
    local kitGroup = { oddball = { id = entry.id } }
    check(SC.Oddballs._seedPersonalKitForTests(kitGroup, subject) == true
        and #subject.inventory == entry.count
        and (entry.weapon == nil and subject.primary == nil
            or subject.primary and subject.primary.kind == entry.weapon),
        "authored kit gives the correct weapon and inventory to " .. entry.id)
    check(SC.Oddballs._seedPersonalKitForTests(kitGroup, subject) == true
        and #subject.inventory == entry.count,
        "an encounter reawaken does not duplicate " .. entry.id .. "'s kit")
    kitGroup.oddball.kitSeeded = false
    check(SC.Oddballs._seedPersonalKitForTests(kitGroup, subject) == true
        and #subject.inventory == entry.count,
        "a retried partial kit reuses existing items for " .. entry.id)
end
local priorIdOf = U.idOf
U.idOf = function(subject) return subject.id end
local first = { id = "kit-first", inventory = {} }
local second = { id = "kit-second", inventory = {} }
local groupKit = { oddball = { id = "bledsoe_brothers_still" },
    members = { { actorId = first.id }, { actorId = second.id } } }
check(SC.Oddballs._seedPersonalKitForTests(groupKit, second) == true
    and #second.inventory == 0 and groupKit.oddball.kitSeeded ~= true,
    "a secondary group member cannot consume the leader's personal kit")
check(SC.Oddballs._seedPersonalKitForTests(groupKit, first) == true
    and #first.inventory == 2 and groupKit.oddball.kitSeeded == true,
    "the first named group member receives the personal kit")
check(SC.Oddballs._seedPersonalKitForTests(groupKit, first) == true
    and #first.inventory == 2,
    "the group personal kit is not duplicated on reawaken")
U.idOf = priorIdOf
U.inventory, U.inventoryItemsDeep = priorInventory, priorDeep
U.itemType, U.addItem = priorItemType, priorAddItem
pyroGroup.oddball.fuelSpawned = { true, true }
pyroGroup.oddball.stage = "burning"
pyroGroup.oddball.ignitedAt = 12345
pyroGroup.oddball.kitSeeded = true
local pyroSave = SC.Factions.export()
check(pyroSave and SC.Factions.restore(pyroSave) == true,
    "triggered pyromaniac scene survives save/load")
check(SC.Factions.group(pyroGroup.id).oddball.ignitedAt == 12345
    and SC.Factions.group(pyroGroup.id).oddball.kitSeeded == true,
    "ignition and one-time kit state persist without relighting or duplicates")
local duplicateFuelSave = SC.StableValue.copyStrict(pyroSave,
    { maxDepth = 16, maxEntries = 131072 })
duplicateFuelSave.groups[pyroGroup.id].oddball.site.fuelPosts[2].x =
    duplicateFuelSave.groups[pyroGroup.id].oddball.site.fuelPosts[1].x
duplicateFuelSave.groups[pyroGroup.id].oddball.site.fuelPosts[2].y =
    duplicateFuelSave.groups[pyroGroup.id].oddball.site.fuelPosts[1].y
check(SC.Factions.restore(duplicateFuelSave) == false,
    "duplicate pyromaniac fuel posts are rejected on restore")
U.isSquareFree = previousFree
stationSquares["21:20"], stationSquares["22:20"] = nil, nil
check(SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, deputy, "policelocker", true) == nil,
    "a police station without any loaded cell is not used for this encounter")
U.gridSquare, SC.Factions.oddballHouseAt = oldGridSquare, oldOddballHouseAt

SC.Config.testSet("debugSpawnEnabled", false)
local debugAllowed, debugReason = SC.Oddballs.debugSpawnRandom(player)
check(debugAllowed == false and debugReason == "debug_tools_disabled",
    "manual encounter spawning stays behind the private debug gate")
SC.Config.testSet("debugSpawnEnabled", true)
SC.Oddballs.reset()
local room = { getName = function() return "spiffoskitchen" end }
local building = {}
U.gridSquare = function(x, y, z)
    if z ~= 0 then return nil end
    return { x = x, y = y, z = z,
        getRoom = function() return room end,
        getBuilding = function() return building end }
end
local debugSawVisibleLandmark = false
SC.Factions.oddballHouseAt = function(square, _, allowSeen)
    debugSawVisibleLandmark = debugSawVisibleLandmark or allowSeen == true
    return { id = "debug-spiffos", anchor = { x = square.x, y = square.y, z = 0 },
        bounds = { x1 = square.x, y1 = square.y,
            x2 = square.x + 2, y2 = square.y + 2, z = 0 },
        interior = { { x = square.x, y = square.y, z = 0 } }, openings = {} }
end
local debugCreated, debugGroup = 0, nil
local createRealOddballGroup = SC.Factions.createOddballGroup
SC.Factions.createOddballGroup = function(candidate, character, isDebug)
    check(isDebug == true and candidate.spawn ~= nil,
        "manual encounter uses the authored landmark and debug faction spawn")
    debugCreated = debugCreated + 1
    debugGroup = { id = "debug-odd-" .. debugCreated,
        oddball = { id = character.id, stage = "unmet", site = candidate } }
    return debugGroup
end
local debugSpawned, debugId = SC.Oddballs.debugSpawnRandom(player)
check(debugSpawned == true and debugId == "debug-odd-1"
    and debugGroup.oddball.id == "window_spiffo_kevin"
    and debugSawVisibleLandmark,
    "debug button queues one random eligible authored encounter")
debugSpawned, debugReason = SC.Oddballs.debugSpawnRandom(player)
check(debugSpawned == false and debugReason == "oddball_spawn_pending"
    and debugCreated == 1,
    "a second click cannot queue a duplicate while the first spawn is pending")
SC.Oddballs.spawned(debugGroup, nil)
debugSpawned, debugReason = SC.Oddballs.debugSpawnRandom(player)
check(debugSpawned == false and debugReason == "no_eligible_loaded_site"
    and debugCreated == 1,
    "the saved unique ledger prevents another Kevin at the same landmark")

for _, pair in ipairs({
    { "gordon_pettibone", "OddballGordon" },
    { "morton_buster", "OddballMorton" },
    { "mien_ward", "OddballMien" },
    { "grinder_berg", "OddballGrinder" },
}) do
    local definition = SC.Oddballs.definition(pair[1])
    check(definition and definition.module == pair[2],
        "last encounters registered with native behavior modules")
end

-- A sealed horde may only seed behind one closed, reachable interior door.
do
    local bedroom = { getName = function() return "bedroom" end }
    local hallway = { getName = function() return "hall" end }
    local tiles = {}
    local function tile(x, y, room)
        local value = { x = x, y = y, z = 0, room = room, objects = {} }
        function value:getRoom() return self.room end
        function value:getObjects() return self.objects end
        tiles[x .. ":" .. y] = value
        return value
    end
    for x = 40, 41 do
        for y = 40, 41 do tile(x, y, bedroom) end
    end
    local outside = tile(40, 42, hallway)
    local door = { __class = "IsoDoor" }
    function door:getNorth() return true end
    function door:getObjectIndex() return 0 end
    function door:IsOpen() return false end
    outside.objects[1] = door
    U.gridSquare = function(x, y, z)
        return z == 0 and tiles[x .. ":" .. y] or nil
    end
    U.instanceOf = function(object, class)
        return object.__class == class
    end
    U.squareObjects = function(square, callback)
        for index, object in ipairs(square.objects) do
            callback(object, index - 1)
        end
    end
    SC.Factions.oddballHouseAt = function()
        return { id = "sealed-house", anchor = { x = 40, y = 40, z = 0 },
            bounds = { x1 = 40, y1 = 40, x2 = 41, y2 = 42 },
            interior = { { x = 40, y = 40, z = 0 },
                { x = 41, y = 40, z = 0 },
                { x = 40, y = 41, z = 0 },
                { x = 41, y = 41, z = 0 },
                { x = 40, y = 42, z = 0 } }, openings = {} }
    end
    local site = SC.Oddballs._siteForResidentForTests(
        tiles["40:40"], player,
        SC.Oddballs.definition("survivalist_locked_horde"),
        "bedroom", true)
    check(site and site.spawn.y == 42 and site.roomDoor.objectIndex == 0
        and #site.hordeSpawns == 4,
        "sealed room selects four real floor squares and one exterior-side post")
    local sealedGroup = createRealOddballGroup(site,
        SC.Oddballs.definition("survivalist_locked_horde"), true)
    check(sealedGroup and sealedGroup.oddball.site.roomDoor
        and #sealedGroup.oddball.site.hordeSpawns == 4,
        "faction creation preserves the sealed door and horde tiles")
    local sealedSave = SC.Factions.export()
    check(sealedSave and SC.Factions.restore(sealedSave) == true
        and SC.Factions.group(sealedGroup.id).oddball.site.sealedRoom.x == 40,
        "sealed scene survives faction save and restore")
    local extra = { __class = "IsoDoor" }
    function extra:IsOpen() return true end
    function extra:getNorth() return false end
    tile(42, 40, hallway).objects[1] = extra
    site = SC.Oddballs._siteForResidentForTests(
        tiles["40:40"], player,
        SC.Oddballs.definition("survivalist_locked_horde"),
        "bedroom", true)
    check(site == nil, "a room with an open second exit is rejected")
    local voice = SC.Oddballs._siteForResidentForTests(
        tiles["40:40"], player,
        SC.Oddballs.definition("voice_actor_vera_quill"),
        "bedroom", true)
    check(voice and voice.bedroomDoor.objectIndex == 0,
        "voice actor bedroom requires a real closed door")
    local voiceGroup = createRealOddballGroup(voice,
        SC.Oddballs.definition("voice_actor_vera_quill"), true)
    check(voiceGroup and voiceGroup.oddball.site.bedroomDoor
        and SC.Factions.restore(SC.Factions.export()) == true,
        "voice actor bedroom door survives faction save and restore")
    function door:IsOpen() return true end
    voice = SC.Oddballs._siteForResidentForTests(
        tiles["40:40"], player,
        SC.Oddballs.definition("voice_actor_vera_quill"),
        "bedroom", true)
    check(voice == nil, "voice actor is not seeded in an open bedroom")
end

-- Bedridden Arthur needs a real bed and an intact bedroom before the scene
-- reserves a post. The four costume ambushers must share one physical room;
-- a second living room with the same name cannot supply missing members.
do
    local previousGrid, previousSquareOf, previousHouseAt =
        U.gridSquare, U.squareOf, SC.Factions.oddballHouseAt
    local previousOccupying, previousSeating =
        U.squareOccupyingObject, SeatingManager
    local bedroom = { getName = function() return "bedroom" end }
    local hallway = { getName = function() return "hall" end }
    local livingA = { getName = function() return "livingroom" end }
    local livingB = { getName = function() return "livingroom" end }
    local tiles = {}
    local function tile(x, y, room)
        local square = { x = x, y = y, z = 0, room = room, objects = {} }
        function square:getRoom() return self.room end
        function square:getObjects() return self.objects end
        tiles[x .. ":" .. y] = square
        return square
    end
    local bedTile = tile(70, 70, bedroom)
    local otherBedTile = tile(71, 70, bedroom)
    local footTile = tile(69, 70, bedroom)
    local bed = { __class = "IsoObject" }
    local bedGrid = {}
    local bedSprite
    function bedGrid:getSpriteGridPosX(sprite)
        return sprite == bedSprite and 0 or 1
    end
    function bedGrid:getSpriteGridPosY() return 0 end
    bedSprite = {
        getName = function() return "furniture_bedding_01_25" end,
        getSpriteGrid = function() return bedGrid end,
    }
    local otherBedSprite = {
        getName = function() return "furniture_bedding_01_27" end,
        getSpriteGrid = function() return bedGrid end,
    }
    function bed:getName() return "Bed" end
    function bed:getSprite() return bedSprite end
    bed.square = bedTile
    bedTile.objects[1], bedTile.fixtureOccupied = bed, bed
    local otherBed = { __class = "IsoObject", square = otherBedTile }
    function otherBed:getName() return "Bed" end
    function otherBed:getSprite() return otherBedSprite end
    otherBedTile.objects[1], otherBedTile.fixtureOccupied =
        otherBed, otherBed
    SeatingManager = { getInstance = function()
        return { getFacingDirection = function(_, object)
            return object.seatingFacing or "W"
        end }
    end }
    -- The real house descriptor omits the bed's occupied square from its
    -- safe actor posts. Site discovery must still find that bed by its room.
    local bedroomPosts = { { x = 69, y = 70, z = 0 } }
    for _, coordinates in ipairs({ { 70, 71 }, { 71, 71 },
        { 72, 71 }, { 71, 72 } }) do
        tile(coordinates[1], coordinates[2], bedroom)
        bedroomPosts[#bedroomPosts + 1] = {
            x = coordinates[1], y = coordinates[2], z = 0 }
    end
    local doorTile = tile(71, 73, hallway)
    local door = { __class = "IsoDoor", open = false }
    function door:getNorth() return true end
    function door:getObjectIndex() return 0 end
    function door:IsOpen() return self.open end
    doorTile.objects[1] = door
    bedroomPosts[#bedroomPosts + 1] = { x = 71, y = 73, z = 0 }
    local bedroomHouse = { id = "arthur-test-bedroom",
        anchor = { x = 70, y = 70, z = 0 },
        bounds = { x1 = 69, x2 = 72, y1 = 70, y2 = 73 },
        interior = bedroomPosts, openings = {} }
    U.gridSquare = function(x, y, z)
        return z == 0 and tiles[x .. ":" .. y] or nil
    end
    U.squareOf = function(value) return value and value.square end
    U.squareOccupyingObject = function(square)
        return square and square.fixtureOccupied or nil
    end
    SC.Factions.oddballHouseAt = function() return bedroomHouse end
    local arthur = SC.Oddballs.definition("bedridden_arthur_hale")
    check(arthur and arthur.module == "OddballBedridden"
        and arthur.kind == "resident" and arthur.recruitment == false,
        "Arthur is registered as a unique nonrecruitable resident")
    local normalized, foot, entryReason =
        SC.Oddballs.nativeBedFootEntry(bed)
    check(normalized == otherBed and foot and foot.x == 71.5
        and math.abs(foot.y - 71.3) < 0.001
        and foot.facing == "W" and foot.entryKind == "HeadLeft"
        and entryReason == "entry",
        "Arthur's two-tile bed uses the stock normalized head-side entry")
    -- The four tiles of a large double bed all face south, although its
    -- head tiles expose W/E seating positions. The stock context menu uses
    -- those W/E directions for normalization and the actual entry clip.
    local doubleGrid = {}
    function doubleGrid:getSpriteGridPosX(sprite) return sprite.gx end
    function doubleGrid:getSpriteGridPosY(sprite) return sprite.gy end
    local south = { get = function(_, key)
        return key == "Facing" and "S" or nil
    end }
    local function doublePart(x, y, gx, gy, seatingFacing, spriteProperty)
        local square = tile(x, y, bedroom)
        local sprite = { gx = gx, gy = gy,
            getSpriteGrid = function() return doubleGrid end }
        local object = { square = square,
            seatingFacing = seatingFacing,
            getSprite = function() return sprite end }
        if spriteProperty then
            sprite.getProperties = function() return south end
        else
            object.getProperties = function() return south end
        end
        square.objects[1], square.fixtureOccupied = object, object
        return object, square
    end
    local leftHead = doublePart(80, 80, 0, 0, "W", false)
    local leftFoot = doublePart(80, 81, 0, 1, "S", false)
    local rightHead = doublePart(81, 80, 1, 0, "E", true)
    local rightFoot = doublePart(81, 81, 1, 1, "S", true)
    local leftEntry = { tile(79, 81, bedroom),
        tile(82, 81, bedroom) }
    local doubleHead, doublePoint, doubleReason =
        SC.Oddballs.nativeBedFootEntry(leftFoot)
    check(doubleHead == leftFoot and doubleReason == "entry"
        and doublePoint and math.abs(doublePoint.x - 79.7) < 0.001
        and doublePoint.y == 81.5
        and doublePoint.facing == "S"
        and doublePoint.entryKind == "HeadRight"
        and doublePoint.pillow and doublePoint.pillow.x == 80
        and doublePoint.pillow.y == 80,
        "double bed uses its S-facing clip and pillow alignment")
    doubleHead, doublePoint, doubleReason =
        SC.Oddballs.nativeBedFootEntry(rightHead)
    check(doubleHead == leftFoot and doubleReason == "entry"
        and doublePoint and math.abs(doublePoint.x - 79.7) < 0.001
        and doublePoint.y == 81.5
        and doublePoint.facing == "S"
        and doublePoint.entryKind == "HeadRight",
        "double bed pillow segment resolves to supported lengthwise lane")
    local rightNormalized, rightPoint =
        SC.Oddballs.nativeBedFootEntry(rightFoot)
    check(rightNormalized == leftFoot and rightPoint
        and math.abs(rightPoint.x - 79.7) < 0.001,
        "double bed prefers its validated west entry while available")
    leftEntry[1].fixtureOccupied = { name = "Chair" }
    local blockedLane, blockedLaneReason
    blockedLane, doublePoint, blockedLaneReason =
        SC.Oddballs.nativeBedFootEntry(rightHead)
    rightNormalized, rightPoint =
        SC.Oddballs.nativeBedFootEntry(leftHead)
    check(blockedLane == rightFoot and blockedLaneReason == "entry"
        and doublePoint and math.abs(doublePoint.x - 82.3) < 0.001
        and doublePoint.pillow.x == 81
        and rightNormalized == rightFoot and rightPoint,
        "blocked west side chooses the east lengthwise bed lane")
    leftEntry[2].fixtureOccupied = { name = "Chair" }
    blockedLane, _, blockedLaneReason =
        SC.Oddballs.nativeBedFootEntry(leftHead)
    check(blockedLane == nil and blockedLaneReason == "bed_entry_blocked",
        "blocked double-bed sides reject the lie instead of using floor")
    leftEntry[2].fixtureOccupied = nil
    leftEntry[1].fixtureOccupied = nil
    local function checkOrientations()
    local orientationCases = {
        { facing = "N", head = { 300, 301, 0, 1 },
            foot = { 300, 300, 0, 0 }, entry = { 299.7, 301.5 } },
        { facing = "S", head = { 304, 300, 0, 0 },
            foot = { 304, 301, 0, 1 }, entry = { 303.7, 300.5 } },
        { facing = "W", head = { 309, 300, 1, 0 },
            foot = { 308, 300, 0, 0 }, entry = { 309.5, 299.7 } },
        { facing = "E", head = { 313, 300, 0, 0 },
            foot = { 314, 300, 1, 0 }, entry = { 313.5, 299.7 } },
    }
    for _, case in ipairs(orientationCases) do
        local grid = {}
        function grid:getSpriteGridPosX(sprite) return sprite.gx end
        function grid:getSpriteGridPosY(sprite) return sprite.gy end
        local properties = { get = function(_, key)
            return key == "Facing" and case.facing or nil
        end }
        local function segment(post)
            local square = tile(post[1], post[2], bedroom)
            local sprite = { gx = post[3], gy = post[4],
                getSpriteGrid = function() return grid end,
                getProperties = function() return properties end }
            local object = { square = square,
                seatingFacing = case.facing,
                getSprite = function() return sprite end }
            square.objects[1], square.fixtureOccupied = object, object
            return object
        end
        local head = segment(case.head)
        local footPart = segment(case.foot)
        tile(math.floor(case.entry[1]),
            math.floor(case.entry[2]), bedroom)
        local resolved, point, why =
            SC.Oddballs.nativeBedFootEntry(footPart)
        local fromHead, headPoint =
            SC.Oddballs.nativeBedFootEntry(head)
        check(resolved == head and fromHead == head
            and why == "entry" and point and headPoint
            and math.abs(point.x - case.entry[1]) < 0.001
            and math.abs(point.y - case.entry[2]) < 0.001
            and math.abs(headPoint.x - point.x) < 0.001
            and math.abs(headPoint.y - point.y) < 0.001
            and point.facing == case.facing,
            "native bed head entry normalizes a " .. case.facing
                .. "-facing two-piece bed")
    end
    end
    checkOrientations()
    -- Four-piece stock double beds place two lengthwise lanes in one sprite
    -- grid. The entry for one lane must never be inferred from the other.
    local function checkDoubleOrientations()
        local cases = {
            { facing = "N", gx = 0, gy = 1, axis = "y",
                entries = { { 399.7, 400.5 }, { 402.3, 400.5 } } },
            { facing = "W", gx = 1, gy = 0, axis = "x",
                entries = { { 410.5, 399.7 }, { 410.5, 402.3 } } },
            { facing = "E", gx = 0, gy = 0, axis = "x",
                entries = { { 420.5, 399.7 }, { 420.5, 402.3 } } },
        }
        for _, case in ipairs(cases) do
            local grid = {}
            function grid:getSpriteGridPosX(sprite) return sprite.gx end
            function grid:getSpriteGridPosY(sprite) return sprite.gy end
            local properties = { get = function(_, key)
                return key == "Facing" and case.facing or nil
            end }
            local headX = case.facing == "N" and 400
                or case.facing == "W" and 410 or 420
            local headY = 400
            local function segment(x, y, gx, gy)
                local square = tile(x, y, bedroom)
                local sprite = { gx = gx, gy = gy,
                    getSpriteGrid = function() return grid end,
                    getProperties = function() return properties end }
                local object = { square = square,
                    seatingFacing = case.facing,
                    getSprite = function() return sprite end }
                square.objects[1], square.fixtureOccupied = object, object
                return object
            end
            for lane = 0, 1 do
                local hx = headX + (case.axis == "y" and lane or 0)
                local hy = headY + (case.axis == "x" and lane or 0)
                local fx = hx + (case.facing == "E" and 1
                    or case.facing == "W" and -1 or 0)
                local fy = hy + (case.facing == "S" and 1
                    or case.facing == "N" and -1 or 0)
                local hGX = case.axis == "x" and case.gx or lane
                local hGY = case.axis == "y" and case.gy or lane
                local fGX = hGX + (case.facing == "E" and 1
                    or case.facing == "W" and -1 or 0)
                local fGY = hGY + (case.facing == "S" and 1
                    or case.facing == "N" and -1 or 0)
                local head = segment(hx, hy, hGX, hGY)
                local foot = segment(fx, fy, fGX, fGY)
                local entryX = case.entries[lane + 1][1]
                local entryY = case.entries[lane + 1][2]
                tile(math.floor(entryX), math.floor(entryY), bedroom)
                local resolved, point, why =
                    SC.Oddballs.nativeBedFootEntry(foot)
                local fromHead = SC.Oddballs.nativeBedFootEntry(head)
                check(resolved == head and fromHead == head
                    and why == "entry" and point
                    and math.abs(point.x - entryX) < 0.001
                    and math.abs(point.y - entryY) < 0.001,
                    "native double bed " .. case.facing
                        .. " lane " .. lane .. " uses its own head-side entry")
            end
        end
    end
    checkDoubleOrientations()
    local arthurSite = SC.Oddballs._siteForResidentForTests(
        bedTile, player, arthur, "bedroom", true)
    check(arthurSite and arthurSite.bed.objectIndex == 0
        and arthurSite.bedroomDoor.objectIndex == 0
        and (arthurSite.spawn.x ~= bedTile.x
            or arthurSite.spawn.y ~= bedTile.y)
        and arthurSite.floor
        and (arthurSite.floor.x ~= bedTile.x
            or arthurSite.floor.y ~= bedTile.y)
        and (arthurSite.floor.x ~= arthurSite.spawn.x
            or arthurSite.floor.y ~= arthurSite.spawn.y),
        "Arthur chooses a real bed and two distinct clear bedroom floor posts")
    local arthurGroup, arthurReason = createRealOddballGroup(
        arthurSite, arthur, true)
    check(arthurGroup and arthurGroup.oddball.site.bed
        and arthurGroup.oddball.site.floor
        and arthurGroup.oddball.site.bedroomDoor,
        "Arthur's bed, floor death post, and protected door persist in the group: "
            .. tostring(arthurReason))
    local arthurSave = SC.Factions.export()
    check(arthurSave and SC.Factions.restore(arthurSave) == true
        and SC.Factions.group(arthurGroup.id).oddball.site.floor,
        "Arthur's clear death post survives faction save and load")
    footTile.fixtureOccupied = { name = "Chair" }
    tiles["70:71"].fixtureOccupied = { name = "Chair" }
    tiles["71:71"].fixtureOccupied = { name = "Chair" }
    local blockedBed, _, blockedReason =
        SC.Oddballs.nativeBedFootEntry(bed)
    check(blockedBed == nil and blockedReason == "bed_entry_blocked"
        and SC.Oddballs._siteForResidentForTests(
            bedTile, player, arthur, "bedroom", true) == nil,
        "Arthur skips a bed with every native entry post blocked")
    local secondBedTile = tile(70, 72, bedroom)
    local secondOtherTile = tiles["71:72"]
    local secondFootTile = tile(69, 72, bedroom)
    -- These stock hospital sprites have a bed grid outside the furniture
    -- bedding family. The object label must still let Arthur find them.
    bedSprite.getName = function()
        return "location_community_medical_01_20"
    end
    otherBedSprite.getName = function()
        return "location_community_medical_01_21"
    end
    local secondBed = { square = secondBedTile,
        seatingFacing = "S",
        getName = function() return "Bed" end,
        getSprite = function() return bedSprite end }
    local secondOther = { square = secondOtherTile,
        getName = function() return "Bed" end,
        getSprite = function() return otherBedSprite end }
    secondBedTile.objects[1], secondBedTile.fixtureOccupied =
        secondBed, secondBed
    secondOtherTile.objects[1], secondOtherTile.fixtureOccupied =
        secondOther, secondOther
    local laterSite = SC.Oddballs._siteForResidentForTests(
        bedTile, player, arthur, "bedroom", true)
    check(laterSite and laterSite.bed.x == 70 and laterSite.bed.y == 72
        and (function()
            local hospitalBed, hospitalEntry =
                SC.Oddballs.nativeBedFootEntry(secondBed)
            return hospitalBed == secondBed and hospitalEntry
                and hospitalEntry.x == 69.7
                and hospitalEntry.y == 72.5
                and hospitalEntry.facing == "S"
        end)(),
        "Arthur accepts a hospital bed whose seating faces across its tile Facing")
    secondBedTile.objects[1], secondBedTile.fixtureOccupied = nil, nil
    secondOtherTile.objects[1], secondOtherTile.fixtureOccupied = nil, nil
    tiles["69:72"] = nil
    footTile.fixtureOccupied = nil
    tiles["70:71"].fixtureOccupied = nil
    tiles["71:71"].fixtureOccupied = nil
    door.open = true
    check(SC.Oddballs._siteForResidentForTests(bedTile, player,
        arthur, "bedroom", true) == nil,
        "an open bedroom door rejects Arthur's protected scene")
    door.open = false
    bedTile.objects[1], bedTile.fixtureOccupied = nil, nil
    check(SC.Oddballs._siteForResidentForTests(bedTile, player,
        arthur, "bedroom", true) == nil,
        "Arthur cannot reserve a bedroom without a real bed")
    bedTile.objects[1], bedTile.fixtureOccupied = bed, bed
    bedSprite.getSpriteGrid = function() return nil end
    check(SC.Oddballs._siteForResidentForTests(bedTile, player,
        arthur, "bedroom", true) == nil,
        "a bed without the native lying sprite grid cannot consume Arthur's encounter")
    bedSprite.getSpriteGrid = function() return bedGrid end
    local windowTile = tiles["72:71"]
    local window = { __class = "IsoWindow" }
    function window:getNorth() return true end
    function window:IsOpen() return true end
    function window:isSmashed() return false end
    windowTile.objects[1] = window
    bedroomHouse.openings = { { kind = "window", x = 72, y = 71,
        z = 0, objectIndex = 0 } }
    check(SC.Oddballs._siteForResidentForTests(bedTile, player,
        arthur, "bedroom", true) == nil,
        "an open bedroom window rejects Arthur's protected scene")
    windowTile.objects[1], bedroomHouse.openings = nil, {}
    local previousFurniture = {}
    for _, post in ipairs(bedroomPosts) do
        local square = tiles[post.x .. ":" .. post.y]
        if square.room == bedroom and square ~= bedTile then
            previousFurniture[square] = square.fixtureOccupied or false
            square.fixtureOccupied = { name = "Chair" }
        end
    end
    check(SC.Oddballs._siteForResidentForTests(bedTile, player,
        arthur, "bedroom", true) == nil,
        "a real bed without clear bedroom floor cannot host Arthur")
    for square, fixture in pairs(previousFurniture) do
        square.fixtureOccupied = fixture ~= false and fixture or nil
    end

    local smokeRoom = { getName = function() return "livingroom" end }
    local smokeInside = tile(90, 90, smokeRoom)
    tile(90, 89, nil)
    tile(90, 91, smokeRoom)
    tile(89, 90, smokeRoom)
    tile(91, 90, smokeRoom)
    local smokeWindow = { __class = "IsoWindow", locked = true,
        permaLocked = false }
    function smokeWindow:getNorth() return true end
    function smokeWindow:isSmashed() return false end
    function smokeWindow:isBarricaded() return false end
    function smokeWindow:isLocked() return self.locked end
    function smokeWindow:isPermaLocked() return self.permaLocked end
    smokeInside.objects[1] = smokeWindow
    local smokeHouse = { id = "smoker-test-house",
        anchor = { x = 90, y = 90, z = 0 },
        bounds = { x1 = 89, x2 = 91, y1 = 90, y2 = 91 },
        interior = { { x = 90, y = 90, z = 0 },
            { x = 90, y = 91, z = 0 },
            { x = 89, y = 90, z = 0 },
            { x = 91, y = 90, z = 0 } },
        openings = { { kind = "window", x = 90, y = 90,
            z = 0, objectIndex = 0 } } }
    SC.Factions.oddballHouseAt = function() return smokeHouse end
    local smoker = SC.Oddballs.definition("window_smoker_mara_voss")
    local smokeSite = SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true)
    check(smoker and smoker.module == "OddballSmoker"
        and smokeSite and smokeSite.chair.x == 90
        and smokeSite.chair.y == 90
        and smokeSite.chair.spriteName == "furniture_seating_indoor_01_43"
        and smokeSite.spawn.x == 89 and smokeSite.spawn.y == 90
        and smokeSite.lookOut.x == 90 and smokeSite.lookOut.y == 89
        and smokeSite.window.objectIndex == 0
        and #smokeInside.objects == 1,
        "Mara reserves a north-facing chair by the real exterior window without placing it during search")
    local smokeGroup = createRealOddballGroup(smokeSite, smoker, true)
    local smokeSave = SC.Factions.export()
    check(smokeGroup and smokeSave and SC.Factions.restore(smokeSave) == true
        and SC.Factions.group(smokeGroup.id).oddball.site.window.objectIndex == 0
        and SC.Factions.group(smokeGroup.id).oddball.site.chair.spriteName
            == "furniture_seating_indoor_01_43",
        "Mara's chair and window scene survives faction save and load")
    check(SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true) ~= nil,
        "an ordinary locked window can be unlocked and opened for Mara")
    smokeWindow.permaLocked = true
    check(SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true) == nil,
        "a permanently locked window cannot seed Mara's open-window scene")
    smokeWindow.permaLocked = false
    smokeInside.fixtureOccupied = { name = "Table" }
    check(SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true) == nil,
        "an occupied window tile cannot be overwritten with Mara's chair")
    smokeInside.fixtureOccupied = nil
    tiles["89:90"].fixtureOccupied = { name = "Table" }
    check(SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true).spawn.x == 91,
        "Mara can use the other clear side of the chair")
    tiles["91:90"].fixtureOccupied = { name = "Table" }
    check(SC.Oddballs._siteForResidentForTests(
        smokeInside, player, smoker, "livingroom", true) == nil,
        "Mara needs a clear native side approach to the chair")
    tiles["89:90"].fixtureOccupied = nil
    tiles["91:90"].fixtureOccupied = nil

    local packPosts = { { x = 80, y = 80, z = 0 } }
    local packStart = tile(80, 80, livingA)
    for _, coordinates in ipairs({ { 86, 80 }, { 86, 82 },
        { 86, 84 } }) do
        tile(coordinates[1], coordinates[2], livingB)
        packPosts[#packPosts + 1] = {
            x = coordinates[1], y = coordinates[2], z = 0 }
    end
    local chairTile = tile(82, 80, livingA)
    chairTile.fixtureOccupied = { name = "Chair" }
    packPosts[#packPosts + 1] = { x = 82, y = 80, z = 0 }
    for _, coordinates in ipairs({ { 80, 82 }, { 82, 82 },
        { 84, 82 } }) do
        tile(coordinates[1], coordinates[2], livingA)
        packPosts[#packPosts + 1] = {
            x = coordinates[1], y = coordinates[2], z = 0 }
    end
    local packHouse = { id = "spiffo-pack-test-house",
        anchor = { x = 80, y = 80, z = 0 },
        bounds = { x1 = 80, x2 = 86, y1 = 80, y2 = 84 },
        interior = packPosts, openings = {} }
    SC.Factions.oddballHouseAt = function() return packHouse end
    local pack = SC.Oddballs.definition("spiffo_dressup_ambush")
    check(pack and pack.module == "OddballFurryPack"
        and pack.memberCountMin == 4 and #pack.memberIdentities == 4,
        "Spiffo ambush registers four named native members")
    local packSite = SC.Oddballs._siteForResidentForTests(
        packStart, player, pack, "livingroom", true)
    local nativeSameRoom, clear, distinct = true, true, {}
    for _, post in ipairs(packSite and packSite.memberSpawns or {}) do
        local square = tiles[post.x .. ":" .. post.y]
        nativeSameRoom = nativeSameRoom and square:getRoom() == livingA
        clear = clear and U.isClearActorSpawnSquare(square) == true
        local key = post.x .. ":" .. post.y
        if distinct[key] then clear = false end
        distinct[key] = true
    end
    check(packSite and #packSite.memberSpawns == 4
        and nativeSameRoom and clear,
        "all four ambushers occupy distinct clear tiles in one native living room")
    local packGroup, packReason = createRealOddballGroup(
        packSite, pack, true)
    check(packGroup and #packGroup.members == 4
        and #packGroup.oddball.site.memberSpawns == 4,
        "the four ambushers enter one faction group: "
            .. tostring(packReason))
    local packSave = SC.Factions.export()
    check(packSave and SC.Factions.restore(packSave) == true
        and #SC.Factions.group(packGroup.id).oddball.site.memberSpawns == 4,
        "four separate member posts survive faction save and load")
    tiles["84:82"].fixtureOccupied = { name = "Table" }
    check(SC.Oddballs._siteForResidentForTests(packStart, player,
        pack, "livingroom", true) == nil,
        "three same-room clear posts cannot borrow a fourth from another living room")
    U.gridSquare, U.squareOf, U.squareOccupyingObject, SeatingManager =
        previousGrid, previousSquareOf, previousOccupying, previousSeating
    SC.Factions.oddballHouseAt = previousHouseAt
end

-- A paired story needs two unresolved slots. With one slot left it must wait,
-- even when its landmark is valid; the same landmark seeds both rivals when
-- the cap has room.
do
    local oldClock = SC_TEST_CLOCK
    local oldGridSquare, oldCanSee = U.gridSquare, U.canSee
    local oldList = SC.Factions.list
    local oldHouseAt = SC.Factions.oddballHouseAt
    local oldCreate = SC.Factions.createOddballGroup
    local oldPlayerNum = player.getPlayerNum
    local oldFirstDay = SC.Config.get("oddballFirstEligibleDay")
    local oldMaxActive = SC.Config.get("oddballMaxActive")
    local oldBudget = SC.Config.get("oddballScanSampleBudget")
    local office = { getName = function() return "office" end }
    local building = {}
    U.gridSquare = function(x, y, z)
        if z ~= 0 then return nil end
        return { x = x, y = y, z = z,
            getRoom = function() return office end,
            getBuilding = function() return building end,
            isCanSee = function() return false end }
    end
    U.canSee = function() return false end
    player.getPlayerNum = function() return 0 end
    local mainPoint
    SC.Factions.oddballHouseAt = function(square)
        mainPoint = mainPoint or { x = square.x, y = square.y }
        local dx, dy = square.x - mainPoint.x, square.y - mainPoint.y
        local id = dx * dx + dy * dy < 100
            and "doctor-office" or "rival-office"
        return { id = id, anchor = { x = square.x, y = square.y, z = 0 },
            bounds = { x1 = square.x, y1 = square.y,
                x2 = square.x + 2, y2 = square.y + 2 },
            interior = { { x = square.x, y = square.y, z = 0 } },
            openings = {} }
    end
    local created = {}
    SC.Factions.createOddballGroup = function(_, character)
        created[#created + 1] = character.id
        return { id = "capacity-" .. character.id,
            oddball = { id = character.id } }
    end
    SC.Config.testSet("oddballFirstEligibleDay", 0)
    SC.Config.testSet("oddballMaxActive", 2)
    SC.Config.testSet("oddballScanSampleBudget", 1)
    SC_TEST_CLOCK = 15 * 86400000
    SC.Oddballs.reset()
    SC.Factions.list = function()
        return { { id = "existing-oddball",
            oddball = { id = "grocery_gale_mercer" }, lifecycle = "settled" } }
    end
    local seeded, reason = SC.Oddballs.pulse(player, SC_TEST_CLOCK)
    check(seeded == false and reason == "no_eligible_loaded_site"
        and #created == 0,
        "paired rivals wait when only one active encounter slot remains: "
            .. tostring(reason) .. ", created=" .. tostring(#created))
    SC.Oddballs.reset()
    SC.Factions.list = function() return {} end
    mainPoint = nil
    seeded, reason = SC.Oddballs.pulse(player, SC_TEST_CLOCK)
    check(seeded == true and #created == 2
        and created[1] == "doctor_pest" and created[2] == "bluegrass_bolt",
        "the same office still seeds both rivals when two slots are free: "
            .. tostring(reason))
    SC.Oddballs.reset()
    SC_TEST_CLOCK = oldClock
    U.gridSquare, U.canSee = oldGridSquare, oldCanSee
    SC.Factions.list = oldList
    SC.Factions.oddballHouseAt = oldHouseAt
    SC.Factions.createOddballGroup = oldCreate
    player.getPlayerNum = oldPlayerNum
    SC.Config.testSet("oddballFirstEligibleDay", oldFirstDay)
    SC.Config.testSet("oddballMaxActive", oldMaxActive)
    SC.Config.testSet("oddballScanSampleBudget", oldBudget)
end

-- A chair can be placed after the encounter has reserved a spawn tile. The
-- final queue check must move a single-post resident to clear floor in the
-- same room, and a fixed multi-actor scene must wait at its authored post.
do
    local previousGrid = U.gridSquare
    local previousOccupying = U.squareOccupyingObject
    local previousBegin = SC.Actor.beginSpawn
    local room = { name = "bedroom" }
    local squares = {}
    for x = 10, 12 do
        local square = { x = x, y = 10, z = 0,
            getRoom = function() return room end }
        squares[x .. ":10:0"] = square
    end
    U.gridSquare = function(x, y, z)
        return squares[tostring(x) .. ":" .. tostring(y)
            .. ":" .. tostring(z or 0)]
    end
    U.squareOccupyingObject = function(square)
        return square and square.chair or nil
    end
    local house = { id = "queued-chair-fixture",
        anchor = { x = 10, y = 10, z = 0 },
        bounds = { x1 = 10, x2 = 12, y1 = 10, y2 = 10, z = 0 },
        interior = { { x = 10, y = 10, z = 0 },
            { x = 11, y = 10, z = 0 }, { x = 12, y = 10, z = 0 } },
        openings = {} }
    local site = { kind = "resident", room = "bedroom", house = house,
        anchor = house.anchor, spawn = { x = 10, y = 10, z = 0 } }
    local definition = { id = "queued_chair_fixture", name = "Queue Guard",
        archetype = "oddball_resident", memberCountMin = 1,
        memberCountMax = 1, identity = { forename = "Queue",
            surname = "Guard", gender = "female" } }
    SC.Factions.reset()
    squares["10:10:0"].chair = { name = "Chair" }
    check(U.isClearActorSpawnSquare(squares["10:10:0"]) == false,
        "fixture chair occupies a native-safe floor square")
    local blockedGroup = createRealOddballGroup(site, definition, true)
    check(blockedGroup == nil,
        "an occupied post is rejected before it enters the spawn queue")
    squares["10:10:0"].chair = nil
    local queuedGroup, queueReason = createRealOddballGroup(
        site, definition, true)
    check(queuedGroup ~= nil,
        "the clear encounter post enters the queue: " .. tostring(queueReason))
    local begun = {}
    SC.Actor.beginSpawn = function(square)
        begun[#begun + 1] = square
        return { square = square }, "spawn_pending"
    end
    squares["10:10:0"].chair = { name = "Chair" }
    SC.Factions._beginNextSpawnForTests()
    check(#begun == 0 and queuedGroup.members[1].spawnQueued == true,
        "a chair added after queueing blocks native spawn at that tile")
    SC.Factions._beginNextSpawnForTests()
    check(#begun == 1 and begun[1].x == 11 and begun[1].y == 10
        and begun[1]:getRoom() == room,
        "a single-post resident falls back to clear floor in its own room")
    SC.Factions.reset()
    squares["10:10:0"].chair = nil
    local staged = { id = "queued_scene_fixture", name = "Staged Scene",
        archetype = "oddball_resident", memberCountMin = 2,
        memberCountMax = 2, identity = definition.identity,
        memberIdentities = { definition.identity,
            { forename = "Second", surname = "Guard", gender = "male" } } }
    site.memberSpawns = { { x = 10, y = 10, z = 0 },
        { x = 11, y = 10, z = 0 } }
    local stagedGroup = createRealOddballGroup(site, staged, true)
    check(stagedGroup ~= nil, "fixed two-member scene queues clear posts")
    squares["10:10:0"].chair = { name = "Chair" }
    SC.Factions._beginNextSpawnForTests()
    check(#begun == 1 and SC.Factions.group(stagedGroup.id) == stagedGroup
        and stagedGroup.members[1].spawnQueued == false,
        "a fixed scene waits for its obstructed post without spawning elsewhere")
    SC.Factions.reset()
    squares["10:10:0"].chair = nil
    squares["11:10:0"].chair = { name = "Chair" }
    site.memberSpawns = nil
    site.petSpawns = { { x = 11, y = 10, z = 0 },
        { x = 12, y = 10, z = 0 } }
    site.toySpawns = { { x = 10, y = 10, z = 0 },
        { x = 11, y = 10, z = 0 }, { x = 12, y = 10, z = 0 } }
    local milliDefinition = { id = "milli_tea_and_trouble",
        name = "Milli", archetype = "oddball_resident",
        memberCountMin = 1, memberCountMax = 1,
        identity = definition.identity }
    local petPostGroup, petPostReason = createRealOddballGroup(
        site, milliDefinition, true)
    check(petPostGroup == nil and petPostReason == "milli_pet_posts_unavailable",
        "a chair appearing on a pet post invalidates that new scene")
    SC.Actor.beginSpawn = previousBegin
    U.gridSquare, U.squareOccupyingObject = previousGrid, previousOccupying
end
SC_TEST_REPORT = "Oddball foundation PASS: " .. checks .. " checks"
