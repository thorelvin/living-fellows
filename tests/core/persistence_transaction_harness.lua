-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local function deepEqual(left, right, seen)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local SC = SurvivorCompanion
local function playerFor(document)
    local data = { SC_SaveV1 = document }
    return { getModData = function() return data end }, data
end

local function emptyInventory()
    return {
        schema = 2, complete = true, count = 0, roots = {}, legacy = false,
        equipment = { worn = {}, attached = {} },
    }
end

local function record(id)
    return {
        id = id, recruited = true, factionId = "household-alpha",
        factionRole = "guard", factionLeader = true,
        identity = { forename = "Morgan", surname = "Reed", gender = "female", outfit = "" },
        position = { x = 10, y = 20, z = 0 },
        inventory = emptyInventory(),
        skills = { { id = "Axe", level = 4, xp = 812.5 } },
        vitals = {}, order = { mode = "follow" },
    }
end

-- Mixed numeric/string bucket keys must never enter table.sort's incomparable
-- key path. Invalid numeric keys remain raw quarantine passthrough values.
check(SC.Persistence.reset() == true, "persistence starts from a clean transaction")
local mixedValid = record("sc-mixed-valid")
local mixedRaw = { marker = "numeric-key-must-survive" }
local mixedDocument = {
    schema = SC.Identity.saveSchema,
    companions = { [7] = mixedRaw, ["sc-mixed-valid"] = mixedValid },
    factionActors = {},
}
local mixedPlayer, mixedData = playerFor(mixedDocument)
local mixedRestored, mixedReason = SC.Persistence.restore(mixedPlayer)
check(mixedRestored == true and mixedReason ~= nil
        and SC.Persistence.isPending("sc-mixed-valid"),
    "mixed numeric/string keys restore without a sort exception: restored="
        .. tostring(mixedRestored) .. " reason=" .. tostring(mixedReason)
        .. " pending=" .. tostring(SC.Persistence.isPending("sc-mixed-valid")))
local mixedSaved, mixedOutgoing = SC.Persistence.save(mixedPlayer)
check(mixedSaved == true and mixedOutgoing.companions[7].marker == mixedRaw.marker
        and mixedData.SC_SaveV1.companions[7].marker == mixedRaw.marker,
    "invalid numeric-key data is re-emitted without truncation")

-- A malformed top-level actor bucket cannot be treated as empty, because the
-- next save would erase it. It also must fail before a subsystem is invoked.
check(SC.Persistence.reset() == true, "mixed-key state resets cleanly")
local subsystemCalls = 0
local priorCommunity = SC.Community
SC.Community = {
    restore = function() subsystemCalls = subsystemCalls + 1 return true end,
    export = function() return {} end,
}
local malformedDocument = {
    schema = SC.Identity.saveSchema, companions = {},
    factionActors = "not-a-table", community = { sentinel = "untouched" },
}
local malformedPlayer, malformedData = playerFor(malformedDocument)
local malformedRestored, malformedReason = SC.Persistence.restore(malformedPlayer)
local malformedSaved = SC.Persistence.save(malformedPlayer)
check(malformedRestored == false
        and string.find(tostring(malformedReason), "factionActors", 1, true) ~= nil
        and subsystemCalls == 0,
    "malformed factionActors blocks before subsystem restore")
check(malformedSaved == false and malformedData.SC_SaveV1 == malformedDocument
        and malformedData.SC_SaveV1.community.sentinel == "untouched",
    "malformed factionActors leaves the exact prior document assigned")

check(SC.Persistence.reset() == true, "malformed bucket block resets explicitly")
local mutatingRaw = { sentinel = "original", nested = { value = 17 } }
SC.Community = {
    restore = function(input)
        input.sentinel = "mutated"
        input.nested.value = -1
        return false, "injected mutating subsystem rejection"
    end,
    export = function() return { sentinel = "replacement" } end,
}
local mutatingDocument = {
    schema = SC.Identity.saveSchema, companions = {}, factionActors = {},
    community = mutatingRaw,
}
local mutatingPlayer = playerFor(mutatingDocument)
check(SC.Persistence.restore(mutatingPlayer) == true,
    "subsystem rejection commits raw quarantine rather than gameplay state")
