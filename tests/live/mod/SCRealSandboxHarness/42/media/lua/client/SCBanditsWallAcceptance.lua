-- SPDX-License-Identifier: MIT
-- Real solid wall, normal Move here traversal, then native exposed combat.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local CombatProbe = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance
local Shared = CombatProbe.shared
local call, partsHealth = Shared.call, Shared.partsHealth
local function candidate(SC, player, inside)
    if not inside or not inside:getRoom() or not SC.GameplayUtil.isClearActorSpawnSquare(inside) then return nil end
    local x, y, z = inside:getX(), inside:getY(), inside:getZ()
    for _, direction in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local outside = getCell():getGridSquare(x + direction[1], y + direction[2], z)
        if outside and outside:getRoom() == nil and SC.GameplayUtil.isSquareFree(outside) then
            local object, kind = SC.Topology.barrierBetween(inside, outside)
            -- Doors, windows and fences have their own affordances and cannot
            -- substitute for the solid-wall requirement.
            if object == nil and kind == "blocked" then
                local previous, clear = outside, true
                for offset = 2, 7 do
                    local square = getCell():getGridSquare(x + direction[1] * offset, y + direction[2] * offset, z)
                    if not square or square:getRoom() ~= nil or not SC.GameplayUtil.isSquareFree(square)
                        or not SC.GameplayUtil.isClearActorSpawnSquare(square) then clear = false break end
                    local edge = SC.Topology.classifyEdge(player, previous, square, {})
                    if not edge.traversable or edge.affordance ~= "open" then clear = false break end
                    previous = square
                end
                if clear then
                    for back = 2, 5 do
                        local observer = getCell():getGridSquare(x - direction[1] * back, y - direction[2] * back, z)
                        if observer and observer:getRoom() == inside:getRoom()
                            and SC.GameplayUtil.isClearActorSpawnSquare(observer)
                            and tostring(LosUtil.lineClear(getCell(), x + 0.5, y + 0.5, z,
                                observer:getX() + 0.5, observer:getY() + 0.5, z, false)) ~= "Blocked"
                            and tostring(LosUtil.lineClear(getCell(), x + 0.5, y + 0.5, z,
                                previous:getX() + 0.5, previous:getY() + 0.5, z, false)) == "Blocked" then
                            return { inside = inside, outside = outside, enemy = previous, observer = observer,
                                exposed = getCell():getGridSquare(x + direction[1] * 3, y + direction[2] * 3, z) }
                        end
                    end
                end
            end
        end
    end
end
local function findSlice(SC, f)
    local player = f.primary.player
    for _ = 1, 48 do
        if f.scanY > 28 then return nil, true end
        local square = getCell():getGridSquare(f.scanX + f.originX, f.scanY + f.originY, f.floor)
        f.scanX = f.scanX + 1
        if f.scanX > 28 then f.scanX, f.scanY = -28, f.scanY + 1 end
        local site = candidate(SC, player, square)
        if site then return site, false end
    end
    return nil, false
end
local function place(actor, square)
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    actor:teleportTo(x, y, z)
    actor:setX(x) actor:setY(y) actor:setLastX(x) actor:setLastY(y) actor:setNextX(x) actor:setNextY(y)
    actor:setCurrentSquareFromPosition() actor:setMovingSquareNow()
end
local function finish(H, current, check, result, setPhase, okay, why)
    local f = H.banditsWall
    if f then
        okay = check("wall_primary_isolation", Shared.samePlayers(f.primary), "native main identity/slots/count unchanged") and okay
        CombatProbe.cleanup(f)
    end
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-solid-wall.png")
    result(okay and "PASS" or "FAIL", "bandits_live_solid_wall", why)
    setPhase("finish", current)
