-- SPDX-License-Identifier: MIT

-- Project A-Life owns its shells, diplomacy and wounds. This boundary adds LF
-- people to combat perception without publishing them as simulation anchors.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ALifeAdapter = SC.ALifeAdapter or {}
local Adapter = SC.ALifeAdapter
local PREFIX, REJECT = "lf:", "SC_ALIFE_VICTIM_UNAVAILABLE"
local unpackValues = unpack or table.unpack
local bindings, owners = {}, nil
local seen, incarnations = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local contacts = setmetatable({}, { __mode = "k" })
local bodyOwners = setmetatable({}, { __mode = "kv" })
local state, detail, retryable, watching = "absent", "Project A-Life is not enabled", true, false
local lifetime, permission, incarnation = 0, 0, 0
local scope, nextCheck, lastCheck = nil, 0, nil
local roster, rosterAt, rosterVersion = nil, -math.huge, nil
local metrics = { listBuilds = 0, wounds = 0, rejected = 0 }
local listeners = {}
-- Unknown until world initialization: early marked shells remain protected.
local modPresent = nil

local function pack(...) return { n = select("#", ...), ... } end
local function object(value) return type(value) == "table" or type(value) == "userdata" end
local function call(value, name, ...)
    if not object(value) then return nil end
    local okay, method = pcall(function() return value[name] end)
    if not okay or type(method) ~= "function" then return nil end
    local result = pack(pcall(method, value, ...))
    if result[1] then return result[2] end
end
local function now() return type(getTimestampMs) == "function" and getTimestampMs() or 0 end
local function dataOf(actor)
    if call(actor, "hasModData") == false then return nil end
    local data = call(actor, "getModData")
    return type(data) == "table" and data or nil
end
local function enabled(id)
    local mods = type(getActivatedMods) == "function" and getActivatedMods() or nil
    return call(mods, "contains", id) == true or call(mods, "contains", "\\" .. id) == true
end
local function configured()
    return not SC.UserOptions or SC.UserOptions.get("alifeCompatibility") ~= false
end
local function active()
    return state == "active" and configured() and (not SC.State or SC.State.active == true)
end
local function changeState(value, reason, canRetry)
    local changed = state ~= value or detail ~= reason
    if (state == "active") ~= (value == "active") then permission = permission + 1 end
    state, detail, retryable = value, reason, canRetry ~= false
    if changed then
        Adapter.invalidate()
        if value == "unsupported" and SC.Diagnostics then
            SC.Diagnostics.report("alife-adapter", nil, "A-Life adapter unavailable", reason)
        end
    end
end
local function lfIdentity(actor)
    if not object(actor) then return nil end
    local id = SC.Registry and SC.Registry.idOf(actor)
    if not id and not seen[actor] then
        local data = dataOf(actor)
        if data and SC.Actor and type(SC.Actor._isRegistryActor) == "function"
            and SC.Actor._isRegistryActor(actor) then id = data.SC_Id end
    end
    if type(id) == "string" and id:sub(1, 3) == "sc-" then
        seen[actor] = PREFIX .. id
        if not incarnations[actor] then
            incarnation = incarnation + 1
            incarnations[actor] = incarnation
        end
    end
    return seen[actor]
