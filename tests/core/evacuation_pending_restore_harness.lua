-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local P = SC.Persistence
local crewId, otherId = "oddball-evacuation-fixture", "oddball-neighbor-fixture"
local joy, brock, neighbor, playerCompanion = "sc-test-joy", "sc-test-brock", "sc-test-neighbor", "sc-player-friend"
local groups = {
    [crewId] = { members = { { actorId = joy }, { actorId = brock } } },
    [otherId] = { members = { { actorId = neighbor } } },
}
SC.Factions = {
    group = function(id) return groups[id] end,
    restore = function() return true end,
    export = function() return {} end,
}

local function snapshot(id, faction, x)
    return {
        id = id, factionId = faction, recruited = faction == nil,
        identity = { forename = "Resident", surname = "Test", gender = "female", outfit = "" },
        position = { x = x, y = 10, z = 0 },
        inventory = { schema = 2, complete = true, count = 0, roots = {}, legacy = false,
            equipment = { worn = {}, attached = {} } },
        vitals = {}, order = { mode = "follow" },
    }
end
local document = {
    schema = SC.Identity.saveSchema,
    factionActors = {
        [joy] = snapshot(joy, crewId, 1000),
        [brock] = snapshot(brock, crewId, 30),
        [neighbor] = snapshot(neighbor, otherId, 40),
    },
    companions = { [playerCompanion] = snapshot(playerCompanion, nil, 50) },
}
local square = { getX = function() return 30 end, getY = function() return 10 end,
    getZ = function() return 0 end }
function getCell()
    return { getGridSquare = function(_, x, y, z)
        if x == 30 and y == 10 and z == 0 then return square end
    end }
end

local ticket, cancelReady, cancelCalls = {}, false, 0
SC.Actor = {
    beginSpawn = function(at, profile)
        assert(at == square and profile.id == brock, "only Brock has a loaded native post")
        return ticket
    end,
    pollSpawn = function(value)
        assert(value == ticket, "only the exact admitted ticket is polled")
        return nil, "spawn_pending"
    end,
    cancelSpawn = function(value)
        assert(value == ticket, "only the exact owned ticket may be cancelled")
        cancelCalls = cancelCalls + 1
        return cancelReady, "native_cancel_pending"
    end,
}
local store = SC_TEST_SET_WORLD_STORE({ document = document })
assert(P.restore({}))
P.restorePulse({})
assert(P.pendingRestoreStatus(joy) == "waiting_environment"
    and P.pendingRestoreStatus(brock) == "spawn_pending", "cold restart retains offscreen and in-flight crew")
assert(not P.retirePendingFactionActor(neighbor, crewId) and P.isPending(neighbor),
    "a different household's pending actor is preserved")
groups[crewId].members[3] = { actorId = playerCompanion }
assert(not P.retirePendingFactionActor(playerCompanion, crewId) and P.isPending(playerCompanion),
    "faction membership alone cannot retire a recruited snapshot")
groups[crewId].members[3] = { actorId = neighbor }
assert(not P.retirePendingFactionActor(neighbor, crewId) and P.isPending(neighbor),
    "a snapshot with a different faction ID is preserved even when the member row claims it")
groups[crewId].members[3] = nil

local byId = SC.Registry.byId
SC.Registry.byId = function(id) if id == joy then return { id = id } end return byId(id) end
assert(not P.retirePendingFactionActor(joy, crewId) and P.isPending(joy),
    "a live registry owner blocks retirement")
SC.Registry.byId = byId
SC.Vehicle = { contains = function(id) return id == joy end }
assert(not P.retirePendingFactionActor(joy, crewId) and P.isPending(joy),
    "a live vehicle-storage owner blocks retirement")
SC.Vehicle = nil

local previousClock = getTimestampMs
getTimestampMs = function()
    SC_TEST_CLOCK = SC_TEST_CLOCK + 1
    return SC_TEST_CLOCK
end
local requested, _, staged = P.requestScheduledSave({})
assert(requested and staged)
for _ = 1, 400 do
    if staged.document.factionActors[joy] then break end
    assert(P.pulse() == "yielded")
end
getTimestampMs = previousClock
assert(staged.document.factionActors[joy] ~= nil, "the staged save has already copied Joy")
assert(P.retirePendingFactionActor(joy, crewId) and not P.isPending(joy)
    and P._scheduledSaveForTests() == nil and store.document.factionActors[joy] ~= nil,
    "an exact unloaded actor drops from pending and staged saves, preserving the durable checkpoint")
assert(P.retirePendingFactionActor(joy, crewId), "checked absence is idempotent")
assert(not P.retirePendingFactionActor(brock, crewId) and P.pendingRestoreStatus(brock) == "spawn_pending"
    and cancelCalls == 1, "an unconfirmed cancellation preserves the pending ticket and snapshot")
cancelReady = true
assert(P.retirePendingFactionActor(brock, crewId) and not P.isPending(brock) and cancelCalls == 2,
    "verified native cancellation releases only the owned faction actor")

assert(P.save({}) and store.document.factionActors[joy] == nil and store.document.factionActors[brock] == nil
    and store.document.factionActors[neighbor] ~= nil and store.document.companions[playerCompanion] ~= nil,
    "the next save removes only the retired crew snapshots")
assert(P.restore({}) and P.pendingCount() == 2 and P.isPending(neighbor) and P.isPending(playerCompanion)
    and not P.isPending(joy) and not P.isPending(brock), "a second cold restore cannot recreate the retired crew")
