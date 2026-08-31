-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCConfig"
require "SCDiagnostics"
require "SCRegistry"
require "SCNativeActions"
require "SCBackground"

local SC = SurvivorCompanion
SC.Actor = SC.Actor or {}

local actorService = SC.Actor
local cachedProvider = nil
local cachedReady = false
local cachedReason = "actor provider has not been checked"
local experimentalOwned = setmetatable({}, { __mode = "k" })
local experimentalDisabledReason = nil
local nativeOwned = setmetatable({}, { __mode = "k" })
local spawnTickets = setmetatable({}, { __mode = "k" })
local expectedNativeProtocol = "42.20-isocompanion-5"

local function method(object, name)
    if object == nil then
        return nil
    end
    local ok, value = pcall(function()
        return object[name]
    end)
    if not ok or type(value) ~= "function" then
        return nil
    end
    return value
end

local function invoke(object, name, ...)
    local callback = method(object, name)
    if callback == nil then
        return false, "method unavailable: " .. tostring(name)
    end
    local values = { pcall(callback, object, ...) }
    if not values[1] then
        return false, tostring(values[2])
    end
    local unpackFn = table.unpack or unpack
    return true, unpackFn(values, 2)
end

local function staticInvoke(object, name, ...)
    local callback = method(object, name)
    if callback == nil then
        return false, "static method unavailable: " .. tostring(name)
    end
    local values = { pcall(callback, ...) }
    if not values[1] then
        return false, tostring(values[2])
    end
    local unpackFn = table.unpack or unpack
    return true, unpackFn(values, 2)
end

local function multiplayerActive()
    local client = false
    local server = false
    if type(isClient) == "function" then
        local ok, value = pcall(isClient)
        client = ok and value == true
    end
    if type(isServer) == "function" then
        local ok, value = pcall(isServer)
        server = ok and value == true
    end
    return client or server
end

local function nativeComponents(actor)
    local required = { "getBodyDamage", "getMoodles", "getXp", "getEmitter", "getVisual" }
    for _, name in ipairs(required) do
        local ok, value = invoke(actor, name)
        if not ok or value == nil then
            return false, "native actor component is unavailable: " .. name
        end
    end
    local deadOk, dead = invoke(actor, "isDead")
    local squareOk, square = invoke(actor, "getCurrentSquare")
    if not deadOk or dead == true or not squareOk or square == nil then
        return false, "native actor is not alive on a valid square"
    end
    return true
end

local function globalValue(name)
    if type(_G) ~= "table" then
        return nil
    end
    return rawget(_G, name)
end

local function readStaticPlayerState()
    local playerClass = globalValue("IsoPlayer")
    if playerClass == nil then
        return nil, "IsoPlayer is not exposed to Kahlua"
    end
    local specificPlayer = globalValue("getSpecificPlayer")
    local activePlayerCount = globalValue("getNumActivePlayers")
    if type(specificPlayer) ~= "function" or type(activePlayerCount) ~= "function" then
        return nil, "safe local-player accessors are not exposed to Kahlua"
    end
    local ok, state = pcall(function()
        local instanceOk, instance = staticInvoke(playerClass, "getInstance")
        if not instanceOk then
            error("IsoPlayer.getInstance is unavailable: " .. tostring(instance))
        end
        local result = {
            instance = instance,
            numPlayers = playerClass.numPlayers,
            activePlayers = activePlayerCount(),
            slots = {},
            indexes = {},
        }
        -- IsoPlayer.players is a Java array in the live B42 Kahlua runtime.
        -- Direct Lua indexing (players[index]) throws before pcall can turn it
        -- into a quiet provider rejection, so use the vanilla accessors only.
        for index = 0, 3 do
            local value = specificPlayer(index)
            result.slots[index] = value
            if value ~= nil then
                local indexOk, playerIndex = invoke(value, "getPlayerNum")
                if not indexOk then
                    error("local player index is unavailable at slot " .. tostring(index))
                end
                result.indexes[index] = playerIndex
            end
        end
        return result
    end)
    if not ok then
        return nil, "IsoPlayer singleton invariants cannot be observed: " .. tostring(state)
    end
    return state
end

local function samePlayerState(before, after, candidate)
    if before == nil or after == nil then
        return false, "local-player snapshot is unavailable"
    end
    if before.instance ~= after.instance then
        return false, "IsoPlayer singleton changed"
    end
    if before.numPlayers ~= after.numPlayers then
        return false, "IsoPlayer.numPlayers changed from " .. tostring(before.numPlayers)
            .. " to " .. tostring(after.numPlayers)
    end
    if before.activePlayers ~= after.activePlayers then
        return false, "active-player count changed from " .. tostring(before.activePlayers)
            .. " to " .. tostring(after.activePlayers)
    end
    for index = 0, 3 do
        if after.slots[index] == candidate then
            return false, "candidate occupied local-player slot " .. tostring(index)
        end
        if before.slots[index] ~= after.slots[index] then
            return false, "local-player slot " .. tostring(index) .. " changed"
        end
        if before.indexes[index] ~= after.indexes[index] then
            return false, "player number changed in local slot " .. tostring(index)
        end
    end
    return true, nil
