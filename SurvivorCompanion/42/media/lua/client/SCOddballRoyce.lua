-- SPDX-License-Identifier: MIT
-- Lucky's betrayal uses one real, tagged inventory transfer. The same actor
-- returns by the normal roamer snapshot path for his apology and warning.

local SC = SurvivorCompanion
SC.OddballRoyce = SC.OddballRoyce or {}
local Royce = SC.OddballRoyce
local ID = "trickster_lucky_royce"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.visit = tonumber(value.visit) or 1
    value.stage = value.stage or "unmet"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function stashPoint(value)
    return value.site and (value.site.stashEntry
        or value.site.house and value.site.house.anchor)
end

local function nearbyZombies(position, radius)
    if not position then return 0 end
    local count = 0
    radius = radius or 8
    for dx = -radius, radius do
        for dy = -radius, radius do
            if dx * dx + dy * dy <= radius * radius then
                local square = U().gridSquare(position.x + dx,
                    position.y + dy, position.z or 0)
                local moving = square and select(1, U().call(square,
                    "getMovingObjects"))
                if moving and SC.NativeList then
                    for index = 0, math.min(15,
                        SC.NativeList.size(moving) - 1) do
                        local actor = SC.NativeList.get(moving, index)
                        if actor and U().isZombie(actor) then count = count + 1 end
                    end
                end
            end
        end
    end
    return count
end

local function spawnStash(value, group)
    if value.stashSpawned then return true end
    if type(addZombiesInOutfit) ~= "function" then
        return false, "zombie_spawn_unavailable"
    end
    local count = 0
    for _, post in ipairs(value.site and value.site.stashSpawns or {}) do
        local square = U().gridSquare(post.x, post.y, post.z or 0)
        if square and U().isSafeSpawnSquare(square) then
            local okay, list = pcall(addZombiesInOutfit,
                post.x, post.y, post.z or 0, 1, nil, 50)
            if okay and list and SC.NativeList then
                for index = 0, math.min(3, SC.NativeList.size(list) - 1) do
                    local zombie = SC.NativeList.get(list, index)
                    local data = zombie and U().modData(zombie)
                    if type(data) == "table" then
                        data.lfRoyceStashGroupId = group.id
                        count = count + 1
                    end
                end
            end
        end
    end
    if count == 0 then return false, "stash_zombies_not_spawned" end
    value.stashSpawned = count
    return true, "stash_zombies_released"
end

local function companionPackItem(player, thief)
    if not SC.Registry or type(SC.Registry.living) ~= "function" then return nil end
    for _, actor in ipairs(SC.Registry.living()) do
        local id = U().idOf(actor)
        local record = id and SC.Registry.byId(id) or nil
        if record and record.recruited == true
            and U().distance(actor, player) <= 8
            and U().distance(actor, thief) <= 3 then
            local root = U().inventory(actor)
            for _, item in ipairs(root and U().inventoryItemsDeep(root,
                120, 6) or {}) do
                local source = select(1, U().call(item, "getContainer"))
                local kind = U().itemType(item)
                if source and source ~= root and type(kind) == "string"
                    and not string.find(kind, "Radio", 1, true)
                    and not string.find(kind, "Key", 1, true) then
                    return item, source, id
                end
            end
        end
    end
    return nil
end

local function stealOnce(group, player)
    local value = story(group)
    if value.stolen == true then return true, "already_stolen" end
    local actor = actorFor(group)
    local item, source, ownerId = companionPackItem(player, actor)
    if not item then return false, "no_fellow_pack_item_in_reach" end
    local destination = actor and U().inventory(actor)
    if not destination or not U().transferItemVerified(source,
        destination, item) then return false, "theft_transfer_failed" end
    local data = U().modData(item)
    if type(data) == "table" then data.lfRoyceStolenGroupId = group.id end
    value.stolen = true
    value.stolenOwnerId = ownerId
    value.stolenType = U().itemType(item)
    local clean = U().config and U().config("profanityEnabled") == false
    U().say(actor, clean
        and "Aw, heck. You weren't supposed to live through that part."
        or "Aw, hell. You weren't supposed to live through that part.")
    return true, "one_pack_item_stolen"
end