local mutatingSaved, mutatingOutgoing = SC.Persistence.save(mutatingPlayer)
check(mutatingSaved == true
        and mutatingOutgoing.community.sentinel == "original"
        and mutatingOutgoing.community.nested.value == 17
        and mutatingRaw.sentinel == "original" and mutatingRaw.nested.value == 17,
    "mutating restore adapter receives a disposable copy and cannot corrupt passthrough raw data")

-- Manual subsystem retry is the same trust boundary as initial restore. Both a
-- thrown adapter and an explicit rejection may mutate only their disposable
-- input; the quarantined raw value must remain byte-for-value saveable.
local subsystemRetryMode = "throw"
SC.Community.restore = function(input)
    input.sentinel = "retry-mutated"
    input.nested.value = -99
    if subsystemRetryMode == "throw" then
        error("injected mutating subsystem retry exception")
    end
    if subsystemRetryMode == "false" then
        return false, "injected mutating subsystem retry rejection"
    end
    return true
end
local threwRetry = SC.Persistence.retrySubsystem("community")
check(threwRetry == false
        and SC.Persistence.quarantineSnapshot().subsystems.community ~= nil,
    "throwing subsystem retry remains quarantined")
local threwSaved, threwOutgoing = SC.Persistence.save(mutatingPlayer)
check(threwSaved == true and deepEqual(threwOutgoing.community, mutatingRaw),
    "throwing mutating subsystem retry preserves untouched raw state")

subsystemRetryMode = "false"
local rejectedRetry = SC.Persistence.retrySubsystem("community")
check(rejectedRetry == false
        and SC.Persistence.quarantineSnapshot().subsystems.community ~= nil,
    "false subsystem retry remains quarantined")
local rejectedSaved, rejectedOutgoing = SC.Persistence.save(mutatingPlayer)
check(rejectedSaved == true and deepEqual(rejectedOutgoing.community, mutatingRaw),
    "false mutating subsystem retry preserves untouched raw state")

subsystemRetryMode = "success"
check(SC.Persistence.retrySubsystem("community") == true
        and SC.Persistence.quarantineSnapshot().subsystems.community == nil,
    "successful disposable subsystem retry releases quarantine")
SC.Community = priorCommunity

-- Accepted actor records use a normalized working record for activation, but
-- must retain and re-emit their untouched accepted raw value until activation
-- succeeds. A legacy inventory makes any accidental normalized write visible.
check(SC.Persistence.reset() == true, "subsystem retry state resets cleanly")
local function legacyRecord(id, recruited, factionId)
    local value = record(id)
    value.recruited = recruited == true
    value.factionId = factionId
    value.inventory = {
        {
            type = "Base.Katana", condition = 7,
            forwardOnly = { marker = "must-survive-normalization" },
        },
    }
    value.forwardOnly = { schema = 77, marker = id }
    return value
end

local priorCellForRaw = getCell
local priorBeginForRaw = SC.Actor.beginSpawn
local priorPollForRaw = SC.Actor.pollSpawn
local priorFactionsForRaw = SC.Factions
getCell = function()
    return { getGridSquare = function() return { x = 10, y = 20, z = 0 } end }
end
SC.Actor.beginSpawn = function()
    return nil, "invalid injected terminal activation"
end
SC.Actor.pollSpawn = function()
    error("terminal beginSpawn rejection must not produce a poll ticket")
end
SC.Factions = {
    group = function(id)
        if id == "raw-household" then return { id = id } end
        return nil
    end,
}

