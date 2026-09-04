-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
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
-- Pending native work is an ownership ledger, not a cache.  Strong references
-- are intentional: losing the caller's last ticket/actor reference must not
-- make an unfinished bridge transaction impossible to retry.
local spawnTickets = {}
local actorCleanupPending = {}
local spawnCleanupPendingPrefix = "spawn_cleanup_pending:"
local expectedNativeProtocol = SC.Identity.bridgeProtocol
local providerKinds = SC.Identity.providers

-- Some supported Build 42 Kahlua paths omit Lua's global next(). Ownership
-- ledgers must remain inspectable during teardown even in that environment.
local function tableHasEntries(value)
    if type(value) ~= "table" then return false end
    for _ in pairs(value) do return true end
    return false
end

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
    return SC.Call.method(object, name, ...)
end

local function staticInvoke(object, name, ...)
    return SC.Call.static(object, name, ...)
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
        kind = providerKinds.experimental,
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
        kind = providerKinds.native,
        directNative = true,
    }
    local awaitingForget = {}
    local cleanupPendingPrefix = spawnCleanupPendingPrefix .. " "

    local function lastBridgeFailure(fallback)
        local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
        return reasonOk and tostring(reason) or tostring(fallback)
    end

    local function forgetRequest(requestId)
        local ok, forgot = staticInvoke(bridge, "forgetSpawnRequest", requestId)
        if ok and forgot == true then return true end
        return false, lastBridgeFailure(forgot)
    end

    local function cancelRequest(requestId)
        local ok, cancelled = staticInvoke(bridge, "cancelSpawnRequest", requestId)
        if ok and cancelled == true then return true end
        return false, lastBridgeFailure(cancelled)
    end

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
        local deferred = awaitingForget[requestId]
        if deferred ~= nil then
            local forgot, forgetReason = forgetRequest(requestId)
            if not forgot then
                return nil, cleanupPendingPrefix .. tostring(forgetReason)
            end
            awaitingForget[requestId] = nil
            if deferred.actor ~= nil then return deferred.actor end
            return nil, tostring(deferred.reason or "native companion spawn failed")
        end
        local stateOk, state = staticInvoke(bridge, "getSpawnState", requestId)
        if not stateOk then
            local cancelled, cancelReason = cancelRequest(requestId)
            if not cancelled then
                return nil, cleanupPendingPrefix .. tostring(cancelReason)
            end
            return nil, "native spawn state query failed"
        end
        state = tostring(state or "unknown")
        if state == "pending" then return nil, "spawn_pending" end
        if state == "failed" then
            local reasonOk, reason = staticInvoke(bridge, "getSpawnFailure", requestId)
            local failure = reasonOk and tostring(reason) or "native companion spawn failed"
            local forgot, forgetReason = forgetRequest(requestId)
            if not forgot then
                awaitingForget[requestId] = { reason = failure }
                return nil, cleanupPendingPrefix .. tostring(forgetReason)
            end
            return nil, failure
        end
        if state == "cleanup_pending" then
            local cancelled, cancelReason = cancelRequest(requestId)
            if not cancelled then
                return nil, cleanupPendingPrefix .. tostring(cancelReason)
            end
            return nil, "native spawn cleanup completed after a failed request"
        end
        if state ~= "ready" then
            return nil, "native spawn request is unknown"
        end

        local resultOk, actor = staticInvoke(bridge, "getSpawnResult", requestId)
        if not resultOk or actor == nil then
            local cancelled, cancelReason = cancelRequest(requestId)
            if not cancelled then
                return nil, cleanupPendingPrefix .. tostring(cancelReason)
            end
            return nil, "native spawn result is unavailable"
        end
        nativeOwned[actor] = true
        local healthy, healthReason = self:validate(actor)
        if not healthy then
            local removeOk, removed = staticInvoke(bridge, "remove", actor)
            if not removeOk or removed ~= true then
                return nil, cleanupPendingPrefix .. lastBridgeFailure(removed)
            end
            nativeOwned[actor] = nil
            local forgot, forgetReason = forgetRequest(requestId)
            if not forgot then
                awaitingForget[requestId] = { reason = healthReason }
                return nil, cleanupPendingPrefix .. tostring(forgetReason)
            end
            return nil, healthReason
        end
        local forgot, forgetReason = forgetRequest(requestId)
        if not forgot then
            awaitingForget[requestId] = { actor = actor }
            return nil, cleanupPendingPrefix .. tostring(forgetReason)
        end
        return actor
    end

    function provider:cancelSpawn(requestId)
        local cancelled, reason = cancelRequest(requestId)
        if cancelled then awaitingForget[requestId] = nil end
        return cancelled, reason
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
        if not ok or removed ~= true then
            local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
            return false, reasonOk and reason or removed
        end
        nativeOwned = setmetatable({}, { __mode = "k" })
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
        if status.provider == providerKinds.experimental then
            status.code = "experimental_provider"
        elseif status.provider == providerKinds.test then
            status.code = "test_provider"
        end
        -- Surface the swing/floor collision capability (review 4.3). The bridge can
        -- report ready while the combat collision reflection is missing, which
        -- silently leaves a combat companion swinging without ever landing a hit.
        -- Report it (and warn once) so the support view and combat gate can see a
        -- degraded state instead of a phantom-ready one.
        local bridge = globalValue("SCBridge")
        if bridge ~= nil then
            local combatOk, combatReady = staticInvoke(bridge, "isCombatCollisionReady")
            if combatOk then status.combatCollision = combatReady == true end
            local floorOk, floorReady = staticInvoke(bridge, "isFloorAttackReady")
            if floorOk then status.floorAttack = floorReady == true end
            if combatOk and combatReady ~= true then
                status.combatCapability = "degraded"
                if not actorService._combatCapabilityWarned then
                    actorService._combatCapabilityWarned = true
                    local failOk, failure = staticInvoke(bridge, "getCombatCapabilityFailure")
                    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                        pcall(SC.Diagnostics.report, "actor-provider", "combat",
                            "native combat collision capability is degraded",
                            failOk and tostring(failure) or "unknown")
                    end
                end
            end
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

