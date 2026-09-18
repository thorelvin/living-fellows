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
    local data = SC_TEST_SET_WORLD_STORE({ document = document })
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

do
    local markerData = { LF_ProductionOrderId = "production-order:before" }
    local item = { getModData = function() return markerData end }
    local items = {
        size = function() return 1 end,
        get = function(_, index) return index == 0 and item or nil end,
    }
    local inventory = { getItems = function() return items end }
    local actor = { getInventory = function() return inventory end }
    local before = SC.Persistence._inventoryIdentitySequenceForTests(actor)
    markerData.LF_ProductionOrderId = "production-order:after"
    local after = SC.Persistence._inventoryIdentitySequenceForTests(actor)
    local changed = type(before) == "table" and type(after) == "table" and #before == #after
    if changed then
        changed = false
        for index = 1, #before do
            if before[index] ~= after[index] then changed = true break end
        end
    end
    check(changed, "production cargo marker mutation changes the final inventory identity proof")
end

do
    -- A save written before companions were seeded with the vanilla passive
    -- baseline carries Strength/Fitness 0. Spawn now applies 5 before restore
    -- runs, so replaying the record verbatim would push the actor back below
    -- character creation and leave it unable to climb anything. Earned progress
    -- above the seeded level must still restore exactly.
    local priorPerkFactory = PerkFactory
    PerkFactory = { getPerkFromName = function(name) return name end }
    local applied = {}
    local xp = {
        setXPToLevel = function(_, perk, level) applied[perk] = level return true end,
        getXP = function() return 0 end,
    }
    local seeded = { Strength = 5, Fitness = 5, Axe = 0 }
    local actor = {
        getXp = function() return xp end,
        getPerkLevel = function(_, perk) return seeded[perk] or 0 end,
    }
    local ok = SC.Persistence._applySkillsForTests(actor, {
        { id = "Strength", level = 0 },
        { id = "Fitness", level = 3 },
        { id = "Axe", level = 4 },
    })
    check(ok == true and applied.Strength == 5 and applied.Fitness == 5
            and applied.Axe == 4,
        "restore never lowers a passive perk below the level spawn seeded")

    applied, seeded = {}, { Strength = 5, Fitness = 5 }
    check(SC.Persistence._applySkillsForTests(actor, {
            { id = "Strength", level = 8 },
        }) == true and applied.Strength == 8,
        "earned progress above the passive baseline restores unchanged")
    PerkFactory = priorPerkFactory
end

-- A scheduled capture yields between items, so a companion can drop an item
-- mid-walk. The shrunken list reads as churn, never as an out-of-range get()
-- (a Java IndexOutOfBoundsException with a stack trace in the game log).
do
    local shrunk, requested = false, {}
    local first = { getModData = function() shrunk = true return {} end }
    local second = { getModData = function() return {} end }
    local items = {
        size = function() return shrunk and 1 or 2 end,
        get = function(_, index)
            requested[#requested + 1] = index
            if index >= (shrunk and 1 or 2) then error("IndexOutOfBoundsException") end
            return index == 0 and first or second
        end,
    }
    local inventory = { getItems = function() return items end }
    local actor = { getInventory = function() return inventory end }
    local identity, reason = SC.Persistence._inventoryIdentitySequenceForTests(actor)
    local outOfRange = false
    for _, index in ipairs(requested) do
        if index >= 1 then outOfRange = true end
    end
    check(identity == nil and reason == "inventory_changed" and not outOfRange,
        "an inventory that shrinks during the identity walk reads as churn without an out-of-range get: "
            .. tostring(reason))
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
        and mixedData.document.companions[7].marker == mixedRaw.marker,
    "invalid numeric-key data is re-emitted without truncation")

check(SC.Persistence.reset() == true, "saw receipt persistence starts cleanly")
local sawRecord = record("sc-saw-recovery")
sawRecord.productionAction = {
    kind = "saw_logs", orderId = "production-order:7", logKey = "native:41",
    beforeCount = 2, startedAt = 12345,
}
local sawDocument = {
    schema = SC.Identity.saveSchema,
    companions = { [sawRecord.id] = sawRecord }, factionActors = {},
}
local sawPlayer = playerFor(sawDocument)
check(SC.Persistence.restore(sawPlayer) == true
        and SC.Persistence.isPending(sawRecord.id),
    "a completed-before-poll saw receipt survives document validation")