end

local function removeExperimental(actor)
    invoke(actor, "StopAllActionQueue")
    local existsBeforeOk, existedBefore = invoke(actor, "isExistInTheWorld")
    local worldRemoved, worldReason = true, nil
    if not existsBeforeOk or existedBefore == true then
        worldRemoved, worldReason = invoke(actor, "removeFromWorld")
    end
    local squareRemoved, squareReason = invoke(actor, "removeFromSquare")
    local squareCleared, clearReason = invoke(actor, "setCurrentSquare", nil)
    local existsOk, exists = invoke(actor, "isExistInTheWorld")
    local currentOk, current = invoke(actor, "getCurrentSquare")
    local squareOk, square = invoke(actor, "getSquare")
    if not worldRemoved or not squareRemoved or not squareCleared
        or not existsOk or exists == true
        or not currentOk or current ~= nil or not squareOk or square ~= nil then
        return false, "native removal postcondition failed: "
            .. tostring(worldReason or squareReason or clearReason or "world/square membership remains")
    end
    experimentalOwned[actor] = nil
    return true
end

local function translatedExperimentalFailure(reason)
    local fallback = "Experimental NPC-player provider failed and was disabled: " .. tostring(reason)
    if type(getText) == "function" then
        local ok, value = pcall(getText, "UI_SC_ExperimentalProviderFailed", tostring(reason))
        if ok and type(value) == "string" and value ~= "UI_SC_ExperimentalProviderFailed" then
            return value
        end
    end
    return fallback
end

local function rejectExperimental(actor, reason)
    if actor ~= nil then
        local removed, cleanupReason = removeExperimental(actor)
        if not removed then
            reason = tostring(reason) .. "; candidate cleanup was not verified: "
                .. tostring(cleanupReason)
        end
    end
    experimentalDisabledReason = translatedExperimentalFailure(reason)
    cachedProvider = nil
    cachedReady = false
    cachedReason = experimentalDisabledReason
    SC.Diagnostics.report("actor-provider", nil, "experimental provider disabled",
        experimentalDisabledReason)
    return nil, experimentalDisabledReason
end

