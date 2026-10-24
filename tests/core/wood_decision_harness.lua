-- SPDX-License-Identifier: MIT
-- Real decision arbitration must service a mission-owned native chop, and a
-- preparation request must safely release the prior resident controller.
local SC = SurvivorCompanion
local D, checks = SC.Decision, 0
local function check(value, label)
    checks = checks + 1
    assert(value, "wood decision " .. checks .. ": " .. label)
end
check(type(D._evaluateForTests) == "function" and type(D._delegateForTests) == "function",
    "the real decision module is loaded")
local actor = { id = "wood-worker" }
local calm = { threats = {}, immediateAttackers = {}, allies = {}, sounds = {},
    threatCount = 0, immediateCount = 0, closeThreatCount = 0, pressure = 0,
    player = { danger = 0 } }
local danger = { threats = { { actor = {} } }, immediateAttackers = { {} }, allies = {}, sounds = {},
    threatCount = 1, immediateCount = 1, closeThreatCount = 1, pressure = 2,
    player = { danger = 0 } }
local assessment = { alive = true, health = 100, critical = false, downed = false,
    bleedingCount = 0, needsBandage = false }
local commands = { recruited = true, order = "stay", combatMode = "defensive",
    combatDoctrine = "close_defense", scavenge = false, commandSerial = 7 }
local request = { missionId = "wood:test", wood = { request = { mode = "count", quantity = 12 } } }
local preparation, work, delivered = nil, request, nil
local woodCalls, woodSnapshot, baseCancels, nativeCancels = 0, nil, 0, 0
local packingResets, downtimeCancels, interrupts = 0, 0, 0
local packing, baseCanCancel, token, nativePhase = false, true, nil, "none"
SC.GameplayUtil = {
    actorState = function(_, runtime) return runtime end,
    idOf = function(value) return value and value.id end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function() return false end,
    nativeHealth = function() return 100 end,
    nowMs = function() return 1000 end,
    isDue = function() return false end,
    config = function() return nil end,
    call = function(value, method, ...)
        if value and type(value[method]) == "function" then return value[method](value, ...), true end
        return nil, false
    end,
    safeSubsystem = function(_, _, callback, ...) return pcall(callback, ...) end,
    stop = function() return true end,
    distance = function() return 0 end,
    distanceSq = function() return 0 end,
    sameFloor = function() return true end,
    modData = function(item) return item.data end,
    sortByScoreDescending = function(rows)
        table.sort(rows, function(a, b)
            if a.safetyRank ~= b.safetyRank then return a.safetyRank > b.safetyRank end
            return a.score > b.score
        end)
    end,
}
SC.Commands = { effective = function() return commands end }
SC.Medical = { assessCached = function() return assessment end }
SC.ExpeditionPrototype = {
    isMember = function() return false end,
    woodPreparationFor = function() return preparation end,
    woodRequestFor = function() return work end,
    integrationFor = function() return delivered end,
    updateWood = function(value, snapshot)
        check(value == actor, "wood decision services the actual companion")
        woodCalls, woodSnapshot = woodCalls + 1, snapshot
        return true, "wood_chopping"
    end,
}
SC.NativeActions = {
    cancelWork = function()
        nativeCancels = nativeCancels + 1
        return true
    end,
    activityStatus = function() return nativePhase, "work", "chop_tree" end,
    interruptOwnedActivity = function(_, reason)
        check(reason == "survival_priority", "native chopping yields for the real safety reason")
        interrupts, nativePhase = interrupts + 1, "none"
        return true
    end,
}
SC.ActionSupervisor = { current = function() return token end }
SC.BaseWork = { cancel = function()
    baseCancels = baseCancels + 1
    return baseCanCancel, baseCanCancel and "released" or "base_transaction_pending"
end }
SC.Logistics = { busy = function() return packing end,
    reset = function() packingResets, packing = packingResets + 1, false end }
SC.Downtime = { peek = function() return { active = true } end,
    cancel = function() downtimeCancels = downtimeCancels + 1 return true end }

