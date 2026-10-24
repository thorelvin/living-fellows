-- SPDX-License-Identifier: MIT
-- Standalone wiring and ownership matrix: decisions must be selectable,
-- reach their controllers, and release control for independent emergencies.
local SC, checks = SurvivorCompanion, 0
local D, Supervisor = SC.Decision, SC.ActionSupervisor
local clock, delegated, interrupted = 10000, nil, 0
local nativePhase, nativeOwner, nativeName = "none", nil, nil
local function check(value, message)
    checks = checks + 1
    if not value then error("decision arbitration check " .. checks .. ": " .. message) end
end
function getTimestampMs() return clock end
local function person(id, x)
    local value = { id = id, x = x or 0, y = 0, z = 0 }
    function value:getVehicle() return nil end
    function value:isMoving() return false end
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    return value
end
local actor, player = person("decision", 0), person("player", 2)
local function record(name)
    return function() delegated = name return true, name end
end
SC.GameplayUtil = {
    nowMs = function() return clock end,
    config = function(key)
        if key == "followSettleMs" or key == "followSettleStaggerMs" then return 0 end
        return nil
    end,
    idOf = function(value) return value.id end,
    position = function(value) return value.x, value.y, value.z or 0 end,
    distance = function(first, second) return math.abs(first.x - second.x) end,
    distanceSq = function(first, second) return (first.x - second.x)^2 end,
    sameFloor = function(first, second) return (first.z or 0) == (second.z or 0) end,
    stableHash = function() return 1 end,
    isDead = function() return false end,
    isValidActor = function(value) return value ~= nil end,
    nativeHealth = function() return 100 end,
    squareOf = function(value) return value end,
    squareKey = function(value) return tostring(value.x) .. ":" .. tostring(value.y) .. ":" .. tostring(value.z or 0) end,
    loadedSquare = function(value) return value end,
    stop = record("stop"),
    move = function(_, _, intent) delegated = intent.action return true, intent.action end,
    isDue = function() return true end,
    actorState = function(_, runtime) return runtime end,
    diagnostic = function() end,
    call = function(value, name, ...)
        if value and type(value[name]) == "function" then return value[name](value, ...), true end
        return nil, false
    end,
    safeSubsystem = function(_, _, callback, ...)
        local okay, first, second = pcall(callback, ...)
        if not okay then return false, nil, first end
        return true, first, second
    end,
    sortByScoreDescending = function(values)
        table.sort(values, function(a, b)
            if a.score == b.score then return a.kind < b.kind end
            return a.score > b.score
        end)
    end,
}
local function quiet()
    return { threats = {}, allies = {}, immediateAttackers = {}, escapeSquares = {},
        threatCount = 0, immediateCount = 0, pressure = 0, closeThreatCount = 0,
        player = { danger = 0 } }
end
local function healthy()
    return { health = 100, alive = true, bleedingCount = 0, critical = false, downed = false }
end
local function order(kind)
    return { recruited = true, order = kind or "follow", followDistance = 3,
        moveMode = "walk", commandSerial = 1, personalityProfile = {} }
end
local function modules()
    nativePhase, nativeOwner, nativeName, delegated = "none", nil, nil, nil
    SC.Personality, SC.Objectives = nil, nil
    SC.Combat = { update = record("combat"), onlyUnreachableThreats = function() return false end }
    SC.Medical = { update = record("medical") }
    SC.Needs = { update = record("needs"), refill = record("water_refill") }
    SC.Downtime = { update = record("downtime") }
    SC.BaseWork = { update = record("base_work") }
    SC.BaseLife = { isInside = function() return true end }
    SC.Encounter = { update = record("encounter"), peek = function() return nil end }
    SC.Logistics = { update = record("logistics") }
    SC.FieldWork = { update = record("field_work"), wants = function() return false end }
    SC.ExpeditionPrototype = { updateIntegration = record("expedition_delivery") }
    SC.Fishing = { update = record("fishing") }
    SC.InfectionCrisis = { updateActor = record("infection_crisis") }
    SC.FactionBehavior = { update = record("faction") }
    SC.BaseAlert = { act = record("base_alert"), directiveFor = function() return nil end }
    SC.Autonomy = { update = record("autonomy") }
    SC.Positioning = {
        updateConversation = record("conversation"),
        formationTarget = function() return player end,
        shouldHold = function() return true end,
    }
    SC.Navigation = { request = record("navigation") }
    SC.NativeActions = {
        activityStatus = function() return nativePhase, nativeOwner, nativeName end,
        interruptOwnedActivity = function()
            interrupted = interrupted + 1
            nativePhase, nativeOwner = "none", nil
            return true, "interrupted"
        end,
        pacingStatus = function() return false end,
    }
