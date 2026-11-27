-- SPDX-License-Identifier: MIT
-- Subject scenarios use the same native-shaped fixture as the essential checks.
local f = assert(LivingFellows.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog = f.makeSquare, f.squares, f.movementLog
local squareKey = f.squareKey
function LivingFellows.__testCompanionWashing()
BloodBodyPartType = {
    MAX = { index = function() return 2 end },
    FromIndex = function(index) return index end,
}
local dirtyVisual = { blood = { [0] = 0.8, [1] = 0 }, dirt = { [0] = 0.2, [1] = 0 } }
function dirtyVisual:getBlood(part) return self.blood[part] or 0 end
function dirtyVisual:getDirt(part) return self.dirt[part] or 0 end
function dirtyVisual:setBlood(part, amount) self.blood[part] = amount end
function dirtyVisual:setDirt(part, amount) self.dirt[part] = amount end
local washSquare = cell:getGridSquare(-2, 5, 0)
local sink = { square = washSquare, fluid = 40 }
function sink:getSquare() return self.square end
function sink:getX() return self.square.x + 0.5 end
function sink:getY() return self.square.y + 0.5 end
function sink:getZ() return self.square.z end
function sink:getFluidAmount() return self.fluid end
function sink:isTaintedWater() return false end
function sink:useFluid(amount) self.fluid = self.fluid - amount end
function sink:transmitModData() self.transmitted = true end
washSquare.objects[#washSquare.objects + 1] = sink
-- Since 0.27.10 washing runs the stock timed actions through
-- SC.NativeActions.startDowntimeAction; their completion, water use and
-- cleaning are covered by tests/essential/native_care_harness.lua in the
-- release gate. Here only Downtime's own choice is checked: which wash,
-- at which source, for which item.
local createdNativeActions = LivingFellows.NativeActions == nil
local nativeActions = LivingFellows.NativeActions or {}
LivingFellows.NativeActions = nativeActions
local savedStartDowntime = nativeActions.startDowntimeAction
local startedCare = {}
nativeActions.startDowntimeAction = function(careActor, activity)
    startedCare[careActor] = activity
    return true, "native_care_started"
end
local washActor = actor("sc-wash-self", -2, 5, { humanVisual = dirtyVisual })
washActor.modData.SC_Order = "stay"
function washActor.inventory:getSoapList() return {} end
local washStarted, washKind = LivingFellows.Downtime.update(washActor, player, safeRuntime)
local washCare = startedCare[washActor]
check(washStarted == true and washKind == "wash_self" and washCare
    and washCare.kind == "wash_self" and washCare.object == sink,
    "safe idle companions start washing their body at a nearby clean water source")
LivingFellows.Downtime.cancel(washActor, "test_complete")

local dirtyJacket = item("Base.Jacket_LeatherWildRacoons", "Clothing", {
    bodyLocation = "Jacket", bloodLevel = 50, dirtiness = 25,
})
local washBagInventory = inventory({ dirtyJacket })
local washBag = item("Base.Bag_DuffelBag", "Container", {
    nestedInventory = washBagInventory, bagCapacity = 18, weightReduction = 65,
    bodyLocation = "Back", equipLocation = "Back",
})
local gearWashActor = actor("sc-wash-gear", -2, 5,
    { inventory = inventory({ washBag }) })
gearWashActor.modData.SC_Order = "stay"
function gearWashActor.inventory:getSoapList() return {} end
local gearWashStarted, gearWashKind = LivingFellows.Downtime.update(gearWashActor, player, safeRuntime)
local gearCare = startedCare[gearWashActor]
check(gearWashStarted == true and gearWashKind == "wash_equipment" and gearCare
    and gearCare.item == dirtyJacket and gearCare.object == sink,
    "downtime inventory inspection reaches inside bags and starts washing dirty equipment")
LivingFellows.Downtime.cancel(gearWashActor, "test_complete")
nativeActions.startDowntimeAction = savedStartDowntime
if createdNativeActions then LivingFellows.NativeActions = nil end

do
    local showerActivity = LivingFellows.Downtime._showerForTests()
    local savedInside = LivingFellows.BaseLife.isInside
    LivingFellows.BaseLife.isInside = function() return true end
    local showerVisual = {
        blood = { [0] = 0.8, [1] = 0 },
        dirt = { [0] = 0.2, [1] = 0 },
    }
    function showerVisual:getBlood(part) return self.blood[part] or 0 end
    function showerVisual:getDirt(part) return self.dirt[part] or 0 end
    function showerVisual:setBlood(part, amount) self.blood[part] = amount end
    function showerVisual:setDirt(part, amount) self.dirt[part] = amount end
    local showerActor = actor("sc-shower", -3, 5,
        { humanVisual = showerVisual })
    local shirt = item("Base.Shirt_FormalWhite", "Clothing",
        { bodyLocation = "Shirt" })
    local trousers = item("Base.Trousers", "Clothing",
        { bodyLocation = "Pants" })
    showerActor.inventory:AddItem(shirt)
    showerActor.inventory:AddItem(trousers)
    showerActor:setWornItem("Shirt", shirt)
    showerActor:setWornItem("Pants", trousers)
    local showerSquare = showerActor.square
    local fixture = { square = showerSquare, fluid = 20 }
    function fixture:getSquare() return self.square end
    function fixture:getFluidAmount() return self.fluid end
    function fixture:isTaintedWater() return false end
    function fixture:useFluid(amount) self.fluid = self.fluid - amount end
    function fixture:transmitModData() end
    function fixture:getSprite()
        return { getProperties = function()
            return { get = function(_, key)
                return key == "CustomName" and "Shower" or nil
            end }
        end }
    end
    showerSquare.objects[#showerSquare.objects + 1] = fixture
    registry[showerActor.id] = { actor = showerActor,
        state = { downtime = {} } }
    local activity = showerActivity(showerActor, {}, f.clock)
    check(activity and activity.kind == "shower" and activity.object == fixture,
        "a dirty camp companion selects an available shower")
    -- Since 0.27.11 undressing, dressing and the shower itself are native
    -- timed actions over several updates. Exact-slot removal, restoration,
    -- cancellation and save handling are checked in the release gate by
    -- tests/essential/native_clothing_harness.lua (completion by
    -- native_care_harness.lua).
    showerSquare.objects[#showerSquare.objects] = nil
    registry[showerActor.id] = nil
    LivingFellows.BaseLife.isInside = savedInside
end
end
LivingFellows.__testCompanionWashing()
LivingFellows.__testCompanionWashing = nil

function LivingFellows.__testCurtainHabits()
local curtainSquare = squares[squareKey(-4, 7, 0)]
curtainSquare.room = { name = "bedroom" }
local testCurtain = { __class = "IsoCurtain", square = curtainSquare, open = true }
function testCurtain:getSquare() return self.square end
function testCurtain:getX() return self.square.x end
function testCurtain:getY() return self.square.y end
function testCurtain:getZ() return self.square.z end
function testCurtain:IsOpen() return self.open end
function testCurtain:ToggleDoor(character)
    if self.noopToggle then return true end
    self.open = not self.open
end
curtainSquare.objects[#curtainSquare.objects + 1] = testCurtain
local curtainActor = actor("sc-curtain", -4, 7, {})
curtainActor.modData.SC_Order = "stay"
curtainActor.modData.SC_CombatDoctrine = "stealth"
registry[curtainActor.id] = curtainActor
local curtainThreat = { threatCount = 1, immediateCount = 1 }
local attemptedCurtain = LivingFellows.Downtime.considerCurtain(
    curtainActor, curtainThreat, f.clock)
check(not attemptedCurtain and testCurtain.open,
    "curtain habit never outranks an active zombie threat")

f.worldHour = 12
local stealthClosed = false
for _ = 1, 20 do
    f.clock = f.clock + 12001
    local closeAttempted, closeAccepted = LivingFellows.Downtime.considerCurtain(
        curtainActor, { threatCount = 0, immediateCount = 0 }, f.clock)
    if closeAttempted and closeAccepted and not testCurtain.open then stealthClosed = true break end
end
check(stealthClosed, "safe stealth downtime sometimes closes an open indoor curtain")

check(LivingFellows.Commands.issue(curtainActor.id, "set_combat_doctrine",
        { doctrine = "close_defense" }, player),
    "curtain fixture can leave stealth doctrine")
local openedCurtain = false
for _ = 1, 100 do
    f.clock = f.clock + 12001
    local openAttempted, openAccepted = LivingFellows.Downtime.considerCurtain(
        curtainActor,
        { threatCount = 0, immediateCount = 0 },
        f.clock
    )
    if openAttempted and openAccepted and testCurtain.open then openedCurtain = true break end
end
check(openedCurtain, "safe daylight cadence occasionally opens a nearby indoor curtain")
f.worldHour = 22
f.clock = f.clock + 45001
local nightAttempted, nightAccepted = LivingFellows.Downtime.considerCurtain(
    curtainActor,
    { threatCount = 0, immediateCount = 0 },
    f.clock
)
check(nightAttempted and nightAccepted and not testCurtain.open,
    "nighttime indoor curtain decision closes for concealment")
f.worldHour = 12

local farRoom = { name = "warehouse" }
local farActorSquare = squares[squareKey(-4, 6, 0)]
local farCurtainSquare = squares[squareKey(-1, 6, 0)]
farActorSquare.room, farCurtainSquare.room = farRoom, farRoom
local farCurtain = { __class = "IsoCurtain", square = farCurtainSquare, open = true }
function farCurtain:getSquare() return self.square end
function farCurtain:getX() return self.square.x end
function farCurtain:getY() return self.square.y end
function farCurtain:getZ() return self.square.z end
function farCurtain:IsOpen() return self.open end
function farCurtain:ToggleDoor(character) self.open = not self.open end
farCurtainSquare.objects[#farCurtainSquare.objects + 1] = farCurtain
local farCurtainActor = actor("sc-curtain-approach", -4, 6, {})
farCurtainActor.modData.SC_Order = "stay"
farCurtainActor.modData.SC_CombatDoctrine = "stealth"
registry[farCurtainActor.id] = farCurtainActor
local approachStarted = false
for _ = 1, 20 do
    f.clock = f.clock + 12001
    local attempted, accepted, reason = LivingFellows.Downtime.considerCurtain(
        farCurtainActor, { threatCount = 0, immediateCount = 0 }, f.clock)
    if attempted and accepted and reason == "approaching_curtain" then
        approachStarted = true
        break
    end
end
check(approachStarted and LivingFellows.Downtime.peek(farCurtainActor).curtainTask ~= nil
        and farCurtain.open,
    "a stealth companion reserves and walks toward an open curtain in the same building")
farCurtainActor.square, farCurtainActor.worldX, farCurtainActor.worldY = farCurtainSquare, nil, nil
local arrivedAttempted, arrivedAccepted = LivingFellows.Downtime.considerCurtain(
    farCurtainActor, { threatCount = 0, immediateCount = 0 }, f.clock + 100)
check(arrivedAttempted and arrivedAccepted and not farCurtain.open
        and LivingFellows.Downtime.peek(farCurtainActor).curtainTask == nil,
    "the reserved curtain is closed only after the companion physically arrives")

-- A path request can be accepted repeatedly without moving the actor. The
-- failed task must abandon this curtain for a while instead of selecting it
-- again at the next decision interval.
farCurtain.open = true
farCurtainActor.square, farCurtainActor.worldX, farCurtainActor.worldY =
    farActorSquare, nil, nil
f.worldHour = 22
f.clock = f.clock + 120001
local originalCurtainRequestAny = LivingFellows.Navigation.requestAny
local curtainApproachCalls = 0
LivingFellows.Navigation.requestAny = function(_, targets, _, intent)
    curtainApproachCalls = curtainApproachCalls + 1
    check(#targets > 0 and intent.environmentalTask == "curtain"
            and intent.requireSameSquare == true,
        "curtain uses actual accessible interaction squares")
    return true, "moving"
end
local stalledAttempted, stalledAccepted, stalledReason =
    LivingFellows.Downtime.considerCurtain(farCurtainActor,
        { threatCount = 0, immediateCount = 0 }, f.clock)
check(stalledAttempted and stalledAccepted and stalledReason == "approaching_curtain"
        and farCurtain.open,
    "curtain task keeps its target state while approach is pending")
local stalledDeadline = LivingFellows.Downtime.peek(farCurtainActor)
    .curtainTask.expiresAt
local expiredAttempted, expiredAccepted, expiredReason =
    LivingFellows.Downtime.considerCurtain(farCurtainActor,
        { threatCount = 0, immediateCount = 0 }, stalledDeadline)
check(expiredAttempted and not expiredAccepted
        and expiredReason == "curtain_approach_timeout"
        and LivingFellows.Downtime.peek(farCurtainActor).curtainTask == nil,
    "an accepted but stalled curtain approach expires cleanly")
local retryAttempted = LivingFellows.Downtime.considerCurtain(farCurtainActor,
    { threatCount = 0, immediateCount = 0 }, stalledDeadline + 12001)
check(not retryAttempted and curtainApproachCalls == 1,
    "the same unreachable curtain is not selected again immediately")
local laterAttempted, laterAccepted = LivingFellows.Downtime.considerCurtain(
    farCurtainActor, { threatCount = 0, immediateCount = 0 },
    stalledDeadline + 120001)
check(laterAttempted and laterAccepted and curtainApproachCalls == 2,
    "a curtain may be reconsidered after its failure cooldown")
LivingFellows.Downtime.cancel(farCurtainActor, "fixture_done")
LivingFellows.Navigation.requestAny = originalCurtainRequestAny
f.worldHour = 12

local noOpCurtainSquare = squares[squareKey(-5, 7, 0)]
noOpCurtainSquare.room = { name = "bedroom" }
local noOpCurtain = { __class = "IsoCurtain", square = noOpCurtainSquare, open = true, noopToggle = true }
function noOpCurtain:getSquare() return self.square end
function noOpCurtain:getX() return self.square.x end
function noOpCurtain:getY() return self.square.y end
function noOpCurtain:getZ() return self.square.z end
function noOpCurtain:IsOpen() return self.open end
function noOpCurtain:ToggleDoor(character) return true end
noOpCurtainSquare.objects[#noOpCurtainSquare.objects + 1] = noOpCurtain
local noOpCurtainActor = actor("sc-curtain-noop", -5, 7, {})
noOpCurtainActor.modData.SC_Order = "stay"
registry[noOpCurtainActor.id] = noOpCurtainActor
f.worldHour = 22
LivingFellows.Downtime.considerCurtain(
    noOpCurtainActor, { threatCount = 0, immediateCount = 0 }, f.clock)
f.clock = f.clock + 12001
local noOpCurtainAttempted, noOpCurtainAccepted = LivingFellows.Downtime.considerCurtain(
    noOpCurtainActor,
    { threatCount = 0, immediateCount = 0 },
    f.clock
)
check(noOpCurtainAttempted and not noOpCurtainAccepted and noOpCurtain.open,
    "curtain decision propagates a native no-op postcondition failure")
f.worldHour = 12

end
LivingFellows.__testCurtainHabits()
LivingFellows.__testCurtainHabits = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
