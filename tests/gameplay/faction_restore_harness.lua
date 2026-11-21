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
    local native = actor(saved.id, 2, 2, { recruited = false })
    member.actorId = saved.id
    registry[saved.id] = { id = saved.id, actor = native, factionId = group.id, runtime = {} }
    local originalRemove, originalCanSee = Actor.remove, SC.GameplayUtil.canSee
    local originalSenses, originalComplete = SC.Senses.snapshot, SC.Senses.isCompleteObservation
    local originalX, originalY = player.worldX, player.worldY
    player.worldX, player.worldY = 1000, 1000
    Actor.remove = function(subject)
        assert(subject == native)
        registry[saved.id] = nil
        return true
    end
    SC.GameplayUtil.canSee = function() return false end
    SC.Senses.snapshot = function() return { valid = true, threatCount = 0 } end
    SC.Senses.isCompleteObservation = function() return true end
    local initialized, finished, reject = 0, 0, true
    SC.Persistence = {
        captureRecord = function(record)
            assert(record.actor == native)
            return saved
        end,
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
    for _ = 1, 12 do f.clock = f.clock + 3000; Factions.pulse(player, f.clock) end
    check(registry[saved.id] == nil and Factions.retainsActor(saved.id),
        "a distant household holds the sleeping actor's ID across repeated pulses")
    check(not Factions.affiliation({ id = saved.id, actor = native }),
        "a retained snapshot does not give a retired native actor active affiliation")
    check(not Factions.retainsActor("other-resident"), "a household snapshot is specific to one ID")
    local sleeping = assert(Factions.export())
    check(Factions.restore(nil) and not Factions.retainsActor(saved.id),
        "loading a fresh world drops the previous household's sleeping ID")
    check(Factions.restore(sleeping) and Factions.retainsActor(saved.id),
        "loading a sleeping household restores ownership before its actor wakes")
    group = Factions.group("faction-transaction-a")
    member = group.members[1]
    saved = member.snapshot
    local byId = SC.Registry.byId
    SC.Registry.byId = function() error("the faction snapshot lookup must not read the registry") end
    check(Factions.retainsActor(saved.id), "the sleeping identity is independent of the live registry")
    SC.Registry.byId = byId
    local id = saved.id
    saved.id = "other-snapshot"
    check(not Factions.retainsActor(id), "a mismatched saved identity cannot retain a house resident")
    saved.id = id
    member.away = "recruitment_trial"
    check(not Factions.retainsActor(id), "a trial recruit belongs to the party")
    member.away, member.departed = nil, true
    check(not Factions.retainsActor(id), "a departed member leaves faction ownership")
    member.departed, member.alive = nil, false
    check(not Factions.retainsActor(id), "a dead member cannot keep an old snapshot")
    member.alive = true
    group.lifecycle = "destroyed"
    check(not Factions.retainsActor(id), "a retired household cannot reclaim its member")
    group.lifecycle = "settled"
    group.oddball = { id = "hitchhiker_ruth_ann", stage = "gone_inside" }
    check(not Factions.retainsActor(id) and group.oddball.departed == nil,
        "the hitchhiker's permanent exit closes ownership without rewriting the story")
    group.oddball = nil
    player.worldX, player.worldY = 2, 2
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
            and member.hibernated == true and member.snapshot == saved and Factions.retainsActor(saved.id),
        "failed clothing restoration retains the snapshot without publishing a bare actor")
    reject, f.clock = false, f.clock + 31000
    for _ = 1, 8 do f.clock = f.clock + 1000; Factions.pulse(player, f.clock) end
    local restored = registry[saved.id] and registry[saved.id].actor
    check(restored and restored.savedInventory == saved.inventory and restored.savedVitals == saved.vitals
            and finished == 1 and member.hibernated == false and member.snapshot == nil,
        "a successful wake restores outfit, kit and vitals once before consuming its snapshot")
    check(not Factions.retainsActor(saved.id), "a successful wake releases faction snapshot ownership")
    local unaffiliatedRecord = { id = id, actor = restored }
    group.members[2] = { key = "member-b", alive = true, role = "resident" }
    local function currentAffiliation()
        local found = Factions.affiliation(unaffiliatedRecord)
        return found and found.factionId
    end
    check(currentAffiliation() == group.id,
        "a waking member's actor ID still resolves its faction")
    check(Factions.detachMemberForRecruitment(group.id, member.key)
            and not Factions.affiliation(unaffiliatedRecord) and not Factions.retainsActor(id),
        "a public recruitment trial releases faction ownership")
    check(Factions.restoreMemberFromRecruitment(group.id, member.key, id)
            and currentAffiliation() == group.id,
        "a returned recruit regains its faction identity")
    check(Factions.detachMemberForRecruitment(group.id, member.key)
            and Factions.completeMemberRecruitment(group.id, member.key, id)
            and not Factions.affiliation(unaffiliatedRecord) and not Factions.retainsActor(id),
        "a completed recruitment releases the former faction identity")
    check(Factions.restore(sleeping), "restore household for captive release")
    group = Factions.group(group.id)
    group.oddball = { captives = true }
    group.members[1].captive, group.members[1].role = true, "captive"
    registry[id].factionId = group.id
    local releaseCaptive = SC.Commands.releaseFactionCaptive
    SC.Commands.releaseFactionCaptive = function(subject) return subject == restored end
    check(Factions.releaseCaptiveMember(group.id, member.key) and not Factions.retainsActor(id),
        "freeing a captive drops its former household claim")
    SC.Commands.releaseFactionCaptive = releaseCaptive
    check(Factions.restore(sleeping) and Factions.memberDied({ id = saved.id, factionId = group.id })
            and not Factions.retainsActor(saved.id), "final faction death releases the saved ID")
    registry[id] = nil
    check(Factions.restore(sleeping), "restore household for group deletion")
    Factions.group(group.id).debugCreated = true
    local configGet = SC.Config.get
    SC.Config.get = function(key)
        if key == "debugSpawnEnabled" then return true end
        return configGet(key)
    end
    check(Factions.debugDelete(group.id) and not Factions.retainsActor(id),
        "removing a household drops its sleeping actor IDs")
    SC.Config.get = configGet
    check(Factions.restore(sleeping) and Factions.retainsActor(saved.id), "a later world can reuse its own resident ID")
    Factions.reset()
    check(not Factions.retainsActor(saved.id), "world reset drops sleeping faction identities")
    registry[saved.id] = nil
    SC.Senses.snapshot, SC.Senses.isCompleteObservation = originalSenses, originalComplete
    Actor.remove, SC.GameplayUtil.canSee = originalRemove, originalCanSee
    player.worldX, player.worldY = originalX, originalY
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