local function reportOwnership(summary, detail, id)
    if SC.Diagnostics ~= nil and type(SC.Diagnostics.report) == "function" then
        pcall(SC.Diagnostics.report, "actor-ownership", id, summary, detail)
    end
end

local function registryRecordFor(actor)
    if actor == nil then return nil, nil, true end
    if SC.Registry == nil or type(SC.Registry.idOf) ~= "function" then
        return nil, nil, false, "registry ownership adapter is unavailable"
    end
    local id = nil
    local idOk, idValue = pcall(SC.Registry.idOf, actor)
    if not idOk then return nil, nil, false, tostring(idValue) end
    id = idValue
    local record = nil
    if id ~= nil and type(SC.Registry.byId) == "function" then
        local ok, value = pcall(SC.Registry.byId, id)
        if not ok then return nil, id, false, tostring(value) end
        record = value
    elseif id ~= nil then
        return nil, id, false, "registry record adapter is unavailable"
    end
    return record, id, true
end

local function retainActorCleanup(actor, provider, options)
    if actor == nil or provider == nil then
        return nil, "cleanup ownership cannot be retained without actor and provider"
    end
    options = type(options) == "table" and options or {}
    local entry = actorCleanupPending[actor]
    if entry == nil then
        entry = {
            actor = actor,
            provider = provider,
            operation = options.operation or "remove",
            nativeReleased = options.nativeReleased == true,
            unregister = options.unregister == true,
            permadead = options.permadead == true,
            record = options.record,
            reason = tostring(options.reason or "native actor cleanup is pending"),
            attempts = 0,
        }
        actorCleanupPending[actor] = entry
    else
        -- Never weaken an existing cleanup obligation.  In particular, an
        -- already-released native actor must not be removed a second time.
        entry.provider = entry.provider or provider
        entry.unregister = entry.unregister == true or options.unregister == true
        entry.permadead = entry.permadead == true or options.permadead == true
        entry.record = entry.record or options.record
        if options.nativeReleased == true then entry.nativeReleased = true end
        if options.reason ~= nil then entry.reason = tostring(options.reason) end
    end
    local record, id, registryObserved, registryReason = registryRecordFor(actor)
    record = entry.record or record
    entry.record = record
    if entry.unregister and not registryObserved then
        entry.registryObservationFailure = tostring(registryReason)
    end
    if entry.unregister and type(record) == "table" then
        record.runtime = type(record.runtime) == "table" and record.runtime or {}
        record.runtime.inactive = true
        record.runtime.unrecoverable = true
        record.runtime.removalPending = true
        record.runtime.removalFailure = entry.reason
    end
    reportOwnership("native actor cleanup retained for retry", entry.reason, id)
    return entry