local function stolenItem(actor, groupId)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfRoyceStolenGroupId == groupId then
            return item
        end
    end
    return nil
end

local function oneDollar(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        120, 6) or {}) do
        if U().itemType(item) == "Base.Money" then return item end
    end
    return nil
end

local function hordeNear(actor)
    if type(getCell) ~= "function" or not actor or not SC.NativeList then
        return nil
    end
    local okay, cell = pcall(getCell)
    local list = okay and cell and select(1, U().call(cell,
        "getZombieList")) or nil
    if not list then return nil end
    local ax, ay, az = U().position(actor)
    if not ax then return nil end
    local bins = {}
    for index = 0, math.min(1023, SC.NativeList.size(list) - 1) do
        local zombie = SC.NativeList.get(list, index)
        local x, y, z
        if zombie then x, y, z = U().position(zombie) end
        if x and math.floor(z or 0) == math.floor(az or 0)
            and (x - ax) ^ 2 + (y - ay) ^ 2 <= 60 * 60 then
            local bx, by = math.floor(x / 16), math.floor(y / 16)
            local key = bx .. ":" .. by
            local bin = bins[key] or { count = 0,
                x = bx * 16 + 8, y = by * 16 + 8, z = z or 0 }
            bin.count = bin.count + 1
            bins[key] = bin
            if bin.count >= 6 then return bin end
        end
    end
    return nil
end

local function moveOn(group, player, nextVisit)
    local value = story(group)
    if not SC.Factions
        or type(SC.Factions.hibernateOddballRoamer) ~= "function" then
        return false, "roamer_lifecycle_unavailable"
    end
    local gone = SC.Factions.hibernateOddballRoamer(group.id, player)
    if not gone then return false, "royce_departure_pending" end
    value.stage = "awaiting_site"
    value.nextVisit = nextVisit
    value.awaitingStageSite = true
    value.nextSearchAt = nil
    return true, "royce_moved_on"
end

function Royce.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "royce_unavailable" end
    if value.stage == "unmet" then value.stage = "bait"
    elseif value.stage == "arriving" then
        value.visit = tonumber(value.nextVisit) or value.visit
        value.nextVisit = nil
        value.stage = value.visit == 2 and "apology" or "warning"
    end
    return true, "royce_ready"
end

function Royce.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local member = group.members and group.members[1]
    if value.stage == "awaiting_site" and member and member.hibernated then
        if current < (tonumber(value.nextSearchAt) or 0) then
            return true, "road_search_cooldown" end
        value.nextSearchAt = current + 20000
        local prior = value.site and (value.site.wake or value.site.spawn)
        local site = SC.Oddballs and SC.Oddballs.findRoamerLandmark
            and SC.Oddballs.findRoamerLandmark(player, prior, false, 160)
        if not site then return true, "next_road_unloaded" end
        value.site.wake, value.site.spawn = site.spawn, site.spawn
        value.site.anchor = site.spawn
        value.site.house = { id = site.house.id,
            anchor = site.house.anchor, bounds = site.house.bounds }
        value.awaitingStageSite = nil
        value.stage = "arriving"
        return true, "royce_next_meeting_ready"
    end
    if member and member.hibernated
        and (value.stage == "betrayed" or value.stage == "apology_done") then
        value.nextVisit = value.stage == "betrayed" and 2 or 3
        value.stage = "awaiting_site"
        value.awaitingStageSite = true
        return true, "royce_departed_offscreen"
    end
    local actor = actorFor(group)
    if not actor then return true, "royce_unloaded" end
    if near(group, player) and value.metVisit ~= value.visit then
        value.metVisit = value.visit
        group.discovered = true
        U().say(actor, value.visit == 1
            and "Friend! Got a sweet little spot just over here. Trust me."
            or value.visit == 2
                and "No hard feelings? Business is business. Here, half price."
                or "I'm a changed man. Partly. Mostly. I'll keep an eye on the road.")
    end
    if value.stage == "ambush" then
        local stash = stashPoint(value)
        if stash and player and U().distance(player, stash) <= 18 then
            if not value.stashSpawned then spawnStash(value, group) end
            if value.stashSpawned and current >= (tonumber(value.nextTheftCheckAt) or 0) then
                value.nextTheftCheckAt = current + 2000
                if nearbyZombies(stash, 8) > 0
                    and U().distance(player, stash) <= 10 then
                    local stolen = stealOnce(group, player)
                    if stolen then value.stage = "betrayed" end
                end
            end
        end
    elseif value.stage == "warning"
        and current >= (tonumber(value.nextHordeCheckAt) or 0) then
        value.nextHordeCheckAt = current + 15000
        local horde = hordeNear(actor)
        if horde then
            value.stage = "warned"
            value.horde = { x = horde.x, y = horde.y, z = horde.z,
                count = horde.count }
            U().say(actor, "Six or more dead at " .. horde.x .. ", "
                .. horde.y .. ". Take the other road. I owe you that much.")
        end
    end
    local departure = (value.stage == "betrayed" and 2)
        or (value.stage == "apology_done" and 3) or nil
    if departure then
        if player and U().canSee(player, actor) == true then
            value.unseenSince = nil
        else
            value.unseenSince = value.unseenSince or current
            if current - value.unseenSince >= 45000 then
                return moveOn(group, player, departure)
            end
        end
    end
    return true, value.stage
