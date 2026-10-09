-- SPDX-License-Identifier: MIT
-- Focused negative controls for Clem's opt-in duel and the Purdy body clue.

local SC = SurvivorCompanion
local Clem, Purdy = SC.OddballClem, SC.OddballPurdy
local checks, now, timeOfDay = 0, 1000, 11.5
local groups, actors, squares = {}, {}, {}
local spawnedBodies, transfers = 0, 0
local visionOverrides, blockedWindowEdges, unloadedSquares = {}, {}, {}
local windowCrossingsEnabled = true

local function check(name, value)
    if not value then error("ODDBALL_12_13_FAIL " .. name, 2) end
    checks = checks + 1
end

local function key(x, y, z)
    return tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))
        .. ":" .. tostring(math.floor(z or 0))
end

local function square(x, y, z)
    local id = key(x, y, z)
    if squares[id] then return squares[id] end
    local value = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0),
        static = {}, road = math.floor(x) % 4 == 0 }
    function value:getStaticMovingObjects() return self.static end
    function value:getFloor()
        return { getSprite = function()
            return { getName = function()
                return self.road and "blends_street_01" or "blends_natural_01"
            end }
        end }
    end
    function value:getRoom() return nil end
    function value:isCanSee() return false end
    function value:testVisionAdjacent(dx, dy, dz)
        local from = key(self.x + dx, self.y + dy, self.z + dz)
        local edge = from .. "->" .. key(self.x, self.y, self.z)
        if visionOverrides[edge] then return visionOverrides[edge] end
        if windowCrossingsEnabled and self.z == 1 and dz == 0
            and dy == 1 and self.y == 0 and self.x <= 2 then
            return "ClearThroughWindow"
        end
        return "Clear"
    end
    function value:isWindowBlockedTo(other)
        local selfKey = key(self.x, self.y, self.z)
        local otherKey = key(other.x, other.y, other.z)
        return blockedWindowEdges[selfKey .. "->" .. otherKey] == true
            or blockedWindowEdges[otherKey .. "->" .. selfKey] == true
    end
    squares[id] = value
    return value
end