end

local function attemptActorCleanup(actor)
    local entry = actorCleanupPending[actor]
    if entry == nil then return true, "no actor cleanup is pending" end
    entry.attempts = (entry.attempts or 0) + 1

    if entry.nativeReleased ~= true then
        local callback = entry.provider.remove
        if entry.operation == "retireDead" then
            callback = entry.provider.retireDead
        end
        if type(callback) ~= "function" then
            entry.reason = "actor provider has no " .. tostring(entry.operation)
                .. " cleanup adapter"
            reportOwnership("native actor cleanup retry failed", entry.reason)
            return false, entry.reason
        end
        local ok, removed, reason = pcall(callback, entry.provider, actor)
        if not ok or removed ~= true then
            entry.reason = tostring(reason or removed or "actor cleanup failed")
            local _, id = registryRecordFor(actor)
            if type(entry.record) == "table" then
                entry.record.runtime = type(entry.record.runtime) == "table"
                    and entry.record.runtime or {}
                entry.record.runtime.removalFailure = entry.reason
            end
            reportOwnership("native actor cleanup retry failed", entry.reason, id)
            return false, entry.reason
        end
        entry.nativeReleased = true
    end

    local releasedRecord = entry.record
    if entry.unregister == true then
        local record, id, observed, observationReason = registryRecordFor(actor)
        releasedRecord = releasedRecord or record
        if not observed then
            entry.reason = "registry ownership could not be observed: "
                .. tostring(observationReason)
            reportOwnership("registry cleanup retained for retry", entry.reason, id)
            return false, entry.reason
        end
        if id ~= nil then
            if SC.Registry == nil or type(SC.Registry.unregister) ~= "function" then
                entry.reason = "registry unregister adapter is unavailable"
                reportOwnership("registry cleanup retained for retry", entry.reason, id)
                return false, entry.reason
            end
            local ok, unregistered, reason = pcall(SC.Registry.unregister, actor)
            if not ok or unregistered == nil then
                -- A throwing adapter may have committed before it threw.  Only
                -- retry when the registry still proves ownership.
                local remaining, remainingId, remainingObserved, remainingReason =
                    registryRecordFor(actor)
                if not remainingObserved or remainingId ~= nil or remaining ~= nil then
                    entry.reason = tostring(reason or unregistered
                        or remainingReason or "registry cleanup failed")
                    reportOwnership("registry cleanup retained for retry",
                        entry.reason, id)
                    return false, entry.reason
                end
            else
                releasedRecord = unregistered
            end
        end
    end

    if type(releasedRecord) == "table" then
        releasedRecord.runtime = {}
        if entry.permadead == true then releasedRecord.permadead = true end
    end
    actorCleanupPending[actor] = nil
    reportOwnership("native actor cleanup completed after retry",
        "attempts=" .. tostring(entry.attempts))
    return true, releasedRecord
end

local function rollbackSpawn(actor, provider, reason, unregister, record)
    provider = provider or cachedProvider
    if actor == nil then return true end
    local entry, retainReason = retainActorCleanup(actor, provider, {
        operation = "remove",
        unregister = unregister == true,
        record = record,
        reason = reason or "spawn finalization rollback",
    })
    if entry == nil then
        cachedReady = false
        cachedReason = "actor rollback ownership could not be retained: "
            .. tostring(retainReason)
        reportOwnership("actor provider disabled", cachedReason)
        return false, cachedReason
    end
    local cleaned, cleanupReason = attemptActorCleanup(actor)
    if not cleaned then
        cachedReady = false
        cachedReason = "actor rollback was not verified; provider disabled: "
            .. tostring(cleanupReason)
        reportOwnership("actor provider disabled", cachedReason)
        return false, cleanupReason
    end
    return true
end

