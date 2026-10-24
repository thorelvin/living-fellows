-- SPDX-License-Identifier: MIT

local SC, checks = SurvivorCompanion, 0
local O, U, F = SC.Oddballs, SC.GameplayUtil, SC.Factions
local function check(value, message)
    checks = checks + 1
    assert(value, "oddball budget check " .. checks .. ": " .. message)
end
local player = { x = 100, y = 100, z = 0, getPlayerNum = function() return 0 end }
local fake, counters, probes, records, groups = 0, {}, {}, {}, {}
local oldPerformance = SC.Performance
SC.Performance = { count = function(name)
    counters[name] = (counters[name] or 0) + 1
    if string.find(name, "oddball_background_", 1, true) == 1 then fake = fake + 1 end
end }
U.position = function(value) return value and value.x, value and value.y, value and value.z or 0 end
U.isValidActor = function(actor) return actor ~= nil end
U.isClearActorSpawnSquare = function() return false end
U.canSee = function() return false end
U.gridSquare = function(x, y, z)
    probes[#probes + 1] = x .. ":" .. y .. ":" .. z
    return { x = x, y = y, z = z,
        getRoom = function() return { getName = function() return "no_story_room" end } end }
end
SC.Registry.byId = function(id) return records[id] end
local oldList, oldGroup = F.list, F.group
F.list = function() return groups end
F.group = function(id)
    for _, group in ipairs(groups) do if group.id == id then return group end end
end
SC.Actor.checkBridge = function() return true end
SC.Config.testSet("oddballsEnabled", true)
SC.Config.testSet("oddballFirstEligibleDay", 0)
SC.Config.testSet("oddballMaxActive", 2)
SC.Config.testSet("oddballScanSampleBudget", 96)
SC_TEST_CLOCK = 15 * 86400000
local function budget(units)
    local deadline = fake + units
    return function() return deadline - fake end
end
local function drain(callback, units)
    local more, result, reason, calls = true, nil, nil, 0
    while more and calls < 5000 do
        calls = calls + 1
        result, reason, more = callback(budget(units or 5))
    end
    check(more ~= true, "small positive slices eventually complete: " .. tostring(reason))
    return result, reason, calls
end
local function reset()
    O.reset()
    fake, counters, probes = 0, {}, {}
end

-- Compare actual square-probe order, not just a loop counter: a yield within
-- the archetype loop must retain both the sample and its exact scan serial.
reset()
local result, reason = O.pulse(player, SC_TEST_CLOCK)
check(result == false and reason == "no_eligible_loaded_site", "synchronous scan still completes")
local expected, expectedArchetypes = probes, counters.oddball_background_archetype or 0
reset()
local _, _, more = O.pulse(player, SC_TEST_CLOCK, budget(4))
check(more == true and (counters.oddball_background_sample or 0) < 96,
    "first short slice yields rather than executing all samples")
check(expectedArchetypes > 96,
    "reference fixture exercises multiple archetypes per loaded square")
local firstProbes, firstArchetypes = #probes, counters.oddball_background_archetype or 0
O.pulse(player, SC_TEST_CLOCK + 1, budget(4))
check(#probes == firstProbes + 1 and probes[#probes] == probes[#probes - 1]
    and (counters.oddball_background_archetype or 0) > firstArchetypes,
    "archetype continuation revalidates the current square without resampling")
local _, scanReason, calls = drain(function(remaining)
    return O.pulse(player, SC_TEST_CLOCK + 2, remaining)
end)
local distinctProbes = {}
for _, position in ipairs(probes) do
    if distinctProbes[#distinctProbes] ~= position then distinctProbes[#distinctProbes + 1] = position end
end
check(calls > 1 and scanReason == "no_eligible_loaded_site" and #distinctProbes == #expected,
    "continuation bypasses scan throttle and finishes exactly the reference sample count")
for index, position in ipairs(expected) do
    check(distinctProbes[index] == position, "resumed reference square order " .. index)
end
check(counters.oddball_background_sample == 96
    and counters.oddball_background_archetype == expectedArchetypes,
    "resumed scan neither skips nor repeats sample/archetype work")

-- Restore while suspended abandons the old square/archetype cursor.
reset()
O.pulse(player, SC_TEST_CLOCK, budget(4))
local document = O.export()
check(O.restore(document) == true, "saved unique ledger restores during a scan")
fake, counters, probes = 0, {}, {}
drain(function(remaining) return O.pulse(player, SC_TEST_CLOCK, remaining) end)
check(counters.oddball_background_sample == 96 and probes[1] == expected[1],
    "restore starts a fresh scan cursor")

-- A change of floor invalidates a snapshot instead of spawning at stale origin.
reset()
O.pulse(player, SC_TEST_CLOCK, budget(4))
player.z = 1
local moved, movedReason, movedMore = O.pulse(player, SC_TEST_CLOCK + 1, budget(4))
check(moved == false and movedReason == "oddball_search_moved" and movedMore == false,
    "moved player cancels the staged old-floor scan")
player.z = 0

-- Recruited callbacks run once per group, even if their work consumes a slice.
reset()
local recruitedCalls = {}
SC.OddballRed = { pulseRecruited = function(group)
    recruitedCalls[group.id] = (recruitedCalls[group.id] or 0) + 1
    fake = fake + 2
    return true
end }
for index = 1, 4 do
    local id = "budget-recruit:" .. index
    groups[index] = { id = id, lifecycle = "settled", oddball = { id = "gut_cloaked_red" },
        recruitment = { joinedActorId = id } }
    records[id] = { actor = { id = id }, recruited = true }
end
SC.Config.testSet("oddballsEnabled", false)
drain(function(remaining) return O.pulse(player, SC_TEST_CLOCK, remaining) end, 2)
for _, group in ipairs(groups) do check(recruitedCalls[group.id] == 1,
    "recruited story does not replay across slices: " .. group.id) end
groups = {}
SC.Config.testSet("oddballsEnabled", true)

-- A factory reached after many archetype slices commits the paired unique
-- encounter atomically. Resuming or calling again must not create extra actors.
reset()
local oldCreate, oldHouseAt = F.createOddballGroup, F.oddballHouseAt
local office = { getName = function() return "office" end }
local building, origin, created = {}, nil, {}
U.isClearActorSpawnSquare = function() return true end
U.gridSquare = function(x, y, z)
    if z ~= 0 then return nil end
    return { x = x, y = y, z = z, getRoom = function() return office end,
        getBuilding = function() return building end, isCanSee = function() return false end }
end
F.oddballHouseAt = function(square)
    origin = origin or { x = square.x, y = square.y }
    local dx, dy = square.x - origin.x, square.y - origin.y
    return { id = dx * dx + dy * dy < 100 and "doctor-office" or "rival-office",
        anchor = { x = square.x, y = square.y, z = 0 },
        bounds = { x1 = square.x, y1 = square.y, x2 = square.x + 2, y2 = square.y + 2 },
        interior = { { x = square.x, y = square.y, z = 0 } }, openings = {} }
end
F.createOddballGroup = function(_, definition)
    created[#created + 1] = definition.id
    return { id = "budget-unique:" .. definition.id, oddball = { id = definition.id } }
end
SC.Config.testSet("oddballScanSampleBudget", 1)
local seeded, _, seedCalls = drain(function(remaining)
    return O.pulse(player, SC_TEST_CLOCK, remaining)
end, 2)
check(seeded and seedCalls > 1 and #created == 2
    and created[1] == "doctor_pest" and created[2] == "bluegrass_bolt",
    "yielded scan creates both paired actors exactly once at its final atomic factory")
O.pulse(player, SC_TEST_CLOCK + 1, budget(2))
check(#created == 2, "subsequent pulse does not duplicate the committed encounter")
F.createOddballGroup, F.oddballHouseAt = oldCreate, oldHouseAt
SC.Config.testSet("oddballScanSampleBudget", 96)

-- Successful native kit and scene receipts persist before the next checkpoint.
reset()
local actor = { id = "budget-loretta", inventory = {} }
local member = { actorId = actor.id, oddballKitPending = true, oddballScenePending = true }
local group = { id = "budget-kit", lifecycle = "settled", members = { member },
    oddball = { id = "loretta_ten_and_two" } }
records[actor.id] = { actor = actor }
local added, spawned, storyPulses, radioPulses = 0, 0, 0, 0
U.inventory = function(value) return value.inventory end
U.inventoryItemsDeep = function(value) return value end
U.itemType = function(item) return item.kind end
U.addItem = function(inventory, kind)
    local item = { kind = kind }
    inventory[#inventory + 1] = item
    added, fake = added + 1, fake + 1
    return item
end
SC.OddballLoretta = {
    onSpawn = function() spawned, fake = spawned + 1, fake + 2 return true end,
    pulse = function() storyPulses, fake = storyPulses + 1, fake + 2 return true end,
}
SC.OddballDistressRadio = { pulse = function() radioPulses = radioPulses + 1 end }
local _, _, setupMore = O.pulseGroup(group, player, SC_TEST_CLOCK, budget(2))
check(setupMore and added == 2 and spawned == 0 and member.oddballKitPending == nil
    and member.oddballScenePending == true, "kit receipt saved before yielding ahead of scene")
drain(function(remaining) return O.pulseGroup(group, player, SC_TEST_CLOCK + 1, remaining) end, 2)
check(added == 2 and #actor.inventory == 2 and spawned == 1 and storyPulses == 1 and radioPulses == 1,
    "kit, scene, story and radio each finish once without replay")
check(member.oddballScenePending == nil and group.oddball.kitSeeded == true,
    "completed setup clears saved pending flags")

-- Factions must retain its final delegate phase on the child's explicit pending.
F.list, F.group = oldList, oldGroup
F.reset()
local houseCalls, worldCalls, oddCalls = 0, 0, 0
F.productionPulse = function() houseCalls = houseCalls + 1 return false end
F.banditProductionPulse = function() return false end
SC.FactionWorld = { pulse = function() worldCalls = worldCalls + 1 return false end }
SC.Oddballs = { pulse = function(_, _, remaining)
    check(type(remaining) == "function", "Factions passes remaining budget to Oddballs")
    oddCalls = oddCalls + 1
    return false, "fixture", oddCalls == 1
end }
drain(function(remaining) return F.pulse(player, SC_TEST_CLOCK, remaining) end, 20)
check(houseCalls == 1 and worldCalls == 1 and oddCalls == 2,
    "pending global Oddballs phase resumes without replaying earlier families")

-- Exercise the real registered group's phase, rather than only a direct child
-- call: pending group setup must hold Factions.groupPhase at five.
F.reset()
local room = { getName = function() return "bedroom" end }
U.gridSquare = function(x, y, z)
    return { x = x, y = y, z = z, getRoom = function() return room end }
end
U.isClearActorSpawnSquare = function() return true end
U.isSafeSpawnSquare = function() return true end
U.text = function(_, fallback) return fallback end
U.idOf = function(value) return value and value.id end
local house = { id = "budget-delegate-house", anchor = { x = 10, y = 10, z = 0 },
    bounds = { x1 = 10, x2 = 12, y1 = 10, y2 = 12 },
    interior = { { x = 10, y = 10, z = 0 } }, openings = {} }
local registered, registerReason = F.createOddballGroup({ house = house,
    anchor = house.anchor, spawn = house.anchor, kind = "resident", room = "bedroom" },
    O.definition("gut_cloaked_red"), true)
check(registered ~= nil, "real oddball group registered for phase fixture: " .. tostring(registerReason))
SC.Actor.beginSpawn = function() return {}, "spawn_pending" end
SC.Actor.pollSpawn = function() return nil, "spawn_pending" end
local groupCalls, globalCalls = 0, 0
SC.Oddballs = {
    pulseGroup = function(candidate, _, _, remaining)
        check(candidate == registered and type(remaining) == "function",
            "Factions passes budget and exact group to setup delegate")
        groupCalls = groupCalls + 1
        return false, "setup_pending", groupCalls == 1
    end,
    pulse = function() globalCalls = globalCalls + 1 return false end,
}
drain(function(remaining) return F.pulse(player, SC_TEST_CLOCK, remaining) end, 20)
check(groupCalls == 2 and globalCalls == 1,
    "group continuation stays at its phase before advancing to global discovery")
SC.Oddballs, SC.Performance = O, oldPerformance
O.reset()
SC_TEST_REPORT = "ODDBALL_BUDGET_PASS checks=" .. checks