local function experimentalProvider()
    if SC.Config.get("experimentalNpcPlayerActor") ~= true then
        return nil, "native actor bridge unavailable; experimental IsoPlayer NPC fallback is disabled"
    end
    if experimentalDisabledReason ~= nil then
        return nil, experimentalDisabledReason
    end
    local playerClass = globalValue("IsoPlayer")
    local factory = globalValue("SurvivorFactory")
    if playerClass == nil or factory == nil or method(playerClass, "new") == nil then
        return nil, "experimental IsoPlayer constructor is not exposed to Kahlua"
    end
    local observable, observationReason = readStaticPlayerState()
    if observable == nil then
        return rejectExperimental(nil, observationReason)
    end

    local provider = {
        kind = "experimental-npc-player",
        directNative = true,
    }

    function provider:isActor(actor)
        return experimentalOwned[actor] == true
    end

    function provider:spawn(square, identity)
        if experimentalDisabledReason ~= nil then
            return nil, experimentalDisabledReason
        end
        local before, beforeReason = readStaticPlayerState()
        if before == nil then
            return rejectExperimental(nil, beforeReason)
        end
        local cellOk, cell = invoke(square, "getCell")
        local xOk, x = invoke(square, "getX")
        local yOk, y = invoke(square, "getY")
        local zOk, z = invoke(square, "getZ")
        if not cellOk or cell == nil or not xOk or not yOk or not zOk then
            return rejectExperimental(nil, "spawn square is not fully loaded")
        end

        local descriptorOk, descriptor = staticInvoke(factory, "CreateSurvivor")
        if not descriptorOk or descriptor == nil then
            return rejectExperimental(nil, "SurvivorFactory did not create a descriptor")
        end
        invoke(descriptor, "setFemale", identity.gender == "female" or identity.gender == "woman")
        invoke(descriptor, "setForename", tostring(identity.forename or "Fellow"))
        invoke(descriptor, "setSurname", tostring(identity.surname or "Survivor"))
        if identity.outfit ~= nil and tostring(identity.outfit) ~= "" then
            invoke(descriptor, "dressInNamedOutfit", tostring(identity.outfit))
        end

        local constructed, actor = staticInvoke(playerClass, "new", cell, descriptor, x, y, z, false)
        if not constructed or actor == nil then
            return rejectExperimental(nil, "IsoPlayer construction failed: " .. tostring(actor))
        end
        invoke(actor, "setCurrentSquare", square)
        invoke(actor, "setNpc", true)

        local npcOk, npc = invoke(actor, "isNpc")
        local localOk, isLocal = invoke(actor, "isLocalPlayer")
        local afterConstruction, afterConstructionReason = readStaticPlayerState()
        local constructionStable, constructionReason = samePlayerState(before, afterConstruction, actor)
        if not npcOk or npc ~= true or not localOk or isLocal == true then
            return rejectExperimental(actor, "IsoPlayer did not remain a non-local NPC")
        end
        if not constructionStable then
            return rejectExperimental(actor, "IsoPlayer construction mutated local-player state: "
                .. tostring(afterConstructionReason or constructionReason))
        end

        local componentsOk, componentReason = nativeComponents(actor)
        if not componentsOk then
            return rejectExperimental(actor, componentReason)
        end

        local updated, updateReason = invoke(actor, "update")
        if not updated then
            return rejectExperimental(actor, "IsoPlayer failed native update: " .. tostring(updateReason))
        end
        local afterUpdate, afterUpdateReason = readStaticPlayerState()
        local updateStable, updateMutation = samePlayerState(before, afterUpdate, actor)
        if not updateStable then
            return rejectExperimental(actor, "IsoPlayer update mutated local-player state: "
                .. tostring(afterUpdateReason or updateMutation))
        end

        local added, addReason = invoke(actor, "addToWorld")
        if not added then
            return rejectExperimental(actor, "IsoPlayer could not enter the world: " .. tostring(addReason))
        end
        experimentalOwned[actor] = true
        local afterWorld, afterWorldReason = readStaticPlayerState()
        local worldStable, worldMutation = samePlayerState(before, afterWorld, actor)
        if not worldStable then
            return rejectExperimental(actor, "IsoPlayer world insertion mutated local-player state: "
                .. tostring(afterWorldReason or worldMutation))
        end
        local indexOk, playerIndex = invoke(actor, "getPlayerNum")
        if indexOk and tonumber(playerIndex) == 0 then
            SC.Diagnostics.report("actor-provider", nil,
                "experimental provider risk", "NPC actor has duplicate playerIndex=0")
        end
        return actor
    end

    function provider:remove(actor)
        if experimentalOwned[actor] ~= true then
            return false, "actor is not owned by the experimental provider"
        end
        return removeExperimental(actor)
    end

    function provider:retireDead(actor)
        if experimentalOwned[actor] ~= true then
            return false, "actor is not owned by the experimental provider"
        end
        local deadOk, dead = invoke(actor, "isDead")
        local doneOk, done = invoke(actor, "isOnDeathDone")
        if not deadOk or dead ~= true then return false, "actor is still alive" end
        if not doneOk or done ~= true then return false, "death_pending" end
        experimentalOwned[actor] = nil
        return true
    end

    function provider:stop(actor)
        return SC.NativeActions.stopDirect(actor), nil
    end

    return provider
end

