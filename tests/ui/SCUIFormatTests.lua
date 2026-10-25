-- SPDX-License-Identifier: MIT

local Format = SurvivorCompanion and SurvivorCompanion.UIFormat
assert(Format, "SCUIFormat must be loaded before this test")

local roster = {
    { recruited = false, name = "Francis" },
    { recruited = true, order = "stay", name = "Merle" },
    { recruited = true, order = "follow", name = "Sam" },
    { recruited = true, order = "follow", expeditionMember = true,
        name = "Rochelle" },
}
table.sort(roster, function(left, right)
    return Format.rosterPriority(left) < Format.rosterPriority(right)
end)
assert(roster[1].name == "Sam" and roster[2].name == "Merle"
    and roster[3].name == "Rochelle" and roster[4].name == "Francis",
    "following, other recruits, expedition members, and unrecruited stay grouped")

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
    UI_SC_Supplies_Summary = "Clean bandages/rags: %1 | Food: %2 | Water: %3",
    UI_SC_Ammunition_Count = "%1 rounds",
    UI_SC_Signal_Recipients = "%1 companions received the signal.",
    UI_SC_CommandAccepted = "Command accepted.",
    UI_SC_State_moderate = "Moderate",
    UI_SC_State_defensive = "Defensive",
    UI_SC_State_steady = "Steady",
    UI_SC_Base_Zone_parking = "Parking area",
    UI_SC_Base_Zone_lumber = "Lumber area",
    UI_SC_Base_Zone_ = "Zone",
}

local function text(key, ...)
    local value = translations[key] or key
    local arguments = { ... }
    for index = 1, #arguments do
        value = string.gsub(value, "%%" .. tostring(index), tostring(arguments[index]))
    end
    return value
end

assert(Format.baseZoneLabel({ id = "zone:42", name = "  North orchard  ", kind = "farm",
        x1 = 12030, y1 = 6748, z = 0 }, text) == "North orchard",
    "meaningful custom zone names are preserved with surrounding whitespace trimmed")
assert(Format.baseZoneLabel({ id = "zone:42", name = " \t ", kind = "parking",
        x1 = 12030, y1 = 6748, z = 0 }, text) == "Parking area (12030, 6748, 0)",
    "a blank parking name becomes a translated location instead of an invisible entry")
assert(Format.baseZoneLabel({ id = "zone:42", name = "", kind = "lumber",
        x = 100.9, y = 200.2, z = 1 }, text) == "Lumber area (100, 200, 1)",
    "point-style coordinates identify unnamed locations using actual integer tiles")
assert(Format.baseZoneLabel({ kind = "parking", name = "parking", x1 = 10, y1 = 20 }, text)
        == "Parking area (10, 20)", "old raw kind names receive the translated label and omit unknown floors")
assert(Format.baseZoneLabel({ id = "zone:42", name = "zone:42", kind = "parking" }, text)
        == "Parking area", "internal zone identifiers never become visible fallback names")
assert(Format.baseZoneLabel({ id = "zone:private", x = 10, y = 20 }, text) == "Zone (10, 20)",
    "missing kinds use a readable generic zone label without leaking an identifier")
assert(Format.baseZoneLabel({ kind = "parking", x = 0 / 0, y = math.huge }, text) == "Parking area",
    "unreadable coordinates cannot put NaN or infinity in a location selector")
assert(Format.baseZoneLabel(nil, text) == "Zone", "unavailable location data still has a nonblank label")
assert(Format.baseZoneLabel({ kind = "parking" }, function() return "" end) == "Parking area",
    "an empty translation cannot erase the location label")
assert(Format.baseZoneLabel({ kind = "parking", x = 10, y = 20 }, function(key)
        return key == "UI_SC_Base_Zone_parking" and "Translated parking" or key
    end) == "Translated parking (10, 20)", "zone-kind labels use the supplied translation provider")

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
assert(Format.formatSupplies(description.supplies, text) == "Clean bandages/rags: 3 | Food: 2 | Water: 4")
assert(Format.formatAmmunition(description.supplies.ammunition, text) == "37 rounds")
assert(Format.formatKnox(description.knox, text) == "No Knox symptoms observed")
assert(Format.stateText(description.combatStance, text) == "Defensive")
assert(Format.stateText(description.personality, text) == "Steady")
assert(Format.stateText("very_careful", text) == "Very careful")
assert(Format.formatSignalSuccess("whistle", 0, text) == "0 companions received the signal.")
assert(Format.formatSignalSuccess("follow", 3, text) == "3 companions received the signal.")
assert(Format.formatSignalSuccess("whistle", nil, text) == "Whistle")
