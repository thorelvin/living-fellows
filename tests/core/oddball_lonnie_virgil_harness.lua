-- SPDX-License-Identifier: MIT
-- Focused, deterministic wedding and mail route contracts.

local SC = SurvivorCompanion
local Lonnie, Virgil = SC.OddballLonnie, SC.OddballVirgil
local checks = 0
local now, hours = 1000, 24 * 9
local groups, records, zombies, zombieSpawns = {}, {}, {}, 0
local doors = {}
local player = { id = "player", x = 10, y = 10, z = 0, alive = true }

local function check(name, okay)
    if not okay then error("LONNIE_VIRGIL_FAIL " .. name, 2) end
    checks = checks + 1
end

local function inv()
    local box = { items = {} }
    function box:AddItem(spec)
        local item = type(spec) == "table" and spec or { kind = spec }
        item.container = self
        function item:getFullType() return self.kind end
        function item:getContainer() return self.container end
        function item:setName(text) self.name = text end
        function item:setCustomName(value) self.custom = value end
        self.items[#self.items + 1] = item
        return item
    end
    function box:Remove(item)
        for index, candidate in ipairs(self.items) do
            if candidate == item then
                table.remove(self.items, index)
                item.container = nil
                return
            end
        end
    end
    return box
end

local function actor(id, x, y)
    local result = { id = id, x = x, y = y, z = 0, alive = true, inv = inv() }
    function result:getInventory() return self.inv end
    function result:setPrimaryHandItem(item) self.primary = item end
    function result:setSecondaryHandItem(item) self.secondary = item end
    return result
end
player.inv = inv()

local function distance(a, b)
    if not a or not b then return math.huge end
    local dx, dy = (a.x or 0) - (b.x or 0), (a.y or 0) - (b.y or 0)
    return math.sqrt(dx * dx + dy * dy)
end

SC.Registry = {
    byId = function(id) return records[id] end,
    living = function() return {} end,
}
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local okay, value = pcall(object[method], object, ...)
        return okay and value or nil, okay
    end,
    idOf = function(value) return value and value.id end,
    isValidActor = function(value) return value and value.alive == true end,
    isZombie = function(value) return value and value.zombie == true end,
    isDead = function(value) return value and value.dead == true end,
    distance = distance,
    position = function(value) return value.x, value.y, value.z or 0 end,
    squareOf = function(value) return { x = value.x, y = value.y, z = value.z or 0 } end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z or 0 } end,
    isSafeSpawnSquare = function(value) return value ~= nil end,
    squareObjects = function(square, callback)
        local door = doors[square.x .. ":" .. square.y]
        if door then callback(door) end
    end,
    squareSpecialObjects = function(square, callback)
        local door = doors[square.x .. ":" .. square.y]
        if door then callback(door) end
    end,
    squareMovingObjects = function(square, callback)
        for _, zombie in ipairs(zombies) do
            if zombie.x == square.x and zombie.y == square.y then callback(zombie) end
        end
    end,
    instanceOf = function(value, kind) return kind == "IsoDoor" and value.door == true end,
    listGet = function(list, index) return list[index + 1] end,
    modData = function(value) value.data = value.data or {} return value.data end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(box) return box and box.items or {} end,
    itemType = function(value) return value and value.kind end,
    addItem = function(box, item) return box:AddItem(item) end,
    containerContainsIdentity = function(box, item)
        for _, candidate in ipairs(box.items) do
            if candidate == item then return true end
        end
        return false
    end,
    transferItemVerified = function(source, destination, item)
        if not source or not destination then return false, "missing_container" end
        if not SC.GameplayUtil.containerContainsIdentity(source, item) then
            return false, "source_missing"
        end
        source:Remove(item)
        destination:AddItem(item)
        return true, "transferred"
    end,
    canSee = function(_, target) return target and target.alive == true end,
    say = function(value, line) value.lastLine = line return true end,
    nowMs = function() return now end,
    stop = function() return true end,
}
SC.Factions = {
    group = function(id) return groups[id] end,
    forceStanding = function(id, standing)
        local group = groups[id]
        if not group then return false, "missing_group" end
        group.standing = standing
        return true, standing
    end,
    describeLocation = function(point)
        return { address = "House near " .. tostring(point.x) .. ", "
            .. tostring(point.y) }
    end,
}
SC.Navigation = {
    request = function(actor, square)
        actor.pathTarget = square
        return true, "path_requested"
    end,
}

