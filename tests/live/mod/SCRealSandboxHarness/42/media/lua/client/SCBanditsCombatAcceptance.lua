-- SPDX-License-Identifier: MIT
-- Disposable, rendered combat scenes. Setup uses real native actors/items;
-- attacks, accuracy, damage, reactions and wound application stay production.
local Probe = {}
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function call(actor, key, ...)
    local SC = SurvivorCompanion
    local okay, callback = SC.Call.resolve(actor, key)
    if not okay then return nil end
    local safe, result = pcall(callback, actor, ...)
    if safe then return result end
end
local function partsHealth(actor)
    local parts = call(call(actor, "getBodyDamage"), "getBodyParts")
    if not parts then return nil end
    local sum = 0
    for index = 0, parts:size() - 1 do sum = sum + parts:get(index):getHealth() end
    return sum
end
local function targetID(actor)
    if actor == nil then return nil end
    if type(BanditUtils) == "table" then return BanditUtils.GetCharacterID(actor) end
    return call(actor, "getID")
end
local function banditCache()
    return type(BanditZombie) == "table" and BanditZombie.Cache or {}
end
local function taskFor(actor)
    if type(Bandit) ~= "table" or type(Bandit.GetTask) ~= "function" then return nil end
    local okay, task = pcall(Bandit.GetTask, actor)
    if okay then return task end
end
local function playerState()
    local slots = IsoPlayer.getPlayers()
    local state = { player = getSpecificPlayer(0), slots = {}, size = slots:size(), count = IsoPlayer.numPlayers }
    for index = 0, state.size - 1 do state.slots[index + 1] = slots:get(index) end
    return state
end
local function samePlayers(state)
    local slots = IsoPlayer.getPlayers()
    if slots:size() ~= state.size or IsoPlayer.numPlayers ~= state.count
        or getSpecificPlayer(0) ~= state.player
        or type(getPlayer) == "function" and getPlayer() ~= state.player
        or type(BanditUtils) == "table" and BanditUtils.GetCharacterID(state.player) ~= 1 then return false end
    for index = 0, state.size - 1 do if slots:get(index) ~= state.slots[index + 1] then return false end end
    return true
end
local function cleanup(fixture)
    if fixture then
        fixture.observing = false
        if fixture.shootOwner and fixture.shootOwner.onComplete == fixture.shootWrapper then
            fixture.shootOwner.onComplete = fixture.shootOriginal
        end
    end
    if fixture and fixture.hitObserver then Events.OnHitZombie.Remove(fixture.hitObserver) fixture.hitObserver = nil end
    if fixture and fixture.shotObserver then Events.OnWeaponSwingHitPoint.Remove(fixture.shotObserver) fixture.shotObserver = nil end
    if fixture and fixture.deathObserver then Events.OnZombieDead.Remove(fixture.deathObserver) fixture.deathObserver = nil end
end
local function observeFirearms(f)
    local owner = ZombieActions and ZombieActions.Shoot
    if type(owner) ~= "table" or type(owner.onComplete) ~= "function" then return false, "native Shoot callback missing" end
    local original = owner.onComplete
    f.observing, f.nativeBulletWounds = true, 0
    local wrapper = function(attacker, task, ...)
        if not f.observing then return original(attacker, task, ...) end
        local matched = f.bandits[attacker] and not (f.retired and f.retired[attacker])
            and type(task) == "table" and task.eid == "lf:" .. f.id
        local before, requests, armorBefore
        if matched then
            before = partsHealth(f.actor)
            requests = SurvivorCompanion.BanditsAdapter.status().bulletHits
            if f.armor then armorBefore = f.armorModule.lfSnapshot(f.armor) end
        end
        local values = pack(pcall(original, attacker, task, ...))
        if not values[1] then
            f.failure = "native Shoot failed: " .. tostring(values[2])
            cleanup(f)
            error(values[2], 0)
        end
        if matched then
            local after = partsHealth(f.actor)
            local status = SurvivorCompanion.BanditsAdapter.status()
            if f.armor then
                f.armorModule.observeShot(f, armorBefore, f.armorModule.lfSnapshot(f.armor), requests, status, before, after)
            end
            if before and after and after < before and status.bulletHits > requests
                and status.lastVictim == "lf:" .. f.id and status.lastModel == "BulletHit" then
                f.nativeBulletWounds, f.incoming = f.nativeBulletWounds + 1, true
                print("SC_REAL_SANDBOX|FIREARMS_NATIVE_WOUND|victim=lf:" .. f.id
                    .. "|parts=" .. before .. "->" .. after .. "|requests=" .. (status.bulletHits - requests))
            end
        end
        return unpackValues(values, 2, values.n)
    end
    f.shootOwner, f.shootOriginal, f.shootWrapper = owner, original, wrapper
    owner.onComplete = wrapper
    return true
