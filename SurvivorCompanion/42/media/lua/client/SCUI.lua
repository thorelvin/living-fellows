-- SPDX-License-Identifier: MIT

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTickBox"
require "ISUI/ISComboBox"
require "ISUI/ISLabel"
require "ISUI/ISScrollingListBox"
require "SCUIBounds"
require "SCUIBridge"
require "SCUIFormat"
require "SCUIPixels"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UI = SC.UI or {}
local UI = SC.UI
local Bounds = SC.UIBounds
local Bridge = SC.UIBridge
local Format = SC.UIFormat
local Pixels = SC.UIPixels

UI.SETTINGS_KEY = "SC_UISettings"
UI.SETTINGS_VISIBILITY_REVISION = 1
UI.HOTKEY_ACTION = "Toggle Living Fellows menu"
UI.DEFAULT_HOTKEY = Keyboard.KEY_F7
UI.instance = UI.instance or nil
UI.launcher = UI.launcher or nil
UI._hooksInstalled = UI._hooksInstalled or false
UI._gameStarted = UI._gameStarted or false

local function registerHotkey()
    if type(keyBinding) ~= "table" then return false end
    local categoryFound = false
    for _, binding in ipairs(keyBinding) do
        if binding.value == "[Living Fellows]" then categoryFound = true end
        if binding.value == UI.HOTKEY_ACTION then return true end
    end
    if not categoryFound then
        table.insert(keyBinding, { value = "[Living Fellows]" })
    end
    table.insert(keyBinding, {
        value = UI.HOTKEY_ACTION,
        key = UI.DEFAULT_HOTKEY,
    })
    return true
end

UI._hotkeyRegistered = registerHotkey()

local TAB_IDS = {
    "overview", "orders", "gear", "health", "journal", "base", "groups", "factions",
    "support",
}
local TAB_KEYS = {
    overview = "UI_SC_Tab_Overview",
    orders = "UI_SC_Tab_Orders",
    gear = "UI_SC_Tab_Gear",
    health = "UI_SC_Tab_Health",
    journal = "UI_SC_Tab_Journal",
    base = "UI_SC_Tab_Base",
    groups = "UI_SC_Tab_Groups",
    factions = "UI_SC_Tab_Factions",
    support = "UI_SC_Tab_Support",
    debug = "UI_SC_Tab_Debug",
}

