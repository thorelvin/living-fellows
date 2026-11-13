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
local function findStair(SC, cx, cy, radius)
    local U, Topology = SC.GameplayUtil, SC.Topology
    local best, bestD2
    for dy = -radius, radius do
        for dx = -radius, radius do
            local tx, ty = cx + dx, cy + dy
            local exit = U.gridSquare(tx, ty, 0)
            if exit and U.isSquareFree(exit) and not Topology.squareHasStairs(exit) then
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
                        and tostring(stairPiece(SC, last)):find("stairsT", 1, true) == 1 then
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

function Probe.step(H, current, check, result, setPhase)
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
        if not check("stair_combat_actor_ready_" .. H.stairTrialIndex, weapon ~= nil
            and call(actor, "getPrimaryHandItem") == weapon and ordered == true,
            "order=" .. tostring(orderReason)) then
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