end

-- Selection and dispatch are both exercised. This is a wiring matrix, rather
-- than only calling each module directly and assuming Decision can reach it.
local rows = {
    { "medical", "medical", function(_, assessment) assessment.bleedingCount = 1 end },
    { "combat", "combat", function(snapshot)
        snapshot.threatCount, snapshot.immediateCount = 1, 1
    end },
    { "needs", "needs", function(_, _, needs)
        needs.hungry, needs.hunger, needs.emergency = true, 0.9, true
    end },
    { "water_refill", "water_refill", function(_, _, _, commands)
        commands.order = "base_duty"
        SC.Needs.refillDue = function() return true end
    end },
    { "base_work", "base_work", function(_, _, _, commands) commands.order = "base_duty" end },
    { "expedition_delivery", "expedition_delivery", function()
        SC.ExpeditionPrototype.integrationFor = function() return true end
    end },
    { "field_work", "field_work", function() SC.FieldWork.wants = function() return true end end },
    { "fishing", "fishing", function()
        SC.ExpeditionPrototype.fishingRequestFor = function() return { water = true } end
    end },
    { "logistics", "logistics", function()
        SC.Logistics.status = function() return { shouldManage = true, overloaded = true } end
    end },
    { "infection_crisis", "infection_crisis", function()
        SC.InfectionCrisis.intentFor = function() return { priority = 100 } end
    end },
    { "faction", "faction", function(_, _, _, commands)
        commands.recruited = false
        SC.FactionBehavior.intentFor = function() return { priority = 77, mode = "construction" } end
    end },
    { "encounter", "encounter", function(_, _, _, commands) commands.recruited = false end },
    { "scavenge", "encounter", function(_, _, _, commands)
        commands.order, commands.scavenge = "stay", true
    end },
    { "downtime", "downtime", function(_, _, _, commands) commands.order = "stay" end },
    { "follow", "stop", function() end },
    { "tactical", "navigation", function(_, _, _, commands)
        commands.order, commands.tacticalTarget = "move_to", { x = 20, y = 0, z = 0 }
    end },
    { "retreat", "navigation", function(snapshot, _, _, commands)
        commands.order = "retreat"
        snapshot.threatCount, snapshot.immediateCount = 1, 1
        snapshot.escapeSquares = { { square = { x = -10, y = 0, z = 0 } } }
    end },
    { "alert", "face_alert", function(snapshot)
        snapshot.sounds = { { kind = "companion_alert", x = 2, y = 0, time = clock, distanceSq = 4 } }
    end },
    { "base_alert", "base_alert", function(_, _, _, commands)
        commands.order = "base_duty"
        SC.BaseAlert.directiveFor = function() return { mode = "respond", score = 88 } end
    end },
    { "conversation", "conversation", function()
        SC.Positioning.activeConversation = function() return true end
    end },
}
for _, kind in ipairs({ "mental_episode", "grief_response", "purposeful_idle",
        "joy_response", "social_participant", "ritual" }) do
    rows[#rows + 1] = { kind, "autonomy", function()
        SC.Autonomy.intentFor = function() return { kind = kind, priority = 100 } end
    end }
end
for _, row in ipairs(rows) do
    modules()
    local snapshot, assessment, needs, commands = quiet(), healthy(), {}, order()
    row[3](snapshot, assessment, needs, commands)
    local candidates = D._evaluateForTests(actor, player, snapshot, commands,
        assessment, needs, {}, clock)
    local selected = D._selectWithHysteresisForTests({}, candidates, clock)
    check(selected and selected.kind == row[1], row[1] .. " can win arbitration")
    local handled, reason = D._delegateForTests(selected, actor, player,
        { snapshot = snapshot }, commands, snapshot, {})
    check(handled == true and delegated == row[2], row[1] .. " reaches its controller: " .. tostring(reason))
