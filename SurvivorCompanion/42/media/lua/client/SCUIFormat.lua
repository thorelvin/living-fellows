-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.UIFormat = SC.UIFormat or {}
local Format = SC.UIFormat

local WOUND_FLAGS = {
    { field = "bleeding", key = "UI_SC_Wound_Bleeding" },
    { field = "bitten", key = "UI_SC_Wound_Bitten" },
    { field = "infected", key = "UI_SC_Wound_Infected" },
    { field = "bandaged", key = "UI_SC_Wound_Bandaged" },
    { field = "dirtyBandage", key = "UI_SC_Wound_DirtyBandage" },
    { field = "scratched", key = "UI_SC_Wound_Scratched" },
    { field = "cut", key = "UI_SC_Wound_Cut" },
    { field = "deepWound", key = "UI_SC_Wound_DeepWound" },
    { field = "burned", key = "UI_SC_Wound_Burned" },
    { field = "fractured", key = "UI_SC_Wound_Fractured" },
}

local function translated(textFunction, key, ...)
    if type(textFunction) ~= "function" then
        return key
    end
    local ok, value = pcall(textFunction, key, ...)
    if ok and value ~= nil then
        return tostring(value)
    end
    return key
end

function Format.normalizeState(value)
    if value == nil then
        return nil
    end
    local state = string.lower(tostring(value))
    state = string.gsub(state, "[^a-z0-9]+", "_")
    state = string.gsub(state, "^_+", "")
    state = string.gsub(state, "_+$", "")
    return state
end

function Format.humanize(value)
    if value == nil then
        return ""
    end
    local readable = tostring(value)
    readable = string.gsub(readable, "([a-z0-9])([A-Z])", "%1 %2")
    readable = string.gsub(readable, "[_%-]+", " ")
    readable = string.gsub(readable, "%s+", " ")
    readable = string.gsub(readable, "^%s+", "")
    readable = string.gsub(readable, "%s+$", "")
    if string.match(readable, "^[a-z]") then
        readable = string.upper(string.sub(readable, 1, 1)) .. string.sub(readable, 2)
    end
    return readable
end

function Format.numberText(value, decimals, textFunction)
    local number = tonumber(value)
    if not number then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    if decimals == 0 then
        return tostring(math.floor(number + 0.5))
    end
    return string.format("%.1f", number)
end

function Format.stateText(value, textFunction)
    if value == nil or value == "" then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    local textValue = tostring(value)
    if string.sub(textValue, 1, 6) == "UI_SC_" then
        local direct = translated(textFunction, textValue)
        if direct ~= textValue then
            return direct
        end
        return Format.humanize(string.gsub(textValue, "^UI_SC_", ""))
    end
    local key = "UI_SC_State_" .. (Format.normalizeState(textValue) or "unknown")
    local state = translated(textFunction, key)
    if state ~= key then
        return state
    end
    return Format.humanize(textValue)
end

function Format.booleanText(value, textFunction)
    if value == true or value == 1 or value == "true" then
        return translated(textFunction, "UI_SC_Value_On")
    end
    if value == false or value == 0 or value == "false" then
        return translated(textFunction, "UI_SC_Value_Off")
    end
    return translated(textFunction, "UI_SC_Value_Unknown")
end

function Format.summaryText(value, textFunction)
    if type(value) == "number" then
        return Format.numberText(value, 0, textFunction)
    end
    if type(value) == "boolean" then
        return Format.booleanText(value, textFunction)
    end
    return Format.stateText(value, textFunction)
end

local function woundRecords(wounds)
    local records = {}
    for _, wound in ipairs(wounds) do
        if type(wound) == "table" then
            records[#records + 1] = wound
        end
    end
    if #records == 0 then
        for _, wound in pairs(wounds) do
            if type(wound) == "table" then
                records[#records + 1] = wound
            end
        end
    end
    return records
end

function Format.formatWounds(wounds, textFunction)
    if wounds == nil then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    if type(wounds) ~= "table" then
        return Format.stateText(wounds, textFunction)
    end
    local entries = {}
    for _, wound in ipairs(woundRecords(wounds)) do
        local details = {}
        for _, flag in ipairs(WOUND_FLAGS) do
            if wound[flag.field] == true then
                details[#details + 1] = translated(textFunction, flag.key)
            end
        end
        if wound.severity ~= nil and wound.severity ~= "" then
            details[#details + 1] = translated(
                textFunction,
                "UI_SC_Wound_Severity",
                Format.summaryText(wound.severity, textFunction)
            )
        end
        if #details == 0 then
            details[1] = translated(textFunction, "UI_SC_Wound_Injured")
        end
        local name = wound.name
        if name == nil or name == "" then
            name = translated(textFunction, "UI_SC_Wound_UnknownPart")
        else
            local rawName = tostring(name)
            local localizedName = translated(textFunction, rawName)
            name = localizedName ~= rawName and localizedName or Format.humanize(rawName)
        end
        entries[#entries + 1] = translated(
            textFunction,
            "UI_SC_Wound_Entry",
            tostring(name),
            table.concat(details, translated(textFunction, "UI_SC_Value_ListSeparator"))
        )
    end
    if #entries == 0 then
        return translated(textFunction, "UI_SC_Value_NoWounds")
    end
    return table.concat(entries, translated(textFunction, "UI_SC_Value_WoundSeparator"))
end

function Format.formatSupplies(supplies, textFunction)
    if supplies == nil then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    if type(supplies) ~= "table" then
        return Format.summaryText(supplies, textFunction)
    end
    return translated(
        textFunction,
        "UI_SC_Supplies_Summary",
        Format.numberText(supplies.bandages, 0, textFunction),
        Format.numberText(supplies.food, 0, textFunction),
        Format.numberText(supplies.water, 0, textFunction)
    )
end

function Format.formatAmmunition(ammunition, textFunction)
    if ammunition == nil then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    if type(ammunition) == "table" then
        ammunition = ammunition.ammunition or ammunition.count
    end
    return translated(
        textFunction,
        "UI_SC_Ammunition_Count",
        Format.numberText(ammunition, 0, textFunction)
    )
end

function Format.formatKnox(knox, textFunction)
    if knox == nil or knox == "" then
        return translated(textFunction, "UI_SC_Value_Unknown")
    end
    if type(knox) == "string" then
        if string.sub(knox, 1, 6) == "UI_SC_" then
            return translated(textFunction, knox)
        end
        -- SC.Commands.describe already localizes this field.
        return knox
    end
    return Format.summaryText(knox, textFunction)
end

function Format.formatSignalSuccess(signal, count, textFunction)
    local numericCount = tonumber(count)
    if numericCount ~= nil then
        return translated(
            textFunction,
            "UI_SC_Signal_Recipients",
            Format.numberText(numericCount, 0, textFunction)
        )
    end
    if type(signal) == "string" and signal ~= "" then
        if string.sub(signal, 1, 6) == "UI_SC_" or string.sub(signal, 1, 8) == "IGUI_SC_" then
            return translated(textFunction, signal)
        end
        return Format.humanize(signal)
    end
    return translated(textFunction, "UI_SC_CommandAccepted")
end

return Format
