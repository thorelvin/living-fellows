-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then error("check " .. tostring(checks) .. " failed: " .. message) end
end

local function contains(value, token)
    return string.find(tostring(value or ""), token, 1, true) ~= nil
end

local square = { x = 11, y = 12, z = 0 }
function square:getX() return self.x end
function square:getY() return self.y end
function square:getZ() return self.z end

local actorSequence = 0
local function newActor()
    actorSequence = actorSequence + 1
    local value = {
        __class = "IsoPlayer",
        __owned = true,
        data = {},
        square = square,
        name = "Ownership-" .. tostring(actorSequence),
    }
    function value:getModData() return self.data end
    function value:getBodyDamage() return {} end
    function value:getMoodles() return {} end
    function value:getXp() return {} end
    function value:getEmitter() return {} end
    function value:getVisual() return {} end
    function value:isDead() return false end
    function value:getCurrentSquare() return self.square end
    return value
end

local function resetActorService()
    local ok, reason = SC.Actor.reset()
    check(ok == true, "actor service reset failed: " .. tostring(reason))
    SC.Registry.reset()
end

local function installProvider(provider)
    provider.testOnly = true
    provider.kind = "iso-companion"
    provider.directNative = true
    check(SC.Actor._setProviderForTests(provider), "test provider was rejected")
end

local requestSequence = 900
local function providerFor(candidate, failures)
    requestSequence = requestSequence + 1
    local provider = {
        actor = candidate,
        failures = failures or {},
        pollCalls = 0,
        removeCalls = 0,
        cancelCalls = 0,
        request = requestSequence,
    }
    function provider:isActor(actor) return actor == self.actor and actor.__owned == true end
    function provider:requestSpawn() return self.request end
    function provider:pollSpawn(request)
        self.pollCalls = self.pollCalls + 1
        check(request == self.request, "provider received the wrong request")
        return self.actor
    end
    function provider:remove(actor)
        self.removeCalls = self.removeCalls + 1
        local failure = table.remove(self.failures, 1)
        if failure == "throw" then error("injected provider remove throw") end
        if failure == "false" then return false, "injected provider remove false" end
        actor.__owned = false
        return true
    end
    function provider:cancelSpawn()
        self.cancelCalls = self.cancelCalls + 1
        return true
    end
    return provider
end

local function begin(provider, actor, suffix, initialize)
    installProvider(provider)
    local ticket, reason = SC.Actor.beginSpawn(square, {
        id = "sc-ownership-" .. tostring(suffix),
        recruited = false,
        identity = { forename = "Retry", surname = "Owner" },
        initialize = initialize,
    })
    check(ticket ~= nil and reason == "spawn_pending", "spawn ticket did not begin")
    return ticket
end

-- A failed finalization rollback must retain both the actor and the ticket.
-- Exercise both ordinary false and thrown provider failures.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    local provider = providerFor(candidate, { mode })
    local initializeCalls = 0
    local ticket = begin(provider, candidate, "finalize-" .. mode, function()
        initializeCalls = initializeCalls + 1
        return false, "injected finalization failure"
    end)
    local actor, status, detail = SC.Actor.pollSpawn(ticket)
    local snapshot = SC.Actor.ownershipSnapshot()
    check(actor == nil and status == "spawn_pending" and contains(detail, "cleanup pending")
            and snapshot.tickets == 1 and snapshot.actorCleanups == 1
            and provider.removeCalls == 1,
        "failed finalization did not retain retry ownership for " .. mode)
    actor, status = SC.Actor.pollSpawn(ticket)
    snapshot = SC.Actor.ownershipSnapshot()
    check(actor == nil and contains(status, "actor initialization failed")
            and snapshot.tickets == 0 and snapshot.actorCleanups == 0
            and provider.removeCalls == 2 and initializeCalls == 1
            and candidate.__owned == false,
        "finalization cleanup retry did not release exactly once for " .. mode)
end

