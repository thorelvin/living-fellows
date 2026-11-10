-- SPDX-License-Identifier: MIT
-- Native-shaped needs, survival priority, stamina reserve and sleep speech ownership.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check = f.check
local worker = f.actor("essential-needs", 2, 1, {})
f.registry[worker.id] = worker
worker.modData.SC_Order = "stay"
local player, playerHealth = f.player, f.player.body.health
local hunger, thirst = player.hunger, player.thirst
worker.hunger, worker.thirst, worker.fatigue = 0.9, 0.2, 0
local needs = SC.Needs.assess(worker, {})
check(needs.hungry and needs.hungerEmergency and needs.emergency,
    "actual carried actor stats expose urgent hunger")
local quiet = { threats = {}, allies = {}, threatCount = 0, immediateCount = 0,
    pressure = 0, closeThreatCount = 0, player = { danger = 0 } }
local commands = { recruited = true, order = "stay", commandSerial = 1 }
local healthy = { health = 100, alive = true, wounds = {}, bleedingCount = 0 }
local candidates = SC.Decision._evaluateForTests(worker, player, quiet, commands,
    healthy, needs, {}, f.clock)
check(candidates[1].kind == "needs" and candidates[1].emergency,
    "urgent food outranks ordinary orders and downtime")
local immediate = { threats = { { actor = f.zombie(3, 1, {}), visible = true } },
    threatCount = 1, immediateCount = 1, closeThreatCount = 1, pressure = 1,
    player = { danger = 0 } }
local threatened = SC.Decision._evaluateForTests(worker, player, immediate, commands,
    healthy, needs, {}, f.clock)
check(threatened[1].kind == "combat", "immediate defense interrupts a routine meal")
worker.endurance = 0.05
local readiness = SC.Combat.readiness(worker, immediate, nil, commands)
check(readiness.staminaCritical and readiness.endurance <= readiness.enduranceReserve,
    "native endurance below reserve is unavailable for sustained fighting")

local meal = f.item("Base.EssentialMeal", "Food", { hungerChange = -1 })
local spoiled = f.item("Base.EssentialSpoiledMeal", "Food", { hungerChange = -1, rotten = true })
worker.inventory:AddItem(spoiled)
worker.inventory:AddItem(meal)
local accepted, mealReason, eating
local mealRuntime = { snapshot = quiet }
for _ = 1, 12 do
    accepted, mealReason = SC.Needs.update(worker, player, mealRuntime, { expeditionMember = true })
    eating = worker.lastIntent
    if eating and eating.action == "eat_food" then break end
    f.clock = f.clock + 501
end
check(accepted and eating and eating.action == "eat_food" and eating.item == meal,
    "real needs dispatch selects its safe carried meal: " .. tostring(mealReason))
-- Complete the native consumption boundary, then let the real controller observe recovery.
worker:getStats():set(CharacterStat.HUNGER, worker.hunger + meal:getHungerChange() * eating.percentage)
worker.inventory:Remove(meal)
worker.lastIntent, f.clock = nil, f.clock + 1001
SC.Needs.update(worker, player, mealRuntime, { expeditionMember = true })
check(not SC.Needs.assess(worker, mealRuntime).hungry and worker.hunger < 0.3 and not worker.lastIntent
        and worker.inventory:contains(spoiled),
    "verified meal recovery releases needs without selecting rotten food")

f.makeSquare(60,60,0)
local empty=f.actor("empty-camp-meal",60,60,{})
empty.modData.SC_Order="base_duty";empty.hunger,empty.thirst=.8,.2
local oldInside,oldSupply=SC.BaseLife.isInside,SC.Encounter.takePlayerSupply
SC.BaseLife.isInside=function(a) return a==empty or oldInside(a) end
local searching=true
SC.Encounter.takePlayerSupply=function() return searching and "in_progress" or "missing","test search","searching" end
local emptyRuntime={snapshot=quiet}
SC.Needs.update(empty,player,emptyRuntime)
check(not SC.Needs.assess(empty,emptyRuntime).supplyMissing,"an unfinished preferred-food search is not a shortage")
searching=false
for _=1,5 do SC.Needs.update(empty,player,emptyRuntime);f.clock=f.clock+1001 end
check(SC.Needs.assess(empty,emptyRuntime).supplyMissing,"a completed empty search exposes the actual food shortage")
empty.inventory:AddItem(f.item("Base.RecoveredMeal","Food",{hungerChange=-1}))
for _=1,5 do SC.Needs.update(empty,player,emptyRuntime);f.clock=f.clock+1001 end
check(not SC.Needs.assess(empty,emptyRuntime).supplyMissing,"finding a real meal clears the supply shortage")
SC.BaseLife.isInside,SC.Encounter.takePlayerSupply=oldInside,oldSupply

