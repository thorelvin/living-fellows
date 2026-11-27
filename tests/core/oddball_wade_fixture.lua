-- SPDX-License-Identifier: MIT
local SC = LivingFellows
local F = { events = {}, nextItem = 0, slot = 1, now = 0, bankReady = true, state = { immediateCount = 0 } }
SC.WadeFixture = F

local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0, inventory = {} }
    function value:getPrimaryHandItem() return self.primary end
    function value:setPrimaryHandItem(item) self.primary = item end
    function value:getSecondaryHandItem() return self.secondary end
    function value:setSecondaryHandItem(item) self.secondary = item end
    function value:playSound(sound) F.record("sound", sound) end
    function value:getPlayerNum() return self.slot end
    return value
end

F.wade, F.player, F.witness = actor("wade", 10.5, 10.5), actor("player", 13, 10.5), actor("witness", 11, 10.5)
F.player.slot = F.slot
F.group = { id = "wade-test", members = { { actorId = F.wade.id } }, oddball = {
    id = "wade_hensley", stage = "unmet", site = { spawn = { x = 10, y = 10, z = 0 } },
} }
F.group.oddball.site.bank = F.group.oddball.site.spawn
F.group.oddball.site.water = { x = 9, y = 10, z = 0 }

function F.record(kind, detail)
    F.events[#F.events + 1] = { kind = kind, detail = detail }
end

local function contains(inventory, item)
    for _, candidate in ipairs(inventory) do if candidate == item then return true end end
    return false
end

local function remove(inventory, item)
    for index, candidate in ipairs(inventory) do
        if candidate == item then
            table.remove(inventory, index)
            item.container = nil
            return true
        end
    end
    return false
end

function F.add(inventory, kind, uses)
    local item = { kind = kind, data = {}, uses = uses or 0, container = inventory }
    function item:getCurrentUsesFloat() return self.uses end
    function item:getContainer() return self.container end
    inventory[#inventory + 1] = item
    return item
end

function F.owned(owner, kind)
    local count = 0
    for _, item in ipairs(owner.inventory) do
        if item.kind == kind then count = count + 1 end
    end
    return count
end

function F.find(owner, id)
    for _, item in ipairs(owner.inventory) do
        if item.id == id then return item end
    end
end

function F.clone(source)
    if type(source) ~= "table" then return source end
    local target = {}
    for key, value in pairs(source) do target[key] = F.clone(value) end
    return target
end

function F.pulse(group, player, now)
    F.now = now
    return SC.OddballWade.pulse(group, player, now)
end

SC.GameplayUtil = {
    call = function(object, method, ...)
        if object and type(object[method]) == "function" then return object[method](object, ...), true end
        return nil, false
    end,
    distance = function(a, b)
        if not a or not b then return math.huge end
        return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
    end,
    canSee = function(_, player) return player.visible ~= false end,
    sameFloor = function(a, b) return a and b and a.z == b.z end,
    arrived = function(wade, square, options)
        return wade.z == square.z
            and (wade.x - square.x - 0.5)^2 + (wade.y - square.y - 0.5)^2 <= options.distance^2
    end,
    inventory = function(owner) return owner and owner.inventory end,
    inventoryItemsDeep = function(inventory) return inventory end,
    isValidActor = function(owner) return owner ~= nil end,
    isDead = function(owner) return owner.dead == true end,
    idOf = function(owner) return owner.id end,
    modData = function(item) return item and item.data end,
    itemType = function(item) return item.kind end,
    itemStableId = function(item, allocate)
        if not item.id and allocate then
            F.nextItem = F.nextItem + 1
            item.id = "lf-item:" .. F.nextItem
        end
        return item.id
    end,
    addItem = F.add,
    inventoryContains = contains,
    transferItemVerified = function(source, destination, item)
        if F.blockTransfer == item then return false end
        if not remove(source, item) then return false end
        item.container = destination
        destination[#destination + 1] = item
        F.record("transfer", item)
        return true
    end,
    say = function(wade, text)
        assert(wade == F.wade)
        F.record("say", text)
        return true
    end,
    speechDisplayMillis = function() return 500 end,
    nowMs = function() return F.now end,
}

F.wade.inventory.Remove = function(inventory, item)
    F.record("release-attempt", item)
    if F.blockRelease ~= item then remove(inventory, item) end
end

SC.Registry = { byId = function(id)
    if id == F.wade.id then return { actor = F.wade, runtime = { snapshot = F.state } } end
end }
SC.OddballWadeBank = {
    onSpawn = function() return F.bankReady end,
    castSite = function(group) return F.bankReady and group.oddball.site or nil end,
    storyRules = { siteKind = "wade_bank", validate = function() return true end },
}

SC.OddballDistressRadio = {
    register = function(id, module, labels) F.radio = { id = id, module = module, labels = labels } end,
    provisionRadio = function(wade, allowCreate)
        if not wade.radio and allowCreate then wade.radio = F.add(wade.inventory, "Base.WalkieTalkie2") end
        if wade.radio then wade:setSecondaryHandItem(wade.radio) end
        return wade.radio ~= nil, wade.radio
    end,
}

local function stockAction(effect)
    return { new = function(_, wade, rod, item)
        assert(wade == F.wade and contains(wade.inventory, item) and contains(wade.inventory, rod))
        return { complete = function()
            effect(rod, item)
            F.record("rig", item)
            return true
        end }
    end }
end

ISChangeFishingRodEquip = stockAction(function(rod, item)
    if item.kind == "Base.FishingHook" then rod.data.fishing_HookType = item.kind
    else
        assert(item.uses > 0)
        rod.data.fishing_LineCondition = item.uses
    end
    remove(F.wade.inventory, item)
end)
AIAttachLureAction = stockAction(function(rod, item)
    rod.data.fishing_Lure = item.kind
    remove(F.wade.inventory, item)
end)

SC.Fishing = {
    beginScriptedCast = function(wade, site, rod, token, callback)
        assert(wade == F.wade and site.bank and site.water and rod == F.rod and wade.primary == rod)
        F.cast = { token = token, callback = callback, phase = "waiting" }
        F.record("cast", token)
        return true, "casting"
    end,
    scriptedCastStatus = function(wade, token)
        assert(wade == F.wade and F.cast and F.cast.token == token)
        return F.cast.phase, nil, F.cast.didHook
    end,
    cancelScriptedCast = function(wade, token, reason)
        assert(wade == F.wade and F.cast and F.cast.token == token)
        F.cast.phase = "cancelled"
        F.record("cancel-cast", reason)
        return true
    end,
}

function getText(key) return key end
function getSpecificPlayer(slot) return slot == F.slot and F.player or nil end

F.rod = F.add(F.wade.inventory, "Base.FishingRod")
F.rod.data.fishing_LineCondition = 0.9
F.hook = F.add(F.wade.inventory, "Base.FishingHook")
F.worm = F.add(F.wade.inventory, "Base.Worm")
