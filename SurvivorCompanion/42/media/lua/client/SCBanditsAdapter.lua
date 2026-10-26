-- SPDX-License-Identifier: MIT

-- Optional interop with Bandits2. The foreign AI and damage calculations stay
-- with their owner; only character discovery, identity and command delivery
-- cross this boundary. Never publish these actors to an engine player list.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.BanditsAdapter = SC.BanditsAdapter or {}
local Adapter = SC.BanditsAdapter
local PREFIX = "lf:"
local bindings = {}
local seen = setmetatable({}, { __mode = "k" })
local cached, cacheAt, cacheVersion = nil, -math.huge, nil
local originalMembers, originalCount = {}, -1
local cacheActive = false
local state, detail = "absent", "Bandits2 is not enabled"
local recognized = setmetatable({}, { __mode = "k" })
local damageContacts = setmetatable({}, { __mode = "k" })
local routedDamage, listBuilds = 0, 0
local routedModels = { BulletHit = 0, MeleeHit = 0, BareHandHit = 0 }
local lifetime, permission = 0, 0
local nextCheckAt, lastCheckAt, retryable = 0, nil, true
local watching = false
local owners, damageHandler = nil, nil
local listFactory = nil
local lastVictim, lastModel = nil, nil
local damageScope = nil
local unpackValues = unpack or table.unpack
local function pack(...) return { n = select("#", ...), ... } end
local function object(value) return type(value) == "table" or type(value) == "userdata" end
local function method(actor, key)
    if not object(actor) then return nil end
    local okay, callback
    if SC.Call and type(SC.Call.resolve) == "function" then
        okay, callback = SC.Call.resolve(actor, key)
    else
        okay, callback = pcall(function() return actor[key] end)
    end
    return okay and type(callback) == "function" and callback or nil
end
local function call(actor, key, ...)
    -- Keep method lookup protected too: unexposed Java values can throw before
    -- an invocation reaches pcall.
    local callback = method(actor, key)
    if not callback then return nil end
    local result = pack(pcall(callback, actor, ...))
    if result[1] then return result[2] end
end
local function now()
    return type(getTimestampMs) == "function" and getTimestampMs() or 0
end
local function enabledMod(id)
    local mods = type(getActivatedMods) == "function" and getActivatedMods() or nil
    return call(mods, "contains", id) == true or call(mods, "contains", "\\" .. id) == true
end
local function configured()
    return not SC.UserOptions or SC.UserOptions.get("banditsCompatibility") ~= false
end
local function changeState(value, reason, canRetry)
    local changed = state ~= value or detail ~= reason
    if (state == "active") ~= (value == "active") then permission = permission + 1 end
    state, detail = value, reason
    retryable = canRetry ~= false
    cached = nil
    if changed and value == "unsupported" and SC.Diagnostics then
        SC.Diagnostics.report("bandits-adapter", nil, "Bandits adapter unavailable", reason)
    end
end
local function dataOf(actor)
    if call(actor, "hasModData") == false then return nil end
    local data = call(actor, "getModData")
    return type(data) == "table" and data or nil
end
local function lfIdentity(actor)
    if not object(actor) then return nil end
    local id = SC.Registry and SC.Registry.idOf(actor)
    if id == nil then
        if seen[actor] then return seen[actor] end
        local data = dataOf(actor)
        if not data or type(data.SC_Id) ~= "string" then return nil end
        local registryActor = SC.Actor and type(SC.Actor._isRegistryActor) == "function"
            and SC.Actor._isRegistryActor(actor)
        id = registryActor and data.SC_Id or nil
    end
    if type(id) == "string" and id:sub(1, 3) == "sc-" then
        seen[actor] = PREFIX .. id
    end
    return seen[actor]
