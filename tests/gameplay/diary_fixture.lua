-- SPDX-License-Identifier: MIT
-- Deterministic globals for the private diary harness. World age hour 0 is
-- 9 July 1993, 07:00, as in a default Build 42 start.

function require() return true end

SC_TEST_CLOCK = 1000
function getTimestampMs() return SC_TEST_CLOCK end
function isClient() return false end
function isServer() return false end
function instanceof(value, className)
    return type(value) == "table" and value.__class == className
end

CharacterTrait = { ILLITERATE = { name = "ILLITERATE" } }

DIARY_TEST_HOURS = 3

local MONTH_DAYS = { 31, 31, 30, 31, 30, 31 }

function DIARY_TEST_CALENDAR(hours)
    local absolute = (hours or DIARY_TEST_HOURS) + 8 * 24 + 7
    local dayIndex = math.floor(absolute / 24)
    local hour = math.floor(absolute - dayIndex * 24)
    local month, day, index = 6, dayIndex, 1
    while day >= MONTH_DAYS[index] do
        day = day - MONTH_DAYS[index]
        month = month + 1
        index = index + 1
    end
    return 1993, month, day, hour
end

function getGameTime()
    return {
        getWorldAgeHours = function() return DIARY_TEST_HOURS end,
        getYear = function() local year = DIARY_TEST_CALENDAR() return year end,
        getMonth = function() local _, month = DIARY_TEST_CALENDAR() return month end,
        getDay = function() local _, _, day = DIARY_TEST_CALENDAR() return day end,
        getHour = function() local _, _, _, hour = DIARY_TEST_CALENDAR() return hour end,
    }
end