end
function Probe.step(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.banditsWall
    if not f then
        if current - H.startedAt < 10000 or not SC.State.active then return end
        if not check("wall_adapter_active", SC.BanditsAdapter.status().active, SC.BanditsAdapter.status().reason) then
            setPhase("finish", current) return
        end
        local primary = Shared.playerState()
        H.banditsWall = { primary = primary, stage = "find_wall", started = current, scanX = -28, scanY = -28,
            originX = math.floor(primary.player:getX()), originY = math.floor(primary.player:getY()),
            floor = math.floor(primary.player:getZ()), before = {}, bandits = {}, retired = {},
            blockedSamples = 0, outgoing = 0, rounds = 0, nativeBulletWounds = 0 }
        return
    end
    if f.failure or current - f.started > 180000 or call(f.primary.player, "isDead") == true
        or f.actor and call(f.actor, "isDead") == true then
        finish(H, current, check, result, setPhase, false, f.failure or "native death/deadline; stage=" .. f.stage) return
    end
    if f.stage == "find_wall" then
        local site, done = findSlice(SC, f)
        if not site then
            if done then finish(H, current, check, result, setPhase, false, "no loaded solid-wall scene with clear native staging") end
            return
        end
        f.site = site
        place(f.primary.player, site.observer)
        getGameTime():setTimeOfDay(12)
        local ticket, reason = SC.Actor.beginSpawn(site.inside, { recruited = true, identity = SC.Spawn.generateIdentity(),
            background = { profession = "policeofficer" } })
        if not ticket then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
        f.ticket, f.stage = ticket, "spawn_lf"
        result("PASS", "wall_native_geometry", "actual solid edge=" .. site.inside:getX() .. "," .. site.inside:getY()
            .. "->" .. site.outside:getX() .. "," .. site.outside:getY() .. "; native LOS Blocked; no door/window/fence")
        return
    end
    if f.stage == "spawn_lf" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        local gun, why = Shared.equip(actor)
        if not gun then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        f.gun, f.lastAmmo = gun, gun:getCurrentAmmoCount()
        SC.InventoryIndex.touch(actor)
        SC.BaseLife.setDuty(f.id, false)
        for _, order in ipairs({ { "set_scavenge", false }, { "set_weapon_priority", "firearm" },
            { "set_combat_doctrine", "weapons_free" }, { "stay" } }) do
            local accepted, why = SC.Commands.issue(f.id, order[1], order[2], f.primary.player)
            if not accepted then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        end
        if not SC.Combat.equipPreferred(actor, "firearm") then finish(H, current, check, result, setPhase, false, "native gun equip rejected") return end
        for id in pairs(BanditZombie.Cache) do f.before[id] = true end
        local enemy = f.site.enemy
        BanditServer.Spawner.Clan(f.primary.player, { cid = "d7ba1cc0-de47-4162-b5bd-6295c47b890d", size = 1,
            hostile = false, hostileP = false, spawnPoints = { { x = enemy:getX(), y = enemy:getY(), z = enemy:getZ() } } })
        f.spawnAt, f.stage = current, "spawn_bandit"
        return
    end
    if f.stage == "spawn_bandit" then
        local bandit
        for id, actor in pairs(BanditZombie.Cache) do
            if not f.before[id] and SC.BanditsAdapter.owns(actor) and SC.GameplayUtil.distance(actor, f.actor) < 16 then bandit = actor break end
        end
        if not bandit or current - f.spawnAt < 2500 then return end
        if f.actor:getSquare() ~= f.site.inside and not SC.GameplayUtil.isClearActorSpawnSquare(f.site.inside) then
            finish(H, current, check, result, setPhase, false, "initial indoor square became occupied") return
        end
        place(f.actor, f.site.inside)
        SC.Commands.issue(f.id, "stay", nil, f.primary.player)
        f.bandit, f.bandits[bandit] = bandit, true
        if BanditUtils.LineClear(bandit, f.actor) then finish(H, current, check, result, setPhase, false, "initial native wall LOS already clear") return end
        local okay, why = CombatProbe.observeFirearms(f)
        if not okay then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        f.hitObserver = function(target, attacker, _, weapon)
            if attacker == f.actor and target == f.bandit and weapon == f.gun then
                f.outgoing = f.outgoing + 1
                if not BanditUtils.LineClear(attacker, target) then f.failure = "native LF hit crossed blocked wall LOS" end
                Shared.claimImpact(f, target)
            end
        end
        Events.OnHitZombie.Add(f.hitObserver)
        BanditPlayer.CheckFriendlyFire(bandit, f.actor)
        f.healthBefore, f.nextSample, f.nextTrace, f.stage = partsHealth(f.actor), current, current, "blocked"
        return
    end
    if Shared.consumeImpact(f) then f.damaged = true end
    local ammo = f.gun:getCurrentAmmoCount()
    if ammo < f.lastAmmo then f.rounds = f.rounds + f.lastAmmo - ammo end
    f.lastAmmo = ammo
    local clear = BanditUtils.LineClear(f.bandit, f.actor)
    if f.stage == "blocked" and current >= f.nextSample then
        f.nextSample = current + 100
        if clear or partsHealth(f.actor) ~= f.healthBefore or f.outgoing > 0 or f.nativeBulletWounds > 0 then
            finish(H, current, check, result, setPhase, false, "wall protection changed before the bounded blocked observation") return
        end
        f.blockedSamples = f.blockedSamples + 1
        if f.blockedSamples >= 20 then
            local square = f.site.exposed
            local moved, why = SC.Commands.issue(f.id, "move_to", { x = square:getX(), y = square:getY(), z = square:getZ() }, f.primary.player)
            if not moved then finish(H, current, check, result, setPhase, false, "public exposed move: " .. tostring(why)) return end
            f.stage = "exposing"
            result("PASS", "wall_blocked_native_interval", "20 native blocked LOS samples; no LF wound/hit through wall; normal Move here now requested")
        end
    elseif f.stage == "exposing" and clear and ((f.nativeBulletWounds or 0) > 0 or f.damaged and f.rounds > 0) then
        finish(H, current, check, result, setPhase, true, "solid wall blocked fire; normal physical route exposed actors; owned LF hits="
            .. f.outgoing .. "; rounds=" .. f.rounds .. "; native LF bullet wounds=" .. f.nativeBulletWounds) return
    end
    if current >= f.nextTrace then
        f.nextTrace = current + 1000
        local decision = SC.Decision.peek(f.actor) or {}
        print("SC_REAL_SANDBOX|SOLID_WALL|stage=" .. f.stage .. "|blocked_samples=" .. f.blockedSamples
            .. "|native_clear=" .. tostring(clear) .. "|rounds=" .. f.rounds .. "|hits=" .. f.outgoing
            .. "|native_wounds=" .. f.nativeBulletWounds .. "|intent=" .. tostring(decision.intent))
    end
end
Probe.candidate = candidate
SCRealSandboxHarnessProbes.SCBanditsWallAcceptance = Probe
return Probe