local terminalCompanion = legacyRecord("sc-raw-terminal", true, "raw-household")
local terminalFaction = legacyRecord("sc-raw-faction-terminal", false, "raw-household")
local terminalDocument = {
    schema = SC.Identity.saveSchema,
    companions = { [terminalCompanion.id] = terminalCompanion },
    factionActors = { [terminalFaction.id] = terminalFaction },
}
local terminalPlayer = playerFor(terminalDocument)
check(SC.Persistence.restore(terminalPlayer) == true,
    "terminal actor activation failures do not reject the accepted document")
local terminalPending = SC.Persistence.pendingSnapshot()
check(terminalPending[terminalCompanion.id].status == "quarantined"
        and terminalPending[terminalFaction.id].status == "quarantined",
    "companion and faction actor enter terminal activation quarantine")
local terminalSaved, terminalOutgoing = SC.Persistence.save(terminalPlayer)
check(terminalSaved == true
        and deepEqual(terminalOutgoing.companions[terminalCompanion.id], terminalCompanion)
        and deepEqual(terminalOutgoing.factionActors[terminalFaction.id], terminalFaction),
    "terminal activation quarantine re-emits untouched companion and faction raw records")

check(SC.Persistence.retry(terminalCompanion.id) == true
        and SC.Persistence.retry(terminalFaction.id) == true,
    "manual retry schedules both terminal actor classes")
local retrySaved, retryOutgoing = SC.Persistence.save(terminalPlayer)
check(retrySaved == true
        and deepEqual(retryOutgoing.companions[terminalCompanion.id], terminalCompanion)
        and deepEqual(retryOutgoing.factionActors[terminalFaction.id], terminalFaction),
    "pending manual retries retain bucket identity and untouched raw records")

-- A faction actor may first be quarantined because its group is unavailable.
-- Once the group appears, the quarantine-to-pending manual path must attach
-- the same raw record instead of retaining only validateRecord's normalized
-- working value.
check(SC.Persistence.reset() == true, "terminal raw records reset cleanly")
SC.Factions = { group = function() return nil end }
local delayedFaction = legacyRecord("sc-raw-faction-delayed", false, "delayed-household")
local delayedDocument = {
    schema = SC.Identity.saveSchema, companions = {},
    factionActors = { [delayedFaction.id] = delayedFaction },
}
local delayedPlayer = playerFor(delayedDocument)
check(SC.Persistence.restore(delayedPlayer) == true
        and not SC.Persistence.isPending(delayedFaction.id)
        and SC.Persistence.quarantineSnapshot().factionActors[delayedFaction.id] ~= nil,
    "unavailable faction keeps its actor in raw quarantine")
SC.Factions = {
    group = function(id)
        if id == "delayed-household" then return { id = id } end
        return nil
    end,
}
check(SC.Persistence.retry(delayedFaction.id) == true
        and SC.Persistence.isPending(delayedFaction.id),
    "manual faction retry moves accepted raw state back to pending")
local delayedSaved, delayedOutgoing = SC.Persistence.save(delayedPlayer)
check(delayedSaved == true
        and deepEqual(delayedOutgoing.factionActors[delayedFaction.id], delayedFaction),
    "quarantine-to-pending faction retry re-emits untouched raw state")

check(SC.Persistence.reset() == true, "manual faction retry state resets cleanly")
getCell = priorCellForRaw
SC.Actor.beginSpawn = priorBeginForRaw
SC.Actor.pollSpawn = priorPollForRaw
SC.Factions = priorFactionsForRaw

-- Build a real pending spawn ticket, then inject every checked cancellation
-- boundary. False and thrown cancellation outcomes retain the same ticket and
-- pending record rather than silently replacing/resetting it.
check(SC.Persistence.reset() == true, "subsystem quarantine resets explicitly")
local priorCell = getCell
getCell = function()
    return { getGridSquare = function() return { x = 10, y = 20, z = 0 } end }
end
local priorBeginSpawn = SC.Actor.beginSpawn
local priorPollSpawn = SC.Actor.pollSpawn
local priorCancelSpawn = SC.Actor.cancelSpawn
local ticket = { identity = "retained-ticket" }
SC.Actor.beginSpawn = function() return ticket, "spawn_pending" end
SC.Actor.pollSpawn = function(value)
    check(value == ticket, "restore pulse polls the owned ticket")
    return nil, "spawn_pending"
