-- SPDX-License-Identifier: MIT
-- Stair combat facts (horde plan S0). The runner installs this only in a
-- disposable cloned save. It finds a real staircase, puts one armed companion
-- at one end and one zombie at the other, and records what the engine does as
-- they meet: climb speed, when the companion first treats the zombie as a
-- threat, who lands the first blow and at what height, and knockdowns on the
-- slope. It measures; it does not judge production behaviour.
local Probe = {}
local FILE = "SurvivorCompanionHarness/stair-combat-results.txt"
local CASES = { "top_defender", "bottom_defender" }
local TRIAL_MS = 45000
local SAMPLE_MS = 100
local LIFETIME_KEY = "SC_StairProbeZombie"
local OBSERVER_SETUP_DISTANCE = 3

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end
local function number(value, fallback) return tonumber(tostring(value)) or fallback end
local function alive(actor)
    return actor ~= nil and call(actor, "isDead") == false
        and SurvivorCompanion.GameplayUtil.nativeHealth(actor) > 0
end
local function fmt(value)
    if value == nil then return "-" end
    if type(value) == "number" then return string.format("%.2f", value) end
    return tostring(value)
end

-- The engine names each stair piece: stairsB*/stairsM*/stairsT* (bottom,
-- middle, top) for north- and west-facing stairs.
local function stairPiece(SC, square)
    local piece
    SC.GameplayUtil.squareObjects(square, function(object)
        if call(object, "isStairsObject") == true then
            piece = tostring(call(object, "getType"))
            return false
        end
    end, 16)
    return piece
end

-- The navigation stair survey's geometry: a free exit tile, three stair tiles
-- in one direction, and a free landing one floor up. Both ends of a staircase
-- often fit that shape, so the bottom piece must face the exit and the top
-- piece the landing, or the "landing" is the floor above the stairs' foot.
local DIRECTIONS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- A Stay order inside the save's camp becomes base duty, and the companion
-- walks off to camp jobs (it left the staircase in earlier runs). Only a
-- staircase entirely outside the camp keeps a fixture still.
local function inCamp(SC, square)
    local base = SC.BaseLife
    return base ~= nil and type(base.isInside) == "function" and base.isInside(square) == true
end

local function findStair(SC, cx, cy, radius, building)
    local U, Topology = SC.GameplayUtil, SC.Topology
    local best, bestD2
    for dy = -radius, radius do
        for dx = -radius, radius do
            local tx, ty = cx + dx, cy + dy
            local exit = U.gridSquare(tx, ty, 0)
            if exit and (not building or call(exit,"getBuilding")==building)
                and U.isSquareFree(exit) and not Topology.squareHasStairs(exit) then
                for _, d in ipairs(DIRECTIONS) do
                    local first = U.gridSquare(tx + d[1], ty + d[2], 0)
                    local middle = U.gridSquare(tx + d[1] * 2, ty + d[2] * 2, 0)
                    local last = U.gridSquare(tx + d[1] * 3, ty + d[2] * 3, 0)
                    local landing = U.gridSquare(tx + d[1] * 4, ty + d[2] * 4, 1)
                    local beyond = U.gridSquare(tx + d[1] * 5, ty + d[2] * 5, 1)
                    if first and middle and last and landing and beyond
                        and Topology.squareHasStairs(first) and Topology.squareHasStairs(middle)
                        and Topology.squareHasStairs(last)
                        and U.isSquareFree(landing) and U.isSquareFree(beyond)
                        and tostring(stairPiece(SC, first)):find("stairsB", 1, true) == 1
                        and tostring(stairPiece(SC, last)):find("stairsT", 1, true) == 1
                        and not inCamp(SC, exit) and not inCamp(SC, landing)
                        and not inCamp(SC, beyond) then
                        local d2 = dx * dx + dy * dy
                        if not bestD2 or d2 < bestD2 then
                            best, bestD2 = { exit = exit, first = first, middle = middle,
                                last = last, landing = landing, beyond = beyond,
                                below = U.gridSquare(tx - d[1], ty - d[2], 0),
                                dx = d[1], dy = d[2], x = tx, y = ty }, d2
                        end
                    end
                end
            end
        end
    end
    return best
end

local function key(square)
    if not square then return "none" end
    return tostring(call(square, "getX")) .. ":" .. tostring(call(square, "getY"))
        .. ":" .. tostring(call(square, "getZ"))
end

-- Which stair tile a height belongs to, counted from the bottom (0 = off the
-- stairs below, 4 = landing above). Uses position along the stair axis.
local function stairIndex(stair, x, y, z)
    if x == nil then return nil end
    local along = (x - (stair.x + 0.5)) * stair.dx + (y - (stair.y + 0.5)) * stair.dy
    return math.floor(along + 0.5), z
end

local function removeZombie(zombie)
    if not zombie then return end
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

local function cleanup(H)
    local SC = SurvivorCompanion
    if H.stairZombie then removeZombie(H.stairZombie) end
    if H.stairActor then
        if alive(H.stairActor) then pcall(SC.Actor.remove, H.stairActor)
        else pcall(SC.Actor.retireDead, H.stairActor) end
    end
    H.stairZombie, H.stairActor = nil, nil
    if H.stair then
        H.clearZombiesNear(H.stair.exit, 12)
        H.clearZombiesNear(H.stair.landing, 12)
    end
end

local function writeResults(H)
    if type(getFileWriter) ~= "function" then return false end
    local writer = getFileWriter(FILE, true, false)
    if not writer then return false end
    writer:writeln("case,trial,stair,outcome,elapsed_ms,climb_ms,climb_start_index,threat_seen_ms,threat_seen_index,threat_seen_z,first_action,first_action_ms,first_action_index,first_action_z,first_hit_ms,first_hit_index,first_hit_z,first_hurt_ms,first_hurt_index,first_hurt_z,knockdowns,knockdown_indices,fell_back,zombie_health_end,companion_health_end,actions")
    for _, row in ipairs(H.stairResults or {}) do
        writer:writeln(table.concat({ row.case, row.trial, row.stair, row.outcome,
            fmt(row.elapsed), fmt(row.climbMs), fmt(row.climbStartIndex),
            fmt(row.threatMs), fmt(row.threatIndex), fmt(row.threatZ),
            fmt(row.firstAction), fmt(row.firstActionMs), fmt(row.firstActionIndex), fmt(row.firstActionZ),
            fmt(row.firstHitMs), fmt(row.firstHitIndex), fmt(row.firstHitZ),
            fmt(row.firstHurtMs), fmt(row.firstHurtIndex), fmt(row.firstHurtZ),
            fmt(row.knockdowns), row.knockdownIndices or "-", fmt(row.fellBack),
            fmt(row.zombieHealthEnd), fmt(row.companionHealthEnd), row.actions or "-" }, ","))
    end
    writer:close()
    return true
end

-- The companion's live runtime is the registry record's, not the weak
-- per-actor table GameplayUtil.actorState hands out without one.
local function runtimeOf(SC, actor)
    local id = actor and SC.Registry.idOf(actor)
    local record = id and SC.Registry.byId(id) or nil
    return record and record.runtime or {}
