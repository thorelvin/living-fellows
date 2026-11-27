-- SPDX-License-Identifier: MIT

-- Run the game's real PZAPI.ModOptions implementation against an in-memory
-- ModOptions.ini so the adapter is tested without touching the player's file.
LivingFellows = { Gestures = { nativeOptionApplies = 0 } }
function LivingFellows.Gestures.applyNativeOptions()
    local gestures = LivingFellows.Gestures
    gestures.nativeOptionApplies = gestures.nativeOptionApplies + 1
    return true
end
SCBridge = { calls = {}, comfortCalls = {} }
function SCBridge.setProtectRecruitedCompanions(enabled)
    SCBridge.calls[#SCBridge.calls + 1] = enabled
    return true
end
function SCBridge.setCompanionComfortOptions(mode, ordinaryColds)
    SCBridge.comfortCalls[#SCBridge.comfortCalls + 1] = {
        mode = mode,
        ordinaryColds = ordinaryColds,
    }
    return true
end

function require(name)
    assert(name == "SCNamespace" or name == "PZAPI/ModOptions", name)
    return true
end

function getText(key) return key end

local diskLines = {
    "combobox|LivingFellows|chatter|3",
    "combobox|LivingFellows|coughSneezes|2",
    "tickbox|LivingFellows|ordinaryColds|false",
    "tickbox|LivingFellows|protectRecruitedCompanions|true",
    "tickbox|LivingFellows|banditsCompatibility|false",
    "tickbox|LivingFellows|alifeCompatibility|false",
    "combobox|SurvivorCompanion|chatter|2",
    "combobox|SurvivorCompanion|terminalLamp|2",
    "combobox|SurvivorCompanion|speechColors|99",
    "tickbox|SurvivorCompanion|alifeCompatibility|true",
    "tickbox|SurvivorCompanion|pzOptimizerCompatibility|false",
    "tickbox|AnotherMod|enabled|false",
}

function getFileReader(name)
    assert(name == "ModOptions.ini")
    local index = 0
    return {
        readLine = function()
            index = index + 1
            return diskLines[index]
        end,
        close = function() end,
    }
end

function getFileWriter(name)
    assert(name == "ModOptions.ini")
    diskLines = {}
    return {
        write = function(_, line)
            diskLines[#diskLines + 1] = string.gsub(line, "\r\n$", "")
        end,
        close = function() end,
    }
end

luautils = {}
function luautils.split(source, delimiter)
    local parts = {}
    local start = 1
    while true do
        local index = string.find(source, delimiter, start, true)
        if index == nil then
            parts[#parts + 1] = string.sub(source, start)
            return parts
        end
        parts[#parts + 1] = string.sub(source, start, index - 1)
        start = index + string.len(delimiter)
    end
end

function SC_TEST_MOD_OPTIONS_DISK() return diskLines end
function SC_TEST_SET_MOD_OPTIONS_DISK(lines) diskLines = lines end
