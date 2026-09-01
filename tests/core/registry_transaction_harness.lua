-- SPDX-License-Identifier: MIT

local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local SC = SurvivorCompanion
SC.Actor = SC.Actor or {}
SC.Actor._isRegistryActor = function(actor)
    return type(actor) == "table" and actor.__owned == true
end

local function actorWith(data)
    local actor = { __owned = true, data = data or {} }
    function actor:getModData() return self.data end
    function actor:isDead() return false end
    return actor
end

local commitBoundaries = {
    { target = "modData", key = "SC_Id" },
    { target = "modData", key = "SC_FactionId" },
    { target = "modData", key = "SC_FactionRole" },
    { target = "recordsById" },
    { target = "idsByActor" },
}

for index, boundary in ipairs(commitBoundaries) do
    local data = { SC_FactionId = "old-faction", SC_FactionRole = "old-role" }
    local candidate = actorWith(data)
    local id = "sc-fault-" .. tostring(index)
    local injected = false
    SC.Registry._setAssignmentFaultForTests(function(phase, target, key)
        if not injected and phase == "commit" and target == boundary.target
            and (boundary.key == nil or key == boundary.key) then
            injected = true
            return false, "commit boundary " .. target
        end
        return true
    end)
    local record, reason = SC.Registry.register(candidate, {
        id = id, recruited = true, factionId = "new-faction", factionRole = "new-role",
    })
    SC.Registry._setAssignmentFaultForTests(nil)
    check(injected and record == nil
            and string.find(tostring(reason), "registry commit failed", 1, true) ~= nil,
        "commit assignment boundary is executable: " .. boundary.target
            .. "." .. tostring(boundary.key or "map"))
    check(data.SC_Id == nil and data.SC_FactionId == "old-faction"
            and data.SC_FactionRole == "old-role"
            and SC.Registry.byId(id) == nil and SC.Registry.idOf(candidate) == nil
            and SC.Registry.quarantineOf(candidate) == nil,
        "successful rollback restores all publications at boundary " .. tostring(index))
end

for index, boundary in ipairs(commitBoundaries) do
    local data = { SC_FactionId = "old-faction", SC_FactionRole = "old-role" }
    local candidate = actorWith(data)
    local id = "sc-silent-" .. tostring(index)
    local injected = false
    SC.Registry._setAssignmentFaultForTests(function(phase, target, key)
        if not injected and phase == "commit" and target == boundary.target
            and (boundary.key == nil or key == boundary.key) then
            injected = true
            return "silent_reject"
        end
        return true
    end)
    local record, reason = SC.Registry.register(candidate, {
        id = id, recruited = true, factionId = "new-faction", factionRole = "new-role",
    })
    SC.Registry._setAssignmentFaultForTests(nil)
    check(injected and record == nil
            and string.find(tostring(reason), "assignment did not persist", 1, true) ~= nil,
        "read-back rejects a silently discarded write at " .. boundary.target
            .. "." .. tostring(boundary.key or "map"))
    check(data.SC_Id == nil and data.SC_FactionId == "old-faction"
            and data.SC_FactionRole == "old-role"
            and SC.Registry.byId(id) == nil and SC.Registry.idOf(candidate) == nil
            and SC.Registry.quarantineOf(candidate) == nil,
        "silent write rejection rolls every publication back at boundary "
            .. tostring(index))
end

do
    local candidate = actorWith({ SC_FactionId = "old-faction", SC_FactionRole = "old-role" })
    local rollbackVisits = {}
    SC.Registry._setAssignmentFaultForTests(function(phase, target, key)
        if phase == "commit" and target == "idsByActor" then
            return false, "force late commit failure"
        end
        if phase == "rollback" then
            rollbackVisits[target] = (rollbackVisits[target] or 0) + 1
            rollbackVisits[target .. "." .. tostring(key)] = true
            if target == "recordsById" then
                return false, "force rollback failure"
            end
        end
        return true
    end)
    local record, reason = SC.Registry.register(candidate, {
        id = "sc-quarantine", recruited = true,
        factionId = "new-faction", factionRole = "new-role",
    })
    SC.Registry._setAssignmentFaultForTests(nil)
    local quarantine = SC.Registry.quarantineOf(candidate)
    local partial = SC.Registry.byId("sc-quarantine")
    check(record == nil and string.find(tostring(reason), "registry rollback failed", 1, true)
            and quarantine ~= nil and quarantine.inactive == true
            and candidate.data.SC_RegistryQuarantined == true
            and type(candidate.data.SC_RegistryQuarantineReason) == "string",
        "rollback failure explicitly quarantines and marks the actor")
    check(rollbackVisits.recordsById == 1 and rollbackVisits.idsByActor == 1
            and rollbackVisits["modData.SC_Id"]
            and rollbackVisits["modData.SC_FactionId"]
            and rollbackVisits["modData.SC_FactionRole"],
        "rollback attempts both maps and every mod-data identity field after one failure")
    check(partial ~= nil and partial.runtime.inactive == true
            and partial.runtime.registryQuarantined == true
            and SC.Registry.isActive(candidate, "sc-quarantine") == false
            and #SC.Registry.living() == 0,
        "partial publication remains observable but cannot become active work")
    local retried, retryReason = SC.Registry.register(candidate, { id = "sc-quarantine" })
    check(retried == nil and string.find(tostring(retryReason), "quarantined", 1, true),
        "quarantined actor cannot be silently republished")
    SC.Registry.reset()
