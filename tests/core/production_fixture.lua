-- SPDX-License-Identifier: MIT

-- Minimal Build 42 surfaces used by base production. Every fake keeps the
-- vanilla constructor and argument shape, so SCNativeActions runs its real
-- inventory preparation, queue retention and restore code. Completion
-- (perform) mirrors the vanilla complete() effect the production layer must
-- later prove from the world.

ItemTag = ItemTag or {}
ItemTag.CHOP_TREE = ItemTag.CHOP_TREE or { name = "CHOP_TREE", tag = "choptree" }
ItemTag.SAW = ItemTag.SAW or { name = "SAW", tag = "saw" }
ItemTag.DIG_GRAVE = ItemTag.DIG_GRAVE or { name = "DIG_GRAVE", tag = "diggrave" }

SC_PRODUCTION_CALLS = { chop = {}, handcraft = {}, bury = {}, fill = {}, build = {}, graves = {} }

function getSpecificPlayer()
    return nil
end

ArrayList = {}
function ArrayList.new()
    local list = { values = {} }
    function list:add(value)
        self.values[#self.values + 1] = value
        return true
    end
    function list:size() return #self.values end
    function list:get(index) return self.values[index + 1] end
    return list
end

ISChopTreeAction = ISBaseTimedAction:derive("ISChopTreeAction")

function ISChopTreeAction:new(character, tree)
    local action = ISBaseTimedAction.new(self, character)
    action.tree = tree
    action.maxTime = -1
    SC_PRODUCTION_CALLS.chop[#SC_PRODUCTION_CALLS.chop + 1] = action
    return action
end

function ISChopTreeAction:isValid()
    local primary = self.character:getPrimaryHandItem()
    return self.tree ~= nil and self.tree:getObjectIndex() >= 0 and primary ~= nil
        and primary:hasTag(ItemTag.CHOP_TREE) and not primary:isBroken()
end

function ISChopTreeAction:start()
    self.axe = self.character:getPrimaryHandItem()
end

function ISChopTreeAction:animEvent(event)
    if event == "ChopTree" and self.axe then
        self.hits = (self.hits or 0) + 1
        self.tree:WeaponHit(self.character, self.axe)
    end
end

SC_TEST_SAW_INPUTS = {}
local function sawInput(keep, index)
    local input = { keep = keep, index = index }
    function input:isKeep() return self.keep end
    return input
end
SC_TEST_SAW_INPUTS[1] = sawInput(false, 0)
SC_TEST_SAW_INPUTS[2] = sawInput(true, 1)
SC_TEST_SAW_RECIPE = { name = "SawLogs" }
function SC_TEST_SAW_RECIPE:getInputs() return SC_TEST_SAW_INPUTS end
function SC_TEST_SAW_RECIPE:getIndexForIO(input) return input.index end

function getScriptManager()
    local manager = {}
    function manager:getCraftRecipe(name)
        if name == "Base.SawLogs" or name == "SawLogs" then return SC_TEST_SAW_RECIPE end
        return nil
    end
    return manager
end

ISHandcraftAction = ISBaseTimedAction:derive("ISHandcraftAction")

function ISHandcraftAction:new(character, craftRecipe, containers, isoObject, craftBench,
    manualInputs, items, recipeItem, variableInputRatio, eatPercentage)
    local action = ISBaseTimedAction.new(self, character)
    action.craftRecipe, action.containers, action.manualInputs = craftRecipe, containers, manualInputs
    action.maxTime = 230
    SC_PRODUCTION_CALLS.handcraft[#SC_PRODUCTION_CALLS.handcraft + 1] = action
    return action
end

function ISHandcraftAction:isValid()
    return self.craftRecipe ~= nil
end

function ISHandcraftAction:start() end

-- Mirrors HandcraftLogic.performCurrentRecipe + Actions.addOrDropItem: the
-- pinned consumed input leaves the inventory and three planks arrive.
function ISHandcraftAction:perform()
    if SC_TEST_SAW_FAILS ~= true then
        for _, input in ipairs(SC_TEST_SAW_INPUTS) do
            if not input:isKeep() then
                local list = self.manualInputs and self.manualInputs[input.index]
                local log = list and list:get(0) or nil
                if log and log.container then log.container:Remove(log) end
            end
        end
        local inventory = self.character:getInventory()
        for _ = 1, 3 do inventory:AddItem("Base.Plank") end
    end
    ISBaseTimedAction.perform(self)
end

ISEmptyGraves = {}
ISEmptyGraves.__index = ISEmptyGraves

function ISEmptyGraves:new(sprite, sprite2, northSprite, northSprite2, tool)
    local graves = setmetatable({
        sprite = sprite, sprite2 = sprite2, northSprite = northSprite,
        northSprite2 = northSprite2, equipBothHandItem = tool, maxTime = 150,
        noNeedHammer = true, north = false,
    }, self)
    SC_PRODUCTION_CALLS.graves[#SC_PRODUCTION_CALLS.graves + 1] = graves
    return graves
end

function ISEmptyGraves:getSprite()
    return self.north and self.northSprite or self.sprite
end

function ISEmptyGraves:isValid(square)
    return square ~= nil and square.diggable ~= false
end

function ISEmptyGraves:create(x, y, z, north, sprite)
    self.createdBy = self.character
    if SC_TEST_CREATE_GRAVE then SC_TEST_CREATE_GRAVE(x, y, z, north, self.halfOnly) end
end

function ISEmptyGraves.getMaxCorpses()
    return 5
end

-- The shared work fixture supplies ISBuildAction:derive. Give it the
-- timed-action lifecycle Build 42 inherits from ISBaseTimedAction.
ISBuildAction = ISBuildAction or {}
setmetatable(ISBuildAction, { __index = ISBaseTimedAction })

function ISBuildAction:new(character, item, x, y, z, north, spriteName, time)
    local action = ISBaseTimedAction.new(self, character)
    action.item, action.x, action.y, action.z = item, x, y, z
    action.north, action.spriteName, action.maxTime = north, spriteName, time
    SC_PRODUCTION_CALLS.build[#SC_PRODUCTION_CALLS.build + 1] = action
    return action
end

function ISBuildAction:isValid()
    return true
end

function ISBuildAction:start()
    local number = self.character:getPlayerNum()
    self.bridgedPlayer = getSpecificPlayer(number)
end

function ISBuildAction:perform()
    self.item.character = self.character
    self.item:create(self.x, self.y, self.z, self.north, self.spriteName)
    ISBaseTimedAction.perform(self)
end

local function graveHalves(grave)
    local result = { grave }
    for _, other in ipairs(SC_TEST_GRAVE_PARTNERS and SC_TEST_GRAVE_PARTNERS(grave) or {}) do
        result[#result + 1] = other
    end
    return result
end

ISBuryCorpse = ISBaseTimedAction:derive("ISBuryCorpse")

function ISBuryCorpse:new(character, grave, primaryHandItem, bodySquare)
    local action = ISBaseTimedAction.new(self, character)
    action.grave, action.primaryHandItem, action.bodySquare = grave, primaryHandItem, bodySquare
    action.maxTime = 300
    SC_PRODUCTION_CALLS.bury[#SC_PRODUCTION_CALLS.bury + 1] = action
    return action
end

function ISBuryCorpse:isValid()
    return true
end

function ISBuryCorpse:start() end

-- Vanilla complete(): remove the body this character tagged, count it into
-- both grave halves. A body tagged by someone else is never touched.
function ISBuryCorpse:perform()
    local playerId = self.character:getPlayerNum()
    local bodies = self.bodySquare.staticMoving
    local target, targetIndex
    for index = #bodies, 1, -1 do
        local body = bodies[index]
        if body.modData.lastPlayerGrabbed ~= nil and body.modData.lastPlayerGrabbed == playerId then
            target, targetIndex = body, index
        end
    end
    if target then
        table.remove(bodies, targetIndex)
        for _, half in ipairs(graveHalves(self.grave)) do
            half.modData.corpses = half.modData.corpses + 1
        end
    end
    ISBaseTimedAction.perform(self)
end

ISFillGrave = ISBaseTimedAction:derive("ISFillGrave")

function ISFillGrave:new(character, graves, shovel)
    local action = ISBaseTimedAction.new(self, character)
    action.graves, action.item = graves, shovel
    action.maxTime = 150
    SC_PRODUCTION_CALLS.fill[#SC_PRODUCTION_CALLS.fill + 1] = action
    return action
end

function ISFillGrave:isValid()
    return true
end

function ISFillGrave:start() end

function ISFillGrave:perform()
    for _, half in ipairs(graveHalves(self.graves)) do half.modData.filled = true end
    ISBaseTimedAction.perform(self)
end

return true
