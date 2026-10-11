-- SPDX-License-Identifier: MIT
-- Focused, disposable real-engine fixtures for Corey and Earl.  The runner
-- clones a save; this file is never shipped with Living Fellows.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCOddballCoreyEarlProbe = Probe

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end,
        ...)
    return ok and value or nil
end

local function position(U, object)
    local x, y, z = U.position(object)
    return tonumber(x), tonumber(y), math.floor(tonumber(z) or 0)
end

local function squareAt(U, x, y, z)
    return U.gridSquare(math.floor(x), math.floor(y), z or 0)
end

local function safe(U, square)
    return square ~= nil and U.isSafeSpawnSquare(square) == true
end

local function clearActor(U, square)
    return square ~= nil and U.isClearActorSpawnSquare(square) == true
end

local function outdoor(U, square)
    return safe(U, square) and call(square, "getRoom") == nil
end

local function actorFor(SC, group)
    local member = group and SC.Factions.member(group.id, "member-1")
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor or nil
end

-- The cloned source save may already contain the authored character under
-- test. Oddballs are unique by definition ID, so remove only that faction
-- from the disposable clone before creating the controlled scene. Keep every
-- other faction instead of resetting the whole save's household state.
local function clearExistingOddball(SC, definitionId)
    if type(definitionId) ~= "string" then
        return false, "invalid_fixture_definition"
    end
    local existing
    for _, group in ipairs(SC.Factions.list(false) or {}) do
        if type(group.oddball) == "table"
            and group.oddball.id == definitionId then
            existing = group
            break
        end
    end
    if not existing then return true, "no_existing_" .. definitionId end

    local factions, exportReason = SC.Factions.export()
    if type(factions) ~= "table" then
        return false, "faction_export_failed:" .. tostring(exportReason)
    end
    factions.groups[existing.id] = nil
    local order = {}
    for _, id in ipairs(factions.order or {}) do
        if id ~= existing.id then order[#order + 1] = id end
    end
    factions.order = order
    local restored, restoreReason = SC.Factions.restore(factions)
    if restored ~= true then
        return false, "faction_isolation_failed:" .. tostring(restoreReason)
    end

    local ledger, ledgerReason = SC.Oddballs.export()
    if type(ledger) ~= "table" then
        return false, "oddball_export_failed:" .. tostring(ledgerReason)
    end
    ledger.seeded[definitionId] = nil
    ledger.retired[definitionId] = nil
    if ledger.pending and ledger.pending.id == definitionId then
        ledger.pending = nil
    end
    local reset, resetReason = SC.Oddballs.restore(ledger)
    if reset ~= true then
        return false, "oddball_isolation_failed:" .. tostring(resetReason)
    end
    return true, "removed_existing_" .. definitionId
        .. ":" .. tostring(existing.id)
end
Probe.clearExistingOddball = clearExistingOddball

local function syntheticSite(id, spawn, kind, room, posts)
    local x, y, z = spawn.x, spawn.y, spawn.z
    return {
        kind = kind, room = room, spawn = spawn, anchor = spawn,
        fuelPosts = posts,
        house = {
            id = "live-oddball-" .. id .. "-" .. tostring(x) .. ":" .. tostring(y),
            anchor = spawn,
            bounds = { x1 = x - 8, x2 = x + 8,
                y1 = y - 8, y2 = y + 8, z = z },
            interior = { spawn }, openings = {},
            roomGroup = room or "outdoor_fixture",
        },
    }
end

local function findStraightOutdoor(U, player)
    local px, py, pz = position(U, player)
    if not px then return nil end
    px, py = math.floor(px), math.floor(py)
    for radius = 3, 36 do
        for _, corner in ipairs({ { radius, 0 }, { -radius, 0 },
            { 0, radius }, { 0, -radius } }) do
            local x, y = px + corner[1], py + corner[2]
            local observer = squareAt(U, x, y, pz)
            if outdoor(U, observer) then
                for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
                    { 0, 1 }, { 0, -1 } }) do
                    local clear = true
                    for step = 1, 20 do
                        local square = squareAt(U, x + direction[1] * step,
                            y + direction[2] * step, pz)
                        if not outdoor(U, square) then
                            clear = false
                            break
                        end
                    end
                    if clear then
                        return observer, squareAt(U, x + direction[1] * 20,
                            y + direction[2] * 20, pz)
                    end
                end
            end
        end
    end
    return nil
end