local function candidates(snapshot)
    return D._evaluateForTests(actor, nil, snapshot, commands, assessment, {}, {}, 1000)
end
local function has(rows, kind)
    for _, candidate in ipairs(rows) do if candidate.kind == kind then return candidate end end
end
local available = candidates(calm)
check(has(available, "wood") and not has(available, "field_work"),
    "mission wood is a dedicated decision independent of Follow field clearing")
preparation = request
available = candidates(calm)
check(has(available, "wood_preparation") and not has(available, "wood"),
    "equipment preparation takes precedence over site execution")
local threatened = candidates(danger)
check(not has(threatened, "wood") and not has(threatened, "wood_preparation")
    and has(threatened, "combat") and has(threatened, "combat").emergency,
    "immediate danger removes wood chores and retains emergency combat")
preparation, delivered = nil, { tripId = "wood:return" }
available = candidates(calm)
check(has(available, "expedition_delivery") and has(available, "expedition_delivery").score
    > has(available, "wood").score,
    "exact cargo settlement wins over another collection pass")
delivered = nil
check(select(2, D._delegateForTests({ kind = "wood", detail = request }, actor, nil,
    { snapshot = calm }, commands, calm, {})) == "wood_chopping" and woodSnapshot == calm,
    "worker delegation passes the fresh danger snapshot unchanged")

preparation, packing = request, true
token = { owner = "logistics", phase = "committing", action = "pack" }
local runtime = { snapshot = calm }
check(select(2, D.update(actor, nil, runtime, 1000)) == "wood_preparation_inventory_pending"
    and baseCancels == 0 and nativeCancels == 0 and packingResets == 0,
    "preparation waits for an inventory commit before resetting any owner")
token, baseCanCancel = nil, false
check(select(2, D.update(actor, nil, runtime, 1100)) == "base_transaction_pending"
    and baseCancels == 1 and nativeCancels == 0,
    "unsettled resident work retains its physical transaction")
baseCanCancel = true
D.update(actor, nil, runtime, 1200)
check(baseCancels == 2 and nativeCancels == 1 and downtimeCancels == 1 and packingResets == 1,
    "successful preparation handoff settles camp work, native work, downtime and packing once")
D.update(actor, nil, runtime, 1300)
check(baseCancels == 2 and nativeCancels == 1 and downtimeCancels == 1 and packingResets == 1,
    "the same equipment preparation does not repeatedly cancel its own gear pickup")

preparation, nativePhase, woodCalls = nil, "active", 0
runtime = { snapshot = calm }
check(select(2, D.update(actor, nil, runtime, 1400)) == "wood_chopping" and woodCalls == 1
    and woodSnapshot == calm,
    "a native mission chop polls its actual controller instead of starving behind the activity lease")
runtime.snapshot, woodCalls = danger, 0
D.update(actor, nil, runtime, 1500)
check(interrupts == 1 and woodCalls == 0,
    "fresh immediate danger interrupts the native chop before another wood-worker pulse")

local function marked(key)
    local item = { data = { [key] = { tripId = "wood:test", id = "native:1", memberId = actor.id } } }
    function item:getModData() return self.data end
    return item
end
local cargo, axe = marked("LF_ExpeditionWood"), marked("LF_ExpeditionWoodTool")
for _, operation in ipairs({ "loadout", "base_haul", "base_build", "trade", "work_gather" }) do
    check(SC.PersonalItems.isProtected(cargo, actor, operation)
        and SC.PersonalItems.isProtected(axe, actor, operation),
        "mission cargo and loaned axe are protected from " .. operation)
end
cargo.data.LF_ExpeditionWood, axe.data.LF_ExpeditionWoodTool = nil, nil
check(not SC.PersonalItems.isProtected(cargo, actor, "loadout")
    and not SC.PersonalItems.isProtected(axe, actor, "base_build"),
    "verified marker removal restores ordinary cargo availability")

SC_TEST_REPORT = "Wood decision and cargo ownership: " .. checks .. " checks passed"