end

-- Drive the complete update/fallback loop as well: a chore that has no
-- concrete action must not leave the actor stuck on that failed decision.
modules()
local following = person("fallback-follow", 0)
local followCommands = order()
SC.Commands = { effective = function() return followCommands end }
SC.ExpeditionPrototype.isMember = function() return false end
SC.Needs.assess = function() return { hungry = true, hunger = 0.6 } end
SC.Needs.update = function() return false, "food_unavailable" end
local followRuntime = { snapshot = quiet() }
for _ = 1, 3 do
    clock = clock + 1000
    check(D.update(following, player, followRuntime, clock) == true
        and D.peek(following).current == "follow" and delegated == "stop",
        "a failed food search releases selection to Follow on each fresh decision")
end
modules()
local resident = person("fallback-base", 0)
SC.Commands = { effective = function() return order("base_duty") end }
SC.ExpeditionPrototype.isMember = function() return false end
SC.BaseWork.update = function() return false, "no_actionable_job" end
local baseRuntime = { snapshot = quiet() }
check(D.update(resident, player, baseRuntime, clock) == true
    and D.peek(resident).current == "downtime" and delegated == "downtime",
    "base work with no actionable job releases selection to ordinary downtime")

local function hold(snapshot, assessment, needs, commands, state)
    return D._holdOwnedActivityOrPacingForTests(actor, player, snapshot or quiet(),
        assessment or healthy(), needs or {}, commands or order(), state or {}, clock, {})
end

-- A seated driver retains control under foot combat contacts, while its
-- personal health/needs emergencies still request a safe stop.
check(D._ownerNeedsImmediatePreemptionForTests("drive", { immediateCount = 1 },
        healthy(), {}, order()) == false
    and D._ownerNeedsImmediatePreemptionForTests("drive", quiet(),
        { bleedingCount = 1 }, {}, order()) == true
    and D._ownerNeedsImmediatePreemptionForTests("drive", quiet(),
        healthy(), { emergency = true }, order()) == true,
    "driving ownership distinguishes nearby foot combat from a driver's own emergency")

-- Native meal actions have no supervisor token. Their own hunger/thirst is
-- the reason to finish, never a fresh reason to cancel them every decision beat.
for _, kind in ipairs({ "eat", "drink" }) do
    modules()
    nativePhase, nativeOwner, nativeName = "active", "needs", kind
    local before = interrupted
    for _ = 1, 5 do
        local held = hold(nil, nil, { active = true, emergency = true, hunger = 0.9, thirst = 0.9 })
        check(held == true and nativePhase == "active", "emergency " .. kind .. " keeps its native owner")
    end
    check(interrupted == before, "emergency " .. kind .. " is not cancelled by its own need")
end

-- Each independent emergency must still release the meal for its controller.
for _, cause in ipairs({ "attack", "human", "bleeding", "retreat", "faction" }) do
    modules()
    nativePhase, nativeOwner, nativeName = "active", "needs", "drink"
    local snapshot, assessment, commands = quiet(), healthy(), order()
    if cause == "attack" then snapshot.immediateCount = 1
    elseif cause == "human" then snapshot.humanThreat = { visible = true }
    elseif cause == "bleeding" then assessment.bleedingCount = 1
    elseif cause == "retreat" then commands.order = "retreat"
    else
        commands.recruited = false
        SC.FactionBehavior.intentFor = function() return { mode = "hostile" } end
    end
    check(hold(snapshot, assessment, { active = true, emergency = true }, commands) == false
        and nativePhase == "none", cause .. " interrupts an emergency meal")
end