local function quarantineRecord(record, reason)
    if type(record) ~= "table" then return end
    record.runtime = type(record.runtime) == "table" and record.runtime or {}
    record.runtime.inactive = true
    record.runtime.unrecoverable = true
    record.runtime.removalPending = true
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
        local cleaned, cleanupReason = rollbackSpawn(actor, provider, nativeReason)
        local failure = tostring(nativeReason)
        if not cleaned then
            failure = failure .. "; cleanup pending: " .. tostring(cleanupReason)
        end
        return nil, failure, not cleaned and actor or nil
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
            local failure = "actor initialization failed: "
                .. tostring(initializeReason or result)
            local cleaned, cleanupReason = rollbackSpawn(actor, provider, failure)
            if not cleaned then
                failure = failure .. "; cleanup pending: " .. tostring(cleanupReason)
            end
            return nil, failure, not cleaned and actor or nil
        end
    end

    local record, registerReason = SC.Registry.register(actor, recordInput)
    if record == nil then
        local cleanupRecord, cleanupId, cleanupObserved = registryRecordFor(actor)
        local failure = tostring(registerReason)
        local cleaned, cleanupReason = rollbackSpawn(actor, provider, failure,
            cleanupObserved ~= true or cleanupId ~= nil, cleanupRecord)
        if not cleaned then
            failure = failure .. "; cleanup pending: " .. tostring(cleanupReason)
        end
        return nil, failure, not cleaned and actor or nil
    end
    if SC.Commands and type(SC.Commands.restore) == "function" then
        local restoredOk, restored, characterReason = pcall(SC.Commands.restore, actor, record)
        if not restoredOk or restored ~= true then
            local failure = "character-depth initialization failed: "
                .. tostring(characterReason or restored)
            local cleaned, cleanupReason = rollbackSpawn(actor, provider,
                failure, true, record)
            if not cleaned then
                failure = failure .. "; cleanup pending: " .. tostring(cleanupReason)
            end
            return nil, failure, not cleaned and actor or nil
        end
    end
    return actor, record
end

local function safelyFinalizeSpawn(actor, profile, provider)
    local ok, finalized, result, cleanupActor = pcall(
        finalizeSpawn, actor, profile, provider)
    if ok then return finalized, result, cleanupActor end

    -- Finalization calls adapters owned by several subsystems.  An exception
    -- may happen before or after registry publication, so conservatively
    -- observe registry ownership and retain both cleanup phases when the
    -- observation itself is unavailable.
    local record, id, observed = registryRecordFor(actor)
    local failure = "actor finalization threw: " .. tostring(finalized)
    local cleaned, cleanupReason = rollbackSpawn(actor, provider, failure,
        observed ~= true or id ~= nil, record)
    if not cleaned then
        failure = failure .. "; cleanup pending: " .. tostring(cleanupReason)
    end
    return nil, failure, not cleaned and actor or nil
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
    return safelyFinalizeSpawn(actorOrReason, profile, cachedProvider)
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

