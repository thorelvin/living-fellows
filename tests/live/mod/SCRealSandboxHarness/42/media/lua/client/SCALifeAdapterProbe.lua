-- SPDX-License-Identifier: MIT
-- Private clone fixture. Spawning, attacks, animation, wounds and persistence
-- use the owning mods. No zombie removal or synthetic health changes.
local Probe = {}
local function call(actor, method, ...)
    local okay, value = pcall(function(...) return actor[method](actor, ...) end, ...)
    if okay then return value end
end
local function nativeCount()
    return tonumber(tostring(SCSplitScreenProbe.releaseDiagnostics()):match("numPlayers=(%d+)"))
end
local function finish(H, current, result, setPhase, okay, detail)
    local f = H.alifeAdapter
    if f and f.hitObserver then Events.ProjectALife_NpcHit.Remove(f.hitObserver) f.hitObserver = nil end
    if f and f.nativeHitObserver then Events.OnHitZombie.Remove(f.nativeHitObserver) f.nativeHitObserver = nil end
    if f and f.swingObserver then Events.OnWeaponSwingHitPoint.Remove(f.swingObserver) f.swingObserver = nil end
    if f and f.player then
        local count = nativeCount()
        result(getSpecificPlayer(0) == f.player and count == f.nativeCount
            and IsoPlayer.getPlayers():size() == f.nativeSize and ProjectALife.Reputation.playerKey(f.player) == f.key
            and "PASS" or "FAIL", "alife_end_primary_isolation", "actual native count=" .. tostring(count)
                .. "/" .. tostring(f.nativeCount) .. "; main key=" .. tostring(ProjectALife.Reputation.playerKey(f.player)))
    end
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-alife-adapter.png")
    local scenario = H.config.project_alife_scenario or "combat"
    result(okay and "PASS" or "FAIL", scenario == "combat" and "alife_two_way_combat"
        or "alife_" .. scenario .. "_complete", detail)
    setPhase("finish", current)
