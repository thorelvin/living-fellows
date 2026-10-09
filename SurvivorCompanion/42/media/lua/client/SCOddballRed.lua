-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.OddballRed = SC.OddballRed or {}
local Red = SC.OddballRed
local immunityByActor = setmetatable({}, { __mode = "k" })
local gutByActor = setmetatable({}, { __mode = "k" })
local roamByActor = setmetatable({}, { __mode = "k" })
local RUN_ITEMS = {
    medicine = "Base.FirstAidKit",
    ammunition = "Base.Bullets9mmBox",
    tools = "Base.HandAxe",
}
local GUT_REACH = 1.5
local GUT_APPROACH_TIMEOUT_MS = 30000
local GUT_VISUAL_TIMEOUT_MS = 15000
local scrapingTools = {
    ["Base.HandScythe"] = true, ["Base.HuntingKnife"] = true,
    ["Base.KitchenKnife"] = true, ["Base.MeatCleaver"] = true,
    ["Base.FlintKnife"] = true, ["Base.Machete"] = true,
}
local RED_STARTING_GEAR = { "Base.HandScythe", "Base.TinnedBeans" }

local function U() return SC.GameplayUtil end
local function state(group)
    return SC.Oddballs and type(SC.Oddballs.state) == "function"
        and SC.Oddballs.state(group) or group and group.oddball
end
local function worldHour()
    if type(getGameTime) == "function" then
        local ok, clock = pcall(getGameTime)
        if ok and clock then
            local hour, called = U().call(clock, "getWorldAgeHours")
            if called and tonumber(hour) then return tonumber(hour) end
        end
    end
    return U().nowMs() / 3600000
end
local function actorFor(group)
    local member = SC.Factions and SC.Factions.member(group, "member-1")
    local actorId = member and member.actorId or group and group.recruitment
        and group.recruitment.joinedActorId
    local record = actorId and SC.Registry and SC.Registry.byId(actorId)
    return record and record.actor or nil
end
local function speak(actor, topic, fallback)
    if not actor then return end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "oddball.red." .. topic, nil, nil,
            { fallback = fallback })
    else U().say(actor, fallback) end
end
local function rainyOutside(actor)
    if not actor or type(getClimateManager) ~= "function" then return false end
    local square = U().squareOf(actor)
    local outside, outsideOk = U().call(square, "isOutside")
    if not outsideOk or outside ~= true then return false end
    local ok, climate = pcall(getClimateManager)
    return ok and climate ~= nil
        and select(1, U().call(climate, "isRaining")) == true
end
local function cloak(group)
    local value = state(group)
    return value and type(value.cloak) == "table" and value.cloak or nil
end
local function active(group)
    local value = cloak(group)
    return value ~= nil and (tonumber(value.remainingHours) or 0) > 0
end
local function safeBlood(actor)
    local parts = type(_G) == "table" and rawget(_G, "BloodBodyPartType") or nil
    if not actor or not parts then return end
    local maxOk, maximum = pcall(function() return parts.MAX:index() end)
    if not maxOk or not tonumber(maximum) then return end

    -- addBlood is affected by clothing degradation and one call may leave only
    -- a faint splatter. Set the visual levels directly so Red is blood-soaked
    -- even when that sandbox setting is low or disabled.
    local visual = select(1, U().call(actor, "getHumanVisual"))
    local changed = false
    for index = 0, math.min(tonumber(maximum), 64) - 1 do
        local partOk, part = pcall(function() return parts.FromIndex(index) end)
        if partOk and part and visual then
            local _, set = U().call(visual, "setBlood", part, 1)
            changed = changed or set
        end
    end

    local worn = select(1, U().call(actor, "getWornItems"))
    local wornCount = select(1, U().call(worn, "size"))
    local clothing = type(_G) == "table" and rawget(_G, "BloodClothingType") or nil
    for index = 0, math.min(tonumber(wornCount) or 0, 64) - 1 do
        local entry = select(1, U().call(worn, "get", index))
        local item = select(1, U().call(entry, "getItem"))
        local kinds = select(1, U().call(item, "getBloodClothingType"))
        local coveredOk, covered = pcall(function()
            return clothing and kinds and clothing.getCoveredParts(kinds)
        end)
        if coveredOk and covered then
            local coveredCount = select(1, U().call(covered, "size"))
            for partIndex = 0, math.min(tonumber(coveredCount) or 0, 64) - 1 do
                local part = select(1, U().call(covered, "get", partIndex))
                if part then
                    local _, set = U().call(item, "setBlood", part, 1)
                    changed = changed or set
                end
            end
            pcall(function() clothing.calcTotalBloodLevel(item) end)
        end
    end
    if changed then U().call(actor, "resetModelNextFrame") end
end
local function syncImmunity(group, actor)
    if not actor then return end
    local enabled = active(group)
    local last = immunityByActor[actor]
    if last == enabled then return end
    local _, set = U().call(actor, "setZombiesDontAttack", enabled)
    if not set then return end
    immunityByActor[actor] = enabled
    if enabled then
        local snapshot = SC.Senses and type(SC.Senses.cached) == "function"
            and SC.Senses.cached(actor) or nil
        if snapshot and SC.ZombieTargeting
            and type(SC.ZombieTargeting.releaseTargets) == "function" then
            SC.ZombieTargeting.releaseTargets(actor, snapshot.threats)
        end
        if SC.ZombieAttack and type(SC.ZombieAttack.reset) == "function" then
            SC.ZombieAttack.reset(actor)
        end
    end
