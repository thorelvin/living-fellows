-- SPDX-License-Identifier: MIT
-- Explicit disposable fixture: one stock Bandits clan member, one controlled
-- wound transaction, then ordinary production AI. No zombie clearing/healing.
local Probe = {}
local function call(actor, method, ...)
    if actor == nil or type(actor[method]) ~= "function" then return nil end
    local okay, value = pcall(actor[method], actor, ...)
    if okay then return value end
end
local function health(actor)
    return call(call(actor, "getBodyDamage"), "getOverallBodyHealth")
end
local function partHealth(actor)
    local parts = call(call(actor, "getBodyDamage"), "getBodyParts")
    if not parts then return nil end
    local total = 0
    for index = 0, parts:size() - 1 do total = total + parts:get(index):getHealth() end
    return total
end
local function playerSnapshot(source)
    local members = {}
    for index = 0, source:size() - 1 do members[index + 1] = source:get(index) end
    return members
end
local function samePlayers(fixture)
    local actual = IsoPlayer.getPlayers()
    if actual:size() ~= fixture.playerCount then return false end
    for index = 0, actual:size() - 1 do
        if actual:get(index) ~= fixture.players[index + 1] then return false end
    end
    return getSpecificPlayer(0) == fixture.player and IsoPlayer.numPlayers == fixture.nativeNumPlayers
end
local function cleanup(fixture)
    if fixture and fixture.hitObserver then Events.OnHitZombie.Remove(fixture.hitObserver) end
end
local function finish(H, result, setPhase, current, okay, label, detail)
    if H.banditsAdapter and H.banditsAdapter.bandit then
        getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-" .. label .. ".png")
    end
    cleanup(H.banditsAdapter)
    result(okay and "PASS" or "FAIL", label, detail)
    setPhase("finish", current)
end
local function openApproach(SC, actor, destination)
    local start = actor:getSquare()
    local dx, dy = destination:getX() - start:getX(), destination:getY() - start:getY()
    local steps, previous = math.max(math.abs(dx), math.abs(dy)), start
    for index = 1, steps do
        local square = getCell():getGridSquare(start:getX() + math.floor(dx * index / steps + 0.5),
            start:getY() + math.floor(dy * index / steps + 0.5), start:getZ())
        if not square then return false end
        local edge = SC.Topology.classifyEdge(actor, previous, square, {})
        if not edge.traversable or edge.affordance ~= "open" then return false end
        previous = square
    end
    return true