-- An exception outside profile.initialize (for example in background/profile
-- preparation) is also a finalization boundary and must enter the same
-- retryable rollback ledger.
resetActorService()
local throwingFinalizeActor = newActor()
local throwingFinalizeProvider = providerFor(throwingFinalizeActor, { "false" })
local throwingFinalizeTicket = begin(throwingFinalizeProvider,
    throwingFinalizeActor, "finalize-outer-throw")
local realPrepareProfile = SC.Background.prepareProfile
SC.Background.prepareProfile = function() error("injected outer finalization throw") end
local _, throwingFinalizeStatus, throwingFinalizeDetail =
    SC.Actor.pollSpawn(throwingFinalizeTicket)
SC.Background.prepareProfile = realPrepareProfile
check(throwingFinalizeStatus == "spawn_pending"
        and contains(throwingFinalizeDetail, "actor finalization threw")
        and SC.Actor.ownershipSnapshot().actorCleanups == 1,
    "outer finalization exception did not retain rollback ownership")
local _, throwingFinalizeTerminal = SC.Actor.pollSpawn(throwingFinalizeTicket)
check(contains(throwingFinalizeTerminal, "actor finalization threw")
        and throwingFinalizeProvider.removeCalls == 2
        and SC.Actor.ownershipSnapshot().actorCleanups == 0,
    "outer finalization rollback did not release on retry")

-- An explicit remove failure quarantines gameplay use but remains callable as
-- a cleanup retry.  A successful retry unregisters exactly once.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    local provider = providerFor(candidate, {})
    local ticket = begin(provider, candidate, "remove-" .. mode)
    local spawned = SC.Actor.pollSpawn(ticket)
    check(spawned == candidate, "remove fixture did not finalize")
    provider.failures = { mode }
    local removed, reason = SC.Actor.remove(candidate)
    local record = SC.Registry.byId("sc-ownership-remove-" .. mode)
    check(not removed and contains(reason, "retained for retry")
            and record ~= nil and record.runtime.inactive == true
            and record.runtime.removalPending == true
            and SC.Actor.ownershipSnapshot().actorCleanups == 1,
        "remove failure did not retain its actor/record for " .. mode)
    removed = SC.Actor.remove(candidate)
    check(removed == true and provider.removeCalls == 2
            and SC.Registry.idOf(candidate) == nil
            and SC.Actor.ownershipSnapshot().actorCleanups == 0,
        "remove retry did not release exactly once for " .. mode)
end

-- Permanent-death cleanup has the same ownership guarantee.  The ordinary
-- death_pending response remains active, while unexpected false/throw results
-- are quarantined with a callable retry handle.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    local provider = providerFor(candidate, {})
    provider.retireCalls = 0
    function provider:retireDead(actor)
        self.retireCalls = self.retireCalls + 1
        if self.retireCalls == 1 then
            if mode == "throw" then error("injected retire throw") end
            return false, "injected retire false"
        end
        actor.__owned = false
        return true
    end
    local id = "sc-ownership-retire-" .. mode
    local ticket = begin(provider, candidate, "retire-" .. mode)
    check(SC.Actor.pollSpawn(ticket) == candidate, "retire fixture did not finalize")
    function candidate:isDead() return true end
    local retired, reason = SC.Actor.retireDead(candidate)
    check(not retired and contains(reason, "retained for retry")
            and SC.Registry.byId(id).runtime.inactive == true
            and SC.Actor.ownershipSnapshot().actorCleanups == 1,
        "retire failure did not retain ownership for " .. mode)
    local retiredRecord
    retired, retiredRecord = SC.Actor.retireDead(candidate)
    check(retired == true and retiredRecord.permadead == true
            and provider.retireCalls == 2 and SC.Registry.byId(id) == nil
            and SC.Actor.ownershipSnapshot().actorCleanups == 0,
        "retire retry did not release exactly once for " .. mode)
end

