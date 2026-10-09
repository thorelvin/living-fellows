-- SPDX-License-Identifier: MIT

SurvivorCompanion = {}
local SC = SurvivorCompanion

SC.StableValue = { copyStrict = function(value) return value end }
SC.NativeList = { size = function() return 0 end, get = function() return nil end }
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    config = function() return nil end,
    idOf = function(value) return value and value.id end,
    nameOf = function(value) return value and value.rawName end,
    inventory = function(value) return value and value.inventory end,
    itemName = function(value) return value:getDisplayName() end,
    loadedSquare = function(point) return point.square end,
    modData = function(value) return value.data end,
    squareObjects = function(square, callback)
        for _, object in ipairs(square.objects) do
            if callback(object) == false then break end
        end
    end,
    call = function(object, method, ...)
        local callback = object and object[method]
        if type(callback) ~= "function" then return nil, false end
        return callback(object, ...), true
    end,
    transferItem = function(source, destination, item)
        for index, value in ipairs(source) do
            if value == item then
                table.remove(source, index)
                destination[#destination + 1] = item
                return true
            end
        end
        return false
    end,
}

local memorial = {}
SC.BaseLife = {
    completeJob = function(id, actorId, result)
        SC_TEST_GRAVE_JOB_COMPLETED = { id, actorId, result }
        return true
    end,
    storageRows = function(category)
        return category == "memorial" and { { id = "storage:1" } } or {}
    end,
    resolveContainer = function() return memorial end,
    noteHistory = function() end,
}
SC_TEST_MEMORIAL_CONTAINER = memorial
SC.Commands = { export = function(subject)
    return { possessions = { keepsake = { key = subject.id .. ":keepsake" } } }
end }
SC.PersonalItems = { find = function(subject) return subject.inventory[1] end }
SC.Names = { displayName = function(subject)
    return subject.displayName
end }
SC.Registry = { byId = function(id)
    return SC_TEST_RECIPIENT and SC_TEST_RECIPIENT.id == id
        and { actor = SC_TEST_RECIPIENT } or nil
end }

ISBuildAction = { derive = function(self)
    return setmetatable({}, { __index = self })
end }
