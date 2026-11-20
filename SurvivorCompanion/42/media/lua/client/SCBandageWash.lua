-- SPDX-License-Identifier: MIT
-- Exact carried inputs and water policy shared by personal and camp washing.
-- Native timed actions own consumption and create every replacement.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BandageWash = SC.BandageWash or {}
local W = SC.BandageWash
local EPS = 0.0001
W.BATCH_LIMIT, W.LITRES, W.DRINK_RESERVE = 8, 0.5, 1
local cleanTypes = {
    ["base.bandagedirty"] = "Base.Bandage",
    ["base.rippedsheetsdirty"] = "Base.RippedSheets",
    ["base.denimstripsdirty"] = "Base.DenimStrips",
    ["base.leatherstripsdirty"] = "Base.LeatherStrips",
}
local function U() return SC.GameplayUtil end
local function value(object, method, ...) return select(1, U().call(object, method, ...)) end
local function finite(number)
    number = tonumber(number)
    return number and number == number and number >= 0 and number < math.huge and number or nil
end
function W.cleanType(item) return cleanTypes[string.lower(U().itemType(item) or "")] end
function W.isClean(item)
    return SC.Medical and SC.Medical.dressingRank
        and SC.Medical.dressingRank(item, false) ~= nil or false
end

-- Complete, bounded observation: an interrupted inventory scan never proves
-- that no clean dressing or drinking reserve exists.
function W.inventoryEntries(actor)
    local root = U().inventory(actor)
    if not root then return nil, "inventory_unavailable" end
    local pending, seen, seenItems, entries, count = { { container = root, ancestors = {} } }, {}, {}, {}, 0
    while #pending > 0 do
        local row = table.remove(pending)
        if not seen[row.container] then
            seen[row.container] = true
            local items, okay = U().call(row.container, "getItems")
            if not okay or not items then return nil, "inventory_unreadable" end
            local size = U().listSize(items)
            if type(size) ~= "number" or count + size > 4096 then return nil, "inventory_scan_limit" end
            for index = 0, size - 1 do
                local item = U().listGet(items, index)
                count = count + 1
                if item then
                    if seenItems[item] or value(item, "getContainer") ~= row.container then return nil, "inventory_ownership_changed" end
                    seenItems[item] = true
                    entries[#entries + 1] = { item = item, source = row.container, ancestors = row.ancestors }
                    local nested = value(item, "getInventory") or value(item, "getItemContainer")
                    if nested and nested ~= row.container and not seen[nested] then
                        if #row.ancestors >= 16 then return nil, "inventory_depth_limit" end
                        local ancestors = {}
                        for _, parent in ipairs(row.ancestors) do ancestors[#ancestors + 1] = parent end
                        ancestors[#ancestors + 1] = item
                        pending[#pending + 1] = { container = nested, ancestors = ancestors }
                    end
                end
            end
        end
    end
    return entries
end
function W.carriedEntry(actor, item, entries)
    entries = entries or W.inventoryEntries(actor)
    for _, row in ipairs(entries or {}) do
        if row.item == item and value(item, "getContainer") == row.source
            and U().containerContainsIdentity(row.source, item) then return row end
    end
end
local function strict(actor, item, allowFavorite)
    if not SC.PersonalItems or type(SC.PersonalItems.isProtected) ~= "function"
        or SC.PersonalItems.isProtected(item, actor, "wash_bandage") == true then return false end
    if SC.WorkTransport and SC.WorkTransport.foreignProtected then
        local protected, reason = SC.WorkTransport.foreignProtected(item, actor)
        if protected == true and not (allowFavorite and reason == "favorite_item") then return false end
    end
    return true
end
local function ancestorsAllowed(actor, row, allowFavorite)
    for _, item in ipairs(row.ancestors or {}) do if not strict(actor, item, allowFavorite) then return false end end
    return true
end
local function originAllowed(actor, origin, entries, bottle)
    if not origin then return true end
    for _, parent in ipairs(origin.ancestors or {}) do
        if not W.carriedEntry(actor, parent, entries) or not strict(actor, parent, not bottle) then return false end
    end
    if origin.source == U().inventory(actor) then return true end
    for _, row in ipairs(entries or {}) do
        if value(row.item, "getInventory") == origin.source or value(row.item, "getItemContainer") == origin.source then return true end
    end
    return false
end
function W.isInputAllowed(actor, item, claim, entries, origin)
    entries = entries or W.inventoryEntries(actor)
    local row = W.carriedEntry(actor, item, entries)
    if not row or not ancestorsAllowed(actor, row, true) or not originAllowed(actor, origin, entries, false) then return false end
    if claim then
        local transport = SC.WorkTransport
        return transport and type(transport.bandageWashInputAllowed) == "function"
            and transport.bandageWashInputAllowed(item, actor, claim) == true or false
    end
    return strict(actor, item, true)
end
local function loaned(item)
    local data = value(item, "getModData")
    if type(data) ~= "table" then return true end
    for key, marker in pairs(data) do
        local name = string.lower(tostring(key))
        if marker ~= nil and marker ~= false and (string.sub(name, 1, 3) == "lf_"
            or string.sub(name, 1, 3) == "sc_")
            and (string.find(name, "loan", 1, true) or string.find(name, "borrow", 1, true)) then
            return true
        end
    end
    return false
end
local function bottleAllowed(actor, row)
    if not strict(actor, row.item) or loaned(row.item) or not ancestorsAllowed(actor, row) then return false end
    for _, parent in ipairs(row.ancestors or {}) do if loaned(parent) then return false end end
    return true
end
function W.inspectWater(item)
    local fluid = value(item, "getFluidContainer")
    if not fluid or not Fluid or not Fluid.Water or not Fluid.TaintedWater then return nil end
    local amount = finite(value(fluid, "getAmount"))
    local water = finite(value(fluid, "getSpecificFluidAmount", Fluid.Water))
    local tainted = finite(value(fluid, "getSpecificFluidAmount", Fluid.TaintedWater))
    if not amount or not water or not tainted or amount <= EPS
        or math.abs(amount - water - tainted) > EPS then return nil end
    -- Quantities account for the entire mixture; alcohol, cleaners and other
    -- fluids cannot slip through a broad native Water category match.
    local drinkable = tainted <= EPS and SC.Needs and SC.Needs.isSafeWaterItem
        and SC.Needs.isSafeWaterItem(item) == true or false
    return { item = item, fluid = fluid, amount = amount, water = water,
        tainted = tainted, drinkable = drinkable }
end
local function drinkingReserve(actor, entries)
    local total = 0
    for _, row in ipairs(entries) do
        if bottleAllowed(actor, row) then
            local info = W.inspectWater(row.item)
            if info and info.drinkable then total = total + info.amount end
        end
    end
    return total
end
function W.carriedWaterPlan(actor, entries)
    entries = entries or W.inventoryEntries(actor)
    if not entries then return nil, "inventory_unreadable" end
    local reserve, best = drinkingReserve(actor, entries), nil
    for _, row in ipairs(entries) do
        if bottleAllowed(actor, row) then
            local info = W.inspectWater(row.item)
            if info and info.amount + EPS >= W.LITRES
                and (not info.drinkable or reserve - W.LITRES + EPS >= W.DRINK_RESERVE)
                and (not best or info.tainted > EPS and best.tainted <= EPS) then
                best = info
                best.container = row.source
                best.source, best.ancestors = row.source, row.ancestors
            end
        end
    end
    return best, best and nil or "no_water_for_bandages"
end
function W.waterPlanValid(actor, plan, entries)
    if not plan or not plan.item then return false end
    entries = entries or W.inventoryEntries(actor)
    if not entries then return false end
    local row = W.carriedEntry(actor, plan.item, entries)
    if not row or not bottleAllowed(actor, row) or not originAllowed(actor, plan, entries, true) then return false end
    for _, parent in ipairs(plan.ancestors or {}) do if loaned(parent) then return false end end
    local info = W.inspectWater(plan.item)
    return info ~= nil and info.fluid == plan.fluid and info.amount + EPS >= W.LITRES
        and (not info.drinkable or drinkingReserve(actor, entries) - W.LITRES + EPS >= W.DRINK_RESERVE)
end
function W.returnContainerAllowed(actor, activity, container)
    if container == U().inventory(actor) then return true end
    local entries = W.inventoryEntries(actor)
    if not entries then return false end
    local known = false
    if activity.washInputEntry and activity.washInputEntry.source == container then
        known = true
        if not originAllowed(actor, activity.washInputEntry, entries, false) then return false end
    end
    local plan = activity.washWaterPlan
    if plan and plan.source == container then
        if not originAllowed(actor, plan, entries, true) then return false end
        for _, parent in ipairs(plan.ancestors or {}) do if loaned(parent) then return false end end
        known = true
    end
    return known
end
function W.worldSourceValid(object)
    local amount, okay = U().call(object, "getFluidAmount")
    return okay and (finite(amount) or 0) >= (tonumber(U().config("downtimeWashMinimumWater")) or 4)
        and value(object, "isTaintedWater") ~= true
end
function W.makeActivity(actor, item, options)
    options = options or {}
    local entries, reason = W.inventoryEntries(actor)
    local row = entries and W.carriedEntry(actor, item, entries)
    local cleanType = W.cleanType(item)
    local claim = options.claim or options.washJobClaim
    if not row or not cleanType or not W.isInputAllowed(actor, item, claim, entries) then
        return nil, reason or "wash_dressing_unavailable"
    end
    local plan = options.waterPlan
    if plan then
        if not W.waterPlanValid(actor, plan, entries) then return nil, "no_water_for_bandages" end
    elseif not W.worldSourceValid(options.object) then return nil, "no_water_for_bandages" end
    return {
        kind = "wash_bandage", item = item, itemContainer = row.source,
        cleanType = cleanType, object = options.object, square = options.square,
        washInputEntry = row,
        washWaterPlan = plan, waterItem = plan and plan.item or nil, washJobClaim = claim,
        fact = { activity = "wash_bandage", itemType = U().itemType(item) },
    }
end
