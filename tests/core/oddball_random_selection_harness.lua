-- SPDX-License-Identifier: MIT

local SC, checks = SurvivorCompanion, 0
local O, U, F = SC.Oddballs, SC.GameplayUtil, SC.Factions
local function check(value, message)
    checks = checks + 1
    assert(value, "oddball random selection check " .. checks .. ": " .. message)
end

local KEVIN, CLEM, LORETTA = "window_spiffo_kevin", "duelist_clem_sutter",
    "loretta_ten_and_two"
local player = { x = 100, y = 100, z = 0, getPlayerNum = function() return 0 end }
local room = { getName = function() return "clothingstore" end }
local buildings, groups, created, draws, counters
local loaded, vehicleAvailable, vehicleSqlId, factoryFailures, afterDraw, chooseLast
local work, houseCalls, vehicleCalls
local originalRandom, originalMathRandom = ZombRand, math.random
local originalGameTime = getGameTime

U.position = function(value)
    return value and value.x, value and value.y, value and value.z or 0
end
U.canSee = function() return false end
U.isSafeSpawnSquare = function(square) return square ~= nil end
U.isClearActorSpawnSquare = U.isSafeSpawnSquare
U.gridSquare = function(x, y, z)
    if not loaded or z ~= 0 then return nil end
    local key = x .. ":" .. y
    buildings[key] = buildings[key] or {}
    local building = buildings[key]
    -- Return a fresh wrapper on every lookup, as streaming can do between slices.
    return { x = x, y = y, z = z,
        getRoom = function() return room end,
        getBuilding = function() return building end,
        isCanSee = function() return false end }
end
F.list = function() return groups end
F.group = function(id)
    for _, group in ipairs(groups) do if group.id == id then return group end end
end
F.oddballHouseAt = function(square)
    houseCalls = houseCalls + 1
    if not loaded or not square then return nil end
    local post = { x = square.x, y = square.y, z = square.z }
    return { id = "random-shop:" .. square.x .. ":" .. square.y,
        anchor = post,
        bounds = { x1 = square.x, y1 = square.y,
            x2 = square.x + 2, y2 = square.y + 2 },
        interior = { post },
        openings = { { kind = "door", x = square.x, y = square.y, z = square.z } } }
