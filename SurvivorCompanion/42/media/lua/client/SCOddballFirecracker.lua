-- SPDX-License-Identifier: MIT
-- Bernice "Miss Liberty" Hupp follows the player at a distance and throws
-- her ten real firecrackers through vanilla IsoGameCharacter.Throw, the same
-- call the stock swing makes at its impact frame. The landing trap makes the
-- game's own noise, so the dead come for whoever stands under it. She runs
-- when the box is empty, when the dead get close or when she is struck, and
-- leaves through roamer hibernation once nobody can see her.

local SC = SurvivorCompanion
SC.OddballFirecracker = SC.OddballFirecracker or {}
local Firecracker = SC.OddballFirecracker

local ID = "firecracker_bernice_hupp"
local STOCK = 10
local ITEM = "Base.Firecracker"
local GREET_DISTANCE = 12
local CLOSE_DISTANCE = 4
local HOLD_DISTANCE = 9
local THROW_MIN_DISTANCE = 3
-- Vanilla clamps each axis of a throw to the firecracker's MaxRange (10).
local THROW_MAX_DISTANCE = 9.5
local ZOMBIE_FLEE_DISTANCE = 12
local WINDUP_MS = 600
local THROW_COOLDOWN_MS = 6500
local THROW_SPREAD_MS = 4000
local RAMBLE_COOLDOWN_MS = 9000
local RAMBLE_SPREAD_MS = 5000
local CLOSE_LINE_COOLDOWN_MS = 8000
local UNSEEN_MS = 4000
local FLEE_TARGET_MS = 20000
local LOST_HOURS = 2
local LOST_DISTANCE = 70

local runtimeByActor = setmetatable({}, { __mode = "k" })

local LINES = {
    greet = {
        "You! Yeah, you! This is a restricted celebration!",
        "Miss Liberty sees you! Miss Liberty always sees you!",
        "Halt! State your business and your favorite founding father!",
    },
    throw = {
        { "Happy Fourth, you son of a bitch!", clean = "Happy Fourth, you son of a gun!" },
        "Dogs hate it! Cats hate it! You'll hate it!",
        "Bought these in Tennessee! Kentucky won't sell the good ones!",
        "That's the sound of freedom! Hear it?",
        "Back! Get back! They're scared of noise, everybody knows that!",
        "Duck and cover! They taught us that in school!",
        "This one's for the county commissioner! He knows what he did!",
        "Light it and throw it! Light it and throw it!",
        "I got a permit! Wrote it myself!",
        { "Eat gunpowder, you shuffling bastard!", clean = "Eat gunpowder, you shuffling buzzard!" },
        "Ka-boom! Ha! Did you see that? Did you see it?",
        "Nobody tells Miss Liberty when the Fourth is over!",
        { "Get the hell out of my parade!", clean = "Get the heck out of my parade!" },
        "Oh say, can you SEE that one coming!",
    },
    low = {
        "Running low! That don't mean running out!",
        "Last few! I was saving these for New Year's!",
        "Almost out! Don't you dare look relieved!",
    },
    ramble = {
        "Dogs run from fireworks. Those things are just slow dogs. It's science.",
        "I ran the fireworks tent at the Fourth of July picnic. Sold out. Then everybody died.",
        "Fourth never ended. Nobody came to tell me to fold up the tent.",
        "The government did this. Or the Russians. Or the government's Russians.",
        "No more Soviets, they say. That's exactly what a Soviet would say.",
        "I ain't slept since the Fourth. Coffee and gunpowder. Breakfast of patriots.",
        "You look like a census taker. Didn't fill it out in 1990, won't now.",
        "Lloyd said I'd blow my fingers off. Lloyd's dead. I still got all ten.",
        "Mama always said, light it and walk away. I walk away. Then I come back.",
        "You're one of them, ain't you? You got the walk.",
        "Every bang buys me a minute. I counted. Mostly.",
        { "Damn things are scared of noise. Stands to reason.",
            clean = "Dang things are scared of noise. Stands to reason." },
        "There was a parade planned. Nobody came but me and the band. Band's dead.",
        "This is Uncle Sam's hat. Real felt. Don't you touch it.",
        "Pink is a patriotic color if you wear it hard enough.",
    },
    close = {
        "Back off! Personal space is in the Constitution!",
        "Closer and I light two at once! I'll do it!",
        "Don't you crowd a lady holding explosives!",
    },
    stop = {
        "Stop? The Fourth don't stop, honey!",
        "I'll stop when you stop being one of them.",
        "Ask nice. No. Too late. Fire in the hole!",
        { "Stop? Who the hell made you mayor?", clean = "Stop? Who the heck made you mayor?" },
    },
    empty = {
        "That's the show! God bless America, now get away from me!",
        "Out! I'm all out! Fourth's over, everybody go home!",
        "Grand finale! That was it! That was the grand finale!",
    },
    zombies = {
        "Why are they coming TOWARD it? That's backwards!",
        { "Oh shit, it's working backwards! Bye!", clean = "Oh shoot, it's working backwards! Bye!" },
        "They're supposed to be scared! Somebody lied to me!",
    },
    hurt = {
        "You hit a lady in a hat! I'm telling the county!",
        "Assault! Assault on a patriot! I'll remember your face!",
    },
    fellowThrow = {
        "Is she throwing firecrackers at us?",
        "She's ringing the dinner bell, and we're the dinner.",
        "That crazy old bat is calling every corpse in the county.",
    },
    fellowGone = {
        "Well. She's gone, and the dead aren't.",
        "Fourth's over. Somebody tell the dead.",
        "Never thought I'd miss the quiet this much.",
    },
}
Firecracker.LINES = LINES

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "approach" end
    value.thrown = tonumber(value.thrown) or 0
    value.lines = type(value.lines) == "table" and value.lines or {}
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function runtimeFor(actor)
    local entry = runtimeByActor[actor]
    if not entry then
        entry = {}
        runtimeByActor[actor] = entry
    end
    return entry
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    local hours = select(1, U().call(time, "getWorldAgeHours"))
    return tonumber(hours)