local function nativeBridgeProvider()
    local bridge = globalValue("SCBridge")
    if bridge == nil then
        return nil, "SCBridge is not exposed; install or repair the native companion bootstrap"
    end
    local protocolOk, protocol = staticInvoke(bridge, "getProtocol")
    if not protocolOk or protocol ~= expectedNativeProtocol then
        return nil, "native bridge protocol mismatch: expected " .. expectedNativeProtocol
            .. ", received " .. tostring(protocol)
    end
    local readyOk, readyReason = staticInvoke(bridge, "checkReady")
    if not readyOk then
        return nil, "native bridge readiness check failed: " .. tostring(readyReason)
    end
    if type(readyReason) ~= "string" or readyReason ~= "" then
        return nil, tostring(readyReason or "native bridge is not ready")
    end

    local provider = {
        kind = "iso-companion",
        directNative = true,
    }

    function provider:isActor(actor)
        if actor == nil or nativeOwned[actor] ~= true then return false end
        local ok, result = staticInvoke(bridge, "isCompanion", actor)
        return ok and result == true
    end

    function provider:validate(actor)
        if not self:isActor(actor) then return false, "actor is not owned by SCBridge" end
        local ok, reason = staticInvoke(bridge, "checkActor", actor)
        if not ok then return false, tostring(reason) end
        if type(reason) ~= "string" or reason ~= "" then return false, tostring(reason) end
        return true
    end

    function provider:recover(actor, square)
        if not self:isActor(actor) then return false, "actor is not owned by SCBridge" end
        local ok, recovered = staticInvoke(bridge, "recover", actor, square)
        if not ok or recovered ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return false, reasonOk and reason or recovered
        end
        return true
    end

    function provider:requestSpawn(square, identity)
        identity = type(identity) == "table" and identity or {}
        local ok, requestId = staticInvoke(bridge, "requestSpawn", square,
            tostring(identity.forename or "Fellow"),
            tostring(identity.surname or "Survivor"),
            identity.gender == "female" or identity.gender == "woman",
            tostring(identity.outfit or ""))
        if not ok or tonumber(requestId) == nil or tonumber(requestId) < 1 then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return nil, reasonOk and reason or requestId
        end
        return tonumber(requestId)
    end

    function provider:pollSpawn(requestId)
        local stateOk, state = staticInvoke(bridge, "getSpawnState", requestId)
        if not stateOk then
            staticInvoke(bridge, "cancelSpawnRequest", requestId)
            return nil, "native spawn state query failed"
        end
        state = tostring(state or "unknown")
        if state == "pending" then return nil, "spawn_pending" end
        if state == "failed" then
            local reasonOk, reason = staticInvoke(bridge, "getSpawnFailure", requestId)
            staticInvoke(bridge, "forgetSpawnRequest", requestId)
            return nil, reasonOk and tostring(reason) or "native companion spawn failed"
        end
        if state ~= "ready" then
            staticInvoke(bridge, "cancelSpawnRequest", requestId)
            return nil, "native spawn request is unknown"
        end

        local resultOk, actor = staticInvoke(bridge, "getSpawnResult", requestId)
        if not resultOk or actor == nil then
            staticInvoke(bridge, "cancelSpawnRequest", requestId)
            return nil, "native spawn result is unavailable"
        end
        nativeOwned[actor] = true
        local healthy, healthReason = self:validate(actor)
        if not healthy then
            staticInvoke(bridge, "remove", actor)
            nativeOwned[actor] = nil
            staticInvoke(bridge, "forgetSpawnRequest", requestId)
            return nil, healthReason
        end
        local forgotOk, forgot = staticInvoke(bridge, "forgetSpawnRequest", requestId)
        if not forgotOk or forgot ~= true then
            staticInvoke(bridge, "remove", actor)
            nativeOwned[actor] = nil
            return nil, "native spawn request could not be finalized"
        end
        return actor
    end

    function provider:cancelSpawn(requestId)
        local ok, cancelled = staticInvoke(bridge, "cancelSpawnRequest", requestId)
        if ok and cancelled == true then return true end
        local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
        return false, reasonOk and tostring(reason) or tostring(cancelled)
    end

    function provider:spawn()
        return nil, "synchronous native spawn is disabled"
    end

    function provider:remove(actor)
        if not self:isActor(actor) then return false, "actor is not owned by SCBridge" end
        local ok, removed = staticInvoke(bridge, "remove", actor)
        if not ok or removed ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return false, reasonOk and reason or removed
        end
        nativeOwned[actor] = nil
        return true
    end

    function provider:retireDead(actor)
        if not self:isActor(actor) then return false, "actor is not owned by SCBridge" end
        local ok, retired = staticInvoke(bridge, "retireDead", actor)
        if not ok or retired ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            reason = reasonOk and tostring(reason) or tostring(retired)
            if string.find(reason, "death is not finalized", 1, true) ~= nil then
                return false, "death_pending"
            end
            return false, reason
        end
        nativeOwned[actor] = nil
        return true
    end

    function provider:stop(actor)
        if not self:isActor(actor) then return false, "actor is not owned by SCBridge" end
        local ok, stopped = staticInvoke(bridge, "stop", actor)
        if not ok or stopped ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return false, reasonOk and reason or stopped
        end
        return true
    end

    function provider:disposeAll()
        local ok, removed = staticInvoke(bridge, "removeAll")
        nativeOwned = setmetatable({}, { __mode = "k" })
        if not ok or removed ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return false, reasonOk and reason or removed
        end
        return true
    end

    return provider
end

local function resolveProvider()
    local native, nativeReason = nativeBridgeProvider()
    if native ~= nil then
        return native, "native IsoCompanion provider ready"
    end
    local experimental, experimentalReason = experimentalProvider()
    if experimental ~= nil then
        return experimental, "experimental private-test provider ready"
    end
    return nil, tostring(nativeReason) .. "; fallback: " .. tostring(experimentalReason)
end

function actorService.checkBridge(force)
    if not force and (cachedReady or cachedProvider ~= nil) then
        return cachedReady, cachedReason
    end
    cachedProvider = nil
    cachedReady = false
    if multiplayerActive() then
        cachedReason = "Living Fellows: Companion is single-player only"
        return false, cachedReason
    end
    cachedProvider, cachedReason = resolveProvider()
    cachedReady = cachedProvider ~= nil
    return cachedReady, cachedReason
