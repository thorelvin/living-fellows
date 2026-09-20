-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCGatherWork")
    pcall(require, "SCFarmWork")
    pcall(require, "SCNativeList")
    pcall(require, "BuildingObjects/TimedActions/ISBuildAction")
    pcall(require, "TimedActions/ISTimedActionQueue")
end

-- Build 42 defines ISBuildIsoEntity in the vanilla server script set and
-- publishes the global into single-player before world actions run. A client
-- require cannot resolve that server-owned path and only produces a warning;
-- recipeInfo() below already fails closed until the global is available.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BaseWork = SC.BaseWork or {}
local BaseWork = SC.BaseWork

local states = setmetatable({}, { __mode = "k" })
local maintenanceCursor = 1
local auditPhase = 0
local nextRoutineJobAt = 0
local buildRecipeAliases = {
    wall_frame = { "ES_Wood_Wallframe" },
    wall = { "ES_Wood_WallLvl1", "ES_Wood_WallLvl2", "ES_Wood_WallLvl3" },
    floor = { "ES_WoodFloorLvl1", "ES_WoodFloorLvl2", "ES_WoodFloorLvl3" },
    door_frame = { "ES_Wood_DoorframeLvl1", "ES_Wood_DoorframeLvl2", "ES_Wood_DoorframeLvl3" },
    door = { "ES_Wood_DoorLvl1", "ES_Wood_DoorLvl2", "ES_Wood_DoorLvl3" },
    -- Burial markers are ordinary Build 42 buildable entities.
    grave_marker = { "ES_WoodCross", "WoodCross", "ES_RuggedCross", "RuggedCross" },
}

local function U()
    return SC.GameplayUtil
end

local function now()
    return U().nowMs()
end

local function invoke(object, name, ...)
    return U().call(object, name, ...)
end

local listSize = SC.NativeList.size
local listGet = SC.NativeList.get

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = { phase = "idle", nextRoutineAt = 0, patrolIndex = 0 }
        states[actor] = state
    end
    return state
end

local function actorId(actor)
    return U().idOf(actor)
end

local function targetSquare(job)
    return type(job) == "table" and type(job.target) == "table"
        and U().loadedSquare(job.target) or nil
end

local function freeAdjacent(square, actor)
    local x, y, z = U().position(square)
    if x == nil then return nil end
    local best, bestDistance
    for _, offset in ipairs({
        { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }) do
        local candidate = U().gridSquare(x + offset[1], y + offset[2], z)
        if candidate and U().isSquareFree(candidate) then
            local distance = U().distance(actor, candidate)
            if bestDistance == nil or distance < bestDistance then
                best, bestDistance = candidate, distance
            end
        end
    end
    return best
end

local function resolveRecipeName(info)
    local script, ok = invoke(info, "getScript")
    if not ok or not script then return nil end
    local name, nameOk = invoke(script, "getName")
    return nameOk and tostring(name) or nil
end

function BaseWork.recipeInfo(recipeId)
    if type(ISBuildIsoEntity) ~= "table"
        or type(ISBuildIsoEntity.GetAllBuildableEntities) ~= "function" then return nil end
    local ok, infos = pcall(ISBuildIsoEntity.GetAllBuildableEntities)
    if not ok or infos == nil then return nil end
    for index = 1, #infos do
        local info = infos[index]
        if resolveRecipeName(info) == recipeId then return info end
    end
    return nil
end

function BaseWork.recipeForKind(kind)
    local candidates = buildRecipeAliases[kind]
    if not candidates then return nil end
    for _, recipeId in ipairs(candidates) do
        if BaseWork.recipeInfo(recipeId) then return recipeId end
    end
    return candidates[1]
end

local function buildProtected(actor, item)
    return SC.PersonalItems and type(SC.PersonalItems.isProtected) == "function"
        and SC.PersonalItems.isProtected(item, actor, "base_build") == true
end

-- What the worker really carries for this type, bags included, and where the
-- nested ones are. A hammer in a backpack is carried, not missing.
local function carriedSupplies(actor, itemType)
    local count, nested = 0, {}
    local inspect = function(item, depth)
        if U().itemType(item) == itemType and not buildProtected(actor, item) then
            count = count + 1
            if (depth or 0) > 0 then nested[#nested + 1] = item end
        end
    end
    if SC.PersonalItems and type(SC.PersonalItems.walkActorInventory) == "function" then
        SC.PersonalItems.walkActorInventory(actor, inspect)
    else
        for _, item in ipairs(U().inventoryItems(U().inventory(actor), 256)) do inspect(item, 0) end
    end
    return count, nested
end

local function inventoryCount(actor, itemType)
    return (carriedSupplies(actor, itemType))
end
BaseWork._carriedSuppliesForTests = carriedSupplies

-- The native build action reads the worker's main inventory, so a required
-- item sitting in a bag is moved to the root first, through the same verified
-- transfer used everywhere else.
local function stageCarriedSupply(actor, itemType, needed)
    local rootCount = 0
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 256)) do
        if U().itemType(item) == itemType and not buildProtected(actor, item) then
            rootCount = rootCount + 1
        end
    end
    if rootCount >= needed then return true, "supply_at_hand" end
    local _, nested = carriedSupplies(actor, itemType)
    for _, item in ipairs(nested) do
        if rootCount >= needed then break end
        local source = select(1, U().call(item, "getContainer"))
        if source ~= nil then
            local moved, reason
            if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
                moved, reason = SC.WorkTransport.transferVerified(source,
                    U().inventory(actor), item, actor)
            else
                moved, reason = U().transferItemVerified(source, U().inventory(actor), item)
            end
            if moved == true then rootCount = rootCount + 1
            elseif reason ~= nil then return false, reason end
        end
    end
    if rootCount >= needed then return true, "supply_staged" end
    return false, "carried_supply_unreachable"
end
BaseWork._stageCarriedSupplyForTests = stageCarriedSupply

