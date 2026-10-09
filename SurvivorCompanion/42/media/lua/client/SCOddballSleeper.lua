-- SPDX-License-Identifier: MIT
-- The dancer uses the existing native bed action. Waking and the lost-bag
-- errand are persistent; the bag is a real item in a real bar container.

local SC = SurvivorCompanion
SC.OddballSleeper = SC.OddballSleeper or {}
local Sleeper = SC.OddballSleeper
local ID = "sleeping_it_off"

local function U() return SC.GameplayUtil end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "sleeping"
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function ageHours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    local raw = time and select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(raw)
end
local function bedObject(value)
    local post = value.site and value.site.bed
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    if not objects or not SC.NativeList then return nil end
    local object = SC.NativeList.get(objects, post.objectIndex)
    return object, square
end
local function wake(actor)
    U().call(actor, "setAsleep", false)
    if SC.NativeActions and type(SC.NativeActions.leaveSeating) == "function" then
        SC.NativeActions.leaveSeating(actor)
    end
end

local function startledBottle(actor)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    local empty
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 80, 4)) do
        local kind = U().itemType(item)
        if kind == "Base.SmashedBottle" then return item end
        if kind == "Base.BeerEmpty" then empty = item end
    end
    if not empty then return nil end
    local source = select(1, U().call(empty, "getContainer"))
    if not source then return nil end
    local _, removed = U().call(source, "Remove", empty)
    if not removed or U().inventoryContains(source, empty) then return nil end
    if type(U().touchInventoryIndex) == "function" then
        U().touchInventoryIndex(source)
    end
    local weapon = U().addItem(inventory, "Base.SmashedBottle")
    if not weapon then U().addItem(source, "Base.BeerEmpty") end
    return weapon
end

local function roughWake(group, actor)
    local value = story(group)
    if not value or value.stage ~= "sleeping" then
        return false, "dancer_already_awake" end
    wake(actor)
    value.stage = "startled"
    value.roughWakeUntil = U().nowMs() + 3000
    SC.Factions.adjustStanding(group.id, -12, "rough_wake")
    U().say(actor, "Back off! I've thrown bigger drunks than you out of the club!")
    return true, "dancer_startled_awake"
end
local function hasBag(actor, groupId)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        240, 10) or {}) do
        local data = U().modData(item)
        if data and data.lfSleeperBagGroupId == groupId then return item end
    end
    return nil
end
local function roomName(square)
    local room = square and select(1, U().call(square, "getRoom"))
    local name = room and select(1, U().call(room, "getName"))
    return type(name) == "string" and string.lower(name) or nil
end
local function clubContainer(player)
    local square = U().squareOf(player)
    local name = roomName(square)
    if name ~= "stripclub" and name ~= "bar" then return nil end
    local building = select(1, U().call(square, "getBuilding"))
    local px, py, pz = U().position(player)
    if not px then return nil end
    for radius = 0, 8 do
        for dx = -radius, radius do
            for _, dy in ipairs({ -radius, radius }) do
                local tile = U().gridSquare(math.floor(px + dx),
                    math.floor(py + dy), pz)
                if tile and select(1,
                    U().call(tile, "getBuilding")) == building then
                    local found, locator
                    U().squareObjects(tile, function(object, index)
                        local inventory = select(1,
                            U().call(object, "getContainer"))
                        if inventory then
                            found = inventory
                            locator = { x = math.floor(px + dx),
                                y = math.floor(py + dy), z = pz,
                                objectIndex = index,
                                containerType = select(1,
                                    U().call(inventory, "getType")) }
                            return false
                        end
                    end, 32)
                    if found then return found, locator end
                end
            end
        end
    end
    return nil
end