end
local function live(actor)
    local alias = lfIdentity(actor)
    if not alias or not SC.Registry then return false end
    local id = alias:sub(#PREFIX + 1)
    local record = SC.Registry.byId(id)
    if not record or record.actor ~= actor or not SC.Registry.isActive(actor, id) then return false end
    if call(actor, "isDead") == true or call(actor, "isAlive") == false then return false end
    local health = call(actor, "getHealth")
    if type(health) == "number" and health <= 0 then return false end
    -- Native teardown can precede the registry lifecycle notification. A
    -- removed actor may retain a square and positive health during that gap.
    if call(actor, "isExistInTheWorld") == false then return false end
    return call(actor, "getSquare") ~= nil
end
local function protected(actor)
    return call(actor, "isGhostMode") == true or call(actor, "isInvisible") == true
        or call(actor, "isGodMod") == true or call(actor, "isInvincible") == true
end
local function eligible(actor)
    return live(actor) and not protected(actor)
end
local function active()
    return state == "active" and configured() and (not SC.State or SC.State.active == true)
end
local function brainOf(actor)
    local data = dataOf(actor)
    return data and type(data.brain) == "table" and data.brain or nil
end
local function readyBrain(actor)
    local brain = brainOf(actor)
    local cache = type(BanditZombie) == "table" and BanditZombie.Cache
    if not brain or (type(brain.id) ~= "number" and type(brain.id) ~= "string")
        or brain.clan == nil or type(brain.program) ~= "table"
        or type(brain.hostile) ~= "boolean" or type(brain.hostileP) ~= "boolean"
        or type(cache) ~= "table" or cache[brain.id] ~= actor then return nil end
    return brain
end

function Adapter.owns(actor)
    if not object(actor) then return false end
    local marked = call(actor, "getVariableBoolean", "Bandit") == true
    if marked then recognized[actor] = true return true end
    -- Brain data can precede the animation flag while Bandits initializes an
    -- actor. Require its own cache identity as well; another mod's 'brain'
    -- field is not a Bandits ownership claim.
    local data = dataOf(actor)
    local brain = data and data.brain
    local cache = type(BanditZombie) == "table" and BanditZombie.Cache
    local owned = type(brain) == "table" and brain.id ~= nil
        and brain.clan ~= nil and type(brain.program) == "table"
        and type(cache) == "table" and cache[brain.id] == actor
    if owned then recognized[actor] = true end
    return owned == true
end

function Adapter.relationship(bandit, lfActor)
    if not Adapter.owns(bandit) or not active() then return "unknown" end
    if not eligible(lfActor) or call(bandit, "isDead") == true then return "unknown" end
    local brain = readyBrain(bandit)
    if not brain then return "unknown" end
    return (brain.hostile or brain.hostileP) and "hostile" or "neutral"
end

function Adapter.idFor(actor) return lfIdentity(actor) end
function Adapter.isAttacking(bandit, actor)
    local brain = readyBrain(bandit)
    if not active() or not Adapter.owns(bandit) or not object(actor)
        or call(bandit, "isDead") == true or call(bandit, "getSquare") == nil
        or not brain or not (brain.hostile or brain.hostileP) then return false end
    if lfIdentity(actor) and not eligible(actor) then return false end
    local contact = damageContacts[actor]
    local age = contact and now() - contact.at
    if age and (age < 0 or age >= 5000) then damageContacts[actor], contact = nil, nil end
    if contact and contact.actor == bandit then return true end
    local task = brain and type(brain.tasks) == "table" and brain.tasks[1]
    local id = lfIdentity(actor) or (BanditUtils and BanditUtils.GetCharacterID(actor))
    return type(task) == "table" and task.eid == id
        and (task.action == "Shoot" or task.action == "Smack" or task.action == "Push")
end
function Adapter.resolve(id)
    if not active() or type(id) ~= "string" or id:sub(1, #PREFIX) ~= PREFIX then return nil end
    local record = SC.Registry and SC.Registry.byId(id:sub(#PREFIX + 1))
    local actor = record and record.actor
    return eligible(actor) and actor or nil
end
function Adapter.status()
    local count = 0
    for _ in pairs(recognized) do count = count + 1 end
    return { state = state, active = active(), reason = detail,
        profile = "Bandits2/42.21", recognized = count,
        routedDamage = routedDamage, listBuilds = listBuilds,
        bulletHits = routedModels.BulletHit, meleeHits = routedModels.MeleeHit,
        bareHandHits = routedModels.BareHandHit, lastVictim = lastVictim, lastModel = lastModel }
end
function Adapter.invalidate()
    cached, cacheVersion, cacheAt, cacheActive = nil, nil, -math.huge, false
    originalMembers, originalCount = {}, -1
end

local function listActor(actor)
    return actor == nil or method(actor, "getSquare") ~= nil and method(actor, "getX") ~= nil
end
local function sourceList(original, inspect)
    local okay, source = pcall(original)
    local size = okay and call(source, "size")
    if type(size) ~= "number" or size ~= size or size < 0 or size > 64
        or size ~= math.floor(size) or method(source, "get") == nil then
        changeState("unsupported", "Bandits GetPlayers returned an invalid list")
        return nil
    end
    if inspect then
        for index = 0, size - 1 do
            local valid, actor = pcall(method(source, "get"), source, index)
            if not valid or not listActor(actor) then
                changeState("unsupported", "Bandits GetPlayers returned an invalid actor entry") return nil
            end
        end
    end
    return source, size
end

local function playerView(original)
    local source, size = sourceList(original)
    if not source then return listFactory() end
    local version = SC.Registry and SC.Registry.version() or 0
    local current = now()
    local integrationActive = active()
    local same = size == originalCount
    if same then
        for index = 0, source:size() - 1 do
            if source:get(index) ~= originalMembers[index + 1] then same = false break end
        end
    end
    if cached and same and integrationActive == cacheActive and version == cacheVersion
        and current >= cacheAt and current - cacheAt < 250 then return cached end
    local list = listFactory()
    local included = setmetatable({}, { __mode = "k" })
    local function add(actor)
        if not listActor(actor) then error("invalid actor in Bandits player list", 0) end
        if actor and not included[actor] then
            included[actor] = true
            list:add(actor)
        end
    end
    for index = 0, source:size() - 1 do
        local actor = source:get(index)
        if not lfIdentity(actor) or (integrationActive and eligible(actor)) then add(actor) end
    end
    if integrationActive and SC.Registry then
        for _, record in ipairs(SC.Registry.snapshot()) do
            if eligible(record.actor) then add(record.actor) end
        end
    end
    originalMembers, originalCount = {}, source:size()
    for index = 0, source:size() - 1 do originalMembers[index + 1] = source:get(index) end
    cached, cacheAt, cacheVersion = list, current, version
    cacheActive = integrationActive
    listBuilds = listBuilds + 1
    return list
end

local function bind(owner, key, factory)
    local original = owner[key]
    local binding = { owner = owner, key = key, original = original, current = true }
    local wrapper = factory(original, binding)
    binding.wrapper = wrapper
    owner[key] = wrapper
    bindings[#bindings + 1] = binding
end
local function isBound(owner, key)
    for _, binding in ipairs(bindings) do
        if binding.owner == owner and binding.key == key then return true end
    end
    return false
end

-- The stock models produce Commands.PlayerDamage for their explicit victim.
-- A non-local actor cannot send a player command. Deliver that one request to
-- the stock SP handler synchronously, preserving all armour/RNG/wound logic.
local function damageWrapper(original, model, binding)
    return function(shooter, second, third, ...)
        local victim = model == "BulletHit" and third or second
        if not lfIdentity(victim) then return original(shooter, second, third, ...) end
        if not active() or not eligible(victim) then return false, "lf_victim_unavailable" end
        if not binding.current then
            -- A foreign wrapper may retain us inside a freshly installed
            -- wrapper's chain. Delegate only while that exact victim/model is
            -- protected by a current synchronous routing scope. A standalone
            -- old callback has no authority to send an unrouted LF wound.
            local scope = damageScope
            if not scope or scope.victim ~= victim or scope.model ~= model
                or scope.lifetime ~= lifetime or scope.permission ~= permission then
                return false, "lf_victim_unavailable"
            end
            return original(shooter, second, third, ...)
        end
        local callbackLifetime, callbackPermission = lifetime, permission
        local handler = damageHandler
        local serverOwner, commandOwner = owners and owners.server, owners and owners.commands
        local prior = sendClientCommand
        local inScope = true
        local route = function(player, module, command, args, ...)
            if inScope and player == victim and module == "Commands" and command == "PlayerDamage" then
                if lifetime ~= callbackLifetime or permission ~= callbackPermission
                    or not active() or not eligible(victim) then return false end
                if type(args) ~= "table" then
                    changeState("unsupported", "Malformed Bandits damage request", false) return false
                end
                for _, field in ipairs({ "healthDrop", "intoxication", "sickness", "bodyPartIndex" }) do
                    local value = args[field]
                    if value ~= nil and (type(value) ~= "number" or value ~= value
                        or value < 0 or value == math.huge
                        or field == "bodyPartIndex" and (value > 16 or value ~= math.floor(value))) then
                        changeState("unsupported", "Malformed Bandits damage field: " .. field, false) return false
                    end
                end
                if not owners or BanditServer ~= serverOwner or BanditServer.Commands ~= commandOwner
                    or BanditServer.Commands.PlayerDamage ~= handler or type(handler) ~= "function" then
                    changeState("unsupported", "Bandits damage handler changed during an attack") return false
                end
                routedDamage = routedDamage + 1
                routedModels[model] = routedModels[model] + 1
                lastVictim, lastModel = lfIdentity(victim), model
                local result = pack(pcall(handler, victim, args))
                if not result[1] then
                    if lifetime == callbackLifetime then
                        changeState("unsupported", "Bandits damage handler failed: " .. tostring(result[2]), false)
                    end
                    error(result[2], 0)
                end
                if lifetime == callbackLifetime and permission == callbackPermission and result[2] ~= false
                    and type(args.healthDrop) == "number" and args.healthDrop > 0 then
                    damageContacts[victim] = { actor = shooter, at = now() }
                end
                return unpackValues(result, 2, result.n)
            end
            return prior(player, module, command, args, ...)
        end
        sendClientCommand = route
        local priorScope = damageScope
        local scope = { victim = victim, model = model, lifetime = callbackLifetime, permission = callbackPermission }
        damageScope = scope
        local result = pack(pcall(original, shooter, second, third, ...))
        if damageScope == scope then damageScope = priorScope end
        scope.victim = nil
        inScope = false
        -- An outer command wrapper can retain this closure for the rest of
        -- the session. Its inactive forwarding chain must not retain actors.
        victim, shooter, handler, serverOwner, commandOwner = nil, nil, nil, nil, nil
        -- Do not overwrite a binding installed by another callback while the
        -- model was running. Its chain may still contain our now-inert route.
        if sendClientCommand == route then sendClientCommand = prior end
        if not result[1] then error(result[2]) end
        return unpackValues(result, 2, result.n)
    end
end

local function retaliate(bandit, attacker)
    if not active() or not eligible(attacker) or not Adapter.owns(bandit) then return end
    local brain = readyBrain(bandit)
    if not brain or brain.hostile or brain.hostileP then return end
    local ax, ay = call(attacker, "getX"), call(attacker, "getY")
    if type(ax) ~= "number" or type(ay) ~= "number" then return end
    -- Use the native Bandits escalation APIs for the victim and its witnessed
    -- incident. Never disguise an NPC as the real player to bypass isNpc().
    local function notify(witness)
        if not Adapter.owns(witness) or call(witness, "isDead") == true then return end
        local observed = readyBrain(witness)
        if not observed or observed.hostile or observed.hostileP then return end
        if witness ~= bandit and call(witness, "CanSee", attacker) ~= true then return end
        Bandit.SetHostileP(witness, true)
        Bandit.SetProgram(witness, "Bandit", {})
        Bandit.ForceSyncPart(witness, { id = observed.id, hostileP = true,
            program = { name = "Bandit", stage = "Prepare" } })
    end
    notify(bandit)
    for id, row in pairs(BanditZombie.CacheLightB) do
        if type(row) == "table" and type(row.x) == "number" and type(row.y) == "number"
            and (row.x - ax)^2 + (row.y - ay)^2 < 144 then
            local witness = BanditZombie.Cache[id]
            if witness ~= bandit then notify(witness) end
        end
    end
end

local function validate()
    for _, entry in ipairs({
        { BanditUtils, "GetCharacterID" }, { BanditPlayer, "GetPlayerById" },
        { BanditPlayer, "GetPlayers" }, { BanditPlayer, "CheckFriendlyFire" },
        { PlayerDamageModel, "BulletHit" }, { PlayerDamageModel, "BareHandHit" },
        { PlayerDamageModel, "MeleeHit" },
        { type(BanditServer) == "table" and BanditServer.Commands, "PlayerDamage" },
        { Bandit, "SetHostileP" }, { Bandit, "SetProgram" }, { Bandit, "ForceSyncPart" },
        { ArrayList, "new" },
    }) do
        if type(entry[1]) ~= "table" or type(entry[1][entry[2]]) ~= "function" then
            return false, "Required Bandits interface missing: " .. entry[2]
        end
    end
    if type(BanditZombie) ~= "table" or type(BanditZombie.Cache) ~= "table"
        or type(BanditZombie.CacheLightB) ~= "table" or type(sendClientCommand) ~= "function" then
        return false, "Bandits caches or command delivery are unavailable"
    end
    return true
end

function Adapter.initialize()
    watching = true
    if not enabledMod("Bandits2") then changeState("absent", "Bandits2 is not enabled") return false end
    if (type(isClient) == "function" and isClient())
        or (type(isServer) == "function" and isServer()) then
        changeState("unsupported", "Bandits interop supports single-player only") return false
    end
    if owners and (BanditUtils ~= owners.utils or BanditPlayer ~= owners.players
        or owners.models and PlayerDamageModel ~= owners.models
        or owners.server and BanditServer ~= owners.server) then
        changeState("unsupported", "Bandits interface table changed; restart the game", false) return false
    end
    for _, binding in ipairs(bindings) do
        if binding.owner[binding.key] ~= binding.wrapper then
            changeState("unsupported", "Bandits hook changed: " .. binding.key, false) return false
        end
    end
    -- These guards also cover an unsupported/Off profile: an owned second
    -- view must never appear to Bandits as another instance of player ID 1.
    if #bindings == 0 then
        for _, entry in ipairs({ { BanditUtils, "GetCharacterID" },
            { BanditPlayer, "GetPlayerById" }, { BanditPlayer, "GetPlayers" }, { ArrayList, "new" } }) do
            if type(entry[1]) ~= "table" or type(entry[1][entry[2]]) ~= "function" then
                changeState("unsupported", "Required identity interface missing: " .. entry[2]) return false
            end
        end
        listFactory = ArrayList.new
        bind(BanditUtils, "GetCharacterID", function(original)
            return function(actor, ...)
                -- Retained identity wrappers keep weak tombstones safe even
                -- after teardown; they never expose a target or start work.
                return lfIdentity(actor) or original(actor, ...)
            end
        end)
        bind(BanditPlayer, "GetPlayerById", function(original, binding)
            return function(id, ...)
                if type(id) == "string" and id:sub(1, #PREFIX) == PREFIX then
                    if binding.current then return Adapter.resolve(id) end
                    return nil
                end
                return original(id, ...)
            end
        end)
        bind(BanditPlayer, "GetPlayers", function(original, binding)
            return function(...)
                if binding.current then
                    local okay, result = pcall(playerView, original)
                    if okay then return result end
                    changeState("unsupported", "Bandits player list failed: " .. tostring(result))
                    return listFactory()
                end
                return original(...)
            end
        end)
        owners = { utils = BanditUtils, players = BanditPlayer, models = PlayerDamageModel, server = BanditServer }
    end
    if type(PlayerDamageModel) == "table" then
        owners.models = PlayerDamageModel
        for _, key in ipairs({ "BulletHit", "BareHandHit", "MeleeHit" }) do
            if type(PlayerDamageModel[key]) == "function" and not isBound(PlayerDamageModel, key) then
                local model = key
                bind(PlayerDamageModel, key, function(original, binding) return damageWrapper(original, model, binding) end)
            end
        end
    end
    if not configured() then
        changeState("disabled", "Combat integration is off; identity guards retained") return false
    end
    if enabledMod("BanditsWeekOne") or enabledMod("BanditsDayOne") then
        changeState("unsupported", "This adapter profile targets Bandits2 core") return false
    end
    local okay, reason = validate()
    if not okay then changeState("unsupported", reason) return false end
    local listBinding
    for _, binding in ipairs(bindings) do
        if binding.owner == BanditPlayer and binding.key == "GetPlayers" then listBinding = binding end
    end
    if not sourceList(listBinding.original, true) then return false end
    if damageHandler and (damageHandler ~= BanditServer.Commands.PlayerDamage
        or owners.commands ~= BanditServer.Commands) then permission = permission + 1 end
    owners.commands = BanditServer.Commands
    owners.server = BanditServer
    damageHandler = BanditServer.Commands.PlayerDamage
    if not isBound(BanditPlayer, "CheckFriendlyFire") then
        bind(BanditPlayer, "CheckFriendlyFire", function(original, binding)
            return function(bandit, attacker, ...)
                local result = pack(original(bandit, attacker, ...))
                if binding.current then
                    local okay, reason = pcall(retaliate, bandit, attacker)
                    if not okay then changeState("unsupported", "Bandits retaliation failed: " .. tostring(reason), false) end
                end
                return unpackValues(result, 1, result.n)
            end
        end)
    end
    changeState(configured() and "active" or "disabled",
        configured() and "Bandits2 core interfaces ready" or "Combat integration is off; identity guards retained")
    return active()
end

function Adapter.pulse(current)
    if not watching or SC.State and SC.State.active ~= true then return end
    current = type(current) == "number" and current or now()
    if lastCheckAt and current >= lastCheckAt and current < nextCheckAt then return end
    lastCheckAt, nextCheckAt = current, current + 1000
    for actor, contact in pairs(damageContacts) do
        local age = current - contact.at
        if age < 0 or age >= 5000 or not eligible(actor) then damageContacts[actor] = nil end
    end
    if SC.Registry and cacheVersion ~= SC.Registry.version() then Adapter.invalidate() end
    if state == "active" or retryable then Adapter.initialize() end
end

function Adapter.reset()
    watching = false
    damageScope = nil
    lifetime = lifetime + 1
    changeState("absent", "World stopped")
    for index = #bindings, 1, -1 do
        local binding = bindings[index]
        binding.current = false
        if binding.owner[binding.key] == binding.wrapper then binding.owner[binding.key] = binding.original end
    end
    bindings = {}
    owners, damageHandler, lastVictim, lastModel, listFactory = nil, nil, nil, nil, nil
    nextCheckAt, lastCheckAt = 0, nil
    Adapter.invalidate()
    -- Keys are weak and values are strings. Old actors can be collected,
    -- while a foreign retained reference can never become player ID 1.
    recognized = setmetatable({}, { __mode = "k" })
    damageContacts = setmetatable({}, { __mode = "k" })
    routedDamage, listBuilds = 0, 0
    routedModels = { BulletHit = 0, MeleeHit = 0, BareHandHit = 0 }
    return true
end

return Adapter