end
F.createOddballGroup = function(site, definition)
    created[#created + 1] = { id = definition.id, site = site }
    if factoryFailures[definition.id] then return nil, "injected_factory_failure" end
    return { id = "random-group:" .. definition.id,
        lifecycle = "settled", oddball = { id = definition.id, site = site } }
end
SC.Actor.checkBridge = function() return true end
SC.Registry.byId = function() return nil end
SC.Performance = { count = function(name)
    counters[name] = (counters[name] or 0) + 1
    if string.find(name, "oddball_background_", 1, true) == 1 then work = work + 1 end
end }
SC.OddballLoretta = { siteFor = function()
    vehicleCalls = vehicleCalls + 1
    if not loaded or not vehicleAvailable then return nil end
    local post = { x = 150, y = 100, z = 0 }
    return { kind = "resident", anchor = post, spawn = post, carSqlId = vehicleSqlId,
        seat = 0, vehicle = { sqlId = vehicleSqlId, seat = 0, door = post },
        house = { id = "loretta-car-" .. vehicleSqlId, anchor = post,
            bounds = { x1 = 149, y1 = 99, x2 = 151, y2 = 101 },
            interior = { post }, openings = {} } }
end }

local forcedIndex
local function randomIndex(count)
    check(type(count) == "number" and count >= 1, "RNG receives a nonempty type pool")
    draws[#draws + 1] = count
    if afterDraw then afterDraw(#draws) end
    if forcedIndex ~= nil then return math.min(forcedIndex, count - 1) end
    return chooseLast and count - 1 or 0
end
ZombRand = randomIndex
getGameTime = nil

local function reset(ageDays, samples)
    O.reset()
    buildings, groups, created, draws, counters = {}, {}, {}, {}, {}
    loaded, vehicleAvailable, vehicleSqlId, factoryFailures = true, false, 741, {}
    afterDraw, chooseLast, forcedIndex = nil, false, nil
    work, houseCalls, vehicleCalls = 0, 0, 0
    SC_TEST_CLOCK = (ageDays or 0) * 86400000
    SC.Config.testSet("oddballsEnabled", true)
    SC.Config.testSet("oddballFirstEligibleDay", 0)
    SC.Config.testSet("oddballEncounterDays", 3)
    SC.Config.testSet("oddballMaxActive", 2)
    SC.Config.testSet("oddballScanSampleBudget", samples or 12)
end
local function pulse()
    return O.pulse(player, SC_TEST_CLOCK)
end
local function chosen()
    return #created > 0 and created[#created].id or nil
end
local function restoreLedger(change)
    local document = O.export()
    change(document)
    check(O.restore(document) == true, "test ledger restores through the public contract")
end

-- The same loaded shops support both Kevin and Clem. Controlled opposite RNG
-- results must reach each type, without multiplying its weight by site count.
for _, last in ipairs({ false, true }) do
    reset(0, 12)
    chooseLast = last
    local seeded = pulse()
    check(seeded == true and #created == 1, "one ambient encounter is queued")
    check(chosen() == (last and CLEM or KEVIN), "either eligible shop character can win")
    check(#draws == 1 and draws[1] == 2,
        "many distinct viable shops contribute one pool entry per character")
    check(houseCalls > 2, "selection considers more than the first viable landmark")
end

-- Loretta participates in the same pool on the first admitted scan. Enumerating
-- its three RNG outcomes proves neither car-first priority nor exclusion.
local vehicleWinners, lorettaIndex = {}, nil
for index = 0, 2 do
    reset(4, 6)
    vehicleAvailable, forcedIndex = true, index
    local seeded = pulse()
    check(seeded == true and #created == 1 and draws[1] == 3,
        "car and two building encounters share one three-type draw")
    vehicleWinners[chosen()] = true
    if chosen() == LORETTA then lorettaIndex = index end
    check(vehicleCalls >= 1, "the first admitted scan checks the loaded vehicle")
end
check(vehicleWinners[KEVIN] and vehicleWinners[CLEM] and vehicleWinners[LORETTA],
    "each building and vehicle type can win the shared draw")

reset(4, 6)
vehicleAvailable, forcedIndex = true, lorettaIndex
afterDraw = function() vehicleSqlId = 742 end
check(pulse() == true and #created == 1 and chosen() ~= LORETTA,
    "a different newly loaded car cannot replace Loretta's selected vehicle")

reset(0)
vehicleAvailable = true
check(pulse() == true and draws[1] == 2 and chosen() ~= LORETTA,
    "Loretta's later age requirement excludes her from an earlier pool")

reset(0)
restoreLedger(function(document)
    document.seeded[KEVIN] = { day = 0, groupId = "previous-kevin" }
end)
check(pulse() == true and chosen() == CLEM,
    "a previously seeded character cannot win another encounter")
reset(0)
restoreLedger(function(document) document.retired[CLEM] = "resolved" end)
chooseLast = true
check(pulse() == true and chosen() == KEVIN,
    "a retired character is excluded even when the RNG favors the last entry")
reset(0)
restoreLedger(function(document)
    document.seeded[KEVIN] = { day = 0, groupId = "previous-kevin" }
    document.retired[CLEM] = "resolved"
end)
check(pulse() == false and #draws == 0 and #created == 0,
    "an empty eligible pool does not draw or retry already used characters")

-- Admission failures never consume a random result or reach a factory.
reset(0)
SC.Config.testSet("oddballMaxActive", 0)
local seeded, reason = pulse()
check(seeded == false and reason == "oddball_cap_reached"
    and #draws == 0 and #created == 0, "active cap blocks selection before RNG")
reset(0)
groups[1] = { id = "pending-kevin", lifecycle = "settled",
    oddball = { id = KEVIN }, members = { {} } }
restoreLedger(function(document)
    document.pending = { id = KEVIN, groupId = "pending-kevin" }
end)
seeded, reason = pulse()
check(seeded == false and reason == "oddball_spawn_pending"
    and #draws == 0 and #created == 0, "pending native spawn blocks another selection")
reset(2)
restoreLedger(function(document) document.lastSeedDay = 1 end)
seeded, reason = pulse()
check(seeded == false and reason == "oddball_cooldown"
    and #draws == 0 and #created == 0, "encounter cooldown blocks selection before RNG")

-- Native spawn polling runs before a suspended ambient scan resumes. A debug
-- encounter can therefore finish and clear pending while the old pool exists;
-- its newly recorded cooldown must still prevent that pool from committing.
reset(0)
local scanMore
seeded, reason, scanMore = O.pulse(player, SC_TEST_CLOCK, function()
    return houseCalls < 2 and 1 or 0
end)
check(scanMore == true and houseCalls >= 2 and #draws == 0 and #created == 0,
    "the interleaving fixture suspends after discovering both shop types")
groups[1] = { id = "interleaved-native-kevin", lifecycle = "settled",
    oddball = { id = KEVIN }, members = {} }
check(O.spawned(groups[1], nil) == true,
    "an independently completed native spawn records its day during suspension")
seeded, reason, scanMore = O.pulse(player, SC_TEST_CLOCK)
check(seeded == false and reason == "oddball_cooldown" and scanMore == false
    and #draws == 0 and #created == 0,
    "a cooldown established during suspension cancels the old pool before RNG")

reset(0)
seeded, reason, scanMore = O.pulse(player, SC_TEST_CLOCK, function()
    return houseCalls < 2 and 1 or 0
end)
check(scanMore == true and houseCalls >= 2 and #draws == 0 and #created == 0,
    "provider failure fixture suspends with gathered candidates")
SC.Actor.checkBridge = function() return false, "injected_provider_failure" end
seeded, reason, scanMore = O.pulse(player, SC_TEST_CLOCK)
SC.Actor.checkBridge = function() return true end
check(seeded == false and reason == "actor_provider_unavailable" and scanMore == false
    and #draws == 0 and #created == 0,
    "losing the native provider during suspension cancels selection before RNG")

-- A world change between discovery and commit invalidates cached candidates.
-- The chosen site must be loaded and checked again before the factory runs.
reset(0)
afterDraw = function() loaded = false end
seeded = pulse()
check(seeded == false and #created == 0,
    "a site unloaded during the draw cannot create an encounter from cached data")
check(#draws <= 2, "stale candidates are discarded with bounded attempts")

-- Failed factories draw from the remaining types rather than retrying the same
-- favored character, and exhausting the finite pool ends the scan.
reset(0)
factoryFailures[KEVIN] = true
seeded = pulse()
check(seeded == true and #created == 2
    and created[1].id == KEVIN and created[2].id == CLEM,
    "a failed selected type falls back to a different random candidate")
check(#draws <= 2 and draws[1] == 2,
    "factory fallback is bounded by the number of candidate types")
reset(0)
factoryFailures[KEVIN], factoryFailures[CLEM] = true, true
seeded = pulse()
check(seeded == false and #created == 2 and #draws <= 2,
    "exhausting failed candidate types terminates without replacement")

-- Budget slicing must retain the gathered pool and postpone its sole draw
-- until selection; dozens of continuations must not alter either probability.
reset(0, 12)
chooseLast = true
local calls, more, earlyCommit, rerolled = 0, true, false, false
while more and calls < 5000 do
    calls = calls + 1
    local deadline = work + 3
    seeded, reason, more = O.pulse(player, SC_TEST_CLOCK, function() return deadline - work end)
    if more and #draws == 0 and #created > 0 then earlyCommit = true end
    if #draws > 1 then rerolled = true end
end
check(not earlyCommit and not rerolled,
    "gathering slices neither commit early nor reroll a selected valid pool")
check(more ~= true and calls > 1 and seeded == true
    and chosen() == CLEM and #created == 1 and draws[1] == 2,
    "sliced selection preserves the complete two-type pool and chosen outcome")
check(counters.oddball_background_sample == 12,
    "sliced discovery retains the configured sample bound")

-- The documented fallback also uses the complete pool with Lua's one-based RNG.
reset(0)
ZombRand = nil
math.random = function(count)
    draws[#draws + 1] = count
    return count
end
check(pulse() == true and chosen() == CLEM and draws[1] == 2,
    "math.random fallback can select the last eligible type")
ZombRand, math.random, getGameTime = originalRandom, originalMathRandom, originalGameTime
O.reset()
SC_TEST_REPORT = "ODDBALL_RANDOM_SELECTION_PASS checks=" .. checks
