-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.OddballSpiffo = SC.OddballSpiffo or {}
local Kevin = SC.OddballSpiffo
local poseByActor = setmetatable({}, { __mode = "k" })
local immunityByActor = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function state(group)
    return SC.Oddballs and type(SC.Oddballs.state) == "function"
        and SC.Oddballs.state(group) or group and group.oddball
end
local function actorFor(group)
    local member = SC.Factions and SC.Factions.member(group, "member-1")
    local actorId = member and member.actorId or group and group.recruitment
        and group.recruitment.joinedActorId
    local record = actorId and SC.Registry and SC.Registry.byId(actorId)
    return record and record.actor or nil
end
local function say(actor, topic, fallback)
    if not actor then return end
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(actor, "oddball.spiffo." .. topic, nil, nil,
            { fallback = fallback })
    else U().say(actor, fallback) end
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
local function posing(group)
    local value = state(group)
    return value and (value.stage == "unmet" or value.stage == "posing")
        and value.revealed ~= true
end
local MANNEQUIN_EXT = "LF_SpiffoMannequin"
local function holdMannequin(actor, pose)
    if pose.held then return true end
    local _, set = U().call(actor, "setVariable", "Ext", MANNEQUIN_EXT)
    if not set then return false end
    local _, reported = U().call(actor, "reportEvent", "EventDoExt")
    if not reported then
        U().call(actor, "clearVariable", "Ext")
        return false
    end
    pose.held = true
    return true
end
local function releaseMannequin(actor)
    local pose = poseByActor[actor]
    if not pose or not pose.held then return end
    pose.held = false
    U().call(actor, "reportEvent", "ExtFinishing")
    U().call(actor, "clearVariable", "Ext")
end
local function syncImmunity(group, actor)
    if not actor then return end
    local enabled = posing(group)
    if immunityByActor[actor] == enabled then return end
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
local function watched(player, target)
    if not player or not target or U().distance(player, target) > 30 then return false end
    local px, py = U().position(player)
    local tx, ty = U().position(target)
    if not px or not tx then return false end
    local dx, dy = tx - px, ty - py
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.05 then return true end
    local fx, fxOk = U().call(player, "getForwardDirectionX")
    local fy, fyOk = U().call(player, "getForwardDirectionY")
    if not fxOk or not fyOk then return false end
    local facingLength = math.sqrt(fx * fx + fy * fy)
    if facingLength < 0.05 then return false end
    local angle = tonumber(U().config("oddballPoseWatchAngle")) or 60
    local dot = (dx * fx + dy * fy) / (length * facingLength)
    if dot < math.cos(math.rad(math.max(0, math.min(89, angle)))) then return false end
    return U().canSee(player, U().loadedSquare(target))
end
local function nearZombie(actor, snapshot)
    if type(snapshot) ~= "table" then return false end
    for _, entry in ipairs(snapshot.threats or {}) do
        local zombie = type(entry) == "table" and entry.actor or entry
        if zombie and U().isZombie(zombie) and not U().isDead(zombie)
            and U().distance(actor, zombie) <= 3 then return true end
    end
    return false
end
local function squareLabel(square)
    local label = ""
    U().squareObjects(square, function(object)
        local text = string.lower(U().objectLabel(object) or "")
        if string.find(text, "window", 1, true) then label = "window"
        elseif label ~= "window" and string.find(text, "counter", 1, true) then
            label = "counter"
        elseif label == "" and string.find(text, "door", 1, true) then
            label = "door"
        elseif label == "" and string.find(text, "booth", 1, true) then
            label = "booth" end
    end, 28)
    return label
