-- SPDX-License-Identifier: MIT
-- Observe the real LF firing veto with native neutral and loyal Bandits.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance then
    require "SCBanditsCombatAcceptance"
end
local Probe = {}
local Shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
local call = Shared.call
local function inLane(actor, bystander, target)
    if math.floor(actor:getZ()) ~= math.floor(bystander:getZ())
        or math.floor(actor:getZ()) ~= math.floor(target:getZ()) then return false end
    local dx, dy = target:getX() - actor:getX(), target:getY() - actor:getY()
    local px, py = bystander:getX() - actor:getX(), bystander:getY() - actor:getY()
    local length = dx * dx + dy * dy
    if length < 0.01 then return false end
    local t = (px * dx + py * dy) / length
    return t > 0 and t < 1 and (px - t * dx)^2 + (py - t * dy)^2 <= 0.8^2
end
local function place(actor, square)
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    actor:teleportTo(x, y, z)
    actor:setX(x) actor:setY(y) actor:setLastX(x) actor:setLastY(y) actor:setNextX(x) actor:setNextY(y)
    actor:setCurrentSquareFromPosition() actor:setMovingSquareNow()
end
local function clearFor(SC, square, actor)
    if SC.GameplayUtil.isClearActorSpawnSquare(square) then return true end
    -- Native isFree(true) rejects the actor already occupying its own initial
    -- spawn tile. Re-centering that one actor is safe only with no other body,
    -- static obstruction or furniture on this already-validated scene tile.
    if not square or actor:getSquare() ~= square or not SC.GameplayUtil.isSquareFree(square)
        or SC.GameplayUtil.squareOccupyingObject(square) ~= nil then return false end
    local moving = square:getMovingObjects()
    for index = 0, moving:size() - 1 do if moving:get(index) ~= actor then return false end end
    return true
end
local function cleanup(f)
    if not f then return end
    f.observing = false
    if f.laneOwner and f.laneOwner.friendlyFireBlocked == f.laneWrapper then
        f.laneOwner.friendlyFireBlocked = f.laneOriginal
    end
    if f.hitObserver then Events.OnHitZombie.Remove(f.hitObserver) f.hitObserver = nil end
    if f.shotObserver then Events.OnWeaponSwingHitPoint.Remove(f.shotObserver) f.shotObserver = nil end
    if f.deathObserver then Events.OnZombieDead.Remove(f.deathObserver) f.deathObserver = nil end
end
local function observeLane(f, actor, target, context, blocked)
    if not f.observing or actor ~= f.actor or not f.targets[target] or not blocked then return end
    local snapshot = type(context) == "table" and context.snapshot
    if not snapshot then return end
    for _, row in ipairs(snapshot.protectedActors or {}) do
        local kind = f.bystanders[row.actor]
        if kind and inLane(actor, row.actor, target) then
            f.blocked[kind] = f.blocked[kind] + 1
        end
    end
end
local function claimHit(f, target, weapon)
    if weapon ~= f.gun or call(f.actor, "isDoShove") == true then return end
    local attempt, receipt = call(f.actor, "getCompanionAttackAttemptSerial"), call(f.actor, "getCompanionAttackReceiptSerial")
    local serial, health = call(f.actor, "getCompanionAttackCollisionSerial"), call(target, "getHealth")
    if type(attempt) ~= "number" or type(receipt) ~= "number" or attempt ~= receipt + 1
        or type(serial) ~= "number" or type(health) ~= "number" then return end
    f.actualHits = f.actualHits or {}
    f.actualHits[#f.actualHits + 1] = { target = target, id = call(target, "getID"), health = health,
        attempt = attempt, serial = serial + 1, dead = call(target, "isDead") == true }