end

-- Public, read-only bridge health used by the in-game support report.  Keep
-- this independent from the provider implementation so a missing or outdated
-- bootstrap can still explain itself without throwing another Lua error.
function actorService.bridgeStatus(force)
    local ready, reason = actorService.checkBridge(force == true)
    local status = {
        ready = ready == true,
        provider = cachedProvider and cachedProvider.kind or nil,
        expectedProtocol = expectedNativeProtocol,
        observedProtocol = nil,
        code = ready == true and "ready" or "unavailable",
        reason = tostring(reason or "actor provider status is unavailable"),
    }

    if multiplayerActive() then
        status.code = "unsupported_multiplayer"
        return status
    end
    if ready == true then
        if status.provider == "experimental-isoplayer" then
            status.code = "experimental_provider"
        elseif status.provider == "test" then
            status.code = "test_provider"
        end
        return status
    end

    local bridge = globalValue("SCBridge")
    if bridge == nil then
        status.code = "bridge_missing"
        return status
    end
    local protocolOk, protocol = staticInvoke(bridge, "getProtocol")
    if protocolOk then status.observedProtocol = tostring(protocol) end
    if not protocolOk then
        status.code = "bridge_error"
    elseif protocol ~= expectedNativeProtocol then
        status.code = "protocol_mismatch"
    else
        status.code = "bridge_not_ready"
    end
    return status
end

function actorService._isSurvivor(actor)
    if actor == nil or type(instanceof) ~= "function" then
        return false
    end
    local ok, result = pcall(instanceof, actor, "IsoSurvivor")
    return ok and result == true
end

function actorService._isRegistryActor(actor)
    if actorService._isSurvivor(actor) then
        return true
    end
    return cachedProvider ~= nil and type(cachedProvider.isActor) == "function"
        and cachedProvider:isActor(actor)
end

function actorService.validateNative(actor)
    if cachedProvider == nil or type(cachedProvider.validate) ~= "function" then
        return true
    end
    local ok, healthy, reason = pcall(cachedProvider.validate, cachedProvider, actor)
    if not ok or healthy ~= true then
        return false, tostring(reason or healthy)
    end
    return true
end

function actorService.isCompanion(actor)
    if not actorService._isRegistryActor(actor) then
        return false
    end
    local ok, data = invoke(actor, "getModData")
    if not ok or type(data) ~= "table" or not SC.Registry.isValidId(data.SC_Id) then
        return false
    end
    local record = SC.Registry.byId(data.SC_Id)
    return SC.Registry.isActive(actor, data.SC_Id) and record ~= nil
        and not (type(record.runtime) == "table" and record.runtime.inactive == true)
end

local function rollbackSpawn(actor, provider)
    provider = provider or cachedProvider
    if actor ~= nil and provider ~= nil then
        local ok, removed, reason = pcall(provider.remove, provider, actor)
        if not ok or removed ~= true then
            cachedReady = false
            cachedReason = "actor rollback was not verified; provider disabled: "
                .. tostring(reason or removed)
            SC.Diagnostics.report("actor-provider", nil, cachedReason)
        end
    end
end

local function quarantineRecord(record, reason)
    if type(record) ~= "table" then return end
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    record.runtime.inactive = true
    record.runtime.unrecoverable = true
    record.runtime.removalFailure = tostring(reason)
    SC.Diagnostics.report("actor-removal", record.id,
        "actor quarantined inactive after unverified removal", reason)
end

local function validateSpawnRequest(square, profile)
    local ready, reason = actorService.checkBridge(false)
    if not ready then return nil, reason end
    if square == nil then return nil, "spawn square is required" end
    profile = type(profile) == "table" and profile or {}
    if profile.id ~= nil and (not SC.Registry.isValidId(profile.id)
        or SC.Registry.byId(profile.id) ~= nil) then
        return nil, "restore companion id is invalid or already active"
    end
    return profile
end