end
local function poseSpots(group)
    local value = state(group)
    if type(value.poseSpots) == "table" and #value.poseSpots > 0 then return value.poseSpots end
    local site = value.site or {}
    local origin = site.spawn or site.anchor
    local bounds = site.house and site.house.bounds
    if not origin or not bounds then return {} end
    local ox, oy, oz = math.floor(origin.x), math.floor(origin.y), math.floor(origin.z or 0)
    local spots = { { x = ox, y = oy, z = oz, label = "window" } }
    local candidates = {}
    for x = math.max(bounds.x1, ox - 6), math.min(bounds.x2, ox + 6) do
        for y = math.max(bounds.y1, oy - 6), math.min(bounds.y2, oy + 6) do
            if x ~= ox or y ~= oy then
                local square = U().gridSquare(x, y, oz)
                if square and U().isSquareFree(square) and U().roomName(square) then
                    local label = squareLabel(square)
                    local priority = label == "counter" and 1 or label == "door" and 2
                        or label == "booth" and 3 or label == "window" and 4 or 5
                    candidates[#candidates + 1] = { x = x, y = y, z = oz,
                        label = label, priority = priority }
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        local da = math.abs(a.x - ox) + math.abs(a.y - oy)
        local db = math.abs(b.x - ox) + math.abs(b.y - oy)
        return da < db
    end)
    for _, candidate in ipairs(candidates) do
        local spaced = true
        for _, chosen in ipairs(spots) do
            if math.abs(chosen.x - candidate.x) + math.abs(chosen.y - candidate.y) < 2 then
                spaced = false break
            end
        end
        if spaced then
            candidate.priority = nil
            spots[#spots + 1] = candidate
            if #spots >= 6 then break end
        end
    end
    value.poseSpots = spots
    value.poseIndex = 1
    return spots
end
local function managerSquare(group, player)
    local house = group.house or {}
    local bounds = house.bounds
    if type(bounds) ~= "table" then return nil end
    local best
    local limit = 0
    for x = bounds.x1, bounds.x2 do
        for y = bounds.y1, bounds.y2 do
            limit = limit + 1
            if limit > 512 then return best end
            for z = 0, 1 do
                local square = U().gridSquare(x, y, z)
                local room = string.lower(U().roomName(square) or "")
                if square and (string.find(room, "kitchen", 1, true)
                        or string.find(room, "storage", 1, true))
                    and U().isSafeSpawnSquare(square)
                    and (not player or not U().canSee(player, square)) then
                    if string.find(room, "kitchen", 1, true) then return square end
                    best = best or square
                end
            end
        end
    end
    return best
end
local function fallbackManagerKeys(group)
    local value = state(group)
    if value.managerQuestReady then return true end
    local house = group.house or {}
    local container = house.questContainer and SC.Factions
        and SC.Factions.resolveQuestContainer(house.questContainer,
            house.bounds, house.anchor) or nil
    local bounds = house.bounds
    if not container and type(bounds) == "table" then
        local checked = 0
        for x = bounds.x1, bounds.x2 do
            for y = bounds.y1, bounds.y2 do
                checked = checked + 1
                if checked > 512 then break end
                for z = 0, 1 do
                    local square = U().gridSquare(x, y, z)
                    local room = string.lower(U().roomName(square) or "")
                    if string.find(room, "kitchen", 1, true)
                        or string.find(room, "storage", 1, true) then
                        U().squareObjects(square, function(object)
                            if not container then
                                container = select(1, U().call(object, "getContainer"))
                            end
                        end, 32)
                    end
                    if container then break end
                end
                if container then break end
            end
            if container or checked > 512 then break end
        end
    end
    if not container then return false, "manager_key_container_missing" end
    local key, reason = U().addItem(container, "Base.KeyRing_Spiffos")
    if not key then return false, reason end
    value.managerQuestReady = true
    value.managerKeyFallback = true
    return true, "manager_keys_in_kitchen"
end
local function spawnManager(group, player)
    local value = state(group)
    if value.managerSpawned then return true end
    if type(addZombiesInOutfit) ~= "function" then return false end
    local square = managerSquare(group, player)
    if not square then return false end
    local x, y, z = U().position(square)
    local ok, zombies = pcall(addZombiesInOutfit, x, y, z, 1,
        "Cook_Spiffos", 0)
    if not ok or not zombies then return false end
    local manager = U().listGet(zombies, 0)
    if not manager then return false end
    value.managerSpawned = true
    local key, reason = U().addItem(U().inventory(manager), "Base.KeyRing_Spiffos")
    if key then
        value.managerQuestReady = true
        value.manager = { x = x, y = y, z = z }
        return true
    end
    local fallback = fallbackManagerKeys(group)
    if fallback then return true end
    value.managerIssue = reason or "manager_keys_missing"
    return false
end
local function inventoryItem(inventory, wanted)
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 220, 12)) do
        local kind = U().itemType(item)
        if wanted[kind] then return item end
    end
    return nil
