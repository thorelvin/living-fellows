-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end

CharacterStat = { HUNGER = "HUNGER", THIRST = "THIRST", FATIGUE = "FATIGUE" }
local hour, now = 240, 1000
function getGameTime()
    return { getWorldAgeHours = function() return hour end }
end

SurvivorCompanion = SurvivorCompanion or {}
SurvivorCompanion.GameplayUtil = {
    actorState = function(_, runtime) return runtime end,
    characterStatValue = function(actor, name) return actor.values[name] end,
    clamp = function(value, low, high) return math.max(low, math.min(high, value)) end,
    config = function(name)
        if name == "needsRateMultiplier" then return 1 / 3 end
        if name == "needsRateSampleMs" then return 1000 end
        return nil
    end,
    nowMs = function() return now end,
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        return object[method](object, ...), true
    end,
}

local actor = { values = { HUNGER = 0.20, THIRST = 0.20, FATIGUE = 0 } }
local stats = {
    get = function(_, stat) return actor.values[stat] end,
    set = function(_, stat, value) actor.values[stat] = value end,
}
function actor:getStats() return stats end
function actor:isAsleep() return false end

local needs = SurvivorCompanion.Needs
local runtime = {}
check(needs.updateRates(actor, runtime, now), "first needs sample failed")
hour = hour + 4
now = now + 1001
check(needs.updateRates(actor, runtime, now), "idle needs growth failed")
check(math.abs(actor.values.HUNGER - (0.20 + 4 * 0.0000096 * 3600 / 3)) < 0.001,
    "hunger did not grow at one third the player baseline")
check(math.abs(actor.values.THIRST - (0.20 + 4 * 0.0000080 * 3600 / 3)) < 0.001,
    "thirst did not grow at one third the player baseline")

actor.values.HUNGER, actor.values.THIRST = 0.10, 0.09
hour = hour + 1
now = now + 1001
check(needs.updateRates(actor, runtime, now), "food and water sample failed")
check(actor.values.HUNGER == 0.10 and actor.values.THIRST == 0.09,
    "food and water reductions were overwritten")

actor.values.HUNGER = actor.values.HUNGER + 0.05
hour = hour + 1
now = now + 1001
check(needs.updateRates(actor, runtime, now), "native increase sample failed")
check(math.abs(actor.values.HUNGER - (0.10 + 0.05 / 3)) < 0.001,
    "native hunger and game-time growth were counted twice")

actor.isAsleep = function() return true end
local before = actor.values.HUNGER
hour = hour + 1
now = now + 1001
check(needs.updateRates(actor, runtime, now), "sleeping needs sample failed")
check(math.abs(actor.values.HUNGER - (before + 0.0000010 * 3600 / 3)) < 0.001,
    "sleeping hunger should grow at the slower vanilla rate")

actor.isAsleep = function() return false end
MoodleType = { FOOD_EATEN = "FOOD_EATEN" }
function actor:getMoodles()
    return { getMoodleLevel = function() return 1 end }
end
before = actor.values.HUNGER
local beforeThirst = actor.values.THIRST
hour = hour + 1
now = now + 1001
check(needs.updateRates(actor, runtime, now), "well-fed needs sample failed")
check(actor.values.HUNGER == before and actor.values.THIRST > beforeThirst,
    "well-fed hunger pauses while thirst still advances")

SC_TEST_REPORT = "needs rate regression: " .. tostring(checks) .. " checks"