end
local function consumeHits(f)
    local claims = f.actualHits or {}
    f.actualHits = {}
    for _, hit in ipairs(claims) do
        local health = call(hit.target, "getHealth")
        if call(f.actor, "getCompanionAttackAttemptSerial") == hit.attempt
            and call(f.actor, "getCompanionAttackReceiptSerial") == hit.attempt
            and call(f.actor, "getCompanionAttackReceiptOutcome") == "completed"
            and call(f.actor, "getCompanionAttackCollisionSerial") == hit.serial
            and call(hit.target, "getID") == hit.id and hit.id ~= nil and not hit.dead
            and call(hit.target, "getAttackedBy") == f.actor and call(hit.target, "isOnFire") ~= true
            and (type(health) == "number" and health < hit.health or call(hit.target, "isDead") == true) then
            f.damaged = true
            print("SC_REAL_SANDBOX|LANE_ACTUAL_NATIVE_DAMAGE|attempt=" .. hit.attempt .. "|target=" .. tostring(hit.id)
                .. "|health=" .. hit.health .. "->" .. tostring(health) .. "|attacked_by_exact_lf=true")
        end
    end
end
local function nativeAimTarget(f)
    local text = tostring(call(f.actor, "getCompanionRangedReadiness"))
    local x, y, z = string.match(text, "aimTarget=([^,%s]+),([^,%s]+),([^%s]+)")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return nil end
    local selected
    for target in pairs(f.targets) do
        if math.abs(target:getX() - x) < 0.01 and math.abs(target:getY() - y) < 0.01
            and math.abs(target:getZ() - z) < 0.01 then
            if selected then return nil end
            selected = target
        end
    end
    return selected
end
local function consumeShots(f)
    local shots = f.pendingShots or {}
    f.pendingShots = {}
    for _, shot in ipairs(shots) do
        local fired = f.gun:getCurrentAmmoCount() < shot.ammo
            or shot.chambered and call(f.gun, "isRoundChambered") == false
        if fired then
            if call(f.actor, "getCompanionAttackReceiptSerial") ~= shot.attempt
                or call(f.actor, "getCompanionAttackReceiptOutcome") ~= "completed" then
                f.failure = "actual gunshot has no matching completed native receipt"
            elseif not shot.target then f.failure = "actual gunshot target could not be verified from native aim"
            elseif shot.blocked then f.failure = "actual consumed LF gunshot crossed a protected firing lane"
            else f.safeShots = (f.safeShots or 0) + 1 end
        end
    end