end
local function roleRecord(H, SC, player)
    local role = H.config.bandits_lf_role or "saved"
    if role == "saved" then return true end
    if role == "resident" then
        for _, record in ipairs(SC.Registry.snapshot()) do
            if SC.BaseLife.resident(record.id) and SC.GameplayUtil.isValidActor(record.actor) then
                return true, record
            end
        end
        return false, nil, "no_loaded_camp_resident"
    end
    if not H.banditsRoleGroup then
        if role == "household" then
            local okay, id = SC.Factions.debugSpawnHousehold(player, 1)
            if not okay then return false, nil, id end
            H.banditsRoleGroup = SC.Factions.group(id)
        else
            local point
            for radius = 12, 25 do
                for _, offset in ipairs({ { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }) do
                    local square = getCell():getGridSquare(math.floor(player:getX() + offset[1]),
                        math.floor(player:getY() + offset[2]), math.floor(player:getZ()))
                    if square and square:getRoom() == nil and SC.GameplayUtil.isClearActorSpawnSquare(square) then
                        point = { x = square:getX(), y = square:getY(), z = square:getZ() } break
                    end
                end
                if point then break end
            end
            if not point then return false, nil, "no_loaded_outdoor_scene" end
            local group, reason = SC.Factions.createOddballGroup({
                kind = "roamer", spawn = point, anchor = point,
                house = { id = "bandits-live-corey", anchor = point,
                    bounds = { x1 = point.x - 8, x2 = point.x + 8,
                        y1 = point.y - 8, y2 = point.y + 8, z = point.z },
                    interior = { point }, openings = {}, roomGroup = "outdoor_fixture" },
            }, SC.Oddballs.definition("fan_corey_biggs"), true)
            if not group then return false, nil, reason end
            H.banditsRoleGroup = group
        end
    end
    local member = H.banditsRoleGroup.members[1]
    return member.actorId ~= nil, member.actorId and SC.Registry.byId(member.actorId), "waiting_for_native_actor"
end
local function performance(H, current, check, result, setPhase, SC)
    local fixture = H.banditsPerformance
    if not fixture then
        if current - H.startedAt < 10000 then return end
        if not SC.State.active or SC.Registry.count() == 0 then return end
        local player = getSpecificPlayer(0)
        fixture = { player = player, players = playerSnapshot(IsoPlayer.getPlayers()), nativeNumPlayers = IsoPlayer.numPlayers,
            counts = { 1, 4, 16 }, index = 1, actors = {}, before = {}, queued = false }
        fixture.playerCount = IsoPlayer.getPlayers():size()
        H.banditsPerformance = fixture
        for id in pairs(BanditZombie.Cache) do fixture.before[id] = true end
        -- Cohort construction only in this disposable clone, through the
        -- ordinary actor ownership service. No registry-only actors or slots.
        for _, record in ipairs(SC.Registry.snapshot()) do
            if not SC.Actor.remove(record.actor) then
                finish(H, result, setPhase, current, false, "bandits_perf_remove", "fixture could not clear saved LF roster") return
            end
        end
        result("PASS", "bandits_perf_fixture", "replace cloned LF roster with native 1/4/16 cohorts; ordinary zombies retained")
    end
    local wanted = fixture.counts[fixture.index]
    if #fixture.actors < wanted then
        if fixture.ticket then
            local actor, reason = SC.Actor.pollSpawn(fixture.ticket)
            if actor then
                fixture.actors[#fixture.actors + 1] = actor
                fixture.ticket = nil
            elseif reason ~= "spawn_pending" then
                finish(H, result, setPhase, current, false, "bandits_perf_spawn", tostring(reason))
            end
            return
        end
        local point
        for radius = 4, 20 do
            for _, offset in ipairs({ { radius, 0 }, { -radius, 0 }, { 0, radius }, { 0, -radius } }) do
                local square = getCell():getGridSquare(math.floor(fixture.player:getX() + offset[1]),
                    math.floor(fixture.player:getY() + offset[2]), math.floor(fixture.player:getZ()))
                if square and SC.GameplayUtil.isSquareFree(square)
                    and SC.GameplayUtil.isClearActorSpawnSquare(square) then
                    local separate = true
                    for _, actor in ipairs(fixture.actors) do
                        if SC.GameplayUtil.distance(actor, square) < 2 then separate = false break end
                    end
                    if separate then point = square break end
                end
            end
            if point then break end
        end
        if not point then finish(H, result, setPhase, current, false, "bandits_perf_site", "no loaded native spawn tile") return end
        local ticket, reason = SC.Actor.beginSpawn(point, { recruited = true, identity = SC.Spawn.generateIdentity() })
        if not ticket then finish(H, result, setPhase, current, false, "bandits_perf_ticket", tostring(reason)) return end
        fixture.ticket = ticket
        return
    end
    if not fixture.queued then
        local clan
        for id in pairs(BanditCustom.ClanGetAll()) do clan = id break end
        local actor = fixture.actors[1]
        BanditServer.Spawner.Clan(fixture.player, { cid = clan, size = 1, hostile = false, hostileP = false,
            spawnPoints = { { x = math.floor(actor:getX()) + 2, y = math.floor(actor:getY()), z = math.floor(actor:getZ()) } } })
        fixture.queued, fixture.spawnAt = true, current
        return
    end
    if not fixture.bandit then
        for id, actor in pairs(BanditZombie.Cache) do
            if not fixture.before[id] and SC.BanditsAdapter.owns(actor) then fixture.bandit = actor break end
        end
        if not fixture.bandit and current - fixture.spawnAt > 20000 then
            finish(H, result, setPhase, current, false, "bandits_perf_bandit", "native Bandit did not initialize")
        end
        return
    end
    if SC.Registry.count() ~= wanted or call(fixture.bandit, "isDead") == true then
        finish(H, result, setPhase, current, false, "bandits_perf_population",
            "wanted=" .. wanted .. "; actual=" .. SC.Registry.count()
                .. "; bandit_dead=" .. tostring(call(fixture.bandit, "isDead"))) return
    end
    if not fixture.sample then
        if not fixture.withAdapter then SC.BanditsAdapter.reset() else SC.BanditsAdapter.initialize() end
        fixture.sample = { at = current + 1000, calls = 0, queryMs = 0, frames = 0, frameMs = 0, prior = nil }
        return
    end
    local sample = fixture.sample
    if current < sample.at then return end
    if sample.prior then sample.frameMs = sample.frameMs + current - sample.prior end
    sample.prior, sample.frames = current, sample.frames + 1
    local start = getTimestampMs()
    for _ = 1, 200 do BanditPlayer.GetPlayers() end
    sample.queryMs = sample.queryMs + getTimestampMs() - start
    sample.calls = sample.calls + 200
    if current - sample.at < 3000 then return end
    local mode = fixture.withAdapter and "with" or "without"
    check("bandits_perf_" .. wanted .. "_" .. mode, samePlayers(fixture),
        "native LF=" .. wanted .. "; stock Bandit engine=" .. tostring(Bandit.Engine)
            .. "; calls=" .. sample.calls .. "; query_ms=" .. sample.queryMs
            .. "; mean_frame_ms=" .. (sample.frameMs / math.max(1, sample.frames - 1))
            .. "; controlled query workload, not an FPS guarantee")
    fixture.sample = nil
    if not fixture.withAdapter then fixture.withAdapter = true return end
    fixture.index, fixture.withAdapter = fixture.index + 1, false
    if fixture.index > #fixture.counts then
        finish(H, result, setPhase, current, SC.BanditsAdapter.initialize(), "bandits_performance_complete",
            "one active stock Bandit; real native LF cohorts; normal player slots unchanged")
    end
end
function Probe.step(H, current, check, result, setPhase)
    local scenario = H.config.bandits_combat_scenario
    if scenario == "solid_wall" then
        require "SCBanditsWallAcceptance"
        return SCRealSandboxHarnessProbes.SCBanditsWallAcceptance.step(H, current, check, result, setPhase)
    end
    if scenario == "protected_lane" then
        require "SCBanditsProtectedLaneAcceptance"
        return SCRealSandboxHarnessProbes.SCBanditsProtectedLaneAcceptance.step(H, current, check, result, setPhase)
    end
    if scenario == "vehicle_window" or scenario == "vehicle_bullets" then
        require "SCBanditsVehicleAcceptance"
        return SCRealSandboxHarnessProbes.SCBanditsVehicleAcceptance.step(H, current, check, result, setPhase)
    end
    if scenario == "lifecycle" then
        require "SCBanditsLifecycleAcceptance"
        return SCRealSandboxHarnessProbes.SCBanditsLifecycleAcceptance.step(H, current, check, result, setPhase)
    end
    if scenario == "melee" or scenario == "unarmed" or scenario == "infected" then
        require "SCBanditsCloseCombatAcceptance"
        return SCRealSandboxHarnessProbes.SCBanditsCloseCombatAcceptance.step(H, current, check, result, setPhase)
    end
    if H.config.bandits_combat_scenario and H.config.bandits_combat_scenario ~= "legacy" then
        require "SCBanditsCombatAcceptance"
        SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance.step(H, current, check, result, setPhase)
        return
    end
    local SC = SurvivorCompanion
    if H.config.bandits_lf_role == "reload" then
        if current - H.startedAt < 10000 or not SC.State.active then return end
        local id = H.config.bandits_expected_lf_id
        local record = SC.Registry.byId(id)
        if not record or not SC.GameplayUtil.isValidActor(record.actor) then
            if current - H.startedAt > 60000 then
                finish(H, result, setPhase, current, false, "bandits_reload_actor", tostring(id))
            end
            return
        end
        local actor = record.actor
        local nativeList = IsoPlayer.getPlayers()
        local fixture = { player = getSpecificPlayer(0), players = playerSnapshot(nativeList),
            nativeNumPlayers = IsoPlayer.numPlayers, playerCount = nativeList:size() }
        local alias = BanditUtils.GetCharacterID(actor)
        check("bandits_reload_identity", alias == "lf:" .. id and BanditPlayer.GetPlayerById(alias) == actor,
            "previous run's persistent UUID resolves to the restored native actor: " .. tostring(alias))
        check("bandits_reload_primary", BanditUtils.GetCharacterID(fixture.player) == 1 and samePlayers(fixture),
            "native main player/slots remain unchanged after loading the Bandits-enabled clone")
        local recognized = 0
        for _, bandit in pairs(BanditZombie.Cache) do
            if SC.BanditsAdapter.owns(bandit) then recognized = recognized + 1 end
        end
        check("bandits_reload_foreign_ownership", recognized > 0,
            "native Bandits after reload=" .. recognized .. "; no actor conversion")
        getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-reload.png")
        finish(H, result, setPhase, current, SC.BanditsAdapter.status().active,
            "bandits_reload_complete", "existing schemas; no persisted alias objects")
        return
    end
    if H.config.bandits_lf_role == "performance" then
        performance(H, current, check, result, setPhase, SC) return
    end
    if H.phase == "bandits_adapter_setup" then
        if not SC.State.active or SC.Registry.count() == 0 then
            if current - H.startedAt > 60000 then
                finish(H, result, setPhase, current, false, "bandits_runtime_ready", "LF did not start")
            end
            return
        end
        if not H.banditsProfileChecked then
            local status = SC.BanditsAdapter.status()
            print("SC_REAL_SANDBOX|BANDITS_PROFILE|engine=" .. tostring(Bandit.Engine)
                .. "|plain=" .. tostring(getActivatedMods():contains("Bandits2"))
                .. "|prefixed=" .. tostring(getActivatedMods():contains("\\Bandits2")))
            if not check("bandits_adapter_active", status.active == true, tostring(status.reason)) then
                setPhase("finish", current) return
            end
            H.banditsProfileChecked = true
        end
        local player = getSpecificPlayer(0)
        local roleReady, roleActor, roleReason = roleRecord(H, SC, player)
        if not roleReady then
            if current - H.startedAt > 60000 then
                finish(H, result, setPhase, current, false, "bandits_role_fixture", tostring(roleReason))
            end
            return
        end
        local nativeList = IsoPlayer.getPlayers()
        local fixture = { player = player, players = playerSnapshot(nativeList), playerCount = nativeList:size(),
            nativeNumPlayers = IsoPlayer.numPlayers, before = {}, outgoing = 0, outgoingById = {}, startedAt = current }
        H.banditsAdapter = fixture
        local selected, selectedDistance, selectedScore = nil, -1, -1
        local aliases = {}
        for _, record in ipairs(SC.Registry.snapshot()) do
            local actor = record.actor
            if actor and SC.GameplayUtil.isValidActor(actor) then
                local alias = BanditUtils.GetCharacterID(actor)
                if not check("bandits_identity_" .. record.id,
                    alias == "lf:" .. record.id and not aliases[alias]
                        and BanditPlayer.GetPlayerById(alias) == actor,
                    "exact loaded actor; namespaced stable ID") then setPhase("finish", current) return end
                aliases[alias] = actor
                local distance = SC.GameplayUtil.distance(player, actor)
                local score = distance + (call(actor:getSquare(), "getRoom") == nil and 100 or 0)
                if (not roleActor or record == roleActor) and score > selectedScore
                    and distance < 60 and SC.GameplayUtil.sameFloor(player, actor) then
                    selected, selectedDistance, selectedScore = record, distance, score
                end
            end
        end
        if not selected then finish(H, result, setPhase, current, false, "bandits_saved_crew", "No loaded saved actor") return end
        fixture.record, fixture.actor = selected, selected.actor
        check("bandits_lf_role", not roleActor or H.config.bandits_lf_role == "resident"
            and SC.BaseLife.resident(selected.id) ~= nil or SC.Commands.peek(selected.actor).recruited ~= true,
            "role=" .. tostring(H.config.bandits_lf_role or "saved") .. "; faction=" .. tostring(selected.factionId))
        local view = BanditPlayer.GetPlayers()
        check("bandits_native_player_isolation", samePlayers(fixture)
            and getSpecificPlayer(0) == player and BanditUtils.GetCharacterID(player) == 1,
            "derived Bandits list=" .. view:size() .. "; engine list=" .. fixture.playerCount)
        for id in pairs(BanditZombie.Cache) do fixture.before[id] = true end
        local clan, profile
        for id in pairs(BanditCustom.ClanGetAll()) do
            local allArmed, any = true, nil
            for _, candidate in pairs(BanditCustom.GetFromClan(id)) do
                local weapons, ammo = candidate.weapons or {}, candidate.ammo or {}
                if not ((weapons.primary and ammo.primary) or (weapons.secondary and ammo.secondary)) then
                    allArmed = false break
                end
                any = candidate
            end
            if allArmed and any then clan, profile = id, any break end
        end
        if not clan then finish(H, result, setPhase, current, false, "bandits_stock_clan", "No armed official clan loaded") return end
        local actor = fixture.actor
        local square
        local dx, dy = actor:getX() - player:getX(), actor:getY() - player:getY()
        local length = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        for radius = 2, 6 do
            for _, direction in ipairs({ { dx / length, dy / length }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local at = getCell():getGridSquare(math.floor(actor:getX() + direction[1] * radius),
                    math.floor(actor:getY() + direction[2] * radius), math.floor(actor:getZ()))
                if at and SC.GameplayUtil.isSquareFree(at) and SC.GameplayUtil.canSee(actor, at)
                    and openApproach(SC, actor, at) then square = at break end
            end
            if square then break end
        end
        if not square then finish(H, result, setPhase, current, false, "bandits_spawn_square", "No free loaded native square") return end
        BanditServer.Spawner.Clan(player, { cid = clan, size = 1, hostile = false, hostileP = false,
            spawnPoints = { { x = square:getX(), y = square:getY(), z = square:getZ() } } })
        result("PASS", "bandits_stock_spawn_requested", "one member of armed official clan=" .. tostring(clan)
            .. "; LF=" .. selected.id .. "; distance from primary=" .. selectedDistance
            .. "; no loadout/stat/position edits, no zombies removed")
        fixture.spawnAt = current
        setPhase("bandits_adapter_spawn", current)
    elseif H.phase == "bandits_adapter_spawn" then
        local fixture = H.banditsAdapter
        for id, bandit in pairs(BanditZombie.Cache) do
            if not fixture.before[id] and SC.BanditsAdapter.owns(bandit)
                and SC.GameplayUtil.distance(bandit, fixture.actor) < 14 then fixture.bandit = bandit break end
        end
        if not fixture.bandit then
            if current - fixture.spawnAt > 20000 then finish(H, result, setPhase, current,
                false, "bandits_stock_actor", "Spawn did not produce a live Bandit") end
            return
        end
        if current - fixture.spawnAt < 2500 then return end
        local bandit, actor = fixture.bandit, fixture.actor
        -- Initial facing belongs to this explicitly spawned test scene. Leave
        -- its native AI, animation and attack decisions alone afterwards.
        bandit:faceLocationF(actor:getX(), actor:getY())
        if not check("bandits_neutral_human", SC.BanditsAdapter.relationship(bandit, actor) == "neutral"
            and not SC.GameplayUtil.isZombie(bandit), "native Bandits actor is a protected human") then
            setPhase("finish", current) return
        end
        if H.config.bandits_lf_role == "strange_folk_save" then
            finish(H, result, setPhase, current, true, "bandits_save_fixture",
                "native Corey UUID=" .. fixture.record.id .. "; valid roamer site; stock Bandit retained for reload")
            return
        end
        local beforeActor, beforePlayer = partHealth(actor), partHealth(fixture.player)
        local beforeRouted = SC.BanditsAdapter.status().routedDamage
        PlayerDamageModel.BareHandHit(bandit, actor)
        local afterActor, afterPlayer = partHealth(actor), partHealth(fixture.player)
        check("bandits_native_wound_routing", beforeActor and afterActor and afterActor < beforeActor
            and beforePlayer == afterPlayer and SC.BanditsAdapter.status().routedDamage == beforeRouted + 1
            and SC.BanditsAdapter.status().lastVictim == "lf:" .. fixture.record.id,
            "controlled native callback: NPC=" .. tostring(beforeActor) .. "->" .. tostring(afterActor)
                .. "; main=" .. tostring(beforePlayer) .. "->" .. tostring(afterPlayer))
        fixture.baselineRouted = SC.BanditsAdapter.status().routedDamage
        local counters = SC.BanditsAdapter.status()
        fixture.modelsBefore = { bullet = counters.bulletHits, melee = counters.meleeHits, hand = counters.bareHandHits }
        fixture.hitObserver = function(zombie, attacker)
            local id = SC.Registry.idOf(attacker)
            if zombie == bandit and id then
                fixture.outgoing = fixture.outgoing + 1
                fixture.outgoingById[id] = (fixture.outgoingById[id] or 0) + 1
            end
        end
        Events.OnHitZombie.Add(fixture.hitObserver)
        BanditPlayer.CheckFriendlyFire(bandit, actor)
        check("bandits_native_retaliation", Bandit.IsHostile(bandit) == true,
            "confirmed LF aggression uses the Bandits escalation APIs")
        fixture.combatAt, fixture.nextTraceAt = current, current
        setPhase("bandits_adapter_combat", current)
    elseif H.phase == "bandits_adapter_combat" then
        local fixture = H.banditsAdapter
        local status = SC.BanditsAdapter.status()
        if current >= fixture.nextTraceAt then
            fixture.nextTraceAt = current + 1000
            local brain = BanditBrain.Get(fixture.bandit)
            local task = Bandit.GetTask(fixture.bandit)
            local decision = SC.Decision.peek(fixture.actor) or {}
            print("SC_REAL_SANDBOX|BANDITS|ms=" .. (current - fixture.combatAt)
                .. "|LF=" .. tostring(health(fixture.actor)) .. "|bandit=" .. tostring(call(fixture.bandit, "getHealth"))
                .. "|outgoing=" .. fixture.outgoing .. "|routed=" .. status.routedDamage
                .. "|task=" .. tostring(task and task.action) .. ":" .. tostring(task and task.eid)
                .. "|canSeeLF=" .. tostring(call(fixture.bandit, "CanSee", fixture.actor))
                .. "|engine=" .. tostring(Bandit.Engine)
                .. "|banditState=" .. tostring(call(fixture.bandit, "getCurrentStateName"))
                .. "|LFstate=" .. tostring(call(fixture.actor, "getCurrentStateName")))
            print("SC_REAL_SANDBOX|BANDITS_LF|intent=" .. tostring(decision.intent)
                .. "|relation=" .. SC.BanditsAdapter.relationship(fixture.bandit, fixture.actor)
                .. "|distance=" .. SC.GameplayUtil.distance(fixture.actor, fixture.bandit)
                .. "|last_victim=" .. tostring(status.lastVictim)
                .. "|weapon=" .. tostring(call(call(fixture.actor, "getPrimaryHandItem"), "getFullType")))
        end
        local incoming = status.routedDamage > fixture.baselineRouted
        if fixture.outgoing > 0 and incoming then
            local attackers = {}
            for id, count in pairs(fixture.outgoingById) do attackers[#attackers + 1] = id .. ":" .. count end
            table.sort(attackers)
            getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-combat.png")
            check("bandits_native_player_isolation_after_combat", samePlayers(fixture)
                and getSpecificPlayer(0) == fixture.player, "primary player list/count/owner unchanged")
            finish(H, result, setPhase, current, true, "bandits_two_way_native_combat",
                "actual outgoing hit events=" .. fixture.outgoing .. "; stock incoming wound transactions="
                    .. (status.routedDamage - fixture.baselineRouted)
                    .. "; bullet=" .. (status.bulletHits - fixture.modelsBefore.bullet)
                    .. "; melee=" .. (status.meleeHits - fixture.modelsBefore.melee)
                    .. "; hand=" .. (status.bareHandHits - fixture.modelsBefore.hand)
                    .. "; last_victim=" .. tostring(status.lastVictim)
                    .. "; outgoing_by_id=" .. table.concat(attackers, ",") .. "; no forced attack outcomes")
        elseif current - fixture.combatAt > 180000 or call(fixture.actor, "isDead") == true
            or call(fixture.bandit, "isDead") == true then
            finish(H, result, setPhase, current, false, "bandits_two_way_native_combat",
                "outgoing=" .. fixture.outgoing .. "; incoming=" .. tostring(incoming)
                    .. "; LFdead=" .. tostring(call(fixture.actor, "isDead"))
                    .. "; banditDead=" .. tostring(call(fixture.bandit, "isDead")))
        end
    end
end
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCBanditsAdapterProbe = Probe
Probe.roleRecord = roleRecord
return Probe
