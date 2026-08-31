-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.Performance and type(require) == "function" then pcall(require, "SCPerformance") end

SC.Encounter = SC.Encounter or {}
local Encounter = SC.Encounter
local states = setmetatable({}, { __mode = "k" })
local containerReservations = setmetatable({}, { __mode = "k" })
local corpseContainers = setmetatable({}, { __mode = "k" })
local failedContainers = setmetatable({}, { __mode = "k" })
local stopScavengeMovement

local function U()
    return SC.GameplayUtil
end

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = {
            scanPhase = 0,
            lastActionAt = 0,
            visited = setmetatable({}, { __mode = "k" }),
        }
        states[actor] = state
    end
    return state
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, value = pcall(SC.Commands.peek, actor)
        if ok and type(value) == "table" then return value end
    end
    return { recruited = false, scavenge = false, order = "wander" }
end

local function now()
    return U().nowMs()
end

local function debugTrace(actor, task, phase, reason)
    local utility = U()
    if not utility or utility.config("debugSpawnEnabled") ~= true then return end
    print("[SurvivorCompanion][scavenge] actor=" .. tostring(utility.idOf(actor))
        .. " phase=" .. tostring(phase or "none")
        .. " item=" .. tostring(task and task.itemType or "none")
        .. " source=" .. tostring(task and task.sourceKind or "none")
        .. " destination=" .. tostring(task and task.destinationKind or "none")
        .. " result=" .. tostring(reason or "none"))
end

local function setTaskPhase(actor, state, task, phase, reason)
    if not task then return end
    local changed = task.phase ~= phase or (reason ~= nil and task.reason ~= reason)
    task.phase = phase
    task.reason = reason
    task.phaseAt = now()
    state.task = task
    if changed then debugTrace(actor, task, phase, reason) end
end

-- NativeActions is intentionally optional in the pure gameplay harness. In a
-- real game this reports the exact state of our queued human animation, letting
-- inventory mutation wait for the rummage action instead of racing it.
local function nativeVisualStatus(actor, expectedAction)
    local adapter = SC.NativeActions
    if type(adapter) ~= "table" or type(adapter.visualStatus) ~= "function" then
        return nil
    end
    local ok, status, actionName = pcall(adapter.visualStatus, actor, expectedAction)
    if not ok then return nil end
    return status, actionName
end

local function clearNativeVisual(actor)
    if SC.NativeActions and type(SC.NativeActions.clearVisual) == "function" then
        pcall(SC.NativeActions.clearVisual, actor)
    end
end

local function cancelOwnedVisual(actor, expectedAction, reason)
    local status = nativeVisualStatus(actor, expectedAction)
    if status == nil or status == "none" or status == "different" then return end
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        pcall(SC.NativeActions.cancelVisual, actor, reason)
    else
        clearNativeVisual(actor)
    end
end

local function containerOnCooldown(container, current)
    local expires = container and failedContainers[container] or nil
    if expires and expires <= current then
        failedContainers[container] = nil
        return false
    end
    return expires ~= nil
end

local function coolDownContainer(container, current)
    if container then
        failedContainers[container] = current
            + (U().config("scavengeFailureCooldownMs") or 15000)
    end
end

local function pruneReservation(container, time)
    local reservation = containerReservations[container]
    if reservation and reservation.expires <= time then
        containerReservations[container] = nil
        return nil
    end
    return reservation
end

local function reserveContainer(container, actor, time, leaseMs)
    local reservation = pruneReservation(container, time)
    if reservation and reservation.actor ~= actor then return false end
    containerReservations[container] = {
        actor = actor,
        expires = time + (leaseMs or U().config("scavengeReservationMs") or 12000),
    }
    return true
end

local function releaseContainer(container, actor)
    local reservation = container and containerReservations[container]
    if reservation and reservation.actor == actor then containerReservations[container] = nil end
end

local function containerOwner(container)
    local utility = U()
    local owner, ok = utility.call(container, "getParent")
    if ok and owner then return owner end
    owner, ok = utility.call(container, "getContainingItem")
    if ok and owner then return owner end
    return container
end

local function containerFlags(container)
    local utility = U()
    local owner = containerOwner(container)
    local data = utility.modData(owner) or utility.modData(container)
    return data
end

function Encounter.markPlayerOpened(containerOrObject)
    local utility = U()
    if not containerOrObject then return false end
    local container = containerOrObject
    if not utility.hasMethod(container, "getItems") then
        local value, ok = utility.call(containerOrObject, "getContainer")
        if ok and value then container = value end
    end
    local flags = containerFlags(container)
    if not flags then return false end
    flags.SC_PlayerOpened = true
    flags.SC_PlayerOpenedAt = now()
    return true
end

function Encounter.onPlayerContainerOpened(containerOrObject)
    return Encounter.markPlayerOpened(containerOrObject)
end

function Encounter.wasPlayerOpened(containerOrObject)
    if not containerOrObject then return false end
    local utility = U()
    local container = containerOrObject
    if not utility.hasMethod(container, "getItems") then
        local value, ok = utility.call(containerOrObject, "getContainer")
        if ok and value then container = value end
    end
    local flags = containerFlags(container)
    return flags and flags.SC_PlayerOpened == true or false
end

local containerItems

local function supplyStillPresent(supply)
    return type(supply) == "table" and supply.container ~= nil and supply.item ~= nil
        and U().inventoryContains(supply.container, supply.item)
end

local function releasePlayerSupply(actor, state)
    state = state or (actor and states[actor])
    local supply = state and state.supply or nil
    if supply and supply.phase == "visual" then
        cancelOwnedVisual(actor, "loot_container", "camp_supply_cancelled")
    end
    if supply then releaseContainer(supply.container, actor) end
    if state then state.supply = nil end
end