function UI.tabIds()
    local result = {}
    for _, id in ipairs(TAB_IDS) do result[#result + 1] = id end
    if SC.Config and type(SC.Config.get) == "function"
        and SC.Config.get("debugSpawnEnabled") == true then
        result[#result + 1] = "debug"
    end
    return result
end

local COMBAT_DOCTRINES = {
    { id = "stealth", key = "UI_SC_Doctrine_Stealth" },
    { id = "close_defense", key = "UI_SC_Doctrine_CloseDefense" },
    { id = "ranged_support", key = "UI_SC_Doctrine_RangedSupport" },
    { id = "weapons_free", key = "UI_SC_Doctrine_WeaponsFree" },
}

local MAIN_ORDERS = {
    { id = "follow", key = "UI_SC_Select_OrderFollow", command = "follow" },
    { id = "stay", key = "UI_SC_Select_OrderStay", command = "stay" },
    { id = "guard", key = "UI_SC_Select_OrderGuard", command = "guard" },
}
local FOLLOW_DISTANCES = {
    { id = 2, key = "UI_SC_Select_Distance2" },
    { id = 3, key = "UI_SC_Select_Distance3" },
    { id = 5, key = "UI_SC_Select_Distance5" },
    { id = 8, key = "UI_SC_Select_Distance8" },
}
local WORK_MODES = {
    { id = "auto", key = "UI_SC_Select_WorkAuto" },
    { id = "idle", key = "UI_SC_Select_WorkIdle" },
    { id = "craft", key = "UI_SC_Select_WorkCraft" },
}
local MOVE_MODES = {
    { id = "copy", key = "UI_SC_Select_MoveCopyPlayer" },
    { id = "walk", key = "UI_SC_Select_MoveWalk" },
    { id = "sneak", key = "UI_SC_Select_MoveSneak" },
    { id = "jog", key = "UI_SC_Select_MoveRun" },
}
local COMBAT_STANCES = {
    { id = "passive", key = "UI_SC_Select_StancePassive" },
    { id = "defensive", key = "UI_SC_Select_StanceDefensive" },
    { id = "aggressive", key = "UI_SC_Select_StanceAggressive" },
}
local WEAPON_PRIORITIES = {
    { id = "best", key = "UI_SC_Select_WeaponBest" },
    { id = "melee", key = "UI_SC_Select_WeaponMelee" },
    { id = "firearm", key = "UI_SC_Select_WeaponFirearm" },
    { id = "quiet", key = "UI_SC_Select_WeaponQuiet" },
}
local GROUPS = {
    { id = "", key = "UI_SC_Select_GroupNone" },
    { id = "alpha", key = "UI_SC_Select_GroupAlpha" },
    { id = "bravo", key = "UI_SC_Select_GroupBravo" },
    { id = "charlie", key = "UI_SC_Select_GroupCharlie" },
}

function UI.normalizeTab(tab)
    if type(tab) ~= "string" then
        return nil
    end
    local normalized = string.lower(tab)
    if TAB_KEYS[normalized] and (normalized ~= "debug"
        or SC.Config and type(SC.Config.get) == "function"
            and SC.Config.get("debugSpawnEnabled") == true) then
        return normalized
    end
    return nil
end

local function safeMethod(object, methodName, ...)
    if not object then
        return nil
    end
    local method = object[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value, second = pcall(method, object, ...)
    if not ok then
        return nil
    end
    return value, second
end

-- Project Zomboid's Kahlua runtime does not consistently expose Lua's global
-- next() to mods. Iterating is portable across the supported Build 42 runtime
-- and avoids crashing a tab merely to decide whether a payload is empty.
local function tableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _, _ in pairs(value) do return true end
    return false
end

function UI.hotkeyName()
    local key = UI.DEFAULT_HOTKEY
    local core = getCore and getCore() or nil
    local configured = core and safeMethod(core, "getKey", UI.HOTKEY_ACTION) or nil
    if tonumber(configured) and tonumber(configured) > 0 then
        key = tonumber(configured)
    end
    if getKeyName then
        local ok, name = pcall(getKeyName, key)
        if ok and name and name ~= "" then return tostring(name) end
    end
    return "F7"
end

local function screenSize()
    local core = getCore and getCore() or nil
    local width = core and safeMethod(core, "getScreenWidth") or 1280
    local height = core and safeMethod(core, "getScreenHeight") or 720
    return tonumber(width) or 1280, tonumber(height) or 720
end

function UI.text(key, ...)
    if getText then
        local ok, value = pcall(getText, key, ...)
        if ok and value then
            return value
        end
    end
    return key
end

function UI.fontHeight(font, override)
    local explicit = tonumber(override)
    if explicit then
        return math.max(1, math.floor(explicit + 0.5))
    end
    local manager = getTextManager and getTextManager() or nil
    local height = manager and safeMethod(manager, "getFontHeight", font or UIFont.Small) or nil
    return math.max(1, math.floor((tonumber(height) or 14) + 0.5))
end

function UI.textWidth(font, value)
    local manager = getTextManager and getTextManager() or nil
    local width = manager and safeMethod(manager, "MeasureStringX", font or UIFont.Small, tostring(value or "")) or nil
    return tonumber(width) or (string.len(tostring(value or "")) * 8)
end

function UI.layoutMetrics(fontHeightOverride)
    local fontHeight = UI.fontHeight(UIFont.Small, fontHeightOverride)
    local lineHeight = fontHeight + 4
    local buttonHeight = math.max(26, fontHeight + 12)
    return {
        fontHeight = fontHeight,
        lineHeight = lineHeight,
        infoLineHeight = fontHeight + 5,
        sectionHeight = fontHeight + 10,
        buttonHeight = buttonHeight,
        tabHeight = buttonHeight,
        headerHeight = math.max(36, buttonHeight + 10),
        rosterItemHeight = (lineHeight * 4) + 10,
    }
end

local function unknownValue()
    return UI.text("UI_SC_Value_Unknown")
end

function UI.stateText(value)
    return Format.stateText(value, UI.text)
end

function UI.booleanText(value)
    return Format.booleanText(value, UI.text)
end

function UI.humanize(value)
    return Format.humanize(value)
end

local function playerForUI()
    if getPlayer then
        return getPlayer()
    end
    return nil
end

local function configuredOpacity(multiplier, minimum, maximum)
    local configured = SC.Config and type(SC.Config.get) == "function"
        and tonumber(SC.Config.get("uiPanelOpacity")) or 0.66
    local value = configured * (tonumber(multiplier) or 1)
    return math.max(tonumber(minimum) or 0.12, math.min(tonumber(maximum) or 0.92, value))
end

local function makeButtonTranslucent(button)
    if not button then return end
    button.backgroundColor = { r = 0.035, g = 0.04, b = 0.035,
        a = configuredOpacity(0.88, 0.22, 0.78) }
    button.backgroundColorMouseOver = { r = 0.28, g = 0.30, b = 0.25,
        a = configuredOpacity(1.18, 0.48, 0.9) }
end

local signatureExcludedFields = {
    actor = true,
    distance = true,
    tooltip = true,
}

local function stableSignatureValue(value, depth, budget, seen)
    local valueType = type(value)
    if valueType == "nil" then return "nil" end
    if valueType == "boolean" or valueType == "string" then return tostring(value) end
    if valueType == "number" then return string.format("%.2f", value) end
    if valueType ~= "table" or depth <= 0 or budget.count <= 0 then
        return valueType
    end
    if seen[value] then return "cycle" end
    seen[value] = true
    local keys = {}
    for key, _ in pairs(value) do
        if (type(key) == "string" or type(key) == "number")
            and not signatureExcludedFields[key] then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    local parts = {}
    for _, key in ipairs(keys) do
        if budget.count <= 0 then break end
        budget.count = budget.count - 1
        parts[#parts + 1] = tostring(key) .. "="
            .. stableSignatureValue(value[key], depth - 1, budget, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

local function detailRowSignature(row)
    if type(row) ~= "table" then return "none" end
    local distance = tonumber(row.distance)
    local distanceBand = distance == nil and "unknown"
        or (distance <= 4 and "touch"
            or (distance <= 16 and "conversation" or "far"))
    return distanceBand .. ":"
        .. stableSignatureValue(row, 4, { count = 160 }, {})
end

local function factionDetailSignature()
    if not SC.Factions or type(SC.Factions.list) ~= "function" then return "factions:none" end
    local rows = {}
    for _, group in ipairs(SC.Factions.list(false)) do
        local summary = SC.Factions.summary(group.id)
        if SC.Trade and type(SC.Trade.canOpen) == "function" then
            local canOpen, reason = SC.Trade.canOpen(group.id, playerForUI())
            summary.tradeAccess = canOpen == true and "open" or tostring(reason)
        end
        rows[#rows + 1] = summary
    end
    local worldVersion = SC.FactionWorld and type(SC.FactionWorld.version) == "function"
        and SC.FactionWorld.version() or 0
    return "factions:" .. stableSignatureValue(rows, 6, { count = 640 }, {})
        .. ":world:" .. tostring(worldVersion)
end

local function baseDetailSignature()
    if not SC.BaseLife or type(SC.BaseLife.summary) ~= "function" then return "base:none" end
    local summary = SC.BaseLife.summary()
    local operations = summary.operations or {}
    return "base:" .. stableSignatureValue({
        configured = summary.configured, name = summary.name, zones = summary.zones,
        storages = summary.storages, residents = summary.residents, duty = summary.duty,
        jobs = summary.jobs, rows = summary.rows, residentRows = summary.residentRows,
        operations = {
            readiness = operations.readiness, stock = operations.stock,
            alerts = operations.alerts, policies = operations.policies,
            activeGuard = operations.activeGuard,
            unloadedStores = operations.unloadedStores,
        },
    }, 6, { count = 480 }, {})
end

function UI.getSettings()
    local player = playerForUI()
    local modData = player and safeMethod(player, "getModData") or nil
    if type(modData) == "table" then
        if type(modData[UI.SETTINGS_KEY]) ~= "table" then
            modData[UI.SETTINGS_KEY] = {}
        end
        return modData[UI.SETTINGS_KEY]
    end
    UI._sessionSettings = UI._sessionSettings or {}
    return UI._sessionSettings
end

local function actorAndId(entry)
    local actor = entry
    local id = nil
    if type(entry) == "table" then
        actor = entry.actor or entry.javaObject or entry
        id = entry.id or entry.companionId
    end
    if not id and actor then
        local modData = safeMethod(actor, "getModData")
        if type(modData) == "table" then
            id = modData.SC_Id
        end
    end
    return actor, id
end

local function actorName(actor)
    local descriptor = safeMethod(actor, "getDescriptor")
    local forename = descriptor and safeMethod(descriptor, "getForename") or nil
    local surname = descriptor and safeMethod(descriptor, "getSurname") or nil
    if forename and surname and surname ~= "" then
        return tostring(forename) .. " " .. tostring(surname)
    end
    if forename and forename ~= "" then
        return tostring(forename)
    end
    local fullName = safeMethod(actor, "getFullName")
    if fullName and fullName ~= "" then
        return tostring(fullName)
    end
    return UI.text("UI_SC_Value_UnknownCompanion")
end

local function actorHealth(actor)
    local bodyDamage = safeMethod(actor, "getBodyDamage")
    return bodyDamage and safeMethod(bodyDamage, "getHealth") or nil
end

local function actorDistance(actor, player)
    if not actor or not player then
        return nil
    end
    return safeMethod(player, "DistTo", actor)
end

local function copySummary(row, summary)
    if type(summary) ~= "table" then
        return
    end
    row.id = summary.id or summary.companionId or row.id
    row.actor = summary.actor or row.actor
    row.name = summary.name or summary.fullName or row.name
    row.health = summary.health or row.health
    if summary.hunger ~= nil then row.hunger = summary.hunger end
    if summary.thirst ~= nil then row.thirst = summary.thirst end
    row.distance = summary.distance or row.distance
    row.order = summary.order or row.order
    row.activity = summary.activity or row.activity
    row.intent = summary.intent or row.intent
    row.combatDoctrine = summary.combatDoctrine or summary.combat_doctrine or row.combatDoctrine
    row.combatStance = summary.combatStance or summary.combatMode
        or summary.combat_mode or row.combatStance
    if summary.holdFire ~= nil then row.holdFire = summary.holdFire end
    row.weaponPriority = summary.weaponPriority or summary.weapon_priority or row.weaponPriority
    row.equippedWeapon = summary.equippedWeapon or summary.equipped_weapon or row.equippedWeapon
    row.followDistance = summary.followDistance or summary.follow_distance
    row.moveMode = summary.moveMode or summary.move_mode or row.moveMode
    if summary.scavenge ~= nil then row.scavenge = summary.scavenge end
    row.scavengeStatus = summary.scavengeStatus
    if summary.allowOverload ~= nil then row.allowOverload = summary.allowOverload end
    if summary.rideWithPlayer ~= nil then row.rideWithPlayer = summary.rideWithPlayer end
    row.vehicleStatus = summary.vehicleStatus
    row.workMode = summary.workMode or summary.work_mode or row.workMode
    if summary.group ~= nil then row.group = summary.group end
    row.knox = summary.knox or summary.knoxStatus or summary.knox_status or row.knox
    if summary.alive ~= nil then row.alive = summary.alive end
    if summary.available ~= nil then row.available = summary.available end
    row.wounds = summary.wounds or row.wounds
    row.supplies = summary.supplies or row.supplies
    if summary.loadWeight ~= nil then row.loadWeight = summary.loadWeight end
    if summary.loadCapacity ~= nil then row.loadCapacity = summary.loadCapacity end
    if summary.loadRatio ~= nil then row.loadRatio = summary.loadRatio end
    row.loadRole = summary.loadRole or row.loadRole
    local supplyAmmunition = type(summary.supplies) == "table" and summary.supplies.ammunition or nil
    row.ammunition = summary.ammunition or summary.ammo or supplyAmmunition or row.ammunition
    row.personality = summary.personality or row.personality
    row.profession = summary.profession or row.profession
    row.aptitude = summary.aptitude or row.aptitude
    row.backgroundLabel = summary.backgroundLabel or row.backgroundLabel
    if summary.trust ~= nil then row.trust = summary.trust end
    if summary.bond ~= nil then row.bond = summary.bond end
    if summary.morale ~= nil then row.morale = summary.morale end
    if summary.stress ~= nil then row.stress = summary.stress end
    row.stressResponse = summary.stressResponse or row.stressResponse
    row.stressResponseLabel = summary.stressResponseLabel or row.stressResponseLabel
    row.joyResponse = summary.joyResponse or row.joyResponse
    row.joyResponseLabel = summary.joyResponseLabel or row.joyResponseLabel
    if summary.boredom ~= nil then row.boredom = summary.boredom end
    row.topThoughts = summary.topThoughts or row.topThoughts
    row.currentExpectation = summary.currentExpectation
    row.activeEpisode = summary.activeEpisode
    row.inspiration = summary.inspiration
    row.pendingRequest = summary.pendingRequest
    row.relationshipTier = summary.relationshipTier or row.relationshipTier
    row.mood = summary.mood or row.mood
    row.currentNeed = summary.currentNeed or row.currentNeed
    row.recentMemory = summary.recentMemory or row.recentMemory
    row.background = summary.background or row.background
    row.personalityProfile = summary.personalityProfile or row.personalityProfile
    row.objectives = summary.objectives or row.objectives
    row.possessions = summary.possessions or row.possessions
    row.journal = summary.journal or row.journal
    if summary.timeTogetherHours ~= nil then row.timeTogetherHours = summary.timeTogetherHours end
    if summary.recruited ~= nil then row.recruited = summary.recruited end
    if summary.factionMember ~= nil then row.factionMember = summary.factionMember end
    row.factionId = summary.factionId or row.factionId
    row.factionRole = summary.factionRole or row.factionRole
    row.factionStanding = summary.factionStanding or row.factionStanding
end

function UI.describeEntry(entry, player)
    local actor, id = actorAndId(entry)
    local row = {
        actor = actor,
        id = id,
        name = actorName(actor),
        health = actorHealth(actor),
        distance = actorDistance(actor, player),
        order = nil,
        activity = nil,
        alive = true,
    }
    if id and SC.Commands and type(SC.Commands.describe) == "function" then
        local ok, summary = pcall(SC.Commands.describe, id, player)
        if ok then
            copySummary(row, summary)
        end
    end
    if type(entry) == "table" then
        copySummary(row, entry)
    end
    row.name = row.name or UI.text("UI_SC_Value_UnknownCompanion")
    row.id = row.id or ""
    return row
end

local function numericText(value, decimals)
    return Format.numberText(value, decimals, UI.text)
end

function UI.summaryText(value)
    return Format.summaryText(value, UI.text)
end

function UI.formatWounds(value)
    return Format.formatWounds(value, UI.text)
end

function UI.formatSupplies(value)
    return Format.formatSupplies(value, UI.text)
end

function UI.formatAmmunition(value)
    return Format.formatAmmunition(value, UI.text)
end

function UI.formatKnox(value)
    return Format.formatKnox(value, UI.text)
end

function UI.healthText(value)
    return UI.text("UI_SC_Value_Health", numericText(value, 0))
end

function UI.distanceText(value)
    return UI.text("UI_SC_Value_Distance", numericText(value, 1))
end

local function summaryTooltip(row)
    return table.concat({
        tostring(row.name or unknownValue()),
        UI.text("UI_SC_Roster_Health", UI.healthText(row.health)),
        UI.text("UI_SC_Roster_Distance", UI.distanceText(row.distance)),
        UI.text("UI_SC_Roster_Order", UI.stateText(row.order)),
        UI.text("UI_SC_Roster_Activity", UI.stateText(row.activity)),
    }, "\n")
end

local function fitText(font, textValue, maximumWidth)
    local value = tostring(textValue or "")
    if UI.textWidth(font, value) <= maximumWidth then
        return value
    end
    local suffix = "..."
    while string.len(value) > 1 and UI.textWidth(font, value .. suffix) > maximumWidth do
        value = string.sub(value, 1, string.len(value) - 1)
    end
    return value .. suffix
end

function UI.wrapText(font, textValue, maximumWidth)
    local value = tostring(textValue or "")
    if value == "" or UI.textWidth(font, value) <= maximumWidth then
        return { value }
    end
    local lines = {}
    local current = ""
    for word in string.gmatch(value, "%S+") do
        local candidate = current == "" and word or (current .. " " .. word)
        if current ~= "" and UI.textWidth(font, candidate) > maximumWidth then
            lines[#lines + 1] = current
            current = word
        else
            current = candidate
        end
    end
    if current ~= "" then
        lines[#lines + 1] = current
    end
    if #lines == 0 then
        lines[1] = fitText(font, value, maximumWidth)
    end
    for index, line in ipairs(lines) do
        if UI.textWidth(font, line) > maximumWidth then
            lines[index] = fitText(font, line, maximumWidth)
        end
    end
    return lines
end

local SCUIRoster = ISScrollingListBox:derive("SCUIRoster")

function SCUIRoster:new(x, y, width, height, owner)
    local object = ISScrollingListBox.new(self, x, y, width, height)
    object.owner = owner
    object.font = UIFont.Small
    object.metrics = UI.layoutMetrics()
    object.fontHgt = object.metrics.fontHeight
    object.itemheight = object.metrics.rosterItemHeight
    object.drawBorder = true
    object.backgroundColor = { r = 0.02, g = 0.025, b = 0.02,
        a = configuredOpacity(0.58, 0.18, 0.72) }
    return object
end

function SCUIRoster:doDrawItem(y, item, alternate)
    local row = item.item
    local metrics = self.metrics or UI.layoutMetrics()
    local height = metrics.rosterItemHeight
    item.height = height
    if self.selected == item.index then
        self:drawRect(0, y, self:getWidth(), height, 0.34, 0.36, 0.43, 0.31)
    elseif alternate then
        self:drawRect(0, y, self:getWidth(), height, 0.12, 0.12, 0.12, 0.2)
    end
    self:drawRectBorder(0, y, self:getWidth(), height, 0.22, 0.55, 0.58, 0.51)
    local maximumWidth = self:getWidth() - 16
    local lineY = y + 5
    self:drawText(fitText(UIFont.Small, row.name, maximumWidth), 8, lineY, 0.92, 0.93, 0.89, 1, UIFont.Small)
    lineY = lineY + metrics.lineHeight
    self:drawText(fitText(UIFont.Small, UI.text("UI_SC_Roster_HealthDistance", UI.healthText(row.health), UI.distanceText(row.distance)), maximumWidth), 8, lineY, 0.72, 0.77, 0.72, 1, UIFont.Small)
    lineY = lineY + metrics.lineHeight
    self:drawText(fitText(UIFont.Small, UI.text("UI_SC_Roster_Order", UI.stateText(row.order)), maximumWidth), 8, lineY, 0.78, 0.80, 0.73, 1, UIFont.Small)
    lineY = lineY + metrics.lineHeight
    self:drawText(fitText(UIFont.Small, UI.text("UI_SC_Roster_Activity", UI.stateText(row.activity)), maximumWidth), 8, lineY, 0.67, 0.72, 0.68, 1, UIFont.Small)
    item.tooltip = row.tooltip
    return y + height
end

function SCUIRoster:onMouseDown(x, y)
    local result = ISScrollingListBox.onMouseDown(self, x, y)
    if self.owner then
        self.owner:onRosterSelectionChanged(self.selected)
    end
    return result
end

local RECRUITED_COMMANDS = {
    dismiss = true,
    follow = true,
    stay = true,
    guard = true,
    regroup = true,
    retreat = true,
    set_follow_distance = true,
    set_scavenge = true,
    set_allow_overload = true,
    set_ride_with_player = true,
    set_work_mode = true,
    set_move_mode = true,
    set_combat_mode = true,
    set_combat_doctrine = true,
    set_weapon_priority = true,
    set_hold_fire = true,
    hold_fire = true,
    fire_at_will = true,
    move_to = true,
    open_door = true,
    close_door = true,
    check_room = true,
    board_vehicle = true,
    exit_vehicle = true,
    open_inventory = true,
    open_health = true,
    emote = true,
    relationship = true,
    encourage = true,
    praise = true,
    set_group = true,
    base_duty = true,
    set_base_role = true,
}

local PROXIMITY_LIMITS = {
    status = 16,
    needs = 16,
    memory = 16,
    background = 16,
    opinion = 16,
    relationship = 16,
    encourage = 16,
    praise = 16,
    plans = 16,
    emote = 16,
    recruit = 16,
    open_inventory = 4,
    open_health = 4,
}

local function usableGroup(group)
    if group == nil then
        return false
    end
    local normalized = string.lower(tostring(group))
    return normalized ~= "" and normalized ~= "none"
end

function UI.commandAvailability(row, command, payload)
    if not row or not row.id or row.id == "" then
        return false, "UI_SC_Disabled_NoSelection"
    end
    if row.alive == false then
        return false, "UI_SC_Disabled_NotAlive"
    end
    if row.available == false then
        return false, "UI_SC_Disabled_Unavailable"
    end
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "UI_SC_Disabled_CommandService"
    end
    if command == "recruit" and row.recruited == true then
        return false, "UI_SC_Disabled_AlreadyRecruited"
    end
    if RECRUITED_COMMANDS[command] and row.recruited == false then
        return false, "UI_SC_Disabled_RecruitedOnly"
    end
    if type(payload) == "table" and payload.scope == "group" and not usableGroup(row.group or payload.group) then
        return false, "UI_SC_Disabled_NoGroup"
    end
    if command == "board_vehicle" and not (type(payload) == "table" and payload.vehicle) then
        local player = playerForUI()
        if not player then
            return false, "UI_SC_Disabled_NoPlayer"
        end
        if not safeMethod(player, "getVehicle") then
            return false, "UI_SC_Disabled_NoPlayerVehicle"
        end
    end
    if command == "exit_vehicle" then
        local status = row.vehicleStatus
        if type(status) ~= "table" or status.status ~= "in_vehicle"
            or status.canExitNow ~= true then
            return false, "UI_SC_Disabled_UnsafeVehicleExit"
        end
    end
    local limit = PROXIMITY_LIMITS[command]
    if limit then
        local distance = tonumber(row.distance)
        if not distance or distance > limit then
            return false, "UI_SC_Disabled_TooFar", limit
        end
    end
    return true, nil
end

function UI.signalAvailability(root, signal, activePlayer)
    local player = activePlayer or playerForUI()
    if not player then
        return false, "UI_SC_Disabled_NoPlayer"
    end
    if signal == "whistle" then
        if not SC.Commands or type(SC.Commands.whistle) ~= "function" then
            return false, "UI_SC_Disabled_CommandService"
        end
        return true, nil
    end
    if not SC.Commands or type(SC.Commands.isHandSign) ~= "function"
        or not SC.Commands.isHandSign(signal) then
        return false, "UI_SC_Disabled_CommandService"
    end
    if not SC.Commands or type(SC.Commands.handSign) ~= "function" then
        return false, "UI_SC_Disabled_CommandService"
    end
    local uncertain = false
    local items = root and root.roster and root.roster.items or {}
    for _, item in ipairs(items) do
        local row = item.item
        if row and row.alive ~= false and row.available ~= false and row.recruited ~= false then
            local actor = row.actor
            if row.recruited == nil or not actor then
                uncertain = true
            else
                local visible = safeMethod(actor, "CanSee", player)
                if visible == nil then
                    visible = safeMethod(actor, "canSee", player)
                end
                if visible == true then
                    return true, nil
                end
                if visible == nil then
                    uncertain = true
                end
            end
        end
    end
    if uncertain then
        -- Missing visibility/recruitment metadata is not grounds for a false
        -- negative; SC.Commands.handSign still performs authoritative checks.
        return true, nil
    end
    return false, "UI_SC_Disabled_NoVisibleRecruits"
end

local function commandResultDescription(first, second, third)
    if type(first) == "table" then return first end
    if type(second) == "table" then return second end
    if type(third) == "table" then return third end
    return nil
end

local function buttonFeedbackLabel(button)
    if button and type(button.scLabel) == "string" and button.scLabel ~= "" then
        return button.scLabel
    end
    return button and UI.humanize(button.scCommand or button.scSignal or "command")
        or UI.text("UI_SC_CommandAccepted")
end

local function setButtonFeedback(target, message, success)
    if not target then return end
    target.feedback = message
    target.feedbackSuccess = success == true
    local now = SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function"
        and SC.GameplayUtil.nowMs() or 0
    target.feedbackUntil = now + 4500
end

local function onCommandButton(target, button)
    local row = target.root and target.root.selectedRow or nil
    local available = UI.commandAvailability(row, button.scCommand, button.scPayload)
    if not available then
        return false
    end
    local player = playerForUI()
    local ok, accepted, reason, extra = pcall(SC.Commands.issue, row.id, button.scCommand, button.scPayload, player)
    if not ok or accepted == false then
        setButtonFeedback(target,
            UI.text("UI_SC_CommandRejectedDetail", buttonFeedbackLabel(button)), false)
        if type(reason) == "string" and string.sub(reason, 1, 6) == "UI_SC_" then
            setButtonFeedback(target, UI.text(reason), false)
        end
    else
        local resultText
        if button.scCommand == "set_weapon_priority" then
            local weaponName = type(extra) == "table" and extra.weaponName or nil
            if (reason == "weapon_equipped" or reason == "weapon_already_equipped") and weaponName then
                resultText = UI.text("UI_SC_Result_WeaponEquipped", weaponName)
            elseif reason == "weapon_priority_equip_deferred" then
                resultText = UI.text("UI_SC_Result_WeaponDeferred")
            end
        end
        setButtonFeedback(target,
            resultText and UI.text("UI_SC_CommandAcceptedResult",
                buttonFeedbackLabel(button), resultText)
                or UI.text("UI_SC_CommandAcceptedDetail", buttonFeedbackLabel(button)),
            true)
    end
    if button.scCommand == "status" and ok and accepted ~= false then
        local description = commandResultDescription(accepted, reason, extra)
        if description then
            UI.showStatus(description)
        else
            UI.open("overview", row.id)
        end
    else
        UI.refresh()
    end
    return ok and accepted ~= false
end

local function onBooleanCommand(target, index, selected, command, payloadKey, tickBox)
    local row = target.root and target.root.selectedRow or nil
    local previous = row and row[tickBox.scRowField] == true or false
    local payload = {}
    payload[payloadKey] = selected == true
    local accepted = onCommandButton(target, {
        scCommand = command,
        scPayload = payload,
        scLabel = tickBox.scLabel,
    })
    if accepted ~= true and tickBox and type(tickBox.setSelected) == "function" then
        tickBox:setSelected(index, previous)
    end
end

local function selectComboValue(combo, value)
    for index = 1, #(combo.options or {}) do
        local data = combo:getOptionData(index)
        if type(data) == "table" and data.value == value then
            combo.selected = index
            return true
        end
    end
    return false
end

local function onCommandSelector(target, combo)
    if not combo or not combo.selected then return end
    local option = combo:getOptionData(combo.selected)
    if type(option) ~= "table" or option.command == nil
        or option.value == combo.scValue then return end
    local previous = combo.scValue
    local payload = {}
    if type(option.payload) == "table" then
        for key, value in pairs(option.payload) do payload[key] = value end
    end
    if option.payloadKey then payload[option.payloadKey] = option.value end
    local accepted = onCommandButton(target, {
        scCommand = option.command,
        scPayload = tableHasEntries(payload) and payload or nil,
        scLabel = UI.text("UI_SC_Select_Command", combo.scLabel, option.label),
    })
    if accepted == true then
        combo.scValue = option.value
    else
        selectComboValue(combo, previous)
    end
end

local function onDoctrineChange(target, combo)
    if not combo or not combo.selected then return end
    local doctrine = combo:getOptionData(combo.selected)
    if doctrine == combo.scDoctrine then return end
    local previous = combo.scDoctrine
    local accepted = onCommandButton(target, {
        scCommand = "set_combat_doctrine",
        scPayload = { doctrine = doctrine, scope = "team" },
        scLabel = UI.text("UI_SC_Action_SetTeamDoctrine", UI.stateText(doctrine)),
    })
    if accepted == true then
        combo.scDoctrine = doctrine
        return
    end
    for index = 1, #combo.options do
        if combo:getOptionData(index) == previous then
            combo.selected = index
            break
        end
    end
end

local function signalResultText(value)
    if type(value) == "number" then
        return UI.text("UI_SC_Signal_Recipients", math.floor(value))
    end
    if type(value) ~= "string" or value == "" then
        return nil
    end
    if string.sub(value, 1, 6) == "UI_SC_" or string.sub(value, 1, 8) == "IGUI_SC_" then
        return UI.text(value)
    end
    return UI.humanize(value)
end

function UI.signalSuccessText(signal, count)
    return Format.formatSignalSuccess(signal, count, UI.text)
end

local function onSignalButton(target, button)
    local player = playerForUI()
    if not player then
        setButtonFeedback(target, UI.text("UI_SC_Disabled_NoPlayer"), false)
        return
    end
    local available = UI.signalAvailability(target.root, button.scSignal, player)
    if not available then
        return
    end
    local ok, accepted, reason, extra, results
    if button.scSignal == "whistle" then
        ok, accepted, reason, extra, results = pcall(SC.Commands.whistle, player)
    else
        ok, accepted, reason, extra, results = pcall(SC.Commands.handSign, player, button.scSignal)
    end
    if not ok or accepted == false then
        setButtonFeedback(target, signalResultText(reason)
            or UI.text("UI_SC_CommandRejectedDetail", buttonFeedbackLabel(button)), false)
    else
        local resultText = UI.signalSuccessText(reason, extra)
            or (type(accepted) ~= "boolean" and signalResultText(accepted))
        setButtonFeedback(target,
            resultText and UI.text("UI_SC_CommandAcceptedResult",
                buttonFeedbackLabel(button), resultText)
                or UI.text("UI_SC_CommandAcceptedDetail", buttonFeedbackLabel(button)),
            true)
    end
    UI.refresh()
end

local function onCrisisButton(target, button)
    if not SC.InfectionCrisis then return end
    local ok, accepted, reason
    if button.scCrisisAction == "authorize" then
        ok, accepted, reason = pcall(SC.InfectionCrisis.authorize, button.scCrisisId,
            button.scOutcome)
    else
        ok, accepted, reason = pcall(SC.InfectionCrisis.choose, button.scCrisisId,
            button.scOutcome)
    end
    setButtonFeedback(target,
        ok and accepted == true
            and UI.text("UI_SC_CommandAcceptedDetail", buttonFeedbackLabel(button))
            or UI.text("UI_SC_Base_ActionFailed", tostring(reason or accepted)),
        ok and accepted == true)
    UI.refresh()
end

local function onBaseToggle(target, index, selected, policyKey, tickBox)
    if not SC.BaseLife or type(SC.BaseLife.setPolicy) ~= "function" then return end
    local ok, accepted, reason = pcall(SC.BaseLife.setPolicy, policyKey, selected == true)
    if not ok or accepted ~= true then
        if tickBox and type(tickBox.setSelected) == "function" then
            tickBox:setSelected(index, selected ~= true)
        end
    end
    setButtonFeedback(target, ok and accepted == true
        and UI.text("UI_SC_Base_PolicyUpdated")
        or UI.text("UI_SC_Base_ActionFailed", tostring(reason or accepted)),
        ok and accepted == true)
    UI.refresh()
end

local function onBasePolicySelector(target, combo)
    if not combo or not combo.selected or not SC.BaseLife
        or type(SC.BaseLife.setPolicy) ~= "function" then return end
    local option = combo:getOptionData(combo.selected)
    if type(option) ~= "table" or option.value == combo.scValue then return end
    local previous = combo.scValue
    local ok, accepted, reason = pcall(SC.BaseLife.setPolicy,
        combo.scPolicyKey, option.value)
    if ok and accepted == true then
        combo.scValue = option.value
    else
        selectComboValue(combo, previous)
    end
    setButtonFeedback(target, ok and accepted == true
        and UI.text("UI_SC_Base_PolicyUpdated")
        or UI.text("UI_SC_Base_ActionFailed", tostring(reason or accepted)),
        ok and accepted == true)
    UI.refresh()
end

local function onAutonomyButton(target, button)
    local row = target.root and target.root.selectedRow or nil
    if not row or not SC.Autonomy or type(SC.Autonomy.respond) ~= "function" then return end
    local ok, accepted, reason = pcall(
        SC.Autonomy.respond, row.id, button.scAutonomyChoice, playerForUI())
    setButtonFeedback(target,
        ok and accepted == true
            and UI.text("UI_SC_CommandAcceptedDetail", buttonFeedbackLabel(button))
            or UI.text("UI_SC_Base_ActionFailed", tostring(reason or accepted)),
        ok and accepted == true)
    UI.refresh()
end

local function newestFactionId(discoveredOnly)
    if not SC.Factions or type(SC.Factions.list) ~= "function" then return nil end
    local rows = SC.Factions.list(discoveredOnly == true)
    return rows[#rows] and rows[#rows].id or nil
end

local function onTradeChoice(target, index, selected, side, factionId, tickBox)
    target.tradeSelections = target.tradeSelections or {}
    local selection = target.tradeSelections[factionId]
    if not selection then
        selection = { offer = {}, request = {} }
        target.tradeSelections[factionId] = selection
    end
    local bucket = side == "offer" and selection.offer or selection.request
    if tickBox and tickBox.scTradeRow and tickBox.scTradeRow.item then
        bucket[tickBox.scTradeRow.item] = selected == true and tickBox.scTradeRow or nil
    end
    target:rebuild(true)
end

local function selectedTradeRows(target, factionId)
    local selection = target.tradeSelections and target.tradeSelections[factionId] or nil
    local offer, request = {}, {}
    for _, row in pairs(selection and selection.offer or {}) do offer[#offer + 1] = row end
    for _, row in pairs(selection and selection.request or {}) do request[#request + 1] = row end
    return offer, request
end

local function debugHouseDirection(dx, dy)
    local horizontal = dx < 0 and "W" or "E"
    local vertical = dy < 0 and "N" or "S"
    local absoluteX, absoluteY = math.abs(dx), math.abs(dy)
    if absoluteX < 1 and absoluteY < 1 then return "HERE" end
    if absoluteX > absoluteY * 2 then return horizontal end
    if absoluteY > absoluteX * 2 then return vertical end
    return vertical .. horizontal
end

function UI.debugHouseLocation(factionOrSummary, player)
    local summary = factionOrSummary
    if type(summary) == "string" and SC.Factions
        and type(SC.Factions.summary) == "function" then
        summary = SC.Factions.summary(summary)
    elseif type(summary) == "table" and summary.house == nil and summary.id
        and SC.Factions and type(SC.Factions.summary) == "function" then
        summary = SC.Factions.summary(summary.id) or summary
    end
    local anchor = type(summary) == "table" and type(summary.house) == "table"
        and summary.house.anchor or nil
    local x, y, z = anchor and tonumber(anchor.x), anchor and tonumber(anchor.y),
        anchor and tonumber(anchor.z) or 0
    if not x or not y then return nil end
    player = player or playerForUI()
    local px, py
    if player and SC.GameplayUtil and type(SC.GameplayUtil.position) == "function" then
        px, py = SC.GameplayUtil.position(player)
    end
    local dx, dy = (px and x - px or 0), (py and y - py or 0)
    local distance = px and py and math.sqrt(dx * dx + dy * dy) or nil
    return {
        factionId = summary and summary.id or nil,
        x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        distance = distance,
        direction = px and py and debugHouseDirection(dx, dy) or "?",
    }
end

function UI.clearDebugHouseLocator()
    local locator = UI._debugHouseLocator
    if type(locator) == "table" then
        if locator.square then safeMethod(locator.square, "remove") end
        if locator.homing then safeMethod(locator.homing, "remove") end
    end
    UI._debugHouseLocator = nil
    return true
end

function UI.locateDebugFactionHouse(factionId)
    local location = UI.debugHouseLocation(factionId, playerForUI())
    if not location then return false, UI.text("UI_SC_Debug_HouseUnavailable") end
    UI.clearDebugHouseLocator()
    local player = playerForUI()
    local markers
    if type(getWorldMarkers) == "function" then
        local ok, value = pcall(getWorldMarkers)
        if ok then markers = value end
    end
    local locator = { factionId = location.factionId }
    if markers and player then
        local square = SC.GameplayUtil and type(SC.GameplayUtil.gridSquare) == "function"
            and SC.GameplayUtil.gridSquare(location.x, location.y, location.z) or nil
        if square then
            local ok, marker = pcall(function()
                return markers:addGridSquareMarker(square, 0.92, 0.76, 0.18, true, 2.5)
            end)
            if ok then
                locator.square = marker
                if marker then safeMethod(marker, "setScaleCircleTexture", true) end
            end
        end
        local ok, homing = pcall(function()
            return markers:addPlayerHomingPoint(player, location.x, location.y,
                0.92, 0.76, 0.18, 1)
        end)
        if ok then locator.homing = homing end
    end
    UI._debugHouseLocator = locator
    return true, UI.text("UI_SC_Debug_HouseLocation", location.x, location.y,
        location.z, location.direction, numericText(location.distance, 1))
end

local function onFactionButton(target, button)
    if not SC.Factions then return end
    local action, factionId = button.scFactionAction, button.scFactionId
    local ok, accepted, reason
    if string.sub(tostring(action), 1, 5) == "talk_" then
        ok, accepted, reason = pcall(SC.FactionContracts.talk, factionId,
            playerForUI(), string.sub(action, 6), false)
    elseif action == "recruitment_ask" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.ask,
            factionId, playerForUI(), false)
    elseif action == "recruitment_trial" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.startTrial,
            factionId, playerForUI(), false)
    elseif action == "recruitment_decide" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.decide,
            factionId, playerForUI())
    elseif action == "recruitment_return" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.returnNow,
            factionId, playerForUI(), false)
    elseif action == "recruitment_debug_prepare" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.debugPrepare, factionId)
    elseif action == "recruitment_debug_candidate" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.debugCandidate,
            factionId, playerForUI())
    elseif action == "recruitment_debug_trial" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.debugTrial,
            factionId, playerForUI())
    elseif string.sub(tostring(action), 1, 27) == "recruitment_debug_decision_" then
        ok, accepted, reason = pcall(SC.FactionRecruitment.debugDecision,
            factionId, playerForUI(), string.sub(action, 28))
    elseif action == "accept_contract" then
        ok, accepted, reason = pcall(SC.FactionContracts.accept,
            factionId, playerForUI(), false)
    elseif action == "fulfill_contract" then
        ok, accepted, reason = pcall(SC.FactionContracts.fulfill,
            factionId, playerForUI(), false)
    elseif action == "withdraw_contract" then
        local summary = SC.Factions.summary(factionId)
        local contractId = summary and summary.social and summary.social.active
            and summary.social.active.id or nil
        local now = SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function"
            and SC.GameplayUtil.nowMs() or 0
        local pending = target.pendingContractWithdraw
        if not pending or pending.factionId ~= factionId or pending.contractId ~= contractId
            or now > (tonumber(pending.untilMs) or 0) then
            target.pendingContractWithdraw = {
                factionId = factionId, contractId = contractId, untilMs = now + 8000,
            }
            setButtonFeedback(target, UI.text("UI_SC_Faction_WithdrawConfirm"), false)
            return
        end
        target.pendingContractWithdraw = nil
        ok, accepted, reason = pcall(SC.FactionContracts.withdraw,
            factionId, playerForUI(), false)
    elseif action == "request_access" then
        ok, accepted, reason = pcall(SC.FactionContracts.requestAccess,
            factionId, playerForUI(), false)
    elseif action == "respect_boundary" or action == "appeal_objection" then
        ok, accepted, reason = pcall(SC.FactionContracts.resolveAccessDispute,
            factionId, playerForUI(), action == "respect_boundary"
                and "respect_boundary" or "appeal", false)
    elseif string.sub(tostring(action), 1, 15) == "contract_offer_" then
        ok, accepted, reason = pcall(SC.FactionContracts.debugOffer,
            factionId or newestFactionId(false), string.sub(action, 16))
    elseif string.sub(tostring(action), 1, 13) == "complication_" then
        ok, accepted, reason = pcall(SC.FactionContracts.debugComplication,
            factionId or newestFactionId(false), string.sub(action, 14))
    elseif action == "complete_contract" then
        ok, accepted, reason = pcall(SC.FactionContracts.debugComplete,
            factionId or newestFactionId(false))
    elseif action == "expire_contract" then
        ok, accepted, reason = pcall(SC.FactionContracts.debugExpire,
            factionId or newestFactionId(false))
    elseif string.sub(tostring(action), 1, 16) == "contract_access_" then
        ok, accepted, reason = pcall(SC.FactionContracts.debugAccess,
            factionId or newestFactionId(false), string.sub(action, 17))
    elseif action == "request" then
        ok, accepted, reason = pcall(SC.Factions.fulfillRequest, factionId, playerForUI())
    elseif action == "barter" then
        local offered, requested = selectedTradeRows(target, factionId)
        ok, accepted, reason = pcall(SC.Trade.barter, factionId,
            playerForUI(), offered, requested)
        if ok and accepted == true and target.tradeSelections then
            target.tradeSelections[factionId] = nil
        end
    elseif action == "reconcile" then
        local offered = selectedTradeRows(target, factionId)
        ok, accepted, reason = pcall(SC.Trade.payRestitution, factionId,
            playerForUI(), offered)
        if ok and accepted == true and target.tradeSelections then
            target.tradeSelections[factionId] = nil
        end
    elseif action == "spawn_1" or action == "spawn_2" or action == "spawn_3" then
        ok, accepted, reason = pcall(SC.Factions.debugSpawnHousehold, playerForUI(),
            tonumber(string.sub(action, -1)))
    elseif action == "spawn_random" then
        ok, accepted, reason = pcall(SC.Factions.debugSpawnHousehold, playerForUI(), "random")
    elseif action == "locate_house" then
        local located, message = UI.locateDebugFactionHouse(factionId or newestFactionId(false))
        setButtonFeedback(target, message, located == true)
        return
    elseif action == "clear_house_marker" then
        UI.clearDebugHouseLocator()
        setButtonFeedback(target, UI.text("UI_SC_Debug_HouseMarkerCleared"), true)
        return
    elseif string.sub(tostring(action), 1, 12) == "world_event_" then
        ok, accepted, reason = pcall(SC.FactionWorld.debugForceEvent,
            string.sub(action, 13))
    elseif action == "advance_job" then
        ok, accepted, reason = pcall(SC.Factions.debugAdvanceJob,
            factionId or newestFactionId(false))
    elseif action == "force_wary" or action == "force_trusted" or action == "force_hostile" then
        local standing = action == "force_wary" and "Wary"
            or action == "force_trusted" and "Trusted" or "Hostile"
        ok, accepted, reason = pcall(SC.Factions.forceStanding,
            factionId or newestFactionId(false), standing)
    elseif action == "force_request" then
        ok, accepted, reason = pcall(SC.Factions.debugForceRequest,
            factionId or newestFactionId(false), "materials")
    elseif action == "unlock_barter" or action == "lock_barter" then
        ok, accepted, reason = pcall(SC.Factions.debugSetBarter,
            factionId or newestFactionId(false), action == "unlock_barter")
    elseif action == "ask_rumour" then
        ok, accepted, reason = pcall(SC.FactionLife.shareRumour,
            factionId or newestFactionId(false), playerForUI(), false)
    elseif string.sub(tostring(action), 1, 12) == "personality_" then
        local personality = string.sub(action, 13)
        ok, accepted, reason = pcall(SC.FactionLife.debugSetPersonality,
            factionId or newestFactionId(false), personality)
    elseif string.sub(tostring(action), 1, 7) == "crisis_" then
        local crisis = string.sub(action, 8)
        ok, accepted, reason = pcall(SC.FactionLife.debugTriggerCrisis,
            factionId or newestFactionId(false), crisis)
    elseif action == "resolve_crisis" then
        ok, accepted, reason = pcall(SC.FactionLife.debugResolveCrisis,
            factionId or newestFactionId(false))
    elseif action == "advance_routine" then
        ok, accepted, reason = pcall(SC.FactionLife.debugAdvanceRoutine,
            factionId or newestFactionId(false))
    elseif action == "audit_resources" then
        ok, accepted, reason = pcall(SC.FactionLife.debugAuditResources,
            factionId or newestFactionId(false))
    elseif action == "share_rumour" then
        ok, accepted, reason = pcall(SC.FactionLife.debugShareRumour,
            factionId or newestFactionId(false), playerForUI())
    elseif action == "delete" then
        local id = factionId or newestFactionId(false)
        if target.pendingDebugDeleteId ~= id then
            target.pendingDebugDeleteId = id
            setButtonFeedback(target, UI.text("UI_SC_Debug_DeleteConfirm"), false)
            return
        end
        target.pendingDebugDeleteId = nil
        ok, accepted, reason = pcall(SC.Factions.debugDelete, id)
    elseif action == "inspect" then
        local summary = SC.Factions.summary(factionId or newestFactionId(false))
        if summary then
            setButtonFeedback(target, UI.text("UI_SC_Debug_InspectResult",
                summary.id, summary.lifecycle, summary.alive, summary.active), true)
        else
            setButtonFeedback(target, UI.text("UI_SC_Base_ActionFailed", "No faction exists."), false)
        end
        return
    end
    local successful = ok and accepted == true
    if successful and (action == "spawn_1" or action == "spawn_2"
        or action == "spawn_3" or action == "spawn_random") then
        local located, locationText = UI.locateDebugFactionHouse(reason)
        if located then reason = locationText end
    end
    setButtonFeedback(target, successful
        and UI.text("UI_SC_CommandAcceptedResult", button.scLabel, tostring(reason or "Done"))
        or UI.text("UI_SC_Base_ActionFailed", tostring(reason or accepted)), successful)
    UI.refresh()
end

local function onSupportButton(target, button)
    if not SC.Support then
        setButtonFeedback(target, UI.text("UI_SC_Support_Unavailable"), false)
        return
    end
    local action = button and button.scSupportAction or "refresh"
    if action == "copy" then
        local ok, reason = SC.Support.copySummary(true)
        setButtonFeedback(target, tostring(reason), ok == true)
    elseif action == "performance_copy" then
        local ok, reason = SC.Support.copyPerformance()
        setButtonFeedback(target, tostring(reason), ok == true)
    elseif action == "performance_reset" then
        local ok, reason = SC.Support.resetPerformance()
        setButtonFeedback(target, tostring(reason), ok == true)
    elseif action == "performance_refresh" then
        setButtonFeedback(target, UI.text("UI_SC_Debug_PerformanceRefreshed"), true)
    elseif action == "movement_copy" then
        local row = target.root and target.root.selectedRow or nil
        local ok, reason = SC.Support.copyMovement(row and row.actor or nil)
        setButtonFeedback(target, tostring(reason), ok == true)
    elseif action == "movement_clear" then
        local row = target.root and target.root.selectedRow or nil
        local ok, reason = SC.Support.clearMovement(row and row.actor or nil)
        setButtonFeedback(target, tostring(reason), ok == true)
    elseif action == "movement_refresh" then
        setButtonFeedback(target, UI.text("UI_SC_Debug_MovementRefreshed"), true)
    elseif action == "retry" then
        local ok, count = SC.Support.retryFailures()
        setButtonFeedback(target, ok and UI.text("UI_SC_Support_Retried", count or 0)
            or UI.text("UI_SC_Support_Unavailable"), ok == true)
    else
        local status = SC.Support.snapshot(true)
        local bridge = status and status.bridge or {}
        setButtonFeedback(target, bridge.ready == true
            and UI.text("UI_SC_Support_Ready")
            or tostring(bridge.reason or UI.text("UI_SC_Support_Unavailable")),
            bridge.ready == true)
    end
    target:rebuild(true)
end

local SCUIDetail = ISPanel:derive("SCUIDetail")

local SCUIClippedScrollPanel = ISPanel:derive("SCUIClippedScrollPanel")

function SCUIClippedScrollPanel:new(x, y, width, height)
    local object = ISPanel.new(self, x, y, width, height)
    object.background = false
    return object
end

function SCUIClippedScrollPanel:prerender()
    ISPanel.prerender(self)
    self:setStencilRect(0, 0, self:getWidth(), self:getHeight())
end

function SCUIClippedScrollPanel:render()
    ISPanel.render(self)
    self:clearStencilRect()
    self:repaintStencilRect(0, 0, self:getWidth(), self:getHeight())
end

function SCUIClippedScrollPanel:onMouseWheel(delta)
    self:setYScroll(self:getYScroll() - delta * 30)
    return true
end

function SCUIDetail:new(x, y, width, height, root)
    local object = ISPanel.new(self, x, y, width, height)
    object.root = root
    object.background = false
    object.borderColor = { r = 0.45, g = 0.47, b = 0.41, a = 0.5 }
    object.tab = "overview"
    object.feedback = nil
    object.feedbackUntil = nil
    object.feedbackSuccess = false
    object.metrics = UI.layoutMetrics()
    object.lastContentHeight = 0
    return object
end

function SCUIDetail:createChildren()
    ISPanel.createChildren(self)
    self:rebuild()
end

-- Command feedback owns a fixed footer below the scroll viewport. Keeping the
-- space reserved even while the message is hidden prevents a late "Order
-- sent" banner from covering the final information line or command button.
function SCUIDetail:feedbackFooterHeight()
    local metrics = self.metrics or UI.layoutMetrics()
    return 12 + (2 * metrics.infoLineHeight)
end

function SCUIDetail:contentViewportHeight()
    return math.max(1, self:getHeight() - self:feedbackFooterHeight() - 2)
end

function SCUIDetail:addInformationLine(panel, y, labelKey, value)
    local textValue = UI.text(labelKey, value or unknownValue())
    local metrics = self.metrics or UI.layoutMetrics()
    local maximumWidth = math.max(80, panel:getWidth() - 32)
    local lines = UI.wrapText(UIFont.Small, textValue, maximumWidth)
    for _, line in ipairs(lines) do
        local label = ISLabel:new(8, y, metrics.fontHeight, line, 0.88, 0.89, 0.83, 1, UIFont.Small, true)
        label:initialise()
        label.tooltip = textValue
        panel:addChild(label)
        panel.scContentWidth = math.max(panel.scContentWidth or panel:getWidth(), UI.textWidth(UIFont.Small, line) + 24)
        y = y + metrics.infoLineHeight
    end
    return y
end

function SCUIDetail:addSection(panel, y, labelKey)
    local metrics = self.metrics or UI.layoutMetrics()
    local textValue = UI.text(labelKey)
    local label = ISLabel:new(8, y, metrics.fontHeight, textValue, 0.79, 0.73, 0.48, 1, UIFont.Small, true)
    label:initialise()
    panel:addChild(label)
    panel.scContentWidth = math.max(panel.scContentWidth or panel:getWidth(), UI.textWidth(UIFont.Small, textValue) + 24)
    return y + metrics.sectionHeight
end

function SCUIDetail:addCommand(panel, y, labelKey, command, payload)
    local metrics = self.metrics or UI.layoutMetrics()
    local availableWidth = math.max(100, panel:getWidth() - 28)
    local fullLabel = UI.text(labelKey)
    local buttonWidth = availableWidth
    local visibleLabel = fitText(UIFont.Small, fullLabel, math.max(40, buttonWidth - 16))
    local button = ISButton:new(8, y, buttonWidth, metrics.buttonHeight, visibleLabel, self, onCommandButton)
    button:initialise()
    makeButtonTranslucent(button)
    button:setWidth(buttonWidth)
    button.scCommand = command
    button.scPayload = payload
    button.scLabel = fullLabel
    local enabled, reasonKey, reasonArgument = UI.commandAvailability(self.root and self.root.selectedRow or nil, command, payload)
    if button.setEnable then
        button:setEnable(enabled)
    end
    button.enable = enabled
    if not enabled then
        if reasonArgument ~= nil then
            button.tooltip = UI.text(reasonKey, reasonArgument)
        else
            button.tooltip = UI.text(reasonKey)
        end
    else
        button.tooltip = fullLabel
    end
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addBooleanCommand(panel, y, labelKey, command, rowField, selected)
    local metrics = self.metrics or UI.layoutMetrics()
    local availableWidth = math.max(100, panel:getWidth() - 28)
    local fullLabel = UI.text(labelKey)
    local boxHeight = math.max(18, metrics.fontHeight)
    local visibleLabel = fitText(UIFont.Small, fullLabel,
        math.max(40, availableWidth - boxHeight - 14))
    local tickBox = ISTickBox:new(12, y, availableWidth, boxHeight, "", self,
        onBooleanCommand, command, "enabled")
    tickBox:initialise()
    tickBox.background = false
    tickBox:addOption(visibleLabel, command)
    tickBox:setSelected(1, selected == true)
    tickBox.scLabel = fullLabel
    tickBox.scRowField = rowField
    local row = self.root and self.root.selectedRow or nil
    local enabled, reasonKey, reasonArgument = UI.commandAvailability(row, command,
        { enabled = selected == true })
    if not enabled then
        tickBox:disableOption(visibleLabel, true)
        tickBox.tooltip = reasonArgument ~= nil and UI.text(reasonKey, reasonArgument)
            or UI.text(reasonKey)
    else
        tickBox.tooltip = fullLabel
    end
    panel:addChild(tickBox)
    panel.scContentWidth = panel:getWidth()
    return y + math.max(metrics.buttonHeight, tickBox:getHeight()) + 4
end

function SCUIDetail:addCommandSelector(panel, y, labelKey, currentValue, options,
        command, payloadKey)
    local metrics = self.metrics or UI.layoutMetrics()
    local availableWidth = math.max(100, panel:getWidth() - 28)
    local label = UI.text(labelKey)
    local combo = ISComboBox:new(8, y, availableWidth, metrics.buttonHeight,
        self, onCommandSelector)
    combo:initialise()
    combo:instantiate()
    combo.backgroundColor = { r = 0.035, g = 0.04, b = 0.035,
        a = configuredOpacity(0.88, 0.22, 0.78) }
    combo.backgroundColorMouseOver = { r = 0.28, g = 0.30, b = 0.25,
        a = configuredOpacity(1.18, 0.48, 0.9) }
    combo.scValue = currentValue
    combo.scLabel = label
    local selected = false
    for index, option in ipairs(options or {}) do
        local optionLabel = UI.text(option.key)
        local optionCommand = option.command or command
        local optionPayload = option.payload
        combo:addOptionWithData(optionLabel, {
            value = option.id,
            label = optionLabel,
            command = optionCommand,
            payload = optionPayload,
            payloadKey = option.payloadKey or payloadKey,
        }, option.tooltipKey and UI.text(option.tooltipKey) or optionLabel)
        if option.id == currentValue then combo.selected, selected = index, true end
    end
    if not selected and currentValue ~= nil then
        local currentLabel = UI.text("UI_SC_Select_Current", UI.stateText(currentValue))
        combo:addOptionWithData(currentLabel, {
            value = currentValue, label = currentLabel, command = nil,
        }, currentLabel)
        combo.selected = #(combo.options or {})
    end
    local first = options and options[1] or nil
    local availabilityCommand = first and (first.command or command) or command
    local availabilityPayload = {}
    if first and (first.payloadKey or payloadKey) then
        availabilityPayload[first.payloadKey or payloadKey] = first.id
    elseif first and type(first.payload) == "table" then
        availabilityPayload = first.payload
    end
    local row = self.root and self.root.selectedRow or nil
    local enabled, reasonKey, reasonArgument = UI.commandAvailability(
        row, availabilityCommand,
        tableHasEntries(availabilityPayload) and availabilityPayload or nil)
    combo:setEnabled(enabled)
    combo.tooltip = enabled and label
        or (reasonArgument ~= nil and UI.text(reasonKey, reasonArgument) or UI.text(reasonKey))
    panel:addChild(combo)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addDoctrineSelector(panel, y, doctrine)
    local metrics = self.metrics or UI.layoutMetrics()
    local availableWidth = math.max(100, panel:getWidth() - 28)
    local combo = ISComboBox:new(8, y, availableWidth, metrics.buttonHeight,
        self, onDoctrineChange)
    combo:initialise()
    combo:instantiate()
    combo.backgroundColor = { r = 0.035, g = 0.04, b = 0.035,
        a = configuredOpacity(0.88, 0.22, 0.78) }
    combo.backgroundColorMouseOver = { r = 0.28, g = 0.30, b = 0.25,
        a = configuredOpacity(1.18, 0.48, 0.9) }
    combo.scDoctrine = doctrine
    for index, option in ipairs(COMBAT_DOCTRINES) do
        combo:addOptionWithData(UI.text(option.key), option.id,
            UI.text(option.key .. "_Tooltip"))
        if option.id == doctrine then combo.selected = index end
    end
    local row = self.root and self.root.selectedRow or nil
    local enabled, reasonKey, reasonArgument = UI.commandAvailability(row,
        "set_combat_doctrine", { doctrine = doctrine, scope = "team" })
    combo:setEnabled(enabled)
    combo.tooltip = enabled and UI.text("UI_SC_Doctrine_TeamTooltip")
        or (reasonArgument ~= nil and UI.text(reasonKey, reasonArgument) or UI.text(reasonKey))
    panel:addChild(combo)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addSignal(panel, y, labelKey, signal)
    local metrics = self.metrics or UI.layoutMetrics()
    local availableWidth = math.max(100, panel:getWidth() - 28)
    local fullLabel = UI.text(labelKey)
    local buttonWidth = availableWidth
    local visibleLabel = fitText(UIFont.Small, fullLabel, math.max(40, buttonWidth - 16))
    local button = ISButton:new(8, y, buttonWidth, metrics.buttonHeight, visibleLabel, self, onSignalButton)
    button:initialise()
    makeButtonTranslucent(button)
    button:setWidth(buttonWidth)
    button.scSignal = signal
    button.scLabel = fullLabel
    local enabled, reasonKey = UI.signalAvailability(self.root, signal)
    if button.setEnable then
        button:setEnable(enabled)
    end
    button.enable = enabled
    button.tooltip = enabled and fullLabel or UI.text(reasonKey)
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addCrisisAction(panel, y, labelKey, crisisId, outcome, action)
    local metrics = self.metrics or UI.layoutMetrics()
    local label = UI.text(labelKey)
    local width = math.max(100, panel:getWidth() - 28)
    local visibleLabel = fitText(UIFont.Small, label, math.max(40, width - 16))
    local button = ISButton:new(8, y, width, metrics.buttonHeight, visibleLabel, self, onCrisisButton)
    button:initialise()
    makeButtonTranslucent(button)
    button.scCrisisId, button.scOutcome = crisisId, outcome
    button.scCrisisAction = action or "choose"
    button.scLabel = label
    button.tooltip = label
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addBaseToggle(panel, y, labelKey, policyKey, selected)
    local metrics = self.metrics or UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local label = UI.text(labelKey)
    local tick = ISTickBox:new(12, y, width, math.max(18, metrics.fontHeight), "",
        self, onBaseToggle, policyKey)
    tick:initialise()
    tick.background = false
    tick:addOption(fitText(UIFont.Small, label,
        math.max(40, width - metrics.fontHeight - 14)), policyKey)
    tick:setSelected(1, selected == true)
    tick.tooltip = label
    panel:addChild(tick)
    panel.scContentWidth = panel:getWidth()
    return y + math.max(metrics.buttonHeight, tick:getHeight()) + 4
end

function SCUIDetail:addBasePolicySelector(panel, y, labelKey, policyKey, current, options)
    local metrics = self.metrics or UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local combo = ISComboBox:new(8, y, width, metrics.buttonHeight,
        self, onBasePolicySelector)
    combo:initialise()
    combo:instantiate()
    combo.backgroundColor = { r = 0.035, g = 0.04, b = 0.035,
        a = configuredOpacity(0.88, 0.22, 0.78) }
    combo.backgroundColorMouseOver = { r = 0.28, g = 0.30, b = 0.25,
        a = configuredOpacity(1.18, 0.48, 0.9) }
    combo.scPolicyKey, combo.scValue = policyKey, current
    for index, option in ipairs(options or {}) do
        local label = UI.text(option.key)
        combo:addOptionWithData(label, { value = option.id }, label)
        if option.id == current then combo.selected = index end
    end
    combo.tooltip = UI.text(labelKey)
    panel:addChild(combo)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addAutonomyAction(panel, y, labelKey, choice)
    local metrics = self.metrics or UI.layoutMetrics()
    local label = UI.text(labelKey)
    local width = math.max(100, panel:getWidth() - 28)
    local visibleLabel = fitText(UIFont.Small, label, math.max(40, width - 16))
    local button = ISButton:new(8, y, width, metrics.buttonHeight, visibleLabel, self, onAutonomyButton)
    button:initialise()
    makeButtonTranslucent(button)
    button.scAutonomyChoice, button.scLabel = choice, label
    button.tooltip = label
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addFactionAction(panel, y, labelKey, action, factionId)
    local metrics = self.metrics or UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local label = UI.text(labelKey)
    local button = ISButton:new(8, y, width, metrics.buttonHeight,
        fitText(UIFont.Small, label, math.max(40, width - 16)), self, onFactionButton)
    button:initialise()
    makeButtonTranslucent(button)
    button.scFactionAction, button.scFactionId, button.scLabel = action, factionId, label
    button.tooltip = label
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addSupportAction(panel, y, labelKey, action)
    local metrics = self.metrics or UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local label = UI.text(labelKey)
    local button = ISButton:new(8, y, width, metrics.buttonHeight,
        fitText(UIFont.Small, label, math.max(40, width - 16)), self, onSupportButton)
    button:initialise()
    makeButtonTranslucent(button)
    button.scSupportAction, button.scLabel = action, label
    button.tooltip = label
    panel:addChild(button)
    panel.scContentWidth = panel:getWidth()
    return y + metrics.buttonHeight + 4
end

function SCUIDetail:addTradeChoice(panel, y, side, factionId, row, selected)
    local metrics = self.metrics or UI.layoutMetrics()
    local width = math.max(100, panel:getWidth() - 28)
    local name = SC.GameplayUtil and SC.GameplayUtil.itemName
        and SC.GameplayUtil.itemName(row.item) or UI.humanize(row.type)
    local label = fitText(UIFont.Small,
        tostring(name) .. " | value " .. tostring(row.value or 0), math.max(40, width - 28))
    local tick = ISTickBox:new(12, y, width, math.max(18, metrics.fontHeight), "",
        self, onTradeChoice, side, factionId)
    tick:initialise()
    tick.background = false
    tick:addOption(label, row.item)
    tick:setSelected(1, selected == true)
    tick.scTradeRow = row
    tick.tooltip = tostring(name) .. " | trade value " .. tostring(row.value or 0)
    panel:addChild(tick)
    panel.scContentWidth = panel:getWidth()
    return y + math.max(metrics.buttonHeight, tick:getHeight()) + 2
end

function SCUIDetail:buildOverview(panel, row)
    local y = 7
    -- Recruitment is the primary action for a neutral encounter. Keep it
    -- visible without scrolling, then remove it entirely once accepted.
    if row and row.recruited ~= true then
        y = self:addCommand(panel, y, "UI_SC_Action_Recruit", "recruit", nil)
        y = y + 4
    end
    y = self:addSection(panel, y, "UI_SC_Section_Status")
    if not row then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_NoSelection"))
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Name", row.name)
        y = self:addInformationLine(panel, y, "UI_SC_Info_Health", UI.healthText(row.health))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Hunger",
            numericText((tonumber(row.hunger) or 0) * 100, 0) .. "%")
        y = self:addInformationLine(panel, y, "UI_SC_Info_Thirst",
            numericText((tonumber(row.thirst) or 0) * 100, 0) .. "%")
        y = self:addInformationLine(panel, y, "UI_SC_Info_Wounds", UI.formatWounds(row.wounds))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Supplies", UI.formatSupplies(row.supplies))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Ammunition", UI.formatAmmunition(row.ammunition))
        local loadText = numericText(row.loadWeight, 1) .. " / "
            .. numericText(row.loadCapacity, 1) .. " ("
            .. numericText((tonumber(row.loadRatio) or 0) * 100, 0) .. "%)"
        if row.loadRole then loadText = loadText .. " | " .. UI.stateText(row.loadRole) end
        y = self:addInformationLine(panel, y, "UI_SC_Info_Load", loadText)
        y = self:addInformationLine(panel, y, "UI_SC_Info_AllowOverload",
            UI.booleanText(row.allowOverload))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Order", UI.stateText(row.order))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Intent", UI.stateText(row.intent or row.activity))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Distance", UI.distanceText(row.distance))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Scavenging", UI.booleanText(row.scavenge))
        if type(row.scavengeStatus) == "table" then
            if row.scavengeStatus.phase then
                local statusText = row.scavengeStatus.itemName
                    and (UI.stateText(row.scavengeStatus.phase) .. ": "
                        .. tostring(row.scavengeStatus.itemName))
                    or UI.stateText(row.scavengeStatus.phase)
                if row.scavengeStatus.progress and row.scavengeStatus.total then
                    statusText = statusText .. " " .. tostring(row.scavengeStatus.progress)
                        .. "/" .. tostring(row.scavengeStatus.total)
                end
                if row.scavengeStatus.destinationName then
                    statusText = statusText .. " -> " .. tostring(row.scavengeStatus.destinationName)
                elseif row.scavengeStatus.destination then
                    statusText = statusText .. " -> " .. UI.stateText(row.scavengeStatus.destination)
                end
                y = self:addInformationLine(panel, y, "UI_SC_Info_ScavengeStatus", statusText)
            end
            local lastLoot = row.scavengeStatus.lastLoot
            if type(lastLoot) == "table" and lastLoot.name then
                local destination = lastLoot.destinationName or lastLoot.destination
                local lastText = tostring(lastLoot.name)
                if destination then lastText = lastText .. " -> " .. UI.stateText(destination) end
                y = self:addInformationLine(panel, y, "UI_SC_Info_LastLoot", lastText)
            end
        end
        y = self:addInformationLine(panel, y, "UI_SC_Info_WorkMode", UI.stateText(row.workMode))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Background",
            row.backgroundLabel or unknownValue())
        y = self:addInformationLine(panel, y, "UI_SC_Info_Personality", UI.summaryText(row.personality))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Trust", numericText(row.trust, 0))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Bond", numericText(row.bond, 0))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Mood", UI.stateText(row.mood))
        if type(row.grief) == "table" then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Grief",
                UI.text("UI_SC_Info_GriefValue", row.grief.subjectName or unknownValue(),
                    UI.stateText(row.grief.stage),
                    numericText(row.grief.currentIntensity, 0)))
        end
        y = self:addInformationLine(panel, y, "UI_SC_Info_Morale", numericText(row.morale, 0))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Stress", numericText(row.stress, 0))
        y = self:addInformationLine(panel, y, "UI_SC_Info_StressResponse",
            row.stressResponseLabel or unknownValue())
        y = self:addInformationLine(panel, y, "UI_SC_Info_JoyResponse",
            row.joyResponseLabel or unknownValue())
        y = self:addInformationLine(panel, y, "UI_SC_Info_Boredom", numericText(row.boredom, 0))
        if type(row.topThoughts) == "table" and #row.topThoughts > 0 then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Thoughts",
                table.concat(row.topThoughts, "; "))
        end
        if row.currentExpectation then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Expectation",
                UI.stateText(row.currentExpectation))
        end
        if row.activeEpisode then
            y = self:addInformationLine(panel, y, "UI_SC_Info_MentalEpisode",
                UI.stateText(row.activeEpisode))
        end
        if row.inspiration then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Inspiration",
                UI.stateText(row.inspiration))
        end
        y = self:addInformationLine(panel, y, "UI_SC_Info_Relationship", UI.stateText(row.relationshipTier))
        y = self:addInformationLine(panel, y, "UI_SC_Info_CurrentNeed", UI.stateText(row.currentNeed))
        y = self:addInformationLine(panel, y, "UI_SC_Info_TimeTogether", numericText(row.timeTogetherHours, 1))
        y = self:addInformationLine(panel, y, "UI_SC_Info_RecentMemory", UI.summaryText(row.recentMemory))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Knox", UI.formatKnox(row.knox))
        y = self:addInformationLine(panel, y, "UI_SC_Info_CombatStance",
            UI.stateText(row.combatStance))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Combat",
            UI.stateText(row.combatDoctrine))
        y = self:addInformationLine(panel, y, "UI_SC_Info_FollowDistance", UI.distanceText(row.followDistance))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Group", UI.stateText(row.group))
    end
    if row and type(row.pendingRequest) == "table"
        and row.pendingRequest.kind == "supply_run" then
        y = self:addSection(panel, y + 4, "UI_SC_Section_Request")
        y = self:addInformationLine(panel, y, "UI_SC_Info_Request",
            UI.text("UI_SC_Request_SupplyRun"))
        y = self:addAutonomyAction(panel, y, "UI_SC_Request_Soon", "soon")
        y = self:addAutonomyAction(panel, y, "UI_SC_Request_ComeWithMe", "come_with_me")
        y = self:addAutonomyAction(panel, y, "UI_SC_Request_NotNow", "not_now")
        y = self:addAutonomyAction(panel, y, "UI_SC_Request_CannotSpare", "cannot_spare")
    end
    y = self:addSection(panel, y + 4, "UI_SC_Section_Signals")
    y = self:addSignal(panel, y, "UI_SC_Action_WhistleRegroup", "whistle")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignFollow", "follow")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignHold", "hold")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignRegroup", "regroup")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignCautious", "cautious")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignMoveOut", "move_out")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignCeaseFire", "cease_fire")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignFire", "fire")
    y = self:addSignal(panel, y, "UI_SC_Action_HandSignFallBack", "fall_back")
    y = self:addSection(panel, y + 4, "UI_SC_Section_Conversation")
    y = self:addCommand(panel, y, "UI_SC_Action_Status", "status", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Needs", "needs", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Memory", "memory", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Background", "background", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Opinion", "opinion", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Relationship", "relationship", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Encourage", "encourage", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Praise", "praise", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Plans", "plans", nil)
    if row and row.recruited == true then
        y = self:addCommand(panel, y, "UI_SC_Action_Dismiss", "dismiss", nil)
    end
    y = self:addSection(panel, y + 4, "UI_SC_Section_Emotes")
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteGreet", "emote", { emote = "wavehi" })
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteAcknowledge", "emote", { emote = "signalok" })
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteThank", "emote", { emote = "thankyou" })
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteCelebrate", "emote", { emote = "clap" })
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteSalute", "emote", { emote = "salute" })
    y = self:addCommand(panel, y, "UI_SC_Action_EmoteUnsure", "emote", { emote = "shrug" })
    return y
