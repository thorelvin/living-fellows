-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Downtime = SC.Downtime or {}
local Downtime = SC.Downtime
local states = setmetatable({}, { __mode = "k" })
local reservations = setmetatable({}, { __mode = "k" })
local visualActivities = {
    read = true, repair = true, craft_supply = true,
    wash_self = true, wash_equipment = true,
}

local function U()
    return SC.GameplayUtil
end

local function supervisor()
    return type(SC.ActionSupervisor) == "table" and SC.ActionSupervisor or nil
end

local function debugTrace(actor, event, activity, reason)
    local utility = U()
    if not utility or utility.config("debugSpawnEnabled") ~= true then return end
    print("[SurvivorCompanion][downtime] actor=" .. tostring(utility.idOf(actor))
        .. " event=" .. tostring(event)
        .. " kind=" .. tostring(activity and activity.kind or "none")
        .. " reason=" .. tostring(reason or "none"))
end

local function stateFor(actor)
    local state = states[actor]
    if not state then
        state = { safeSince = nil, active = nil, idleStopped = false, nextEvaluationAt = 0 }
        states[actor] = state
    end
    return state
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, value = pcall(SC.Commands.peek, actor)
        if ok and type(value) == "table" then return value end
    end
    return { order = "stay", commandSerial = 0, recruited = false }
end

local function reserve(value, actor, now)
    if not value then return true end
    local existing = reservations[value]
    if existing and existing.actor ~= actor and existing.expires > now then return false end
    reservations[value] = {
        actor = actor,
        expires = now + (U().config("downtimeReservationMs") or 30000),
    }
    return true
end

local function release(value, actor)
    local existing = value and reservations[value]
    if existing and existing.actor == actor then reservations[value] = nil end
end

local function releaseActivity(actor, activity)
    if not activity then return end
    release(activity.object, actor)
    release(activity.item, actor)
    release(activity.material, actor)
    if activity.scraps then
        for _, item in ipairs(activity.scraps) do release(item, actor) end
    end
end

local function dangerPresent(snapshot)
    if type(snapshot) ~= "table" then return false end
    return (snapshot.immediateCount or 0) > 0 or (snapshot.threatCount or 0) > 0
        or (snapshot.player and snapshot.player.danger or 0) > 0
end

local function objectOpen(object)
    local value, ok = U().call(object, "IsOpen")
    if ok then return value == true end
    value, ok = U().call(object, "isOpen")
    return ok and value == true
end

local function isCurtain(object)
    local utility = U()
    if utility.instanceOf(object, "IsoCurtain") then return true end
    local objectType, typeOk = utility.call(object, "getType")
    local name, nameOk = utility.call(object, "getName")
    local textValue = string.lower(
        (typeOk and tostring(objectType) or "") .. " " .. (nameOk and tostring(name) or "")
    )
    return string.find(textValue, "curtain", 1, true) ~= nil
end

local function worldHour()
    if type(getGameTime) ~= "function" then return 12 end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime then return 12 end
    local hour, hourOk = U().call(gameTime, "getHour")
    if hourOk and type(hour) == "number" then return hour end
    return 12
end

local orderAllowsIdle

local function sameBuilding(actorSquare, candidateSquare)
    local actorRoom, actorRoomOk = U().call(actorSquare, "getRoom")
    local candidateRoom, candidateRoomOk = U().call(candidateSquare, "getRoom")
    if not actorRoomOk or not candidateRoomOk or actorRoom == nil or candidateRoom == nil then
        return false
    end
    if actorRoom == candidateRoom then return true end
    local actorBuilding, actorBuildingOk = U().call(actorRoom, "getBuilding")
    local candidateBuilding, candidateBuildingOk = U().call(candidateRoom, "getBuilding")
    return actorBuildingOk and candidateBuildingOk and actorBuilding ~= nil
        and actorBuilding == candidateBuilding
end

local function nearbyCurtain(actor, desiredOpen)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return nil end
    local actorSquare = utility.squareOf(actor)
    local radius = math.max(1, math.min(8,
        math.floor(utility.config("curtainSearchRadius") or 5)))
    local squareBudget = math.max(9, math.min(289,
        math.floor(utility.config("curtainSearchSquareBudget") or 121)))
    local objectBudget = math.max(48, math.min(256,
        math.floor(utility.config("curtainSearchObjectBudget") or 128)))
    local inspected = 0
    local squaresInspected = 0
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    squaresInspected = squaresInspected + 1
                    if squaresInspected > squareBudget then return nil end
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    local found
                    if sameBuilding(actorSquare, square) then
                        utility.squareObjects(square, function(object)
                            inspected = inspected + 1
                            if inspected > objectBudget then return false end
                            if isCurtain(object) and objectOpen(object) ~= desiredOpen then
                                found = object
                                return false
                            end
                        end, math.max(0, objectBudget - inspected))
                    end
                    if found then return found, square end
                    if inspected >= objectBudget then return nil end
                end
            end
        end
    end
    return nil
end

local function clearCurtainTask(actor, state)
    local task = state and state.curtainTask or nil
    if not task then return false end
    release(task.object, actor)
    state.curtainTask = nil
    return true
end