local sawSaved, sawOutgoing = SC.Persistence.save(sawPlayer)
check(sawSaved == true
        and sawOutgoing.companions[sawRecord.id].productionAction.orderId
            == "production-order:7",
    "an unresolved saw receipt is re-emitted for later output reconciliation")

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
check(malformedSaved == false and malformedData.document == malformedDocument
        and malformedData.document.community.sentinel == "untouched",
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

-- tradeRecovery is a first-class quarantined subsystem and must use the same
-- disposable retry boundary as the other subsystem documents.
check(SC.Persistence.reset() == true, "community retry state resets before trade recovery")
local priorTrade = SC.Trade
local tradeRetryMode = "reject"
local tradeRaw = { queue = { { id = "recovery-1", phase = "rollback" } } }
SC.Trade = {
    restore = function(input)
        input.queue[1].phase = "mutated-disposable-copy"
        if tradeRetryMode == "reject" then
            return false, "injected trade recovery rejection"
        end
        return true
    end,
    export = function() return {} end,
}
local tradeDocument = {
    schema = SC.Identity.saveSchema, companions = {}, factionActors = {},
    tradeRecovery = tradeRaw,
}
local tradePlayer = playerFor(tradeDocument)
check(SC.Persistence.restore(tradePlayer) == true
        and SC.Persistence.quarantineSnapshot().subsystems.tradeRecovery ~= nil
        and tradeRaw.queue[1].phase == "rollback",
    "rejected trade recovery restore keeps untouched raw quarantine")
tradeRetryMode = "success"
check(SC.Persistence.retrySubsystem("tradeRecovery") == true
        and SC.Persistence.quarantineSnapshot().subsystems.tradeRecovery == nil,
    "manual trade recovery retry resolves through its canonical owner")
SC.Trade = priorTrade

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

-- Periodic saves stage a complete document without exposing intermediate
-- subsystem/actor copies. A deliberately advancing sub-millisecond clock makes
-- the 0.75 ms slices observable in the headless VM.
check(SC.Persistence.reset() == true, "scheduled-save test starts cleanly")
local stagedStore = SC_TEST_SET_WORLD_STORE({ document = { sentinel = "prior-complete" } })
local stagedPlayer = { getModData = function() return {} end }
local priorTimestamp = getTimestampMs
local stagedClock = 2000
getTimestampMs = function()
    stagedClock = stagedClock + 0.2
    return stagedClock
end
local requested, requestReason = SC.Persistence.requestScheduledSave(stagedPlayer)
check(requested == true and requestReason == "requested"
        and stagedStore.document.sentinel == "prior-complete",
    "scheduled save request leaves the prior atomic document assigned")
local stagedStatus, stagedOutgoing
local stagedYielded = false
for _ = 1, 10000 do
    stagedStatus, stagedOutgoing = SC.Persistence.pulse()
    if stagedStatus == "yielded" then
        stagedYielded = true
        check(stagedStore.document.sentinel == "prior-complete",
            "yielded save pulse never publishes partial staging")
    else break end
end
check(stagedYielded and stagedStatus == "complete"
        and type(stagedOutgoing) == "table"
        and stagedStore.document == stagedOutgoing
        and stagedStore.document.sentinel == nil,
    "scheduled save completes through bounded pulses and commits once")

-- Work receipts and marked actor cargo are one persistence consistency unit.
-- A ledger mutation after baseLife export must reject publication even when
-- registry and inventory object identities would otherwise remain stable.
check(SC.Persistence.reset() == true,
    "work-ledger barrier test resets scheduled persistence")
local realBaseLife = SC.BaseLife
local workRevision, workExports = 41, 0
local largeWorkExport = { work = { receipts = {}, orders = {} }, payload = {} }
for index = 1, 1024 do largeWorkExport.payload[index] = index end
SC.BaseLife = {
    export = function()
        workExports = workExports + 1
        return largeWorkExport
    end,
    workConsistencyRevision = function() return workRevision end,
}
local workPrior = { sentinel = "prior-work-consistent" }
local workStore = SC_TEST_SET_WORLD_STORE({ document = workPrior })
local workRequested = SC.Persistence.requestScheduledSave(stagedPlayer)
local workStatus, workReason, revisionChanged = nil, nil, false
for _ = 1, 10000 do
    workStatus, workReason = SC.Persistence.pulse()
    if workExports > 0 and not revisionChanged then
        workRevision, revisionChanged = workRevision + 1, true
    end
    if workStatus ~= "yielded" then break end
end
check(workRequested == true and revisionChanged and workStatus == "failed"
        and string.find(tostring(workReason), "gather work ownership changed", 1, true)
        and workStore.document == workPrior,
    "cross-slice receipt/marker mutation preserves the prior complete document")

check(SC.Persistence.reset() == true,
    "unchanged work-ledger control resets scheduled persistence")
workExports = 0
local stableWorkStore = SC_TEST_SET_WORLD_STORE({ document = { sentinel = "stable-work" } })
local stableWorkRequested = SC.Persistence.requestScheduledSave(stagedPlayer)
local stableWorkStatus, stableWorkOutgoing
for _ = 1, 10000 do
    stableWorkStatus, stableWorkOutgoing = SC.Persistence.pulse()
    if stableWorkStatus ~= "yielded" then break end
end
check(stableWorkRequested == true and workExports > 0
        and stableWorkStatus == "complete"
        and stableWorkStore.document == stableWorkOutgoing,
    "unchanged work-ledger revision still permits one atomic scheduled commit")
SC.BaseLife = realBaseLife

check(SC.Persistence.requestScheduledSave(stagedPlayer) == true,
    "a second scheduled save can enter staging")
local synchronous, synchronousDocument = SC.Persistence.save(stagedPlayer)
check(synchronous == true and type(synchronousDocument) == "table"
        and SC.Persistence.pulse() == "idle",
    "synchronous OnSave-style capture cancels staging and commits a fresh document")
getTimestampMs = priorTimestamp

print("PERSISTENCE_TRANSACTION_KAHLUA_PASS checks=" .. tostring(checks))
