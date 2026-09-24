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
    wash_self = true, wash_equipment = true, study_corpse = true, pay_respects = true,
    workout = true, write_diary = true,
}
local restPostures = { sit = true, rest_bed = true, rest_floor = true }

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

-- A camp book is borrowed only for the supervised read action. Return the
-- exact object to the exact marked container on every terminal path. If the
-- container becomes unavailable or rejects the transfer, keeping the book on
-- the companion is the lossless fallback; a later logistics pass may deposit
-- it, but the item is never copied or discarded.
local function returnBorrowedReadingItem(actor, activity)
    if not activity or activity.borrowedReading ~= true or not activity.item then return true end
    local utility = U()
    local source = activity.borrowedFrom
    local inventory = utility.inventory(actor)
    if source and utility.inventoryContains(source, activity.item) then
        activity.borrowedReading = false
        return true
    end
    if not source or not inventory or not utility.inventoryContains(inventory, activity.item) then
        debugTrace(actor, "borrow_return_blocked", activity, "borrowed_book_unavailable")
        return false
    end
    local atSource = activity.borrowedOwner ~= nil
        and utility.directInteractionAccess(actor, activity.borrowedOwner)
    if atSource ~= true then
        -- Cancellation may happen after danger or a new order has pulled the
        -- reader away.  Keeping the exact book on the actor is lossless;
        -- teleporting it through a wall back into its shelf is not.
        debugTrace(actor, "borrow_return_blocked", activity,
            "borrowed_book_source_not_in_reach")
        return false
    end
    local returned, reason = utility.transferItemVerified(inventory, source, activity.item)
    if returned == true then
        activity.borrowedReading = false
        return true
    end
    debugTrace(actor, "borrow_return_blocked", activity, reason or "borrowed_book_return_failed")
    return false
end

local function releaseActivity(actor, activity)
    if not activity then return end
    -- Getting up from a seat may earn a stretch (SCGestures), once per sit.
    if restPostures[activity.kind]
        and activity.preserveSeating ~= true
        and activity.actionAccepted == true and not activity.stoodUpNoted
        and SC.Gestures and type(SC.Gestures.noteStoodUp) == "function" then
        activity.stoodUpNoted = true
        pcall(SC.Gestures.noteStoodUp, actor, U().nowMs())
    end
    if restPostures[activity.kind] and activity.preserveSeating ~= true
        and SC.NativeActions and type(SC.NativeActions.leaveSeating) == "function" then
        pcall(SC.NativeActions.leaveSeating, actor)
    end
    returnBorrowedReadingItem(actor, activity)
    release(activity.object, actor)
    release(activity.item, actor)
    release(activity.material, actor)
    if activity.scraps then
        for _, item in ipairs(activity.scraps) do release(item, actor) end
    end
end

-- Threats that combat has just judged out of reach (a zombie behind the base
-- fence) do not stop idle life; anything close, attacking, human or
-- surrounding does (SCCombat.onlyUnreachableThreats).
local function dangerPresent(snapshot, actor, now)
    if type(snapshot) ~= "table" then return false end
    if (snapshot.immediateCount or 0) > 0
        or (snapshot.player and snapshot.player.danger or 0) > 0 then
        return true
    end
    if (snapshot.threatCount or 0) == 0 then return false end
    local combat = SC.Combat
    if actor == nil or type(combat) ~= "table"
        or type(combat.onlyUnreachableThreats) ~= "function" then
        return true
    end
    local ok, unreachable = pcall(combat.onlyUnreachableThreats, actor, snapshot, now)
    return not (ok and unreachable == true)
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
    if dangerPresent(snapshot, actor, now) or (commands.commandSerial or 0) ~= task.commandSerial
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
    if dangerPresent(snapshot, actor, now) or not orderAllowsIdle(commands, actor, player) then
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

local function literatureUseful(actor, item)
    if not isLiterature(item) then return false end
    local utility = U()
    local pages, pagesOk = utility.call(item, "getNumberOfPages")
    local fullType = utility.itemType(item)
    local alreadyRead, readOk = utility.call(actor, "getAlreadyReadPages", fullType)
    return not pagesOk or (type(pages) == "number" and pages > 0
        and (not readOk or type(alreadyRead) ~= "number" or alreadyRead < pages))
end

local function readActivity(actor, items)
    local utility = U()
    for _, item in ipairs(items) do
        if literatureUseful(actor, item) then
            return {
                kind = "read",
                score = 34,
                item = item,
                fact = { activity = "read", itemType = utility.itemType(item) },
            }
        end
    end
    return nil
end