end
local function finish(H, current, check, result, setPhase, okay, detail)
    local f = H.banditsAcceptance
    if f and f.primary then
        local isolated = check("combat_primary_isolation_final", samePlayers(f.primary), "native slots/owner/identity unchanged")
        okay = okay and isolated
    end
    cleanup(f)
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-" .. tostring(H.config.bandits_combat_scenario) .. ".png")
    result(okay and "PASS" or "FAIL", H.config.companion_firearms_probe == "true"
        and "lf_live_firearms" or "bandits_live_" .. tostring(H.config.bandits_combat_scenario), detail)
    setPhase("finish", current)
end
local function field(SC, player, firstRadius, lastRadius)
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for radius = firstRadius or 8, lastRadius or 40, 2 do
        for _, origin in ipairs({ { px + radius, py }, { px - radius, py }, { px, py + radius }, { px, py - radius } }) do
            for _, direction in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local previous, points, clear = nil, {}, true
                for offset = 0, 18 do
                    local sq = getCell():getGridSquare(origin[1] + direction[1] * offset,
                        origin[2] + direction[2] * offset, pz)
                    if not sq or sq:getRoom() ~= nil or not SC.GameplayUtil.isSquareFree(sq)
                        or not SC.GameplayUtil.isClearActorSpawnSquare(sq)
                        or SC.Topology.squareIsWater(sq) then clear = false break end
                    for side = -1, 1, 2 do
                        local flank = getCell():getGridSquare(sq:getX() - direction[2] * side,
                            sq:getY() + direction[1] * side, pz)
                        if not flank or flank:getRoom() ~= nil or not SC.GameplayUtil.isSquareFree(flank)
                            or not SC.GameplayUtil.isClearActorSpawnSquare(flank)
                            or SC.Topology.squareIsWater(flank) then clear = false break end
                        local cross = SC.Topology.classifyEdge(player, sq, flank, {})
                        if not cross.traversable or cross.affordance ~= "open" then clear = false break end
                        if previous then
                            local priorFlank = getCell():getGridSquare(previous:getX() - direction[2] * side,
                                previous:getY() + direction[1] * side, pz)
                            local edge = SC.Topology.classifyEdge(player, priorFlank, flank, {})
                            if not edge.traversable or edge.affordance ~= "open" then clear = false break end
                        end
                    end
                    if not clear then break end
                    if previous then
                        local edge = SC.Topology.classifyEdge(player, previous, sq, {})
                        if not edge.traversable or edge.affordance ~= "open" then clear = false break end
                    end
                    points[offset + 1], previous = sq, sq
                end
                if clear then return { observer = points[1], fellow = points[6], enemy = points[16], direction = direction } end
            end
        end
    end