local function inventory()
    local value = { items = {} }
    function value:AddItem(kind)
        local item = { kind = kind, container = self, data = {} }
        function item:getFullType() return self.kind end
        function item:getContainer() return self.container end
        function item:setCurrentAmmoCount(count) self.ammo = count end
        function item:setName(name) self.name = name end
        function item:setCustomName() end
        self.items[#self.items + 1] = item
        return item
    end
    function value:Remove(item)
        for index, existing in ipairs(self.items) do
            if existing == item then
                table.remove(self.items, index)
                item.container = nil
                return
            end
        end
    end
    return value
end

local function actor(id, x, y, z)
    local value = { id = id, x = x, y = y, z = z or 0,
        health = 100, inv = inventory(), alive = true }
    function value:getInventory() return self.inv end
    function value:getPrimaryHandItem() return self.primary end
    function value:setPrimaryHandItem(item) self.primary = item end
    function value:setSecondaryHandItem(item) self.secondary = item end
    function value:CanSee() return false end
    function value:getPlayerNum() return 0 end
    function value:playSound(name) self.sound = name end
    actors[id] = value
    return value
end

getGameTime = function()
    return { getTimeOfDay = function() return timeOfDay end }
end
SC.GameplayUtil = {
    call = function(object, method, ...)
        if not object or type(object[method]) ~= "function" then return nil, false end
        local okay, result = pcall(object[method], object, ...)
        return okay and result or nil, okay
    end,
    idOf = function(value) return value and value.id end,
    position = function(value)
        return value and value.x, value and value.y, value and value.z or 0
    end,
    isValidActor = function(value) return value and value.alive == true end,
    nativeHealth = function(value) return value and value.health or 0 end,
    distance = function(a, b)
        if not a or not b then return math.huge end
        local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
        return math.sqrt(dx * dx + dy * dy + dz * dz * 9)
    end,
    stableHash = function(value)
        if tostring(value):find("cap", 1, true) then return 0 end
        return 1
    end,
    nowMs = function() return now end,
    config = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(value) return value and value.items or {} end,
    itemType = function(value) return value and value.kind end,
    addItem = function(value, kind) return value:AddItem(kind) end,
    transferItemVerified = function(source, target, item)
        source:Remove(item)
        target.items[#target.items + 1] = item
        item.container = target
        transfers = transfers + 1
        return true, "transferred"
    end,
    modData = function(value) value.data = value.data or {} return value.data end,
    stop = function(value) value.stopped = true return true end,
    move = function(value, _, intent) value.lastAction = intent.action
        return true, intent.action end,
    gridSquare = function(x, y, z)
        if unloadedSquares[key(x, y, z)] then return nil end
        return square(x, y, z)
    end,
    isSafeSpawnSquare = function() return true end,
    squareStaticMovingObjects = function(value, callback)
        if value then for _, entry in ipairs(value.static) do callback(entry) end end
    end,
    instanceOf = function(value, kind)
        return value and value.__class == kind
    end,
    canSee = function() return false end,
}
SC.Registry = { byId = function(id)
    return actors[id] and { id = id, actor = actors[id] } or nil
end }
SC.Factions = { forceStanding = function(id, standing)
    local group = groups[id]
    if not group then return false, "missing_group" end
    group.standing = standing
    group.lifecycle = standing == "Hostile" and "hostile" or "settled"
    return true, standing
end }
SC.Combat = { friendlyFireBlocked = function() return false end }
SC.Navigation = { request = function(value, target)
    value.lastNavigation = target
    return true, "navigation_requested"
end }

createRandomDeadBody = function(location)
    spawnedBodies = spawnedBodies + 1
    local body = { __class = "IsoDeadBody", data = {}, square = location,
        container = inventory() }
    function body:getContainer() return self.container end
    location.static[#location.static + 1] = body
    return body
end

local player = actor("player", 8, 0)
local function clemGroup(id)
    local clem = actor(id .. "-clem", 0, 0)
    local group = { id = id, standing = "Wary", lifecycle = "settled",
        members = { { key = "member-1", actorId = clem.id, alive = true } },
        oddball = { id = "duelist_clem_sutter", stage = "challenged",
            site = { spawn = { x = 0, y = 0, z = 0 },
                duelGround = { x = 0, y = 0, z = 0 } } } }
    groups[id] = group
    return group, clem
end

local real, realActor = clemGroup("real")
check("real_weapon_seeded_once", Clem.onSpawn(real, realActor) == true
    and Clem.onSpawn(real, realActor) == true
    and #realActor.inv.items == 1
    and realActor.inv.items[1].kind == "Base.Revolver")
check("noon_gate", Clem.action(real, "accept_duel", player) == false
    and real.standing == "Wary")
timeOfDay = 12.2
check("noon_accept", Clem.action(real, "accept_duel", player) == true)
Clem.pulse(real, player, now)
check("eight_tile_setup", real.oddball.stage == "duel_countdown"
    and real.standing == "Wary")
now = now + 3100
Clem.pulse(real, player, now)
check("delayed_native_draw", real.oddball.stage == "duel_draw_wait"
    and real.standing == "Hostile"
    and Clem.intentFor(realActor, player, nil, real).mode == "clem_wait")
now = real.oddball.firstShotAt - 1
Clem.pulse(real, player, now)
check("no_early_shot", real.oddball.stage == "duel_draw_wait")
now = now + 1
Clem.pulse(real, player, now)
check("real_shot_uses_faction_combat", real.oddball.stage == "duel_active"
    and Clem.intentFor(realActor, player, nil, real).mode == "hostile")
player.health = 80
Clem.pulse(real, player, now + 1)
check("first_player_hit_stops", real.oddball.stage == "lost"
    and real.standing == "Wary")
local hitRelay, hitRelayActor = clemGroup("hit-relay")
hitRelay.oddball.stage = "duel_active"
hitRelay.oddball.capGun = false
hitRelay.standing = "Hostile"
check("native_hit_event_stops_immediately",
    Clem.action(hitRelay, "hit_player", player, { attacker = hitRelayActor })
    and hitRelay.oddball.stage == "lost" and hitRelay.standing == "Wary")

local declined = clemGroup("declined")
check("decline_without_hostility", Clem.action(declined, "decline_duel", player)
    and declined.standing == "Wary" and declined.oddball.stage == "declined")

local won, wonActor = clemGroup("won")
Clem.onSpawn(won, wonActor)
wonActor.inv:AddItem("Base.Hat_Cowboy")
Clem.action(won, "accept_duel", player)
Clem.pulse(won, player, now)
check("first_clem_hit_stops", Clem.action(won, "hurt", player)
    and won.oddball.stage == "won" and won.standing == "Trusted"
    and Clem.canRecruit(won) == true)
check("gear_is_transferred_once", Clem.action(won, "claim_gear", player)
    and transfers == 2 and won.oddball.gearClaimed == true
    and Clem.action(won, "claim_gear", player) == false)

local cap, capActor = clemGroup("cap")
check("cap_gun_chosen", Clem.onSpawn(cap, capActor) == true
    and cap.oddball.capGun == true
    and capActor.inv.items[1].kind == "Base.Revolver_CapGun")
now = now + 100
Clem.action(cap, "accept_duel", player)
Clem.pulse(cap, player, now)
now = now + 3100
Clem.pulse(cap, player, now)
check("cap_never_hostile", cap.oddball.stage == "duel_draw_wait"
    and cap.standing == "Wary")
now = cap.oddball.firstShotAt
Clem.pulse(cap, player, now)
check("cap_bang_no_damage", cap.oddball.stage == "embarrassed"
    and cap.standing == "Wary" and player.health == 80)

local pa = actor("pa", 0.5, 1.5, 1)
local son1 = actor("son1", 1.5, 1.5, 1)
local son2 = actor("son2", 2.5, 1.5, 1)
local purdy = { id = "purdy", standing = "Wary", lifecycle = "settled",
    members = {
        { key = "member-1", actorId = "pa", alive = true },
        { key = "member-2", actorId = "son1", alive = true },
        { key = "member-3", actorId = "son2", alive = true },
    }, oddball = { id = "sniper_purdy_clan", stage = "unmet",
        site = { anchor = { x = 0, y = 0, z = 0 },
            memberSpawns = {
                { x = 0, y = 1, z = 1 }, { x = 1, y = 1, z = 1 },
                { x = 2, y = 1, z = 1 } },
            tradePost = { x = 3, y = 3, z = 0 },
            house = { bounds = { x1 = -2, y1 = -2, x2 = 4, y2 = 4 } } } } }
groups.purdy = purdy
check("three_real_weapons", Purdy.onSpawn(purdy, pa)
    and Purdy.onSpawn(purdy, son1) and Purdy.onSpawn(purdy, son2)
    and Purdy.onSpawn(purdy, pa) and #pa.inv.items == 2
    and pa.inv.items[1].kind == "Base.HuntingRifle"
    and pa.inv.items[2].kind == "Base.308Box"
    and pa.inv.items[1].ammo == 4
    and son1.inv.items[1].kind == "Base.VarmintRifle"
    and son1.inv.items[2].kind == "Base.556Box"
    and son2.inv.items[1].kind == "Base.DoubleBarrelShotgun")
player.x = 150
player.y = 0
now = now + 10000
Purdy.pulse(purdy, player, now)
check("one_roadside_body", spawnedBodies == 1
    and purdy.oddball.tuckerStatus == "placed")
local target = purdy.oddball.tuckerSquare
local roadBody = square(target.x, target.y, 0).static[1]
check("letter_and_identity_tag", roadBody.data.LF_PurdyGroupId == "purdy"
    and roadBody.data.LF_PurdyToken == purdy.oddball.tuckerToken
    and roadBody.container.items[1].kind == "Base.LetterHandwritten")
now = now + 5000
Purdy.pulse(purdy, player, now)
check("no_duplicate_on_repeat", spawnedBodies == 1)
player.x, player.y = 4, 0
now = now + 5000
Purdy.pulse(purdy, player, now)
check("physical_body_required", purdy.oddball.tuckerReturned ~= true)
now = now + 3100
Purdy.pulse(purdy, player, now)
check("warn_before_attack", purdy.standing == "Hostile")
local fake = createRandomDeadBody(square(3, 0, 0))
check("foreign_corpse_rejected", Purdy.action(purdy, "return_tucker", player)
    == false and purdy.standing == "Hostile")
local origin, home = square(target.x, target.y, 0), square(1, 0, 0)
for index, body in ipairs(origin.static) do
    if body == roadBody then table.remove(origin.static, index) break end
end
home.static[#home.static + 1] = roadBody
roadBody.square = home
check("tagged_body_reconciles", Purdy.action(purdy, "return_tucker", player)
    and purdy.oddball.tuckerReturned == true and purdy.standing == "Wary"
    and purdy.barterUnlocked == true)
now = now + 10000
Purdy.pulse(purdy, player, now)
check("resolution_once_no_respawn", spawnedBodies == 2
    and Purdy.action(purdy, "return_tucker", player)
    and purdy.standing == "Wary")
local leaderHome = Purdy.update(pa, player, {},
    Purdy.intentFor(pa, player, {}, purdy), purdy)
check("reconciled_leader_descends_to_trade_post", leaderHome == true
    and pa.lastNavigation and pa.lastNavigation.x == 3
    and pa.lastNavigation.y == 3 and pa.lastNavigation.z == 0)
Purdy.update(son1, player, {}, Purdy.intentFor(son1, player, {}, purdy), purdy)
check("reconciled_son_keeps_upper_perch", son1.lastNavigation == nil)

-- Half-tile positions mirror real character coordinates. The player is far
-- enough south that the shot exits the upper window before dropping a floor.
player.x, player.y = 4.5, -4.5
purdy.standing = "Hostile"
local handled = Purdy.update(son2, player, {},
    Purdy.intentFor(son2, player, {}, purdy), purdy)
check("native_window_lane_fires_without_cached_actor_sight", handled == true
    and son2:CanSee(player) == false
    and son2.lastAction == "attack_firearm")
local windowEdge = key(2, 1, 1) .. "->" .. key(2, 0, 1)
blockedWindowEdges[windowEdge] = true
son2.lastAction = nil
Purdy.update(son2, player, {}, Purdy.intentFor(son2, player, {}, purdy), purdy)
check("barricaded_window_refuses_shot", son2.lastAction ~= "attack_firearm")
blockedWindowEdges[windowEdge] = nil
visionOverrides[windowEdge] = "Blocked"
son2.lastAction = nil
Purdy.update(son2, player, {}, Purdy.intentFor(son2, player, {}, purdy), purdy)
check("wall_refuses_shot", son2.lastAction ~= "attack_firearm")
visionOverrides[windowEdge] = "ClearThroughClosedDoor"
son2.lastAction = nil
Purdy.update(son2, player, {}, Purdy.intentFor(son2, player, {}, purdy), purdy)
check("closed_door_refuses_shot", son2.lastAction ~= "attack_firearm")
visionOverrides[windowEdge] = nil
windowCrossingsEnabled = false
son2.lastAction = nil
Purdy.update(son2, player, {}, Purdy.intentFor(son2, player, {}, purdy), purdy)
check("no_upper_window_refuses_shot", son2.lastAction ~= "attack_firearm")
windowCrossingsEnabled = true
unloadedSquares[key(2, 0, 1)] = true
son2.lastAction = nil
Purdy.update(son2, player, {}, Purdy.intentFor(son2, player, {}, purdy), purdy)
check("unloaded_lane_refuses_shot", son2.lastAction ~= "attack_firearm")
unloadedSquares[key(2, 0, 1)] = nil
purdy.oddball.tuckerReturned = false
son1.alive, son2.alive = false, false
pa.lastAction = nil
Purdy.update(pa, player, {}, Purdy.intentFor(pa, player, {}, purdy), purdy)
check("leader_has_clear_window_lane_without_ally",
    pa.lastAction == "attack_firearm")
son1.alive = true
son1.x, son1.y = 0.5, 0.5
pa.lastAction = nil
Purdy.update(pa, player, {}, Purdy.intentFor(pa, player, {}, purdy), purdy)
check("clanmate_in_upper_window_lane_blocks_shot",
    pa.lastAction ~= "attack_firearm")

print("ODDBALL_12_13_PASS " .. tostring(checks) .. " checks")