local function cancelTicketRequest(ticket, context)
    if type(ticket) ~= "table" or ticket.provider == nil
        or type(ticket.provider.cancelSpawn) ~= "function" then
        return false, tostring(context or "spawn cleanup")
            .. ": spawn cancellation is unavailable"
    end
    local ok, cancelled, reason = pcall(ticket.provider.cancelSpawn,
        ticket.provider, ticket.request)
    if not ok or cancelled ~= true then
        return false, tostring(context or "spawn cleanup") .. ": "
            .. tostring(reason or cancelled)
    end
    return true
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
    if ticket.state == "cleanup_pending" and ticket.actor ~= nil then
        local cleaned, cleanupReason = attemptActorCleanup(ticket.actor)
        if not cleaned then
            ticket.reason = tostring(ticket.failureReason or "actor spawn failed")
                .. "; cleanup pending: " .. tostring(cleanupReason)
            reportOwnership("spawn ticket cleanup is still pending", ticket.reason)
            return nil, "spawn_pending", ticket.reason
        end
        ticket.actor = nil
        ticket.state = "failed"
        ticket.reason = tostring(ticket.failureReason or "actor spawn failed")
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end
    if ticket.state ~= "pending" or ticket.provider == nil
        or type(ticket.provider.pollSpawn) ~= "function" then
        local cancelled, cancelReason = cancelTicketRequest(ticket,
            "spawn ticket cannot be polled")
        if not cancelled then
            ticket.reason = tostring(cancelReason)
            reportOwnership("spawn ticket retained for cancellation retry", ticket.reason)
            return nil, "spawn_pending", ticket.reason
        end
        ticket.state = "failed"
        ticket.reason = "spawn ticket could not be polled and was cancelled"
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end

    local ok, actor, reason = pcall(ticket.provider.pollSpawn,
        ticket.provider, ticket.request)
    if not ok then
        local cancelled, cancelReason = cancelTicketRequest(ticket,
            "spawn provider failed")
        if not cancelled then
            ticket.reason = "spawn provider failed and cleanup is pending: "
                .. tostring(actor) .. "; " .. tostring(cancelReason)
            reportOwnership("spawn ticket retained after provider exception", ticket.reason)
            return nil, "spawn_pending", ticket.reason
        end
        ticket.state = "failed"
        ticket.reason = tostring(actor)
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end
    if actor == nil then
        if reason == "spawn_pending"
            or string.find(tostring(reason or ""), spawnCleanupPendingPrefix,
                1, true) == 1 then
            ticket.reason = tostring(reason)
            if reason ~= "spawn_pending" then
                reportOwnership("native spawn request cleanup is pending", ticket.reason)
            end
            return nil, "spawn_pending", ticket.reason
        end
        ticket.state = "failed"
        ticket.reason = tostring(reason or "actor provider spawn failed")
        spawnTickets[ticket] = nil
        return nil, ticket.reason
    end

    local finalized, result, cleanupActor = safelyFinalizeSpawn(
        actor, ticket.profile, ticket.provider)
    if finalized == nil then
        if cleanupActor ~= nil and actorCleanupPending[cleanupActor] ~= nil then
            ticket.state = "cleanup_pending"
            ticket.actor = cleanupActor
            ticket.failureReason = tostring(result)
            ticket.reason = tostring(result)
            reportOwnership("spawn finalization retained actor and ticket", ticket.reason)
            return nil, "spawn_pending", ticket.reason
        end
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
    if ticket.state == "pending" then
        local cancelled, reason = cancelTicketRequest(ticket,
            "spawn ticket cancellation failed")
        if not cancelled then
            ticket.reason = tostring(reason)
            reportOwnership("spawn ticket cancellation retained for retry", ticket.reason)
            return false, ticket.reason
        end
    elseif ticket.state == "cleanup_pending" and ticket.actor ~= nil then
        local cleaned, reason = attemptActorCleanup(ticket.actor)
        if not cleaned then
            ticket.reason = tostring(ticket.failureReason or "actor spawn failed")
                .. "; cleanup pending: " .. tostring(reason)
            return false, ticket.reason
        end
    elseif ticket.state == "ready" and ticket.actor ~= nil then
        local removed, reason = actorService.remove(ticket.actor)
        if not removed then return false, tostring(reason) end
    elseif ticket.state ~= "failed" and ticket.state ~= "cancelled" then
        ticket.reason = "spawn ticket has an unsupported cleanup state: "
            .. tostring(ticket.state)
        reportOwnership("spawn ticket retained in unsupported state", ticket.reason)
        return false, ticket.reason
    end
    ticket.state = "cancelled"
    ticket.actor = nil
    spawnTickets[ticket] = nil
    return true
end

local function releaseActionOwnership(actor, reason, preserveVehicleBoardCommit)
    local service = SC.ActionSupervisor
    if actor == nil or type(service) ~= "table" or type(service.reset) ~= "function" then
        return true, "action_supervisor_unavailable"
    end
    if preserveVehicleBoardCommit == true and type(service.current) == "function" then
        local token = service.current(actor)
        if token and token.owner == "vehicle" and token.action == "board_vehicle"
            and token.phase == "committing" then
            -- Virtual boarding removes the world actor as the physical effect
            -- of the still-live vehicle transaction.  Its owner must retain
            -- the receipt long enough to enter verifying and complete.
            if type(service.clearUrgent) == "function" then
                service.clearUrgent(actor, reason or "actor_removed")
            end
            if type(service.resetRetry) == "function" then
                service.resetRetry(actor, reason or "actor_removed")
            end
            return true, "vehicle_board_commit_retained"
        end
    end
    service.reset(actor, reason or "actor_removed")
    return true, reason or "actor_removed"