function getGameTime()
    return { getWorldAgeHours = function() return hours end }
end
function getPlayer() return player end
function addZombiesInOutfit(x, y, z, count, outfit, female)
    zombieSpawns = zombieSpawns + 1
    local result = { x = x, y = y, z = z, zombie = true,
        outfit = outfit, female = female, dead = false }
    zombies[#zombies + 1] = result
    return { result }
end

local function group(id, moduleActor, site)
    local result = { id = id, standing = "Wary", members = {
        { actorId = moduleActor.id, alive = true } },
        oddball = { id = id, stage = "unmet", site = site } }
    groups[id] = result
    records[moduleActor.id] = { actor = moduleActor }
    return result
end

local lonnieActor = actor("lonnie", 11, 10)
local lonnieSite = { altar = { x = 11, y = 10, z = 0 },
    vestry = { x = 14, y = 10, z = 0 },
    vestryDoor = { x = 13, y = 10, z = 0 } }
local lonnie = group("wedding_lonnie_tackett", lonnieActor, lonnieSite)
doors["13:10"] = { door = true, open = false,
    IsOpen = function(self) return self.open end,
    ToggleDoorActual = function(self) self.open = not self.open end }

check("closed vestry spawns bride", Lonnie.onSpawn(lonnie, lonnieActor) == true)
check("bride is vanilla wedding zombie", zombieSpawns == 1
    and zombies[1].outfit == "WeddingDress" and zombies[1].female == 100)
check("second spawn never duplicates", Lonnie.onSpawn(lonnie, lonnieActor) == true
    and zombieSpawns == 1)
check("axe present", lonnieActor.inv.items[1].kind == "Base.WoodAxe")
check("ceremony unavailable until invited", Lonnie.action(lonnie,
    "perform_ceremony", player) == false)
check("invitation", Lonnie.action(lonnie, "ask_ceremony", player) == true)
check("refusal waits today", Lonnie.action(lonnie, "refuse", player) == true
    and Lonnie.action(lonnie, "ask_ceremony", player) == false)
hours = hours + 24
Lonnie.pulse(lonnie, player, now)
check("invitation returns next day", lonnie.oddball.stage == "invited")
check("no ring no ceremony", Lonnie.action(lonnie,
    "perform_ceremony", player) == false)
local ring = player.inv:AddItem("Base.Ring_Left_RingFinger_Gold")
check("ring and door transferred", Lonnie.action(lonnie,
    "perform_ceremony", player) == true and doors["13:10"].open == true
    and ring.container == lonnieActor.inv and lonnie.oddball.stage == "ceremony")
check("ceremony does not duplicate bride", zombieSpawns == 1)
lonnieActor.alive, lonnie.members[1].alive = false, false
Lonnie.pulse(lonnie, player, now)
check("real death concludes wedding", lonnie.oddball.stage == "married")
check("reception paid once", lonnie.oddball.receptionGiven == true
    and #player.inv.items == 3)
Lonnie.pulse(lonnie, player, now)
check("reception does not duplicate", #player.inv.items == 3)

local angryActor = actor("angry-lonnie", 11, 10)
local angry = group("wedding_lonnie_tackett", angryActor, lonnieSite)
local killedBride = { zombie = true, data = {
    LF_OddballBrideGroupId = angry.id } }
check("tagged bride death triggers hostility", Lonnie.onZombieDead(killedBride)
    == true and angry.oddball.stage == "hostile")

player.x, player.y = 10, 10
local virgilActor = actor("virgil", 11, 10)
local virgilSite = {
    spawn = { x = 11, y = 10, z = 0 },
    mailTargets = {
        { x = 20, y = 20, z = 0, label = "20 Maple" },
        { x = 30, y = 30, z = 0, label = "30 Maple" },
        { x = 40, y = 40, z = 0, label = "40 Maple" },
    },
    homeTarget = { x = 50, y = 50, z = 0, label = "Virgil's porch" },
    homeZombie = { x = 51, y = 50, z = 0 },
}
local virgil = group("postman_virgil_toombs", virgilActor, virgilSite)
check("five letters and hammer seeded", Virgil.onSpawn(virgil, virgilActor)
    == true and #virgilActor.inv.items == 6)
check("repeat spawn cannot duplicate mail", Virgil.onSpawn(virgil,
    virgilActor) == true and #virgilActor.inv.items == 6)
check("mail route issued", Virgil.action(virgil, "accept_route", player)
    == true and virgil.oddball.stage == "route" and #player.inv.items == 6)
Virgil.pulse(virgil, player, now)
check("wrong address cannot deliver", not virgil.oddball.delivered[1])
for slot, target in ipairs(virgilSite.mailTargets) do
    player.x, player.y = target.x, target.y
    Virgil.pulse(virgil, player, now)
    check("verified delivery " .. tostring(slot), virgil.oddball.delivered[slot] == true)
end
check("route complete", virgil.oddball.stage == "route_complete")
player.x, player.y = 10, 10
check("one payout", Virgil.action(virgil, "claim_reward", player)
    == true and virgil.oddball.rewarded == true)
local paidCount = #player.inv.items
check("reward idempotent", Virgil.action(virgil, "claim_reward", player)
    == true and #player.inv.items == paidCount)
check("fourth sealed letter issued", Virgil.action(virgil,
    "take_final_letter", player) == true
    and virgil.oddball.stage == "final_delivery"
    and virgil.oddball.issued[4] == true)
player.x, player.y = 50, 50
player.z = 1
Virgil.pulse(virgil, player, now)
check("different floor cannot deliver final letter",
    virgil.oddball.delivered[4] ~= true and zombieSpawns == 1)
player.z = 0
Virgil.pulse(virgil, player, now)
check("final letter delivered at doorstep", virgil.oddball.delivered[4] == true
    and virgil.oddball.stage == "awaiting_wife")
Virgil.pulse(virgil, player, now)
check("wife spawns at real home", virgil.oddball.wifeSpawned == true
    and zombieSpawns == 2 and zombies[2].x == 51)
check("wife never duplicates", Virgil.pulse(virgil, player, now) == true
    and zombieSpawns == 2)
check("wife death requires return", Virgil.onZombieDead(zombies[2]) == true
    and virgil.oddball.stage == "return_to_post"
    and Virgil.canRecruit(virgil) == false)
check("Virgil stayed at post office", virgilActor.x == 11
    and virgilActor.y == 10)
player.x, player.y = 10, 10
Virgil.pulse(virgil, player, now)
check("return unlocks final choice", Virgil.canRecruit(virgil) == true)
check("stay ending at post office", Virgil.action(virgil,
    "stay", player) == true and virgil.oddball.stage == "stayed")

local theftActor = actor("theft-virgil", 11, 10)
local theft = group("postman_virgil_toombs", theftActor, virgilSite)
Virgil.onSpawn(theft, theftActor)
local stolen = theftActor.inv.items[2]
theftActor.inv:Remove(stolen)
player.inv:AddItem(stolen)
Virgil.pulse(theft, player, now)
check("unissued satchel mail theft hostile", theft.oddball.stage == "hostile"
    and theft.standing == "Hostile")

local readActor = actor("read-virgil", 11, 10)
local readGroup = group("postman_virgil_toombs", readActor, virgilSite)
Virgil.onSpawn(readGroup, readActor)
local privateLetter = readActor.inv.items[2]
check("ordinary letter ignored", Virgil.isSealedMail({ kind =
    "Base.LetterHandwritten" }) == false)
check("sealed mail recognized", Virgil.isSealedMail(privateLetter) == true)
check("opening tagged letter provokes Virgil", Virgil.openMailFor(
    privateLetter, player) == true and readGroup.oddball.stage == "hostile")

print("ODDBALL_LONNIE_VIRGIL_OK " .. tostring(checks))
