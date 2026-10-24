-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCFloorSort")
    pcall(require, "SCGatherWork")
    pcall(require, "SCFarmWork")
    pcall(require, "SCChefWork")
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
local storageItemCursors = setmetatable({}, { __mode = "k" })
local cleaningSourceCache = setmetatable({}, { __mode = "k" })
local maintenanceCursor = 1
local auditPhase = 0
local cleaningScan
local nextRoutineJobAt = 0
local maintenanceAudit
local function maintenanceBudget(remainingBudget)
    return type(remainingBudget) ~= "function" or (tonumber(remainingBudget()) or 0) > 0
end
local buildRecipeAliases = {
    -- GetAllBuildableEntities() exposes EntityScript:getName(), not the
    -- UiConfig entityStyle IDs used by the crafting window.
    wall_frame = { "WoodenWallFrame" },
    wall = { "WoodenWallLvl1", "WoodenWallLvl2", "WoodenWallLvl3" },
    floor = { "WoodFloorLvl1", "WoodFloorLvl2", "WoodFloorLvl3" },
    door_frame = { "WoodDoorFrameLvl1", "WoodDoorFrameLvl2", "WoodDoorFrameLvl3" },
    door = { "WoodenDoorLvl1", "WoodenDoorLvl2", "WoodenDoorLvl3" },
    -- Burial markers use the same EntityScript names.
    grave_marker = { "WoodCross", "RuggedCross" },
}
local FALLEN_NAME = "LF_FallenName"
local FALLEN_DISPLAY_NAME = "LF_FallenDisplayName"
local FALLEN_MARKER = "LF_FallenMarker"

local function U()
    return SC.GameplayUtil
end

-- Marked storage and guard routes use the camp floor admission. Storage may
-- require a standing tile just outside the drawn boundary, within work reach.
local function workRoute(intent, allowReach)
    intent.workCampOnly = true
    intent.workReach = allowReach == true
    return intent
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

local function reportBlockedTool(actor, player, state, runtime)
    if actor == player then return end
    local pending = state.pendingToolRequest
    if not pending or not SC.Dialogue
        or type(SC.Dialogue.requestMissingTool) ~= "function" then return end
    local job = SC.BaseLife and SC.BaseLife.job(pending.jobId) or nil
    if not job or job.state == "completed" or job.state == "cancelled"
        or now() - pending.createdAt > 600000 then
        state.pendingToolRequest = nil
        return
    end
    -- The worker may have found the tool on a retry. Only approach while the
    -- job is still blocked for the same shortage.
    if job.state ~= "blocked" or job.blocker ~= pending.reason then return end
    local snapshot = type(runtime) == "table"
        and (runtime.snapshot or (type(runtime.senses) == "table"
            and runtime.senses.current)) or nil
    SC.Dialogue.requestMissingTool(actor, player, pending.kind, snapshot, function()
        if state.pendingToolRequest == pending then state.pendingToolRequest = nil end
    end, function()
        return state.pendingToolRequest == pending
            and job.state == "blocked" and job.blocker == pending.reason
    end)
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
    if not nameOk or name == nil then return nil end
    -- Some script wrappers qualify the module (Base.WoodenWallLvl1).
    return tostring(name):match("[^%.]+$")
end

local recipeInfoCache = {}
function BaseWork.recipeInfo(recipeId)
    if recipeInfoCache[recipeId] then return recipeInfoCache[recipeId] end
    if type(ISBuildIsoEntity) ~= "table"
        or type(ISBuildIsoEntity.GetAllBuildableEntities) ~= "function" then return nil end
    local ok, infos = pcall(ISBuildIsoEntity.GetAllBuildableEntities)
    if not ok or infos == nil then return nil end
    for index = 1, #infos do
        local info = infos[index]
        if resolveRecipeName(info) == recipeId then
            recipeInfoCache[recipeId] = info
            return info
        end
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

local function faceIndex(face)
    if face == 2 then return 0 end -- north
    if face == 4 then return 2 end -- south
    return face -- west or east
end

function BaseWork.recipeFace(recipeId, requestedFace)
    local info = BaseWork.recipeInfo(recipeId)
    if not info then return nil, nil end
    requestedFace = math.max(1, math.min(4, math.floor(tonumber(requestedFace) or 1)))
    for offset = 0, 3 do
        local face = ((requestedFace + offset - 1) % 4) + 1
        local value = select(1, invoke(info, "getFace", faceIndex(face)))
        if value then return value, face end
    end
    return nil, nil
end

function BaseWork.recipeSprite(recipeId, requestedFace)
    local face, resolvedFace = BaseWork.recipeFace(recipeId, requestedFace)
    if not face then return nil, resolvedFace end
    local rawWidth = select(1, invoke(face, "getWidth"))
    local rawHeight = select(1, invoke(face, "getHeight"))
    local width = tonumber(rawWidth) or 1
    local height = tonumber(rawHeight) or 1
    for x = 0, width - 1 do
        for y = 0, height - 1 do
            local tile = select(1, invoke(face, "getTileInfo", x, y, 0))
            local sprite = tile and select(1, invoke(tile, "getSpriteName")) or nil
            if type(sprite) == "string" and sprite ~= "" then
                return sprite, resolvedFace
            end
        end
    end
    return nil, resolvedFace
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

-- Keep work scans bounded, but rotate their starting position so supplies
-- beyond the first budgeted items are eventually considered too.
local function storageItemSlice(container)
    local items, readable = U().call(container, "getItems")
    if not readable then items = type(container) == "table" and container.items or nil end
    local size = U().listSize(items)
    if size == 0 then return {}, 0 end
    local budget = math.max(1, math.floor(tonumber(U().config("campStorageItemBudget")) or 80))
    local count = math.min(size, budget)
    local start = (storageItemCursors[container] or 0) % size
    local result = {}
    for offset = 0, count - 1 do
        local item = U().listGet(items, (start + offset) % size)
        if item ~= nil then result[#result + 1] = item end
    end
    storageItemCursors[container] = (start + count) % size
    return result, start
end

local function sourceItemAvailable(storage, itemType)
    if SC.BaseLife.storageReserve(storage, itemType) == 0 then return true end
    return SC.BaseLife.availableCountExact(storage, itemType) > 0
end

local function findSource(actor, requirement)
    -- Craft inputs are alternatives (for example any usable hammer), so an
    -- absent first type must not reject a later type already carried.
    for _, itemType in ipairs(requirement.types) do
        local have = inventoryCount(actor, itemType)
        if have >= requirement.count then return false end
    end
    -- One container window must be tested against every alternative. Advancing
    -- its cursor once per type can alternate disjoint half-container windows
    -- forever when the budget is half the container size.
    local windows = {}
    for _, itemType in ipairs(requirement.types) do
        for _, category in ipairs(sourceCategories(requirement)) do
            for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
                local container = SC.BaseLife.resolveContainer(storage)
                if container then
                    local items = windows[container]
                    if items == nil then
                        items = storageItemSlice(container)
                        windows[container] = items
                    end
                    for _, item in ipairs(items) do
                        if U().itemType(item) == itemType
                            and not BaseWork.choreReserved(item)
                            and sourceItemAvailable(storage, itemType)
                            and not (SC.PersonalItems and SC.PersonalItems.isProtected
                                and SC.PersonalItems.isProtected(item, actor, "base_build")) then
                            return storage, container, item, itemType
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, requirement.types[1]
end
BaseWork._findSourceForTests = findSource

local function withdrawalAllowed(storage, expectedContainer, item)
    if type(storage) ~= "table" or type(storage.id) ~= "string" then
        return false, "base_storage_invalid"
    end
    if SC.BaseLife.storage(storage.id) ~= storage then
        return false, "base_storage_changed"
    end
    if not SC.BaseLife.withdrawable(storage) then
        return false, "base_storage_withdrawals_disabled"
    end
    local currentContainer = SC.BaseLife.resolveContainer(storage)
    if currentContainer == nil then return false, "base_storage_unloaded" end
    if currentContainer ~= expectedContainer then return false, "base_storage_changed" end
    if not U().inventoryContains(currentContainer, item) then
        return false, "base_supply_moved"
    end
    local itemType = U().itemType(item)
    local available = type(SC.BaseLife.availableCountExact) == "function"
        and SC.BaseLife.availableCountExact(storage, itemType)
        or SC.BaseLife.availableCount(storage, itemType)
    if available <= 0 then
        return false, "base_supply_reserved"
    end
    return true
end

local function transferFromStorage(actor, state, storage, container, item)
    if type(storage) ~= "table" or SC.BaseLife.storage(storage.id) ~= storage then
        return false, "base_storage_changed"
    end
    if not SC.BaseLife.withdrawable(storage) then
        return false, "base_storage_withdrawals_disabled"
    end
    local object = SC.BaseLife.resolveObject(storage)
    if not object then return false, "base_storage_unloaded" end
    local atStorage, targets, accessReason = U().directInteractionAccess(actor, object)
    if atStorage ~= true then
        if accessReason == "no_interaction_targets" then return false, accessReason end
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        -- Only (handled, reason): a third navigation value would be read as
        -- the terminal flag and block the job on every approach.
        local approached, approachReason = SC.Navigation.requestAny(actor, targets, "walk", workRoute({
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 0.35, requireSameSquare = true,
            continuousApproach = true,
        }, true))
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
local function transferToStorage(actor, state, storage, container, item, requireDeposits, options)
    if type(storage) == "table" and storage.kind == "log_yard" then
        local square = SC.LogYard and SC.LogYard.tile(storage.x, storage.y,
            storage.z, storage.zoneId) or nil
        if not square then return false, "log_yard_unloaded" end
        local inventory = U().inventory(actor)
        if not inventory or not U().inventoryContains(inventory, item) then
            return false, "borrowed_supply_missing"
        end
        if not U().sameSquare(actor, square) then
            if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
                return false, "navigation_unavailable"
            end
            local approached, reason = SC.Navigation.requestAny(actor, { square }, "walk",
                workRoute({ action = "move_to_log_yard", targetSquare = square,
                    arrivalDistance = 0.45, workReach = true }, true))
            return approached == true, reason
        end
        local dropped, reason = SC.LogYard.deposit(actor, item, storage)
        if dropped == true and SC.LogYard.bundleAt
            and not (type(options) == "table" and options.deferLogYardBundle == true) then
            SC.LogYard.bundleAt(actor, square)
        end
        return dropped == true, dropped and "base_supply_returned" or reason
    end
    if U().inventoryContains(container, item) then return true, "base_supply_returned" end
    if type(storage) ~= "table" then return false, "base_storage_invalid" end
    if requireDeposits == true then
        local accepts, depositReason = SC.BaseLife.storageAcceptsDeposit(storage, container)
        if accepts ~= true then return false, depositReason end
    end
    local object = SC.BaseLife.resolveObject(storage)
    local currentContainer = SC.BaseLife.resolveContainer(storage)
    if not object or not currentContainer then return false, "base_storage_unloaded" end
    if currentContainer ~= container then return false, "base_storage_changed" end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, item) then
        return false, "borrowed_supply_missing"
    end
    if requireDeposits == true then
        local accepts, depositReason = SC.BaseLife.storageAcceptsDeposit(storage, container)
        if accepts ~= true then return false, depositReason end
    end
    local atStorage, targets, accessReason = U().directInteractionAccess(actor, object)
    if atStorage ~= true then
        if accessReason == "no_interaction_targets" then return false, accessReason end
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            return false, "navigation_unavailable"
        end
        local approached, approachReason = SC.Navigation.requestAny(actor, targets, "walk", workRoute({
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 0.35, requireSameSquare = true,
            continuousApproach = true,
            movementPriority = type(options) == "table"
                and tonumber(options.movementPriority) or nil,
        }, true))
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
    -- Policy can change while the worker is walking or playing the loot pose.
    -- Revalidate immediately before the identity transfer, not just selection.
    if requireDeposits == true then
        local accepts, depositReason = SC.BaseLife.storageAcceptsDeposit(storage, container)
        if accepts ~= true then return false, depositReason end
    end
    local moved, reason
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        moved, reason = SC.WorkTransport.transferVerified(inventory, container, item, actor)
    else
        moved, reason = U().transferItemVerified(inventory, container, item)
    end
    return moved == true, moved and "base_supply_returned"
        or reason or "base_supply_return_failed"
end

-- Cleaning borrows two exact objects. Keep the receipt on the saved job and
-- a job marker on each item: inventory and container objects are recreated
-- across reloads, while the job ID survives. Carried personal supplies never
-- get a receipt and therefore never get returned to camp storage.
local CLEAN_MARKERS = {
    tool = "LF_CleanToolJobId", liquid = "LF_CleanLiquidJobId",
}

local function cleaningLiquidAmount(item)
    local fluid = select(1, U().call(item, "getFluidContainer"))
    local bleach = Fluid and Fluid.Bleach
    local cleaning = Fluid and Fluid.CleaningLiquid
    if not fluid or ((not bleach or select(1, U().call(fluid, "contains", bleach)) ~= true)
        and (not cleaning or select(1, U().call(fluid, "contains", cleaning)) ~= true)) then
        return nil
    end
    local amount = select(1, U().call(fluid, "getAmount"))
    return tonumber(amount)
