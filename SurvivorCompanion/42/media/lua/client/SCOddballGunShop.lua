-- SPDX-License-Identifier: MIT
-- Bob Kenley of Kenley's Guns nearly shoots the player at the door, then
-- swears his new front glass is rated for anything. A few seconds later the
-- shop's real exterior window is smashed and real zombies, spawned out of
-- sight beyond it and drawn by the noise, come through. Most gun stores have
-- no sound glass; there he has locked himself in, brags about his deadbolts,
-- and the dead come at his door. Bob fights with his own shotgun. If he
-- lives, he hands over the good stuff from the back.

local SC = SurvivorCompanion
SC.OddballGunShop = SC.OddballGunShop or {}
local GunShop = SC.OddballGunShop

local ID = "gunshop_bob_kenley"
local GREET_DISTANCE = 9
local MENU_DISTANCE = 4
local LINE_GAP_MS = 2600
local SMASH_DELAY_MS = 9000
local SMASH_RETRY_MS = 5000
local SMASH_ATTEMPTS = 6
local HORDE_SIZE = 5
local MIN_UNSEEN_POSTS = 3
local BARK_MS = 8000
local SIEGE_LIMIT_MS = 600000
local NOISE_RADIUS = 30

local REWARD = {
    { kind = "Base.Pistol2", count = 1 },
    { kind = "Base.45Clip", count = 2 },
    { kind = "Base.Bullets45Box", count = 1 },
}
GunShop.REWARD = REWARD

local LINES = {
    greet = { "Whoa! Hands! Let me see hands!" },
    greet2 = { "You're breathing. Sorry. Nearly blew your head clean off." },
    intro = { "Bob Kenley. Kenley's Guns. Since nineteen seventy-one." },
    safe = { "Relax. Front glass is brand new. Rated for anything." },
    safeLocked = { "Relax. Steel door, two deadbolts. I locked myself in. Nothing gets in." },
    smash = {
        "That is not supposed to happen.",
        { "Son of a bitch! That glass was rated!", clean = "Son of a gun! That glass was rated!" },
    },
    door = {
        "Hear that? That's my door. That's them, knocking wrong.",
        { "Son of a bitch. Two deadbolts and they still come knocking.",
            clean = "Son of a gun. Two deadbolts and they still come knocking." },
    },
    doorOpen = {
        "You came in my door. So will they.",
        { "Who left my door open? Who the hell left it open?",
            clean = "Who left my door open? Who the heck left it open?" },
    },
    bark = {
        "Get behind the counter! Behind the counter!",
        "Shotgun's for them, not you! Stay left!",
        "This is a place of business!",
        { "Get out of my store, you ugly sons of bitches!",
            clean = "Get out of my store, you ugly so-and-sos!" },
        "Watch the display case! That's walnut!",
    },
    survived = { "Okay. Okay. We're okay." },
    survivedGlass = { "Glass was rated for anything. Anything alive, I guess." },
    survivedDoor = { "Two deadbolts. Should've bought three." },
    reward = { "Take this. From the back. The good stuff. Least I can do." },
    quiet = { "Quiet out there today. I don't like quiet." },
    shop = {
        "Sporting goods, mostly. Deer rifles. Duck guns. A fella bought every shell I had on the eighth.",
        "Don't touch the long guns. Look all you want. Don't touch.",
    },
    family = {
        "Got a girl, Emma. Put her on the bus the first day. Best thing I ever did.",
        "She hated this shop. Said it smelled like gun oil and bad decisions.",
    },
    fellow = {
        "He said the glass was rated.",
        "Remind me never to buy a window from that man.",
    },
    fellowDoor = {
        "So much for two deadbolts.",
        "Remind me never to buy a lock from that man.",
    },
}
GunShop.LINES = LINES

local runtimeByGroup = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "waiting" end
    value.lines = type(value.lines) == "table" and value.lines or {}
    value.spawned = tonumber(value.spawned) or 0
    value.killed = tonumber(value.killed) or 0
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    local actor = record and record.actor
    return actor and U().isValidActor(actor) and not U().isDead(actor) and actor or nil