local function finalizeSpawn(actor, profile, provider)
    local initialized, nativeReason = nativeComponents(actor)
    if not initialized then
        rollbackSpawn(actor, provider)
        return nil, nativeReason
    end
    local background
    if SC.Background and type(SC.Background.prepareProfile) == "function" then
        profile, background = SC.Background.prepareProfile(profile)
    end
    if background and SC.Background and type(SC.Background.applyNative) == "function" then
        local applied, backgroundReason = SC.Background.applyNative(actor, background)
        if not applied and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("background", profile.id,
                "native companion background could not be applied", backgroundReason)
        end
    end
    local identity = type(profile.identity) == "table" and profile.identity or profile
    local recordInput = {
        id = profile.id,
        recruited = profile.recruited == true,
        identity = identity,
        state = profile.state,
        restored = profile.restored == true,
        debugSpawn = profile.debugSpawn == true,
        debugDiscovered = profile.debugDiscovered == true,
        factionId = profile.factionId,
        factionRole = profile.factionRole,
        factionLeader = profile.factionLeader == true,
    }
    if type(profile.initialize) == "function" then
        local ok, result, initializeReason = pcall(profile.initialize, actor, recordInput)
        if not ok or result == false then
            rollbackSpawn(actor, provider)
            return nil, "actor initialization failed: " .. tostring(initializeReason or result)
        end
    end

    local record, registerReason = SC.Registry.register(actor, recordInput)
    if record == nil then
        rollbackSpawn(actor, provider)
        return nil, registerReason
    end
    if SC.Commands and type(SC.Commands.restore) == "function" then
        local restoredOk, restored, characterReason = pcall(SC.Commands.restore, actor, record)
        if not restoredOk or restored ~= true then
            SC.Registry.unregister(actor)
            rollbackSpawn(actor, provider)
            return nil, "character-depth initialization failed: "
                .. tostring(characterReason or restored)
        end
    end
    return actor, record
end

function actorService.spawn(square, profile)
    local checked, reason = validateSpawnRequest(square, profile)
    if checked == nil then return nil, reason end
    profile = checked
    if type(cachedProvider.requestSpawn) == "function" then
        return nil, "native provider requires deferred spawn"
    end
    if type(cachedProvider.spawn) ~= "function" then
        return nil, "actor provider has no spawn entry point"
    end
    local identity = type(profile.identity) == "table" and profile.identity or profile
    local spawnOk, actorOrReason, providerReason = pcall(cachedProvider.spawn,
        cachedProvider, square, identity)
    if not spawnOk or actorOrReason == nil then
        return nil, "actor provider spawn failed: " .. tostring(providerReason or actorOrReason)
    end
    return finalizeSpawn(actorOrReason, profile, cachedProvider)
end

function actorService.beginSpawn(square, profile)
    local checked, reason = validateSpawnRequest(square, profile)
    if checked == nil then return nil, reason end
    profile = checked

    if type(cachedProvider.requestSpawn) ~= "function" then
        local actor, result = actorService.spawn(square, profile)
        local ticket = {
            state = actor and "ready" or "failed",
            actor = actor,
            reason = actor and nil or result,
            provider = cachedProvider,
            profile = profile,
        }
        spawnTickets[ticket] = true
        return ticket, actor and "spawn_ready" or result
    end

    local identity = type(profile.identity) == "table" and profile.identity or profile
    local ok, requestOrReason, providerReason = pcall(cachedProvider.requestSpawn,
        cachedProvider, square, identity)
    if not ok or requestOrReason == nil then
        return nil, "actor provider spawn request failed: "
            .. tostring(providerReason or requestOrReason)
    end
    local ticket = {
        state = "pending",
        request = requestOrReason,
        provider = cachedProvider,
        profile = profile,
    }
    spawnTickets[ticket] = true
    return ticket, "spawn_pending"
end

function actorService.pollSpawn(ticket)
    if type(ticket) ~= "table" or spawnTickets[ticket] ~= true then
        return nil, "invalid spawn ticket"
    end
    if ticket.state == "ready" then
        local actor = ticket.actor
        ticket.state = "consumed"
        ticket.actor = nil
        spawnTickets[ticket] = nil
        return actor, "spawn_ready"
    end
    if ticket.state == "failed" or ticket.state == "cancelled" then
        spawnTickets[ticket] = nil
        return nil, tostring(ticket.reason or "actor spawn failed")
    end
    if ticket.state ~= "pending" or ticket.provider == nil
        or type(ticket.provider.pollSpawn) ~= "function" then
        spawnTickets[ticket] = nil
        return nil, "spawn ticket cannot be polled"
    end

    local ok, actor, reason = pcall(ticket.provider.pollSpawn,
        ticket.provider, ticket.request)
    if not ok then
        if type(ticket.provider.cancelSpawn) == "function" then
            pcall(ticket.provider.cancelSpawn, ticket.provider, ticket.request)
        end
        ticket.state = "failed"
        ticket.reason = tostring(actor)
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end
    if actor == nil then
        if reason == "spawn_pending" then return nil, reason end
        ticket.state = "failed"
        ticket.reason = tostring(reason or "actor provider spawn failed")
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end

    local finalized, result = finalizeSpawn(actor, ticket.profile, ticket.provider)
    if finalized == nil then
        ticket.state = "failed"
        ticket.reason = tostring(result)
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end
    ticket.state = "consumed"
    spawnTickets[ticket] = nil
    return finalized, result
end

