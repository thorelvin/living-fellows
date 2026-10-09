-- SPDX-License-Identifier: MIT
-- Elmer tells his whole story with profanity on and off. Every line must be
-- spoken either way, and the clean telling must carry no profanity at all,
-- whichever position a line holds.

local SC = SurvivorCompanion
local checks = 0
local function check(condition, message)
    checks = checks + 1
    if not condition then error("Elmer check " .. checks .. ": " .. message, 2) end
end

local profanity = true
local said = {}
local elmer = {}
SC.GameplayUtil = {
    config = function(key)
        if key == "profanityEnabled" then return profanity end
        return nil
    end,
    say = function(_, line)
        said[#said + 1] = line
        return true
    end,
    isValidActor = function(actor) return actor ~= nil end,
    distance = function() return 2 end,
    canSee = function() return true end,
}
SC.Registry = { byId = function(id)
    return id == "elmer" and { actor = elmer } or nil
end }
local trusted = {}
SC.Factions = { forceStanding = function(groupId, standing)
    trusted[groupId] = standing
    return true
end }

local function tell(enabled)
    profanity = enabled
    said = {}
    local group = { id = "elmer-" .. tostring(enabled),
        members = { { actorId = "elmer" } },
        oddball = { id = "man_in_the_chair", stage = "telling", line = 1 } }
    local now = 0
    for _ = 1, 64 do
        SC.OddballElmer.pulse(group, {}, now)
        if group.oddball.stage ~= "telling" then break end
        now = now + 20000
    end
    check(group.oddball.stage == "clear" and trusted[group.id] == "Trusted",
        "the full story must end with Elmer trusting the player")
    return said
end

local profane = { "shit", "damn", "hell", "fuck", "bastard", "bitch", "ass" }
local function swears(line)
    local lower = string.lower(line)
    for _, word in ipairs(profane) do
        if string.find(" " .. lower .. " ", "[^%a]" .. word .. "[^%a]") then
            return true
        end
    end
    return false
end

local raw = tell(true)
local clean = tell(false)
check(#raw >= 10 and #raw == #clean,
    "both tellings must speak every line: " .. #raw .. " vs " .. #clean)
local twins, rawSwears = 0, 0
for index = 1, #raw do
    check(type(raw[index]) == "string" and type(clean[index]) == "string",
        "line " .. index .. " must be spoken as text")
    check(not swears(clean[index]),
        "clean telling swears on line " .. index .. ": " .. tostring(clean[index]))
    if swears(raw[index]) then rawSwears = rawSwears + 1 end
    if raw[index] ~= clean[index] then
        twins = twins + 1
        check(swears(raw[index]),
            "only a profane line may change: line " .. index)
    end
end
check(rawSwears >= 1 and twins == rawSwears,
    "each profane line needs a clean twin: " .. rawSwears .. " profane, "
        .. twins .. " replaced")

SC_TEST_REPORT = "Elmer story PASS: " .. checks .. " checks, " .. #raw
    .. " lines, " .. twins .. " clean twin(s)"
