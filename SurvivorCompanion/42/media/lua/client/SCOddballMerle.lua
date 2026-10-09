-- SPDX-License-Identifier: MIT
-- Merle digs an actual two-square vanilla grave with the Gravekeeper's native
-- action. The ring only becomes a reward after the grave object exists.

local SC = SurvivorCompanion
SC.OddballMerle = SC.OddballMerle or {}
local Merle = SC.OddballMerle
local ID = "digger_merle_lusby"

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "seeking_granddaddy"
    return value
end

local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end

local function loanedShovel(actor, group)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        local data = U().modData(item)
        if U().itemType(item) == "Base.Shovel" and data
            and data.lfMerleLoanGroupId == group.id then return item end
    end
    return nil
end

local function betterShovel(player, merle)
    local own = itemFor(merle, "Base.Shovel")
    local ownRaw = own and select(1, U().call(own, "getCondition"))
    local ownCondition = tonumber(ownRaw)
    local inventory = player and U().inventory(player)
    local best, bestCondition
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}) do
        if U().itemType(item) == "Base.Shovel" then
            local raw = select(1, U().call(item, "getCondition"))
            local condition = tonumber(raw)
            if (not condition or condition > 0)
                and (not ownCondition or not condition or condition > ownCondition)
                and (not best or (condition or 0) > (bestCondition or 0)) then
                best, bestCondition = item, condition
            end
        end
    end
    return best
end

local function gravekeeperNearby(actor)
    if not SC.Registry or type(SC.Registry.living) ~= "function"
        or not SC.BaseLife or type(SC.BaseLife.resident) ~= "function" then
        return false
    end
    for _, fellow in ipairs(SC.Registry.living() or {}) do
        if fellow ~= actor and U().distance(actor, fellow) <= 4 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id)
            local resident = id and SC.BaseLife.resident(id)
            if record and record.recruited == true and resident
                and resident.role == "corpsekeeper" then return true end
        end
    end
    return false
end

local function near(group, player)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= 7
        and U().canSee(player, actor) == true
end

local function graveExists(value)
    local site = value.site and value.site.grave
    local square = site and U().gridSquare(site.x, site.y, site.z or 0)
    local partner = site and U().gridSquare(site.x - 1, site.y, site.z or 0)
    if not square or not partner then return false end
    local function hasGrave(tile)
        local found = false
        U().squareSpecialObjects(tile, function(object)
            if select(1, U().call(object, "getName")) == "EmptyGraves" then
                found = true
            end
        end, 16)
        return found
    end
    return hasGrave(square) and hasGrave(partner)
end

local function nativeWork(actor)
    local owner = SC.NativeActions
    return owner and type(owner.isWorkActive) == "function"
        and owner.isWorkActive(actor) == true
        and owner.workKind(actor) == "dig_grave"
end

local function finishDig(group, actor)
    local value = story(group)
    if not value or value.digStarted ~= true then return false end
    if nativeWork(actor) then return true, "granddaddy_grave_digging" end
    local owner = SC.NativeActions
    if owner and type(owner.finishWork) == "function" then
        local finished = owner.finishWork(actor)
        if finished ~= true then return false, "grave_tool_restore_pending" end
    end
    value.digStarted = false
    if not graveExists(value) then
        value.retryAt = U().nowMs() + 30000
        return false, "granddaddy_grave_incomplete"
    end
    if value.rewardSeeded ~= true then
        local inventory = U().inventory(actor)
        local ring = inventory and U().addItem(inventory,
            "Base.Ring_Left_RingFinger_Gold")
        local letter = inventory and U().addItem(inventory,
            "Base.LetterHandwritten")
        if not ring or not letter then return false, "buried_reward_unavailable" end
        U().call(letter, "setName", "Merle's granddaddy and the third oak")
        local data = U().modData(ring)
        if data then data.lfMerleGold = true end
        value.rewardSeeded = true
    end
    value.stage = "gold_found"
    U().say(actor,
        "Granddaddy lied about the oak, but not the gold. The dead don't need it. Ask 'em.")
    return true, "real_grave_and_gold_found"
end

function Merle.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "merle_unavailable" end
    if value.shovelSeeded ~= true then
        local shovel = itemFor(actor, "Base.Shovel")
            or U().addItem(U().inventory(actor), "Base.Shovel")
        if not shovel then return false, "shovel_unavailable" end
        local condition = select(1, U().call(shovel, "getCondition"))
        if tonumber(condition) and condition > 3 then
            U().call(shovel, "setCondition", 3)
        end
        U().call(actor, "setPrimaryHandItem", shovel)
        value.shovelSeeded = true
    end
    return true, "merle_ready_to_dig"
end