end
local cancelMode = "false"
SC.Actor.cancelSpawn = function(value)
    check(value == ticket, "cancellation receives the exact pending ticket")
    if cancelMode == "throw" then error("injected cancellation exception") end
    if cancelMode == "false" then return false, "injected cancellation refusal" end
    return true
end

local firstDocument = {
    schema = SC.Identity.saveSchema,
    companions = { ["sc-ticket-one"] = record("sc-ticket-one") }, factionActors = {},
}
local firstPlayer = playerFor(firstDocument)
check(SC.Persistence.restore(firstPlayer) == true
        and SC.Persistence.pendingSnapshot()["sc-ticket-one"].hasSpawnTicket == true,
    "initial import retains a deferred spawn ticket")

local replacementDocument = {
    schema = SC.Identity.saveSchema,
    companions = { ["sc-ticket-two"] = record("sc-ticket-two") }, factionActors = {},
}
local replacementPlayer = playerFor(replacementDocument)
local replaced, replaceReason = SC.Persistence.restore(replacementPlayer)
check(replaced == false
        and string.find(tostring(replaceReason), "cancellation refusal", 1, true) ~= nil
        and SC.Persistence.isPending("sc-ticket-one")
        and not SC.Persistence.isPending("sc-ticket-two")
        and SC.Persistence.pendingSnapshot()["sc-ticket-one"].hasSpawnTicket == true,
    "document replacement retains old pending state when cancellation returns false")

cancelMode = "throw"
local retried, retryReason = SC.Persistence.retry("sc-ticket-one")
check(retried == false
        and string.find(tostring(retryReason), "cancellation exception", 1, true) ~= nil
        and SC.Persistence.pendingSnapshot()["sc-ticket-one"].hasSpawnTicket == true,
    "manual retry retains its ticket when cancellation throws")
local emptyPlayer = playerFor(nil)
local emptied, emptyReason = SC.Persistence.restore(emptyPlayer)
check(emptied == false
        and string.find(tostring(emptyReason), "cancellation exception", 1, true) ~= nil
        and SC.Persistence.pendingSnapshot()["sc-ticket-one"].hasSpawnTicket == true,
    "empty-document restore cannot discard a ticket after cancellation throws")

cancelMode = "false"
local reset, resetReason = SC.Persistence.reset()
check(reset == false
        and string.find(tostring(resetReason), "cancellation refusal", 1, true) ~= nil
        and SC.Persistence.pendingSnapshot()["sc-ticket-one"].hasSpawnTicket == true,
    "reset retains pending ticket/state after cancellation refusal")

cancelMode = "true"
check(SC.Persistence.reset() == true and SC.Persistence.pendingCount() == 0,
    "successful cancellation permits the deferred-state reset to commit")

-- Initial activation exceptions are isolated from document import. The raw
-- record remains pending and saveable after the pulse throws.
SC.Actor.beginSpawn = function() error("injected initial restore-pulse exception") end
SC.Actor.pollSpawn = priorPollSpawn
local pulseDocument = {
    schema = SC.Identity.saveSchema,
    companions = { ["sc-pulse-retained"] = record("sc-pulse-retained") }, factionActors = {},
}
local pulsePlayer = playerFor(pulseDocument)
local pulseRestored = SC.Persistence.restore(pulsePlayer)
local committed, commitReason = SC.Persistence.restoreStatus()
check(pulseRestored == true and committed == true and commitReason == nil
        and SC.Persistence.isPending("sc-pulse-retained"),
    "initial restore-pulse exception preserves a committed pending import")
local pulseSaved, pulseOutgoing = SC.Persistence.save(pulsePlayer)
check(pulseSaved == true and pulseOutgoing.companions["sc-pulse-retained"] ~= nil,
    "pulse exception cannot turn imported raw data into a destructive save failure")