end

local function releaseAllActionOwnership(reason)
    if SC.Registry == nil or type(SC.Registry.records) ~= "function" then
        local service = SC.ActionSupervisor
        if type(service) == "table" and type(service.reset) == "function" then
            service.reset(nil, reason or "actor_unload")
        end
        return
    end
    for _, record in ipairs(SC.Registry.records()) do
        if record.actor ~= nil then releaseActionOwnership(record.actor,
            reason or "actor_unload", false) end
    end
    local service = SC.ActionSupervisor
    if type(service) == "table" and type(service.reset) == "function" then
        service.reset(nil, reason or "actor_unload")
    end
end

function actorService.remove(actor)
    local pendingCleanup = actorCleanupPending[actor]
    if pendingCleanup ~= nil then
        if pendingCleanup.operation ~= "remove" then
            return false, "actor has a different cleanup operation pending: "
                .. tostring(pendingCleanup.operation)
        end
        local cleaned, result = attemptActorCleanup(actor)
        if not cleaned then
            quarantineRecord(pendingCleanup.record, result)
            return false, "actor removal cleanup is still pending: " .. tostring(result)
        end
        return true, result
    end
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
    releaseActionOwnership(actor, "actor_removed", true)
    retainActorCleanup(actor, cachedProvider, {
        operation = "remove",
        unregister = true,
        record = activeRecord,
        reason = "explicit actor removal",
    })
    local cleaned, result = attemptActorCleanup(actor)
    if not cleaned then
        quarantineRecord(activeRecord, result)
        return false, "actor removal was not verified; registry record is inactive; "
            .. "ownership retained for retry: " .. tostring(result)
    end
    return true, result
end