local function possibleTypes(input)
    local result = {}
    local values, ok = invoke(input, "getPossibleInputItems")
    if not ok then return result end
    for index = 0, listSize(values) - 1 do
        local scriptItem = listGet(values, index)
        local fullType, fullOk = invoke(scriptItem, "getFullName")
        if fullOk and type(fullType) == "string" then result[#result + 1] = fullType end
    end
    return result
end

local function recipeRequirements(info)
    local recipeInfo, recipeInfoOk = invoke(info, "getRecipe")
    local recipe, recipeOk
    if recipeInfoOk then recipe, recipeOk = invoke(recipeInfo, "getCraftRecipe") end
    if not recipeOk or not recipe then return nil, "build_recipe_unavailable" end
    local inputs, inputsOk = invoke(recipe, "getInputs")
    if not inputsOk then return nil, "build_inputs_unavailable" end
    local result = {}
    for index = 0, listSize(inputs) - 1 do
        local input = listGet(inputs, index)
        local itemCount, countOk = invoke(input, "isItemCount")
        local required
        if countOk and itemCount == true then
            required = select(1, invoke(input, "getIntAmount"))
        else
            required = select(1, invoke(input, "getAmount"))
        end
        local keep = select(1, invoke(input, "isKeep")) == true
        local tool = select(1, invoke(input, "isTool")) == true
        local types = possibleTypes(input)
        if #types > 0 then
            result[#result + 1] = {
                types = types, count = math.max(1, math.ceil(tonumber(required) or 1)),
                keep = keep, tool = tool,
            }
        end
    end
    return result, recipe
end

local function sourceCategories(requirement)
    if requirement.tool then return { "tools", "construction", "general" } end
    return { "construction", "crafting", "general" }
end

local function findSource(actor, requirement)
    -- Craft inputs are alternatives (for example any usable hammer), so an
    -- absent first type must not reject a later type already carried.
    for _, itemType in ipairs(requirement.types) do
        local have = inventoryCount(actor, itemType)
        if have >= requirement.count then return false end
    end
    for _, itemType in ipairs(requirement.types) do
        for _, category in ipairs(sourceCategories(requirement)) do
            for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
                if SC.BaseLife.availableCount(storage, itemType) > 0 then
                    local container = SC.BaseLife.resolveContainer(storage)
                    if container then
                        for _, item in ipairs(U().inventoryItems(container,
                            U().config("campStorageItemBudget") or 80)) do
                            if U().itemType(item) == itemType
                                and not (SC.PersonalItems and SC.PersonalItems.isProtected
                                    and SC.PersonalItems.isProtected(item, actor, "base_build")) then
                                return storage, container, item, itemType
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, requirement.types[1]
end

local function withdrawalAllowed(storage, expectedContainer, item)
    if type(storage) ~= "table" or storage.withdrawals == false then
        return false, "base_storage_withdrawals_disabled"
    end
    local currentContainer = SC.BaseLife.resolveContainer(storage)
    if currentContainer == nil then return false, "base_storage_unloaded" end
    if currentContainer ~= expectedContainer then return false, "base_storage_changed" end
    if not U().inventoryContains(currentContainer, item) then
        return false, "base_supply_moved"
    end
    local itemType = U().itemType(item)
    if SC.BaseLife.availableCount(storage, itemType) <= 0 then
        return false, "base_supply_reserved"
    end
    return true
end

local function transferFromStorage(actor, state, storage, container, item)
    local object = SC.BaseLife.resolveObject(storage)
    if not object then return false, "base_storage_unloaded" end
    if U().distance(actor, object) > 1.5 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local targets = SC.Navigation.interactionTargets(actor, object)
        -- Only (handled, reason): a third navigation value would be read as
        -- the terminal flag and block the job on every approach.
        local approached, approachReason = SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
        return approached == true, approachReason
    end
    if state.visualAt ~= nil then
        local status = nil
        if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local ok, value = pcall(SC.NativeActions.visualStatus,
                actor, "loot_container")
            if ok then status = value end
        end
        if status == "active" then return true, "base_storage_looting" end
        if status == "completed" then
            if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
                pcall(SC.NativeActions.clearVisual, actor)
            end
            state.visualAt = nil
        elseif status ~= nil then
            state.visualAt = nil
            return false, "base_storage_animation_" .. tostring(status)
        else
            state.visualAt = nil
        end
    else
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, actor, "base_storage_interaction")
        end
        if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
            pcall(SC.NativeActions.stopDirect, actor)
        else
            U().stop(actor)
        end
        local accepted = U().move(actor, "walk", {
            action = "loot_container", container = container, item = item, baseStorage = true,
        })
        if accepted ~= true then return false, "base_storage_action_rejected" end
        local status = nil
        if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local ok, value = pcall(SC.NativeActions.visualStatus,
                actor, "loot_container")
            if ok then status = value end
        end
        if status == "active" then
            state.visualAt = now()
            return true, "base_storage_looting"
        elseif status == "completed" then
            if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
                pcall(SC.NativeActions.clearVisual, actor)
            end
        elseif status ~= nil then
            return false, "base_storage_animation_" .. tostring(status)
        end
    end
    -- Selection is advisory. Re-read the registered source, its withdrawal
    -- setting and its live reserve immediately before the authoritative move.
    local allowed, withdrawalReason = withdrawalAllowed(storage, container, item)
    if not allowed then return false, withdrawalReason end
    local transferred, reason
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        transferred, reason = SC.WorkTransport.transferVerified(
            container, U().inventory(actor), item, actor)
    else
        transferred, reason = U().transferItemVerified(container, U().inventory(actor), item)
    end
    return transferred == true, transferred and "base_supply_taken"
        or reason or "base_supply_transfer_failed"
end