-- Native removal may commit before registry cleanup fails.  The retry must
-- only unregister; calling provider.remove twice would be a double release.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    local provider = providerFor(candidate, {})
    local id = "sc-ownership-registry-" .. mode
    local ticket = begin(provider, candidate, "registry-" .. mode)
    check(SC.Actor.pollSpawn(ticket) == candidate, "registry fixture did not finalize")
    local realUnregister = SC.Registry.unregister
    SC.Registry.unregister = function()
        if mode == "throw" then error("injected registry unregister throw") end
        return nil, "injected registry unregister false"
    end
    local removed, reason = SC.Actor.remove(candidate)
    SC.Registry.unregister = realUnregister
    check(not removed and contains(reason, "retained for retry")
            and provider.removeCalls == 1 and SC.Registry.byId(id) ~= nil,
        "registry failure did not retain registry-only cleanup for " .. mode)
    removed = SC.Actor.remove(candidate)
    check(removed == true and provider.removeCalls == 1
            and SC.Registry.byId(id) == nil
            and SC.Actor.ownershipSnapshot().actorCleanups == 0,
        "registry-only retry repeated native removal for " .. mode)
end

-- A request provider without a poll/cancel adapter cannot authorize release.
resetActorService()
local missingAdapter = { requests = 0, cancels = 0 }
function missingAdapter:isActor() return false end
function missingAdapter:requestSpawn() self.requests = self.requests + 1 return 1201 end
installProvider(missingAdapter)
local missingTicket = SC.Actor.beginSpawn(square, { id = "sc-ownership-missing-adapter" })
local _, missingStatus, missingDetail = SC.Actor.pollSpawn(missingTicket)
check(missingStatus == "spawn_pending" and contains(missingDetail, "unavailable")
        and SC.Actor.ownershipSnapshot().tickets == 1,
    "missing poll/cancel adapter discarded a live request")
function missingAdapter:cancelSpawn() self.cancels = self.cancels + 1 return true end
local _, cancelledStatus = SC.Actor.pollSpawn(missingTicket)
check(contains(cancelledStatus, "was cancelled") and missingAdapter.cancels == 1
        and SC.Actor.ownershipSnapshot().tickets == 0,
    "installed cancellation adapter did not release the retained request")

-- Provider exceptions retain the ticket when cancellation returns false or
-- throws, then release it only after an explicit successful retry.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local provider = { cancelCalls = 0 }
    function provider:isActor() return false end
    function provider:requestSpawn() return 1301 end
    function provider:pollSpawn() error("injected poll exception") end
    function provider:cancelSpawn()
        self.cancelCalls = self.cancelCalls + 1
        if self.cancelCalls == 1 then
            if mode == "throw" then error("injected cancel throw") end
            return false, "injected cancel false"
        end
        return true
    end
    installProvider(provider)
    local ticket = SC.Actor.beginSpawn(square,
        { id = "sc-ownership-poll-" .. mode })
    local _, status, detail = SC.Actor.pollSpawn(ticket)
    check(status == "spawn_pending" and contains(detail, "cleanup is pending")
            and SC.Actor.ownershipSnapshot().tickets == 1,
        "poll/cancel failure discarded the request for " .. mode)
    local cancelled, reason = SC.Actor.cancelSpawn(ticket)
    check(cancelled == true and reason == nil and provider.cancelCalls == 2
            and SC.Actor.ownershipSnapshot().tickets == 0,
        "poll/cancel retry did not release once for " .. mode)
end