end
local function breakCloak(group, actor, reason)
    local value = cloak(group)
    if not value or (tonumber(value.remainingHours) or 0) <= 0 then return false end
    value.remainingHours = 0
    value.updatedHour = worldHour()
    syncImmunity(group, actor)
    if reason == "rain" then
        speak(actor, "cloak_fading", "I can feel it washing off. They're starting to look.")
    end
    return true
end
local function fadeCloak(group, actor)
    local cover = cloak(group)
    if not cover then return end
    local hour = worldHour()
    local previous = tonumber(cover.updatedHour) or hour
    local elapsed = math.max(0, math.min(168, hour - previous))
    local multiplier = rainyOutside(actor)
        and (tonumber(U().config("oddballGoreRainMultiplier")) or 4) or 1
    cover.remainingHours = math.max(0,
        (tonumber(cover.remainingHours) or 0) - elapsed * multiplier)
    cover.updatedHour = hour
    if actor and (select(1, U().call(actor, "isRunning")) == true
        or select(1, U().call(actor, "isSprinting")) == true
        or select(1, U().call(actor, "isAttackStarted")) == true) then
        breakCloak(group, actor, "movement")
    end
    syncImmunity(group, actor)
end
local function corpseNear(actor, radius)
    local x, y, z = U().position(actor)
    if not x then return nil end
    radius = math.max(1, math.min(15, math.floor(radius or 3)))
    local best, bestDistance
    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= radius * radius then
                local square = U().gridSquare(x + dx, y + dy, z)
                U().squareStaticMovingObjects(square, function(body)
                    if not U().instanceOf(body, "IsoDeadBody") then return end
                    local animal, animalOk = U().call(body, "isAnimal")
                    if animalOk and animal then return end
                    local distance = U().distanceSq(actor, body)
                    if best == nil or distance < bestDistance then
                        best, bestDistance = body, distance
                    end
                end, 12)
            end
        end
    end
    return best
end
local function corpseAt(point)
    if type(point) ~= "table" then return nil, nil end
    local square = U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return nil, nil end
    local found
    U().squareStaticMovingObjects(square, function(body)
        if found or not U().instanceOf(body, "IsoDeadBody") then return end
        local animal = select(1, U().call(body, "isAnimal"))
        if animal ~= true then found = body end
    end, 12)
    return found, square
end
local function scraperFor(actor)
    local inventory = U().inventory(actor)
    if not inventory then return nil, "inventory_unavailable" end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        if scrapingTools[U().itemType(item)] == true then return item end
    end
    return nil, "scraping_tool_required"
end
local function seedStartingGear(group, actor)
    local value = state(group)
    if not value or value.gearSeeded == true then return true end
    local inventory = U().inventory(actor)
    if not inventory then return false, "red_inventory_unavailable" end
    local present = {}
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        present[U().itemType(item)] = true
    end
    for _, kind in ipairs(RED_STARTING_GEAR) do
        if not present[kind] then
            local added, reason = U().addItem(inventory, kind)
            if not added or U().itemType(added) ~= kind then
                value.gearProblem = reason or "red_gear_add_failed:" .. kind
                return false, value.gearProblem
            end
            present[kind] = true
        end
    end
    -- This durable marker is deliberately separate from the current inventory:
    -- a confiscated scythe or eaten beans must stay gone after save/load.
    value.gearSeeded = true
    value.gearProblem = nil
    return true
end
local function scraperCarried(actor, item)
    if not item then return false end
    local inventory = U().inventory(actor)
    if not inventory then return false end
    for _, candidate in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        if candidate == item then return true end
    end
    return false
end
local function gutServices()
    local service = SC.ActionSupervisor
    if not service or type(service.begin) ~= "function"
        or type(service.current) ~= "function"
        or type(service.isCurrent) ~= "function"
        or type(service.reserve) ~= "function" then
        return nil, "action_supervisor_unavailable"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return nil, "navigation_unavailable"
    end
    if not SC.NativeActions or type(SC.NativeActions.visualStatus) ~= "function" then
        return nil, "visual_unavailable"
    end
    return service
end
local function clearGut(group, actor, reason, failToken)
    local value = state(group)
    local record = gutByActor[actor]
    local service = SC.ActionSupervisor
    if failToken and record and record.token and service
        and service.isCurrent(record.token) then
        if record.phase == "animating" and SC.NativeActions
            and type(SC.NativeActions.cancelVisual) == "function" then
            local cancelled, cancelReason = SC.NativeActions.cancelVisual(actor,
                reason or "red_gutting_cancelled")
            if cancelled ~= true then return false, cancelReason end
        elseif record.phase == "approaching" and record.navStarted
            and SC.Navigation and type(SC.Navigation.cancel) == "function" then
            SC.Navigation.cancel(actor, "red_gutting_failed:" .. tostring(reason))
        end
    end
    if value then
        value.gutting = nil
        if reason then value.guttingProblem = reason end
    end
    gutByActor[actor] = nil
    if failToken and record and record.token and service
        and service.isCurrent(record.token) then
        service.fail(record.token, reason or "gutting_cancelled")
    end
    return false, reason or "gutting_cancelled"
