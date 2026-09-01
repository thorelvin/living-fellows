-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion

local function copy(value, path)
    local result, reason = SC.StableValue.copyStrict(value, {
        maxDepth = 20, maxEntries = 262144, path = path or "$.test",
    })
    assert(result ~= nil, tostring(reason))
    return result
end

local function equal(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] ~= nil then return seen[left] == right end
    seen[left] = right
    for key, value in pairs(left) do
        if not equal(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function rejectedUnchanged(module, candidate, expectedPath, message)
    local before = module.export()
    local accepted, reason = module.restore(candidate)
    local after = module.export()
    check(accepted == false and string.find(tostring(reason), expectedPath, 1, true) ~= nil,
        message .. " reports its exact path: " .. tostring(reason))
    check(equal(after, before), message .. " leaves the prior exported state unchanged")
end

local baseDocument = {
    version = 1,
    activeBaseId = "base:1",
    nextBaseSerial = 2,
    nextZoneSerial = 2,
    nextStorageSerial = 1,
    nextTargetSerial = 1,
    nextJobSerial = 1,
    bases = {
        ["base:1"] = {
            id = "base:1", name = "Integrity Camp", core = { x = 10, y = 10, z = 0 },
            zones = {
                { id = "zone:1", kind = "area", name = "Camp area",
                    x1 = 8, y1 = 8, x2 = 12, y2 = 12, z = 0, createdAt = 100 },
            },
            storages = {}, maintenanceTargets = {}, jobs = {}, completed = {},
            settings = {
                defense = "rotation", workload = "balanced", routines = true,
                autoMaintenance = true,
                stockTargets = { food = 3, water = 2, medical = 1,
                    construction = 2, ammunition = 6 },
            },
            createdAt = 100,
        },
    },
    residents = {
        ["sc-resident"] = { baseId = "base:1", role = "builder", duty = true },
    },
    restrictions = { ["sc-resident"] = "watch" },
    history = { { kind = "base_created", at = 100 } },
}

check(SC.BaseLife.restore(copy(baseDocument)) and SC.BaseLife.active().id == "base:1",
    "one valid base-life document commits")
do
    local malformed = copy(baseDocument)
    malformed.residents["sc-resident"].baseId = "base:missing"
    rejectedUnchanged(SC.BaseLife, malformed,
        "$.baseLife.residents[sc-resident].baseId", "malformed resident")
end
do
    local malformed = copy(baseDocument)
    malformed.restrictions["sc-resident"] = "banished"
    rejectedUnchanged(SC.BaseLife, malformed,
        "$.baseLife.restrictions[sc-resident]", "malformed restriction")
end
do
    local malformed = copy(baseDocument)
    malformed.history = { [2] = { kind = "gap", at = 200 } }
    rejectedUnchanged(SC.BaseLife, malformed,
        "$.baseLife.history", "sparse base history")
end
do
    local malformed = copy(baseDocument)
    malformed.history[1] = "not a record"
    rejectedUnchanged(SC.BaseLife, malformed,
        "$.baseLife.history[1]", "malformed base history entry")
end

local crisisDocument = {
    version = 1, nextSerial = 2,
    crises = {
        ["crisis:1"] = {
            id = "crisis:1", subjectId = "sc-resident", subjectName = "Morgan",
            phase = "discovered", strategy = "confess", outcome = nil,
            createdAt = 100, updatedAt = 100, irreversibleAfter = 200,
            deliberateAfter = 300, biteCount = 1, infectionLevel = 30,
            participants = {
                ["sc-resident"] = { knowledge = "confirmed", certainty = 100,
                    stance = nil, choice = nil, spoken = false },
            },
            evidence = {
                { kind = "bite", observerId = "sc-resident", certainty = 100,
                    at = 100, details = "new bite" },
            },
            artifacts = {}, finalAuthorized = false,
        },
    },
    observations = {
        ["sc-resident"] = { bites = 1, infected = true,
            infectionLevel = 30, seenAt = 100 },
    },
    history = { { kind = "created", at = 100, crisisId = "crisis:1" } },
}

check(SC.InfectionCrisis.restore(copy(crisisDocument))
        and SC.InfectionCrisis.summary().active == 1,
    "one valid infection-crisis document commits")
do
    local malformed = copy(crisisDocument)
    malformed.crises["crisis:1"].participants["sc-resident"].knowledge = "maybe"
    rejectedUnchanged(SC.InfectionCrisis, malformed,
        "$.infectionCrisis.crises[crisis:1].participants[sc-resident].knowledge",
        "malformed crisis participant")
end
do
    local malformed = copy(crisisDocument)
    malformed.crises["crisis:1"].evidence = {
        [2] = copy(crisisDocument.crises["crisis:1"].evidence[1]),
    }
    rejectedUnchanged(SC.InfectionCrisis, malformed,
        "$.infectionCrisis.crises[crisis:1].evidence", "sparse crisis evidence")
end

local communityDocument = {
    version = 2,
    minds = {
        ["sc-resident"] = {
            id = "sc-resident", stressResponse = "restless", joyResponse = "focused",
            impatience = 55, boredom = 12,
            thoughts = {
                { key = "memory:1", kind = "worked", text = "We fixed the wall.",
                    stress = -1, morale = 3, at = 100, expiresAt = 500,
                    sourceId = "sc-resident", targetId = "", memoryId = "memory:1" },
            },
            expectations = {
                { kind = "supply_run", madeAt = 100, dueAt = 500, status = "pending" },
            },
            grief = {
                { subjectId = "sc-dead", subjectName = "Glenn", startedAt = 100,
                    acuteUntil = 200, recoveryAt = 400, intensity = 80,
                    witnessed = true, reactionPending = true, nextReactionAt = 100,
                    reactedAt = 0, resolvedAt = 0 },
            },
            lastEvaluatedAt = 100, criticalSince = 0, hopefulSince = 0,
            nextMinorAt = 200, nextMajorAt = 300, nextJoyAt = 400,
            nextPurposeAt = 500, lastSupplyRequestAt = 100,
            activeEpisode = nil, inspiration = nil, pendingRequest = nil,
            stressTarget = 20, moraleTarget = 60,
        },
    },
    pairs = {
        ["sc-resident|sc-two"] = {
            id = "sc-resident|sc-two", firstId = "sc-resident", secondId = "sc-two",
            opinion = 5, trust = 10, tension = 2, familiarity = 20,
            lastInteractionAt = 100, memories = { { id = "shared:1", at = 100 } },
        },
    },
    history = { { id = "community:1", kind = "worked", at = 100 } },
    deaths = {
        ["sc-dead"] = { subjectId = "sc-dead", subjectName = "Glenn", startedAt = 100 },
    },
    groupMajorCooldownUntil = 0, groupJoyCooldownUntil = 0,
    lastSupplyRunAt = 100, activeRun = nil, playerAtBase = nil,
}

check(SC.Community.restore(copy(communityDocument))
        and SC.Community.peekMind("sc-resident") ~= nil,
    "one valid community document commits")
do
    local malformed = copy(communityDocument)
    malformed.minds["sc-resident"].thoughts[1].text = nil
    rejectedUnchanged(SC.Community, malformed,
        "$.community.minds[sc-resident].thoughts[1]", "malformed community mind")
end
do
    local malformed = copy(communityDocument)
    malformed.pairs["sc-resident|sc-two"].id = "wrong-pair"
    rejectedUnchanged(SC.Community, malformed,
        "$.community.pairs[sc-resident|sc-two]", "malformed community pair")
end
do
    local malformed = copy(communityDocument)
    malformed.deaths["sc-dead"].subjectId = "sc-someone-else"
    rejectedUnchanged(SC.Community, malformed,
        "$.community.deaths[sc-dead]", "malformed community death")
end
do
    local malformed = copy(communityDocument)
    malformed.history = { [2] = { id = "gap", kind = "worked", at = 200 } }
    rejectedUnchanged(SC.Community, malformed,
        "$.community.history", "sparse community history")
end

local function factionGroup(id, memberKey, x)
    return {
        id = id, archetype = "barricaded_household", name = "Household " .. id,
        lifecycle = "settled", standing = "Tolerated", reputation = 10,
        discovered = true, barterUnlocked = false, permanentHostility = false,
        shortageKind = "food",
        house = {
            id = tostring(x) .. ":1:" .. tostring(x + 3) .. ":4",
            bounds = { x1 = x, y1 = 1, x2 = x + 3, y2 = 4, z = 0 },
            anchor = { x = x + 1, y = 2, z = 0 },
            interior = { { x = x + 1, y = 2, z = 0 } },
            openings = { { x = x, y = 2, z = 0, objectIndex = 0, kind = "door" } },
            primaryEntry = { x = x, y = 2, z = 0, objectIndex = 0, kind = "door" },
        },
        members = {
            { key = memberKey, role = "leader", identity = {
                forename = "Test", surname = memberKey, gender = "male",
            }, alive = true, hibernated = false },
        },
        jobs = {}, offenses = {}, history = {},
        request = { kind = "food", status = "available", rewardReserved = true,
            required = { { category = "food", count = 1 } }, reward = {} },
    }
end

local factionDocument = {
    schema = 1, sequence = 2, lastWorldSpawnDay = 1, lastProductionCheckDay = 1,
    order = { "faction-a", "faction-b" },
    groups = {
        ["faction-a"] = factionGroup("faction-a", "member-a", 1),
        ["faction-b"] = factionGroup("faction-b", "member-b", 10),
    },
}

check(SC.Factions.restore(copy(factionDocument)) and #SC.Factions.list(false) == 2,
    "one valid faction document commits")
check(SC.FactionWorld.reconcile()
        and SC.FactionWorld.relation("faction-a", "faction-b") ~= nil,
    "dependent world graph is established for the valid factions")

local function rejectedFactionsUnchanged(candidate, expectedPath, message)
    local beforeFactions, beforeWorld = SC.Factions.export(), SC.FactionWorld.export()
    local accepted, reason = SC.Factions.restore(candidate)
    check(accepted == false and string.find(tostring(reason), expectedPath, 1, true) ~= nil,
        message .. " reports its exact path: " .. tostring(reason))
    check(equal(SC.Factions.export(), beforeFactions),
        message .. " leaves faction state unchanged")
    check(equal(SC.FactionWorld.export(), beforeWorld),
        message .. " leaves dependent world state unchanged")
end

do
    local malformed = copy(factionDocument)
    malformed.order = { [2] = "faction-a", [3] = "faction-b" }
    rejectedFactionsUnchanged(malformed, "$.factions.order", "sparse faction order")
end
do
    local malformed = copy(factionDocument)
    malformed.order = { "faction-a", "faction-a" }
    rejectedFactionsUnchanged(malformed, "$.factions.order[2]", "duplicate faction order id")
end
do
    local malformed = copy(factionDocument)
    malformed.order = { "faction-a" }
    rejectedFactionsUnchanged(malformed, "$.factions.groups[faction-b]",
        "group absent from faction order")
end
do
    local malformed = copy(factionDocument)
    malformed.groups["faction-a"].house.interior = {
        [2] = { x = 2, y = 2, z = 0 },
    }
    rejectedFactionsUnchanged(malformed,
        "$.factions.groups[faction-a].house.interior", "sparse faction interior")
end

local validWorld = SC.FactionWorld.export()
check(SC.FactionWorld.restore(copy(validWorld)), "one valid faction-world document commits")
do
    local malformed = copy(validWorld)
    malformed.news = {
        [2] = { id = "world-news-1", kind = "shared_warning", hour = 10,
            leftId = "faction-a", rightId = "faction-b", delta = 5,
            status = "Neutral", message = "Warning shared.", known = true },
    }
    rejectedUnchanged(SC.FactionWorld, malformed,
        "$.factionWorld.news", "sparse faction-world news")
end
do
    local malformed = copy(validWorld)
    malformed.relations["faction-a|faction-b"].rightId = "faction-missing"
    rejectedUnchanged(SC.FactionWorld, malformed,
        "$.factionWorld.relations[faction-a|faction-b]", "orphaned world relation")
end

print("Subsystem restore integrity harness PASS: " .. tostring(checks) .. " checks")
