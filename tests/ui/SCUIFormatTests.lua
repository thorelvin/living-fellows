-- SPDX-License-Identifier: MIT

local Format = SurvivorCompanion and SurvivorCompanion.UIFormat
assert(Format, "SCUIFormat must be loaded before this test")

local translations = {
    UI_SC_Value_Unknown = "Unknown",
    UI_SC_Value_On = "On",
    UI_SC_Value_Off = "Off",
    UI_SC_Value_NoWounds = "No active wounds",
    UI_SC_Value_ListSeparator = ", ",
    UI_SC_Value_WoundSeparator = " | ",
    UI_SC_Wound_Entry = "%1: %2",
    UI_SC_Wound_UnknownPart = "Unknown body part",
    UI_SC_Wound_Injured = "Injured",
    UI_SC_Wound_Severity = "Severity: %1",
    UI_SC_Wound_Bleeding = "Bleeding",
    UI_SC_Wound_Bitten = "Bitten",
    UI_SC_Wound_Infected = "Infected",
    UI_SC_Wound_Bandaged = "Bandaged",
    UI_SC_Wound_DirtyBandage = "Dirty bandage",
    UI_SC_Wound_Scratched = "Scratched",
    UI_SC_Wound_Cut = "Cut",
    UI_SC_Wound_DeepWound = "Deep wound",
    UI_SC_Wound_Burned = "Burned",
    UI_SC_Wound_Fractured = "Fractured",
    UI_SC_Supplies_Summary = "Bandages: %1 | Food: %2 | Water: %3",
    UI_SC_Ammunition_Count = "%1 rounds",
    UI_SC_Signal_Recipients = "%1 companions received the signal.",
    UI_SC_CommandAccepted = "Command accepted.",
    UI_SC_State_moderate = "Moderate",
    UI_SC_State_defensive = "Defensive",
    UI_SC_State_steady = "Steady",
}

local function text(key, ...)
    local value = translations[key] or key
    local arguments = { ... }
    for index = 1, #arguments do
        value = string.gsub(value, "%%" .. tostring(index), tostring(arguments[index]))
    end
    return value
end

local description = {
    id = "sc-format-test",
    wounds = {
        {
            name = "Left Forearm",
            bleeding = true,
            bitten = false,
            infected = false,
            bandaged = true,
            dirtyBandage = true,
            scratched = false,
            cut = true,
            deepWound = false,
            burned = false,
            fractured = false,
            severity = "moderate",
        },
        {
            name = "Right_Hand",
            bleeding = false,
            bitten = true,
            infected = true,
            bandaged = false,
            dirtyBandage = false,
            scratched = true,
            cut = false,
            deepWound = true,
            burned = true,
            fractured = true,
            severity = 7,
        },
    },
    supplies = { bandages = 3, food = 2, water = 4, ammunition = 37 },
    knox = "No Knox symptoms observed",
    combatStance = "defensive",
    personality = "steady",
}

local wounds = Format.formatWounds(description.wounds, text)
assert(string.find(wounds, "Left Forearm", 1, true))
assert(string.find(wounds, "Bleeding", 1, true))
assert(string.find(wounds, "Dirty bandage", 1, true))
assert(string.find(wounds, "Severity: Moderate", 1, true))
assert(string.find(wounds, "Right Hand", 1, true))
assert(string.find(wounds, "Bitten", 1, true))
assert(string.find(wounds, "Deep wound", 1, true))
assert(string.find(wounds, "Fractured", 1, true))
assert(string.find(wounds, "Severity: 7", 1, true))

assert(Format.formatWounds({}, text) == "No active wounds")
assert(Format.formatSupplies(description.supplies, text) == "Bandages: 3 | Food: 2 | Water: 4")
assert(Format.formatAmmunition(description.supplies.ammunition, text) == "37 rounds")
assert(Format.formatKnox(description.knox, text) == "No Knox symptoms observed")
assert(Format.stateText(description.combatStance, text) == "Defensive")
assert(Format.stateText(description.personality, text) == "Steady")
assert(Format.stateText("very_careful", text) == "Very careful")
assert(Format.formatSignalSuccess("whistle", 0, text) == "0 companions received the signal.")
assert(Format.formatSignalSuccess("follow", 3, text) == "3 companions received the signal.")
assert(Format.formatSignalSuccess("whistle", nil, text) == "Whistle")