end
local function beginGut(group, actor, body, explicit)
    local service, serviceReason = gutServices()
    if not service then return false, serviceReason end
    if service.current(actor) then return false, "actor_owned_by_other_action" end
    local tool, toolReason = scraperFor(actor)
    if not tool then return false, toolReason end
    local x, y, z = U().position(body)
    if x == nil then return false, "corpse_unavailable" end
    local point = { x = math.floor(x), y = math.floor(y),
        z = math.floor(z or 0) }
    local actual = corpseAt(point)
    if actual ~= body then return false, "corpse_gone" end
    if U().distance(actor, body) > 3 or not U().sameFloor(actor, body) then
        return false, "nearby_zombie_corpse_required"
    end
    local key = tostring(point.x) .. ":" .. tostring(point.y)
        .. ":" .. tostring(point.z)
    local token, reason = service.begin(actor, {
        owner = "player_control", action = "red_gut_up",
        priority = service.Priority and service.Priority.PLAYER or 400,
        targetKey = key, targetLabel = "zombie corpse",
        deadlines = { approaching = GUT_APPROACH_TIMEOUT_MS,
            animating = GUT_VISUAL_TIMEOUT_MS },
        allowedActions = { red_approach_corpse = true,
            study_corpse = true },
        onCancel = function(_, cancelReason, cancelled)
            local record = gutByActor[actor]
            if record and record.token == cancelled then
                if record.phase == "animating" and SC.NativeActions
                    and type(SC.NativeActions.cancelVisual) == "function" then
                    local stopped, stopReason = SC.NativeActions.cancelVisual(actor,
                        cancelReason or "red_gutting_interrupted")
                    if stopped ~= true then return false, stopReason end
                elseif record.phase == "approaching" and record.navStarted
                    and SC.Navigation and type(SC.Navigation.cancel) == "function" then
                    SC.Navigation.cancel(actor, "red_gutting_interrupted")
                end
                local value = state(group)
                if value then value.gutting = nil
                    value.guttingProblem = cancelReason or "gutting_interrupted" end
                gutByActor[actor] = nil
            end
            return true
        end,
    })
    if not token then
        if service.containsDeferredStatus
            and service.containsDeferredStatus(reason) then
            return false, "deferred:" .. tostring(reason)
        end
        return false, reason or "gutting_owner_rejected"
    end
    local reserved, reserveReason = service.reserve(token, body, "red_gutting_corpse")
    if reserved == true then
        reserved, reserveReason = service.reserve(token, tool, "red_scraping_tool")
    end
    if reserved ~= true then
        service.fail(token, reserveReason or "gutting_resource_reserved")
        return false, reserveReason or "gutting_resource_reserved"
    end
    local approaching, phaseReason = service.transition(token, "approaching",
        { corpse = key })
    if approaching ~= true then
        service.fail(token, phaseReason or "gutting_approach_rejected")
        return false, phaseReason or "gutting_approach_rejected"
    end
    local value = state(group)
    value.gutting = point
    value.guttingProblem = nil
    gutByActor[actor] = { token = token, corpse = body, tool = tool,
        phase = "approaching", explicit = explicit == true,
        startedAt = U().nowMs(), navStarted = false }
    return true, "gutting_started"
end
local function checkNear(group, player)
    local actor = actorFor(group)
    if not actor or not player then return nil, "red_unavailable" end
    if U().distance(actor, player) > 8 then return nil, "red_too_far" end
    return actor
end
local function itemType(item)
    return item and U().itemType(item) or nil
end
local function findPayment(inventory)
    local food, cigarettes
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        local full = itemType(item)
        if full == "Base.CigarettePack" then cigarettes = cigarettes or item end
        if full == "Base.TinnedBeans" or full == "Base.CannedSardines"
            or full == "Base.CannedCornedBeef" then food = food or item end
        if food and cigarettes then return food, cigarettes end
    end
    return food, cigarettes
end
local function transfer(sourceActor, destinationActor, item)
    local source = select(1, U().call(item, "getContainer"))
    local destination = U().inventory(destinationActor)
    if not source or not destination then return false, "payment_container_missing" end
    return U().transferItemVerified(source, destination, item)
end
local function hash(group, salt)
    local value = tostring(group.id or "red") .. ":" .. tostring(salt or "")
    local result = 17
    for index = 1, #value do result = (result * 31 + value:byte(index)) % 1000003 end
    return result
end
local function unseenRunWaypoint(actor, player)
    local ax, ay, az = U().position(actor)
    local px, py = U().position(player)
    if not ax or not px then return nil end
    local directions = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
    local best, bestDistance
    for _, distance in ipairs({ 24, 36, 48 }) do
        for _, direction in ipairs(directions) do
            local x = math.floor(ax + direction[1] * distance)
            local y = math.floor(ay + direction[2] * distance)
            local square = U().gridSquare(x, y, az)
            if square and U().isSquareFree(square)
                and not U().canSee(player, square) then
                local playerDistance = U().distance(player, square)
                if playerDistance > 20 and (not best or playerDistance > bestDistance) then
                    best = { x = x, y = y, z = az }
                    bestDistance = playerDistance
                end
            end
        end
    end
    return best