-- Return an exact borrowed supply to the exact marked container it came from.
-- This mirrors withdrawal: the worker approaches the storage, visibly uses it,
-- revalidates the registration at commit time, and verifies the identity move.
local function transferToStorage(actor, state, storage, container, item)
    if U().inventoryContains(container, item) then return true, "base_supply_returned" end
    if type(storage) ~= "table" then return false, "base_storage_invalid" end
    local object = SC.BaseLife.resolveObject(storage)
    local currentContainer = SC.BaseLife.resolveContainer(storage)
    if not object or not currentContainer then return false, "base_storage_unloaded" end
    if currentContainer ~= container then return false, "base_storage_changed" end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, item) then
        return false, "borrowed_supply_missing"
    end
    if U().distance(actor, object) > 1.5 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local targets = SC.Navigation.interactionTargets(actor, object)
        local approached, approachReason = SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
        return approached == true, approachReason
    end
    if state.visualAt ~= nil then
        local status
        if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local ok, value = pcall(SC.NativeActions.visualStatus, actor, "loot_container")
            if ok then status = value end
        end
        if status == "active" then return true, "base_storage_looting" end
        if status == "completed" and SC.NativeActions
            and type(SC.NativeActions.clearVisual) == "function" then
            pcall(SC.NativeActions.clearVisual, actor)
        elseif status ~= nil then
            state.visualAt = nil
            return false, "base_storage_animation_" .. tostring(status)
        end
        state.visualAt = nil
    else
        if SC.Navigation and type(SC.Navigation.cancel) == "function" then
            pcall(SC.Navigation.cancel, actor, "base_storage_interaction")
        end
        if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
            pcall(SC.NativeActions.stopDirect, actor)
        else
            U().stop(actor)
        end
        local accepted = U().move(actor, "walk", {
            action = "loot_container", container = container, item = item, baseStorage = true,
        })
        if accepted ~= true then return false, "base_storage_action_rejected" end
        local status
        if SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local ok, value = pcall(SC.NativeActions.visualStatus, actor, "loot_container")
            if ok then status = value end
        end
        if status == "active" then
            state.visualAt = now()
            return true, "base_storage_looting"
        elseif status == "completed" and SC.NativeActions
            and type(SC.NativeActions.clearVisual) == "function" then
            pcall(SC.NativeActions.clearVisual, actor)
        elseif status ~= nil then
            return false, "base_storage_animation_" .. tostring(status)
        end
    end
    local room, roomReason = true, nil
    if SC.WorkTransport and type(SC.WorkTransport.hasRoom) == "function" then
        room, roomReason = SC.WorkTransport.hasRoom(container, actor, item)
    else
        local allowed, called = U().call(container, "hasRoomFor", actor, item)
        if called then room = allowed == true end
    end
    if room ~= true then return false, roomReason or "destination_full" end
    local moved, reason
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        moved, reason = SC.WorkTransport.transferVerified(inventory, container, item, actor)
    else
        moved, reason = U().transferItemVerified(inventory, container, item)
    end
    return moved == true, moved and "base_supply_returned"
        or reason or "base_supply_return_failed"
end

local function prepareBuild(actor, state, job, info)
    local requirements, recipeOrReason = recipeRequirements(info)
    if not requirements then return false, recipeOrReason end
    for _, requirement in ipairs(requirements) do
        local storage, container, item, missingType = findSource(actor, requirement)
        if storage == nil then return false, "missing_build_supply:" .. tostring(missingType) end
        if storage ~= false then
            return transferFromStorage(actor, state, storage, container, item)
        end
        -- Carried already: make sure it is somewhere the build action can use.
        for _, carriedType in ipairs(requirement.types) do
            if carriedSupplies(actor, carriedType) >= requirement.count then
                local staged, stagedReason = stageCarriedSupply(actor, carriedType, requirement.count)
                if not staged then return false, stagedReason or "carried_supply_unreachable" end
                break
            end
        end
    end
    state.requirementsReady = true
    return true, "build_supplies_ready"
end

local function actionActive(actor, action)
    if action == nil or type(ISTimedActionQueue) ~= "table" then return false end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" then return false end
    if queue.current == action then return true end
    for _, queued in ipairs(type(queue.queue) == "table" and queue.queue or {}) do
        if queued == action then return true end
    end
    return false
end

local function squareObjectCount(square)
    local count = 0
    U().squareObjects(square, function() count = count + 1 end, 128)
    return count
end

local SCCompanionBuildAction = ISBuildAction:derive("SCCompanionBuildAction")

function SCCompanionBuildAction:stop()
    self.scStopped = true
    if type(ISBuildAction.stop) == "function" then ISBuildAction.stop(self) end
end

function SCCompanionBuildAction:perform()
    -- Build 42's entity builder calls getSpecificPlayer(self.player) while
    -- assigning construction health.  Companions deliberately do not occupy a
    -- local-player slot, so bridge that lookup only for this synchronous create.
    local original = getSpecificPlayer
    local companion = self.character
    getSpecificPlayer = function(index)
        if companion and tonumber(index) == tonumber(companion:getPlayerNum()) then return companion end
        return original and original(index) or nil
    end
    local ok, reason = pcall(ISBuildAction.perform, self)
    getSpecificPlayer = original
    if not ok then error(reason) end
    -- A real completion receipt. Queue absence alone never proves a build.
    self.scCompleted = true
end

-- Did the requested construction actually appear? true, false, or nil when
-- the expected sprite cannot be read and the question stays open.
local function squareHasSprite(square, spriteName)
    if type(spriteName) ~= "string" or spriteName == "" then return nil end
    local found, readable = false, false
    U().squareObjects(square, function(object)
        local sprite = select(1, invoke(object, "getSprite"))
        local name = sprite and select(1, invoke(sprite, "getName")) or nil
        if type(name) == "string" then
            readable = true
            if name == spriteName then found = true end
        end
    end, 128)
    if found then return true end
    -- `readable and false or nil` would always be nil; be explicit.
    if readable then return false end
    return nil
end

-- "complete", "missing" or "cancelled". A cancelled action, an unrelated
-- object appearing, or placement turning invalid are never a finished build.
local function buildOutcome(state, square)
    local completed = type(state.action) == "table" and state.action.scCompleted == true
    if not completed then return "cancelled" end
    local built = squareHasSprite(square, state.buildSpriteName)
    if built == true then return "complete" end
    if built == false then return "missing" end
    -- Sprite identity unreadable: fall back to the old evidence, but only
    -- together with a real completion receipt.
    if squareObjectCount(square) > (state.initialObjectCount or 0) then return "complete" end
    return "missing"