local function processCurtainTask(actor, state, commands, snapshot, now)
    local task = state.curtainTask
    if not task then return false, false, "no_curtain_task" end
    if dangerPresent(snapshot) or (commands.commandSerial or 0) ~= task.commandSerial
        or now >= (task.expiresAt or 0) then
        clearCurtainTask(actor, state)
        return true, false, "curtain_task_cancelled"
    end
    local square = U().squareOf(task.object)
    if not square or not isCurtain(task.object) then
        clearCurtainTask(actor, state)
        return true, false, "curtain_target_changed"
    end
    if objectOpen(task.object) == task.desiredOpen then
        clearCurtainTask(actor, state)
        return true, true, task.desiredOpen and "curtain_already_open" or "curtain_already_closed"
    end
    if not reserve(task.object, actor, now) then
        clearCurtainTask(actor, state)
        return true, false, "curtain_reserved"
    end
    if U().distance(actor, square) > 1.75 then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            clearCurtainTask(actor, state)
            return true, false, "navigation_unavailable"
        end
        local mode = commands.combatDoctrine == "stealth" and "sneak" or "walk"
        local accepted, reason = SC.Navigation.request(actor, square, mode, {
            action = "approach_interaction",
            targetSquare = square,
            object = task.object,
            environmentalTask = "curtain",
        })
        if not accepted then
            clearCurtainTask(actor, state)
            return true, false, reason or "curtain_approach_rejected"
        end
        return true, true, "approaching_curtain"
    end
    if not SC.Navigation or type(SC.Navigation.interact) ~= "function" then
        clearCurtainTask(actor, state)
        return true, false, "navigation_unavailable"
    end
    local accepted, reason = SC.Navigation.interact(actor, task.object,
        task.desiredOpen and "open_curtain" or "close_curtain")
    clearCurtainTask(actor, state)
    if not accepted then return true, false, reason or "curtain_interaction_rejected" end
    return true, true, task.desiredOpen and "curtain_opened" or "curtain_closed"
end

-- Bounded environmental behavior: search only the current building, cap both
-- visited squares and objects, reserve the chosen curtain, then use ordinary
-- Navigation so the NPC must physically approach it before toggling it.
function Downtime.considerCurtain(actor, snapshot, current, player)
    local utility = U()
    if not utility.isValidActor(actor) then return false, false, "invalid_actor" end
    local now = current or utility.nowMs()
    local commands = commandState(actor)
    local state = stateFor(actor)
    if state.curtainTask then
        return processCurtainTask(actor, state, commands, snapshot, now)
    end
    if dangerPresent(snapshot) or not orderAllowsIdle(commands, actor, player) then
        return false, false, "curtain_unsafe_or_busy"
    end
    local interval = utility.config("curtainDecisionIntervalMs") or 12000
    if not utility.isDue(actor, "downtime_curtain", interval, now) then
        return false, false, "curtain_deferred"
    end
    local actorSquare = utility.squareOf(actor)
    local room, roomOk = utility.call(actorSquare, "getRoom")
    local indoors = roomOk and room ~= nil
    if not indoors then return false, false, "curtain_not_indoors" end
    local hour = worldHour()
    local night = hour >= 20 or hour < 6
    local desiredOpen
    local stealth = commands.combatDoctrine == "stealth" or commands.moveMode == "sneak"
        or commands.holdFire == true
    local phase = math.floor(now / math.max(1, interval))
    local baseSeed = utility.stableHash(utility.idOf(actor) .. ":curtain")
    local mixedSeed = (baseSeed + (phase % 2147483647) * 1103515245) % 2147483647
    local roll = math.floor(mixedSeed / 65536) % 10
    if night then
        desiredOpen = false
    elseif stealth then
        -- A stealth companion sometimes spends safe downtime improving
        -- concealment, but never reverses it by opening a curtain.
        if roll <= 3 then desiredOpen = false end
    elseif roll == 0 then
        desiredOpen = false
    elseif roll == 1 then
        desiredOpen = true
    end
    if desiredOpen == nil then return false, false, "curtain_not_useful" end
    local curtain, curtainSquare = nearbyCurtain(actor, desiredOpen)
    if not curtain then return false, false, "no_curtain_change" end
    if not reserve(curtain, actor, now) then
        return true, false, "curtain_reserved"
    end
    state.curtainTask = {
        object = curtain,
        square = curtainSquare,
        desiredOpen = desiredOpen,
        commandSerial = commands.commandSerial or 0,
        startedAt = now,
        expiresAt = now + (utility.config("curtainTaskTimeoutMs") or 30000),
    }
    return processCurtainTask(actor, state, commands, snapshot, now)
end

orderAllowsIdle = function(commands, actor, player, snapshot)
    if not commands.recruited then return false end
    if commands.order == "stay" or commands.order == "guard"
        or commands.order == "base_duty" then return true end
    if commands.order == "follow" and player then
        local indoors = type(snapshot) == "table" and snapshot.indoors == true
        if not indoors then
            local square = U().squareOf(actor)
            local room, roomOk = U().call(square, "getRoom")
            indoors = roomOk and room ~= nil
        end
        if not indoors then return false end
        local distance = U().distance(actor, player)
        return distance <= math.max(3, (commands.followDistance or 3) + 1.5)
    end
    return false
end