end

do
    local originalGet = SC.Config.get
    SC.Config.get = function(...)
        local arguments = { ... }
        if arguments[1] == "orders" and arguments[2] == "defaultScavenge" then
            return false
        end
        return originalGet(...)
    end
    local candidate = actorWith()
    local record = SC.Registry.register(candidate, {
        id = "sc-default-false", recruited = true,
    })
    SC.Config.get = originalGet
    check(record ~= nil and record.scavenge == false
            and record.state.order.scavenge == false,
        "configured defaultScavenge=false survives registry defaulting")
    SC.Registry.unregister(candidate)
end

do
    local source = {
        identity = { name = "Owned", nested = { rank = 2 } },
        state = {
            order = {
                current = "invalid", followDistance = math.huge,
                movementMode = "invalid", movementModeVersion = math.huge,
                combatStance = "invalid", combatDoctrine = "invalid",
                weaponPriority = "invalid", workMode = "build",
                workTarget = {
                    x = 2000000, y = -2000000, z = 999,
                    objectIndex = -5, initialPlanks = 20000,
                    kind = "invalid", baseJobId = string.rep("j", 80),
                },
                returnOrder = "invalid", returnWorkMode = "invalid",
            },
            group = string.rep("g", 80),
            personality = {
                archetype = string.rep("a", 60),
                profile = { traits = { patient = true } },
                trust = -1, bond = 200, morale = 0 / 0, stress = math.huge,
                memories = { { text = "original" } },
                background = { occupation = "carpenter" },
                care = { wounds = {} }, reveals = { secret = false },
                timeTogetherMs = -5, lastEncouragedAt = math.huge,
            },
            objectives = { { kind = "survive" } },
            possessions = { token = { type = "Base.Key" } },
            downtime = { lastCompleted = string.rep("d", 80), facts = { repaired = 1 } },
        },
    }
    local candidate = actorWith()
    local record = SC.Registry.register(candidate, {
        id = "sc-normalized", recruited = true,
        identity = source.identity, state = source.state,
    })
    check(record ~= nil and record.order == "follow" and record.followDistance == 3
            and record.moveMode == "copy" and record.state.order.movementModeVersion == 0
            and record.combatMode == "defensive"
            and record.combatDoctrine == "close_defense"
            and record.weaponPriority == "best" and record.workMode == "build"
            and record.returnOrder == nil and record.returnWorkMode == nil,
        "invalid enums and finite-only command scalars normalize to canonical domains")
    check(record.workTarget.x == 1000000 and record.workTarget.y == -1000000
            and record.workTarget.z == 128 and record.workTarget.objectIndex == 0
            and record.workTarget.initialPlanks == 10000
            and record.workTarget.kind == "barricade"
            and #record.workTarget.baseJobId == 64,
        "work-target numeric and text boundaries clamp deterministically")
    check(record.trust == 0 and record.bond == 100 and record.morale == 55
            and record.stress == 12 and record.timeTogetherMs == 0
            and record.state.personality.lastEncouragedAt == 0
            and #record.group == 64 and #record.personality == 48
            and #record.lastDowntime == 64,
        "personality and persisted scalar boundaries reject non-finite values and clamp ranges")

    source.identity.nested.rank = 99
    source.state.personality.profile.traits.patient = false
    source.state.personality.memories[1].text = "source-mutated"
    source.state.objectives[1].kind = "source-mutated"
    source.state.possessions.token.type = "source-mutated"
    source.state.downtime.facts.repaired = 99
    source.state.order.workTarget.x = 1
    check(record.identity.nested.rank == 2
            and record.personalityProfile.traits.patient == true
            and record.memories[1].text == "original"
            and record.objectives[1].kind == "survive"
            and record.possessions.token.type == "Base.Key"
            and record.state.downtime.facts.repaired == 1
            and record.workTarget.x == 1000000,
        "committed registry state owns every mutable source input")

    record.identity.nested.rank = 7
    record.personalityProfile.traits.patient = "record-mutated"
    record.memories[1].text = "record-mutated"
    record.objectives[1].kind = "record-mutated"
    record.possessions.token.type = "record-mutated"
    record.state.downtime.facts.repaired = 7
    record.workTarget.x = 7
    check(source.identity.nested.rank == 99
            and source.state.personality.profile.traits.patient == false
            and source.state.personality.memories[1].text == "source-mutated"
            and source.state.objectives[1].kind == "source-mutated"
            and source.state.possessions.token.type == "source-mutated"
            and source.state.downtime.facts.repaired == 99
            and source.state.order.workTarget.x == 1,
        "registry mutations cannot write back into source-owned tables")
    SC.Registry.unregister(candidate)
end

SC.Registry.reset()
print("REGISTRY_TRANSACTION_KAHLUA_PASS checks=" .. tostring(checks))
