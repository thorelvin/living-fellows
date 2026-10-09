-- SPDX-License-Identifier: MIT
-- Dedicated deterministic contract test for the Shotgun Farmer story.

local W = SurvivorCompanion.OddballWendell
local SC = SurvivorCompanion
local hour, noiseCount, attackCount, animalCount = 0, 0, 0, 0
local records = {}
local photos = {}

local function check(name, condition)
    if not condition then error("WENDELL_FAIL " .. name, 2) end
    print("WENDELL_PASS " .. name)
end

local function item(kind, container)
    local value = { kind = kind, container = container, ammo = 0 }
    function value:getFullType() return self.kind end
    function value:getContainer() return self.container end
    function value:getCurrentAmmoCount() return self.ammo end
    function value:setCurrentAmmoCount(count) self.ammo = count end
    return value
end

local function inventory()
    local result = { items = {} }
    function result:AddItem(kind)
        local value = item(kind, self)
        self.items[#self.items + 1] = value
        return value
    end
    function result:Remove(value)
        for index, candidate in ipairs(self.items) do
            if candidate == value then
                table.remove(self.items, index)
                value.container = nil
                return
            end
        end
    end
    function result:contains(value)
        for _, candidate in ipairs(self.items) do
            if candidate == value then return true end
        end
        return false
    end
    return result
end

local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0,
        inv = inventory(), primary = nil, alive = true }
    function value:getInventory() return self.inv end
    function value:getPrimaryHandItem() return self.primary end
    function value:setPrimaryHandItem(weapon) self.primary = weapon end
    function value:setSecondaryHandItem(weapon) self.secondary = weapon end
    function value:playSound(name) self.lastSound = name return 1 end
    function value:pressedAttack() attackCount = attackCount + 1 end
    return value
end

local function group(id, withActor, coop)
    local square = { x = 10, y = 10, z = 0 }
    local resident = actor(id .. "-actor", 15, 15)
    local result = {
        id = id, house = { bounds = { x1 = 10, y1 = 10, x2 = 20, y2 = 20 } },
        standing = "Wary", lifecycle = "settled", members = {
            { key = "member-1", actorId = resident.id, alive = true },
        },
        oddball = { id = "shotgun_farmer_wendell", stage = "unmet",
            site = { kind = "resident", anchor = square,
                spawn = { x = 15, y = 15, z = 0 },
                house = { bounds = { x1 = 10, y1 = 10,
                    x2 = 20, y2 = 20 } }, coop = coop } },
    }
    if withActor then records[resident.id] = { actor = resident } end
    return result, resident
end

SC.Oddballs = { state = function(group) return group.oddball end }
SC.Registry = { byId = function(id) return records[id] end }
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local ok, value = pcall(object[method], object, ...)
        if not ok then return nil, false end
        return value, true
    end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(container) return container and container.items or {} end,
    containerContainsIdentity = function(container, value)
        return container:contains(value)
    end,
    position = function(value)
        if value and value.x ~= nil then return value.x, value.y, value.z end
        if value and value.getX then
            return value:getX(), value:getY(), value:getZ()
        end
    end,
    isValidActor = function(value) return value and value.alive == true end,
    config = function(key) if key == "profanityEnabled" then return false end end,
    say = function(value, line) value.lastLine = line return true end,
    gridSquare = function(x, y, z)
        if x >= 40 and x <= 41 and y >= 40 and y <= 41 then
            return { x = x, y = y, z = z }
        end
    end,
}

function getGameTime() return { getWorldAgeHours = function() return hour end } end
function getCell() return {} end
function getPlayer() return photos.player end
function addSound() noiseCount = noiseCount + 1 end
function addAnimal(cell, x, y, z, kind, breed)
    animalCount = animalCount + 1
    local value = { id = 9000 + animalCount, type = kind, data = {} }
    function value:setWild(flag) self.wild = flag end
    function value:getModData() return self.data end
    function value:addToWorld() self.inWorld = true end
    function value:getAnimalID() return self.id end
    return value
end

SC.FactionRecruitment = {
    status = "available", asked = 0, started = 0,
    summary = function()
        return { status = SC.FactionRecruitment.status,
            canDecide = true, canReturn = true }
    end,
    ask = function()
        SC.FactionRecruitment.asked = SC.FactionRecruitment.asked + 1
        SC.FactionRecruitment.status = "candidate"
        return true, "candidate_named"
    end,
    startTrial = function()
        SC.FactionRecruitment.started = SC.FactionRecruitment.started + 1
        SC.FactionRecruitment.status = "trial"
        return true, "trial_started"
    end,
    decide = function() return true, "joined" end,
    returnNow = function() return true, "returned" end,
}

local player = actor("player", 25, 15)
photos.player = player
local warningGroup, warningActor = group("warning", true)
check("spawn_loadout", W.onSpawn(warningGroup, warningActor) == true)
local gun = warningActor.primary
check("shotgun_loaded", gun and gun:getCurrentAmmoCount() == 6)
W.pulse(warningGroup, player)
check("outer_property_warning", warningGroup.oddball.stage == "warned")
check("warning_one_shell", gun:getCurrentAmmoCount() == 5)
check("warning_world_noise", noiseCount == 1)
check("warning_cannot_damage", attackCount == 0)
W.pulse(warningGroup, player)
check("warning_once", gun:getCurrentAmmoCount() == 5 and noiseCount == 1)
player.x = 15
W.pulse(warningGroup, player)
check("porch_is_hostile", warningGroup.oddball.stage == "hostile"
    and warningGroup.standing == "Hostile")