local function findEarlRoom(U, player)
    local px, py, pz = position(U, player)
    if not px then return nil end
    px, py = math.floor(px), math.floor(py)
    local rooms, order = {}, {}
    for radius = 0, 40 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = squareAt(U, px + dx, py + dy, pz)
                    local room = square and call(square, "getRoom")
                    if room and clearActor(U, square) then
                        if not rooms[room] then
                            rooms[room] = {}
                            order[#order + 1] = room
                        end
                        rooms[room][#rooms[room] + 1] = square
                    end
                end
            end
        end
        if radius >= 8 then
            for _, room in ipairs(order) do
                local squares = rooms[room]
                for _, origin in ipairs(squares) do
                    local posts = {}
                    for _, candidate in ipairs(squares) do
                        local dx = candidate:getX() - origin:getX()
                        local dy = candidate:getY() - origin:getY()
                        if dx * dx + dy * dy >= 4 then
                            local separated = true
                            for _, selected in ipairs(posts) do
                                local sx = candidate:getX() - selected:getX()
                                local sy = candidate:getY() - selected:getY()
                                if sx * sx + sy * sy < 4 then
                                    separated = false
                                    break
                                end
                            end
                            if separated then posts[#posts + 1] = candidate end
                        end
                        if #posts >= 4 then break end
                    end
                    if #posts >= 2 then return origin, room, posts end
                end
            end
        end
    end
    return nil
end
Probe.findEarlRoom = findEarlRoom

local function attackPreempted(story, warningIgniteAt)
    local litAt = story and tonumber(story.ignitedAt)
    local delayedUntil = tonumber(warningIgniteAt)
    return story and story.stage == "burning"
        and story.attackTriggered == true
        and litAt ~= nil and delayedUntil ~= nil
        and litAt < delayedUntil or false
end
Probe.attackPreempted = attackPreempted

local function itemAtPost(U, post, groupId, index)
    local square = squareAt(U, post.x, post.y, post.z)
    local objects = square and call(square, "getWorldObjects")
    local count = tonumber(call(objects, "size")) or 0
    for slot = 0, count - 1 do
        local world = call(objects, "get", slot)
        local item = call(world, "getItem")
        local data = item and U.modData(item)
        if item and U.itemType(item) == "Base.PetrolCan"
            and type(data) == "table"
            and data.lfPyroFuelGroupId == groupId
            and data.lfPyroFuelIndex == index then
            return world, item
        end
    end
    return nil
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "oddball_corey_setup" then
        local isolated, isolationReason = clearExistingOddball(SC,
            "fan_corey_biggs")
        if not check("corey_clone_scene_isolated", isolated,
            tostring(isolationReason)) then
            setPhase("finish", current)
            return
        end
        local observer, spawn = findStraightOutdoor(U, H.player)
        if not check("corey_open_approach_site", observer ~= nil,
            "requires a loaded 20-tile outdoor path") then
            setPhase("finish", current)
            return
        end
        local moved = pcall(function()
            H.player:teleportTo(observer:getX() + 0.5,
                observer:getY() + 0.5, observer:getZ())
        end)
        local point = { x = spawn:getX(), y = spawn:getY(),
            z = spawn:getZ() }
        local definition = SC.Oddballs.definition("fan_corey_biggs")
        local group, reason
        if moved then
            group, reason = SC.Factions.createOddballGroup(
                syntheticSite("corey", point, "witness", nil),
                definition, true)
        else
            reason = "observer_teleport_failed"
        end
        if not check("corey_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current)
            return
        end
        H.oddballGroup = group
        setPhase("oddball_corey_spawn", current)
        return
    elseif H.phase == "oddball_corey_spawn" then
        local actor = actorFor(SC, H.oddballGroup)
        if not actor then
            if current - H.phaseStartedAt > 18000 then
                check("corey_native_actor", false, "spawn timed out")
                setPhase("finish", current)
            end
            return
        end
        local distance = U.distance(actor, H.player)
        local story = H.oddballGroup.oddball
        local initialGreeting = story.greeted == true
        SC.OddballCorey.pulse(H.oddballGroup, H.player, current)
        if not check("corey_no_distant_greeting",
            distance >= 12 and not initialGreeting and story.greeted ~= true,
            "distance=" .. tostring(distance)
                .. " greeted=" .. tostring(story.greeted)) then
            setPhase("finish", current)
            return
        end
        H.corey = { actor = actor, startDistance = distance,
            bestDistance = distance, lastX = select(1, position(U, actor)),
            lastY = select(2, position(U, actor)), lastSampleAt = current,
            maxStep = 0, movingSamples = 0, navigationSamples = 0,
            recoverySamples = 0 }
        setPhase("oddball_corey_follow", current)
        return
    elseif H.phase == "oddball_corey_follow" then
        local state = H.corey
        local actor = state.actor
        local x, y = position(U, actor)
        local distance = U.distance(actor, H.player)
        if x and current - state.lastSampleAt >= 250 then
            local step = math.sqrt((x - state.lastX) ^ 2
                + (y - state.lastY) ^ 2)
            state.maxStep = math.max(state.maxStep, step)
            if step > 0.05 then state.movingSamples = state.movingSamples + 1 end
            state.lastX, state.lastY, state.lastSampleAt = x, y, current
        end
        state.bestDistance = math.min(state.bestDistance, distance)
        local navigation = SC.Navigation and SC.Navigation.status(actor) or nil
        navigation = type(navigation) == "table" and navigation or {}
        if navigation.action == "faction_follow" then
            state.navigationSamples = state.navigationSamples + 1
        end
        if navigation.phase == "recovering" or navigation.phase == "failed" then
            state.recoverySamples = state.recoverySamples + 1
        end
        if distance <= 6 and U.canSee(actor, H.player) == true then
            SC.OddballCorey.pulse(H.oddballGroup, H.player, current)
        end
        if H.oddballGroup.oddball.greeted == true
            or current - H.phaseStartedAt >= 42000 then
            check("corey_reaches_player", state.bestDistance <= 6.5,
                "start=" .. tostring(state.startDistance)
                    .. " closest=" .. tostring(state.bestDistance))
            check("corey_normal_navigation",
                state.navigationSamples >= 2 and state.recoverySamples == 0,
                "follow_samples=" .. tostring(state.navigationSamples)
                    .. " recovery_samples=" .. tostring(state.recoverySamples))
            check("corey_smooth_motion",
                state.movingSamples >= 5 and state.maxStep < 4,
                "moving_samples=" .. tostring(state.movingSamples)
                    .. " largest_250ms_step=" .. tostring(state.maxStep))
            check("corey_close_greeting",
                H.oddballGroup.oddball.greeted == true,
                "greeted=" .. tostring(H.oddballGroup.oddball.greeted)
                    .. " distance=" .. tostring(distance))
            setPhase("finish", current)
        end
        return
    elseif H.phase == "oddball_earl_setup" then
        local isolated, isolationReason = clearExistingOddball(SC,
            "pyromaniac_earl_kessler")
        if not check("earl_clone_scene_isolated", isolated,
            tostring(isolationReason)) then
            setPhase("finish", current)
            return
        end
        local origin, room, squares = findEarlRoom(U, H.player)
        if not check("earl_loaded_room_site", origin ~= nil,
            "requires a loaded room with spaced floor squares") then
            setPhase("finish", current)
            return
        end
        local point = { x = origin:getX(), y = origin:getY(),
            z = origin:getZ() }
        local posts = {}
        for _, square in ipairs(squares) do
            posts[#posts + 1] = { x = square:getX(), y = square:getY(),
                z = square:getZ() }
        end
        -- Keep the native spawn tile vacant.  The observer stands at the
        -- first fuel post, close enough for Earl's pickup reaction.
        local moved = pcall(function()
            H.player:teleportTo(squares[1]:getX() + 0.5,
                squares[1]:getY() + 0.5, squares[1]:getZ())
        end)
        local definition = SC.Oddballs.definition("pyromaniac_earl_kessler")
        local group, reason
        if moved then
            group, reason = SC.Factions.createOddballGroup(
                syntheticSite("earl", point, "resident",
                    tostring(call(room, "getName") or "livingroom"), posts),
                definition, true)
        else
            reason = "observer_teleport_failed"
        end
        if not check("earl_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current)
            return
        end
        H.oddballGroup = group
        H.earlPosts = posts
        setPhase("oddball_earl_spawn", current)
        return
    elseif H.phase == "oddball_earl_spawn" then
        local actor = actorFor(SC, H.oddballGroup)
        local spawned = H.oddballGroup.oddball.fuelSpawned
        if not actor or type(spawned) ~= "table" or #spawned < 2 then
            if current - H.phaseStartedAt > 18000 then
                check("earl_native_fuel_spawn", false,
                    "actor=" .. tostring(actor)
                        .. " spawned=" .. tostring(spawned and #spawned))
                setPhase("finish", current)
            end
            return
        end
        local found, spaced = 0, true
        for index, post in ipairs(H.earlPosts) do
            local world = itemAtPost(U, post, H.oddballGroup.id, index)
            if world then found = found + 1 end
            for other = index + 1, #H.earlPosts do
                local dx = post.x - H.earlPosts[other].x
                local dy = post.y - H.earlPosts[other].y
                if dx * dx + dy * dy < 4 then spaced = false end
            end
        end
        if not check("earl_real_fuel_cans_tagged_and_spaced",
            found == #H.earlPosts and spaced,
            "tagged_world_cans=" .. tostring(found)
                .. "/" .. tostring(#H.earlPosts)
                .. " spaced=" .. tostring(spaced)) then
            setPhase("finish", current)
            return
        end
        local world, item = itemAtPost(U, H.earlPosts[1],
            H.oddballGroup.id, 1)
        local taken, reason = U.takeWorldItemVerified(world,
            U.inventory(H.player), item)
        if not check("earl_exact_world_can_picked_up", taken == true,
            tostring(reason)) then
            setPhase("finish", current)
            return
        end
        local stillWorld = itemAtPost(U, H.earlPosts[1],
            H.oddballGroup.id, 1)
        check("earl_can_leaves_world_for_player",
            stillWorld == nil and U.inventoryContains(U.inventory(H.player),
                item) == true,
            "world=" .. tostring(stillWorld)
                .. " inventory=" .. tostring(U.inventoryContains(
                    U.inventory(H.player), item)))
        SC.OddballPyromaniac.pulse(H.oddballGroup, H.player, current)
        local story = H.oddballGroup.oddball
        if not check("earl_detects_taken_can", story.stage == "warning",
            "stage=" .. tostring(story.stage)) then
            setPhase("finish", current)
            return
        end
        -- A real native player hit must light the room immediately, before
        -- the can-theft warning's delayed ignition. The source save is cloned
        -- for this probe, so the fire and the temporary weapon stay in it.
        local warningIgniteAt = tonumber(story.igniteAt) or 0
        if not check("earl_theft_warning_has_ignition_delay",
            warningIgniteAt > current,
            "igniteAt=" .. tostring(story.igniteAt)
                .. " now=" .. tostring(current)) then
            setPhase("finish", current)
            return
        end
        local inventory = U.inventory(H.player)
        local weapon = inventory and call(inventory, "AddItem", "Base.Crowbar")
        local originalSay, attackLine = U.say, nil
        U.say = function(speaker, line, ...)
            if speaker == actor then attackLine = line end
            return originalSay(speaker, line, ...)
        end
        local hitOk, hitResult = pcall(function()
            return actor:Hit(weapon, H.player, 0.2, false, 1.0, false)
        end)
        U.say = originalSay
        if not check("earl_native_player_attack_event",
            weapon ~= nil and hitOk and type(hitResult) == "number"
                and hitResult > 0,
            "weapon=" .. tostring(weapon)
                .. " Hit=" .. tostring(hitResult)
                .. " call=" .. tostring(hitOk)) then
            setPhase("finish", current)
            return
        end
        check("earl_attack_shouts_at_player",
            story.attackTriggered == true and type(attackLine) == "string"
                and (attackLine:find("fire", 1, true) ~= nil
                    or attackLine:find("spark", 1, true) ~= nil
                    or attackLine:find("burn", 1, true) ~= nil
                    or attackLine:find("gasoline", 1, true) ~= nil),
            "shouted=" .. tostring(attackLine)
                .. " triggered=" .. tostring(story.attackTriggered))
        if not check("earl_attack_preempts_theft_delay",
            attackPreempted(story, warningIgniteAt),
            "stage=" .. tostring(story.stage)
                .. " ignitedAt=" .. tostring(story.ignitedAt)
                .. " originalDelayedUntil=" .. tostring(warningIgniteAt)
                .. " currentIgniteAt=" .. tostring(story.igniteAt)) then
            setPhase("finish", current)
            return
        end
        setPhase("oddball_earl_fire", current)
        return
    elseif H.phase == "oddball_earl_fire" then
        local burning = 0
        for _, post in ipairs(H.earlPosts or {}) do
            local square = squareAt(U, post.x, post.y, post.z)
            if square and call(square, "haveFire") == true then
                burning = burning + 1
            end
        end
        if burning > 0 or current - H.phaseStartedAt >= 3000 then
            check("earl_native_fire_after_player_attack", burning > 0,
                "burning fuel squares=" .. tostring(burning))
            setPhase("finish", current)
        end
    end
end

return Probe