end

function SCUIDetail:buildOrders(panel)
    local y = 7
    local row = self.root and self.root.selectedRow or nil
    y = self:addSection(panel, y, "UI_SC_Section_DirectOrders")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_MainOrder",
        row and row.order or nil, MAIN_ORDERS)
    y = self:addCommand(panel, y, "UI_SC_Action_Regroup", "regroup", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Retreat", "retreat", nil)
    y = self:addSection(panel, y + 4, "UI_SC_Section_FollowDistance")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_FollowDistance",
        row and tonumber(row.followDistance) or 3, FOLLOW_DISTANCES,
        "set_follow_distance", "distance")
    y = self:addSection(panel, y + 4, "UI_SC_Section_Scavenging")
    y = self:addBooleanCommand(panel, y, "UI_SC_Toggle_Scavenging",
        "set_scavenge", "scavenge", row and row.scavenge == true)
    y = self:addSection(panel, y + 4, "UI_SC_Section_Work")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_WorkMode",
        row and row.workMode or "auto", WORK_MODES, "set_work_mode", "mode")
    y = self:addSection(panel, y + 4, "UI_SC_Section_Movement")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_MovementMode",
        row and row.moveMode or "copy", MOVE_MODES, "set_move_mode", "mode")
    y = self:addSection(panel, y + 4, "UI_SC_Section_Combat")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_CombatStance",
        row and row.combatStance or "defensive", COMBAT_STANCES,
        "set_combat_mode", "mode")
    y = self:addBooleanCommand(panel, y, "UI_SC_Toggle_HoldFire",
        "set_hold_fire", "holdFire", row and row.holdFire == true)
    y = self:addSection(panel, y + 4, "UI_SC_Section_CombatDoctrine")
    y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
        UI.text("UI_SC_Doctrine_TeamScope"))
    local doctrine = row and row.combatDoctrine or "close_defense"
    if SC.Commands and type(SC.Commands.teamCombatDoctrine) == "function" then
        local ok, value = pcall(SC.Commands.teamCombatDoctrine, playerForUI())
        if ok and type(value) == "string" then doctrine = value end
    end
    y = self:addDoctrineSelector(panel, y, doctrine)
    return y
