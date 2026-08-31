-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Needs = SC.Needs or {}
local Needs = SC.Needs
local states = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor, runtime)
    local root = U().actorState(actor, runtime)
    root.needs = root.needs or {}
    states[actor] = root.needs
    return root.needs
end

local function enumValue(name)
    if CharacterStat == nil then return nil end
    local ok, value = pcall(function() return CharacterStat[name] end)
    return ok and value or nil
end

local function setStat(actor, name, value)
    local stats, statsOk = U().call(actor, "getStats")
    local stat = enumValue(name)
    if not statsOk or not stats or stat == nil then return false end
    value = U().clamp(tonumber(value) or 0, 0, 1)
    local result, called = U().call(stats, "set", stat, value)
    if not called or result == false then return false end
    local after, afterOk = U().call(stats, "get", stat)
    return afterOk and type(after) == "number" and math.abs(after - value) <= 0.001
end

local function compensatePositiveDelta(actor, state, field, statName, currentValue)
    local previous = state[field]
    if type(previous) ~= "number" then
        state[field] = currentValue
        return currentValue
    end
    local delta = currentValue - previous
    local limit = U().config("needsNaturalDeltaLimit") or 1.0
    if delta > 0 and delta <= limit then
        local multiplier = U().clamp(U().config("needsRateMultiplier") or 0.5, 0, 1)
        local adjusted = previous + delta * multiplier
        if setStat(actor, statName, adjusted) then currentValue = adjusted end
    end
    -- Negative deltas are native food/drink effects and remain fully applied.
    state[field] = currentValue
    return currentValue
end

function Needs.updateRates(actor, runtime, current)
    if not actor then return false, "invalid_actor" end
    local state = stateFor(actor, runtime)
    current = current or U().nowMs()
    local sampleMs = U().config("needsRateSampleMs") or 1000
    if current < (state.nextRateSampleAt or 0) then return true, "needs_rate_deferred" end
    state.nextRateSampleAt = current + sampleMs
    local hunger = U().characterStatValue(actor, "HUNGER", 0)
    local thirst = U().characterStatValue(actor, "THIRST", 0)
    hunger = compensatePositiveDelta(actor, state, "sampledHunger", "HUNGER", hunger)
    thirst = compensatePositiveDelta(actor, state, "sampledThirst", "THIRST", thirst)
    state.hunger, state.thirst = hunger, thirst
    return true, "needs_rate_updated"
end

function Needs.assess(actor, runtime)
    local state = stateFor(actor, runtime)
    local hunger = U().characterStatValue(actor, "HUNGER", state.hunger or 0)
    local thirst = U().characterStatValue(actor, "THIRST", state.thirst or 0)
    state.hunger, state.thirst = hunger, thirst
    local active = false
    if SC.NativeActions and type(SC.NativeActions.needsStatus) == "function" then
        local ok, value, kind = pcall(SC.NativeActions.needsStatus, actor)
        active = ok and value == true
        if ok and value ~= true and kind ~= nil
            and type(SC.NativeActions.finishNeeds) == "function" then
            pcall(SC.NativeActions.finishNeeds, actor)
        end
    end
    return {
        hunger = hunger,
        thirst = thirst,
        hungry = hunger >= (U().config("needsHungerThreshold") or 0.55),
        thirsty = thirst >= (U().config("needsThirstThreshold") or 0.48),
        emergency = hunger >= (U().config("needsHungerEmergency") or 0.82)
            or thirst >= (U().config("needsThirstEmergency") or 0.75),
        active = active,
    }
end

local function walkInventory(container, limit, callback, visited)
    if not container or limit.remaining <= 0 then return end
    visited = visited or setmetatable({}, { __mode = "k" })
    if visited[container] then return end
    visited[container] = true
    local items, itemsOk = U().call(container, "getItems")
    if not itemsOk and type(container) == "table" then items = container.items or container end
    U().each(items, limit.remaining, function(item)
        limit.remaining = limit.remaining - 1
        if callback(item) == false or limit.remaining <= 0 then return false end
        local nested, nestedOk = U().call(item, "getInventory")
        if nestedOk and nested then walkInventory(nested, limit, callback, visited) end
        return limit.remaining > 0
    end)
end

local function unsafeFood(item)
    local rotten, rottenOk = U().call(item, "isRotten")
    local burnt, burntOk = U().call(item, "isBurnt")
    local dangerous, dangerousOk = U().call(item, "isbDangerousUncooked")
    local cooked, cookedOk = U().call(item, "isCooked")
    local poison, poisonOk = U().call(item, "getPoisonPower")
    local script, scriptOk = U().call(item, "getScriptItem")
    local cantEat, cantEatOk = U().call(script, "isCantEat")
    if rottenOk and rotten then return true end
    if burntOk and burnt then return true end
    if dangerousOk and dangerous and (not cookedOk or cooked ~= true) then return true end
    if poisonOk and tonumber(poison) and tonumber(poison) > 0 then return true end
    if scriptOk and script and cantEatOk and cantEat then return true end
    return false