end

local function sees(SC, actor, zombie)
    local runtime = runtimeOf(SC, actor)
    local snapshot = runtime and runtime.senses and runtime.senses.current
    for _, threat in ipairs(snapshot and snapshot.threats or {}) do
        if threat.actor == zombie then return true end
    end
    return false
end

local function finishTrial(H, current, result, setPhase, outcome)
    local SC = SurvivorCompanion
    local trial = H.stairTrial
    local histogram = {}
    for kind, count in pairs(trial.actions) do histogram[#histogram + 1] = kind .. "=" .. count end
    table.sort(histogram)
    trial.row.outcome = outcome
    trial.row.elapsed = current - trial.startedAt
    trial.row.zombieHealthEnd = number(call(H.stairZombie, "getHealth"), nil)
    trial.row.companionHealthEnd = H.stairActor and SC.GameplayUtil.nativeHealth(H.stairActor) or nil
    trial.row.knockdownIndices = #trial.knockdownAt > 0 and table.concat(trial.knockdownAt, ";") or "-"
    trial.row.actions = #histogram > 0 and table.concat(histogram, ";") or "-"
    print("SC_REAL_SANDBOX|STAIR_TIMELINE|" .. trial.case .. "_" .. tostring(trial.row.trial)
        .. "|" .. table.concat(trial.timeline, " "))
    local row = trial.row
    H.stairResults[#H.stairResults + 1] = row
    result("PASS", "stair_combat_" .. row.case .. "_" .. row.trial,
        "outcome=" .. outcome .. " climb_ms=" .. fmt(row.climbMs)
            .. " threat_seen=" .. fmt(row.threatMs) .. "@" .. fmt(row.threatIndex) .. "/z" .. fmt(row.threatZ)
            .. " first_action=" .. fmt(row.firstAction) .. "@" .. fmt(row.firstActionIndex) .. "/z" .. fmt(row.firstActionZ)
            .. " first_hit=" .. fmt(row.firstHitMs) .. "@" .. fmt(row.firstHitIndex) .. "/z" .. fmt(row.firstHitZ)
            .. " first_hurt=" .. fmt(row.firstHurtMs) .. "@" .. fmt(row.firstHurtIndex) .. "/z" .. fmt(row.firstHurtZ)
            .. " knockdowns=" .. fmt(row.knockdowns) .. "[" .. row.knockdownIndices .. "]"
            .. " fell_back=" .. fmt(row.fellBack) .. " actions=" .. row.actions)
    cleanup(H)
    H.stairTrialIndex = H.stairTrialIndex + 1
    H.stairNextAt = current + 3000
    setPhase("stair_combat_prepare", current)
end

local function sample(H, current, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local trial, stair, actor, zombie = H.stairTrial, H.stair, H.stairActor, H.stairZombie
    local elapsed = current - trial.startedAt
    if not alive(actor) then return finishTrial(H, current, result, setPhase, "companion_dead") end
    local zx, zy, zz = U.position(zombie)
    if not alive(zombie) or zx == nil then
        return finishTrial(H, current, result, setPhase, "zombie_dead")
    end
    local index = stairIndex(stair, zx, zy, zz)
    local row = trial.row
    -- Climb: from leaving the start floor to reaching the far one.
    local startZ, endZ = trial.zombieStartZ, 1 - trial.zombieStartZ
    if row.climbStartMs == nil and math.abs(zz - startZ) > 0.05 then
        row.climbStartMs, row.climbStartIndex = elapsed, index
    end
    if row.climbStartMs ~= nil and row.climbMs == nil and math.abs(zz - endZ) < 0.05 then
        row.climbMs = elapsed - row.climbStartMs
    end
    if row.threatMs == nil and sees(SC, actor, zombie) then
        row.threatMs, row.threatIndex, row.threatZ = elapsed, index, zz
    end
    local runtime = runtimeOf(SC, actor)
    local action = runtime and runtime.combatAction or nil
    if elapsed >= (trial.nextTimelineAt or 0) then
        trial.nextTimelineAt = elapsed + 1000
        local ax, ay, az = U.position(actor)
        local target = call(zombie, "getTarget")
        trial.timeline[#trial.timeline + 1] = string.format(
            "%d:z(%.1f,%.1f,%.2f)i%s:a(%.1f,%.1f,%.2f):t%s:%s:%s:%s:%s",
            math.floor(elapsed / 1000), zx, zy, zz, tostring(index), ax or -1, ay or -1, az or -1,
            target == actor and "A" or target == H.player and "P" or target and "o" or "-",
            (tostring(call(zombie, "getCurrentStateName") or "-"):gsub("[^%w]", "")),
            call(zombie, "isAttacking") == true and "att" or "-",
            tostring(action or "-"),
            (tostring(call(actor, "getCompanionActionStateName") or "-"):gsub("[^%w_]", "")))
    end
    if action ~= nil and action ~= trial.lastAction then
        trial.actions[action] = (trial.actions[action] or 0) + 1
        if row.firstAction == nil then
            row.firstAction, row.firstActionMs, row.firstActionIndex, row.firstActionZ =
                action, elapsed, index, zz
        end
    end
    trial.lastAction = action
    local zombieHealth = number(call(zombie, "getHealth"), nil)
    if row.firstHitMs == nil and zombieHealth and trial.zombieHealth
        and zombieHealth < trial.zombieHealth - 0.001 then
        row.firstHitMs, row.firstHitIndex, row.firstHitZ = elapsed, index, zz
    end
    trial.zombieHealth = zombieHealth or trial.zombieHealth
    local actorHealth = U.nativeHealth(actor)
    if row.firstHurtMs == nil and actorHealth < trial.actorHealth - 0.001 then
        row.firstHurtMs, row.firstHurtIndex, row.firstHurtZ = elapsed, index, zz
    end
    local down = call(zombie, "isOnFloor") == true
    if down and not trial.down then
        row.knockdowns = (row.knockdowns or 0) + 1
        trial.knockdownAt[#trial.knockdownAt + 1] = tostring(index) .. "/z" .. fmt(zz)
        trial.downZ = zz
    end
    -- A zombie knocked down on the slope that ends lower than it fell counts
    -- as falling back down the stairs.
    if trial.down and not down and trial.downZ and zz < trial.downZ - 0.2 then
        row.fellBack = (row.fellBack or 0) + 1
    end
    trial.down = down
    if actorHealth < 45 then return finishTrial(H, current, result, setPhase, "companion_hurt") end
    if elapsed >= TRIAL_MS then return finishTrial(H, current, result, setPhase, "timeout") end
end

-- Optional explicit-post acceptance uses the same real staircase, plus a
-- loaded house door. It never supplies fake perceptions or combat plans.
local function guardPhoto(H, label)
    pcall(function()
        if SurvivorCompanion.UI then SurvivorCompanion.UI.close() end
        for slot=0,(getSpecificPlayer(1) and 1 or 0) do
            call(getPlayerInfoPanel(slot),"setVisible",false)
            call(getPlayerInventory(slot),"setVisible",false)
            call(getPlayerLoot(slot),"setVisible",false)
            call(getPlayerMiniMap(slot),"setVisible",false)
            getCore():setAutoZoom(slot, false)
            for _ = 1, 8 do if getCore():getZoom(slot) < 2.5 then getCore():doZoomScroll(slot, 1) end end
        end
        getCore():TakeFullScreenshot(H.config.run_id .. "-guard-" .. label .. ".png")
    end)
end

-- Spectate on the defenders' floor, clear of the fight. Prefer a room in
-- this house; nearby loaded rooms are a
-- fallback when a small upper floor has no sufficiently distant safe tile.
local function distantGuardObserver(SC, H)
    local U, post = SC.GameplayUtil, H.guardPost
    local building = call(U.gridSquare(post.x, post.y, post.z), "getBuilding")
    local best, bestScore
    for y = post.y-32, post.y+32 do for x = post.x-32, post.x+32 do
        local square = U.gridSquare(x, y, post.z)
        if square and call(square,"getRoom") ~= nil and U.isSquareFree(square)
            and call(square,"TreatAsSolidFloor")==true and not SC.Combat.atStairs(square) then
            local minimum = math.huge
            for _,actor in ipairs(H.guardActors) do
                local ax,ay = U.position(actor)
                minimum = math.min(minimum,(x-ax)^2+(y-ay)^2)
            end
            -- Leave staging room for the guard slots to settle after the
            -- observer moves. The actual required clearance is three tiles.
            if minimum >= (OBSERVER_SETUP_DISTANCE+2)^2 then
                -- Leave room for a genuine retreat without bringing the
                -- fighting companions into the observer's three-tile clearance.
                local score = building and call(square,"getBuilding")==building and 10000+minimum or -minimum
                if not bestScore or score > bestScore then best,bestScore = square,score end
            end
        end
    end end
    return best
end

local function guardDoor(SC, cx, cy)
    local U, best, distance = SC.GameplayUtil
    for y = cy - 45, cy + 45 do for x = cx - 45, cx + 45 do
        local sq = U.gridSquare(x, y, 0)
        if sq then U.squareObjects(sq, function(object)
            if not U.instanceOf(object, "IsoDoor") or call(object, "isGarageDoor") == true then return end
            local north = call(object, "getNorth")
            local other = U.gridSquare(x - (north and 0 or 1), y - (north and 1 or 0), 0)
            local inside, outside, dx, dy
            if call(sq, "getRoom") and other and not call(other, "getRoom") then
                inside, outside, dx, dy = sq, other, north and 0 or 1, north and 1 or 0
            elseif other and call(other, "getRoom") and not call(sq, "getRoom") then
                inside, outside, dx, dy = other, sq, north and 0 or -1, north and -1 or 0
            end
            if not inside or inCamp(SC, inside) then return end
            local ix, iy = U.position(inside)
            local post = { x = ix, y = iy, z = 0, dx = dx, dy = dy }
            for depth = -4, 3 do
                local tile = U.gridSquare(ix + dx * depth, iy + dy * depth, 0)
                if not tile or not U.isSquareFree(tile) or SC.Topology.squareHasStairs(tile)
                    or call(tile, "TreatAsSolidFloor") ~= true then return end
                if depth > 0 then
                    local previous = U.gridSquare(ix + dx * (depth - 1), iy + dy * (depth - 1), 0)
                    local edge = SC.Topology.classifyEdge(nil, previous, tile, {})
                    if not edge or not edge.traversable or edge.affordance ~= "open" then return end
                end
            end
            local d2 = (ix - cx)^2 + (iy - cy)^2
            if not distance or d2 < distance then
                best, distance = { square = inside, outside = outside, object = object, post = post }, d2
            end
        end, 32) end
    end end
    return best
end

local function guardZombieAlive(H, zombie)
    local receipt = H.guardLives and H.guardLives[zombie]
    if not receipt or receipt.dead then return false end
    local data = call(zombie, "getModData")
    if not data or data[LIFETIME_KEY] ~= receipt.token then
        H.guardLostLife = true; return false
    end
    if call(zombie, "isDead") == true then receipt.dead = true; return false end
    return true
end

-- View-only clone setup. Guard-here actors normally cannot enroll in Base
-- Watch; satisfy its duty precondition synchronously, then restore it before
-- the engine advances. Never issue a new order or overwrite the guard anchor.
local function startGuardWatch(SC,H)
    local U,leader=SC.GameplayUtil,H.guardActors[1]
    local definition=call(call(U.gridSquare(H.guardPost.x,H.guardPost.y,H.guardPost.z),"getBuilding"),"getDef")
    if not definition then return false,"watch_building_missing" end
    SC.BaseLife.reset()
    local okay,why=SC.BaseLife.create(U.squareOf(leader),"Stair combat watch camp")
    if not okay then return false,why end
    for floor=0,1 do
        okay,why=SC.BaseLife.beginZone("area",{x=definition:getX(),y=definition:getY(),z=floor})
        if okay then okay,why=SC.BaseLife.finishZone(
            {x=definition:getX2()-1,y=definition:getY2()-1,z=floor},"Watch camp floor " .. floor) end
        if not okay then return false,why end
    end
    for _,actor in ipairs(H.guardActors) do
        okay,why=SC.BaseLife.assign(SC.Registry.idOf(actor),"guard",true)
        if not okay then return false,why end
    end
    local commands=SC.Commands.peek(leader)
    local originalOrder=commands.order
    commands.order="base_duty"
    local called,watched,watchWhy=pcall(SC.BaseWatch.start,SC.Registry.idOf(leader))
    commands.order=originalOrder
    if not called then return false,watched end
    H.guardWatchStarted=watched
    return watched,watchWhy
end

local function guardCleanup(H)
    local SC = SurvivorCompanion
    if H.guardWatchStarted then
        local released=SC.BaseWatch.prepareReset()
        if not released then return false end
        SC.BaseWatch.reset()
        H.guardWatchStarted=nil
    end
    if H.guardDeathObserver then Events.OnZombieDead.Remove(H.guardDeathObserver); H.guardDeathObserver = nil end
    for _, zombie in ipairs(H.guardZombies or {}) do
        if guardZombieAlive(H, zombie) then removeZombie(zombie) end
    end
    for _, actor in ipairs(H.guardActors or {}) do
        if alive(actor) then pcall(SC.Actor.remove, actor) else pcall(SC.Actor.retireDead, actor) end
    end
    H.guardZombies, H.guardActors = {}, {}
    return true
end

local function guardStep(H, current, check, result, setPhase)
    local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
    local function fail(id, why)
        guardPhoto(H, "blocked-" .. id)
        result("FAIL", id, tostring(why)); H.guardFailedAt = current
        setPhase("stair_combat_guard_failed", current)
    end
    if H.phase == "stair_combat_guard_failed" then
        if H.stair and current - H.guardFailedAt >= 1000 and not H.guardLowerPhotoAt then
            H.player:teleportTo(H.stair.exit:getX()+0.5,H.stair.exit:getY()+0.5,0)
            H.guardLowerPhotoAt = current
        end
        if current - H.guardFailedAt >= 2000 then
            if H.guardLowerPhotoAt then guardPhoto(H,"blocked-downstairs") end
            if guardCleanup(H) then setPhase("finish", current) end
        end
        return
    end
    -- One ordinary round trip before the armed landing trial. Only fixture
    -- staging relocates companions; the two floor changes use Follow itself.
    if H.phase == "stair_combat_walk" then
        local direction = H.guardWalkDirection
        if direction == "setup" then
            if current - H.phaseStartedAt < 1000 then return end
            guardPhoto(H, "house-ground-setup")
            local observer = H.guardUpperObserver
            H.player:teleportTo(observer:getX() + 0.5, observer:getY() + 0.5, 1)
            for _, actor in ipairs(H.guardActors) do
                local okay, why = SC.Commands.issue(SC.Registry.idOf(actor), "follow", nil, H.player)
                if not okay then return fail("stair_follow_order", why) end
            end
            H.guardWalkDirection, H.guardWalkStarted, H.guardWalkSlope = "up", current, {}
            return
        end
        local reached, details = 0, {}
        for _, actor in ipairs(H.guardActors) do
            local x, y, z = U.position(actor)
            if not alive(actor) then return fail("stair_follow_alive", direction) end
            if z > 0.05 and z < 0.95 then H.guardWalkSlope[actor] = true end
            local targetZ = direction == "up" and 1 or 0
            if math.abs(z - targetZ) < 0.05 and not SC.Combat.atStairs(actor)
                and U.distance(actor, H.player) <= 5 then reached = reached + 1 end
            details[#details + 1] = string.format("%.2f:%.2f:%.2f/%s", x, y, z,
                tostring(call(actor, "getCurrentStateName")))
        end
        if current - H.guardWalkStarted > 65000 then
            return fail("stair_follow_" .. direction, table.concat(details, ";"))
        end
        if reached ~= 2 then H.guardWalkSettledAt = nil; return end
        H.guardWalkSettledAt = H.guardWalkSettledAt or current
        if current - H.guardWalkSettledAt < 700 then return end
        for _, actor in ipairs(H.guardActors) do
            if not H.guardWalkSlope[actor] then return fail("stair_follow_native_crossing", direction) end
        end
        check("stair_follow_" .. direction, true, "two companions; elapsed_ms="
            .. tostring(current - H.guardWalkStarted) .. " positions=" .. table.concat(details, ";"))
        guardPhoto(H, "house-follow-" .. direction)
        H.guardWalkSettledAt = nil
        if direction == "up" then
            local observer = H.guardLowerObserver
            H.player:teleportTo(observer:getX() + 0.5, observer:getY() + 0.5, 0)
            H.guardWalkDirection, H.guardWalkStarted, H.guardWalkSlope = "down", current, {}
        else
            H.guardWalkComplete = true
            -- Spawn the combat pair on its actual floor. Raw teleportTo does
            -- not update the companion provider's floor ownership reliably.
            guardCleanup(H)
            local observer = H.guardUpperObserver
            H.player:teleportTo(observer:getX() + 0.5, observer:getY() + 0.5, 1)
            setPhase("stair_combat_guard_prepare", current)
        end
        return
    end
    if H.phase == "stair_combat_setup" then
        if current - H.phaseStartedAt < 4000 then return end
        if H.config.stair_combat_site=="rosewood_firestation" then
            if not H.guardSiteLoadAt then
                H.player:setGhostMode(true)
                H.player:teleportTo(8140,11738,0)
                H.guardSiteLoadAt = current
                return
            end
            if current-H.guardSiteLoadAt < 8000 then return end
            H.guardSiteBuilding = call(U.gridSquare(8140,11738,0),"getBuilding")
            if not H.guardSiteBuilding then
                if current-H.guardSiteLoadAt > 45000 then
                    return fail("stair_site_load","Rosewood fire station has not streamed")
                end
                return
            end
        end
        for _, actor in ipairs(SC.Registry.living()) do pcall(SC.Actor.remove, actor) end
        local x, y = U.position(H.player)
        H.stair = findStair(SC, math.floor(x), math.floor(y), 70,H.guardSiteBuilding)
        H.guardRecoveryOnly = H.config.stair_combat_mode == "recovery"
        H.guardStairsOnly = H.config.stair_combat_mode == "stairs" or H.guardRecoveryOnly
        H.guardTrial, H.guardTrials = 1, number(H.config.stair_combat_trials, 3)
        H.guardDoor = not H.guardStairsOnly and guardDoor(SC, math.floor(x), math.floor(y)) or nil
        if not H.stair or (not H.guardStairsOnly and not H.guardDoor) then return fail("guard_geometry", "stairs="
            .. tostring(H.stair ~= nil) .. " door=" .. tostring(H.guardDoor ~= nil)) end
        pcall(function() getGameTime():setTimeOfDay(12) end)
        pcall(function() H.player:setGhostMode(true) end)
        pcall(function() if SC.UI then SC.UI.close() end end)
        pcall(function() getPlayerInventory(0):setVisible(false); getPlayerLoot(0):setVisible(false) end)
        H.guardCase = 1
        H.guardActors, H.guardZombies = {}, {}
        setPhase("stair_combat_guard_prepare", current); return
    end
    if H.phase == "stair_combat_guard_prepare" then
        if current < (H.guardNextAt or 0) then return end
        if H.guardCase > 3 or H.guardStairsOnly and H.guardTrial > H.guardTrials then
            setPhase("finish", current); return
        end
        local square = H.guardCase == 1 and H.stair.landing or H.guardDoor.square
        local post = SC.GuardPost.detect(H.player, square, H.guardCase > 1 and {
            x = H.guardDoor.post.dx, y = H.guardDoor.post.dy } or nil)
        if not post then return fail("guard_detect", key(square)) end
        H.guardPost = post
        H.clearZombiesNear(square, 18)
        H.clearZombiesNear(H.stair.exit, 15)
        H.guardActors, H.guardZombies, H.guardTickets, H.guardStageSquares = {}, {}, {}, {}
        H.guardSamples, H.guardSlope, H.guardMaxDrift = 0, 0, 0
        H.guardEarly, H.guardStallPhoto, H.guardLastKills = false, false, 0
        H.guardEarlyZ, H.guardResets, H.guardResetReachedAt = nil, 0, nil
        H.guardLives, H.guardLostLife = {}, false
        H.guardObserverReadyAt, H.guardObserverClosest = nil,math.huge
        local walkFixture = H.guardStairsOnly and not H.guardRecoveryOnly and not H.guardWalkComplete
        if walkFixture then
            local stair, places = H.stair, {}
            for depth = 0, 4 do for side = -2, 2 do
                local sq = U.gridSquare(stair.x - stair.dx * depth - stair.dy * side,
                    stair.y - stair.dy * depth + stair.dx * side, 0)
                if #places < 3 and sq and U.isSquareFree(sq)
                    and call(sq, "TreatAsSolidFloor") == true and not SC.Topology.squareHasStairs(sq)
                    and call(sq, "getRoom") == call(stair.exit, "getRoom") then places[#places+1] = sq end
            end end
            if #places < 3 then return fail("stair_follow_space", "three clear tiles in the ground-floor hall required") end
            H.guardWalkPlaces, H.guardLowerObserver = places, places[3]
        end
        for i = 1, 2 do
            local spawn = walkFixture and H.guardWalkPlaces[i] or nil
            for depth = 0, 4 do
                for side = -2, 2 do
                    local candidate = U.gridSquare(post.x + post.dx * depth - post.dy * side,
                        post.y + post.dy * depth + post.dx * side, post.z)
                    if not spawn and candidate and not H.guardStageSquares[key(candidate)]
                        and U.isSafeSpawnSquare(candidate)
                        and not SC.Combat.atStairs(candidate) then spawn = candidate end
                end
            end
            if not spawn then return fail("guard_spawn_space", "no clear staging square") end
            H.guardStageSquares[key(spawn)] = true
            local ticket, why = SC.Actor.beginSpawn(spawn, { recruited = true, identity = {
                forename = "Guard", surname = tostring(H.guardCase) .. " " .. tostring(i),
                gender = i == 1 and "woman" or "man", outfit = "Generic01" } })
            if not ticket then return fail("guard_spawn", why) end
            H.guardTickets[i] = ticket
        end
        local observer
        local offsets = H.guardCase == 1 and { { 2, 1 }, { 2, -1 }, { 3, 0 }, { 1, 1 }, { 1, -1 } }
            or { { 10, 0 }, { 10, 2 }, { 10, -2 }, { 8, 0 }, { 8, 2 }, { 8, -2 },
                { 6, 0 }, { 5, 0 }, { 4, 0 }, { 4, 1 }, { 4, -1 } }
        for _, offset in ipairs(offsets) do
            local sq = U.gridSquare(post.x + post.dx * offset[1] - post.dy * offset[2],
                post.y + post.dy * offset[1] + post.dx * offset[2], post.z)
            if sq and call(sq, "TreatAsSolidFloor") == true and U.isSquareFree(sq)
                and not SC.Combat.atStairs(sq)
                and (H.guardCase == 1 or SC.Navigation.openSegment({ x = post.x + 0.5,
                    y = post.y + 0.5, z = post.z }, sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ())) then
                observer = sq; break end
        end
        if not observer then return fail("guard_observer", "no protected observer square") end
        H.guardUpperObserver = observer
        H.player:teleportTo(observer:getX() + 0.5, observer:getY() + 0.5, observer:getZ())
        if H.guardCase > 1 and call(H.guardDoor.object, "IsOpen") ~= true
            and call(H.guardDoor.object, "isOpen") ~= true then
            pcall(function() H.guardDoor.object:ToggleDoor(H.player) end)
        end
        setPhase("stair_combat_guard_poll", current); return
    end
    if H.phase == "stair_combat_guard_poll" then
        for i, ticket in ipairs(H.guardTickets) do if not H.guardActors[i] then
            local actor, why = SC.Actor.pollSpawn(ticket)
            if actor then
                H.guardActors[i] = actor
                if not H.guardRecoveryOnly then
                    local item = call(call(actor, "getInventory"), "AddItem", "Base.Crowbar")
                    if not item then return fail("guard_weapon", "crowbar creation failed") end
                    actor:setPrimaryHandItem(item)
                end
                actor:getStats():set(CharacterStat.ENDURANCE, 1)
                actor:getStats():set(CharacterStat.FATIGUE, 0)
            elseif why ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                return fail("guard_spawn_poll", why)
            end
        end end
        if H.guardActors[1] and H.guardActors[2] then
            if H.guardStairsOnly and not H.guardRecoveryOnly and not H.guardWalkComplete then
                local stair, places = H.stair, H.guardWalkPlaces
                for _, actor in ipairs(H.guardActors) do
                    local _, _, z = U.position(actor)
                    if z ~= 0 then return fail("stair_follow_spawn_floor", tostring(z)) end
                end
                H.player:teleportTo(places[3]:getX()+0.5,places[3]:getY()+0.5,0)
                H.guardWalkDirection = "setup"
                result("PASS", "stair_house_setup", "ground=" .. key(stair.exit) .. " upper=" .. key(stair.landing)
                    .. " pieces=" .. tostring(stairPiece(SC,stair.first)) .. "/"
                    .. tostring(stairPiece(SC,stair.middle)) .. "/" .. tostring(stairPiece(SC,stair.last)))
                setPhase("stair_combat_walk", current); return
            end
            -- Native IDs contain variable-length timestamps. Stage the fight
            -- at its ID-ordered positions; do not make two actors swap through
            -- each other in the one-square choke before the trial starts.
            table.sort(H.guardActors, function(a, b)
                return tostring(SC.Registry.idOf(a)) < tostring(SC.Registry.idOf(b))
            end)
            if H.guardRecoveryOnly then
                -- The rear guard covers the unarmed front defender. Two
                -- unarmed actors correctly choose withdrawal before a reset
                -- can be exercised reliably; do not override that decision.
                local cover = H.guardActors[2]
                local item = call(call(cover, "getInventory"), "AddItem", "Base.Crowbar")
                if not item then return fail("guard_cover_weapon", "crowbar creation failed") end
                cover:setPrimaryHandItem(item)
            end
            for i, actor in ipairs(H.guardActors) do
                local p = H.guardPost
                actor:teleportTo(p.x + p.dx * (i - 1) + 0.5,
                    p.y + p.dy * (i - 1) + 0.5, p.z)
                local ordered, reason = SC.Commands.issue(SC.Registry.idOf(actor), "guard",
                    { target = { x = p.x, y = p.y, z = p.z } }, H.player)
                if not ordered or call(actor, "getModData").SC_Order ~= "guard" then
                    return fail("guard_order", reason) end
            end
            -- All orders must exist before resolving the shared positions.
            -- This is fixture staging only, before any attackers are spawned.
            for _, actor in ipairs(H.guardActors) do
                SC.Navigation.cancel(actor, "guard_probe_staging")
                U.stop(actor)
                local post = SC.GuardPost.forActor(actor, runtimeOf(SC, actor), nil, current)
                local point = SC.GuardPost.point(post)
                if not point then return fail("guard_stage_position", "post has no safe position") end
                actor:teleportTo(point.x, point.y, point.z)
            end
            setPhase("stair_combat_guard_quiet", current)
        end
        return
    end
    if H.phase == "stair_combat_guard_quiet" then
        if current - H.phaseStartedAt < 6000 then return end
        if H.config.stair_combat_base_watch=="true" then
            if not H.guardWatchStarted then
                local okay,why=startGuardWatch(SC,H)
                if not okay then return fail("guard_base_watch_start",why) end
                H.guardWatchRequestedAt=current
                return
            end
            if getSpecificPlayer(1)~=H.guardActors[1] then
                if current-H.guardWatchRequestedAt>15000 then return fail("guard_base_watch_join","view join timed out") end
                return
            end
            if not H.guardWatchVerified then
                result("PASS","guard_base_watch_view","camp=" .. SC.BaseLife.active().name
                    .. " leader=" .. SC.Registry.idOf(H.guardActors[1]) .. " native_slot=1")
                H.guardWatchVerified=true
                guardPhoto(H,"base-watch-ready")
            end
        end
        if not H.guardObserverReadyAt then
            local observer = distantGuardObserver(SC,H)
            if not observer then return fail("guard_observer_clearance","no safe same-floor observer tile at least " .. OBSERVER_SETUP_DISTANCE .. " metres from both defenders") end
            H.player:teleportTo(observer:getX()+0.5,observer:getY()+0.5,observer:getZ())
            H.player:setCurrentSquare(observer)
            H.guardObserverReadyAt = current+1000
            return
        end
        if current < H.guardObserverReadyAt then return end
        local ox,oy,oz = U.position(H.player)
        local separation = math.huge
        for _,actor in ipairs(H.guardActors) do separation = math.min(separation,U.distance(actor,H.player)) end
        if math.abs(oz-H.guardPost.z)>0.01 or call(call(H.player,"getCurrentSquare"),"getZ")~=H.guardPost.z
            or separation<OBSERVER_SETUP_DISTANCE then return fail("guard_observer_clearance","floor=" .. tostring(oz) .. " minimum_distance=" .. fmt(separation)) end
        result("PASS","guard_observer_position_" .. H.guardTrial,
            string.format("observer=%.2f:%.2f:%.2f defenders_floor=%s minimum_distance=%.2f ghost=%s",
                ox,oy,oz,tostring(H.guardPost.z),separation,tostring(call(H.player,"isGhostMode"))))
        for _, actor in ipairs(H.guardActors) do
            local post = SC.GuardPost.forActor(actor, runtimeOf(SC, actor), nil, current)
            if not post or not SC.GuardPost.atPosition(actor, post) then
                local x, y, z = U.position(actor)
                local point = SC.GuardPost.point(post)
                return fail("guard_settled", string.format("%.2f:%.2f:%.2f expected=%s:%s:%s", x, y, z,
                    tostring(point and point.x), tostring(point and point.y), tostring(point and point.z))) end
        end
        result("PASS", "guard_settled_" .. H.guardCase,
            "kind=" .. H.guardPost.kind .. " anchor=" .. key(call(H.guardActors[1], "getSquare")))
        if H.guardWatchStarted then
            -- The observer's bedroom is outside the landing's original
            -- clearance radius. Remove ambient actors before the measured
            -- wave exists, so this remains exactly two versus five.
            local removed=H.clearZombiesNear(U.gridSquare(H.guardPost.x,H.guardPost.y,H.guardPost.z),64)
            result("PASS","guard_watch_observer_safety","ambient_removed=" .. tostring(removed)
                .. " radius=64 measured_wave_not_yet_spawned=true")
        end
        guardPhoto(H, tostring(H.guardCase) .. "-" .. H.guardTrial .. "-holding")
        H.guardStarted, H.guardNextSample = current, current
        H.guardLastKillAt = current
        H.guardDeathObserver = function(zombie)
            local receipt = H.guardLives[zombie]
            local data = receipt and call(zombie, "getModData")
            if data and data[LIFETIME_KEY] == receipt.token then
                receipt.dead = true
                print("SC_REAL_SANDBOX|GUARD_KILL|trial=" .. H.guardTrial .. " index=" .. receipt.index)
            end
        end
        Events.OnZombieDead.Add(H.guardDeathObserver)
        local count = H.guardRecoveryOnly and 1 or H.guardCase == 3 and 12
            or math.max(1, math.min(12, number(H.config.stair_combat_zombies, 3)))
        for i = 1, count do
            local p = H.guardPost
            local square = H.guardCase == 1 and H.stair.first
                or U.gridSquare(p.x - p.dx * (3 + math.floor((i - 1) / 3)),
                    p.y - p.dy * (3 + math.floor((i - 1) / 3)), p.z)
            local ok, list = pcall(addZombiesInOutfit, square:getX(), square:getY(), square:getZ(), 1, nil, 0)
            local zombie = ok and list and call(list, "get", 0)
            if not zombie then return fail("guard_zombie_spawn", tostring(i)) end
            local token = {}
            call(zombie, "getModData")[LIFETIME_KEY] = token
            H.guardLives[zombie] = { token = token, index = i }
            H.guardZombies[#H.guardZombies + 1] = zombie
            local target = H.guardActors[(i - 1) % 2 + 1]
            zombie:spotted(target, true)
        end
        result("PASS", "guard_attackers_spawned", "companions=" .. #H.guardActors .. " zombies=" .. #H.guardZombies)
        setPhase("stair_combat_guard_observe", current); return
    end
    if H.phase == "stair_combat_guard_observe" then
        if current < H.guardNextSample then return end
        H.guardNextSample = current + 100
        if not alive(H.player) then return fail("guard_observer_alive", "observer died; trial invalid") end
        local observerZ = select(3,U.position(H.player))
        if math.abs(observerZ-H.guardPost.z)>0.01 then return fail("guard_observer_floor",tostring(observerZ)) end
        local live, dead, retreating, bites, lowestHealth, resetSettled = 0, 0, 0, 0, 100, 0
        for _, actor in ipairs(H.guardActors) do
            if alive(actor) then live = live + 1 end
            if alive(actor) then
                local separation = U.distance(actor,H.player)
                H.guardObserverClosest = math.min(H.guardObserverClosest,separation)
                if separation < OBSERVER_SETUP_DISTANCE then return fail("guard_observer_entered_arena","minimum_distance=" .. fmt(separation)) end
            end
            local assessment = SC.Medical.assess(actor)
            bites = bites + (assessment.bites or 0)
            lowestHealth = math.min(lowestHealth, U.nativeHealth(actor))
            local rt = runtimeOf(SC, actor)
            for _, incoming in ipairs(rt.senses and rt.senses.current and rt.senses.current.stairIncoming or {}) do
                if (incoming.z or 1) < H.guardPost.z - 0.1 then
                    H.guardEarly = true
                    H.guardEarlyZ = math.min(H.guardEarlyZ or incoming.z, incoming.z)
                end
            end
            local ctx = rt.guardPost
            if rt.stairCombat and rt.stairCombat.recovery then H.guardResets = H.guardResets + 1 end
            if ctx and ctx.insetUntil and current < ctx.insetUntil
                and SC.GuardPost.atPosition(actor, ctx) then resetSettled = resetSettled + 1 end
            local x, y, z = U.position(actor)
            if SC.Combat.atStairs(actor) then H.guardSlope = H.guardSlope + 1 end
            if ctx and ctx.position then
                local drift = math.sqrt((x - ctx.position.x - 0.5)^2 + (y - ctx.position.y - 0.5)^2)
                H.guardMaxDrift = math.max(H.guardMaxDrift, drift)
            end
            if call(actor, "getModData").SC_Order == "retreat" then retreating = retreating + 1 end
        end
        for _, zombie in ipairs(H.guardZombies) do
            guardZombieAlive(H, zombie)
            if H.guardLives[zombie].dead then dead = dead + 1 end
        end
        if H.guardLostLife then return fail("guard_zombie_identity", "spawn token lost without confirmed death") end
        if current >= (H.guardRetargetAt or 0) then
            H.guardRetargetAt = current + 1000
            for i, zombie in ipairs(H.guardZombies) do if guardZombieAlive(H, zombie) then
                local target = H.guardActors[(i - 1) % 2 + 1]
                -- Preserve native switches between living defenders. Replacing
                -- that target every second can interrupt a valid stair path.
                if not alive(call(zombie, "getTarget")) then
                    if not alive(target) then target = H.guardActors[i % 2 + 1] end
                else target = nil end
                if alive(target) then
                    zombie:spotted(target, true)
                    if call(zombie, "getTarget") ~= target then zombie:setTarget(target) end
                end
            end end
            local states = {}
            for _, actor in ipairs(H.guardActors) do
                local rt = runtimeOf(SC, actor)
                local combat = SC.Combat.peek(actor)
                local plan = combat and combat.squadPlan
                local ev = combat and combat.lastCombatEvidence
                local x, y, z = U.position(actor)
                states[#states + 1] = string.format("%.1f:%.1f:%.1f/%s/%s/%s/%s/shoves%s/ev%s:%s", x, y, z,
                    tostring(call(actor, "getModData").SC_Order), tostring(rt.combatAction),
                    tostring(plan and plan.mode), tostring(plan and plan.forecast),
                    tostring(combat and combat.stairShoves and combat.stairShoves.count),
                    tostring(ev and ev.action), tostring(ev and ev.result))
                    .. "/hp" .. fmt(ev and ev.healthBefore) .. ":" .. fmt(ev and ev.healthAfter)
                    .. "/serial" .. tostring(call(actor, "getCompanionAttackReceiptSerial"))
                    .. "/native" .. tostring(call(actor, "getCompanionActionStateName"))
                local overrun = combat and combat.overrun or {}
                local readiness = overrun.readiness or {}
                states[#states] = states[#states] .. "/risk" .. fmt(overrun.risk) .. ":" .. fmt(overrun.threshold)
                    .. "/covered" .. tostring(overrun.coveredStair)
                    .. "/holds" .. tostring(plan and plan.holds) .. "/support" .. fmt(overrun.support)
                    .. "/sectors" .. fmt(overrun.occupiedSectors) .. "/internal" .. fmt(readiness.internalRisk)

            end
            local zombies = {}
            for _, zombie in ipairs(H.guardZombies) do if guardZombieAlive(H, zombie) then
                local x, y, z = U.position(zombie)
                zombies[#zombies + 1] = string.format("%.2f:%.2f:%.2f/hp%s/%s/stairs%s",
                    x, y, z, fmt(call(zombie, "getHealth")), tostring(call(zombie, "getCurrentStateName")),
                    tostring(SC.Combat.atStairs(zombie)))
                local path, target = call(zombie,"getPathFindBehavior2"),call(zombie,"getTarget")
                zombies[#zombies] = zombies[#zombies] .. "/target"
                    .. (target==H.guardActors[1] and "1" or target==H.guardActors[2] and "2" or "other")
                    .. "/goal" .. fmt(call(path,"getTargetX")) .. ":" .. fmt(call(path,"getTargetY"))
                    .. ":" .. fmt(call(path,"getTargetZ")) .. "/goal_kind"
                    .. (call(path,"isGoalSound")==true and "sound" or call(path,"isGoalCharacter")==true
                        and "character" or call(path,"isGoalLocation")==true and "location" or "other")
            end end
            print("SC_REAL_SANDBOX|GUARD_TIMELINE|" .. H.guardCase .. "|" .. table.concat(states, ";")
                .. "|zombies=" .. table.concat(zombies, ";"))
        end
        if current - H.guardStarted >= 6000 and not H.guardFightPhoto then
            guardPhoto(H, tostring(H.guardCase) .. "-" .. H.guardTrial .. "-combat"); H.guardFightPhoto = true
        end
        if dead > H.guardLastKills then H.guardLastKills, H.guardLastKillAt = dead, current end
        if not H.guardStallPhoto and current - H.guardLastKillAt >= 30000 then
            guardPhoto(H, "stalled-" .. H.guardCase .. "-" .. H.guardTrial); H.guardStallPhoto = true
        end
        -- This scenario exercises native shoves and the resulting movement,
        -- not an unarmed victory. Armed landing trials separately require kills.
        if H.guardRecoveryOnly and H.guardResets > 0 and resetSettled == 2 then
            H.guardResetReachedAt = H.guardResetReachedAt or current
        end
        local resetFinished = H.guardRecoveryOnly and H.guardResetReachedAt
            and current - H.guardResetReachedAt >= 1000
        if H.guardCase == 3 and retreating == 2 or dead == #H.guardZombies
            or resetFinished
            or live < 2 or current - H.guardStarted > (H.guardStairsOnly and 90000 or 45000) then
            guardPhoto(H, tostring(H.guardCase) .. "-" .. H.guardTrial .. "-end")
            local passed = live == 2 and H.guardSlope == 0 and (H.guardCase ~= 3 or retreating == 2)
                and (H.guardRecoveryOnly or H.guardCase == 3 or dead == #H.guardZombies)
                and (not H.guardStairsOnly or H.guardEarly)
                and (not H.guardRecoveryOnly or resetFinished and H.guardEarly and bites == 0)
            local detail = "alive=" .. live .. " kills=" .. dead .. " slope_samples=" .. H.guardSlope
                .. " attackers=" .. #H.guardZombies .. " elapsed_ms=" .. tostring(current - H.guardStarted)
                .. " max_drift=" .. fmt(H.guardMaxDrift) .. " retreating=" .. retreating .. " early=" .. tostring(H.guardEarly)
                .. " earliest_z=" .. fmt(H.guardEarlyZ) .. " reset_samples=" .. H.guardResets
                .. " reset_settled=" .. tostring(H.guardResetReachedAt ~= nil)
                .. " lowest_health=" .. fmt(lowestHealth) .. " bites=" .. bites
                .. " observer_floor=" .. fmt(observerZ) .. " observer_closest=" .. fmt(H.guardObserverClosest)
            local id = "guard_live_" .. H.guardCase .. "_" .. H.guardTrial
            if not passed then return fail(id, detail) end
            check(id, passed, detail)
            guardCleanup(H)
            H.guardNextAt = current + 3000
            if H.guardStairsOnly then H.guardTrial = H.guardTrial + 1 else H.guardCase = H.guardCase + 1 end
            H.guardFightPhoto = nil
            setPhase("stair_combat_guard_prepare", current)
        end
    end
end

function Probe.step(H, current, check, result, setPhase)
    if H.config.stair_combat_mode == "guard" or H.config.stair_combat_mode == "stairs"
        or H.config.stair_combat_mode == "recovery" then
        return guardStep(H, current, check, result, setPhase)
    end
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "stair_combat_setup" then
        if current - H.phaseStartedAt < 4000 then return end
        if type(addZombiesInOutfit) ~= "function" then
            result("FAIL", "stair_combat_native_spawn", "addZombiesInOutfit unavailable")
            setPhase("finish", current) return
        end
        for _, bystander in ipairs(SC.Registry.living()) do pcall(SC.Actor.remove, bystander) end
        if not check("stair_combat_bystanders_removed", #SC.Registry.living() == 0,
            "remaining=" .. tostring(#SC.Registry.living())) then
            setPhase("finish", current) return
        end
        local px, py = U.position(H.player)
        H.stair = findStair(SC, math.floor(px), math.floor(py), 70)
        if not check("stair_combat_staircase", H.stair ~= nil,
            "near=" .. tostring(math.floor(px)) .. ":" .. tostring(math.floor(py))) then
            setPhase("finish", current) return
        end
        local stair = H.stair
        result("PASS", "stair_combat_staircase_detail",
            "exit=" .. key(stair.exit) .. " first=" .. key(stair.first) .. " last=" .. key(stair.last)
                .. " landing=" .. key(stair.landing) .. " dir=" .. stair.dx .. ":" .. stair.dy
                .. " pieces=" .. tostring(stairPiece(SC, stair.first)) .. "/"
                .. tostring(stairPiece(SC, stair.middle)) .. "/" .. tostring(stairPiece(SC, stair.last))
                .. " stairTop=" .. tostring(call(stair.landing, "HasStairTop"))
                .. " sameStair=" .. tostring(call(stair.first, "isSameStaircase",
                    call(stair.last, "getX"), call(stair.last, "getY"), 0)))
        H.clearZombiesNear(stair.exit, 15)
        H.clearZombiesNear(stair.landing, 15)
        H.stairResults, H.stairTrialIndex = {}, 1
        H.stairTrials = math.max(1, math.min(5, number(H.config.stair_combat_trials, 3)))
        H.stairNextAt = current
        setPhase("stair_combat_prepare", current)
        return
    end
    if H.phase == "stair_combat_prepare" then
        if current < (H.stairNextAt or 0) then return end
        local total = #CASES * H.stairTrials
        if H.stairTrialIndex > total then
            check("stair_combat_results_written", writeResults(H), FILE)
            setPhase("finish", current) return
        end
        local caseIndex = math.floor((H.stairTrialIndex - 1) / H.stairTrials) + 1
        local case = CASES[caseIndex]
        local stair = H.stair
        local actorSquare = case == "top_defender" and stair.landing or stair.exit
        local ticket, reason = SC.Actor.beginSpawn(actorSquare, {
            recruited = true, identity = { forename = "Stair", surname = tostring(H.stairTrialIndex),
                gender = H.stairTrialIndex % 2 == 0 and "woman" or "man", outfit = "Generic01" },
        })
        if not check("stair_combat_actor_spawn_" .. H.stairTrialIndex, ticket ~= nil,
            case .. " at " .. key(actorSquare) .. " reason=" .. tostring(reason)) then
            cleanup(H); setPhase("finish", current) return
        end
        H.stairTicket = ticket
        H.stairTrial = { case = case, row = { case = case,
            trial = (H.stairTrialIndex - 1) % H.stairTrials + 1,
            stair = key(stair.exit) .. ">" .. key(stair.landing) } }
        setPhase("stair_combat_poll_actor", current)
        return
    end
    if H.phase == "stair_combat_poll_actor" then
        local actor, reason = SC.Actor.pollSpawn(H.stairTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                result("FAIL", "stair_combat_actor_spawn", tostring(reason))
                cleanup(H); setPhase("finish", current)
            end
            return
        end
        H.stairActor = actor
        local weapon = call(call(actor, "getInventory"), "AddItem", "Base.Crowbar")
        if weapon then pcall(function() actor:setPrimaryHandItem(weapon) end) end
        pcall(function() actor:getStats():set(CharacterStat.ENDURANCE, 1) end)
        local ordered, orderReason = SC.Commands.issue(SC.Registry.idOf(actor), "stay", nil, H.player)
        local data = call(actor, "getModData")
        local order = type(data) == "table" and data.SC_Order or nil
        if not check("stair_combat_actor_ready_" .. H.stairTrialIndex, weapon ~= nil
            and call(actor, "getPrimaryHandItem") == weapon and ordered == true and order == "stay",
            "order=" .. tostring(orderReason) .. " saved=" .. tostring(order)) then
            cleanup(H); setPhase("finish", current) return
        end
        local stair, top = H.stair, H.stairTrial.case == "top_defender"
        local face = top and stair.first or stair.landing
        pcall(function() actor:faceLocationF(call(face, "getX") + 0.5, call(face, "getY") + 0.5) end)
        local zombieSquare = top and (stair.below or stair.exit) or stair.beyond
        local ok, list = pcall(addZombiesInOutfit, call(zombieSquare, "getX"),
            call(zombieSquare, "getY"), call(zombieSquare, "getZ"), 1, nil, 0)
        local zombie = ok and list and call(list, "get", 0) or nil
        if not check("stair_combat_zombie_spawn_" .. H.stairTrialIndex, zombie ~= nil,
            "at " .. key(zombieSquare)) then
            cleanup(H); setPhase("finish", current) return
        end
        local data = call(zombie, "getModData")
        if type(data) == "table" then data[LIFETIME_KEY] = true end
        H.stairZombie = zombie
        pcall(function() zombie:spotted(actor, true) end)
        if call(zombie, "getTarget") ~= actor then pcall(function() zombie:setTarget(actor) end) end
        local _, _, zz = U.position(zombie)
        H.stairTrial.zombieStartZ = math.floor((zz or 0) + 0.5)
        H.stairTrial.startedAt = current
        H.stairTrial.nextSampleAt = current
        H.stairTrial.actions, H.stairTrial.knockdownAt, H.stairTrial.timeline = {}, {}, {}
        H.stairTrial.zombieHealth = number(call(zombie, "getHealth"), nil)
        H.stairTrial.actorHealth = U.nativeHealth(actor)
        result("PASS", "stair_combat_trial_start_" .. H.stairTrialIndex,
            H.stairTrial.case .. " actor=" .. key(call(actor, "getSquare"))
                .. " zombie=" .. key(zombieSquare)
                .. " targeting=" .. tostring(call(zombie, "getTarget") == actor))
        setPhase("stair_combat_observe", current)
        return
    end
    if H.phase == "stair_combat_observe" then
        local trial = H.stairTrial
        if current < trial.nextSampleAt then return end
        trial.nextSampleAt = current + SAMPLE_MS
        -- Keep the zombie on the companion: the observer is nearby.
        if alive(H.stairZombie) and call(H.stairZombie, "getTarget") ~= H.stairActor then
            pcall(function() H.stairZombie:setTarget(H.stairActor) end)
        end
        return sample(H, current, result, setPhase)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCStairCombatProbe = Probe
return Probe
