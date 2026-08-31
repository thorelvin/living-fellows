-- SPDX-License-Identifier: MIT

function require() return true end

SC_TEST_CLOCK = 1000
function getTimestampMs() return SC_TEST_CLOCK end
function isClient() return false end
function isServer() return false end
function getCell() return nil end
function ZombRand(minimum, maximum)
    if maximum == nil then return 0 end
    return minimum
end
function instanceof(value, className)
    return type(value) == "table" and value.__class == className
end

CharacterStat = {
    HUNGER = { name = "HUNGER" },
    THIRST = { name = "THIRST" },
}

CharacterActionAnims = {
    Bandage = { name = "Bandage" },
    Craft = { name = "Craft" },
    Read = { name = "Read" },
}

ISBaseTimedAction = {}

function ISBaseTimedAction:derive(name)
    local class = { Type = name }
    setmetatable(class, { __index = self })
    class.__index = class
    return class
end

function ISBaseTimedAction.new(class, character)
    local value = { character = character, maxTime = -1 }
    setmetatable(value, { __index = class })
    return value
end

function ISBaseTimedAction:setActionAnim(animation)
    self.animationStarted = animation
    self.character.lastAnimation = animation
end

function ISBaseTimedAction:setAnimVariable(key, value)
    self.character.lastAnimVariable = { key = key, value = value }
end

function ISBaseTimedAction:setOverrideHandModels(primary, secondary)
    self.primaryModel = primary
    self.secondaryModel = secondary
end

function ISBaseTimedAction:begin()
    local action = { started = true }
    function action:isStarted() return self.started == true end
    function action:forceStop() self.started = false end
    self.action = action
    self.character.characterActions:add(action)
    self:start()
end

function ISBaseTimedAction:isStarted()
    return self.action ~= nil and self.action:isStarted()
end

function ISBaseTimedAction:forceStop()
    if self.action then self.action:forceStop() end
    local actions = self.character and self.character.characterActions
    if actions and actions.remove then actions:remove(self.action) end
end

function ISBaseTimedAction.stop(self)
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    queue.queue = {}
    queue.current = nil
    local actions = self.character and self.character.characterActions
    if actions and actions.remove then actions:remove(self.action) end
end

function ISBaseTimedAction.perform(self)
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    queue:removeFromQueue(self)
    queue.current = queue.queue[1]
    local actions = self.character and self.character.characterActions
    if actions and actions.remove then actions:remove(self.action) end
end

ISTimedActionQueue = { queues = setmetatable({}, { __mode = "k" }) }

function ISTimedActionQueue.getTimedActionQueue(character)
    local queue = ISTimedActionQueue.queues[character]
    if queue == nil then
        queue = { character = character, queue = {}, current = nil }
        function queue:removeFromQueue(action)
            for index, candidate in ipairs(self.queue) do
                if candidate == action then table.remove(self.queue, index) return end
            end
        end
        ISTimedActionQueue.queues[character] = queue
    end
    return queue
end

function ISTimedActionQueue.add(action)
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
    table.insert(queue.queue, action)
    if queue.current == nil then
        queue.current = action
        action:begin()
    end
    return queue
end