worker.hunger, worker.thirst, worker.fatigue = 0.2, 0.2, 1
SC.Needs.reset(worker)
check(SC.Needs.assess(worker, {}).exhausted, "native fatigue exposes exhaustion")
local native, access, time = SC.NativeActions, SC.GameplayUtil.directInteractionAccess, getGameTime
local elapsed, baseHour = 0, getGameTime():getWorldAgeHours()
getGameTime = function() return { getWorldAgeHours = function() return baseHour + elapsed end,
    getTimeOfDay = function() return 12 end } end
function worker:setAsleep(value) self.asleep = value end
function worker:isOnBed() return self.onBed == true end
SC.NativeActions = { bedStatus = function() worker.onBed = true return "entered" end,
    seatingStatus = function() return worker.onBed and "bed" or "standing" end,
    leaveSeating = function() worker.onBed = false return true end }
local bed = { getSquare = function() return worker.square end }
SC.GameplayUtil.directInteractionAccess = function(subject, object)
    if object == bed then return true, { worker.square }, "arrived" end
    return access(subject, object)
end
local _, _, _, begin, _, _, _, _, _, _, _, stateFor = SC.Downtime._furnitureForTests()
local function sleep()
    local sleepCommands = SC.Commands.effective(worker)
    local accepted, reason = begin(worker, stateFor(worker), { kind = "rest_bed", object = bed,
        square = worker.square, lightChecked = true, fact = { activity = "rest_bed" } }, sleepCommands, f.clock)
    check(accepted, "real bed rest starts: " .. tostring(reason))
    local entered, why
    for _ = 1, 8 do
        entered, why = SC.Downtime.update(worker, player, { snapshot = quiet }, "rest_bed")
        if worker.asleep or not SC.Downtime.peek(worker).active then break end
        f.clock = f.clock + 501
    end
    check(entered and worker.asleep and why == "sleeping_on_bed", "native bed entry starts actual sleep: " .. tostring(why))
    return SC.Downtime.peek(worker).active
end
local sleeping = sleep()
local moves = worker.movementCalls or 0
local receipt = SC.Dialogue.lastSpokenAt(worker)
local said, why = SC.Dialogue.say(worker, "essential.sleep", { "Still asleep." })
check(SC.GameplayUtil.isSleeping(worker) and not said and why == "speaker_asleep"
        and SC.Dialogue.lastSpokenAt(worker) == receipt
        and (worker.movementCalls or 0) == moves,
    "owned bed sleep suppresses speech and receipts without moving the actor")
check(not SC.Banter.availableSpeaker({ actor = worker, runtime = { snapshot = quiet } },
        player, f.clock, 14), "sleep takes priority over optional conversation")
elapsed = sleeping.gameDurationHours / 2
SC.Downtime.update(worker, player, { snapshot = quiet }, "rest_bed")
check(worker.asleep and worker.fatigue > 0.1 and worker.fatigue < 0.7,
    "sleep restores fatigue gradually while retaining the same bed")
elapsed = sleeping.gameDurationHours + 0.01
SC.Downtime.update(worker, player, { snapshot = quiet }, "rest_bed")
check(not worker.asleep and worker.fatigue <= 0.1 and not SC.Downtime.peek(worker).active,
    "completed sleep wakes the actor and releases its activity")
elapsed, worker.fatigue = elapsed + 1.01, 0.85
sleep()
SC.Downtime.update(worker, player, { snapshot = immediate }, "rest_bed")
check(not worker.asleep and not SC.Downtime.peek(worker).active and not worker.onBed,
    "danger wakes the sleeper and releases the native bed posture")
SC.NativeActions, SC.GameplayUtil.directInteractionAccess, getGameTime = native, access, time

