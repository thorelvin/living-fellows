-- SPDX-License-Identifier: MIT

-- Player preferences live in the game's built-in Options > Mods file, not in
-- world sandbox settings or companion save data. Register before the options
-- screen is built; load again on game start before the first NPC update.
require "SCNamespace"
if PZAPI == nil or PZAPI.ModOptions == nil then
    require "PZAPI/ModOptions"
end

local SC = SurvivorCompanion
SC.UserOptions = SC.UserOptions or {}
local UserOptions = SC.UserOptions

local MOD_ID = "SurvivorCompanion"
local CHATTER = { "normal", "less", "rare" }
local COUGH_SNEEZES = { "normal", "rare", "off" }
local values = {
    chatter = "normal",
    coughSneezes = "normal",
    ordinaryColds = true,
    protectRecruitedCompanions = false,
}

local api = PZAPI.ModOptions
local options = api:getOptions(MOD_ID)
if options == nil then
    options = api:create(MOD_ID, "UI_SC_ModOptions_Title")
end

local function combo(id, label, tooltip, choices, choiceLabels)
    local option = options:getOption(id)
    if option == nil then
        option = options:addComboBox(id, label, tooltip)
        for index, key in ipairs(choices) do
            option:addItem(choiceLabels[index], index == 1)
        end
    end
    return option
end

local function tickBox(id, label, default, tooltip)
    return options:getOption(id) or options:addTickBox(id, label, default, tooltip)
end

local chatterOption = combo("chatter", "UI_SC_ModOptions_Chatter",
    "UI_SC_ModOptions_Chatter_Tooltip", CHATTER, {
        "UI_SC_ModOptions_Normal", "UI_SC_ModOptions_Less", "UI_SC_ModOptions_Rare",
    })
local coughOption = combo("coughSneezes", "UI_SC_ModOptions_CoughSneezes",
    "UI_SC_ModOptions_CoughSneezes_Tooltip", COUGH_SNEEZES, {
        "UI_SC_ModOptions_Normal", "UI_SC_ModOptions_Rare", "UI_SC_ModOptions_Off",
    })
local coldOption = tickBox("ordinaryColds", "UI_SC_ModOptions_OrdinaryColds",
    true, "UI_SC_ModOptions_OrdinaryColds_Tooltip")
local protectionOption = tickBox("protectRecruitedCompanions",
    "UI_SC_ModOptions_ProtectRecruitedCompanions", false,
    "UI_SC_ModOptions_ProtectRecruitedCompanions_Tooltip")

local function selectedChoice(option, choices)
    local index = tonumber(option.selected)
    if index == nil or index % 1 ~= 0 or index < 1 or index > #choices then
        index = 1
        option:setValue(index)
    end
    return choices[index]
end

function UserOptions.get(key)
    return values[key]
end

-- The native gates need the live choices before a new actor's first update.
function UserOptions.syncNative()
    if SCBridge == nil then return false end
    local ok, result, comfortResult = pcall(function()
        local protection = SCBridge.setProtectRecruitedCompanions(
            values.protectRecruitedCompanions == true)
        local comfort = SCBridge.setCompanionComfortOptions(
            values.coughSneezes, values.ordinaryColds == true)
        return protection, comfort
    end)
    return ok and result ~= false and comfortResult ~= false
end

function UserOptions.apply()
    local priorCoughSneezes = values.coughSneezes
    local priorOrdinaryColds = values.ordinaryColds
    values.chatter = selectedChoice(chatterOption, CHATTER)
    values.coughSneezes = selectedChoice(coughOption, COUGH_SNEEZES)
    values.ordinaryColds = coldOption:getValue() == true
    values.protectRecruitedCompanions = protectionOption:getValue() == true
    UserOptions.syncNative()
    if (priorCoughSneezes ~= values.coughSneezes
            or priorOrdinaryColds ~= values.ordinaryColds)
        and SC.Gestures ~= nil
        and type(SC.Gestures.applyNativeOptions) == "function" then
        SC.Gestures.applyNativeOptions()
    end
end

function UserOptions.load()
    local ok, reason = pcall(function() api:load() end)
    if not ok then return false, tostring(reason) end
    UserOptions.apply()
    return true
end

-- MainOptions calls this immediately after applying its controls and before
-- the built-in ModOptions.ini save. Gameplay sees the new values in this frame.
function options:apply()
    UserOptions.apply()
end

return UserOptions
