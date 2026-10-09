-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local actor = { id = "sc-nickname-display" }
local descriptor = {}
function descriptor:getForename() return "Sarah" end
function descriptor:getSurname() return "Shaw" end
function actor:getDescriptor() return descriptor end
function actor:getFullName() return "Sarah Shaw" end

local record = {
    id = actor.id, actor = actor,
    identity = { forename = "Sarah", surname = "Shaw", gender = "female" },
}
SC.Registry = {
    idOf = function(value) return value == actor and actor.id or nil end,
    byId = function(id) return id == actor.id and record or nil end,
}
local settings = { showNicknames = true }
SC.UI = { getSettings = function() return settings end }

local accepted = SC.Names.setNickname(record, "Doc", "player", true)
assert(accepted == true, "nickname assignment failed")
assert(SC.UIBridge.borrowedInventoryLabel(actor) == 'Sarah "Doc" Shaw',
    "companion inventory label must include the public nickname")

SC.GameplayUtil = {
    config = function() return nil end,
    idOf = function(value) return value.id end,
    nameOf = function(value) return value == actor and "Sarah Shaw" or "Taylor Reed" end,
    nowMs = function() return 100000 end,
}
SC.Community = {
    relation = function() return { familiarity = 75, opinion = 30, tension = 0 } end,
}
local spoken
SC.Dialogue = {
    register = function() return true end,
    say = function(_speaker, topic, _target, arguments, settings)
        spoken = { topic = topic, arguments = arguments, settings = settings }
        return true
    end,
}
local speaker = { id = "sc-nickname-speaker" }
assert(SC.Banter.crowdYield(speaker, actor, 100000) == true,
    "urgent banter should speak once")
assert(spoken.topic == "banter.crowd.yield" and spoken.arguments[1] == "Doc"
    and type(spoken.settings.salt) == "string",
    "urgent banter must pass the nickname and stable salt to dialogue")
assert(SC.Banter.crowdYield(speaker, actor, 100001) == false,
    "urgent nickname speech must preserve its cooldown")

settings.showNicknames = false
SC.UIBridge.invalidateNearbyInventoryLabels()
assert(SC.UIBridge.borrowedInventoryLabel(actor) == "Sarah Shaw",
    "panel preference must suppress nickname in the inventory label")
settings.showNicknames = true
assert(SC.Names.clearNickname(record) == true, "nickname clear failed")
assert(SC.UIBridge.borrowedInventoryLabel(actor) == "Sarah Shaw",
    "clearing the nickname must restore the identity label")

print("NICKNAME_DISPLAY_KAHLUA_PASS checks=7")
