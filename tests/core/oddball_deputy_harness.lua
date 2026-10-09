-- SPDX-License-Identifier: MIT
-- Deterministic contract for Rhonda's badge, captives, checkpoint, and gear.

local SC = SurvivorCompanion
local Deputy = SC.OddballDeputy
local now = 1000
local records, groups, worldDrops = {}, {}, {}
local releaseBlocked = false
local checks = 0

local function check(name, condition)
    if not condition then error("DEPUTY_FAIL " .. name, 2) end
    checks = checks + 1
end

local function inventory()
    local result = { items = {} }
    function result:AddItem(kind)
        local item = { kind = kind, container = self }
        function item:getFullType() return self.kind end
        function item:getContainer() return self.container end
        function item:setCurrentAmmoCount(count) self.ammo = count end
        function item:setName(name) self.name = name end
        function item:setCustomName(value) self.customName = value end
        function item:addPage(number, text) self.pages = self.pages or {}
            self.pages[number] = text end
        self.items[#self.items + 1] = item
        return item
    end
    function result:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    function result:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then table.remove(self.items, index) item.container = nil return end
        end
    end
    return result
end

local function actor(id, x, y)
    local value = { id = id, x = x, y = y, z = 0, inv = inventory(), alive = true }
    function value:getInventory() return self.inv end
    function value:getPrimaryHandItem() return self.primary end
    function value:getSecondaryHandItem() return self.secondary end
    function value:setPrimaryHandItem(item) self.primary = item end
    function value:setSecondaryHandItem(item) self.secondary = item end
    return value
end

local player = actor("player", 10, 10)
local follower = actor("follower", 10, 11)
records.follower = { id = "follower", actor = follower, recruited = true }

SC.Registry = {
    byId = function(id) return records[id] end,
    living = function() return { follower } end,
}
SC.GameplayUtil = {
    call = function(object, method, ...)
        if object == nil or type(object[method]) ~= "function" then return nil, false end
        local okay, result = pcall(object[method], object, ...)
        return okay and result or nil, okay
    end,
    idOf = function(value) return value and value.id end,
    position = function(value)
        return value and value.x, value and value.y, value and value.z or 0
    end,
    isValidActor = function(value) return value and value.alive == true end,
    distance = function(a, b)
        if not a or not b then return math.huge end
        local dx, dy = a.x - b.x, a.y - b.y
        return math.sqrt(dx * dx + dy * dy)
    end,
    canSee = function() return true end,
    config = function() return true end,
    say = function(value, line) value.lastLine = line return true end,
    inventory = function(value) return value and value.inv end,
    inventoryItemsDeep = function(container) return container and container.items or {} end,
    itemType = function(item) return item and item.kind end,
    instanceOf = function(item, kind) return item and item.weapon == true
        and (kind == "HandWeapon" or kind == "zombie.inventory.types.HandWeapon") end,
    hasMethod = function(item, method) return item and type(item[method]) == "function" end,
    squareOf = function(value) return value and { x = value.x, y = value.y, z = value.z } end,
    containerContainsIdentity = function(container, item) return container:contains(item) end,
    dropItem = function(container, square, item)
        if not container:contains(item) then return false, "missing_item" end
        container:Remove(item)
        worldDrops[#worldDrops + 1] = item
        return true, item
    end,
    addItem = function(container, kind) return container:AddItem(kind) end,
    modData = function(value) value.data = value.data or {} return value.data end,
    stop = function() return true end,
    move = function() return true, "posed" end,
    nowMs = function() return now end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
}
SC.Factions = {
    forceStanding = function(id, standing)
        local group = groups[id]
        if not group then return false, "missing_group" end
        if group.permanentHostility and standing ~= "Hostile" then
            return false, "permanent_hostility"
        end
        group.standing = standing
        group.lifecycle = standing == "Hostile" and "hostile" or "settled"
        return true, standing
    end,
    releaseCaptiveMember = function(id, key)
        if releaseBlocked then return false, "captive_actor_unloaded" end
        local group = groups[id]
        for _, member in ipairs(group.members) do
            if member.key == key and member.role == "captive" and member.alive ~= false then
                member.departed = true
                return true, "released"
            end
        end
        return false, "not_a_captive"
    end,
}

local function group(id)
    local rhonda = actor(id .. "-rhonda", 12, 10)
    local captive1 = actor(id .. "-captive-1", 13, 11)
    local captive2 = actor(id .. "-captive-2", 13, 12)
    local result = { id = id, standing = "Wary", lifecycle = "settled",
        members = {
            { key = "member-1", actorId = rhonda.id, role = "leader", alive = true },
            { key = "member-2", actorId = captive1.id, role = "captive", alive = true },
            { key = "member-3", actorId = captive2.id, role = "captive", alive = true },
        }, oddball = { id = "checkpoint_deputy_rhonda", stage = "unmet",
            site = { spawn = { x = 12, y = 10, z = 0 },
                house = { bounds = { x1 = 9, y1 = 9, x2 = 15, y2 = 15 } } } } }
    groups[id] = result
    records[rhonda.id] = { id = rhonda.id, actor = rhonda, recruited = false }
    records[captive1.id] = { id = captive1.id, actor = captive1, recruited = false }
    records[captive2.id] = { id = captive2.id, actor = captive2, recruited = false }
    return result, rhonda, captive1, captive2
end

local badgeGroup, rhonda = group("badge")
check("deputy_gear", Deputy.onSpawn(badgeGroup, rhonda) == true
    and #rhonda.inv.items == 3 and rhonda.primary ~= nil)
check("captive_no_gear", Deputy.onSpawn(badgeGroup,
    records["badge-captive-1"].actor) == true
    and #records["badge-captive-1"].actor.inv.items == 0)
Deputy.pulse(badgeGroup, player, now)
check("checkpoint_started", badgeGroup.oddball.stage == "checkpoint"
    and badgeGroup.oddball.checkpointDeadlineAt == now + 30000)
check("reaction", follower.lastLine == "Is she arresting us? Is that what this is?")
check("no_badge", Deputy.action(badgeGroup, "show_badge", player) == false)
player.inv:AddItem("Base.Badge")
releaseBlocked = true
local accepted = Deputy.action(badgeGroup, "show_badge", player)
check("badge_release_waits", accepted == true
    and badgeGroup.oddball.stage == "badge_release_pending"
    and Deputy.canRecruit(badgeGroup) == false)
releaseBlocked = false
Deputy.pulse(badgeGroup, player, now + 100)
check("badge_releases_both", badgeGroup.members[2].departed == true
    and badgeGroup.members[3].departed == true
    and badgeGroup.oddball.stage == "officer"
    and badgeGroup.standing == "Trusted")
check("deputy_recruitable", Deputy.canRecruit(badgeGroup) == true)
check("captives_no_human_combat", Deputy.intentFor(
    records["badge-captive-1"].actor, player, {}, badgeGroup).mode == "deputy_captive")

local compliance, officer = group("compliance")
local playerWeapon = player.inv:AddItem("Base.Axe")
playerWeapon.weapon = true
player.primary = playerWeapon
local followerWeapon = follower.inv:AddItem("Base.Crowbar")
followerWeapon.weapon = true
follower.primary = followerWeapon
Deputy.pulse(compliance, player, now)
local complied = Deputy.action(compliance, "surrender_weapons", player)
check("party_weapons_dropped", complied == true and #worldDrops == 2
    and player.primary == nil and follower.primary == nil)
check("citation", compliance.oddball.stage == "processed"
    and player.inv.items[#player.inv.items].kind == "Base.SheetPaper2"
    and player.inv.items[#player.inv.items].pages[1]:find("curfew violation", 1, true)
    and player.inv.items[#player.inv.items].data.SC_CitationFactionId == "compliance")
check("processed_no_timeout", Deputy.pulse(compliance, player, now + 60000) == true
    and compliance.standing ~= "Hostile")

local refused = group("refused")
Deputy.pulse(refused, player, now)
Deputy.pulse(refused, player, now + 20001)
check("warning_line", records["refused-rhonda"].actor.lastLine:find("dipshit", 1, true))
Deputy.pulse(refused, player, now + 30001)
check("thirty_second_refusal", refused.standing == "Hostile"
    and refused.permanentHostility == true)
check("captive_still_noncombat_hostile", Deputy.intentFor(
    records["refused-captive-1"].actor, player, {}, refused).mode == "deputy_captive")

local bypass = group("bypass")
player.x = 8
Deputy.pulse(bypass, player, now)
check("outside_station_no_challenge", bypass.oddball.stage == "unmet")
player.x = 10
Deputy.pulse(bypass, player, now)
player.x = 30
Deputy.pulse(bypass, player, now + 1000)
check("leaving_active_checkpoint_refuses", bypass.standing == "Hostile")
player.x = 10

local force = group("force")
Deputy.pulse(force, player, now)
check("forced_release_fight", Deputy.action(force, "force_release", player) == true
    and force.standing == "Hostile" and force.members[2].departed == true)

local fallen = group("fallen")
fallen.members[1].alive = false
check("death_frees_captives", Deputy.pulse(fallen, player, now) == true
    and fallen.members[2].departed == true and fallen.members[3].departed == true)

local resumed = group("resumed")
Deputy.pulse(resumed, player, now)
resumed.oddball.checkpointSession = "stale-session"
now = now + 30001
Deputy.pulse(resumed, player, now)
check("load_resets_timer", resumed.standing ~= "Hostile"
    and resumed.oddball.checkpointDeadlineAt == now + 30000)

print("Deputy contract PASS: " .. tostring(checks) .. " checks")
