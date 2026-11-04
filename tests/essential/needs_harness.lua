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
print("BEHAVIOUR_NEEDS_PASS checks=" .. tostring(f.checks()))