end

local function lineText(entry)
    if type(entry) == "table" then
        return U().config("profanityEnabled") == false and entry.clean or entry[1]
    end
    return entry
end

-- Each pool walks its own saved cursor, so a line never repeats until the
-- whole pool has been heard, and a reload resumes where she left off.
local function nextLine(value, pool)
    local list = LINES[pool]
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return lineText(list[index])
end

local function speak(actor, value, pool)
    if not actor then return false end
    return U().say(actor, nextLine(value, pool)) == true
end

local function fellowLine(group, player, pool, flag)
    local value = story(group)
    if not value or value[flag] == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local bernice = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= bernice and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, pool))
                value[flag] = true
                return true
            end
        end
    end
    return false
end

local function stock(actor, groupId)
    local found = {}
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 120, 4) or {}) do
        local data = U().modData(item)
        if type(data) == "table" and data.lfFirecrackerGroupId == groupId then
            found[#found + 1] = item
        end
    end
    return found
end

function Firecracker.remaining(group)
    local actor = actorFor(group)
    return actor and #stock(actor, group.id) or 0
end

local function beginFlight(value, reason)
    if value.stage == "fleeing" then return false end
    value.stage = "fleeing"
    value.fleeReason = reason
    value.fleeLinePending = true
    value.unseenSince = nil
    return true
end

function Firecracker.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "bernice_unavailable" end
    if value.stockSeeded ~= true then
        -- A failed add leaves the cursor short; the next setup retry tops it up
        -- to exactly ten. Once seeded, a missing firecracker is never minted.
        local inventory = U().inventory(actor)
        if not inventory then return false, "bernice_inventory_unavailable" end
        local present = #stock(actor, group.id)
        while present + value.thrown < STOCK do
            local item = U().addItem(inventory, ITEM)
            if not item then return false, "bernice_firecracker_unavailable" end
            local data = U().modData(item)
            if type(data) ~= "table" then return false, "bernice_firecracker_metadata_unavailable" end
            data.lfFirecrackerGroupId = group.id
            present = present + 1
        end
        value.stockSeeded = true
    end
    return true, "bernice_ready"
end

-- The perception snapshot lists the dead she can actually see. Anything
-- inside flight range turns the show into a retreat.
local function nearestThreat(actor, snapshot)
    if type(snapshot) ~= "table" or type(snapshot.threats) ~= "table" then return nil end
    local best, bestDistance
    for index = 1, math.min(#snapshot.threats, 32) do
        local threat = snapshot.threats[index]
        local zombie = type(threat) == "table" and threat.actor or nil
        if zombie and not U().isDead(zombie) then
            local distance = U().distance(actor, zombie)
            if distance and distance <= ZOMBIE_FLEE_DISTANCE
                and (bestDistance == nil or distance < bestDistance) then
                best, bestDistance = zombie, distance
            end
        end
    end
    return best
end

function Firecracker.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage ~= "fleeing" then
        local threat = nearestThreat(actor, snapshot)
        if threat then
            beginFlight(value, "zombies")
            local x, y = U().position(threat)
            if x then value.fleeFrom = { x = math.floor(x), y = math.floor(y) } end
        elseif group.standing == "Hostile" then
            beginFlight(value, "hurt")
        end
    end
    if value.stage == "fleeing" then
        return { mode = "firecracker_flee", priority = 96 }
    end
    if value.stage == "harass" then
        return { mode = "firecracker_harass", priority = 40 }
    end
    return { mode = "firecracker_approach", priority = 30 }
end

local function cancelFollow(actor, reason)
    if SC.Navigation and type(SC.Navigation.peek) == "function"
        and type(SC.Navigation.cancel) == "function" then
        local route = SC.Navigation.peek(actor)
        if route and (route.goalAction == "faction_follow"
            or route.goalAction == "faction_retreat") then
            SC.Navigation.cancel(actor, reason)
        end
    end
end

local function follow(actor, player, distance, hasSight, holdAt)
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    local target = U().squareOf(player)
    if not target then return true, "bernice_target_unloaded" end
    return SC.Navigation.request(actor, target, distance > 18 and "jog" or "walk", {
        action = "faction_follow",
        -- A sight-line hold must not count as arrival through a wall.
        arrivalDistance = hasSight and holdAt or 0.85,
        player = player, followRecovery = true, movingTarget = true,
        continuousApproach = true, movementPriority = 20,
    })
end

-- A standable square roughly `span` meters from `actor`, pointing away from
-- `fromX, fromY`. Fans out to the sides when the straight line is blocked.
local function awaySquare(actor, fromX, fromY, span)
    local ax, ay, az = U().position(actor)
    if not ax or not fromX then return nil end
    local dx, dy = ax - fromX, ay - fromY
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.01 then dx, dy, length = 1, 0, 1 end
    local base = math.atan2 and math.atan2(dy, dx) or math.atan(dy, dx)
    for _, turn in ipairs({ 0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5 }) do
        local angle = base + turn
        local square = U().gridSquare(math.floor(ax + math.cos(angle) * span),
            math.floor(ay + math.sin(angle) * span), math.floor(az or 0))
        if square and U().isSafeSpawnSquare(square) then return square end
    end
    return nil
end

local function throwAt(actor, player, item)
    local square = U().squareOf(player)
    if not square then return false, "bernice_target_square_unavailable" end
    local previous = select(1, U().call(actor, "getAttackTargetSquare"))
    local _, aimed = U().call(actor, "setAttackTargetSquare", square)
    if not aimed then return false, "bernice_aim_unavailable" end
    U().call(actor, "faceThisObject", player)
    -- IsoGameCharacter.Throw builds the vanilla IsoMolotovCocktail from the
    -- held weapon. Its IsoTrap carries the firecracker's own noise and sound.
    local _, thrown = U().call(actor, "Throw", item)
    U().call(actor, "setAttackTargetSquare", previous)
    if not thrown then return false, "bernice_native_throw_failed" end
    U().call(actor, "playSound", "FireCrackerThrow")
    -- The stock swing spends a UseSelf throwable right after Throw.
    U().consumeItem(U().inventory(actor), item)
    return true, "bernice_threw"
end

local function harass(actor, player, value, group)
    local entry = runtimeFor(actor)
    local current = U().nowMs()
    local supply = stock(actor, group.id)
    if #supply == 0 and value.stockSeeded == true then
        beginFlight(value, "empty")
        return true, "bernice_out_of_stock"
    end
    local distance = U().distance(actor, player)
    local hasSight = U().sameFloor(actor, player) and U().canSee(actor, player) == true
    if entry.windupAt then
        if not hasSight or distance > THROW_MAX_DISTANCE then
            entry.windupAt = nil
        elseif current - entry.windupAt >= WINDUP_MS then
            entry.windupAt = nil
            local thrown, reason = throwAt(actor, player, supply[1])
            if not thrown then
                entry.nextThrowAt = current + THROW_COOLDOWN_MS
                return true, reason
            end
            value.thrown = value.thrown + 1
            entry.nextThrowAt = current + THROW_COOLDOWN_MS
                + (value.thrown * 1373) % THROW_SPREAD_MS
            entry.nextRambleAt = math.max(tonumber(entry.nextRambleAt) or 0,
                current + 3500)
            local left = #supply - 1
            if left == 0 then
                beginFlight(value, "empty")
            else
                speak(actor, value, left <= 2 and "low" or "throw")
            end
            fellowLine(group, player, "fellowThrow", "fellowSawThrow")
            return true, "bernice_threw"
        else
            return true, "bernice_lighting_fuse"
        end
    end
    if hasSight and distance >= THROW_MIN_DISTANCE and distance <= THROW_MAX_DISTANCE
        and current >= (tonumber(entry.nextThrowAt) or 0) then
        cancelFollow(actor, "bernice_lighting_fuse")
        U().stop(actor)
        U().call(actor, "faceThisObject", player)
        U().call(actor, "playSound", "FireCrackerEquip")
        entry.windupAt = current
        return true, "bernice_lighting_fuse"
    end
    if hasSight and distance < CLOSE_DISTANCE then
        if current >= (tonumber(entry.nextCloseLineAt) or 0) then
            entry.nextCloseLineAt = current + CLOSE_LINE_COOLDOWN_MS
            speak(actor, value, "close")
        end
        local px, py = U().position(player)
        local square = awaySquare(actor, px, py, 8)
        if square and SC.Navigation and type(SC.Navigation.request) == "function" then
            return SC.Navigation.request(actor, square, "walk", {
                action = "faction_retreat", arrivalDistance = 1.5 })
        end
        return true, "bernice_cornered"
    end
    if hasSight and distance <= HOLD_DISTANCE then
        cancelFollow(actor, "bernice_holding_distance")
    else
        local followed, reason = follow(actor, player, distance, hasSight, 7)
        if not followed then return followed, reason end
    end
    if hasSight and current >= (tonumber(entry.nextRambleAt) or 0) then
        entry.nextRambleAt = current + RAMBLE_COOLDOWN_MS
            + ((tonumber(value.lines.ramble) or 0) * 2137) % RAMBLE_SPREAD_MS
        speak(actor, value, "ramble")
    end
    return true, "bernice_harassing"
end

local function flee(actor, player, value)
    local entry = runtimeFor(actor)
    entry.windupAt = nil
    if value.fleeLinePending == true then
        value.fleeLinePending = false
        local pool = value.fleeReason == "zombies" and "zombies"
            or value.fleeReason == "hurt" and "hurt" or "empty"
        speak(actor, value, pool)
    end
    local current = U().nowMs()
    local target = entry.fleeTarget
    if target then
        local x, y = U().position(actor)
        if not x or (x - target.x) ^ 2 + (y - target.y) ^ 2 <= 9
            or current - target.at >= FLEE_TARGET_MS then
            target = nil
        end
    end
    if not target then
        local fromX, fromY
        if value.fleeReason == "zombies" and type(value.fleeFrom) == "table" then
            fromX, fromY = value.fleeFrom.x, value.fleeFrom.y
        elseif player then
            fromX, fromY = U().position(player)
        end
        local square = awaySquare(actor, fromX, fromY, 16)
        if not square then return true, "bernice_no_escape_square" end
        local x, y, z = U().position(square)
        target = { x = x, y = y, z = z, at = current }
        entry.fleeTarget = target
    end
    local square = U().gridSquare(target.x, target.y, target.z)
    if not square then
        entry.fleeTarget = nil
        return true, "bernice_escape_unloaded"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, square, "run", {
        action = "faction_retreat", arrivalDistance = 2 })
end

function Firecracker.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent or not player then return false end
    if intent.mode == "firecracker_flee" then return flee(actor, player, value) end
    if intent.mode == "firecracker_harass" then return harass(actor, player, value, group) end
    if intent.mode ~= "firecracker_approach" then return false end
    local distance = U().distance(actor, player)
    local hasSight = U().sameFloor(actor, player) and U().canSee(actor, player) == true
    return follow(actor, player, distance, hasSight, GREET_DISTANCE - 2)
end

local function departOrWait(group, value, player, current, reason)
    local actor = actorFor(group)
    if player and actor and U().canSee(player, actor) == true then
        value.unseenSince = nil
        return true, "bernice_still_in_view"
    end
    value.unseenSince = tonumber(value.unseenSince) or current
    if current - value.unseenSince < UNSEEN_MS then return true, "bernice_slipping_away" end
    local member = group.members and group.members[1]
    local gone = member and member.hibernated == true
    if not gone and SC.Factions and type(SC.Factions.hibernateOddballRoamer) == "function" then
        gone = SC.Factions.hibernateOddballRoamer(group.id, player) == true
    end
    if not gone then return true, "bernice_waiting_to_vanish" end
    group.lifecycle = "destroyed"
    if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
        SC.Oddballs.retire(group, reason)
    end
    return true, "bernice_" .. reason
end

function Firecracker.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local member = group.members and group.members[1]
    if value.stage == "fleeing" and member and member.hibernated == true then
        group.lifecycle = "destroyed"
        if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
            SC.Oddballs.retire(group, "ran_off")
        end
        return true, "bernice_ran_off"
    end
    local actor = actorFor(group)
    if not actor then return true, "bernice_unloaded" end
    if value.stage == "fleeing" then
        fellowLine(group, player, "fellowGone", "fellowSawFlight")
        return departOrWait(group, value, player, current, "ran_off")
    end
    local hours = worldHours()
    if not player or U().distance(actor, player) > LOST_DISTANCE then
        value.lostSinceHour = tonumber(value.lostSinceHour) or hours
        if hours and value.lostSinceHour and hours - value.lostSinceHour >= LOST_HOURS then
            return departOrWait(group, value, player, current, "lost_interest")
        end
        return true, "bernice_lost_the_player"
    end
    value.lostSinceHour = nil
    if value.stage == "approach" and U().distance(actor, player) <= GREET_DISTANCE
        and U().sameFloor(actor, player) and U().canSee(actor, player) == true then
        value.stage = "harass"
        group.discovered = true
        speak(actor, value, "greet")
        local entry = runtimeFor(actor)
        entry.nextThrowAt = current + 2500
        entry.nextRambleAt = current + RAMBLE_COOLDOWN_MS
        return true, "bernice_greeted"
    end
    return true, value.stage
end

function Firecracker.menuOptions(group, player)
    local value = story(group)
    local actor = actorFor(group)
    if not value or value.stage ~= "harass" or not actor or not player
        or U().distance(actor, player) > 10 then return {} end
    return { { id = "tell_bernice_stop", label = "Tell her to stop", enabled = true } }
end

function Firecracker.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        -- She never fights back. A blow sends her running and keeps the
        -- faction standing out of it.
        beginFlight(value, "hurt")
        return true, "bernice_flees_the_blow"
    end
    if action == "tell_bernice_stop" then
        if not actor or not player or U().distance(actor, player) > 10
            or value.stage ~= "harass" then
            return false, "bernice_out_of_earshot"
        end
        speak(actor, value, "stop")
        return true, "bernice_refuses"
    end
    return false, "unknown_bernice_choice"
end

function Firecracker.avoidsZombieCombat()
    return true
end

function Firecracker.canRecruit()
    return false, "miss_liberty_answers_to_no_one"
end

function Firecracker._resetForTests()
    runtimeByActor = setmetatable({}, { __mode = "k" })
end

return Firecracker
