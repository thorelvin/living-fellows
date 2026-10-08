-- SPDX-License-Identifier: MIT
-- One meal per persisted base job. Native recipe actions own the actual food
-- conversion; exact-item transfers and the job receipt own the surrounding work.
if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "TimedActions/ISTimedActionQueue")
    pcall(require, "TimedActions/ISAddItemInRecipe")
    pcall(require, "TimedActions/ISTakeWaterAction")
    pcall(require, "TimedActions/ISToggleStoveAction")
    pcall(require, "Entity/TimedActions/ISHandcraftAction")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ChefWork = SC.ChefWork or {}
local Chef = SC.ChefWork
local states = setmetatable({}, { __mode = "k" })
local scans = setmetatable({}, { __mode = "k" })
local autoChecks = setmetatable({}, { __mode = "k" })
local recipes = {
    { name = "Salad", base = "Base.Bowl", hot = false },
    { name = "Sandwich", base = "Base.BreadSlices", hot = false },
    { name = "Soup", base = "Base.Pot", hot = true, portioned = true },
    { id = "fish_soup", name = "Soup", base = "Base.Pot", hot = true,
        portioned = true, ingredient = "Base.FishFillet" },
    { id = "fish_stew", name = "Stew", base = "Base.Pot", hot = true,
        portioned = true, ingredient = "Base.FishFillet" },
    { id = "venison_stew", name = "Stew", base = "Base.Pot", hot = true,
        portioned = true, ingredient = "Base.Venison" },
    { id = "venison_sandwich", name = "Sandwich", base = "Base.BreadSlices",
        hot = false, ingredient = "Base.Venison" },
    { id = "stir_fry", name = "Stir fry", base = "Base.Pan", hot = true },
    { id = "pasta", name = "PastaPot", base = "Base.Pot", hot = true,
        portioned = true, water = 1.5, dry = "Base.Pasta",
        preparedBase = "Base.WaterPotPasta" },
}
local preparedTypes = {
    ["Base.Salad"] = true, ["Base.Sandwich"] = true,
    ["Base.PotOfSoupRecipe"] = true, ["Base.SoupBowl"] = true,
    ["Base.SoupBowlClay"] = true, ["Base.PotOfStew"] = true,
    ["Base.StewBowl"] = true, ["Base.StewBowlClay"] = true,
    ["Base.PanFriedVegetables"] = true, ["Base.PastaPot"] = true,
    ["Base.PastaBowl"] = true, ["Base.PastaBowlClay"] = true,
}

local function U() return SC.GameplayUtil end
local function call(object, method, ...) return U().call(object, method, ...) end
local function now() return U().nowMs() end
local function numeric(value)
    if type(value) == "number" then return value end
    return value ~= nil and tonumber(tostring(value)) or nil
end
local function waterRequired(spec)
    return spec.base == "Base.Pot" and (spec.water or 0.9) or 0
end
local function usablePotFluid(item, required)
    local fluid = select(1, call(item, "getFluidContainer"))
    if not fluid or select(1, call(fluid, "isTainted")) == true
        or select(1, call(item, "isTaintedWater")) == true then
        return false, fluid
    end
    if (numeric(select(1, call(fluid, "getCapacity"))) or 0) < required then
        return false, fluid
    end
    local amount = numeric(select(1, call(fluid, "getAmount"))) or 0
    if amount > 0 then
        local primary = select(1, call(fluid, "getPrimaryFluid"))
        if select(1, call(primary, "getFluidTypeString")) ~= "Water" then
            return false, fluid
        end
        local primaryAmount = numeric(select(1, call(fluid,
            "getPrimaryFluidAmount")))
        -- A water-dominant mixture is not the same as the clean water the
        -- handcraft recipe consumes. Keep a partly filled pot water-only.
        if not primaryAmount or primaryAmount + 0.001 < amount then
            return false, fluid
        end
        if Fluid and Fluid.Water
            and select(1, call(fluid, "contains", Fluid.Water)) ~= true then
            return false, fluid
        end
    end
    return true, fluid, amount
end
local function contains(container, item)
    return container and item and U().inventoryContains(container, item) == true
end
local function safeFood(item, willCook, allowFrozen)
    if item == nil then return false end
    for _, method in ipairs({ "isRotten", "isBurnt", "isPoisonous" }) do
        if select(1, call(item, method)) == true then return false end
    end
    if not allowFrozen and select(1, call(item, "isFrozen")) == true then
        return false
    end
    if (numeric(select(1, call(item, "getPoisonPower"))) or 0) > 0 then return false end
    if not willCook and select(1, call(item, "isDangerousUncooked")) == true
        and select(1, call(item, "isCooked")) ~= true then return false end
    return true
end

local function heatFinished(state)
    if state.heatPurpose == "ingredient" then
        return select(1, call(state.resultItem, "isCooked")) == true
            and safeFood(state.resultItem)
    end
    return Chef.isPrepared(state.resultItem)
end

local function finishHeat(state, job)
    if state.heatPurpose == "ingredient" then
        if not heatFinished(state) then return false, "chef_venison_not_safe", true end
        state.heatPurpose = nil
        job.target.heatPurpose = nil
        job.target.ownOven = nil
        job.target.prepVenison = false
        job.target.cookPhase = "prep_venison_cooked"
        state.phase = "select_ingredient"
        state.nativeCommitted = true
    else
        state.phase = state.spec.portioned and "portion" or "deposit"
    end
    return true
end

function Chef.isPrepared(item)
    local itemType = U().itemType(item)
    if not preparedTypes[itemType] or not safeFood(item) then return false end
    if (itemType == "Base.PotOfSoupRecipe" or itemType == "Base.PotOfStew"
        or itemType == "Base.PanFriedVegetables" or itemType == "Base.PastaPot"
        or itemType == "Base.SoupBowl" or itemType == "Base.SoupBowlClay"
        or itemType == "Base.StewBowl" or itemType == "Base.StewBowlClay"
        or itemType == "Base.PastaBowl" or itemType == "Base.PastaBowlClay")
        and select(1, call(item, "isCooked")) ~= true then
        return false
    end
    return true
end

local function containerFor(object)
    local container = select(1, call(object, "getContainer"))
    return container, container and tostring(select(1, call(container, "getType")) or "") or ""
end

local function poweredFridge(container, kind)
    return kind == "fridge" and select(1, call(container, "isPowered")) == true
end

-- Walk every camp area, including linked floors, in bounded slices. Building
-- a fixed 1600-square list skipped later floors in larger camps.
local function nextCampScanPoint(scan)
    local zones = scan.zones
    if #zones == 0 then return nil, true end
    for _ = 1, 128 do
        local unfinished = false
        for _, zone in ipairs(zones) do
            if not zone.done then unfinished = true break end
        end
        if not unfinished then return nil, true end
        local zone = zones[scan.zoneIndex]
        scan.zoneIndex = scan.zoneIndex % #zones + 1
        if zone and not zone.done then
            local x, y = zone.x, zone.y
            zone.x = zone.x + 1
            if zone.x > zone.x2 then zone.x, zone.y = zone.x1, zone.y + 1 end
            if zone.y > zone.y2 then zone.done = true end
            local key = x .. ":" .. y .. ":" .. zone.z
            if not scan.seen[key] then
                scan.seen[key] = true
                return { x = x, y = y, z = zone.z }, false
            end
        end
    end
    return nil, false
end

