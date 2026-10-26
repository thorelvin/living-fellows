-- SPDX-License-Identifier: MIT
-- Rendered native close combat. Only scene placement/equipment are staged.
-- Foreign action observers call the original once and preserve every return.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local Shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
local call, partsHealth = Shared.call, Shared.partsHealth
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function bites(actor)
    local parts = call(call(actor, "getBodyDamage"), "getBodyParts")
    if not parts then return nil end
    local count = 0
    for index = 0, parts:size() - 1 do if call(parts:get(index), "bitten") == true then count = count + 1 end end
    return count
end
local function cleanup(f)
    if not f then return end
    f.observing = false
    for _, binding in ipairs(f.bindings or {}) do
        if binding.owner[binding.key] == binding.wrapper then binding.owner[binding.key] = binding.original end
    end
    f.bindings = {}
    if f.hitObserver then Events.OnHitZombie.Remove(f.hitObserver) f.hitObserver = nil end
    if f.deathObserver then Events.OnZombieDead.Remove(f.deathObserver) f.deathObserver = nil end
end
local function finish(H, current, check, result, setPhase, okay, why)
    local f = H.banditsClose
    if f then
        okay = check("close_primary_isolation", Shared.samePlayers(f.primary), "native main/slots/count unchanged") and okay
        okay = check("close_damage_isolation", not f.leaked and not f.shoveDamage,
            "no main-player wound during exact-LF callbacks; native Push adds no health loss") and okay
    end
    cleanup(f)
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-" .. tostring(H.config.bandits_combat_scenario) .. ".png")
    result(okay and "PASS" or "FAIL", "bandits_live_" .. tostring(H.config.bandits_combat_scenario), why)
    setPhase("finish", current)
end
local function bump(actor)
    return tostring(call(actor, "getBumpType")) .. ":" .. tostring(call(actor, "getCurrentStateName"))
