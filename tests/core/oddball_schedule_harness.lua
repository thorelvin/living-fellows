-- SPDX-License-Identifier: MIT

local SC, checks = SurvivorCompanion, 0
local O, U, F = SC.Oddballs, SC.GameplayUtil, SC.Factions
local function check(value, message)
    checks = checks + 1
    assert(value, "oddball schedule check " .. checks .. ": " .. message)
end

-- Load the real config after the lifecycle fixture so this covers the shipped
-- default as well as the scheduler's fallback. Other fixture settings stay local.
check(SC.Config.defaults.oddballFirstEligibleDay == 1,
    "the shipped first eligible world day is zero-based day one")
local configured = SC.Config.get
local overrides = { oddballsEnabled = true, oddballMaxActive = 2,
    oddballScanSampleBudget = 1 }
local omitFirstDay = false
SC.Config.get = function(section, key)
    if key == nil then
        if section == "oddballFirstEligibleDay" and omitFirstDay then return nil end
        if overrides[section] ~= nil then return overrides[section] end
    end
    return configured(section, key)
end

local hours, roomName, created = 0, "spiffos", {}
function getGameTime()
    return { getWorldAgeHours = function() return hours end }
end
local player = { x = 100, y = 100, z = 0, getPlayerNum = function() return 0 end }
local room = { getName = function() return roomName end }
local building = {}
U.position = function(value) return value and value.x, value and value.y, value and value.z end
U.canSee = function() return false end
U.isSafeSpawnSquare = function(square) return square ~= nil end
U.isClearActorSpawnSquare = function(square) return square ~= nil end
U.gridSquare = function(x, y, z)
    if z ~= 0 then return nil end
    return { x = x, y = y, z = z, getRoom = function() return room end,
        getBuilding = function() return building end, isCanSee = function() return false end }
end
F.list = function() return {} end
F.oddballHouseAt = function(square)
    local point = { x = square.x, y = square.y, z = 0 }
    return { id = "schedule-house", anchor = point,
        bounds = { x1 = square.x, y1 = square.y, x2 = square.x + 2, y2 = square.y + 2 },
        interior = { point }, openings = {} }
end
F.createOddballGroup = function(site, definition)
    local group = { id = "schedule-" .. definition.id,
        oddball = { id = definition.id, site = site } }
    created[#created + 1] = group
    return group
end

local function pulse()
    SC_TEST_CLOCK = SC_TEST_CLOCK + 30001
    return O.pulse(player, SC_TEST_CLOCK)
end
local function fresh(worldHours, name)
    O.reset()
    hours, roomName, created = worldHours, name or "spiffos", {}
end

-- Host milliseconds deliberately disagree with the game clock in both directions.
-- Eligibility belongs to elapsed world hours, not the operating system clock.
fresh(23.999)
SC_TEST_CLOCK = 1000000000000
local admitted, reason = pulse()
check(admitted == false and reason == "first_day_not_reached" and #created == 0,
    "23.999 world hours remain blocked despite a large host timestamp")
fresh(24)
SC_TEST_CLOCK = 0
admitted, reason = pulse()
check(admitted == true and #created == 1
    and created[1].oddball.id == "window_spiffo_kevin",
    "exactly 24 world hours admit the first suitable encounter: " .. tostring(reason))
fresh(48)
admitted, reason = pulse()
check(admitted == true and #created == 1,
    "48 world hours remain eligible: " .. tostring(reason))

omitFirstDay = true
fresh(23.999)
admitted, reason = pulse()
check(admitted == false and reason == "first_day_not_reached",
    "missing first-day config keeps the 24-hour lower boundary")
fresh(24)
admitted, reason = pulse()
check(admitted == true and #created == 1,
    "missing first-day config falls back to the second day: " .. tostring(reason))
omitFirstDay = false

-- Existing explicit config values keep their zero-based world-day semantics.
overrides.oddballFirstEligibleDay = 0
fresh(0)
admitted, reason = pulse()
check(admitted == true and #created == 1,
    "an explicit day-zero override still permits the first day: " .. tostring(reason))
overrides.oddballFirstEligibleDay = 2
fresh(24)
admitted, reason = pulse()
check(admitted == false and reason == "first_day_not_reached",
    "an explicit day-two override still waits through world hour 24")
fresh(48)
admitted, reason = pulse()
check(admitted == true and #created == 1,
    "an explicit day-two override retains its 48-hour boundary: " .. tostring(reason))
overrides.oddballFirstEligibleDay = nil

-- Gale's three additional days retain their zero-based meaning when the global
-- start moves earlier: day one plus three means eligibility at world hour 96.
check(O.definition("grocery_gale_mercer").firstEligibleOffsetDays == 3,
    "Gale retains his authored three-day offset")
fresh(95.999, "grocery")
admitted, reason = pulse()
check(admitted == false and reason == "no_eligible_loaded_site" and #created == 0,
    "a valid later character waits until its own offset: " .. tostring(reason))
fresh(96, "grocery")
admitted, reason = pulse()
check(admitted == true and #created == 1
    and created[1].oddball.id == "grocery_gale_mercer",
    "a later character unlocks at global day one plus its offset: " .. tostring(reason))

-- A completed spawn starts the saved cooldown. Reconstruct the subsystem with
-- no faction groups so this assertion depends on the saved ledger itself.
fresh(24)
admitted = pulse()
check(admitted == true and O.spawned(created[1], nil) == true,
    "the first successful spawn is recorded")
local document = O.export()
check(document.lastSeedDay == 1 and document.seeded.window_spiffo_kevin.day == 1,
    "the ledger records the world day rather than the host timestamp")
O.reset()
check(O.restore(document) == true, "the saved cooldown ledger restores")
hours, roomName, created = 95.999, "grocery", {}
admitted, reason = pulse()
check(admitted == false and reason == "oddball_cooldown" and #created == 0,
    "reload preserves the three-day wait before world hour 96")
hours = 96
admitted, reason = pulse()
check(admitted == true and #created == 1
    and created[1].oddball.id == "grocery_gale_mercer",
    "the restored cooldown expires at the original world-day boundary: " .. tostring(reason))
check(O.export().seeded.window_spiffo_kevin ~= nil,
    "admitting the next encounter preserves the first character's unique seed")

-- A save predating Strange Folk has no ledger. Its existing world age applies;
-- installing the subsystem does not start a new 24-hour grace period.
fresh(30 * 24)
check(O.restore(nil) == true, "an older save can initialize its missing ledger")
admitted, reason = pulse()
check(admitted == true and #created == 1,
    "an older eligible world needs no additional install grace: " .. tostring(reason))

SC_TEST_REPORT = "Oddball schedule PASS: " .. checks .. " checks"
