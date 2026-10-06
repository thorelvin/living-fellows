-- SPDX-License-Identifier: MIT
-- Disposable-save probe: a real base sort job must deliver to a marked z=1
-- container through the house stairs. The source save is never modified.

local Probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end

local function pos(object)
    return tonumber(call(object, "getX")), tonumber(call(object, "getY")),
        tonumber(call(object, "getZ"))
end

local function label(object)
    local x, y, z = pos(object)
    local sprite = call(call(object, "getSprite"), "getName")
    return tostring(sprite or "object") .. "@" .. tostring(x) .. ","
        .. tostring(y) .. "," .. tostring(z)
end

local function objectsInZone(zone, callback)
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            local square = getCell():getGridSquare(x, y, zone.z)
            local objects = call(square, "getObjects")
            if objects then
                for index = 0, objects:size() - 1 do
                    callback(objects:get(index), square)
                end
            end
        end
    end
end

local function findFixtures(base, SC, actor)
    local televisions, ground, upper = {}, {}, {}
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" and (zone.z == 0 or zone.z == 1) then
            objectsInZone(zone, function(object, square)
                local data = SC.GameplayUtil.instanceOf(object,
                    "IsoWaveSignal") and call(object, "getDeviceData") or nil
                if zone.z == 1 and call(data, "getIsTelevision") == true then
                    televisions[#televisions + 1] = { object = object,
                        square = square, data = data }
                end
                if call(object, "getObjectIndex") ~= nil
                    and (tonumber(call(object, "getObjectIndex")) or -1) >= 0
                    and call(object, "getContainer") ~= nil then
                    local container = call(object, "getContainer")
                    local items = call(container, "getItems")
                    local row = { object = object, square = square,
                        container = container,
                        itemCount = tonumber(call(items, "size")) or 9999 }
                    row.hasPlank = false
                    if items then
                        for itemIndex = 0, items:size() - 1 do
                            if SC.GameplayUtil.itemType(items:get(itemIndex))
                                == "Base.Plank" then row.hasPlank = true break end
                        end
                    end
                    if zone.z == 0 then ground[#ground + 1] = row
                    else upper[#upper + 1] = row end
                end
            end)
        end
    end
    table.sort(ground, function(a, b)
        if a.itemCount ~= b.itemCount then return a.itemCount < b.itemCount end
        local ax, ay = pos(actor)
        local x1, y1 = pos(a.square)
        local x2, y2 = pos(b.square)
        return (x1 - ax)^2 + (y1 - ay)^2 < (x2 - ax)^2 + (y2 - ay)^2
    end)
    table.sort(upper, function(a, b)
        if a.hasPlank ~= b.hasPlank then return a.hasPlank == false end
        if a.itemCount ~= b.itemCount then return a.itemCount < b.itemCount end
        local function score(row)
            local best = 100000
            for _, tv in ipairs(televisions) do
                local x, y = pos(row.square)
                local tx, ty = pos(tv.square)
                local sameRoom = call(row.square, "getRoom") ~= nil
                    and call(row.square, "getRoom") == call(tv.square, "getRoom")
                best = math.min(best, (x - tx)^2 + (y - ty)^2
                    + (sameRoom and 0 or 10000))
            end
            return best
        end
        return score(a) < score(b)
    end)
    return televisions, ground, upper
end

local function chooseActor(SC)
    local best, bestScore
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        local actor = record.actor
        local x, y, z = pos(actor)
        if record.recruited == true and actor and x and z == 0
            and SC.BaseLife.isInside(actor) == true
            and call(actor, "isDead") ~= true then
            local resident = SC.BaseLife.resident(record.id)
            local job = SC.BaseLife.jobFor(record.id)
            local score = (job and 0 or 100)
                + (resident and resident.duty and 20 or 0)
                + (resident and resident.role == "corpsekeeper" and -50 or 0)
            if not best or score > bestScore then
                best, bestScore = { actor = actor, id = record.id,
                    name = call(actor, "getFullName") or record.id,
                    x = x, y = y, z = z, oldJob = job }, score
            end
        end
    end
    return best
end

local function markStorage(SC, candidates, category)
    local lastReason
    for _, row in ipairs(candidates) do
        local okay, marker = SC.BaseLife.registerStorage(row.object, category)
        if okay == true then
            row.marker = marker
            return row
        end
        lastReason = marker
    end
    return nil, lastReason
end

local function listStorages(base)
    local rows = {}
    for _, storage in ipairs(base.storages or {}) do
        rows[#rows + 1] = tostring(storage.id) .. ":" .. tostring(storage.category)
            .. "@" .. tostring(storage.x) .. "," .. tostring(storage.y)
            .. "," .. tostring(storage.z)
    end
    return table.concat(rows, "; ")
end

local function cargoLocation(fixture, SC)
    local item = fixture.item
    local root = call(fixture.actor, "getInventory")
    local parent = call(item, "getContainer")
    local nested, complete = false, false
    if SC.PersonalItems and type(SC.PersonalItems.walkActorInventory) == "function" then
        local _, scanned = SC.PersonalItems.walkActorInventory(fixture.actor,
            function(value)
                if value == item then nested = true end
            end, { budget = 4096 })
        complete = scanned == true
    end
    return "root=" .. tostring(SC.GameplayUtil.inventoryContains(root, item))
        .. " source=" .. tostring(SC.GameplayUtil.inventoryContains(
            fixture.source.container, item))
        .. " destination=" .. tostring(SC.GameplayUtil.inventoryContains(
            fixture.destination.container, item))
        .. " nested=" .. tostring(nested)
        .. " scanComplete=" .. tostring(complete)
        .. " parentRoot=" .. tostring(parent == root)
        .. " parentSource=" .. tostring(parent == fixture.source.container)
        .. " parentDestination=" .. tostring(parent == fixture.destination.container)
        .. " parent=" .. tostring(parent)
end

local function returnedToGroundStorage(fixture, SC)
    for _, storage in ipairs(SC.BaseLife.storageRows("general") or {}) do
        local container = SC.BaseLife.resolveContainer(storage)
        if storage.z == 0 and container and fixture.item
            and SC.GameplayUtil.inventoryContains(container,
                fixture.item) == true then return storage end
    end
    return nil
end

local function navigationDetail(actor, SC)
    local state = SC.Navigation.peek(actor)
    local status = SC.Navigation.status(actor)
    local lease = state and state.nativeLease
    local transition = state and state.stairTransition
    local square = SC.GameplayUtil.squareOf(actor)
    local sx, sy, sz = pos(square)
    local nearbyStairs = 0
    if sx and sy and sz and sz >= 1 then
        for dx = -1, 1 do for dy = -1, 1 do
            local tread = SC.GameplayUtil.gridSquare(sx + dx, sy + dy,
                math.floor(sz) - 1)
            if tread and SC.Topology.squareHasStairs(tread) then
                nearbyStairs = nearbyStairs + 1
            end
        end end
    end
    return "nav=" .. tostring(status.phase)
        .. " path=" .. tostring(status.pathReason)
        .. " target=" .. tostring(status.target)
        .. " attempts=" .. tostring(status.stuckAttempts)
        .. " terminal=" .. tostring(status.terminalReason)
        .. " lease=" .. tostring(lease and lease.affordance)
        .. " inside=" .. tostring(SC.BaseLife.isInside(actor))
        .. " admit=" .. tostring(lease and SC.BaseLife.admitsStairTransit(
            square, lease))
        .. " nearStairs=" .. tostring(nearbyStairs)
        .. " multilevelFailures=" .. tostring(state and state.multiLevelFailureCount)
        .. " stairTarget=" .. tostring(transition and transition.descent
            and transition.descent.key)
end

local function enableTelevision(fixture, SC)
    local tv = fixture.televisions[1]
    if not tv then return false, "none" end
    local power = tonumber(call(tv.data, "getPower")) or 0
    if power > 0 then
        call(tv.data, "setDeviceVolume", 0.6)
        call(tv.data, "setIsTurnedOn", true)
    end
    return SC.TVWatching.isOn(tv.object) == true,
        label(tv.object) .. " power=" .. tostring(power)
end

local function setup(H, SC, check, result, setPhase, current)
    local base = SC.BaseLife.active()
    if not check("second_floor_base", base ~= nil,
        base and base.name or "no active camp") then
        setPhase("finish", current) return
    end
    local actor = chooseActor(SC)
    if not check("second_floor_actor", actor ~= nil,
        actor and actor.name or "no recruited companion on ground floor") then
        setPhase("finish", current) return
    end
    H.secondFloor = actor
    local televisions, ground, upper = findFixtures(base, SC, actor.actor)
    actor.televisions = televisions
    result("PASS", "second_floor_fixture_scan",
        "ground=" .. tostring(#ground) .. " upper=" .. tostring(#upper)
            .. " televisions=" .. tostring(#televisions)
            .. " existing=" .. listStorages(base))
    if not check("second_floor_containers", #ground > 0 and #upper > 0,
        "need loaded physical containers on both floors") then
        setPhase("finish", current) return
    end
    if not check("second_floor_empty_source", ground[1].itemCount == 0,
        "ground=" .. tostring(ground[1].itemCount)
            .. " upper=" .. tostring(upper[1].itemCount)
            .. " at=" .. label(ground[1].object)) then
        setPhase("finish", current) return
    end
    local source, sourceReason = markStorage(SC, ground, "general")
    local destination, destinationReason = markStorage(SC, upper, "construction")
    if not check("second_floor_marked_storage", source ~= nil
        and destination ~= nil,
        "ground=" .. tostring(source and label(source.object) or sourceReason)
            .. " upper=" .. tostring(destination
                and label(destination.object) or destinationReason)) then
        setPhase("finish", current) return
    end
    actor.source, actor.destination = source, destination
    for _, storage in ipairs(base.storages or {}) do
        if storage.id ~= source.marker.id and storage.category == "general" then
            storage.withdrawals = false
            storage.deposits = false
        end
        if storage.id ~= destination.marker.id
            and storage.category == "construction" then
            storage.deposits = false
            storage.withdrawals = false
        end
    end
    source.marker.withdrawals = true
    destination.marker.deposits = true
    -- Existing stock in the upstairs fixture belongs to the cloned save.
    -- Reserve those exact type counts so the return job selects only the
    -- plank introduced by this probe.
    destination.marker.reserves = destination.marker.reserves or {}
    local originalItems = call(destination.container, "getItems")
    if originalItems then
        for index = 0, originalItems:size() - 1 do
            local existing = originalItems:get(index)
            local itemType = SC.GameplayUtil.itemType(existing)
            destination.marker.reserves[itemType] =
                (destination.marker.reserves[itemType] or 0) + 1
        end
    end
    local item = call(source.container, "AddItem", "Base.Plank")
    actor.item = item
    check("second_floor_fixture_item", item ~= nil
        and SC.GameplayUtil.inventoryContains(source.container, item) == true,
        "plank=" .. tostring(item ~= nil)
            .. " originalItems=" .. tostring(source.itemCount)
            .. " source=" .. label(source.object)
            .. " destination=" .. label(destination.object))
    local tvOn, tvInfo = enableTelevision(actor, SC)
    result("PASS", "second_floor_television", tvInfo
        .. " on=" .. tostring(tvOn))
    if tvOn then
        local downstairs = SC.Downtime.canPerform(actor.actor, "tv_watch")
        local direct = SC.TVWatching.candidate(actor.actor, {}, current,
            { seatingStatus = function() return "standing" end }, "tv_watch")
        local utility = SC.GameplayUtil
        local tx, ty, tz = pos(actor.televisions[1].object)
        local viewport = utility.squareOf(actor.televisions[1].object)
        local counts = { room = 0, free = 0, clear = 0, seen = 0,
            range = 0 }
        local nearest = math.huge
        for dx = -3, 3 do for dy = -3, 3 do
            local square = utility.gridSquare(tx + dx, ty + dy, tz)
            local sameRoom = square and call(square, "getRoom") ~= nil
                and call(square, "getRoom") == call(viewport, "getRoom")
            if sameRoom then
                counts.room = counts.room + 1
                if utility.isSquareFree(square) then
                    counts.free = counts.free + 1
                    if not utility.movingBlocker(square, actor.actor) then
                        counts.clear = counts.clear + 1
                        if utility.canSee(square, viewport) then
                            counts.seen = counts.seen + 1
                            local distance = utility.distance(actor.actor, square)
                            nearest = math.min(nearest, distance)
                            if distance <= 8 then
                                counts.range = counts.range + 1
                            end
                        end
                    end
                end
            end
        end end
        check("second_floor_tv_candidate_downstairs",
            downstairs == true and direct ~= nil,
            tostring(downstairs)
                .. " direct=" .. tostring(direct and direct.kind)
                .. " route=" .. tostring(SC.BaseLife.allowsFloorTransit(
                    actor.actor, actor.televisions[1].object,
                    { workCampOnly = true }))
                .. " distance=" .. tostring(SC.GameplayUtil.distance(
                    actor.actor, actor.televisions[1].object))
                .. " room/free/clear/seen/range=" .. counts.room .. "/"
                    .. counts.free .. "/" .. counts.clear .. "/"
                    .. counts.seen .. "/" .. counts.range
                .. " nearest=" .. tostring(nearest))
    end
    local oldJob = SC.BaseLife.jobFor(actor.id)
    if oldJob then
        local cancelled, reason = SC.BaseLife.cancelJob(oldJob.id)
        result(cancelled and "PASS" or "FAIL", "second_floor_old_job_cancel",
            tostring(reason or oldJob.id))
    end
    local issued, order = SC.Commands.issue(actor.id, "stay", {}, H.player)
    result(issued and "PASS" or "FAIL", "second_floor_base_duty",
        tostring(order))
    local queued, job = SC.BaseLife.enqueueJob({ type = "sort", priority = 9,
        assignedId = actor.id, target = { destinationCategory = "construction" } })
    if not check("second_floor_sort_job", queued == true,
        tostring(job and job.id or job)) then
        setPhase("finish", current) return
    end
    actor.jobId = job.id
    actor.startedAt, actor.lastLogAt, actor.lastZ = current, current, 0
    setPhase("base_second_floor_route", current)
end

local function beginReturn(H, SC, fixture, current, check, setPhase)
    SC.Downtime.cancel(fixture.actor, "second_floor_return_probe")
    local queued, job = SC.BaseLife.enqueueJob({ type = "haul", priority = 9,
        assignedId = fixture.id, target = {
            sourceCategory = "construction", destinationCategory = "general",
        } })
    if check("second_floor_return_job", queued == true,
        tostring(job and job.id or job)) then
        fixture.returnJobId = job.id
        fixture.returnStartedAt = current
        fixture.returnLastLogAt = current
        setPhase("base_second_floor_return", current)
    else
        setPhase("finish", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "base_second_floor_setup" then
        if (not SC.BaseLife.active() or #(SC.Registry.snapshot() or {}) == 0)
            and current - H.phaseStartedAt < 12000 then return end
        setup(H, SC, check, result, setPhase, current)
        return
    end
    if H.phase == "base_second_floor_tv" then
        local fixture = H.secondFloor
        if current - (fixture.nextTvAt or 0) < 250 then return end
        fixture.nextTvAt = current
        local handled, reason = SC.Downtime.update(fixture.actor, H.player,
            {}, "tv_watch")
        local tv = fixture.televisions[1]
        local tx, ty, tz = pos(tv.object)
        local watching = SC.TVWatching.isWatching(fixture.actor, tx, ty, tz)
        if watching then
            result("PASS", "second_floor_tv_watching",
                fixture.name .. " watching at " .. tostring(tx) .. ","
                    .. tostring(ty) .. "," .. tostring(tz)
                    .. " update=" .. tostring(handled) .. "/" .. tostring(reason))
            beginReturn(H, SC, fixture, current, check, setPhase)
        elseif current - fixture.tvStartedAt > 30000 then
            result("FAIL", "second_floor_tv_watching",
                "timeout update=" .. tostring(handled) .. "/" .. tostring(reason)
                    .. " " .. navigationDetail(fixture.actor, SC))
            setPhase("finish", current)
        end
        return
    end
    if H.phase == "base_second_floor_return" then
        local fixture = H.secondFloor
        if current - (fixture.nextAt or 0) < 500 then return end
        fixture.nextAt = current
        local x, y, z = pos(fixture.actor)
        local job = SC.BaseLife.job(fixture.returnJobId)
        local destination = returnedToGroundStorage(fixture, SC)
        local returned = destination ~= nil
        if current - fixture.returnLastLogAt >= 10000 then
            result("PASS", "second_floor_return_position",
                fixture.name .. " @" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z) .. " job="
                    .. tostring(job and job.state) .. " blocker="
                    .. tostring(job and job.blocker) .. " returned="
                    .. tostring(returned) .. " "
                    .. navigationDetail(fixture.actor, SC))
            fixture.returnLastLogAt = current
        end
        if z and z < 0.95 and not fixture.reachedGround then
            fixture.reachedGround = true
            result("PASS", "second_floor_downstairs_reached",
                fixture.name .. " @" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z))
        end
        if returned then
            check("second_floor_return_delivered", fixture.reachedGround == true,
                "job=" .. tostring(job and job.state)
                    .. " destination=" .. tostring(destination.id) .. " "
                    .. cargoLocation(fixture, SC))
            setPhase("finish", current)
        elseif job and job.state == "blocked" then
            result("FAIL", "second_floor_return_blocked",
                tostring(job.blocker) .. " " .. navigationDetail(fixture.actor, SC))
            setPhase("finish", current)
        elseif current - fixture.returnStartedAt > 160000 then
            result("FAIL", "second_floor_return_delivered",
                "timeout job=" .. tostring(job and job.state)
                    .. " actor=" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z) .. " " .. navigationDetail(fixture.actor, SC))
            setPhase("finish", current)
        end
        return
    end
    if H.phase ~= "base_second_floor_route" then return end
    local fixture = H.secondFloor
    if current - (fixture.nextAt or 0) < 500 then return end
    fixture.nextAt = current
    local x, y, z = pos(fixture.actor)
    local job = SC.BaseLife.job(fixture.jobId)
    local inDestination = fixture.item and SC.GameplayUtil.inventoryContains(
        fixture.destination.container, fixture.item) == true
    local nav = SC.Navigation.status(fixture.actor)
    if fixture.reachedUpper and not inDestination
        and not fixture.rallyLogged
        and type(nav.target) == "string"
        and string.sub(nav.target, -2) == ":0" then
        fixture.rallyLogged = true
        result("PASS", "second_floor_cargo_return_retry",
            "actor=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                .. " " .. navigationDetail(fixture.actor, SC)
                .. " " .. cargoLocation(fixture, SC))
    end
    local floor = z and math.floor(z + 0.05) or nil
    if floor ~= fixture.lastZ or current - fixture.lastLogAt >= 10000 then
        result("PASS", "second_floor_position",
            fixture.name .. " @" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z)
                .. " job=" .. tostring(job and job.state)
                .. " blocker=" .. tostring(job and job.blocker)
                .. " delivered=" .. tostring(inDestination)
                .. " " .. navigationDetail(fixture.actor, SC))
        fixture.lastLogAt, fixture.lastZ = current, floor
    end
    if z and z > 0.05 and z < 0.95 and not fixture.stairEntered then
        fixture.stairEntered = true
        result("PASS", "second_floor_stair_entered",
            "at=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                .. " " .. cargoLocation(fixture, SC))
        pcall(function() getCore():TakeFullScreenshot(
            tostring(H.config.run_id) .. "-stair-crossing.png") end)
    end
    if job and job.state == "blocked" and not fixture.blockedLogged then
        fixture.blockedLogged = true
        result("FAIL", "second_floor_sort_blocked",
            tostring(job.blocker) .. " " .. cargoLocation(fixture, SC))
        setPhase("finish", current)
        return
    end
    if z and z > 0.05 and z < 0.95 then
        local same = fixture.lastStairX and
            (x - fixture.lastStairX)^2 + (y - fixture.lastStairY)^2 < 0.01
        fixture.stairStalledSince = same
            and (fixture.stairStalledSince or current) or nil
        fixture.lastStairX, fixture.lastStairY = x, y
        if fixture.stairStalledSince
            and current - fixture.stairStalledSince > 15000 then
            result("FAIL", "second_floor_stair_stalled",
                "at=" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
                    .. " " .. navigationDetail(fixture.actor, SC)
                    .. " " .. cargoLocation(fixture, SC))
            setPhase("finish", current)
            return
        end
    else
        fixture.stairStalledSince = nil
    end
    if z and z >= 1 and not fixture.reachedUpper then
        fixture.reachedUpper = true
        result("PASS", "second_floor_upstairs_reached",
            fixture.name .. " @" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z))
        pcall(function() getCore():TakeFullScreenshot(
            tostring(H.config.run_id) .. "-upstairs-storage.png") end)
    end
    if inDestination then
        check("second_floor_sort_delivered", fixture.reachedUpper == true,
            "job=" .. tostring(job and job.state)
                .. " marker=" .. tostring(fixture.destination.marker.id)
                .. " at=" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z))
        local on, info = enableTelevision(fixture, SC)
        local candidate, reason = SC.Downtime.canPerform(fixture.actor, "tv_watch")
        result("PASS", "second_floor_tv_after_delivery",
            info .. " on=" .. tostring(on)
                .. " candidate=" .. tostring(candidate)
                .. " reason=" .. tostring(reason))
        if on and candidate then
            fixture.tvStartedAt = current
            setPhase("base_second_floor_tv", current)
        else
            beginReturn(H, SC, fixture, current, check, setPhase)
        end
        return
    end
    if current - fixture.startedAt > 160000 then
        result("FAIL", "second_floor_sort_delivered",
            "timeout actor=" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z)
                .. " reachedUpper=" .. tostring(fixture.reachedUpper)
                .. " job=" .. tostring(job and job.state)
                .. " blocker=" .. tostring(job and job.blocker))
        setPhase("finish", current)
    end
end

return Probe