-- Returned cargo must get a decision after a casual pause, without waking a
-- sleeper or interrupting cleaning's owned item transfers.
local downtime, expedition = SC.Downtime, SC.ExpeditionPrototype
local supervisor = SC.ActionSupervisor
SC.ExpeditionPrototype = { integrationFor = function(subject)
    return subject == worker and { id = "returned-cargo" } or nil
end }
for _, kind in ipairs({ "sit", "read", "rest_bed", "clean_base" }) do
    supervisor.reset(worker)
    SC.Downtime = {
        peek = function() return { active = { kind = kind } } end,
        update = function() return true, "owned_pause" end,
        cancel = function(subject, reason) return supervisor.cancel(subject, reason, nil, false) end,
    }
    local token = assert(supervisor.begin(worker, {
        owner = "downtime", action = kind, priority = supervisor.Priority.WORK,
        metadata = { commandSerial = 1 }, ignoreRetry = true,
        onCancel = function() return true end,
    }))
    local held = SC.Decision._holdOwnedActivityOrPacingForTests(worker, player,
        quiet, healthy, {}, { recruited = true, order = "base_duty", commandSerial = 1 },
        {}, f.clock, {})
    local casual = kind == "sit" or kind == "read"
    check(casual and held == false and not supervisor.isCurrent(token)
            or not casual and held == true and supervisor.isCurrent(token),
        "ready expedition cargo releases only casual downtime: " .. kind)
    if casual then
        local delivery = false
        for _, candidate in ipairs(SC.Decision._evaluateForTests(worker, player,
                quiet, commands, healthy, {}, {}, f.clock)) do
            if candidate.kind == "expedition_delivery" then delivery = true end
        end
        check(delivery, "released downtime exposes the returned-cargo decision")
    end
end
supervisor.reset(worker)
SC.Downtime, SC.ExpeditionPrototype = downtime, expedition

local wound = f.bodyPart({ name = "ForeArm_R", isBleeding = true })
local patient = f.actor("essential-bandage", 0, 2, { body = f.bodyDamage(70, { wound }) })
local bandage = f.item("Base.Bandage", "Medical")
player.inventory:AddItem(bandage)
check(SC.Medical.assessCached(patient).needsBandage, "the wound cache sees the original bleeding injury")
local ready, _, context = SC.Medical.playerBandagePreflight(patient, player)
check(ready and context.wound.part == wound and context.bandage == bandage
        and player.inventory:contains(bandage), "player-care preflight resolves exact wound and dressing without consuming it")
check(SC.Medical.applyPlayerBandage(patient, player) and wound.isBandaged and not wound.isBleeding
        and not player.inventory:contains(bandage) and bandage:getContainer() == nil
        and not SC.Medical.assessCached(patient).needsBandage,
    "verified player care consumes exactly its dressing, stops bleeding and invalidates cached need")
check(not SC.Medical.applyPlayerBandage(patient, player), "completed player care cannot consume another dressing")
check(player.hunger == hunger and player.thirst == thirst and player.body.health == playerHealth
        and not player.lastIntent, "companion needs never change player vitals or actions")
-- The real ownership gate must poll a floor pickup's parent, including a
-- completed result; generic visuals must not overwrite that parent identity.
local oldFloor, oldWork, oldLife, oldNative = SC.FloorSort, SC.BaseWork, SC.BaseLife, SC.NativeActions
local pickupToken, foreignToken = {}, {}
local floorJob = { id = "floor:owned", type = "sort_floor" }
local currentToken, phase, polled, paused, releaseOkay = pickupToken, "active", 0, 0, true
SC.FloorSort = {
    pendingPickup = function() return floorJob.id, pickupToken end,
    pause = function(subject, job)
        check(subject == worker and (job == floorJob or job == nil), "only matching floor controller is paused")
        paused = paused + 1
        if not releaseOkay then return false, "cancel_pending" end
        currentToken = nil; return true
    end,
}
SC.BaseWork = { update = function() polled = polled + 1; return true, "floor_controller_polled" end }
SC.BaseLife = { jobFor = function() return floorJob end, isInside = function() return true end }
SC.NativeActions = { activityStatus = function() return phase, "visual", "loot_container" end,
    visualToken = function() return currentToken end }
local floorCommands = { recruited = true, order = "base_duty" }
for _, value in ipairs({ "active", "result_pending" }) do
    phase = value
    local decision = {}
    local held = SC.Decision._holdOwnedActivityOrPacingForTests(worker, player,
        quiet, healthy, {}, floorCommands, decision, f.clock + 5000, {})
    check(held and decision.current == "base_work", "floor result stays with its parent: " .. value)
end
check(polled == 2 and paused == 0, "both running and delayed completed pickups are polled")
releaseOkay = false
local held = SC.Decision._holdOwnedActivityOrPacingForTests(worker, player,
    quiet, healthy, { emergency = true }, floorCommands, {}, f.clock, {})