end
local function hordeEscape(actor, player, group)
    local snapshot = SC.Senses and type(SC.Senses.cached) == "function"
        and SC.Senses.cached(actor) or nil
    local closest, distance
    for index, entry in ipairs(snapshot and snapshot.threats or {}) do
        if index > 64 then break end
        local zombie = type(entry) == "table" and entry.actor or entry
        local gap = zombie and U().isZombie(zombie) and not U().isDead(zombie)
            and U().distance(actor, zombie) or math.huge
        if gap <= 20 and (not distance or gap < distance) then
            local x, y, z = U().position(zombie)
            if x then
                closest, distance = { x = math.floor(x), y = math.floor(y),
                    z = math.floor(z or 0) }, gap
            end
        end
    end
    return closest or unseenRunWaypoint(actor, player)
        or state(group).site and state(group).site.spawn
end
local function roadAt(square)
    if not square then return false end
    local floor = select(1, U().call(square, "getFloor"))
    local sprite = floor and select(1, U().call(floor, "getSprite"))
    local name = sprite and select(1, U().call(sprite, "getName"))
    name = string.lower(tostring(name or ""))
    return string.find(name, "street", 1, true) ~= nil
        or string.find(name, "road", 1, true) ~= nil
        or string.find(name, "asphalt", 1, true) ~= nil