-- Searches only world containers explicitly opened by the local player.  The
-- rotating outer-band sample keeps a 24-tile camp useful without turning every
-- companion decision into a full square scan.
local function findPlayerSupply(actor, predicate, options, state)
    local utility = U()
    local origin = options.origin or actor
    local ox, oy, oz = utility.position(origin)
    if not ox then return nil end
    local radius = math.max(1, math.min(32,
        math.floor(tonumber(options.radius) or utility.config("campStorageRadius") or 24)))
    local squareBudget = math.max(1,
        math.floor(tonumber(options.squareBudget)
            or utility.config("campStorageSquareBudget") or 220))
    local itemBudget = math.max(1,
        math.floor(tonumber(options.itemBudget)
            or utility.config("campStorageItemBudget") or 80))
    state.supplyScanPhase = ((state.supplyScanPhase or 0) + 1) % 8
    local phase = state.supplyScanPhase
    local scanned = 0
    local best, bestDistance

    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if scanned >= squareBudget then return best end
                local edge = math.max(math.abs(dx), math.abs(dy)) == distance
                local sampled = distance <= 6 or ((dx * 17 + dy * 31) % 8) == phase
                if edge and sampled then
                    local square = utility.gridSquare(ox + dx, oy + dy, oz)
                    if square then
                        scanned = scanned + 1
                        utility.squareObjects(square, function(object)
                            local container, containerOk = utility.call(object, "getContainer")
                            if containerOk and container and Encounter.wasPlayerOpened(container) then
                                local reservation = pruneReservation(container, now())
                                if not reservation or reservation.actor == actor then
                                    local examined = 0
                                    utility.each(containerItems(container), itemBudget, function(candidate)
                                        examined = examined + 1
                                        local accepted = false
                                        local protected = SC.PersonalItems
                                            and SC.PersonalItems.isProtected(candidate, actor, "camp_supply")
                                        if not protected then
                                            local ok, value = pcall(predicate, candidate)
                                            if ok then accepted = value == true end
                                        end
                                        if accepted then
                                            local owner = containerOwner(container)
                                            local candidateDistance = utility.distance(actor, owner)
                                            if not bestDistance or candidateDistance < bestDistance then
                                                best = {
                                                    container = container,
                                                    item = candidate,
                                                    owner = owner,
                                                }
                                                bestDistance = candidateDistance
                                            end
                                            return false
                                        end
                                        return examined < itemBudget
                                    end)
                                end
                            end
                        end, 40)
                    end
                end
            end
        end
        if best then return best end
    end
    return best
end

-- Transaction state is deliberately transient.  Return values are a small
-- state machine: "taken", "in_progress", "missing", "unsafe", or "error".
function Encounter.takePlayerSupply(actor, supplyKey, predicate, options)
    if not actor or type(predicate) ~= "function" then
        return "error", "invalid_supply_request"
    end
    options = type(options) == "table" and options or {}
    local utility = U()
    local state = stateFor(actor)
    local snapshot = options.snapshot
    if type(snapshot) == "table" and ((snapshot.immediateCount or 0) > 0
        or (snapshot.pressure or 0) >= 2.5) then
        releasePlayerSupply(actor, state)
        return "unsafe", "camp_supply_threat"
    end

    local supply = state.supply
    if supply and (supply.key ~= supplyKey or not supplyStillPresent(supply)) then
        releasePlayerSupply(actor, state)
        supply = nil
    end
    local current = now()
    local lease = utility.config("campStorageReservationMs") or 20000
    if supply and not reserveContainer(supply.container, actor, current, lease) then
        releasePlayerSupply(actor, state)
        supply = nil
    end
    if not supply then
        supply = findPlayerSupply(actor, predicate, options, state)
        if not supply then return "missing", "camp_supply_missing" end
        if not reserveContainer(supply.container, actor, current, lease) then
            return "in_progress", "camp_supply_reserved"
        end
        supply.key = supplyKey
        state.supply = supply
    end

    if utility.distance(actor, supply.owner) > 1.45 then
        local square = utility.squareOf(supply.owner)
        if not square or not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            releasePlayerSupply(actor, state)
            return "error", "camp_supply_navigation_unavailable"
        end
        local accepted, reason = SC.Navigation.request(actor, square,
            options.moveMode or "walk", {
                action = "move_to_camp_storage",
                container = supply.container,
                item = supply.item,
                snapshot = snapshot,
            })
        if accepted then return "in_progress", reason or "approaching_camp_storage" end
        return "in_progress", reason or "camp_supply_path_wait"
    end

    if SC.PersonalItems and SC.PersonalItems.isProtected(
        supply.item, actor, "camp_supply") then
        releasePlayerSupply(actor, state)
        return "error", "camp_supply_item_became_personal"
    end

    if stopScavengeMovement then stopScavengeMovement(actor) end

    if supply.phase == "visual" then
        local visualState = nativeVisualStatus(actor, "loot_container")
        if visualState == "active" then
            return "in_progress", "camp_supply_looting"
        elseif visualState == "completed" then
            clearNativeVisual(actor)
            supply.phase = nil
        elseif visualState ~= nil then
            releasePlayerSupply(actor, state)
            return "error", "camp_supply_animation_" .. tostring(visualState)
        else
            -- Test providers without the native timed-action adapter retain the
            -- original synchronous transfer contract.
            supply.phase = nil
        end
    else
        local animated, animationReason = utility.move(actor, "walk", {
            action = "loot_container",
            container = supply.container,
            item = supply.item,
            campStorage = true,
        })
        if not animated then
            -- A prior verified loot animation may still own the native queue.
            -- Keep the reservation and retry rather than dropping the order.
            return "in_progress", animationReason or "camp_supply_action_wait"
        end
        local visualState = nativeVisualStatus(actor, "loot_container")
        if visualState == "active" then
            supply.phase = "visual"
            return "in_progress", "camp_supply_looting"
        elseif visualState == "completed" then
            clearNativeVisual(actor)
        elseif visualState ~= nil then
            releasePlayerSupply(actor, state)
            return "error", "camp_supply_animation_" .. tostring(visualState)
        end
    end

    local destination = utility.inventory(actor)
    if SC.Logistics and type(SC.Logistics.preferredLootDestination) == "function" then
        destination = SC.Logistics.preferredLootDestination(actor, supply.item) or destination
    end
    local transferred, transferReason = utility.transferItemVerified(
        supply.container, destination, supply.item)
    if not transferred then
        if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("camp-supply-transfer", utility.idOf(actor),
                "verified container transfer failed: " .. tostring(transferReason),
                utility.itemType(supply.item))
        end
        releasePlayerSupply(actor, state)
        return "error", "camp_supply_transfer_failed"
    end
    local item = supply.item
    local flags = containerFlags(supply.container)
    if flags then flags.SC_LastCompanionUseAt = current end
    if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
        SC.NativeActions.noteResult(actor, "camp_supply", "taken", { kind = "short" })
    end
    releasePlayerSupply(actor, state)
    return "taken", "camp_supply_taken", item
end

function Encounter.cancelPlayerSupply(actor)
    if not actor then return false end
    releasePlayerSupply(actor, states[actor])
    return true
end

local function currentNeeds(actor)
    local utility = U()
    local health = utility.nativeHealth(actor)
    local hunger = utility.characterStatValue(actor, "HUNGER", 0.25)
    local thirst = utility.characterStatValue(actor, "THIRST", 0.25)
    local medicalNeed = math.max(0, (70 - health) / 70)
    if SC.Medical and type(SC.Medical.assess) == "function" then
        local ok, assessment = pcall(SC.Medical.assess, actor)
        if ok and assessment then
            medicalNeed = math.max(medicalNeed, math.min(1, assessment.bleedingCount * 0.6 + assessment.woundCount * 0.15))
        end
    end
    return {
        food = math.max(0.15, hunger),
        water = math.max(0.2, thirst),
        medicine = medicalNeed,
        ammunition = 0.5,
        weapon = 0.35,
        clothing = 0.2,
    }