-- A resident should use the books the camp actually owns, not stand beside a
-- marked bookshelf because its personal inventory happens to be empty. The
-- scan is base-only, close-range and globally bounded per decision. Reserves
-- and personal/work-cargo ownership are honoured before offering the exact
-- book as a downtime resource.
local function campReadingActivity(actor)
    local utility = U()
    local base = SC.BaseLife
    if not base or type(base.isInside) ~= "function"
        or type(base.storageRows) ~= "function"
        or type(base.resolveContainer) ~= "function"
        or base.isInside(actor) ~= true then return nil end
    local radius = tonumber(utility.config("campReadingStorageRadius")) or 8
    local storageLimit = math.max(1,
        math.floor(tonumber(utility.config("campReadingStorageBudget")) or 8))
    local remaining = math.max(1,
        math.floor(tonumber(utility.config("campReadingItemBudget")) or 120))
    -- Dedicated library storage is searched first, so a camp with many marked
    -- containers cannot exhaust this bounded scan before reaching its shelf.
    local storages, seen = {}, {}
    local function append(rows)
        for _, storage in ipairs(rows or {}) do
            local key = storage.id or storage
            if not seen[key] then
                seen[key] = true
                storages[#storages + 1] = storage
            end
        end
    end
    append(base.storageRows("literature", true))
    append(base.storageRows(nil, true))
    local inspected = 0
    for _, storage in ipairs(storages) do
        inspected = inspected + 1
        if inspected > storageLimit or remaining <= 0 then break end
        local container, object = base.resolveContainer(storage)
        if container and object and utility.sameFloor(actor, object)
            and utility.distance(actor, object) <= radius then
            local items = utility.inventoryItems(container, remaining)
            remaining = remaining - #items
            local counts = {}
            for _, item in ipairs(items) do
                local itemType = utility.itemType(item)
                counts[itemType] = (counts[itemType] or 0) + 1
            end
            for _, item in ipairs(items) do
                local itemType = utility.itemType(item)
                local perType = type(storage.reserves) == "table"
                    and tonumber(storage.reserves[itemType]) or nil
                local reserveCount = math.max(0, math.floor(perType
                    or tonumber(storage.reserve) or 0))
                local protected = SC.PersonalItems
                    and type(SC.PersonalItems.isProtected) == "function"
                    and SC.PersonalItems.isProtected(item, actor, "camp_reading_borrow")
                if counts[itemType] > reserveCount and not protected
                    and literatureUseful(actor, item) then
                    return {
                        kind = "read",
                        score = 32,
                        item = item,
                        object = object,
                        square = utility.squareOf(object),
                        borrowedFrom = container,
                        borrowedOwner = object,
                        borrowedStorageId = storage.id,
                        fact = { activity = "read", itemType = itemType,
                            borrowedFromCamp = true },
                    }
                end
            end
        end
    end
    return nil
end

local function availableReadActivity(actor, carriedItems)
    return readActivity(actor, carriedItems) or campReadingActivity(actor)
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
    -- Change a soiled dressing, or dress a wound that stopped bleeding undressed.
    if assessment and (assessment.dirtyBandages > 0
        or (tonumber(assessment.openWounds) or 0) > 0) then
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

-- A water source a companion could not reach (a sink with no free square in
-- front of it, a blocked kitchen) is skipped for a while instead of being
-- picked again every downtime pulse.
-- Distance alone says nothing about reach: the square on the far side of a
-- wall is closer to a sink than the square in front of it. Every wash start
-- and every wash commit goes through the topology-aware interaction rule, so
-- proximity can never stand in for being able to touch the water.
local function washSourceInReach(actor, activity)
    local utility = U()
    local target = activity.object or activity.square
    if target == nil then return false, "wash_source_missing" end
    local reachable, _, reason = utility.directInteractionAccess(actor, target)
    if reachable == true then return true end
    return false, reason or "wash_source_not_in_reach"
end

local function washSourceCooling(state, object, current)
    local failed = type(state) == "table" and state.failedWashSources or nil
    local untilAt = failed and object ~= nil and failed[object] or nil
    return untilAt ~= nil and (tonumber(current) or U().nowMs()) < untilAt
end

local function coolWashSource(state, object, current)
    if type(state) ~= "table" or object == nil then return end
    state.failedWashSources = state.failedWashSources or setmetatable({}, { __mode = "k" })
    state.failedWashSources[object] = (tonumber(current) or U().nowMs())
        + (tonumber(U().config("downtimeWashFailureCooldownMs")) or 60000)
end

-- A sink, tub or well blocks its own square, so a wash trip walks to a free
-- square beside it with direct access instead of to the source itself (which
-- navigation rejected as an invalid destination).
local function approachWashSource(actor, activity)
    local navigation = SC.Navigation
    if not navigation or type(navigation.interactionTargets) ~= "function"
        or type(navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    local targets = navigation.interactionTargets(actor, activity.object or activity.square, {
        requireDirectAccess = true,
    })
    if type(targets) ~= "table" or #targets == 0 then return false, "no_interaction_targets" end
    local accepted, status = navigation.requestAny(actor, targets, "walk", {
        action = "move_to_water_source",
        object = activity.object,
        supervisorToken = activity.supervisorToken,
        arrivalDistance = 0.6,
    })
    return accepted == true, status
end

local function nearbyWashSource(actor, skip)
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
                        if washSourceValid(object) and not (skip and skip(object)) then
                            found = object
                            return false
                        end
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

local function washActivity(actor, items, state, current)
    local bodyScore = bodyDirt(actor)
    local bestItem, bestItemScore
    for _, item in ipairs(items) do
        local score = itemDirt(item)
        if score > 0.01 and (not bestItemScore or score > bestItemScore) then
            bestItem, bestItemScore = item, score
        end
    end
    if bodyScore <= 0.01 and not bestItem then return nil end
    local source, square = nearbyWashSource(actor, function(object)
        return washSourceCooling(state, object, current)
    end)
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

local function seatingPositionCount(object)
    if type(SeatingManager) ~= "table" or type(SeatingManager.getInstance) ~= "function" then
        return 0
    end
    local ok, manager = pcall(SeatingManager.getInstance)
    if not ok or manager == nil then return 0 end
    local count, countOk = U().call(manager, "getTilePositionCount", object)
    return countOk and math.max(0, tonumber(count) or 0) or 0
end

local function restFurnitureText(value)
    return value ~= nil and string.lower(tostring(value)) or ""
end

local function hasFurnitureWord(text, word)
    for token in string.gmatch(text, "%a+") do
        if token == word or token == word .. "s" then return true end
    end
    return false
end

local function isNamedBed(value)
    local text = restFurnitureText(value)
    return hasFurnitureWord(text, "bed") or hasFurnitureWord(text, "cot")
        or hasFurnitureWord(text, "stretcher")
end

local function isNamedSeat(value)
    local text = restFurnitureText(value)
    return string.find(text, "chair", 1, true) ~= nil
        or string.find(text, "sofa", 1, true) ~= nil
        or string.find(text, "couch", 1, true) ~= nil
        or string.find(text, "stool", 1, true) ~= nil
        or string.find(text, "bench", 1, true) ~= nil
        or string.find(text, "pew", 1, true) ~= nil
        or string.find(text, "booth", 1, true) ~= nil
        or string.find(text, "ottoman", 1, true) ~= nil
        or string.find(text, "seat", 1, true) ~= nil
end

local function furnitureKind(object)
    local utility = U()
    local name, nameOk = utility.call(object, "getName")
    local objectName = nameOk and name or nil
    local sprite, spriteOk = utility.call(object, "getSprite")
    if spriteOk and sprite then
        local spriteName, spriteNameOk = utility.call(sprite, "getName")
        local loweredSprite = spriteNameOk and restFurnitureText(spriteName) or ""
        local properties, propertiesOk = utility.call(sprite, "getProperties")
        if propertiesOk and properties then
            local customName, customNameOk = utility.call(properties, "Val", "CustomName")
            if not customNameOk or customName == nil then
                customName, customNameOk = utility.call(properties, "get", "CustomName")
            end
            local groupName, groupNameOk = utility.call(properties, "Val", "GroupName")
            if not groupNameOk or groupName == nil then
                groupName, groupNameOk = utility.call(properties, "get", "GroupName")
            end
            -- Build 42 also gives bed-like properties to chairs and couches.
            -- Use explicit object/tile semantics to identify a physical bed;
            -- otherwise SeatingManager is the authoritative seating catalogue.
            if isNamedBed(objectName) or isNamedBed(customNameOk and customName or nil)
                or isNamedBed(groupNameOk and groupName or nil)
                or string.find(loweredSprite, "furniture_bedding", 1, true) then
                return "rest_bed"
            end
            -- Build 42's pathToSitOnFurniture and ISRestAction both use
            -- SeatingManager as the authoritative contract. Names, IsChair and
            -- BedType describe many decorative/non-enterable tiles and caused
            -- companions to spend twelve seconds trying to sit in open air.
            if seatingPositionCount(object) > 0 then return "sit" end
        end
    end
    if isNamedBed(objectName) then return "rest_bed" end
    if seatingPositionCount(object) > 0 then return "sit" end
    return nil
end

local function sameFurnitureContext(actorSquare, candidateSquare)
    local actorRoom, actorRoomOk = U().call(actorSquare, "getRoom")
    local candidateRoom, candidateRoomOk = U().call(candidateSquare, "getRoom")
    if not actorRoomOk or not candidateRoomOk then return false end
    if actorRoom == nil or candidateRoom == nil then
        return actorRoom == nil and candidateRoom == nil
    end
    return sameBuilding(actorSquare, candidateSquare)
end

local function furnitureCooling(state, object, current)
    local failed = type(state) == "table" and state.failedFurniture or nil
    local untilAt = failed and object ~= nil and failed[object] or nil
    return untilAt ~= nil and (tonumber(current) or U().nowMs()) < untilAt
end

local function coolFurniture(state, object, current)
    if type(state) ~= "table" or object == nil then return end
    state.failedFurniture = state.failedFurniture or setmetatable({}, { __mode = "k" })
    state.failedFurniture[object] = (tonumber(current) or U().nowMs())
        + (tonumber(U().config("downtimeFurnitureFailureCooldownMs")) or 60000)
end

local function seatingStatus(actor)
    if SC.NativeActions and type(SC.NativeActions.seatingStatus) == "function" then
        local ok, value = pcall(SC.NativeActions.seatingStatus, actor)
        if ok and value ~= nil then return tostring(value) end
    end
    local sitting, sittingOk = U().call(actor, "isSittingOnFurniture")
    if sittingOk and sitting == true then return "furniture" end
    local onBed, bedOk = U().call(actor, "isOnBed")
    if bedOk and onBed == true then return "bed" end
    local ground, groundOk = U().call(actor, "isSitOnGround")
    if groundOk and ground == true then return "ground" end
    return "standing"
end

local function seatActivity(actor, state, current, seatOnly)
    local utility = U()
    if seatingStatus(actor) ~= "standing" then return nil end
    if type(state) == "table" and (tonumber(current) or utility.nowMs())
        < (tonumber(state.furnitureBackoffUntil) or 0) then return nil end
    local x, y, z = utility.position(actor)
    if not x then return nil end
    local actorSquare = utility.squareOf(actor)
    local radius = math.max(1, math.min(12,
        math.floor(tonumber(utility.config("downtimeFurnitureRadius")) or 8)))
    local budget = math.max(16,
        math.floor(tonumber(utility.config("downtimeFurnitureSquareBudget")) or 200))
    local scanned = 0
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    scanned = scanned + 1
                    local found, kind
                    if sameFurnitureContext(actorSquare, square) then
                        utility.squareObjects(square, function(object)
                            local value = furnitureKind(object)
                            local occupied, occupiedOk = utility.call(
                                object, "isFurnitureOccupied", actor)
                            if value and (seatOnly ~= true or value == "sit")
                                and not (occupiedOk and occupied == true)
                                and not furnitureCooling(state, object, current) then
                                found, kind = object, value
                                return false
                            end
                        end, 32)
                    end
                    if found then
                        local fatigue = utility.clamp(tonumber(
                            utility.characterStatValue(actor, "FATIGUE", 0)) or 0, 0, 1)
                        local tired = fatigue >= (tonumber(
                            utility.config("needsFatigueThreshold")) or 0.50)
                        local score = kind == "rest_bed" and 13 or 12
                        if tired then
                            score = (kind == "rest_bed" and 48 or 40)
                                + math.floor(fatigue * 10)
                        end
                        return {
                            kind = kind,
                            score = score,
                            object = found,
                            square = square,
                            fact = { activity = kind },
                        }
                    end
                    if scanned >= budget then return nil end
                end
            end
        end
    end
    return nil
end

local function floorRestActivity(actor, furnitureAvailable)
    local utility = U()
    if furnitureAvailable or seatingStatus(actor) ~= "standing" then return nil end
    local fatigue = utility.clamp(tonumber(
        utility.characterStatValue(actor, "FATIGUE", 0)) or 0, 0, 1)
    local threshold = tonumber(utility.config("needsFatigueThreshold")) or 0.50
    if fatigue < threshold then return nil end
    return {
        kind = "rest_floor",
        score = 36 + math.floor(fatigue * 12),
        durationMs = tonumber(utility.config("downtimeFloorRestMs")) or 12000,
        fact = { activity = "rest_floor", fatigue = fatigue },
    }
end

local function approachFurniture(actor, activity)
    local arrived, targets, accessReason = U().directInteractionAccess(
        actor, activity.object)
    if arrived == true then return true, "arrived" end
    if accessReason == "no_interaction_targets" then return false, accessReason end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.requestAny(actor, targets, "walk", {
        action = "move_to_seat", targetSquare = activity.square,
        object = activity.object, arrivalDistance = 0.35,
        requireSameSquare = true, continuousApproach = true,
        supervisorToken = activity.supervisorToken,
    })
end

-- ---------------------------------------------------------------------------
-- Studying the dead
-- ---------------------------------------------------------------------------
-- A rare, low-priority moment. Once a spot has been quiet for a while, a
-- companion may crouch over a nearby zombie corpse and talk through what it
-- sees: the clothes, what the infection did to the person, and what Knox
-- Knews and LBMW radio said back in July 1993, in its own voice. Temperament
-- and profession decide how curious it is and how it signs off. Each body is
-- studied once; per-companion and party cooldowns keep it rare. Lines stay
-- ASCII so every font renders them unchanged.

local RESPECT_MARKER = "LF_Respected"
local Study = { lastPartyAt = -math.huge, MARKER = "LF_Studied", REACH = 1.6 }

local STUDY_POOLS = {
    ["study.open"] = {
        common = {
            "Hold on. Let me look at this one.",
            "Let's see who you were.",
            "Everybody's got a story. Let's see yours.",
            "Just looking. Nobody panic.",
            "Don't mind me. Checking on the neighbors.",
            "Easy. It's down. I just want a closer look.",
            "Huh. Come here a second. No, actually, don't.",
        },
        brave = { "Let's see what beat you. Wasn't the fence, that's for sure." },
        cautious = { "Checking it's really down before I get close. Okay. Okay." },
        caring = { "Hey there. I'm not going to hurt you. Not that anything can now." },
        practical = { "Quick look. Could tell us something useful." },
        stressed = { "I shouldn't. I'm going to. Why am I like this?" },
        low = { "Another one. Let's see which kind of unlucky you were." },
        hopeful = { "Maybe you left us a clue. Somebody always leaves a clue." },
    },
    ["study.crawler"] = {
        common = {
            "No legs. Still dragged itself after us. That's commitment.",
            "Crawler. Lost the lower half somewhere and kept going. Kentucky stubborn.",
            "Look at those elbows. Worn to the bone from crawling. It never stopped wanting.",
            "Couldn't walk anymore, so it crawled. The hunger doesn't take a day off.",
        },
        cautious = { "Crawlers are the ones you don't see coming. Remember that." },
    },
    ["study.skeleton"] = {
        common = {
            "Just bones in a jacket. Been out here longer than we have.",
            "Picked clean. The crows ate better than we did this week.",
            "Bones. Whoever you were, the summer took the rest.",
        },
    },
    ["study.fresh"] = {
        common = {
            "Fresh. Blood's barely dark. Somebody put this one down today.",
            "Still warm-ish. I don't love that.",
            "Recent. Which means whatever's walking around here is recent too.",
        },
    },
    ["study.old"] = {
        common = {
            "This one's been baking in the sun for days. The smell is its own enemy.",
            "Old. Skin like wet paper. Nature's trying to finish the job.",
            "Been lying here a while. The flies have filed a claim.",
        },
    },
    ["study.ours.self"] = {
        common = {
            "That's my work. Clean. I don't feel good about it. I don't feel bad either.",
            "I remember this one. Came at me by the fence. Didn't get far.",
            "Mine. Sorry, friend. You were in the way of the rest of us.",
        },
    },
    ["study.ours.team"] = {
        common = {
            "One of ours put this one down. Good hit.",
            "Right between the ears. Somebody on this team has been practicing.",
            "That's our work. Team effort. Well, one very determined team member.",
        },
    },
    ["study.symptoms"] = {
        common = {
            "Look at the collar. Sweat stains. The fever came first, just like the paper said.",
            "Knuckles split to the bone. Pounded on some door until there was nothing left.",
            "Eyes gone milky. Whatever was in there left before the body did.",
            "Skin's grey, veins gone dark. Like the blood gave up and turned to ink.",
            "Vomit down the front of the shirt. Fevers and vomiting. First-week symptoms.",
            "Fingernails torn off. Clawed at something. Or someone.",
            "Bite on the forearm. Tried to fend it off. It always starts with a bite.",
            "Teeth broken. Chewed on something harder than people. A car door, maybe.",
            "Wedding ring sunk into a swollen finger. Nobody was taking that off. Nobody tried.",
            "Weighs nothing. It kept walking long after there was anything left to burn.",
            "Glass in the palms. Never flinched. It doesn't feel a thing. That's the part that scares me.",
            "Flu-like at first, they said. Then panic and confusion. Then this.",
        },
        caring = { "Look at the hands. Somebody held these once." },
        practical = { "The legs rot slower than the rest. Good to know when you're running." },
        stressed = { "The eyes. Why did I look at the eyes?" },
    },
    ["study.lore"] = {
        common = {
            "Knox Knews called it an 'unusual illness'. Unusual. That's one word for it.",
            "The paper said fevers and vomiting in Muldraugh. March Ridge opened its military hospital. Look how that turned out.",
            "Radio said flu-like, then panic and confusion. They left out the part where confusion bites.",
            "LBMW kept saying there was NO evidence of fatalities. I'd like to show them some evidence.",
            "Keep safe, Kentucky, the radio lady said every night. Tried, Jackie. Tried real hard.",
            "Phones in Knox went dead days before anybody got sick. Knox Telecom said sorry. Funny timing.",
            "Army truck rolled over near March Ridge on the Fourth. 'No danger to the public.' Sure, Colonel.",
            "They said it didn't spread person to person. This one would like a word.",
            "The Exclusion Zone. Fancy government words for a fence around a graveyard.",
            "Took them weeks to admit it was 'degenerative'. Big word for 'they rot and keep walking'.",
            "The man on TV said it was contained. Contained where?",
            "Paper was still printing ballgame scores the week it started. Rangers won in West Point. Then nobody won.",
            "Fourth of July. Parade, fireworks, barbecue. Two days later the paper was talking about a mystery illness.",
            "The second wave got the folks who thought they'd dodged the first. Don't get comfortable.",
            "The CDC was 'on the way', the paper said. Must have taken the scenic route.",
            "The Governor was fretting over tornado money for Brandenburg that week. Bet he misses those problems.",
        },
        cautious = { "Everything the radio said was wrong. So I assume everything is worse than it looks." },
        practical = { "Nobody outside the zone knows what we know. So we'd better remember it." },
        hopeful = { "Says here to stay tuned for further updates. I'm all ears.",
            "'Temporary inconvenience.' Somebody typed that. Somebody approved it." },
    },
    ["study.psa"] = {
        common = {
            "Remember, citizens: the dead are not your neighbors anymore. Please adjust your casseroles accordingly.",
            "This has been a Knox County Civil Defense reminder: stay indoors, stay quiet, stay you.",
            "Feeling feverish? Confused? Hungry for the mailman? Please report to your nearest checkpoint. Or don't. It's closed.",
            "The Kentucky Board of Health reminds you: wash your hands, cover your cough, and never, ever get bitten.",
            "Safety tip from your friendly neighborhood survivor: if they're lying still, assume they're lying.",
            "Duck, cover, and aim for the head.",
            "A tidy town is a safe town! Please dispose of your deceased neighbors promptly.",
            "Keep calm and carry a crowbar. Brought to you by the good folks still breathing.",
            "Remember: it's only the flu until it isn't!",
            "Did you know? Nine out of ten doctors are now patients.",
            "Official instructions were to stay home and wait for instructions. Still waiting, Frank.",
            "Tonight's forecast: warm, humid, and a ninety percent chance of neighbors.",
            "Ask your doctor if not turning into one of these is right for you.",
            "The Kentucky Department of Tourism invites you: come for the bourbon, stay forever.",
        },
        brave = { "Civil Defense says lock your doors. I say lock and load." },
        cautious = { "Public service announcement: nobody touches anything. That's the whole announcement." },
        stressed = { "This is fine. This is a normal Tuesday. Please remain calm. I am remaining calm." },
        hopeful = { "Someone laminated this. Laminated it. That's faith, that is.",
            "'Report to your nearest shelter.' I'd love to. Which one's nearest?" },
    },
    ["study.kentucky"] = {
        common = {
            "Kentucky kept its gold at Fort Knox. Should have guarded the other Knox instead.",
            "Derby silks, bourbon barrels, bluegrass. And now this. Kentucky never did anything halfway.",
            "The tobacco barns are still standing out there. The farmers aren't.",
            "Somewhere a bourbon's been aging twelve years for a party that'll never happen. Honestly, the worst part.",
            "The Ohio's right there. The river doesn't care what floats in it anymore.",
            "Mama always said Kentucky folks never really leave. Didn't mean it like this.",
            "Burgoo, hot browns, sweet tea on the porch. I'd kill for a hot brown. Poor choice of words.",
            "A Kentucky colonel would be ashamed. Our finest, shuffling around like they own the place.",
            "Y'all wanted the quiet country life. Well. It's real quiet now.",
            "Horse country. The horses are fine, you know. It's just us.",
        },
        hopeful = { "Kentucky came through floods, fires and tornadoes. It'll still be Kentucky after this.",
            "Leaflet says our county is prepared for any emergency. This may be an addendum.",
            "'Your County Cares.' I think somebody meant it when they printed that." },
    },
    ["study.close"] = {
        common = {
            "Alright. Seen enough.",
            "Rest easy. Or just rest.",
            "Whoever you were, you're done carrying it.",
            "Okay. Back to it.",
        },
        brave = { "You lost. We didn't. That's the whole lesson.",
            "Stay down. That's the only order I have for you." },
        cautious = { "Checked the neck twice. Not getting up. Probably. Stepping back now.",
            "Nobody touch it. I mean it. Nobody." },
        caring = { "Somebody's kid. Somebody's everything.",
            "I hope whoever you were waiting for got out.",
            "Sleep now. Nobody needs anything from you anymore." },
        practical = { "Noted. Moving on.", "Clothes, wounds, smell. Filed. Back to work." },
        stressed = { "I shouldn't have looked. Why do I always look?",
            "Okay. Okay. That's going in the nightmare pile." },
        low = { "Could be any of us next week. Could be me.",
            "One more face I'll see when I close my eyes." },
        hopeful = { "One day somebody will write all of this down. Maybe us.",
            "We're still here. That counts for something." },
    },
    -- %1 is the companion's home town from its background.
    ["study.home"] = {
        common = {
            "Could have been my neighbor back in %1. Might have been.",
            "Folks like this used to wave from the porch back in %1.",
            "I keep checking faces for somebody from %1. Not this one. Thank God. Or not.",
        },
    },
    ["study.profession.doctor"] = { common = {
        "Pupils fixed and clouded. Mottling like late sepsis. Except sepsis has the decency to stop.",
        "I'd write a cause of death, but I'd need a longer form.",
        "The joints move wrong. Like the tendons forgot who they belonged to.",
        "Medical school promised me the dead don't bite. I want a refund.",
    } },
    ["study.profession.nurse"] = { common = {
        "I charted fevers like this. We sent them home with fluids and told them to rest.",
        "Hospital bracelet. Somebody triaged this one and sent them back out. Could have been me.",
        "Bedside manner's wasted on this one. Old habits.",
    } },
    ["study.profession.policeofficer"] = { common = {
        "No wallet, no ID. John Doe number... I stopped counting.",
        "Defensive wounds on the forearms. Fought whoever bit them. Lost.",
        "Back on the job I'd tape this off and call it in. Now I just step over.",
    } },
    ["study.profession.veteran"] = { common = {
        "Seen bodies before. Never seen them get back up. Different war.",
        "The Army said that crash was nothing. The Army says a lot of things.",
        "Check the pockets. Old habit. Keeps you alive.",
    } },
    ["study.profession.parkranger"] = { common = {
        "Tracks, scat, bodies. Same job, meaner animal.",
        "Walked a long way on those shoes. Soles are gone. Came in from the east road, I'd say.",
    } },
    ["study.profession.fireofficer"] = { common = {
        "We used to carry people out. Now we make sure they stay down.",
        "Smoke on the jacket. Got out of one fire and walked into this.",
    } },
    ["study.profession.chef"] = { common = {
        "Grey meat. I wouldn't serve it to a raccoon.",
        "Smells like a walk-in cooler three weeks after the power died.",
    } },
    ["study.profession.farmer"] = { common = {
        "Seen livestock go down sick. Never seen a cow get up afterwards.",
        "Put down a lame horse once. Cried all night. This one I'd do again.",
    } },
    ["study.profession.mechanics"] = { common = {
        "Engine runs, nobody driving. Bad wiring all the way down.",
        "Everything's still hooked up and nothing runs right. Won't stop turning over, though.",
    } },
    ["study.profession.burglar"] = { common = {
        "Pockets already turned out. Somebody got here first. Professional courtesy.",
        "Keys on the belt. Some house out there is still locked and waiting. Tempting.",
    } },
    ["study.profession.securityguard"] = { common = {
        "Night shift, I'd bet. Walked the same loop forever. Still doing it, in a way.",
    } },
    ["study.outfit.law"] = {
        common = {
            "Badge still pinned on. Served and protected right up to the end.",
            "Sheriff's star. Wonder if they ever got the order to evacuate.",
            "Cuffs on the belt. Never got to use them on the right suspect.",
            "Security uniform. Minimum wage to guard somebody else's stuff. Guarded it to the last.",
        },
        caring = { "Kept people safe for a living. Nobody kept them safe." },
    },
    ["study.outfit.medic"] = { common = {
        "Scrubs. They were the first to catch it. They were the first to try.",
        "Doctor's coat, stethoscope still on. Diagnosis: everything.",
        "Paramedic. Answered the call. The call answered back.",
    } },
    ["study.outfit.patient"] = { common = {
        "Hospital gown. Walked out of March Ridge in slippers.",
        "Hospital bracelet. Already sick when they checked in. They treated the flu. It wasn't the flu.",
    } },
    ["study.outfit.military"] = { common = {
        "Army fatigues. Sent here to hold the line. The line held them.",
        "Soldier. They put kids on that fence with orders nobody explained.",
        "Dog tags. Somebody's going to wait for a letter that never gets sent.",
    } },
    ["study.outfit.fire"] = { common = {
        "Firefighter. Ran toward this. Of course they did.",
        "Turnout gear. Built for heat. Not for teeth.",
    } },
    ["study.outfit.hazmat"] = { common = {
        "Hazmat suit. Didn't help. Nothing helped.",
        "Sealed suit, torn at the glove. One tear was all it took.",
        "They knew something. You don't dress like this for the flu.",
    } },
    ["study.outfit.food"] = { common = {
        "Name tag from the burger place. Still smells a little like fryer oil. And worse.",
        "Spiffo's uniform. The raccoon on the shirt's still smiling. Somebody should.",
        "Apron and a hairnet. Health code violations: all of them.",
    } },
    ["study.outfit.farm"] = { common = {
        "Overalls, boots, dirt under the nails. Kentucky farmer. The corn will go to seed now.",
        "Hunting vest. Spent a life stalking deer. Ended up the one doing the stalking.",
    } },
    ["study.outfit.office"] = { common = {
        "Tie still knotted. Stuck on Monday morning forever.",
        "Office clothes. Probably died wondering about a deadline.",
        "Company badge from some office in Louisville. Came in for one meeting. Stayed.",
    } },
    ["study.outfit.student"] = { common = {
        "Just a kid. Summer vacation, 1993. Should have been the best one.",
        "School jacket. Somebody's honor roll.",
    } },
    ["study.outfit.sports"] = { common = {
        "Baseball cap. Louisville fan. Season's over, champ.",
        "Team jersey. Went to the game, came home a monster. Well, some fans always did.",
        "Running shoes. A jogger. Outran nothing in the end.",
    } },
    ["study.outfit.jockey"] = { common = {
        "Jockey silks. Derby dreams, Knox County nightmare.",
        "A jockey. Small, quick, light. Still wasn't fast enough.",
    } },
    ["study.outfit.wedding"] = { common = {
        "Wedding clothes. 'Til death do us part. Death did its part. Then kept going.",
        "Somebody was getting married that week. Somebody's still waiting at the altar.",
    } },
    ["study.outfit.inmate"] = { common = {
        "Prison orange. Got out in the end. Not how anybody planned it.",
        "Inmate. Served the sentence and then some.",
    } },
    ["study.outfit.clergy"] = { common = {
        "Priest's collar. I hope they found the answers they preached.",
        "A preacher. The end times came and nobody got raptured. Just this.",
    } },
    ["study.outfit.home"] = { common = {
        "Bathrobe and slippers. It came for them at home, on an ordinary morning.",
        "Pajamas. Went to bed with a fever. Never really woke up.",
    } },
    ["study.outfit.worker"] = { common = {
        "Coveralls with a name stitched on. Somebody's mechanic. Somebody's dad, maybe.",
        "Mail carrier. Neither rain, nor sleet, nor this.",
        "Hard hat still on. Safety first. It helped with falling bricks. Not with this.",
        "Gas station shirt. Somebody still owes them for a fill-up.",
    } },
    ["study.outfit.party"] = { common = {
        "Party clothes. Last good night out in Kentucky.",
        "Dressed as a monster for fun. Irony has a mean streak.",
    } },
    ["study.outfit.santa"] = { common = {
        "A Santa suit in July. There's a story here I'll never hear.",
    } },
    ["study.outfit.reporter"] = { common = {
        "Press badge. LBMW. Told us all to keep calm right up to the end.",
        "A reporter. Stayed on the story too long. The good ones always do.",
    } },
    ["study.outfit.traveler"] = { common = {
        "Tourist. Came to see Kentucky. Saw too much of it.",
        "Backpack still on. Was trying to leave. Almost made it.",
        "Evacuee. They told them where to go. Nobody said what would be waiting.",
    } },
    ["study.outfit.raider"] = { common = {
        "Bandit gear. Lived by taking. Died the same as everybody.",
        "Mask and a mean streak. Doesn't matter now.",
    } },
    ["study.outfit.survivor"] = { common = {
        "Survivor gear. One of us, once. Didn't make it.",
        "Good boots, full pack, homemade armor. Did everything right. Still ended up here.",
    } },
    ["study.ritual.spiffo_salute"] = { common = {
        "*salutes* Colonel Spiffo, one more for the lost and found.",
    } },
    ["study.ritual.bourbon_blessing"] = { common = {
        "By the barrel and the bluegrass, rest easy. I'd pour one out, but we're rationing.",
    } },
    ["study.ritual.mannequin_apology"] = { common = {
        "Sorry. You're real, aren't you? I thought you were a mannequin. I'm so sorry.",
    } },
    ["study.ritual.gnome_commander"] = { common = {
        "Gnome Command, be advised: one more hostile neutralized. Requesting tiny medals.",
    } },
    ["study.ritual.sports_pep_talk"] = { common = {
        "Hey. You played the whole game. Final whistle, champ.",
    } },
    ["study.ritual.rubber_duck_oracle"] = { common = {
        "The Duck sees all. The Duck says this one is done. Squeak.",
    } },
}

-- Vanilla outfit names, checked in order. A token starting with "=" must
-- match exactly; any other token is a plain substring of the outfit name.
Study.OUTFITS = {
    { "party", { "Stripper", "Costume", "=Party", "ClubGoer", "=Gaudy" } },
    { "santa", { "Santa" } },
    { "reporter", { "Frank_Hemingway", "Jackie_Jaye" } },
    { "patient", { "HospitalPatient" } },
    { "medic", { "Doctor", "Nurse", "Pharmacist", "AmbulanceDriver" } },
    { "hazmat", { "HazardSuit", "Exterminator" } },
    { "fire", { "Fireman" } },
    { "military", { "Army", "=Veteran", "Ghillie" } },
    { "law", { "Police", "Sheriff", "PrisonGuard", "Security", "Detective", "=Agent", "=Ranger" } },
    { "inmate", { "Inmate" } },
    { "jockey", { "Jockey" } },
    { "sports", { "Baseball", "Football", "IceHockey", "HockeyPsycho", "Golfer", "SportsFan",
        "FitnessInstructor", "Cyclist", "Bowling", "Swimmer", "=Ski", "StreetSports", "Boxing",
        "Varsity" } },
    { "food", { "Chef", "Cook_", "Waiter_", "=Spiffo", "Meat_Master", "GigaMart" } },
    { "farm", { "Farmer", "Woodcut", "=Hunter", "Fisherman", "Redneck" } },
    { "wedding", { "Groom", "WeddingDress", "NakedVeil" } },
    { "clergy", { "Priest", "Rev_" } },
    { "home", { "Bathrobe", "Bedroom", "=Naked" } },
    { "office", { "OfficeWorker", "=IT", "Teacher", "=Classy", "=Dean", "Judge", "Mayor" } },
    { "student", { "Student", "=Young" } },
    { "worker", { "Mechanic", "ConstructionWorker", "Foreman", "MetalWorker", "Trucker",
        "Sanitation", "Postal", "Fossoil", "Gas2Go", "ThunderGas", "McCoys", "AirportWorker",
        "AirCrew", "RiverboatCaptain" } },
    { "raider", { "Bandit", "Raider", "=Thug", "BankRobber", "PrivateMilitia", "=Mob" } },
    { "survivor", { "Survivalist" } },
    { "traveler", { "Tourist", "Camper", "Backpacker", "Evacuee", "Hobbo", "Retiree" } },
}
Study.PROFESSION_ALIASES = {
    burgerflipper = "chef", rancher = "farmer", engineer = "mechanics",
    electrician = "mechanics", repairman = "mechanics",
}
Study.HOMES = {
    muldraugh = "Muldraugh", rosewood = "Rosewood", riverside = "Riverside",
    west_point = "West Point", louisville = "Louisville", brandenburg = "Brandenburg",
}
-- How each temperament likes to sign off: a closing thought, a civil-defense
-- joke or a word about Kentucky.
Study.CLOSER_WEIGHTS = {
    brave = { psa = 3, kentucky = 2, close = 2 },
    cautious = { psa = 2, kentucky = 1, close = 3 },
    caring = { psa = 1, kentucky = 2, close = 4 },
    practical = { psa = 3, kentucky = 2, close = 2 },
}

function Study.register()
    if not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return false end
    if type(SC.Dialogue.has) == "function" and SC.Dialogue.has("study.open") then return true end
    for topic, pool in pairs(STUDY_POOLS) do SC.Dialogue.register(topic, pool) end
    return true
end

function Study.outfitGroup(name)
    if type(name) ~= "string" or name == "" then return nil end
    for _, row in ipairs(Study.OUTFITS) do
        for _, token in ipairs(row[2]) do
            if string.sub(token, 1, 1) == "=" then
                if name == string.sub(token, 2) then return row[1] end
            elseif string.find(name, token, 1, true) then
                return row[1]
            end
        end
    end
    return nil
end

-- A zombie corpse that stays down: never one that is faking, due to
-- reanimate, or already studied or given its moment.
function Study.eligible(body)
    local utility = U()
    if not utility.instanceOf(body, "IsoDeadBody") then return false end
    if utility.call(body, "isZombie") ~= true then return false end
    if utility.call(body, "isFakeDead") == true then return false end
    if (tonumber((utility.call(body, "getReanimateTime"))) or 0) > 0 then return false end
    local data = utility.modData(body)
    return not (type(data) == "table"
        and (data[Study.MARKER] ~= nil or data[RESPECT_MARKER] ~= nil))
end

-- Nearest eligible body on this side of the walls: indoors only within the
-- companion's own building, outdoors only outdoors.
function Study.nearbyBody(actor)
    local utility = U()
    local x, y, z = utility.position(actor)
    if not x then return nil end
    local actorSquare = utility.squareOf(actor)
    local room = utility.call(actorSquare, "getRoom")
    local indoors = room ~= nil
    local radius = math.max(1, math.min(10, math.floor(utility.config("downtimeStudyRadius") or 6)))
    for distance = 0, radius do
        for dx = -distance, distance do
            for dy = -distance, distance do
                if math.max(math.abs(dx), math.abs(dy)) == distance then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    local squareIndoors = square ~= nil and utility.call(square, "getRoom") ~= nil
                    if square and squareIndoors == indoors
                        and (not indoors or sameBuilding(actorSquare, square)) then
                        local found
                        utility.squareStaticMovingObjects(square, function(object)
                            if Study.eligible(object) then found = object return false end
                        end, 8)
                        if found then return found, square end
                    end
                end
            end
        end
    end
    return nil
end

function Study.trait(profile, name)
    local value = tonumber(type(profile) == "table" and profile[name] or nil) or 50
    return (math.max(0, math.min(100, value)) - 50) / 50
end

-- Chance per roll window. Practical minds and people who handled the dead
-- for a living lean in; cautious ones keep their distance; a frayed nerve
-- never goes looking.
function Study.chance(commands)
    local utility = U()
    commands = type(commands) == "table" and commands or {}
    if (tonumber(commands.stress) or 0) >= 65 then return 0 end
    local profile = type(commands.personalityProfile) == "table" and commands.personalityProfile or {}
    local chance = (tonumber(utility.config("downtimeStudyChancePercent")) or 18)
        + Study.trait(profile, "practicality") * 10 - Study.trait(profile, "caution") * 8
        + Study.trait(profile, "courage") * 4
    if SC.Background and type(SC.Background.downtimeModifier) == "function" then
        chance = chance + (tonumber(SC.Background.downtimeModifier(profile, "study_corpse")) or 0) * 4
    end
    return math.max(0, math.min(100, chance))
end

function Study.hash(text)
    return math.abs(tonumber(U().stableHash(text)) or 0)
end

function Study.activity(actor, commands, state, current)
    local utility = U()
    if current - (state.safeSince or current) < (utility.config("downtimeStudySafeMs") or 20000) then
        return nil
    end
    if current - (tonumber(state.studiedAt) or -math.huge)
            < (utility.config("downtimeStudyActorCooldownMs") or 900000)
        or current - Study.lastPartyAt < (utility.config("downtimeStudyPartyCooldownMs") or 240000) then
        return nil
    end
    local window = math.max(10000, tonumber(utility.config("downtimeStudyRollWindowMs")) or 90000)
    local roll = Study.hash(tostring(utility.idOf(actor)) .. ":study:"
        .. tostring(math.floor(current / window))) % 100
    if roll >= Study.chance(commands) then return nil end
    local body, square = Study.nearbyBody(actor)
    if not body then return nil end
    return {
        kind = "study_corpse", score = 22, object = body, square = square,
        fact = { activity = "study_corpse",
            outfit = Study.outfitGroup(utility.call(body, "getOutfitName")) or "unknown" },
    }
end

function Study.isPlayer(character)
    if character == nil or type(getPlayer) ~= "function" then return false end
    local ok, player = pcall(getPlayer)
    return ok and player ~= nil and player == character
end

function Study.ageHours(body)
    local died = tonumber((U().call(body, "getDeathTime")))
    if not died or died <= 0 or type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or not gameTime then return nil end
    local nowHours = tonumber((U().call(gameTime, "getWorldAgeHours")))
    if not nowHours or nowHours < died then return nil end
    return nowHours - died
end

function Study.pick(options, seed)
    local total = 0
    for _, option in ipairs(options) do total = total + math.max(0, option.weight or 0) end
    if total <= 0 then return nil end
    local roll = seed % total
    for _, option in ipairs(options) do
        local weight = math.max(0, option.weight or 0)
        if roll < weight then return option end
        roll = roll - weight
    end
    return options[#options]
end

-- Two or three lines: what it sees first, what that means (its own trade,
-- the body's age, who put it down, the symptoms or the news), and, by
-- temperament, a closing thought, a civil-defense joke or a word about
-- Kentucky. A companion with a ritual quirk may close with its ritual.
function Study.lines(actor, commands, body, current)
    local utility = U()
    Study.register()
    local function has(topic)
        return SC.Dialogue and type(SC.Dialogue.has) == "function" and SC.Dialogue.has(topic)
    end
    local profile = type(commands.personalityProfile) == "table" and commands.personalityProfile or {}
    local seed = tostring(utility.idOf(actor)) .. ":" .. tostring(body) .. ":" .. tostring(current)
    local group = Study.outfitGroup(utility.call(body, "getOutfitName"))
    local skeleton = utility.call(body, "isSkeleton") == true
    local lines = {}
    if skeleton then
        lines[1] = { topic = "study.skeleton" }
    elseif utility.call(body, "isCrawling") == true and Study.hash(seed .. ":crawl") % 2 == 0 then
        lines[1] = { topic = "study.crawler" }
    elseif group and has("study.outfit." .. group) then
        lines[1] = { topic = "study.outfit." .. group }
    else
        lines[1] = { topic = "study.open" }
    end
    local middle = {}
    local killer = utility.call(body, "getKilledBy")
    if killer ~= nil and killer == actor then
        middle[#middle + 1] = { topic = "study.ours.self", weight = 5 }
    elseif killer ~= nil and (utility.isCompanion(killer) or Study.isPlayer(killer)) then
        middle[#middle + 1] = { topic = "study.ours.team", weight = 3 }
    end
    local age = not skeleton and Study.ageHours(body) or nil
    if age and age < (utility.config("downtimeStudyFreshHours") or 12) then
        middle[#middle + 1] = { topic = "study.fresh", weight = 2 }
    elseif age and age > (utility.config("downtimeStudyOldHours") or 96) then
        middle[#middle + 1] = { topic = "study.old", weight = 2 }
    end
    local profession = Study.PROFESSION_ALIASES[profile.profession] or profile.profession
    if type(profession) == "string" and has("study.profession." .. profession) then
        middle[#middle + 1] = { topic = "study.profession." .. profession, weight = 4 }
    end
    local background = type(profile.background) == "table" and profile.background or {}
    local home = Study.HOMES[background.home]
    if home then middle[#middle + 1] = { topic = "study.home", weight = 1, arguments = { home } } end
    middle[#middle + 1] = { topic = "study.symptoms", weight = 4 }
    middle[#middle + 1] = { topic = "study.lore", weight = 4 }
    local second = Study.pick(middle, Study.hash(seed .. ":middle"))
    if second then lines[#lines + 1] = { topic = second.topic, arguments = second.arguments } end
    local voice = SC.Personality and type(SC.Personality.voice) == "function"
        and SC.Personality.voice(profile) or "practical"
    local weights = Study.CLOSER_WEIGHTS[voice] or Study.CLOSER_WEIGHTS.practical
    local closers = {
        { topic = "study.psa", weight = weights.psa },
        { topic = "study.kentucky", weight = weights.kentucky },
        { topic = "study.close", weight = weights.close },
    }
    local ritual = SC.Quirks and type(SC.Quirks.normalize) == "function"
        and SC.Quirks.normalize(commands.ritual) or nil
    if type(ritual) == "table" and ritual.id and has("study.ritual." .. tostring(ritual.id)) then
        closers[#closers + 1] = { topic = "study.ritual." .. tostring(ritual.id), weight = 3 }
    end
    if Study.hash(seed .. ":closer") % 100 < (utility.config("downtimeStudyCloserPercent") or 75) then
        local closer = Study.pick(closers, Study.hash(seed .. ":closerPick"))
        if closer then lines[#lines + 1] = { topic = closer.topic } end
    end
    return lines
end

function Study.duration(kind)
    local utility = U()
    if kind == "study_corpse" then return utility.config("downtimeStudyMs") or 7000 end
    if kind == "pay_respects" then return utility.config("downtimeRespectMs") or 6000 end
    return utility.config("downtimeActivityMs") or 6000
end

-- The start claims the companion and party cooldowns, so an interrupted or
-- unreachable look is not retried at once.
function Study.prepare(actor, activity, commands, state, now)
    activity.lines = Study.lines(actor, commands, activity.object, now)
    activity.nextLineAt = 0
    state.studiedAt = now
    Study.lastPartyAt = now
end

function Study.speakNext(actor, activity, now)
    local queue = activity and activity.lines
    if type(queue) ~= "table" or #queue == 0 or now < (activity.nextLineAt or 0) then return false end
    local line = table.remove(queue, 1)
    activity.nextLineAt = now + (U().config("downtimeStudyLineGapMs") or 2600)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    local spoken = SC.Dialogue.say(actor, line.topic, nil, line.arguments, {
        recentLimit = 6, salt = line.topic .. ":" .. tostring(now),
    })
    return spoken == true
end

function Study.stillThere(activity)
    local present = false
    U().squareStaticMovingObjects(activity.square, function(object)
        if object == activity.object then present = true return false end
    end, 16)
    return present
end

-- A finished look marks the body for good and never cuts off the last thought.
function Study.finish(actor, activity, now)
    local data = U().modData(activity.object)
    if type(data) == "table" then data[Study.MARKER] = true end
    if type(activity.lines) == "table" and #activity.lines > 0 then
        activity.nextLineAt = 0
        Study.speakNext(actor, activity, now)
    end
end

-- ---------------------------------------------------------------------------
-- Paying respects
-- ---------------------------------------------------------------------------
-- Now and then a companion stops by a body, not to study it but to give it a
-- moment: a few quiet words, and sometimes a keepsake noticed and left where
-- it lies. Caring minds stop most, and more often right after a hard fight;
-- a frayed nerve never does. A body gets one moment from the party, studied
-- or respected, and nothing on it is touched. The pose is the study crouch.

local Respect = { lastPartyAt = -math.huge, MARKER = RESPECT_MARKER }

Respect.VOICE_SCALE = { caring = 2.5, practical = 1, brave = 0.8, cautious = 0.6 }

local RESPECT_POOLS = {
    ["respects.gesture"] = {
        common = {
            "Hold up a second.",
            "Give me a moment here.",
            "Just a second. Won't take long.",
            "Wait. Not this one. Not like this.",
            "One moment. For them.",
            "Hang on. This one deserves a second.",
            "Let me do this properly.",
        },
        brave = { "Stand easy. This one gets a moment." },
        cautious = { "It's down. It's really down. Okay. A moment, then." },
        caring = { "Wait. Nobody should just be left like this." },
        practical = { "Ten seconds. Then we move." },
    },
    ["respects.act"] = {
        common = {
            "Rest now. You don't have to walk anymore.",
            "Whoever you were, you're off shift.",
            "Sorry it went this way, friend.",
            "Nobody's going to make you get up again.",
            "You fought it as long as you could. I'd bet on it.",
            "There. That's all anybody can do now.",
            "You can stop now. It's over.",
            "Whoever you were waiting for, I hope they made it.",
            "No more walking. No more hunger. Just rest.",
        },
        brave = { "You went down swinging. I hope." },
        cautious = { "Stay down. Please. For both of us." },
        caring = { "I'm sorry. I'm so sorry. Somebody should say it.",
            "Somebody missed you. I'm sure of it." },
        practical = { "Done now. That's something." },
    },
    -- %1 is the keepsake's name, lowercase.
    ["respects.memento"] = {
        common = {
            "Their %1. That stays. It's theirs.",
            "Look. Their %1. Somebody loved this one. Leave it be.",
            "Kept their %1 all the way to the end. I'm not taking that.",
            "Their %1. Some things you keep to the very end.",
            "Their %1. I won't take it. It's the last thing that's theirs.",
            "Their %1. Somebody out there would know that. Maybe still misses them.",
        },
        caring = { "Their %1. Whoever gave them that, I hope they got out." },
    },
    ["respects.reaction"] = {
        common = {
            "...Yeah. Rest easy.",
            "Amen. Or whatever fits.",
            "Nice words. They'd have liked that.",
            "That was decent of you.",
            "Rest easy, whoever you were.",
            "Yeah. Somebody should.",
        },
        brave = { "Good. Now let's make sure it doesn't happen to us." },
        cautious = { "That was nice. Can we go now? That was nice." },
        caring = { "Thank you for doing that." },
        practical = { "Right. Moving on." },
    },
}

Respect.POOLS = RESPECT_POOLS

function Respect.register()
    if not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return false end
    if type(SC.Dialogue.has) == "function" and SC.Dialogue.has("respects.act") then return true end
    for topic, pool in pairs(RESPECT_POOLS) do SC.Dialogue.register(topic, pool) end
    return true
end

-- Chance per roll window, by temperament; doubled just after a fight ends.
function Respect.chance(commands, current)
    local utility = U()
    commands = type(commands) == "table" and commands or {}
    if (tonumber(commands.stress) or 0) >= (tonumber(utility.config("respectStressLimit")) or 72) then
        return 0
    end
    local profile = type(commands.personalityProfile) == "table" and commands.personalityProfile or {}
    local voice = SC.Personality and type(SC.Personality.voice) == "function"
        and SC.Personality.voice(profile) or "practical"
    local chance = (tonumber(utility.config("respectChancePercent")) or 10)
        * (Respect.VOICE_SCALE[voice] or 1)
    local ended = SC.Tales and type(SC.Tales.lastEpisodeEndedAt) == "function"
        and tonumber(SC.Tales.lastEpisodeEndedAt()) or nil
    if ended and current >= ended
        and current - ended <= (tonumber(utility.config("respectAfterFightMs")) or 120000) then
        chance = chance * 2
    end
    return math.max(0, math.min(100, chance))
end

-- A keepsake on the body, by name. Read-only and bounded; it stays there.
function Respect.memento(body)
    local utility = U()
    local container = utility.call(body, "getContainer")
    if container == nil then return nil end
    for _, item in ipairs(utility.inventoryItems(container, 20)) do
        local category = utility.call(item, "getDisplayCategory")
        if utility.call(item, "isMemento") == true
            or string.lower(tostring(category or "")) == "memento" then
            local name = utility.call(item, "getDisplayName")
            if type(name) == "string" and name ~= "" then
                return string.lower(string.sub(name, 1, 40))
            end
        end
    end
    return nil
end

function Respect.activity(actor, commands, state, current)
    local utility = U()
    if current - (state.safeSince or current) < (utility.config("downtimeStudySafeMs") or 20000) then
        return nil
    end
    if current - (tonumber(state.respectedAt) or -math.huge)
            < (utility.config("respectActorCooldownMs") or 2700000)
        or current - Respect.lastPartyAt < (utility.config("respectPartyCooldownMs") or 1200000) then
        return nil
    end
    local window = math.max(10000, tonumber(utility.config("downtimeStudyRollWindowMs")) or 90000)
    local roll = Study.hash(tostring(utility.idOf(actor)) .. ":respect:"
        .. tostring(math.floor(current / window))) % 100
    if roll >= Respect.chance(commands, current) then return nil end
    local body, square = Study.nearbyBody(actor)
    if not body then return nil end
    return {
        kind = "pay_respects", score = 20, object = body, square = square,
        fact = { activity = "pay_respects" },
    }
end

function Respect.lines(body)
    Respect.register()
    local lines = { { topic = "respects.gesture" }, { topic = "respects.act" } }
    local memento = Respect.memento(body)
    if memento then lines[#lines + 1] = { topic = "respects.memento", arguments = { memento } } end
    return lines
end

-- Like a study, the start claims both cooldowns.
function Respect.prepare(actor, activity, commands, state, now)
    activity.lines = Respect.lines(activity.object)
    activity.nextLineAt = 0
    state.respectedAt = now
    Respect.lastPartyAt = now
end

-- Sometimes a calm companion standing by says something back.
function Respect.react(actor, now)
    local utility = U()
    if Study.hash(tostring(utility.idOf(actor)) .. ":react:" .. tostring(now)) % 100
        >= (tonumber(utility.config("respectReactionPercent")) or 30) then
        return nil
    end
    local owner = SC.Banter
    if type(owner) ~= "table" or type(owner.availableSpeaker) ~= "function"
        or not SC.Registry or not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return nil
    end
    local radius = tonumber(utility.config("respectReactionRadius")) or 8
    for _, record in ipairs(SC.Registry.records()) do
        if record.actor ~= actor and owner.availableSpeaker(record, actor, now, radius) then
            local spoken = SC.Dialogue.say(record.actor, "respects.reaction", nil, nil, {
                recentLimit = 6, salt = "respects.reaction:" .. tostring(now),
            })
            return spoken == true and record.actor or nil
        end
    end
    return nil
end

function Respect.finish(actor, activity, now)
    local data = U().modData(activity.object)
    if type(data) == "table" then data[Respect.MARKER] = true end
    if type(activity.lines) == "table" and #activity.lines > 0 then
        activity.nextLineAt = 0
        Study.speakNext(actor, activity, now)
    end
    return Respect.react(actor, now)
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
    activity = washActivity(actor, items, state, current)
    if activity then filtered[#filtered + 1] = activity end
    if workMode == "craft" then
        activity = craftActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
    elseif workMode == "idle" then
        activity = availableReadActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
    else
        activity = repairActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = availableReadActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
        activity = craftActivity(actor, items)
        if activity then filtered[#filtered + 1] = activity end
    end
    if workMode ~= "craft" and (desiredKind == nil or desiredKind == "study_corpse") then
        activity = Study.activity(actor, commands, state or {}, current)
        if activity then filtered[#filtered + 1] = activity end
    end
    if workMode ~= "craft" and (desiredKind == nil or desiredKind == "pay_respects") then
        activity = Respect.activity(actor, commands, state or {}, current)
        if activity then filtered[#filtered + 1] = activity end
    end
    if workMode ~= "craft" and (desiredKind == nil or desiredKind == "workout")
        and SC.Gestures and type(SC.Gestures.workoutActivity) == "function" then
        local ok, workout = pcall(SC.Gestures.workoutActivity, actor, commands, state or {}, current)
        if ok and type(workout) == "table" then filtered[#filtered + 1] = workout end
    end
    -- A private diary entry: SCDiary offers one only when a truthful page is
    -- prepared and the exact book and a pen are carried.
    if workMode ~= "craft" and (desiredKind == nil or desiredKind == "write_diary")
        and SC.Diary and type(SC.Diary.writeActivity) == "function" then
        local ok, writing = pcall(SC.Diary.writeActivity, actor, current)
        if ok and type(writing) == "table" then filtered[#filtered + 1] = writing end
    end
    if workMode ~= "craft" then
        local furniture = seatActivity(actor, state, current)
        local seatedTask, seatedTaskScore
        for _, candidate in ipairs(filtered) do
            if candidate.kind == "read" or candidate.kind == "write_diary" then
                local score = tonumber(candidate.score) or 0
                if seatedTask == nil or score > seatedTaskScore then
                    seatedTask, seatedTaskScore = candidate, score
                end
            end
        end
        local rest = furniture
        if seatedTask ~= nil and seatingStatus(actor) == "standing" then
            -- Sit first, then the normal next downtime pass starts Read/Write
            -- without getting up. Beds remain available for actual tired rest;
            -- a chair/sofa/stool is selected specifically for desk-like activity.
            local readingSeat = furniture and furniture.kind == "sit" and furniture
                or seatActivity(actor, state, current, true)
            if readingSeat then
                readingSeat.score = math.max(tonumber(readingSeat.score) or 0,
                    (seatedTaskScore or 0) + 1)
                readingSeat.fact.seatingFor = seatedTask.kind
                rest = readingSeat
            end
        end
        if rest then filtered[#filtered + 1] = rest end
        local floorRest = floorRestActivity(actor,
            furniture ~= nil and desiredKind ~= "rest_floor")
        if floorRest then filtered[#filtered + 1] = floorRest end
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
    -- An interrupted diary entry leaves no page behind.
    if activity.kind == "write_diary" and SC.Diary and type(SC.Diary.abandonWrite) == "function" then
        pcall(SC.Diary.abandonWrite, actor, activity.diary)
    end
    if state and state.active == activity then state.active = nil end
    return true, reason or "cancelled"
end

local function failActivity(actor, state, reason, detail)
    local activity = state and state.active
    if not activity then return false, reason or "no_activity" end
    debugTrace(actor, "finish_blocked", activity, reason)
    if activity.kind == "sit" or activity.kind == "rest_bed" then
        -- A rejected/invalid seat should not monopolize every downtime pass.
        -- Remember the exact object long enough for another activity or piece
        -- of furniture to win while the world topology remains unchanged.
        coolFurniture(state, activity.object, U().nowMs())
        -- A failure normally reflects unavailable/blocked SeatingManager data,
        -- not one uniquely bad sprite. Stop cycling through every chair in the
        -- room; during this bounded backoff a tired actor can choose floor rest
        -- and read/diary activities may continue in the posture they have.
        state.furnitureBackoffUntil = U().nowMs()
            + (tonumber(U().config("downtimeFurnitureFailureCooldownMs")) or 60000)
    end
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
        deadlines = activity.deadlines,
        allowedActions = {
            [activity.kind] = true,
            move_to_seat = true, move_to_water_source = true, move_to_corpse = true,
            move_to_base_storage = true,
            sit_ground = true, stand_ground = true,
            -- A seated companion may yawn or stretch without getting up.
            ext_gesture = true,
        },
        onCancel = function(_, cancelReason)
            return releaseDowntimeResources(actor, state, activity,
                cancelReason or "downtime_cancelled")
        end,
        metadata = { commandSerial = activity.commandSerial or 0 },
    })
    if not token then
        if service.containsDeferredStatus and service.containsDeferredStatus(reason) then
            -- Urgent survival work was dispatched for this actor during begin(); the
    -- companion is committed to it this cycle.  That is the urgent succeeding,
    -- not this action failing, so report a deferral the decision layer can
    -- recognise instead of a refusal that would cool the target down.
            return false, "deferred:" .. tostring(reason)
        end
        return false, reason or "downtime_owner_rejected"
    end
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

local function approachBorrowedReadingSource(actor, activity)
    local utility = U()
    if not activity.borrowedOwner or not activity.borrowedFrom
        or not utility.inventoryContains(activity.borrowedFrom, activity.item) then
        return false, "borrowed_book_unavailable"
    end
    local atSource, targets, accessReason = utility.directInteractionAccess(
        actor, activity.borrowedOwner)
    if atSource == true then return true, "arrived" end
    if accessReason == "no_interaction_targets" then return false, accessReason end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return false, "navigation_unavailable"
    end
    local accepted, status = SC.Navigation.requestAny(actor, targets, "walk", {
        action = "move_to_base_storage",
        targetSquare = utility.squareOf(activity.borrowedOwner),
        object = activity.borrowedOwner,
        container = activity.borrowedFrom,
        item = activity.item,
        arrivalDistance = 0.35,
        requireSameSquare = true,
        continuousApproach = true,
        supervisorToken = activity.supervisorToken,
    })
    return accepted == true, status
end

-- Selection happens across the room and checkout happens a walk later, so the
-- policy that authorised the choice is re-read at the moment the item actually
-- changes hands. The player can un-register the shelf, raise the reserve,
-- protect the book or remove the other copies during that walk; the selected
-- copy then becomes the reserved last copy and must stay on the shelf.
local function borrowedCheckoutAuthorized(actor, activity)
    if activity.borrowedStorageId == nil then return true end
    local utility = U()
    local base = SC.BaseLife
    if not base or type(base.storage) ~= "function"
        or type(base.resolveContainer) ~= "function"
        or type(base.availableCountExact) ~= "function" then
        return false, "base_storage_unavailable"
    end
    local storage = base.storage(activity.borrowedStorageId)
    if type(storage) ~= "table" then return false, "borrowed_book_storage_changed" end
    if storage.withdrawals == false then return false, "borrowed_book_withdrawals_disabled" end
    local container = base.resolveContainer(storage)
    if container == nil or container ~= activity.borrowedFrom then
        return false, "borrowed_book_storage_changed"
    end
    if not utility.inventoryContains(container, activity.item) then
        return false, "borrowed_book_unavailable"
    end
    if base.availableCountExact(storage, utility.itemType(activity.item)) < 1 then
        return false, "borrowed_book_reserved"
    end
    if SC.PersonalItems and type(SC.PersonalItems.isProtected) == "function"
        and SC.PersonalItems.isProtected(activity.item, actor, "camp_reading_borrow") then
        return false, "borrowed_book_protected"
    end
    return true
end

local function startBorrowedReading(actor, activity, now)
    local utility = U()
    local atSource = utility.directInteractionAccess(actor, activity.borrowedOwner)
    if atSource ~= true then return false, "borrowed_book_source_not_in_reach" end
    local authorized, authorizedReason = borrowedCheckoutAuthorized(actor, activity)
    if authorized ~= true then return false, authorizedReason or "borrowed_book_unavailable" end
    local inventory = utility.inventory(actor)
    local transferred, transferReason = utility.transferItemVerified(
        activity.borrowedFrom, inventory, activity.item)
    if transferred ~= true then
        return false, transferReason or "borrowed_book_transfer_failed"
    end
    activity.borrowedReading = true
    local expected, expectedReason = startSupervisedVisual(actor, activity, {
        action = activity.kind,
    })
    if expected ~= true then return false, expectedReason or "visual_registration_failed" end
    if not utility.move(actor, "walk", {
        action = activity.kind,
        item = activity.item,
        object = activity.borrowedOwner,
        downtime = true,
        durationMs = activity.durationMs or Study.duration(activity.kind),
        supervisorToken = activity.supervisorToken,
    }) then
        return false, "animation_rejected"
    end
    activity.approaching = nil
    activity.actionAccepted = true
    activity.startedAt = now
    transitionActivity(activity, "animating", { action = activity.kind })
    return true, activity.kind
end

local function beginActivity(actor, state, activity, commands, now)
    if activity.kind == "replace_bandage" then
        if not SC.Medical or type(SC.Medical.replaceDirtyBandage) ~= "function" then
            return false, "medical_unavailable"
        end
        return SC.Medical.replaceDirtyBandage(actor)
    end
    if not reserveActivity(actor, activity, now) then return false, "reserved" end
    if restPostures[activity.kind] then
        activity.deadlines = activity.deadlines or {}
        activity.deadlines.animating = tonumber(
            U().config("bedEntryTimeoutMs")) or 12000
        activity.deadlines.waiting = math.max(
            tonumber(activity.durationMs) or 0, 30000)
    end
    activity.commandSerial = commands.commandSerial or 0
    local owned, ownerReason = beginSupervisedActivity(actor, state, activity)
    if owned ~= true then
        releaseActivity(actor, activity)
        return false, ownerReason or "downtime_owner_rejected"
    end
    local utility = U()
    local wash = activity.kind == "wash_self" or activity.kind == "wash_equipment"
    local study = activity.kind == "study_corpse" or activity.kind == "pay_respects"
    local furniture = activity.kind == "sit" or activity.kind == "rest_bed"
    local floorRest = activity.kind == "rest_floor"
    local borrowedRead = activity.kind == "read" and activity.borrowedFrom ~= nil
    if activity.kind == "study_corpse" then Study.prepare(actor, activity, commands, state, now) end
    if activity.kind == "pay_respects" then Respect.prepare(actor, activity, commands, state, now) end
    if floorRest then
        if not utility.move(actor, "walk", {
            action = "sit_ground",
            downtime = true,
            supervisorToken = activity.supervisorToken,
        }) then
            state.active = activity
            return failActivity(actor, state, "ground_rest_rejected")
        end
        activity.actionAccepted = true
        activity.entryStartedAt = now
        activity.startedAt = nil
        transitionActivity(activity, "approaching", {
            action = activity.kind, finalAlignment = true,
        })
    elseif borrowedRead then
        state.active = activity
        local accepted, status = approachBorrowedReadingSource(actor, activity)
        if not accepted then return failActivity(actor, state, status or "route_failed") end
        activity.approaching = true
        transitionActivity(activity, "approaching", { status = status })
        if status == "arrived" then
            local started, startReason = startBorrowedReading(actor, activity, now)
            if not started and startReason == "borrowed_book_source_not_in_reach" then
                -- The selected multi-goal can become invalid between native
                -- arrival and this fresh topology check (a companion moved
                -- through the use square in the live camp). Keep the checkout
                -- uncommitted and re-approach instead of failing/reselecting the
                -- same book every decision pulse.
                return true, "approaching_reading_storage"
            end
            if not started then return failActivity(actor, state, startReason) end
        end
    elseif furniture and activity.square then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
            state.active = activity
            return failActivity(actor, state, "navigation_unavailable")
        end
        local accepted, status = approachFurniture(actor, activity)
        if not accepted then
            state.active = activity
            return failActivity(actor, state, status or "route_failed")
        end
        if status == "arrived" then
            if not utility.move(actor, "walk", {
                action = activity.kind,
                object = activity.object,
                downtime = true,
                supervisorToken = activity.supervisorToken,
            }) then
                state.active = activity
                return failActivity(actor, state, "animation_rejected")
            end
            activity.approaching = nil
            activity.actionAccepted = true
            activity.entryStartedAt = now
            activity.startedAt = nil
            transitionActivity(activity, "approaching", {
                action = activity.kind, finalAlignment = true,
            })
        else
            activity.approaching = true
            transitionActivity(activity, "approaching", { status = status })
        end
    elseif (wash or study) and activity.square
        and (wash and not washSourceInReach(actor, activity)
            or not wash and utility.distance(actor, activity.square) > Study.REACH) then
        if SC.Navigation and (type(SC.Navigation.request) == "function"
            or wash and type(SC.Navigation.requestAny) == "function") then
            local accepted, status
            if wash then
                accepted, status = approachWashSource(actor, activity)
                if not accepted then coolWashSource(state, activity.object, now) end
            else
                accepted, status = SC.Navigation.request(actor, activity.square, "walk", {
                    action = study and "move_to_corpse" or "move_to_seat",
                    targetSquare = activity.square,
                    object = activity.object,
                    supervisorToken = activity.supervisorToken,
                })
            end
            if not accepted then
                state.active = activity
                return failActivity(actor, state, status or "route_failed")
            end
            if wash and status == "arrived" then activity.atSource = true end
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
            exercise = activity.exercise,
            struggle = activity.struggle,
            downtime = true,
            durationMs = activity.durationMs or Study.duration(activity.kind),
            supervisorToken = activity.supervisorToken,
        }) then
            state.active = activity
            return failActivity(actor, state, "animation_rejected")
        end
        if restPostures[activity.kind] then
            activity.entryStartedAt = now
            activity.startedAt = nil
        else
            activity.startedAt = now
        end
        activity.actionAccepted = true
        if study then Study.speakNext(actor, activity, now) end
        if activity.kind == "workout" and SC.Gestures
            and type(SC.Gestures.workoutStarted) == "function" then
            pcall(SC.Gestures.workoutStarted, actor, activity, now)
        end
        -- The stock furniture actions may still make a short, precise move to
        -- a SeatingManager position. Keep movement legal until the native pose
        -- is actually entered; protecting the pose here falsely cancelled that
        -- final alignment as "protected_pose_moved".
        transitionActivity(activity, furniture and "approaching"
            or visualActivities[activity.kind]
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
    if not washSourceValid(activity.object) then return false end
    if not washSourceInReach(actor, activity) then return false end
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
    if not washSourceValid(activity.object) then return false end
    if not washSourceInReach(actor, activity) then return false end
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
    elseif activity.kind == "rest_bed" then
        success = activity.actionAccepted == true
    elseif activity.kind == "rest_floor" then
        success = activity.actionAccepted == true
    elseif activity.kind == "wash_self" then
        success = completeWashSelf(actor, activity)
    elseif activity.kind == "wash_equipment" then
        success = completeWashEquipment(actor, activity)
    elseif activity.kind == "study_corpse" or activity.kind == "pay_respects"
        or activity.kind == "workout" then
        success = activity.actionAccepted == true
    elseif activity.kind == "write_diary" then
        -- The page is committed only now, after the verified writing pose
        -- completed, and only if the author and exact book still qualify.
        success = activity.actionAccepted == true and SC.Diary ~= nil
            and type(SC.Diary.commitWrite) == "function"
            and SC.Diary.commitWrite(actor, activity.diary) == true
    end
    local failureReasons = {
        repair = "repair_commit_failed",
        craft_supply = "craft_commit_failed",
        read = "read_verification_failed",
        sit = "sit_verification_failed",
        rest_bed = "bed_rest_verification_failed",
        rest_floor = "floor_rest_verification_failed",
        wash_self = "wash_self_commit_failed",
        wash_equipment = "wash_equipment_commit_failed",
        study_corpse = "study_verification_failed",
        pay_respects = "respects_verification_failed",
        workout = "workout_verification_failed",
        write_diary = "diary_commit_failed",
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
    -- A completed chair/sofa sit becomes a passive posture. The native rest
    -- action has left the queue, so Read/Write may begin without getting up.
    -- Skip the ordinary post-action look-around pause here: that observation
    -- is a standing action and could undo the seat before the follow-up starts.
    if activity.kind == "sit" and activity.furnitureEntered == true then
        activity.preserveSeating = true
    end
    if success then
        if activity.kind == "study_corpse" then Study.finish(actor, activity, now) end
        if activity.kind == "pay_respects" then Respect.finish(actor, activity, now) end
        if activity.kind == "workout" and SC.Gestures
            and type(SC.Gestures.workoutFinished) == "function" then
            pcall(SC.Gestures.workoutFinished, actor, activity, now)
        end
        if SC.Diary and type(SC.Diary.noteDowntime) == "function" then
            local memento = activity.kind == "pay_respects" and activity.object ~= nil
                and Respect.memento(activity.object) or nil
            pcall(SC.Diary.noteDowntime, actor, activity, { memento = memento })
        end
        local fact = U().copyShallow(activity.fact)
        fact.completedAt = now
        state.lastFact = fact
        if SC.Commands and type(SC.Commands.noteDowntime) == "function" then
            pcall(SC.Commands.noteDowntime, actor, fact)
        end
        if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
            SC.NativeActions.noteResult(actor, "downtime_" .. tostring(activity.kind),
                "completed", { kind = "long", skip = activity.preserveSeating == true })
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
    if seatingStatus(actor) ~= "standing" and SC.NativeActions
        and type(SC.NativeActions.leaveSeating) == "function" then
        local ok, stood = pcall(SC.NativeActions.leaveSeating, actor)
        changed = changed or ok and stood == true
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
    local unsafe = dangerPresent(snapshot, actor, current)
        or not orderAllowsIdle(commands, actor, player, snapshot)
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
        local furniture = state.active.kind == "sit" or state.active.kind == "rest_bed"
        local floorRest = state.active.kind == "rest_floor"
        local borrowedCheckout = state.active.kind == "read"
            and state.active.borrowedFrom ~= nil and state.active.borrowedReading ~= true
        if borrowedCheckout then
            local accepted, status = approachBorrowedReadingSource(actor, state.active)
            if not accepted then return failActivity(actor, state, status or "route_failed") end
            transitionActivity(state.active, "approaching", { status = status })
            if status ~= "arrived" then return true, "approaching_reading_storage" end
            local started, startReason = startBorrowedReading(actor, state.active, current)
            if not started and startReason == "borrowed_book_source_not_in_reach" then
                transitionActivity(state.active, "approaching", { status = startReason })
                return true, "approaching_reading_storage"
            end
            if not started then return failActivity(actor, state, startReason) end
            return true, state.active.kind
        end
        if furniture and state.active.square and state.active.approaching then
            local accepted, status = approachFurniture(actor, state.active)
            if not accepted then return failActivity(actor, state, status or "route_failed") end
            transitionActivity(state.active, "approaching", { status = status })
            if status ~= "arrived" then return true, "approaching_seat" end
        end
        local washing = state.active.kind == "wash_self"
            or state.active.kind == "wash_equipment"
        if washing and state.active.approaching and state.active.atSource ~= true
            and not washSourceInReach(actor, state.active) then
            local accepted, status = approachWashSource(actor, state.active)
            if not accepted then
                coolWashSource(state, state.active.object, current)
                return failActivity(actor, state, status or "route_failed")
            end
            if status ~= "arrived" then
                transitionActivity(state.active, "approaching", { status = status })
                return true, "approaching_wash_source"
            end
            -- Standing on a free square beside the source is close enough.
            state.active.atSource = true
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
        local studying = state.active.kind == "study_corpse" or state.active.kind == "pay_respects"
        if studying and not Study.stillThere(state.active) then
            return failActivity(actor, state, state.active.kind == "pay_respects"
                and "respects_body_gone" or "study_body_gone")
        end
        if studying and state.active.approaching then
            if utility.distance(actor, state.active.square) > Study.REACH then
                if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
                    return failActivity(actor, state, "navigation_unavailable")
                end
                local accepted, status = SC.Navigation.request(actor, state.active.square, "walk", {
                    action = "move_to_corpse",
                    targetSquare = state.active.square,
                    object = state.active.object,
                    supervisorToken = state.active.supervisorToken,
                })
                if not accepted then
                    return failActivity(actor, state, status or "route_failed")
                end
                transitionActivity(state.active, "approaching", { status = status })
                return true, "approaching_corpse"
            end
            local kind = state.active.kind
            local expected, expectedReason = startSupervisedVisual(actor, state.active, {
                action = kind,
            })
            if expected ~= true then return failActivity(actor, state,
                expectedReason or "visual_registration_failed") end
            if not utility.move(actor, "walk", {
                action = kind,
                object = state.active.object,
                downtime = true,
                durationMs = Study.duration(kind),
                supervisorToken = state.active.supervisorToken,
            }) then
                return failActivity(actor, state, "animation_rejected")
            end
            state.active.approaching = nil
            state.active.actionAccepted = true
            state.active.startedAt = current
            transitionActivity(state.active, "animating", { action = kind })
            Study.speakNext(actor, state.active, current)
            return true, kind
        end
        if studying then Study.speakNext(actor, state.active, current) end
        if furniture and state.active.approaching then
            if not utility.move(actor, "walk", {
                action = state.active.kind,
                object = state.active.object,
                downtime = true,
                supervisorToken = state.active.supervisorToken,
            }) then
                return failActivity(actor, state, "animation_rejected")
            end
            state.active.approaching = nil
            state.active.actionAccepted = true
            if state.active.kind == "rest_bed" or state.active.kind == "sit" then
                state.active.entryStartedAt = current
                state.active.startedAt = nil
                transitionActivity(state.active, "approaching", {
                    action = state.active.kind, finalAlignment = true,
                })
            else
                state.active.startedAt = current
                transitionActivity(state.active, "settling", { action = state.active.kind })
            end
            return true, state.active.kind
        end
        if (furniture or floorRest) and state.active.actionAccepted == true
            and state.active.furnitureEntered ~= true then
            local entryState = "none"
            if state.active.kind == "rest_bed" and SC.NativeActions
                and type(SC.NativeActions.bedStatus) == "function" then
                entryState = SC.NativeActions.bedStatus(actor)
            elseif state.active.kind == "sit" and SC.NativeActions
                and type(SC.NativeActions.furnitureStatus) == "function" then
                entryState = SC.NativeActions.furnitureStatus(actor)
            elseif floorRest and SC.NativeActions
                and type(SC.NativeActions.groundStatus) == "function" then
                entryState = SC.NativeActions.groundStatus(actor)
            elseif floorRest then
                local seated, seatedOk = utility.call(actor, "isSitOnGround")
                entryState = seatedOk and seated == true and "entered" or "entering"
            end
            if entryState == "entered" then
                state.active.furnitureEntered = true
                state.active.startedAt = current
                local animated, animatedReason = transitionActivity(
                    state.active, "animating", { action = state.active.kind, entered = true })
                if animated ~= true then
                    return failActivity(actor, state,
                        animatedReason or "furniture_pose_transition_failed")
                end
                local transitioned, transitionReason = transitionActivity(
                    state.active, "waiting", { action = state.active.kind, entered = true })
                if transitioned ~= true then
                    return failActivity(actor, state,
                        transitionReason or "furniture_entry_transition_failed")
                end
                if state.active.kind == "rest_bed" then return true, "resting_on_bed" end
                if floorRest then return true, "resting_on_floor" end
                return true, "sitting_on_furniture"
            end
            local elapsed = current - (tonumber(state.active.entryStartedAt) or current)
            if entryState ~= "entering"
                or elapsed >= (utility.config("bedEntryTimeoutMs") or 12000) then
                local prefix = state.active.kind == "rest_bed" and "bed"
                    or floorRest and "floor" or "furniture"
                return failActivity(actor, state, entryState == "entering"
                    and prefix .. "_entry_timeout" or prefix .. "_entry_failed")
            end
            if state.active.kind == "rest_bed" then return true, "getting_on_bed" end
            if floorRest then return true, "sitting_on_floor" end
            return true, "taking_seat"
        end
        local duration = state.active.durationMs or Study.duration(state.active.kind)
        -- Work speed shapes chores; an activity with its own length keeps it.
        if not state.active.durationMs and SC.Autonomy
            and type(SC.Autonomy.workDuration) == "function" then
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

function Downtime._readingForTests()
    return readActivity, campReadingActivity, returnBorrowedReadingItem
end

function Downtime._furnitureForTests()
    return furnitureKind, seatActivity, approachFurniture, beginActivity,
        coolFurniture, furnitureCooling, floorRestActivity, seatingStatus
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
        Study.lastPartyAt = -math.huge
        Respect.lastPartyAt = -math.huge
    end
end

-- Test seam: the harness checks eligibility, curiosity and outfit groups.
-- Test seam: wash source choice, approach, failure memory, the reach rule
-- every start and commit shares, and the two commits themselves.
function Downtime._washForTests()
    return nearbyWashSource, approachWashSource, coolWashSource, washSourceCooling,
        washSourceInReach, completeWashSelf, completeWashEquipment
end

-- Test seam: the camp-book checkout policy re-read at transfer time.
function Downtime._borrowedCheckoutForTests()
    return borrowedCheckoutAuthorized
end

function Downtime._studyForTests()
    return Study
end

function Downtime._respectForTests()
    return Respect
end

Study.register()
Respect.register()

return Downtime
