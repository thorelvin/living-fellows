-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.ComfortTestConfig = {}
SC.GameplayUtil = {
    config = function(key) return SC.ComfortTestConfig[key] end,
    nowMs = function() return SC.ComfortTestNow or 0 end,
    idOf = function(actor) return actor.id end,
    nameOf = function(actor) return actor.name or actor.id end,
    isValidActor = function(actor) return actor ~= nil end,
    isDead = function(actor) return actor.dead == true end,
    sameFloor = function() return true end,
    distance = function() return 1 end,
    stableHash = function() return 0 end,
    roomName = function() return SC.ComfortTestRoom end,
    squareOf = function() return {} end,
    characterStatValue = function() return 0 end,
    move = function(actor, _, intent)
        actor.lastIntent = intent
        actor.moves = (actor.moves or 0) + 1
        return true
    end,
    call = function(object, method, ...)
        if object == nil or type(object[method]) ~= "function" then return nil, false end
        local ok, value = pcall(object[method], object, ...)
        if not ok then return nil, false end
        return value, true
    end,
}

SC.Dialogue = {
    register = function() end,
    say = function(actor, topic)
        actor.lastTopic = topic
        return true
    end,
}
SC.Commands = { peek = function(actor) return actor.commands end }
SC.ActionSupervisor = { current = function() return nil end }
SC.BaseLife = { isInside = function() return false end }