end
local function install(f)
    local owner = SurvivorCompanion.Combat
    local original = owner.friendlyFireBlocked
    f.observing = true
    local wrapper = function(actor, target, context)
        local blocked, blocker = original(actor, target, context)
        observeLane(f, actor, target, context, blocked)
        return blocked, blocker
    end
    f.laneOwner, f.laneOriginal, f.laneWrapper = owner, original, wrapper
    owner.friendlyFireBlocked = wrapper
    f.hitObserver = function(target, attacker, _, weapon)
        if attacker ~= f.actor then return end
        if f.bystanders[target] then f.failure = "native LF collateral hit on " .. f.bystanders[target] end
        if f.targets[target] and call(weapon, "isRanged") == true then
            f.hits = f.hits + 1
            Shared.claimImpact(f, target)
            claimHit(f, target, weapon)
            print("SC_REAL_SANDBOX|LANE_NATIVE_HIT_EVENT|target=" .. tostring(Shared.targetID(target))
                .. "|serial=" .. tostring(call(f.actor, "getCompanionAttackCollisionSerial"))
                .. "|attempt=" .. tostring(call(f.actor, "getCompanionAttackAttemptSerial"))
                .. "|receipt=" .. tostring(call(f.actor, "getCompanionAttackReceiptSerial"))
                .. "|outcome=" .. tostring(call(f.actor, "getCompanionAttackReceiptOutcome"))
                .. "|health=" .. tostring(call(target, "getHealth"))
                .. "|attacked_by_lf=" .. tostring(call(target, "getAttackedBy") == f.actor))
        end
    end
    f.shotObserver = function(actor, weapon)
        if actor ~= f.actor or weapon ~= f.gun then return end
        local target, blocked = nativeAimTarget(f), false
        if target then
            local record = SurvivorCompanion.Registry.byId(f.id)
            local snapshot = SurvivorCompanion.Senses.cached(actor, record and record.runtime)
            blocked = original(actor, target, { player = f.primary.player, snapshot = snapshot, kind = "ranged" })
        end
        f.pendingShots = f.pendingShots or {}
        -- Vanilla ISReloadWeaponAction.onShoot is registered before this
        -- observer on the same event. It already consumed/rechambered the
        -- round; compare with the preceding rendered sample, not this event's
        -- post-consumption magazine count. Reconcile the native receipt next.
        f.pendingShots[#f.pendingShots + 1] = { target = target, blocked = blocked,
            ammo = f.lastAmmo, chambered = f.lastChambered,
            attempt = call(actor, "getCompanionAttackAttemptSerial") }
        print("SC_REAL_SANDBOX|LANE_GUN_EVENT|attempt=" .. tostring(call(actor, "getCompanionAttackAttemptSerial"))
            .. "|ammo=" .. tostring(f.lastAmmo) .. "->" .. f.gun:getCurrentAmmoCount()
            .. "|target=" .. tostring(target and Shared.targetID(target)) .. "|blocked=" .. tostring(blocked)
            .. "|shove=" .. tostring(call(actor, "isDoShove")))
    end
    Events.OnHitZombie.Add(f.hitObserver)
    Events.OnWeaponSwingHitPoint.Add(f.shotObserver)
    f.deathObserver = function(target) f.targets[target] = nil end
    Events.OnZombieDead.Add(f.deathObserver)
end
local function finish(H, current, check, result, setPhase, good, why)
    local f = H.banditsLane
    if f then
        good = check("lane_primary_isolation", Shared.samePlayers(f.primary), "native main identity/slots/count unchanged") and good
        cleanup(f)
    end
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-protected-lane.png")
    result(good and "PASS" or "FAIL", "bandits_live_protected_lane", why)
    setPhase("finish", current)