SC.Actor.beginSpawn = priorBeginSpawn
SC.Actor.pollSpawn = priorPollSpawn
SC.Actor.cancelSpawn = priorCancelSpawn
getCell = priorCell

-- LF-002 boundary: a provider-unavailable record at the configured inventory
-- depth and count must round-trip every equipment/personal/skill/faction field.
check(SC.Persistence.reset() == true, "pulse-exception state resets cleanly")
local maximumItems = SC.Config.get("persistence", "maxSavedInventoryItems")
local maximumDepth = SC.Config.get("persistence", "maxSavedInventoryDepth")
local roots, first, cursor = {}, nil, nil
for index = 1, maximumItems do
    local node = {
        id = "item-" .. tostring(index), type = "Base.Item" .. tostring(index),
        children = {}, weaponParts = {},
    }
    if index == 1 then
        node.favorite = true
        node.personal = {
            version = 1, ownerId = "sc-max-pending", key = "keepsake-key", kind = "memento",
        }
        first, cursor = node, node
        roots[#roots + 1] = node
    elseif index <= maximumDepth then
        cursor.children[1] = node
        cursor = node
    else
        roots[#roots + 1] = node
    end
end
local maximumRecord = record("sc-max-pending")
maximumRecord.inventory = {
    schema = 2, complete = true, count = maximumItems, roots = roots, legacy = false,
    equipment = {
        primary = "item-1", secondary = "item-2",
        worn = { { id = "item-3", location = "Torso1" } },
        attached = { { id = "item-4", location = "Belt Left" } },
    },
}
local maximumDocument = {
    schema = SC.Identity.saveSchema,
    companions = { ["sc-max-pending"] = maximumRecord }, factionActors = {},
}
local maximumPlayer = playerFor(maximumDocument)
check(SC.Persistence.restore(maximumPlayer) == true
        and SC.Persistence.isPending("sc-max-pending"),
    "configured maximum inventory depth/count imports while provider/world is unavailable")
local maximumSaved, maximumOutgoing = SC.Persistence.save(maximumPlayer)
check(maximumSaved == true
        and deepEqual(maximumOutgoing.companions["sc-max-pending"], maximumRecord),
    "maximum pending inventory re-emits field-for-field including equipment, skills, personal and faction data")

-- One item over the configured limit is quarantined as untouched raw data. It
-- may be saved as passthrough, but it is never truncated to the valid maximum.
check(SC.Persistence.reset() == true, "maximum-boundary state resets cleanly")
local overflowRecord = record("sc-overflow-pending")
local overflowRoots = {}
for index = 1, maximumItems + 1 do
    overflowRoots[index] = {
        id = "overflow-" .. tostring(index), type = "Base.Overflow",
        children = {}, weaponParts = {},
    }
end
overflowRecord.inventory = {
    schema = 2, complete = true, count = maximumItems + 1,
    roots = overflowRoots, legacy = false,
    equipment = { worn = {}, attached = {} },
}
local overflowDocument = {
    schema = SC.Identity.saveSchema,
    companions = { ["sc-overflow-pending"] = overflowRecord }, factionActors = {},
}
local overflowPlayer = playerFor(overflowDocument)
check(SC.Persistence.restore(overflowPlayer) == true
        and not SC.Persistence.isPending("sc-overflow-pending")
        and SC.Persistence.quarantineSnapshot().companions["sc-overflow-pending"] ~= nil,
    "one-over inventory is rejected from gameplay state")
local overflowSaved, overflowOutgoing = SC.Persistence.save(overflowPlayer)
check(overflowSaved == true
        and overflowOutgoing.companions["sc-overflow-pending"].inventory.count
            == maximumItems + 1
        and #overflowOutgoing.companions["sc-overflow-pending"].inventory.roots
            == maximumItems + 1
        and deepEqual(overflowOutgoing.companions["sc-overflow-pending"], overflowRecord),
    "one-over failure preserves the complete prior record instead of truncating it")

print("PERSISTENCE_TRANSACTION_KAHLUA_PASS checks=" .. tostring(checks))
