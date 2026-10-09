-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local C = SC_TEST_CLOCK
local red = SC_TEST_ACTOR(10, 10)
red.inventory = {}
local bodyParts = { { name = "head" }, { name = "torso" }, { name = "arm" } }
BloodBodyPartType = {
    MAX = { index = function() return #bodyParts end },
    FromIndex = function(index) return bodyParts[index + 1] end,
}
local function nativeList(items)
    return { size = function() return #items end,
        get = function(_, index) return items[index + 1] end }
end
BloodClothingType = {
    getCoveredParts = function(kinds) return kinds end,
    calcTotalBloodLevel = function(item) item.bloodLevel = 100 end,
}
local skin = { blood = {} }
function skin:setBlood(part, level) self.blood[part] = level end
function red:getHumanVisual() return skin end
local shirt = { blood = {}, kinds = nativeList({ bodyParts[2], bodyParts[3] }) }
local mask = { blood = {}, kinds = nativeList({ bodyParts[1] }) }
for _, item in ipairs({ shirt, mask }) do
    function item:getBloodClothingType() return self.kinds end
    function item:setBlood(part, level) self.blood[part] = level end
end
local worn = nativeList({
    { getItem = function() return shirt end },
    { getItem = function() return mask end },
})
function red:getWornItems() return worn end
function red:resetModelNextFrame()
    self.modelRefreshes = (self.modelRefreshes or 0) + 1
end
local player = SC_TEST_ACTOR(10, 7)
player.visible = { ["10:10"] = true, ["14:10"] = true }
local redGroup = { id = "red-1", members = { ["member-1"] = { actorId = "red" } },
    oddball = { id = "gut_cloaked_red", stage = "unmet",
        cloak = { remainingHours = 18, updatedHour = 0 } } }
SC.Registry.actors.red = { actor = red }
SC.Oddballs.actorGroups[red] = redGroup
assert(SC.OddballRed.onSpawn(redGroup, red) == true)
assert(skin.blood[bodyParts[1]] == 1
    and skin.blood[bodyParts[2]] == 1
    and skin.blood[bodyParts[3]] == 1
    and shirt.blood[bodyParts[2]] == 1
    and shirt.blood[bodyParts[3]] == 1
    and mask.blood[bodyParts[1]] == 1
    and shirt.blood[bodyParts[1]] == nil
    and shirt.bloodLevel == 100 and mask.bloodLevel == 100
    and red.modelRefreshes == 1,
    "Red's exposed skin and worn clothing must be visibly soaked in blood")
assert(#red.inventory == 2
    and red.inventory[1].fullType == "Base.HandScythe"
    and red.inventory[2].fullType == "Base.TinnedBeans"
    and redGroup.oddball.gearSeeded == true,
    "Red must receive his authored scythe and food on first spawn")
SC.OddballRed.onSpawn(redGroup, red)
assert(#red.inventory == 2, "repeat onSpawn must not duplicate Red's gear")
red.inventory[2] = nil
SC.OddballRed.onSpawn(redGroup, red)
assert(#red.inventory == 1 and red.inventory[1].fullType == "Base.HandScythe",
    "save/load must not replace Red's food after he consumes or trades it")
assert(red.immunity == true, "Red must set native attack immunity")
red.immunity = false
SC.OddballRed.onSpawn(redGroup, red)
assert(red.immunity == true,
    "Red must re-apply attack immunity when the native flag drifted off")

local zombie = { zombie = true, x = 11, y = 10, z = 0, target = red }
function zombie:getTarget() return self.target end
function zombie:setTarget(value) self.target = value end
function zombie:setTargetSeenTime(value) self.seenTime = value end
function zombie:isUseless() return false end
function zombie:spotted(actor) self.target = actor end
local ok, reason = SC.ZombieTargeting.consider(zombie, red)
assert(ok == false and reason == "actor_gore_cloaked",
    "targeting gate must reject a cloaked Red")
local released, _, counts = SC.ZombieTargeting.releaseTargets(red, { zombie })
assert(released and zombie.target == nil and counts.released == 1,
    "new cloak must release a zombie already chasing Red")
C.hour, C.rain = 1, true
SC.OddballRed.pulse(redGroup, player, C.ms)
assert(redGroup.oddball.cloak.remainingHours == 14,
    "outdoor rain must cost four cloak hours per hour")
redGroup.oddball.cloak.remainingHours = 0
SCBridge.refuse = true
SC.OddballRed.pulse(redGroup, player, C.ms)
assert(red.immunity == true,
    "a refused bridge call must leave the native flag as it was")
SCBridge.refuse = false
SC.OddballRed.pulse(redGroup, player, C.ms)
assert(red.immunity == false, "faded cloak must clear native immunity")
zombie.visible = { ["10:10"] = true }
local reacquired = SC.ZombieTargeting.consider(zombie, red)
assert(reacquired == true and zombie.target == red,
    "normal spotted targeting must return after the cloak fades")

local kevin = SC_TEST_ACTOR(0, 0)
local kevinGroup = { id = "kevin-1", members = { ["member-1"] = { actorId = "kevin" } },
    oddball = { id = "window_spiffo_kevin", stage = "posing",
        managerSpawned = true,
        poseSpots = { { x = 0, y = 0, z = 0 }, { x = 4, y = 0, z = 0 } },
        poseIndex = 1 } }
SC.Registry.actors.kevin = { actor = kevin }
SC.Oddballs.actorGroups[kevin] = kevinGroup
assert(SC.OddballSpiffo.onSpawn(kevinGroup, kevin) == true)
assert(kevin.immunity == true, "posing Kevin must set native attack immunity")
player.x, player.y, player.fx, player.fy = 0, -3, 0, 1
player.visible = { ["0:0"] = true, ["4:0"] = true }
C.ms = 100
local intent = SC.OddballSpiffo.intentFor(kevin, player, {}, kevinGroup)
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.nav == 0, "Kevin must freeze while watched")
assert(kevin.variables.Ext == "LF_SpiffoMannequin"
    and kevin.events[#kevin.events] == "EventDoExt",
    "watched Kevin must enter the held mannequin animation")
local poseEvents = #kevin.events
C.ms = 5100
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.nav == 0, "watching longer than step cooldown must still freeze him")
assert(#kevin.events == poseEvents,
    "held pose must not restart the animation on every decision tick")
player.fx, player.fy = 0, -1
C.ms = 5200
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.nav == 0, "looking away starts the four-second pose timer")
C.ms = 9300
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.nav == 1 and C.lastTarget.x == 4,
    "one unseen step must use Navigation after four seconds")