end

function SCUIDetail:buildGear(panel, row)
    local y = 7
    y = self:addSection(panel, y, "UI_SC_Section_Gear")
    if row then
        y = self:addInformationLine(panel, y, "UI_SC_Info_WeaponPriority",
            UI.stateText(row.weaponPriority))
        y = self:addInformationLine(panel, y, "UI_SC_Info_EquippedWeapon",
            row.equippedWeapon or UI.text("UI_SC_State_none"))
    end
    y = self:addCommand(panel, y, "UI_SC_Action_OpenInventory", "open_inventory", nil)
    y = self:addSection(panel, y + 4, "UI_SC_Section_LoadPolicy")
    y = self:addBooleanCommand(panel, y, "UI_SC_Toggle_AllowOverload",
        "set_allow_overload", "allowOverload", row and row.allowOverload == true)
    y = self:addSection(panel, y + 4, "UI_SC_Section_WeaponPriority")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_WeaponPriority",
        row and row.weaponPriority or "best", WEAPON_PRIORITIES,
        "set_weapon_priority", "priority")
    y = self:addSection(panel, y + 4, "UI_SC_Section_Vehicle")
    y = self:addBooleanCommand(panel, y, "UI_SC_Toggle_RideWithPlayer",
        "set_ride_with_player", "rideWithPlayer", row and row.rideWithPlayer ~= false)
    if row and type(row.vehicleStatus) == "table" then
        local statusKey = "UI_SC_VehicleStatus_" .. tostring(row.vehicleStatus.status or "on_foot")
        y = self:addInformationLine(panel, y, "UI_SC_Info_VehicleStatus", UI.text(statusKey))
        if row.vehicleStatus.capacityWait == true then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                UI.text("UI_SC_Vehicle_Waiting", row.vehicleStatus.assigned or 0,
                    row.vehicleStatus.capacity or 0, row.vehicleStatus.waiting or 0))
        elseif row.vehicleStatus.status == "approaching_vehicle" then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                UI.text("UI_SC_Vehicle_Assigned", row.vehicleStatus.seat or "?",
                    row.vehicleStatus.assigned or 0, row.vehicleStatus.capacity or 0,
                    row.vehicleStatus.waiting or 0))
        end
        if row.vehicleStatus.status == "in_vehicle"
            and row.vehicleStatus.canExitNow == true then
            y = self:addCommand(panel, y, "UI_SC_Action_ExitVehicleNow",
                "exit_vehicle", nil)
        end
    end
    return y