end
function Probe.step(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.banditsLane
    if not f then
        if current - H.startedAt < 10000 or not SC.State.active then return end
        if not check("lane_adapter_active", SC.BanditsAdapter.status().active, SC.BanditsAdapter.status().reason) then
            setPhase("finish", current) return
        end
        local primary = Shared.playerState()
        local site = Shared.field(SC, primary.player)
        if not site then finish(H, current, check, result, setPhase, false, "no loaded open field") return end
        primary.player:teleportTo(site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
        getGameTime():setTimeOfDay(12)
        local ticket, reason = SC.Actor.beginSpawn(site.fellow, { recruited = true, identity = SC.Spawn.generateIdentity(),
            background = { profession = "policeofficer" } })
        if not ticket then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
        f = { primary = primary, site = site, ticket = ticket, stage = "spawn_lf", started = current,
            before = {}, bystanders = {}, targets = {}, blocked = { neutral = 0, loyal = 0 }, samples = 0, hits = 0, rounds = 0 }
        H.banditsLane = f
        for id in pairs(BanditZombie.Cache) do f.before[id] = true end
        return
    end
    if f.failure or current - f.started > 120000 or call(f.primary.player, "isDead") == true
        or f.actor and call(f.actor, "isDead") == true then
        finish(H, current, check, result, setPhase, false, f.failure or "native death/deadline; neutral=" .. f.blocked.neutral
            .. "; loyal=" .. f.blocked.loyal .. "; rounds=" .. f.rounds .. "; hits=" .. f.hits .. "; samples=" .. f.samples) return
    end
    if f.stage == "spawn_lf" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        local offDuty, dutyWhy = SC.BaseLife.setDuty(f.id, false)
        if not offDuty then finish(H, current, check, result, setPhase, false, "off-duty setup: " .. tostring(dutyWhy)) return end
        local gun, why = Shared.equip(actor)
        if not gun then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        f.gun, f.lastAmmo = gun, gun:getCurrentAmmoCount()
        SC.InventoryIndex.touch(actor)
        for _, order in ipairs({ { "set_scavenge", false }, { "set_weapon_priority", "firearm" },
            { "set_combat_doctrine", "weapons_free" }, { "stay" } }) do
            local okay, failure = SC.Commands.issue(f.id, order[1], order[2], f.primary.player)
            if not okay then finish(H, current, check, result, setPhase, false, tostring(failure)) return end
        end
        if not SC.Combat.equipPreferred(actor, "firearm") then finish(H, current, check, result, setPhase, false, "real gun equip failed") return end
        for index, kind in ipairs({ "neutral", "loyal" }) do
            local distance = index * 2 + 2
            local point = { x = f.site.fellow:getX() + f.site.direction[1] * distance,
                y = f.site.fellow:getY() + f.site.direction[2] * distance, z = f.site.fellow:getZ() }
            BanditServer.Spawner.Clan(f.primary.player, { cid = "0dfc13d3-4ce6-4af8-aac6-326eb7514c36", size = 1,
                hostile = false, hostileP = false, loyal = kind == "loyal",
                program = kind == "loyal" and "Companion" or "Bandit", spawnPoints = { point } })
        end
        f.spawnAt, f.stage = current, "spawn_bystanders"
        return
    end
    if f.stage == "spawn_bystanders" then
        local count = 0
        for id, actor in pairs(BanditZombie.Cache) do
            if not f.before[id] and SC.BanditsAdapter.owns(actor) and SC.GameplayUtil.distance(actor, f.actor) < 18 then
                local brain = BanditBrain.Get(actor)
                if brain and type(brain.loyal) == "boolean" then
                    f.bystanders[actor] = brain.loyal and "loyal" or "neutral"
                    count = count + 1
                end
            end
        end
        if count < 2 or current - f.spawnAt < 2000 then return end
        -- Initial scene placement ends before targets and observers are enabled.
        for actor, kind in pairs(f.bystanders) do
            local distance = kind == "neutral" and 4 or 6
            local selected
            for _, offset in ipairs({ 0, -1, 1, -2, 2 }) do
                local square = getCell():getGridSquare(f.site.fellow:getX() + f.site.direction[1] * (distance + offset),
                    f.site.fellow:getY() + f.site.direction[2] * (distance + offset), f.site.fellow:getZ())
                if clearFor(SC, square, actor) then selected = square break end
            end
            if not selected then
                finish(H, current, check, result, setPhase, false, "no clear initial bystander square for " .. kind) return
            end
            place(actor, selected)
        end
        local list = addZombiesInOutfit(f.site.enemy:getX(), f.site.enemy:getY(), f.site.enemy:getZ(), 4, nil, 0)
        for index = 0, list:size() - 1 do f.targets[list:get(index)] = true end
        if list:size() < 1 then finish(H, current, check, result, setPhase, false, "no native ordinary targets") return end
        install(f)
        f.lastAmmo, f.lastChambered = f.gun:getCurrentAmmoCount(), call(f.gun, "isRoundChambered") == true
        f.stage, f.nextSample, f.nextTrace = "combat", current, current
        result("PASS", "lane_native_scene", "real neutral and native loyal Companion Bandits; no recruitment; normal zombies retained; gun id=" .. f.gun:getID())
        return
    end
    if Shared.consumeImpact(f) then f.damaged = true end
    consumeShots(f)
    consumeHits(f)
    local ammo = f.gun:getCurrentAmmoCount()
    if ammo < f.lastAmmo then f.rounds = f.rounds + f.lastAmmo - ammo end
    f.lastAmmo = ammo
    f.lastChambered = call(f.gun, "isRoundChambered") == true
    if current >= f.nextSample then
        f.nextSample = current + 100
        local record = SC.Registry.byId(f.id)
        local snapshot = SC.Senses.cached(f.actor, record and record.runtime)
        local protected, allied = {}, {}
        for _, row in ipairs(snapshot and snapshot.protectedActors or {}) do protected[row.actor] = true end
        for _, row in ipairs(snapshot and snapshot.allies or {}) do allied[row.actor] = true end
        local both = true
        for actor, kind in pairs(f.bystanders) do
            local brain = BanditBrain.Get(actor)
            if SC.Registry.idOf(actor) ~= nil or SC.Actor.isCompanion(actor) or allied[actor]
                or SC.BanditsAdapter.relationship(actor, f.actor) ~= "neutral"
                or not brain or brain.loyal ~= (kind == "loyal") then f.failure = "bystander ownership/hostility drift: " .. kind end
            if not protected[actor] then both = false end
        end
        if both then f.samples = f.samples + 1 end
        if not f.repositionAt and f.blocked.neutral > 0 and f.blocked.loyal > 0 and f.samples >= 20 then
            for _, side in ipairs({ 1, -1 }) do
                local x = math.floor(f.actor:getX() - f.site.direction[2] * side * 3) + 0.5
                local y = math.floor(f.actor:getY() + f.site.direction[1] * side * 3) + 0.5
                local z = math.floor(f.actor:getZ())
                local square = getCell():getGridSquare(x, y, z)
                if SC.GameplayUtil.isClearActorSpawnSquare(square) and SC.Navigation.openSegment(f.actor, x, y, z) then
                    local moved, why = SC.Commands.issue(f.id, "move_to", { x = x, y = y, z = z }, f.primary.player)
                    if not moved then f.failure = "normal flank order: " .. tostring(why) end
                    f.repositionAt = current
                    result(moved and "PASS" or "FAIL", "lane_normal_flank_order", "public Move here; no repositioning or attack override")
                    break
                end
            end
        end
        if current >= f.nextTrace then
            f.nextTrace = current + 1000
            local state = SC.Combat.peek(f.actor) or {}
            local living = 0
            for target in pairs(f.targets) do if not call(target, "isDead") then living = living + 1 end end
            print("SC_REAL_SANDBOX|PROTECTED_LANE|samples=" .. f.samples .. "|neutral_blocks=" .. f.blocked.neutral
                .. "|loyal_blocks=" .. f.blocked.loyal .. "|rounds=" .. f.rounds .. "|hits=" .. f.hits
                .. "|action=" .. tostring(state.lastAction) .. "|living_targets=" .. living
                .. "|order=" .. tostring(SC.Commands.peek(f.actor).order)
                .. "|duty=" .. tostring(SC.BaseLife.resident(f.id) and SC.BaseLife.resident(f.id).duty))
            if living == 0 and not f.damaged then f.failure = "all native targets died before exact owned-damage proof" end
        end
    end
    if not f.failure and f.blocked.neutral > 0 and f.blocked.loyal > 0 and f.samples >= 20
        and f.hits > 0 and f.damaged and f.rounds > 0 and (f.safeShots or 0) > 0 then
        finish(H, current, check, result, setPhase, true, "actual protected firing veto: neutral=" .. f.blocked.neutral
            .. "; loyal=" .. f.blocked.loyal .. "; later LF native hits=" .. f.hits .. "; rounds=" .. f.rounds
            .. "; neither Bandit recruited/allied/hit/escalated")
    end
end
Probe.inLane, Probe.observeLane, Probe.cleanup, Probe.clearFor = inLane, observeLane, cleanup, clearFor
Probe.claimHit, Probe.consumeHits, Probe.consumeShots = claimHit, consumeHits, consumeShots
SCRealSandboxHarnessProbes.SCBanditsProtectedLaneAcceptance = Probe
return Probe