end

local function isSafeFood(item)
    if not U().instanceOf(item, "Food") and not U().hasMethod(item, "getHungerChange") then
        return false
    end
    local change, changeOk = U().call(item, "getHungerChange")
    return changeOk and type(change) == "number" and change < -0.001 and not unsafeFood(item)
end

local function fluidConstant(name)
    if Fluid == nil then return nil end
    local ok, value = pcall(function() return Fluid[name] end)
    return ok and value or nil
end

local function isSafeWaterItem(item)
    local fluid, fluidOk = U().call(item, "getFluidContainer")
    if not fluidOk or not fluid then return false end
    local empty, emptyOk = U().call(fluid, "isEmpty")
    if emptyOk and empty then return false end
    local canEmpty, canEmptyOk = U().call(fluid, "canPlayerEmpty")
    if canEmptyOk and canEmpty ~= true then return false end
    local capacity, capacityOk = U().call(fluid, "getCapacity")
    if capacityOk and tonumber(capacity) and tonumber(capacity) > 3 then return false end
    local poisonous, poisonousOk = U().call(fluid, "isPoisonous")
    local taintedStatus, taintedStatusOk = U().call(fluid, "isTainted")
    if poisonousOk and poisonous then return false end
    if taintedStatusOk and taintedStatus then return false end
    local tainted = fluidConstant("TaintedWater")
    local water = fluidConstant("Water")
    if tainted then
        local contains, containsOk = U().call(fluid, "contains", tainted)
        if containsOk and contains then return false end
    end
    local clean, cleanOk = U().call(fluid, "isFilledWithCleanWater")
    if cleanOk then return clean == true end
    local waterOnly, waterOnlyOk = U().call(fluid, "isWaterOnlySource")
    if waterOnlyOk then return waterOnly == true end
    if water then
        local contains, containsOk = U().call(fluid, "contains", water)
        if containsOk then return contains == true end
    end
    local source, sourceOk = U().call(item, "isWaterSource")
    return sourceOk and source == true
end

local function firstInventoryItem(actor, predicate)
    local best, bestScore
    walkInventory(U().inventory(actor), { remaining = 256 }, function(item)
        local ok, accepted = pcall(predicate, item)
        if ok and accepted then
            local score = 1
            if isSafeFood(item) then
                local change, changeOk = U().call(item, "getHungerChange")
                score = changeOk and math.abs(tonumber(change) or 0) or 0
            else
                local fluid, fluidOk = U().call(item, "getFluidContainer")
                local amount, amountOk
                if fluidOk and fluid then amount, amountOk = U().call(fluid, "getAmount") end
                score = amountOk and tonumber(amount) or 0
            end
            if not bestScore or score > bestScore then best, bestScore = item, score end
        end
        return true
    end)
    return best
end

local function nativeNeedsActive(actor)
    if not SC.NativeActions or type(SC.NativeActions.needsStatus) ~= "function" then return false end
    local active, kind = SC.NativeActions.needsStatus(actor)
    if active then return true, kind end
    if type(SC.NativeActions.finishNeeds) == "function" then SC.NativeActions.finishNeeds(actor) end
    return false
end

local function eat(actor, item, hunger)
    local change, changeOk = U().call(item, "getHungerChange")
    local reduction = changeOk and math.abs(tonumber(change) or 0) or 0
    if reduction <= 0 then return false, "food_has_no_hunger_reduction" end
    local desired = math.max(0.1, hunger - 0.25)
    local percentage = U().clamp(desired / reduction, 0.25, 1)
    return U().move(actor, "walk", {
        action = "eat_food",
        item = item,
        percentage = percentage,
        transactional = true,
    })
end

local function drinkItem(actor, item, thirst)
    local fluid, fluidOk = U().call(item, "getFluidContainer")
    local amount, amountOk
    if fluidOk and fluid then amount, amountOk = U().call(fluid, "getAmount") end
    local availableUses = amountOk and math.max(1, math.floor((tonumber(amount) or 0) / 0.12)) or 1
    local uses = math.min(availableUses, math.max(1, math.ceil(thirst * 10)))
    return U().move(actor, "walk", {
        action = "drink_item",
        item = item,
        uses = uses,
        transactional = true,
    })
end

local function validWaterSource(object)
    local has, hasOk = U().call(object, "hasFluid")
    local amount, amountOk = U().call(object, "getFluidAmount")
    local tainted, taintedOk = U().call(object, "isTaintedWater")
    return hasOk and has == true and amountOk and (tonumber(amount) or 0) > 0.05
        and (not taintedOk or tainted ~= true)
