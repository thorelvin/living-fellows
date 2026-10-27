-- SPDX-License-Identifier: MIT
-- Small native boundary shared by building services and portable PC hardware.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ControlUtil = SC.ControlUtil or {}
local U = SC.ControlUtil
function U.call(object, method, ...)
    if object == nil then return nil end
    local value, okay = SC.GameplayUtil.call(object, method, ...)
    if okay then return value end
    return nil
end
function U.list(value, limit)
    local result = {}
    if not value then return result end
    if type(value) == "table" and not value.size then
        for i, row in ipairs(value) do if i > (limit or 256) then break end result[#result + 1] = row end
    else
        for i = 0, math.min(tonumber(U.call(value, "size")) or 0, limit or 256) - 1 do
            result[#result + 1] = U.call(value, "get", i)
        end
    end
    return result
end
function U.data(object) return U.call(object, "getModData") end
function U.square(object) return U.call(object, "getSquare") end
function U.position(object)
    local square = U.square(object) or object
    local x, y, z = U.call(square, "getX"), U.call(square, "getY"), U.call(square, "getZ")
    if x == nil or y == nil or z == nil then return nil end
    return math.floor(x), math.floor(y), math.floor(z)
end
function U.present(object)
    return U.square(object) ~= nil and (tonumber(U.call(object, "getObjectIndex")) or -1) >= 0
end
function U.hours()
    return tonumber(U.call(type(getGameTime) == "function" and getGameTime(), "getWorldAgeHours"))
end
function U.now() return SC.GameplayUtil.nowMs() end
function U.skill(player)
    return tonumber(U.call(player, "getPerkLevel", Perks and Perks.Electricity)) or 0
end
-- Build 42 removed getUsedDelta(), while retaining its setter. Read the
-- current/max use contract rather than mistaking a charged battery for flat.
function U.charge(item)
    local current=tonumber(U.call(item,"getCurrentUsesFloat"))
    if current then return math.max(0,math.min(1,current)) end
    local legacy=tonumber(U.call(item,"getUsedDelta"))
    return legacy and math.max(0,math.min(1,legacy)) or nil
end
function U.setCharge(item,charge)
    local current=tonumber(U.call(item,"getCurrentUsesFloat"))
    if current then U.call(item,"setCurrentUsesFloat",math.max(0,math.min(1,charge)))
    else U.call(item,"setUsedDelta",math.max(0,math.min(1,charge))) end
    local observed=U.charge(item)
    return observed and math.abs(observed-charge)<0.0001
end
function U.nativePower(object)
    return SC.TerminalWorld and SC.TerminalWorld.powered(U.square(object)) == true
end
function U.kind(object, kind) return SC.GameplayUtil.instanceOf(object, kind) == true end
function U.near(actor, object, distance)
    local x,y,z = U.position(actor)
    local tx,ty,tz = U.position(object)
    return x ~= nil and tx ~= nil and z == tz and (x-tx)^2 + (y-ty)^2 <= (distance or 3)^2
end
function U.property(object, name)
    local props = U.call(object, "getProperties") or U.call(U.call(object, "getSprite"), "getProperties")
    return U.call(props, "get", name)
end
function U.inventory(actor) return U.call(actor, "getInventory") end
function U.items(actor)
    local found, seen, count = {}, {}, 0
    local function walk(container, depth)
        if not container or seen[container] or depth > 8 or count >= 2048 then return end
        seen[container] = true
        for _, item in ipairs(U.list(U.call(container, "getItems"), 2048 - count)) do
            count = count + 1
            if U.call(item, "getContainer") == container then
                found[#found + 1] = item
                walk(U.call(item, "getInventory"), depth + 1)
            end
        end
    end
    walk(U.inventory(actor), 0)
    return found
end
function U.owns(actor, item)
    for _, candidate in ipairs(U.items(actor)) do if candidate == item then return true end end
    return false
end
function U.parts(actor, costs)
    local selected, left = {}, {}
    for kind, amount in pairs(costs or {}) do left[kind] = amount end
    for _, item in ipairs(U.items(actor)) do
        local kind = U.call(item, "getFullType")
        if (left[kind] or 0) > 0 then selected[#selected + 1] = item left[kind] = left[kind] - 1 end
    end
    local missing = {}
    for kind, amount in pairs(left) do if amount > 0 then missing[#missing + 1] = kind .. " x" .. amount end end
    table.sort(missing)
    if #missing > 0 then return nil, "Missing: " .. table.concat(missing, ", ") end
    return selected
end
function U.hasTool(actor, kind)
    for _, item in ipairs(U.items(actor)) do if U.call(item, "getFullType") == kind then return true end end
    return false
end
-- On the game thread, either every exact component is removed or all are put
-- back in their original containers. Never manufacture replacement parts.
function U.consume(actor, costs)
    local items, reason = U.parts(actor, costs)
    if not items then return false, reason end
    local removed = {}
    for _, item in ipairs(items) do
        local container = U.call(item, "getContainer")
        if not U.owns(actor, item) then reason = "Supplies changed." break end
        U.call(container, "Remove", item)
        if SC.GameplayUtil.containerContainsIdentity(container, item) then reason = "A component could not be removed." break end
        removed[#removed + 1] = { item = item, container = container }
    end
    if #removed ~= #items then
        for _, row in ipairs(removed) do U.call(row.container, "AddItem", row.item) end
        return false, reason
    end
    return true, removed
end
function U.refund(receipt)
    for _,row in ipairs(type(receipt)=="table" and receipt or {}) do
        if not SC.GameplayUtil.containerContainsIdentity(row.container,row.item) then U.call(row.container,"AddItem",row.item) end
    end
end
function U.error(reason) return tostring(reason or "Unavailable"):gsub("_", " ") end
return U
