-- SPDX-License-Identifier: MIT
-- Disposable saved-world test. Companions use normal AI, routes and furniture.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCGuardFollowProbe = Probe

local function SC() return SurvivorCompanion end
local function call(object, method, ...)
    local value = SC().GameplayUtil.call(object, method, ...)
    return value
end
local function position(object) return SC().GameplayUtil.position(object) end
local function at(object)
    local x, y, z = position(object)
    return x and string.format("%.3f,%.3f,%.2f", x, y, z or 0) or "none"
end
local function distance(a, b) return SC().GameplayUtil.distance(a, b) end
local function picture(H, suffix)
    pcall(function() getCore():TakeFullScreenshot(H.config.run_id .. "-guard-follow-" .. suffix) end)
end
local function clear(square, actor)
    local U = SC().GameplayUtil
    return square and U.isSquareFree(square) and U.squareOccupyingObject(square) == nil
        and U.movingBlocker(square, actor) == nil
end
local function seated(actor)
    return call(actor, "isSittingOnFurniture") == true
        and call(actor, "getSitOnFurnitureObject") ~= nil
end
local function standing(actor)
    return SC().NativeActions.seatingStatus(actor) == "standing"
        and call(actor, "isSittingOnFurniture") ~= true
        and call(actor, "isOnBed") ~= true and call(actor, "isSitOnGround") ~= true