function Sleeper.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "sleeping_dancer_unavailable" end
    local hours = ageHours()
    if hours and not value.spawnHour then value.spawnHour = hours end
    if value.bottlesSeeded ~= true then
        local bed = value.site and value.site.bed
        local square = bed and U().gridSquare(bed.x, bed.y, bed.z or 0)
        if square then
            local added = 0
            for index = 1, 3 do
                local _, okay = U().call(square,
                    "AddWorldInventoryItem", "Base.BeerEmpty",
                    0.2 + index * 0.15, 0.3, 0)
                if okay then added = added + 1 end
            end
            if added > 0 then value.bottlesSeeded = true end
        end
    end
    local inventory = U().inventory(actor)
    if value.bottleCarried ~= true and inventory then
        local bottle = U().addItem(inventory, "Base.BeerEmpty")
        if bottle then value.bottleCarried = true end
    end
    local stats = select(1, U().call(actor, "getStats"))
    if stats then U().call(stats, "setDrunkenness", 40) end
    return true, "hungover_dancer_in_bedroom"
end

function Sleeper.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "dancer_unloaded" end
    local hours = ageHours()
    if value.stage == "startled" and current >=
        (tonumber(value.roughWakeUntil) or 0) then
        value.stage = "bag_quest"
        U().say(actor, "Sorry. I thought you were somebody from the club.")
    end
    if value.stage == "sleeping" then
        if hours and value.spawnHour
            and hours - value.spawnHour >= 24 then
            wake(actor)
            value.stage = "wander_off"
            U().say(actor,
                "What day is it? Never mind. I have to get back to the club.")
        elseif near(group, player, 5)
            and current >= (tonumber(value.nextMumbleAt) or 0) then
            value.nextMumbleAt = current + 45000
            U().say(actor,
                "Mmh. Five more minutes. Tell the DJ five more minutes.")
            group.discovered = true
        end
    elseif value.stage == "wander_off" and player
        and U().canSee(player, actor) ~= true
        and U().distance(player, actor) >= 20
        and SC.Actor and SC.Actor.remove and SC.Actor.remove(actor) then
        local member = group.members and group.members[1]
        if member then member.actorId, member.departed = nil, true end
        value.stage = "gone"
        group.lifecycle = "destroyed"
        if SC.Oddballs then SC.Oddballs.retire(group, "woke_and_left") end
    end
    return true, value.stage
end

function Sleeper.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then
        if value.stage == "sleeping" or value.stage == "startled" then
            wake(actor)
            value.stage = "bag_quest"
            U().say(actor, "That is NOT a customer! Get it off!")
        end
        return { mode = "zombie_defense", priority = 18 }
    end
    if value.stage == "sleeping" then
        return { mode = "dancer_bed", priority = 60 }
    end
    if value.stage == "startled" then
        return { mode = "dancer_startled_swing", priority = 75 }
    end
    if value.stage == "bag_quest" then
        return { mode = "dancer_follow", priority = 40 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Sleeper.update(actor, player, runtime, intent, group)
    if not intent then return false, "dancer_idle" end
    if intent.mode == "dancer_startled_swing" then
        local value = story(group)
        if not value or value.stage ~= "startled" then
            return false, "startle_finished" end
        if U().nowMs() >= (tonumber(value.roughWakeUntil) or 0)
            or not player or U().distance(actor, player) > 1.35 then
            value.stage = "bag_quest"
            return true, "dancer_calmed_down" end
        if select(1, U().call(actor, "isOnBed")) == true then
            wake(actor)
            return true, "dancer_getting_off_bed" end
        local bottle = startledBottle(actor)
        if not bottle then
            value.stage = "bag_quest"
            return false, "startled_bottle_unavailable" end
        local swung, reason = U().move(actor, "walk", {
            action = "attack_melee", weapon = bottle, target = player,
            factionCombat = true })
        if swung then
            value.stage = "bag_quest"
            value.roughSwingDone = true
            U().say(actor, "Sorry. Instinct. My head's still at the club.")
            return true, "single_startled_bottle_swing" end
        return true, reason or "waiting_to_swing"
    end
    if intent.mode == "dancer_follow" then
        if not player or U().distance(actor, player) <= 4 then
            return true, "dancer_follows_to_club"
        end
        local square = U().squareOf(player)
        if not square or not SC.Navigation then
            return false, "club_route_unavailable"
        end
        return SC.Navigation.request(actor, square, "walk", {
            action = "dancer_club_errand", arrivalDistance = 3 })
    end
    if intent.mode ~= "dancer_bed" then return false, "dancer_idle" end
    local object = bedObject(story(group))
    if not object then return false, "bed_object_unavailable" end
    if select(1, U().call(actor, "isOnBed")) == true then
        U().call(actor, "setAsleep", true)
        return true, "sleeping_through_the_end"
    end
    local arrived, targets = U().directInteractionAccess(actor, object)
    if not arrived then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function"
            or #targets == 0 then return false, "bed_entry_unavailable" end
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "dancer_approach_bed", object = object,
            targetSquare = U().squareOf(object),
            requireSameSquare = true, continuousApproach = true })
    end
    return U().move(actor, "walk", { action = "rest_bed",
        object = object, targetSquare = U().squareOf(object) })