end
local function nearby(group, player)
    local actor = actorFor(group)
    if not actor or not player then return nil, "kevin_unavailable" end
    if U().distance(actor, player) > 8 then return nil, "kevin_too_far" end
    return actor
end
local function escapeSquare(actor, player)
    local x, y, z = U().position(actor)
    if not x then return nil end
    local directions = { { 1, 0 }, { 1, 1 }, { 0, 1 }, { -1, 1 },
        { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }
    local best, distance
    for _, radius in ipairs({ 24, 36, 48 }) do
        for _, direction in ipairs(directions) do
            local square = U().gridSquare(x + direction[1] * radius,
                y + direction[2] * radius, z)
            if square and U().isSquareFree(square)
                and (not player or not U().canSee(player, square)) then
                local away = player and U().distance(player, square) or radius
                if away > (distance or 0) then
                    local sx, sy, sz = U().position(square)
                    best = { x = sx, y = sy, z = sz }
                    distance = away
                end
            end
        end
    end
    return best
end
local function reveal(group, actor, reason)
    local value = state(group)
    if value.revealed then return true end
    value.revealed = true
    value.stage = "revealed"
    value.revealReason = reason
    releaseMannequin(actor)
    if SC.Navigation then SC.Navigation.cancel(actor, "kevin_revealed") end
    syncImmunity(group, actor)
    if SC.Factions then SC.Factions.markDiscovered(group.id) end
    say(actor, "reveal", "I can't talk. The Secret Shopper could be anyone. Could be you.")
    return true
end

function Kevin.zombiesIgnore(actor, group)
    return actor ~= nil and group ~= nil and posing(group), "actor_posing"
end

function Kevin.onSpawn(group, actor)
    local value = state(group)
    if not value or value.id ~= "window_spiffo_kevin" then return false end
    value.stage = value.stage == "unmet" and "posing" or value.stage
    poseSpots(group)
    syncImmunity(group, actor)
    return true
end

function Kevin.pulse(group, player, current)
    local value = state(group)
    if not value or value.id ~= "window_spiffo_kevin" then return false end
    local actor = actorFor(group)
    if actor then
        if not value.poseSpots then Kevin.onSpawn(group, actor) end
        local moving = select(1, U().call(actor, "isMoving")) == true
        local activity = SC.NativeActions and SC.NativeActions.activityStatus
            and SC.NativeActions.activityStatus(actor) or "none"
        if not posing(group) or moving or activity == "active" then
            releaseMannequin(actor)
        end
        syncImmunity(group, actor)
    end
    if not value.managerQuestReady and (tonumber(value.managerAttempts) or 0) < 8 then
        value.managerAttempts = (tonumber(value.managerAttempts) or 0) + 1
        if value.managerSpawned then fallbackManagerKeys(group)
        else spawnManager(group, player) end
    elseif not value.managerQuestReady and value.managerFallbackAttempted ~= true then
        value.managerFallbackAttempted = true
        local placed, reason = fallbackManagerKeys(group)
        if not placed then value.managerIssue = reason end
    end
    return true
end

function Kevin.canRecruit(group)
    local value = state(group)
    return value and value.id == "window_spiffo_kevin"
        and value.clockedOut == true
        and group.standing ~= "Hostile" and not group.permanentHostility
        and not (group.recruitment and (group.recruitment.status == "joined"
            or group.recruitment.status == "trial"))
end

function Kevin.menuOptions(group, player)
    local value = state(group)
    if not value then return {} end
    local actor = actorFor(group)
    local near = actor and player and U().distance(actor, player) <= 8
    local inventory = player and U().inventory(player)
    local key = inventory and inventoryItem(inventory, { ["Base.KeyRing_Spiffos"] = true })
    local meat = inventory and inventoryItem(inventory, { ["Base.MeatPatty"] = true })
    local bread = inventory and inventoryItem(inventory, {
        ["Base.Bread"] = true, ["Base.BreadSlices"] = true,
    })
    local options = {
        { id = "reveal", label = "Talk to the Spiffo", enabled = near == true },
        { id = "clock_out", label = "Give the manager's keys",
            enabled = near == true and key ~= nil and not value.clockedOut,
            detail = "The manager worked in the kitchen." },
        { id = "order_food", label = "Order a burger",
            enabled = near == true and meat ~= nil and bread ~= nil,
            detail = "Bring a raw meat patty and bread." },
        { id = "recruit", label = "Ask Kevin to join",
            enabled = near == true and Kevin.canRecruit(group) },
    }
    if value.managerFallbackAttempted and not value.managerQuestReady then
        options[#options + 1] = { id = "manager_unavailable",
            label = "Manager's keys unavailable: " .. tostring(value.managerIssue or "no storage"),
            enabled = false }
    end
    if group.recruitment and group.recruitment.status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Decide Kevin's trial", enabled = near == true }
        options[#options + 1] = { id = "recruitment_return",
            label = "End Kevin's trial", enabled = near == true }
    end
    return options
end

function Kevin.action(group, action, player, payload)
    local value = state(group)
    if not value or value.id ~= "window_spiffo_kevin" then return false, "wrong_oddball" end
    -- A ranged hit or a nearby fellow's ritual is valid outside player talk range.
    local actor, reason
    if action == "hurt" or action == "quirk" then
        actor = actorFor(group)
        reason = actor and nil or "kevin_unavailable"
    else actor, reason = nearby(group, player) end
    if not actor then return false, reason end
    if action == "reveal" or action == "talk" or action == "quirk" then
        reveal(group, actor, action)
        if action == "quirk" then
            say(actor, "quirk", "Apology accepted, valued guest. Enjoy your meal.")
        end
        return true, "kevin_revealed"
    elseif action == "clock_out" then
        if value.clockedOut then return false, "already_clocked_out" end
        local inventory = U().inventory(player)
        local key = inventoryItem(inventory, { ["Base.KeyRing_Spiffos"] = true })
        if not key then return false, "manager_keys_required" end
        local source = select(1, U().call(key, "getContainer"))
        local moved, moveReason = U().transferItemVerified(source, U().inventory(actor), key)
        if not moved then return false, moveReason end
        reveal(group, actor, "clocked_out")
        value.clockedOut = true
        value.stage = "clocked_out"
        if SC.Factions then SC.Factions.adjustStanding(group.id, 75, "kevin_clocked_out") end
        say(actor, "clocked_out", "Oh my God. Air. Real air.")
        return true, "kevin_clocked_out"
    elseif action == "order_food" then
        local inventory = U().inventory(player)
        local meat = inventoryItem(inventory, { ["Base.MeatPatty"] = true })
        local bread = inventoryItem(inventory, {
            ["Base.Bread"] = true, ["Base.BreadSlices"] = true,
        })
        if not meat or not bread then return false, "burger_ingredients_required" end
        local meatSource = select(1, U().call(meat, "getContainer"))
        local breadSource = select(1, U().call(bread, "getContainer"))
        local destination = U().inventory(actor)
        local paid, payReason = U().transferItemVerified(meatSource, destination, meat)
        if not paid then return false, payReason end
        local second, secondReason = U().transferItemVerified(breadSource, destination, bread)
        if not second then
            U().transferItemVerified(destination, meatSource, meat)
            return false, secondReason
        end
        local burger, burgerReason = U().addItem(inventory, "Base.Burger")
        if not burger then
            U().transferItemVerified(destination, meatSource, meat)
            U().transferItemVerified(destination, breadSource, bread)
            return false, burgerReason
        end
        say(actor, "serve", "Welcome to Spiffo's! Have you tried the Spiffo Supreme?")
        return true, "burger_served"
    elseif action == "recruit" then
        if not Kevin.canRecruit(group) then return false, "kevin_not_ready_to_join" end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local status = group.recruitment and group.recruitment.status
        if status ~= "candidate" then
            local named, why = SC.FactionRecruitment.ask(group, player, false)
            if not named then return false, why end
        end
        return SC.FactionRecruitment.startTrial(group, player, false)
    elseif action == "recruitment_decide" then
        return SC.FactionRecruitment.decide(group, player)
    elseif action == "recruitment_return" then
        return SC.FactionRecruitment.returnNow(group, player, false)
    elseif action == "hurt" then
        if value.relocationUsed then
            local escape = escapeSquare(actor, player)
            if not escape then return false, "kevin_no_loaded_escape" end
            value.relocation = escape
            value.stage = "fleeing"
            syncImmunity(group, actor)
            say(actor, "hurt", "I'm on break! I'm on break!")
            return true, "kevin_fleeing"
        end
        local ax, ay, az = U().position(actor)
        local destination
        for dx = -30, 30, 3 do
            for dy = -30, 30, 3 do
                local square = U().gridSquare(ax + dx, ay + dy, az)
                local room = string.lower(U().roomName(square) or "")
                if square and string.find(room, "spiffo", 1, true)
                    and U().isSquareFree(square)
                    and not U().canSee(player, square)
                    and U().distance(actor, square) >= 12 then
                    local house = value.site and value.site.house and value.site.house.bounds
                    local sx, sy = U().position(square)
                    if not house or sx < house.x1 or sx > house.x2
                        or sy < house.y1 or sy > house.y2 then
                        destination = { x = sx, y = sy, z = az }
                        break
                    end
                end
            end
            if destination then break end
        end
        value.relocation = destination or escapeSquare(actor, player)
        if not value.relocation then return false, "kevin_no_loaded_escape" end
        value.relocationUsed = true
        value.stage = destination and "relocating" or "fleeing"
        reveal(group, actor, "hurt")
        value.stage = destination and "relocating" or "fleeing"
        syncImmunity(group, actor)
        say(actor, "hurt", "I'm on break! I'm on break!")
        return true, destination and "kevin_relocating" or "kevin_fleeing"
    end
    return false, "unknown_kevin_action"
end

function Kevin.intentFor(actor, player, snapshot, group)
    local value = state(group)
    if not value or value.id ~= "window_spiffo_kevin" then return nil end
    local mode = (value.stage == "relocating" or value.stage == "fleeing")
        and "spiffo_relocate"
        or posing(group) and "spiffo_pose" or "spiffo_hold"
    return { priority = mode == "spiffo_relocate" and 96 or 40,
        kind = "faction", mode = mode, factionId = group.id,
        zombieNearby = nearZombie(actor, snapshot) }
end

function Kevin.update(actor, player, runtimeState, intent, group)
    local value = state(group)
    local mode = intent and intent.mode
    local current = U().nowMs()
    local pose = poseByActor[actor]
    if not pose then pose = { nextAt = current + 4000 } poseByActor[actor] = pose end
    if mode == "spiffo_relocate" then
        releaseMannequin(actor)
        local square = value.relocation and U().loadedSquare(value.relocation)
        if not square then return false, "relocation_unloaded" end
        if U().distance(actor, square) <= 1 then
            value.stage = value.stage == "fleeing" and "fled" or "relocated"
            return true, value.stage == "fled" and "kevin_fled" or "kevin_relocated"
        end
        return SC.Navigation.request(actor, square, "jog", {
            action = "spiffo_relocate", targetSquare = square,
        })
    end
    if mode ~= "spiffo_pose" then
        releaseMannequin(actor)
        if not pose.stopped then
            if SC.Navigation then SC.Navigation.cancel(actor, "kevin_revealed") end
            pose.stopped = true
        end
        return true, "kevin_revealed"
    end
    pose.stopped = false
    local isWatched = watched(player, actor)
    if isWatched then
        if pose.target then
            if SC.Navigation then SC.Navigation.cancel(actor, "kevin_watched") end
            pose.target = nil
        end
        pose.unwatchedAt = nil
        pose.nextAt = current + (tonumber(U().config("oddballPoseStepCooldownMs")) or 4000)
        holdMannequin(actor, pose)
        if U().distance(player, actor) <= (tonumber(U().config("oddballPoseRevealDistance")) or 2) then
            pose.closeWatchedAt = pose.closeWatchedAt or current
            if current - pose.closeWatchedAt >= 5000 then
                reveal(group, actor, "watched_close")
                return true, "kevin_revealed"
            end
        else pose.closeWatchedAt = nil end
        return true, "kevin_posing_watched"
    end
    pose.closeWatchedAt = nil
    if intent.zombieNearby then
        if pose.target and SC.Navigation then SC.Navigation.cancel(actor, "zombie_near_pose") end
        pose.target = nil
        pose.nextAt = current + 4000
        holdMannequin(actor, pose)
        return true, "kevin_posing_for_zombie"
    end
    if pose.target then
        local square = U().loadedSquare(pose.target)
        if square and U().distance(actor, square) <= 0.8 then
            value.poseIndex = pose.targetIndex
            pose.target = nil
            pose.nextAt = current + (tonumber(U().config("oddballPoseStepCooldownMs")) or 4000)
            local px, py = U().position(player)
            if px then U().call(actor, "faceLocationF", px, py) end
            holdMannequin(actor, pose)
            return true, "kevin_new_pose"
        end
        if not square or watched(player, square) then
            if SC.Navigation then SC.Navigation.cancel(actor, "pose_destination_seen") end
            pose.target = nil
            pose.nextAt = current + 4000
            return true, "kevin_pose_step_cancelled"
        end
        releaseMannequin(actor)
        return SC.Navigation.request(actor, square, "walk", {
            action = "spiffo_pose_step", targetSquare = square,
            arrivalDistance = 0.7,
        })
    end
    if current < (pose.nextAt or current) then
        holdMannequin(actor, pose)
        return true, "kevin_posing"
    end
    local spots = poseSpots(group)
    if #spots < 2 then
        holdMannequin(actor, pose)
        return true, "pose_spots_unavailable"
    end
    for step = 1, #spots - 1 do
        local index = ((tonumber(value.poseIndex) or 1) + step - 1) % #spots + 1
        local target = spots[index]
        local square = U().loadedSquare(target)
        if square and U().isSquareFree(square) and not watched(player, square)
            and not U().edgeBlocked(U().squareOf(actor), square) then
            pose.target = target
            pose.targetIndex = index
            releaseMannequin(actor)
            return SC.Navigation.request(actor, square, "walk", {
                action = "spiffo_pose_step", targetSquare = square,
                arrivalDistance = 0.7,
            })
        end
    end
    pose.nextAt = current + 4000
    holdMannequin(actor, pose)
    return true, "kevin_no_unseen_pose"
end

-- The recruited actor's downtime scheduler may call this for a night window
-- activity. It deliberately does not move the actor: movement remains owned by
-- the scheduler and Navigation, so he only supplies flavor when already there.
function Kevin.windowDuty(actor, windowSquare)
    if not actor or not windowSquare or U().distance(actor, windowSquare) > 1.5 then
        return false, "window_duty_not_at_window"
    end
    say(actor, "window_duty", "Back on the floor. Somebody has to be the face of this place.")
    return true, "window_duty_spoken"
end

return Kevin