local function isLiterature(item)
    local utility = U()
    local category, categoryOk = utility.call(item, "getCategory")
    if categoryOk and tostring(category) == "Literature" then return true end
    local itemType = string.lower(utility.itemType(item))
    return string.find(itemType, "book", 1, true) ~= nil
        or string.find(itemType, "magazine", 1, true) ~= nil
end

local function readActivity(actor, items)
    local utility = U()
    for _, item in ipairs(items) do
        if isLiterature(item) then
            local pages, pagesOk = utility.call(item, "getNumberOfPages")
            local fullType = utility.itemType(item)
            local alreadyRead, readOk = utility.call(actor, "getAlreadyReadPages", fullType)
            local useful = not pagesOk or (type(pages) == "number" and pages > 0
                and (not readOk or type(alreadyRead) ~= "number" or alreadyRead < pages))
            if useful then
                return {
                    kind = "read",
                    score = 34,
                    item = item,
                    fact = { activity = "read", itemType = utility.itemType(item) },
                }
            end
        end
    end
    return nil
end

local function repairActivity(actor, items)
    local utility = U()
    local damaged
    for _, item in ipairs(items) do
        local condition, conditionOk = utility.call(item, "getCondition")
        local maximum, maxOk = utility.call(item, "getConditionMax")
        if conditionOk and maxOk and type(condition) == "number" and type(maximum) == "number"
            and maximum > 0 and condition / maximum < 0.65
            and (utility.instanceOf(item, "HandWeapon") or utility.hasMethod(item, "getMaxDamage")) then
            damaged = item
            break
        end
    end
    if not damaged then return nil end
    for _, material in ipairs(items) do
        local itemType = string.lower(utility.itemType(material))
        local protected = SC.PersonalItems and SC.PersonalItems.isProtected(
            material, actor, "craft_material")
        if not protected and material ~= damaged and (string.find(itemType, "ducttape", 1, true)
            or string.find(itemType, "woodglue", 1, true)
            or string.find(itemType, "glue", 1, true)) then
            return {
                kind = "repair",
                score = 43,
                item = damaged,
                material = material,
                fact = { activity = "repair", itemType = utility.itemType(damaged) },
            }
        end
    end
    return nil
end

local function dirtyBandageActivity(actor)
    if not SC.Medical or type(SC.Medical.assess) ~= "function" then return nil end
    local assessment = SC.Medical.assess(actor)
    if assessment and assessment.dirtyBandages > 0 then
        if type(SC.Medical.canReplaceDirtyBandage) == "function" then
            local available = SC.Medical.canReplaceDirtyBandage(actor)
            if available ~= true then return nil end
        end
        return {
            kind = "replace_bandage",
            score = 75,
            fact = { activity = "replace_bandage" },
        }
    end
    return nil
end

local function craftActivity(actor, items)
    local utility = U()
    for _, item in ipairs(items) do
        local itemType = string.lower(utility.itemType(item))
        local protected = SC.PersonalItems and SC.PersonalItems.isProtected(
            item, actor, "craft_material")
        if not protected and (itemType == "sheet" or itemType == "base.sheet") then
            return {
                kind = "craft_supply",
                score = 27,
                scraps = { item },
                outputType = "Base.SheetRope",
                fact = { activity = "craft_supply", itemType = "Base.SheetRope" },
            }
        end
    end
    return nil
end

local function washSourceValid(object)
    local amount, amountOk = U().call(object, "getFluidAmount")
    if not amountOk or (tonumber(amount) or 0)
        < (U().config("downtimeWashMinimumWater") or 4) then return false end
    local tainted, taintedOk = U().call(object, "isTaintedWater")
    return not taintedOk or tainted ~= true
end

local function nearbyWashSource(actor)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return nil, nil end
    local radius = math.max(1, math.min(8,
        math.floor(utility.config("downtimeWashRadius") or 4)))
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    local found
                    utility.squareObjects(square, function(object)
                        if washSourceValid(object) then found = object return false end
                    end, 48)
                    if found then return found, square end
                end
            end
        end
    end
    return nil, nil
end

local function bodyDirt(actor)
    local visual, visualOk = U().call(actor, "getHumanVisual")
    if not visualOk or not visual then return 0 end
    local score = 0
    local ok = pcall(function()
        for index = 0, BloodBodyPartType.MAX:index() - 1 do
            local part = BloodBodyPartType.FromIndex(index)
            score = score + math.max(0, tonumber(visual:getBlood(part)) or 0)
                + math.max(0, tonumber(visual:getDirt(part)) or 0)
        end
    end)
    return ok and score or 0
end

local function itemDirt(item)
    local blood, bloodOk = U().call(item, "getBloodLevel")
    local dirt, dirtOk = U().call(item, "getDirtiness")
    if not bloodOk and not dirtOk then return 0 end
    return math.max(0, tonumber(blood) or 0) + math.max(0, tonumber(dirt) or 0)
end