end

local function itemCategory(item)
    local utility = U()
    local itemType = string.lower(utility.itemType(item))
    local category, categoryOk = utility.call(item, "getCategory")
    category = categoryOk and string.lower(tostring(category)) or ""
    if string.find(itemType, "bandage", 1, true)
        or string.find(itemType, "rippedsheet", 1, true)
        or string.find(itemType, "disinfect", 1, true)
        or string.find(itemType, "painkiller", 1, true)
        or string.find(itemType, "antibiotic", 1, true) then return "medicine" end
    if string.find(itemType, "water", 1, true) or U().itemHasTag(item, "WaterContainer") then return "water" end
    if category == "food" or U().hasMethod(item, "getCalories") then return "food" end
    if string.find(itemType, "ammo", 1, true)
        or string.find(itemType, "bullet", 1, true)
        or string.find(itemType, "shell", 1, true) then return "ammunition" end
    if U().instanceOf(item, "HandWeapon") or U().hasMethod(item, "getMaxDamage") then return "weapon" end
    if category == "clothing" then return "clothing" end
    return nil
end

local function itemNeedScore(actor, item, needs, commands, audit)
    if SC.Logistics and type(SC.Logistics.itemNeedScore) == "function" then
        return SC.Logistics.itemNeedScore(actor, item, commands, audit)
    end
    local utility = U()
    local category = itemCategory(item)
    if not category then return 0, nil end
    local score = (needs[category] or 0) * 60
    local condition, conditionOk = utility.call(item, "getCondition")
    local maximum, maxOk = utility.call(item, "getConditionMax")
    if conditionOk and maxOk and maximum and maximum > 0 then score = score * condition / maximum end
    if category == "food" then
        local rotten, rottenOk = utility.call(item, "isRotten")
        if rottenOk and rotten then score = score - 60 end
    elseif category == "water" then
        local amount, amountOk = utility.call(item, "getUsedDelta")
        if amountOk then score = score * math.max(0.2, amount) end
    end
    return score, category
end

containerItems = function(container)
    local items, ok = U().call(container, "getItems")
    if ok then return items end
    return type(container) == "table" and (container.items or container) or nil
end

local function containerSignature(container)
    local utility = U()
    local count, hash = 0, 0
    utility.each(containerItems(container), utility.config("scavengeItemBudget") or 40,
        function(item)
            count = count + 1
            local id, idOk = utility.call(item, "getID")
            local identity = idOk and tostring(id) or utility.itemType(item)
            hash = (hash + utility.stableHash(utility.itemType(item) .. ":" .. identity))
                % 2147483647
        end)
    return tostring(count) .. ":" .. tostring(hash)
end

local function memoryAllows(state, container, current)
    local memory = state.visited and state.visited[container] or nil
    if not memory then return true end
    local signature = containerSignature(container)
    if signature ~= memory.signature then
        state.visited[container] = nil
        return true
    end
    return current >= (tonumber(memory.expires) or 0)
end

local function rememberContainer(state, container, result, current)
    if not state or not container then return end
    state.visited = state.visited or setmetatable({}, { __mode = "k" })
    if state.visited[container] == nil then
        local count, oldestContainer, oldestExpiry = 0, nil, math.huge
        for remembered, memory in pairs(state.visited) do
            count = count + 1
            local expiry = tonumber(memory.expires) or 0
            if expiry < oldestExpiry then
                oldestContainer, oldestExpiry = remembered, expiry
            end
        end
        if count >= (U().config("scavengeMemoryLimit") or 96) and oldestContainer then
            state.visited[oldestContainer] = nil
        end
    end
    local duration = result == "looted"
        and (U().config("scavengeSuccessCooldownMs") or 4000)
        or result == "nothing_needed"
            and (U().config("scavengeNoUsefulCooldownMs") or 30000)
            or (U().config("scavengeFailureCooldownMs") or 15000)
    state.visited[container] = {
        signature = containerSignature(container),
        result = result,
        expires = current + duration,
    }
end

local function scoreContainer(actor, container, needs, objectives, commands, audit)
    local utility = U()
    local bestItem, bestCategory, bestScore = nil, nil, 0
    local budget = utility.config("scavengeItemBudget") or 40
    utility.each(containerItems(container), budget, function(item)
        local protected = SC.PersonalItems
            and SC.PersonalItems.isProtected(item, actor, "return_to_owner")
        local score, category = 0, nil
        if not protected then
            score, category = itemNeedScore(actor, item, needs, commands, audit)
            if SC.Objectives and type(SC.Objectives.itemBonus) == "function" then
                local bonus = SC.Objectives.itemBonus(objectives, item, actor)
                score = score + bonus
                if bonus > 0 and not category then category = "personal" end
            end
        end
        if score > bestScore then bestItem, bestCategory, bestScore = item, category, score end
    end)
    local owner = containerOwner(container)
    bestScore = bestScore - utility.distance(actor, owner) * 1.5
    return bestScore, bestItem, bestCategory, owner
end

local function isZombieCorpse(object)
    if not U().instanceOf(object, "IsoDeadBody") then return false end
    local animal, animalOk = U().call(object, "isAnimal")
    if animalOk and animal == true then return false end
    local zombie, zombieOk = U().call(object, "isZombie")
    if zombieOk then return zombie == true end
    local wasZombie, wasZombieOk = U().call(object, "wasZombie")
    if wasZombieOk then return wasZombie == true end
    return false
end