end

local function cleaningItemUsable(item, kind)
    if kind == "tool" then
        return ItemTag and ItemTag.CLEAN_STAINS
            and select(1, U().call(item, "hasTag", ItemTag.CLEAN_STAINS)) == true
            and select(1, U().call(item, "isBroken")) ~= true or false
    end
    local minimum = ZomboidGlobals and ZomboidGlobals.CleanBloodBleachAmount
    local amount = cleaningLiquidAmount(item)
    return type(minimum) == "number" and minimum > 0
        and amount ~= nil and amount >= minimum
end

local function cleaningReceipt(job, kind)
    local target = type(job) == "table" and job.target or nil
    return type(target) == "table" and type(target.cleanLoans) == "table"
        and target.cleanLoans[kind] or nil
end

local function cleaningMarked(item, job, kind)
    local data = item and U().modData(item) or nil
    local receipt = cleaningReceipt(job, kind)
    return type(data) == "table" and type(receipt) == "table"
        and data[CLEAN_MARKERS[kind]] == job.id
        and tostring(receipt.itemId) == tostring(select(1, U().call(item, "getID")))
end

local function cleaningLoanItem(actor, job, kind)
    local receipt = cleaningReceipt(job, kind)
    if not receipt then return nil, nil, nil end
    local inventory = actor and U().inventory(actor) or nil
    local owned, container, found
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 512, 24) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data[CLEAN_MARKERS[kind]] == job.id then
            if found then return nil, nil, "cleaning_loan_ambiguous" end
            found, owned = item, true
        end
    end
    local storage = SC.BaseLife.storage(receipt.sourceStorageId)
    container = storage and SC.BaseLife.resolveContainer(storage) or nil
    if container then
        for _, item in ipairs(U().inventoryItems(container, 1024)) do
            local data = U().modData(item)
            if type(data) == "table" and data[CLEAN_MARKERS[kind]] == job.id then
                if found and found ~= item then
                    return nil, nil, "cleaning_loan_ambiguous" end
                found, owned = item, false
            end
        end
    end
    if found then
        if owned and inventory and not U().inventoryContains(inventory, found) then
            local nested = select(1, U().call(found, "getContainer"))
            if not nested or U().transferItemVerified(nested, inventory, found) ~= true then
                return nil, nil, "cleaning_loan_nested_unreachable"
            end
        end
        local id = select(1, U().call(found, "getID"))
        if id == nil then return nil, nil, "cleaning_loan_id_missing" end
        -- Restored companion inventory items can have new native IDs. A
        -- unique marked item on the assigned worker is the recovery proof.
        if tostring(id) ~= tostring(receipt.itemId) then
            if not owned or job.assignedId ~= U().idOf(actor) then
                return nil, nil, "cleaning_loan_id_changed" end
            receipt.itemId = id
        end
    end
    return found, owned, nil, storage, container
end

local function carriedCleaningItem(actor, kind, job)
    local inventory = U().inventory(actor)
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 180, 12)) do
        if cleaningItemUsable(item, kind)
            and (not BaseWork.choreReserved(item)
                or job and cleaningMarked(item, job, kind)) then
            return item
        end
    end
    return nil
end

local function findCleaningSource(actor, kind)
    local cached = cleaningSourceCache[actor]
    local remembered = cached and cached[kind]
    if remembered then
        local storage = SC.BaseLife.storage(remembered.storageId)
        local container = storage and SC.BaseLife.resolveContainer(storage)
        local item = remembered.item
        local itemType = item and U().itemType(item)
        if storage and SC.BaseLife.withdrawable(storage)
            and container and U().inventoryContains(container, item)
            and itemType and cleaningItemUsable(item, kind)
            and not BaseWork.choreReserved(item)
            and sourceItemAvailable(storage, itemType)
            and not (SC.WorkTransport and SC.WorkTransport.foreignProtected
                and SC.WorkTransport.foreignProtected(item, actor) == true)
            and not (SC.PersonalItems and SC.PersonalItems.isProtected
                and SC.PersonalItems.isProtected(item, actor, "base_clean")) then
            return storage, container, item
        end
        cached[kind] = nil
    end
    local seen = {}
    for _, category in ipairs({ "tools", "general", "crafting", false }) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category or nil, true)) do
            if not seen[storage.id] then
                seen[storage.id] = true
                local container = SC.BaseLife.resolveContainer(storage)
                if container then
                    for _, item in ipairs(storageItemSlice(container)) do
                        local itemType = U().itemType(item)
                        if itemType and cleaningItemUsable(item, kind)
                            and not BaseWork.choreReserved(item)
                            and sourceItemAvailable(storage, itemType)
                            and not (SC.WorkTransport and SC.WorkTransport.foreignProtected
                                and SC.WorkTransport.foreignProtected(item, actor) == true)
                            and not (SC.PersonalItems and SC.PersonalItems.isProtected
                                and SC.PersonalItems.isProtected(item, actor, "base_clean")) then
                            cached = cached or {}
                            cached[kind] = { storageId = storage.id, item = item }
                            cleaningSourceCache[actor] = cached
                            return storage, container, item
                        end
                    end
                end
            end
        end
    end
    return nil
end

function BaseWork.cleaningSuppliesAvailable(actor, job)
    if not actor then return false end
    for _, kind in ipairs({ "tool", "liquid" }) do
        local borrowed = job and cleaningReceipt(job, kind)
        local loanItem = borrowed and cleaningLoanItem(actor, job, kind) or nil
        if not loanItem and not carriedCleaningItem(actor, kind, job)
            and not findCleaningSource(actor, kind) then return false end
    end
    return true
end

local function clearCleaningLoan(job, kind, item)
    local receipt = cleaningReceipt(job, kind)
    if not receipt then return true end
    if item then
        local data = U().modData(item)
        if type(data) ~= "table" then return false end
        if data[CLEAN_MARKERS[kind]] == job.id then
            data[CLEAN_MARKERS[kind]] = nil
        end
    end
    job.target.cleanLoans[kind] = nil
    if not job.target.cleanLoans.tool and not job.target.cleanLoans.liquid then
        job.target.cleanLoans = nil
        job.assignedId = nil
    end
    return true
end

local function returnCleaningLoans(actor, state, job, direct)
    for _, kind in ipairs({ "tool", "liquid" }) do
        local receipt = cleaningReceipt(job, kind)
        if receipt then
            local item, carried, itemReason, storage, container =
                cleaningLoanItem(actor, job, kind)
            if itemReason then return false, itemReason end
            if item and carried then
                if not storage then
                    -- An unmarked source cannot receive the borrowed object.
                    -- Keep it with the worker, now as ordinary inventory.
                    if not clearCleaningLoan(job, kind, item) then
                        return false, "cleaning_marker_uncertain" end
                elseif not container then
                    return false, "base_storage_unloaded"
                else
                    local returned, reason
                    if direct then
                        returned, reason = BaseWork.restoreToStorage(actor,
                            storage, container, item)
                    else
                        returned, reason = transferToStorage(actor, state,
                            storage, container, item)
                    end
                    if returned == true and reason ~= "base_supply_returned" then
                        return nil, reason
                    end
                    if returned ~= true then
                        if reason == "base_storage_action_rejected" then
                            return nil, "cleaning_storage_busy" end
                        return false, reason
                    end
                    if not U().inventoryContains(container, item) then
                        return false, "cleaning_return_unverified" end
                    if not clearCleaningLoan(job, kind, item) then
                        return false, "cleaning_marker_uncertain" end
                end
            elseif item and container and U().inventoryContains(container, item) then
                if not clearCleaningLoan(job, kind, item) then
                    return false, "cleaning_marker_uncertain" end
            elseif not storage then
                clearCleaningLoan(job, kind, item)
            elseif not container then
                return false, "base_storage_unloaded"
            else
                -- The player moved the item. Its marker goes stale when this
                -- receipt is cleared; never fabricate a replacement.
                clearCleaningLoan(job, kind, nil)
            end
        end
    end
    return true
end

local function stageCleaningItem(actor, state, job, kind)
    local receipt = cleaningReceipt(job, kind)
    if receipt then
        local item, carried, reason, storage, container =
            cleaningLoanItem(actor, job, kind)
        if reason then return false, reason, true end
        if item and carried and cleaningItemUsable(item, kind) then
            return true, "cleaning_supply_carried" end
        if item and carried then
            local returned, why = returnCleaningLoans(actor, state, job)
            return returned, why or "cleaning_supply_exhausted", returned == false
        end
        if not item then
            if storage and not container then return false, "base_storage_unloaded", true end
            clearCleaningLoan(job, kind, nil)
            return true, "cleaning_supply_reselecting"
        end
        if not storage or not container then
            return false, "base_storage_unloaded", true end
        local taken, why = transferFromStorage(actor, state, storage, container, item)
        if U().inventoryContains(U().inventory(actor), item) then
            return true, "cleaning_supply_carried" end
        -- A failed withdrawal is conclusive for this source. The caller
        -- settles any selected or already borrowed supplies before blocking.
        return taken == true, why, taken == false
    end
    if carriedCleaningItem(actor, kind, job) then
        return true, "cleaning_personal_supply" end
    local storage, container, item = findCleaningSource(actor, kind)
    if not item then return false, "cleaning_supplies_missing", true end
    local id = select(1, U().call(item, "getID"))
    local data = U().modData(item)
    if id == nil or type(data) ~= "table" then
        return false, "cleaning_supply_id_missing", true end
    local marker = CLEAN_MARKERS[kind]
    if data[marker] ~= nil and BaseWork.choreReserved(item) then
        return false, "cleaning_supply_reserved", true end
    job.target.cleanLoans = job.target.cleanLoans or {}
    job.target.cleanLoans[kind] = { sourceStorageId = storage.id, itemId = id }
    job.assignedId = U().idOf(actor)
    data[marker] = job.id
    return true, "cleaning_supply_selected"
end

local function prepareBuild(actor, state, job, info)
    local requirements, recipeOrReason = recipeRequirements(info)
    if not requirements then return false, recipeOrReason end
    for _, requirement in ipairs(requirements) do
        local storage, container, item, missingType = findSource(actor, requirement)
        if storage == nil then
            if missingType == "Base.Log" and SC.LogYard and SC.LogYard.source then
                local yard = SC.LogYard.source(actor)
                if yard then
                    local taken, reason = SC.LogYard.takeOne(actor, yard)
                    return taken, reason or "build_log_yard_unavailable"
                end
            end
            return false, "missing_build_supply:" .. tostring(missingType)
        end
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

-- Remove exactly the build action owned by this job.  Clearing the whole
-- timed-action queue can destroy unrelated work from another mod, while merely
-- deleting the BaseLife row leaves Build 42 free to perform the accepted
-- construction later.
local function cancelBuildAction(actor, state, reason)
    local action = state and state.action or nil
    if action == nil then return true, "build_action_absent" end
    action.scCancelled, action.scCancelReason = true, reason or "build_cancelled"
    local queue = type(ISTimedActionQueue) == "table"
        and type(ISTimedActionQueue.getTimedActionQueue) == "function"
        and ISTimedActionQueue.getTimedActionQueue(actor) or nil
    if action.action ~= nil then
        invoke(actor, "cancelCompanionPendingAction", action.action)
    end
    if type(action.forceStop) == "function" then pcall(action.forceStop, action) end
    if type(queue) == "table" and type(queue.removeFromQueue) == "function" then
        pcall(queue.removeFromQueue, queue, action)
        if queue.current == action then
            queue.current = type(queue.queue) == "table" and queue.queue[1] or nil
        end
    end
    if state.entity and state.entity.buildPanelLogic
        and type(state.entity.buildPanelLogic.stopCraftAction) == "function" then
        pcall(state.entity.buildPanelLogic.stopCraftAction, state.entity.buildPanelLogic)
    end
    if actionActive(actor, action) then return false, "build_action_cancel_failed" end
    state.action, state.entity, state.buildSpriteName = nil, nil, nil
    state.phase = "idle"
    return true, "build_action_cancelled"
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
    local job = self.scJobId and SC.BaseLife and SC.BaseLife.job
        and SC.BaseLife.job(self.scJobId) or nil
    if self.scCancelled == true or not job or job.reservedBy ~= self.scActorId
        or (job.state ~= "reserved" and job.state ~= "active") then
        self.scStopped = true
        local queue = type(ISTimedActionQueue) == "table"
            and type(ISTimedActionQueue.getTimedActionQueue) == "function"
            and ISTimedActionQueue.getTimedActionQueue(self.character) or nil
        if type(queue) == "table" and type(queue.removeFromQueue) == "function" then
            pcall(queue.removeFromQueue, queue, self)
            if queue.current == self then
                queue.current = type(queue.queue) == "table" and queue.queue[1] or nil
            end
        end
        return
    end
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