end

function SCUIDetail:buildHealth(panel, row)
    local y = 7
    y = self:addSection(panel, y, "UI_SC_Section_Health")
    if not row then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_NoSelection"))
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Name", row.name)
        y = self:addInformationLine(panel, y, "UI_SC_Info_Health", UI.healthText(row.health))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Wounds", UI.formatWounds(row.wounds))
        y = self:addInformationLine(panel, y, "UI_SC_Info_Knox", UI.formatKnox(row.knox))
    end
    y = self:addSection(panel, y + 4, "UI_SC_Section_HealthActions")
    y = self:addCommand(panel, y, "UI_SC_Action_OpenHealth", "open_health", nil)
    y = self:addCommand(panel, y, "UI_SC_Action_Status", "status", nil)
    return y
end

function SCUIDetail:buildBase(panel, row)
    local y = 7
    local base = SC.BaseLife and SC.BaseLife.summary and SC.BaseLife.summary() or { configured = false }
    y = self:addSection(panel, y, "UI_SC_Base_Section_Status")
    if not base.configured then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_Base_NotConfigured"))
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Base_Summary", base.name or "Main Camp", base.zones or 0,
                base.storages or 0, base.residents or 0, base.duty or 0))
        local jobs = base.jobs or {}
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Base_Jobs", jobs.pending or 0, jobs.active or 0, jobs.blocked or 0))
        local operations = base.operations or {}
        y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Operations")
        y = self:addInformationLine(panel, y, "UI_SC_Base_Readiness",
            tostring(operations.readiness or 0))
        if (operations.unloadedStores or 0) > 0 then
            y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                UI.text("UI_SC_Base_UnloadedStores", operations.unloadedStores))
        end
        for _, stock in ipairs(operations.stock or {}) do
            y = self:addInformationLine(panel, y, "UI_SC_Base_Stock",
                UI.text("UI_SC_Base_StockValue", UI.humanize(stock.category),
                    stock.count, stock.target, stock.status))
        end
        for alertIndex = 1, math.min(5, #(operations.alerts or {})) do
            y = self:addInformationLine(panel, y, "UI_SC_Base_Alert",
                operations.alerts[alertIndex])
        end
        y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Policies")
        local policies = operations.policies or {}
        y = self:addBasePolicySelector(panel, y, "UI_SC_Base_DefensePolicy", "defense",
            policies.defense or "rotation", {
                { id = "rotation", key = "UI_SC_Base_Defense_rotation" },
                { id = "role_based", key = "UI_SC_Base_Defense_role_based" },
                { id = "all_hands", key = "UI_SC_Base_Defense_all_hands" },
            })
        y = self:addBasePolicySelector(panel, y, "UI_SC_Base_WorkloadPolicy", "workload",
            policies.workload or "balanced", {
                { id = "essential", key = "UI_SC_Base_Workload_essential" },
                { id = "balanced", key = "UI_SC_Base_Workload_balanced" },
                { id = "continuous", key = "UI_SC_Base_Workload_continuous" },
            })
        y = self:addBaseToggle(panel, y, "UI_SC_Base_RoutineToggle", "routines",
            policies.routines ~= false)
        y = self:addBaseToggle(panel, y, "UI_SC_Base_MaintenanceToggle", "autoMaintenance",
            policies.autoMaintenance ~= false)
        y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Staffing")
        for _, residentRow in ipairs(base.residentRows or {}) do
            y = self:addInformationLine(panel, y, "UI_SC_Base_StaffingRow",
                UI.text("UI_SC_Base_StaffingValue", residentRow.name,
                    UI.humanize(residentRow.role),
                    residentRow.guarding and UI.text("UI_SC_Base_StateGuard")
                        or residentRow.job and UI.humanize(residentRow.job)
                        or residentRow.duty and UI.text("UI_SC_Base_StateAvailable")
                        or UI.text("UI_SC_Base_StateOffDuty")))
        end
    end
    y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Selected")
    if row then
        local resident = SC.BaseLife and SC.BaseLife.resident and SC.BaseLife.resident(row.id) or nil
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Base_Resident", row.name, resident and resident.role or "generalist",
                resident and UI.booleanText(resident.duty == true) or UI.booleanText(false)))
        y = self:addCommand(panel, y, "UI_SC_Base_Duty", "base_duty", nil)
        for _, role in ipairs({ "generalist", "guard", "builder", "quartermaster", "medic" }) do
            y = self:addCommand(panel, y, "UI_SC_Base_Role_" .. role,
                "set_base_role", { role = role })
        end
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_NoSelection"))
    end
    y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Queue")
    if type(base.rows) ~= "table" or #base.rows == 0 then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_Base_NoJobs"))
    else
        for _, job in ipairs(base.rows) do
            y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                UI.text("UI_SC_Base_JobRow", UI.humanize(job.type), UI.humanize(job.state),
                    tostring(job.reservedBy or "-")))
        end
    end
    y = self:addSection(panel, y + 4, "UI_SC_Base_Section_Crisis")
    local crises = SC.InfectionCrisis and SC.InfectionCrisis.summary
        and SC.InfectionCrisis.summary() or { rows = {} }
    if #crises.rows == 0 then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_Base_NoCrisis"))
    else
        for _, crisis in ipairs(crises.rows) do
            y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                UI.text("UI_SC_Base_CrisisRow", crisis.subjectName or crisis.subjectId,
                    UI.humanize(crisis.phase),
                    tostring(math.floor(tonumber(crisis.infectionLevel) or 0)),
                    UI.humanize(crisis.outcome or crisis.strategy)))
            if crisis.phase ~= "resolved" and crisis.phase ~= "terminal" then
                for _, outcome in ipairs({ "watch", "quarantine", "exile", "mercy" }) do
                    if outcome ~= "mercy" or not crisis.subjectIsPlayer then
                        y = self:addCrisisAction(panel, y, "UI_SC_Base_Outcome_" .. outcome,
                            crisis.id, outcome, "choose")
                    end
                end
            elseif (crisis.outcome == "mercy" or crisis.outcome == "self_sacrifice")
                and not crisis.finalAuthorized then
                y = self:addCrisisAction(panel, y, "UI_SC_Base_AuthorizeFinal",
                    crisis.id, crisis.outcome, "authorize")
            end
        end
    end
    return y
end

function SCUIDetail:buildJournal(panel, row)
    local y = 7
    if not row or type(row.journal) ~= "table" then
        y = self:addSection(panel, y, "UI_SC_Section_Journal")
        return self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_NoSelection"))
    end
    local journal = row.journal
    local profile = type(journal.profile) == "table" and journal.profile or {}
    y = self:addSection(panel, y, "UI_SC_Journal_Who")
    local backgroundProfile = type(journal.backgroundProfile) == "table"
        and journal.backgroundProfile or {}
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Profession",
        backgroundProfile.profession or unknownValue())
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Aptitude",
        backgroundProfile.aptitude or unknownValue())
    y = self:addInformationLine(panel, y, "UI_SC_Journal_PreferredRole",
        UI.stateText(backgroundProfile.preferredRole))
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Personality", profile.label or unknownValue())
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Dimensions",
        UI.text("UI_SC_Journal_DimensionValues",
            numericText(profile.courage, 0), numericText(profile.caution, 0),
            numericText(profile.compassion, 0), numericText(profile.practicality, 0)))
    local background = type(journal.background) == "table" and journal.background or {}
    if #background == 0 then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_Journal_PrivateBackground"))
    else
        for _, fact in ipairs(background) do
            y = self:addInformationLine(panel, y, "UI_SC_Journal_Fact",
                UI.text("UI_SC_Journal_FactValue", fact.label or fact.key, UI.humanize(fact.value)))
        end
    end

    local relationship = type(journal.relationship) == "table" and journal.relationship or {}
    y = self:addSection(panel, y + 4, "UI_SC_Journal_Relationship")
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Tier", UI.stateText(relationship.tier))
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Mood", UI.stateText(relationship.mood))
    for _, reason in ipairs(type(relationship.reasons) == "table" and relationship.reasons or {}) do
        y = self:addInformationLine(panel, y, "UI_SC_Journal_Reason", reason)
    end

    local objective = type(journal.objective) == "table" and journal.objective or {}
    y = self:addSection(panel, y + 4, "UI_SC_Journal_Goal")
    if objective.known then
        y = self:addInformationLine(panel, y, "UI_SC_Journal_GoalName", objective.label)
        y = self:addInformationLine(panel, y, "UI_SC_Journal_Progress",
            numericText((tonumber(objective.progress) or 0) * 100, 0) .. "%")
    else
        local key = objective.status == "none" and "UI_SC_Journal_NoGoal" or "UI_SC_Journal_PrivateGoal"
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text(key))
    end

    local keepsake = type(journal.keepsake) == "table" and journal.keepsake or {}
    y = self:addSection(panel, y + 4, "UI_SC_Journal_Keepsake")
    if keepsake.known then
        y = self:addInformationLine(panel, y, "UI_SC_Journal_KeepsakeKind", UI.stateText(keepsake.kind))
        y = self:addInformationLine(panel, y, "UI_SC_Journal_KeepsakeStatus", UI.stateText(keepsake.status))
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("UI_SC_Journal_PrivateKeepsake"))
    end

    y = self:addSection(panel, y + 4, "UI_SC_Journal_Memories")
    local memories = type(journal.memories) == "table" and journal.memories or {}
    if #memories == 0 then
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message", UI.text("IGUI_SC_Memory_None"))
    else
        for _, memory in ipairs(memories) do
            y = self:addInformationLine(panel, y, "UI_SC_Journal_Memory", memory.text)
        end
    end
    y = self:addSection(panel, y + 4, "UI_SC_Journal_SharedLife")
    y = self:addInformationLine(panel, y, "UI_SC_Info_TimeTogether",
        numericText(journal.timeTogetherHours, 1))
    local care = type(journal.care) == "table" and journal.care or {}
    y = self:addInformationLine(panel, y, "UI_SC_Journal_Care",
        UI.text("UI_SC_Journal_CareValues", tonumber(care.treatment) or 0,
            tonumber(care.meals) or 0, tonumber(care.rescues) or 0,
            tonumber(care.goalsCompleted) or 0))
    return y
end

function SCUIDetail:buildGroups(panel, row)
    local y = 7
    y = self:addSection(panel, y, "UI_SC_Section_GroupAssignment")
    y = self:addCommandSelector(panel, y, "UI_SC_Select_Group",
        row and (row.group or "") or "", GROUPS, "set_group", "group")
    y = self:addSection(panel, y + 4, "UI_SC_Section_GroupOrders")
    local group = row and row.group or nil
    y = self:addCommand(panel, y, "UI_SC_Action_GroupFollow", "follow", { scope = "group", group = group })
    y = self:addCommand(panel, y, "UI_SC_Action_GroupStay", "stay", { scope = "group", group = group })
    y = self:addCommand(panel, y, "UI_SC_Action_GroupGuard", "guard", { scope = "group", group = group })
    y = self:addCommand(panel, y, "UI_SC_Action_GroupRegroup", "regroup", { scope = "group", group = group })
    return y
end