end
BaseWork._buildOutcomeForTests = buildOutcome

local function startBuildAction(actor, state, job, info, square)
    local entity = ISBuildIsoEntity:new(actor, info, tonumber(job.face) or 1, { U().inventory(actor) })
    if not entity then return false, "build_entity_creation_failed" end
    entity.nSprite = tonumber(job.face) or 1
    local sprite = entity:getSprite()
    if sprite == nil or entity:isValid(square) ~= true then return false, "build_target_invalid" end
    local recipeInfo = select(1, invoke(info, "getRecipe"))
    local recipe = recipeInfo and select(1, invoke(recipeInfo, "getCraftRecipe")) or nil
    local duration = recipe and select(1, invoke(recipe, "getTime")) or 200
    duration = math.max(1, tonumber(duration) or 200)
    local action = SCCompanionBuildAction:new(actor, entity,
        select(1, U().position(square)), select(2, U().position(square)),
        select(3, U().position(square)), entity.north, sprite, duration)
    if not action then return false, "build_action_creation_failed" end
    if entity.buildPanelLogic and type(action.setOnComplete) == "function" then
        action:setOnComplete(entity.onActionComplete, entity)
        action:setOnCancel(entity.onActionComplete, entity)
        entity.buildPanelLogic:startCraftAction(action)
    end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil
        or (type(queue.queue) == "table" and #queue.queue > 0) then
        if entity.buildPanelLogic then entity.buildPanelLogic:stopCraftAction() end
        return false, "actor_has_native_action"
    end
    local queued, reason = pcall(ISTimedActionQueue.add, action)
    if not queued or not actionActive(actor, action) then
        if entity.buildPanelLogic then entity.buildPanelLogic:stopCraftAction() end
        return false, queued and "build_action_not_retained" or tostring(reason)
    end
    state.action, state.entity = action, entity
    state.buildSpriteName = type(sprite) == "string" and sprite or nil
    state.initialObjectCount, state.startedAt = squareObjectCount(square), now()
    state.phase = "building"
    SC.BaseLife.touchJob(job.id, actorId(actor), "active")
    return true, "build_started"
end

local function updateBuild(actor, state, job)
    local square = targetSquare(job)
    if not square then return false, "build_target_unloaded", true end
    local info = BaseWork.recipeInfo(job.recipeId)
    if not info then return false, "build_recipe_missing", true end
    if state.phase ~= "building" then
        local prepared, reason = prepareBuild(actor, state, job, info)
        if not prepared or reason ~= "build_supplies_ready" then return prepared, reason end
        local approaches = SC.Navigation and SC.Navigation.interactionTargets
            and SC.Navigation.interactionTargets(actor, square) or {}
        local adjacent = approaches[1] or freeAdjacent(square, actor)
        if not adjacent then return false, "build_approach_missing", true end
        if #approaches == 0 then approaches[1] = adjacent end
        if U().distance(actor, adjacent) > 0.8 then
            if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
                return false, "navigation_unavailable", true
            end
            local approached, approachReason = SC.Navigation.requestAny(actor, approaches, "walk", {
                action = "move_to_base_build", targetSquare = square,
                arrivalDistance = 0.8,
            })
            return approached == true, approachReason
        end
        return startBuildAction(actor, state, job, info, square)
    end
    if actionActive(actor, state.action) then
        SC.BaseLife.touchJob(job.id, actorId(actor), "active")
        return true, "building"
    end
    local outcome = buildOutcome(state, square)
    if outcome == "complete" then
        SC.BaseLife.completeJob(job.id, actorId(actor), "built")
        state.phase, state.action, state.entity = "idle", nil, nil
        state.buildSpriteName = nil
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "base_build", "built", { kind = "long" })
        end
        return true, "build_complete"
    end
    state.phase, state.action, state.entity = "idle", nil, nil
    state.buildSpriteName = nil
    -- The job stays unfinished, so a later attempt can still build it.
    return false, outcome == "missing" and "build_result_missing" or "build_action_cancelled", true
end

local function classifyItem(item)
    local itemType = string.lower(U().itemType(item))
    local category = select(1, invoke(item, "getCategory"))
    category = string.lower(tostring(category or ""))
    if SC.FarmWork and type(SC.FarmWork.isFarmingSupply) == "function"
        and SC.FarmWork.isFarmingSupply(item) == true then return "farming" end
    if category == "food" then return "food" end
    if category == "literature" then return "literature" end
    if string.find(itemType, "water", 1, true) or string.find(itemType, "bottle", 1, true) then return "water" end
    if string.find(itemType, "bandage", 1, true) or string.find(itemType, "rippedsheet", 1, true)
        or string.find(itemType, "disinfect", 1, true) then return "medical" end
    if category == "weapon" then return "weapons" end
    if string.find(itemType, "ammo", 1, true) or string.find(itemType, "bullets", 1, true)
        or string.find(itemType, "round", 1, true) then return "ammunition" end
    if U().itemHasTag(item, "Hammer") or string.find(itemType, "saw", 1, true)
        or string.find(itemType, "screwdriver", 1, true) then return "tools" end
    if string.find(itemType, "plank", 1, true) or string.find(itemType, "nails", 1, true)
        or string.find(itemType, "lumber", 1, true) then return "construction" end
    return "crafting"
end

local function destinationHasRoom(container, actor, item)
    if SC.WorkTransport and type(SC.WorkTransport.hasRoom) == "function" then
        local ok, room = pcall(SC.WorkTransport.hasRoom, container, actor, item)
        if ok then return room ~= false end
    end
    local room, roomOk = U().call(container, "hasRoomFor", actor, item)
    if roomOk then return room ~= false end
    return true
end