function Merle.pulse(group, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return false, "digger_unloaded" end
    if value.digStarted then finishDig(group, actor) end
    if near(group, player) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        U().say(actor,
            "Granddaddy buried it under the third oak. Or the fourth. Lend a hand if you fancy gold.")
    end
    return true, value.stage
end

function Merle.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then return { mode = "zombie_defense", priority = 18 } end
    if value.stage == "seeking_granddaddy" then
        return { mode = "merle_dig", priority = 57 }
    end
    return { mode = "oddball_idle", priority = 28 }
end

function Merle.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent or intent.mode ~= "merle_dig" then
        return false, "merle_idle"
    end
    if value.digStarted then return finishDig(group, actor) end
    if U().nowMs() < (tonumber(value.retryAt) or 0) then
        return true, "grave_retry_wait"
    end
    local point = value.site and value.site.grave
    local square = point and U().gridSquare(point.x, point.y, point.z or 0)
    if not square then return false, "grave_site_unloaded" end
    local ax, ay, az = U().position(actor)
    if ax == nil or az ~= (point.z or 0) then
        return false, "grave_different_floor"
    end
    if math.abs(ax - point.x) > 1.6 or math.abs(ay - point.y) > 1.6 then
        if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
            return false, "grave_navigation_unavailable"
        end
        local post = value.site.spawn
        local destination = post and U().gridSquare(post.x, post.y,
            post.z or 0)
        if not destination then return false, "grave_approach_unloaded" end
        return SC.Navigation.request(actor, destination, "walk", {
            action = "merle_approach_grave", arrivalDistance = 0.6 })
    end
    local shovel = loanedShovel(actor, group)
        or itemFor(actor, "Base.Shovel")
    if not shovel then return false, "merle_needs_a_shovel" end
    if graveExists(value) then
        value.digStarted = true
        return finishDig(group, actor)
    end
    local helped = loanedShovel(actor, group) ~= nil
        or gravekeeperNearby(actor)
    local accepted, reason = U().move(actor, "walk", {
        action = "dig_grave", square = square, tool = shovel,
        north = false, targetSquare = square,
        durationTicks = helped and 75 or nil })
    if accepted and nativeWork(actor) then
        value.digStarted = true
        U().say(actor, helped and
            "Two sets of hands, and granddaddy's secret comes up sooner." or
            "The dead don't need it. Ask 'em.")
        return true, "granddaddy_grave_digging"
    end
    value.retryAt = U().nowMs() + 30000
    return false, reason or "grave_action_rejected"
end

function Merle.canRecruit() return false, "merle_keeps_digging" end

function Merle.menuOptions(group, player)
    local value = story(group)
    if not value or not near(group, player) then return {} end
    if value.stage == "gold_found" then
        return { { id = "claim_gold", label = "Hear Merle's tale and take the gold",
            enabled = value.goldClaimed ~= true } }
    end
    return {
        { id = "ask_oak", label = "Ask Merle about granddaddy's oak",
            enabled = true },
        { id = "lend_shovel", label = "Lend Merle a better shovel",
            enabled = betterShovel(player, actorFor(group)) ~= nil
                and loanedShovel(actorFor(group), group) == nil
                and value.digStarted ~= true },
    }
end

function Merle.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "hurt" then
        return SC.Factions.forceStanding(group.id, "Hostile")
    end
    if not near(group, player) then return false, "digger_too_far" end
    local actor = actorFor(group)
    if action == "ask_oak" then
        U().say(actor,
            "Third oak, fourth oak, maybe a maple. Granddaddy knew how to keep a story alive.")
        return true, "merle_told_oak_story"
    end
    if action == "lend_shovel" then
        if loanedShovel(actor, group) or value.digStarted == true then
            return false, "merle_already_has_help" end
        local shovel = betterShovel(player, actor)
        local source = shovel and select(1, U().call(shovel, "getContainer"))
        if not shovel or not source or not U().transferItemVerified(source,
            U().inventory(actor), shovel) then
            return false, "shovel_transfer_failed"
        end
        local data = U().modData(shovel)
        if data then data.lfMerleLoanGroupId = group.id end
        U().call(actor, "setPrimaryHandItem", shovel)
        U().say(actor, "That'll do. I'll bring it back when granddaddy's secret comes up.")
        return true, "shovel_lent_to_merle"
    end
    if action ~= "claim_gold" or value.stage ~= "gold_found"
        or value.goldClaimed == true then return false, "gold_unavailable" end
    local ring
    for _, item in ipairs(U().inventoryItemsDeep(U().inventory(actor), 160, 8)) do
        local data = U().modData(item)
        if data and data.lfMerleGold == true then ring = item; break end
    end
    local source = ring and select(1, U().call(ring, "getContainer"))
    if not ring or not source or not U().transferItemVerified(source,
        U().inventory(player), ring) then return false, "gold_transfer_failed" end
    local loan = loanedShovel(actor, group)
    if loan then
        local loanSource = select(1, U().call(loan, "getContainer"))
        U().call(actor, "setPrimaryHandItem", nil)
        if not loanSource or not U().transferItemVerified(loanSource,
            U().inventory(player), loan) then
            U().transferItemVerified(U().inventory(player), source, ring)
            U().call(actor, "setPrimaryHandItem", loan)
            return false, "loaned_shovel_return_failed"
        end
        local data = U().modData(loan)
        if data then data.lfMerleLoanGroupId = nil end
        U().call(actor, "setPrimaryHandItem", itemFor(actor, "Base.Shovel"))
    end
    value.goldClaimed = true
    U().say(actor,
        "He buried one ring and a letter. Said true wealth was a story worth passing on. Damn fool was right.")
    return true, "granddaddy_ring_received"
end

return Merle
