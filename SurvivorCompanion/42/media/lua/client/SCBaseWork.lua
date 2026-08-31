-- SPDX-License-Identifier: MIT

require "SCBaseLife"
require "BuildingObjects/TimedActions/ISBuildAction"
require "TimedActions/ISTimedActionQueue"

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

local function listSize(value)
    if value == nil then return 0 end
    if type(value) == "table" then return #value end
    local size, ok = invoke(value, "size")
    return ok and tonumber(size) or 0
end

local function listGet(value, index)
    if type(value) == "table" then return value[index + 1] end
    local child, ok = invoke(value, "get", index)
    return ok and child or nil
end

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

local function inventoryCount(actor, itemType)
    local count = 0
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 256)) do
        if U().itemType(item) == itemType then count = count + 1 end
    end
    return count
end

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

local function transferFromStorage(actor, state, storage, container, item)
    local object = SC.BaseLife.resolveObject(storage)
    if not object then return false, "base_storage_unloaded" end
    if U().distance(actor, object) > 1.5 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local targets = SC.Navigation.interactionTargets(actor, object)
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
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
    if not U().inventoryContains(container, item) then return false, "base_supply_moved" end
    local transferred, reason = U().transferItemVerified(
        container, U().inventory(actor), item)
    return transferred == true, transferred and "base_supply_taken"
        or reason or "base_supply_transfer_failed"
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
end

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
            return SC.Navigation.requestAny(actor, approaches, "walk", {
                action = "move_to_base_build", targetSquare = square,
                arrivalDistance = 0.8,
            })
        end
        return startBuildAction(actor, state, job, info, square)
    end
    if actionActive(actor, state.action) then
        SC.BaseLife.touchJob(job.id, actorId(actor), "active")
        return true, "building"
    end
    local created = squareObjectCount(square) > (state.initialObjectCount or 0)
        or (state.entity and state.entity:isValid(square) ~= true)
    if created then
        SC.BaseLife.completeJob(job.id, actorId(actor), "built")
        state.phase, state.action, state.entity = "idle", nil, nil
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "base_build", "built", { kind = "long" })
        end
        return true, "build_complete"
    end
    return false, "build_action_cancelled", true
end

local function classifyItem(item)
    local itemType = string.lower(U().itemType(item))
    local category = select(1, invoke(item, "getCategory"))
    category = string.lower(tostring(category or ""))
    if category == "food" then return "food" end
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

local function findTransfer(job, actor)
    local sourceCategory = job.type == "sort" and "general"
        or (type(job.target) == "table" and job.target.sourceCategory) or "general"
    for _, source in ipairs(SC.BaseLife.storageRows(sourceCategory, true)) do
        local container = SC.BaseLife.resolveContainer(source)
        if container then
            for _, item in ipairs(U().inventoryItems(container, 80)) do
                if not (SC.PersonalItems and SC.PersonalItems.isProtected
                    and SC.PersonalItems.isProtected(item, actor, "base_haul")) then
                    local destinationCategory = type(job.target) == "table"
                        and job.target.destinationCategory or classifyItem(item)
                    for _, destination in ipairs(SC.BaseLife.storageRows(destinationCategory, false)) do
                        if destination.id ~= source.id and destination.deposits ~= false then
                            local destinationContainer = SC.BaseLife.resolveContainer(destination)
                            if destinationContainer then
                                return source, container, destination, destinationContainer, item
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function updateTransfer(actor, state, job)
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
            if not ok or reason ~= "base_supply_taken" then return ok, reason end
        end
        transfer.phase = "deposit"
    end
    local object = SC.BaseLife.resolveObject(transfer.destination)
    if not object then return false, "destination_storage_unloaded", true end
    if U().distance(actor, object) > 1.5 then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable", true
        end
        local targets = SC.Navigation.interactionTargets(actor, object)
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
    end
    if not U().inventoryContains(U().inventory(actor), transfer.item) then
        return false, "hauled_item_missing", true
    end
    local moved = U().transferItem(U().inventory(actor), transfer.destinationContainer, transfer.item)
    if not moved then return false, "base_deposit_failed", true end
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
        local ok, reason = SC.Medical and SC.Medical.replaceDirtyBandage(actor)
        if ok and reason == "bandaged" then
            SC.BaseLife.completeJob(job.id, actorId(actor), reason)
        end
        local terminalFailure = ok ~= true and reason ~= "treatment_animation_active"
            and reason ~= "treatment_animation_started"
        return ok == true, reason or "medical_unavailable", terminalFailure
    end
    if state.choreKind ~= job.type then
        state.choreKind, state.choreStartedAt = job.type, now()
    end
    local before = SC.Commands and SC.Commands.export(actor) or nil
    local prior = before and before.lastDowntime
    local desired = job.type == "maintain" and "repair" or job.type
    local handled, reason = SC.Downtime and SC.Downtime.update(actor, player, runtime, desired)
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

local function guardRoutine(actor, state)
    local center = SC.BaseLife.zoneCenter("guard") or SC.BaseLife.zoneCenter("rally")
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
    if not SC.BaseLife.isInside(actor) then
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
    local job = SC.BaseLife.jobFor(id)
    if not job then job = select(1, SC.BaseLife.claimJob(id)) end
    if not job then
        local activeGuard = SC.BaseLife.guardStatus
            and select(1, SC.BaseLife.guardStatus(id, now())) or resident.role == "guard"
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
    end
    local handled, reason, terminal
    if job.type == "build" then handled, reason, terminal = updateBuild(actor, state, job)
    elseif job.type == "barricade" then handled, reason, terminal = queueBarricade(actor, job)
    elseif job.type == "haul" or job.type == "sort" or job.type == "fetch" then
        handled, reason, terminal = updateTransfer(actor, state, job)
    else
        handled, reason, terminal = updateChore(actor, state, job, player, runtime)
    end
    if terminal then
        SC.BaseLife.blockJob(job.id, id, reason, U().config("baseJobRetryMs") or 10000)
        state.jobId, state.phase, state.action, state.transfer = nil, "idle", nil, nil
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
    if type(SC.BaseLife.auditOperations) == "function" then SC.BaseLife.auditOperations(false) end
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
    maintenanceCursor, auditPhase, nextRoutineJobAt = 1, 0, 0
end

return BaseWork