local function requestItemsText(items)
    local rows = {}
    for _, item in ipairs(type(items) == "table" and items or {}) do
        local label = item.label or item.type or item.category
            or type(item.types) == "table" and table.concat(item.types, " / ") or "item"
        rows[#rows + 1] = tostring(item.count or 0) .. " x " .. UI.humanize(label)
    end
    return #rows > 0 and table.concat(rows, ", ") or UI.text("UI_SC_Value_None")
end

function SCUIDetail:buildFactions(panel)
    local y = 7
    y = self:addSection(panel, y, "UI_SC_Factions_Discovered")
    local factions = SC.Factions and type(SC.Factions.list) == "function"
        and SC.Factions.list(true) or {}
    if #factions == 0 then
        return self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Factions_None"))
    end
    for index, faction in ipairs(factions) do
        local summary = SC.Factions.summary(faction.id)
        if index > 1 then y = y + 6 end
        y = self:addSection(panel, y, "UI_SC_Factions_Household")
        y = self:addInformationLine(panel, y, "UI_SC_Faction_Name", summary.name)
        y = self:addInformationLine(panel, y, "UI_SC_Faction_Standing", summary.standing)
        y = self:addInformationLine(panel, y, "UI_SC_Faction_Lifecycle",
            UI.stateText(summary.lifecycle))
        y = self:addInformationLine(panel, y, "UI_SC_Faction_Members",
            tostring(summary.alive) .. " alive | " .. tostring(summary.active) .. " active")
        local world = summary.world
        if world then
            y = self:addSection(panel, y + 4, "UI_SC_FactionWorld_Section")
            if #world.relations == 0 then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_FactionWorld_None"))
            else
                for _, relation in ipairs(world.relations) do
                    y = self:addInformationLine(panel, y, "UI_SC_FactionWorld_Relation",
                        UI.text("UI_SC_FactionWorld_RelationValue", relation.name,
                            UI.stateText(relation.status), tostring(relation.score)))
                end
            end
            for newsIndex = 1, math.min(#world.news, 3) do
                y = self:addInformationLine(panel, y, "UI_SC_FactionWorld_News",
                    tostring(world.news[newsIndex].message))
            end
        end
        local social = summary.social
        if social then
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Conversation")
            local canTalk, talkReason = SC.FactionContracts.canTalk(
                summary.id, playerForUI())
            if canTalk then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskStatus",
                    "talk_status", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskNeeds",
                    "talk_needs", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskMembers",
                    "talk_members", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskTrade",
                    "talk_trade", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskDanger",
                    "talk_danger", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskRumours",
                    "talk_rumours", summary.id)
                if social.privateContactAvailable then
                    y = self:addFactionAction(panel, y, "UI_SC_Faction_PrivateTalk",
                        "talk_private", summary.id)
                end
            else
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_TalkUnavailable", UI.stateText(talkReason)))
            end
            if social.lastResponse then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_LastResponse",
                    tostring(social.lastSpeaker or "Representative") .. ": "
                        .. tostring(social.lastResponse))
            end
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Access",
                UI.text("UI_SC_Faction_AccessValue", UI.stateText(social.access.state),
                    UI.stateText(social.access.reason),
                    social.access.safeRest and UI.text("UI_SC_Faction_SafeRestGranted")
                        or UI.text("UI_SC_Faction_SafeRestDenied")))
            local canRest, restReason = SC.FactionContracts.safeRestStatus(
                summary.id, playerForUI())
            y = self:addInformationLine(panel, y, "UI_SC_Faction_SafeRest",
                canRest and UI.text("UI_SC_Faction_SafeRestReady")
                    or UI.text("UI_SC_Faction_SafeRestBlocked", UI.stateText(restReason)))
            if canTalk and social.access.state ~= "guest"
                and social.access.state ~= "contested" then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_RequestAccess",
                    "request_access", summary.id)
            elseif canTalk and social.access.state == "contested" then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_RespectBoundary",
                    "respect_boundary", summary.id)
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AppealObjection",
                    "appeal_objection", summary.id)
            end
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Contract")
            local contract = social.active or social.offer
            if not contract then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_NoContract"))
            else
                y = self:addInformationLine(panel, y, "UI_SC_Faction_ContractTitle",
                    tostring(contract.title))
                y = self:addInformationLine(panel, y, "UI_SC_Faction_ContractStatus",
                    UI.stateText(contract.status))
                if contract.status == "active" or contract.revealed
                    and (contract.hiddenSeverity ~= true or summary.standing == "Trusted") then
                    if contract.requirements then
                        y = self:addInformationLine(panel, y, "UI_SC_Faction_ContractTerms",
                            requestItemsText(contract.requirements))
                    elseif contract.target then
                        y = self:addInformationLine(panel, y, "UI_SC_Faction_ContractTerms",
                            UI.text("UI_SC_Faction_ThreatTerms", contract.target.x,
                                contract.target.y, contract.requiredKills or 0))
                    end
                else
                    y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                        UI.text("UI_SC_Faction_AskNeedFirst"))
                end
                if contract.status == "offered" and contract.revealed and canTalk then
                    y = self:addFactionAction(panel, y, "UI_SC_Faction_AcceptContract",
                        "accept_contract", summary.id)
                elseif contract.status == "active" then
                    y = self:addInformationLine(panel, y, "UI_SC_Faction_Deadline",
                        UI.text("UI_SC_Faction_DeadlineValue",
                            string.format("%.1f", tonumber(social.progress
                                and social.progress.hoursRemaining) or 0),
                            UI.stateText(social.progress and social.progress.urgency or "normal")))
                    local progress = social.progress
                    if progress and contract.kind == "local_threat" then
                        y = self:addInformationLine(panel, y, "UI_SC_Faction_Progress",
                            UI.text("UI_SC_Faction_ThreatProgress", progress.kills or 0,
                                progress.requiredKills or 0,
                                progress.remainingThreats == nil and "unknown"
                                    or tostring(progress.remainingThreats),
                                progress.loadedSquares or 0,
                                progress.minimumLoadedSquares or 0))
                    elseif progress then
                        for _, requirement in ipairs(progress.requirements or {}) do
                            y = self:addInformationLine(panel, y, "UI_SC_Faction_Progress",
                                UI.text("UI_SC_Faction_DeliveryProgress", requirement.label,
                                    requirement.available or 0, requirement.required or 0,
                                    requirement.remaining or 0))
                        end
                    end
                    if contract.marker then
                        y = self:addInformationLine(panel, y, "UI_SC_Faction_MapMarker",
                            UI.text(contract.marker.added and "UI_SC_Faction_MapMarkerActive"
                                or "UI_SC_Faction_MapMarkerPending"))
                    end
                    if contract.kind == "local_threat" or canTalk then
                        y = self:addFactionAction(panel, y, "UI_SC_Faction_FulfillContract",
                            "fulfill_contract", summary.id)
                    end
                    if canTalk then
                        y = self:addFactionAction(panel, y, "UI_SC_Faction_WithdrawContract",
                            "withdraw_contract", summary.id)
                    end
                end
            end
            y = self:addInformationLine(panel, y, "UI_SC_Faction_ContractHistory",
                UI.text("UI_SC_Faction_ContractHistoryValue", social.completedContracts,
                    social.brokenPromises, social.memoryCount))
            if social.householdDebt > 0 then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_HouseholdDebt",
                    tostring(social.householdDebt))
            end
            if social.futureRecruitConsideration then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_FutureRecruitment"))
            end
            local notifications = social.notifications or {}
            local latest = notifications[#notifications]
            if latest then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_LatestUpdate",
                    tostring(latest.message))
            end
        end
        local recruitment = summary.recruitment
        if recruitment then
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Recruitment")
            y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentStatus",
                UI.stateText(recruitment.status))
            if recruitment.candidateName then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentCandidate",
                    recruitment.candidateName)
            end
            y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentRequirements",
                UI.text("UI_SC_Faction_RecruitmentRequirementsValue",
                    recruitment.contractsCompleted or 0, recruitment.contractsRequired or 0,
                    recruitment.presentResidents or 0))
            if recruitment.status == "trial" then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentTrial",
                    UI.text("UI_SC_Faction_RecruitmentTrialValue",
                        numericText(recruitment.hoursOnTrial, 1),
                        numericText(recruitment.hoursUntilDecision, 1)))
            elseif recruitment.cooldownHours and recruitment.cooldownHours > 0 then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentCooldown",
                    numericText(recruitment.cooldownHours, 1))
            end
            y = self:addInformationLine(panel, y, "UI_SC_Faction_RecruitmentReason",
                UI.stateText(recruitment.reason or "unknown"))
            if recruitment.canAsk then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_RecruitmentAsk",
                    "recruitment_ask", summary.id)
            elseif recruitment.canStartTrial then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_RecruitmentStartTrial",
                    "recruitment_trial", summary.id)
            elseif recruitment.status == "trial" then
                if recruitment.canDecide then
                    y = self:addFactionAction(panel, y, "UI_SC_Faction_RecruitmentAskDecision",
                        "recruitment_decide", summary.id)
                end
                y = self:addFactionAction(panel, y, "UI_SC_Faction_RecruitmentEndTrial",
                    "recruitment_return", summary.id)
            elseif recruitment.status == "joined" then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_RecruitmentJoined"))
            elseif recruitment.status == "returned" then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_RecruitmentReturned"))
            end
        end
        local life = summary.life
        if life then
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Life")
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Personality",
                life.personality)
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Resources",
                UI.text("UI_SC_Faction_ResourceValue",
                    UI.stateText(life.resources.level),
                    UI.humanize(life.resources.shortage or "none")))
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Representative",
                UI.stateText(life.representative.state or "inside"))
            if type(life.mourning) == "table" then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Mourning",
                    UI.text("UI_SC_Faction_MourningValue",
                        life.mourning.subjectName or unknownValue(),
                        numericText(life.mourning.hoursRemaining, 1)))
            end
            for _, member in ipairs(life.members or {}) do
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Routine",
                    UI.text("UI_SC_Faction_RoutineValue", member.name,
                        UI.stateText(member.routine), UI.humanize(member.role)))
            end
            for _, relation in ipairs(life.relations or {}) do
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Relationship",
                    UI.text("UI_SC_Faction_RelationshipValue", relation.leftName,
                        relation.rightName, relation.kind, relation.trust, relation.tension))
            end
            if life.crisis then
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Crisis",
                    UI.stateText(life.crisis.kind))
            else
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Crisis",
                    UI.text("UI_SC_Value_None"))
            end
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Rumours",
                UI.text("UI_SC_Faction_RumoursValue",
                    life.rumoursShared, life.rumoursTotal))
            if (summary.standing == "Tolerated" or summary.standing == "Trusted")
                and life.rumoursShared < life.rumoursTotal then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_AskRumour",
                    "ask_rumour", summary.id)
            end
        end
        if summary.request and not social then
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Request",
                summary.request.label .. ": " .. requestItemsText(summary.request.required))
            y = self:addInformationLine(panel, y, "UI_SC_Faction_Reward",
                requestItemsText(summary.request.reward))
            if summary.request.status == "available" then
                y = self:addFactionAction(panel, y, "UI_SC_Faction_FulfillRequest",
                    "request", summary.id)
            end
        end
        if (tonumber(summary.unresolvedOffenses) or 0) > 0 then
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Restitution")
            if summary.permanentHostility then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_RestitutionPermanent"))
            else
                local canReconcile, reconcileReason = SC.Factions.canReconcile(summary.id)
                y = self:addInformationLine(panel, y, "UI_SC_Faction_RestitutionValue",
                    tostring(summary.restitutionRequired or 0))
                if not canReconcile then
                    y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                        UI.text("UI_SC_Faction_RestitutionUnavailable",
                            UI.stateText(reconcileReason)))
                else
                    local canOffer, offerReason = SC.Trade.canOfferRestitution(
                        summary.id, playerForUI())
                    if not canOffer then
                        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                            UI.text("UI_SC_Faction_RestitutionUnavailable",
                                UI.stateText(offerReason)))
                    else
                        local playerRows = SC.Trade.playerCatalog(playerForUI()) or {}
                        local selection = self.tradeSelections and self.tradeSelections[summary.id]
                            or { offer = {}, request = {} }
                        for itemIndex = 1, math.min(#playerRows, 48) do
                            local tradeRow = playerRows[itemIndex]
                            y = self:addTradeChoice(panel, y, "offer", summary.id, tradeRow,
                                selection.offer[tradeRow.item] ~= nil)
                        end
                        local offered = selectedTradeRows(self, summary.id)
                        y = self:addInformationLine(panel, y, "UI_SC_Faction_RestitutionOffer",
                            tostring(SC.Trade.selectionValue(offered)) .. " / "
                                .. tostring(summary.restitutionRequired or 0))
                        y = self:addFactionAction(panel, y, "UI_SC_Faction_OfferRestitution",
                            "reconcile", summary.id)
                    end
                end
            end
        end
        y = self:addInformationLine(panel, y, "UI_SC_Faction_Barter",
            summary.barterUnlocked and UI.text("UI_SC_Faction_BarterUnlocked")
                or UI.text("UI_SC_Faction_BarterLocked"))
        if social and type(social.reserveSummary) == "table" and #social.reserveSummary > 0 then
            y = self:addSection(panel, y + 4, "UI_SC_Faction_Reserves")
            for _, reserve in ipairs(social.reserveSummary) do
                y = self:addInformationLine(panel, y, "UI_SC_Faction_Reserve",
                    reserve.count == -1
                        and UI.text("UI_SC_Faction_ReserveAll", UI.humanize(reserve.category),
                            reserve.reason)
                        or UI.text("UI_SC_Faction_ReserveCount", reserve.count,
                            UI.humanize(reserve.category), reserve.reason))
            end
        end
        if summary.barterUnlocked and SC.Trade then
            local canOpen, unavailable = SC.Trade.canOpen(summary.id, playerForUI())
            if not canOpen then
                y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                    UI.text("UI_SC_Faction_BarterUnavailable", UI.stateText(unavailable)))
            else
                local playerRows = SC.Trade.playerCatalog(playerForUI()) or {}
                local factionRows = SC.Trade.catalog(summary.id) or {}
                local selection = self.tradeSelections and self.tradeSelections[summary.id]
                    or { offer = {}, request = {} }
                y = self:addSection(panel, y + 4, "UI_SC_Faction_YourOffer")
                for itemIndex = 1, math.min(#playerRows, 48) do
                    local tradeRow = playerRows[itemIndex]
                    y = self:addTradeChoice(panel, y, "offer", summary.id, tradeRow,
                        selection.offer[tradeRow.item] ~= nil)
                end
                if #playerRows == 0 then
                    y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                        UI.text("UI_SC_Faction_NoOfferItems"))
                end
                y = self:addSection(panel, y + 4, "UI_SC_Faction_TheirGoods")
                for itemIndex = 1, math.min(#factionRows, 48) do
                    local tradeRow = factionRows[itemIndex]
                    y = self:addTradeChoice(panel, y, "request", summary.id, tradeRow,
                        selection.request[tradeRow.item] ~= nil)
                end
                if #factionRows == 0 then
                    y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
                        UI.text("UI_SC_Faction_NoGoods"))
                end
                local offered, requested = selectedTradeRows(self, summary.id)
                local quote = SC.Trade.quote(summary.id, offered, requested)
                if quote then
                    y = self:addInformationLine(panel, y, "UI_SC_Faction_Quote",
                        UI.text("UI_SC_Faction_QuoteValue", quote.offerValue,
                            quote.requiredOffer, quote.counterOffer, quote.refusedText))
                end
                y = self:addFactionAction(panel, y, "UI_SC_Faction_CompleteBarter",
                    "barter", summary.id)
            end
        end
    end
    return y
end

function SCUIDetail:buildDebug(panel)
    local y = 7
    if not SC.Config or type(SC.Config.get) ~= "function"
        or SC.Config.get("debugSpawnEnabled") ~= true then
        return self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Debug_Disabled"))
    end
    local selected = self.root and self.root.selectedRow or nil
    local movement = selected and selected.actor and SC.Locomotion
        and type(SC.Locomotion.snapshot) == "function"
        and SC.Locomotion.snapshot(selected.actor) or nil
    y = self:addSection(panel, y, "UI_SC_Debug_Movement")
    if movement then
        local navigation, telemetry = movement.navigation or {}, movement.telemetry or {}
        local blocker = navigation.lastBlocker or {}
        y = self:addInformationLine(panel, y, "UI_SC_Debug_MovementState",
            tostring(movement.name) .. " | " .. tostring(movement.phase)
                .. " | " .. tostring(movement.owner) .. " | " .. tostring(movement.action))
        y = self:addInformationLine(panel, y, "UI_SC_Debug_MovementTarget",
            tostring(movement.target or "none") .. " / " .. tostring(movement.next or "none"))
        y = self:addInformationLine(panel, y, "UI_SC_Debug_MovementNative",
            tostring(movement.activityPhase) .. " / " .. tostring(movement.activityOwner)
                .. " / " .. tostring(movement.activityName) .. " | path "
                .. tostring(telemetry.active == true) .. " | pending "
                .. tostring(telemetry.pending == true))
        y = self:addInformationLine(panel, y, "UI_SC_Debug_MovementBlocker",
            tostring(blocker.type or "none") .. " / "
                .. tostring(blocker.recoveryResult or "none") .. " | events "
                .. tostring(#(movement.events or {})))
        y = self:addSupportAction(panel, y, "UI_SC_Debug_MovementCopy", "movement_copy")
        y = self:addSupportAction(panel, y, "UI_SC_Debug_MovementRefresh", "movement_refresh")
        y = self:addSupportAction(panel, y, "UI_SC_Debug_MovementClear", "movement_clear")
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Debug_MovementUnavailable"))
    end
    local performance = SC.Performance and type(SC.Performance.snapshot) == "function"
        and SC.Performance.snapshot() or nil
    y = self:addSection(panel, y + 4, "UI_SC_Debug_Performance")
    if performance then
        y = self:addInformationLine(panel, y, "UI_SC_Debug_PerformanceFrame",
            string.format("%.2f / %.2f / %.2f ms",
                tonumber(performance.lastFrameMs) or 0,
                tonumber(performance.p95FrameMs) or 0,
                tonumber(performance.maxFrameMs) or 0))
        y = self:addInformationLine(panel, y, "UI_SC_Debug_PerformanceLoad",
            tostring(performance.loadLevel or 0) .. " / "
                .. tostring(performance.overBudgetFrames or 0) .. " / "
                .. tostring(performance.deferredFrames or 0))
        y = self:addInformationLine(panel, y, "UI_SC_Debug_PerformanceWork",
            tostring(performance.yieldedJobs or 0) .. " / "
                .. tostring(performance.cacheHits or 0) .. " / "
                .. tostring(performance.cacheMisses or 0))
        for index = 1, math.min(5, #(performance.topSystems or {})) do
            local metric = performance.topSystems[index]
            y = self:addInformationLine(panel, y, "UI_SC_Debug_PerformanceSystem",
                string.format("%s | p95 %.2f ms | max %.2f ms | %d yields",
                    tostring(metric.label or metric.key), tonumber(metric.p95Ms) or 0,
                    tonumber(metric.maxMs) or 0, tonumber(metric.yielded) or 0))
        end
        for index = 1, math.min(5, #(performance.topActors or {})) do
            local metric = performance.topActors[index]
            y = self:addInformationLine(panel, y, "UI_SC_Debug_PerformanceActor",
                string.format("%s | p95 %.2f ms | max %.2f ms",
                    tostring(metric.label or metric.key), tonumber(metric.p95Ms) or 0,
                    tonumber(metric.maxMs) or 0))
        end
        y = self:addSupportAction(panel, y, "UI_SC_Debug_PerformanceCopy", "performance_copy")
        y = self:addSupportAction(panel, y, "UI_SC_Debug_PerformanceRefresh", "performance_refresh")
        y = self:addSupportAction(panel, y, "UI_SC_Debug_PerformanceReset", "performance_reset")
    else
        y = self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Debug_PerformanceUnavailable"))
    end
    y = self:addSection(panel, y + 4, "UI_SC_Debug_Spawn")
    y = self:addFactionAction(panel, y, "UI_SC_Debug_SpawnOne", "spawn_1")
    y = self:addFactionAction(panel, y, "UI_SC_Debug_SpawnTwo", "spawn_2")
    y = self:addFactionAction(panel, y, "UI_SC_Debug_SpawnThree", "spawn_3")
    y = self:addFactionAction(panel, y, "UI_SC_Debug_SpawnRandom", "spawn_random")
    if UI._debugHouseLocator then
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ClearHouseMarker",
            "clear_house_marker")
    end
    local factions = SC.Factions and SC.Factions.list(false) or {}
    if #factions >= 2 and SC.FactionWorld then
        y = self:addSection(panel, y + 4, "UI_SC_Debug_FactionWorld")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_WorldWarning",
            "world_event_shared_warning")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_WorldTrade",
            "world_event_supply_exchange")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_WorldAid",
            "world_event_medical_aid")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_WorldDispute",
            "world_event_boundary_dispute")
    end
    y = self:addSection(panel, y + 4, "UI_SC_Debug_Selected")
    if #factions == 0 then
        y = self:addInformationLine(panel, y, "UI_SC_Debug_Target",
            UI.text("UI_SC_Value_None"))
    end
    for _, faction in ipairs(factions) do
        local id = faction.id
        local location = UI.debugHouseLocation(faction, playerForUI())
        y = self:addInformationLine(panel, y + 4, "UI_SC_Debug_Target",
            tostring(faction.name or id) .. " [" .. tostring(id) .. "]")
        if location then
            y = self:addInformationLine(panel, y, "UI_SC_Debug_House",
                UI.text("UI_SC_Debug_HouseLocation", location.x, location.y,
                    location.z, location.direction, numericText(location.distance, 1)))
            y = self:addFactionAction(panel, y, "UI_SC_Debug_LocateHouse",
                "locate_house", id)
        end
        y = self:addFactionAction(panel, y, "UI_SC_Debug_Inspect", "inspect", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ForceWary", "force_wary", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ForceTrusted", "force_trusted", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ForceHostile", "force_hostile", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ForceRequest", "force_request", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_UnlockBarter", "unlock_barter", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_LockBarter", "lock_barter", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AdvanceJob", "advance_job", id)
        y = self:addSection(panel, y + 4, "UI_SC_Debug_FactionLife")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityParanoid",
            "personality_Paranoid", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityGenerous",
            "personality_Generous", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityMilitarized",
            "personality_Militarized", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityDesperate",
            "personality_Desperate", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityIsolationist",
            "personality_Isolationist", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_PersonalityResourceful",
            "personality_Resourceful", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_CrisisSupply",
            "crisis_supply_collapse", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_CrisisIllness",
            "crisis_illness", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_CrisisDispute",
            "crisis_internal_dispute", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ResolveCrisis",
            "resolve_crisis", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AdvanceRoutine",
            "advance_routine", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AuditResources",
            "audit_resources", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ShareRumour",
            "share_rumour", id)
        y = self:addSection(panel, y + 4, "UI_SC_Debug_SocialContracts")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ContractSupply",
            "contract_offer_supply", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ContractMedical",
            "contract_offer_medical", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ContractThreat",
            "contract_offer_local_threat", id)
        for _, complication in ipairs({
            { id = "none", key = "UI_SC_Debug_Complication_none" },
            { id = "hidden_severity", key = "UI_SC_Debug_Complication_hidden_severity" },
            { id = "diverted_delivery", key = "UI_SC_Debug_Complication_diverted_delivery" },
            { id = "rival_objection", key = "UI_SC_Debug_Complication_rival_objection" },
            { id = "broken_reward", key = "UI_SC_Debug_Complication_broken_reward" },
            { id = "private_dissent", key = "UI_SC_Debug_Complication_private_dissent" },
        }) do
            y = self:addFactionAction(panel, y, complication.key,
                "complication_" .. complication.id, id)
        end
        y = self:addFactionAction(panel, y, "UI_SC_Debug_CompleteContract",
            "complete_contract", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_ExpireContract",
            "expire_contract", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AccessGuest",
            "contract_access_guest", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AccessDenied",
            "contract_access_denied", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_AccessContested",
            "contract_access_contested", id)
        y = self:addSection(panel, y + 4, "UI_SC_Debug_Recruitment")
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentPrepare",
            "recruitment_debug_prepare", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentCandidate",
            "recruitment_debug_candidate", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentTrial",
            "recruitment_debug_trial", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentMoreTime",
            "recruitment_debug_decision_more_time", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentJoin",
            "recruitment_debug_decision_join", id)
        y = self:addFactionAction(panel, y, "UI_SC_Debug_RecruitmentReturn",
            "recruitment_debug_decision_return", id)
        if faction.debugCreated == true then
            y = self:addFactionAction(panel, y, "UI_SC_Debug_Delete", "delete", id)
        end
    end
    return y