local function fallenMarkerNames(job)
    if type(job) ~= "table" or job.type ~= "build"
        or (job.recipeId ~= "WoodCross" and job.recipeId ~= "RuggedCross")
        or type(job.fallenName) ~= "string" or job.fallenName == "" then
        return nil
    end
    local displayName = type(job.fallenDisplayName) == "string"
        and job.fallenDisplayName ~= "" and job.fallenDisplayName or job.fallenName
    return job.fallenName, displayName
end

-- Companion builds receive these fields before vanilla copies the cursor's
-- name and modData into the IsoThumpable. Player-completed queued crosses are
-- tagged when the world object is reconciled instead.
local function nameFallenMarker(job, square, spriteName)
    local name, displayName = fallenMarkerNames(job)
    if not name or type(spriteName) ~= "string" then return false end
    local marker
    U().squareObjects(square, function(object)
        local sprite = select(1, invoke(object, "getSprite"))
        if sprite and select(1, invoke(sprite, "getName")) == spriteName then
            marker = object
            return false
        end
    end, 128)
    if not marker then return false end
    local data = U().modData(marker)
    if type(data) ~= "table" then return false end
    data[FALLEN_NAME], data[FALLEN_DISPLAY_NAME], data[FALLEN_MARKER] =
        name, displayName, true
    invoke(marker, "setName", displayName)
    invoke(marker, "transmitModData")
    return true
end
BaseWork._nameFallenMarkerForTests = nameFallenMarker

-- A normal player build may finish a queued segment without going through the
-- companion action. Only world evidence advances it; an absent action cannot.
function BaseWork.reconcileBuildJob(job, actorId)
    if type(job) ~= "table" or job.type ~= "build" then return false, "not_build_job" end
    if actorId == nil and job.reservedBy ~= nil then return false, "worker_owns_job" end
    local square = targetSquare(job)
    if not square then return false, "build_target_unloaded" end
    local stages = type(job.stages) == "table" and job.stages or {}
    local lastRecipe = #stages > 0 and stages[#stages] or job.recipeId
    local finalSprite = BaseWork.recipeSprite(lastRecipe, job.face)
    if squareHasSprite(square, finalSprite) == true then
        nameFallenMarker(job, square, finalSprite)
        return SC.BaseLife.completeJob(job.id, actorId, "built")
    end
    local currentSprite = BaseWork.recipeSprite(job.recipeId, job.face)
    if squareHasSprite(square, currentSprite) == true then
        return SC.BaseLife.advanceBuildStage(job.id, actorId)
    end
    return false, "build_not_present"
end

function BaseWork.reconcileBarricadeJob(job, actorId)
    if type(job) ~= "table" or job.type ~= "barricade"
        or type(job.target) ~= "table" then return false, "not_barricade_job" end
    if actorId == nil and job.reservedBy ~= nil then return false, "worker_owns_job" end
    local object = SC.BaseLife.resolveObject(job.target)
    if not object then return false, "barricade_target_unloaded" end
    local method = job.target.barricadeSide == "opposite"
        and "getBarricadeOnOppositeSquare" or "getBarricadeOnSameSquare"
    local barricade = select(1, invoke(object, method))
    if barricade and select(1, invoke(barricade, "canAddPlank")) == false then
        return SC.BaseLife.completeJob(job.id, actorId, "barricaded")
    end
    return false, "barricade_not_full"
end