-- Every registered destination that can actually take this exact item now.
-- A full store is not a destination; choosing one would strand the cargo.
local function destinationsFor(job, item, actor, sourceId)
    local category = type(job.target) == "table" and job.target.destinationCategory
        or classifyItem(item)
    local rows = {}
    for _, destination in ipairs(SC.BaseLife.storageRows(category, false)) do
        if destination.id ~= sourceId and destination.deposits ~= false then
            local container = SC.BaseLife.resolveContainer(destination)
            if container and destinationHasRoom(container, actor, item) then
                rows[#rows + 1] = { destination = destination, container = container }
            end
        end
    end
    return rows
end

local function findTransfer(job, actor)
    local sourceCategory = job.type == "sort" and "general"
        or (type(job.target) == "table" and job.target.sourceCategory) or "general"
    for _, source in ipairs(SC.BaseLife.storageRows(sourceCategory, true)) do
        local container = SC.BaseLife.resolveContainer(source)
        if container then
            for _, item in ipairs(U().inventoryItems(container, 80)) do
                if SC.BaseLife.availableCount(source, U().itemType(item)) > 0
                    and not (SC.PersonalItems and SC.PersonalItems.isProtected
                    and SC.PersonalItems.isProtected(item, actor, "base_haul")) then
                    local rows = destinationsFor(job, item, actor, source.id)
                    if #rows > 0 then
                        return source, container, rows[1].destination, rows[1].container, item
                    end
                end
            end
        end
    end
    return nil
end

-- Put carried cargo back where it came from, so a blocked job never leaves a
-- worker quietly holding base stock.
local function returnCargo(actor, cargo)
    if type(cargo) ~= "table" or cargo.item == nil then return true end
    if not U().inventoryContains(U().inventory(actor), cargo.item) then return true end
    local container = cargo.source and SC.BaseLife.resolveContainer(cargo.source)
        or cargo.sourceContainer
    if container == nil then return false end
    local moved
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        moved = SC.WorkTransport.transferVerified(U().inventory(actor), container, cargo.item, actor)
    else
        moved = U().transferItemVerified(U().inventory(actor), container, cargo.item)
    end
    return moved == true
end

local function updateTransfer(actor, state, job)
    -- Cargo from an earlier attempt is still owned by this worker: deliver
    -- that before withdrawing anything else.
    if state.transfer == nil and type(state.cargo) == "table" then
        local cargo = state.cargo
        if U().inventoryContains(U().inventory(actor), cargo.item) then
            local rows = destinationsFor(job, cargo.item, actor, cargo.sourceId)
            if #rows > 0 then
                state.transfer = {
                    source = cargo.source, sourceContainer = cargo.sourceContainer,
                    destination = rows[1].destination, destinationContainer = rows[1].container,
                    item = cargo.item, phase = "deposit",
                }
            else
                local returned = returnCargo(actor, cargo)
                if returned then state.cargo = nil end
                return false, returned and "haul_cargo_returned" or "haul_destinations_full", true
            end
        else
            state.cargo = nil
        end
    end
    if state.transfer == nil then
        local source, sourceContainer, destination, destinationContainer, item = findTransfer(job, actor)
        if not source then return false, "no_sortable_supply", true end
        state.transfer = {
            source = source, sourceContainer = sourceContainer, destination = destination,
            destinationContainer = destinationContainer, item = item, phase = "take",
        }
    end
    local transfer = state.transfer
    if transfer.phase == "take" then
        if not U().inventoryContains(U().inventory(actor), transfer.item) then
            local ok, reason = transferFromStorage(actor, state, transfer.source,
                transfer.sourceContainer, transfer.item)
            if not ok then
                if reason == "base_supply_reserved"
                    or reason == "base_storage_withdrawals_disabled"
                    or reason == "base_storage_changed"
                    or reason == "base_supply_moved" then
                    state.transfer = nil
                    return false, reason, true
                end
                return false, reason
            end
            if reason ~= "base_supply_taken" then return true, reason end
        end
        transfer.phase = "deposit"
        -- An exact receipt for what this worker now carries, kept until the
        -- item is delivered or verifiably returned.
        state.cargo = {
            item = transfer.item, source = transfer.source,
            sourceContainer = transfer.sourceContainer,
            sourceId = type(transfer.source) == "table" and transfer.source.id or nil,
        }
    end
    local object = SC.BaseLife.resolveObject(transfer.destination)
    if not object then return false, "destination_storage_unloaded", true end
    if U().distance(actor, object) > 1.5 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable", true
        end
        local targets = SC.Navigation.interactionTargets(actor, object)
        local approached, approachReason = SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
        return approached == true, approachReason
    end
    if not U().inventoryContains(U().inventory(actor), transfer.item) then
        return false, "hauled_item_missing", true
    end
    local moved, moveReason
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        moved, moveReason = SC.WorkTransport.transferVerified(U().inventory(actor),
            transfer.destinationContainer, transfer.item, actor)
    else
        moved, moveReason = U().transferItem(
            U().inventory(actor), transfer.destinationContainer, transfer.item)
    end
    if not moved then
        -- A refused deposit is not the end of the cargo. Try another store
        -- that has room, and only then put the item back where it came from.
        local rows = destinationsFor(job, transfer.item, actor,
            type(transfer.source) == "table" and transfer.source.id or nil)
        for _, row in ipairs(rows) do
            if row.container ~= transfer.destinationContainer then
                transfer.destination, transfer.destinationContainer = row.destination, row.container
                return true, "haul_destination_changed"
            end
        end
        local returned = returnCargo(actor, state.cargo)
        if returned then
            state.cargo, state.transfer = nil, nil
            return false, "haul_cargo_returned", true
        end
        return false, moveReason or "base_deposit_failed", true
    end
    state.cargo = nil
    SC.BaseLife.completeJob(job.id, actorId(actor), "hauled")
    state.transfer, state.phase = nil, "idle"
    if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
        SC.NativeActions.noteResult(actor, "base_transfer", "hauled")
    end
    return true, "base_transfer_complete"
end

local function queueBarricade(actor, job)
    local object = type(job.target) == "table" and SC.BaseLife.resolveObject(job.target) or nil
    if not object then return false, "barricade_target_unloaded", true end
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "commands_unavailable", true
    end
    local ok, reason = SC.Commands.issue(actorId(actor), "barricade", {
        object = object, baseJobId = job.id,
    })
    return ok == true, reason, ok ~= true
end

local function updateChore(actor, state, job, player, runtime)
    if job.type == "replace_bandage" then
        local ok, reason = false, "medical_unavailable"
        if SC.Medical and type(SC.Medical.replaceDirtyBandage) == "function" then
            ok, reason = SC.Medical.replaceDirtyBandage(actor)
        end
        if ok and reason == "bandaged" then
            SC.BaseLife.completeJob(job.id, actorId(actor), reason)
        end
        local activeTreatment = SC.Medical and type(SC.Medical.peek) == "function"
            and SC.Medical.peek(actor) or nil
        local terminalFailure = ok ~= true and activeTreatment == nil
        return ok == true, reason or "medical_unavailable", terminalFailure
    end
    if state.choreKind ~= job.type then
        state.choreKind, state.choreStartedAt = job.type, now()
    end
    local before = SC.Commands and SC.Commands.export(actor) or nil
    local prior = before and before.lastDowntime
    local desired = job.type == "maintain" and "repair" or job.type
    local handled, reason = false, "downtime_unavailable"
    if SC.Downtime and type(SC.Downtime.update) == "function" then
        handled, reason = SC.Downtime.update(actor, player, runtime, desired)
    end
    local after = SC.Commands and SC.Commands.export(actor) or nil
    local completed = after and after.lastDowntime
    local priorKind = type(prior) == "table" and prior.kind or prior
    local completedKind = type(completed) == "table" and completed.kind or completed
    local priorAt = type(prior) == "table" and prior.completedAt or nil
    local completedAt = type(completed) == "table" and completed.completedAt or nil
    if handled and completed ~= nil
        and (completedKind ~= priorKind or completedAt ~= priorAt) then
        SC.BaseLife.completeJob(job.id, actorId(actor), job.type)
        state.choreKind, state.choreStartedAt = nil, nil
    end
    local exhausted = handled ~= true and reason == "stable_idle"
        and now() - (state.choreStartedAt or now())
            > (U().config("downtimeSafeMs") or 5000) + 3000
    return handled == true, reason or "downtime_unavailable", exhausted
end

-- The square a companion was told to guard inside the base. Base duty from
-- the menu anchors on the base core, which is no post of its own.
local function guardPost(actor)
    local commands = SC.Commands and type(SC.Commands.peek) == "function"
        and SC.Commands.peek(actor) or nil
    local anchor = type(commands) == "table" and commands.order == "base_duty"
        and commands.anchor or nil
    local base = SC.BaseLife.active()
    if type(anchor) ~= "table" or tonumber(anchor.x) == nil or tonumber(anchor.y) == nil
        or not base then
        return nil
    end
    local core = type(base.core) == "table" and base.core or {}
    if math.floor(anchor.x) == math.floor(tonumber(core.x) or -1)
        and math.floor(anchor.y) == math.floor(tonumber(core.y) or -1) then
        return nil
    end
    if SC.BaseLife.isInside(anchor) ~= true then return nil end
    return { x = math.floor(anchor.x), y = math.floor(anchor.y), z = math.floor(anchor.z or 0) }
end

-- A job left for this resident by name (a bandage change, an assigned craft).
local function namedJobWaiting(actorId)
    local base = SC.BaseLife.active()
    for _, job in ipairs(base and base.jobs or {}) do
        if job.assignedId == actorId and (job.state == "pending"
            or (job.state == "blocked" and (tonumber(job.retryAt) or 0) <= now())) then
            return true
        end
    end
    return false
end

BaseWork._guardPostForTests = guardPost

local function guardRoutine(actor, state)
    local center = guardPost(actor)
        or SC.BaseLife.zoneCenter("guard") or SC.BaseLife.zoneCenter("rally")
    if not center then return false, "guard_zone_missing" end
    if now() < (state.nextRoutineAt or 0) and U().distance(actor, center) <= 3 then
        return false, "guard_holding"
    end
    local offsets = { { 0, 0 }, { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 } }
    state.patrolIndex = (state.patrolIndex % #offsets) + 1
    local offset = offsets[state.patrolIndex]
    local target = U().gridSquare(center.x + offset[1], center.y + offset[2], center.z)
    state.nextRoutineAt = now() + (U().config("baseGuardPatrolIntervalMs") or 30000)
    if not target then return false, "guard_target_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, target, "walk", {
        action = "base_guard_patrol", targetSquare = target,
    })