end

function Sleeper.canRecruit(group)
    local value = story(group)
    return value and value.stage == "bag_found"
        and group.standing ~= "Hostile" or false, "find_the_club_bag_first"
end

function Sleeper.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player, 7) then return {} end
    if value.stage == "sleeping" then
        return {
            { id = "wake_gently", label = "Gently wake the dancer",
                enabled = true },
            { id = "wake_rough", label = "Shout them awake",
                enabled = true },
        }
    end
    if value.stage == "bag_quest" then
        return {
            { id = "ask_club", label = "Ask about the club", enabled = true },
            { id = "look_for_bag", label = "Look for the bag in this club",
                enabled = clubContainer(player) ~= nil },
            { id = "return_bag", label = "Return the dancer's bag",
                enabled = hasBag(player, group.id) ~= nil },
        }
    end
    if value.stage == "bag_found" then
        return { { id = "recruit", label = "Ask the dancer to come along",
            enabled = true } }
    end
    return {}
end

function Sleeper.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" and value.stage == "sleeping" then
        return roughWake(group, actor)
    elseif action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player, 7) then return false, "dancer_too_far" end
    if action == "wake_rough" then return roughWake(group, actor) end
    if action == "wake_gently" and value.stage == "sleeping" then
        wake(actor)
        value.stage = "bag_quest"
        group.discovered = true
        U().say(actor,
            "Whoa. Whose bed is this? Everybody's what? Eating each other? Coffee first, then I panic.")
        U().say(actor,
            "My bag's still at the club. Tips, car keys, real shoes. Walk me there?")
        return true, "dancer_gently_woken"
    end
    if action == "ask_club" and value.stage == "bag_quest" then
        U().say(actor,
            "Last thing I remember is the bachelor party. Find a bar or the strip club. I left my bag there.")
        return true, "club_errand_explained"
    end
    if action == "look_for_bag" and value.stage == "bag_quest" then
        if value.bagSeeded == true then return true, "bag_already_at_club" end
        local container, locator = clubContainer(player)
        if not container then return false, "not_in_a_loaded_club" end
        local bag = U().addItem(container, "Base.Bag_DuffelBag")
        if not bag then return false, "club_bag_unavailable" end
        local data = U().modData(bag)
        if data then data.lfSleeperBagGroupId = group.id end
        local inside = select(1, U().call(bag, "getInventory"))
        if inside then
            U().addItem(inside, "Base.MoneyBundle")
            U().addItem(inside, "Base.Shoes_BlackBoots")
        end
        value.bagSeeded, value.bagContainer = true, locator
        U().say(actor, "That's it! The bag with my tips. Bring it over.")
        return true, "real_club_bag_seeded"
    end
    if action == "return_bag" and value.stage == "bag_quest" then
        local bag = hasBag(player, group.id)
        local source = bag and select(1, U().call(bag, "getContainer"))
        if not bag or not source or not U().transferItemVerified(source,
            U().inventory(actor), bag) then return false, "club_bag_not_carried" end
        value.stage = "bag_found"
        SC.Factions.forceStanding(group.id, "Trusted")
        U().say(actor,
            "My real shoes. My tips. I slept through the end of the world, but I can work a rough crowd.")
        return true, "exact_club_bag_returned"
    end
    if action == "recruit" and Sleeper.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id, player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id, player, false)
    end
    return false, "dancer_choice_unavailable"
end

return Sleeper