local function fakeBridge(mode, state, candidate)
    local bridge = {
        mode = mode,
        state = state,
        actor = candidate,
        forgetCalls = 0,
        cancelCalls = 0,
        removeCalls = 0,
        lastFailure = "",
    }
    function bridge.getProtocol() return SC.Identity.bridgeProtocol end
    function bridge.checkReady() return "" end
    function bridge.requestSpawn() return 1401 end
    function bridge.getSpawnState() return bridge.state end
    function bridge.getSpawnFailure() return "injected bridge spawn failure" end
    function bridge.getSpawnResult() return bridge.actor end
    function bridge.isCompanion(actor) return actor == bridge.actor and actor.__owned == true end
    function bridge.checkActor() return "" end
    function bridge.forgetSpawnRequest()
        bridge.forgetCalls = bridge.forgetCalls + 1
        if bridge.forgetCalls == 1 then
            bridge.lastFailure = "injected bridge forget " .. mode
            if mode == "throw" then error(bridge.lastFailure) end
            return false
        end
        return true
    end
    function bridge.cancelSpawnRequest()
        bridge.cancelCalls = bridge.cancelCalls + 1
        bridge.state = "unknown"
        if bridge.actor ~= nil then bridge.actor.__owned = false end
        return true
    end
    function bridge.remove(actor)
        bridge.removeCalls = bridge.removeCalls + 1
        actor.__owned = false
        return true
    end
    function bridge.removeAll() return true end
    function bridge.getLastFailure() return bridge.lastFailure end
    return bridge
end

-- A throwing state query followed by a false/throwing bridge cancellation is
-- still a live native request.  The second verified cancellation releases it.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    SCBridge = fakeBridge(mode, "pending", nil)
    SCBridge.cancelCalls = 0
    SCBridge.getSpawnState = function() error("injected bridge poll throw") end
    SCBridge.cancelSpawnRequest = function()
        SCBridge.cancelCalls = SCBridge.cancelCalls + 1
        if SCBridge.cancelCalls == 1 then
            SCBridge.lastFailure = "injected bridge cancel " .. mode
            if mode == "throw" then error(SCBridge.lastFailure) end
            return false
        end
        return true
    end
    check(SC.Actor.checkBridge(true) == true, "bridge cancel fixture was not selected")
    local ticket = SC.Actor.beginSpawn(square,
        { id = "sc-ownership-bridge-cancel-" .. mode })
    local _, status, detail = SC.Actor.pollSpawn(ticket)
    check(status == "spawn_pending" and contains(detail, "spawn_cleanup_pending")
            and SCBridge.cancelCalls == 1 and SC.Actor.ownershipSnapshot().tickets == 1,
        "bridge cancellation failure discarded its request for " .. mode)
    local _, terminal = SC.Actor.pollSpawn(ticket)
    check(terminal == "native spawn state query failed"
            and SCBridge.cancelCalls == 2 and SC.Actor.ownershipSnapshot().tickets == 0,
        "bridge cancellation retry did not release exactly once for " .. mode)
    SCBridge = nil
end

-- Exercise the real Lua bridge adapter's failed-request forget transaction.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    SCBridge = fakeBridge(mode, "failed", nil)
    local ready, reason = SC.Actor.checkBridge(true)
    check(ready == true, "fake native bridge was not selected: " .. tostring(reason))
    local ticket = SC.Actor.beginSpawn(square,
        { id = "sc-ownership-bridge-failed-" .. mode })
    local _, status, detail = SC.Actor.pollSpawn(ticket)
    check(status == "spawn_pending" and contains(detail, "spawn_cleanup_pending")
            and SCBridge.forgetCalls == 1 and SC.Actor.ownershipSnapshot().tickets == 1,
        "bridge forget failure discarded its request for " .. mode)
    local _, terminal = SC.Actor.pollSpawn(ticket)
    check(terminal == "injected bridge spawn failure"
            and SCBridge.forgetCalls == 2
            and SC.Actor.ownershipSnapshot().tickets == 0,
        "bridge forget retry did not release exactly once for " .. mode)
    SCBridge = nil
end