local function scavengeOffsets(radius, budget, phase)
    local offsets = {}
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if #offsets >= budget then return offsets end
                if math.max(math.abs(dx), math.abs(dy)) == distance
                    and (distance <= 3 or (dx * 17 + dy * 31) % 4 == phase) then
                    offsets[#offsets + 1] = { x = dx, y = dy }
                end
            end
        end
    end
    return offsets
end

local function newContainerSearch(actor, state, allowCorpses, current, radius, budget)
    local ax, ay, az = U().position(actor)
    state.scanPhase = ((state.scanPhase or 0) + 1) % 4
    return {
        originX = ax, originY = ay, originZ = az,
        radius = radius,
        budget = budget,
        allowCorpses = allowCorpses == true,
        current = current,
        offsets = scavengeOffsets(radius, budget, state.scanPhase),
        index = 1,
        candidates = {},
        seenContainers = setmetatable({}, { __mode = "k" }),
    }
end

local function containerSearchInvalid(job, actor, allowCorpses, radius, budget)
    if type(job) ~= "table" or job.allowCorpses ~= (allowCorpses == true)
        or job.radius ~= radius or job.budget ~= budget then return true end
    local ax, ay, az = U().position(actor)
    if ax == nil or az ~= job.originZ then return true end
    local dx, dy = ax - job.originX, ay - job.originY
    return dx * dx + dy * dy > 16
end

local function candidateContainers(actor, player, state, allowCorpses, current)
    local utility = U()
    local ax, ay, az = utility.position(actor)
    if not ax then return {}, true end
    local radius = math.floor(math.min(math.max(utility.config("scavengeRadius") or 14,
        allowCorpses and (utility.config("corpseLootRadius") or 10) or 0), 18))
    local budget = math.max(utility.config("scavengeSquareBudget") or 100,
        allowCorpses and (utility.config("corpseLootSquareBudget") or 80) or 0)
    local job = state.containerSearch
    if containerSearchInvalid(job, actor, allowCorpses, radius, budget) then
        job = newContainerSearch(actor, state, allowCorpses, current, radius, budget)
        state.containerSearch = job
    end
    local requested = math.max(0, #job.offsets - job.index + 1)
    local granted = requested
    if SC.Performance and type(SC.Performance.claimUnits) == "function" then
        granted = SC.Performance.claimUnits("scavengeSquares", requested, false)
    end
    local startedAt, processed = utility.nowMs(), 0
    while processed < granted and job.index <= #job.offsets do
        local offset = job.offsets[job.index]
        job.index = job.index + 1
        processed = processed + 1
        local square = utility.gridSquare(job.originX + offset.x, job.originY + offset.y, job.originZ)
        if square and (not player or utility.distanceSq(player, square) <= radius * radius) then
            utility.squareObjects(square, function(object)
                local container, ok = utility.call(object, "getContainer")
                if ok and container and not job.seenContainers[container]
                    and not containerOnCooldown(container, current)
                    and memoryAllows(state, container, current)
                    and not Encounter.wasPlayerOpened(container) then
                    -- SC_CompanionVisited is informational. A prior companion
                    -- taking one item must not hide the remaining contents.
                    job.seenContainers[container] = true
                    job.candidates[#job.candidates + 1] = container
                end
            end, 40)
            if allowCorpses then
                utility.squareStaticMovingObjects(square, function(object)
                    if isZombieCorpse(object) then
                        local container, ok = utility.call(object, "getContainer")
                        if ok and container and not job.seenContainers[container]
                            and not containerOnCooldown(container, current)
                            and memoryAllows(state, container, current) then
                            job.seenContainers[container] = true
                            corpseContainers[container] = true
                            job.candidates[#job.candidates + 1] = container
                        end
                    end
                end, 16)
            end
        end
    end
    local complete = job.index > #job.offsets
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("scavenge.scan", utility.idOf(actor),
            utility.nowMs() - startedAt, processed, false)
    end
    if not complete then
        if SC.Performance and type(SC.Performance.markYield) == "function" then
            SC.Performance.markYield("scavenge.scan", utility.idOf(actor), processed)
        end
        return nil, false, job.index - 1, #job.offsets
    end
    local candidates = job.candidates
    state.containerSearch = nil
    return candidates, true, #job.offsets, #job.offsets
end

local function safeForScavenging(snapshot, commands)
    if commands.order == "regroup" or commands.order == "retreat" then return false end
    if type(snapshot) ~= "table" then return true end
    return (snapshot.immediateCount or 0) == 0 and (snapshot.pressure or 0) < 1.5
end

local function safeForCorpseLoot(actor, snapshot, state, current)
    if type(snapshot) == "table" and ((snapshot.threatCount or 0) > 0
        or (snapshot.immediateCount or 0) > 0 or (snapshot.pressure or 0) > 0) then
        state.lastThreatAt = current
        return false
    end
    local lastDanger = state.lastThreatAt or -math.huge
    if SC.Combat and type(SC.Combat.peek) == "function" then
        local combat = SC.Combat.peek(actor)
        if combat and combat.active then return false end
        if combat then lastDanger = math.max(lastDanger, tonumber(combat.lastActionAt) or -math.huge) end
    end
    if current - lastDanger < (U().config("corpseLootGraceMs") or 6000) then return false end
    return true
end

stopScavengeMovement = function(actor)
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "scavenge_interaction")
    end
    if SC.NativeActions and type(SC.NativeActions.stopDirect) == "function" then
        pcall(SC.NativeActions.stopDirect, actor)
    else
        U().stop(actor)
    end
end

local function clearTaskFields(state)
    state.task = nil
    -- Retain the old fields as nil so external diagnostics cannot mistake a
    -- completed transaction for a still-owned target.
    state.container = nil
    state.item = nil
    state.itemCategory = nil
    state.containerOwner = nil
    state.lootPhase = nil
end

local function clearSearchFields(actor, state)
    local selection = state and state.selectionJob or nil
    if selection and selection.bestContainer then
        releaseContainer(selection.bestContainer, actor)
    end
    if state then
        state.selectionJob = nil
        state.containerSearch = nil
    end
end

local function resetScavengeTarget(actor, state, options)
    options = options or {}
    local task = state.task
    local container = task and task.container or state.container
    if options.cancelVisual and task and task.phase == "animate" then
        cancelOwnedVisual(actor, "loot_container", options.reason or "scavenge_cancelled")
    end
    if options.stopMovement then stopScavengeMovement(actor) end
    if options.cooldown and container then coolDownContainer(container, options.time or now()) end
    if options.memoryResult and container then
        rememberContainer(state, container, options.memoryResult, options.time or now())
    end
    if container then releaseContainer(container, actor) end
    clearSearchFields(actor, state)
    if task and options.status ~= false then
        state.lastStatus = {
            phase = options.phase or "cancelled",
            reason = options.reason,
            itemType = task.itemType,
            itemName = task.itemName,
            category = task.category,
            sourceKind = task.sourceKind,
            destinationKind = task.destinationKind,
            destinationName = task.destinationName,
            expires = (options.time or now()) + (U().config("scavengeStatusHoldMs") or 8000),
        }
        debugTrace(actor, task, state.lastStatus.phase, options.reason)
    end
    clearTaskFields(state)
end

local function chooseDestination(actor, item, category, audit)
    local utility = U()
    if SC.Logistics and type(SC.Logistics.preferredLootDestination) == "function" then
        local destination, kind, bag = SC.Logistics.preferredLootDestination(
            actor, item, category, audit)
        if destination then
            return destination, kind or "inventory", bag and utility.itemName(bag) or nil
        end
    end
    return utility.inventory(actor), "inventory", nil
end

local function beginTask(actor, state, container, item, category, owner, commands, audit, time)
    local destination, destinationKind, destinationName = chooseDestination(
        actor, item, category, audit)
    if not destination then return nil, "destination_unavailable" end
    local task = {
        container = container,
        owner = owner or containerOwner(container),
        item = item,
        itemType = U().itemType(item),
        itemName = U().itemName(item),
        category = category,
        sourceKind = corpseContainers[container] and "zombie_corpse" or "world_container",
        destination = destination,
        destinationKind = destinationKind,
        destinationName = destinationName,
        selectedAt = time,
        commandSerial = tonumber(commands.commandSerial) or 0,
    }
    state.container = container
    state.item = item
    state.itemCategory = category
    state.containerOwner = task.owner
    setTaskPhase(actor, state, task, "select", "selected")
    state.lastStatus = nil
    return task
end

local function selectTask(actor, player, state, commands, needs, audit, allowCorpses, time)
    local selection = state.selectionJob
    if selection and selection.commandSerial ~= (tonumber(commands.commandSerial) or 0) then
        clearSearchFields(actor, state)
        selection = nil
    end
    if not selection then
        local candidates, complete, progress, total = candidateContainers(
            actor, player, state, allowCorpses, time)
        if not complete then
            state.lastStatus = {
                phase = "search", reason = "searching_containers",
                progress = progress, total = total,
                expires = time + 1000,
            }
            return nil, "searching"
        end
        selection = {
            candidates = candidates or {}, index = 1,
            commandSerial = tonumber(commands.commandSerial) or 0,
        }
        state.selectionJob = selection
    end

    local remaining = math.max(0, #selection.candidates - selection.index + 1)
    local granted = remaining
    if SC.Performance and type(SC.Performance.claimUnits) == "function" then
        granted = SC.Performance.claimUnits("scavengeContainers", remaining, false)
    end
    local startedAt, processed = U().nowMs(), 0
    while processed < granted and selection.index <= #selection.candidates do
        local container = selection.candidates[selection.index]
        selection.index = selection.index + 1
        processed = processed + 1
        if reserveContainer(container, actor, time) then
            local score, item, category, owner = scoreContainer(
                actor, container, needs, commands.objectives, commands, audit)
            if item and score > 0 then
                if selection.bestScore == nil or score > selection.bestScore then
                    if selection.bestContainer and selection.bestContainer ~= container then
                        releaseContainer(selection.bestContainer, actor)
                    end
                    selection.bestContainer, selection.bestItem, selection.bestCategory,
                        selection.bestOwner, selection.bestScore =
                        container, item, category, owner, score
                else
                    releaseContainer(container, actor)
                end
            else
                rememberContainer(state, container, "nothing_needed", time)
                releaseContainer(container, actor)
            end
        end
    end
    if SC.Performance and type(SC.Performance.record) == "function" then
        SC.Performance.record("scavenge.score", U().idOf(actor),
            U().nowMs() - startedAt, processed, false)
    end
    if selection.index <= #selection.candidates then
        if SC.Performance and type(SC.Performance.markYield) == "function" then
            SC.Performance.markYield("scavenge.score", U().idOf(actor), processed)
        end
        state.lastStatus = {
            phase = "search", reason = "evaluating_supplies",
            progress = selection.index - 1, total = #selection.candidates,
            expires = time + 1000,
        }
        return nil, "searching"
    end
    state.selectionJob = nil
    if not selection.bestContainer or not selection.bestItem then return nil, "nothing_needed" end
    return beginTask(actor, state, selection.bestContainer, selection.bestItem,
        selection.bestCategory, selection.bestOwner, commands, audit, time)
end

local function commitTask(actor, state, task, commands, audit, time)
    local utility = U()
    if SC.Logistics and type(SC.Logistics.audit) == "function" then
        local ok, fresh = pcall(SC.Logistics.audit, actor)
        if ok and type(fresh) == "table" then audit = fresh end
    end
    if (tonumber(commands.commandSerial) or 0) ~= task.commandSerial then
        resetScavengeTarget(actor, state, {
            reason = "command_changed", phase = "cancelled", memoryResult = "interrupted",
            time = time,
        })
        return false, "command_changed"
    end
    if not utility.inventoryContains(task.container, task.item) then
        resetScavengeTarget(actor, state, {
            reason = "source_changed", phase = "failed", memoryResult = "source_changed",
            time = time,
        })
        return false, "source_changed"
    end
    if SC.Logistics and type(SC.Logistics.canTake) == "function" then
        local accepted, reason = SC.Logistics.canTake(actor, task.item, task.category, audit)
        if accepted ~= true then
            resetScavengeTarget(actor, state, {
                reason = reason or "loadout_changed", phase = "cancelled",
                memoryResult = "loadout_changed", time = time,
            })
            return false, reason or "loadout_changed"
        end
    end

    local destination, destinationKind, destinationName = chooseDestination(
        actor, task.item, task.category, audit)
    if not destination then
        resetScavengeTarget(actor, state, {
            reason = "destination_unavailable", phase = "failed", cooldown = true,
            memoryResult = "destination_unavailable", time = time,
        })
        return false, "destination_unavailable"
    end
    task.destination = destination
    task.destinationKind = destinationKind
    task.destinationName = destinationName
    local allowed, allowedOk = utility.call(destination, "isItemAllowed", task.item)
    if allowedOk and allowed ~= true then
        resetScavengeTarget(actor, state, {
            reason = "destination_rejected_item", phase = "failed", cooldown = true,
            memoryResult = "destination_rejected_item", time = time,
        })
        return false, "destination_rejected_item"
    end
    local room, roomOk = utility.call(destination, "hasRoomFor", actor, task.item)
    if roomOk and room ~= true then
        resetScavengeTarget(actor, state, {
            reason = "destination_full", phase = "cancelled",
            memoryResult = "destination_full", time = time,
        })
        return false, "destination_full"
    end

    setTaskPhase(actor, state, task, "verify", "committing")
    local transferred, transferReason, receipt = utility.transferItemVerified(
        task.container, destination, task.item)
    if transferred and utility.inventoryContains(destination, task.item)
        and not utility.inventoryContains(task.container, task.item) then
        local flags = containerFlags(task.container)
        if flags and task.sourceKind ~= "zombie_corpse" then
            flags.SC_LastScavengedAt = time
            flags.SC_CompanionVisited = true
        end
        rememberContainer(state, task.container, "looted", time)
        state.lastLoot = {
            type = task.itemType,
            name = task.itemName,
            category = task.category,
            source = task.sourceKind,
            destination = task.destinationKind,
            destinationName = task.destinationName,
            time = time,
            verified = receipt ~= nil,
        }
        if SC.Logistics and type(SC.Logistics.reset) == "function" then
            SC.Logistics.reset(actor)
        end
        state.lastStatus = {
            phase = "complete", reason = "looted", itemType = task.itemType,
            itemName = task.itemName, category = task.category,
            sourceKind = task.sourceKind, destinationKind = task.destinationKind,
            destinationName = task.destinationName,
            expires = time + (utility.config("scavengeStatusHoldMs") or 8000),
        }
        setTaskPhase(actor, state, task, "complete", "looted")
        releaseContainer(task.container, actor)
        clearTaskFields(state)
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "scavenge", "looted")
        end
        return true, "looted"
    end

    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("scavenge-transfer", utility.idOf(actor),
            "verified container transfer failed: " .. tostring(transferReason), task.itemType)
    end
    resetScavengeTarget(actor, state, {
        reason = transferReason or "transfer_failed", phase = "failed", cooldown = true,
        memoryResult = "transfer_failed", time = time,
    })
    return false, transferReason or "transfer_failed"
end

function Encounter.tryScavenge(actor, player, runtime, neutralOverride)
    local utility = U()
    local rootRuntime = utility.actorState(actor, runtime)
    local state = stateFor(actor)
    local commands = commandState(actor)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    local time = now()
    if (not commands.scavenge and not neutralOverride) or not safeForScavenging(snapshot, commands) then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = state.task ~= nil,
            reason = not commands.scavenge and "scavenge_disabled" or "scavenge_unsafe",
            phase = "cancelled", memoryResult = state.task and "interrupted" or nil,
            time = time, status = state.task ~= nil,
        })
        return false, "scavenge_disabled_or_unsafe"
    end
    local radius = utility.config("scavengeRadius") or 14
    if player and utility.distanceSq(actor, player) > radius * radius then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = state.task ~= nil,
            reason = "outside_scavenge_radius", phase = "cancelled",
            memoryResult = state.task and "interrupted" or nil,
            time = time, status = state.task ~= nil,
        })
        return false, "outside_scavenge_radius"
    end

    local needs = currentNeeds(actor)
    local audit = SC.Logistics and type(SC.Logistics.status) == "function"
        and SC.Logistics.status(actor) or nil
    if audit and audit.shouldUnload then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = state.task ~= nil,
            reason = "loadout_needs_unloading", phase = "cancelled",
            memoryResult = state.task and "loadout_changed" or nil,
            time = time, status = state.task ~= nil,
        })
        return false, "loadout_needs_unloading"
    end
    local allowCorpses = safeForCorpseLoot(actor, snapshot, state, time)
    local task = state.task
    if task and containerOnCooldown(task.container, time) then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = true, reason = "container_cooldown",
            phase = "cancelled", time = time,
        })
        return false, "container_cooldown"
    end
    if task and not utility.inventoryContains(task.container, task.item) then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = true, reason = "source_changed",
            phase = "failed", memoryResult = "source_changed", time = time,
        })
        return false, "source_changed"
    end
    if task and (tonumber(commands.commandSerial) or 0) ~= task.commandSerial then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = true, reason = "command_changed",
            phase = "cancelled", memoryResult = "interrupted", time = time,
        })
        return false, "command_changed"
    end
    if not task then
        local selectionReason
        task, selectionReason = selectTask(
            actor, player, state, commands, needs, audit, allowCorpses, time)
        if not task then
            if selectionReason == "searching" then return true, "searching_for_supplies" end
            return false, selectionReason or "nothing_needed"
        end
    end

    if not reserveContainer(task.container, actor, time) then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = true, reason = "container_reserved",
            phase = "cancelled", time = time,
        })
        return false, "container_reserved"
    end
    if task.sourceKind == "zombie_corpse"
        and not safeForCorpseLoot(actor, snapshot, state, time) then
        resetScavengeTarget(actor, state, {
            cancelVisual = true, stopMovement = true, reason = "corpse_loot_unsafe",
            phase = "cancelled", memoryResult = "interrupted", time = time,
        })
        return false, "corpse_loot_unsafe"
    end

    if utility.distance(actor, task.owner) > 1.45 then
        setTaskPhase(actor, state, task, "approach", "approaching_container")
        if SC.Navigation and type(SC.Navigation.requestAny) == "function" then
            local targets = SC.Navigation.interactionTargets(actor, task.owner, {
                snapshot = snapshot,
            })
            local ok, status = SC.Navigation.requestAny(actor, targets, "walk", {
                action = "move_to_scavenge", container = task.container,
                item = task.item, object = task.owner, snapshot = snapshot,
                arrivalDistance = 1.0,
            })
            return ok, status or "approaching_container"
        end
        resetScavengeTarget(actor, state, {
            stopMovement = true, reason = "navigation_unavailable", phase = "failed",
            cooldown = true, memoryResult = "navigation_unavailable", time = time,
        })
        return false, "navigation_unavailable"
    end

    if task.phase == "select" or task.phase == "approach" then
        stopScavengeMovement(actor)
        task.settleUntil = time + (utility.config("scavengeSettleMs") or 250)
        setTaskPhase(actor, state, task, "settle", "stopping_at_container")
    end
    if task.phase == "settle" and time < (task.settleUntil or time) then
        return true, "settling_at_container"
    end
    if task.phase == "settle" then
        stopScavengeMovement(actor)
        local moving, movingOk = utility.call(actor, "isMoving")
        if movingOk and moving == true then return true, "settling_at_container" end
    end

    if SC.Logistics and type(SC.Logistics.canTake) == "function" then
        local accepted, reason = SC.Logistics.canTake(actor, task.item, task.category, audit)
        if accepted ~= true then
            resetScavengeTarget(actor, state, {
                reason = reason or "loadout_changed", phase = "cancelled",
                memoryResult = "loadout_changed", time = time,
            })
            return false, reason or "loadout_changed"
        end
    end

    if task.phase == "animate" then
        local visualState = nativeVisualStatus(actor, "loot_container")
        if visualState == "active" then return true, "looting" end
        if visualState == "completed" then
            clearNativeVisual(actor)
            setTaskPhase(actor, state, task, "commit", "animation_completed")
        elseif visualState ~= nil then
            resetScavengeTarget(actor, state, {
                reason = "loot_animation_" .. tostring(visualState), phase = "failed",
                cooldown = true, memoryResult = "animation_failed", time = time,
            })
            return false, "loot_animation_" .. tostring(visualState)
        else
            setTaskPhase(actor, state, task, "commit", "animation_untracked_complete")
        end
    elseif task.phase == "settle" then
        local animated, animationReason = utility.move(actor, "walk", {
            action = "loot_container", container = task.container,
            item = task.item, category = task.category,
        })
        if not animated then
            resetScavengeTarget(actor, state, {
                reason = animationReason or "loot_action_rejected", phase = "failed",
                cooldown = true, memoryResult = "animation_failed", time = time,
            })
            return false, animationReason or "loot_action_rejected"
        end
        local visualState = nativeVisualStatus(actor, "loot_container")
        if visualState == "active" then
            state.lootPhase = "visual"
            setTaskPhase(actor, state, task, "animate", "looting")
            return true, "looting"
        elseif visualState == "completed" then
            clearNativeVisual(actor)
        elseif visualState ~= nil then
            resetScavengeTarget(actor, state, {
                reason = "loot_animation_" .. tostring(visualState), phase = "failed",
                cooldown = true, memoryResult = "animation_failed", time = time,
            })
            return false, "loot_animation_" .. tostring(visualState)
        end
        setTaskPhase(actor, state, task, "commit", "animation_completed")
    end

    if task.phase == "commit" then
        return commitTask(actor, state, task, commands, audit, time)
    end
    return true, task.phase or "scavenging"