end

function BaseWork.update(actor, player, runtime)
    local id, state = actorId(actor), stateFor(actor)
    local resident = SC.BaseLife and SC.BaseLife.resident(id) or nil
    if not resident or resident.duty ~= true then return false, "not_on_base_duty" end
    if not SC.BaseLife.active() then return false, "base_missing" end
    local job = SC.BaseLife.jobFor(id)
    if not SC.BaseLife.isInside(actor) then
        -- Lumber work may continue in the bounded reach band outside the
        -- camp; every other job walks back to the rally point first.
        local reachable = type(SC.BaseLife.withinWorkReach) == "function"
            and SC.BaseLife.withinWorkReach(actor) == true
        if reachable and not job then job = select(1, SC.BaseLife.claimJob(id)) end
        if not (reachable and job and type(SC.BaseLife.jobAllowsWorkReach) == "function"
            and SC.BaseLife.jobAllowsWorkReach(job) == true) then
            local target = SC.BaseLife.zoneCenter("rally") or SC.BaseLife.active().core
            local square = U().loadedSquare(target)
            if not square then return false, "base_unloaded" end
            if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
                return false, "navigation_unavailable"
            end
            return SC.Navigation.request(actor, square, "walk", {
                action = "return_to_base", targetSquare = square,
            })
        end
    end
    local activeGuard = SC.BaseLife.guardStatus
        and select(1, SC.BaseLife.guardStatus(id, now())) or resident.role == "guard"
    -- A guard on shift keeps watch instead of wandering off to generic chores;
    -- only a job left for it by name pulls it away.
    if not job and (not (activeGuard and resident.role == "guard") or namedJobWaiting(id)) then
        job = select(1, SC.BaseLife.claimJob(id))
    end
    if not job then
        if activeGuard then
            local handled, reason = guardRoutine(actor, state)
            if handled or reason ~= "guard_zone_missing" then return handled, reason end
        end
        local base = SC.BaseLife.active()
        if base and base.settings and base.settings.routines ~= false
            and SC.Downtime and type(SC.Downtime.update) == "function" then
            local handled, reason = SC.Downtime.update(actor, player, runtime, nil)
            return handled == true, handled and reason or "base_downtime_idle"
        end
        return false, "no_base_job"
    end
    if state.jobId ~= job.id then
        state.jobId, state.phase, state.action, state.transfer = job.id, "idle", nil, nil
        state.visualAt, state.requirementsReady = nil, nil
        -- state.cargo deliberately survives: a worker still holding base
        -- stock must deliver or return it, whatever job comes next.
    end
    local handled, reason, terminal
    if job.type == "build" then handled, reason, terminal = updateBuild(actor, state, job)
    elseif job.type == "barricade" then handled, reason, terminal = queueBarricade(actor, job)
    elseif job.type == "gather_materials" then
        if not SC.GatherWork or type(SC.GatherWork.update) ~= "function" then
            handled, reason, terminal = false, "gather_work_unavailable", true
        else
            handled, reason, terminal = SC.GatherWork.update(actor, state, job)
        end
    elseif job.type == "production" then
        if not SC.Production or type(SC.Production.update) ~= "function" then
            handled, reason, terminal = false, "production_unavailable", true
        else
            handled, reason, terminal = SC.Production.update(actor, state, job, runtime)
        end
    elseif job.type == "farm" then
        if not SC.FarmWork or type(SC.FarmWork.update) ~= "function" then
            handled, reason, terminal = false, "farm_work_unavailable", true
        else
            handled, reason, terminal = SC.FarmWork.update(actor, state, job, runtime)
        end
    elseif job.type == "haul" or job.type == "sort" or job.type == "fetch" then
        handled, reason, terminal = updateTransfer(actor, state, job)
    else
        handled, reason, terminal = updateChore(actor, state, job, player, runtime)
    end
    if terminal then
        SC.BaseLife.blockJob(job.id, id, reason, U().config("baseJobRetryMs") or 10000)
        state.jobId, state.phase, state.action, state.transfer = nil, "idle", nil, nil
        -- A blocked job forgets its selection, never the cargo it still owns.
    elseif handled then
        SC.BaseLife.touchJob(job.id, id, job.state == "reserved" and "active" or job.state)
    end
    return handled == true, reason