check("hostile_uses_faction_combat",
    W.intentFor(warningActor, player, {}, warningGroup).mode == "hostile")

player.x = 24
local hurtGroup, hurtActor = group("hurt", true)
hurtGroup.oddball.stage = "warned"
check("player_hit_sets_hostility", W.action(hurtGroup, "hurt", player) == true
    and hurtGroup.oddball.stage == "hostile"
    and hurtGroup.lifecycle == "hostile"
    and W.intentFor(hurtActor, player, {}, hurtGroup).mode == "hostile")
local offenseGroup, offenseActor = group("offense", true)
offenseGroup.oddball.stage = "warned"
offenseGroup.standing = "Hostile"
check("faction_hostility_enters_combat",
    W.intentFor(offenseActor, player, {}, offenseGroup).mode == "hostile"
    and offenseGroup.oddball.stage == "hostile")

local helpGroup, helpActor = group("help", true)
helpGroup.oddball.stage = "warned"
helpGroup.oddball.chickens = { spawned = true, slots = {} }
function helpActor:getX() return 15 end
function helpActor:getY() return 15 end
function helpActor:getZ() return 0 end
helpActor.x, helpActor.y, helpActor.z = nil, nil, nil
W.onSpawn(helpGroup, helpActor)
player.inv:AddItem("Base.ShotgunShellsBox")
player.inv:AddItem("Base.ShotgunShellsBox")
local delivered = W.action(helpGroup, "offer_shells", player)
check("first_box_consumed", delivered == true
    and helpGroup.oddball.shellDeliveries == 1 and #player.inv.items == 0 + 1)
delivered = W.action(helpGroup, "offer_shells", player)
check("second_box_consumed", delivered == true
    and helpGroup.oddball.shellDeliveries == 2 and #player.inv.items == 0)
check("delivery_adds_real_shells", #helpActor.inv.items >= 49)
check("recruit_requires_watch", W.canRecruit(helpGroup) == false)
hour = 20.5
check("night_watch_scheduled", W.action(helpGroup, "start_watch", player) == true
    and helpGroup.oddball.watch.startHour == 21)
for index = 0, 96 do
    hour = 21 + index / 12
    W.pulse(helpGroup, player)
end
check("full_watch_completed", helpGroup.oddball.watch.completed == true)
check("recruitment_gate_open", W.canRecruit(helpGroup) == true)
local options = W.menuOptions(helpGroup, player)
check("recruit_menu_enabled", options[3].id == "recruit"
    and options[3].enabled == true)
check("trial_started", W.action(helpGroup, "recruit", player) == true
    and SC.FactionRecruitment.asked == 1
    and SC.FactionRecruitment.started == 1)
options = W.menuOptions(helpGroup, player)
check("trial_followups", options[4].id == "recruitment_decide"
    and options[5].id == "recruitment_return")

local resetGroup, resetActor = group("reset", true)
resetGroup.oddball.shellDeliveries = 2
resetGroup.oddball.chickens = { spawned = true, slots = {} }
W.onSpawn(resetGroup, resetActor)
hour = 20.5
W.action(resetGroup, "start_watch", player)
hour = 21
W.pulse(resetGroup, player)
player.x = 100
hour = 21.05
W.pulse(resetGroup, player)
hour = 21.13
W.pulse(resetGroup, player)
check("brief_absence_tolerated", resetGroup.oddball.watch.resetCount == 0)
hour = 21.22
W.pulse(resetGroup, player)
check("ten_minute_absence_resets",
    resetGroup.oddball.watch.completed ~= true
        and resetGroup.oddball.watch.resetCount == 1
        and resetGroup.oddball.watch.startHour == 45)

local coop = { x = 40, y = 40, z = 0, enclosed = true }
local chickenGroup = group("chickens", false, coop)
hour = 0
W.pulse(chickenGroup, player)
check("three_hens_one_cockerel", animalCount == 4
    and chickenGroup.oddball.chickens.spawned == true
    and chickenGroup.oddball.chickens.slots[4].type == "cockerel")
local firstId = chickenGroup.oddball.chickens.slots[1].id
local loadedSquare = SC.GameplayUtil.gridSquare
SC.GameplayUtil.gridSquare = function() return nil end
W.pulse(chickenGroup, player)
check("unloaded_birds_not_declared_dead", animalCount == 4
    and firstId == chickenGroup.oddball.chickens.slots[1].id)
SC.GameplayUtil.gridSquare = loadedSquare

local lastGroup, lastActor = group("last", true)
lastGroup.oddball.chickens = { spawned = true, slots = {} }
W.onSpawn(lastGroup, lastActor)
lastActor.primary:setCurrentAmmoCount(0)
hour = 0
W.pulse(lastGroup, player)
records[lastActor.id] = nil
hour = 120
W.pulse(lastGroup, player)
check("unseen_five_day_last_stand",
    lastGroup.oddball.stage == "last_stand"
        and lastGroup.oddball.lastStandTriggered == true
        and lastGroup.lifecycle == "destroyed")
hour = 130
W.pulse(lastGroup, player)
check("last_stand_once", lastGroup.oddball.lastStandTriggered == true)

print("ODDBALL_WENDELL_PASS")