end
local function equip(actor)
    local inventory = actor:getInventory()
    local gun = inventory:AddItem("Base.Pistol")
    if not gun then return nil, "native pistol unavailable" end
    local clip = gun:getClipSize()
    local magazine = gun:getMagazineType()
    for _ = 1, 2 do
        local item = inventory:AddItem(tostring(magazine))
        if not item then return nil, "native magazine unavailable" end
        item:setCurrentAmmoCount(clip)
    end
    gun:setContainsClip(true)
    gun:setCurrentAmmoCount(clip)
    gun:setRoundChambered(true)
    gun:setJammed(false)
    return gun
end
local function banditRounds(bandit)
    if type(BanditBrain) ~= "table" then return nil end
    local brain = BanditBrain.Get(bandit)
    if not brain or type(brain.weapons) ~= "table" then return nil end
    local rounds = 0
    for _, weapon in pairs(brain and brain.weapons or {}) do
        if type(weapon) == "table" and type(weapon.bulletsLeft) == "number" then rounds = rounds + weapon.bulletsLeft end
    end
    return rounds
end
local function claimImpact(f, target)
    local serial = call(f.actor, "getCompanionAttackCollisionSerial")
    if type(serial) ~= "number" then return end
    f.impactClaims = f.impactClaims or {}
    -- Native serial advances after the synchronous collision callback, while
    -- OnHitZombie runs inside it. Associate this event with that exact impact.
    local claims = f.impactClaims[serial + 1] or {}
    claims[target], f.impactClaims[serial + 1] = true, claims
end
local function consumeImpact(f)
    local claims = f.impactClaims or {}
    f.impactClaims = {}
    local serial = call(f.actor, "getCompanionAttackCollisionSerial")
    local target = call(f.actor, "getCompanionAttackCollisionTarget")
    if claims[serial] and claims[serial][target]
        and call(f.actor, "didCompanionAttackCollisionHitTarget") == true then
        f.nativeDamageProof = true
        print("SC_REAL_SANDBOX|OWNED_NATIVE_DAMAGE|LF=" .. f.id .. "|serial=" .. serial
            .. "|target=" .. tostring(targetID(target)))
        return true
    end
    for pendingSerial, targets in pairs(claims) do
        for hitTarget in pairs(targets) do
            print("SC_REAL_SANDBOX|UNCONFIRMED_NATIVE_DAMAGE|LF=" .. tostring(f.id)
                .. "|claimed_serial=" .. tostring(pendingSerial) .. "|completed_serial=" .. tostring(serial)
                .. "|event_target=" .. tostring(targetID(hitTarget)) .. "|collision_target=" .. tostring(targetID(target))
                .. "|collision_hit=" .. tostring(call(f.actor, "didCompanionAttackCollisionHitTarget"))
                .. "|health=" .. tostring(call(hitTarget, "getHealth")) .. "|dead=" .. tostring(call(hitTarget, "isDead")))
        end
    end
    -- A failed native callback cannot leave a future claim for the next
    -- successful swing. These observers execute after synchronous impacts.
    return false
