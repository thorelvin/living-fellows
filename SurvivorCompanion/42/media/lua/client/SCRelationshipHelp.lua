-- SPDX-License-Identifier: MIT
-- Explicit interactions only: no update hook, world scan or retained native items.
require "SCTrade"
require "SCNeeds"
require "SCRelationship"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.RelationshipHelp = SC.RelationshipHelp or {}
local Help = SC.RelationshipHelp
local function U() return SC.GameplayUtil end
local function value(object, method)
    local result = U().call(object, method)
    return result
end

function Help.describe(id, player)
    if type(getSpecificPlayer) == "function" and getSpecificPlayer(0) ~= player then
        return nil, "help_unavailable"
    end
    local actor, entry = U().resolveActor(id)
    if not actor or not entry then return nil, "help_unavailable" end
    local row = SC.Commands.describe(id, player)
    if not row or row.alive == false or row.available == false then return nil, "help_unavailable" end
    local group = row.factionId and SC.Factions and SC.Factions.group(row.factionId)
    local story = SC.Oddballs and SC.Oddballs.groupForActor and SC.Oddballs.groupForActor(actor)
    if story then return nil, "help_story" end
    if group and (group.oddball or group.standing == "Hostile"
        or group.lifecycle == "hostile" or group.permanentHostility == true) then
        return nil, group.oddball and "help_story" or "help_hostile"
    end
    local state = SC.Commands.peek and SC.Commands.peek(actor)
    if row.hostile == true or state and (state.hostileToPlayer == true
        or state.care and (state.care.playerHostile == true
            or state.care.playerCeasefire == true)) then return nil, "help_hostile" end
    if not player or not U().sameFloor(actor, player) or U().distance(actor, player) > 6 then
        return nil, "help_too_far"
    end
    return { actor = actor, row = row, group = group,
        food = (tonumber(row.hunger) or 0) >= 0.62,
        water = (tonumber(row.thirst) or 0) >= 0.62,
        medical = (tonumber(row.woundCount) or 0) > 0 }
end

local function acceptable(item, kind)
    if value(item, "isFavorite") == true then return false end
    if SC.ActionSupervisor and SC.ActionSupervisor.isReserved
        and SC.ActionSupervisor.isReserved(item) then return false end
    if kind == "food" then return SC.Needs.foodTier(item) ~= nil end
    if kind ~= "water" or SC.Needs.isSafeWaterItem(item) ~= true then return false end
    local fluid = value(item, "getFluidContainer")
    return fluid and (tonumber(value(fluid, "getAmount")) or 0) > 0
end

-- This existing catalog is bounded at 512 items, including nested bags, and
-- excludes worn/favourite/reserved items. It runs only when the player asks.
function Help.catalog(id, kind, player)
    local status, reason = Help.describe(id, player)
    if not status then return nil, reason end
    if kind ~= "food" and kind ~= "water" then return nil, "invalid_help" end
    if status[kind] ~= true then return nil, "help_no_need" end
    local catalog, why, complete = SC.Trade.playerCatalog(player)
    if not catalog then return nil, why end
    local result = {}
    for _, row in ipairs(catalog) do
        if acceptable(row.item, kind) then
            row.name = value(row.item, "getDisplayName") or row.type
            row.tier = kind == "food" and SC.Needs.foodTier(row.item) or 1
            local fluid = value(row.item, "getFluidContainer")
            row.litres = fluid and tonumber(value(fluid, "getAmount")) or nil
            result[#result + 1] = row
        end
    end
    table.sort(result, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        return tostring(a.name) < tostring(b.name)
    end)
    return result, nil, complete
end

function Help.give(id, kind, selected, player)
    if ISTimedActionQueue and type(ISTimedActionQueue.isPlayerDoingAction) == "function" then
        local checked, busy = pcall(ISTimedActionQueue.isPlayerDoingAction, player)
        if not checked or busy then return false, "help_busy" end
    end
    local status, reason = Help.describe(id, player)
    if not status then return false, reason end
    if status[kind] ~= true or kind ~= "food" and kind ~= "water" then return false, "help_no_need" end
    if type(selected) ~= "table" or not acceptable(selected.item, kind) then
        return false, "help_item_changed"
    end
    local relief = 1
    if kind == "food" then
        relief = math.min(1, math.max(0, -(tonumber(value(selected.item, "getHungerChange")) or 0)) / 0.12)
    else
        local fluid = value(selected.item, "getFluidContainer")
        relief = math.min(1, (tonumber(value(fluid, "getAmount")) or 0) / 0.25)
    end
    return SC.Trade.giveToActor(status.actor, player, selected, {
        factionId = status.row.factionId, maximumDistance = 6,
        validate = function(_, _, recipient)
            local current, why = Help.describe(id, player)
            if not current then return false, why end
            if current.actor ~= recipient or current.row.factionId ~= status.row.factionId then
                return false, "help_item_changed"
            end
            return current[kind] == true and acceptable(selected.item, kind), "help_no_need"
        end,
        finalize = function()
            local accepted, why = SC.Commands.recordHelp(status.actor, kind, selected.item, relief)
            if accepted then
                local data = U().modData(selected.item)
                if type(data) == "table" then data.SC_GivenByPlayer = true end
            end
            return accepted, why
        end,
    })
end

return Help
