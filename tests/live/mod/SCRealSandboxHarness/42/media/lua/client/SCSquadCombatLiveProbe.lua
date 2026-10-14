-- SPDX-License-Identifier: MIT
-- Native squad survival trials. The runner installs this only in a disposable
-- cloned save; all actors and zombies are created and removed inside that clone.
local Probe = {}
local FILE = "SurvivorCompanionHarness/squad-combat-results.txt"
local CASES = { { 3, 6 }, { 5, 10 }, { 5, 12 } }

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end

local function number(value, fallback)
    return tonumber(tostring(value)) or fallback
end

local function alive(actor)
    return actor ~= nil and call(actor, "isDead") == false
        and SurvivorCompanion.GameplayUtil.nativeHealth(actor) > 0
end

local function openSquare(x, y, z)
    local U = SurvivorCompanion.GameplayUtil
    local square = U.gridSquare(x, y, z)
    if not square or not call(square, "getChunk")
        or not U.isSquareFree(square) then return nil end
    local moving = call(square, "getMovingObjects")
    if moving ~= nil and number(call(moving, "size"), 1) > 0 then return nil end
    return square
end

local function survivorSquares(center)
    local result = {}
    local x, y, z = math.floor(center.x), math.floor(center.y),
        math.floor(center.z or 0)
    for _, offset in ipairs({ { 0, 0 }, { -1, 0 }, { 1, 0 },
        { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 },
        { -1, 1 }, { 1, 1 } }) do
        local square = openSquare(x + offset[1], y + offset[2], z)
        if square then result[#result + 1] = square end
    end
    return result
end

local function zombieSquares(center)
    local result, seen = {}, {}
    local x, y, z = math.floor(center.x), math.floor(center.y),
        math.floor(center.z or 0)
    for _, radius in ipairs({ 5, 6, 7, 8 }) do
        for index = 0, 15 do
            local angle = index * math.pi / 8
            local sx = x + math.floor(math.cos(angle) * radius + 0.5)
            local sy = y + math.floor(math.sin(angle) * radius + 0.5)
            local key = tostring(sx) .. ":" .. tostring(sy)
            if not seen[key] then
                seen[key] = true
                local square = openSquare(sx, sy, z)
                if square and call(square, "getRoom") == nil then
                    result[#result + 1] = square
                end
            end
        end
    end
    return result
end

local function removeZombie(zombie)
    if not zombie then return end
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

local function cleanup(H)
    local SC = SurvivorCompanion
    for _, zombie in ipairs(H.squadCombatZombies or {}) do removeZombie(zombie) end
    for _, actor in ipairs(H.squadCombatActors or {}) do
        if alive(actor) then pcall(SC.Actor.remove, actor)
        else pcall(SC.Actor.retireDead, actor) end
    end
    H.squadCombatZombies, H.squadCombatActors = {}, {}
    if H.squadCombatArena then H.clearZombiesNear(H.squadCombatArena, 20) end
end

local function writeResults(H)
    if type(getFileWriter) ~= "function" then return false end
    local writer = getFileWriter(FILE, true, false)
    if not writer then return false end
    writer:writeln("scenario,trial,companions,zombies,survivors,zombie_kills,actions,offensive_actions,elapsed_ms")
    for _, row in ipairs(H.squadCombatResults or {}) do
        writer:writeln(table.concat({ row.scenario, row.trial,
            row.companions, row.zombies, row.survivors, row.kills,
            row.actions, row.offensive, row.elapsed }, ","))
    end
    writer:close()
    return true
end

local function finishTrial(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local survivors, kills = 0, 0
    for _, actor in ipairs(H.squadCombatActors or {}) do
        if alive(actor) then survivors = survivors + 1 end
    end
    for _, zombie in ipairs(H.squadCombatZombies or {}) do
        if call(zombie, "isDead") == true then kills = kills + 1 end
    end
    local team, zombies = H.squadCombatCase[1], H.squadCombatCase[2]
    local elapsed = current - H.squadCombatStartedAt
    local row = { scenario = tostring(team) .. "v" .. tostring(zombies),
        trial = H.squadCombatRepeat, companions = team, zombies = zombies,
        survivors = survivors, kills = kills, actions = H.squadCombatActions or 0,
        offensive = H.squadCombatOffensive or 0, elapsed = elapsed }
    H.squadCombatResults[#H.squadCombatResults + 1] = row
    writeResults(H)
    check("squad_combat_trial_" .. row.scenario .. "_" .. tostring(row.trial),
        row.offensive > 0 and row.actions > 0,
        "survivors=" .. survivors .. "/" .. team .. " kills=" .. kills
            .. "/" .. zombies .. " actions=" .. row.actions
            .. " offensive=" .. row.offensive .. " elapsed_ms=" .. elapsed)
    cleanup(H)
    H.squadCombatRepeat = H.squadCombatRepeat + 1
    if H.squadCombatRepeat > H.squadCombatTrials then
        H.squadCombatCaseIndex = H.squadCombatCaseIndex + 1
        H.squadCombatRepeat = 1
    end
    if H.squadCombatCaseIndex > #CASES then
        for _, case in ipairs(CASES) do
            local scenario = tostring(case[1]) .. "v" .. tostring(case[2])
            local total, surviving, killsTotal = 0, 0, 0
            for _, sample in ipairs(H.squadCombatResults) do
                if sample.scenario == scenario then
                    total = total + sample.companions
                    surviving = surviving + sample.survivors
                    killsTotal = killsTotal + sample.kills
                end
            end
            result("PASS", "squad_combat_survival_" .. scenario,
                "survivors=" .. surviving .. "/" .. total
                    .. " rate=" .. string.format("%.1f", 100 * surviving / total)
                    .. "% zombie_kills=" .. killsTotal
                    .. " trials=" .. H.squadCombatTrials)
        end
        check("squad_combat_results_written", writeResults(H), FILE)
        setPhase("finish", current)
    else
        H.squadCombatNextAt = current + 1500
        setPhase("squad_combat_prepare", current)
    end
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    if H.phase == "squad_combat_setup" then
        if current - H.phaseStartedAt < 4000 then return end
        if type(addZombiesInOutfit) ~= "function" then
            result("FAIL", "squad_combat_native_spawn", "addZombiesInOutfit unavailable")
            setPhase("finish", current) return
        end
        H.squadCombatArena = H.findCombatArena(H.player)
        if not check("squad_combat_arena", H.squadCombatArena ~= nil,
            "loaded outdoor combat arena away from observer") then
            setPhase("finish", current) return
        end
        H.squadCombatResults, H.squadCombatCaseIndex = {}, 1
        H.squadCombatRepeat = 1
        H.squadCombatTrials = number(H.config.squad_combat_trials, 3)
        H.squadCombatSeconds = number(H.config.squad_combat_seconds, 55)
        H.squadCombatActors, H.squadCombatZombies = {}, {}
        H.clearZombiesNear(H.squadCombatArena, 20)
        setPhase("squad_combat_prepare", current)
        return
    end
    if H.phase == "squad_combat_prepare" then
        if current < (H.squadCombatNextAt or 0) then return end
        H.clearZombiesNear(H.squadCombatArena, 20)
        H.squadCombatCase = CASES[H.squadCombatCaseIndex]
        H.squadCombatSurvivorSquares = survivorSquares(H.squadCombatArena)
        H.squadCombatZombieSquares = zombieSquares(H.squadCombatArena)
        local enough = #H.squadCombatSurvivorSquares >= H.squadCombatCase[1]
            and #H.squadCombatZombieSquares >= H.squadCombatCase[2]
        if not check("squad_combat_fixture_" .. H.squadCombatCaseIndex
            .. "_" .. H.squadCombatRepeat, enough,
            "survivor_tiles=" .. #H.squadCombatSurvivorSquares
                .. " zombie_tiles=" .. #H.squadCombatZombieSquares) then
            setPhase("finish", current) return
        end
        H.squadCombatActors, H.squadCombatZombies = {}, {}
        H.squadCombatSpawnIndex = 1
        setPhase("squad_combat_spawn_actor", current)
        return
    end
    if H.phase == "squad_combat_spawn_actor" then
        local index = H.squadCombatSpawnIndex
        local square = H.squadCombatSurvivorSquares[index]
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true, identity = { forename = "Trial",
                surname = tostring(H.squadCombatCaseIndex) .. "_"
                    .. tostring(H.squadCombatRepeat) .. "_" .. tostring(index),
                gender = index % 2 == 0 and "woman" or "man",
                outfit = "Generic01" },
        })
        if not ticket then
            result("FAIL", "squad_combat_actor_spawn", tostring(reason))
            cleanup(H); setPhase("finish", current) return
        end
        H.squadCombatTicket = ticket
        setPhase("squad_combat_poll_actor", current)
        return
    end
    if H.phase == "squad_combat_poll_actor" then
        local actor, reason = SC.Actor.pollSpawn(H.squadCombatTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                result("FAIL", "squad_combat_actor_spawn", tostring(reason))
                cleanup(H); setPhase("finish", current)
            end
            return
        end
        local weapon = call(call(actor, "getInventory"), "AddItem", "Base.Crowbar")
        if weapon then pcall(function() actor:setPrimaryHandItem(weapon) end) end
        local id = SC.Registry.idOf(actor)
        local ordered, orderReason = SC.Commands.issue(id, "stay", nil, H.player)
        if not check("squad_combat_actor_ready", weapon ~= nil
            and call(actor, "getPrimaryHandItem") == weapon
            and ordered == true,
            "index=" .. H.squadCombatSpawnIndex
                .. " order=" .. tostring(orderReason)) then
            H.squadCombatActors[#H.squadCombatActors + 1] = actor
            cleanup(H); setPhase("finish", current) return
        end
        H.squadCombatActors[#H.squadCombatActors + 1] = actor
        H.squadCombatSpawnIndex = H.squadCombatSpawnIndex + 1
        if H.squadCombatSpawnIndex <= H.squadCombatCase[1] then
            setPhase("squad_combat_spawn_actor", current)
        else setPhase("squad_combat_spawn_zombies", current) end
        return
    end
    if H.phase == "squad_combat_spawn_zombies" then
        local count = H.squadCombatCase[2]
        for index = 1, count do
            local square = H.squadCombatZombieSquares[index]
            local ok, list = pcall(addZombiesInOutfit,
                square:getX(), square:getY(), square:getZ(), 1, nil, 0)
            local zombie = ok and list and call(list, "get", 0) or nil
            if not zombie then
                result("FAIL", "squad_combat_zombie_spawn",
                    "index=" .. index .. " count=" .. #H.squadCombatZombies)
                cleanup(H); setPhase("finish", current) return
            end
            H.squadCombatZombies[#H.squadCombatZombies + 1] = zombie
            local target = H.squadCombatActors[(index - 1)
                % #H.squadCombatActors + 1]
            pcall(function() zombie:setTarget(target) end)
        end
        H.squadCombatStartedAt = current
        H.squadCombatActions, H.squadCombatOffensive = 0, 0
        H.squadCombatActionAt = setmetatable({}, { __mode = "k" })
        setPhase("squad_combat_observe", current)
        return
    end
    if H.phase == "squad_combat_observe" then
        local survivors, deadZombies = 0, 0
        for _, actor in ipairs(H.squadCombatActors) do
            if alive(actor) then survivors = survivors + 1 end
            local state = SC.Combat.peek(actor)
            if state and number(state.lastActionAt, 0)
                > (H.squadCombatActionAt[actor] or 0) then
                H.squadCombatActionAt[actor] = state.lastActionAt
                H.squadCombatActions = H.squadCombatActions + 1
                if state.lastAction == "melee" or state.lastAction == "shove"
                    or state.lastAction == "stomp" or state.lastAction == "shoot" then
                    H.squadCombatOffensive = H.squadCombatOffensive + 1
                end
            end
        end
        for _, zombie in ipairs(H.squadCombatZombies) do
            if call(zombie, "isDead") == true then deadZombies = deadZombies + 1 end
        end
        local elapsed = current - H.squadCombatStartedAt
        if elapsed >= H.squadCombatSeconds * 1000
            or (elapsed >= 5000 and (survivors == 0
                or deadZombies == H.squadCombatCase[2])) then
            finishTrial(H, current, check, result, setPhase)
        end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCSquadCombatLiveProbe = Probe
return Probe
