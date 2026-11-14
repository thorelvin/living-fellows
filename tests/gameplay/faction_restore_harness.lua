-- SPDX-License-Identifier: MIT
-- Distinct subject regressions retained from the former gameplay monolith.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog, squareKey = f.makeSquare, f.squares, f.movementLog, f.squareKey
function SurvivorCompanion.__testFactionRestoreTransactions()
local Factions = SurvivorCompanion.Factions
local World = SurvivorCompanion.FactionWorld
local Actor = SurvivorCompanion.Actor
-- Earlier gameplay cases leave a marked store on this shared test square.
-- The transaction fixture needs a genuinely clear tile for its spawn ticket.
local fixtureSquare = cell:getGridSquare(2, 2, 0)
local fixtureObjects, fixtureSpecialObjects =
    fixtureSquare.objects, fixtureSquare.specialObjects
fixtureSquare.objects, fixtureSquare.specialObjects = {}, {}
local baseline = {
    schema = 1, sequence = 7, lastWorldSpawnDay = 3, lastProductionCheckDay = 4,
    order = { "faction-transaction-a" },
    groups = {
        ["faction-transaction-a"] = {
            id = "faction-transaction-a", archetype = "barricaded_household",
            name = "Transaction household A", lifecycle = "settled",
            standing = "Tolerated", reputation = 5, discovered = true,
            barterUnlocked = false, permanentHostility = false,
            shortageKind = "food",
            house = {
                id = "1:1:4:4", bounds = { x1 = 1, y1 = 1, x2 = 4, y2 = 4, z = 0 },
                anchor = { x = 2, y = 2, z = 0 },
                interior = { { x = 2, y = 2, z = 0 } }, openings = {},
            },
            members = { { key = "member-a", role = "leader", identity = {
                forename = "Ada", surname = "Test", gender = "female",
            }, alive = true, hibernated = false } },
            jobs = {}, offenses = {}, history = {},
            request = { kind = "food", status = "available", rewardReserved = true,
                required = { { category = "food", count = 1 } }, reward = {} },
        },
    },
}

local function candidateDocument()
    local candidate = SurvivorCompanion.StableValue.copyStrict(baseline, {
        maxDepth = 16, maxEntries = 131072, path = "$.transactionCandidate",
    })
    local second = SurvivorCompanion.StableValue.copyStrict(
        baseline.groups["faction-transaction-a"], {
            maxDepth = 16, maxEntries = 131072, path = "$.transactionGroup",
        })
    second.id, second.name = "faction-transaction-b", "Transaction household B"
    second.house.id = "5:1:8:4"
    second.house.anchor = { x = 6, y = 2, z = 0 }
    second.house.bounds = { x1 = 5, y1 = 1, x2 = 8, y2 = 4, z = 0 }
    second.house.interior = { { x = 6, y = 2, z = 0 } }
    second.members[1].key = "member-b"
    candidate.sequence = 99
    candidate.order[2] = second.id
    candidate.groups[second.id] = second
    return candidate
end

local function relationCount(document)
    local amount = 0
    for _ in pairs(document and document.relations or {}) do amount = amount + 1 end
    return amount
end

local function sameWorldState(left, right)
    return relationCount(left) == relationCount(right)
        and left.serial == right.serial and left.version == right.version
        and left.nextEventHour == right.nextEventHour
        and #(left.news or {}) == #(right.news or {})
end

Factions.reset()
check(Factions.restore(baseline), "transaction fixture restores its baseline household")
World.reset()
check(World.reconcile(), "transaction fixture starts with a reconciled world graph")
World.pulse(10)

do
    local beforeFaction, beforeWorld = Factions.export(), World.export()
    local originalReconcile = World.reconcile
    World.reconcile = function()
        originalReconcile()
        error("forced reconcile exception after mutation")
    end
    local accepted, reason = Factions.restore(candidateDocument())
    World.reconcile = originalReconcile
    local afterFaction, afterWorld = Factions.export(), World.export()
    check(not accepted
        and string.find(tostring(reason), "forced reconcile exception", 1, true) ~= nil
        and #afterFaction.order == 1 and afterFaction.order[1] == beforeFaction.order[1]
        and afterFaction.sequence == beforeFaction.sequence
        and Factions.group("faction-transaction-b") == nil
        and sameWorldState(afterWorld, beforeWorld),
        "a reconcile exception rolls back faction globals and world mutations")
end

do
    local beforeWorld = World.export()
    local originalReconcile = World.reconcile
    World.reconcile = function()
        originalReconcile()
        return false, "forced reconcile rejection after mutation"
    end
    local accepted, reason = Factions.restore(candidateDocument())
    World.reconcile = originalReconcile
    local afterWorld = World.export()
    check(not accepted
        and string.find(tostring(reason), "forced reconcile rejection", 1, true) ~= nil
        and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-b") == nil
        and sameWorldState(afterWorld, beforeWorld),
        "a reconcile false result is a transactional failure, not a partial restore")
end

do
    local beforeWorld = World.export()
    local replacement = SurvivorCompanion.StableValue.copyStrict(beforeWorld, {
        maxDepth = 8, maxEntries = 8192, path = "$.worldReplacement",
    })
    replacement.serial, replacement.version = 41, 73
    replacement.nextEventHour = 999
    local originalReconcile = World.reconcile
    World.reconcile = function() return false, "forced world restore rejection" end
    local accepted, reason = World.restore(replacement)
    World.reconcile = originalReconcile
    check(not accepted and reason == "forced world restore rejection"
        and sameWorldState(World.export(), beforeWorld),
        "faction-world restore rolls back when reconciliation returns false")