function actorService.cancelSpawn(ticket)
    if type(ticket) ~= "table" or spawnTickets[ticket] ~= true then
        return false, "invalid spawn ticket"
    end
    if ticket.state == "pending" and ticket.provider ~= nil
        and type(ticket.provider.cancelSpawn) == "function" then
        local ok, cancelled, reason = pcall(ticket.provider.cancelSpawn,
            ticket.provider, ticket.request)
        if not ok or cancelled ~= true then
            return false, tostring(reason or cancelled)
        end
    elseif ticket.state == "ready" and ticket.actor ~= nil then
        local removed, reason = actorService.remove(ticket.actor)
        if not removed then return false, tostring(reason) end
    end
    ticket.state = "cancelled"
    ticket.actor = nil
    spawnTickets[ticket] = nil
    return true
end

function actorService.remove(actor)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active SurvivorCompanion actor"
    end
    local ready, reason = actorService.checkBridge(false)
    if not ready then
        return false, reason
    end
    local id = SC.Registry.idOf(actor)
    local activeRecord = id and SC.Registry.byId(id) or nil
    if activeRecord ~= nil and (activeRecord.recruited == true
        or type(activeRecord.factionId) == "string") and SC.Persistence ~= nil
        and type(SC.Persistence.captureRecord) == "function" then
        local capturedOk, snapshot = pcall(SC.Persistence.captureRecord, activeRecord)
        if capturedOk and type(snapshot) == "table" then
            activeRecord.runtime = type(activeRecord.runtime) == "table"
                and activeRecord.runtime or {}
            activeRecord.runtime.lastStableSnapshot = snapshot
        end
    end
    local removedOk, removed, removeReason = pcall(cachedProvider.remove, cachedProvider, actor)
    if not removedOk or removed ~= true then
        local failure = tostring(removeReason or removed or "actor removal failed")
        quarantineRecord(activeRecord, failure)
        return false, "actor removal was not verified; registry record is inactive: " .. failure
    end
    local record, unregisterReason = SC.Registry.unregister(actor)
    if record == nil then
        quarantineRecord(activeRecord, unregisterReason)
        return false, "world removal succeeded but registry cleanup failed: "
            .. tostring(unregisterReason)
    end
    return true, record
end

function actorService.retireDead(actor)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active SurvivorCompanion actor"
    end
    local deadOk, dead = invoke(actor, "isDead")
    if not deadOk or dead ~= true then return false, "actor is still alive" end
    if cachedProvider == nil or type(cachedProvider.retireDead) ~= "function" then
        return false, "actor provider cannot finalize a permanent death"
    end
    local id = SC.Registry.idOf(actor)
    local retiredOk, retired, retireReason = pcall(
        cachedProvider.retireDead, cachedProvider, actor)
    if not retiredOk or retired ~= true then
        return false, tostring(retireReason or retired)
    end
    local record, unregisterReason = SC.Registry.unregister(actor)
    if record == nil then
        return false, "death ownership was released but roster cleanup failed: "
            .. tostring(unregisterReason or id)
    end
    record.permadead = true
    return true, record
end

function actorService.setMovement(actor, mode, intent)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active companion"
    end
    if cachedProvider == nil then
        return false, "actor provider is unavailable"
    end
    local healthy, healthReason = actorService.validateNative(actor)
    if not healthy then return false, "native companion is unhealthy: " .. tostring(healthReason) end
    local effectiveMode = mode
    local effectiveIntent = intent
    if SC.Locomotion and type(SC.Locomotion.resolveMovementMode) == "function"
        and type(intent) == "table" then
        local utility = SC.GameplayUtil
        if utility and type(utility.copyShallow) == "function" then
            effectiveIntent = utility.copyShallow(intent)
        else
            effectiveIntent = {}
            for key, value in pairs(intent) do effectiveIntent[key] = value end
        end
        local resolvedMode, overrideReason = SC.Locomotion.resolveMovementMode(mode, effectiveIntent)
        effectiveMode = resolvedMode or mode
        effectiveIntent.requestedMovementMode = mode
        effectiveIntent.mode = effectiveMode
        effectiveIntent.movementSpeedOverride = overrideReason
        if overrideReason == "escape_speed_override" then
            -- Running away owns the lower body. Drop aim/corner-strafe flags
            -- which make vanilla deliberately walk even when setRunning(true).
            effectiveIntent.weaponReady = false
            effectiveIntent.tacticalCorner = nil
            effectiveIntent.tacticalStrafe = nil
            effectiveIntent.keepFacing = nil
            effectiveIntent.facingTarget = nil
        end
    end
    if SC.Locomotion and type(SC.Locomotion.authorize) == "function" then
        local authorized, locomotionReason = SC.Locomotion.authorize(
            actor, effectiveMode, effectiveIntent)
        if not authorized then return false, locomotionReason end
    end
    local accepted, reason = SC.NativeActions.dispatch(
        actor, effectiveMode, effectiveIntent, cachedProvider)
    if SC.Locomotion and type(SC.Locomotion.noteResult) == "function" then
        SC.Locomotion.noteResult(actor, accepted, reason, effectiveMode, effectiveIntent)
    end
    return accepted, reason