function actorService.retireDead(actor)
    local pendingCleanup = actorCleanupPending[actor]
    if pendingCleanup ~= nil then
        if pendingCleanup.operation ~= "retireDead" then
            return false, "actor has a different cleanup operation pending: "
                .. tostring(pendingCleanup.operation)
        end
        local cleaned, result = attemptActorCleanup(actor)
        if not cleaned then return false, tostring(result) end
        return true, result
    end
    if not actorService.isCompanion(actor) then
        return false, "actor is not an active SurvivorCompanion actor"
    end
    local deadOk, dead = invoke(actor, "isDead")
    if not deadOk or dead ~= true then return false, "actor is still alive" end
    if cachedProvider == nil or type(cachedProvider.retireDead) ~= "function" then
        return false, "actor provider cannot finalize a permanent death"
    end
    local id = SC.Registry.idOf(actor)
    releaseActionOwnership(actor, "actor_death", false)
    local retiredOk, retired, retireReason = pcall(
        cachedProvider.retireDead, cachedProvider, actor)
    if not retiredOk or retired ~= true then
        local failure = tostring(retireReason or retired)
        if retiredOk and failure == "death_pending" then return false, failure end
        retainActorCleanup(actor, cachedProvider, {
            operation = "retireDead",
            unregister = true,
            permadead = true,
            record = id and SC.Registry.byId(id) or nil,
            reason = failure,
        })
        return false, "death cleanup ownership retained for retry: " .. failure
    end
    retainActorCleanup(actor, cachedProvider, {
        operation = "retireDead",
        nativeReleased = true,
        unregister = true,
        permadead = true,
        record = id and SC.Registry.byId(id) or nil,
        reason = "death roster cleanup",
    })
    local cleaned, result = attemptActorCleanup(actor)
    if not cleaned then
        return false, "death ownership was released but roster cleanup is pending: "
            .. tostring(result or id)
    end
    return true, result
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
    releaseAllActionOwnership("actor_unload")
    -- Prefer the cached provider so test/alternate providers can own teardown.
    if cachedProvider ~= nil and type(cachedProvider.disposeAll) == "function" then
        local ok, removed, reason = pcall(cachedProvider.disposeAll, cachedProvider)
        if not ok or removed ~= true then return false, tostring(reason or removed) end
        nativeOwned = setmetatable({}, { __mode = "k" })
        experimentalOwned = setmetatable({}, { __mode = "k" })
        spawnTickets = {}
        actorCleanupPending = {}
        return true
    end

    -- Lua can lose its cached provider while Java still owns old-world actors.
    local bridge = globalValue("SCBridge")
    if bridge ~= nil then
        local protocolOk, protocol = staticInvoke(bridge, "getProtocol")
        if protocolOk and protocol == expectedNativeProtocol then
            local ok, removed = staticInvoke(bridge, "removeAll")
            if not ok or removed ~= true then
                local reasonOk, reason = staticInvoke(bridge, "getLastFailure")
                return false, tostring(reasonOk and reason or removed)
            end
            nativeOwned = setmetatable({}, { __mode = "k" })
            spawnTickets = {}
            actorCleanupPending = {}
            return true
        end
    end

    -- Final fallback for the disabled raw test provider.
    if cachedProvider ~= nil and type(cachedProvider.remove) == "function" then
        local clean, failure = true, nil
        local tickets = {}
        for ticket in pairs(spawnTickets) do tickets[#tickets + 1] = ticket end
        for _, ticket in ipairs(tickets) do
            local cancelled, reason = actorService.cancelSpawn(ticket)
            if not cancelled then
                clean = false
                failure = reason or failure
            end
        end
        local cleanupActors = {}
        for actor in pairs(actorCleanupPending) do
            cleanupActors[#cleanupActors + 1] = actor
        end
        for _, actor in ipairs(cleanupActors) do
            local removed, reason = attemptActorCleanup(actor)
            if not removed then
                clean = false
                failure = reason or failure
            end
        end
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
        if clean then
            experimentalOwned = setmetatable({}, { __mode = "k" })
            spawnTickets = {}
            actorCleanupPending = {}
        end
        return clean, failure
    end
    if tableHasEntries(spawnTickets) or tableHasEntries(actorCleanupPending) then
        return false, "actor ownership remains but no cleanup provider is available"
    end
    return true
end

function actorService.ownershipSnapshot()
    local tickets = 0
    local ticketStates = {}
    for ticket in pairs(spawnTickets) do
        tickets = tickets + 1
        local state = tostring(ticket.state or "unknown")
        ticketStates[state] = (ticketStates[state] or 0) + 1
    end
    local cleanups = 0
    local cleanupDetails = {}
    for actor, entry in pairs(actorCleanupPending) do
        cleanups = cleanups + 1
        cleanupDetails[#cleanupDetails + 1] = {
            actor = actor,
            operation = entry.operation,
            nativeReleased = entry.nativeReleased == true,
            unregister = entry.unregister == true,
            attempts = entry.attempts or 0,
            reason = entry.reason,
        }
    end
    return {
        tickets = tickets,
        ticketStates = ticketStates,
        actorCleanups = cleanups,
        cleanupDetails = cleanupDetails,
    }
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
    local snapshot = actorService.ownershipSnapshot()
    local activeRecords = 0
    if SC.Registry ~= nil and type(SC.Registry.records) == "function" then
        local ok, records = pcall(SC.Registry.records)
        if ok and type(records) == "table" then activeRecords = #records end
    end
    if snapshot.tickets > 0 or snapshot.actorCleanups > 0 or activeRecords > 0 then
        local reason = "actor service reset refused while ownership remains: tickets="
            .. tostring(snapshot.tickets) .. ", cleanups="
            .. tostring(snapshot.actorCleanups) .. ", records=" .. tostring(activeRecords)
        reportOwnership("actor service reset retained live ownership", reason)
        return false, reason
    end
    local service = SC.ActionSupervisor
    if type(service) == "table" and type(service.reset) == "function" then
        service.reset(nil, "actor_service_reset")
    end
    cachedProvider = nil
    cachedReady = false
    cachedReason = "actor provider has not been checked"
    experimentalOwned = setmetatable({}, { __mode = "k" })
    experimentalDisabledReason = nil
    nativeOwned = setmetatable({}, { __mode = "k" })
    spawnTickets = {}
    actorCleanupPending = {}
    return true
end

return actorService