end

do
    local originalBegin = Actor.beginSpawn
    local originalPoll = Actor.pollSpawn
    local originalCancel = Actor.cancelSpawn
    local activeTicket = { id = "faction-transaction-ticket" }
    local beginCalls, pollCalls, cancelCalls = 0, 0, 0
    Actor.beginSpawn = function()
        beginCalls = beginCalls + 1
        return activeTicket, "spawn_pending"
    end
    Actor.pollSpawn = function(ticket)
        if ticket == activeTicket then pollCalls = pollCalls + 1 end
        return nil, "spawn_pending"
    end
    Actor.cancelSpawn = function(ticket)
        if ticket == activeTicket then cancelCalls = cancelCalls + 1 end
        return false, "forced cancellation rejection"
    end
    Factions._nextProductionAt = math.huge
    Factions.pulse(player, f.clock)
    Factions.pulse(player, f.clock + 1)
    check(beginCalls == 1 and Factions.group("faction-transaction-a").members[1].spawnQueued == true,
        "transaction fixture owns one active faction spawn before restore")

    local beforeWorld = World.export()
    local cleared, clearReason = Factions.restore(nil)
    check(not cleared
        and string.find(tostring(clearReason), "forced cancellation rejection", 1, true) ~= nil
        and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-a").members[1].spawnQueued == true,
        "nil faction restore preserves live state when spawn cancellation fails")

    local accepted, reason = Factions.restore(candidateDocument())
    local afterWorld = World.export()
    check(not accepted
        and string.find(tostring(reason), "forced cancellation rejection", 1, true) ~= nil
        and cancelCalls == 2 and Factions.group("faction-transaction-a") ~= nil
        and Factions.group("faction-transaction-b") == nil
        and Factions.group("faction-transaction-a").members[1].spawnQueued == true
        and sameWorldState(afterWorld, beforeWorld),
        "late spawn cancellation failure rolls back candidate groups, queue state and world relations")
    Factions.pulse(player, f.clock + 2)
    check(pollCalls == 1 and beginCalls == 1,
        "the original active spawn ticket remains owned after restore rollback")

    Actor.cancelSpawn = function(ticket)
        if ticket == activeTicket then cancelCalls = cancelCalls + 1 end
        return true
    end
    check(Factions.restore(baseline) and cancelCalls == 3,
        "a verified cancellation commits the replacement and clears transient spawn work")
    Actor.beginSpawn, Actor.pollSpawn, Actor.cancelSpawn = originalBegin, originalPoll, originalCancel
end

-- A resident's distance-based wake must restore the same snapshot as a save
-- load before publishing the new native actor, or it wakes naked and empty.
do
    local SC = SurvivorCompanion
    local originalPersistence, originalBegin, originalPoll = SC.Persistence, Actor.beginSpawn, Actor.pollSpawn
    local clockBefore = f.clock
    check(Factions.restore(baseline), "wake fixture restores one household")
    local group = Factions.group("faction-transaction-a")
    local member = group.members[1]
    local saved = { id = "resident-wake-test", identity = member.identity,
        inventory = { receipt = "outfit-and-kit" }, vitals = { health = 83 } }
    member.actorId, member.hibernated, member.snapshot = saved.id, true, saved
    local initialized, finished, reject = 0, 0, true
    SC.Persistence = {
        initializeRestoredActor = function(native, input, snapshot)
            initialized = initialized + 1
            assert(snapshot == saved and input.factionId == group.id)
            if reject then return false, "saved_clothing_restore_failed" end
            native.savedInventory, native.savedVitals = snapshot.inventory, snapshot.vitals
            return true
        end,
        finishRestoredActor = function(native, snapshot)
            assert(registry[saved.id].actor == native and snapshot == saved)
            finished = finished + 1
        end,
    }
    Actor.beginSpawn = function(square, profile)
        local native = actor(saved.id, square.x, square.y, { recruited = false })
        assert(profile.restored == true and profile.state == saved)
        local accepted, reason = profile.initialize(native, {})
        if not accepted then return nil, reason end
        return { native = native }
    end
    Actor.pollSpawn = function(ticket)
        registry[saved.id] = { actor = ticket.native, id = saved.id, runtime = {} }
        return ticket.native
    end
    for _ = 1, 8 do f.clock = f.clock + 1000; Factions.pulse(player, f.clock) end
    check(initialized > 0 and registry[saved.id] == nil and finished == 0
            and member.hibernated == true and member.snapshot == saved,
        "failed clothing restoration retains the snapshot without publishing a bare actor")
    reject, f.clock = false, f.clock + 31000
    for _ = 1, 8 do f.clock = f.clock + 1000; Factions.pulse(player, f.clock) end
    local restored = registry[saved.id] and registry[saved.id].actor
    check(restored and restored.savedInventory == saved.inventory and restored.savedVitals == saved.vitals
            and finished == 1 and member.hibernated == false and member.snapshot == nil,
        "a successful wake restores outfit, kit and vitals once before consuming its snapshot")
    Factions.reset()
    registry[saved.id] = nil
    SC.Persistence, Actor.beginSpawn, Actor.pollSpawn, f.clock =
        originalPersistence, originalBegin, originalPoll, clockBefore
end

Factions.reset()
fixtureSquare.objects, fixtureSquare.specialObjects =
    fixtureObjects, fixtureSpecialObjects
end
SurvivorCompanion.__testFactionRestoreTransactions()
SurvivorCompanion.__testFactionRestoreTransactions = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