end

function actorService.stop(actor)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active companion"
    end
    if cachedProvider == nil then
        return false, "actor provider is unavailable"
    end
    if type(cachedProvider.stop) == "function" then
        local ok, stopped, reason = pcall(cachedProvider.stop, cachedProvider, actor)
        if not ok or stopped ~= true then
            return false, tostring(reason or stopped)
        end
        if SC.Locomotion and type(SC.Locomotion.noteStop) == "function" then
            SC.Locomotion.noteStop(actor, "provider_stop")
        end
        return true
    end
    if cachedProvider.directNative then
        local stopped = SC.NativeActions.stopDirect(actor)
        if stopped and SC.Locomotion and type(SC.Locomotion.noteStop) == "function" then
            SC.Locomotion.noteStop(actor, "native_stop")
        end
        return stopped, nil
    end
    return false, "provider has no verified stop adapter"
end

function actorService.recover(actor, square)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active companion"
    end
    if cachedProvider == nil or type(cachedProvider.recover) ~= "function" then
        return false, "actor provider cannot recover an unloaded companion"
    end
    local ok, recovered, reason = pcall(cachedProvider.recover,
        cachedProvider, actor, square)
    if not ok or recovered ~= true then
        return false, tostring(reason or recovered)
    end
    return true
end

function actorService.endLife(actor)
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active companion"
    end
    local bridge = globalValue("SCBridge")
    if bridge == nil then return false, "SCBridge is unavailable" end
    local protocolOk, protocol = staticInvoke(bridge, "getProtocol")
    if not protocolOk or protocol ~= expectedNativeProtocol then
        return false, "native bridge protocol mismatch"
    end
    local called, applied = staticInvoke(bridge, "endLife", actor)
    if called and applied == true then return true, "native fatal injury applied" end
    local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
    return false, tostring(reasonOk and reason or applied)
end

function actorService.disposeAll()
    -- Prefer the cached provider so test/alternate providers can own teardown.
    if cachedProvider ~= nil and type(cachedProvider.disposeAll) == "function" then
        local ok, removed, reason = pcall(cachedProvider.disposeAll, cachedProvider)
        if not ok or removed ~= true then return false, tostring(reason or removed) end
        nativeOwned = setmetatable({}, { __mode = "k" })
        experimentalOwned = setmetatable({}, { __mode = "k" })
        return true
    end

    -- Lua can lose its cached provider while Java still owns old-world actors.
    local bridge = globalValue("SCBridge")
    if bridge ~= nil then
        local protocolOk, protocol = staticInvoke(bridge, "getProtocol")
        if protocolOk and protocol == expectedNativeProtocol then
            local ok, removed = staticInvoke(bridge, "removeAll")
            nativeOwned = setmetatable({}, { __mode = "k" })
            if not ok or removed ~= true then
                local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
                return false, tostring(reasonOk and reason or removed)
            end
            return true
        end
    end

    -- Final fallback for the disabled raw test provider.
    if cachedProvider ~= nil and type(cachedProvider.remove) == "function" then
        local clean, failure = true, nil
        for _, record in ipairs(SC.Registry.records()) do
            local actor = record.actor
            local ownedOk, owned = pcall(cachedProvider.isActor, cachedProvider, actor)
            if actor ~= nil and ownedOk and owned == true then
                local removedOk, removed, reason = pcall(
                    cachedProvider.remove, cachedProvider, actor)
                if not removedOk or removed ~= true then
                    clean = false
                    failure = reason or removed
                end
            end
        end
        experimentalOwned = setmetatable({}, { __mode = "k" })
        return clean, failure
    end
    return true
end

function actorService.providerKind()
    return cachedProvider and cachedProvider.kind or nil
end

function actorService._setProviderForTests(provider)
    if type(provider) ~= "table" or provider.testOnly ~= true then
        return false
    end
    cachedProvider = provider
    cachedReady = true
    cachedReason = "test provider"
    return true
end

function actorService.reset()
    cachedProvider = nil
    cachedReady = false
    cachedReason = "actor provider has not been checked"
    experimentalOwned = setmetatable({}, { __mode = "k" })
    experimentalDisabledReason = nil
    nativeOwned = setmetatable({}, { __mode = "k" })
    spawnTickets = setmetatable({}, { __mode = "k" })
end

return actorService
