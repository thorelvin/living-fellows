-- SPDX-License-Identifier: MIT
-- A small B42-shaped bedroom, inventory, and native-animal world for Milli.

SurvivorCompanion = { GameplayUtil = {}, Registry = {}, Factions = {},
    OddballAnimals = {}, OddballRoomGuard = {}, Trade = {}, Actor = {},
    FactionRecruitment = {}, Diagnostics = {}, Community = {},
    BaseLife = {}, ActionSupervisor = {}, Downtime = {} }
local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
SC_MILLI_FIXTURE = { hour = 100, now = 1000, lines = {}, squares = {},
    animals = {}, spawnCalls = 0, followCalls = 0, guardRegisters = 0,
    guardReleases = 0, movement = {}, deliveries = 0, offenses = 0,
    reconciliations = 0, standings = {}, worldItems = {}, recruitment = 0,
    pathCalls = 0, settleCalls = 0, clockHour = 12 }
local F = SC_MILLI_FIXTURE
Perks = { Strength = 'Strength', Fitness = 'Fitness',
    Blunt = 'Blunt', SmallBlunt = 'SmallBlunt',
    SmallBlade = 'SmallBlade', Sneak = 'Sneak',
    Lightfoot = 'Lightfoot', Nimble = 'Nimble' }
ImmutableColor = { new = function(r, g, b, a)
    return { r = r, g = g, b = b, a = a }
end }
ResourceLocation = { of = function(id) return id end }
CharacterTrait = { get = function(id) return id end }

local function list(rows)
    return { size = function() return #rows end,
        get = function(_, index) return rows[index + 1] end }
end