local externalBuildCursor = 1
function BaseWork.reconcileExternalBuilds()
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active() or nil
    local jobs = base and base.jobs or nil
    if type(jobs) ~= "table" or #jobs == 0 then return 0 end
    local checked, changed = 0, 0
    while checked < math.min(4, #jobs) do
        if externalBuildCursor > #jobs then externalBuildCursor = 1 end
        local job = jobs[externalBuildCursor]
        checked = checked + 1
        if job and (job.type == "build" or job.type == "barricade")
            and job.reservedBy == nil then
            local okay
            if job.type == "build" then
                okay = BaseWork.reconcileBuildJob(job, nil)
            else
                okay = BaseWork.reconcileBarricadeJob(job, nil)
            end
            if okay == true then changed = changed + 1
            else externalBuildCursor = externalBuildCursor + 1 end
        else
            externalBuildCursor = externalBuildCursor + 1
        end
    end
    return changed
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
    if not ArrayList or type(ArrayList.new) ~= "function" then
        return false, "build_container_list_unavailable"
    end
    local containers = ArrayList.new()
    containers:add(U().inventory(actor))
    local entity = ISBuildIsoEntity:new(actor, info, tonumber(job.face) or 1, containers)
    if not entity then return false, "build_entity_creation_failed" end
    local fallenName, fallenDisplayName = fallenMarkerNames(job)
    if fallenName then
        entity.name = fallenDisplayName
        entity.modData = type(entity.modData) == "table" and entity.modData or {}
        entity.modData[FALLEN_NAME] = fallenName
        entity.modData[FALLEN_DISPLAY_NAME] = fallenDisplayName
        entity.modData[FALLEN_MARKER] = true
    end
    entity.nSprite = tonumber(job.face) or 1
    -- The vanilla entity cursor uses getSprite() to set its facing, but its
    -- inherited method may return nil: rendering/building uses getFace().
    local sprite = entity:getSprite() or BaseWork.recipeSprite(job.recipeId, job.face)
    if entity:isValid(square) ~= true then return false, "build_target_invalid" end
    local recipeInfo = select(1, invoke(info, "getRecipe"))
    local recipe = recipeInfo and select(1, invoke(recipeInfo, "getCraftRecipe")) or nil
    local duration = recipe and select(1, invoke(recipe, "getTime")) or 200
    duration = math.max(1, tonumber(duration) or 200)
    local action = SCCompanionBuildAction:new(actor, entity,
        select(1, U().position(square)), select(2, U().position(square)),
        select(3, U().position(square)), entity.north, sprite, duration)
    if not action then return false, "build_action_creation_failed" end
    action.scJobId, action.scActorId, action.scEntity = job.id, actorId(actor), entity
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
    if state.phase ~= "building" then
        local reconciled = BaseWork.reconcileBuildJob(job, actorId(actor))
        if reconciled == true then
            state.phase, state.action, state.entity = "idle", nil, nil
            state.buildSpriteName = nil
            return true, "build_already_present"
        end
    end
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
            local approached, approachReason = SC.Navigation.requestAny(actor, approaches, "walk", workRoute({
                action = "move_to_base_build", targetSquare = square,
                arrivalDistance = 0.8,
            }, true))
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
        nameFallenMarker(job, square, state.buildSpriteName)
        SC.BaseLife.advanceBuildStage(job.id, actorId(actor))
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

-- The game's own shelf label (DisplayCategory) decides first. getCategory()
-- reports "Weapon" for every Build 42 hand weapon, which includes hammers,
-- axes, shovels and even planks, so it cannot tell a work tool or building
-- material from a pistol. Shells, magazines and pills have no telling word
-- in their type names either.
local DISPLAY_CATEGORIES = {
    ammo = "ammunition",
    firstaid = "medical", bandage = "medical",
    tool = "tools", toolweapon = "tools", gardeningweapon = "tools",
    materialweapon = "construction",
    weapon = "weapons", weaponcrafted = "weapons", sportsweapon = "weapons",
    literature = "literature", skillbook = "literature",
    food = "food",
}

-- Hand tools are weapons too, so either shelf is a proper home for them.
local DUAL_USE_DISPLAY = { toolweapon = true, gardeningweapon = true, cookingweapon = true }

local function displayCategory(item)
    return string.lower(tostring(select(1, invoke(item, "getDisplayCategory")) or ""))
end

local function isHandTool(item)
    return DUAL_USE_DISPLAY[displayCategory(item)] == true
        or U().itemHasTag(item, "Hammer") or U().itemHasTag(item, "Saw")
        or U().itemHasTag(item, "Screwdriver")
end

-- Returns the category and whether it is certain. Only the final crafting
-- fallback is a guess.
local function classifyItem(item)
    local itemType = string.lower(U().itemType(item))
    local category = select(1, invoke(item, "getCategory"))
    category = string.lower(tostring(category or ""))
    if SC.FarmWork and type(SC.FarmWork.isFarmingSupply) == "function"
        and SC.FarmWork.isFarmingSupply(item) == true then return "farming", true end
    if SC.BaseLife.isValuableItem(item)
        and #SC.BaseLife.depositStorageRows("valuables") > 0 then
        return "valuables", true
    end
    local display = displayCategory(item)
    local isClothing, clothingKnown = invoke(item, "IsClothing")
    if category == "clothing" or display == "clothing"
        or (clothingKnown and isClothing == true) then
        return "clothing", true
    end
    local shelf = DISPLAY_CATEGORIES[display]
    if shelf == "food" or category == "food" then
        return SC.BaseLife.foodStorageCategory(item), true
    end
    if shelf then return shelf, true end
    if category == "literature" then return "literature", true end
    if string.find(itemType, "water", 1, true) or string.find(itemType, "bottle", 1, true) then return "water", true end
    if string.find(itemType, "bandage", 1, true) or string.find(itemType, "rippedsheet", 1, true)
        or string.find(itemType, "disinfect", 1, true) then return "medical", true end
    if string.find(itemType, "ammo", 1, true) or string.find(itemType, "bullets", 1, true)
        or string.find(itemType, "round", 1, true) then return "ammunition", true end
    -- Tools and building material before the weapon test: the engine counts
    -- both as hand weapons.
    if U().itemHasTag(item, "Hammer") or string.find(itemType, "saw", 1, true)
        or string.find(itemType, "screwdriver", 1, true) then return "tools", true end
    if itemType == "base.log" or string.find(itemType, "plank", 1, true)
        or string.find(itemType, "nails", 1, true)
        or string.find(itemType, "lumber", 1, true) then return "construction", true end
    if category == "weapon" then return "weapons", true end
    return "crafting", false
end

-- Expedition receipts use the same category decision as ordinary camp sorting.
function BaseWork.classifyItem(item)
    return classifyItem(item)
end

-- General and output storage are staging shelves: sorting empties them. A
-- specific shelf keeps an item unless it surely belongs somewhere else, so a
-- hammer in Tools, a shotgun shell in Ammunition or a pill in Medical stays.
local STAGING_CATEGORIES = { general = true, output = true }

local function belongsIn(item, category)
    if STAGING_CATEGORIES[category] then return false end
    local wanted, certain = classifyItem(item)
    if wanted == "food" or wanted == "fresh_food" then
        wanted = SC.BaseLife.foodDepositCategory(item)
    end
    if not certain or wanted == category then return true end
    return (category == "tools" or category == "weapons") and isHandTool(item)
end

local function destinationHasRoom(container, actor, item)
    if SC.WorkTransport and type(SC.WorkTransport.hasRoom) == "function" then
        local ok, room = pcall(SC.WorkTransport.hasRoom, container, actor, item)
        if ok then return room == true end
    end
    local room, roomOk = U().call(container, "hasRoomFor", actor, item)
    return roomOk and room == true
end

-- Every registered destination that can actually take this exact item now.
-- A full store is not a destination; choosing one would strand the cargo.
local function destinationsFor(job, item, actor, sourceId)
    local category = type(job.target) == "table" and job.target.destinationCategory
        or classifyItem(item)
    if category == "food" or category == "fresh_food" then
        category = SC.BaseLife.foodDepositCategory(item)
    end
    local rows = {}
    if U().itemType(item) == "Base.Log" and category == "construction"
        and SC.LogYard and SC.LogYard.select then
        local yard = SC.LogYard.select(actor)
        if yard then rows[#rows + 1] = { destination = yard, container = yard.square } end
    end
    for _, destination in ipairs(SC.BaseLife.depositStorageRows(category)) do
        if destination.id ~= sourceId then
            local container = SC.BaseLife.resolveContainer(destination)
            if container and destinationHasRoom(container, actor, item) then
                rows[#rows + 1] = { destination = destination, container = container }
            end
        end
    end
    return rows
end

-- Floor intake follows the ordinary camp sorter's exact category and capacity
-- rules. It never falls back to General when a dedicated marker is absent.
function BaseWork.floorDestinations(actor, item)
    -- The ordinary sorter leaves valuables on a general shelf until their
    -- dedicated marker exists. A floor intake has no shelf to preserve them
    -- on, so identify the category even when its destination is missing.
    local category = SC.BaseLife.isValuableItem(item)
        and "valuables" or classifyItem(item)
    if category == "food" or category == "fresh_food" then
        category = SC.BaseLife.foodDepositCategory(item)
    end
    local rows = destinationsFor({ type = "sort",
        target = { destinationCategory = category } }, item, actor, nil)
    if #rows > 0 then return rows, category end
    if U().itemType(item) == "Base.Log" and category == "construction"
        and SC.LogYard and SC.LogYard.hasZone and SC.LogYard.hasZone() then
        return {}, category, "floor_storage_unavailable"
    end
    local marked = SC.BaseLife.depositStorageRows(category)
    return {}, category, #marked > 0 and "floor_storage_full"
        or "floor_storage_missing"
end

function BaseWork.destinationForCarItem(actor, item)
    local category = classifyItem(item)
    if category == "food" or category == "fresh_food" then
        category = SC.BaseLife.foodDepositCategory(item)
    end
    local kinds = category == "valuables" and { category }
        or { category, "general", "output" }
    for _, kind in ipairs(kinds) do
        if kind ~= "memorial" then
            for _, storage in ipairs(SC.BaseLife.depositStorageRows(kind)) do
                local container = SC.BaseLife.resolveContainer(storage)
                if container and destinationHasRoom(container, actor, item) then
                    return storage, container
                end
            end
        end
    end
    return nil, nil, "car_unload_storage_full_or_missing"
end

local function findTransfer(job, actor)
    local sourceCategory = (type(job.target) == "table" and job.target.sourceCategory)
        or "general"
    if job.type == "sort" then sourceCategory = nil end
    local matchingStoreFull = false
    for _, source in ipairs(SC.BaseLife.storageRows(sourceCategory, true)) do
        local container = SC.BaseLife.resolveContainer(source)
        if container then
            local items, scanStart = storageItemSlice(container)
            for _, item in ipairs(items) do
                local itemType = U().itemType(item)
                if not BaseWork.choreReserved(item)
                    and not (SC.PersonalItems and SC.PersonalItems.isProtected
                    and SC.PersonalItems.isProtected(item, actor, "base_haul")) then
                    local needsSorting = job.type ~= "sort"
                        or not belongsIn(item, source.category)
                    local rows = needsSorting and destinationsFor(job, item, actor, source.id)
                        or {}
                    if #rows > 0 and sourceItemAvailable(source, itemType) then
                        -- The audit also calls this selector. Leave its selected
                        -- window ready for the worker's first execution tick.
                        storageItemCursors[container] = scanStart
                        return source, container, rows[1].destination, rows[1].container, item
                    elseif needsSorting and #rows == 0
                        and sourceItemAvailable(source, itemType) then
                        local category = type(job.target) == "table"
                            and job.target.destinationCategory or classifyItem(item)
                        if category == "food" or category == "fresh_food" then
                            category = SC.BaseLife.foodDepositCategory(item)
                        end
                        if itemType == "Base.Log" and category == "construction"
                            and SC.LogYard and SC.LogYard.hasZone
                            and SC.LogYard.hasZone() then matchingStoreFull = true end
                        for _, destination in ipairs(SC.BaseLife.depositStorageRows(category)) do
                            if destination.id ~= source.id
                                and SC.BaseLife.resolveContainer(destination) then
                                matchingStoreFull = true
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil, nil,
        matchingStoreFull and "haul_destinations_full" or "no_sortable_supply"
end

local function cargoContainer(actor, cargo)
    local root = U().inventory(actor)
    if U().inventoryContains(root, cargo.item) then return root, "owned" end
    if SC.PersonalItems and type(SC.PersonalItems.ownedBy) == "function" then
        local owned = SC.PersonalItems.ownedBy(cargo.item, actor)
        if owned == true then
            local container = select(1, U().call(cargo.item, "getContainer"))
            if container and U().inventoryContains(container, cargo.item) then
                return container, "owned"
            end
            return nil, "unknown"
        end
        if owned == nil then return nil, "unknown" end
    end
    return nil, "absent"
end

-- Put carried cargo back where it came from, so a blocked job never leaves a
-- worker quietly holding base stock.
local function returnCargo(actor, cargo)
    if type(cargo) ~= "table" or cargo.item == nil then return true end
    local sourceInventory, ownership = cargoContainer(actor, cargo)
    if ownership == "absent" then return true end
    if ownership ~= "owned" then return false, "haul_cargo_owner_unknown" end
    -- A marker removed while the worker was hauling must not cause a silent
    -- transfer into an old container pointer that the player reclaimed.
    local source = cargo.source
    if type(source) ~= "table" or SC.BaseLife.storage(source.id) ~= source then
        return false, "haul_source_marker_missing"
    end
    -- The marker resolves through its persistent object id, so whatever it
    -- resolves to now is still that storage. A chunk reload rebuilds the
    -- object's ItemContainer; comparing against the pointer captured at
    -- withdrawal refused that return for the rest of the session, and with it
    -- every BaseWork.cancel (leaving duty, dismissal, the night pause). Only an
    -- unloaded or containerless marker has to wait.
    local container = SC.BaseLife.resolveContainer(source)
    if container == nil then
        return false, "haul_source_storage_changed"
    end
    if not destinationHasRoom(container, actor, cargo.item) then
        return false, "destination_full"
    end
    local moved, reason
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        moved, reason = SC.WorkTransport.transferVerified(
            sourceInventory, container, cargo.item, actor)
    else
        moved, reason = U().transferItemVerified(sourceInventory, container, cargo.item)
    end
    return moved == true, moved and "haul_cargo_returned"
        or reason or "haul_cargo_return_failed"
end

-- A marked source cannot be removed while a sorter holds its exact item.
-- Destination markers remain editable; the worker can choose another one or
-- return cargo to its still-registered source.
function BaseWork.storageInUse(storageId)
    for actor, state in pairs(states) do
        local cargo = state.cargo
        if type(cargo) == "table" and cargo.sourceId == storageId
            and cargo.item ~= nil then
            local _, ownership = cargoContainer(actor, cargo)
            if ownership ~= "absent" then return true, "sort_cargo_uses_storage" end
        end
    end
    return false
end

local function settleCargo(actor, state)
    if type(state.cargo) ~= "table" then return true end
    local called, returned, reason = pcall(returnCargo, actor, state.cargo)
    if not called or returned ~= true then
        return false, called and reason or "haul_cargo_return_failed"
    end
    state.cargo, state.transfer = nil, nil
    return true
end

local function updateTransfer(actor, state, job)
    -- Cargo from an earlier attempt is still owned by this worker: deliver
    -- that before withdrawing anything else.
    if state.transfer == nil and type(state.cargo) == "table" then
        local cargo = state.cargo
        local sourceInventory, ownership = cargoContainer(actor, cargo)
        if ownership == "unknown" then return false, "haul_cargo_owner_unknown", true end
        if ownership == "owned" and sourceInventory ~= U().inventory(actor) then
            local returned, reason = returnCargo(actor, cargo)
            if returned then state.cargo = nil end
            return false, returned and "haul_cargo_returned" or reason, true
        end
        if ownership == "owned" then
            local rows = destinationsFor(job, cargo.item, actor, cargo.sourceId)
            if #rows > 0 then
                state.transfer = {
                    source = cargo.source, sourceContainer = cargo.sourceContainer,
                    destination = rows[1].destination, destinationContainer = rows[1].container,
                    item = cargo.item, phase = "deposit",
                }
            else
                local returned, reason = returnCargo(actor, cargo)
                if returned then state.cargo = nil end
                return false, returned and "haul_destinations_full"
                    or reason or "haul_cargo_return_failed", true
            end
        else
            state.cargo = nil
        end
    end
    if state.transfer == nil then
        local source, sourceContainer, destination, destinationContainer, item,
            selectionReason = findTransfer(job, actor)
        if not source then return false, selectionReason, true end
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
            jobId = job.id,
        }
    end
    if not U().inventoryContains(U().inventory(actor), transfer.item) then
        local _, ownership = cargoContainer(actor, state.cargo)
        if ownership == "owned" then
            -- Another inventory action put the exact cargo into a carried bag.
            -- Return it through its verified owner instead of reporting it lost.
            local returned, reason = returnCargo(actor, state.cargo)
            if returned then state.cargo, state.transfer = nil, nil end
            return false, returned and "haul_cargo_returned" or reason, true
        end
        if ownership == "unknown" then return false, "haul_cargo_owner_unknown", true end
        state.cargo, state.transfer = nil, nil
        return false, "hauled_item_missing", true
    end
    -- Sorting uses the same approach, visible interaction, capacity check,
    -- marker revalidation and verified transfer as other camp deposits.
    local moved, moveReason = transferToStorage(actor, state, transfer.destination,
        transfer.destinationContainer, transfer.item, true)
    if moved and moveReason ~= "base_supply_returned" then return true, moveReason end
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
        local returned, returnReason = returnCargo(actor, state.cargo)
        if returned then
            state.cargo, state.transfer = nil, nil
            return false, moveReason == "destination_full"
                and "haul_destinations_full" or "haul_cargo_returned", true
        end
        -- The return failure now owns the recovery decision. For example, a
        -- destination marker may be disabled while the source fills too; the
        -- source's capacity blocker must keep this exact cargo retryable.
        return false, returnReason or moveReason or "base_deposit_failed", true
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
    local alreadyFull = BaseWork.reconcileBarricadeJob(job, actorId(actor))
    if alreadyFull == true then return true, "barricade_already_full" end
    local object = type(job.target) == "table" and SC.BaseLife.resolveObject(job.target) or nil
    if not object then return false, "barricade_target_unloaded", true end
    if not SC.Commands or type(SC.Commands.issue) ~= "function" then
        return false, "commands_unavailable", true
    end
    local ok, reason = SC.Commands.issue(actorId(actor), "barricade", {
        object = object, baseJobId = job.id,
        barricadeSide = job.target.barricadeSide,
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
        elseif not ok and reason == "no_treatable_wound" then
            -- Another care path may have changed the dressing since this job
            -- was queued. The work is resolved; retrying cannot improve it.
            SC.BaseLife.completeJob(job.id, actorId(actor), "already_treated")
            return true, "already_treated", false
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

local function updateCleaning(actor, state, job, player, runtime)
    local function abort(reason)
        state.cleanFailureReason = reason or "cleaning_unavailable"
        local returned, why = returnCleaningLoans(actor, state, job)
        if returned == true then
            local failure = state.cleanFailureReason
            state.cleanFailureReason = nil
            return false, failure, true
        end
        if returned == nil then return true, why or "cleaning_return_pending" end
        return false, why or state.cleanFailureReason, true
    end
    if state.cleanFailureReason then return abort(state.cleanFailureReason) end
    local target = type(job.target) == "table" and U().gridSquare(
        job.target.x, job.target.y, job.target.z) or nil
    local stained = target and select(1, U().call(target, "haveStains")) == true
    local nativeActive = SC.NativeActions
        and type(SC.NativeActions.isWorkActive) == "function"
        and SC.NativeActions.isWorkActive(actor) == true
    if not stained and not nativeActive then
        local returned, returnReason = returnCleaningLoans(actor, state, job)
        if returned ~= true then
            return returned == nil, returnReason or "cleaning_return_pending",
                returned == false
        end
        if not target then return abort("cleaning_target_unavailable") end
        SC.BaseLife.completeJob(job.id, actorId(actor),
            state.cleanStartedAt and "cleaned" or "already_clean")
        state.cleanStartedAt = nil
        return true, "cleaned", false, true
    end
    if not target then return abort("cleaning_target_unavailable") end
    if not SC.Downtime or type(SC.Downtime.update) ~= "function" then
        return abort("cleaning_unavailable")
    end
    local quiet = SC.Downtime.peek and SC.Downtime.peek(actor) or nil
    if not (quiet and quiet.active and quiet.active.kind == "clean_base") then
        for _, kind in ipairs({ "tool", "liquid" }) do
            local staged, stageReason, terminal =
                stageCleaningItem(actor, state, job, kind)
            if not staged then
                if terminal == true then return abort(stageReason) end
                return staged == nil, stageReason or "cleaning_supply_pending",
                    false
            end
            if stageReason ~= "cleaning_supply_carried"
                and stageReason ~= "cleaning_personal_supply" then
                return true, stageReason
            end
        end
        local eligible, reason = SC.Downtime.canCleanAt(actor, target)
        if not eligible then return abort(reason or "cleaning_unavailable") end
    end
    state.cleanStartedAt = state.cleanStartedAt or now()
    local handled, reason = SC.Downtime.update(actor, player, runtime,
        "clean_base", target)
    stained = select(1, U().call(target, "haveStains")) == true
    if not stained and (not SC.NativeActions
        or type(SC.NativeActions.isWorkActive) ~= "function"
        or SC.NativeActions.isWorkActive(actor) ~= true) then
        -- Let the next pulse return the exact borrowed objects before the
        -- job disappears from the save and its markers become stale.
        return true, "cleaning_returning_supplies"
    end
    local timedOut = now() - state.cleanStartedAt > 90000
        and not (quiet and quiet.active and quiet.active.kind == "clean_base")
    if timedOut then return abort(reason or "cleaning_timeout") end
    return handled == true, reason or "cleaning_waiting", timedOut
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
        and math.floor(anchor.y) == math.floor(tonumber(core.y) or -1)
        and math.floor(anchor.z or 0) == math.floor(tonumber(core.z) or 0) then
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

-- Decision checks this sparingly while a resident is on an ordinary seated
-- break. Keep the same duty/guard admission as the main work controller when
-- newly queued work can bring that resident back to its job.
function BaseWork.claimDuringAmbientPause(actor)
    if not SC.BaseLife or type(SC.BaseLife.resident) ~= "function"
        or type(SC.BaseLife.claimJob) ~= "function" then return nil end
    local id = actorId(actor)
    local resident = SC.BaseLife.resident(id)
    if not resident or resident.duty ~= true then return nil end
    local guarding = type(SC.BaseLife.guardStatus) == "function"
        and select(1, SC.BaseLife.guardStatus(id, now())) == true
        or type(SC.BaseLife.guardStatus) ~= "function" and resident.role == "guard"
    if guarding and resident.role == "guard" and not namedJobWaiting(id) then
        return nil
    end
    return SC.BaseLife.claimJob(id)
end

BaseWork._guardPostForTests = guardPost

local function clearGuardPatrol(actor, state, reason)
    state.guardPatrolTarget, state.guardPatrolKey = nil, nil
    local navigation = SC.Navigation
    local route = navigation and type(navigation.peek) == "function"
        and navigation.peek(actor) or nil
    -- A named job or quiet activity may already own a different route. Only
    -- release the patrol's own movement when its waypoint is retired.
    if route and route.goalAction == "base_guard_patrol"
        and type(navigation.cancel) == "function" then
        navigation.cancel(actor, reason or "guard_patrol_cancelled")
    end
end

local function guardPatrolKey(base, center)
    local x, y, z = U().position(center)
    local parts = { tostring(base), tostring(base and base.id),
        tostring(x), tostring(y), tostring(z) }
    -- A room-wide mark can change shape without moving its centre. The
    -- compact zone signature invalidates that old patrol as well.
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "guard" or zone.kind == "rally" then
            parts[#parts + 1] = table.concat({ tostring(zone.id), zone.kind,
                tostring(zone.x1), tostring(zone.y1), tostring(zone.x2),
                tostring(zone.y2), tostring(zone.z) }, ":")
        end
    end
    return table.concat(parts, "|")
end

local function guardTargetClear(actor, target)
    return target and SC.BaseLife.isInside(target)
        and SC.Navigation and SC.Navigation.standingSquareClear
        and SC.Navigation.standingSquareClear(actor, target)
        and (not SC.BaseLife.outdoorNightRestricted()
            and not (SC.BaseWatch and SC.BaseWatch.isLeader(actor))
            or SC.BaseLife.isOutdoorSquare(target) == false)
end

local function guardRoutine(actor, state)
    local base = SC.BaseLife.active()
    local center = guardPost(actor)
        or SC.BaseLife.zoneCenter("guard") or SC.BaseLife.zoneCenter("rally")
    if not center or not base then
        clearGuardPatrol(actor, state, "guard_zone_missing")
        return false, "guard_zone_missing"
    end
    local key = guardPatrolKey(base, center)
    if state.guardPatrolKey ~= key then
        clearGuardPatrol(actor, state, "guard_area_changed")
        state.guardPatrolKey, state.nextRoutineAt, state.guardRetryAt = key, 0, nil
    end
    local point = state.guardPatrolTarget
    local target = point and U().gridSquare(point.x, point.y, point.z) or nil
    if point and not guardTargetClear(actor, target) then
        clearGuardPatrol(actor, state, "guard_spot_changed")
        state.guardPatrolKey, state.nextRoutineAt, state.guardRetryAt = key, 0, nil
        target = nil
    end
    if not target then
        local current = now()
        -- A failed route or an unloaded post backs off wherever the guard is.
        if current < (state.guardRetryAt or 0) then return false, "guard_holding" end
        -- The pause between waypoints is for a guard at its post. One pulled
        -- away by an alarm or a short job walks back first.
        if current < (state.nextRoutineAt or 0)
            and U().distance(actor, center) <= 3 then
            return false, "guard_holding"
        end
    end
    local offsets = { { 0, 0 }, { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 } }
    if not target then
        for _ = 1, #offsets do
            state.patrolIndex = ((state.patrolIndex or 0) % #offsets) + 1
            local offset = offsets[state.patrolIndex]
            local candidate = U().gridSquare(center.x + offset[1],
                center.y + offset[2], center.z)
            if guardTargetClear(actor, candidate) then
                target = candidate
                local x, y, z = U().position(target)
                state.guardPatrolTarget = { x = x, y = y, z = z }
                break
            end
        end
    end
    if not target then
        state.guardRetryAt = now() + 5000
        return false, "guard_target_unloaded"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    local handled, reason = SC.Navigation.request(actor, target, "walk", workRoute({
        action = "base_guard_patrol", targetSquare = target,
    }))
    if handled and reason == "arrived" then
        clearGuardPatrol(actor, state, "guard_patrol_complete")
        state.guardPatrolKey, state.guardRetryAt = key, nil
        state.nextRoutineAt = now() + (U().config("baseGuardPatrolIntervalMs") or 30000)
    elseif handled ~= true then
        clearGuardPatrol(actor, state, "guard_patrol_failed")
        state.guardPatrolKey, state.guardRetryAt = key, now() + 5000
    end
    return handled, reason
end

BaseWork._guardRoutineForTests = guardRoutine

local NIGHT_SHELTER_SCAN_BUDGET = 128
local NIGHT_SHELTER_TARGET_LIMIT = 8

local function indoorCampShelter(square)
    return square and SC.BaseLife.isInside(square) == true
        and SC.BaseLife.isOutdoorSquare(square) == false
        and U().isSquareFree(square) == true
end

-- Large and multi-floor camps are surveyed over several updates. A failed
-- search never falls back to an outdoor rally/core square.
local function scanNightShelter(base, state)
    local scan = state.nightShelterScan
    if not scan or scan.baseId ~= base.id then
        scan = { baseId = base.id, zoneIndex = 1 }
        state.nightShelterScan = scan
    end
    local targets, checked = {}, 0
    while checked < NIGHT_SHELTER_SCAN_BUDGET
        and #targets < NIGHT_SHELTER_TARGET_LIMIT do
        local zone = base.zones[scan.zoneIndex]
        if not zone then
            state.nightShelterScan = nil
            return targets, true
        end
        if zone.kind ~= "area" then
            scan.zoneIndex, scan.x, scan.y = scan.zoneIndex + 1, nil, nil
        else
            local x, y = scan.x or zone.x1, scan.y or zone.y1
            local square = U().gridSquare(x, y, zone.z)
            checked = checked + 1
            scan.x, scan.y = x + 1, y
            if scan.x > zone.x2 then scan.x, scan.y = zone.x1, y + 1 end
            if scan.y > zone.y2 then
                scan.zoneIndex, scan.x, scan.y = scan.zoneIndex + 1, nil, nil
            end
            if indoorCampShelter(square) then targets[#targets + 1] = square end
        end
    end
    return targets, false
end

local function returnInsideAtNight(actor, state)
    local base = SC.BaseLife.active()
    if not base then return false, "base_missing" end
    if SC.BaseLife.isOutdoorSquare(actor) == false then
        return false, "already_inside_at_night"
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    local cached = state.nightShelterBaseId == base.id
        and now() < (state.nightShelterRefreshAt or 0)
        and state.nightShelterTargets or nil
    local targets = {}
    if cached then
        for _, square in ipairs(cached) do
            if indoorCampShelter(square) then targets[#targets + 1] = square end
        end
    end
    if #targets == 0 and not (cached and #cached == 0) then
        local complete
        targets, complete = scanNightShelter(base, state)
        if #targets == 0 and not complete then
            return false, "night_shelter_searching"
        end
        state.nightShelterBaseId = base.id
        state.nightShelterTargets = targets
        state.nightShelterRefreshAt = now() + 10000
    end
    if #targets == 0 then return false, "night_shelter_unavailable" end
    local intent = {
        action = "return_to_base", targetSquare = targets[1],
        nightShelter = true,
    }
    if SC.BaseLife.withinWorkReach(actor) then intent = workRoute(intent, true) end
    local handled, reason = SC.Navigation.requestAny(actor, targets, "walk", intent)
    return handled, reason
end

local function sleepBeforeNewJob(actor, player, runtime, job)
    local resting = SC.Downtime and type(SC.Downtime.peek) == "function"
        and SC.Downtime.peek(actor) or nil
    if resting and resting.active and resting.active.kind == "rest_bed"
        and type(SC.Downtime.update) == "function" then
        return SC.Downtime.update(actor, player, runtime, "rest_bed")
    end
    if job or not SC.Downtime or type(SC.Downtime.canPerform) ~= "function"
        or type(SC.Downtime.update) ~= "function"
        or U().characterStatValue(actor, "FATIGUE", 0)
            <= (tonumber(U().config("sleepFatigueThreshold")) or 0.30)
        or SC.Downtime.canPerform(actor, "rest_bed") ~= true then
        return nil
    end
    local handled, reason = SC.Downtime.update(actor, player, runtime, "rest_bed")
    if handled == true or reason == "settling" or reason == "cooldown" then
        return handled == true, reason or "bed_sleep"
    end
    return nil
end

BaseWork._sleepBeforeNewJobForTests = sleepBeforeNewJob

function BaseWork.update(actor, player, runtime)
    local id, state = actorId(actor), stateFor(actor)
    local resident = SC.BaseLife and SC.BaseLife.resident(id) or nil
    if not resident or resident.duty ~= true then
        clearGuardPatrol(actor, state, "not_on_base_duty")
        return false, "not_on_base_duty"
    end
    if not SC.BaseLife.active() then
        clearGuardPatrol(actor, state, "base_missing")
        return false, "base_missing"
    end
    -- A sleeper owns the bed through the whole rest, even after fatigue falls
    -- below the threshold or the base scheduler offers another job.
    local activeRest = SC.Downtime and type(SC.Downtime.peek) == "function"
        and SC.Downtime.peek(actor) or nil
    if activeRest and activeRest.active
        and activeRest.active.kind == "rest_bed"
        and type(SC.Downtime.update) == "function" then
        clearGuardPatrol(actor, state, "guard_resting")
        return SC.Downtime.update(actor, player, runtime, "rest_bed")
    end
    reportBlockedTool(actor, player, state, runtime)
    local job = SC.BaseLife.jobFor(id)
    if job then clearGuardPatrol(actor, state, "guard_job_assigned") end
    -- A corpse in tow belongs to a production haul. Without that job in hand
    -- (blocked, released or finished), the body goes down before rest,
    -- downtime or another chore can walk off with it.
    if not (job and job.type == "production") and SC.Production
        and type(SC.Production.releaseDrag) == "function" then
        SC.Production.releaseDrag(actor, "base_job_without_haul")
    end
    if SC.BaseWatch and SC.BaseWatch.isLeader(actor) then
        if job and SC.BaseLife.outdoorJob(job) then
            local cancelled, reason = BaseWork.cancel(actor, "base_watch_indoor_duty")
            if cancelled ~= true then return false, reason end
            if job.reservedBy == id then
                SC.BaseLife.releaseJob(job.id, id, "base_watch_indoor_duty")
            end
            state, job = stateFor(actor), nil
        end
        if SC.Fishing and SC.Fishing.active(actor) then
            SC.Fishing.cancel(actor, "base_watch_indoor_duty")
        end
        if SC.BaseLife.isOutdoorSquare(actor) == true then
            return returnInsideAtNight(actor, state)
        end
    end
    if SC.BaseLife.outdoorNightRestricted() then
        if SC.Fishing and SC.Fishing.active(actor) then
            SC.Fishing.cancel(actor, "outdoor_night")
        end
        if job and job.type ~= "farm" and SC.BaseLife.outdoorJob(job) then
            local cancelled, cancelReason = BaseWork.cancel(actor, "outdoor_night")
            if cancelled ~= true then return false, cancelReason end
            if job.reservedBy == id then
                SC.BaseLife.releaseJob(job.id, id, "outdoor_night")
            end
            state, job = stateFor(actor), nil
        end
        local tendingHeat = job and job.type == "cook" and SC.ChefWork
            and type(SC.ChefWork.mustTendHeat) == "function"
            and SC.ChefWork.mustTendHeat(actor, job) == true
        if (not job or job.type ~= "farm") and not tendingHeat
            and SC.BaseLife.isOutdoorSquare(actor) == true then
            return returnInsideAtNight(actor, state)
        end
    end
    if not job and resident.role == "angler" and SC.Fishing
        and type(SC.Fishing.update) == "function"
        and not SC.BaseLife.outdoorNightRestricted() then
        -- Fishing never runs out the way a job queue can, so a tired angler
        -- sleeps first like any worker before new work. With outdoor night
        -- work allowed it otherwise never went to bed.
        local sleeping, sleepReason = sleepBeforeNewJob(actor, player, runtime, nil)
        if sleeping ~= nil then
            if SC.Fishing.active(actor) then SC.Fishing.cancel(actor, "angler_resting") end
            return sleeping, sleepReason
        end
        local handled, reason = SC.Fishing.update(actor, "camp", nil, player,
            type(runtime) == "table" and (runtime.snapshot
                or (type(runtime.senses) == "table" and runtime.senses.current))
                or nil)
        if handled or (reason ~= "fishing_zone_missing"
            and reason ~= "fishing_rod_missing"
            and reason ~= "fishing_bait_missing"
            and reason ~= "fishing_engine_cooldown"
            and reason ~= "no_fishing_water") then
            return handled, reason
        end
    elseif SC.Fishing and SC.Fishing.active(actor) then
        SC.Fishing.cancel(actor, "camp_fishing_paused")
    end
    if not SC.BaseLife.isInside(actor) then
        -- Only jobs admitted by BaseLife may continue in the bounded reach
        -- band; other workers return to the rally point first.
        local reachable = type(SC.BaseLife.withinWorkReach) == "function"
            and SC.BaseLife.withinWorkReach(actor) == true
        if reachable and not job then job = select(1, SC.BaseLife.claimJob(id)) end
        local workingOutside = reachable and ((job
            and type(SC.BaseLife.jobAllowsWorkReach) == "function"
            and SC.BaseLife.jobAllowsWorkReach(job) == true)
            or (not job and resident.role == "angler"
                and SC.BaseLife.zoneCenter("fishing") ~= nil))
        local storageAccess = reachable and job
            and type(SC.BaseLife.atStorageAccess) == "function"
            and SC.BaseLife.atStorageAccess(actor) == true
        if not workingOutside and not storageAccess then
            local target = SC.BaseLife.zoneCenter("rally") or SC.BaseLife.active().core
            local square = U().loadedSquare(target)
            if not square then return false, "base_unloaded" end
            if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
                return false, "navigation_unavailable"
            end
            local intent = {
                action = "return_to_base", targetSquare = square,
            }
            if reachable then intent = workRoute(intent, true) end
            return SC.Navigation.request(actor, square, "walk", intent)
        end
    end
    -- Finish a job already in hand, then let a tired resident sleep before
    -- claiming another one. Otherwise the endless base queue always wins over
    -- Downtime and beds are only used when there is no work at all.
    -- Some jobs keep their lease indefinitely. An exhausted worker may pause
    -- one only after a real, reachable bed has been found; cancel settles any
    -- carried cargo and loans before the job is released for later pickup.
    if job and U().characterStatValue(actor, "FATIGUE", 0)
            >= (tonumber(U().config("needsFatigueEmergency")) or 0.82)
        and now() >= (state.nextSleepProbeAt or 0)
        and SC.Downtime and type(SC.Downtime.canPerform) == "function" then
        state.nextSleepProbeAt = now() + 5000
        if SC.Downtime.canPerform(actor, "rest_bed") == true then
            local cancelled = BaseWork.cancel(actor, "exhausted_sleep")
            if cancelled == true then
                if job.reservedBy == id then
                    SC.BaseLife.releaseJob(job.id, id, "exhausted_sleep")
                end
                state, job = stateFor(actor), nil
            end
        end
    end
    local sleeping, sleepReason = sleepBeforeNewJob(actor, player, runtime, job)
    if sleeping ~= nil then return sleeping, sleepReason end
    local activeGuard
    if type(SC.BaseLife.guardStatus) == "function" then
        activeGuard = select(1, SC.BaseLife.guardStatus(id, now())) == true
    else
        activeGuard = resident.role == "guard"
    end
    if not activeGuard then clearGuardPatrol(actor, state, "guard_shift_ended") end
    -- A watched camp leader gets an occasional social pause between jobs.
    -- Keep the visit in Downtime so its navigation, supervisor ownership and
    -- danger cancellation follow the same rules as every quiet activity.
    local visitState = SC.Downtime and type(SC.Downtime.peek) == "function"
        and SC.Downtime.peek(actor) or nil
    local activeQuiet = visitState and visitState.active
    local activeVisit = activeQuiet and activeQuiet.kind == "leader_check_in"
    if job and activeQuiet
        and not (job.type == "clean" and activeQuiet.kind == "clean_base")
        and type(SC.Downtime.cancel) == "function" then
        SC.Downtime.cancel(actor, "base_job_assigned")
    elseif not job and activeQuiet
        and SC.Downtime and type(SC.Downtime.update) == "function" then
        clearGuardPatrol(actor, state, "guard_quiet_activity")
        -- Once a quiet action owns the actor, let it finish before the next
        -- queue claim. A fresh base job used to strand an active lookout.
        return SC.Downtime.update(actor, player, runtime,
            activeQuiet.kind == "leader_check_in" and "leader_check_in" or nil)
    end
    local base = SC.BaseLife.active()
    if not job and not activeGuard and base and base.settings
        and base.settings.routines ~= false
        and SC.BaseWatch and SC.BaseWatch.isLeader(actor)
        and SC.Downtime and type(SC.Downtime.canPerform) == "function"
        and type(SC.Downtime.update) == "function"
        and (activeVisit or SC.Downtime.canPerform(actor, "leader_check_in") == true) then
        local handled, reason = SC.Downtime.update(actor, player, runtime,
            "leader_check_in")
        if handled or reason == "settling" or reason == "cooldown" then
            return true, reason or "leader_check_in"
        end
    end
    -- A guard on shift keeps watch instead of wandering off to generic chores;
    -- only a job left for it by name pulls it away.
    if not job and resident.role == "chef" and SC.ChefWork
        and type(SC.ChefWork.ensureAutomaticJob) == "function" then
        SC.ChefWork.ensureAutomaticJob(actor, resident)
    end
    if not job and not activeGuard and base and base.settings
        and base.settings.routines ~= false
        and SC.Downtime and type(SC.Downtime.canPerform) == "function"
        and type(SC.Downtime.update) == "function" then
        -- The queue can be permanently populated. Offer quiet activities
        -- between jobs at a sparse per-resident cadence, never mid-job.
        -- Every third pause favors a lookout so gear checks and seating do
        -- not permanently outscore it.
        if state.nextQuietAt == nil then
            local spread = 0
            for index = 1, #tostring(id) do
                spread = (spread + string.byte(tostring(id), index)) % 120000
            end
            state.nextQuietAt = now() + 180000 + spread
        end
        if now() >= state.nextQuietAt then
            local lookout = (state.quietPasses or 0) % 3 == 0
                and SC.Downtime.canPerform(actor, "window_watch") == true
            local handled, reason = SC.Downtime.update(actor, player,
                runtime, lookout and "window_watch" or nil)
            if handled then
                state.quietPasses = (state.quietPasses or 0) + 1
                state.nextQuietAt = now() + 480000
            elseif reason ~= "settling" and reason ~= "cooldown" then
                state.nextQuietAt = now() + 90000
            end
            if handled or reason == "settling" or reason == "cooldown" then
                return true, reason or "base_downtime"
            end
        end
    end
    if not job and (not (activeGuard and resident.role == "guard") or namedJobWaiting(id)) then
        job = select(1, SC.BaseLife.claimJob(id))
    end
    if job then clearGuardPatrol(actor, state, "guard_job_assigned") end
    if not job then
        if not activeGuard and SC.LogYard
            and type(SC.LogYard.updateBundle) == "function"
            and not SC.BaseLife.outdoorNightRestricted() then
            if state.nextLogYardAt == nil or now() >= state.nextLogYardAt then
                state.nextLogYardAt = now() + 30000
                local handled, reason = SC.LogYard.updateBundle(actor)
                if handled then
                    if reason ~= "log_yard_bundled" then state.nextLogYardAt = now() + 2000 end
                    return true, reason
                end
            end
        end
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
    -- Base duty can win while an opportunistic scavenger still owns its
    -- approach or loot pose. Release that owner's reservation/visual first;
    -- a pending handoff keeps this lease instead of counting a job failure.
    if SC.Encounter and type(SC.Encounter.cancelScavenge) == "function" then
        local released, why = SC.Encounter.cancelScavenge(actor, "base_job_assigned")
        if released ~= true then
            SC.BaseLife.touchJob(job.id, id)
            return true, why or "base_scavenge_handoff_pending"
        end
    end
    if state.jobId ~= job.id then
        if SC.FloorSort and type(SC.FloorSort.pause) == "function" then
            local released, why = SC.FloorSort.pause(actor, nil, "base_job_changed")
            if released ~= true then
                SC.BaseLife.touchJob(job.id, id)
                return true, why or "floor_visual_release_pending"
            end
        end
        state.jobId, state.phase, state.action, state.transfer = job.id, "idle", nil, nil
        state.visualAt, state.requirementsReady, state.cleanStartedAt = nil, nil, nil
        state.cleanFailureReason, state.floorCandidate = nil, nil
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
    elseif job.type == "cook" then
        if not SC.ChefWork or type(SC.ChefWork.update) ~= "function" then
            handled, reason, terminal = false, "chef_work_unavailable", true
        else
            local completed
            handled, reason, terminal, completed = SC.ChefWork.update(actor, state, job, player)
            if completed then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId = nil
                return true, reason
            end
        end
    elseif job.type == "clean" then
        local completed
        handled, reason, terminal, completed = updateCleaning(actor,
            state, job, player, runtime)
        if completed then
            state.jobId = nil
            return true, reason
        end
    elseif job.type == "unload_vehicle" then
        if not SC.VehicleUnload or type(SC.VehicleUnload.update) ~= "function" then
            handled, reason, terminal = false, "vehicle_unload_unavailable", true
        else
            local complete
            handled, reason, terminal, complete = SC.VehicleUnload.update(actor, state, job)
            if complete then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId = nil
                return true, reason
            end
        end
    elseif job.type == "refuel_vehicle" then
        if not SC.VehicleRefuel or type(SC.VehicleRefuel.update) ~= "function" then
            handled, reason, terminal = false, "vehicle_refuel_unavailable", true
        else
            local complete
            handled, reason, terminal, complete = SC.VehicleRefuel.update(actor, state, job)
            if complete then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId = nil
                return true, reason
            end
        end
    elseif job.type == "refuel_generator" then
        if not SC.GeneratorRefuel or type(SC.GeneratorRefuel.update) ~= "function" then
            handled, reason, terminal = false, "generator_refuel_unavailable", true
        else
            local complete
            handled, reason, terminal, complete = SC.GeneratorRefuel.update(actor, state, job)
            if complete then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId = nil
                return true, reason
            end
        end
    elseif job.type == "inflate_tires" or job.type == "wash_vehicle" then
        if not SC.VehicleUpkeep or type(SC.VehicleUpkeep.update) ~= "function" then
            handled, reason, terminal = false, "vehicle_upkeep_unavailable", true
        else
            local complete
            handled, reason, terminal, complete = SC.VehicleUpkeep.update(actor, state, job)
            if complete then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId = nil
                return true, reason
            end
        end
    elseif job.type == "sort_floor" then
        if not SC.FloorSort or type(SC.FloorSort.update) ~= "function" then
            handled, reason, terminal = false, "floor_sort_unavailable", true
        else
            local completed
            handled, reason, terminal, completed = SC.FloorSort.update(actor, state, job)
            if completed then
                SC.BaseLife.completeJob(job.id, id, reason)
                state.jobId, state.floorCandidate = nil, nil
                return true, reason
            end
        end
    elseif job.type == "haul" or job.type == "sort" or job.type == "fetch" then
        handled, reason, terminal = updateTransfer(actor, state, job)
    else
        handled, reason, terminal = updateChore(actor, state, job, player, runtime)
    end
    if terminal then
        if job.type == "sort_floor" and SC.FloorSort
            and type(SC.FloorSort.pause) == "function" then
            local released, why = SC.FloorSort.pause(actor, job, "floor_job_blocked")
            if released ~= true then
                SC.BaseLife.touchJob(job.id, id)
                return true, why or "floor_visual_release_pending"
            end
        end
        local uncertainChef = job.type == "cook" and (reason == "chef_restart_needs_recovery"
            or string.find(tostring(reason or ""), "receipt", 1, true) ~= nil
            or string.find(tostring(reason or ""), "outcome_unknown", 1, true) ~= nil
            or string.find(tostring(reason or ""), "chef_native", 1, true) ~= nil
            or reason == "chef_heating_receipt_missing")
        local uncertainRefuel = (job.type == "refuel_vehicle"
                or job.type == "refuel_generator"
                or job.type == "inflate_tires" or job.type == "wash_vehicle")
            and (string.find(tostring(reason or ""), "uncertain", 1, true) ~= nil
                or string.find(tostring(reason or ""), "unreadable", 1, true) ~= nil
                or string.find(tostring(reason or ""), "missing", 1, true) ~= nil)
        local retryMs = (uncertainChef or uncertainRefuel)
            and 3600000 or (U().config("baseJobRetryMs") or 10000)
        SC.BaseLife.blockJob(job.id, id, reason, retryMs)
        if SC.Dialogue and type(SC.Dialogue.missingToolKind) == "function"
            and type(SC.Dialogue.requestMissingTool) == "function" then
            local tool = SC.Dialogue.missingToolKind(reason)
            if tool then
                state.pendingToolRequest = {
                    jobId = job.id, reason = reason, kind = tool, createdAt = now(),
                }
                reportBlockedTool(actor, player, state, runtime)
            end
        end
        state.jobId, state.phase, state.action, state.transfer = nil, "idle", nil, nil
        state.floorCandidate = nil
        state.cleanFailureReason = nil
        -- A blocked job forgets its selection, never the cargo it still owns.
    elseif handled then
        if (reason == "car_item_stored" or reason == "floor_item_stored"
            or reason == "floor_item_discarded")
            and SC.BaseLife.noteJobStorageProgress then
            SC.BaseLife.noteJobStorageProgress(job.id, id)
        end
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

local function maintenanceResidents()
    if type(SC.BaseLife.dutyResidentIds) ~= "function" then
        return SC.BaseLife.summary().residentRows or {}
    end
    local rows = {}
    for _, id in ipairs(SC.BaseLife.dutyResidentIds()) do rows[#rows + 1] = { id = id, duty = true } end
    return rows
end

local function auditMedical(base, remainingBudget, scan)
    scan.rows = scan.rows or maintenanceResidents()
    scan.index = scan.index or 1
    while scan.index <= #scan.rows do
        if not maintenanceBudget(remainingBudget) then return false, "medical_audit_pending", true end
        local resident = scan.rows[scan.index]
        scan.index = scan.index + 1
        local id = resident.id
        if resident.duty == true and not openJob(base, "replace_bandage", id) then
            local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(id) or nil
            local actor = type(record) == "table" and (record.actor or record) or nil
            local medical
            if actor and SC.Medical and type(SC.Medical.assess) == "function" then
                local ok, value = pcall(SC.Medical.assessCached or SC.Medical.assess, actor)
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

local function auditSorting(base, remainingBudget, scan)
    if not scan.floorChecked and SC.FloorSort and type(SC.FloorSort.audit) == "function" then
        scan.floorChecked = true
        local queued, result = SC.FloorSort.audit(base)
        if queued then return queued, result end
    end
    if openJob(base, "sort") then return false, "sorting_already_queued" end
    if #SC.BaseLife.storageRows(nil, true) == 0 then
        return false, "sorting_source_missing"
    end
    scan.categories = scan.categories or {}
    if scan.categoryIndex == nil then
        for category in pairs(SC.BaseLife.STORAGE_CATEGORIES) do scan.categories[#scan.categories + 1] = category end
        scan.categoryIndex, scan.destinations = 1, 0
    end
    while scan.categoryIndex <= #scan.categories do
        if not maintenanceBudget(remainingBudget) then return false, "sorting_audit_pending", true end
        local category = scan.categories[scan.categoryIndex]
        scan.categoryIndex = scan.categoryIndex + 1
        if category ~= "general" and #SC.BaseLife.depositStorageRows(category) > 0 then
            scan.destinations = scan.destinations + 1
        end
    end
    if scan.destinations == 0 then return false, "sorted_storage_missing" end
    local actionable = false
    scan.rows = scan.rows or maintenanceResidents()
    scan.index = scan.index or 1
    while scan.index <= #scan.rows do
        if not maintenanceBudget(remainingBudget) then return false, "sorting_audit_pending", true end
        local resident = scan.rows[scan.index]
        scan.index = scan.index + 1
        if resident.duty == true then
            local record = SC.Registry and SC.Registry.byId
                and SC.Registry.byId(resident.id) or nil
            if record and record.actor then
                local source, _, _, _, _, reason = findTransfer(
                    { type = "sort" }, record.actor)
                if source ~= nil then actionable = true break end
                if reason == "haul_destinations_full" then scan.matchingStoreFull = true end
            end
        end
    end
    if not actionable and not scan.matchingStoreFull then
        return false, "no_sortable_supply"
    end
    return SC.BaseLife.enqueueJob({ type = "sort", priority = 2 })
end

local function auditRoutine(base, remainingBudget, scan)
    if now() < nextRoutineJobAt then return false, "routine_not_due" end
    scan.rows = scan.rows or maintenanceResidents()
    scan.desiredIndex, scan.index = scan.desiredIndex or 1, scan.index or 1
    while scan.desiredIndex <= 2 do
        local desired = ({ "craft_supply", "repair" })[scan.desiredIndex]
        if not openJob(base, desired)
            and (desired ~= "craft_supply" or #SC.BaseLife.depositStorageRows("output") > 0) then
            while scan.index <= #scan.rows do
                if not maintenanceBudget(remainingBudget) then return false, "routine_audit_pending", true end
                local resident = scan.rows[scan.index]
                scan.index = scan.index + 1
                if resident.duty == true then
                    local record = SC.Registry and SC.Registry.byId
                        and SC.Registry.byId(resident.id) or nil
                    local actor = record and record.actor or nil
                    if actor and SC.Downtime and type(SC.Downtime.canPerform) == "function"
                        and SC.Downtime.canPerform(actor, desired) == true then
                        nextRoutineJobAt = now() + 60000
                        return SC.BaseLife.enqueueJob({
                            type = desired, priority = 1, assignedId = resident.id,
                        })
                    end
                end
            end
        end
        scan.desiredIndex, scan.index = scan.desiredIndex + 1, 1
    end
    nextRoutineJobAt = now() + 60000
    return false, "no_actionable_routine"
end

local function auditCleaning(base, remainingBudget, scan)
    for _, job in ipairs(base.jobs or {}) do
        if job.type == "clean" and job.state ~= "completed"
            and job.state ~= "cancelled" then
            return false, "cleaning_order_active"
        end
    end
    local zones = {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" then zones[#zones + 1] = zone end
    end
    if #zones == 0 then return false, "cleaning_area_missing" end
    local cursor = cleaningScan
    if not cursor or cursor.baseId ~= base.id
        or cursor.zoneCount ~= #zones then
        cursor = { baseId = base.id, zoneCount = #zones, index = 1,
            x = zones[1].x1, y = zones[1].y1 }
        cleaningScan = cursor
    end
    scan.cleanRemaining = scan.cleanRemaining or 96
    while scan.cleanRemaining > 0 do
        if not maintenanceBudget(remainingBudget) then return false, "cleaning_audit_pending", true end
        scan.cleanRemaining = scan.cleanRemaining - 1
        local zone = zones[cursor.index]
        local square = U().gridSquare(cursor.x, cursor.y, zone.z)
        cursor.x = cursor.x + 1
        if cursor.x > zone.x2 then cursor.x, cursor.y = zone.x1, cursor.y + 1 end
        if cursor.y > zone.y2 then
            cursor.index = cursor.index % #zones + 1
            cursor.x, cursor.y = zones[cursor.index].x1,
                zones[cursor.index].y1
        end
        if square and select(1, U().call(square, "haveStains")) == true then
            local queued, job = SC.BaseLife.requestCleaning(square)
            if queued then return true, job end
            if job == "cleaning_supplies_missing"
                or job == "cleaning_worker_missing" then
                return false, job
            end
        end
    end
    return false, "no_actionable_stain"
end

local function auditMaintenanceStep(player, remainingBudget, scan)
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base then return false, "base_missing" end
    -- Farming participates in the same bounded round-robin as every other
    -- maintenance family. A productive field must not starve bandages,
    -- sorting, routines, or barricade inspection indefinitely.
    if auditPhase == 1 then
        if SC.FarmWork and type(SC.FarmWork.audit) == "function" then
            return SC.FarmWork.audit(base, now())
        end
        return false, "farm_audit_unavailable"
    end
    if auditPhase == 2 then return auditMedical(base, remainingBudget, scan) end
    local settings = base.settings or {}
    if auditPhase == 3 then
        if settings.autoMaintenance == false or settings.workload == "essential" then
            return false, "automatic_sorting_disabled"
        end
        return auditSorting(base, remainingBudget, scan)
    end
    if auditPhase == 4 then
        if settings.routines == false or settings.workload ~= "continuous" then
            return false, "continuous_routines_disabled"
        end
        return auditRoutine(base, remainingBudget, scan)
    end
    if auditPhase == 5 and settings.autoMaintenance ~= false then
        local queued, job, pending = auditCleaning(base, remainingBudget, scan)
        if pending then return false, job, true end
        if queued then return true, job end
    end
    if auditPhase == 6 then
        if type(SC.BaseLife.auditRoleProduction) == "function" then
            return SC.BaseLife.auditRoleProduction()
        end
        return false, "role_production_unavailable"
    end
    if auditPhase == 7 then
        if settings.unloadCarInventory ~= true then
            return false, "automatic_car_unloading_disabled"
        end
        if SC.VehicleUnload and type(SC.VehicleUnload.audit) == "function" then
            return SC.VehicleUnload.audit()
        end
        return false, "vehicle_unload_unavailable"
    end
    if auditPhase == 8 then
        if SC.VehicleRefuel and type(SC.VehicleRefuel.audit) == "function" then
            return SC.VehicleRefuel.audit()
        end
        return false, "vehicle_refuel_unavailable"
    end
    if auditPhase == 9 then
        if SC.GeneratorRefuel and type(SC.GeneratorRefuel.audit) == "function" then
            return SC.GeneratorRefuel.audit()
        end
        return false, "generator_refuel_unavailable"
    end
    if auditPhase == 10 then
        if SC.VehicleUpkeep and type(SC.VehicleUpkeep.audit) == "function" then
            return SC.VehicleUpkeep.audit()
        end
        return false, "vehicle_upkeep_unavailable"
    end
    local maintainerId
    for _, id in ipairs(SC.BaseLife.dutyResidentIds()) do
        local resident = SC.BaseLife.resident(id)
        if resident and resident.role == "maintainer" then
            maintainerId = id
            break
        end
    end
    if settings.autoMaintenance == false and maintainerId == nil then
        return false, "automatic_maintenance_disabled"
    end
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
                type = "barricade", priority = 4, assignedId = maintainerId,
                target = {
                    x = target.x, y = target.y, z = target.z,
                    objectIndex = target.objectIndex, maintenanceId = target.id,
                },
            })
        end
    end
    return false, "maintenance_not_due"
end

function BaseWork.auditMaintenance(player, remainingBudget)
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base then maintenanceAudit = nil return false, "base_missing" end
    local scan = maintenanceAudit
    if not scan or scan.base ~= base then
        scan = { base = base, stage = "family" }
        maintenanceAudit = scan
        auditPhase = (auditPhase % 10) + 1
        if SC.WorkTransport and type(SC.WorkTransport.recoverPending) == "function" then
            pcall(SC.WorkTransport.recoverPending, U().config("workRecoveryPerPulse") or 2)
        end
    end
    -- Recovery precedes optional audits, but at most once per second during
    -- continuations. Re-arming one job yields this frame and preserves the
    -- family cursor, so recurrent blocked work cannot starve every family.
    if type(SC.BaseLife.auditJobRecovery) == "function"
        and now() >= (scan.nextRecoveryAt or 0) then
        scan.nextRecoveryAt = now() + 1000
        local recovered, reason = SC.BaseLife.auditJobRecovery()
        if recovered then return true, reason, true end
    end
    if not maintenanceBudget(remainingBudget) then
        if SC.Performance and SC.Performance.count then SC.Performance.count("base_maintenance_yield") end
        return false, "base_maintenance_pending", true
    end
    if scan.stage == "family" then
        local queued, reason, pending = auditMaintenanceStep(player, remainingBudget, scan)
        if pending then
            if SC.Performance and SC.Performance.count then SC.Performance.count("base_maintenance_yield") end
            return queued, reason, true
        end
        scan.queued, scan.reason, scan.stage = queued, reason, "operations"
        if SC.Performance and SC.Performance.count then SC.Performance.count("base_maintenance_phase_" .. auditPhase) end
    end
    if type(SC.BaseLife.auditOperations) == "function" then
        local _, _, pending = SC.BaseLife.auditOperations(false,
            remainingBudget or function() return math.huge end)
        if pending then return scan.queued == true, "base_operations_pending", true end
    end
    maintenanceAudit = nil
    return scan.queued == true, scan.reason, false
end

function BaseWork.cancel(actor, reason)
    local state = states[actor]
    if SC.FloorSort and type(SC.FloorSort.cancelActor) == "function" then
        local okay, why = SC.FloorSort.cancelActor(actor)
        if okay ~= true then return false, why or "floor_sort_cancel_failed" end
    end
    -- Do this before releasing the job or cancelling another subsystem. A
    -- failed exact return leaves the receipt, worker and lease intact.
    if state then
        local floorJob = state.jobId and SC.BaseLife.job(state.jobId) or nil
        if floorJob and floorJob.type == "sort_floor" then
            local okay, why = SC.FloorSort and SC.FloorSort.cancel(actor, floorJob)
            if okay ~= true then return false, why or "floor_sort_cancel_failed" end
        end
        local settled, cargoReason = settleCargo(actor, state)
        if settled ~= true then return false, cargoReason end
        local job = state.jobId and SC.BaseLife.job(state.jobId) or nil
        if job and job.type == "clean" then
            local quiet = SC.Downtime and SC.Downtime.peek
                and SC.Downtime.peek(actor) or nil
            if quiet and quiet.active and quiet.active.kind == "clean_base" then
                local stopped, why = SC.Downtime.cancel(actor,
                    reason or "base_work_cancelled")
                if stopped ~= true then return false, why or "cleaning_busy" end
            end
            local returned, why = returnCleaningLoans(actor, state, job, true)
            if returned ~= true then return false, why or "cleaning_return_pending" end
        end
        local fuelWork = job and (job.type == "unload_vehicle" and SC.VehicleUnload
            or job.type == "refuel_vehicle" and SC.VehicleRefuel
            or job.type == "refuel_generator" and SC.GeneratorRefuel
            or (job.type == "inflate_tires" or job.type == "wash_vehicle")
                and SC.VehicleUpkeep) or nil
        if fuelWork then
            local returned, returnReason = fuelWork.cancel(actor, job)
            if returned ~= true then return false, returnReason end
        end
    end
    if SC.ChefWork and type(SC.ChefWork.cancelActor) == "function" then
        local cancelled, cancelReason = SC.ChefWork.cancelActor(actor,
            reason or "base_work_cancelled")
        if cancelled ~= true then return false, cancelReason end
    end
    if SC.Fishing and type(SC.Fishing.cancel) == "function" then
        SC.Fishing.cancel(actor, reason or "base_work_cancelled")
    end
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
    if state.action then
        local cancelled, cancelReason = cancelBuildAction(actor, state,
            reason or "base_work_cancelled")
        if cancelled ~= true then return false, cancelReason end
    end
    if state.jobId then SC.BaseLife.releaseJob(state.jobId, id, reason or "base_work_cancelled") end
    if state.visualAt ~= nil and SC.NativeActions
        and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "base_work_cancelled")
    end
    clearGuardPatrol(actor, state, reason or "base_work_cancelled")
    states[actor] = nil
    return true
end

-- BaseLife calls this before deleting a build row, so cancellation cannot
-- report success while the exact accepted native action is still executable.
function BaseWork.cancelJob(jobId, ownerId, reason)
    local unloadJob = SC.BaseLife and SC.BaseLife.job(jobId) or nil
    if unloadJob and unloadJob.type == "sort_floor" then
        local worker = ownerId or unloadJob.assignedId
        local actor = worker and U().resolveActor(worker) or nil
        local state = actor and states[actor] or nil
        if not actor then
            for candidate, candidateState in pairs(states) do
                if candidateState.jobId == jobId then
                    actor, state = candidate, candidateState
                    break
                end
            end
        end
        if not SC.FloorSort or type(SC.FloorSort.cancel) ~= "function" then
            return false, "floor_sort_cancel_unavailable"
        end
        local cancelled, why = SC.FloorSort.cancel(actor, unloadJob)
        if cancelled ~= true then return false, why end
        if state and state.jobId == jobId then
            if SC.Navigation and type(SC.Navigation.cancel) == "function" then
                SC.Navigation.cancel(actor, reason or "floor_sort_cancelled")
            end
            if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
                SC.NativeActions.stopDirect(actor)
            else U().stop(actor) end
            state.jobId, state.floorCandidate, state.visualAt = nil, nil, nil
            state.phase = "idle"
        end
        return true, why or "floor_sort_cancelled"
    end
    if unloadJob and unloadJob.type == "clean" then
        local workerId = ownerId or unloadJob.assignedId
        local actor = workerId and U().resolveActor(workerId) or nil
        if not actor and unloadJob.target and unloadJob.target.cleanLoans then
            if not BaseWork.workerUnregistered(workerId) then
                return false, "cleaning_worker_unavailable" end
            unloadJob.target.cleanLoans, unloadJob.assignedId = nil, nil
        end
        local quiet = actor and SC.Downtime and SC.Downtime.peek
            and SC.Downtime.peek(actor) or nil
        if quiet and quiet.active and quiet.active.kind == "clean_base" then
            local cancelled, why = SC.Downtime.cancel(actor,
                reason or "base_job_cancelled")
            if cancelled ~= true then return false, why or "cleaning_busy" end
        end
        local state = actor and states[actor] or nil
        if actor then
            local returned, why = returnCleaningLoans(actor, state or {},
                unloadJob, true)
            if returned ~= true then return false, why or "cleaning_return_pending" end
        end
        if state and state.jobId == jobId then states[actor] = nil end
        return true, "cleaning_cancelled"
    end
    if unloadJob and (unloadJob.type == "unload_vehicle"
        or unloadJob.type == "refuel_vehicle"
        or unloadJob.type == "refuel_generator"
        or unloadJob.type == "inflate_tires"
        or unloadJob.type == "wash_vehicle") then
        local worker = ownerId or unloadJob.assignedId
        local owner = worker and U().resolveActor(worker) or nil
        local fuelWork = unloadJob.type == "unload_vehicle"
            and SC.VehicleUnload or unloadJob.type == "refuel_vehicle"
            and SC.VehicleRefuel or unloadJob.type == "refuel_generator"
            and SC.GeneratorRefuel or SC.VehicleUpkeep
        if fuelWork and type(fuelWork.cancel) == "function" then
            return fuelWork.cancel(owner, unloadJob)
        end
        return false, "fuel_work_cancel_unavailable"
    end
    local actor = U().resolveActor(ownerId)
    local state = actor and states[actor] or nil
    if ownerId == nil then
        -- A terminal transfer keeps exact cargo after BaseLife releases its
        -- lease. Find that receipt even though reservedBy is now nil.
        for candidate, candidateState in pairs(states) do
            if type(candidateState.cargo) == "table"
                and candidateState.cargo.jobId == jobId then
                actor, state = candidate, candidateState
                break
            end
        end
    end
    if not state then
        return ownerId == nil, ownerId == nil and "base_job_not_started"
            or "base_job_owner_state_missing"
    end
    if state.jobId ~= jobId
        and not (type(state.cargo) == "table" and state.cargo.jobId == jobId) then
        return false, "base_job_owner_state_mismatch"
    end
    local settled, cargoReason = settleCargo(actor, state)
    if settled ~= true then return false, cargoReason end
    if state.jobId ~= jobId then
        -- A later transfer may have claimed this worker while it was still
        -- carrying the old job's item. Its selection can be rebuilt next tick.
        if state.jobId == nil then states[actor] = nil end
        return true, "base_job_cargo_returned"
    end
    local cancelled, cancelReason = cancelBuildAction(actor, state,
        reason or "base_job_cancelled")
    if cancelled ~= true then return false, cancelReason end
    if state.visualAt ~= nil and SC.NativeActions
        and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "base_job_cancelled")
    end
    states[actor] = nil
    return true, "base_job_cancelled"
end

-- An expired active lease is only reclaimable after the former worker has no
-- native action, transfer, cargo, or subsystem-owned recovery obligation.
-- The caller leaves unsafe rows with their old owner for explicit recovery.
-- Refuel and car-upkeep chores reserve one exact item by job id. A marker
-- whose job no longer names that item is stale and reserves nothing.
function BaseWork.choreReserved(item)
    local data = U().modData(item) or {}
    for kind, marker in pairs(CLEAN_MARKERS) do
        local jobId = data[marker]
        local job = jobId and SC.BaseLife and SC.BaseLife.job(jobId) or nil
        if job and cleaningMarked(item, job, kind) then return true end
    end
    if data.LF_RefuelJobId == nil and data.LF_UpkeepJobId == nil then return false end
    return not SC.BaseFuel or type(SC.BaseFuel.reserved) ~= "function"
        or SC.BaseFuel.reserved(item) == true
end

-- A worker that died or was removed for good (SCBaseFuel owns the rule: a
-- dormant or not-yet-restored companion still counts as present).
function BaseWork.workerUnregistered(id)
    return SC.BaseFuel and type(SC.BaseFuel.workerIdGone) == "function"
        and SC.BaseFuel.workerIdGone(id) == true or false
end

function BaseWork.reconcileExpiredJob(job, ownerId)
    if type(job) ~= "table" or type(ownerId) ~= "string" then
        return false, "expired_job_owner_missing"
    end
    if job.type == "production" then
        if SC.Production and type(SC.Production.reconcileExpiredJob) == "function" then
            return SC.Production.reconcileExpiredJob(job, ownerId)
        end
        return false, "expired_job_subsystem_owned"
    end
    if job.type == "farm" or job.type == "gather_materials"
        or job.type == "cook" then
        return false, "expired_job_subsystem_owned"
    end
    if job.type == "clean" and cleaningReceipt(job, "tool")
        or job.type == "clean" and cleaningReceipt(job, "liquid") then
        if not BaseWork.workerUnregistered(ownerId) then
            return false, "expired_cleaning_loan_pending" end
        job.target.cleanLoans, job.assignedId = nil, nil
    end
    if (job.type == "refuel_vehicle" or job.type == "refuel_generator"
        or job.type == "inflate_tires" or job.type == "wash_vehicle")
        and type(job.target) == "table"
        and job.target.stage ~= nil then
        -- Only the chore can release a receipt whose worker is gone for good.
        local work = job.type == "refuel_vehicle" and SC.VehicleRefuel
            or job.type == "refuel_generator" and SC.GeneratorRefuel
            or SC.VehicleUpkeep
        if not BaseWork.workerUnregistered(ownerId) or not work
            or type(work.releaseAffinity) ~= "function"
            or work.releaseAffinity(nil, job) ~= true then
            return false, "expired_refuel_receipt_pending"
        end
    end
    local actor = U().resolveActor(ownerId)
    if actor == nil then
        -- Nothing of a dead or removed worker remains to settle.
        if BaseWork.workerUnregistered(ownerId) then return true, "expired_job_worker_gone" end
        return false, "expired_job_actor_missing"
    end
    if SC.NativeActions and type(SC.NativeActions.isWorkActive) == "function"
        and SC.NativeActions.isWorkActive(actor) == true then
        return false, "expired_job_native_active"
    end
    if SC.Navigation and type(SC.Navigation.peek) == "function" then
        local navigation = SC.Navigation.peek(actor)
        if type(navigation) == "table" and navigation.goalSquare ~= nil then
            return false, "expired_job_navigation_active"
        end
    end
    local state = states[actor]
    if state and state.jobId == job.id then
        if state.action and actionActive(actor, state.action) then
            return false, "expired_job_action_active"
        end
        if state.transfer ~= nil or state.cargo ~= nil or state.visualAt ~= nil
            or state.phase == "building" then
            return false, "expired_job_recovery_pending"
        end
        state.jobId, state.requirementsReady = nil, nil
        state.phase = "idle"
    end
    return true, "expired_job_settled"
end

function BaseWork.reset(actor)
    if actor then
        local cancelled, reason = BaseWork.cancel(actor, "base_work_reset")
        if cancelled ~= true then return false, reason end
    else
        for value, _ in pairs(states) do
            local cancelled, reason = BaseWork.cancel(value, "base_work_reset")
            if cancelled ~= true then return false, reason end
        end
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
    if SC.ChefWork and type(SC.ChefWork.reset) == "function" then
        SC.ChefWork.reset(actor)
    end
    if SC.WorkTransport and type(SC.WorkTransport.reset) == "function" then
        SC.WorkTransport.reset(actor)
    end
    maintenanceCursor, auditPhase, nextRoutineJobAt = 1, 0, 0
    cleaningScan = nil
    if actor then cleaningSourceCache[actor] = nil
    else
        storageItemCursors = setmetatable({}, { __mode = "k" })
        cleaningSourceCache = setmetatable({}, { __mode = "k" })
    end
    return true
end

-- Production supply trips reuse the exact storage withdrawal transaction
-- (approach, loot pose, reserve re-check at commit, verified transfer).
function BaseWork.withdrawFromStorage(actor, state, storage, container, item)
    return transferFromStorage(actor, state, storage, container, item)
end

function BaseWork.returnToStorage(actor, state, storage, container, item)
    return transferToStorage(actor, state, storage, container, item)
end

function BaseWork.depositToStorage(actor, state, storage, container, item, options)
    return transferToStorage(actor, state, storage, container, item, true, options)
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

function BaseWork.restoreDepositToStorage(actor, storage, container, item)
    if not actor or not item then return false, "farm_output_missing" end
    local accepts, reason = SC.BaseLife.storageAcceptsDeposit(storage, container)
    if accepts ~= true then return false, reason end
    local inventory = U().inventory(actor)
    if not inventory or not U().inventoryContains(inventory, item) then
        return false, "farm_output_missing"
    end
    if SC.WorkTransport and type(SC.WorkTransport.hasRoom) == "function" then
        local room, roomReason = SC.WorkTransport.hasRoom(container, actor, item)
        if room ~= true then return false, roomReason or "destination_full" end
    end
    if SC.WorkTransport and type(SC.WorkTransport.transferVerified) == "function" then
        local moved, transferReason = SC.WorkTransport.transferVerified(
            inventory, container, item, actor)
        return moved == true, moved and "base_supply_returned" or transferReason
    end
    return U().transferItemVerified(inventory, container, item)
end

return BaseWork
