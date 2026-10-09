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
    bounds = { x1 = 20, y1 = 20, x2 = 22, y2 = 20 },
    interior = { { x = 20, y = 20, z = 0 },
        { x = 21, y = 20, z = 0 }, { x = 22, y = 20, z = 0 } }, openings = {} }
SC.Factions.oddballHouseAt = function() return stationHouse end
local deputySite = SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, deputy, "policelocker", true)
check(deputySite and deputySite.spawn.x == 20
    and #deputySite.captiveSpawns >= 1
    and deputySite.captiveSpawns[1].x ~= deputySite.spawn.x,
    "deputy stands at the checkpoint while captives begin in distinct cells")
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
local badAnimalIdSave = SC.StableValue.copyStrict(phaseTwoSave,
    { maxDepth = 16, maxEntries = 131072 })
badAnimalIdSave.groups[juneGroup.id].oddball.animals.slots[2].id = 4001
check(SC.Factions.restore(badAnimalIdSave) == false,
    "two named rabbits cannot restore with one native animal ID")
local pyro = SC.Oddballs.definition("pyromaniac_earl_kessler")
check(pyro and pyro.recruitment == true and pyro.kind == "resident",
    "Earl's recruitable resident encounter is registered")
local previousFree = U.isSquareFree
U.isSquareFree = function(square) return square ~= nil end
stationSquares["21:20"], stationSquares["22:20"] = locker, locker
local pyroSite = SC.Oddballs._siteForResidentForTests(
    U.gridSquare(20, 20, 0), player, pyro, "policelocker", true)
check(pyroSite and #pyroSite.fuelPosts == 2
    and pyroSite.fuelPosts[1].x ~= pyroSite.spawn.x,
    "eligible room receives separate visible floor fuel posts")
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
SC_TEST_REPORT = "Oddball foundation PASS: " .. checks .. " checks"