check(held and currentToken == pickupToken, "urgent handoff waits for exact pickup cancellation")
releaseOkay = true
held = SC.Decision._holdOwnedActivityOrPacingForTests(worker, player,
    quiet, healthy, { emergency = true }, floorCommands, {}, f.clock, {})
check(not held and currentToken == nil and polled == 2, "released pickup hands control to survival without claiming completion")
currentToken, phase = foreignToken, "active"
local beforePause = paused
SC.Decision._holdOwnedActivityOrPacingForTests(worker, player, quiet, healthy, {}, floorCommands, {}, f.clock, {})
check(paused == beforePause and polled == 2, "a foreign token is neither polled nor cancelled as a floor pickup")
SC.FloorSort, SC.BaseWork, SC.BaseLife, SC.NativeActions = oldFloor, oldWork, oldLife, oldNative

-- The native damage callback is deliberately pure Lua even when called from
-- inside a native operation. Damage and summaries stay isolated by identity.
local oldIdOf, oldById = SC.Registry.idOf, SC.Registry.byId
local damaged = f.actor("damage:one", 0, 0, {})
local second = f.actor("damage:two", 1, 0, {})
local owned = { [damaged.id] = { actor = damaged }, [second.id] = { actor = second } }
SC.Registry.idOf = function(subject) return subject == damaged and damaged.id or subject == second and second.id end
SC.Registry.byId = function(id) return owned[id] end
local util = SC.GameplayUtil
SC.GameplayUtil = setmetatable({}, { __index = function() error("native damage callback tried a gameplay/native read") end })
SC.Medical.noteNativeDamage(damaged, "HUNGRY", 1.5)
SC.Medical.noteNativeDamage(damaged, "HUNGRY", 1.5)
SC.Medical.noteNativeDamage(second, "THIRST", 4)
SC.Medical.noteNativeDamage(player, "POISON", 100)
SC.GameplayUtil = util
local summary = SC.Medical.deathSummary(damaged)
check(string.find(summary, "HUNGRY:3/2", 1, true) and not string.find(summary, "THIRST:", 1, true)
    and not string.find(summary, "POISON:", 1, true), "death records only the intended companion's native damage")
check(string.find(SC.Medical.deathSummary(second), "THIRST:4/1", 1, true), "second companion retains its own damage receipt")
for _, reason in ipairs({ "SICK", "THIRST", "HEAVYLOAD", "INFECTION" }) do SC.Medical.noteNativeDamage(damaged, reason, 1) end
check(not string.find(SC.Medical.deathSummary(damaged), "HUNGRY:", 1, true), "native damage history is bounded to four coalesced records")
SC.Medical.releaseActor(damaged)
check(string.find(SC.Medical.deathSummary(damaged), "recentNativeDamage=unknown", 1, true), "actor retirement explicitly clears damage history")
local originalPrint, warnings = print, 0
print = function(line) if string.find(tostring(line), "[SurvivorCompanion/health-decline]", 1, true) then warnings = warnings + 1 end end
for _, health in ipairs({ 69, 68, 75, 69 }) do damaged.body.health = health; SC.Medical.assess(damaged) end
print = originalPrint
check(warnings == 2, "critical snapshots occur once per decline and rearm after recovery")
SC.Medical.releaseActor(damaged); SC.Medical.releaseActor(second)
SC.Registry.idOf, SC.Registry.byId = oldIdOf, oldById
local milkFarmer=f.actor("milk-loan-refill",1,1,{})
local milkBucket=f.item("Base.Bucket","Drainable")
local emptyMilkFluid={getAmount=function() return 0 end,getCapacity=function() return 2 end,
    isInputLocked=function() return false end,isPoisonous=function() return false end,
    canAddFluid=function() return true end}
function milkBucket:getFluidContainer() return emptyMilkFluid end
milkFarmer.inventory:AddItem(milkBucket)
milkBucket:getModData()[SC.FarmWork.ITEM_MARKER]="farm:milk-loan"
check(not SC.Needs.refillDue(milkFarmer,f.clock),"an empty receipted milk bucket cannot trigger hydration refill")
milkBucket:getModData()[SC.FarmWork.ITEM_MARKER]=nil
SC.Needs.reset(milkFarmer)
check(SC.Needs.refillDue(milkFarmer,f.clock+60000),"releasing the same vessel restores ordinary hydration eligibility")
print("BEHAVIOUR_NEEDS_PASS checks=" .. tostring(f.checks()))