end

function Royce.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    return { mode = "royce_guide", priority = 30 }
end

function Royce.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "royce_guide" then return false end
    local value = story(group)
    local destination = value.stage == "ambush" and stashPoint(value)
        or value.site and (value.site.wake or value.site.spawn)
    if not destination then return true, "road_post_unavailable" end
    local x, y, z = U().position(actor)
    if x and z == (destination.z or 0)
        and (x - destination.x) ^ 2 + (y - destination.y) ^ 2 <= 2.25 then
        return true, "royce_waiting"
    end
    local square = U().gridSquare(destination.x, destination.y,
        destination.z or 0)
    if not square then return true, "destination_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "walk", {
        action = "faction_guide", arrivalDistance = 1.5 })
end

function Royce.canRecruit(group)
    local value = story(group)
    return value and value.stage == "warned" or false,
        "hear_royces_horde_warning_first"
end

function Royce.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "bait" then
        return { { id = "follow_stash", label = "Follow Royce to the stash",
            enabled = true } }
    elseif value.stage == "apology" then
        return { { id = "buy_back", label = "Buy back the stolen item for $1",
            enabled = stolenItem(actorFor(group), group.id) ~= nil
                and oneDollar(player) ~= nil },
            { id = "accept_apology", label = "Hear his apology",
                enabled = true } }
    end
    return {}
end

function Royce.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        local actor = actorFor(group)
        local clean = U().config and U().config("profanityEnabled") == false
        U().say(actor, clean
            and "Aw, heck. You weren't supposed to live through that part."
            or "Aw, hell. You weren't supposed to live through that part.")
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "royce_too_far" end
    local actor = actorFor(group)
    if action == "follow_stash" and value.stage == "bait" then
        value.stage = "ambush"
        U().say(actor, "It's just beyond that door. Keep your eyes on the shelves.")
        return true, "royce_guiding_to_stash"
    elseif action == "accept_apology" and value.stage == "apology" then
        value.stage = "apology_done"
        U().say(actor, "I won't ask you to trust me. You'd be a fool to.")
        return true, "apology_heard"
    elseif action == "buy_back" and value.stage == "apology" then
        local item = stolenItem(actor, group.id)
        local money = oneDollar(player)
        local from = item and select(1, U().call(item, "getContainer"))
        local to = player and U().inventory(player)
        local moneySource = money and select(1,
            U().call(money, "getContainer"))
        local royceInv = U().inventory(actor)
        if not item or not money or not from or not to or not moneySource
            or not royceInv then return false, "buyback_items_unavailable" end
        if not U().transferItemVerified(moneySource, royceInv, money) then
            return false, "buyback_payment_failed"
        end
        if not U().transferItemVerified(from, to, item) then
            U().transferItemVerified(royceInv, moneySource, money)
            return false, "buyback_item_transfer_failed"
        end
        value.itemReturned = true
        U().say(actor, "A dollar. Half what I asked. The thing's yours again.")
        return true, "stolen_item_returned_exactly"
    end
    return false, "unknown_royce_choice"
end

return Royce
