-- SPDX-License-Identifier: MIT
-- Narrow world fixture for the real downtime and action-supervisor controllers.
function require() return true end
SC_READING_CLOCK = 1000
function getTimestampMs() return SC_READING_CLOCK end
SC_READING_RANDOM = { values = {}, calls = 0 }
function ZombRand(low, high)
    SC_READING_RANDOM.calls = SC_READING_RANDOM.calls + 1
    SC_READING_RANDOM.low, SC_READING_RANDOM.high = low, high
    return table.remove(SC_READING_RANDOM.values, 1)
        or math.floor((low + high - 1) / 2)
end
CharacterTrait = { ILLITERATE = "ILLITERATE" }
ItemTag = { PICTUREBOOK = "PICTUREBOOK", PICTURE = "PICTURE" }
local SC = SurvivorCompanion
SC.Background = {}
local function call(object, method, ...)
    if object and type(object[method]) == "function" then
        return object[method](object, ...), true
    end
    return nil, false
end
local function copy(value)
    local result = {}
    for key, child in pairs(value or {}) do result[key] = child end
    return result
end
function SC_READING_INVENTORY(items)
    local result = { items = items or {} }
    for _, item in ipairs(result.items) do item.container = result end
    function result:getItems() return self.items end
    return result
end
function SC_READING_BOOK(id, pages)
    local result = { id = id, pages = pages or 100, data = {} }
    function result:getFullType() return "Base.Book" .. self.id end
    function result:getDisplayName() return self:getFullType() end
    function result:getCategory() return "Literature" end
    function result:getNumberOfPages() return self.pages end
    function result:getModData() return self.data end
    function result:getContainer() return self.container end
    function result:setAlreadyReadPages(pagesRead) self.pagesRead = pagesRead end
    function result:hasTag(tag) return self.tags and self.tags[tag] == true end
    return result
end
function SC_READING_ACTOR(id, books)
    local result = { id = id, data = { SC_Id = id }, x = 10.5, y = 10.5, z = 0,
        inventory = SC_READING_INVENTORY(books),
        commands = { recruited = true, order = "stay", commandSerial = 0 } }
    function result:getModData() return self.data end
    function result:getX() return self.x end
    function result:getY() return self.y end
    function result:getZ() return self.z end
    function result:getVehicle() return nil end
    function result:isDead() return false end
    function result:isAsleep() return false end
    function result:hasTrait(trait) return self.traits and self.traits[trait] == true end
    function result:setAlreadyReadPages(itemType, pagesRead)
        self.data.SC_ReadingPages = self.data.SC_ReadingPages or {}
        self.data.SC_ReadingPages[itemType] = pagesRead
    end
    function result:ReadLiterature(item) self.finishedTitle = item end
    return result
end
local function contains(container, item)
    for _, candidate in ipairs(container and container.items or {}) do
        if candidate == item then return true end
    end
    return false
end
SC.GameplayUtil = {
    config = function(key) return SC.Config.get(key) end,
    nowMs = function() return SC_READING_CLOCK end,
    call = call, copyShallow = copy,
    position = function(value) return value.x, value.y, value.z end,
    idOf = function(value) return value.id end,
    itemType = function(value) return value:getFullType() end,
    itemName = function(value) return value:getDisplayName() end,
    inventory = function(value) return value.inventory end,
    inventoryItems = function(value) return value.items end,
    inventoryContains = contains,
    squareOf = function(value) return value.square or value end,
    isValidActor = function(value) return value ~= nil end,
    isDead = function() return false end,
    actorState = function(_, runtime) return runtime or {} end,
    clamp = function(value, low, high) return math.max(low, math.min(high, value)) end,
    characterStatValue = function(_, _, fallback) return fallback or 0 end,
    directInteractionAccess = function() return true, {} end,
    itemHasTag = function(value, tag) return value:hasTag(tag) end,
    stop = function() return true end,
    move = function(actor, _, intent)
        actor.lastIntent = intent
        actor.visual = { action = intent.action, at = SC_READING_CLOCK,
            duration = intent.durationMs }
        return true
    end,
    transferItemVerified = function(source, destination, item)
        for index, candidate in ipairs(source.items) do
            if candidate == item then
                table.remove(source.items, index)
                destination.items[#destination.items + 1] = item
                item.container = destination
                return true
            end
        end
        return false, "source_missing"
    end,
}
SC.Commands = {
    peek = function(actor) return actor.commands end,
    noteDowntime = function(actor, fact) actor.commands.lastDowntime = fact end,
}
SC.NativeActions = {
    activityStatus = function() return "none" end,
    visualStatus = function(actor)
        local visual = actor.visual
        if not visual then return "none" end
        return not visual.stalled and SC_READING_CLOCK - visual.at >= visual.duration
            and "completed" or "active"
    end,
    clearVisual = function(actor) actor.visual = nil return true end,
    cancelVisual = function(actor) actor.visual = nil return true end,
    seatingStatus = function() return "standing" end,
    leaveSeating = function() return true end,
    noteResult = function() return true end,
}
