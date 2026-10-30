-- SPDX-License-Identifier: MIT
-- Build 42.21's ISBarricadeAction:isValid tests hasEquippedTag(ItemType.HAMMER),
-- and ItemType has no HAMMER field. This fake keeps that line, so the stock check
-- fails here for the same reason it fails in the game.
local SC = SurvivorCompanion
local Actions, checks = SC.NativeActions, 0
local function check(value, message)
    checks = checks + 1
    assert(value, "barricade action " .. checks .. ": " .. message)
end

ItemTag = { HAMMER = "tag:hammer" }
ItemType = {}
ISTimedActionQueue = { queues = {} }
function ISTimedActionQueue.getTimedActionQueue(actor)
    ISTimedActionQueue.queues[actor] = ISTimedActionQueue.queues[actor] or { queue = {} }
    return ISTimedActionQueue.queues[actor]
end
function ISTimedActionQueue.add(action)
    local queue = ISTimedActionQueue.getTimedActionQueue(action.character)
    queue.current = queue.current or action
    queue.queue[#queue.queue + 1] = action
end

ISBarricadeAction = {}
ISBarricadeAction.__index = ISBarricadeAction
-- The real base class has this method. A truthiness check mistakes the
-- inherited function for ISBarricadeAction:start()'s later boolean flag.
function ISBarricadeAction:isStarted() return false end
function ISBarricadeAction:new(character, item, isMetal, isMetalBar)
    return setmetatable({ character = character, item = item,
        isMetal = isMetal, isMetalBar = isMetalBar }, self)
end
function ISBarricadeAction:isValid()
    local barricade = self.item:getBarricadeForCharacter(self.character)
    if barricade and not barricade:canAddPlank() then return false end
    if not self.character:hasEquippedTag(ItemType.HAMMER) then return false end
    return true
end

local function makeItem(kind, tags)
    local item = { kind = kind, tags = tags or {} }
    function item:getType() return self.kind end
    function item:hasTag(tag) return self.tags[tag] == true end
    function item:isBroken() return false end
    function item:getContainer() return self.container end
    return item
end

local function makeWorker(contents)
    local worker = { hands = {} }
    local inventory = { items = {} }
    function inventory:AddItem(item)
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function inventory:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then table.remove(self.items, index) return true end
        end
        return false
    end
    function inventory:getFirstTagEvalRecurse(tag)
        for _, item in ipairs(self.items) do if item:hasTag(tag) then return item end end
    end
    function inventory:getFirstTypeRecurse(kind)
        for _, item in ipairs(self.items) do if item:getType() == kind then return item end end
    end
    function inventory:getSomeTypeRecurse(kind, count)
        local found = {}
        for _, item in ipairs(self.items) do
            if item:getType() == kind and #found < count then found[#found + 1] = item end
        end
        return found
    end
    function inventory:getItemCount(fullType)
        local kind, count = string.gsub(fullType, "^Base%.", ""), 0
        for _, item in ipairs(self.items) do if item:getType() == kind then count = count + 1 end end
        return count
    end
    for _, item in ipairs(contents) do inventory:AddItem(item) end
    function worker:getInventory() return inventory end
    function worker:getPrimaryHandItem() return self.hands.primary end
    function worker:getSecondaryHandItem() return self.hands.secondary end
    function worker:setPrimaryHandItem(item) self.hands.primary = item end
    function worker:setSecondaryHandItem(item) self.hands.secondary = item end
    function worker:hasEquippedTag(tag)
        local primary, secondary = self.hands.primary, self.hands.secondary
        return tag ~= nil and ((primary and primary:hasTag(tag)) or (secondary and secondary:hasTag(tag))) or false
    end
    function worker:hasEquipped(kind)
        local primary, secondary = self.hands.primary, self.hands.secondary
        return (primary and primary:getType() == kind) or (secondary and secondary:getType() == kind) or false
    end
    return worker
end

local function kit()
    return { makeItem("Hammer", { [ItemTag.HAMMER] = true }), makeItem("Plank"),
        makeItem("Nails"), makeItem("Nails") }
end

local function window()
    local value = { __class = "IsoWindow", planks = 0, open = false, index = 3 }
    function value:getObjectIndex() return self.index end
    function value:IsOpen() return self.open end
    function value:getBarricadeForCharacter() return self.barricade end
    return value
end

local provider = { directNative = true }
local start = Actions._startBarricadeForTests

local worker, target = makeWorker(kit()), window()
local started, reason = start(worker, { object = target }, provider)
check(started == true, "a worker holding a full kit starts boarding the window: " .. tostring(reason))
local action = ISTimedActionQueue.getTimedActionQueue(worker).current
check(action and action:isValid() == true, "the action stays valid every tick it runs")
check(worker:getPrimaryHandItem():getType() == "Hammer" and worker:getSecondaryHandItem():getType() == "Plank",
    "the worker holds the hammer and the plank the action will use")

worker.hands.primary = nil
check(action:isValid() == false, "putting the hammer away ends the action")
worker.hands.primary = worker:getInventory():getFirstTagEvalRecurse(ItemTag.HAMMER)
worker.hands.secondary = nil
check(action:isValid() == false, "dropping the plank ends the action")
worker.hands.secondary = worker:getInventory():getFirstTypeRecurse("Plank")
local nail = worker:getInventory():getFirstTypeRecurse("Nails")
worker:getInventory():Remove(nail)
check(action:isValid() == false, "a worker with too few nails stops")
worker:getInventory():AddItem(nail)
target.barricade = { canAddPlank = function() return false end }
check(action:isValid() == false, "a barricade with no room for another plank ends the action")
target.barricade = nil
target.__class = "IsoDoor"
action.isStarted, target.open = true, true
check(action:isValid() == false, "someone opening the door mid-action ends it")
action.isStarted, target.open, target.__class = nil, false, "IsoWindow"
target.index = -1
check(action:isValid() == false, "a window taken out of the world ends the action")

do
    local openWindow, windowWorker = window(), makeWorker(kit())
    openWindow.open = true
    local accepted, why = start(windowWorker, { object = openWindow }, provider)
    check(accepted == true, "an open window follows native boarding rules: " .. tostring(why))
    local windowAction = ISTimedActionQueue.getTimedActionQueue(windowWorker).current
    windowAction.isStarted = true
    check(windowAction:isValid(), "the open-door rule never applies to a window")

    local openDoor, doorWorker = window(), makeWorker(kit())
    openDoor.__class, openDoor.open = "IsoDoor", true
    accepted, why = start(doorWorker, { object = openDoor }, provider)
    check(accepted == true, "an open door may queue so native start can close it: " .. tostring(why))
    local doorAction = ISTimedActionQueue.getTimedActionQueue(doorWorker).current
    openDoor.open, doorAction.isStarted = false, true
    check(doorAction:isValid(), "the closed door remains valid once native start runs")
    openDoor.open = true
    check(not doorAction:isValid(), "reopening a started door cancels boarding")
    openDoor.__class = "IsoThumpable"
    function openDoor:isDoor() return self.door == true end
    openDoor.door = true
    check(not doorAction:isValid(), "a reopened player-built door also cancels boarding")
    openDoor.door = false
    check(doorAction:isValid(), "other barricadable thumpables do not inherit the door check")
end

local empty = makeWorker({ makeItem("Plank"), makeItem("Nails"), makeItem("Nails") })
local refused, why = start(empty, { object = window() }, provider)
check(refused == false and why == "companion needs a hammer", "no hammer, no start: " .. tostring(why))

do
    local originalBase = SC.BaseLife
    local allowed, owner, identity = true, "sc-barricade-owner", "object:guarded-window"
    SC.BaseLife = { barricadeJobCurrent = function(jobId, actorId, objectId)
        return allowed and jobId == "job:guarded" and actorId == owner and objectId == identity
    end }
    local guarded = makeWorker(kit())
    local guardedData = { SC_Id = owner, SC_Order = "work",
        SC_WorkBaseJobId = "job:guarded", SC_WorkObjectId = identity }
    function guarded:getModData() return guardedData end
    local guardedWindow = window()
    check(start(guarded, { object = guardedWindow, baseJobId = "job:guarded", objectId = identity }, provider),
        "a camp worker with the exact current job may queue the plank")
    local guardedAction = ISTimedActionQueue.getTimedActionQueue(guarded).current
    check(guardedAction:isValid(), "the accepted camp action retains its job authority")
    check(Actions.workKind(guarded) == "barricade" and Actions.workJobId(guarded) == "job:guarded",
        "native ownership retains the exact job even after a command changes")
    guardedData.SC_Order = "follow"
    check(not guardedAction:isValid(), "a new player order invalidates the old queued plank")
    guardedData.SC_Order = "work"
    allowed = false
    check(not guardedAction:isValid(), "removing the job's authority invalidates an already queued plank")
    allowed = true
    identity = "object:replacement"
    check(not guardedAction:isValid(), "replacement target identity cannot authorize the old action")
    SC.BaseLife = originalBase
end

SC_TEST_REPORT = "BARRICADE_ACTION_PASS checks=" .. checks
