-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local MedicalUI = assert(SC.MedicalUI)
local prior = {
    Actor = SC.Actor, Registry = SC.Registry, Commands = SC.Commands,
    UI = SC.UI, GameplayUtil = SC.GameplayUtil,
    ISMedicalCheckAction = ISMedicalCheckAction,
    ISTimedActionQueue = ISTimedActionQueue,
    Events = Events, getTimestampMs = getTimestampMs,
}

local clock = 10000
getTimestampMs = function() return clock end
local square = { z = 0 }
function square:getZ() return self.z end
local actor = { x = 10, y = 10, square = square }
function actor:getSquare() return self.square end
function actor:getX() return self.x end
function actor:getY() return self.y end
function actor:getZ() return self.square.z end
function actor:isDead() return false end
local doctor = { distance = 1.5, square = square }
function doctor:getSquare() return self.square end
function doctor:DistTo(subject) assert(subject == actor); return self.distance end
function doctor:isDead() return false end

local record = { actor = actor, recruited = true }
SC.Actor = { isCompanion = function(subject) return subject == actor end }
SC.Registry = {
    idOf = function(subject) return subject == actor and "sc-medical-test" or nil end,
    byId = function(id) return id == "sc-medical-test" and record or nil end,
}
local starts, ends, restored = 0, 0, 0
local held = false
SC.Commands = {
    beginTemporaryStay = function(subject, reason)
        assert(subject == actor and reason == "companion_medical_check")
        starts = starts + 1
        held = true
        return { serial = starts }, "temporary_stay"
    end,
    endTemporaryStay = function(subject, token)
        assert(subject == actor and type(token) == "table")
        ends = ends + 1
        held = false
        return true
    end,
    isTemporaryStay = function(subject) return subject == actor and held end,
}
SC.UI = { restoreInventory = function() restored = restored + 1 end }
SC.GameplayUtil = nil
local windows = {}
ISMedicalCheckAction = {
    new = function(self, character, patient)
        assert(character == doctor and patient == actor)
        return { character = character, otherPlayer = patient }
    end,
    getHealthWindowForPlayer = function(patient) return windows[patient] end,
}
local queued
ISTimedActionQueue = {
    add = function(action) queued = action; return { queue = { action } } end,
    hasAction = function(action) return queued == action end,
}
Events = { OnTick = {
    Add = function() error("medical check must use the central tick") end,
    Remove = function() error("medical check must use the central tick") end,
} }

local opened, reason = MedicalUI.open(actor, doctor)
assert(opened == true and reason == "health_opened")
assert(starts == 1 and restored == 1 and queued.otherPlayer == actor)
assert(MedicalUI.current().doctor == doctor)

windows[actor] = {
    nested = { character = actor, otherPlayer = doctor },
    getIsVisible = function() return true end,
}
MedicalUI.maintain()
assert(MedicalUI.current().phase == "open")
assert(MedicalUI.open(actor, doctor) == true and starts == 1,
    "repeated check should use the open session")

windows[actor].getIsVisible = function() return false end
MedicalUI.maintain()
assert(MedicalUI.current() == nil and ends == 1,
    "closing the panel must release the stay")

doctor.distance = 5
opened, reason = MedicalUI.open(actor, doctor)
assert(opened == false and reason == "UI_SC_Disabled_TooFar")
local available, availabilityReason, range = MedicalUI.availability(actor, doctor)
assert(available == false and availabilityReason == "UI_SC_Disabled_TooFar"
    and range == MedicalUI.RANGE)
doctor.distance = 1
record.recruited = false
opened, reason = MedicalUI.open(actor, doctor)
assert(opened == true and reason == "health_opened" and starts == 2,
    "unrecruited rescue survivors can be examined and treated")
MedicalUI.close("test_closed")
assert(ends == 2)
record.recruited = true
windows[actor] = nil
opened = MedicalUI.open(actor, doctor)
assert(opened == true and starts == 3)
held = false -- A real order superseded the medical stay.
MedicalUI.maintain()
assert(MedicalUI.current() == nil and ends == 3,
    "a superseded stay must not trap the companion")

SC.Actor, SC.Registry, SC.Commands = prior.Actor, prior.Registry, prior.Commands
SC.UI, SC.GameplayUtil = prior.UI, prior.GameplayUtil
ISMedicalCheckAction, ISTimedActionQueue = prior.ISMedicalCheckAction,
    prior.ISTimedActionQueue
Events, getTimestampMs = prior.Events, prior.getTimestampMs
print("SCMedicalUI tests passed")