-- The real Lua bridge provider must also retain actors when SCBridge.remove
-- returns false or throws, and retry through the inactive registry record.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    SCBridge = fakeBridge(mode, "ready", candidate)
    SCBridge.forgetCalls = 1 -- this fixture tests removal, not forget recovery
    SCBridge.removeCalls = 0
    SCBridge.remove = function(actor)
        SCBridge.removeCalls = SCBridge.removeCalls + 1
        if SCBridge.removeCalls == 1 then
            SCBridge.lastFailure = "injected bridge remove " .. mode
            if mode == "throw" then error(SCBridge.lastFailure) end
            return false
        end
        actor.__owned = false
        return true
    end
    check(SC.Actor.checkBridge(true) == true, "bridge remove fixture was not selected")
    local id = "sc-ownership-bridge-remove-" .. mode
    local ticket = SC.Actor.beginSpawn(square, {
        id = id,
        identity = { forename = "Remove", surname = "Bridge" },
    })
    check(SC.Actor.pollSpawn(ticket) == candidate, "bridge remove fixture did not finalize")
    local removed, reason = SC.Actor.remove(candidate)
    check(not removed and contains(reason, "retained for retry")
            and SCBridge.removeCalls == 1 and SC.Registry.byId(id) ~= nil,
        "bridge remove failure discarded actor ownership for " .. mode)
    removed = SC.Actor.remove(candidate)
    check(removed == true and SCBridge.removeCalls == 2
            and SC.Registry.byId(id) == nil,
        "bridge remove retry did not release exactly once for " .. mode)
    SCBridge = nil
end

-- A ready actor remains strongly held while forget fails, and finalization
-- runs once only after the request ledger commits.
for _, mode in ipairs({ "false", "throw" }) do
    resetActorService()
    local candidate = newActor()
    SCBridge = fakeBridge(mode, "ready", candidate)
    check(SC.Actor.checkBridge(true) == true, "ready fake bridge was not selected")
    local initializeCalls = 0
    local ticket = SC.Actor.beginSpawn(square, {
        id = "sc-ownership-bridge-ready-" .. mode,
        identity = { forename = "Bridge", surname = "Owner" },
        initialize = function() initializeCalls = initializeCalls + 1 return true end,
    })
    local actor, status = SC.Actor.pollSpawn(ticket)
    check(actor == nil and status == "spawn_pending"
            and SCBridge.forgetCalls == 1 and initializeCalls == 0,
        "ready actor escaped before request finalization for " .. mode)
    local readyStatus, readyDetail
    actor, readyStatus, readyDetail = SC.Actor.pollSpawn(ticket)
    check(actor == candidate and initializeCalls == 1 and SCBridge.forgetCalls == 2,
        "ready actor was not finalized exactly once for " .. mode
            .. ": actor=" .. tostring(actor) .. " status=" .. tostring(readyStatus)
            .. " detail=" .. tostring(readyDetail) .. " initialize="
            .. tostring(initializeCalls) .. " forget=" .. tostring(SCBridge.forgetCalls))
    check(SC.Actor.remove(candidate) == true and SCBridge.removeCalls == 1,
        "ready bridge fixture could not release its actor")
    SCBridge = nil
end

-- reset is not an escape hatch for an unowned native request.
resetActorService()
local resetProvider = {}
function resetProvider:isActor() return false end
function resetProvider:requestSpawn() return 1501 end
function resetProvider:pollSpawn() return nil, "spawn_pending" end
installProvider(resetProvider)
local resetTicket = SC.Actor.beginSpawn(square, { id = "sc-ownership-reset" })
local resetOk, resetReason = SC.Actor.reset()
check(resetOk == false and contains(resetReason, "ownership remains")
        and SC.Actor.ownershipSnapshot().tickets == 1,
    "reset discarded an outstanding ticket")
function resetProvider:cancelSpawn() return true end
check(SC.Actor.cancelSpawn(resetTicket) == true, "reset fixture could not cancel ticket")
check(SC.Actor.reset() == true, "clean actor service reset was rejected")

SCBridge = nil
SC.Registry.reset()
print("ACTOR_OWNERSHIP_PASS checks=" .. tostring(checks)
    .. " false-throw=true request=true ticket=true actor=true retry=exactly-once")