end

local function targetHasOpenJob(base, target)
    for _, job in ipairs(base.jobs or {}) do
        if job.state ~= "completed" and job.state ~= "cancelled"
            and type(job.target) == "table" and job.target.maintenanceId == target.id then return true end
    end
    return false
end

local function openJob(base, kind, assignedId)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == kind and job.state ~= "completed" and job.state ~= "cancelled"
            and (assignedId == nil or job.assignedId == assignedId) then return true end
    end
    return false
end

local function auditMedical(base)
    local summary = SC.BaseLife.summary()
    for _, resident in ipairs(summary.residentRows or {}) do
        local id = resident.id
        if resident.duty == true and not openJob(base, "replace_bandage", id) then
            local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(id) or nil
            local actor = type(record) == "table" and (record.actor or record) or nil
            local medical
            if actor and SC.Medical and type(SC.Medical.assess) == "function" then
                local ok, value = pcall(SC.Medical.assess, actor)
                if ok then medical = value end
            end
            if medical and (medical.dirtyBandages or 0) > 0 then
                return SC.BaseLife.enqueueJob({
                    type = "replace_bandage", priority = 5, assignedId = id,
                })
            end
        end
    end
    return false, "no_medical_base_job"
end

local function auditSorting(base)
    if openJob(base, "sort") then return false, "sorting_already_queued" end
    if #SC.BaseLife.storageRows("general", true) == 0 then
        return false, "general_storage_missing"
    end
    local destinations = 0
    for category in pairs(SC.BaseLife.STORAGE_CATEGORIES) do
        if category ~= "general" and #SC.BaseLife.storageRows(category, false) > 0 then
            destinations = destinations + 1
        end
    end
    if destinations == 0 then return false, "sorted_storage_missing" end
    local actionable = false
    for _, resident in ipairs(SC.BaseLife.summary().residentRows or {}) do
        if resident.duty == true then
            local record = SC.Registry and SC.Registry.byId
                and SC.Registry.byId(resident.id) or nil
            if record and record.actor
                and select(1, findTransfer({ type = "sort" }, record.actor)) ~= nil then
                actionable = true
                break
            end
        end
    end
    if not actionable then return false, "no_sortable_supply" end
    return SC.BaseLife.enqueueJob({ type = "sort", priority = 2 })
end