local function campScan(base, retainCompleted)
    local scan = scans[base]
    if scan and scan.done
        and (retainCompleted == true or now() - scan.finishedAt < 12000) then
        return scan
    end
    if not scan or (scan.done and now() - scan.finishedAt >= 12000) then
        scan = { zones = {}, zoneIndex = 1, seen = {}, containers = {},
            fridges = {}, ovens = {}, fires = {}, water = {},
            craftSurfaces = {}, done = false }
        for _, zone in ipairs(base.zones or {}) do
            if zone.kind == "area" then
                scan.zones[#scan.zones + 1] = {
                    x1 = zone.x1, x2 = zone.x2, y2 = zone.y2,
                    x = zone.x1, y = zone.y1, z = zone.z,
                }
            end
        end
        scans[base] = scan
    end
    for _ = 1, 24 do
        local point, exhausted = nextCampScanPoint(scan)
        if not point then
            if exhausted then scan.done, scan.finishedAt = true, now() end
            break
        end
        local square = U().gridSquare(point.x, point.y, point.z)
        if square and SC.BaseLife.isInside(point) then
            U().squareObjects(square, function(object)
                local sprite = select(1, call(object, "getSprite"))
                local props = sprite and select(1, call(sprite, "getProperties"))
                if props and select(1, call(props, "has", "IsTable")) == true
                    and select(1, call(props, "has", "Surface")) == true then
                    scan.craftSurfaces[#scan.craftSurfaces + 1] = object
                end
                local container, kind = containerFor(object)
                if container then
                    local row = { object = object, container = container, kind = kind }
                    scan.containers[#scan.containers + 1] = row
                    if kind == "fridge" then
                        scan.fridges[#scan.fridges + 1] = row
                    end
                end
                if type(instanceof) == "function" and instanceof(object, "IsoStove") then
                    scan.ovens[#scan.ovens + 1] = object
                end
                if select(1, call(object, "isWaterSource")) == true
                    and select(1, call(object, "getFluidAmount")) then
                    scan.water[#scan.water + 1] = object
                end
            end, 48)
            if CCampfireSystem and CCampfireSystem.instance then
                local fire = select(1, call(CCampfireSystem.instance,
                    "getLuaObjectOnSquare", square))
                if fire and fire.isLit == true and (fire.fuelAmt or 0) > 5 then
                    local object = select(1, call(fire, "getIsoObject"))
                    local container = object and select(1, call(object, "getContainer"))
                    if object and container then
                        scan.fires[#scan.fires + 1] = {
                            fire = fire, object = object, container = container,
                        }
                    end
                end
            end
        end
    end
    return scan
end

local function markedContainerMap()
    local marked = {}
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, false)) do
        local container = SC.BaseLife.resolveContainer(storage)
        if container then marked[container] = storage end
    end
    return marked
end

local function sources(scan, marked, wanted, actor)
    local result, seen = {}, {}
    local storages = {}
    if wanted then
        for _, category in ipairs(wanted) do
            for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
                storages[#storages + 1] = storage
            end
        end
    else
        storages = SC.BaseLife.storageRows(nil, true)
    end
    for _, storage in ipairs(storages) do
        local container, object = SC.BaseLife.resolveContainer(storage),
            SC.BaseLife.resolveObject(storage)
        if container and object and not seen[container] then
            seen[container] = true
            result[#result + 1] = { container = container, object = object,
                storage = storage }
        end
    end
    for _, row in ipairs(scan.containers) do
        if not seen[row.container] and marked[row.container] == nil then
            seen[row.container] = true
            result[#result + 1] = row
        end
    end
    local inventory = actor and U().inventory(actor)
    if inventory and not seen[inventory] then
        result[#result + 1] = { container = inventory, object = actor,
            carried = true }
    end
    return result
end

local function withdrawalAllowed(row, item)
    if not contains(row.container, item) then return false end
    if row.storage then
        if not SC.BaseLife.withdrawable(row.storage)
            or SC.BaseLife.storage(row.storage.id) ~= row.storage
            or SC.BaseLife.resolveContainer(row.storage) ~= row.container then return false end
        return SC.BaseLife.availableCountExact(row.storage, U().itemType(item)) > 0
    end
    return true
end

local function bestItem(rows, predicate)
    local best, bestRow, age = nil, nil, -math.huge
    for _, row in ipairs(rows) do
        for _, item in ipairs(U().inventoryItems(row.container, 500)) do
            if predicate(item) and withdrawalAllowed(row, item) then
                local itemAge = numeric(select(1, call(item, "getAge"))) or 0
                if not best or itemAge > age then
                    best, bestRow, age = item, row, itemAge
                end
            end
        end
    end
    return bestRow, best
end

local function recipeByName(name)
    if type(getEvolvedRecipes) ~= "function" then return nil end
    local list = getEvolvedRecipes()
    for index = 0, U().listSize(list) - 1 do
        local recipe = U().listGet(list, index)
        if select(1, call(recipe, "getUntranslatedName")) == name then return recipe end
    end
    return nil
end

local function eligibleIngredient(recipe, actor, baseItem, rows, spec)
    if not ArrayList or type(ArrayList.new) ~= "function" then
        return nil, nil, "recipe_container_list_missing"
    end
    local containers = ArrayList.new()
    for _, row in ipairs(rows) do containers:add(row.container) end
    local eligible = select(1, call(recipe, "getItemsCanBeUse", actor, baseItem, containers))
    if not eligible then return nil, nil, "recipe_ingredients_unavailable" end
    local allowed = {}
    for index = 0, U().listSize(eligible) - 1 do
        allowed[U().listGet(eligible, index)] = true
    end
    local row, item = bestItem(rows, function(candidate)
        return allowed[candidate] == true and safeFood(candidate, spec.hot)
            and (not spec.ingredient or U().itemType(candidate) == spec.ingredient)
    end)
    return row, item, item and nil or "chef_ingredient_missing"
end

local function previewBase(spec, baseItem, bread)
    if not spec.preparedBase and baseItem then return baseItem end
    if not spec.preparedBase and not bread then return nil end
    if not instanceItem then return nil end
    local kind = spec.preparedBase or spec.base
    local ok, item = pcall(instanceItem, kind)
    return ok and item or nil
end

local function storageDestinations(scan)
    local preferred, fallback, seen = {}, {}, {}
    local marked = markedContainerMap()
    for _, storage in ipairs(SC.BaseLife.depositStorageRows("food")) do
        local container, object = SC.BaseLife.resolveContainer(storage),
            SC.BaseLife.resolveObject(storage)
        if container and object then
            seen[container] = true
            local row = { container = container, object = object, storage = storage }
            local kind = tostring(select(1, call(container, "getType")) or "")
            local rows = poweredFridge(container, kind) and preferred or fallback
            rows[#rows + 1] = row
        end
    end
    for _, row in ipairs(scan.fridges) do
        if not seen[row.container] and marked[row.container] == nil then
            seen[row.container] = true
            local kind = tostring(select(1, call(row.container, "getType")) or "")
            local rows = poweredFridge(row.container, kind) and preferred or fallback
            rows[#rows + 1] = row
        end
    end
    local result = preferred
    for _, row in ipairs(fallback) do result[#result + 1] = row end
    return result
end

local function approach(actor, object, action)
    local at, targets, reason = U().directInteractionAccess(actor, object)
    if at == true then return true, "at_" .. action end
    if reason == "no_interaction_targets" then return false, reason, true end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable", true
    end
    local handled, pathReason = SC.Navigation.requestAny(actor, targets, "walk", {
        action = action, targetSquare = U().squareOf(object), object = object,
        arrivalDistance = 0.35, requireSameSquare = true,
        continuousApproach = true, workCampOnly = true, workReach = true,
    })
    return false, handled and pathReason or pathReason or "chef_approach_failed",
        handled ~= true
end

local function approachCraftSurface(actor, scan)
    if not HandcraftLogic then return false, "chef_craft_logic_missing", true end
    local logic = HandcraftLogic.new(actor, nil, nil)
    if type(logic.findCraftSurface) ~= "function" then
        return true -- lightweight controller harness has no native surface API
    end
    local nearby = logic:findCraftSurface(actor, 2)
    if nearby then return true, nearby end
    for _, object in ipairs(scan.craftSurfaces or {}) do
        if select(1, U().directInteractionAccess(actor, object)) == true then
            return true, object
        end
    end
    for _, object in ipairs(scan.craftSurfaces or {}) do
        local at, reason, terminal = approach(actor, object,
            "chef_craft_surface")
        if not at then return false, reason, terminal end
        return true, object
    end
    return false, "chef_craft_surface_missing", true
end

local function craftCapacity(actor, reserve)
    local inventory = U().inventory(actor)
    local weight = numeric(select(1, call(inventory, "getCapacityWeight")))
    local capacity = numeric(select(1, call(inventory, "getEffectiveCapacity", actor)))
    if weight and capacity and weight + reserve > capacity then
        return false, "chef_carry_capacity_low", true
    end
    return true
end

local function take(actor, state, row, item)
    if row.carried then
        return contains(U().inventory(actor), item), "chef_supply_carried",
            not contains(U().inventory(actor), item)
    end
    local at, reason, terminal = approach(actor, row.object, "chef_take_supply")
    -- A walk in progress is handled work; an unreachable target is not. The
    -- earlier `terminal and false or true` always produced true (its middle
    -- operand is false), the pitfall SCNavigation documents at its passage
    -- check, so every failed approach also reported progress.
    if not at then return not terminal, reason, terminal end
    if not withdrawalAllowed(row, item) then return false, "chef_supply_changed", true end
    local moved, moveReason
    if row.storage and SC.BaseWork then
        moved, moveReason = SC.BaseWork.withdrawFromStorage(actor,
            state.transfer, row.storage, row.container, item)
        if moved and not contains(U().inventory(actor), item) then
            return true, moveReason, false
        end
    else
        moved, moveReason = U().transferItemVerified(row.container,
            U().inventory(actor), item)
    end
    if moved and contains(U().inventory(actor), item) then
        state.borrowed = state.borrowed or {}
        local recorded = false
        for _, entry in ipairs(state.borrowed) do
            if entry.item == item then recorded = true break end
        end
        if not recorded then
            state.borrowed[#state.borrowed + 1] = { item = item, source = row }
        end
        if state.job and state.job.target
            and (state.job.target.cookPhase == nil
                or state.job.target.cookPhase == "selected") then
            state.job.target.cookPhase = "supplies_withdrawn"
        end
    end
    return moved == true, moveReason, moved ~= true
end

local function queueAction(actor, state, job, action, phase)
    if not action or not ISTimedActionQueue or type(ISTimedActionQueue.add) ~= "function" then
        return false, "chef_native_action_missing", true
    end
    local originalComplete, originalStop = action.complete, action.stop
    action.complete = function(self)
        local completed = originalComplete(self)
        if completed == true then
            if phase == "combine" then state.nativeCommitted = true end
            state.actionResult = self.baseItem or self.item or true
            job.target.cookPhase = phase .. "_done"
            if self.baseItem and type(self.baseItem.getModData) == "function" then
                self.baseItem:getModData().SC_ChefJobId = job.id
                job.target.resultItemId = select(1, call(self.baseItem, "getID"))
            end
        else
            state.actionFailed = "chef_native_action_failed"
        end
        return completed
    end
    action.stop = function(self)
        state.actionFailed = "chef_native_action_interrupted"
        return originalStop(self)
    end
    state.action, state.actionResult, state.actionFailed = action, nil, nil
    state.actionAt = now()
    job.target.cookPhase = phase .. "_queued"
    local ok = pcall(ISTimedActionQueue.add, action)
    if not ok then
        state.action, job.target.cookPhase = nil, "failed"
        return false, "chef_native_queue_rejected", true
    end
    return true, "chef_" .. phase
end

local function waitAction(state, phase)
    if state.actionFailed then return false, state.actionFailed, true end
    if state.actionResult ~= nil then
        state.action = nil
        return true, phase .. "_done"
    end
    if not state.action or now() - state.actionAt > 90000 then
        return false, "chef_native_outcome_unknown", true
    end
    return true, "chef_" .. phase
end

local function queuePotPortions(actor, state, job)
    local capacity, reason, terminal = craftCapacity(actor, 3.5)
    if not capacity then return false, reason, terminal end
    if not ISHandcraftAction or not HandcraftLogic
        or not ISTimedActionQueue or type(getScriptManager) ~= "function"
        or not ArrayList then return false, "chef_portion_action_missing", true end
    local recipe = select(1, call(getScriptManager(), "getCraftRecipe", "Make2Bowls"))
    if not recipe then return false, "chef_portion_recipe_missing", true end
    local containers = ArrayList.new()
    containers:add(U().inventory(actor))
    local logic = HandcraftLogic.new(actor, nil, nil)
    if type(logic.findCraftSurface) == "function"
        and type(logic.setIsoObject) == "function" then
        logic:setIsoObject(state.craftSurface
            or logic:findCraftSurface(actor, 2))
    end
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, state.resultItem)
    if logic:canPerformCurrentRecipe() ~= true then
        return false, "chef_portion_requirements_missing", true
    end
    local action = ISHandcraftAction.FromLogic(logic)
    if not action or type(action.performRecipe) ~= "function" then
        return false, "chef_portion_action_missing", true
    end
    local originalPerform, originalStop = action.performRecipe, action.stop
    action.performRecipe = function(self)
        local before = {}
        for _, item in ipairs(U().inventoryItems(U().inventory(actor), math.huge)) do
            before[item] = true
        end
        originalPerform(self)
        state.nativeCommitted = true
        local outputs = ArrayList.new()
        self.logic:getCreatedOutputItems(outputs)
        local generated = {}
        for index = 0, U().listSize(outputs) - 1 do
            generated[#generated + 1] = U().listGet(outputs, index)
        end
        if #generated < 3 then
            generated = {}
            for _, item in ipairs(U().inventoryItems(U().inventory(actor), math.huge)) do
                if not before[item] then generated[#generated + 1] = item end
            end
        end
        local portions, returnedPot = {}, nil
        for _, item in ipairs(generated) do
            local kind = U().itemType(item)
            if (kind == "Base.SoupBowl" or kind == "Base.SoupBowlClay"
                or kind == "Base.StewBowl" or kind == "Base.StewBowlClay"
                or kind == "Base.PastaBowl" or kind == "Base.PastaBowlClay")
                and Chef.isPrepared(item) then
                portions[#portions + 1] = item
            elseif kind == "Base.Pot" then
                returnedPot = item
            end
        end
        if #portions ~= 2 or not returnedPot
            or not contains(U().inventory(actor), portions[1])
            or not contains(U().inventory(actor), portions[2])
            or not contains(U().inventory(actor), returnedPot) then
            state.actionFailed = "chef_portion_outcome_unknown"
            return
        end
        for index, item in ipairs(portions) do
            local data = select(1, call(item, "getModData"))
            if data then
                data.SC_ChefJobId, data.SC_ChefPortionIndex = job.id, index
            end
        end
        if returnedPot then
            local data = select(1, call(returnedPot, "getModData"))
            if data then data.SC_ChefPotJobId = job.id end
        end
        state.portions, state.emptyPot, state.actionResult = portions, returnedPot, true
        job.target.cookPhase = "portions_ready"
        job.target.portionIndex = 1
    end
    action.stop = function(self)
        state.actionFailed = "chef_portion_action_interrupted"
        return originalStop(self)
    end
    state.action, state.actionResult, state.actionFailed = action, nil, nil
    state.actionAt, job.target.cookPhase = now(), "portion_queued"
    local accepted = pcall(ISTimedActionQueue.add, action)
    if not accepted then
        state.action = nil
        return false, "chef_portion_queue_rejected", true
    end
    return true, "chef_dividing_pot_meal"
end

local function breadKnife(item)
    if not item then return false end
    local usable = numeric(select(1, call(item, "getCondition")))
    if usable ~= nil and usable <= 0 then return false end
    return U().itemHasTag(item, "dullknife")
        or U().itemHasTag(item, "sharpknife")
        or U().itemHasTag(item, "meatcleaver")
end

local function fishKnife(item)
    if not breadKnife(item) then return false end
    return U().itemHasTag(item, "sharpknife")
        or U().itemHasTag(item, "meatcleaver")
end

local function sliceableFish(item)
    if not U().itemHasTag(item, "uncutfish") or not safeFood(item, true) then
        return false
    end
    if RecipeCodeOnTest and type(RecipeCodeOnTest.cutFish) == "function" then
        local okay, allowed = pcall(RecipeCodeOnTest.cutFish, item, nil)
        return okay and allowed == true
    end
    return true
end

local function queueSlices(actor, state, job, kind)
    local capacity, reason, terminal = craftCapacity(actor, 2)
    if not capacity then return false, reason, terminal end
    local bread = kind == "bread"
    local recipeName = bread and "SliceBread" or "SliceFillet"
    local outputKind = bread and "Base.BreadSlices" or "Base.FishFillet"
    local expected = bread and 3 or 2
    local input = bread and state.prepBread or state.prepFish
    if not ISHandcraftAction or not HandcraftLogic or not ISTimedActionQueue
        or type(getScriptManager) ~= "function" or not ArrayList then
        return false, "chef_" .. kind .. "_action_missing", true
    end
    local recipe = select(1, call(getScriptManager(), "getCraftRecipe", recipeName))
    if not recipe then return false, "chef_" .. kind .. "_recipe_missing", true end
    local inventory = U().inventory(actor)
    local containers = ArrayList.new()
    containers:add(inventory)
    local logic = HandcraftLogic.new(actor, nil, nil)
    if type(logic.findCraftSurface) == "function"
        and type(logic.setIsoObject) == "function" then
        logic:setIsoObject(state.craftSurface
            or logic:findCraftSurface(actor, 2))
    end
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, input)
    if logic:canPerformCurrentRecipe() ~= true then
        return false, "chef_" .. kind .. "_requirements_missing", true
    end
    local action = ISHandcraftAction.FromLogic(logic)
    if not action or type(action.performRecipe) ~= "function" then
        return false, "chef_" .. kind .. "_action_missing", true
    end
    local originalPerform, originalStop = action.performRecipe, action.stop
    action.performRecipe = function(self)
        local before = {}
        for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
            before[item] = true
        end
        originalPerform(self)
        state.nativeCommitted = true
        local outputs = ArrayList.new()
        self.logic:getCreatedOutputItems(outputs)
        local slices = {}
        for index = 0, U().listSize(outputs) - 1 do
            local item = U().listGet(outputs, index)
            if U().itemType(item) == outputKind
                and contains(inventory, item) and not before[item]
                and safeFood(item, not bread) then slices[#slices + 1] = item end
        end
        if #slices == 0 then
            for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
                if not before[item] and U().itemType(item) == outputKind
                    and safeFood(item, not bread) then slices[#slices + 1] = item end
            end
        end
        if #slices ~= expected then
            state.actionFailed = "chef_" .. kind .. "_outcome_unknown"
            return
        end
        for _, item in ipairs(slices) do
            local data = select(1, call(item, "getModData"))
            if data then
                data.SC_ChefPrepJobId, data.SC_ChefPrepKind = job.id, kind
            end
        end
        if bread then
            state.baseItem = slices[1]
            job.target.baseItemId = select(1, call(slices[1], "getID"))
        else
            job.target.prepFish = false
        end
        state.actionResult = slices[1]
        job.target.cookPhase = kind .. "_sliced"
    end
    action.stop = function(self)
        state.actionFailed = "chef_" .. kind .. "_action_interrupted"
        return originalStop(self)
    end
    state.action, state.actionResult, state.actionFailed = action, nil, nil
    state.actionAt, job.target.cookPhase = now(), kind .. "_slice_queued"
    local accepted = pcall(ISTimedActionQueue.add, action)
    if not accepted then
        state.action = nil
        return false, "chef_" .. kind .. "_queue_rejected", true
    end
    return true, "chef_slicing_" .. kind
end

-- A pot of dry pasta is a native handcraft input for the evolved PastaPot
-- recipe. Keep the exact output identity so a reload never prepares it twice.
local function queuePastaBase(actor, state, job)
    local capacity, reason, terminal = craftCapacity(actor, 3.5)
    if not capacity then return false, reason, terminal end
    if not ISHandcraftAction or not HandcraftLogic or not ISTimedActionQueue
        or type(getScriptManager) ~= "function" or not ArrayList then
        return false, "chef_pasta_action_missing", true
    end
    local recipe = select(1, call(getScriptManager(), "getCraftRecipe",
        "PlacePastaInCookingPot2"))
    if not recipe then return false, "chef_pasta_recipe_missing", true end
    local inventory = U().inventory(actor)
    local containers = ArrayList.new()
    containers:add(inventory)
    local logic = HandcraftLogic.new(actor, nil, nil)
    if type(logic.findCraftSurface) == "function"
        and type(logic.setIsoObject) == "function" then
        logic:setIsoObject(state.craftSurface
            or logic:findCraftSurface(actor, 2))
    end
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, state.baseItem)
    if logic:canPerformCurrentRecipe() ~= true then
        return false, "chef_pasta_requirements_missing", true
    end
    local action = ISHandcraftAction.FromLogic(logic)
    if not action or type(action.performRecipe) ~= "function" then
        return false, "chef_pasta_action_missing", true
    end
    local originalPerform, originalStop = action.performRecipe, action.stop
    action.performRecipe = function(self)
        local before = {}
        for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
            before[item] = true
        end
        originalPerform(self)
        state.nativeCommitted = true
        local outputs = ArrayList.new()
        self.logic:getCreatedOutputItems(outputs)
        local prepared
        for index = 0, U().listSize(outputs) - 1 do
            local item = U().listGet(outputs, index)
            if U().itemType(item) == state.spec.preparedBase
                and contains(inventory, item) and not before[item] then
                prepared = item
                break
            end
        end
        if not prepared then
            for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
                if not before[item]
                    and U().itemType(item) == state.spec.preparedBase then
                    prepared = item
                    break
                end
            end
        end
        if not prepared then
            state.actionFailed = "chef_pasta_outcome_unknown"
            return
        end
        local data = select(1, call(prepared, "getModData"))
        if not data then
            state.actionFailed = "chef_pasta_receipt_unavailable"
            return
        end
        data.SC_ChefPrepJobId, data.SC_ChefPrepKind = job.id, "pasta"
        state.baseItem, state.actionResult = prepared, prepared
        job.target.baseItemId = select(1, call(prepared, "getID"))
        job.target.cookPhase = "pasta_prepared"
    end
    action.stop = function(self)
        state.actionFailed = "chef_pasta_action_interrupted"
        return originalStop(self)
    end
    state.action, state.actionResult, state.actionFailed = action, nil, nil
    state.actionAt, job.target.cookPhase = now(), "pasta_prep_queued"
    local accepted = pcall(ISTimedActionQueue.add, action)
    if not accepted then
        state.action = nil
        return false, "chef_pasta_queue_rejected", true
    end
    return true, "chef_preparing_pasta"
end

local function countPrepared(scan)
    local seen, count = {}, 0
    for _, row in ipairs(storageDestinations(scan)) do
        if not seen[row.container] then
            seen[row.container] = true
            for _, item in ipairs(U().inventoryItems(row.container, 500)) do
                if Chef.isPrepared(item) then count = count + 1 end
            end
        end
    end
    return count
end

function Chef.ensureAutomaticJob(actor, resident)
    if resident.role ~= "chef" or resident.duty ~= true then return false, "not_chef" end
    local base = SC.BaseLife.active()
    if not base then return false, "base_missing" end
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "cook" and job.state ~= "completed" and job.state ~= "cancelled" then
            return false, "chef_job_pending"
        end
    end
    if (autoChecks[actor] or 0) > now() then
        return false, "chef_stock_check_cooldown"
    end
    local scan = campScan(base)
    if not scan.done then return false, "chef_scan_pending" end
    autoChecks[actor] = now() + 5000
    if #storageDestinations(scan) == 0 then return false, "chef_food_storage_unavailable" end
    local residents = 0
    for _, row in ipairs(SC.BaseLife.summary().residentRows or {}) do
        if row.duty == true then residents = residents + 1 end
    end
    if countPrepared(scan) >= residents then return false, "chef_stock_ready" end
    return SC.BaseLife.enqueueJob({ type = "cook", priority = 1,
        assignedId = U().idOf(actor), target = { manual = false } })
end

function Chef.requestMeal(actor, player)
    local id = U().idOf(actor)
    local resident = SC.BaseLife.resident(id)
    local base = SC.BaseLife.active()
    if not resident or resident.role ~= "chef" or resident.duty ~= true then
        return false, "chef_not_on_duty"
    end
    if not base or not player or not SC.BaseLife.isInside(player) then
        return false, "chef_player_not_at_camp"
    end
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "cook" and job.assignedId == id and job.target
            and job.target.manual == true and job.state ~= "cancelled" then
            return false, "chef_meal_already_requested"
        end
    end
    return SC.BaseLife.enqueueJob({ type = "cook", priority = 5,
        assignedId = id, target = { manual = true } })
end

local function stateFor(actor, job)
    local state = states[actor]
    if state and state.jobId ~= job.id then state = nil end
    if not state then
        state = { jobId = job.id, phase = "select", transfer = {},
            borrowed = {}, recovered = job.target and job.target.cookPhase ~= nil
                and job.target.cookPhase ~= "selected" }
        states[actor] = state
    end
    state.job = job
    return state
end

local function itemId(item)
    return item and select(1, call(item, "getID")) or nil
end

local function rememberOwnedOven(job, oven)
    local square = select(1, call(oven, "getSquare"))
    if not square then return end
    local x, y, z = select(1, call(square, "getX")),
        select(1, call(square, "getY")), select(1, call(square, "getZ"))
    if x ~= nil and y ~= nil and z ~= nil then
        job.target.ownedOvenX, job.target.ownedOvenY,
            job.target.ownedOvenZ = x, y, z
    end
end

local function restoredOwnedOven(job, scan)
    if job.target.ownOven ~= true then return nil, true end
    local x, y, z = job.target.ownedOvenX, job.target.ownedOvenY,
        job.target.ownedOvenZ
    local matches = {}
    for _, oven in ipairs(scan.ovens) do
        local square = select(1, call(oven, "getSquare"))
        if x ~= nil and y ~= nil and z ~= nil and square
            and select(1, call(square, "getX")) == x
            and select(1, call(square, "getY")) == y
            and select(1, call(square, "getZ")) == z then
            matches[#matches + 1] = oven
        elseif x == nil and #scan.ovens == 1 then
            -- A legacy receipt can name its stove only when there is one.
            matches[#matches + 1] = oven
        end
    end
    return #matches == 1 and matches[1] or nil, #matches == 1
end

local function itemTagged(item, job)
    local data = item and select(1, call(item, "getModData"))
    return type(data) == "table" and data.SC_ChefJobId == job.id
end

local function findInventoryItem(container, predicate)
    for _, item in ipairs(U().inventoryItems(container, math.huge)) do
        if predicate(item) then return item end
    end
    return nil
end

local function restoreReceipt(actor, player, state, job, scan, marked)
    local phase = job.target.cookPhase
    if phase == nil or phase == "selected" then return true end
    if phase == "stored" or phase == "served" or phase == "meal_taken" then
        -- These phases are written only after a verified delivery, or after
        -- someone else took the food out of the cooker. The recipient may have
        -- eaten a serving before the completed job is reconciled.
        return true, phase, false, true
    end
    if job.target.mealTakenCleanup == true
        or phase == "meal_taken_cleanup" then
        local oven, found = restoredOwnedOven(job, scan)
        if not found then return false, "chef_owned_oven_missing", true end
        state.mealTaken, state.ownOven, state.phase = true, oven, "switch_off"
        return true
    end
    local allSources = sources(scan, marked, nil, actor)
    for _, spec in ipairs(recipes) do
        if (spec.id or spec.name) == job.target.recipe then
            state.spec, state.recipe, state.sources = spec,
                recipeByName(spec.name), allSources
            break
        end
    end
    if not state.spec or not state.recipe then
        return false, "chef_receipt_recipe_missing", true
    end
    local inventory = U().inventory(actor)
    if phase == "bread_slice_queued" or phase == "bread_sliced" then
        local slice = findInventoryItem(inventory, function(item)
            local data = select(1, call(item, "getModData"))
            return U().itemType(item) == "Base.BreadSlices"
                and type(data) == "table" and data.SC_ChefPrepJobId == job.id
                and data.SC_ChefPrepKind == "bread" and safeFood(item)
        end)
        if not slice then return false, "chef_bread_receipt_missing", true end
        state.baseItem, state.phase = slice, "select_ingredient"
        job.target.baseItemId = itemId(slice)
        job.target.cookPhase = "base_carried"
        return true
    end
    if phase == "pasta_prep_queued" or phase == "pasta_prepared" then
        local prepared = findInventoryItem(inventory, function(item)
            local data = select(1, call(item, "getModData"))
            return U().itemType(item) == state.spec.preparedBase
                and type(data) == "table" and data.SC_ChefPrepJobId == job.id
                and data.SC_ChefPrepKind == "pasta"
        end)
        if not prepared then return false, "chef_pasta_outcome_unknown", true end
        state.baseItem, state.phase = prepared, "select_ingredient"
        job.target.baseItemId = itemId(prepared)
        job.target.cookPhase = "base_carried"
        return true
    end
    local baseId = job.target.baseItemId
    local baseItem = findInventoryItem(inventory, function(item)
        return baseId ~= nil and itemId(item) == baseId
    end)
    if phase == "thawing_ingredient" then
        if not baseItem then return false, "chef_receipt_base_missing", true end
        local frozen = findInventoryItem(inventory, function(item)
            local data = select(1, call(item, "getModData"))
            return U().itemType(item) == state.spec.ingredient
                and type(data) == "table" and data.SC_ChefPrepJobId == job.id
                and data.SC_ChefPrepKind == "thaw"
        end)
        if not frozen then return false, "chef_thaw_receipt_missing", true end
        state.baseItem, state.frozenItem, state.phase = baseItem, frozen,
            "wait_thaw"
        return true
    end
    if phase == "fish_slice_queued" or phase == "fish_sliced" then
        if not baseItem then return false, "chef_receipt_base_missing", true end
        local fillet = findInventoryItem(inventory, function(item)
            local data = select(1, call(item, "getModData"))
            return U().itemType(item) == "Base.FishFillet"
                and type(data) == "table" and data.SC_ChefPrepJobId == job.id
                and data.SC_ChefPrepKind == "fish" and safeFood(item, true)
        end)
        if not fillet then return false, "chef_fish_receipt_missing", true end
        state.baseItem, state.phase = baseItem, "select_ingredient"
        job.target.prepFish = false
        job.target.cookPhase = "base_carried"
        return true
    end
    if string.find(tostring(phase), "prep_venison_", 1, true) == 1 then
        if not baseItem then return false, "chef_receipt_base_missing", true end
        state.baseItem, state.heatPurpose = baseItem, "ingredient"
        local function preparedVenison(item)
            local data = select(1, call(item, "getModData"))
            return U().itemType(item) == "Base.Venison"
                and type(data) == "table" and data.SC_ChefPrepJobId == job.id
                and data.SC_ChefPrepKind == "venison"
        end
        local ingredient = findInventoryItem(inventory, preparedVenison)
        if ingredient then
            state.resultItem = ingredient
            if select(1, call(ingredient, "isCooked")) == true then
                if not safeFood(ingredient) then
                    return false, "chef_venison_not_safe", true
                end
                if job.target.ownOven == true then
                    for _, oven in ipairs(scan.ovens) do
                        if select(1, call(oven, "Activated")) == true then
                            state.ownOven = oven
                            break
                        end
                    end
                end
                state.phase = "switch_off"
                return true
            end
            if job.target.ownOven == true then
                for _, oven in ipairs(scan.ovens) do
                    if select(1, call(oven, "Activated")) == true then
                        state.ownOven = oven
                        break
                    end
                end
            end
            state.phase = "heat"
            return true
        end
        for _, oven in ipairs(scan.ovens) do
            local container = select(1, call(oven, "getContainer"))
            ingredient = findInventoryItem(container, preparedVenison)
            if ingredient then
                state.resultItem, state.cooker, state.phase = ingredient,
                    { object = oven, container = container }, "wait_heat"
                state.ownOven = job.target.ownOven == true and oven or nil
                return true
            end
        end
        for _, fire in ipairs(scan.fires) do
            ingredient = findInventoryItem(fire.container, preparedVenison)
            if ingredient then
                state.resultItem, state.cooker, state.phase = ingredient,
                    fire, "wait_heat"
                return true
            end
        end
        return false, "chef_venison_receipt_missing", true
    end
    local result = findInventoryItem(inventory, function(item)
        return itemTagged(item, job)
    end)
    state.bowls = {}
    for _, bowlId in ipairs(job.target.bowlIds or {}) do
        local bowl = findInventoryItem(inventory, function(item)
            return itemId(item) == bowlId
        end)
        if bowl then state.bowls[#state.bowls + 1] = bowl end
    end
    if phase == "base_carried" or phase == "dry_carried"
        or phase == "ingredients_carried"
        or phase == "bowl_1_carried" or phase == "bowl_2_carried"
        or phase == "bowls_carried"
        or phase == "fill_pot_queued" or phase == "fill_pot_done" then
        if not baseItem then return false, "chef_receipt_base_missing", true end
        state.baseItem = baseItem
        if phase == "base_carried" or phase == "fill_pot_queued"
            or phase == "fill_pot_done" or phase == "dry_carried" then
            if state.spec.dry and U().itemType(baseItem) == state.spec.preparedBase then
                state.phase = "select_ingredient"
            elseif phase == "dry_carried" then
                state.dryItem = findInventoryItem(inventory, function(item)
                    return itemId(item) == job.target.dryItemId
                end)
                if not state.dryItem then return false, "chef_dry_receipt_missing", true end
                state.phase = "prepare_pasta"
            else
                state.phase = waterRequired(state.spec) > 0 and "fill_pot"
                    or "select_ingredient"
            end
            return true
        end
        local ingredientId = job.target.ingredientId
        state.ingredient = findInventoryItem(inventory, function(item)
            return ingredientId ~= nil and itemId(item) == ingredientId
        end)
        if not state.ingredient then return false, "chef_receipt_ingredient_missing", true end
        state.phase = state.spec.portioned and #state.bowls < 2
            and "select_bowls" or "combine"
        return true
    end
    if phase == "portion_queued" or phase == "portions_ready"
        or phase == "portion_1_delivered" or phase == "portions_delivered" then
        local first, second
        local pot, potContainer
        local containers = { inventory }
        if player then containers[#containers + 1] = U().inventory(player) end
        for _, row in ipairs(scan.containers) do
            containers[#containers + 1] = row.container
        end
        for _, container in ipairs(containers) do
            for _, item in ipairs(U().inventoryItems(container, math.huge)) do
                if itemTagged(item, job) and Chef.isPrepared(item) then
                    local data = select(1, call(item, "getModData"))
                    if data.SC_ChefPortionIndex == 1 then first = item end
                    if data.SC_ChefPortionIndex == 2 then second = item end
                end
                local data = select(1, call(item, "getModData"))
                if data and data.SC_ChefPotJobId == job.id then
                    pot, potContainer = item, container
                end
            end
        end
        if (phase == "portion_queued" or phase == "portions_ready")
            and (not first or not second) then
            return false, "chef_portion_outcome_unknown", true
        end
        if phase == "portion_1_delivered" and not second then
            return false, "chef_portion_outcome_unknown", true
        end
        -- An already delivered serving can legitimately have been consumed.
        -- Keep its slot so the remaining serving remains number two.
        state.portions, state.portionCount = { [1] = first, [2] = second }, 2
        state.emptyPot = pot
        if phase == "portions_delivered" then
            if not pot then return false, "chef_pot_receipt_missing", true end
            if potContainer ~= inventory then
                return true, "stored", false, true
            end
            state.phase = "return_pot"
            return true
        end
        state.portionIndex = phase == "portion_1_delivered" and 2 or 1
        state.resultItem = state.portions[state.portionIndex]
        if not contains(inventory, state.resultItem) then
            return false, "chef_portion_delivery_unknown", true
        end
        state.phase = "deposit"
        return true
    end
    if phase == "combine_queued" or phase == "combine_done"
        or phase == "needs_heat" or phase == "ready"
        or phase == "oven_on_queued" or phase == "oven_on_done"
        or phase == "oven_off_queued" or phase == "oven_off_done" then
        if not result then return false, "chef_native_outcome_unknown", true end
        state.resultItem = result
        state.phase = state.spec.hot and (Chef.isPrepared(result)
            and (state.spec.portioned and "portion" or "deposit")
            or "heat") or "deposit"
        if job.target.ownOven == true then
            for _, oven in ipairs(scan.ovens) do
                if select(1, call(oven, "Activated")) == true then
                    state.ownOven = oven
                    break
                end
            end
            if state.ownOven then
                state.heatInterrupted = state.phase == "heat"
                state.phase = "switch_off"
            end
        end
        return true
    end
    if phase == "heating" then
        for _, oven in ipairs(scan.ovens) do
            local container = select(1, call(oven, "getContainer"))
            local found = findInventoryItem(container, function(item)
                return itemTagged(item, job)
            end)
            if found then
                state.resultItem, state.cooker = found,
                    { object = oven, container = container }
                state.ownOven = job.target.ownOven == true and oven or nil
                state.phase = "wait_heat"
                return true
            end
        end
        for _, fire in ipairs(scan.fires) do
            local found = findInventoryItem(fire.container, function(item)
                return itemTagged(item, job)
            end)
            if found then
                state.resultItem, state.cooker, state.phase =
                    found, fire, "wait_heat"
                return true
            end
        end
        return false, "chef_heating_receipt_missing", true
    end
    return false, "chef_restart_needs_recovery", true
end

local function chooseRecipe(actor, state, job, scan, marked)
    local allSources = sources(scan, marked, nil, actor)
    local fridgeReady = #storageDestinations(scan) > 0
    local missingTool
    local availableBowls = 0
    for _, source in ipairs(allSources) do
        local count = 0
        for _, candidate in ipairs(U().inventoryItems(source.container, 500)) do
            if U().itemType(candidate) == "Base.Bowl" then count = count + 1 end
        end
        if source.storage then
            count = math.min(count, SC.BaseLife.availableCountExact(source.storage,
                "Base.Bowl"))
        end
        availableBowls = availableBowls + count
    end
    local first = 1
    if job.target.manual ~= true then
        local completed = SC.BaseLife.active().completed or {}
        local cooked = 0
        for _, row in ipairs(completed) do
            if row.type == "cook" then cooked = cooked + 1 end
        end
        first = (cooked % #recipes) + 1
    end
    for offset = 0, #recipes - 1 do
        local index = ((first + offset - 1) % #recipes) + 1
        local spec = recipes[index]
        local poweredOven = false
        for _, oven in ipairs(scan.ovens) do
            local ovenContainer = select(1, call(oven, "getContainer"))
            if select(1, call(ovenContainer, "isPowered")) == true then
                poweredOven = true
                break
            end
        end
        local heaterReady = poweredOven or (not SC.BaseLife.outdoorNightRestricted()
            and #scan.fires > 0)
        local heatReady = not spec.hot or ((not spec.portioned or availableBowls >= 2)
            and fridgeReady and heaterReady)
        -- When a meal cannot start, still inspect its safe ingredients. That
        -- lets us name a missing implement instead of blaming generic stock.
        if heatReady or fridgeReady then
            local recipe = recipeByName(spec.name)
            local filling, needsCookIngredient, needsSliceFish,
                needsThawIngredient = true, false, false, false
            local fishNeedsKnife = false
            if spec.ingredient then
                local _, available = bestItem(allSources, function(candidate)
                    return U().itemType(candidate) == spec.ingredient
                        and safeFood(candidate, spec.hot)
                end)
                filling = available ~= nil
                if not filling then
                    local _, frozen = bestItem(allSources, function(candidate)
                        return U().itemType(candidate) == spec.ingredient
                            and select(1, call(candidate, "isFrozen")) == true
                            and safeFood(candidate, spec.hot
                                or spec.id == "venison_sandwich", true)
                    end)
                    local cooked = frozen and select(1, call(frozen, "isCooked")) == true
                    if frozen and (spec.id ~= "venison_sandwich" or cooked
                        or poweredOven or (not SC.BaseLife.outdoorNightRestricted()
                            and #scan.fires > 0)) then
                        filling, needsThawIngredient = true, true
                        needsCookIngredient = spec.id == "venison_sandwich"
                            and not cooked
                    end
                end
                if not filling and spec.id == "venison_sandwich"
                    and (poweredOven or (not SC.BaseLife.outdoorNightRestricted()
                        and #scan.fires > 0)) then
                    local _, raw = bestItem(allSources, function(candidate)
                        return U().itemType(candidate) == "Base.Venison"
                            and safeFood(candidate, true)
                            and select(1, call(candidate, "isCooked")) ~= true
                    end)
                    filling, needsCookIngredient = raw ~= nil, raw ~= nil
                end
                if not filling and (spec.id == "fish_soup"
                    or spec.id == "fish_stew") then
                    local _, wholeFish = bestItem(allSources, sliceableFish)
                    local _, knife = bestItem(allSources, fishKnife)
                    fishNeedsKnife = wholeFish ~= nil and knife == nil
                    filling, needsSliceFish = wholeFish ~= nil and knife ~= nil,
                        wholeFish ~= nil and knife ~= nil
                end
            elseif spec.name == "Sandwich" then
                local _, safeFilling = bestItem(allSources, function(candidate)
                    local kind = U().itemType(candidate)
                    return kind ~= "Base.Bread" and kind ~= "Base.BreadSlices"
                        and select(1, call(candidate, "getCategory")) == "Food"
                        and safeFood(candidate)
                end)
                filling = safeFilling ~= nil
            elseif spec.name == "Salad" or spec.name == "Soup"
                or spec.id == "stir_fry" or spec.id == "pasta" then
                local _, safeFilling = bestItem(allSources, function(candidate)
                    local kind = U().itemType(candidate)
                    return kind ~= spec.base and kind ~= "Base.Bowl"
                        and kind ~= "Base.Pot" and kind ~= "Base.Pasta"
                        and kind ~= "Base.Pan"
                        and (spec.name ~= "Soup" or (kind ~= "Base.Venison"
                            and not U().itemHasTag(candidate, "uncutfish")))
                        and select(1, call(candidate, "getCategory")) == "Food"
                        and safeFood(candidate, spec.hot)
                end)
                filling = safeFilling ~= nil
            end
            local dryRow, dryItem
            if spec.dry then
                dryRow, dryItem = bestItem(allSources, function(candidate)
                    return U().itemType(candidate) == spec.dry
                        and safeFood(candidate)
                end)
            end
            local row, item = bestItem(allSources, function(candidate)
                if U().itemType(candidate) ~= spec.base then return false end
                if waterRequired(spec) == 0 then return true end
                return usablePotFluid(candidate, waterRequired(spec))
            end)
            local breadRow, bread, knifeRow, knife
            if not item and spec.base == "Base.BreadSlices" then
                breadRow, bread = bestItem(allSources, function(candidate)
                    return U().itemType(candidate) == "Base.Bread"
                        and safeFood(candidate)
                end)
                knifeRow, knife = bestItem(allSources, breadKnife)
            end
            local basePresent
            if not item and spec.base ~= "Base.BreadSlices" then
                _, basePresent = bestItem(allSources, function(candidate)
                    return U().itemType(candidate) == spec.base
                end)
            end
            local possibleFilling = filling
            local preview = recipe and previewBase(spec, item, bread)
            if recipe and filling and preview
                and not (needsCookIngredient or needsSliceFish
                    or needsThawIngredient) then
                local _, usable = eligibleIngredient(recipe, actor, preview,
                    allSources, spec)
                filling = usable ~= nil
            elseif recipe and not preview then
                filling = false
            end
            if recipe and not missingTool and (not spec.dry or dryItem) then
                if fishNeedsKnife and item and heaterReady
                    and (not spec.portioned or availableBowls >= 2) then
                    missingTool = "knife"
                elseif possibleFilling then
                    local eligible = filling
                    if not item and spec.base ~= "Base.BreadSlices"
                        and type(instanceItem) == "function" then
                        local ok, substitute = pcall(instanceItem, spec.base)
                        if ok and substitute and not (needsCookIngredient
                            or needsSliceFish or needsThawIngredient) then
                            local _, candidate = eligibleIngredient(recipe, actor,
                                substitute, allSources, spec)
                            eligible = candidate ~= nil
                        end
                    end
                    if eligible then
                        if not item and not basePresent then
                            if bread and not knife then missingTool = "knife"
                            elseif spec.base == "Base.Bowl" then missingTool = "bowl"
                            elseif spec.base == "Base.Pot" then missingTool = "pot"
                            elseif spec.base == "Base.Pan" then missingTool = "pan" end
                        elseif spec.portioned and availableBowls < 2
                            and heaterReady then
                            missingTool = "bowl"
                        elseif spec.hot and not heaterReady
                            and (not spec.portioned or availableBowls >= 2) then
                            missingTool = "heat_source"
                        end
                    end
                end
            end
            if heatReady and recipe and filling and (not spec.dry or dryItem)
                and ((row and item) or (bread and knife))
                and (waterRequired(spec) == 0
                    or usablePotFluid(item, waterRequired(spec))) then
                state.spec, state.recipe = spec, recipe
                state.baseRow, state.baseItem, state.sources = row, item, allSources
                state.dryRow, state.dryItem = dryRow, dryItem
                state.prepBreadRow, state.prepBread = breadRow, bread
                state.prepKnifeRow, state.prepKnife = knifeRow, knife
                state.phase = item and "take_base" or "take_bread"
                job.target.recipe = spec.id or spec.name
                job.target.portioned = spec.portioned == true
                job.target.prepVenison = needsCookIngredient
                job.target.prepFish = needsSliceFish
                job.target.prepFrozen = needsThawIngredient
                return true
            end
        end
    end
    return false, missingTool and "chef_tool_missing:" .. missingTool
        or "chef_recipe_supplies_missing", true
end

local function deposit(actor, state, job, scan)
    local item = state.resultItem
    if not item or not Chef.isPrepared(item) then return false, "chef_meal_not_safe", true end
    if job.target.manual == true and (state.portionIndex == nil
        or state.portionIndex == 1) then
        local player = state.player
        if not player or not SC.BaseLife.isInside(player) then
            return true, "chef_waiting_for_player"
        end
        local at, targets, accessReason = U().directInteractionAccess(actor, player)
        if not at then
            if accessReason == "no_interaction_targets" then
                return true, "chef_waiting_for_player_access"
            end
            local handled, reason = SC.Navigation.requestAny(actor, targets, "walk", {
                action = "chef_serve_player", targetSquare = U().squareOf(player),
                arrivalDistance = 0.35, requireSameSquare = true,
                continuousApproach = true,
            })
            return handled == true, reason, handled ~= true
        end
        local moved, reason = U().transferItemVerified(U().inventory(actor),
            U().inventory(player), item)
        if moved then
            job.target.cookPhase = "served"
            return true, "chef_meal_served", false, true
        end
        return false, reason, true
    end
    local destination
    for _, candidate in ipairs(storageDestinations(scan)) do
        local room = SC.WorkTransport and SC.WorkTransport.hasRoom
            and select(1, SC.WorkTransport.hasRoom(candidate.container, actor, item))
        if room ~= false then destination = candidate break end
    end
    if not destination then return true, "chef_waiting_for_food_storage" end
    local at, reason, terminal = approach(actor, destination.object, "chef_store_meal")
    if not at then return not terminal, reason, terminal end
    local moved, moveReason
    if destination.storage and SC.BaseWork then
        moved, moveReason = SC.BaseWork.depositToStorage(actor, state.transfer,
            destination.storage, destination.container, item)
    else
        moved, moveReason = U().transferItemVerified(U().inventory(actor),
            destination.container, item)
    end
    if moved and contains(destination.container, item) then
        job.target.cookPhase = "stored"
        return true, "chef_meal_stored", false, true
    end
    return moved == true, moveReason, moved ~= true
end

local function returnPot(actor, state, job, scan)
    local pot = state.emptyPot
    if not pot or U().itemType(pot) ~= "Base.Pot"
        or not contains(U().inventory(actor), pot) then
        return false, "chef_empty_pot_missing", true
    end
    local destination
    for _, category in ipairs({ "tools", "general", "food" }) do
        for _, storage in ipairs(SC.BaseLife.depositStorageRows(category)) do
            local container, object = SC.BaseLife.resolveContainer(storage),
                SC.BaseLife.resolveObject(storage)
            if container and object and SC.BaseLife.storageAcceptsDeposit(storage,
                container) == true then
                destination = { container = container, object = object,
                    storage = storage }
                break
            end
        end
        if destination then break end
    end
    if not destination then
        local marked = markedContainerMap()
        for _, row in ipairs(scan.containers) do
            if marked[row.container] == nil and row.kind ~= "fridge"
                and row.kind ~= "freezer" then
                destination = row
                break
            end
        end
    end
    if not destination then return true, "chef_waiting_for_pot_storage" end
    local at, reason, terminal = approach(actor, destination.object,
        "chef_return_pot")
    if not at then return not terminal, reason, terminal end
    local moved, moveReason
    if destination.storage and SC.BaseWork then
        moved, moveReason = SC.BaseWork.depositToStorage(actor, state.transfer,
            destination.storage, destination.container, pot)
    else
        moved, moveReason = U().transferItemVerified(U().inventory(actor),
            destination.container, pot)
    end
    if moved and contains(destination.container, pot) then
        job.target.cookPhase = "stored"
        return true, "chef_pot_returned", false, true
    end
    return moved == true, moveReason, moved ~= true
end

function Chef.update(actor, baseState, job, player)
    if not job or job.type ~= "cook" then return false, "not_cook_job", true end
    if not SC.BaseLife.isInside(actor) then return false, "chef_outside_camp", true end
    job.target = type(job.target) == "table" and job.target or {}
    local state = stateFor(actor, job)
    state.player = player
    -- An active recipe keeps its discovered stations until completion. A
    -- large camp must not pause cooking for a fresh floor survey every 12s.
    local scan = campScan(SC.BaseLife.active(), true)
    state.scan = scan
    if not scan.done then return true, "chef_scan_pending" end
    local marked = markedContainerMap()
    if state.phase == "select" and job.target.cookPhase ~= nil
        and job.target.cookPhase ~= "selected" then
        local restored, restoreReason, terminal, completed =
            restoreReceipt(actor, player, state, job, scan, marked)
        if completed then return true, restoreReason, false, true end
        if restored ~= true then return false, restoreReason, terminal end
    end
    if state.phase == "select" then
        local chosen, reason, terminal = chooseRecipe(actor, state, job, scan, marked)
        if not chosen then return false, reason, terminal end
        job.target.cookPhase = "selected"
    end
    if state.phase == "take_bread" then
        local taken, reason, terminal = take(actor, state,
            state.prepBreadRow, state.prepBread)
        if not taken or not contains(U().inventory(actor), state.prepBread) then
            return taken, reason, terminal
        end
        state.phase = "take_bread_knife"
    end
    if state.phase == "take_bread_knife" then
        local taken, reason, terminal = take(actor, state,
            state.prepKnifeRow, state.prepKnife)
        if not taken or not contains(U().inventory(actor), state.prepKnife) then
            return taken, reason, terminal
        end
        state.phase = "slice_bread"
    end
    if state.phase == "slice_bread" then
        local at, surface, terminal = approachCraftSurface(actor, scan)
        if not at then return not terminal, surface, terminal end
        state.craftSurface = surface
        local queued, reason, terminal = queueSlices(actor, state, job, "bread")
        if queued then state.phase = "wait_slice_bread" end
        return queued, reason, terminal
    end
    if state.phase == "wait_slice_bread" then
        local done, reason, terminal = waitAction(state, "bread_slice")
        if not done or not state.actionResult then return done, reason, terminal end
        state.phase = "select_ingredient"
        job.target.cookPhase = "base_carried"
    end
    if state.phase == "take_base" then
        local taken, reason, terminal = take(actor, state, state.baseRow, state.baseItem)
        if not taken or not contains(U().inventory(actor), state.baseItem) then
            return taken, reason, terminal
        end
        job.target.cookPhase = "base_carried"
        job.target.baseItemId = select(1, call(state.baseItem, "getID"))
        state.phase = waterRequired(state.spec) > 0 and "fill_pot"
            or "select_ingredient"
    end
    if state.phase == "fill_pot" then
        local fluid = select(1, call(state.baseItem, "getFluidContainer"))
        if not fluid then return false, "chef_pot_has_no_fluid_container", true end
        if select(1, call(fluid, "isTainted")) == true then
            return false, "chef_pot_water_tainted", true
        end
        if select(1, call(state.baseItem, "isTaintedWater")) == true then
            return false, "chef_pot_water_tainted", true
        end
        if not usablePotFluid(state.baseItem, waterRequired(state.spec)) then
            return false, "chef_pot_contains_non_water", true
        end
        if (numeric(select(1, call(fluid, "getAmount"))) or 0)
            >= waterRequired(state.spec) then
            state.phase = state.spec.dry and "take_dry" or "select_ingredient"
        else
            local water
            for _, source in ipairs(scan.water) do
                local amount = numeric(select(1, call(source, "getFluidAmount"))) or 0
                local tainted, known = call(source, "isTaintedWater")
                if amount >= waterRequired(state.spec) and known and tainted == false then
                    water = source
                    break
                end
            end
            if not water then return false, "chef_clean_water_missing", true end
            local at, reason, terminal = approach(actor, water, "chef_fill_pot")
            if not at then return not terminal, reason, terminal end
            if not ISTakeWaterAction then return false, "chef_water_action_missing", true end
            local queued, queueReason, failed = queueAction(actor, state, job,
                ISTakeWaterAction:new(actor, state.baseItem, water, false), "fill_pot")
            if queued then state.phase = "wait_fill_pot" end
            return queued, queueReason, failed
        end
    end
    if state.phase == "wait_fill_pot" then
        local done, reason, terminal = waitAction(state, "fill_pot")
        if done and state.actionResult then state.phase = "fill_pot" end
        return done, reason, terminal
    end
    if state.phase == "take_dry" then
        if not state.dryItem then
            state.dryRow, state.dryItem = bestItem(state.sources,
                function(candidate)
                    return U().itemType(candidate) == state.spec.dry
                        and safeFood(candidate)
                end)
        end
        if not state.dryItem then return false, "chef_dry_pasta_missing", true end
        local taken, reason, terminal = take(actor, state,
            state.dryRow, state.dryItem)
        if not taken or not contains(U().inventory(actor), state.dryItem) then
            return taken, reason, terminal
        end
        job.target.dryItemId = itemId(state.dryItem)
        job.target.cookPhase = "dry_carried"
        state.phase = "prepare_pasta"
    end
    if state.phase == "prepare_pasta" then
        local at, surface, terminal = approachCraftSurface(actor, scan)
        if not at then return not terminal, surface, terminal end
        state.craftSurface = surface
        local queued, reason, terminal = queuePastaBase(actor, state, job)
        if queued then state.phase = "wait_pasta" end
        return queued, reason, terminal
    end
    if state.phase == "wait_pasta" then
        local done, reason, terminal = waitAction(state, "pasta_prep")
        if not done or not state.actionResult then return done, reason, terminal end
        state.phase = "select_ingredient"
        job.target.cookPhase = "base_carried"
    end
    if state.phase == "select_ingredient" then
        local row, item, reason = eligibleIngredient(state.recipe, actor,
            state.baseItem, state.sources, state.spec)
        if not item and job.target.prepFrozen == true then
            local frozenRow, frozen = bestItem(state.sources, function(candidate)
                return U().itemType(candidate) == state.spec.ingredient
                    and select(1, call(candidate, "isFrozen")) == true
                    and safeFood(candidate, state.spec.hot
                        or state.spec.id == "venison_sandwich", true)
            end)
            if frozen then
                state.frozenRow, state.frozenItem = frozenRow, frozen
                state.phase = "take_frozen_ingredient"
            end
        end
        if state.phase == "select_ingredient" and not item
            and job.target.prepFish == true then
            local fishRow, fish = bestItem(state.sources, sliceableFish)
            local knifeRow, knife = bestItem(state.sources, fishKnife)
            if fish and knife then
                state.prepFishRow, state.prepFish = fishRow, fish
                state.prepKnifeRow, state.prepKnife = knifeRow, knife
                state.phase = "take_whole_fish"
            end
        end
        if state.phase == "select_ingredient" and not item
            and job.target.prepVenison == true then
            row, item = bestItem(state.sources, function(candidate)
                return U().itemType(candidate) == "Base.Venison"
                    and select(1, call(candidate, "isCooked")) ~= true
                    and safeFood(candidate, true)
            end)
            if item then
                state.rawVenisonRow, state.rawVenison = row, item
                state.phase = "take_raw_venison"
            end
        end
        if state.phase == "select_ingredient" and not item then
            return false, reason, true
        end
        if state.phase == "select_ingredient" then
            state.ingredientRow, state.ingredient = row, item
            state.phase = "take_ingredient"
        end
    end
    if state.phase == "take_frozen_ingredient" then
        local taken, reason, terminal = take(actor, state,
            state.frozenRow, state.frozenItem)
        if not taken or not contains(U().inventory(actor), state.frozenItem) then
            return taken, reason, terminal
        end
        local data = select(1, call(state.frozenItem, "getModData"))
        if not data then return false, "chef_thaw_receipt_unavailable", true end
        data.SC_ChefPrepJobId, data.SC_ChefPrepKind = job.id, "thaw"
        state.phase, job.target.cookPhase = "wait_thaw", "thawing_ingredient"
        return true, "chef_ingredient_thawing"
    end
    if state.phase == "wait_thaw" then
        if not contains(U().inventory(actor), state.frozenItem) then
            return false, "chef_thaw_item_missing", true
        end
        if select(1, call(state.frozenItem, "isFrozen")) == true then
            return true, "chef_ingredient_thawing"
        end
        if not safeFood(state.frozenItem, state.spec.hot
            or state.spec.id == "venison_sandwich") then
            return false, "chef_thawed_food_unsafe", true
        end
        state.phase, job.target.cookPhase = "select_ingredient", "base_carried"
        job.target.prepFrozen = false
        return true, "chef_ingredient_thawed"
    end
    if state.phase == "take_whole_fish" then
        local taken, reason, terminal = take(actor, state,
            state.prepFishRow, state.prepFish)
        if not taken or not contains(U().inventory(actor), state.prepFish) then
            return taken, reason, terminal
        end
        state.phase = "take_fish_knife"
    end
    if state.phase == "take_fish_knife" then
        local taken, reason, terminal = take(actor, state,
            state.prepKnifeRow, state.prepKnife)
        if not taken or not contains(U().inventory(actor), state.prepKnife) then
            return taken, reason, terminal
        end
        state.phase = "slice_fish"
    end
    if state.phase == "slice_fish" then
        local at, surface, terminal = approachCraftSurface(actor, scan)
        if not at then return not terminal, surface, terminal end
        state.craftSurface = surface
        local queued, reason, terminal = queueSlices(actor, state, job, "fish")
        if queued then state.phase = "wait_slice_fish" end
        return queued, reason, terminal
    end
    if state.phase == "wait_slice_fish" then
        local done, reason, terminal = waitAction(state, "fish_slice")
        if not done or not state.actionResult then return done, reason, terminal end
        state.phase = "select_ingredient"
        job.target.cookPhase = "base_carried"
    end
    if state.phase == "take_raw_venison" then
        local taken, reason, terminal = take(actor, state,
            state.rawVenisonRow, state.rawVenison)
        if not taken or not contains(U().inventory(actor), state.rawVenison) then
            return taken, reason, terminal
        end
        local data = select(1, call(state.rawVenison, "getModData"))
        if not data then return false, "chef_venison_receipt_unavailable", true end
        data.SC_ChefPrepJobId, data.SC_ChefPrepKind = job.id, "venison"
        state.resultItem, state.heatPurpose = state.rawVenison, "ingredient"
        job.target.heatPurpose = "ingredient"
        job.target.cookPhase = "prep_venison_needs_heat"
        state.phase = "heat"
    end
    if state.phase == "take_ingredient" then
        local taken, reason, terminal = take(actor, state, state.ingredientRow,
            state.ingredient)
        if not taken or not contains(U().inventory(actor), state.ingredient) then
            return taken, reason, terminal
        end
        job.target.cookPhase = "ingredients_carried"
        state.phase = state.spec.portioned and "select_bowls" or "combine"
        job.target.ingredientId = select(1, call(state.ingredient, "getID"))
    end
    if state.phase == "select_bowls" then
        state.bowls = state.bowls or {}
        if #state.bowls >= 2 then
            state.phase = "combine"
            job.target.cookPhase = "bowls_carried"
        else
            local row, bowl = bestItem(state.sources, function(item)
                if U().itemType(item) ~= "Base.Bowl" then return false end
                for _, carried in ipairs(state.bowls) do
                    if carried == item then return false end
                end
                return true
            end)
            if not bowl then return false, "chef_soup_bowls_missing", true end
            state.bowlRow, state.bowlTarget = row, bowl
            state.phase = "take_bowl"
        end
    end
    if state.phase == "take_bowl" then
        local taken, reason, terminal = take(actor, state, state.bowlRow,
            state.bowlTarget)
        if not taken or not contains(U().inventory(actor), state.bowlTarget) then
            return taken, reason, terminal
        end
        state.bowls[#state.bowls + 1] = state.bowlTarget
        job.target.bowlIds = job.target.bowlIds or {}
        job.target.bowlIds[#job.target.bowlIds + 1] = itemId(state.bowlTarget)
        job.target.cookPhase = "bowl_" .. #state.bowls .. "_carried"
        state.bowlRow, state.bowlTarget = nil, nil
        state.phase = "select_bowls"
        return true, "chef_bowl_carried"
    end
    if state.phase == "combine" then
        if not contains(U().inventory(actor), state.baseItem)
            or not contains(U().inventory(actor), state.ingredient) then
            return false, "chef_ingredients_lost", true
        end
        if not ISAddItemInRecipe or type(ISAddItemInRecipe.new) ~= "function" then
            return false, "chef_recipe_action_missing", true
        end
        local action = ISAddItemInRecipe:new(actor, state.recipe,
            state.baseItem, state.ingredient)
        local queued, reason, terminal = queueAction(actor, state, job, action, "combine")
        if queued then state.phase = "wait_combine" end
        return queued, reason, terminal
    end
    if state.phase == "wait_combine" then
        local done, reason, terminal = waitAction(state, "combine")
        if not done or not state.actionResult then return done, reason, terminal end
        state.resultItem = state.actionResult
        state.phase = state.spec.hot and "heat" or "deposit"
        job.target.cookPhase = state.spec.hot and "needs_heat" or "ready"
    end
    if state.phase == "heat" then
        -- The engine cooks either the assembled pot or a raw sandwich filling.
        if heatFinished(state) then
            local finished, reason, terminal = finishHeat(state, job)
            if not finished then return false, reason, terminal end
        else
            local cooker
            for _, oven in ipairs(scan.ovens) do
                local container = select(1, call(oven, "getContainer"))
                if container and select(1, call(container, "isPowered")) == true then
                    cooker = { object = oven, container = container }
                    break
                end
            end
            if not cooker and not SC.BaseLife.outdoorNightRestricted() then
                for _, fire in ipairs(scan.fires) do
                    if fire.fire.isLit == true and (fire.fire.fuelAmt or 0) > 5 then
                        cooker = fire
                        break
                    end
                end
            end
            if not cooker then return false, "chef_heat_source_missing", true end
            local at, reason, terminal = approach(actor, cooker.object, "chef_cook_meal")
            if not at then return not terminal, reason, terminal end
            if cooker.fire == nil and select(1, call(cooker.object, "Activated")) ~= true then
                if not ISToggleStoveAction then return false, "chef_oven_action_missing", true end
                local actionName = state.heatPurpose == "ingredient"
                    and "prep_venison_oven_on" or "oven_on"
                local queued, queueReason, failed = queueAction(actor, state, job,
                    ISToggleStoveAction:new(actor, cooker.object), actionName)
                if queued then
                    state.phase, state.ownOven = "wait_oven", cooker.object
                    job.target.ownOven = true
                    rememberOwnedOven(job, cooker.object)
                end
                return queued, queueReason, failed
            end
            local moved, moveReason = U().transferItemVerified(U().inventory(actor),
                cooker.container, state.resultItem)
            if not moved then return false, moveReason, true end
            state.cooker, state.phase = cooker, "wait_heat"
            job.target.cookPhase = state.heatPurpose == "ingredient"
                and "prep_venison_heating" or "heating"
            return true, "chef_meal_heating"
        end
    end
    if state.phase == "wait_oven" then
        local actionName = state.heatPurpose == "ingredient"
            and "prep_venison_oven_on" or "oven_on"
        local done, reason, terminal = waitAction(state, actionName)
        if done and state.actionResult then state.phase = "heat" end
        return done, reason, terminal
    end
    if state.phase == "wait_heat"
        and not contains(state.cooker.container, state.resultItem) then
        -- Someone took the food out of the cooker (usually the player
        -- helping themselves). Nothing is left to tend: switch off an oven
        -- this cook lit, then close the job. Reporting it as a failure left
        -- the job retrying the missing pot forever while the hot-cook guard
        -- refused every cancel, so the Chef could never leave duty or change
        -- role and the camp could not be abandoned.
        state.mealTaken, state.heatInterrupted, state.burnt = true, nil, nil
        job.target.mealTakenCleanup = true
        job.target.cookPhase = "meal_taken_cleanup"
        state.phase = "switch_off"
    end
    if state.phase == "wait_heat" then
        state.burnt = select(1, call(state.resultItem, "isBurnt")) == true
        local cooked = select(1, call(state.resultItem, "isCooked")) == true
        local heatStopped = state.cooker.fire
            and state.cooker.fire.isLit ~= true
            or not state.cooker.fire
                and select(1, call(state.cooker.container, "isPowered")) ~= true
        if not state.burnt and not cooked and heatStopped then
            -- Take the unfinished food back out. Keeping it in an unpowered
            -- cooker makes both the job and its cancellation permanently wait.
            local at, reason, terminal = approach(actor, state.cooker.object,
                "chef_recover_unheated_meal")
            if not at then return not terminal, reason, terminal end
            local moved, moveReason = U().transferItemVerified(state.cooker.container,
                U().inventory(actor), state.resultItem)
            if not moved then return false, moveReason, true end
            job.target.cookPhase = state.heatPurpose == "ingredient"
                and "prep_venison_needs_heat" or "needs_heat"
            state.heatInterrupted = true
            state.phase = state.ownOven and "switch_off" or "heat"
            return true, "chef_heat_interrupted"
        end
        if not state.burnt and not cooked then return true, "chef_meal_heating" end
        local at, reason, terminal = approach(actor, state.cooker.object,
            "chef_collect_meal")
        if not at then return not terminal, reason, terminal end
        local moved, moveReason = U().transferItemVerified(state.cooker.container,
            U().inventory(actor), state.resultItem)
        if not moved then return false, moveReason, true end
        state.phase = "switch_off"
        job.target.cookPhase = state.heatPurpose == "ingredient"
            and "prep_venison_cooked"
            or (state.burnt and "burnt_recovery" or "ready")
    end
    if state.phase == "switch_off" then
        if state.ownOven and select(1, call(state.ownOven, "Activated")) == true then
            local at, reason, terminal = approach(actor, state.ownOven, "chef_turn_off_oven")
            if not at then return not terminal, reason, terminal end
            local actionName = state.heatPurpose == "ingredient"
                and "prep_venison_oven_off" or "oven_off"
            local queued, queueReason, failed = queueAction(actor, state, job,
                ISToggleStoveAction:new(actor, state.ownOven), actionName)
            if queued then state.phase = "wait_oven_off" end
            return queued, queueReason, failed
        end
        if state.mealTaken then
            job.target.cookPhase = "meal_taken"
            job.target.mealTakenCleanup = nil
            job.target.ownOven = nil
            states[actor] = nil
            return true, "chef_meal_taken", false, true
        end
        if state.heatInterrupted then
            state.heatInterrupted, state.ownOven, state.cooker = nil, nil, nil
            job.target.ownOven = nil
            state.phase = "heat"
            return true, "chef_heat_source_needed"
        end
        if state.burnt then return false, "chef_meal_burnt", true end
        local finished, reason, terminal = finishHeat(state, job)
        if not finished then return false, reason, terminal end
    end
    if state.phase == "wait_oven_off" then
        local actionName = state.heatPurpose == "ingredient"
            and "prep_venison_oven_off" or "oven_off"
        local done, reason, terminal = waitAction(state, actionName)
        if done and state.actionResult then
            if state.mealTaken then
                job.target.cookPhase = "meal_taken"
                job.target.mealTakenCleanup = nil
                job.target.ownOven = nil
                states[actor] = nil
                return true, "chef_meal_taken", false, true
            end
            if state.heatInterrupted then
                state.heatInterrupted, state.ownOven, state.cooker = nil, nil, nil
                job.target.ownOven = nil
                state.phase = "heat"
                return true, "chef_heat_source_needed"
            end
            if state.burnt then return false, "chef_meal_burnt", true end
            local finished, finishReason, failed = finishHeat(state, job)
            if not finished then return false, finishReason, failed end
        end
        return done, reason, terminal
    end
    if state.phase == "portion" then
        local at, surface, terminal = approachCraftSurface(actor, scan)
        if not at then return not terminal, surface, terminal end
        state.craftSurface = surface
        if not contains(U().inventory(actor), state.resultItem)
            or not state.bowls or #state.bowls ~= 2
            or not contains(U().inventory(actor), state.bowls[1])
            or not contains(U().inventory(actor), state.bowls[2]) then
            return false, "chef_portion_inputs_missing", true
        end
        local queued, reason, terminal = queuePotPortions(actor, state, job)
        if queued then state.phase = "wait_portion" end
        return queued, reason, terminal
    end
    if state.phase == "wait_portion" then
        local done, reason, terminal = waitAction(state, "portion")
        if not done or not state.actionResult then return done, reason, terminal end
        state.portionIndex, state.resultItem = 1, state.portions[1]
        state.phase = "deposit"
        job.target.cookPhase = "portions_ready"
    end
    if state.phase == "return_pot" then
        local handled, reason, terminal, completed = returnPot(actor,
            state, job, scan)
        if completed then
            states[actor] = nil
            return true, "chef_meal_stored", false, true
        end
        return handled, reason, terminal
    end
    if state.phase == "deposit" then
        local handled, reason, terminal, completed = deposit(actor, state, job, scan)
        if completed then
            if state.portions and state.portionIndex
                < (state.portionCount or #state.portions) then
                state.portionIndex = state.portionIndex + 1
                state.resultItem = state.portions[state.portionIndex]
                job.target.portionIndex = state.portionIndex
                job.target.cookPhase = "portion_1_delivered"
                return true, reason
            end
            if state.portions then
                state.phase = "return_pot"
                job.target.cookPhase = "portions_delivered"
                return true, reason
            end
            states[actor] = nil
            return true, reason, false, true
        end
        return handled, reason, terminal
    end
    return true, "chef_working"
end

local function returnContainer(row)
    if not row or row.carried or not row.container then return nil end
    if row.storage then
        if SC.BaseLife.storage(row.storage.id) ~= row.storage
            or SC.BaseLife.resolveContainer(row.storage) ~= row.container then
            return nil
        end
    elseif select(1, call(row.object, "getContainer")) ~= row.container then
        return nil
    end
    return row.container
end

local function returnChefSupplies(actor, state)
    local inventory = U().inventory(actor)
    if not inventory then return false, "chef_inventory_missing" end
    local borrowed = {}
    for _, entry in ipairs(state.borrowed or {}) do
        borrowed[entry.item] = entry.source
    end
    local artifacts, seen = {}, {}
    local jobId = state.jobId
    local function personalOutput(item)
        local data = select(1, call(item, "getModData"))
        if type(data) ~= "table" then return false end
        if data.SC_ChefPotJobId == jobId then
            return state.baseRow and state.baseRow.carried == true
        end
        if data.SC_ChefPrepJobId ~= jobId then return false end
        local row = data.SC_ChefPrepKind == "bread" and state.prepBreadRow
            or data.SC_ChefPrepKind == "fish" and state.prepFishRow
            or data.SC_ChefPrepKind == "venison" and state.rawVenisonRow
            or data.SC_ChefPrepKind == "pasta" and state.baseRow
        return row and row.carried == true
    end
    local function add(item)
        if item and contains(inventory, item) and not seen[item]
            and not personalOutput(item) then
            seen[item] = true
            artifacts[#artifacts + 1] = item
        end
    end
    for _, entry in ipairs(state.borrowed or {}) do add(entry.item) end
    for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
        local data = select(1, call(item, "getModData"))
        if type(data) == "table" and (data.SC_ChefJobId == jobId
            or data.SC_ChefPrepJobId == jobId
            or data.SC_ChefPotJobId == jobId) then add(item) end
    end
    add(state.resultItem)
    add(state.emptyPot)
    for _, item in ipairs(state.portions or {}) do add(item) end
    local fridge
    if state.scan then fridge = storageDestinations(state.scan)[1] end
    for _, item in ipairs(artifacts) do
        local destination = returnContainer(borrowed[item])
        if borrowed[item] and not destination then
            return false, "chef_return_source_missing"
        end
        if not destination then
            local data = select(1, call(item, "getModData"))
            if type(data) == "table" and data.SC_ChefPotJobId == jobId then
                destination = returnContainer(state.baseRow)
            elseif Chef.isPrepared(item) and fridge then
                destination = fridge.container
            end
            destination = destination or returnContainer(state.baseRow)
                or returnContainer(state.prepBreadRow)
                or returnContainer(state.prepFishRow)
                or returnContainer(state.ingredientRow)
        end
        if not destination then return false, "chef_return_storage_missing" end
        local moved, moveReason = U().transferItemVerified(inventory,
            destination, item)
        if moved ~= true or not contains(destination, item) then
            return false, moveReason or "chef_supply_return_failed"
        end
    end
    return true
end

function Chef.mustTendHeat(actor, job)
    if not job or job.type ~= "cook" then return false end
    local state = states[actor]
    if state and state.jobId == job.id then
        return state.phase == "wait_heat" and state.cooker ~= nil
            and contains(state.cooker.container, state.resultItem)
    end
    -- After a reload, receipt reconstruction must run before night shelter
    -- routing can move the cook away from a loaded hot vessel.
    local phase = job.target and job.target.cookPhase
    return phase == "heating" or phase == "prep_venison_heating"
end

function Chef.canCancelActor(actor, reason)
    local state = states[actor]
    if not state then return true end
    if state.action and state.actionResult == nil and state.actionFailed == nil then
        -- The native queue does not expose a safe action-specific cancellation
        -- for every Build 42 action. Leave its job owned until outcome known.
        return false, "chef_native_action_pending"
    end
    if state.phase == "wait_heat" or (state.ownOven
        and select(1, call(state.ownOven, "Activated")) == true) then
        return false, "chef_hot_cook_in_progress"
    end
    if state.nativeCommitted and state.actionFailed
        and state.actionResult == nil then
        return false, "chef_native_outcome_unknown"
    end
    if state.nativeCommitted and reason ~= "chef_job_cancelled" then
        return false, "chef_job_cancel_required"
    end
    if state.recovered then return false, "chef_return_receipt_recovery_required" end
    return true
end

function Chef.cancelActor(actor, reason)
    local allowed, blockReason = Chef.canCancelActor(actor, reason)
    if allowed ~= true then return false, blockReason end
    local state = states[actor]
    if not state then return true end
    local returned, returnReason = returnChefSupplies(actor, state)
    if returned ~= true then return false, returnReason end
    if reason ~= "chef_job_cancelled" and state.job then
        local manual = state.job.target and state.job.target.manual
        state.job.target = { manual = manual == true }
    end
    states[actor] = nil
    return true
end

function Chef.canCancelJob(job, ownerId)
    if not job or job.type ~= "cook" then return false, "not_cook_job" end
    if job.target and (job.target.cookPhase == "heating"
        or job.target.cookPhase == "prep_venison_heating") then
        return false, "chef_hot_cook_recovery_pending"
    end
    local actorId = ownerId or job.assignedId
    local actor = actorId and U().resolveActor(actorId) or nil
    local state = actor and states[actor] or nil
    if state and state.jobId == job.id then
        return Chef.canCancelActor(actor, "chef_job_cancelled")
    end
    if job.target and job.target.cookPhase ~= nil
        and job.target.cookPhase ~= "selected" then
        return false, "chef_return_receipt_recovery_required"
    end
    return true
end

function Chef.cancelJob(job, ownerId)
    local allowed, blockReason = Chef.canCancelJob(job, ownerId)
    if allowed ~= true then return false, blockReason end
    local actorId = ownerId or job.assignedId
    local actor = actorId and U().resolveActor(actorId) or nil
    local state = actor and states[actor] or nil
    if state and state.jobId == job.id then
        return Chef.cancelActor(actor, "chef_job_cancelled")
    end
    return true
end

function Chef.canLeaveDuty(actorId)
    local base = SC.BaseLife and SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.type == "cook" and job.assignedId == actorId then
            local allowed, reason = Chef.canCancelJob(job, job.reservedBy)
            if allowed ~= true then return false, reason end
        end
    end
    return true
end

function Chef.reconcileExpiredJob(job)
    if job and job.type == "cook" then return false, "chef_receipt_recovery_required" end
    return true
end

function Chef.reset(actor)
    if actor then states[actor], autoChecks[actor] = nil, nil
    else
        states = setmetatable({}, { __mode = "k" })
        scans = setmetatable({}, { __mode = "k" })
        autoChecks = setmetatable({}, { __mode = "k" })
    end
end

return Chef