end

local function lineText(entry)
    if type(entry) == "table" then
        return U().config("profanityEnabled") == false and entry.clean or entry[1]
    end
    return entry
end

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return lineText(list[index])
end

local function runtimeFor(group)
    local entry = runtimeByGroup[group]
    if not entry then
        entry = { queue = {} }
        runtimeByGroup[group] = entry
    end
    return entry
end

local function queue(group, text, current)
    local entry = runtimeFor(group)
    local last = entry.queue[#entry.queue]
    local at = last and last.at + LINE_GAP_MS or current
    entry.queue[#entry.queue + 1] = { text = text, at = at }
    return at
end

local function flush(group, current)
    local entry = runtimeFor(group)
    local head = entry.queue[1]
    if head and current >= head.at then
        table.remove(entry.queue, 1)
        local actor = actorFor(group)
        if actor then U().say(actor, head.text) end
    end
end

local function fellowLine(group, player, value)
    if value.fellowSpoke == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local bob = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= bob and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, value.siegeVia == "door" and "fellowDoor" or "fellow"))
                value.fellowSpoke = true
                return true
            end
        end
    end
    return false
end

local function tagged(actor, groupId)
    local found = {}
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 160, 4) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfGunShopGroupId == groupId then
            found[#found + 1] = item
        end
    end
    return found
end

function GunShop.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "bob_unavailable" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "bob_inventory_unavailable" end
    if value.gunSeeded ~= true then
        local gun = U().addItem(inventory, "Base.Shotgun")
        if not gun then return false, "bob_shotgun_unavailable" end
        -- A new shotgun comes empty; live, he stood through a siege unable
        -- to fire. Load it, hold it in both hands, keep loose shells to reload.
        U().call(gun, "setCurrentAmmoCount", 6)
        U().call(actor, "setPrimaryHandItem", gun)
        U().call(actor, "setSecondaryHandItem", gun)
        for _ = 1, 12 do U().addItem(inventory, "Base.ShotgunShells") end
        for _ = 1, 2 do U().addItem(inventory, "Base.ShotgunShellsBox") end
        value.gunSeeded = true
    end
    if value.rewardSeeded ~= true then
        -- The reward is stocked once and tagged; it is never minted again.
        local have = {}
        for _, item in ipairs(tagged(actor, group.id)) do
            local kind = U().itemType(item)
            have[kind] = (have[kind] or 0) + 1
        end
        for _, entry in ipairs(REWARD) do
            for _ = (have[entry.kind] or 0) + 1, entry.count do
                local item = U().addItem(inventory, entry.kind)
                local data = item and U().modData(item)
                if type(data) ~= "table" then return false, "bob_reward_unavailable" end
                data.lfGunShopGroupId = group.id
            end
        end
        value.rewardSeeded = true
    end
    -- Without front glass he has locked himself in: the player gets in the
    -- way anyone gets into a locked gun store.
    if not (value.site and value.site.partyWindow) and value.lockedIn ~= true then
        value.lockedIn = true
        value.doorsLocked = GunShop.lockUp(group, value)
    end
    return true, "bob_behind_the_counter"
end

local function openingAt(post, className)
    local square = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    local object = objects and SC.NativeList and SC.NativeList.get(objects, post.objectIndex)
    return object and U().instanceOf(object, className) and object or nil
end

local function shopWindow(value)
    local post = value.site and value.site.partyWindow
    return openingAt(post, "IsoWindow"), post
end

local function shopDoor(value)
    local post = value.site and value.site.partyDoor
    return openingAt(post, "IsoDoor"), post
end

-- Every outside door of the shop, shut and locked from the inside.
function GunShop.lockUp(group, value)
    local posts = {}
    local house = group and group.house
    for _, opening in ipairs(house and house.openings or {}) do
        if opening.kind == "door" then posts[#posts + 1] = opening end
    end
    if value.site and value.site.partyDoor then posts[#posts + 1] = value.site.partyDoor end
    local locked, seen = 0, {}
    for _, post in ipairs(posts) do
        local door = openingAt(post, "IsoDoor")
        if door and not seen[door] then
            seen[door] = true
            if select(1, U().call(door, "IsOpen")) == true then
                U().call(door, "ToggleDoorSilent")
            end
            U().call(door, "setLocked", true)
            U().call(door, "setLockedByKey", true)
            if select(1, U().call(door, "isLocked")) == true then locked = locked + 1 end
        end
    end
    return locked
end

local function unseenPosts(value, player)
    local posts = {}
    local index = player and select(1, U().call(player, "getPlayerNum"))
    for _, post in ipairs(value.site and value.site.hordeSpawns or {}) do
        local square = U().gridSquare(post.x, post.y, post.z or 0)
        local seen = square and tonumber(index)
            and select(1, U().call(square, "isCanSee", math.floor(index))) == true
        if square and not seen and U().canSee(player, square) ~= true
            and U().isSafeSpawnSquare(square) then
            posts[#posts + 1] = post
        end
    end
    return posts
end

-- The window goes, then the dead come. Spawned out of sight, drawn by the
-- glass and a shout of noise at the frame, they arrive through the hole.
-- With no glass left to give way, they come at his door instead: through
-- it, if the player left the way in open, or hammering on it if not.
local function breakIn(group, value, player, current)
    local window, windowPost = shopWindow(value)
    local glass = window ~= nil and select(1, U().call(window, "isSmashed")) ~= true
        and select(1, U().call(window, "isBarricaded")) ~= true
    local door, doorPost = shopDoor(value)
    local post = glass and windowPost or doorPost or windowPost
    local source = glass and window or door or window
    if not post then
        value.stage = "quiet"
        return false, "bob_no_way_in", "quiet"
    end
    local posts = unseenPosts(value, player)
    if #posts < MIN_UNSEEN_POSTS or type(addZombiesInOutfit) ~= "function"
        or not SC.NativeList then
        return false, "bob_no_unseen_approach"
    end
    local pool
    if glass then
        U().call(window, "smashWindow")
        pool = "smash"
    else
        local open = door ~= nil and (select(1, U().call(door, "IsOpen")) == true
            or select(1, U().call(door, "isLocked")) ~= true)
        pool = open and "doorOpen" or "door"
    end
    value.siegeVia = glass and "glass" or "door"
    for index = value.spawned + 1, HORDE_SIZE do
        local spot = posts[((index - 1) % #posts) + 1]
        local okay, list = pcall(addZombiesInOutfit, spot.x, spot.y, spot.z or 0,
            1, "Redneck", 50)
        local zombie = okay and list and SC.NativeList.get(list, 0) or nil
        if zombie then
            local data = U().modData(zombie)
            if data then data.lfGunShopZombieGroupId = group.id end
            value.spawned = value.spawned + 1
        end
    end
    if type(addSound) == "function" then
        pcall(addSound, source, post.x, post.y, post.z or 0, NOISE_RADIUS, NOISE_RADIUS)
    end
    value.stage = "siege"
    value.siegeStartedAt = current
    return true, glass and "bob_window_smashed" or "bob_door_besieged", pool
end

function GunShop.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    flush(group, current)
    local actor = actorFor(group)
    if not actor then return true, "bob_unavailable" end
    local entry = runtimeFor(group)
    if value.stage == "waiting" then
        if player and U().sameFloor(actor, player)
            and U().distance(actor, player) <= GREET_DISTANCE
            and U().canSee(actor, player) == true then
            value.stage = "greeted"
            group.discovered = true
            if SC.Relationship and type(SC.Relationship.playEmote) == "function" then
                SC.Relationship.playEmote(actor, "freeze")
            end
            U().say(actor, nextLine(value, "greet"))
            queue(group, nextLine(value, "greet2"), current + LINE_GAP_MS)
            queue(group, nextLine(value, "intro"), current)
            local safeAt = queue(group, nextLine(value,
                value.site and value.site.partyWindow and "safe" or "safeLocked"), current)
            value.smashAt = safeAt + SMASH_DELAY_MS
            value.smashAttempts = 0
        end
        return true, value.stage
    end
    if value.stage == "greeted" then
        if current < (tonumber(value.smashAt) or 0) then return true, "bob_bragging" end
        local broke, reason, pool = breakIn(group, value, player, current)
        if broke then
            U().say(actor, nextLine(value, pool))
            entry.nextBarkAt = current + BARK_MS
            return true, reason
        end
        if pool then
            U().say(actor, nextLine(value, pool))
            return true, reason
        end
        value.smashAttempts = (tonumber(value.smashAttempts) or 0) + 1
        if value.smashAttempts >= SMASH_ATTEMPTS then
            value.stage = "quiet"
            U().say(actor, nextLine(value, "quiet"))
            return true, "bob_quiet_day"
        end
        value.smashAt = current + SMASH_RETRY_MS
        return true, reason
    end
    if value.stage == "siege" then
        local cleared = value.killed >= value.spawned
        local expired = current - (tonumber(value.siegeStartedAt) or current) >= SIEGE_LIMIT_MS
        if cleared or expired then
            value.stage = "survived"
            U().say(actor, LINES.survived[1])
            queue(group, lineText((value.siegeVia == "door" and LINES.survivedDoor
                or LINES.survivedGlass)[1]), current + LINE_GAP_MS)
            fellowLine(group, player, value)
            return true, "bob_survived"
        end
        if current >= (tonumber(entry.nextBarkAt) or 0) and player
            and U().distance(actor, player) <= 20 then
            entry.nextBarkAt = current + BARK_MS
            U().say(actor, nextLine(value, "bark"))
        end
        return true, "bob_under_siege"
    end
    if value.stage == "survived" and value.rewardGiven ~= true and player
        and U().sameFloor(actor, player) and U().distance(actor, player) <= MENU_DISTANCE + 2 then
        local requirements = {}
        for _, item in ipairs(REWARD) do requirements[item.kind] = item.count end
        if SC.OddballExchange and type(SC.OddballExchange.take) == "function"
            and #tagged(actor, group.id) > 0 then
            local moved = SC.OddballExchange.take(actor, player, requirements)
            value.rewardGiven = moved == true
            if value.rewardGiven then queue(group, LINES.reward[1], current) end
        end
        return true, "bob_paying_his_debt"
    end
    return true, value.stage
end

function GunShop.onZombieDead(group, zombie, attacker, player)
    local value = story(group)
    if not value or not zombie then return false end
    local data = U().modData(zombie)
    if type(data) ~= "table" or data.lfGunShopZombieGroupId ~= group.id
        or data.lfGunShopCounted == true then
        return false
    end
    data.lfGunShopCounted = true
    value.killed = value.killed + 1
    return true
end

function GunShop.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    return { mode = "gunshop_counter", priority = 30 }
end

function GunShop.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "gunshop_counter" then return false end
    return true, "bob_behind_the_counter"
end

function GunShop.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or value.stage == "waiting" or not actor or not player
        or not U().sameFloor(actor, player)
        or U().distance(actor, player) > MENU_DISTANCE then
        return {}
    end
    return {
        { id = "ask_bob_shop", label = "Ask about the shop", enabled = true },
        { id = "ask_bob_family", label = "Ask about his family", enabled = true },
    }
end

function GunShop.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor or not player or U().distance(actor, player) > MENU_DISTANCE then
        return false, "bob_out_of_reach"
    end
    if action == "ask_bob_shop" then
        U().say(actor, nextLine(value, "shop"))
        return true, action
    elseif action == "ask_bob_family" then
        U().say(actor, nextLine(value, "family"))
        return true, action
    end
    return false, "unknown_bob_choice"
end

function GunShop.canRecruit(group)
    local value = story(group)
    if value and (value.stage == "survived" or value.stage == "quiet") then return true end
    return false, "bob_minding_the_store"
end

function GunShop._resetForTests()
    runtimeByGroup = setmetatable({}, { __mode = "k" })
end

return GunShop