local function washActivity(actor, items)
    local bodyScore = bodyDirt(actor)
    local bestItem, bestItemScore
    for _, item in ipairs(items) do
        local score = itemDirt(item)
        if score > 0.01 and (not bestItemScore or score > bestItemScore) then
            bestItem, bestItemScore = item, score
        end
    end
    if bodyScore <= 0.01 and not bestItem then return nil end
    local source, square = nearbyWashSource(actor)
    if not source then return nil end
    if bodyScore > 0.01 and bodyScore * 100 >= (bestItemScore or 0) then
        return {
            kind = "wash_self", score = 48 + math.min(25, bodyScore * 5),
            object = source, square = square,
            fact = { activity = "wash_self" },
        }
    end
    return {
        kind = "wash_equipment", score = 40 + math.min(28, (bestItemScore or 0) * 0.2),
        object = source, square = square, item = bestItem,
        fact = { activity = "wash_equipment", itemType = U().itemType(bestItem) },
    }
end

local function isSeat(object)
    local utility = U()
    local name, nameOk = utility.call(object, "getName")
    local textValue = nameOk and string.lower(tostring(name)) or ""
    if string.find(textValue, "chair", 1, true) or string.find(textValue, "sofa", 1, true) then return true end
    local sprite, spriteOk = utility.call(object, "getSprite")
    if spriteOk and sprite then
        local spriteName, spriteNameOk = utility.call(sprite, "getName")
        local lowered = spriteNameOk and string.lower(tostring(spriteName)) or ""
        if string.find(lowered, "chair", 1, true) or string.find(lowered, "sofa", 1, true) then return true end
        local properties, propertiesOk = utility.call(sprite, "getProperties")
        if propertiesOk and properties then
            local chair, chairOk = utility.call(properties, "Is", "IsChair")
            if chairOk and chair then return true end
        end
    end
    return false
end

local function seatActivity(actor)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return nil end
    for distance = 0, 4 do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    local found
                    utility.squareObjects(square, function(object)
                        if isSeat(object) then found = object return false end
                    end, 32)
                    if found then
                        return {
                            kind = "sit",
                            score = 12,
                            object = found,
                            square = square,
                            fact = { activity = "sit" },
                        }
                    end
                end
            end
        end
    end
    return nil
end