end
function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local regular = H.config.companion_firearms_probe == "true"
    local f = H.banditsAcceptance
    if not f then
        if not SC.State.active or SC.Registry.count() == 0 then return end
        if current - H.startedAt < 10000 then return end
        if regular then
            if not check("regular_lf_bandits_absent", SC.BanditsAdapter.status().state == "absent"
                and type(BanditUtils) ~= "table" and type(BanditBrain) ~= "table",
                "ordinary LF production combat; Bandits2 not loaded") then setPhase("finish", current) return end
        else
            if not check("combat_adapter_active", SC.BanditsAdapter.status().active, SC.BanditsAdapter.status().reason) then
                setPhase("finish", current) return
            end
        end
        local primary = playerState()
        local site = field(SC, primary.player)
        if not site then finish(H, current, check, result, setPhase, false, "no loaded open 18-tile outdoor scene") return end
        primary.player:teleportTo(site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
        getGameTime():setTimeOfDay(12)
        f = { primary = primary, site = site, bandits = {}, banditBefore = {}, rounds = {}, outgoing = 0,
            banditHealth = {}, targetIDs = {}, retired = {}, deadTargets = {}, hitTargets = {}, lastTasks = {},
            combatants = tonumber(H.config.bandits_combatants) == 4 and 4 or 2,
            lfRounds = 0, banditShots = 0, started = current, stage = "spawn_lf", nextTrace = current }
        H.banditsAcceptance = f
        for id in pairs(banditCache()) do f.banditBefore[id] = true end
        local ticket, reason = SC.Actor.beginSpawn(site.fellow, {
            recruited = true, identity = SC.Spawn.generateIdentity(),
            background = H.config.bandits_lf_profession ~= "random"
                and { profession = H.config.bandits_lf_profession } or nil,
            state = { order = { current = "stay", combatDoctrine = "weapons_free", weaponPriority = "firearm" } },
        })
        if not ticket then finish(H, current, check, result, setPhase, false, "LF spawn: " .. tostring(reason)) return end
        f.ticket = ticket
        result("PASS", "combat_scene_setup", "disposable daylight scene; native observer teleport; fresh recruited LF; real loaded pistol; ordinary zombies retained; production profession="
            .. tostring(H.config.bandits_lf_profession) .. "; no skill/stat overrides, no accuracy/damage changes")
        return
    end
    if call(f.primary.player, "isDead") == true then
        finish(H, current, check, result, setPhase, false, "native observer died; scene cannot continue")
        return
    end
    if f.stage == "spawn_lf" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, "LF poll: " .. tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        if H.config.bandits_combat_scenario == "armor" then
            require "SCBanditsArmorEvidence"
            f.armorModule = SCRealSandboxHarnessProbes.SCBanditsArmorEvidence
            local armor, reason = f.armorModule.equip(actor)
            if not armor then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
            f.armor = armor
            result("PASS", "combat_real_lf_armor", "native police vest id=" .. armor.id .. "; condition=" .. armor.condition)
        end
        local gun, failure = equip(actor)
        if not gun then finish(H, current, check, result, setPhase, false, tostring(failure)) return end
        f.gun, f.lastAmmo = gun, gun:getCurrentAmmoCount()
        SC.InventoryIndex.touch(actor)
        for _, command in ipairs({ { "stay", nil }, { "set_scavenge", false },
            { "set_weapon_priority", "firearm" }, { "set_combat_doctrine", H.config.bandits_combat_doctrine or "weapons_free" } }) do
            local ordered, why = SC.Commands.issue(f.id, command[1], command[2], f.primary.player)
            if not ordered then finish(H, current, check, result, setPhase, false, "production order: " .. tostring(why)) return end
        end
        local equipped, why = SC.Combat.equipPreferred(actor, "firearm")
        if not equipped then finish(H, current, check, result, setPhase, false, "production equip: " .. tostring(why)) return end
        f.healthBefore, f.primaryHealth = partsHealth(actor), partsHealth(f.primary.player)
        f.statusBefore = SC.BanditsAdapter.status()
        f.hitObserver = function(zombie, attacker, bodyPart, weapon)
            if attacker == actor and f.bandits[zombie] and not f.retired[zombie]
                and call(weapon, "isRanged") == true then
                f.outgoing = f.outgoing + 1
                f.hitTargets[zombie] = true
                claimImpact(f, zombie)
                if f.armor then f.armorModule.observeHit(f, zombie, bodyPart) end
                print("SC_REAL_SANDBOX|COMBAT_HIT|LF=" .. f.id .. "|target=" .. tostring(targetID(zombie))
                    .. "|weapon=" .. tostring(call(weapon, "getFullType")) .. "|health=" .. tostring(call(zombie, "getHealth")))
            end
        end
        Events.OnHitZombie.Add(f.hitObserver)
        f.shotObserver = function(shooter, weapon)
            if shooter == actor and weapon == f.gun then
                print("SC_REAL_SANDBOX|FIREARMS_IMPACT|" .. tostring(call(actor, "getCompanionRangedReadiness")))
            end
        end
        Events.OnWeaponSwingHitPoint.Add(f.shotObserver)
        f.deathObserver = function(zombie)
            if f.bandits[zombie] and not f.retired[zombie] then
                f.deadTargets[zombie] = true
                print("SC_REAL_SANDBOX|COMBAT_DEATH|target=" .. tostring(targetID(zombie)) .. "|LF_firearm_hit=" .. tostring(f.hitTargets[zombie]))
            end
        end
        Events.OnZombieDead.Add(f.deathObserver)
        if not regular then
            local observed, failure = observeFirearms(f)
            if not observed then finish(H, current, check, result, setPhase, false, failure) return end
        end
        f.equipAt, f.stage = current, "equip"
        return
    end
    if f.stage == "equip" then
        -- isPrimaryHandModelReady is protected in 42.21 and is not exposed to
        -- Lua. The bridge diagnostic probes that exact native method.
        local readiness = tostring(call(f.actor, "getCompanionRangedReadiness"))
        if f.actor:getPrimaryHandItem() ~= f.gun or not string.find(readiness, "handModel=true", 1, true) then
            if current - f.equipAt > 10000 then
                finish(H, current, check, result, setPhase, false, "native gun/hand model not ready: " .. readiness)
            end
            return
        end
        if current - f.equipAt < 1500 then return end
        f.stage = "spawn_targets"
    end
    if f.stage == "spawn_targets" then
        local enemy = f.site.enemy
        if H.config.bandits_combat_scenario == "firearms_zombie_control" then
            local list = addZombiesInOutfit(enemy:getX(), enemy:getY(), enemy:getZ(), f.combatants, nil, 0)
            for index = 0, list:size() - 1 do
                local zombie = list:get(index)
                f.bandits[zombie], f.targetIDs[zombie], f.banditHealth[zombie] = true, call(zombie, "getID"), zombie:getHealth()
            end
        else
            local cid = f.armor and "a2dec2f0-c76d-4640-8a71-733a547a1ebc"
                or "d7ba1cc0-de47-4162-b5bd-6295c47b890d" -- unchanged ArmyDesert or Officers
            local profile = BanditCustom.ClanGet(cid)
            if not profile then finish(H, current, check, result, setPhase, false, "official Officers clan absent") return end
            local points = {}
            for index = 1, f.combatants do
                local forward = f.combatants == 4 and math.floor((index - 1) / 2) * 2 or (index - 1) * 2
                local side = f.combatants == 4 and (index % 2 == 1 and -1 or 1) or 0
                points[index] = { x = enemy:getX() + f.site.direction[1] * forward - f.site.direction[2] * side,
                    y = enemy:getY() + f.site.direction[2] * forward + f.site.direction[1] * side, z = enemy:getZ() }
            end
            BanditServer.Spawner.Clan(f.primary.player, { cid = cid, size = f.combatants,
                hostile = false, hostileP = false, spawnPoints = points })
        end
        f.spawnAt, f.stage = current, "spawn_bandits"
        result("PASS", "combat_real_equipment", "LF=" .. f.id .. "; gun_id=" .. tostring(f.gun:getID()) .. "; ammo=" .. f.lastAmmo
            .. "; native_aiming=" .. tostring(call(f.actor, "getPerkLevel", Perks.Aiming))
            .. "; " .. (H.config.bandits_combat_scenario == "firearms_zombie_control" and "ordinary zombies"
                or f.armor and "stock armored ArmyDesert" or "stock Officers")
            .. " requested=" .. f.combatants .. " near 10/12 tiles; no native model callbacks invoked by the fixture")
        return
    end
    if f.stage == "spawn_bandits" then
        local count = 0
        for id, actor in pairs(banditCache()) do
            if not f.banditBefore[id] and SC.BanditsAdapter.owns(actor)
                and SC.GameplayUtil.distance(actor, f.actor) < 18 then f.bandits[actor] = true end
        end
        local first
        for actor in pairs(f.bandits) do
            first = first or actor
            count = count + 1
            if f.targetIDs[actor] == nil then
                f.targetIDs[actor] = call(actor, "getID")
                f.rounds[actor] = banditRounds(actor)
                f.banditHealth[actor] = actor:getHealth()
            end
        end
        if count < f.combatants or current - f.spawnAt < 3000 then
            if current - f.spawnAt > 20000 then finish(H, current, check, result, setPhase, false, "only " .. count .. " native Bandits loaded") end
            return
        end
        if H.config.bandits_combat_scenario == "firearms_zombie_control" then
            check("combat_normal_zombie_control", SC.GameplayUtil.isZombie(first), "ordinary zombies remain ordinary targets")
        else
            if f.armor then
                local armored, why = f.armorModule.prepareBandits(f)
                if not armored then finish(H, current, check, result, setPhase, false, why) return end
            end
            if not check("combat_neutral_identity", SC.BanditsAdapter.relationship(first, f.actor) == "neutral",
                "stock neutral Bandits are protected before provocation") then
                finish(H, current, check, result, setPhase, false, "unexpected initial relationship") return
            end
            for actor in pairs(f.bandits) do
                actor:faceLocationF(f.actor:getX(), f.actor:getY())
                BanditPlayer.CheckFriendlyFire(actor, f.actor)
            end
        end
        f.combatAt, f.stage = current, "combat"
        return
    end
    if f.stage == "combat" then
        if f.failure then finish(H, current, check, result, setPhase, false, f.failure) return end
        local status = SC.BanditsAdapter.status()
        local ammo = f.gun:getCurrentAmmoCount()
        if ammo < f.lastAmmo then f.lfRounds = f.lfRounds + f.lastAmmo - ammo end
        f.lastAmmo = ammo
        local living = 0
        for actor in pairs(f.bandits) do
            local rounds = banditRounds(actor)
            local task = taskFor(actor)
            local action = task and task.action
            if call(actor, "isDead") == true or call(actor, "isExistInTheWorld") == false
                or call(actor, "getID") ~= f.targetIDs[actor] then f.retired[actor] = true end
            if not f.retired[actor] then
                living = living + 1
                if rounds and f.rounds[actor] and rounds < f.rounds[actor]
                    and (action == "Shoot" or f.lastTasks[actor] == "Shoot") then
                    f.banditShots = f.banditShots + f.rounds[actor] - rounds
                end
            end
            f.rounds[actor], f.lastTasks[actor] = rounds, action
        end
        if consumeImpact(f) then f.banditDamaged = true end
        local incoming = status.bulletHits > f.statusBefore.bulletHits and status.lastVictim == "lf:" .. f.id
            and status.lastModel == "BulletHit"
        if incoming and partsHealth(f.actor) < f.healthBefore and (f.nativeBulletWounds or 0) > 0 then f.incoming = true end
        if current >= f.nextTrace then
            f.nextTrace = current + 1000
            local decision = SC.Decision.peek(f.actor) or {}
            print("SC_REAL_SANDBOX|FIREARMS|ms=" .. (current - f.combatAt) .. "|LF=" .. f.id
                .. "|health=" .. tostring(partsHealth(f.actor)) .. "|intent=" .. tostring(decision.intent)
                .. "|lf_rounds=" .. f.lfRounds .. "|bandit_rounds=" .. f.banditShots
                .. "|outgoing_hits=" .. f.outgoing .. "|bullet_requests=" .. (status.bulletHits - f.statusBefore.bulletHits)
                .. "|last_victim=" .. tostring(status.lastVictim) .. "|living_bandits=" .. living
                .. "|LF_light=" .. tostring(f.actor:getSquare():getLightLevel(0))
                .. "|aiming=" .. tostring(call(f.actor, "getPerkLevel", Perks.Aiming))
                .. "|hit_count=" .. tostring(call(f.actor, "getCompanionAttackCollisionHitCount"))
                .. "|collision_hit_target=" .. tostring(call(f.actor, "didCompanionAttackCollisionHitTarget")))
            print("SC_REAL_SANDBOX|FIREARMS_READY|" .. tostring(call(f.actor, "getCompanionRangedReadiness")))
            print("SC_REAL_SANDBOX|FIREARMS_GEOMETRY|forward=" .. tostring(call(f.actor, "getForwardDirectionX")) .. "," .. tostring(call(f.actor, "getForwardDirectionY"))
                .. "|pitch=" .. tostring(call(f.actor, "getCurrentVerticalAimAngle"))
                .. "|target_pitch=" .. tostring(call(f.actor, "getTargetVerticalAimAngle")))
            for actor in pairs(f.bandits) do
                local task = taskFor(actor)
                print("SC_REAL_SANDBOX|FIREARMS_TARGET|id=" .. tostring(targetID(actor))
                    .. "|task=" .. tostring(task and task.action) .. ":" .. tostring(task and task.eid)
                    .. "|distance=" .. SC.GameplayUtil.distance(actor, f.actor) .. "|health=" .. tostring(call(actor, "getHealth")))
            end
        end
        local zombieControl = H.config.bandits_combat_scenario == "firearms_zombie_control"
        if regular and (current - f.combatAt >= 30000 or living == 0 or call(f.actor, "isDead") == true) then
            local dead = 0
            for _ in pairs(f.deadTargets) do dead = dead + 1 end
            finish(H, current, check, result, setPhase, f.outgoing > 0 and f.banditDamaged and f.lfRounds > 0,
                "regular LF; Bandits absent; native pistol hits=" .. f.outgoing .. "; rounds=" .. f.lfRounds
                    .. "; target deaths=" .. dead .. "; milliseconds=" .. (current - f.combatAt)
                    .. "; LF_dead=" .. tostring(call(f.actor, "isDead")))
        elseif zombieControl and not regular and f.outgoing > 0 and f.banditDamaged and f.lfRounds > 0 then
            finish(H, current, check, result, setPhase, true, "ordinary zombie control: native pistol hits=" .. f.outgoing .. "; rounds=" .. f.lfRounds)
        elseif not zombieControl and f.incoming and f.outgoing > 0 and f.banditDamaged and f.lfRounds > 0 and f.banditShots > 0
            and (not f.armor or f.armorModule.accepted(f)) then
            finish(H, current, check, result, setPhase, true,
                "natural LF pistol hits=" .. f.outgoing .. "; native Bandits bullet wounds to lf:" .. f.id
                    .. "; LF rounds=" .. f.lfRounds .. "; Bandits rounds=" .. f.banditShots .. "; no controlled damage callbacks"
                    .. (f.armor and f.armorModule.detail(f) or ""))
        elseif current - f.combatAt > 180000 or call(f.actor, "isDead") == true or living == 0 then
            finish(H, current, check, result, setPhase, false,
                "outgoing=" .. f.outgoing .. "; incoming=" .. tostring(f.incoming) .. "; LF rounds=" .. f.lfRounds
                    .. "; Bandits rounds=" .. f.banditShots .. "; LF_dead=" .. tostring(call(f.actor, "isDead"))
                    .. (f.armor and f.armorModule.detail(f) or ""))
        end
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance = Probe
Probe.shared = { call = call, partsHealth = partsHealth, playerState = playerState,
    samePlayers = samePlayers, field = field, targetID = targetID, equip = equip,
    claimImpact = claimImpact, consumeImpact = consumeImpact }
Probe.observeFirearms, Probe.cleanup = observeFirearms, cleanup
return Probe