end
local function snapshotGear(f)
    f.gear = {}
    for _, record in ipairs(SC().Registry.snapshot() or {}) do
        if record.actor then
            SC().PersonalItems.walkActorInventory(record.actor, function(item)
                local personal = SC().PersonalItems.personalRecord(item)
                if personal or call(item, "isFavorite") == true
                    or call(record.actor, "isEquipped", item) == true then
                    f.gear[#f.gear + 1] = { item = item, actor = record.actor, id = record.id }
                end
            end, { budget = 1024 })
        end
    end
end
local function verifyGear(f)
    local owned = {}
    for _, row in ipairs(f.gear or {}) do
        if not owned[row.actor] then
            local items = {}
            SC().PersonalItems.walkActorInventory(row.actor, function(item) items[item] = true end,
                { budget = 2048 })
            owned[row.actor] = items
        end
        if owned[row.actor][row.item] ~= true then return false, row.id .. ":" .. tostring(row.item) end
    end
    return true, "protected/equipped exact identities=" .. #(f.gear or {})
end
local function restore(H, f)
    if not f then return end
    if f.commands then SC().Commands.restore(f.actor, f.commands) end
    if f.resident then SC().BaseLife.restoreResident(f.id, f.resident) end
    if f.playerPosition then
        local p = f.playerPosition
        pcall(function()
            H.player:teleportTo(p.x, p.y, p.z)
            H.player:setX(p.x); H.player:setY(p.y)
            H.player:setNextX(p.x); H.player:setNextY(p.y)
            H.player:setLastX(p.x); H.player:setLastY(p.y)
            H.player:setCurrentSquareFromPosition()
        end)
    end
end
local function finish(H, current, check, setPhase, reason)
    local f = H.guardFollow
    if f then
        local okay, detail = verifyGear(f)
        check("guard_follow_foreign_gear_unchanged", okay, detail)
        picture(H, reason or "complete")
        restore(H, f)
    end
    setPhase("finish", current)
end
local function trace(H, f, current)
    if current < (f.nextTrace or 0) then return end
    f.nextTrace = current + 3000
    local nav = SC().Navigation.peek(f.actor) or {}
    local view = SC().Navigation.status(f.actor) or {}
    local activity = SC().Downtime.peek(f.actor) or {}
    local token = SC().ActionSupervisor.snapshot(f.actor) or {}
    local decision = SC().Decision.peek(f.actor) or {}
    local command = SC().Commands.peek(f.actor)
    local resident = SC().BaseLife.resident(f.id) or {}
    print("SC_REAL_SANDBOX|GUARD_FOLLOW_TRACE|phase=" .. H.phase .. " actor=" .. f.id
        .. " pos=" .. at(f.actor) .. " player=" .. at(H.player)
        .. " order=" .. tostring(command.order) .. " duty=" .. tostring(resident.duty)
        .. " role=" .. tostring(resident.role) .. " nav=" .. tostring(nav.goalAction)
        .. " search=" .. tostring(view.pathSearchAgeMs) .. "/" .. tostring(view.expandedNodes)
        .. " downtime=" .. tostring(activity.active and activity.active.kind)
        .. " token=" .. tostring(token.serial) .. "/" .. tostring(token.owner) .. "/" .. tostring(token.action)
        .. " decision=" .. tostring(decision.current)
        .. " intent=" .. tostring(decision.intent) .. " seated=" .. tostring(seated(f.actor))
        .. " posture=" .. tostring(SC().NativeActions.seatingStatus(f.actor))
        .. " context=" .. tostring(call(f.actor, "getActionStateName")))
end
local function choose(H, current, check, setPhase)
    if current - H.phaseStartedAt < 6000 then return end
    local base = SC().BaseLife.active()
    if not base then
        if current - H.phaseStartedAt < 15000 then return end
        check("guard_follow_existing_base", false, "save has no restored camp")
        return setPhase("finish", current)
    end
    local selected, score
    for _, record in ipairs(SC().Registry.snapshot() or {}) do
        local actor = record.actor
        if record.recruited == true and actor and call(actor, "isDead") ~= true
            and call(actor, "getCurrentSquare") and call(actor, "getVehicle") == nil
            and SC().BaseLife.isInside(actor) == true
            and not (SC().BaseWatch and SC().BaseWatch.isLeader(actor)) then
            local resident = SC().BaseLife.resident(record.id) or {}
            local load = SC().Logistics.status(actor) or {}
            local value = (resident.role == "guard" and 100 or 0)
                - (load.overloaded and 1000 or 0) - (load.surplus and 200 or 0)
            if score == nil or value > score then selected, score = record, value end
        end
    end
    if not check("guard_follow_existing_companion", selected ~= nil,
        selected and selected.id or "no loaded recruited camp resident") then return setPhase("finish", current) end
    local px, py, pz = position(H.player)
    local f = { actor = selected.actor, id = selected.id, runtime = selected.runtime,
        startedAt = current, commands = SC().Commands.export(selected.actor),
        resident = SC().BaseLife.snapshotResident(selected.id),
        playerPosition = { x = px, y = py, z = pz }, squares = {}, chairs = {}, seen = {},
        zones = {}, zoneIndex = 1 }
    H.guardFollow = f
    snapshotGear(f)
    local _, _, floor = position(f.actor)
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and zone.z == math.floor(floor or 0) then f.zones[#f.zones + 1] = zone end
    end
    if not check("guard_follow_reversible_saved_state", f.commands ~= nil and f.resident ~= nil
        and #f.zones > 0, "areas=" .. #f.zones) then return finish(H, current, check, setPhase, "fixture-failed") end
    local available, manager = pcall(function() return SeatingManager.getInstance() end)
    if not check("guard_follow_native_seating_catalog", available and manager ~= nil,
        tostring(manager)) then return finish(H, current, check, setPhase, "fixture-failed") end
    f.manager = manager
    setPhase("guard_follow_survey", current)
end
local function survey(H, f, current, check, setPhase)
    local U = SC().GameplayUtil
    for _ = 1, 80 do
        local zone = f.zones[f.zoneIndex]
        if not zone then break end
        f.x, f.y = f.x or zone.x1, f.y or zone.y1
        local key = f.x .. ":" .. f.y .. ":" .. zone.z
        if not f.seen[key] then
            f.seen[key] = true
            local square = U.gridSquare(f.x, f.y, zone.z)
            if clear(square, f.actor) then f.squares[#f.squares + 1] = square end
            U.squareObjects(square, function(object)
                local count = tonumber(call(f.manager, "getTilePositionCount", object)) or 0
                local sprite = call(object, "getSprite")
                local label = string.lower(tostring(call(sprite, "getName"))
                    .. " " .. tostring(call(object, "getName")))
                if count > 0 and not string.find(label, "bed", 1, true)
                    and call(object, "isFurnitureOccupied", f.actor) ~= true then
                    f.chairs[#f.chairs + 1] = object
                end
            end, 64)
        end
        f.x = f.x + 1
        if f.x > zone.x2 then f.x, f.y = zone.x1, f.y + 1 end
        if f.y > zone.y2 then f.zoneIndex, f.x, f.y = f.zoneIndex + 1, nil, nil end
    end
    if f.zones[f.zoneIndex] then return end
    local best
    for _, chair in ipairs(f.chairs) do
        local d = distance(f.actor, chair)
        if best == nil or d < best then f.chair, best = chair, d end
    end
    local postScore
    local sourceRoom = call(call(f.actor, "getCurrentSquare"), "getRoom")
    for _, square in ipairs(f.squares) do
        local d = distance(f.actor, square)
        -- Prefer another real room so guard travel owns an actual pending
        -- frontier instead of completing as an open-floor direct step.
        local score = d + (call(square, "getRoom") ~= sourceRoom and 200 or 0)
        if f.chair and distance(square, f.chair) <= 12 and d >= 6 and d <= 14
            and (postScore == nil or score > postScore) then f.post, postScore = square, score end
        if f.chair and distance(square, f.chair) <= 2
            and (not f.chairPost or distance(square, f.chair) < distance(f.chairPost, f.chair)) then
            f.chairPost = square
        end
    end
    if not check("guard_follow_real_map_fixture", f.post ~= nil and f.chairPost ~= nil,
        "chairs=" .. #f.chairs .. " post=" .. at(f.post) .. " chair=" .. at(f.chair)) then
        return finish(H, current, check, setPhase, "fixture-failed")
    end
    SC().Decision.cancelWork(f.actor, "guard_follow_fixture_setup")
    local accepted, reason = SC().Commands.issue(f.id, "guard", { square = f.post }, H.player)
    if not check("guard_follow_guard_command", accepted == true, tostring(reason)) then
        return finish(H, current, check, setPhase, "guard-failed")
    end
    setPhase("guard_follow_planning", current)
end
local function beginFollow(H, f, current, check, setPhase, label)
    local target, best
    for _, square in ipairs(f.squares) do
        local d = distance(f.actor, square)
        if d >= 9 and d <= 15 and clear(square, f.actor)
            and (best == nil or d > best) then target, best = square, d end
    end
    if not check("guard_follow_" .. label .. "_observer_destination", target ~= nil,
        target and at(target) or "no loaded clear stand 9–15 tiles away") then
        return finish(H, current, check, setPhase, "observer-fixture-failed")
    end
    local x, y, z = position(target)
    -- Only the observer is relocated; every companion retains its native pose.
    H.player:teleportTo(x, y, z)
    H.player:setX(x + 0.5); H.player:setY(y + 0.5)
    H.player:setNextX(x + 0.5); H.player:setNextY(y + 0.5)
    H.player:setLastX(x + 0.5); H.player:setLastY(y + 0.5)
    H.player:setCurrentSquareFromPosition()
    local nav = SC().Navigation.peek(f.actor) or {}
    local activity = SC().Downtime.peek(f.actor) or {}
    local token = SC().ActionSupervisor.snapshot(f.actor) or {}
    local ax, ay, az = position(f.actor)
    f.follow = { label = label, startedAt = current, start = { x = ax, y = ay, z = az },
        distance = distance(f.actor, H.player), search = nav.pathSearch, lease = nav.nativeLease,
        activity = activity.active, token = token.serial }
    picture(H, label .. "-before")
    local accepted, reason = SC().Commands.issue(f.id, "follow", nil, H.player)
    local resident = SC().BaseLife.resident(f.id) or {}
    if not check("guard_follow_" .. label .. "_command", accepted == true
        and SC().Commands.peek(f.actor).order == "follow" and resident.duty == false,
        "accepted=" .. tostring(accepted) .. " reason=" .. tostring(reason)
            .. " duty=" .. tostring(resident.duty)) then
        return finish(H, current, check, setPhase, label .. "-failed")
    end
    setPhase("guard_follow_movement", current)
end
local function movement(H, f, current, check, setPhase)
    local follow = f.follow
    local nav = SC().Navigation.peek(f.actor) or {}
    local downtime = SC().Downtime.peek(f.actor) or {}
    local token = SC().ActionSupervisor.snapshot(f.actor) or {}
    local resident = SC().BaseLife.resident(f.id) or {}
    local ax, ay = position(f.actor)
    local moved = math.sqrt((ax - follow.start.x)^2 + (ay - follow.start.y)^2)
    local oldCleared = (follow.search == nil or nav.pathSearch ~= follow.search)
        and (follow.lease == nil or nav.nativeLease ~= follow.lease)
        and (follow.activity == nil or downtime.active ~= follow.activity)
        and (follow.token == nil or token.serial ~= follow.token)
        and nav.goalAction ~= "base_guard_patrol" and nav.goalAction ~= "move_to_seat"
    follow.stood = follow.stood or standing(f.actor)
    if oldCleared and follow.stood and moved >= 1.5
        and follow.distance - distance(f.actor, H.player) >= 1
        and resident.duty == false and SC().Commands.peek(f.actor).order == "follow" then
        check("guard_follow_" .. follow.label .. "_native_handoff", true,
            "moved=" .. moved .. " distance=" .. follow.distance .. "->" .. distance(f.actor, H.player)
                .. " stood=true oldRouteAndTokenCleared=true")
        picture(H, follow.label .. "-after")
        if follow.label == "seated" then return finish(H, current, check, setPhase, "complete") end
        local accepted, reason = SC().Commands.issue(f.id, "guard", { square = f.chairPost }, H.player)
        if not check("guard_follow_break_guard_command", accepted == true, tostring(reason)) then
            return finish(H, current, check, setPhase, "break-fixture-failed")
        end
        f.nextSitAt = current
        setPhase("guard_follow_break", current)
    elseif current - follow.startedAt > 60000 then
        check("guard_follow_" .. follow.label .. "_native_handoff", false,
            "moved=" .. moved .. " posture=" .. SC().NativeActions.seatingStatus(f.actor)
                .. " cleared=" .. tostring(oldCleared) .. " distance=" .. distance(f.actor, H.player))
        finish(H, current, check, setPhase, follow.label .. "-timeout")
    end
end
function Probe.step(H, current, check, result, setPhase)
    if H.phase == "guard_follow_setup" then return choose(H, current, check, setPhase) end
    local f = H.guardFollow
    if not f then return end
    trace(H, f, current)
    if current - f.startedAt > 300000 then
        check("guard_follow_bounded_completion", false, H.phase)
        return finish(H, current, check, setPhase, "timeout")
    end
    if H.phase == "guard_follow_survey" then return survey(H, f, current, check, setPhase) end
    if H.phase == "guard_follow_planning" then
        local nav = SC().Navigation.peek(f.actor) or {}
        if nav.pathSearch ~= nil and nav.goalAction == "base_guard_patrol" then
            check("guard_follow_real_guard_planning", true,
                "origin=" .. at(f.actor) .. " anchor=" .. tostring(nav.pathSearch.anchorKey))
            return beginFollow(H, f, current, check, setPhase, "planning")
        end
        if current - H.phaseStartedAt > 60000 then
            check("guard_follow_real_guard_planning", false, "no actual pending guard frontier observed")
            return finish(H, current, check, setPhase, "guard-planning-fixture-failed")
        end
    elseif H.phase == "guard_follow_break" then
        local active = (SC().Downtime.peek(f.actor) or {}).active
        local resident = SC().BaseLife.resident(f.id) or {}
        local token = SC().ActionSupervisor.snapshot(f.actor) or {}
        local entered = active and ((active.kind == "sit" and active.furnitureEntered == true
            and token.phase == "waiting") or (active.kind == "read" and active.startedAt ~= nil))
        if seated(f.actor) and active and (active.kind == "sit" or active.kind == "read")
            and entered and resident.role == "guard" and resident.duty == true
            and SC().Commands.peek(f.actor).order == "base_duty" then
            local object = call(f.actor, "getSitOnFurnitureObject")
            if not check("guard_follow_real_guard_seated_break",
                (tonumber(call(object, "getObjectIndex")) or -1) >= 0,
                "kind=" .. active.kind .. " furniture=" .. at(object)
                    .. " native=" .. tostring(call(object, "getObjectIndex"))) then
                return finish(H, current, check, setPhase, "seat-fixture-failed")
            end
            return beginFollow(H, f, current, check, setPhase, "seated")
        end
        if current >= (f.nextSitAt or 0) and distance(f.actor, f.chair) <= 6 then
            f.nextSitAt = current + 500
            -- Public desired-kind staging chooses real furniture and performs its
            -- normal route/entry. Ordinary Decision remains scheduled throughout.
            local okay, reason = SC().Downtime.update(f.actor, H.player, f.runtime, "sit")
            f.lastSitReason = tostring(okay) .. ":" .. tostring(reason)
        end
        if current - H.phaseStartedAt > 150000 then
            check("guard_follow_real_guard_seated_break", false,
                "existing furniture could not be entered faithfully: " .. tostring(f.lastSitReason))
            finish(H, current, check, setPhase, "seat-fixture-failed")
        end
    elseif H.phase == "guard_follow_movement" then movement(H, f, current, check, setPhase) end
end
return Probe