end

local function findWaterSource(actor, state)
    local utility = U()
    local ax, ay, az = utility.position(actor)
    if not ax then return nil end
    local radius = math.max(1, math.min(18,
        math.floor(utility.config("needsWaterSourceRadius") or 12)))
    local budget = math.max(1, math.floor(utility.config("needsWaterSquareBudget") or 180))
    state.waterScanPhase = ((state.waterScanPhase or 0) + 1) % 4
    local scanned = 0
    for distance = 0, radius do
        local found
        for dx = -distance, distance do
            for dy = -distance, distance do
                if scanned >= budget then return found end
                local edge = math.max(math.abs(dx), math.abs(dy)) == distance
                local sampled = distance <= 5 or ((dx * 17 + dy * 31) % 4) == state.waterScanPhase
                if edge and sampled then
                    local square = utility.gridSquare(ax + dx, ay + dy, az)
                    if square then
                        scanned = scanned + 1
                        utility.squareObjects(square, function(object)
                            if validWaterSource(object) then found = object return false end
                        end, 48)
                    end
                end
                if found then return found end
            end
        end
    end
    return nil
end

local function drinkWorldSource(actor, source, snapshot, state)
    if U().distance(actor, source) > 1.45 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "water_source_navigation_unavailable"
        end
        local targets = SC.Navigation.interactionTargets(actor, source, { snapshot = snapshot })
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_water_source",
            object = source,
            snapshot = snapshot,
            arrivalDistance = 1.0,
        })
    end
    state.waterSource = nil
    return U().move(actor, "walk", {
        action = "drink_source",
        object = source,
        transactional = true,
    })
end

local function fetchFromCamp(actor, key, predicate, snapshot)
    if not SC.Encounter or type(SC.Encounter.takePlayerSupply) ~= "function" then
        return false, "camp_storage_unavailable"
    end
    local status, reason = SC.Encounter.takePlayerSupply(actor, key, predicate, {
        origin = actor,
        snapshot = snapshot,
        moveMode = "walk",
    })
    return status == "taken" or status == "in_progress", reason or status
end

function Needs.update(actor, player, runtime)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    local state = stateFor(actor, runtime)
    local active, kind = nativeNeedsActive(actor)
    if active then return true, kind == "eat" and "eating" or "drinking" end
    local root = U().actorState(actor, runtime)
    local snapshot = root.senses and root.senses.current or root.snapshot or {}
    if (snapshot.immediateCount or 0) > 0 or (snapshot.pressure or 0) >= 1.5 then
        return false, "needs_unsafe"
    end
    local assessment = Needs.assess(actor, runtime)
    local function consumable(predicate)
        return function(item)
            if SC.PersonalItems and SC.PersonalItems.isProtected(
                item, actor, "needs_consume") then return false end
            return predicate(item)
        end
    end

    if assessment.thirsty then
        local safeWater = consumable(isSafeWaterItem)
        local water = firstInventoryItem(actor, safeWater)
        if water then return drinkItem(actor, water, assessment.thirst) end
        local fetched, fetchReason = fetchFromCamp(actor, "needs_water", safeWater, snapshot)
        if fetched then return true, fetchReason end
        local source = state.waterSource
        if source and not validWaterSource(source) then source, state.waterSource = nil, nil end
        if not source then source = findWaterSource(actor, state) state.waterSource = source end
        if source then return drinkWorldSource(actor, source, snapshot, state) end
        return false, "clean_water_unavailable"
    end

    if assessment.hungry then
        local safeFood = consumable(isSafeFood)
        local food = firstInventoryItem(actor, safeFood)
        if food then return eat(actor, food, assessment.hunger) end
        local fetched, fetchReason = fetchFromCamp(actor, "needs_food", safeFood, snapshot)
        if fetched then return true, fetchReason end
        return false, "safe_food_unavailable"
    end
    return false, "needs_satisfied"
end

function Needs.cancel(actor, reason)
    if SC.Encounter and type(SC.Encounter.cancelPlayerSupply) == "function" then
        SC.Encounter.cancelPlayerSupply(actor)
    end
    if SC.NativeActions and type(SC.NativeActions.cancelNeeds) == "function" then
        return SC.NativeActions.cancelNeeds(actor, reason)
    end
    return true, reason or "needs_cancelled"
end

function Needs.peek(actor)
    return actor and states[actor] or nil
end

function Needs.reset(actor)
    if actor then
        Needs.cancel(actor, "needs_reset")
        states[actor] = nil
        local runtime = U().peekActorState(actor)
        if runtime then runtime.needs = nil end
    else
        for candidate in pairs(states) do Needs.cancel(candidate, "needs_reset") end
        states = setmetatable({}, { __mode = "k" })
    end
    return true
end

return Needs