local function candidates(actor, commands, state, current, desiredKind)
    local utility = U()
    commands = type(commands) == "table" and commands or {}
    local workMode = commands.workMode or "auto"
    local inventory = utility.inventory(actor)
    local items = utility.inventoryItems(inventory, 100)
    if SC.Logistics and type(SC.Logistics.audit) == "function" then
        local ok, audit = pcall(SC.Logistics.audit, actor)
        if ok and type(audit) == "table" and type(audit.items) == "table" then
            items = {}
            for _, record in ipairs(audit.items) do items[#items + 1] = record.item end
        end
    end
    local filtered = {}
    local activity = dirtyBandageActivity(actor)
    if activity then filtered[#filtered + 1] = activity end
    activity = washActivity(actor, items)
    if activity then filtered[#filtered + 1] = activity end
    if workMode == "craft" then
        activity = craftActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
    elseif workMode == "idle" then
        activity = readActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = seatActivity(actor)
        if activity then filtered[#filtered + 1] = activity end
    else
        activity = repairActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = readActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = craftActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = seatActivity(actor)
        if activity then filtered[#filtered + 1] = activity end
    end
    if desiredKind ~= nil then
        for index = #filtered, 1, -1 do
            if filtered[index].kind ~= desiredKind then table.remove(filtered, index) end
        end
    end
    for _, candidate in ipairs(filtered) do
        if SC.Personality and type(SC.Personality.adjustDowntime) == "function" then
            candidate.score = candidate.score
                + SC.Personality.adjustDowntime(commands.personalityProfile, candidate)
        end
        if SC.Objectives and type(SC.Objectives.activityBonus) == "function" then
            candidate.score = candidate.score
                + SC.Objectives.activityBonus(commands.objectives, candidate)
        end
    end
    local lastFact = state and state.lastFact or nil
    if type(lastFact) == "table" and tonumber(lastFact.completedAt) then
        local age = current - tonumber(lastFact.completedAt)
        if age >= 0 and age < (utility.config("ambientRepeatCooldownMs") or 60000)
            and (lastFact.activity == "read" or lastFact.activity == "sit") then
            for index = #filtered, 1, -1 do
                if filtered[index].kind == lastFact.activity then table.remove(filtered, index) end
            end
        end
    end
    utility.sortByScoreDescending(filtered)
    return filtered
end

-- Read-only capability probe used by the base scheduler. It prevents the
-- operations queue from inventing repair/craft jobs that no resident can
-- currently perform with their real carried tools and materials.
function Downtime.canPerform(actor, desiredKind)
    if not U().isValidActor(actor) or type(desiredKind) ~= "string" then
        return false, "invalid_downtime_probe"
    end
    local rows = candidates(actor, commandState(actor), stateFor(actor), U().nowMs(), desiredKind)
    return #rows > 0, rows[1] and rows[1].kind or "no_matching_activity"
end

local function reserveActivity(actor, activity, now)
    local held = {}
    local function take(value)
        if not value then return true end
        if not reserve(value, actor, now) then return false end
        held[#held + 1] = value
        return true
    end
    if not take(activity.object) or not take(activity.item) or not take(activity.material) then
        for _, value in ipairs(held) do release(value, actor) end
        return false
    end
    if activity.scraps then
        for _, item in ipairs(activity.scraps) do
            if not take(item) then
                for _, value in ipairs(held) do release(value, actor) end
                return false
            end
        end
    end
    return true
end

local function activityTargetKey(activity)
    local utility = U()
    local target = activity.object or activity.item or activity.material
        or activity.scraps and activity.scraps[1]
    if target == nil then return tostring(activity.kind) end
    local x, y, z = utility.position(target)
    if x ~= nil then
        return tostring(activity.kind) .. ":" .. tostring(math.floor(x)) .. ":"
            .. tostring(math.floor(y)) .. ":" .. tostring(math.floor(z or 0))
    end
    return tostring(activity.kind) .. ":" .. tostring(utility.itemType(target))
end

local function releaseDowntimeResources(actor, state, activity, reason)
    activity = activity or state and state.active
    if not activity then return true, reason or "no_activity" end
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function"
        and activity.startedAt then
        pcall(SC.NativeActions.cancelVisual, actor, reason or "downtime_cancelled")
    end
    if activity.approaching and SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, reason or "downtime_cancelled")
    end
    releaseActivity(actor, activity)
    if state and state.active == activity then state.active = nil end
    return true, reason or "cancelled"
end

local function failActivity(actor, state, reason, detail)
    local activity = state and state.active
    if not activity then return false, reason or "no_activity" end
    debugTrace(actor, "finish_blocked", activity, reason)
    releaseDowntimeResources(actor, state, activity, reason)
    state.nextEvaluationAt = U().nowMs() + (U().config("downtimeIntervalMs") or 1500)
    local service = supervisor()
    if service and activity.supervisorToken
        and service.isCurrent(activity.supervisorToken) then
        service.fail(activity.supervisorToken, reason or "downtime_failed", detail)
    end
    return false, reason or "downtime_failed"
end

local function beginSupervisedActivity(actor, state, activity)
    local service = supervisor()
    if not service then return true end
    local token, reason = service.begin(actor, {
        owner = "downtime", action = tostring(activity.kind),
        targetKey = activityTargetKey(activity),
        targetLabel = activity.item and U().itemName(activity.item)
            or activity.kind,
        priority = service.Priority.DOWNTIME,
        interruptible = true, requiresVisual = false,
        allowedActions = {
            [activity.kind] = true,
            move_to_seat = true, move_to_water_source = true,
        },
        onCancel = function(_, cancelReason)
            return releaseDowntimeResources(actor, state, activity,
                cancelReason or "downtime_cancelled")
        end,
        metadata = { commandSerial = activity.commandSerial or 0 },
    })
    if not token then return false, reason or "downtime_owner_rejected" end
    activity.supervisorToken = token
    local resources = {}
    if activity.object then resources[#resources + 1] = activity.object end
    if activity.item then resources[#resources + 1] = activity.item end
    if activity.material then resources[#resources + 1] = activity.material end
    for _, value in ipairs(activity.scraps or {}) do resources[#resources + 1] = value end
    for _, value in ipairs(resources) do
        if value then
            local reserved, reserveReason = service.reserve(token, value, "downtime_resource")
            if reserved ~= true then
                service.fail(token, reserveReason or "reservation_lost")
                activity.supervisorToken = nil
                return false, reserveReason or "reservation_lost"
            end
        end
    end
    return true
end

local function startSupervisedVisual(actor, activity, detail)
    if not SC.NativeActions or type(SC.NativeActions.visualStatus) ~= "function" then
        return true
    end
    local service = supervisor()
    if not service or not activity.supervisorToken then return true end
    return service.expectVisual(activity.supervisorToken, detail)
end

local function transitionActivity(activity, phase, detail)
    local service = supervisor()
    if not service or not activity.supervisorToken then return true, phase end
    return service.transition(activity.supervisorToken, phase, detail)
end

local function beginActivity(actor, state, activity, commands, now)
    if activity.kind == "replace_bandage" then
        if not SC.Medical or type(SC.Medical.replaceDirtyBandage) ~= "function" then
            return false, "medical_unavailable"
        end
        return SC.Medical.replaceDirtyBandage(actor)
    end
    if not reserveActivity(actor, activity, now) then return false, "reserved" end
    activity.commandSerial = commands.commandSerial or 0
    local owned, ownerReason = beginSupervisedActivity(actor, state, activity)
    if owned ~= true then
        releaseActivity(actor, activity)
        return false, ownerReason or "downtime_owner_rejected"
    end
    local utility = U()
    local wash = activity.kind == "wash_self" or activity.kind == "wash_equipment"
    if (activity.kind == "sit" or wash) and activity.square
        and utility.distance(actor, activity.square) > (wash and 1.45 or 1.1) then
        if SC.Navigation and type(SC.Navigation.request) == "function" then
            local accepted, status = SC.Navigation.request(actor, activity.square, "walk", {
                action = wash and "move_to_water_source" or "move_to_seat",
                targetSquare = activity.square,
                object = activity.object,
                supervisorToken = activity.supervisorToken,
            })
            if not accepted then
                state.active = activity
                return failActivity(actor, state, status or "route_failed")
            end
            activity.approaching = true
            transitionActivity(activity, "approaching", { status = status })
        else
            state.active = activity
            return failActivity(actor, state, "navigation_unavailable")
        end
    else
        if visualActivities[activity.kind] then
            local expected, expectedReason = startSupervisedVisual(actor, activity, {
                action = activity.kind,
            })
            if expected ~= true then
                state.active = activity
                return failActivity(actor, state,
                    expectedReason or "visual_registration_failed")
            end
        end
        if not utility.move(actor, "walk", {
            action = activity.kind,
            item = activity.item,
            material = activity.material,
            object = activity.object,
            downtime = true,
            durationMs = utility.config("downtimeActivityMs") or 6000,
            supervisorToken = activity.supervisorToken,
        }) then
            state.active = activity
            return failActivity(actor, state, "animation_rejected")
        end
        activity.startedAt = now
        activity.actionAccepted = true
        transitionActivity(activity, visualActivities[activity.kind]
            and SC.NativeActions and type(SC.NativeActions.visualStatus) == "function"
            and "animating" or "settling", { action = activity.kind })
    end
    state.active = activity
    state.idleStopped = false
    debugTrace(actor, "start", activity, activity.approaching and "approaching" or "action_started")
    return true, activity.kind
end

local function useWashWater(source, amount)
    amount = math.max(0, tonumber(amount) or 0)
    if amount <= 0 then return true end
    local available, availableOk = U().call(source, "getFluidAmount")
    if not availableOk or (tonumber(available) or 0) < amount then return false end
    local result, usedOk = U().call(source, "useFluid", amount)
    if not usedOk or result == false then return false end
    U().call(source, "transmitModData")
    return true
end

local function completeWashSelf(actor, activity)
    local visual, visualOk = U().call(actor, "getHumanVisual")
    if not visualOk or not visual then return false end
    local dirty = {}
    local inspected = pcall(function()
        for index = 0, BloodBodyPartType.MAX:index() - 1 do
            local part = BloodBodyPartType.FromIndex(index)
            if (tonumber(visual:getBlood(part)) or 0) + (tonumber(visual:getDirt(part)) or 0) > 0 then
                dirty[#dirty + 1] = part
            end
        end
    end)
    if not inspected or #dirty == 0 then return false end
    local amount, amountOk = U().call(activity.object, "getFluidAmount")
    local available = amountOk and math.floor(tonumber(amount) or 0) or 0
    local count = math.min(#dirty, available)
    if count <= 0 or not useWashWater(activity.object, count) then return false end
    for index = 1, count do
        U().call(visual, "setBlood", dirty[index], 0)
        U().call(visual, "setDirt", dirty[index], 0)
    end
    U().call(actor, "resetModelNextFrame")
    if type(sendHumanVisual) == "function" then pcall(sendHumanVisual, actor) end
    return true
end

local function completeWashEquipment(actor, activity)
    local item = activity.item
    if not item or itemDirt(item) <= 0.01 then return false end
    local required = math.max(U().config("downtimeWashMinimumWater") or 4,
        math.min(20, math.ceil(4 + itemDirt(item) / 25)))
    if not useWashWater(activity.object, required) then return false end
    pcall(function()
        local clothingType = item:getBloodClothingType()
        local parts = BloodClothingType.getCoveredParts(clothingType)
        if parts then
            for index = 0, parts:size() - 1 do
                item:setBlood(parts:get(index), 0)
                item:setDirt(parts:get(index), 0)
            end
        end
    end)
    U().call(item, "setBloodLevel", 0)
    U().call(item, "setDirtiness", 0)
    U().call(item, "setWetness", 100)
    U().call(actor, "resetModelNextFrame")
    if type(syncVisuals) == "function" then pcall(syncVisuals, actor) end
    return itemDirt(item) <= 0.01
end

local function consumeExact(inventory, item)
    local utility = U()
    local result, ok = utility.call(inventory, "Remove", item)
    if ok then return result ~= false and not utility.inventoryContains(inventory, item) end
    if type(inventory) == "table" and type(inventory.items) == "table" then
        for index, value in ipairs(inventory.items) do
            if value == item then table.remove(inventory.items, index) return true end
        end
    end
    return false
end

local function completeRepair(actor, activity)
    local utility = U()
    local condition, conditionOk = utility.call(activity.item, "getCondition")
    local maximum, maxOk = utility.call(activity.item, "getConditionMax")
    if not conditionOk or not maxOk or not maximum then return false end
    local inventory = utility.inventory(actor)
    local restored = math.min(maximum, condition + math.max(1, math.floor(maximum * 0.25)))
    local setResult, setOk = utility.call(activity.item, "setCondition", restored)
    if not setOk or setResult == false then return false end
    local actual, actualOk = utility.call(activity.item, "getCondition")
    if actualOk and actual ~= restored then
        utility.call(activity.item, "setCondition", condition)
        return false
    end
    if consumeExact(inventory, activity.material) then return true end
    utility.call(activity.item, "setCondition", condition)
    return false
end

local function completeCraft(actor, activity)
    local utility = U()
    local inventory = utility.inventory(actor)
    local output = utility.addItem(inventory, activity.outputType)
    if not output then return false end
    local removed = {}
    for _, item in ipairs(activity.scraps or {}) do
        if not consumeExact(inventory, item) then
            consumeExact(inventory, output)
            for _, previous in ipairs(removed) do utility.addItem(inventory, previous) end
            return false
        end
        removed[#removed + 1] = item
    end
    return true
end

local function finishActivity(actor, state, now)
    local activity = state.active
    if not activity then return false, "none" end
    local committing, commitReason = transitionActivity(activity, "committing", {
        action = activity.kind,
    })
    if committing ~= true then return failActivity(actor, state,
        commitReason or "commit_rejected") end
    local success = true
    if activity.kind == "repair" then
        success = completeRepair(actor, activity)
    elseif activity.kind == "craft_supply" then
        success = completeCraft(actor, activity)
    elseif activity.kind == "read" then
        -- This is deliberate ambient downtime: retain the real book, play the
        -- verified human read action, and record the activity without granting
        -- free player-style skill-book progress.
        success = activity.actionAccepted == true
    elseif activity.kind == "sit" then
        success = activity.actionAccepted == true
    elseif activity.kind == "wash_self" then
        success = completeWashSelf(actor, activity)
    elseif activity.kind == "wash_equipment" then
        success = completeWashEquipment(actor, activity)
    end
    local failureReasons = {
        repair = "repair_commit_failed",
        craft_supply = "craft_commit_failed",
        read = "read_verification_failed",
        sit = "sit_verification_failed",
        wash_self = "wash_self_commit_failed",
        wash_equipment = "wash_equipment_commit_failed",
    }
    if not success then
        return failActivity(actor, state,
            failureReasons[activity.kind] or "downtime_commit_failed")
    end
    local verifying, verifyReason = transitionActivity(activity, "verifying", {
        action = activity.kind,
    })
    if verifying ~= true then return failActivity(actor, state,
        verifyReason or "verification_failed") end
    if success then
        local fact = U().copyShallow(activity.fact)
        fact.completedAt = now
        state.lastFact = fact
        if SC.Commands and type(SC.Commands.noteDowntime) == "function" then
            pcall(SC.Commands.noteDowntime, actor, fact)
        end
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "downtime_" .. tostring(activity.kind),
                "completed", { kind = "long" })
        end
    end
    releaseActivity(actor, activity)
    state.active = nil
    state.nextEvaluationAt = now + (U().config("downtimeIntervalMs") or 1500)
    local service = supervisor()
    if service and activity.supervisorToken and service.isCurrent(activity.supervisorToken) then
        service.complete(activity.supervisorToken, "completed", {
            activity = activity.kind, verified = true,
        })
    end
    debugTrace(actor, "finish", activity, "completed")
    return true, "completed"
end

function Downtime.cancel(actor, reason)
    local state = actor and states[actor]
    if not state then return false end
    local changed = clearCurtainTask(actor, state)
    if state.active then
        local activity = state.active
        local service = supervisor()
        if service and activity.supervisorToken and service.isCurrent(activity.supervisorToken) then
            local cancelled, cancelReason = service.cancel(actor,
                reason or "downtime_cancelled", nil, false)
            if cancelled ~= true then
                debugTrace(actor, "cancel_blocked", activity, cancelReason)
                return false, cancelReason or "downtime_cancel_rejected"
            end
        else
            releaseDowntimeResources(actor, state, activity,
                reason or "downtime_cancelled")
        end
        debugTrace(actor, "cancel", activity, reason)
        changed = true
    end
    if not changed then return false end
    state.safeSince = nil
    state.idleStopped = false
    U().stop(actor)
    return true, reason or "cancelled"
end

function Downtime.update(actor, player, runtime, desiredKind)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local rootRuntime = utility.actorState(actor, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    local commands = commandState(actor)
    local state = stateFor(actor)
    if state.lastFact == nil and type(commands.lastDowntime) == "table" then
        state.lastFact = utility.copyShallow(commands.lastDowntime)
    end
    local current = utility.nowMs()
    local unsafe = dangerPresent(snapshot) or not orderAllowsIdle(commands, actor, player, snapshot)
    local medicalState = SC.Medical and type(SC.Medical.peek) == "function"
        and SC.Medical.peek(actor) or nil
    if unsafe then
        state.safeSince = nil
        if state.active or state.curtainTask then Downtime.cancel(actor, "danger_or_order") end
        if medicalState and medicalState.dirtyOnly
            and type(SC.Medical.cancel) == "function" then
            SC.Medical.cancel(actor, "danger_or_order")
        end
        return false, "unsafe_or_busy"
    end

    -- Downtime may propose a dirty-bandage change, but Medical owns and
    -- advances the entire transaction once accepted.
    if medicalState and medicalState.dirtyOnly
        and type(SC.Medical.replaceDirtyBandage) == "function" then
        return SC.Medical.replaceDirtyBandage(actor)
    end

    if not state.active then
        local curtainAttempted, curtainAccepted, curtainReason = Downtime.considerCurtain(
            actor, snapshot, current, player)
        if curtainAttempted then
            if not curtainAccepted then return false, curtainReason end
            return true, curtainReason
        end
    end

    if not state.safeSince then state.safeSince = current end
    if state.active then
        if (commands.commandSerial or 0) ~= state.active.commandSerial then
            Downtime.cancel(actor, "new_order")
            return false, "cancelled_for_order"
        end
        if state.active.kind == "sit" and state.active.square
            and utility.distance(actor, state.active.square) > 1.1 then
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, status = SC.Navigation.request(actor, state.active.square, "walk", {
                    action = "move_to_seat",
                    targetSquare = state.active.square,
                    supervisorToken = state.active.supervisorToken,
                })
                if not accepted then
                    return failActivity(actor, state, status or "route_failed")
                end
                transitionActivity(state.active, "approaching", { status = status })
            else
                return failActivity(actor, state, "navigation_unavailable")
            end
            return true, "approaching_seat"
        end
        local washing = state.active.kind == "wash_self"
            or state.active.kind == "wash_equipment"
        if washing and state.active.approaching
            and utility.distance(actor, state.active.square) > 1.45 then
            if SC.Navigation and type(SC.Navigation.request) == "function" then
                local accepted, status = SC.Navigation.request(actor, state.active.square, "walk", {
                    action = "move_to_water_source",
                    targetSquare = state.active.square,
                    object = state.active.object,
                    supervisorToken = state.active.supervisorToken,
                })
                if not accepted then
                    return failActivity(actor, state, status or "route_failed")
                end
                transitionActivity(state.active, "approaching", { status = status })
            end
            return true, "approaching_wash_source"
        end
        if washing and state.active.approaching then
            local expected, expectedReason = startSupervisedVisual(actor, state.active, {
                action = state.active.kind,
            })
            if expected ~= true then return failActivity(actor, state,
                expectedReason or "visual_registration_failed") end
            if not utility.move(actor, "walk", {
                action = state.active.kind,
                item = state.active.item,
                object = state.active.object,
                downtime = true,
                durationMs = utility.config("downtimeActivityMs") or 6000,
                supervisorToken = state.active.supervisorToken,
            }) then
                return failActivity(actor, state, "animation_rejected")
            end
            state.active.approaching = nil
            state.active.actionAccepted = true
            state.active.startedAt = current
            transitionActivity(state.active, "animating", { action = state.active.kind })
            return true, state.active.kind
        end
        if state.active.kind == "sit" and state.active.approaching then
            if not utility.move(actor, "walk", {
                action = "sit",
                object = state.active.object,
                downtime = true,
                supervisorToken = state.active.supervisorToken,
            }) then
                return failActivity(actor, state, "animation_rejected")
            end
            state.active.approaching = nil
            state.active.actionAccepted = true
            state.active.startedAt = current
            transitionActivity(state.active, "settling", { action = "sit" })
            return true, "sit"
        end
        local duration = utility.config("downtimeActivityMs") or 6000
        if SC.Autonomy and type(SC.Autonomy.workDuration) == "function" then
            local ok, adjusted = pcall(SC.Autonomy.workDuration, actor, duration)
            if ok and tonumber(adjusted) then duration = tonumber(adjusted) end
        end
        if state.active.startedAt and visualActivities[state.active.kind]
            and SC.NativeActions and type(SC.NativeActions.visualStatus) == "function" then
            local visualState = SC.NativeActions.visualStatus(actor, state.active.kind)
            if visualState == "active" then
                local service = supervisor()
                if service and state.active.supervisorToken then
                    service.progress(state.active.supervisorToken,
                        "visual:" .. tostring(state.active.startedAt), {
                            action = state.active.kind,
                        })
                end
                return true, state.active.kind
            end
            if visualState == "completed" then
                if type(SC.NativeActions.clearVisual) == "function" then
                    SC.NativeActions.clearVisual(actor)
                end
                state.active.visualCompleted = true
                local service = supervisor()
                if service and state.active.supervisorToken then
                    local verified, verifyReason = service.markVisualVerified(
                        state.active.supervisorToken, { action = state.active.kind })
                    if verified ~= true then return failActivity(actor, state,
                        verifyReason or "animation_verification_failed") end
                end
                return finishActivity(actor, state, current)
            end
            return failActivity(actor, state,
                "animation_" .. tostring(visualState))
        elseif state.active.startedAt and current - state.active.startedAt >= duration then
            return finishActivity(actor, state, current)
        end
        return true, state.active.kind
    end

    if current - state.safeSince < (utility.config("downtimeSafeMs") or 5000) then
        if not state.idleStopped then utility.stop(actor) state.idleStopped = true end
        return false, "settling"
    end
    if current < state.nextEvaluationAt then return false, "cooldown" end
    state.nextEvaluationAt = current + (utility.config("downtimeIntervalMs") or 1500)
    for _, activity in ipairs(candidates(actor, commands, state, current, desiredKind)) do
        local ok, reason = beginActivity(actor, state, activity, commands, current)
        if ok then return true, reason end
    end
    if not state.idleStopped then utility.stop(actor) state.idleStopped = true end
    return false, "stable_idle"
end

function Downtime.peek(actor)
    return actor and states[actor] or nil
end

function Downtime.reset(actor)
    if actor then
        Downtime.cancel(actor, "reset")
        states[actor] = nil
    else
        local actors = {}
        for value in pairs(states) do actors[#actors + 1] = value end
        for _, value in ipairs(actors) do Downtime.cancel(value, "reset_all") end
        states = setmetatable({}, { __mode = "k" })
        reservations = setmetatable({}, { __mode = "k" })
    end
end

return Downtime