end

function SCUIDetail:buildSupport(panel)
    local y = self:addSection(panel, 4, "UI_SC_Support_Health")
    if not SC.Support or type(SC.Support.snapshot) ~= "function" then
        return self:addInformationLine(panel, y, "UI_SC_Info_Message",
            UI.text("UI_SC_Support_Unavailable"))
    end
    local status = SC.Support.snapshot(false)
    local bridge = status.bridge or {}
    local scheduler = status.scheduler or {}
    local diagnostics = status.diagnostics or {}
    y = self:addInformationLine(panel, y, "UI_SC_Support_Release", status.release)
    y = self:addInformationLine(panel, y, "UI_SC_Support_GameBuild",
        tostring(status.gameVersion) .. " / " .. tostring(status.expectedGameVersion))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Runtime",
        UI.booleanText(status.runtimeActive))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Bridge",
        UI.humanize(bridge.code or "unknown"))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Provider",
        bridge.provider or UI.text("UI_SC_Value_None"))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Protocol",
        tostring(bridge.observedProtocol or "unavailable") .. " / "
            .. tostring(bridge.expectedProtocol or "unknown"))
    y = self:addInformationLine(panel, y, "UI_SC_Support_BridgeDetail",
        bridge.reason or UI.text("UI_SC_Value_None"))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Action", bridge.advice)
    y = self:addInformationLine(panel, y, "UI_SC_Support_WorldCounts",
        tostring(status.companions or 0) .. " / " .. tostring(status.factions or 0))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Scheduler",
        tostring(scheduler.taskCount or 0) .. " / "
            .. tostring(scheduler.exceptions or 0) .. " / "
            .. tostring(scheduler.deferredFrames or 0))
    y = self:addInformationLine(panel, y, "UI_SC_Support_Diagnostics",
        tostring(diagnostics.reports or 0) .. " / "
            .. tostring(diagnostics.open or 0) .. " / "
            .. tostring(diagnostics.recoveries or 0))
    if status.disabledReason ~= nil then
        y = self:addInformationLine(panel, y, "UI_SC_Support_DisabledReason",
            status.disabledReason)
    end
    y = self:addSection(panel, y + 4, "UI_SC_Support_Actions")
    y = self:addSupportAction(panel, y, "UI_SC_Support_Copy", "copy")
    y = self:addSupportAction(panel, y, "UI_SC_Support_Recheck", "refresh")
    if (tonumber(diagnostics.open) or 0) > 0 then
        y = self:addSupportAction(panel, y, "UI_SC_Support_Retry", "retry")
    end
    return y
end

function SCUIDetail:rebuild(preserveScroll)
    local previousY = 0
    if preserveScroll and self.content and self.content.getYScroll then
        previousY = tonumber(self.content:getYScroll()) or 0
    end
    if self.content then
        self:removeChild(self.content)
        self.content = nil
    end
    local panel = SCUIClippedScrollPanel:new(
        0, 0, self:getWidth(), self:contentViewportHeight())
    panel:initialise()
    panel.background = false
    panel:instantiate()
    if panel.setScrollChildren then
        panel:setScrollChildren(true)
    end
    if panel.addScrollBars then
        panel:addScrollBars(false)
    end
    self:addChild(panel)
    self.content = panel
    panel.scContentWidth = panel:getWidth()
    local row = self.root and self.root.selectedRow or nil
    self.displayedTab = self.tab
    self.displayedCompanionId = row and row.id or nil
    local bottom = 0
    if self.tab == "overview" then
        bottom = self:buildOverview(panel, row)
    elseif self.tab == "orders" then
        bottom = self:buildOrders(panel)
    elseif self.tab == "gear" then
        bottom = self:buildGear(panel, row)
    elseif self.tab == "health" then
        bottom = self:buildHealth(panel, row)
    elseif self.tab == "journal" then
        bottom = self:buildJournal(panel, row)
    elseif self.tab == "base" then
        bottom = self:buildBase(panel, row)
    elseif self.tab == "groups" then
        bottom = self:buildGroups(panel, row)
    elseif self.tab == "factions" then
        bottom = self:buildFactions(panel)
    elseif self.tab == "support" then
        bottom = self:buildSupport(panel)
    elseif self.tab == "debug" then
        bottom = self:buildDebug(panel)
    end
    local contentHeight = math.max(panel:getHeight(), bottom + 8)
    local contentWidth = panel:getWidth()
    self.lastContentHeight = contentHeight
    self.lastContentWidth = contentWidth
    panel:setScrollWidth(contentWidth)
    panel:setScrollHeight(contentHeight)
    local maximumScroll = math.max(0, contentHeight - panel:getHeight())
    panel:setYScroll(Bounds.clamp(previousY, -maximumScroll, 0))
end

function SCUIDetail:setTab(tab)
    self.tab = UI.normalizeTab(tab) or "overview"
    self.feedback = nil
    self.feedbackUntil = nil
    self:rebuild()
end