function F.inventory()
    local inventory = { items = {} }
    function inventory:AddItem(kind)
        local item = { kind = kind, fullType = kind, container = self,
            data = {}, visual = {} }
        function item:getFullType() return self.fullType end
        function item:getType() return self.kind:match('%.(.+)$') end
        function item:getContainer() return self.container end
        function item:getModData() return self.data end
        function item:getVisual() return self.visual end
        function item.visual:setTint(value) self.tint = value end
        function item:setTextureChoice(value) self.texture = value end
        function item:setName(value) self.name = value end
        self.items[#self.items + 1] = item
        return item
    end
    function inventory:getItems() return list(self.items) end
    function inventory:Remove(item)
        for index, row in ipairs(self.items) do
            if row == item then
                table.remove(self.items, index)
                item.container = nil
                return true
            end
        end
        return false
    end
    function inventory:contains(item)
        for _, row in ipairs(self.items) do if row == item then return true end end
        return false
    end
    return inventory
end

function F.actor(x, y, z)
    local actor = { x = x or 10, y = y or 10, z = z or 0,
        inv = F.inventory(), perks = {}, traits = {}, data = {},
        health = 100, maxHealth = 100, sitting = false }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getSquare() return U.gridSquare(self.x, self.y, self.z) end
    function actor:getInventory() return self.inv end
    function actor:getModData() return self.data end
    function actor:getPrimaryHandItem() return self.primary end
    function actor:setPrimaryHandItem(item) self.primary = item; return true end
    function actor:setSecondaryHandItem(item) self.secondary = item; return true end
    function actor:isSitOnGround() return self.sitting end
    function actor:isAsleep() return self.asleep == true end
    function actor:isMoving() return self.moving == true end
    function actor:getHealth() return self.health end
    function actor:getMaxHealth() return self.maxHealth end
    function actor:reportEvent(name)
        self.lastEvent = name
        if name == 'EventSitOnGround' then self.sitting = true end
        return true
    end
    function actor:getPerkLevel(perk) return self.perks[perk] or 0 end
    function actor:setPerkLevelDebug(perk, level)
        self.perks[perk] = level
    end
    function actor:setPerkLevel(perk, level) self.perks[perk] = level end
    function actor:getTraits() return self.traits end
    function actor:getCharacterTraits() return self.traits end
    function actor.traits:add(trait) self[trait] = true end
    function actor.traits:contains(trait) return self[trait] == true end
    return actor
end

local function room(name, id)
    local value = { name = name, id = id }
    function value:getName() return self.name end
    function value:getRoomDef() return self end
    return value
end

function F.square(x, y, z, roomValue, objects)
    local key = table.concat({ x, y, z or 0 }, ':')
    local tile = { x = x, y = y, z = z or 0,
        room = roomValue, objects = objects or {}, free = true }
    function tile:getX() return self.x end
    function tile:getY() return self.y end
    function tile:getZ() return self.z end
    function tile:getRoom() return self.room end
    function tile:getObjects() return list(self.objects) end
    function tile:isFree() return self.free end
    function tile:AddWorldInventoryItem(kind)
        local item = { kind = kind, square = self, data = {} }
        function item:getFullType() return self.kind end
        function item:getModData() return self.data end
        local world = { item = item }
        function world:getItem() return self.item end
        F.worldItems[#F.worldItems + 1] = world
        return world
    end
    F.squares[key] = tile
    return tile
end

function F.house(withKids, large)
    F.squares = {}
    local kids = room('kidsbedroom', 1)
    local bedroom = room('bedroom', 2)
    local living = room('livingroom', 3)
    local secondBedroom = room('bedroom', 4)
    local house = { id = withKids and 'big-kids-house' or 'house',
        bounds = { x1 = 8, y1 = 8, x2 = 18, y2 = 18 },
        anchor = { x = 10, y = 10, z = 0 }, interior = {} }
    local function add(x, y, z, which, bed)
        local objects = bed and { { name = 'Bed', bed = true,
            getName = function(self) return self.name end,
            isBed = function() return true end,
            getProperties = function() return { Is = function(_, key)
                return key == 'Bed' end } end,
            getSprite = function() return { getName = function()
                return 'furniture_bedding_01_0' end } end } } or {}
        F.square(x, y, z, which, objects)
        house.interior[#house.interior + 1] = { x = x, y = y, z = z }
    end
    if withKids then
        add(10, 10, 0, kids, true)
        add(11, 10, 0, kids)
        add(10, 11, 0, kids)
        add(11, 11, 0, kids)
    end
    add(14, 10, 0, bedroom, true)
    add(15, 10, 0, bedroom)
    add(14, 11, 0, bedroom)
    add(15, 11, 0, bedroom)
    if large then
        add(17, 10, 0, secondBedroom, true)
        add(18, 10, 0, secondBedroom)
        for x = 10, 14 do
            for y = 14, 16 do add(x, y, 0, living) end
        end
    end
    return house
end

function U.call(object, method, ...)
    local callback = object and object[method]
    if type(callback) ~= 'function' then return nil, false end
    local okay, result = pcall(callback, object, ...)
    return okay and result or nil, okay
end
function U.nowMs() return F.now end
function U.position(value) return value and value.x, value and value.y,
    value and value.z end
function U.idOf(value) return value and value.id end
function U.gridSquare(x, y, z)
    return F.squares[table.concat({ math.floor(x), math.floor(y), z or 0 }, ':')]
end
function U.squareOf(value) return value and U.gridSquare(value.x, value.y, value.z) end
function U.squareObjects(tile, visit)
    for index, object in ipairs(tile and tile.objects or {}) do
        if visit(object, index - 1) == false then break end
    end
end
function U.isSafeSpawnSquare(tile) return tile ~= nil and tile.free == true end
function U.isSquareFree(tile) return tile ~= nil and tile.free == true end
function U.canSee() return F.visible == true end
function U.inventory(actor) return actor and actor.inv end
function U.inventoryItemsDeep(inv) return inv and inv.items or {} end
function U.itemType(item) return item and item.kind end
function U.addItem(inv, kind) return inv and inv:AddItem(kind) end
function U.transferItemVerified(source, destination, item)
    if not source or not destination or not source:Remove(item) then
        return false, 'source_item_unavailable'
    end
    item.container = destination
    destination.items[#destination.items + 1] = item
    return true, 'transferred'
end
function U.modData(value) return value and value.data end
function U.isValidActor(value) return value and not value.dead end
function U.stableHash(value)
    local total = 0
    for index = 1, #tostring(value) do
        total = (total * 33 + string.byte(tostring(value), index)) % 2147483647
    end
    return total
end
function U.say(actor, line)
    if not actor or type(line) ~= 'string' then return false end
    F.lines[#F.lines + 1] = line
    actor.lastLine = line
    return true
end
function U.distance(left, right)
    if not left or not right or left.z ~= right.z then return math.huge end
    return math.sqrt((left.x - right.x) ^ 2 + (left.y - right.y) ^ 2)
end
function U.config(key, fallback)
    local values = { oddballMilliGuardReleaseTiles = 12,
        oddballMilliStartleTiles = 3, oddballMilliPetTalkMs = 20000,
        oddballMilliTeaCooldownHours = 24, oddballMilliReimbursement = 5 }
    return values[key] or fallback
end
function U.instanceOf(object, class)
    if class == 'IsoObject' then return object ~= nil end
    return object and object.class == class or false
end
SC.NativeList = {
    size = function(values) return values and values:size() or 0 end,
    get = function(values, index) return values and values:get(index) end,
    each = function(values, maximum, visit)
        for index = 0, math.min(values and values:size() or 0,
                maximum or 100) - 1 do
            if visit(values:get(index), index) == false then break end
        end
    end,
}

function SC.Registry.byId(id)
    if F.group and F.group.members and F.group.members[1]
        and F.group.members[1].actorId == id then
        return { actor = F.milli }
    end
    if F.companion and id == F.companion.id then
        return { actor = F.companion, recruited = true }
    end
    return nil
end
function SC.Registry.living()
    return F.companion and { F.companion } or {}
end
function SC.Community.relation(first, second)
    if first == F.milli.id and second == F.companion.id then
        return F.relation
    end
    return nil
end
function SC.BaseLife.isInside() return F.atCamp == true end
function SC.ActionSupervisor.current() return F.token end
function SC.Downtime.peek() return F.downtime end
function SC.Factions.forceStanding(id, standing)
    if not F.group or id ~= F.group.id then return false end
    F.group.standing = standing
    F.standings[#F.standings + 1] = standing
    return true, standing
end
function SC.Factions.group(id)
    return F.group and F.group.id == id and F.group or nil
end
function SC.Factions.adjustStanding(id, delta, reason)
    if not F.group or id ~= F.group.id then return false end
    F.group.reputation = (F.group.reputation or -20) + delta
    F.lastStandingReason = reason
    return true, F.group.standing
end
function SC.Factions.noteOffense()
    F.offenses = F.offenses + 1
    return true
end
function SC.Factions.reconcile()
    F.reconciliations = F.reconciliations + 1
    return true
end
function SC.OddballRoomGuard.register()
    F.guardRegisters = F.guardRegisters + 1
    return true
end
function SC.OddballRoomGuard.release()
    F.guardReleases = F.guardReleases + 1
    return true
end
function SC.Actor.setMovement(actor, _, intent)
    F.movement[#F.movement + 1] = intent.action
    if intent.action == 'sit_ground' then actor.sitting = true end
    if intent.action == 'stand_ground' then actor.sitting = false end
    return true
end
function SC.Trade.deliverRequirements(group, player, requirements)
    local needed = 0
    for _, requirement in ipairs(requirements) do
        if requirement.type == 'Base.Money' then
            needed = needed + (requirement.count or 0)
        end
    end
    if needed ~= 5 then return false, 'wrong_payment' end
    local money = {}
    for _, item in ipairs(player.inv.items) do
        if item.kind == 'Base.Money' then money[#money + 1] = item end
    end
    if #money < needed then return false, 'missing_money' end
    for index = 1, needed do
        player.inv:Remove(money[index])
        group.receivedMoney = (group.receivedMoney or 0) + 1
    end
    F.deliveries = F.deliveries + 1
    return true, 'paid'
end
function SC.FactionRecruitment.summary()
    return { status = 'available' }
end
function SC.FactionRecruitment.ask()
    F.recruitment = F.recruitment + 1
    return true
end
function SC.FactionRecruitment.startTrial()
    F.recruitment = F.recruitment + 1
    return true
end
function SC.Diagnostics.report() end

local function animal(group, slot, spec, post)
    local pet = { id = 900 + slot, kind = spec.kind, name = spec.name,
        x = post.x, y = post.y, z = post.z or 0, health = 100,
        data = { lfOddballGroupId = group.id, lfOddballAnimalSlot = slot } }
    function pet:getAnimalID() return self.id end
    function pet:getAnimalType() return self.kind end
    function pet:getCustomName() return self.name end
    function pet:getHealth() return self.health end
    function pet:getModData() return self.data end
    function pet:getX() return self.x end
    function pet:getY() return self.y end
    function pet:getZ() return self.z end
    function pet:getContainer() return self.holder and self.holder.inv or nil end
    function pet:isAnimalSitting() return self.sitting == true end
    function pet:debugForceSit()
        F.settleCalls = F.settleCalls + 1
        self.sitting = not self.sitting
    end
    function pet:pathToCharacter(target)
        F.pathCalls = F.pathCalls + 1
        self.pathTarget = target
    end
    return pet
end
function SC.OddballAnimals.spawn(group, slot, spec, post)
    group.oddball.animals = group.oddball.animals or { slots = {} }
    local slots = group.oddball.animals.slots
    if slots[slot] then return true, 'already_seeded' end
    local pet = animal(group, slot, spec, post)
    slots[slot] = { id = pet.id, kind = pet.kind,
        name = pet.name, x = post.x, y = post.y, z = post.z or 0 }
    F.animals[slot] = pet
    F.spawnCalls = F.spawnCalls + 1
    return true, pet
end
function SC.OddballAnimals.find(group, slot)
    local record = group.oddball.animals and group.oddball.animals.slots[slot]
    local pet = F.animals[slot]
    if pet and pet.health <= 0 and record then record.dead = true end
    if record and record.dead then return nil, record end
    if F.unloaded and F.unloaded[slot] then return nil, record end
    return pet, record
end
function SC.OddballAnimals.status(group, slot)
    local pet, record = SC.OddballAnimals.find(group, slot)
    if not record then return 'unseeded' end
    if pet then return 'alive', pet end
    return record.dead and 'dead' or 'unloaded', record
end
function SC.OddballAnimals.follow()
    F.followCalls = F.followCalls + 1
    return true
end
function SC.OddballAnimals.isProtected(pet)
    return pet and pet.data and pet.data.lfOddballGroupId ~= nil or false
end

function getGameTime()
    return { getWorldAgeHours = function() return F.hour end,
        getHour = function() return F.clockHour end }
end
function getPlayer() return F.player end
function getCell() return {} end

function F.scene(site)
    F.animals, F.unloaded = {}, {}
    F.relation, F.atCamp, F.token, F.downtime, F.clockHour =
        nil, false, nil, nil, 12
    F.milli = F.actor(site.spawn.x, site.spawn.y, site.spawn.z or 0)
    F.milli.id = 'milli-fixture-actor'
    -- Oddballs.spawned seeds a definition's fixed kit before calling onSpawn.
    for _, kind in ipairs({ 'Base.PanchoDog', 'Base.Money', 'Base.Money',
            'Base.PopBottle', 'Base.MuffinGeneric', 'Base.MuffinGeneric',
            'Base.MuffinFruit', 'Base.Kettle', 'Base.Teabag2',
            'Base.Teabag2', 'Base.Teabag2',
            'Base.Jumper_DiamondPatternTINT',
            'Base.Trousers_WhiteTINT', 'Base.Shoes_Slippers' }) do
        F.milli.inv:AddItem(kind)
    end
    F.player = F.actor(site.spawn.x + 8, site.spawn.y + 8, site.spawn.z or 0)
    F.player.id = 'player-fixture'
    F.companion = F.actor(site.spawn.x + 2, site.spawn.y + 2, site.spawn.z or 0)
    F.companion.id = 'companion-fixture'
    F.group = { id = 'milli-fixture', standing = 'Wary',
        reputation = -20, offenses = {},
        members = { { actorId = 'milli-fixture-actor' } },
        oddball = { id = 'milli_tea_and_trouble',
            site = site, stage = 'unmet' } }
    return F.group, F.milli, F.player
end