end

local function zombieDensity(square, radius, limit)
    local utility = U()
    local x, y, z = utility.position(square)
    local count = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local other = utility.gridSquare(x + dx, y + dy, z)
            if other then
                utility.squareMovingObjects(other, function(value)
                    if utility.isZombie(value) and not utility.isDead(value) then
                        count = count + 1
                        if count >= limit then return false end
                    end
                end, 10)
            end
            if count >= limit then return count end
        end
    end
    return count
end

local function spawnSquareScore(square, player)
    local utility = U()
    if not square or not utility.isSquareFree(square) then return nil end
    if utility.canSee(player, square) then return nil end
    local moving, movingOk = utility.call(square, "getMovingObjects")
    if movingOk and utility.listSize(moving) > 0 then return nil end
    local density = zombieDensity(square, 2, 5)
    if density >= 4 then return nil end
    local score = 40 - density * 12
    local room, roomOk = utility.call(square, "getRoom")
    if roomOk and room then score = score + 18 end
    local x, y, z = utility.position(square)
    local traversable = 0
    for _, delta in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local neighbor = utility.gridSquare(x + delta[1], y + delta[2], z)
        if neighbor and utility.isSquareFree(neighbor) and not utility.edgeBlocked(square, neighbor) then
            traversable = traversable + 1
        end
    end
    if traversable == 0 then return nil end
    score = score + traversable * 4
    if traversable <= 2 then score = score + 6 end -- covered edge with an escape route
    return score