end
local function lfSubject(value)
    if type(value) == "string" then
        if value:sub(1, #PREFIX) ~= PREFIX then return nil end
        local record = SC.Registry and SC.Registry.byId(value:sub(#PREFIX + 1))
        return value, record and record.actor
    end
    return lfIdentity(value), value
end
local function live(actor)
    local alias = lfIdentity(actor)
    local record = alias and SC.Registry and SC.Registry.byId(alias:sub(#PREFIX + 1))
    if not record or record.actor ~= actor or not SC.Registry.isActive(actor, record.id) then return false end
    if call(actor, "isDead") == true or call(actor, "isAlive") == false
        or call(actor, "isExistInTheWorld") == false then return false end
    local health = call(actor, "getHealth")
    if type(health) == "number" and health <= 0 then return false end
    return call(actor, "getSquare") ~= nil
end
local function eligible(actor)
    return live(actor) and call(actor, "isGodMod") ~= true and call(actor, "isInvincible") ~= true
        and call(actor, "isInvisible") ~= true and call(actor, "isGhostMode") ~= true
end
local function primary()
    local player = type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil
    if not player and type(getPlayer) == "function" then player = getPlayer() end
    return player and not lfIdentity(player) and player or nil
end
local function party(actor)
    local alias = lfIdentity(actor)
    local record = alias and SC.Registry and SC.Registry.byId(alias:sub(#PREFIX + 1))
    if not record or record.actor ~= actor then return false end
    if record.recruited == true and record.factionId == nil then return true end
    return SC.BaseLife and type(SC.BaseLife.resident) == "function"
        and SC.BaseLife.resident(record.id) ~= nil or false
end

function Adapter.owns(actor)
    if modPresent == false then return false end
    local data = dataOf(actor)
    if data and (data.ProjectALifeOwned == true or data.ProjectALifeActor == true) then return true end
    local marked = call(actor, "getVariableString", "ALifeActor")
        or call(actor, "GetVariable", "ALifeActor")
    return marked == true or marked == "true"
end
local function readyRecord(shell)
    if not owners or not Adapter.owns(shell) or call(shell, "isDead") == true
        or call(shell, "getSquare") == nil or type(owners.watchdog.bindings) ~= "table" then return nil end
    local data = dataOf(shell)
    local uid = data and data.ProjectALifeUID or call(shell, "getVariableString", "ALifeUID")
    if type(uid) ~= "string" then return nil end
    local okay, record = pcall(owners.registry.peek, uid)
    local binding = owners.watchdog.bindings[uid]
    local generation = data and tonumber(data.ProjectALifeGeneration)
        or tonumber(call(shell, "getVariableString", "ALifeGeneration"))
    if not okay or type(record) ~= "table" or record.uid ~= uid or record.lifecycle ~= "active"
        or type(record.generation) ~= "number" or record.generation ~= record.generation
        or record.generation < 0 or record.generation == math.huge
        or type(binding) ~= "table"
        or binding.shell ~= shell or binding.generation ~= record.generation
        or generation ~= record.generation then return nil end
    return record
end
local function ownHostility(record, actor)
    local alias = lfIdentity(actor)
    if not alias then return false end
    local memory = type(record.memory) == "table" and record.memory or {}
    if type(memory.hostileToPlayerKeys) == "table" and memory.hostileToPlayerKeys[alias] == true then return true end
    if owners.act.live(memory, alias, now()) then return true end
    if owners.reputation.recordedStatus(actor, record) == "hostile" then return true end
    if owners.fair.underAttack(record, actor, now()) then return true end
    return owners.relations.wasAggressor(record, actor, now()) == true
end
local function restrained(record, actor)
    return owners.act.restraint(record, lfIdentity(actor), now()) ~= nil
end

function Adapter.relationship(shell, actor)
    if not active() or not eligible(actor) then return "unknown" end
    local record = readyRecord(shell)
    if not record then return "unknown" end
    local okay, hostile = pcall(owners.relations.hostileToPlayer, record, actor)
    if not okay then changeState("unsupported", "A-Life hostility query failed: " .. tostring(hostile), false) return "unknown" end
    if hostile == true then return "hostile" end
    local valid, stance = pcall(owners.relations.playerStance, record, actor)
    if not valid then changeState("unsupported", "A-Life stance query failed: " .. tostring(stance), false) return "unknown" end
    return stance == "friendly" and "friendly" or "neutral"
end
function Adapter.isAttacking(shell, actor)
    local record = active() and readyRecord(shell)
    if not record or not actor or lfIdentity(actor) and not eligible(actor) then return false end
    local contact = contacts[actor]
    if contact then
        local age = now() - contact.at
        if age >= 0 and age < 5000 and contact.shell == shell
            and contact.uid == record.uid and contact.generation == record.generation then return true end
        if age < 0 or age >= 5000 or contact.uid ~= record.uid
            or contact.generation ~= record.generation then contacts[actor] = nil end
    end
    local held = type(owners.perception.engagements) == "table" and owners.perception.engagements[record.uid]
    local data = dataOf(shell)
    local phase = data and data.ProjectALifeCombatPhase
    return held ~= nil and held.target == actor and (phase == "aim" or phase == "windup")
end
function Adapter.idFor(actor) return lfIdentity(actor) end
function Adapter.resolve(id)
    if type(id) ~= "string" or id:sub(1, #PREFIX) ~= PREFIX then return nil end
    local alias, actor = lfSubject(id)
    return active() and alias and eligible(actor) and actor or nil
end
function Adapter.invalidate()
    roster, rosterAt, rosterVersion = nil, -math.huge, nil
end
function Adapter.status()
    return { state = state, active = active(), reason = detail, profile = "ProjectALife/1.4.6/42.21",
        listBuilds = metrics.listBuilds, wounds = metrics.wounds, rejected = metrics.rejected,
        lastVictim = metrics.lastVictim }
end

local function rosterView()
    local current, version = now(), SC.Registry and SC.Registry.version() or 0
    if roster and version == rosterVersion and current >= rosterAt and current - rosterAt < 250 then return roster end
    local rows = {}
    if SC.Registry then
        for _, record in ipairs(SC.Registry.snapshot()) do
            if eligible(record.actor) then
                rows[#rows + 1] = record.actor
                local body = call(record.actor, "getBodyDamage")
                if body then bodyOwners[body] = record.actor end
            end
        end
    end
    roster, rosterAt, rosterVersion = rows, current, version
    metrics.listBuilds = metrics.listBuilds + 1
    return rows
end
local function bind(owner, key, factory, transient)
    local binding = { owner = owner, key = key, original = owner[key], current = true, transient = transient }
    binding.wrapper = factory(binding.original, binding)
    owner[key] = binding.wrapper
    bindings[#bindings + 1] = binding
    return binding
end
local function bindAvailable(owner, key, factory)
    if type(owner) ~= "table" or type(owner[key]) ~= "function" then return end
    for _, binding in ipairs(bindings) do
        if binding.owner == owner and binding.key == key and binding.current then return end
    end
    bind(owner, key, factory)
end
local function perceptionProvider()
    local adapters = owners.perception.adapters
    local locate = owners.locator.list
    if type(adapters) ~= "table" then return false end
    for _, binding in ipairs(bindings) do
        if binding.owner == adapters and binding.key == "players" and binding.current then return true end
    end
    if adapters.players ~= nil and type(adapters.players) ~= "function" then return false end
    bind(adapters, "players", function(original, binding)
        return function(...)
            local okay, source
            if original then okay, source = pcall(original, ...)
            else okay, source = pcall(locate) end
            if not okay or type(source) ~= "table" or #source > 64 then
                if binding.current then changeState("unsupported", "A-Life perception returned an invalid player list", false) end
                return {}
            end
            local result, included = {}, {}
            local function add(actor)
                if actor and not included[actor] then result[#result + 1], included[actor] = actor, true end
            end
            for _, actor in ipairs(source) do
                if not object(actor) or call(actor, "getSquare") == nil then
                    if binding.current then changeState("unsupported", "A-Life perception returned an invalid actor", false) end
                    return {}
                end
                if not lfIdentity(actor) or binding.current and active() and eligible(actor) then add(actor) end
            end
            if binding.current and active() then
                for _, actor in ipairs(rosterView()) do if eligible(actor) then add(actor) end end
            end
            return result
        end
    end, true)
    return true
end
local function guardVictim(body)
    local actor = call(body, "getParentChar") or bodyOwners[body]
    if scope and scope.body == body and scope.victim and actor ~= scope.victim then
        scope.rejected = true
        metrics.rejected = metrics.rejected + 1
        error(REJECT, 0)
    end
    if not lfIdentity(actor) then return end
    local source = scope and readyRecord(scope.shell)
    if not scope or scope.lifetime ~= lifetime or scope.permission ~= permission
        or not active() or not eligible(actor) or call(actor, "getBodyDamage") ~= body
        or not source or source.uid ~= scope.uid or source.generation ~= scope.generation then
        metrics.rejected = metrics.rejected + 1
        if scope then scope.rejected = true end
        -- The stock caller falls back to AddDamage on a false return. Abort
        -- instead; the outer attack guard recognizes only our own rejection.
        error(REJECT, 0)
    end
end
local function installListeners()
    local epoch = lifetime
    for _, name in ipairs({ "ProjectALife_NpcSpawned", "ProjectALife_NpcDied", "ProjectALife_NpcHit" }) do
        local event = type(Events) == "table" and Events[name] or nil
        if not event or type(event.Add) ~= "function" or type(event.Remove) ~= "function" then return false end
        local previous = listeners[name]
        if previous and previous.event ~= event then return false end
        if not previous then
            local key = name
            local callback = function(body, attacker, damage)
                if epoch ~= lifetime or not watching or not active() then return end
                if key == "ProjectALife_NpcHit" then
                    if type(damage) ~= "number" or damage ~= damage or damage <= 0 or damage == math.huge then return end
                    local utility = SC.GameplayUtil
                    local runtime = lfIdentity(attacker) and utility
                        and type(utility.peekActorState) == "function" and utility.peekActorState(attacker)
                    if runtime and runtime.senses then runtime.senses.alifeNpcsDirty = true end
                else
                    Adapter.invalidate()
                    if key == "ProjectALife_NpcDied" then
                        for actor, contact in pairs(contacts) do if contact.shell == body then contacts[actor] = nil end end
                    end
                end
            end
            if not pcall(event.Add, callback) then return false end
            listeners[name] = { event = event, callback = callback }
        end
    end
    return true
end
local function installIdentity(profile)
    bindAvailable(profile.reputation, "playerKey", function(original)
        return function(actor, ...) return lfIdentity(actor) or original(actor, ...) end
    end)
    bindAvailable(profile.policy, "identityOf", function(original)
        return function(actor, ...)
            local alias = lfIdentity(actor)
            if alias then return alias, incarnations[actor], nil end
            return original(actor, ...)
        end
    end)
    bindAvailable(profile.policy, "canAttack", function(original, binding)
        return function(actor, ...)
            if lfIdentity(actor) and (not binding.current or not active() or not eligible(actor)) then
                return false, "lf_target_unavailable"
            end
            return original(actor, ...)
        end
    end)
end
local function installRelations()
    for _, name in ipairs({ "recordedStatus", "baselineFor" }) do
        local key = name
        bind(owners.reputation, key, function(original, binding)
            return function(value, faction, ...)
                local alias, actor = lfSubject(value)
                if alias and not binding.current then
                    return key == "baselineFor" and "neutral" or nil
                end
                if alias and binding.current and active() then
                    if actor and party(actor) then
                        local player = primary()
                        if not player then return nil end
                        return original(player, faction, ...)
                    elseif key == "baselineFor" then return "neutral" end
                end
                return original(value, faction, ...)
            end
        end)
    end
    bind(owners.reputation, "escalate", function(original, binding)
        return function(value, victim, deed, ...)
            local alias, actor = lfSubject(value)
            if not alias then return original(value, victim, deed, ...) end
            if not binding.current or not active() or not eligible(actor) then return false, "lf_actor_unavailable" end
            if party(actor) then
                local record = owners.relations.actorRecord(victim)
                if record and owners.relations.isSelfDefence(actor, record) then return false, "self_defence" end
                local player = primary()
                if not player then return false, "primary_player_unavailable" end
                return original(player, victim, deed, ...)
            end
            return original(value, victim, deed, ...)
        end
    end)
    bind(owners.relations, "baselineStance", function(original, binding)
        return function(record, actor, ...)
            if lfIdentity(actor) and not binding.current then return "neutral", "lf_adapter_unavailable" end
            if lfIdentity(actor) and binding.current and active() then
                if not party(actor) then return "neutral", "lf_independent" end
                return original(record, primary(), ...)
            end
            return original(record, actor, ...)
        end
    end)
    for _, name in ipairs({ "hostileToPlayer", "basePlayerStance" }) do
        local key = name
        bind(owners.relations, key, function(original, binding)
            return function(record, actor, ...)
                if not lfIdentity(actor) then return original(record, actor, ...) end
                if not binding.current or not active() or not eligible(actor) then
                    if key == "hostileToPlayer" then return false, "lf_actor_unavailable" end
                    return "neutral"
                end
                if not party(actor) then
                    if type(record) ~= "table" or not ownHostility(record, actor) then
                        if key == "hostileToPlayer" then return false, "lf_independent_neutral" end
                        return "neutral"
                    end
                    -- Respect the owner's explicit truce window even when a
                    -- recent attack remains in its aggression ledger.
                    if restrained(record, actor) then
                        if key == "hostileToPlayer" then return false, "lf_truce" end
                        return "neutral"
                    end
                    if owners.relations.wasAggressor(record, actor, now()) then
                        if key == "hostileToPlayer" then return true, "lf_self_defence" end
                        return "hostile"
                    end
                end
                return original(record, actor, ...)
            end
        end)
    end
end
local function installLifecycleGuards(profile)
    for _, entry in ipairs({ { profile.reputation, "onPlayerDied" }, { profile.reputation, "forgetPlayer" },
        { profile.personal, "onPlayerDied" }, { profile.personal, "forgetPlayer" },
        { profile.reset, "check" }, { profile.reset, "onPlayerDied" }, { profile.reset, "forget" },
        { profile.track, "onPlayerDied" } }) do
        bindAvailable(entry[1], entry[2], function(original)
            return function(actor, ...)
                if lfSubject(actor) then return false, "lf_lifecycle_owned" end
                return original(actor, ...)
            end
        end)
    end
end
local function installLifecycle()
    installLifecycleGuards(owners)
    bind(owners.personal, "announce", function(original)
        return function(actor, ...)
            if lfSubject(actor) then return false, "lf_notification_suppressed" end
            return original(actor, ...)
        end
    end)
    bind(owners.reputation, "sync", function(original, binding)
        return function(value, ...)
            local alias, actor = lfSubject(value)
            if alias then
                if binding.current and active() and actor and party(actor) and primary() then
                    return original(primary(), ...)
                end
                return true
            end
            return original(value, ...)
        end
    end)
end
local function installCombat()
    bind(owners.combat, "friendlyBody", function(original, binding)
        return function(record, shell, body, ...)
            if lfIdentity(body) then
                if not binding.current or not active() then return true, "lf_adapter_unavailable" end
                return Adapter.relationship(shell, body) ~= "hostile", "lf_relationship"
            end
            return original(record, shell, body, ...)
        end
    end)
    bind(owners.combat, "hostileToActor", function(original, binding)
        return function(record, body, shell, ...)
            if lfIdentity(body) then
                return binding.current and active() and Adapter.relationship(shell, body) == "hostile"
            end
            return original(record, body, shell, ...)
        end
    end)
    bind(owners.line, "liveBystander", function(original, binding)
        return function(body, shell, target, ...)
            if lfIdentity(body) then
                return binding.current and active() and body ~= shell and body ~= target and live(body)
            end
            return original(body, shell, target, ...)
        end
    end)
    bind(owners.wounds, "damagePlayer", function(original, binding)
        return function(body, ...)
            guardVictim(body)
            local result = pack(original(body, ...))
            local victim = call(body, "getParentChar")
            if binding.current and result[1] == true and lfIdentity(victim) and scope
                and scope.lifetime == lifetime and scope.permission == permission and active() then
                metrics.wounds = metrics.wounds + 1
                metrics.lastVictim = lfIdentity(victim)
                contacts[victim] = { shell = scope.shell, uid = scope.uid, generation = scope.generation, at = now() }
            end
            return unpackValues(result, 1, result.n)
        end
    end)
    bind(owners.combat, "resolveAttack", function(original, binding)
        return function(record, shell, target, ...)
            if not binding.current then
                if scope and scope.lifetime == lifetime and scope.permission == permission then
                    return original(record, shell, target, ...)
                end
                if lfIdentity(target) then return false end
                return original(record, shell, target, ...)
            end
            local source = active() and readyRecord(shell)
            local validSource = source and type(record) == "table" and record.uid == source.uid
                and record.generation == source.generation and record.lifecycle == "active"
            if lfIdentity(target) and (not active() or not eligible(target) or not validSource) then return false end
            local prior = scope
            local current = { shell = validSource and shell or nil, uid = validSource and source.uid or nil,
                generation = validSource and source.generation or nil, lifetime = lifetime, permission = permission }
            if lfIdentity(target) then
                current.victim, current.body = target, call(target, "getBodyDamage")
                if not current.body or call(current.body, "getParentChar") ~= target
                    or current.lifetime ~= lifetime or current.permission ~= permission
                    or not active() or not eligible(target) then
                    return false, "lf_body_owner_unavailable"
                end
                if current.body then bodyOwners[current.body] = target end
            end
            scope = current
            local result = pack(pcall(original, record, shell, target, ...))
            if scope == current then scope = prior end
            current.shell, current.victim, current.body = nil, nil, nil
            if not result[1] then
                if current.rejected and tostring(result[2]) == REJECT then return false, "lf_victim_unavailable" end
                error(result[2], 0)
            end
            return unpackValues(result, 2, result.n)
        end
    end)
end

local function validate(api)
    if type(api) ~= "table" then return nil, "A-Life runtime is not initialized" end
    local found = { api = api, registry = api.ActorRegistry, watchdog = api.Watchdog, locator = api.PlayerLocator,
        perception = api.Perception, reputation = api.Reputation, relations = api.Relations, policy = api.TargetPolicy,
        personal = api.PersonalRep, reset = api.CharacterReset, track = api.RepTrack, act = api.HostileAct,
        fair = api.Fairness, combat = api.Combat, line = api.LineOfFire, wounds = api.Wounds, interop = api.Interop }
    for owner, keys in pairs({ registry = { "peek" }, locator = { "list" }, perception = { "configure" },
        reputation = { "playerKey", "recordedStatus", "baselineFor", "escalate", "sync", "onPlayerDied", "forgetPlayer" },
        relations = { "hostileToPlayer", "playerStance", "baselineStance", "basePlayerStance", "wasAggressor", "actorRecord", "isSelfDefence" },
        policy = { "identityOf", "canAttack" }, personal = { "announce", "onPlayerDied", "forgetPlayer" },
        reset = { "check", "forget", "onPlayerDied" }, track = { "onPlayerDied" }, act = { "live", "restraint" },
        fair = { "underAttack" }, combat = { "resolveAttack", "friendlyBody", "hostileToActor" },
        line = { "liveBystander" }, wounds = { "damagePlayer" }, interop = { "isNpc" } }) do
        for _, key in ipairs(keys) do
            if type(found[owner]) ~= "table" or type(found[owner][key]) ~= "function" then
                return nil, "Required A-Life interface missing: " .. owner .. "." .. key
            end
        end
    end
    if type(found.watchdog) ~= "table" or type(found.watchdog.bindings) ~= "table"
        or type(found.perception.engagements) ~= "table" or found.interop.VERSION ~= 1 then
        return nil, "A-Life bindings, engagements or Interop v1 are unavailable"
    end
    if type(found.perception.adapters) ~= "table" then
        return nil, "A-Life perception adapters are not initialized"
    end
    return found
end
function Adapter.initialize()
    watching = true
    local present = enabled("ProjectALifeNPCs")
    if type(getActivatedMods) == "function" then modPresent = present end
    if not present then changeState("absent", "Project A-Life is not enabled") return false end
    if type(isClient) == "function" and isClient() or type(isServer) == "function" and isServer() then
        changeState("unsupported", "A-Life interop supports single-player only") return false
    end
    for _, binding in ipairs(bindings) do
        if binding.current and binding.owner[binding.key] ~= binding.wrapper then
            changeState("unsupported", "A-Life hook changed: " .. binding.key, false) return false
        end
    end
    local api = type(_G) == "table" and rawget(_G, "ProjectALife")
    if type(api) == "table" and not owners then
        local partial = { reputation = api.Reputation, policy = api.TargetPolicy,
            personal = api.PersonalRep, reset = api.CharacterReset, track = api.RepTrack }
        installIdentity(partial)
        installLifecycleGuards(partial)
    end
    local found, reason = validate(api)
    if not found then changeState("unsupported", reason) return false end
    if owners then
        for key, owner in pairs(owners) do
            if found[key] ~= owner then changeState("unsupported", "A-Life interface table changed: " .. key, false) return false end
        end
        for _, binding in ipairs(bindings) do
            if binding.current and binding.owner[binding.key] ~= binding.wrapper then
                changeState("unsupported", "A-Life hook changed: " .. binding.key, false) return false
            end
        end
    else
        owners = found
        installIdentity(owners)
        installRelations()
        installLifecycle()
        installCombat()
        bind(owners.perception, "configure", function(original, binding)
            return function(...)
                local result = pack(original(...))
                if binding.current then
                    local retained = {}
                    for _, previous in ipairs(bindings) do
                        if previous.transient then
                            previous.current = false
                            if previous.owner[previous.key] == previous.wrapper then previous.owner[previous.key] = previous.original end
                        else retained[#retained + 1] = previous end
                    end
                    bindings = retained
                    if not perceptionProvider() then changeState("unsupported", "A-Life perception provider is invalid", false) end
                    Adapter.invalidate()
                end
                return unpackValues(result, 1, result.n)
            end
        end)
        if not perceptionProvider() then changeState("unsupported", "A-Life perception provider is invalid", false) return false end
    end
    if not installListeners() then changeState("unsupported", "A-Life Interop lifecycle events are unavailable") return false end
    if enabled("Bandits2") then
        changeState("unsupported", "Simultaneous A-Life and Bandits is not supported") return false
    end
    if not configured() then changeState("disabled", "Combat integration is off; identity guards retained") return false end
    changeState("active", "Project A-Life 1.4.6 interfaces ready")
    return active()
end
function Adapter.pulse(current)
    if not watching or SC.State and SC.State.active ~= true then return end
    current = type(current) == "number" and current or now()
    if lastCheck and current >= lastCheck and current < nextCheck then return end
    lastCheck, nextCheck = current, current + 1000
    for actor, contact in pairs(contacts) do
        local age = current - contact.at
        if age < 0 or age >= 5000 or not live(actor) then contacts[actor] = nil end
    end
    if state == "active" or retryable then Adapter.initialize() end
end
function Adapter.reset()
    watching, scope = false, nil
    modPresent = nil
    lifetime = lifetime + 1
    changeState("absent", "World stopped")
    for _, listener in pairs(listeners) do pcall(listener.event.Remove, listener.callback) end
    listeners = {}
    for index = #bindings, 1, -1 do
        local binding = bindings[index]
        binding.current = false
        if binding.owner[binding.key] == binding.wrapper then binding.owner[binding.key] = binding.original end
    end
    bindings, owners = {}, nil
    contacts = setmetatable({}, { __mode = "k" })
    bodyOwners = setmetatable({}, { __mode = "kv" })
    nextCheck, lastCheck = 0, nil
    metrics = { listBuilds = 0, wounds = 0, rejected = 0 }
    Adapter.invalidate()
    -- Weak identity tombstones survive retained callbacks without retaining bodies.
    return true
end

return Adapter
