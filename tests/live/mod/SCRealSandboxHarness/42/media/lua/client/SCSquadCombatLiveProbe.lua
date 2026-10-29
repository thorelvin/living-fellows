-- SPDX-License-Identifier: MIT
-- Native squad survival trials. The runner installs this only in a disposable
-- cloned save; all actors and zombies are created and removed inside that clone.
local Probe = {}
local FILE = "SurvivorCompanionHarness/squad-combat-results.txt"
local RING_CASES = { { 3, 6 }, { 5, 10 }, { 5, 12 } }
local FRONT_CASES = { { 3, 6, "front" }, { 5, 10, "front" },
    { 1, 2, "front" }, { 1, 3, "front" }, { 1, 1, "front" },
    { 1, 3, "staggered" } }

function Probe.cases(config)
    local companions=tonumber(config.squad_combat_custom_companions) or 0
    local raw=tostring(config.squad_combat_custom_zombies or "")
    if companions==0 and raw=="" then
        return config.squad_combat_front_only=="true" and FRONT_CASES or RING_CASES
    end
    if companions<1 or companions>5 or companions~=math.floor(companions) then return nil,"invalid_companion_count" end
    local cases={}
    for token in raw:gmatch("[^,]+") do
        local zombies=tonumber(token)
        if not zombies or zombies<1 or zombies>16 or zombies~=math.floor(zombies) or #cases>=6 then
            return nil,"invalid_zombie_counts"
        end
        cases[#cases+1]={companions,zombies,config.squad_combat_front_only=="true" and "front" or nil}
    end
    if #cases==0 then return nil,"missing_zombie_counts" end
    return cases
end

local function caseName(case)
    return tostring(case[1]) .. "v" .. tostring(case[2])
        .. (case[3] and "_" .. case[3] or "")
end

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

local function frontZombieSquares(center)
    local best, bestDirection = {}, nil
    local x, y, z = math.floor(center.x), math.floor(center.y),
        math.floor(center.z or 0)
    for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
        { 0, 1 }, { 0, -1 } }) do
        local candidates = {}
        for depth = 5, 8 do
            for _, lateral in ipairs({ 0, -1, 1, -2, 2 }) do
                local sx = x + direction[1] * depth - direction[2] * lateral
                local sy = y + direction[2] * depth + direction[1] * lateral
                local candidate = openSquare(sx, sy, z)
                if candidate and call(candidate, "getRoom") == nil then
                    candidates[#candidates + 1] = candidate
                end
            end
        end
        if #candidates > #best then
            best, bestDirection = candidates, direction
        end
    end
    return best, bestDirection
end

local function staggeredZombieSquares(center)
    local U = SurvivorCompanion.GameplayUtil
    local x, y, z = math.floor(center.x), math.floor(center.y),
        math.floor(center.z or 0)
    local bestDirection, bestScore = nil, -1
    for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
        { 0, 1 }, { 0, -1 } }) do
        local function corridor(sign, limit)
            local previous = openSquare(x, y, z)
            if not previous then return 0 end
            local length = 0
            for depth = 1, limit do
                local square = openSquare(x + direction[1] * depth * sign,
                    y + direction[2] * depth * sign, z)
                if not square or call(square, "getRoom") ~= nil
                    or U.edgeBlocked(previous, square) then break end
                length, previous = depth, square
            end
            return length
        end
        local forward, backward = corridor(1, 18), corridor(-1, 10)
        local score = forward + backward * 0.5
        if forward >= 9 and backward >= 5 and score > bestScore then
            bestDirection, bestScore = direction, score
        end
    end
    if not bestDirection then return {}, nil end
    local squares = {}
    for _, depth in ipairs({ 5, 7, 9 }) do
        local square = openSquare(x + bestDirection[1] * depth,
            y + bestDirection[2] * depth, z)
        if square and call(square, "getRoom") == nil then
            squares[#squares + 1] = square
        end
    end
    return squares, bestDirection
end

local function corpsesNear(center, radius)
    local U = SurvivorCompanion.GameplayUtil
    local bodies = {}
    local x, y, z = math.floor(center.x), math.floor(center.y),
        math.floor(center.z or 0)
    for sx = x - radius, x + radius do
        for sy = y - radius, y + radius do
            local square = U.gridSquare(sx, sy, z)
            U.squareStaticMovingObjects(square, function(object)
                if U.instanceOf(object, "IsoDeadBody")
                    and call(object, "isPlayer") ~= true then
                    bodies[#bodies + 1] = object
                end
            end, 16)
        end
    end
    return bodies
end

local function clearCorpsesNear(center, radius)
    local removed = 0
    for _, body in ipairs(corpsesNear(center, radius)) do
        local ok = pcall(function()
            body:removeFromWorld()
            body:removeFromSquare()
        end)
        if ok then removed = removed + 1 end
    end
    return removed
end

-- The shared harness only needs a clear 5x5 spawn patch. Combat also needs
-- room for the approaching ring and for companions to retreat without a
-- nearby wall or fence steering the entire trial back into the base.
local function findOpenCombatArena(player)
    local U = SurvivorCompanion.GameplayUtil
    local px, py, pz = U.position(player)
    if not px or not py then return nil, 0 end
    local z = math.floor(pz or 0)
    local best, bestScore, bestPaved = nil, -math.huge, 0
    local function consider(x, y)
        local center = { x = x + 0.5, y = y + 0.5, z = z }
        local insideBase = SurvivorCompanion.BaseLife
            and type(SurvivorCompanion.BaseLife.isInside) == "function"
            and SurvivorCompanion.BaseLife.isInside(center) == true
        if insideBase then return end
        local score, paved, clearCenter = 0, 0, true
        for dx = -8, 8 do
            for dy = -8, 8 do
                local square = openSquare(x + dx, y + dy, z)
                local clear = square and call(square, "getRoom") == nil
                if clear and dx > -8 then
                    local west = U.gridSquare(x + dx - 1, y + dy, z)
                    if west and U.edgeBlocked(square, west) then clear = false end
                end
                if clear and dy > -8 then
                    local north = U.gridSquare(x + dx, y + dy - 1, z)
                    if north and U.edgeBlocked(square, north) then clear = false end
                end
                if clear then
                    score = score + 1
                    local sprite = call(call(call(square, "getFloor"),
                        "getSprite"), "getName")
                    if type(sprite) == "string" and string.find(
                        sprite, "blends_street_", 1, true) then
                        paved = paved + 1
                    end
                end
                if math.abs(dx) <= 2 and math.abs(dy) <= 2
                    and not clear then clearCenter = false end
            end
        end
        local centerFloor = call(call(call(openSquare(x, y, z),
            "getFloor"), "getSprite"), "getName")
        local centerPaved = type(centerFloor) == "string"
            and string.find(centerFloor, "blends_street_", 1, true)
        local weighted = score + paved * 2
        if clearCenter and centerPaved and paved >= 120
            and weighted > bestScore then
            best, bestScore, bestPaved = center, weighted, paved
        end
    end
    for _, radius in ipairs({ 16, 20, 24, 28 }) do
        for _, direction in ipairs({ { 1, 0 }, { -1, 0 },
            { 0, 1 }, { 0, -1 }, { 1, 1 }, { -1, 1 },
            { 1, -1 }, { -1, -1 } }) do
            local x = math.floor(px + direction[1] * radius)
            local y = math.floor(py + direction[2] * radius)
            consider(x, y)
        end
    end
    -- Coarse directional samples find the lot. Search around the best sample
    -- so the actual spawn is in the asphalt interior, clear of planted islands.
    if best then
        local coarseX, coarseY = math.floor(best.x), math.floor(best.y)
        for dx = -12, 12, 3 do
            for dy = -12, 12, 3 do
                consider(coarseX + dx, coarseY + dy)
            end
        end
        local fineX, fineY = math.floor(best.x), math.floor(best.y)
        for dx = -2, 2 do
            for dy = -2, 2 do
                consider(fineX + dx, fineY + dy)
            end
        end
    end
    return best, bestScore, bestPaved
end

local function removeZombie(zombie)
    if not zombie then return end
    pcall(function() zombie:setTarget(nil) end)
    pcall(function() zombie:removeFromWorld() end)
    pcall(function() zombie:removeFromSquare() end)
end

-- A naked setTarget gives the harness a readable target pointer, but does not
-- exercise the game's sighting path that starts pursuit. Use the same native
-- spotted entry point as production targeting, then fall back only if this
-- particular zombie did not accept the forced sighting.
local function targetZombie(H, zombie, actor)
    H.squadCombatSpottedAttempts = (H.squadCombatSpottedAttempts or 0) + 1
    pcall(function() zombie:spotted(actor, true) end)
    if call(zombie, "getTarget") == actor then
        H.squadCombatSpottedSuccesses =
            (H.squadCombatSpottedSuccesses or 0) + 1
        return true
    end
    H.squadCombatSetTargetFallbacks =
        (H.squadCombatSetTargetFallbacks or 0) + 1
    pcall(function() zombie:setTarget(actor) end)
    return call(zombie, "getTarget") == actor
end

local function cleanup(H)
    local SC = SurvivorCompanion
    if H.squadCombatPhotoOriginal and H.player then
        local original = H.squadCombatPhotoOriginal
        pcall(function()
            H.player:teleportTo(original.x, original.y, original.z)
            H.player:setGhostMode(original.ghost)
        end)
        H.squadCombatPhotoOriginal = nil
    end
    for _, zombie in ipairs(H.squadCombatZombies or {}) do removeZombie(zombie) end
    for _, actor in ipairs(H.squadCombatActors or {}) do
        if alive(actor) then pcall(SC.Actor.remove, actor)
        else pcall(SC.Actor.retireDead, actor) end
    end
    H.squadCombatZombies, H.squadCombatActors = {}, {}
    H.squadCombatLureRadio = nil
    if H.squadCombatArena then H.clearZombiesNear(H.squadCombatArena, 20) end
end

local function writeResults(H)
    if type(getFileWriter) ~= "function" then return false end
    local writer = getFileWriter(FILE, true, false)
    if not writer then return false end
    writer:writeln("scenario,trial,companions,zombies,survivors,lowest_companion_health,zombie_kills,corpses_near_arena,actions,offensive_actions,elapsed_ms,engaged_zombies,zombie_damage,zombies_targeting_squad,zombies_targeting_player,zombies_near_squad,zombies_with_square,retarget_attempts,melee_actions,shove_actions,retreat_actions,anticipatory_actions,melee_landed,melee_no_effect,early_landed,early_no_effect,closing_wait_actions,closing_backpedal_actions,post_swing_backstep_actions,target_samples,target_valid_samples,target_nil_samples,target_player_samples,target_other_samples,target_valid_after_retarget_samples,retarget_successes,wounded_zombies,lowest_living_health_ratio,action_histogram,spotted_attempts,spotted_successes,set_target_fallbacks,early_hit_damage,regular_hit_damage,sampled_health_loss,sampled_health_gain,lowest_seen_health_ratio,health_gain_after_five_seconds,eating_samples,target_visible_samples,target_seen_time_max,zombie_health_and_hits,distance_timeline,final_positions,hit_timeline,health_change_timeline")
    for _, row in ipairs(H.squadCombatResults or {}) do
        writer:writeln(table.concat({ row.scenario, row.trial,
            row.companions, row.zombies, row.survivors,
            row.lowestCompanionHealth, row.kills, row.corpsesNearArena,
            row.actions, row.offensive, row.elapsed, row.engaged,
            row.damage, row.zombiesTargeting, row.zombiesTargetingPlayer,
            row.zombiesNear, row.zombiesWithSquare, row.retargetAttempts,
            row.melee, row.shove, row.retreat,
            row.anticipatory, row.meleeLanded, row.meleeNoEffect,
            row.earlyLanded, row.earlyNoEffect,
            row.closingWait, row.closingBackpedal,
            row.postSwingBackstep, row.targetSamples, row.targetValidSamples,
            row.targetNilSamples, row.targetPlayerSamples, row.targetOtherSamples,
            row.targetValidAfterRetargetSamples, row.retargetSuccesses,
            row.woundedZombies, row.lowestLivingHealthRatio,
            row.actionHistogram, row.spottedAttempts,
            row.spottedSuccesses, row.setTargetFallbacks,
            row.earlyHitDamage, row.regularHitDamage,
            row.sampledHealthLoss, row.sampledHealthGain,
            row.lowestSeenHealthRatio, row.lateHealthGain,
            row.eatingSamples, row.targetVisibleSamples,
            row.targetSeenTimeMax,
            row.zombieHealthAndHits, row.distanceTimeline,
            row.finalPositions, row.hitTimeline,
            row.healthChangeTimeline }, ","))
    end
    writer:close()
    return true
end

local function finishTrial(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local survivors, kills, engaged, damage = 0, 0, 0, 0
    local lowestCompanionHealth = 100
    local woundedZombies, lowestLivingHealthRatio = 0, 1
    local zombiesTargeting, zombiesTargetingPlayer, zombiesNear, zombiesWithSquare =
        0, 0, 0, 0
    for _, actor in ipairs(H.squadCombatActors or {}) do
        if alive(actor) then survivors = survivors + 1 end
        lowestCompanionHealth = math.min(lowestCompanionHealth,
            number(SC.GameplayUtil.nativeHealth(actor), 0))
    end
    local zombieDetails = {}
    local finalPositions = {}
    for index, actor in ipairs(H.squadCombatActors or {}) do
        local x, y = SC.GameplayUtil.position(actor)
        finalPositions[#finalPositions + 1] = string.format("a%d:%.1f:%.1f",
            index, number(x, -1), number(y, -1))
    end
    for index, zombie in ipairs(H.squadCombatZombies or {}) do
        local zx, zy = SC.GameplayUtil.position(zombie)
        finalPositions[#finalPositions + 1] = string.format("z%d:%.1f:%.1f",
            index, number(zx, -1), number(zy, -1))
        if call(zombie, "isDead") == true then kills = kills + 1 end
        if H.squadCombatEngaged[zombie] == true then engaged = engaged + 1 end
        local initial = H.squadCombatInitialHealth[zombie]
        local final = number(call(zombie, "getHealth"), nil)
        zombieDetails[#zombieDetails + 1] = string.format("%d:%.2f:%.2f:%.2f:%d:%s",
            index, H.squadCombatInitialHealth[zombie] or -1,
            H.squadCombatSettledHealth[zombie] or -1,
            final or -1, H.squadCombatHitsByZombie[zombie] or 0,
            tostring(call(zombie, "isOnFloor") == true))
        local dead = call(zombie, "isDead") == true
        if initial and (dead or final and final > 0) then
            damage = damage + math.max(0, initial - (dead and 0 or final))
            if not dead and final and final < initial - 0.001 then
                woundedZombies = woundedZombies + 1
                lowestLivingHealthRatio = math.min(lowestLivingHealthRatio,
                    final / math.max(initial, 0.001))
            end
        end
        local target = call(zombie, "getTarget")
        if target == H.player then
            zombiesTargetingPlayer = zombiesTargetingPlayer + 1
        end
        if call(zombie, "getSquare") ~= nil then
            zombiesWithSquare = zombiesWithSquare + 1
        end
        for _, actor in ipairs(H.squadCombatActors or {}) do
            if target == actor then zombiesTargeting = zombiesTargeting + 1; break end
        end
        for _, actor in ipairs(H.squadCombatActors or {}) do
            if alive(actor) and SC.GameplayUtil.distanceSq(actor, zombie) <= 25 then
                zombiesNear = zombiesNear + 1; break
            end
        end
    end
    local team, zombies = H.squadCombatCase[1], H.squadCombatCase[2]
    -- A killed IsoZombie may be returned to the engine's population pool and
    -- reused before this trial ends. Its later isDead/health/position readings
    -- no longer describe the corpse the fighter made. The arena was cleared
    -- before spawning, so count the actual new IsoDeadBody objects instead.
    local corpseCount = #corpsesNear(H.squadCombatArena, 20)
    kills = math.min(zombies, math.max(kills, corpseCount))
    local elapsed = current - H.squadCombatStartedAt
    local actionKinds = {}
    for kind, count in pairs(H.squadCombatActionKinds or {}) do
        actionKinds[#actionKinds + 1] = { kind = kind, count = count }
    end
    table.sort(actionKinds, function(a, b)
        if a.count == b.count then return a.kind < b.kind end
        return a.count > b.count
    end)
    local actionHistogram = {}
    for _, entry in ipairs(actionKinds) do
        actionHistogram[#actionHistogram + 1] = entry.kind .. ":" .. entry.count
    end
    local row = { scenario = caseName(H.squadCombatCase),
        trial = H.squadCombatRepeat, companions = team, zombies = zombies,
        survivors = survivors, kills = kills, corpsesNearArena = corpseCount,
        actions = H.squadCombatActions or 0,
        lowestCompanionHealth = string.format("%.1f", lowestCompanionHealth),
        offensive = H.squadCombatOffensive or 0, elapsed = elapsed,
        engaged = engaged, damage = string.format("%.2f", damage),
        zombiesTargeting = zombiesTargeting,
        zombiesTargetingPlayer = zombiesTargetingPlayer,
        zombiesNear = zombiesNear, zombiesWithSquare = zombiesWithSquare,
        retargetAttempts = H.squadCombatRetargetAttempts or 0,
        targetSamples = H.squadCombatTargetSamples or 0,
        targetValidSamples = H.squadCombatTargetValidSamples or 0,
        targetNilSamples = H.squadCombatTargetNilSamples or 0,
        targetPlayerSamples = H.squadCombatTargetPlayerSamples or 0,
        targetOtherSamples = H.squadCombatTargetOtherSamples or 0,
        targetValidAfterRetargetSamples =
            H.squadCombatTargetValidAfterRetargetSamples or 0,
        retargetSuccesses = H.squadCombatRetargetSuccesses or 0,
        woundedZombies = woundedZombies,
        lowestLivingHealthRatio = string.format("%.3f", lowestLivingHealthRatio),
        actionHistogram = table.concat(actionHistogram, "|"),
        spottedAttempts = H.squadCombatSpottedAttempts or 0,
        spottedSuccesses = H.squadCombatSpottedSuccesses or 0,
        setTargetFallbacks = H.squadCombatSetTargetFallbacks or 0,
        earlyHitDamage = string.format("%.3f", H.squadCombatEarlyHitDamage or 0),
        regularHitDamage = string.format("%.3f", H.squadCombatRegularHitDamage or 0),
        sampledHealthLoss = string.format("%.3f", H.squadCombatSampledHealthLoss or 0),
        sampledHealthGain = string.format("%.3f", H.squadCombatSampledHealthGain or 0),
        lowestSeenHealthRatio = string.format("%.3f",
            H.squadCombatLowestSeenHealthRatio or 1),
        lateHealthGain = string.format("%.3f", H.squadCombatLateHealthGain or 0),
        eatingSamples = H.squadCombatEatingSamples or 0,
        targetVisibleSamples = H.squadCombatTargetVisibleSamples or 0,
        targetSeenTimeMax = string.format("%.2f",
            H.squadCombatTargetSeenTimeMax or 0),
        zombieHealthAndHits = table.concat(zombieDetails, "|"),
        distanceTimeline = table.concat(H.squadCombatDistanceTimeline or {}, "|"),
        finalPositions = table.concat(finalPositions, "|"),
        hitTimeline = table.concat(H.squadCombatHitTimeline or {}, "|"),
        healthChangeTimeline = table.concat(
            H.squadCombatHealthChangeTimeline or {}, "|"),
        melee = H.squadCombatMelee or 0, shove = H.squadCombatShove or 0,
        retreat = H.squadCombatRetreat or 0,
        anticipatory = H.squadCombatAnticipatory or 0,
        meleeLanded = H.squadCombatMeleeLanded or 0,
        meleeNoEffect = H.squadCombatMeleeNoEffect or 0,
        earlyLanded = H.squadCombatEarlyLanded or 0,
        earlyNoEffect = H.squadCombatEarlyNoEffect or 0,
        closingWait = H.squadCombatClosingWait or 0,
        closingBackpedal = H.squadCombatClosingBackpedal or 0,
        postSwingBackstep = H.squadCombatPostSwingBackstep or 0 }
    H.squadCombatResults[#H.squadCombatResults + 1] = row
    writeResults(H)
    local incomingWounds=0
    for _,actor in ipairs(H.squadCombatActors) do
        local body=call(actor,"getBodyDamage")
        incomingWounds=incomingWounds+number(call(body,"getNumPartsBitten"),0)
            +number(call(body,"getNumPartsScratched"),0)+number(call(body,"getNumPartsBleeding"),0)
    end
    local passive=H.config.squad_combat_passive_control=="true"
    local measured=passive and (incomingWounds>0 or tonumber(row.lowestCompanionHealth)<100)
        or not passive and row.offensive>0 and row.actions>0
    check("squad_combat_trial_" .. row.scenario .. "_" .. tostring(row.trial),
        measured,
        "survivors=" .. survivors .. "/" .. team
            .. " lowest_health=" .. row.lowestCompanionHealth
            .. " kills=" .. kills
            .. "/" .. zombies .. " actions=" .. row.actions
            .. " offensive=" .. row.offensive .. " engaged=" .. engaged
            .. " damage=" .. row.damage .. " retreat=" .. row.retreat
            .. " passive="..tostring(passive).." incoming_wounds="..incomingWounds
            .. " elapsed_ms=" .. elapsed)
    result("PASS", "squad_combat_late_bystanders_removed",
        "count=" .. tostring(H.squadCombatLateBystandersRemoved or 0))
    if H.config.squad_combat_radio_lure == "true" then
        check("squad_combat_radio_sounds_emitted",
            (H.squadCombatRadioSoundCount or 0) > 0,
            "count=" .. tostring(H.squadCombatRadioSoundCount or 0))
    end
    if H.config.squad_combat_backup_weapon_type
        and H.config.squad_combat_backup_weapon_type ~= "" then
        check("squad_combat_backup_added_after_break",
            H.squadCombatBackupInjected[1] ~= nil,
            "original=" .. tostring(H.squadCombatPrimaryWeapons[1] ~= nil))
        check("squad_combat_backup_drawn",
            H.squadCombatBackupEquipped[1] == true,
            "type=" .. tostring(H.config.squad_combat_backup_weapon_type))
    end
    cleanup(H)
    H.squadCombatRepeat = H.squadCombatRepeat + 1
    if H.squadCombatRepeat > H.squadCombatTrials then
        H.squadCombatCaseIndex = H.squadCombatCaseIndex + 1
        H.squadCombatRepeat = 1
    end
    if H.squadCombatCaseIndex > #H.squadCombatCases then
        for _, case in ipairs(H.squadCombatCases) do
            local scenario = caseName(case)
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
        if H.config.squad_combat_multihit ~= nil
            and H.config.squad_combat_multihit ~= "inherit" then
            local expected = H.config.squad_combat_multihit == "on"
            local ok, actual = pcall(function()
                local options = getSandboxOptions()
                options:set("MultiHitZombies", expected)
                return options:getOptionByName("MultiHitZombies"):getValue()
            end)
            if not check("squad_combat_multihit", ok and actual == expected,
                "expected=" .. tostring(expected) .. " actual=" .. tostring(actual)) then
                setPhase("finish", current) return
            end
        end
        if type(addZombiesInOutfit) ~= "function" then
            result("FAIL", "squad_combat_native_spawn", "addZombiesInOutfit unavailable")
            setPhase("finish", current) return
        end
        -- The cloned seed save contains recruited followers. A ghost camera
        -- brought near the arena would otherwise call them into this purported
        -- one-fighter trial and pull zombies away from its actual participant.
        local removed = 0
        for _, bystander in ipairs(SC.Registry.living()) do
            local ok, done = pcall(SC.Actor.remove, bystander)
            if ok and done ~= false then removed = removed + 1 end
        end
        if not check("squad_combat_bystanders_removed",
            #SC.Registry.living() == 0,
            "removed=" .. tostring(removed)
                .. " remaining=" .. tostring(#SC.Registry.living())) then
            setPhase("finish", current) return
        end
        local arenaScore, pavedTiles
        H.squadCombatArena, arenaScore, pavedTiles =
            findOpenCombatArena(H.player)
        if not check("squad_combat_arena", H.squadCombatArena ~= nil,
            "loaded outdoor combat arena away from observer"
                .. " score=" .. tostring(arenaScore)
                .. " paved=" .. tostring(pavedTiles)
                .. " x=" .. tostring(H.squadCombatArena and H.squadCombatArena.x)
                .. " y=" .. tostring(H.squadCombatArena and H.squadCombatArena.y)) then
            setPhase("finish", current) return
        end
        result("PASS", "squad_combat_clone_corpses_cleared",
            "removed=" .. tostring(clearCorpsesNear(H.squadCombatArena, 20)))
        H.squadCombatResults, H.squadCombatCaseIndex = {}, 1
        local casePool,caseReason=Probe.cases(H.config)
        if not check("squad_combat_cases",casePool~=nil,caseReason or "validated fixture cases") then
            setPhase("finish",current) return
        end
        local requestedCase = math.min(#casePool, math.max(1,
            math.floor(number(H.config.squad_combat_case_index, 1))))
        H.squadCombatCases = (H.config.squad_combat_photo == "true"
            or H.config.squad_combat_single_case == "true")
                and { casePool[requestedCase] } or casePool
        H.squadCombatRepeat = 1
        H.squadCombatTrials = number(H.config.squad_combat_trials, 3)
        H.squadCombatSeconds = number(H.config.squad_combat_seconds, 55)
        H.squadCombatActors, H.squadCombatZombies = {}, {}
        H.squadCombatPrimaryWeapons = {}
        H.squadCombatBackupInjected = {}
        H.squadCombatBackupEquipped = {}
        H.squadCombatBackupDiagnosed = nil
        H.clearZombiesNear(H.squadCombatArena, 20)
        setPhase("squad_combat_prepare", current)
        return
    end
    if H.phase == "squad_combat_prepare" then
        if current < (H.squadCombatNextAt or 0) then return end
        H.clearZombiesNear(H.squadCombatArena, 20)
        H.squadCombatCase = H.squadCombatCases[H.squadCombatCaseIndex]
        H.squadCombatSurvivorSquares = survivorSquares(H.squadCombatArena)
        if H.squadCombatCase[3] == "staggered" then
            H.squadCombatZombieSquares, H.squadCombatFrontDirection =
                staggeredZombieSquares(H.squadCombatArena)
        elseif H.squadCombatCase[3] == "front" then
            H.squadCombatZombieSquares, H.squadCombatFrontDirection =
                frontZombieSquares(H.squadCombatArena)
        else
            H.squadCombatZombieSquares = zombieSquares(H.squadCombatArena)
            H.squadCombatFrontDirection = nil
        end
        if H.squadCombatFrontDirection then
            result("PASS", "squad_combat_approach_lane",
                "dx=" .. tostring(H.squadCombatFrontDirection[1])
                    .. " dy=" .. tostring(H.squadCombatFrontDirection[2]))
        end
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
        local weaponType = H.config.squad_combat_weapon_type or "Base.Crowbar"
        local weapons = {}
        for name in tostring(H.config.squad_combat_weapon_types or ""):gmatch("[^,]+") do
            weapons[#weapons + 1] = name
        end
        if #weapons > 0 then
            weaponType = weapons[(H.squadCombatSpawnIndex - 1) % #weapons + 1]
        end
        local weapon = call(call(actor, "getInventory"), "AddItem", weaponType)
        if weapon then pcall(function() actor:setPrimaryHandItem(weapon) end) end
        local fatigue = number(H.config.squad_combat_fatigue, 0)
        local statOk = pcall(function() actor:getStats():set(CharacterStat.FATIGUE, fatigue) end)
        local actualFatigue = U.characterStatValue(actor, "FATIGUE", -1)
        if not check("squad_combat_fatigue", statOk and math.abs(actualFatigue - fatigue) < 0.001,
            "actor=" .. tostring(H.squadCombatSpawnIndex) .. " fatigue=" .. tostring(actualFatigue)) then
            H.squadCombatActors[#H.squadCombatActors + 1] = actor
            cleanup(H); setPhase("finish", current) return
        end
        H.squadCombatPrimaryWeapons[H.squadCombatSpawnIndex] = weapon
        if H.config.squad_combat_radio_lure == "true" then
            local inventory = call(actor, "getInventory")
            local radio = call(inventory, "AddItem", "Base.WalkieTalkie5")
            local device = radio and call(radio, "getDeviceData")
            local radioReady = radio ~= nil and device ~= nil
            if radioReady then
                pcall(function()
                    if not device:getHasBattery() then
                        local battery = inventory:AddItem("Base.Battery")
                        if battery then device:addBattery(battery) end
                    end
                    device:setDeviceVolume(1.0)
                    device:setIsTurnedOn(true)
                end)
                radioReady = call(device, "getIsTurnedOn") == true
                    and call(device, "getDeviceVolume") == 1.0
            end
            if not check("squad_combat_loud_walkie_ready", radioReady,
                "actor=" .. tostring(H.squadCombatSpawnIndex)
                    .. " carried_radio=Base.WalkieTalkie5") then
                H.squadCombatActors[#H.squadCombatActors + 1] = actor
                cleanup(H); setPhase("finish", current) return
            end
            H.squadCombatLureRadio = radio
        end
        local minimum, maximum
        if weapon then minimum, maximum = SC.Combat.meleeRange(actor, weapon) end
        local id = SC.Registry.idOf(actor)
        local ordered, orderReason = SC.Commands.issue(id, "stay", nil, H.player)
        if not check("squad_combat_actor_ready", weapon ~= nil
            and call(actor, "getPrimaryHandItem") == weapon
            and ordered == true,
            "index=" .. H.squadCombatSpawnIndex
                .. " order=" .. tostring(orderReason)
                .. " weapon=" .. tostring(weaponType)
                .. " reach=" .. tostring(maximum)
                .. " minimum=" .. tostring(minimum)) then
            H.squadCombatActors[#H.squadCombatActors + 1] = actor
            cleanup(H); setPhase("finish", current) return
        end
        H.squadCombatActors[#H.squadCombatActors + 1] = actor
        if H.config.squad_combat_passive_control=="true" then
            local supervisor=SC.ActionSupervisor
            supervisor.cancel(actor,"incoming_attack_control",nil,true)
            local held,holdReason=supervisor.begin(actor,{owner="live_harness",action="incoming_attack_control",
                priority=supervisor.Priority.EXTERNAL,phase="approaching",interruptible=false,ignoreRetry=true,
                deadlines={approaching=H.squadCombatSeconds*1000+15000},allowedMovementPhases={approaching=true}})
            if not check("incoming_attack_control",held~=nil,tostring(holdReason)) then
                cleanup(H) setPhase("finish",current) return
            end
            pcall(SC.Actor.stop,actor)
        end
        if H.squadCombatFrontDirection then
            local direction = H.squadCombatFrontDirection
            pcall(function() actor:faceLocationF(
                H.squadCombatArena.x + direction[1] * 8,
                H.squadCombatArena.y + direction[2] * 8) end)
        end
        H.squadCombatSpawnIndex = H.squadCombatSpawnIndex + 1
        if H.squadCombatSpawnIndex <= H.squadCombatCase[1] then
            setPhase("squad_combat_spawn_actor", current)
        else setPhase("squad_combat_spawn_zombies", current) end
        return
    end
    if H.phase == "squad_combat_spawn_zombies" then
        local count = H.squadCombatCase[2]
        H.squadCombatSpottedAttempts, H.squadCombatSpottedSuccesses = 0, 0
        H.squadCombatSetTargetFallbacks = 0
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
            if H.config.squad_combat_natural_acquisition~="true" then targetZombie(H,zombie,target) end
        end
        H.squadCombatStartedAt = current
        H.squadCombatDistanceTimeline = {}
        H.squadCombatNativeLogAt = setmetatable({}, {__mode="k"})
        H.squadCombatNextDistanceSampleAt = current + 5000
        H.squadCombatActions, H.squadCombatOffensive = 0, 0
        H.squadCombatLateBystandersRemoved = 0
        H.squadCombatNextBystanderSweepAt = current + 1000
        H.squadCombatNextRadioSoundAt = current + 1000
        H.squadCombatRadioSoundCount = 0
        H.squadCombatActionKinds = {}
        H.squadCombatMelee, H.squadCombatShove, H.squadCombatRetreat = 0, 0, 0
        H.squadCombatAnticipatory = 0
        H.squadCombatMeleeLanded, H.squadCombatMeleeNoEffect = 0, 0
        H.squadCombatEarlyLanded, H.squadCombatEarlyNoEffect = 0, 0
        H.squadCombatEarlyHitDamage, H.squadCombatRegularHitDamage = 0, 0
        H.squadCombatClosingWait, H.squadCombatPostSwingBackstep = 0, 0
        H.squadCombatClosingBackpedal = 0
        H.squadCombatLastEvidence = setmetatable({}, { __mode = "k" })
        H.squadCombatRetargetAt = current
        H.squadCombatRetargetAttempts = 0
        H.squadCombatTargetSamples, H.squadCombatTargetValidSamples = 0, 0
        H.squadCombatTargetNilSamples, H.squadCombatTargetPlayerSamples = 0, 0
        H.squadCombatTargetOtherSamples = 0
        H.squadCombatTargetValidAfterRetargetSamples = 0
        H.squadCombatRetargetSuccesses = 0
        H.squadCombatInitialHealth = setmetatable({}, { __mode = "k" })
        H.squadCombatLastHealth = setmetatable({}, { __mode = "k" })
        H.squadCombatSettledHealth = setmetatable({}, { __mode = "k" })
        H.squadCombatHitsByZombie = setmetatable({}, { __mode = "k" })
        H.squadCombatSampledHealthLoss, H.squadCombatSampledHealthGain = 0, 0
        H.squadCombatLateHealthGain = 0
        H.squadCombatHitTimeline = {}
        H.squadCombatHealthChangeTimeline = {}
        H.squadCombatEatingSamples = 0
        H.squadCombatTargetVisibleSamples = 0
        H.squadCombatTargetSeenTimeMax = 0
        H.squadCombatLowestSeenHealthRatio = 1
        H.squadCombatEngaged = setmetatable({}, { __mode = "k" })
        for _, zombie in ipairs(H.squadCombatZombies) do
            local health = number(call(zombie, "getHealth"), nil)
            H.squadCombatInitialHealth[zombie] = health
            H.squadCombatLastHealth[zombie] = health
        end
        H.squadCombatActionAt = setmetatable({}, { __mode = "k" })
        if H.config.squad_combat_photo == "true"
            or H.config.squad_combat_near_observer == "true"
            or H.config.squad_combat_order == "follow" then
            local px, py, pz = U.position(H.player)
            local centerX, centerY = math.floor(H.squadCombatArena.x),
                math.floor(H.squadCombatArena.y)
            local direction = H.squadCombatFrontDirection or { 1, 0 }
            local preview
            if H.config.squad_combat_near_observer == "true"
                or H.config.squad_combat_order == "follow" then
                local depths = H.config.squad_combat_order == "follow" and { 3, 4, 5 }
                    or { 13, 15, 11, 17 }
                for _, depth in ipairs(depths) do
                    for _, lateral in ipairs({ 0, -2, 2, -4, 4 }) do
                        preview = openSquare(
                            centerX - direction[1] * depth
                                - direction[2] * lateral,
                            centerY - direction[2] * depth
                                + direction[1] * lateral,
                            math.floor(H.squadCombatArena.z))
                        if preview and call(preview, "getRoom") == nil then break end
                        preview = nil
                    end
                    if preview then break end
                end
            else
                preview = openSquare(centerX - 3, centerY,
                    math.floor(H.squadCombatArena.z))
            end
            local moved, failure = pcall(function()
                if not preview then error("no clear observer tile near arena") end
                H.squadCombatPhotoOriginal = {
                    x = px, y = py, z = pz,
                    ghost = call(H.player, "isGhostMode") == true,
                }
                if H.config.squad_combat_near_observer ~= "true"
                    and H.config.squad_combat_order ~= "follow" then
                    H.player:setGhostMode(true)
                end
                H.player:teleportTo(preview:getX() + 0.5,
                    preview:getY() + 0.5, preview:getZ())
            end)
            if not check(H.config.squad_combat_near_observer == "true"
                and "squad_combat_near_observer" or "squad_combat_photo_observer",
                moved, moved and ("observer=" .. tostring(preview:getX())
                    .. ":" .. tostring(preview:getY()))
                    or tostring(failure)) then
                cleanup(H); setPhase("finish", current) return
            end
            if H.config.squad_combat_photo == "true" then
                H.squadCombatScreenshotAt = current + 5000
            end
            if H.config.squad_combat_order == "follow" then
                for _, follower in ipairs(H.squadCombatActors) do
                    local ordered, why = SC.Commands.issue(SC.Registry.idOf(follower), "follow", nil, H.player)
                    if not check("squad_combat_follow_order", ordered == true, tostring(why)) then
                        cleanup(H); setPhase("finish", current) return
                    end
                end
            end
        end
        setPhase("squad_combat_observe", current)
        return
    end
    if H.phase == "squad_combat_observe" then
        if H.config.squad_combat_passive_control=="true" then
            for _,actor in ipairs(H.squadCombatActors) do
                if alive(actor) then
                    SC.ZombieTargeting.scan(actor,current,H.squadCombatZombies)
                    SC.ZombieAttack.resolve(actor,current,H.squadCombatZombies)
                end
            end
        end
        local backupType = H.config.squad_combat_backup_weapon_type
        if type(backupType) == "string" and backupType ~= "" then
            for index, actor in ipairs(H.squadCombatActors or {}) do
                local original = H.squadCombatPrimaryWeapons[index]
                local carried, usable = SC.Combat.weaponAvailability(actor)
                if original and not H.squadCombatBackupForced
                    and current - H.squadCombatStartedAt >= 1500
                    and (H.squadCombatOffensive or 0) >= 1
                    and number(call(original, "getCondition"), 0) > 0 then
                    local forced = pcall(function() original:setCondition(0) end)
                    H.squadCombatBackupForced = true
                    check("squad_combat_backup_forced_break",
                        forced and number(call(original, "getCondition"), -1) == 0,
                        "after_offensive=" .. tostring(H.squadCombatOffensive))
                    if SC.InventoryIndex then SC.InventoryIndex.touch(actor) end
                    carried, usable = SC.Combat.weaponAvailability(actor)
                end
                if not H.squadCombatBackupDiagnosed
                    and current - H.squadCombatStartedAt >= 5000 then
                    H.squadCombatBackupDiagnosed = true
                    result("PASS", "squad_combat_backup_before_swap",
                        "original=" .. tostring(original ~= nil)
                            .. " condition=" .. tostring(call(original, "getCondition"))
                            .. " carried=" .. tostring(carried)
                            .. " usable=" .. tostring(usable)
                            .. " primary=" .. tostring(U.itemType(
                                call(actor, "getPrimaryHandItem"))))
                end
                if original and not H.squadCombatBackupInjected[index]
                    and current - H.squadCombatStartedAt > 1000
                    and usable == 0 then
                    local backup = call(call(actor, "getInventory"), "AddItem", backupType)
                    if backup then
                        H.squadCombatBackupInjected[index] = backup
                        result("PASS", "squad_combat_backup_available",
                            "actor=" .. index .. " after_broken="
                                .. tostring(H.config.squad_combat_weapon_type)
                                .. " backup=" .. backupType)
                    end
                end
                local backup = H.squadCombatBackupInjected[index]
                if backup and not H.squadCombatBackupEquipped[index]
                    and call(actor, "getPrimaryHandItem") == backup then
                    H.squadCombatBackupEquipped[index] = true
                    result("PASS", "squad_combat_backup_equipped",
                        "actor=" .. index .. " backup=" .. backupType)
                end
            end
        end
        if H.config.squad_combat_radio_lure == "true"
            and current >= (H.squadCombatNextRadioSoundAt or math.huge) then
            H.squadCombatNextRadioSoundAt = current + 2000
            local actor = H.squadCombatActors[1]
            if actor and alive(actor) then
                local x, y, z = U.position(actor)
                local ok, sound = pcall(function()
                    return getWorldSoundManager():addSound(
                        H.squadCombatLureRadio, math.floor(x), math.floor(y),
                        math.floor(z or 0), 18, 35)
                end)
                if ok and sound then
                    H.squadCombatRadioSoundCount = H.squadCombatRadioSoundCount + 1
                end
            end
        end
        if current >= (H.squadCombatNextBystanderSweepAt or math.huge) then
            H.squadCombatNextBystanderSweepAt = current + 1000
            for _, bystander in ipairs(SC.Registry.living()) do
                local participant = false
                for _, actor in ipairs(H.squadCombatActors or {}) do
                    if bystander == actor then participant = true; break end
                end
                if not participant then
                    local ok, done = pcall(SC.Actor.remove, bystander)
                    if ok and done == true then
                        H.squadCombatLateBystandersRemoved =
                            H.squadCombatLateBystandersRemoved + 1
                    end
                end
            end
        end
        if current >= (H.squadCombatNextDistanceSampleAt or math.huge) then
            H.squadCombatNextDistanceSampleAt = current + 5000
            local nearest, farthest = math.huge, 0
            for _, actor in ipairs(H.squadCombatActors or {}) do
                if alive(actor) then
                    for _, zombie in ipairs(H.squadCombatZombies or {}) do
                        if call(zombie, "isDead") ~= true then
                            local squared = tonumber(U.distanceSq(actor, zombie))
                            if squared and squared >= 0 then
                                local distance = math.sqrt(squared)
                                nearest = math.min(nearest, distance)
                                farthest = math.max(farthest, distance)
                            end
                        end
                    end
                end
            end
            local actor = H.squadCombatActors[1]
            local id = actor and SC.Registry.idOf(actor)
            local record = id and SC.Registry.byId(id) or nil
            local runtime = record and record.runtime or {}
            local overrun = runtime.combatOverrun or {}
            local combatState = actor and SC.Combat.peek(actor) or nil
            local holdAge = combatState and combatState.stalledHoldSince
                and math.max(0, current - combatState.stalledHoldSince) / 1000 or -1
            local refreshed = runtime.zombieTargeting
                and runtime.zombieTargeting.refreshed or 0
            local receipt = actor and number(
                call(actor, "getCompanionAttackReceiptSerial"), -1) or -1
            local prone = 0
            for _, zombie in ipairs(H.squadCombatZombies or {}) do
                if call(zombie, "isOnFloor") == true
                    or call(zombie, "isProne") == true then prone = prone + 1 end
            end
            local actionState = actor and tostring(
                call(actor, "getCompanionActionStateName") or "-") or "-"
            H.squadCombatDistanceTimeline[#H.squadCombatDistanceTimeline + 1] =
                string.format("%d:%.1f:%.1f:%s:%.0f/%.0f:hold%.1f:path%d:receipt%d:prone%d:state%s",
                    math.floor((current - H.squadCombatStartedAt) / 1000),
                    nearest == math.huge and -1 or nearest, farthest,
                    tostring(runtime.combatAction or "-"),
                    tonumber(overrun.risk) or -1,
                    tonumber(overrun.threshold) or -1,
                    holdAge, tonumber(refreshed) or 0, receipt, prone,
                    actionState:gsub("[^%w_]", ""))
        end
        if H.squadCombatScreenshotAt and current >= H.squadCombatScreenshotAt then
            H.squadCombatScreenshotAt = nil
            local name = tostring(H.config.run_id) .. "-squad-combat-"
                .. caseName(H.squadCombatCase) .. "-"
                .. tostring(H.squadCombatRepeat) .. ".png"
            local ok, errorText = pcall(function()
                getCore():TakeFullScreenshot(name)
            end)
            result(ok and "PASS" or "FAIL", "squad_combat_screenshot",
                ok and name or tostring(errorText))
            local original = H.squadCombatPhotoOriginal
            if original and H.config.squad_combat_near_observer ~= "true" then
                pcall(function()
                    H.player:teleportTo(original.x, original.y, original.z)
                    H.player:setGhostMode(original.ghost)
                end)
                H.squadCombatPhotoOriginal = nil
            end
        end
        local survivors, deadZombies = 0, 0
        if current >= (H.squadCombatRetargetAt or 0) then
            H.squadCombatRetargetAt = current + 1000
            for index, zombie in ipairs(H.squadCombatZombies) do
                if call(zombie, "isDead") ~= true then
                    if call(zombie, "getEatBodyTarget") ~= nil then
                        H.squadCombatEatingSamples = H.squadCombatEatingSamples + 1
                    end
                    local health = number(call(zombie, "getHealth"), nil)
                    local previous = H.squadCombatLastHealth[zombie]
                    if health ~= nil and previous ~= nil then
                        if health < previous then
                            H.squadCombatSampledHealthLoss =
                                H.squadCombatSampledHealthLoss + previous - health
                        elseif health > previous then
                            H.squadCombatSampledHealthGain =
                                H.squadCombatSampledHealthGain + health - previous
                            if current - H.squadCombatStartedAt > 5000 then
                                H.squadCombatLateHealthGain =
                                    H.squadCombatLateHealthGain + health - previous
                            end
                        end
                        if math.abs(health - previous) > 0.01
                            and #H.squadCombatHealthChangeTimeline < 100 then
                            H.squadCombatHealthChangeTimeline[#H.squadCombatHealthChangeTimeline + 1] =
                                string.format("%d:%d:%.3f>%.3f",
                                    math.floor((current - H.squadCombatStartedAt) / 1000),
                                    index, previous, health)
                        end
                        local initial = H.squadCombatInitialHealth[zombie]
                        if initial and initial > 0 then
                            H.squadCombatLowestSeenHealthRatio = math.min(
                                H.squadCombatLowestSeenHealthRatio,
                                health / initial)
                        end
                    end
                    H.squadCombatLastHealth[zombie] = health
                    if current - H.squadCombatStartedAt >= 5000
                        and H.squadCombatSettledHealth[zombie] == nil then
                        H.squadCombatSettledHealth[zombie] = health
                    end
                    H.squadCombatTargetSamples = H.squadCombatTargetSamples + 1
                    if call(zombie, "isTargetVisible") == true then
                        H.squadCombatTargetVisibleSamples =
                            H.squadCombatTargetVisibleSamples + 1
                    end
                    local seenTime = number(call(zombie, "getTargetSeenTime"), 0)
                    H.squadCombatTargetSeenTimeMax = math.max(
                        H.squadCombatTargetSeenTimeMax, seenTime)
                    local currentTarget = call(zombie, "getTarget")
                    if current>=(H.squadCombatNativeLogAt[zombie] or 0) then
                        H.squadCombatNativeLogAt[zombie]=current+5000
                        print("SC_COMBAT_OBSERVE|case="..caseName(H.squadCombatCase)
                            .." trial="..H.squadCombatRepeat.." zombie="..index
                            .." dead="..tostring(call(zombie,"isDead"))
                            .." inWorld="..tostring(call(call(getCell(),"getZombieList"),"contains",zombie))
                            .." health="..tostring(call(zombie,"getHealth"))
                            .." target="..tostring(currentTarget)
                            .." distance="..tostring(currentTarget and U.distance(zombie,currentTarget))
                            .." state="..tostring(call(zombie,"getCurrentState"))
                            .." attack="..tostring(call(zombie,"getVariableBoolean","bAttack"))
                            .." outcome="..tostring(call(zombie,"getVariableString","AttackOutcome"))
                            .." didDamage="..tostring(call(zombie,"getVariableBoolean","AttackDidDamage")))
                    end
                    local validTarget = false
                    for _, actor in ipairs(H.squadCombatActors) do
                        if currentTarget == actor and alive(actor) then
                            validTarget = true; break
                        end
                    end
                    if validTarget then
                        H.squadCombatTargetValidSamples =
                            H.squadCombatTargetValidSamples + 1
                    elseif currentTarget == nil then
                        H.squadCombatTargetNilSamples =
                            H.squadCombatTargetNilSamples + 1
                    elseif currentTarget == H.player then
                        H.squadCombatTargetPlayerSamples =
                            H.squadCombatTargetPlayerSamples + 1
                    else
                        H.squadCombatTargetOtherSamples =
                            H.squadCombatTargetOtherSamples + 1
                    end
                    if not validTarget then
                        local closest, closestDistance = nil, math.huge
                        for _, actor in ipairs(H.squadCombatActors) do
                            if alive(actor) then
                                local distance = U.distanceSq(actor, zombie)
                                if distance < closestDistance then
                                    closest, closestDistance = actor, distance
                                end
                            end
                        end
                        if closest and H.config.squad_combat_natural_acquisition~="true" then
                            targetZombie(H, zombie, closest)
                            H.squadCombatRetargetAttempts =
                                H.squadCombatRetargetAttempts + 1
                            if call(zombie, "getTarget") == closest then
                                H.squadCombatRetargetSuccesses =
                                    H.squadCombatRetargetSuccesses + 1
                                validTarget = true
                            end
                        end
                    end
                    if validTarget then
                        H.squadCombatTargetValidAfterRetargetSamples =
                            H.squadCombatTargetValidAfterRetargetSamples + 1
                    end
                end
            end
        end
        for _, actor in ipairs(H.squadCombatActors) do
            if alive(actor) then survivors = survivors + 1 end
            local state = SC.Combat.peek(actor)
            local evidence = state and state.lastCombatEvidence or nil
            if evidence and H.squadCombatLastEvidence[actor] ~= evidence then
                H.squadCombatLastEvidence[actor] = evidence
                if evidence.action == "attack_melee" then
                    if evidence.result == "landed" then
                        H.squadCombatMeleeLanded = H.squadCombatMeleeLanded + 1
                        if evidence.target then
                            H.squadCombatHitsByZombie[evidence.target] =
                                (H.squadCombatHitsByZombie[evidence.target] or 0) + 1
                        end
                        local before, after = number(evidence.healthBefore, nil),
                            number(evidence.healthAfter, nil)
                        local damage = before and after
                            and math.max(0, before - after) or 0
                        if #H.squadCombatHitTimeline < 100 then
                            local targetIndex = 0
                            for index, zombie in ipairs(H.squadCombatZombies) do
                                if evidence.target == zombie then
                                    targetIndex = index; break
                                end
                            end
                            H.squadCombatHitTimeline[#H.squadCombatHitTimeline + 1] =
                                string.format("%d:%d:%.3f>%.3f:%s",
                                    math.floor((current - H.squadCombatStartedAt) / 1000),
                                    targetIndex, before or -1, after or -1,
                                    evidence.anticipatorySwing == true and "early" or "regular")
                        end
                        if evidence.anticipatorySwing == true then
                            H.squadCombatEarlyLanded = H.squadCombatEarlyLanded + 1
                            H.squadCombatEarlyHitDamage =
                                H.squadCombatEarlyHitDamage + damage
                        else
                            H.squadCombatRegularHitDamage =
                                H.squadCombatRegularHitDamage + damage
                        end
                    elseif evidence.result == "no_effect" then
                        H.squadCombatMeleeNoEffect = H.squadCombatMeleeNoEffect + 1
                        if evidence.anticipatorySwing == true then
                            H.squadCombatEarlyNoEffect = H.squadCombatEarlyNoEffect + 1
                        end
                    end
                end
            end
            if state and number(state.lastActionAt, 0)
                > (H.squadCombatActionAt[actor] or 0) then
                H.squadCombatActionAt[actor] = state.lastActionAt
                H.squadCombatActions = H.squadCombatActions + 1
                local actionKind = tostring(state.lastAction or "none")
                H.squadCombatActionKinds[actionKind] =
                    (H.squadCombatActionKinds[actionKind] or 0) + 1
                if state.lastAction == "melee" or state.lastAction == "anticipatory_melee"
                    or state.lastAction == "shove"
                    or state.lastAction == "stomp" or state.lastAction == "shoot" then
                    H.squadCombatOffensive = H.squadCombatOffensive + 1
                elseif state.lastAction == "retreat_anticipatory_melee"
                    or state.lastAction == "retreat_melee"
                    or state.lastAction == "retreat_shove"
                    or state.lastAction == "retreat_cover_fire"
                    or state.lastAction == "last_stand_melee"
                    or state.lastAction == "last_stand_shove" then
                    H.squadCombatOffensive = H.squadCombatOffensive + 1
                end
                if state.lastAction == "melee"
                    or state.lastAction == "anticipatory_melee"
                    or state.lastAction == "retreat_anticipatory_melee"
                    or state.lastAction == "retreat_melee"
                    or state.lastAction == "last_stand_melee" then
                    H.squadCombatMelee = H.squadCombatMelee + 1
                elseif state.lastAction == "shove"
                    or state.lastAction == "retreat_shove"
                    or state.lastAction == "last_stand_shove" then
                    H.squadCombatShove = H.squadCombatShove + 1
                elseif state.lastAction == "overrun_retreat" then
                    H.squadCombatRetreat = H.squadCombatRetreat + 1
                end
                if state.lastAction == "anticipatory_wait" then
                    H.squadCombatClosingWait = H.squadCombatClosingWait + 1
                elseif state.lastAction == "anticipatory_backpedal" then
                    H.squadCombatClosingBackpedal = H.squadCombatClosingBackpedal + 1
                elseif state.lastAction == "post_swing_backstep" then
                    H.squadCombatPostSwingBackstep = H.squadCombatPostSwingBackstep + 1
                end
                if state.lastAction == "anticipatory_melee"
                    or state.lastAction == "retreat_anticipatory_melee" then
                    H.squadCombatAnticipatory = H.squadCombatAnticipatory + 1
                end
            end
        end
        for _, zombie in ipairs(H.squadCombatZombies) do
            if call(zombie, "isDead") == true then deadZombies = deadZombies + 1 end
            if H.squadCombatEngaged[zombie] ~= true then
                for _, actor in ipairs(H.squadCombatActors) do
                    if alive(actor) and U.distanceSq(actor, zombie) <= 2.25 * 2.25 then
                        H.squadCombatEngaged[zombie] = true
                        break
                    end
                end
            end
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
