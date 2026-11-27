-- SPDX-License-Identifier: MIT
local SC = LivingFellows
local F = { roofReady = true, carSqlId = 14 }
SC.EvacuationFixture = F
F.joy = { x = 1, y = 1, z = 0, items = {} }
F.brock = { x = 2, y = 1, z = 0, items = {} }
F.player = { x = 1, y = 2, z = 0, items = {} }
local ids = { joy = F.joy, brock = F.brock }
F.group = { id = "test-evacuation", lifecycle = "settled",
    members = { { actorId = "joy", alive = true }, { actorId = "brock", alive = true } },
    oddball = { id = "evacuation", stage = "unmet", site = { memberSpawns = { F.joy, F.brock } } } }
F.story = F.group.oddball

local leg = {
    setFractureTime = function(self, time) self.fracture = time end,
    getFractureTime = function(self) return self.fracture end,
    setScratched = function(self, scratched) self.scratch = scratched end,
    setBleedingTime = function(self, value) self.bleeding = value end,
}
F.leg = leg
BodyPartType = { LowerLeg_L = "leg" }
F.brock.getBodyDamage = function()
    return { getBodyPart = function(_, part) return part == "leg" and leg or nil end }
end
function getText(key, ...) return key end
SC.Registry = { byId = function(id) return ids[id] and { actor = ids[id] } end }
SC.GameplayUtil = {
    call = function(object, method, ...)
        if object and type(object[method]) == "function" then return object[method](object, ...), true end
        return nil, false
    end,
    position = function(point) if point then return point.x, point.y, point.z end end,
    distance = function(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end,
    canSee = function(player) return player.visible ~= false end,
    inventory = function(actor) return actor and actor.items end,
    inventoryItemsDeep = function(items) return items end,
    isValidActor = function(actor) return actor ~= nil end,
    isDead = function(actor) return actor.dead == true end,
    modData = function(item) return item.data end,
    itemType = function(item) return item.kind end,
    itemStableId = function(item) return item and item.id end,
    addItem = function(items, kind)
        F.itemCount = (F.itemCount or 0) + 1
        local item = { kind = kind, data = {}, id = "lf-item:" .. F.itemCount }
        items[#items + 1] = item
        return item
    end,
    transferItemVerified = function(source, destination, item)
        if F.interruptItem == item.id then return false, "fixture_transfer_interrupted" end
        for index, candidate in ipairs(source) do
            if candidate == item then
                table.remove(source, index)
                destination[#destination + 1] = item
                return true
            end
        end
        return false
    end,
    say = function(actor, line) actor.line = line end,
}
SC.OddballEvacuationShelter = {
    siteFields = {}, claims = {},
    onJoySpawn = function() return true end,
    pulse = function() return F.roofReady end,
    release = function() F.shelterReleased = true end,
    validate = function() return true end,
}
SC.OddballEvacuationVehicle = {
    candidate = function() return { sqlId = F.carSqlId, label = "Fixture car", distance = 9 } end,
    accept = function(group, _, sqlId)
        if sqlId ~= F.carSqlId then return false end
        group.oddball.stage = "boarding"
        group.oddball.vehicle = { sqlId = sqlId }
        return true
    end,
    pulse = function()
        F.vehiclePulses = (F.vehiclePulses or 0) + 1
        return F.vehicleStatus or "pending"
    end,
    cancel = function(group) group.oddball.vehicle = nil return true end,
    validate = function() return true end,
    flush = function() F.flushed = true end,
}
SC.Actor = {
    remove = function(actor)
        for id, value in pairs(ids) do
            if actor == value then ids[id] = nil return true end
        end
        return false
    end,
}
SC.Persistence = { retirePendingFactionActor = function() return true end }
SC.TaxiService = { outsideViews = function() return not F.crewVisible end }
SC.Factions = {
    retireOddballMembers = function(group, stage)
        if ids.joy or ids.brock then return false end
        group.oddball.stage, group.lifecycle = stage, "destroyed"
        return true
    end,
}