-- A contact cannot cancel a meal only for that meal to win selection again.
-- A fall-back is independent camp danger and must still get the resident out.
for _, level in ipairs({ "contact", "fall_back" }) do
    modules()
    nativePhase, nativeOwner, nativeName = "active", "needs", "eat"
    SC.BaseAlert.preempts = function() return true end
    SC.BaseAlert.directiveFor = function()
        return { mode = level == "fall_back" and "fall_back" or "watch", level = level,
            score = level == "fall_back" and 96 or 66 }
    end
    local held = hold(nil, nil, { active = true, hunger = 0.6 }, order("base_duty"))
    check(level == "contact" and held == true and nativePhase == "active"
        or level == "fall_back" and held == false and nativePhase == "none",
        level .. " alarm respects meal urgency and evacuation precedence")
end

-- A medical owner likewise retains the wound urgency it is already treating.
modules()
nativePhase, nativeOwner, nativeName = "active", "medical", "bandage"
check(hold(nil, { health = 40, bleedingCount = 2 }, {}) == true
    and nativePhase == "active", "native medical ownership ignores its own bleeding urgency")

-- Medical's actual native child is usually reported as "visual". The live
-- supervisor parent remains authoritative until it releases that child.
modules()
local medical = assert(Supervisor.begin(actor, {
    owner = "medical", action = "bandage", phase = "animating",
    priority = Supervisor.Priority.COMBAT_RESCUE, ignoreRetry = true,
    onCancel = function() nativePhase, nativeOwner = "none", nil return true end,
}))
nativePhase, nativeOwner, nativeName = "active", "visual", "bandage"
check(hold(nil, { health = 40, bleedingCount = 2 }, {}) == true
        and Supervisor.isCurrent(medical) and nativePhase == "active",
    "a medical parent protects its generic visual child from its own wound urgency")
local medicalDanger = quiet()
medicalDanger.immediateCount = 1
check(hold(medicalDanger, { health = 40, bleedingCount = 2 }, {}) == false
        and not Supervisor.isCurrent(medical) and nativePhase == "none",
    "independent danger still releases both the medical parent and its visual child")

-- A cleaning job uses Downtime as its controller. Its own assigned job must
-- not cancel it as though an unrelated chore had arrived during a casual sit.
modules()
local cleaningPolls = 0
SC.Downtime.peek = function() return { active = { kind = "clean_base" } } end
SC.Downtime.update = function() cleaningPolls = cleaningPolls + 1 return true, "cleaning" end
SC.BaseLife.jobFor = function() return { id = "clean", type = "clean" } end
local cleaning = assert(Supervisor.begin(actor, {
    owner = "downtime", action = "clean_base", priority = Supervisor.Priority.WORK,
    metadata = { commandSerial = 1 }, onCancel = function() return true end, ignoreRetry = true,
}))
check(hold(nil, nil, nil, order("base_duty")) == true and cleaningPolls == 1
    and Supervisor.isCurrent(cleaning), "the cleaning controller is polled without cancelling its own job")
local danger = quiet()
danger.immediateCount = 1
check(hold(danger, nil, nil, order("base_duty")) == false
    and not Supervisor.isCurrent(cleaning), "real danger releases cleaning ownership")

-- A non-cancellable commit queues survival, then releases it when its receipt
-- finishes. It cannot make an urgent decision disappear indefinitely.
modules()
local state = {}
local committing = assert(Supervisor.begin(actor, {
    owner = "work", action = "transfer", priority = Supervisor.Priority.WORK,
    phase = "committing", interruptible = false, ignoreRetry = true,
}))
check(hold(danger, nil, nil, order(), state) == true
    and Supervisor.urgentStatus(actor).state == "queued", "a protected transfer queues urgent reassessment")
-- Commit verification is exercised by the real supervisor, not a fake owner.
committing.commitEntered, committing.committed = true, true
check(Supervisor.transition(committing, "verifying") == true
    and Supervisor.complete(committing, "verified", { verified = true }) == true,
    "the transfer produces a verified terminal receipt")
check(Supervisor.urgentStatus(actor).state == "dispatched" and state.current == "urgent"
    and hold(danger, nil, nil, order(), state) == false,
    "fresh survival selection is released immediately after the commit")

Supervisor.reset(actor)
SC_TEST_REPORT = "DECISION_ARBITRATION_PASS checks=" .. checks .. " kinds=" .. #rows