end
local function roamPoints(group)
    local value = state(group)
    if type(value.roam) == "table" then return value.roam end
    local origin = value.site and value.site.spawn
    local points = {}
    if origin then
        local axes = { { 1, 0 }, { 0, 1 } }
        for _, axis in ipairs(axes) do
            for _, sign in ipairs({ -1, 1 }) do
                for distance = 3, 6 do
                    local x = origin.x + axis[1] * distance * sign
                    local y = origin.y + axis[2] * distance * sign
                    local square = U().gridSquare(x, y, origin.z or 0)
                    if square and U().isSquareFree(square) and roadAt(square) then
                        points[#points + 1] = { x = x, y = y, z = origin.z or 0 }
                        break
                    end
                end
            end
            if #points >= 2 then break end
        end
    end
    value.roam = { points = points, index = 1 }
    return value.roam
end
local function safeShelter(group, actor, player)
    local site = state(group) and state(group).site
    local house = site and site.house
    local bounds = house and house.bounds
    if type(bounds) ~= "table" or not actor or not player then return false end
    local x, y, z = U().position(actor)
    local px, py, pz = U().position(player)
    if not x or not px or z ~= pz then return false end
    return x >= bounds.x1 and x <= bounds.x2 and y >= bounds.y1 and y <= bounds.y2
        and px >= bounds.x1 and px <= bounds.x2 and py >= bounds.y1 and py <= bounds.y2
end

function Red.zombiesIgnore(actor, group)
    return actor ~= nil and group ~= nil and active(group), "actor_gore_cloaked"
end

function Red.onSpawn(group, actor)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" then return false end
    seedStartingGear(group, actor)
    value.cloak = type(value.cloak) == "table" and value.cloak or {
        remainingHours = tonumber(U().config("oddballGoreCloakHours")) or 18,
        updatedHour = worldHour(), renewedHour = worldHour(),
    }
    value.cloak.remainingHours = math.max(0,
        math.min(24, tonumber(value.cloak.remainingHours) or 0))
    value.cloak.updatedHour = tonumber(value.cloak.updatedHour) or worldHour()
    if active(group) then safeBlood(actor) end
    syncImmunity(group, actor)
    return true
end

function Red.pulse(group, player, current)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" then return false end
    local actor = actorFor(group)
    if actor and value.cloak == nil then Red.onSpawn(group, actor) end
    if actor and value.gearSeeded ~= true then seedStartingGear(group, actor) end
    local hour = worldHour()
    fadeCloak(group, actor)
    if actor and player and value.stage == "unmet"
        and U().distance(actor, player) <= 12 and U().canSee(player, actor) then
        value.stage = "met"
        if SC.Factions then SC.Factions.markDiscovered(group.id) end
        speak(actor, "first_sight", "Hush. They think I'm kin.")
    end
    local cover = cloak(group)
    if actor and rainyOutside(actor) and not value.shelterCompleted
        and value.stage ~= "fleeing_to_horde"
        and (tonumber(cover and cover.remainingHours) or 0) <= 3
        and not (value.runner and (value.runner.status == "departing"
            or value.runner.status == "away" or value.runner.status == "returning")) then
        value.stage = "seeking_shelter"
        if player and U().distance(actor, player) <= 40
            and hour - (tonumber(value.rainPleaAt) or -math.huge) >= 1 then
            value.rainPleaAt = hour
            speak(actor, "rain_plea", "Open up. Please. It's coming off me.")
        end
    end
    if value.shelterOffered and not value.shelterCompleted then
        if safeShelter(group, actor, player) then
            value.shelterSinceHour = tonumber(value.shelterSinceHour) or hour
            if hour - value.shelterSinceHour >= 1 / 6 then
                value.shelterCompleted = true
                value.stage = "sheltered"
                if SC.Factions then SC.Factions.adjustStanding(group.id, 60, "red_sheltered") end
                speak(actor, "sheltered", "You gave me a roof when the rain stripped me bare.")
            end
        else value.shelterSinceHour = nil end
    end
    local runner = value.runner
    if type(runner) == "table" and runner.status == "departing"
        and hour >= (tonumber(runner.departDeadlineHour) or math.huge) then
        runner.status = "returned"
        runner.outcome = "empty"
        speak(actor, "run_blocked", "Road's blocked. I can't make that run.")
    end
    if type(runner) == "table" and runner.status == "away" then
        local elapsed = math.max(0, math.min(168,
            hour - (tonumber(runner.lastHour) or hour)))
        if rainyOutside(actor) then runner.rainHours = math.min(24,
            (tonumber(runner.rainHours) or 0) + elapsed) end
        runner.lastHour = hour
        if hour >= (tonumber(runner.dueHour) or math.huge) then
            local chance = math.max(10, 75 - math.floor((runner.rainHours or 0) * 10))
            runner.outcome = hash(group, runner.startedHour) % 100 < chance
                and "success" or "empty"
            runner.status = "returning"
            runner.returnDeadlineHour = hour + 1
        end
    end
    if type(runner) == "table" and runner.status == "returning"
        and hour >= (tonumber(runner.returnDeadlineHour) or math.huge) then
        runner.status = "returned"
    end
    if type(runner) == "table" and runner.status == "returned"
        and runner.announced ~= true then
        runner.announced = true
        if runner.outcome == "success" then
            speak(actor, "run_success", "Got what you asked for. Cost me a clean coat.")
        else speak(actor, "run_empty", "Road went bad. I came back with nothing.") end
    end
    return true
end

local function advanceGut(group, actor, now)
    local value = state(group)
    local record = gutByActor[actor]
    if not record and value.gutting then
        -- A save can restore the durable target without its native action token.
        -- Reacquire the exact loaded corpse and owner instead of granting a cloak.
        local body = corpseAt(value.gutting)
        if not body then return clearGut(group, actor, "corpse_gone", false) end
        local started, reason = beginGut(group, actor, body, true)
        if not started then return clearGut(group, actor, reason, false) end
        record = gutByActor[actor]
    end
    if not record then return false, "no_gutting_action" end
    local service = SC.ActionSupervisor
    if not service or not service.isCurrent(record.token) then
        return clearGut(group, actor, "gutting_owner_lost", false)
    end
    if not scraperCarried(actor, record.tool) then
        return clearGut(group, actor, "scraping_tool_lost", true)
    end
    local body = corpseAt(value.gutting)
    if body ~= record.corpse then
        return clearGut(group, actor, "corpse_gone", true)
    end
    if not U().sameFloor(actor, body) then
        return clearGut(group, actor, "corpse_floor_changed", true)
    end
    local senses = SC.Senses and type(SC.Senses.cached) == "function"
        and SC.Senses.cached(actor) or nil
    if senses and (tonumber(senses.threatCount)
        or #(senses.threats or {})) > 0 then
        return clearGut(group, actor, "gutting_interrupted_by_threat", true)
    end
    if record.phase == "approaching" then
        if now - record.startedAt > GUT_APPROACH_TIMEOUT_MS then
            return clearGut(group, actor, "gutting_approach_timeout", true)
        end
        if U().distance(actor, body) > GUT_REACH then
            local square = U().squareOf(body)
            local accepted, reason = SC.Navigation.request(actor, square, "walk", {
                action = "red_approach_corpse", targetSquare = square,
                object = body, arrivalDistance = 1.2,
                supervisorToken = record.token,
            })
            if accepted ~= true then
                return clearGut(group, actor,
                    "gutting_path_failed:" .. tostring(reason), true)
            end
            record.navStarted = true
            return true, reason or "approaching_corpse"
        end
        if record.navStarted and type(SC.Navigation.cancel) == "function" then
            SC.Navigation.cancel(actor, "red_reached_corpse")
            record.navStarted = false
        end
        local expected, visualReason = service.expectVisual(record.token,
            { action = "study_corpse" })
        if expected ~= true then
            return clearGut(group, actor, visualReason or "gutting_visual_rejected", true)
        end
        local transitioned, phaseReason = service.transition(record.token,
            "animating", { action = "study_corpse" })
        if transitioned ~= true then
            return clearGut(group, actor, phaseReason or "gutting_animation_rejected", true)
        end
        local accepted, moveReason = U().move(actor, "walk", {
            action = "study_corpse", object = body, target = body,
            targetSquare = U().squareOf(body), lootPosition = "Low",
            durationMs = 10000, supervisorToken = record.token,
        })
        if accepted ~= true then
            return clearGut(group, actor,
                "gutting_visual_failed:" .. tostring(moveReason), true)
        end
        record.phase = "animating"
        record.visualDeadline = now + GUT_VISUAL_TIMEOUT_MS
        return true, "gutting_corpse"
    end
    local visual = SC.NativeActions.visualStatus(actor, "study_corpse")
    if visual == "active" then
        if now > (record.visualDeadline or now) then
            return clearGut(group, actor, "gutting_visual_timeout", true)
        end
        service.progress(record.token, "visual:study_corpse",
            { action = "study_corpse" })
        return true, "gutting_corpse"
    end
    if visual ~= "completed" then
        return clearGut(group, actor, "gutting_visual_" .. tostring(visual), true)
    end
    if U().distance(actor, body) > GUT_REACH then
        return clearGut(group, actor, "gutting_moved_from_corpse", true)
    end
    local verified, verifyReason = service.markVisualVerified(record.token,
        { action = "study_corpse" })
    if verified ~= true then
        return clearGut(group, actor, verifyReason or "gutting_visual_unverified", true)
    end
    local committing, commitReason = service.transition(record.token,
        "committing", { action = "red_gut_up" })
    if committing ~= true then
        return clearGut(group, actor, commitReason or "gutting_commit_rejected", true)
    end
    local committed, receipt = service.commit(record.token, function()
        value.cloak = { remainingHours = tonumber(U().config(
            "oddballGoreCloakHours")) or 18, updatedHour = worldHour(),
            renewedHour = worldHour() }
        safeBlood(actor)
        syncImmunity(group, actor)
        return true, "gore_cloak_renewed"
    end)
    if committed ~= true then
        return clearGut(group, actor, receipt or "gutting_commit_failed", true)
    end
    service.transition(record.token, "verifying", { action = "red_gut_up" })
    service.complete(record.token, "gore_cloak_renewed")
    if type(SC.NativeActions.clearVisual) == "function" then
        SC.NativeActions.clearVisual(actor)
    end
    value.gutting = nil
    value.guttingProblem = nil
    gutByActor[actor] = nil
    speak(actor, "gutting", "Sorry, friend. I need your coat.")
    return true, "gore_cloak_renewed"
end

function Red.pulseRecruited(group, actor, player, current)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" or not actor then return false end
    if not value.cloak then Red.onSpawn(group, actor) end
    if value.gearSeeded ~= true then seedStartingGear(group, actor) end
    fadeCloak(group, actor)
    local commands = SC.Commands and SC.Commands.peek(actor)
    if not commands or commands.combatDoctrine ~= "stealth" then
        if value.gutting or gutByActor[actor] then
            clearGut(group, actor, "stealth_doctrine_required", true)
        end
        return true
    end
    local now = tonumber(current) or U().nowMs()
    if value.gutting or gutByActor[actor] then
        return advanceGut(group, actor, now)
    end
    local cover = cloak(group)
    if cover and (tonumber(cover.remainingHours) or 0) > 2 then return true end
    local senses = SC.Senses and type(SC.Senses.cached) == "function"
        and SC.Senses.cached(actor) or nil
    local moving = select(1, U().call(actor, "isMoving"))
    if (senses and (tonumber(senses.threatCount) or #(senses.threats or {})) > 0)
        or moving == true then return true end
    local corpse = corpseNear(actor, GUT_REACH)
    if not corpse then return true end
    local started = beginGut(group, actor, corpse, false)
    if started then return advanceGut(group, actor, now) end
    return true
end

function Red.canRecruit(group)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" then return false end
    if group.standing == "Hostile" or group.permanentHostility then return false end
    if group.recruitment and (group.recruitment.status == "joined"
        or group.recruitment.status == "trial") then return false end
    return value.shelterCompleted == true or group.standing == "Trusted"
end

function Red.menuOptions(group, player)
    local value = state(group)
    if not value then return {} end
    local actor = actorFor(group)
    local near = actor and player and U().distance(actor, player) <= 8
    local runner = value.runner
    local available = not runner or runner.status == "collected"
        or (runner.status == "returned" and runner.outcome == "empty")
    local food, cigarettes
    if player then food, cigarettes = findPayment(U().inventory(player)) end
    local options = {
        { id = "greet", label = "Talk to Red", enabled = near == true },
        { id = "offer_shelter", label = "Offer shelter from the rain",
            enabled = near == true and rainyOutside(actor) and not value.shelterCompleted },
    }
    for _, kind in ipairs({ "medicine", "ammunition", "tools" }) do
        options[#options + 1] = {
            id = "start_run_" .. kind, label = "Ask Red to fetch " .. kind,
            enabled = near == true and available and food ~= nil and cigarettes ~= nil,
            detail = "Costs canned food and a pack of cigarettes.",
        }
    end
    options[#options + 1] = { id = "collect_run", label = "Collect Red's haul",
        enabled = near == true and runner and runner.status == "returned"
            and runner.outcome == "success" }
    options[#options + 1] = { id = "recruit", label = "Ask Red to join",
        enabled = near == true and Red.canRecruit(group) }
    if group.recruitment and group.recruitment.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Decide Red's trial", enabled = near == true }
        options[#options + 1] = { id = "recruitment_return",
            label = "End Red's trial", enabled = near == true }
    end
    if group.recruitment and group.recruitment.status == "joined" then
        local commands = actor and SC.Commands and SC.Commands.peek(actor)
        local tool = actor and scraperFor(actor)
        local owner = actor and SC.ActionSupervisor
            and type(SC.ActionSupervisor.current) == "function"
            and SC.ActionSupervisor.current(actor)
        options[#options + 1] = { id = "gut_up", label = "Gut up",
            enabled = near == true and commands
                and commands.combatDoctrine == "stealth" and tool ~= nil
                and owner == nil and corpseNear(actor, 3) ~= nil }
    end
    return options
end

function Red.action(group, action, player, payload)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" then return false, "wrong_oddball" end
    local actor, nearReason
    if action == "hurt" then
        actor = actorFor(group)
        nearReason = actor and nil or "red_unavailable"
    else actor, nearReason = checkNear(group, player) end
    if not actor then return false, nearReason end
    if action == "hurt" then
        local destination = hordeEscape(actor, player, group)
        if not destination then return false, "red_no_loaded_escape" end
        value.flee = { target = destination, startedAt = U().nowMs() }
        value.stage = "fleeing_to_horde"
        speak(actor, "hurt", "Don't follow me. They won't follow me either.")
        return true, "red_fleeing_to_horde"
    elseif action == "greet" then
        value.stage = value.stage == "unmet" and "met" or value.stage
        if SC.Factions then SC.Factions.markDiscovered(group.id) end
        speak(actor, "greet", "Smell is all they've got. Faces are for the living.")
        return true, "red_greeted"
    elseif action == "offer_shelter" then
        if not rainyOutside(actor) then return false, "not_raining_on_red" end
        value.shelterOffered = true
        value.shelterSinceHour = nil
        value.stage = "seeking_shelter"
        speak(actor, "rain_plea", "Open up. Please. It's coming off me.")
        return true, "shelter_offered"
    elseif action == "recruit" then
        if not Red.canRecruit(group) then return false, "red_not_ready_to_join" end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local status = group.recruitment and group.recruitment.status
        if status ~= "candidate" then
            local named, reason = SC.FactionRecruitment.ask(group, player, false)
            if not named then return false, reason end
        end
        return SC.FactionRecruitment.startTrial(group, player, false)
    elseif action == "recruitment_decide" then
        return SC.FactionRecruitment.decide(group, player)
    elseif action == "recruitment_return" then
        return SC.FactionRecruitment.returnNow(group, player, false)
    elseif action == "gut_up" then
        if not group.recruitment or group.recruitment.status ~= "joined" then
            return false, "red_not_recruited"
        end
        local commands = SC.Commands and SC.Commands.peek(actor)
        if not commands or commands.combatDoctrine ~= "stealth" then
            return false, "stealth_doctrine_required"
        end
        local body = corpseNear(actor, 3)
        if not body then return false, "nearby_zombie_corpse_required" end
        if U().distance(actor, player) > 8 then return false, "red_too_far" end
        if value.gutting or gutByActor[actor] then
            return false, "gutting_already_active"
        end
        return beginGut(group, actor, body, true)
    end
    local kind = type(action) == "string" and string.match(action, "^start_run_(%a+)$")
        or action == "start_run" and type(payload) == "table" and payload.kind
    if kind then
        if not RUN_ITEMS[kind] then return false, "invalid_run_kind" end
        if value.runner and value.runner.status ~= "collected"
            and not (value.runner.status == "returned"
                and value.runner.outcome == "empty") then
            return false, "run_already_active"
        end
        local waypoint = unseenRunWaypoint(actor, player)
        if not waypoint then return false, "no_unseen_loaded_run_route" end
        local playerInventory = U().inventory(player)
        local food, cigarettes = findPayment(playerInventory)
        if not food or not cigarettes then return false, "run_payment_missing" end
        local cigaretteSource = select(1, U().call(cigarettes, "getContainer"))
        local paid, reason = transfer(player, actor, cigarettes)
        if not paid then return false, reason end
        local paidFood, foodReason = transfer(player, actor, food)
        if not paidFood then
            U().transferItemVerified(U().inventory(actor),
                cigaretteSource or playerInventory, cigarettes)
            return false, foodReason
        end
        local hour = worldHour()
        value.runner = { status = "departing", kind = kind, startedHour = hour,
            dueHour = hour + 12 + hash(group, kind .. hour) % 13,
            departDeadlineHour = hour + 1, waypoint = waypoint,
            lastHour = hour, rainHours = 0, outcome = nil,
            foodType = itemType(food) }
        speak(actor, "run_depart", "Walk slow. Breathe slow. I'll bring back what I can.")
        return true, "run_started"
    elseif action == "collect_run" then
        local runner = value.runner
        if not runner or runner.status ~= "returned" or runner.outcome ~= "success" then
            return false, "run_not_ready"
        end
        local inventory = U().inventory(player)
        local item, reason = U().addItem(inventory, RUN_ITEMS[runner.kind])
        if not item then return false, reason end
        runner.status = "collected"
        return true, "run_reward_collected"
    end
    return false, "unknown_red_action"
end

function Red.intentFor(actor, player, snapshot, group)
    local value = state(group)
    if not value or value.id ~= "gut_cloaked_red" then return nil end
    local mode = value.gutting and "red_gutting"
        or value.stage == "fleeing_to_horde" and "red_flee_horde"
        or value.stage == "seeking_shelter" and "red_seek_shelter"
        or value.runner and value.runner.status == "departing" and "red_runner_depart"
        or value.runner and value.runner.status == "away" and "red_runner_away"
        or value.runner and value.runner.status == "returning" and "red_runner_return"
        or value.stage == "unmet" and active(group) and "red_roam"
        or "red_hold"
    local priority = mode == "red_flee_horde" and 110
        or mode == "red_gutting" and 108
        or mode == "red_seek_shelter" and 92 or 32
    return { priority = priority, kind = "faction", mode = mode,
        factionId = group.id }
end

function Red.update(actor, player, runtimeState, intent, group)
    local value = state(group)
    local mode = intent and intent.mode
    if mode == "red_flee_horde" then
        local flee = value.flee
        local square = flee and U().loadedSquare(flee.target)
        if not square or U().nowMs() - (tonumber(flee.startedAt) or 0) > 30000 then
            value.flee = nil
            value.stage = "met"
            return true, "red_flee_ended"
        end
        if U().distance(actor, square) <= 1.5 then
            value.flee = nil
            value.stage = "met"
            return true, "red_reached_horde"
        end
        return SC.Navigation.request(actor, square, "walk", {
            action = "red_flee_horde", targetSquare = square,
            arrivalDistance = 1.2,
        })
    elseif mode == "red_seek_shelter" then
        local anchor = value.site and value.site.house and value.site.house.anchor
        local seekingPlayer = value.shelterOffered ~= true and player
            and U().distance(actor, player) <= 40
        local target = seekingPlayer and player or anchor
        if not target or not SC.Navigation then return false, "shelter_unavailable" end
        if U().distance(actor, target) <= (seekingPlayer and 3 or 2) then
            U().stop(actor)
            return true, seekingPlayer and "red_begging_for_shelter"
                or "waiting_under_shelter"
        end
        local targetSquare = U().loadedSquare(target)
        if not targetSquare then return false, "shelter_unloaded" end
        return SC.Navigation.request(actor, targetSquare, "jog", {
            action = seekingPlayer and "red_beg_shelter" or "red_seek_shelter",
            targetSquare = targetSquare, seekOpenEscape = true,
            arrivalDistance = seekingPlayer and 2.5 or 1.5,
        })
    elseif mode == "red_gutting" then
        local target = value.gutting and U().gridSquare(value.gutting.x,
            value.gutting.y, value.gutting.z)
        if not target then value.gutting = nil return false, "corpse_unloaded" end
        local body
        U().squareStaticMovingObjects(target, function(candidate)
            if not body and U().instanceOf(candidate, "IsoDeadBody") then
                local animal = select(1, U().call(candidate, "isAnimal"))
                if animal ~= true then body = candidate end
            end
        end, 12)
        if not body then value.gutting = nil return false, "corpse_gone" end
        if U().distance(actor, body) > 1.5 then
            return SC.Navigation.request(actor, target, "walk", {
                action = "red_approach_corpse", targetSquare = target,
                arrivalDistance = 1.2,
            })
        end
        local record = gutByActor[actor]
        if type(record) ~= "table" then
            record = { gutCompleteAt = U().nowMs() + 10000, visualStarted = false }
            gutByActor[actor] = record
        end
        if not record.visualStarted then
            record.visualStarted = true
            U().move(actor, "walk", { action = "study_corpse", target = body,
                targetSquare = target, lootPosition = "Low" })
        end
        if U().nowMs() < record.gutCompleteAt then return true, "gutting_corpse" end
        value.gutting = nil
        value.cloak = { remainingHours = tonumber(U().config("oddballGoreCloakHours")) or 18,
            updatedHour = worldHour(), renewedHour = worldHour() }
        safeBlood(actor)
        gutByActor[actor] = nil
        syncImmunity(group, actor)
        speak(actor, "gutting", "Sorry, friend. I need your coat.")
        return true, "gore_cloak_renewed"
    elseif mode == "red_runner_depart" then
        local runner = value.runner
        local square = runner and U().loadedSquare(runner.waypoint)
        if not square then return false, "run_waypoint_unloaded" end
        if U().distance(actor, square) <= 1.5 then
            runner.status = "away"
            return true, "red_at_run_waypoint"
        end
        return SC.Navigation.request(actor, square, "walk", {
            action = "red_runner_depart", targetSquare = square,
            arrivalDistance = 1.2,
        })
    elseif mode == "red_runner_return" then
        local runner = value.runner
        local origin = value.site and value.site.spawn
        local square = origin and U().loadedSquare(origin)
        if not square then return false, "run_return_unloaded" end
        if U().distance(actor, square) <= 2 then
            runner.status = "returned"
            return true, "red_back_from_run"
        end
        return SC.Navigation.request(actor, square, "walk", {
            action = "red_runner_return", targetSquare = square,
            arrivalDistance = 1.5,
        })
    elseif mode == "red_runner_away" then
        if SC.Navigation then SC.Navigation.cancel(actor, "red_waits_offscreen") end
        return true, "red_runner_offscreen"
    elseif mode == "red_roam" then
        local roam = roamPoints(group)
        if #roam.points < 2 then return true, "red_waiting_on_road" end
        local moving = roamByActor[actor]
        if not moving then
            moving = { nextAt = U().nowMs() }
            roamByActor[actor] = moving
        end
        if moving.disabled then return true, "red_road_route_blocked" end
        if U().nowMs() < moving.nextAt then return true, "red_pausing_on_road" end
        local point = roam.points[roam.index]
        local square = point and U().loadedSquare(point)
        if not square then return true, "red_road_unloaded" end
        if U().distance(actor, square) <= 1.2 then
            roam.index = roam.index % #roam.points + 1
            moving.nextAt = U().nowMs() + 6000
            moving.targetAt = nil
            return true, "red_shambling_on_road"
        end
        moving.targetAt = moving.targetAt or U().nowMs()
        if U().nowMs() - moving.targetAt > 30000 then
            moving.disabled = true
            if SC.Navigation then SC.Navigation.cancel(actor, "red_roam_timeout") end
            return true, "red_road_route_blocked"
        end
        local accepted, reason = SC.Navigation.request(actor, square, "walk", {
            action = "red_roam_road", targetSquare = square,
            arrivalDistance = 1.1,
        })
        if not accepted then
            moving.failures = (moving.failures or 0) + 1
            if moving.failures >= 3 then moving.disabled = true end
        end
        return accepted, reason
    end
    U().stop(actor)
    return true, "red_holding"
end

return Red