end

function Encounter.chooseSpawnSquare(player, runtime)
    local utility = U()
    if not utility.isValidActor(player) then return nil, "invalid_player" end
    local px, py, pz = utility.position(player)
    local minimum, maximum, attempts = 22, 45, 96
    local seed = utility.stableHash(tostring(math.floor(px)) .. ":" .. tostring(math.floor(py)) .. ":" .. tostring(math.floor(now() / 10000)))
    local best, bestScore
    for index = 1, attempts do
        seed = (seed * 1103515245 + 12345) % 2147483647
        local distance = minimum + (seed % (maximum - minimum + 1))
        seed = (seed * 1103515245 + 12345) % 2147483647
        local side = seed % 4
        seed = (seed * 1103515245 + 12345) % 2147483647
        local offset = (seed % (distance * 2 + 1)) - distance
        local dx, dy
        if side == 0 then dx, dy = distance, offset
        elseif side == 1 then dx, dy = -distance, offset
        elseif side == 2 then dx, dy = offset, distance
        else dx, dy = offset, -distance end
        local square = utility.gridSquare(px + dx, py + dy, pz)
        local score = spawnSquareScore(square, player)
        if score and (not bestScore or score > bestScore) then best, bestScore = square, score end
    end
    return best, best and nil or "no_valid_loaded_square"