function SCUIDetail:render()
    ISPanel.render(self)
    if self.feedback then
        local metrics = self.metrics or UI.layoutMetrics()
        local now = SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function"
            and SC.GameplayUtil.nowMs() or 0
        if self.feedbackUntil and now > self.feedbackUntil then
            self.feedback = nil
            self.feedbackUntil = nil
            return
        end
        local lines = UI.wrapText(UIFont.Small, self.feedback,
            math.max(80, self:getWidth() - 24))
        local count = math.min(2, #lines)
        local bannerHeight = 10 + count * metrics.infoLineHeight
        local footerHeight = self:feedbackFooterHeight()
        local footerTop = self:getHeight() - footerHeight
        local top = footerTop + math.max(2, math.floor((footerHeight - bannerHeight) / 2))
        self:drawRect(4, footerTop, self:getWidth() - 8, 1,
            0.72, 0.62, 0.64, 0.55)
        if self.feedbackSuccess then
            self:drawRect(4, top, self:getWidth() - 8, bannerHeight,
                0.82, 0.13, 0.24, 0.12)
        else
            self:drawRect(4, top, self:getWidth() - 8, bannerHeight,
                0.82, 0.36, 0.10, 0.08)
        end
        for index = 1, count do
            self:drawText(lines[index], 10,
                top + 5 + (index - 1) * metrics.infoLineHeight,
                0.94, 0.95, 0.88, 1, UIFont.Small)
        end
    end
end

local function onCollapseButton(target)
    target:setCollapsed(true)
end

local function onDockButton(target)
    target.dockSide = target.dockSide == "right" and "left" or "right"
    target:applyScreenBounds()
    target:updateDockButton()
    target:saveSettings()
end

local function onTabButton(target, button)
    target:setSelectedTab(button.scTab)
end

local SCUIRoot = ISPanel:derive("SCUIRoot")

function SCUIRoot:new(rect, settings)
    local object = ISPanel.new(self, rect.x, rect.y, rect.width, rect.height)
    object.settings = settings or {}
    object.dockSide = rect.dockSide
    -- The expanded window and collapsed launcher are separate top-level UI
    -- elements. Keeping the root expanded prevents the Collapse button's
    -- mouse-up from also activating a newly shrunken root under the cursor.
    object.collapsed = false
    object.selectedTab = UI.normalizeTab(settings.selectedTab) or "overview"
    object.selectedId = nil
    object.selectedRow = nil
    object.metrics = UI.layoutMetrics()
    object.backgroundColor = { r = 0.055, g = 0.065, b = 0.06,
        a = configuredOpacity(1, 0.25, 0.85) }
    object.borderColor = { r = 0.45, g = 0.49, b = 0.42, a = 0.9 }
    object.moveWithMouse = false
    object.resizable = false
    return object
end

function SCUIRoot:createChildren()
    ISPanel.createChildren(self)
    -- A saved collapsed root is intentionally compact. Build hidden children against safe
    -- provisional expanded dimensions, then lay them out when the tab opens.
    local provisionalWidth = math.max(self:getWidth(), Bounds.defaults.expandedMinWidth)
    local provisionalHeight = math.max(self:getHeight(), Bounds.defaults.expandedMinHeight)
    local metrics = self.metrics or UI.layoutMetrics()
    local collapseWidth = math.max(82, UI.textWidth(UIFont.Small, UI.text("UI_SC_Collapse")) + 18)
    local dockWidth = math.max(
        100,
        UI.textWidth(UIFont.Small, UI.text("UI_SC_DockLeft")) + 18,
        UI.textWidth(UIFont.Small, UI.text("UI_SC_DockRight")) + 18
    )
    self.collapseButton = ISButton:new(6, 5, collapseWidth, metrics.buttonHeight, UI.text("UI_SC_Collapse"), self, onCollapseButton)
    self.collapseButton:initialise()
    makeButtonTranslucent(self.collapseButton)
    self:addChild(self.collapseButton)
    self.dockButton = ISButton:new(12 + collapseWidth, 5, dockWidth, metrics.buttonHeight, "", self, onDockButton)
    self.dockButton:initialise()
    makeButtonTranslucent(self.dockButton)
    self:addChild(self.dockButton)
    self.roster = SCUIRoster:new(6, metrics.headerHeight + 1, 160, provisionalHeight - metrics.headerHeight - 7, self)
    self.roster:initialise()
    self:addChild(self.roster)
    self.tabButtons = {}
    for _, tab in ipairs(UI.tabIds()) do
        local button = ISButton:new(0, 0, 80, metrics.tabHeight, UI.text(TAB_KEYS[tab]), self, onTabButton)
        button:initialise()
        makeButtonTranslucent(button)
        button.scTab = tab
        self:addChild(button)
        self.tabButtons[#self.tabButtons + 1] = button
    end
    self.detail = SCUIDetail:new(170, metrics.headerHeight + (2 * metrics.tabHeight) + 4, provisionalWidth - 176, provisionalHeight - metrics.headerHeight - (2 * metrics.tabHeight) - 11, self)
    self.detail:initialise()
    self.detail:instantiate()
    self:addChild(self.detail)
    self.detail:setTab(self.selectedTab)
    self:updateDockButton()
    self:applyLayout()
end

function SCUIRoot:updateDockButton()
    if not self.dockButton then
        return
    end
    local key = self.dockSide == "right" and "UI_SC_DockLeft" or "UI_SC_DockRight"
    self.dockButton:setTitle(UI.text(key))
end

function SCUIRoot:applyLayout()
    if not self.roster then
        return
    end
    local width = self:getWidth()
    local height = self:getHeight()
    local metrics = UI.layoutMetrics()
    self.metrics = metrics
    local headerHeight = metrics.headerHeight
    local rosterWidth = Bounds.clamp(math.floor(width * 0.39), 145, 210)
    local detailX = rosterWidth + 12
    local detailWidth = width - detailX - 6
    local tabTop = headerHeight + 1
    local tabHeight = metrics.tabHeight
    local tabColumns = 3
    local maximumTabLabelWidth = 0
    for _, tab in ipairs(UI.tabIds()) do
        maximumTabLabelWidth = math.max(maximumTabLabelWidth, UI.textWidth(UIFont.Small, UI.text(TAB_KEYS[tab])) + 16)
    end
    while tabColumns > 1 and math.floor(detailWidth / tabColumns) < maximumTabLabelWidth do
        tabColumns = tabColumns - 1
    end
    local tabRows = math.ceil(#self.tabButtons / tabColumns)
    local tabWidth = math.floor(detailWidth / tabColumns)
    local collapseWidth = math.max(82, UI.textWidth(UIFont.Small, UI.text("UI_SC_Collapse")) + 18)
    local dockWidth = math.max(
        100,
        UI.textWidth(UIFont.Small, UI.text("UI_SC_DockLeft")) + 18,
        UI.textWidth(UIFont.Small, UI.text("UI_SC_DockRight")) + 18
    )
    self.collapseButton:setX(6)
    self.collapseButton:setY(5)
    self.collapseButton:setWidth(collapseWidth)
    self.collapseButton:setHeight(metrics.buttonHeight)
    self.dockButton:setX(12 + collapseWidth)
    self.dockButton:setY(5)
    self.dockButton:setWidth(dockWidth)
    self.dockButton:setHeight(metrics.buttonHeight)
    self.titleX = 18 + collapseWidth + dockWidth
    self.roster:setX(6)
    self.roster:setY(headerHeight + 1)
    self.roster:setWidth(rosterWidth)
    self.roster:setHeight(height - headerHeight - 7)
    self.roster.metrics = metrics
    self.roster.fontHgt = metrics.fontHeight
    self.roster.itemheight = metrics.rosterItemHeight
    for _, item in ipairs(self.roster.items or {}) do
        item.height = metrics.rosterItemHeight
    end
    for index, button in ipairs(self.tabButtons) do
        local column = (index - 1) % tabColumns
        local row = math.floor((index - 1) / tabColumns)
        button:setX(detailX + (column * tabWidth))
        button:setY(tabTop + (row * tabHeight))
        button:setWidth(column == tabColumns - 1 and detailWidth - (column * tabWidth) or tabWidth)
        button:setHeight(tabHeight)
    end
    local detailY = tabTop + (tabRows * tabHeight) + 3
    self.detail:setX(detailX)
    self.detail:setY(detailY)
    self.detail:setWidth(detailWidth)
    self.detail:setHeight(height - detailY - 7)
    self.detail.metrics = metrics
    if self.detail.content then
        self.detail.content:setWidth(detailWidth)
        self.detail.content:setHeight(self.detail:contentViewportHeight())
    end
    self.detail:rebuild(true)
    self:updateTabButtons()
end

function SCUIRoot:updateTabButtons()
    for _, button in ipairs(self.tabButtons or {}) do
        if button.scTab == self.selectedTab then
            button.backgroundColor = { r = 0.34, g = 0.38, b = 0.27,
                a = configuredOpacity(1.15, 0.46, 0.88) }
        else
            button.backgroundColor = { r = 0.12, g = 0.13, b = 0.12,
                a = configuredOpacity(0.88, 0.22, 0.78) }
        end
    end
end

function SCUIRoot:setSelectedTab(tab)
    self.selectedTab = UI.normalizeTab(tab) or "overview"
    self.detail:setTab(self.selectedTab)
    self:updateTabButtons()
    self:saveSettings()
end

function SCUIRoot:setChromeVisible(visible)
    if self.collapseButton then self.collapseButton:setVisible(visible) end
    if self.dockButton then self.dockButton:setVisible(visible) end
    if self.roster then self.roster:setVisible(visible) end
    if self.detail then self.detail:setVisible(visible) end
    for _, button in ipairs(self.tabButtons or {}) do
        button:setVisible(visible)
    end
end

function SCUIRoot:applyRect(rect)
    if not rect then return end
    -- Build 42 clamps setX() against the element's current width. Applying the
    -- edge position before shrinking a right-docked panel leaves the tab at the
    -- expanded panel's old left edge. Size first, then place, for both docks.
    self:setWidth(rect.width)
    self:setHeight(rect.height)
    self:setX(rect.x)
    self:setY(rect.y)
end

function SCUIRoot:setCollapsed(collapsed, initial)
    local requested = collapsed == true
    local sw, sh = screenSize()
    if requested then
        if not self.collapsed then
            self.settings.expandedY = self:getY()
            self.settings.width = self:getWidth()
            self.settings.height = self:getHeight()
            if not initial then
                self.settings.edgeY = self:getY()
            end
        end
        self.collapsed = true
        self.settings.collapsed = true
        self:setVisible(false)
        UI.showCollapsedLauncher(self)
    else
        self.collapsed = false
        self.settings.collapsed = false
        UI.hideCollapsedLauncher()
        local rect = Bounds.expandedRect(
            sw, sh, self.dockSide,
            self.settings.expandedY or self:getY(),
            self.settings.width,
            self.settings.height)
        self:applyRect(rect)
        self:setChromeVisible(true)
        self:applyLayout()
        self:refreshRoster()
        self:setVisible(true)
        self:bringToTop()
    end
    if not initial then
        self:saveSettings()
    end
end

function SCUIRoot:applyScreenBounds()
    local sw, sh = screenSize()
    if self.collapsed then
        UI.showCollapsedLauncher(self)
    else
        local rect = Bounds.expandedRect(sw, sh, self.dockSide, self:getY(), self:getWidth(), self:getHeight())
        self:applyRect(rect)
        self:applyLayout()
    end
    self.lastScreenWidth = sw
    self.lastScreenHeight = sh
end

function SCUIRoot:saveSettings()
    local settings = UI.getSettings()
    settings.dockSide = self.dockSide
    settings.collapsed = self.collapsed
    settings.selectedTab = self.selectedTab
    settings.x = self:getX()
    settings.y = self:getY()
    if self.collapsed then
        settings.edgeY = UI.launcher and UI.launcher:getY()
            or self.settings.edgeY or self:getY()
    else
        settings.expandedY = self:getY()
        settings.width = self:getWidth()
        settings.height = self:getHeight()
    end
    self.settings = settings
end

function SCUIRoot:refreshRoster(preferredId, description, preserveScroll)
    if not self.roster then
        return
    end
    local previousSelectedId = self.selectedId
    local selectedId = preferredId or self.selectedId
    local descriptionId = type(description) == "table" and (description.id or description.companionId) or nil
    selectedId = selectedId or descriptionId
    local previousScroll = tonumber(self.roster:getYScroll()) or 0
    local player = playerForUI()
    local entries = {}
    local descriptionApplied = false
    if SC.Registry and type(SC.Registry.living) == "function" then
        local ok, living = pcall(SC.Registry.living)
        if ok and type(living) == "table" then
            for _, entry in pairs(living) do
                local row = UI.describeEntry(entry, player)
                if row.factionMember ~= true and row.factionId == nil then
                    if type(description) == "table" and row.id == (descriptionId or selectedId) then
                        copySummary(row, description)
                        descriptionApplied = true
                    end
                    entries[#entries + 1] = row
                end
            end
        end
    end
    if type(description) == "table" and not descriptionApplied then
        local row = UI.describeEntry(description, player)
        if row.id ~= "" and row.factionMember ~= true and row.factionId == nil then
            entries[#entries + 1] = row
            descriptionApplied = true
        end
    end
    table.sort(entries, function(left, right)
        local leftName = string.lower(tostring(left.name or ""))
        local rightName = string.lower(tostring(right.name or ""))
        if leftName == rightName then
            return tostring(left.id or "") < tostring(right.id or "")
        end
        return leftName < rightName
    end)
    local selectedIndex = nil
    for index, row in ipairs(entries) do
        row.tooltip = summaryTooltip(row)
        if selectedId and row.id == selectedId then selectedIndex = index end
    end
    if not selectedIndex and #entries > 0 then selectedIndex = 1 end

    -- Scheduled refresh runs twice per second. Replacing all ISUI children at
    -- that cadence causes visible flashes. When roster membership/order is
    -- unchanged, replace only the row data that drawItem reads and rebuild the
    -- selected detail view solely when its meaningful state changed.
    local canReuse = #entries == #(self.roster.items or {})
    if canReuse then
        for index, row in ipairs(entries) do
            local item = self.roster.items[index]
            if not item or not item.item or item.item.id ~= row.id then
                canReuse = false
                break
            end
        end
    end
    if canReuse then
        for index, row in ipairs(entries) do
            local item = self.roster.items[index]
            item.item = row
            item.text = row.name
            item.tooltip = row.tooltip
        end
        self.roster.selected = selectedIndex or 0
        self.selectedRow = selectedIndex and entries[selectedIndex] or nil
        self.selectedId = self.selectedRow and self.selectedRow.id or nil
        local signature = detailRowSignature(self.selectedRow)
        if self.selectedTab == "factions" or self.selectedTab == "debug" then
            signature = signature .. ":" .. factionDetailSignature()
        elseif self.selectedTab == "base" then
            signature = signature .. ":" .. baseDetailSignature()
        end
        local detailChanged = self.detail and (
            self.detail.displayedCompanionId ~= self.selectedId
            or self.detail.displayedTab ~= self.detail.tab
            or self.detailRowSignature ~= signature)
        self.detailRowSignature = signature
        if detailChanged then self.detail:rebuild(true) end
        return
    end

    self.roster.smoothScrollTargetY = nil
    self.roster.smoothScrollY = nil
    self.roster:setYScroll(0)
    self.roster:setScrollHeight(0)
    self.roster:clear()
    self.roster:setScrollHeight(0)
    local contentHeight = 0
    for index, row in ipairs(entries) do
        self.roster:addItem(row.name, row, row.tooltip)
        contentHeight = contentHeight + (self.roster.itemheight or 0)
    end
    self.roster:setScrollHeight(contentHeight)
    local maximumScroll = math.max(0, contentHeight - self.roster:getHeight())
    local desiredScroll = preserveScroll == false and 0 or previousScroll
    self.roster:setYScroll(Bounds.clamp(desiredScroll, -maximumScroll, 0))
    self.roster.selected = selectedIndex or 0
    local actualSelectedId = selectedIndex and entries[selectedIndex] and entries[selectedIndex].id or nil
    self:onRosterSelectionChanged(self.roster.selected, previousSelectedId ~= nil and previousSelectedId == actualSelectedId)
end

function SCUIRoot:onRosterSelectionChanged(index, preserveDetailScroll)
    local item = self.roster and self.roster.items[index] or nil
    self.selectedRow = item and item.item or nil
    self.selectedId = self.selectedRow and self.selectedRow.id or nil
    self.detailRowSignature = detailRowSignature(self.selectedRow)
    if self.selectedTab == "factions" or self.selectedTab == "debug" then
        self.detailRowSignature = self.detailRowSignature .. ":" .. factionDetailSignature()
    elseif self.selectedTab == "base" then
        self.detailRowSignature = self.detailRowSignature .. ":" .. baseDetailSignature()
    end
    if self.detail then
        self.detail:rebuild(preserveDetailScroll == true)
    end
end

function SCUIRoot:isUserInteracting()
    if self.dragging or self.resizingNow then return true end
    local rosterBar = self.roster and self.roster.vscroll or nil
    local content = self.detail and self.detail.content or nil
    local detailBar = content and content.vscroll or nil
    if rosterBar and (rosterBar.scrolling == true
        or safeMethod(rosterBar, "getIsCaptured") == true) then return true end
    if detailBar and (detailBar.scrolling == true
        or safeMethod(detailBar, "getIsCaptured") == true) then return true end
    for _, child in ipairs(content and content.children or {}) do
        if child and child.isCombobox == true and child.expanded == true then return true end
    end
    if type(isMouseButtonDown) == "function" and isMouseButtonDown(0)
        and safeMethod(self, "isMouseOver") == true then return true end
    return false
end

function SCUIRoot:onMouseDown(x, y)
    self.dragStartY = self:getY()
    self.dragDistance = 0
    self.dragging = true
    self.resizingNow = not self.collapsed and x >= self:getWidth() - 14 and y >= self:getHeight() - 14
    if self.setCapture then self:setCapture(true) end
    return true
end

function SCUIRoot:onMouseMove(dx, dy)
    if not self.dragging then
        return false
    end
    self.dragDistance = self.dragDistance + math.abs(tonumber(dx) or 0) + math.abs(tonumber(dy) or 0)
    if self.resizingNow then
        local widthDelta = tonumber(dx) or 0
        if self.dockSide == "right" then
            widthDelta = -widthDelta
        end
        local sw, sh = screenSize()
        local rect = Bounds.resizedRect(sw, sh, self.dockSide, self:getY(), self:getWidth() + widthDelta, self:getHeight() + (tonumber(dy) or 0))
        self:applyRect(rect)
        self:applyLayout()
    else
        local sw, sh = screenSize()
        local requestedY = self:getY() + (tonumber(dy) or 0)
        local rect
        if self.collapsed then
            rect = Bounds.collapsedRect(sw, sh, self.dockSide, requestedY)
        else
            rect = Bounds.expandedRect(sw, sh, self.dockSide, requestedY, self:getWidth(), self:getHeight())
        end
        self:setX(rect.x)
        self:setY(rect.y)
    end
    return true
end

function SCUIRoot:onMouseUp(x, y)
    self.dragging = false
    self.resizingNow = false
    if self.setCapture then self:setCapture(false) end
    self:saveSettings()
    return true
end

function SCUIRoot:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function SCUIRoot:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function SCUIRoot:prerender()
    local sw, sh = screenSize()
    if sw ~= self.lastScreenWidth or sh ~= self.lastScreenHeight then
        self:applyScreenBounds()
    end
    self.backgroundColor = { r = 0.055, g = 0.065, b = 0.06,
        a = configuredOpacity(1, 0.25, 0.85) }
    ISPanel.prerender(self)
end

function SCUIRoot:render()
    ISPanel.render(self)
    local metrics = self.metrics or UI.layoutMetrics()
    local titleX = self.titleX or 202
    local maximumTitleWidth = math.max(1, self:getWidth() - titleX - 8)
    local title = fitText(UIFont.Small, UI.text("UI_SC_Title"), maximumTitleWidth)
    self:drawText(title, titleX, math.floor((metrics.headerHeight - metrics.fontHeight) / 2), 0.91, 0.89, 0.76, 1, UIFont.Small)
    Pixels.draw(self, "grip", self:getWidth() - 11, self:getHeight() - 11, 2, 0.58, 0.60, 0.51, 0.8)
end

local SCUICollapsedLauncher = ISPanel:derive("SCUICollapsedLauncher")

function SCUICollapsedLauncher:new(rect, root)
    local object = ISPanel.new(self, rect.x, rect.y, rect.width, rect.height)
    object.root = root
    object.dockSide = rect.dockSide
    object.backgroundColor = { r = 0.08, g = 0.09, b = 0.075,
        a = configuredOpacity(1.2, 0.42, 0.9) }
    object.borderColor = { r = 0.52, g = 0.56, b = 0.43, a = 0.9 }
    object.moveWithMouse = false
    object.dragging = false
    object.dragDistance = 0
    return object
end

function SCUICollapsedLauncher:applyRect(rect)
    self.dockSide = rect.dockSide
    self:setWidth(rect.width)
    self:setHeight(rect.height)
    self:setX(rect.x)
    self:setY(rect.y)
end

function SCUICollapsedLauncher:applyScreenBounds(savedY)
    local sw, sh = screenSize()
    local dockSide = self.root and self.root.dockSide or self.dockSide
    self:applyRect(Bounds.collapsedRect(sw, sh, dockSide, savedY or self:getY()))
    self.lastScreenWidth = sw
    self.lastScreenHeight = sh
end

function SCUICollapsedLauncher:onMouseDown(x, y)
    self.dragging = true
    self.dragDistance = 0
    if self.setCapture then self:setCapture(true) end
    return true
end

function SCUICollapsedLauncher:onMouseMove(dx, dy)
    if not self.dragging then return false end
    self.dragDistance = self.dragDistance
        + math.abs(tonumber(dx) or 0) + math.abs(tonumber(dy) or 0)
    self:applyScreenBounds(self:getY() + (tonumber(dy) or 0))
    return true
end

function SCUICollapsedLauncher:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function SCUICollapsedLauncher:onMouseUp(x, y)
    -- The launcher can be inserted into UIManager during the Collapse
    -- button's mouse-up dispatch. Ignore that release unless this separate
    -- element received its own preceding mouse-down.
    if not self.dragging then return false end
    local wasClick = (self.dragDistance or 0) < 4
    self.dragging = false
    if self.setCapture then self:setCapture(false) end
    if wasClick and self.root then
        self.root:setCollapsed(false)
    elseif self.root then
        self.root:saveSettings()
    end
    return true
end

function SCUICollapsedLauncher:onMouseUpOutside(x, y)
    return self:onMouseUp(x, y)
end

function SCUICollapsedLauncher:prerender()
    local sw, sh = screenSize()
    if sw ~= self.lastScreenWidth or sh ~= self.lastScreenHeight then
        self:applyScreenBounds()
    end
    ISPanel.prerender(self)
    self:drawRectBorder(0, 0, self:getWidth(), self:getHeight(), 0.9, 0.52, 0.56, 0.43)
    local centreX = math.floor(self:getWidth() / 2)
    self:drawTextCentre("LF", centreX, 8, 0.94, 0.91, 0.69, 1, UIFont.Small)
    local iconScale = self:getWidth() >= 72 and 3 or 2
    local iconWidth = Pixels.measure("companion", iconScale)
    Pixels.draw(self, "companion", centreX - math.floor(iconWidth / 2), 34,
        iconScale, 0.77, 0.76, 0.58, 1)
    local heartWidth = Pixels.measure("heart", 2)
    Pixels.draw(self, "heart", centreX - math.floor(heartWidth / 2),
        self:getHeight() - 48, 2, 0.63, 0.32, 0.26, 1)
    local chevron = self.dockSide == "right" and "chevronLeft" or "chevronRight"
    local chevronWidth = Pixels.measure(chevron, 2)
    Pixels.draw(self, chevron, centreX - math.floor(chevronWidth / 2),
        self:getHeight() - 18, 2, 0.77, 0.79, 0.68, 1)
    self.tooltip = UI.text("UI_SC_OpenRosterHotkey", UI.hotkeyName())
end

function UI.showCollapsedLauncher(root)
    if not root then return nil end
    local sw, sh = screenSize()
    local settings = root.settings or UI.getSettings()
    local rect = Bounds.collapsedRect(sw, sh, root.dockSide,
        settings.edgeY or settings.expandedY or root:getY())
    local launcher = UI.launcher
    if not launcher then
        launcher = SCUICollapsedLauncher:new(rect, root)
        launcher:initialise()
        launcher:instantiate()
        launcher:addToUIManager()
        launcher:setAlwaysOnTop(true)
        UI.launcher = launcher
    else
        launcher.root = root
        launcher:applyRect(rect)
    end
    launcher.lastScreenWidth = sw
    launcher.lastScreenHeight = sh
    launcher:setVisible(true)
    launcher:bringToTop()
    root:setVisible(false)
    return launcher
end

function UI.hideCollapsedLauncher()
    if UI.launcher then
        UI.launcher:setVisible(false)
    end
end

function UI.ensureControl()
    if UI.instance then
        if UI.instance.collapsed then
            UI.showCollapsedLauncher(UI.instance)
        else
            UI.instance:setVisible(true)
        end
        return UI.instance
    end
    local settings = UI.getSettings()
    if tonumber(settings.visibilityRevision) ~= UI.SETTINGS_VISIBILITY_REVISION then
        -- Open once after the visibility patch, including for saves that stored
        -- the old almost-invisible collapsed tab. Later player choice persists.
        settings.collapsed = false
        settings.visibilityRevision = UI.SETTINGS_VISIBILITY_REVISION
    elseif settings.collapsed == nil then
        settings.collapsed = false
    end
    settings.dockSide = Bounds.normalizeDock(settings.dockSide)
    local sw, sh = screenSize()
    local rect = Bounds.expandedRect(
        sw, sh, settings.dockSide,
        settings.expandedY, settings.width, settings.height)
    local root = SCUIRoot:new(rect, settings)
    root:initialise()
    root:instantiate()
    root:addToUIManager()
    root:setAlwaysOnTop(true)
    root.lastScreenWidth = sw
    root.lastScreenHeight = sh
    UI.instance = root
    root:setCollapsed(settings.collapsed == true, true)
    return root
end

function UI.open(tab, companionId, description)
    local root = UI.ensureControl()
    root:setVisible(true)
    root:bringToTop()
    if root.collapsed then
        root:setCollapsed(false)
    end
    root:applyScreenBounds()
    local descriptionId = type(description) == "table" and (description.id or description.companionId) or nil
    root:refreshRoster(companionId or descriptionId, description, true)
    local requestedTab = UI.normalizeTab(tab)
    if description and not requestedTab then
        requestedTab = "overview"
    end
    if requestedTab then
        root:setSelectedTab(requestedTab)
    end
    return root
end

function UI.showStatus(description)
    local companionId = type(description) == "table" and (description.id or description.companionId) or nil
    return UI.open("overview", companionId, description)
end

function UI.openInventory(actor, player)
    return Bridge.openInventory(actor, player or playerForUI())
end

function UI.openHealth(actor, player)
    local activePlayer = player or playerForUI()
    return Bridge.openHealth(actor, activePlayer, UI.open, function(subject, doctor)
        return UI.describeEntry(subject, doctor)
    end)
end

function UI.isOpen()
    return UI.instance ~= nil and UI.instance:isVisible() and UI.instance.collapsed == false
end

function UI.scheduledRefresh()
    if not UI.isOpen() then
        return false
    end
    if UI.instance:isUserInteracting() then
        UI.instance.refreshPending = true
        return false
    end
    UI.instance.refreshPending = false
    UI.instance:refreshRoster(nil, nil, true)
    return true
end

function UI.close()
    if not UI.instance then
        return
    end
    UI.instance:saveSettings()
    UI.instance:removeFromUIManager()
    UI.instance = nil
    if UI.launcher then
        UI.launcher:removeFromUIManager()
        UI.launcher = nil
    end
end

function UI.toggle()
    if not UI.instance then
        return UI.open()
    end
    UI.instance:setCollapsed(not UI.instance.collapsed)
    return UI.instance
end

function UI.onKeyPressed(key)
    if not playerForUI() then return end
    local configured = UI.DEFAULT_HOTKEY
    local core = getCore and getCore() or nil
    local bound = core and safeMethod(core, "getKey", UI.HOTKEY_ACTION) or nil
    if tonumber(bound) and tonumber(bound) > 0 then configured = tonumber(bound) end
    if tonumber(key) == configured then UI.toggle() end
end

function UI.refresh()
    if UI.instance and UI.instance:isVisible() then
        if UI.instance:isUserInteracting() then
            UI.instance.refreshPending = true
            return false
        end
        UI.instance.refreshPending = false
        UI.instance:refreshRoster(nil, nil, true)
    end
    return true
end

function UI.reset()
    UI.clearDebugHouseLocator()
    UI.close()
    UI._gameStarted = false
end

function UI.onCreatePlayer(playerIndex, player)
    -- Build the menu only after the in-game UI manager has reached OnGameStart.
    -- Some load paths fire OnCreatePlayer while top-level UI elements are still
    -- being reset, which used to leave a saved collapsed launcher invisible.
    if UI._gameStarted then
        UI.restoreStartupVisibility()
    end
end

function UI.restoreStartupVisibility()
    if not playerForUI() then return false end
    local root = UI.ensureControl()
    if root.collapsed then
        -- Force a real false-to-true transition after the game's startup UI
        -- reset. This makes the already-created launcher drawable immediately.
        UI.hideCollapsedLauncher()
        UI.showCollapsedLauncher(root)
    else
        UI.hideCollapsedLauncher()
        root:setVisible(true)
        root:bringToTop()
    end
    return true
end

function UI.onGameStart()
    UI._gameStarted = true
    UI.restoreStartupVisibility()
end

function UI.installHooks()
    if UI._hooksInstalled then
        return
    end
    if Events and Events.OnCreatePlayer then
        Events.OnCreatePlayer.Add(UI.onCreatePlayer)
    end
    if Events and Events.OnGameStart then
        Events.OnGameStart.Add(UI.onGameStart)
    end
    if Events and Events.OnKeyPressed then
        Events.OnKeyPressed.Add(UI.onKeyPressed)
    end
    if Events and Events.OnMainMenuEnter then
        Events.OnMainMenuEnter.Add(UI.reset)
    end
    UI._hooksInstalled = true
end

UI.installHooks()
require "SCUIContext"

return UI
