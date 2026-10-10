-- SPDX-License-Identifier: MIT

-- Run the game's real PZAPI.ModOptions implementation against an in-memory
-- ModOptions.ini so the adapter is tested without touching the player's file.
SurvivorCompanion = { Gestures = { nativeOptionApplies = 0 } }
function SurvivorCompanion.Gestures.applyNativeOptions()
    local gestures = SurvivorCompanion.Gestures
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
    "combobox|SurvivorCompanion|chatter|3",
    "combobox|SurvivorCompanion|coughSneezes|2",
    "tickbox|SurvivorCompanion|ordinaryColds|false",
    "tickbox|SurvivorCompanion|protectRecruitedCompanions|true",
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