end

local function viableRescue(snapshot)
    if type(snapshot) ~= "table" then return true end
    if (snapshot.immediateCount or 0) > 0 then return false end
    return #(snapshot.escapeSquares or {}) > 0 or (snapshot.threatCount or 0) <= 1
end

local function indoorCover(actor, snapshot)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return nil end
    local best, bestScore
    local scanned = 0
    for distance = 1, 6 do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if scanned >= 80 then return best end
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if square and utility.isSquareFree(square) then
                        scanned = scanned + 1
                        local room, roomOk = utility.call(square, "getRoom")
                        if roomOk and room then
                            local score = 30 - distance
                            if snapshot and type(snapshot.threats) == "table" then
                                local nearest = math.huge
                                for index = 1, math.min(#snapshot.threats, 10) do
                                    nearest = math.min(nearest, utility.distanceSq(square, snapshot.threats[index].actor))
                                end
                                score = score + math.min(nearest, 64) * 0.2
                            end
                            if not bestScore or score > bestScore then best, bestScore = square, score end
                        end
                    end
                end
            end
        end
    end
    return best
end

local function seekCover(actor, snapshot, action)
    local utility = U()
    local escape = snapshot and snapshot.escapeSquares and snapshot.escapeSquares[1]
    if escape and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, escape.square, action == "retreat" and "jog" or "sneak", {
            action = action,
            snapshot = snapshot,
            neutral = true,
            urgent = action == "retreat",
            escapeSpeedOverride = action == "retreat",
        })
    end
    if escape then
        local accepted = utility.move(actor, action == "retreat" and "jog" or "sneak", {
            action = action, targetSquare = escape.square, enginePath = true,
            snapshot = snapshot, neutral = true,
            urgent = action == "retreat", escapeSpeedOverride = action == "retreat",
        })
        return accepted == true, accepted and action or "cover_action_rejected"
    end
    local immediate = snapshot and snapshot.immediateAttackers
        and snapshot.immediateAttackers[1] or nil
    local known = immediate or (snapshot and snapshot.threats and snapshot.threats[1])
    local threat = type(known) == "table" and known.actor or known
    if threat == nil then return false, "cover_direction_unavailable" end
    local accepted = utility.move(actor, action == "retreat" and "jog" or "sneak", {
        action = action, awayFrom = threat, snapshot = snapshot,
        seekCover = true, neutral = true,
        urgent = action == "retreat", escapeSpeedOverride = action == "retreat",
    })
    return accepted == true, accepted and action or "cover_action_rejected"
end