local function auditRoutine(base)
    if now() < nextRoutineJobAt then return false, "routine_not_due" end
    nextRoutineJobAt = now() + 60000
    local summary = SC.BaseLife.summary()
    for _, desired in ipairs({ "craft_supply", "repair" }) do
        if not openJob(base, desired)
            and (desired ~= "craft_supply" or #SC.BaseLife.storageRows("output", false) > 0) then
            for _, resident in ipairs(summary.residentRows or {}) do
                if resident.duty == true then
                    local record = SC.Registry and SC.Registry.byId
                        and SC.Registry.byId(resident.id) or nil
                    local actor = record and record.actor or nil
                    if actor and SC.Downtime and type(SC.Downtime.canPerform) == "function"
                        and SC.Downtime.canPerform(actor, desired) == true then
                        return SC.BaseLife.enqueueJob({
                            type = desired, priority = 1, assignedId = resident.id,
                        })
                    end
                end
            end
        end
    end
    return false, "no_actionable_routine"
end

function BaseWork.auditMaintenance(player)
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base then return false, "base_missing" end
    if SC.WorkTransport and type(SC.WorkTransport.recoverPending) == "function" then
        pcall(SC.WorkTransport.recoverPending,
            U().config("workRecoveryPerPulse") or 2)
    end
    if type(SC.BaseLife.auditOperations) == "function" then SC.BaseLife.auditOperations(false) end
    if SC.FarmWork and type(SC.FarmWork.audit) == "function" then
        local queued, result = SC.FarmWork.audit(base, now())
        if queued == true then return true, result end
    end
    auditPhase = (auditPhase % 4) + 1
    if auditPhase == 1 then return auditMedical(base) end
    local settings = base.settings or {}
    if auditPhase == 2 then
        if settings.autoMaintenance == false or settings.workload == "essential" then
            return false, "automatic_sorting_disabled"
        end
        return auditSorting(base)
    end
    if auditPhase == 3 then
        if settings.routines == false or settings.workload ~= "continuous" then
            return false, "continuous_routines_disabled"
        end
        return auditRoutine(base)
    end
    if settings.autoMaintenance == false then return false, "automatic_maintenance_disabled" end
    if #base.maintenanceTargets == 0 then return false, "no_maintenance_targets" end
    if maintenanceCursor > #base.maintenanceTargets then maintenanceCursor = 1 end
    local target = base.maintenanceTargets[maintenanceCursor]
    maintenanceCursor = maintenanceCursor + 1
    if not target.enabled or targetHasOpenJob(base, target) then return false, "maintenance_not_due" end
    local object = SC.BaseLife.resolveObject(target)
    if not object then return false, "maintenance_target_unloaded" end
    if target.kind == "barricade" then
        local same = select(1, invoke(object, "getBarricadeOnSameSquare"))
        local opposite = select(1, invoke(object, "getBarricadeOnOppositeSquare"))
        local samePlanks = same and select(1, invoke(same, "getNumPlanks")) or 0
        local oppositePlanks = opposite and select(1, invoke(opposite, "getNumPlanks")) or 0
        local planks = math.max(tonumber(samePlanks) or 0, tonumber(oppositePlanks) or 0)
        if tonumber(planks) < 1 then
            return SC.BaseLife.enqueueJob({
                type = "barricade", priority = 4,
                target = {
                    x = target.x, y = target.y, z = target.z,
                    objectIndex = target.objectIndex, maintenanceId = target.id,
                },
            })
        end
    end
    return false, "maintenance_not_due"
end

function BaseWork.cancel(actor, reason)
    local state = states[actor]
    if SC.GatherWork and type(SC.GatherWork.cancelActor) == "function" then
        pcall(SC.GatherWork.cancelActor, actor, reason or "base_work_cancelled")
    end
    if SC.Production and type(SC.Production.cancelActor) == "function" then
        local called, cancelled, cancelReason = pcall(SC.Production.cancelActor, actor,
            reason or "base_work_cancelled")
        if not called or cancelled ~= true then
            return false, cancelReason or cancelled or "production_cancel_failed"
        end
    end
    if SC.FarmWork and type(SC.FarmWork.cancelActor) == "function" then
        local called, cancelled, cancelReason = pcall(SC.FarmWork.cancelActor, actor,
            reason or "base_work_cancelled")
        if not called or cancelled ~= true then
            return false, cancelReason or cancelled or "farm_cancel_failed"
        end
    end
    if not state then return true end
    local id = actorId(actor)
    if state.jobId then SC.BaseLife.releaseJob(state.jobId, id, reason or "base_work_cancelled") end
    if state.action and type(ISTimedActionQueue) == "table" then
        local queue = ISTimedActionQueue.getTimedActionQueue(actor)
        if queue and type(queue.clear) == "function" then pcall(queue.clear, queue) end
    end
    if state.visualAt ~= nil and SC.NativeActions
        and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "base_work_cancelled")
    end
    -- Cancellation must not quietly leave base stock in a worker's bag.
    if type(state.cargo) == "table" then pcall(returnCargo, actor, state.cargo) end
    states[actor] = nil
    return true
end

function BaseWork.reset(actor)
    if actor then
        BaseWork.cancel(actor, "base_work_reset")
    else
        for value, _ in pairs(states) do BaseWork.cancel(value, "base_work_reset") end
        states = setmetatable({}, { __mode = "k" })
    end
    if SC.GatherWork and type(SC.GatherWork.reset) == "function" then
        SC.GatherWork.reset(actor)
    end
    if SC.Production and type(SC.Production.reset) == "function" then
        SC.Production.reset(actor)
    end
    if SC.FarmWork and type(SC.FarmWork.reset) == "function" then
        SC.FarmWork.reset(actor)
    end
    if SC.WorkTransport and type(SC.WorkTransport.reset) == "function" then
        SC.WorkTransport.reset(actor)
    end
    maintenanceCursor, auditPhase, nextRoutineJobAt = 1, 0, 0
end

-- Production supply trips reuse the exact storage withdrawal transaction
-- (approach, loot pose, reserve re-check at commit, verified transfer).
function BaseWork.withdrawFromStorage(actor, state, storage, container, item)
    return transferFromStorage(actor, state, storage, container, item)
end

function BaseWork.returnToStorage(actor, state, storage, container, item)
    return transferToStorage(actor, state, storage, container, item)
end

-- Cancellation cannot start a new path, but it still returns a borrowed exact
-- item whenever the registered container remains loaded and can accept it.
function BaseWork.restoreToStorage(actor, storage, container, item)
    if not actor or not item then return false, "borrowed_supply_missing" end
    if U().inventoryContains(container, item) then return true, "base_supply_returned" end
    local current = storage and SC.BaseLife.resolveContainer(storage) or container
    if not current or current ~= container then return false, "base_storage_unloaded" end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, item) then
        return false, "borrowed_supply_missing"
    end
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        local moved, reason = SC.WorkTransport.transferVerified(inventory, container, item, actor)
        return moved == true, moved and "base_supply_returned" or reason
    end
    return U().transferItemVerified(inventory, container, item)
end

return BaseWork