assert(kevin.variables.Ext == nil
    and kevin.events[#kevin.events] == "ExtFinishing",
    "Kevin must release the mannequin pose before walking")
player.fx, player.fy = 0, 1
C.ms = 9400
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.cancel > 0, "watching mid-route must cancel Navigation")
assert(kevin.variables.Ext == "LF_SpiffoMannequin",
    "Kevin must resume the mannequin pose when watched mid-route")
player.visible = { ["4:0"] = true }
C.ms = 15000
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(C.nav == 1, "Kevin must never choose a pose destination the player can see")
player.visible = { ["0:0"] = true, ["4:0"] = true }
player.x, player.y = 0, -1
C.ms = 20000
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(kevinGroup.oddball.revealed ~= true, "a glance must not reveal Kevin")
C.ms = 25100
SC.OddballSpiffo.update(kevin, player, nil, intent, kevinGroup)
assert(kevinGroup.oddball.revealed == true and kevin.immunity == false,
    "five seconds of close watching must reveal Kevin and clear immunity")
assert(kevin.variables.Ext == nil
    and kevin.events[#kevin.events] == "ExtFinishing",
    "revealing Kevin must release his mannequin animation")
local kitchen = {}
kevinGroup.house = { questContainer = { container = kitchen } }
kevinGroup.oddball.managerSpawned = false
kevinGroup.oddball.managerQuestReady = false
kevinGroup.oddball.managerAttempts = 8
SC.OddballSpiffo.pulse(kevinGroup, player, C.ms)
assert(kevinGroup.oddball.managerQuestReady and #kitchen == 1,
    "failed manager spawn must place the unique keys in kitchen storage")
redGroup.members["member-1"].actorId = nil
redGroup.recruitment = { status = "joined", joinedActorId = "red" }
local hasGutAction = false
for _, option in ipairs(SC.OddballRed.menuOptions(redGroup, player)) do
    if option.id == "gut_up" then hasGutAction = true end
end
assert(hasGutAction, "joined Red must remain addressable by companion UI")
local accepted = SC.OddballRed.action(redGroup, "hurt", player)
assert(accepted == true and redGroup.oddball.stage == "fleeing_to_horde",
    "a ranged hit must trigger Red's authored escape rather than faction hostility")
local fleeIntent = SC.OddballRed.intentFor(red, player, {}, redGroup)
assert(fleeIntent.mode == "red_flee_horde", "Red's escape must retain movement ownership")

-- A joined Red's UI order must own the companion until approach and the native
-- corpse study finish. Accepting the order alone must never grant the cloak.
red.inventory = { { fullType = "Base.KitchenKnife" } }
red.commands = { combatDoctrine = "stealth" }
redGroup.oddball.stage = "met"
redGroup.oddball.cloak.remainingHours = 0
red.x, red.y = 10, 10
player.x, player.y = 10, 7
local body = SC_TEST_CORPSE(12, 10, 0)
C.ms = 30000
C.hour = 2
local started, gutReason = SC.OddballRed.action(redGroup, "gut_up", player)
assert(started == true and gutReason == "gutting_started",
    "Gut up must acquire a supervised action after inventory and corpse preflight")
assert(SC.ActionSupervisor.current(red) ~= nil
    and SC.ActionSupervisor.current(red).spec.owner == "player_control",
    "the Gut up movement owner must hold Follow until the action ends")
assert(redGroup.oddball.cloak.remainingHours == 0,
    "the UI command itself must never grant a cloak")
local navBefore = C.nav
SC.OddballRed.pulseRecruited(redGroup, red, player, C.ms)
assert(C.nav == navBefore + 1 and C.lastTarget.x == 12,
    "the recruited pulse must navigate to the corpse")
assert(redGroup.oddball.cloak.remainingHours == 0,
    "approaching the corpse must not grant a cloak")
red.x, red.y = 11.25, 10
C.ms = C.ms + 2500
SC.OddballRed.pulseRecruited(redGroup, red, player, C.ms)
assert(C.lastMove and C.lastMove.action == "study_corpse",
    "arrival must start the native corpse study animation")
C.ms = C.ms + 5000
SC.OddballRed.pulseRecruited(redGroup, red, player, C.ms)
assert(redGroup.oddball.cloak.remainingHours == 0,
    "an active animation must not complete Gut up")
C.ms = C.ms + 5500
local renewed, renewalReason = SC.OddballRed.pulseRecruited(
    redGroup, red, player, C.ms)
assert(renewed == true and renewalReason == "gore_cloak_renewed"
    and redGroup.oddball.cloak.remainingHours == 18 and red.immunity == true,
    "verified animation must renew the native zombie cloak")
assert(red.modelRefreshes >= 2 and shirt.blood[bodyParts[2]] == 1,
    "Gut up must restore Red's blood-soaked appearance")
assert(redGroup.oddball.gutting == nil
    and SC.ActionSupervisor.current(red) == nil,
    "completion must release durable gutting state and movement owner")

-- Corpse and scraping tool are real preconditions; a missing item cannot
-- produce a deferred success or quietly renew the cloak later.
redGroup.oddball.cloak.remainingHours = 0
red.inventory = {}
local rejected, rejectReason = SC.OddballRed.action(redGroup, "gut_up", player)
assert(rejected == false and rejectReason == "scraping_tool_required"
    and redGroup.oddball.gutting == nil,
    "Gut up must reject a missing scraping tool before taking ownership: "
        .. tostring(rejectReason))
red.inventory = { { fullType = "Base.KitchenKnife" } }
body.square.bodies = {}
rejected, rejectReason = SC.OddballRed.action(redGroup, "gut_up", player)
assert(rejected == false and rejectReason == "nearby_zombie_corpse_required",
    "Gut up must reject a corpse removed before action start")
local interruptedBody = SC_TEST_CORPSE(12, 10, 0)
local blocker = { actor = red }
SC.ActionSupervisor.owners[red] = blocker
rejected, rejectReason = SC.OddballRed.action(redGroup, "gut_up", player)
assert(rejected == false and rejectReason == "actor_owned_by_other_action",
    "Gut up must preserve an existing companion action owner")
SC.ActionSupervisor.owners[red] = nil
started = SC.OddballRed.action(redGroup, "gut_up", player)
assert(started == true, "Gut up should begin once the owner is released")
C.ms = C.ms + 2500
SC.OddballRed.pulseRecruited(redGroup, red, player, C.ms)
assert(C.visual[red] ~= nil, "nearby corpse should start the native visual")
interruptedBody.square.bodies = {}
C.ms = C.ms + 2500
SC.OddballRed.pulseRecruited(redGroup, red, player, C.ms)
assert(redGroup.oddball.cloak.remainingHours == 0
    and redGroup.oddball.gutting == nil
    and SC.ActionSupervisor.current(red) == nil and C.visual[red] == nil,
    "losing the corpse mid-action must cancel the visual and withhold the cloak")

SC_TEST_REPORT = "STRANGE_FOLK_BEHAVIOR_PASS cloak rain target-release pose-freeze pose-step reveal red-gut-renewal"