end
local function observeActions(f)
    f.observing = true
    for _, name in ipairs({ "Smack", "Push" }) do
        local action = name
        local owner = ZombieActions and ZombieActions[name]
        if type(owner) ~= "table" or type(owner.onWorking) ~= "function" then return false, "missing native " .. name end
        local original = owner.onWorking
        local wrapper = function(attacker, task, ...)
            if not f.observing then return original(attacker, task, ...) end
            local matched = f.bandits[attacker] and not (f.retired and f.retired[attacker])
                and type(task) == "table" and task.eid == "lf:" .. f.id
            local before, beforeBites, mainBefore, hitBefore, windowBefore
            if matched then
                before, beforeBites, mainBefore, hitBefore = partsHealth(f.actor), bites(f.actor), partsHealth(f.primary.player), task.hit
                if f.windowSnapshot then windowBefore = f.windowSnapshot() end
            end
            local values = pack(pcall(original, attacker, task, ...))
            if not values[1] then
                f.failure = "stock " .. action .. " callback failed: " .. tostring(values[2])
                cleanup(f)
                error(values[2], 0)
            end
            if matched then
                local after, afterBites = partsHealth(f.actor), bites(f.actor)
                local status = SurvivorCompanion.BanditsAdapter.status()
                if f.windowObserve then f.windowObserve(action, task, hitBefore, windowBefore, f.windowSnapshot(), before, after) end
                if mainBefore ~= partsHealth(f.primary.player) then f.leaked = true end
                if action == "Push" and hitBefore ~= true and task.hit == true then
                    local reaction = call(f.actor, "getBumpType") == "stagger" or call(f.actor, "isKnockedDown") == true
                    if reaction then f.incomingPush = f.incomingPush + 1 end
                    if before and after and after ~= before then f.shoveDamage = true end
                elseif action == "Smack" then
                    if task.bite == true and beforeBites and afterBites and afterBites > beforeBites then
                        f.incomingBites = f.incomingBites + 1
                    elseif before and after and after < before and status.lastVictim == "lf:" .. f.id then
                        if status.lastModel == "MeleeHit" then f.incomingMelee = f.incomingMelee + 1 end
                        if status.lastModel == "BareHandHit" then f.incomingHand = f.incomingHand + 1 end
                    end
                end
                if hitBefore ~= true and task.hit == true then
                    print("SC_REAL_SANDBOX|CLOSE_NATIVE|action=" .. action .. "|eid=" .. tostring(task.eid)
                        .. "|bite=" .. tostring(task.bite) .. "|parts=" .. tostring(before) .. "->" .. tostring(after)
                        .. "|bites=" .. tostring(beforeBites) .. "->" .. tostring(afterBites)
                        .. "|reaction=" .. bump(f.actor) .. "|model=" .. tostring(status.lastModel))
                end
            end
            return unpackValues(values, 2, values.n)
        end
        f.bindings[#f.bindings + 1] = { owner = owner, key = "onWorking", original = original, wrapper = wrapper }
        owner.onWorking = wrapper
    end
    return true
end
local function emptyWeapons(SC, actor, square)
    actor:setPrimaryHandItem(nil)
    actor:setSecondaryHandItem(nil)
    local dropped = 0
    for _, item in ipairs(SC.GameplayUtil.inventoryItemsDeep(actor:getInventory(), 512)) do
        if instanceof(item, "HandWeapon") then
            call(actor, "removeAttachedItem", item)
            local id = item:getID()
            local okay, reason = SC.GameplayUtil.dropItem(item:getContainer(), square, item)
            if not okay or item:getID() ~= id then return false, "physical weapon drop: " .. tostring(reason) end
            dropped = dropped + 1
        end
    end
    return true, dropped
end
local function localSite(SC, actor, player)
    local source = actor:getSquare()
    local observer
    for radius = 8, 12 do
        for _, offset in ipairs({ { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }) do
            local square = getCell():getGridSquare(source:getX() + offset[1], source:getY() + offset[2], source:getZ())
            if square and SC.GameplayUtil.isClearActorSpawnSquare(square) then observer = square break end
        end
        if observer then break end
    end
    if not observer then return nil, "no_clear_observer_tile" end
    local queue, seen, points, index = { source }, {}, {}, 1
    seen[source:getX() .. ":" .. source:getY()] = true
    while index <= #queue and index <= 64 do
        local previous = queue[index]
        index = index + 1
        for _, direction in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local x, y = previous:getX() + direction[1], previous:getY() + direction[2]
            local key = x .. ":" .. y
            local distanceSq = (x - source:getX())^2 + (y - source:getY())^2
            if not seen[key] and distanceSq <= 9 then
                local square = getCell():getGridSquare(x, y, source:getZ())
                if square and SC.GameplayUtil.isClearActorSpawnSquare(square) then
                    local edge = SC.Topology.classifyEdge(player, previous, square, {})
                    if edge.traversable and edge.affordance == "open" then
                        seen[key] = true
                        queue[#queue + 1] = square
                        if distanceSq >= 2 then points[#points + 1] = square end
                    end
                end
            end
        end
    end
    if #points < 2 then return nil, "only_" .. #points .. "_reachable_staging_tiles" end
    -- Prefer opposing approaches, so the normal attack arcs do not let one
    -- forward swing lock both opponents in a stagger for the entire encounter.
    local first, second, best = 1, 2, math.huge
    for a = 1, #points - 1 do
        local ax, ay = points[a]:getX() - source:getX(), points[a]:getY() - source:getY()
        for b = a + 1, #points do
            local bx, by = points[b]:getX() - source:getX(), points[b]:getY() - source:getY()
            local score = (ax * bx + ay * by) / math.sqrt((ax^2 + ay^2) * (bx^2 + by^2))
                + 0.001 * (ax^2 + ay^2 + bx^2 + by^2)
            if score < best then first, second, best = a, b, score end
        end
    end
    local ordered = { points[first], points[second] }
    for index, point in ipairs(points) do
        if index ~= first and index ~= second then ordered[#ordered + 1] = point end
    end
    return { observer = observer, fellow = source, direction = { 1, 0 }, closePoints = ordered }
end
local function inspectClassification(f, SC)
    local record = SC.Registry.byId(f.id)
    local snapshot = SC.Senses.cached(f.actor, record and record.runtime)
    if snapshot then
        for _, threat in ipairs(snapshot.threats or {}) do
            if f.bandits[threat.actor] and not (f.retired and f.retired[threat.actor]) then f.zombieLeak = true end
            if threat.actor == f.ordinary then f.ordinarySeen = true end
        end
        if snapshot.humanThreat and f.bandits[snapshot.humanThreat.actor]
            and not (f.retired and f.retired[snapshot.humanThreat.actor]) then f.humanSeen = true end
    end
    local factsChecked, allExcluded = 0, true
    for actor in pairs(f.bandits) do
        if not (f.retired and f.retired[actor]) then
            if SC.GameplayUtil.isZombie(actor) then f.zombieLeak = true end
            if SC.ZombieFacts then
                local facts = SC.ZombieFacts.get(actor)
                if facts and facts.zombie == true then f.zombieLeak = true end
                if facts and facts.zombie == false then factsChecked = factsChecked + 1 else allExcluded = false end
            else allExcluded = false end
        end
    end
    if factsChecked > 0 or not allExcluded then f.nativeFactsChecked = allExcluded and factsChecked > 0 end
end
local function placeAt(actor, x, y, z)
    actor:teleportTo(math.floor(x), math.floor(y), math.floor(z))
    -- Native teleportTo truncates even its float overload. Retain the exact
    -- documented initial contact/clear-tile center in this disposable setup.
    actor:setX(x) actor:setY(y)
    actor:setLastX(x) actor:setLastY(y)
    actor:setNextX(x) actor:setNextY(y)
    actor:setCurrentSquareFromPosition()
    actor:setMovingSquareNow()
end
function Probe.step(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.banditsClose
    if not f then
        if not SC.State.active or SC.Registry.count() == 0 or current - H.startedAt < 10000 then return end
        if not check("close_adapter_active", SC.BanditsAdapter.status().active, SC.BanditsAdapter.status().reason) then
            setPhase("finish", current) return
        end
        local role = H.config.bandits_lf_role or "saved"
        local record
        if role ~= "saved" then
            local ready, selected, reason = SCRealSandboxHarnessProbes.SCBanditsAdapterProbe.roleRecord(H, SC, getSpecificPlayer(0))
            if not ready then
                if current - H.startedAt > 60000 then finish(H, current, check, result, setPhase, false, "role: " .. tostring(reason)) end
                return
            end
            record = selected
        end
        local primary = Shared.playerState()
        local site, siteReason
        if record then site, siteReason = localSite(SC, record.actor, primary.player)
        else site = Shared.field(SC, primary.player) end
        if not site and role == "resident" then
            for _, candidate in ipairs(SC.Registry.snapshot()) do
                if SC.BaseLife.resident(candidate.id) and SC.GameplayUtil.isValidActor(candidate.actor) then
                    local available, reason = localSite(SC, candidate.actor, primary.player)
                    if available then record, site = candidate, available break end
                    siteReason = reason
                end
            end
        end
        if not site then finish(H, current, check, result, setPhase, false,
            "no loaded open close-combat site: " .. tostring(siteReason)) return end
        primary.player:teleportTo(site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
        getGameTime():setTimeOfDay(12)
        f = { primary = primary, site = site, actor = record and record.actor, id = record and record.id,
            mode = H.config.bandits_combat_scenario, role = record and role or "recruited", bindings = {}, before = {}, bandits = {},
            health = {}, nativeIDs = {}, retired = {}, pendingPush = {}, hitByLF = {},
            incomingMelee = 0, incomingHand = 0, incomingPush = 0, incomingBites = 0,
            outgoingWeapon = 0, outgoingPush = 0, stage = record and "equipment" or "spawn_lf", started = current }
        H.banditsClose = f
        for id in pairs(BanditZombie.Cache) do f.before[id] = true end
        if not record then
            local ticket, reason = SC.Actor.beginSpawn(site.fellow, { recruited = true, identity = SC.Spawn.generateIdentity(),
                background = { profession = "unemployed" } })
            if not ticket then finish(H, current, check, result, setPhase, false, "spawn: " .. tostring(reason)) return end
            f.ticket = ticket
        end
        result("PASS", "close_scene_setup", "native " .. role .. "; ordinary zombie population retained; no stat/health overrides")
        return
    end
    if f.failure or call(f.primary.player, "isDead") == true then
        finish(H, current, check, result, setPhase, false, f.failure or "observer died") return
    end
    if f.stage == "spawn_lf" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, "poll: " .. tostring(reason)) end
            return
        end
        f.actor, f.id, f.stage = actor, SC.Registry.idOf(actor), "equipment"
    end
    if f.stage == "equipment" then
        if f.role == "resident" then
            local resident = SC.BaseLife.resident(f.id)
            f.residentDutyBefore = resident and resident.duty
            local paused, why = SC.BaseLife.setDuty(f.id, false)
            if not paused then finish(H, current, check, result, setPhase, false, "off-duty setup: " .. tostring(why)) return end
        end
        local okay, dropped = emptyWeapons(SC, f.actor, f.site.observer)
        if not okay then finish(H, current, check, result, setPhase, false, tostring(dropped)) return end
        if f.mode == "melee" then
            f.weapon = f.actor:getInventory():AddItem("Base.RollingPin")
            if not f.weapon then finish(H, current, check, result, setPhase, false, "native rolling pin absent") return end
            SC.InventoryIndex.touch(f.actor)
            local equipped, why = SC.Combat.equipExactWeapon(f.actor, f.weapon)
            if not equipped then finish(H, current, check, result, setPhase, false, "equip: " .. tostring(why)) return end
        end
        if SC.Commands.peek(f.actor).recruited then
            for _, order in ipairs({ { "stay" }, { "set_scavenge", false }, { "set_weapon_priority", "melee" },
                { "set_combat_doctrine", "weapons_free" } }) do
                local accepted, why = SC.Commands.issue(f.id, order[1], order[2], f.primary.player)
                if not accepted then finish(H, current, check, result, setPhase, false, "order: " .. tostring(why)) return end
            end
        end
        f.hitObserver = function(target, attacker, bodyPart, weapon)
            if attacker ~= f.actor or not f.bandits[target] or f.retired[target] then return end
            if weapon == f.weapon and f.weapon then
                f.outgoingWeapon = f.outgoingWeapon + 1
                f.hitByLF[target] = true
                Shared.claimImpact(f, target)
            elseif call(f.actor, "isDoShove") == true and call(f.actor, "isAimAtFloor") ~= true then
                f.pendingPush[target] = { health = target:getHealth(), x = target:getX(), y = target:getY(), bump = bump(target) }
            end
            print("SC_REAL_SANDBOX|CLOSE_LF_HIT|id=" .. f.id .. "|weapon=" .. tostring(call(weapon, "getFullType"))
                .. "|shove=" .. tostring(call(f.actor, "isDoShove")) .. "|health=" .. tostring(target:getHealth()))
        end
        Events.OnHitZombie.Add(f.hitObserver)
        local installed, why = observeActions(f)
        if not installed then finish(H, current, check, result, setPhase, false, why) return end
        f.equippedAt, f.stage = current, "ready"
        result("PASS", "close_equipment", "LF=" .. f.id .. "; real prior weapons dropped with identities preserved=" .. dropped
            .. "; test weapon=" .. tostring(f.weapon and f.weapon:getFullType() or "empty hands")
            .. "; affiliation=" .. tostring(SC.Registry.byId(f.id).factionId) .. "; role=" .. f.role
            .. "; recruited=" .. tostring(SC.Commands.peek(f.actor).recruited)
            .. "; resident_duty_before=" .. tostring(f.residentDutyBefore)
            .. "; resident_duty_now=" .. tostring(SC.BaseLife.resident(f.id) and SC.BaseLife.resident(f.id).duty))
        return
    end
    if f.stage == "ready" then
        if current - f.equippedAt < 2000 then return end
        if f.weapon and f.actor:getPrimaryHandItem() ~= f.weapon
            or not f.weapon and f.actor:getPrimaryHandItem() ~= nil then
            finish(H, current, check, result, setPhase, false, "staged equipment not retained") return
        end
        if f.role ~= "recruited" then
            local site, why = localSite(SC, f.actor, f.primary.player)
            if not site then finish(H, current, check, result, setPhase, false, "ready approach: " .. tostring(why)) return end
            f.site = site
        end
        local cid = f.mode == "infected" and "b7d3a430-e966-48e8-97fa-9078c8d848a4"
            or f.mode == "unarmed" and "0dfc13d3-4ce6-4af8-aac6-326eb7514c36"
            or "d7ba1cc0-de47-4162-b5bd-6295c47b890d"
        local requested, available, points = tonumber(H.config.bandits_combatants) == 4 and 4 or 2, 0, {}
        for _ in pairs(BanditCustom.GetFromClan(cid) or {}) do available = available + 1 end
        -- The original clan spawner draws each configured profile at most once.
        local count = math.min(requested, available)
        if f.site.closePoints then count = math.min(count, #f.site.closePoints) end
        if count == 0 then finish(H, current, check, result, setPhase, false, "stock clan profiles absent") return end
        local x, y, z = f.actor:getX(), f.actor:getY(), f.actor:getZ()
        for index = 1, count do
            local forward = index % 2 == 1 and 2 or -2
            local side = index > 2 and 1 or 0
            local sq = f.site.closePoints and f.site.closePoints[index] or getCell():getGridSquare(math.floor(x + f.site.direction[1] * forward - f.site.direction[2] * side),
                math.floor(y + f.site.direction[2] * forward + f.site.direction[1] * side), math.floor(z))
            if not sq or not SC.GameplayUtil.isClearActorSpawnSquare(sq) then
                finish(H, current, check, result, setPhase, false, "occupied close spawn") return
            end
            points[index] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
        end
        if f.mode == "infected" then
            local square = getCell():getGridSquare(math.floor(f.actor:getX() + f.site.direction[1] * 12),
                math.floor(f.actor:getY() + f.site.direction[2] * 12), math.floor(f.actor:getZ()))
            local zombies = square and addZombiesInOutfit(square:getX(), square:getY(), square:getZ(), 1, nil, 0)
            f.ordinary = zombies and zombies:size() > 0 and zombies:get(0) or nil
            if not f.ordinary then finish(H, current, check, result, setPhase, false, "ordinary zombie control absent") return end
        end
        BanditServer.Spawner.Clan(f.primary.player, { cid = cid, size = count, hostile = false,
            hostileP = false, spawnPoints = points })
        f.count, f.spawnAt, f.stage = count, current, "spawn_bandits"
        result("PASS", "close_stock_clan", "unchanged clan=" .. cid .. "; members=" .. count
            .. "; requested=" .. requested .. "; available profiles=" .. available
            .. (f.site.closePoints and "; verified open local approaches" or "; flanking two-tile spawn"))
        return
    end
    if f.stage == "spawn_bandits" then
        local count, infected = 0, 0
        for id, actor in pairs(BanditZombie.Cache) do
            if not f.before[id] and SC.BanditsAdapter.owns(actor) and SC.GameplayUtil.distance(actor, f.actor) < 8 then
                f.bandits[actor] = true
                if not f.nativeIDs[actor] then f.nativeIDs[actor], f.health[actor] = call(actor, "getID"), actor:getHealth() end
            end
        end
        for actor in pairs(f.bandits) do
            count = count + 1
            if Bandit.HasExpertise(actor, Bandit.Expertise.Infected) then infected = infected + 1 end
        end
        if count < f.count or current - f.spawnAt < 2500 then
            if current - f.spawnAt > 20000 then finish(H, current, check, result, setPhase, false, "stock clan did not load") end
            return
        end
        if f.mode == "infected" and infected == 0 then
            finish(H, current, check, result, setPhase, false, "stock random clan draw contained no infected expertise") return
        end
        if f.role ~= "recruited" and f.mode == "melee" then
            local site, why = localSite(SC, f.actor, f.primary.player)
            if not site or #site.closePoints < f.count then
                finish(H, current, check, result, setPhase, false, "pre-hostility approach: " .. tostring(why)) return
            end
            f.site = site
            placeAt(f.primary.player, site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
            local index = 0
            for actor in pairs(f.bandits) do
                index = index + 1
                local square = site.closePoints[index]
                placeAt(actor, square:getX() + 0.5, square:getY() + 0.5, square:getZ())
            end
            print("SC_REAL_SANDBOX|CLOSE_LOCAL_STAGING|members=" .. f.count
                .. "|clear_connected_opposing_approaches=true|before_hostility=true")
        end
        local contactIndex = 0
        for actor in pairs(f.bandits) do
            if f.mode == "infected" or f.mode == "unarmed" then
                -- Stage contact once, before hostility. Stock AI chooses every
                -- attack; its bite/shove choices have short distance thresholds.
                contactIndex = contactIndex + 1
                local distance = f.mode == "infected" and 0.72 or 0.4
                local direction = contactIndex % 2 == 1 and 1 or -1
                local dx, dy = f.site.direction[1], f.site.direction[2]
                if contactIndex > 2 then dx, dy = -dy, dx end
                local x, y = f.actor:getX() + dx * distance * direction,
                    f.actor:getY() + dy * distance * direction
                placeAt(actor, x, y, f.actor:getZ())
                print("SC_REAL_SANDBOX|CLOSE_CONTACT|mode=" .. f.mode
                    .. "|distance=" .. SC.GameplayUtil.distance(actor, f.actor)
                    .. "|infected=" .. tostring(Bandit.HasExpertise(actor, Bandit.Expertise.Infected)))
            end
        end
        for actor in pairs(f.bandits) do
            actor:faceLocationF(f.actor:getX(), f.actor:getY())
            BanditPlayer.CheckFriendlyFire(actor, f.actor)
        end
        f.combatAt, f.nextTrace, f.stage = current, current, "combat"
        result("PASS", "close_live_started", "LF alias=lf:" .. f.id .. "; infected expertise=" .. infected
            .. "; all later actions are stock AI; no damage callbacks invoked by fixture")
        return
    end
    if f.stage == "combat" then
        local living = 0
        for actor in pairs(f.bandits) do
            if call(actor, "getID") == f.nativeIDs[actor] then
                local push = f.pendingPush[actor]
                if push then
                    local reaction = call(actor, "isKnockedDown") == true or bump(actor) ~= push.bump
                        or (actor:getX() - push.x)^2 + (actor:getY() - push.y)^2 > 0.0009
                    if reaction then
                        if math.abs(actor:getHealth() - push.health) < 0.00001 then f.outgoingPush = f.outgoingPush + 1 end
                        f.pendingPush[actor] = nil
                    end
                end
            end
            if call(actor, "isDead") == true or call(actor, "isExistInTheWorld") == false
                or call(actor, "getID") ~= f.nativeIDs[actor] then f.retired[actor] = true end
            if not f.retired[actor] then living = living + 1 end
        end
        if Shared.consumeImpact(f) then f.outgoingDamage = true end
        inspectClassification(f, SC)
        if current >= f.nextTrace then
            f.nextTrace = current + 1000
            local decision = SC.Decision.peek(f.actor) or {}
            local commands = SC.Commands.peek(f.actor)
            print("SC_REAL_SANDBOX|CLOSE|mode=" .. f.mode .. "|role=" .. f.role .. "|ms=" .. (current - f.combatAt)
                .. "|parts=" .. tostring(partsHealth(f.actor)) .. "|weapon_hits=" .. f.outgoingWeapon
                .. "|push_out=" .. f.outgoingPush .. "|melee_in=" .. f.incomingMelee .. "|hand_in=" .. f.incomingHand
                .. "|push_in=" .. f.incomingPush .. "|bite_in=" .. f.incomingBites .. "|living=" .. living
                .. "|intent=" .. tostring(decision.intent) .. "|ordinary_seen=" .. tostring(f.ordinarySeen)
                .. "|order=" .. tostring(commands.order) .. "|position=" .. f.actor:getX() .. "," .. f.actor:getY()
                .. "|human_seen=" .. tostring(f.humanSeen) .. "|zombie_leak=" .. tostring(f.zombieLeak)
                .. "|native_facts_excluded=" .. tostring(f.nativeFactsChecked))
            for actor in pairs(f.bandits) do
                local task = Bandit.GetTask(actor)
                print("SC_REAL_SANDBOX|CLOSE_TARGET|native=" .. tostring(call(actor, "getID"))
                    .. "|retired=" .. tostring(f.retired[actor]) .. "|health=" .. tostring(call(actor, "getHealth"))
                    .. "|distance=" .. SC.GameplayUtil.distance(f.actor, actor)
                    .. "|marker=" .. tostring(call(actor, "getVariableBoolean", "Bandit"))
                    .. "|visible=" .. tostring(SC.GameplayUtil.canSee(f.actor, actor))
                    .. "|task=" .. tostring(task and task.action) .. ":" .. tostring(task and task.eid)
                    .. "|observer_distance=" .. SC.GameplayUtil.distance(f.primary.player, actor))
            end
        end
        local accepted = f.mode == "melee" and f.outgoingWeapon > 0 and f.outgoingDamage and f.incomingMelee > 0
            or f.mode == "unarmed" and f.outgoingPush > 0 and f.incomingPush > 0 and f.incomingHand > 0
            or f.mode == "infected" and f.incomingBites > 0 and f.ordinarySeen and f.humanSeen
                and f.nativeFactsChecked and not f.zombieLeak
        if accepted or f.leaked or f.shoveDamage or f.zombieLeak or current - f.combatAt > 120000
            or call(f.actor, "isDead") == true or living == 0 then
            finish(H, current, check, result, setPhase, accepted and not f.leaked and not f.shoveDamage and not f.zombieLeak,
                "weapon_hits=" .. f.outgoingWeapon .. "; actual_weapon_damage=" .. tostring(f.outgoingDamage)
                    .. "; outgoing_shoves=" .. f.outgoingPush .. "; incoming_melee=" .. f.incomingMelee
                    .. "; incoming_punches=" .. f.incomingHand .. "; incoming_shoves=" .. f.incomingPush
                    .. "; verified_bites=" .. f.incomingBites .. "; ordinary_seen=" .. tostring(f.ordinarySeen)
                    .. "; human_seen=" .. tostring(f.humanSeen) .. "; native_facts_excluded=" .. tostring(f.nativeFactsChecked)
                    .. "; LF_dead=" .. tostring(call(f.actor, "isDead")))
        end
    end
end
Probe.observeActions, Probe.cleanup, Probe.bites = observeActions, cleanup, bites
Probe.inspectClassification = inspectClassification
SCRealSandboxHarnessProbes.SCBanditsCloseCombatAcceptance = Probe
return Probe
