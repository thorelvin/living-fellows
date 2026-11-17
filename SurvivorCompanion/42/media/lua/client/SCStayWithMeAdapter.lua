-- SPDX-License-Identifier: MIT

-- Optional, read-only identity boundary for Stay With Me (Workshop 3800989007,
-- mod Bridge). Its companions use IsoZombie bodies, but are always protected
-- people to LF. No foreign AI, damage model or navigation is replaced.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.StayWithMeAdapter = SC.StayWithMeAdapter or {}
local Adapter = SC.StayWithMeAdapter
local modPresent
local recognized = setmetatable({}, { __mode = "k" })

local function call(actor, key, ...)
    local okay, callback
    if SC.Call and type(SC.Call.resolve) == "function" then
        okay, callback = SC.Call.resolve(actor, key)
    else
        okay, callback = pcall(function() return actor[key] end)
    end
    if not okay or type(callback) ~= "function" then return nil end
    local success, value = pcall(callback, actor, ...)
    if success then return value, true end
end

local function api(owner, key, actor)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return false end
    local okay, value = pcall(owner[key], actor)
    return okay and value == true
end

function Adapter.owns(actor)
    if modPresent == false or (type(actor) ~= "table" and type(actor) ~= "userdata") then
        return false
    end
    -- Read live identity before the dependency's cached APIs: a normal zombie
    -- can become a companion in the same frame. Never retain ownership after
    -- SWM clears its markers and releases/recycles a body.
    local owned = call(actor, "getVariableBoolean", "NotAloneBody") == true
        or call(actor, "getVariableBoolean", "SWMSeatPuppet") == true
    if not owned and call(actor, "hasModData") ~= false then
        local data = call(actor, "getModData")
        owned = type(data) == "table" and data.notAloneBody == true
    end
    if not owned then
        owned = type(Bridge) == "table" and Bridge.body == actor
            or api(Bridge, "isCompanion", actor)
            or api(BridgeServer, "isCompanionBody", actor)
            or api(BridgeSeatPuppet, "is", actor)
    end
    if owned then recognized[actor] = true end
    return owned == true
end

function Adapter.relationship(actor)
    return Adapter.owns(actor) and "neutral" or "unknown"
end

function Adapter.initialize()
    -- Absence is cached only after the game provides an authoritative list.
    -- Marked actors remain protected during early/partial Lua startup.
    local okay, mods = pcall(function()
        return type(getActivatedMods) == "function" and getActivatedMods() or nil
    end)
    if okay and mods ~= nil then
        local plain, plainOkay = call(mods, "contains", "Bridge")
        local qualified, qualifiedOkay = call(mods, "contains", "\\Bridge")
        if plainOkay and qualifiedOkay then
            modPresent = plain == true or qualified == true
        else modPresent = nil end
    else
        modPresent = nil
    end
    return modPresent == true
end

function Adapter.status()
    local count = 0
    for _ in pairs(recognized) do count = count + 1 end
    return { state = modPresent == false and "absent"
            or modPresent == true and "active" or "pending",
        active = modPresent == true, recognized = count,
        profile = "Stay With Me/0.6.5",
        reason = modPresent == false and "Stay With Me is not enabled"
            or "Stay With Me bodies are protected from LF attacks" }
end

function Adapter.reset()
    modPresent = nil
    recognized = setmetatable({}, { __mode = "k" })
end

return Adapter
