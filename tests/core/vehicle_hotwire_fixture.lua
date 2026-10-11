-- SPDX-License-Identifier: MIT
-- The hotwire order must board through the normal driver path, use the
-- game's attempt API, and leave the car without creating a key.
SurvivorCompanion = {}
local SC = SurvivorCompanion
clock, boards, exits, attempts = 0, 0, 0, 0
Perks = { Electricity = "electrical", Mechanics = "mechanics" }
CharacterTrait = { BURGLAR = "burglar" }
SC.Call = { method = function(object, name, ...)
    if not object or type(object[name]) ~= "function" then return false end
    local ok, value = pcall(object[name], object, ...)
    return ok, value
end }
SC.GameplayUtil = { nowMs = function() return clock end }
SC.Vehicle = {
    isStationary = function() return true end,
    boardingSquares = function() return { {} } end,
    exit = function(actor, car)
        exits = exits + 1
        actor.car, car.driver = nil, nil
        return true
    end,
    cancelTransaction = function() return true end,
}
SC.ExpeditionPrototype = { isMember = function() return false end }
SC.ExpeditionCar = { boardMember = function(actor, order)
    assert(order.seat == 0 and order.hotwire == true)
    boards = boards + 1
    actor.car, order.car.driver = order.car, actor
    return true
end }
SC.BaseWork = { cancel = function() return true end }
SC.NativeActions = { interruptOwnedActivity = function() return true end }
actor = {
    electrical = 1, mechanics = 2, burglar = false, car = nil,
    getX = function() return 0 end, getY = function() return 0 end,
    getZ = function() return 0 end,
    getVehicle = function(self) return self.car end,
    getPerkLevel = function(self, perk) return self[perk] end,
    hasTrait = function(self, trait) return self[trait] end,
}
player = { getVehicle = function() return nil end,
    getX = function() return 1 end, getY = function() return 0 end,
    getZ = function() return 0 end,
    setHaloNote = function(self, note) self.note = note end }
car = {
    hotwired = false, driver = nil,
    isHotwired = function(self) return self.hotwired end,
    isHotwiredBroken = function() return false end,
    isEngineRunning = function() return false end,
    getDriver = function(self) return self.driver end,
    tryHotwire = function(self, level)
        attempts = attempts + 1
        assert(level == 1)
        self.hotwired = true
    end,
}