end
local function openPoint(SC, actor, minimum, maximum)
    for radius = minimum, maximum do
        for _, offset in ipairs({ { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }) do
            local start = actor:getSquare()
            local square = getCell():getGridSquare(math.floor(actor:getX() + offset[1]),
                math.floor(actor:getY() + offset[2]), math.floor(actor:getZ()))
            if square and SC.GameplayUtil.isClearActorSpawnSquare(square) then
                local clear, previous = true, start
                for index = 1, radius do
                    local nextSquare = getCell():getGridSquare(start:getX() + offset[1] / radius * index,
                        start:getY() + offset[2] / radius * index, start:getZ())
                    local edge = nextSquare and SC.Topology.classifyEdge(actor, previous, nextSquare, {})
                    if not edge or not edge.traversable or edge.affordance ~= "open" then clear = false break end
                    previous = nextSquare
                end
                if clear then return square end
            end
        end
    end
end
local function inventoryProof(SC, actor)
    local proof = {}
    for _, entry in ipairs(SC.Logistics.audit(actor).items or {}) do
        local id = SC.GameplayUtil.itemStableId(entry.item, true)
        if id then proof[id] = entry.item:getFullType() end
    end
    return proof
end
local function isolated(f, P)
    return getSpecificPlayer(0) == f.player and nativeCount() == f.nativeCount
        and IsoPlayer.getPlayers():size() == f.nativeSize and P.Reputation.playerKey(f.player) == f.key
end
local function isolationDetail(f, P)
    return "; main_same=" .. tostring(getSpecificPlayer(0) == f.player)
        .. "; count=" .. tostring(nativeCount()) .. "/" .. tostring(f.nativeCount)
        .. "; list=" .. tostring(IsoPlayer.getPlayers():size()) .. "/" .. tostring(f.nativeSize)
        .. "; key=" .. tostring(P.Reputation.playerKey(f.player)) .. "/" .. tostring(f.key)
end
local function reload(H, current, check, result, setPhase, SC, P)
    local proof = ModData.getOrCreate("LF_ALIFE_ACCEPTANCE")
    local record = proof.id and SC.Registry.byId(proof.id)
    local binding = proof.uid and P.Watchdog.bindings[proof.uid]
    if not record or not record.actor or not binding or not binding.shell then
        if current - H.startedAt > 60000 then finish(H, current, result, setPhase, false, "saved LF/A-Life actors not restored") end
        return
    end
    local actor, shell = record.actor, binding.shell
    if SC.ALifeAdapter.relationship(shell, actor) == "unknown" then return end
    local actual, count, exact = inventoryProof(SC, actor), 0, true
    for id, kind in pairs(proof.items or {}) do
        count = count + 1
        if actual[id] ~= kind then exact = false end
    end
    for id in pairs(actual) do if not proof.items[id] then exact = false end end
    local alias, included = SC.ALifeAdapter.idFor(actor), 0
    for _, target in ipairs(P.Perception.adapters.players()) do if target == actor then included = included + 1 end end
    check("alife_reload_inventory", exact and count > 0, "same stable item identities/types; items=" .. count)
    check("alife_reload_identity", alias == proof.alias and SC.ALifeAdapter.resolve(alias) == actor and included == 1,
        "persistent UUID rebuilt against restored native body; no duplicate target")
    check("alife_reload_ownership", SC.ALifeAdapter.owns(shell) and P.ActorRegistry.peek(proof.uid).uid == proof.uid,
        "A-Life restored its own record and shell")
    check("alife_reload_primary", P.Reputation.playerKey(getSpecificPlayer(0)) == proof.key and not SC.Registry.idOf(getSpecificPlayer(0))
        and nativeCount() == proof.nativeCount and IsoPlayer.getPlayers():size() == proof.nativeSize,
        "main key=" .. tostring(P.Reputation.playerKey(getSpecificPlayer(0))) .. "/" .. tostring(proof.key)
            .. "; registered=" .. tostring(SC.Registry.idOf(getSpecificPlayer(0)))
            .. "; native count=" .. tostring(nativeCount()) .. "/" .. tostring(proof.nativeCount)
            .. "; native list=" .. tostring(IsoPlayer.getPlayers():size()) .. "/" .. tostring(proof.nativeSize))
    finish(H, current, result, setPhase, exact and alias == proof.alias and included == 1,
        "cold reload; LF=" .. tostring(alias) .. "; A-Life=" .. tostring(proof.uid))
end
local function performance(H, current, check, result, setPhase, SC, P)
    local f = H.alifeAdapter
    f.cohort = f.cohort or { f.actor }
    f.cohortIndex = f.cohortIndex or 1
    if not f.perfSettledAt then f.perfSettledAt = current + 5000 return end
    if current < f.perfSettledAt then return end
    if not f.perfCleaned then
        -- Moving the cloned observer loads one more saved LF restore. Settle
        -- that queue, then remove non-cohort bodies through their owner once,
        -- before timing. Never erase zombies or interfere during measurement.
        for _, record in ipairs(SC.Registry.snapshot()) do
            if record.actor ~= f.actor and not SC.Actor.remove(record.actor) then
                finish(H, current, result, setPhase, false, "late restore cleanup failed") return
            end
        end
        f.perfCleaned = true
        result("PASS", "alife_perf_cohort_ready", "saved restore queue settled; exact native cohorts; ordinary zombies retained")
        return
    end
    local wanted = ({ 1, 4, 16 })[f.cohortIndex]
    if #f.cohort < wanted then
        if f.perfTicket then
            local actor, reason = SC.Actor.pollSpawn(f.perfTicket)
            if actor then
                f.cohort[#f.cohort + 1], f.perfTicket = actor, nil
                SC.Commands.issue(SC.Registry.idOf(actor), "stay", {}, f.player)
            elseif reason ~= "spawn_pending" then finish(H, current, result, setPhase, false, tostring(reason)) end
            return
        end
        local point
        for radius = 3, 20 do
            for _, offset in ipairs({ { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }) do
                local square = getCell():getGridSquare(math.floor(f.player:getX() + offset[1]), math.floor(f.player:getY() + offset[2]), 0)
                if square and SC.GameplayUtil.isClearActorSpawnSquare(square) then
                    local separate = true
                    for _, actor in ipairs(f.cohort) do if SC.GameplayUtil.distance(actor, square) < 2 then separate = false break end end
                    if separate then point = square break end
                end
            end
            if point then break end
        end
        if not point then finish(H, current, result, setPhase, false, "no clear performance cohort spawn") return end
        f.perfTicket = SC.Actor.beginSpawn(point, { recruited = true, identity = SC.Spawn.generateIdentity() })
        return
    end
    if not f.sample then
        PZAPI.ModOptions:getOptions("SurvivorCompanion"):getOption("alifeCompatibility"):setValue(f.withAdapter == true)
        SC.UserOptions.apply()
        f.sample = { at = current + 1000, calls = 0, queryMs = 0, frames = {}, builds = SC.ALifeAdapter.status().listBuilds }
        return
    end
    local s = f.sample
    if current < s.at then return end
    if s.prior then s.frames[#s.frames + 1] = current - s.prior end
    s.prior = current
    local start = getTimestampMs()
    for _ = 1, 100 do P.Perception.adapters.players() end
    s.queryMs, s.calls = s.queryMs + getTimestampMs() - start, s.calls + 100
    if current - s.at < 4000 then return end
    table.sort(s.frames)
    local sum = 0
    for _, value in ipairs(s.frames) do sum = sum + value end
    check("alife_perf_" .. wanted .. (f.withAdapter and "_on" or "_off"), isolated(f, P) and not f.shell:isDead()
        and SC.Registry.count() == wanted, "native LF=" .. wanted .. "; calls=" .. s.calls .. "; query_ms=" .. s.queryMs
            .. "; mean_frame_ms=" .. sum / math.max(1, #s.frames)
            .. "; p95_frame_ms=" .. tostring(s.frames[math.max(1, math.ceil(#s.frames * 0.95))])
            .. "; roster_builds=" .. (SC.ALifeAdapter.status().listBuilds - s.builds)
            .. "; registered=" .. SC.Registry.count() .. "; foreign_dead=" .. tostring(f.shell:isDead())
            .. isolationDetail(f, P)
            .. "; controlled query stress, not an FPS guarantee")
    f.sample = nil
    if not f.withAdapter then f.withAdapter = true return end
    f.withAdapter, f.cohortIndex = false, f.cohortIndex + 1
    if f.cohortIndex > 3 then
        finish(H, current, result, setPhase, true, "native 1/4/16 cohorts with active A-Life; original slots retained")
    end
end
function Probe.auditView(check)
    local SC, P = SurvivorCompanion, ProjectALife
    local status = SC.ALifeAdapter.status()
    local included, unique = {}, true
    for _, actor in ipairs(P.Perception.adapters.players()) do
        if included[actor] then unique = false end
        included[actor] = true
    end
    local expected = 0
    for _, record in ipairs(SC.Registry.snapshot()) do
        local alias = SC.ALifeAdapter.idFor(record.actor)
        if alias and SC.ALifeAdapter.resolve(alias) == record.actor then
            expected = expected + 1
            if not included[record.actor] then unique = false end
        end
    end
    check("alife_view_return_roster", status.active and unique,
        "live LF targets=" .. expected .. "; one entry per eligible body after view release")
    check("alife_view_return_primary", getPlayer() == getSpecificPlayer(0)
        and not SC.Registry.idOf(getSpecificPlayer(0)) and getSpecificPlayer(1) == nil
        and nativeCount() == 1, "main player restored to solo view; no adapter-owned slots")
end
function Probe.step(H, current, check, result, setPhase)
    local SC, P = SurvivorCompanion, ProjectALife
    if H.config.project_alife_scenario == "reload" then
        if current - H.startedAt < 6000 then return end
        return reload(H, current, check, result, setPhase, SC, P)
    elseif H.phase == "alife_adapter_performance" then
        return performance(H, current, check, result, setPhase, SC, P)
    end
    if H.phase == "alife_adapter_setup" then
        if current - H.phaseStartedAt < 6000 then return end
        local status = SC.ALifeAdapter.status()
        if not check("alife_adapter_active", status.active == true, tostring(status.reason)) then setPhase("finish", current) return end
        local player = getSpecificPlayer(0)
        H.alifeAdapter = { player = player, key = P.Reputation.playerKey(player), nativeCount = nativeCount(),
            nativeSize = IsoPlayer.getPlayers():size(), phaseAt = current, role = H.config.project_alife_role or "member" }
        local f = H.alifeAdapter
        if not check("alife_native_primary_baseline", f.nativeCount == 1 and getSpecificPlayer(1) == nil
            and getSpecificPlayer(2) == nil and getSpecificPlayer(3) == nil and not SC.ALifeAdapter.idFor(player),
            "read-only native count and actual slot occupants; " .. isolationDetail(f, P)) then setPhase("finish", current) return end
        if H.config.project_alife_scenario == "performance" then
            for _, record in ipairs(SC.Registry.snapshot()) do
                if not SC.Actor.remove(record.actor) then finish(H, current, result, setPhase, false, "cohort cleanup failed") return end
            end
        end
        require "SCBanditsCombatAcceptance"
        local shared = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.shared
        f.scene = shared.field(SC, player, 24, 44)
        if not f.scene then finish(H, current, result, setPhase, false, "No surveyed outdoor combat corridor") return end
        player:setX(f.scene.observer:getX() + 0.5)
        player:setY(f.scene.observer:getY() + 0.5)
        player:setZ(f.scene.observer:getZ())
        player:setCurrentSquareFromPosition()
        if f.role == "member" or f.role == "resident" then
            local square = f.scene.fellow
            if not square then finish(H, current, result, setPhase, false, "No clear outdoor native LF spawn") return end
            local ticket, reason = SC.Actor.beginSpawn(square, { recruited = true,
                identity = { forename = "Aster", surname = "Green", gender = "woman", outfit = "Generic01" } })
            if not ticket then finish(H, current, result, setPhase, false, tostring(reason)) return end
            f.ticket = ticket
        else
            -- Reuse the private role fixture, not Bandits' spawning or actors.
            H.config.bandits_lf_role = f.role
        end
        setPhase("alife_adapter_lf", current)
    elseif H.phase == "alife_adapter_lf" then
        local f = H.alifeAdapter
        local actor, reason
        if f.ticket then actor, reason = SC.Actor.pollSpawn(f.ticket)
        else
            require "SCBanditsAdapterProbe"
            local roles = SCRealSandboxHarnessProbes.SCBanditsAdapterProbe
            local ready, record, why = roles.roleRecord(H, SC, f.player)
            actor, reason = ready and record and record.actor, why
        end
        if not actor then
            if current - H.phaseStartedAt > 30000 then finish(H, current, result, setPhase, false, "LF spawn: " .. tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        if f.role == "resident" then SC.BaseLife.assign(f.id, "generalist", false) end
        if f.role == "member" or f.role == "resident" then
            local accepted, why = SC.Commands.issue(f.id, "stay", {}, f.player)
            if not check("alife_stay_command", accepted == true, tostring(why)) then setPhase("finish", current) return end
        end
        local commands = SC.Commands.peek(actor)
        commands.combatDoctrine, commands.combatMode, commands.holdFire = "weapons_free", "aggressive", true
        SC.Commands.persist(actor)
        local weaponType = H.config.project_alife_weapon == "melee" and "Base.BaseballBat" or "Base.Pistol"
        f.expectedWeapon, f.exactHits = weaponType, 0
        if weaponType == "Base.BaseballBat" then f.meleeWeapon = actor:getInventory():AddItem(weaponType) end
        local weapon = actor:getInventory():AddItem("Base.Pistol")
        if not weapon then finish(H, current, result, setPhase, false, "Real weapon unavailable") return end
        if weapon:isRanged() then
            local clip = weapon:getClipSize()
            for _ = 1, 2 do
                local magazine = actor:getInventory():AddItem(tostring(weapon:getMagazineType()))
                if magazine then magazine:setCurrentAmmoCount(clip) end
            end
            weapon:setContainsClip(true)
            weapon:setCurrentAmmoCount(clip)
            weapon:setRoundChambered(true)
            weapon:setJammed(false)
        else
            commands.holdFire = false
            SC.Commands.persist(actor)
        end
        actor:setPrimaryHandItem(weapon)
        f.beforeLF, f.outgoing, f.woundsBefore = call(actor:getBodyDamage(), "getOverallBodyHealth"), 0, SC.ALifeAdapter.status().wounds
        local square
        if f.role == "member" or f.role == "resident" then
            square = getCell():getGridSquare(f.scene.fellow:getX() + f.scene.direction[1] * 2,
                f.scene.fellow:getY() + f.scene.direction[2] * 2, f.scene.fellow:getZ())
        else square = openPoint(SC, actor, 2, 3) end
        if not square then finish(H, current, result, setPhase, false, "No clear A-Life spawn lane") return end
        f.spawn = { x = square:getX(), y = square:getY(), z = square:getZ() }
        f.existing = {}
        for uid in pairs(P.Watchdog.bindings) do f.existing[uid] = true end
        local profileId
        for _, profile in ipairs(P.Catalog.current.npcOrder or {}) do
            if profile.weapons and profile.weapons.primary == "Base.Pistol" and profile.ammo
                and (tonumber(profile.ammo.primary) or 0) > 0 and not P.LoadoutProgression.noncombat(profile) then
                profileId = profile.id break
            end
        end
        if not profileId then finish(H, current, result, setPhase, false, "No armed stock A-Life profile") return end
        f.requestId = "lf-adapter:" .. tostring(current)
        local accepted, why = P.DebugService.spawnEncounter(f.player, {
            requestId = f.requestId, count = 1, mode = "roam",
            profileId = profileId,
            x = f.spawn.x, y = f.spawn.y, z = f.spawn.z, radius = 8, distance = 0,
            playerKeepOut = 0, spawnDelayMs = 0, arrival = "instant",
            slots = { { x = f.spawn.x + 0.5, y = f.spawn.y + 0.5, z = f.spawn.z } },
            playerStance = "neutral", stationary = true, persistent = true,
            health = 100, damageOutput = 3,
        }, true)
        if not accepted then finish(H, current, result, setPhase, false, "A-Life spawn: " .. tostring(why)) return end
        result("PASS", "alife_fixture", "owner spawner; surveyed clear lane; observer relocated only in clone; native " .. weaponType
            .. "; pistol has two magazines and Hold Fire until first incoming wound; melee equips its real bat after that wound; authored A-Life damageOutput=3; ordinary zombies retained; role=" .. f.role)
        setPhase("alife_adapter_foreign", current)
    elseif H.phase == "alife_adapter_foreign" then
        local f = H.alifeAdapter
        local outcome = P.DebugService.groupStatus(f.requestId)
        for _, uid in ipairs(outcome and outcome.actorUids or {}) do
            local binding = P.Watchdog.bindings[uid]
            if not f.existing[uid] and binding and binding.shell and SC.ALifeAdapter.owns(binding.shell) then
                f.uid, f.shell = uid, binding.shell break
            end
        end
        if not f.shell then
            if current - H.phaseStartedAt > 30000 then finish(H, current, result, setPhase, false, "A-Life shell did not materialize") end
            return
        end
        local nativeRecord = P.ActorRegistry.peek(f.uid)
        if not nativeRecord or nativeRecord.lifecycle ~= "active"
            or SC.ALifeAdapter.relationship(f.shell, f.actor) == "unknown" then
            if current - H.phaseStartedAt > 45000 then finish(H, current, result, setPhase, false, "A-Life initialization timeout") end
            return
        end
        if f.role == "household" and H.config.project_alife_observe_household == "true" and not f.observerReady then
            local observer = openPoint(SC, f.shell, 3, 6)
            if not observer then finish(H, current, result, setPhase, false, "No clear household observer position") return end
            f.player:setX(observer:getX() + 0.5)
            f.player:setY(observer:getY() + 0.5)
            f.player:setZ(observer:getZ())
            f.player:setCurrentSquareFromPosition()
            f.observerReady = current + 2000
            return
        end
        if f.observerReady and current < f.observerReady then return end
        local alias = SC.ALifeAdapter.idFor(f.actor)
        P.Combat.faceTarget(f.shell, f.actor)
        check("alife_native_identity", alias == "lf:" .. f.id and P.Reputation.playerKey(f.actor) == alias
            and P.Reputation.playerKey(f.player) == f.key, "distinct LF identity and untouched primary key")
        check("alife_initial_neutral", SC.ALifeAdapter.relationship(f.shell, f.actor) == "neutral", "native neutral scene before provocation")
        if not check("alife_native_scene", P.Health.invulnerable(f.shell) ~= true and f.actor:isNpc() == true,
            "A-Life invulnerable=" .. tostring(P.Health.invulnerable(f.shell)) .. "; LF native NPC=" .. tostring(f.actor:isNpc())
                .. "; primary sees target=" .. tostring(SC.GameplayUtil.canSee(f.player, f.shell))) then
            setPhase("finish", current) return
        end
        if H.config.project_alife_scenario == "reload_stage" then
            local proof = ModData.getOrCreate("LF_ALIFE_ACCEPTANCE")
            proof.id, proof.alias, proof.uid, proof.items = f.id, alias, f.uid, inventoryProof(SC, f.actor)
            proof.key, proof.nativeCount, proof.nativeSize = f.key, f.nativeCount, f.nativeSize
            check("alife_reload_saved", SC.Runtime.save() == true, "LF saved through existing persistence; clone-only proof stores primitive identities")
            finish(H, current, result, setPhase, true, "reload stage; LF=" .. alias .. "; A-Life=" .. f.uid)
            return
        elseif H.config.project_alife_scenario == "performance" then
            setPhase("alife_adapter_performance", current) return
        end
        P.HostileAct.writeWindow({ f.uid }, alias, current)
        result("PASS", "alife_targeted_fixture", "owner HostileAct window for exact LF alias; no player reputation mutation; other LF actors remain in normal play")
        f.beforeForeign = P.ShellSimulation.trueHealth(f.shell)
        f.hitObserver = function(body, attacker)
            if body == f.shell and attacker == f.actor then f.outgoing = f.outgoing + 1 end
        end
        Events.ProjectALife_NpcHit.Add(f.hitObserver)
        f.nativeHitObserver = function(body, attacker, part, weapon)
            if attacker == f.actor then
                if body == f.shell and call(weapon, "getFullType") == f.expectedWeapon then f.exactHits = f.exactHits + 1 end
                print("SC_REAL_SANDBOX|ALIFE_NATIVE_IMPACT|selected=" .. tostring(body == f.shell)
                    .. "|body=" .. tostring(body) .. "|part=" .. tostring(part)
                    .. "|weapon=" .. tostring(call(weapon, "getFullType"))
                    .. "|foreignHealth=" .. tostring(P.ShellSimulation.trueHealth(f.shell)))
            end
        end
        Events.OnHitZombie.Add(f.nativeHitObserver)
        f.swingObserver = function(attacker, weapon)
            if attacker ~= f.actor then return end
            local okay, los = pcall(LosUtil.lineClear, getCell(), math.floor(f.actor:getX()), math.floor(f.actor:getY()), math.floor(f.actor:getZ()),
                math.floor(f.shell:getX()), math.floor(f.shell:getY()), math.floor(f.shell:getZ()), false)
            print("SC_REAL_SANDBOX|ALIFE_NATIVE_SWING|los=" .. tostring(okay and los)
                .. "|shootable=" .. tostring(call(f.shell, "isShootable"))
                .. "|god=" .. tostring(call(f.shell, "isGodMod"))
                .. "|inCell=" .. tostring(getCell():getObjectList():contains(f.shell))
                .. "|weapon=" .. tostring(call(weapon, "getFullType"))
                .. "|aim=" .. tostring(call(f.actor, "getCompanionRangedReadiness")))
        end
        Events.OnWeaponSwingHitPoint.Add(f.swingObserver)
        setPhase("alife_adapter_combat", current)
    elseif H.phase == "alife_adapter_combat" then
        local f, status = H.alifeAdapter, SC.ALifeAdapter.status()
        local afterLF = call(f.actor:getBodyDamage(), "getOverallBodyHealth")
        local afterForeign = P.ShellSimulation.trueHealth(f.shell)
        local receipt = call(f.actor, "getCompanionAttackReceiptSerial")
        if receipt ~= f.receipt then
            f.receipt = receipt
            print("SC_REAL_SANDBOX|ALIFE_NATIVE_RECEIPT|serial=" .. tostring(receipt)
                .. "|outcome=" .. tostring(call(f.actor, "getCompanionAttackReceiptOutcome"))
                .. "|hits=" .. tostring(call(f.actor, "getCompanionAttackCollisionHitCount"))
                .. "|selected=" .. tostring(call(f.actor, "getCompanionAttackCollisionTarget") == f.shell)
                .. "|targetHit=" .. tostring(call(f.actor, "didCompanionAttackCollisionHitTarget"))
                .. "|npc=" .. tostring(f.actor:isNpc())
                .. "|targetHealth=" .. tostring(afterForeign)
                .. "|shellHealth=" .. tostring(f.shell:getHealth())
                .. "|invulnerable=" .. tostring(P.Health.invulnerable(f.shell)))
        end
        if current >= (f.nextTrace or 0) then
            f.nextTrace = current + 2000
            local held = P.Perception.engagements[f.uid]
            local decision = SC.Decision.peek(f.actor) or {}
            local nativeRecord = P.ActorRegistry.peek(f.uid)
            local refusal = P.Perception.playerRefusal(nativeRecord, f.shell, f.actor, 50, false, current)
            local nativeState = P.DecisionLoop.states[f.uid]
            print("SC_REAL_SANDBOX|ALIFE_ADAPTER|role=" .. f.role .. "|LF=" .. tostring(afterLF)
                .. "|id=" .. f.id .. "|LFpos=" .. tostring(f.actor:getX()) .. "," .. tostring(f.actor:getY())
                .. "|foreign=" .. tostring(afterForeign) .. "|outgoing=" .. f.outgoing
                .. "|wounds=" .. status.wounds .. "|relation=" .. SC.ALifeAdapter.relationship(f.shell, f.actor)
                .. "|targetLF=" .. tostring(held and held.target == f.actor)
                .. "|foreignPhase=" .. tostring(f.shell:getModData().ProjectALifeCombatPhase)
                .. "|refusal=" .. tostring(refusal) .. "|state=" .. tostring(nativeState and nativeState.kind)
                .. ":" .. tostring(nativeState and nativeState.intent)
                .. "|weapon=" .. tostring(call(P.Combat.weaponFor(f.shell), "getFullType"))
                .. "|LFweapon=" .. tostring(call(f.actor:getPrimaryHandItem(), "getFullType"))
                .. "|LFammo=" .. tostring(call(f.actor:getPrimaryHandItem(), "getCurrentAmmoCount"))
                .. "|LFreceipt=" .. tostring(call(f.actor, "getCompanionAttackReceiptOutcome"))
                .. "|foreignPos=" .. tostring(f.shell:getX()) .. "," .. tostring(f.shell:getY())
                .. "|LFaim=" .. tostring(call(f.actor, "getCompanionRangedReadiness"))
                .. "|LFintent=" .. tostring(decision.intent))
        end
        local incoming = status.wounds > f.woundsBefore and afterLF and afterLF < f.beforeLF
        local outgoing = f.outgoing > 0 and f.exactHits > 0 and afterForeign < f.beforeForeign
        if incoming and not f.fireReleased then
            if f.meleeWeapon then f.actor:setPrimaryHandItem(f.meleeWeapon) end
            local commands = SC.Commands.peek(f.actor)
            commands.holdFire = false
            SC.Commands.persist(f.actor)
            f.fireReleased = true
            result("PASS", "alife_incoming_wound", "owner applied native wound to exact LF body; release Hold Fire for reciprocal response")
        end
        if incoming and outgoing then
            check("alife_main_player_isolation", getSpecificPlayer(0) == f.player and nativeCount() == f.nativeCount
                and IsoPlayer.getPlayers():size() == f.nativeSize and P.Reputation.playerKey(f.player) == f.key,
                "player slots, primary actor and reputation key unchanged" .. isolationDetail(f, P))
            finish(H, current, result, setPhase, true, "role=" .. f.role .. "; weapon=" .. f.expectedWeapon
                .. "; exact native hits=" .. f.exactHits .. "; outgoing owner hits=" .. f.outgoing
                .. "; incoming native wounds=" .. (status.wounds - f.woundsBefore)
                .. "; LF=" .. f.beforeLF .. "->" .. afterLF .. "; A-Life=" .. f.beforeForeign .. "->" .. afterForeign)
        elseif current - H.phaseStartedAt > 150000 or f.actor:isDead() or f.shell:isDead() then
            finish(H, current, result, setPhase, false, "role=" .. f.role .. "; incoming=" .. tostring(incoming)
                .. "; outgoing=" .. tostring(outgoing) .. "; LFdead=" .. tostring(f.actor:isDead()) .. "; foreignDead=" .. tostring(f.shell:isDead()))
        end
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCALifeAdapterProbe = Probe
return Probe
