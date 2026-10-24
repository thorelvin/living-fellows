-- SPDX-License-Identifier: MIT
-- Exact scavenging cancellation and native visual handoff, in isolation.
local SC = SurvivorCompanion
local Encounter = SC.Encounter
local checks = 0
local function check(value, message)
    checks = checks + 1
    if not value then error("encounter handoff: " .. message) end
end
local actor = { id = "handoff:actor", x = 1, y = 1, z = 0 }
local currentVisual, canCancel, nativeCancels = nil, true, 0
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    config = function() return nil end,
    actorState = function(_, runtime) return runtime or {} end,
    idOf = function(value) return value.id end,
    position = function(value) return value.x, value.y, value.z end,
    stop = function() return true end,
}
SC.Commands = { peek = function() return { scavenge = false } end }
SC.Navigation = { cancel = function() return true end }
SC.NativeActions = {
    visualToken = function() return currentVisual end,
    visualStatus = function() return currentVisual and "active" or "none" end,
    stopDirect = function() return true end,
    cancelVisualOwned = function(_, token)
        if currentVisual ~= token then return true, "visual_no_longer_owned" end
        if not canCancel then return false, "native_cancel_pending" end
        currentVisual = nil
        nativeCancels = nativeCancels + 1
        return true
    end,
}
Encounter.tryScavenge(actor, nil, {}) -- creates the private task state
local state = Encounter.peek(actor)
check(state ~= nil and state.task == nil, "fixture initializes idle encounter state")
local prior, replacement = {}, {}
state.task = { phase = "animate", visualToken = prior }
currentVisual = replacement
check(Encounter.cancelScavenge(actor, "base_job_assigned") == true
    and state.task == nil and currentVisual == replacement and nativeCancels == 0,
    "cancelling an old scavenge task preserves a newer job's visual")

currentVisual, canCancel = prior, false
state.task = { phase = "animate", visualToken = prior }
local cancelled = Encounter.cancelScavenge(actor, "base_job_assigned")
check(cancelled == false and state.pendingVisualCancel == prior
    and currentVisual == prior,
    "an unfinished native cancellation is retained for retry")
canCancel = true
check(Encounter.cancelScavenge(actor, "base_job_assigned") == true
    and currentVisual == nil and state.pendingVisualCancel == nil and nativeCancels == 1,
    "retry settles the exact native visual before allowing base work")
currentVisual = prior
state.task = { phase = "settle", visualToken = prior }
check(Encounter.cancelScavenge(actor, "base_job_assigned") == true
    and currentVisual == nil and nativeCancels == 2,
    "an accepted visual is released even before its animate phase was observed")

for _, phase in ipairs({ "commit", "verify" }) do
    state.task = { phase = phase }
    local stopped, why = Encounter.cancelScavenge(actor, "base_job_assigned")
    check(stopped == false and why == "scavenge_commit_in_progress"
        and state.task.phase == phase,
        "base handoff does not erase an item " .. phase .. " transaction")
end

local token, supervisorCanCancel = {}, false
local settling = { phase = "settle", supervisorToken = token }
state.task = settling
SC.ActionSupervisor = {
    isCurrent = function(value) return value == token end,
    cancel = function()
        if not supervisorCanCancel then return false, "rollback_recovery_pending" end
        return true
    end,
}
local stopped, why = Encounter.cancelScavenge(actor, "base_job_assigned")
check(stopped == false and why == "rollback_recovery_pending"
    and state.task == settling,
    "a supervisor refusal retains the scavenge task and ownership")
supervisorCanCancel = true
check(Encounter.cancelScavenge(actor, "base_job_assigned") == true and state.task == nil,
    "base handoff succeeds after the supervisor permits cancellation")

SC_TEST_REPORT = "ENCOUNTER_HANDOFF_PASS checks=" .. checks