local function neutralUpdate(actor, player, rootRuntime, snapshot, state)
    local utility = U()
    local playerDistance = player and utility.distance(actor, player) or math.huge
    local playerCanSee = player and utility.canSee(player, actor) or false
    local spawnService = SC.Spawn
    local debugActor = type(spawnService) == "table"
        and type(spawnService.isDebugActor) == "function"
        and spawnService.isDebugActor(actor) == true
    local debugProtected = debugActor and type(spawnService.isDebugProtected) == "function"
        and spawnService.isDebugProtected(actor) == true
    if debugProtected and (playerCanSee
        or playerDistance <= (utility.config("debugDiscoveryDistance") or 6)) then
        if type(spawnService.markDebugDiscovered) == "function"
            and spawnService.markDebugDiscovered(actor) == true
            and type(spawnService.debugLog) == "function" then
            spawnService.debugLog("discovered", actor, player, playerCanSee and "line_of_sight" or "proximity")
        end
        debugProtected = false
    end
    if player and playerDistance > (utility.config("encounterDespawnRadius") or 95)
        and not playerCanSee and not debugProtected then
        local debugDescription = debugActor and type(spawnService.debugDescription) == "function"
            and spawnService.debugDescription(actor, player) or nil
        local actorService = SC.Actor
        if type(actorService) == "table" and type(actorService.remove) == "function" then
            local ok, result = pcall(actorService.remove, actor)
            if not ok then ok, result = pcall(actorService.remove, actorService, actor) end
            if ok and result == true then
                if debugDescription ~= nil then
                    print("[SurvivorCompanion][debug-spawn] event=removed " .. debugDescription
                        .. " reason=encounter_distance")
                end
                return true, "despawned"
            end
        end
    end
    if snapshot and (snapshot.immediateCount or 0) > 0 then return seekCover(actor, snapshot, "retreat") end
    if snapshot and (snapshot.threatCount or 0) > 0 then return seekCover(actor, snapshot, "seek_cover") end

    if player and viableRescue(snapshot) and SC.Medical and type(SC.Medical.assess) == "function" then
        local assessment = SC.Medical.assess(player)
        if assessment and (assessment.critical or assessment.needsBandage) and type(SC.Medical.treat) == "function" then
            local ok, reason = SC.Medical.treat(actor, player, rootRuntime)
            if ok then return true, reason or "neutral_rescue" end
        end
    end
    if snapshot and snapshot.strongestSound and SC.Navigation and type(SC.Navigation.request) == "function" then
        local sound = snapshot.strongestSound
        local square = utility.gridSquare(sound.x, sound.y, sound.z)
        if square then
            return SC.Navigation.request(actor, square, "sneak", {
                action = "investigate_sound",
                snapshot = snapshot,
                neutral = true,
            })
        end
    end
    local choice = (utility.stableHash(utility.idOf(actor)) + math.floor(now() / math.max(1, utility.config("encounterIntervalMs") or 1000))) % 4
    if choice == 0 then
        local scavenged, reason = Encounter.tryScavenge(actor, player, rootRuntime, true)
        if scavenged then return true, reason or "neutral_scavenge" end
    elseif choice == 1 then
        local cover = indoorCover(actor, snapshot)
        if cover and SC.Navigation and type(SC.Navigation.request) == "function" then
            return SC.Navigation.request(actor, cover, "sneak", {
                action = "hide_indoors",
                snapshot = snapshot,
                neutral = true,
            })
        end
    end
    if player and utility.distance(actor, player) <= (utility.config("encounterActiveRadius") or 75)
        and not utility.canSee(player, actor) and SC.Navigation and type(SC.Navigation.request) == "function" then
        return SC.Navigation.request(actor, player, "sneak", {
            action = "approach_player_cautiously",
            snapshot = snapshot,
            neutral = true,
        })
    end
    return seekCover(actor, snapshot, "move_cautiously")
end

function Encounter.update(actor, player, runtime)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local rootRuntime = utility.actorState(actor, runtime)
    local state = stateFor(actor)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    local commands = commandState(actor)
    if commands.recruited then
        return Encounter.tryScavenge(actor, player, rootRuntime)
    end
    return neutralUpdate(actor, player, rootRuntime, snapshot, state)
end

local function visibleStatus(state)
    if not state then return nil end
    if state.task then return state.task end
    if state.lastStatus and now() <= (tonumber(state.lastStatus.expires) or 0) then
        return state.lastStatus
    end
    state.lastStatus = nil
    return nil
end

function Encounter.activity(actor)
    local status = actor and visibleStatus(states[actor]) or nil
    if not status then return nil end
    local itemName = status.itemName or status.itemType or "item"
    if status.phase == "select" then return "Selected " .. itemName end
    if status.phase == "approach" then return "Approaching " .. itemName end
    if status.phase == "settle" then return "Stopping to loot " .. itemName end
    if status.phase == "animate" then return "Looting " .. itemName end
    if status.phase == "commit" or status.phase == "verify" then
        return "Verifying " .. itemName
    end
    if status.phase == "complete" then return "Picked up " .. itemName end
    if status.phase == "failed" then return "Could not take " .. itemName end
    if status.phase == "cancelled" then return "Stopped looting " .. itemName end
    return "Scavenging"
end

function Encounter.status(actor)
    local state = actor and states[actor] or nil
    local status = visibleStatus(state)
    if not status and not (state and state.lastLoot) then return nil end
    return {
        phase = status and status.phase or nil,
        reason = status and status.reason or nil,
        itemType = status and status.itemType or nil,
        itemName = status and status.itemName or nil,
        category = status and status.category or nil,
        source = status and status.sourceKind or nil,
        destination = status and status.destinationKind or nil,
        destinationName = status and status.destinationName or nil,
        progress = status and status.progress or nil,
        total = status and status.total or nil,
        lastLoot = state and state.lastLoot and U().copyShallow(state.lastLoot) or nil,
    }
end

function Encounter.cancelScavenge(actor, reason)
    local state = actor and states[actor] or nil
    if not state then return true, reason or "no_scavenge_task" end
    if not state.task then
        clearSearchFields(actor, state)
        state.lastStatus = nil
        return true, reason or "scavenge_search_cancelled"
    end
    resetScavengeTarget(actor, state, {
        cancelVisual = true, stopMovement = true,
        reason = reason or "cancelled", phase = "cancelled",
        memoryResult = "interrupted", time = now(),
    })
    return true, reason or "scavenge_cancelled"
end

function Encounter.peek(actor)
    return actor and states[actor] or nil
end

function Encounter.reset(actor)
    if actor then
        local state = states[actor]
        if state and state.task then
            resetScavengeTarget(actor, state, {
                cancelVisual = true, stopMovement = true, reason = "reset",
                status = false,
            })
        elseif state and state.container then
            releaseContainer(state.container, actor)
        end
        clearSearchFields(actor, state)
        releasePlayerSupply(actor, state)
        states[actor] = nil
    else
        states = setmetatable({}, { __mode = "k" })
        containerReservations = setmetatable({}, { __mode = "k" })
        corpseContainers = setmetatable({}, { __mode = "k" })
        failedContainers = setmetatable({}, { __mode = "k" })
    end
end

return Encounter
