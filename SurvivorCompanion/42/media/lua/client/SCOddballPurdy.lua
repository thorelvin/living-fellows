-- SPDX-License-Identifier: MIT
-- Strange Folk: the Purdy family at the upper-floor farm windows. Native
-- faction weapons do the damage; only a physically returned tagged body ends
-- their feud. Story state is scalar/save-safe and never contains a corpse.

local SC = SurvivorCompanion
SC.OddballPurdy = SC.OddballPurdy or {}
local Purdy = SC.OddballPurdy
local ID = "sniper_purdy_clan"
local SESSION = tostring({}) .. ":" .. tostring(os and os.time and os.time() or 0)
local GUNS = {
    ["member-1"] = "Base.HuntingRifle",
    ["member-2"] = "Base.VarmintRifle",
    ["member-3"] = "Base.DoubleBarrelShotgun",
}
local AMMO_BOX = {
    ["member-1"] = "Base.308Box",
    ["member-2"] = "Base.556Box",
    ["member-3"] = "Base.ShotgunShellsBox",
}
local FIRE_RANGE = { ["member-1"] = 18, ["member-2"] = 16,
    ["member-3"] = 9 }
local WARNING_MS = 3000
local SCAN_INTERVAL_MS = 4000
local RETURN_INTERVAL_MS = 2000

local lines = {
    warn = { "That's far enough. Tucker got that far too.",
        "That's far enough. Tucker got that far too." },
    blame = { "Strangers did it. Strangers always do.",
        "Strangers did it. Strangers always do." },
    fire = { "You bastards took my boy. Now I take yours.",
        "You people took my boy. Now I take yours." },
    returned = { "You brought him home. Lord. You brought him home.",
        "You brought him home. Lord. You brought him home." },
    clue = { "Tucker went down by the road. I couldn't bring him back.",
        "Tucker went down by the road. I couldn't bring him back." },
}

local function U() return SC.GameplayUtil end

local function stateFor(group)
    local state = type(group) == "table" and group.oddball or nil
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    state.weaponSeeded = type(state.weaponSeeded) == "table"
        and state.weaponSeeded or {}
    return state
end

local function memberFor(group, actor)
    local actorId = actor and U().idOf(actor)
    for _, member in ipairs(group.members or {}) do
        if member.actorId == actorId then return member end
    end
    return nil
end

local function actorFor(group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId) or nil
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end

local function speak(group, key, index)
    local actor, choice = actorFor(group, index or 1), lines[key]
    if not actor or not choice then return false end
    return U().say(actor,
        choice[U().config("profanityEnabled") == false and 2 or 1]) == true
end

local function siteAnchor(state)
    return state.site and (state.site.anchor or state.site.spawn)
end

local function territoryDistance(state, value)
    local x, y, z = U().position(value)
    local bounds = state.site and state.site.house and state.site.house.bounds
    local anchor = siteAnchor(state)
    if x == nil or not bounds or not anchor
        or z ~= (tonumber(anchor.z) or 0) then return math.huge end
    local dx = x < bounds.x1 and bounds.x1 - x
        or x > bounds.x2 and x - bounds.x2 or 0
    local dy = y < bounds.y1 and bounds.y1 - y
        or y > bounds.y2 and y - bounds.y2 or 0
    return math.sqrt(dx * dx + dy * dy)
end

local function setStanding(group, standing)
    if SC.Factions and type(SC.Factions.forceStanding) == "function" then
        return SC.Factions.forceStanding(group.id, standing)
    end
    group.standing = standing
    group.lifecycle = standing == "Hostile" and "hostile" or "settled"
    return true, standing
end

local function bodyMarker(body)
    local data = U().modData(body)
    return type(data) == "table" and data or nil
end

local function taggedBodyOn(square, groupId, token)
    local found
    U().squareStaticMovingObjects(square, function(object)
        if found or not U().instanceOf(object, "IsoDeadBody") then return end
        local data = bodyMarker(object)
        if data and data.LF_PurdyGroupId == groupId
            and data.LF_PurdyToken == token then
            found = object
        end
    end, 32)
    return found
end

local function anyBodyOn(square)
    local found
    U().squareStaticMovingObjects(square, function(object)
        if not found and U().instanceOf(object, "IsoDeadBody") then
            found = object
        end
    end, 32)
    return found
end

local function roadSquare(square)
    local floor = select(1, U().call(square, "getFloor"))
    local sprite = floor and select(1, U().call(floor, "getSprite"))
    local name = sprite and select(1, U().call(sprite, "getName"))
    name = type(name) == "string" and string.lower(name) or ""
    return string.find(name, "blends_street", 1, true) ~= nil
        or string.find(name, "floors_exterior_street", 1, true) ~= nil
        or string.find(name, "street_", 1, true) == 1
end

local function unseen(player, square)
    local playerNum = select(1, U().call(player, "getPlayerNum"))
    if playerNum == nil then return false end
    local visible, called = U().call(square, "isCanSee", playerNum)
    return called and visible ~= true and not U().canSee(player, square)
end

-- Only loaded tiles near a player exploring the 100-200 tile ring are read.
-- This never searches unloaded map cells or spawns a body in view.
local function clueSquare(state, player)
    local anchor = siteAnchor(state)
    local px, py, pz = U().position(player)
    if not anchor or px == nil or pz ~= 0 then return nil end
    local ax, ay = tonumber(anchor.x), tonumber(anchor.y)
    if not ax or not ay then return nil end
    local r2 = (px - ax) * (px - ax) + (py - ay) * (py - ay)
    if r2 < 80 * 80 or r2 > 220 * 220 then return nil end
    -- Golden-angle samples cover a compact loaded ring without a grid-wide
    -- scan. Each candidate is a ditch beside a loaded road square.
    for index = 1, 160 do
        local angle = index * 2.399963229728653
        local radius = 10 + (index * 7 % 23)
        local x = math.floor(px + math.cos(angle) * radius)
        local y = math.floor(py + math.sin(angle) * radius)
        local dx, dy = x - ax, y - ay
        local distanceSq = dx * dx + dy * dy
        if distanceSq >= 100 * 100 and distanceSq <= 200 * 200 then
            local road = U().gridSquare(x, y, 0)
            if road and roadSquare(road) then
                for _, offset in ipairs({ { 1, 0 }, { -1, 0 },
                    { 0, 1 }, { 0, -1 } }) do
                    local ditch = U().gridSquare(x + offset[1], y + offset[2], 0)
                    if ditch and U().isSafeSpawnSquare(ditch)
                        and not roadSquare(ditch) and not anyBodyOn(ditch)
                        and unseen(player, ditch) then
                        local room = select(1, U().call(ditch, "getRoom"))
                        if room == nil then
                            return ditch, { x = x + offset[1],
                                y = y + offset[2], z = 0 }
                        end
                    end
                end
            end
        end
    end
end

local function markTucker(group, state, body)
    if not body or not U().instanceOf(body, "IsoDeadBody") then
        return false, "tucker_body_unavailable"
    end
    local data = bodyMarker(body)
    if not data then return false, "tucker_body_moddata_unavailable" end
    if data.LF_PurdyGroupId ~= nil and data.LF_PurdyGroupId ~= group.id then
        return false, "foreign_tagged_body"
    end
    data.LF_PurdyGroupId = group.id
    data.LF_PurdyToken = state.tuckerToken
    local descriptor = select(1, U().call(body, "getDescriptor"))
    if descriptor then
        U().call(descriptor, "setForename", "Tucker")
        U().call(descriptor, "setSurname", "Purdy")
    end
    local inventory = select(1, U().call(body, "getContainer"))
    if inventory and data.LF_PurdyLetterAdded ~= true then
        local letter = U().addItem(inventory, "Base.LetterHandwritten")
        if letter then
            U().call(letter, "setName", "Tucker's mother's letter")
            U().call(letter, "setCustomName", true)
            local letterData = U().modData(letter)
            if letterData then
                letterData.LF_PurdyLetter = true
                letterData.LF_PurdyGroupId = group.id
                letterData.SC_NoteText = "Tucker, come home before dark. Love, Ma."
            end
            data.LF_PurdyLetterAdded = true
        end
    end
    state.tuckerStatus = "placed"
    return true, "tucker_body_placed"
end

local function spawnTucker(group, player, state)
    if state.tuckerStatus ~= nil then return false, "tucker_already_attempted" end
    local square, position = clueSquare(state, player)
    if not square then return false, "no_loaded_roadside_ditch" end
    if type(createRandomDeadBody) ~= "function" then
        return false, "corpse_spawn_unavailable"
    end
    state.tuckerToken = state.tuckerToken or (group.id .. ":tucker")
    state.tuckerSquare = position
    -- Commit the attempt before calling the engine. A failed return value or
    -- interrupted spawn cannot lead to a second corpse after save/load.
    state.tuckerStatus = "attempted"
    local ok, returned = pcall(createRandomDeadBody, square, 6)
    if not ok then return false, "corpse_spawn_failed" end
    local body = U().instanceOf(returned, "IsoDeadBody") and returned
        or anyBodyOn(square)
    if not body then return false, "corpse_spawn_pending_verify" end
    return markTucker(group, state, body)
end

local function verifyAttempted(group, state)
    if state.tuckerStatus ~= "attempted" then return false end
    local location = state.tuckerSquare
    local square = location and U().gridSquare(location.x, location.y,
        location.z or 0)
    if not square then return false, "tucker_square_unloaded" end
    local tagged = taggedBodyOn(square, group.id, state.tuckerToken)
    if tagged then
        state.tuckerStatus = "placed"
        return true, "tucker_body_verified"
    end
    local body = anyBodyOn(square)
    if body then return markTucker(group, state, body) end
    return false, "tucker_body_not_found"
end

local function homeBody(group, state)
    if state.tuckerStatus ~= "placed" or not state.tuckerToken then return nil end
    local bounds = state.site and state.site.house and state.site.house.bounds
    if type(bounds) ~= "table" then return nil end
    local width = (tonumber(bounds.x2) or 0) - (tonumber(bounds.x1) or 0)
    local height = (tonumber(bounds.y2) or 0) - (tonumber(bounds.y1) or 0)
    if width > 24 or height > 24 or width < 0 or height < 0 then return nil end
    local scanned = 0
    for x = bounds.x1 - 3, bounds.x2 + 3 do
        for y = bounds.y1 - 3, bounds.y2 + 3 do
            scanned = scanned + 1
            if scanned > 900 then return nil end
            local square = U().gridSquare(x, y, 0)
            if square then
                local body = taggedBodyOn(square, group.id, state.tuckerToken)
                if body then return body end
            end
        end
    end
end

local function returnTucker(group, state)
    if state.tuckerReturned == true then return true, "tucker_already_home" end
    local body = homeBody(group, state)
    if not body then return false, "tucker_body_not_at_farm" end
    local restored, reason = setStanding(group, "Wary")
    if not restored then return false, reason end
    state.tuckerReturned = true
    state.stage = "reconciled"
    group.barterUnlocked = true
    speak(group, "returned")
    return true, "tucker_brought_home"
end

local function memberPerch(group, actor)
    local state = stateFor(group)
    local member = memberFor(group, actor)
    local index = member and tonumber(member.key:match("^member%-(%d+)$"))
    return index and state and state.site
        and state.site.memberSpawns and state.site.memberSpawns[index], member
end

function Purdy.onSpawn(group, actor)
    local state = stateFor(group)
    if not state or not actor then return false, "wrong_oddball" end
    local _, member = memberPerch(group, actor)
    if not member then return false, "purdy_member_unavailable" end
    local kind = GUNS[member.key]
    if not kind then return false, "purdy_weapon_undefined" end
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    local weapon
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
        if U().itemType(item) == kind then weapon = item break end
    end
    if not weapon and state.weaponSeeded[member.key] ~= true then
        weapon = U().addItem(inventory, kind)
        if not weapon then return false, "purdy_weapon_unavailable" end
    end
    if not weapon then return false, "purdy_weapon_missing" end
    if state.weaponSeeded[member.key] ~= true then
        local ammoType = AMMO_BOX[member.key]
        local foundAmmo
        for _, item in ipairs(U().inventoryItemsDeep(inventory, 160, 8)) do
            if U().itemType(item) == ammoType then foundAmmo = item break end
        end
        if not foundAmmo and not U().addItem(inventory, ammoType) then
            return false, "purdy_ammunition_unavailable"
        end
        U().call(weapon, "setCurrentAmmoCount",
            member.key == "member-3" and 2
                or member.key == "member-1" and 4 or 5)
        state.weaponSeeded[member.key] = true
    end
    if not select(1, U().call(actor, "getPrimaryHandItem")) then
        U().call(actor, "setPrimaryHandItem", weapon)
        if member.key == "member-3" then
            U().call(actor, "setSecondaryHandItem", weapon)
        end
    end
    return true, "purdy_perch_ready"
end

local function clearSightStep(from, to, dx, dy, dz)
    -- The engine's LosUtil.lineClear calls this native edge test on each
    -- traversed square. Asking it directly also works for a non-local NPC,
    -- whose cached player visibility is unrelated to his firing lane.
    local result, called = U().call(to, "testVisionAdjacent",
        -dx, -dy, -dz, false, false)
    if not called or result == nil then return false, false end
    local kind = tostring(result)
    local window = kind == "ClearThroughWindow"
    if kind ~= "Clear" and kind ~= "ClearThroughOpenDoor" and not window then
        return false, false
    end
    if window then
        -- Barricaded windows can otherwise look visually clear in some tile
        -- states. Refuse the shot if either side reports a blocked opening.
        local blockedFrom, checkedFrom = U().call(from, "isWindowBlockedTo", to)
        local blockedTo, checkedTo = U().call(to, "isWindowBlockedTo", from)
        if not checkedFrom or not checkedTo or blockedFrom or blockedTo then
            return false, false
        end
    end
    return true, window
end

local function upperWindowSight(actor, target)
    local ax, ay, az = U().position(actor)
    local tx, ty, tz = U().position(target)
    if ax == nil or tx == nil or az ~= 1 or tz ~= 0 then return false end
    -- Floor heights are roughly three horizontal tiles. Follow the 3D lane
    -- through loaded native squares; an upper-floor window must be crossed.
    local dx, dy, dz = tx - ax, ty - ay, (tz - az) * 3
    local length = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
    if length < 0.01 or length > 24 then return false end
    local steps = math.ceil(length * 4)
    local px, py, pz = math.floor(ax), math.floor(ay), az
    if not U().gridSquare(px, py, pz) then return false end
    local crossedUpperWindow = false
    for index = 1, steps do
        local t = index / steps
        local nx = math.floor(ax + dx * t)
        local ny = math.floor(ay + dy * t)
        local nz = math.floor((az * 3 + 1.5 + dz * t) / 3)
        if nx ~= px or ny ~= py or nz ~= pz then
            local from = U().gridSquare(px, py, pz)
            local to = U().gridSquare(nx, ny, nz)
            if not from or not to then return false end
            local clear, window = clearSightStep(from, to,
                nx - px, ny - py, nz - pz)
            if not clear then return false end
            if window and pz == az and nz == az then
                crossedUpperWindow = true
            end
            px, py, pz = nx, ny, nz
        end
    end
    return crossedUpperWindow
end

local function friendlyShotBlocked(actor, target, group, player)
    local allies = {}
    for _, member in ipairs(group.members or {}) do
        if member.actorId ~= U().idOf(actor) and member.alive ~= false then
            local record = SC.Registry and SC.Registry.byId(member.actorId)
            if record and record.actor then allies[#allies + 1] = record.actor end
        end
    end
    local ax, ay, az = U().position(actor)
    local tx, ty, tz = U().position(target)
    if ax == nil or tx == nil then return true end
    if az == tz then
        if not SC.Combat or type(SC.Combat.friendlyFireBlocked) ~= "function" then
            return true
        end
        return SC.Combat.friendlyFireBlocked(actor, target, {
            player = player, allies = allies, kind = "ranged" }) == true
    end
    -- The shared combat gate deliberately blocks every cross-floor shot.
    -- Project the actual 3D sightline instead, with one floor equal to three
    -- horizontal tiles. Any clan member in its 0.8-tile corridor vetoes fire.
    local dz = ((tz or 0) - (az or 0)) * 3
    local dx, dy = tx - ax, ty - ay
    local lengthSq = dx * dx + dy * dy + dz * dz
    if lengthSq < 0.01 then return true end
    for _, ally in ipairs(allies) do
        local x, y, z = U().position(ally)
        if x ~= nil then
            local vx, vy, vz = x - ax, y - ay, ((z or 0) - (az or 0)) * 3
            local t = math.max(0, math.min(1,
                (vx * dx + vy * dy + vz * dz) / lengthSq))
            local ex, ey, ez = vx - t * dx, vy - t * dy, vz - t * dz
            if ex * ex + ey * ey + ez * ez <= 0.8 * 0.8 then
                return true
            end
        end
    end
    return false
end

function Purdy.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local now = tonumber(current) or U().nowMs()
    if state.tuckerStatus == "attempted" then verifyAttempted(group, state) end
    if state.tuckerStatus == nil and now >= (tonumber(state.nextClueScanAt) or 0) then
        state.nextClueScanAt = now + SCAN_INTERVAL_MS
        spawnTucker(group, player, state)
    end
    if state.tuckerStatus == "placed" and state.tuckerReturned ~= true
        and territoryDistance(state, player) <= 24
        and now >= (tonumber(state.nextReturnScanAt) or 0) then
        state.nextReturnScanAt = now + RETURN_INTERVAL_MS
        local returned = returnTucker(group, state)
        if returned then return true, "tucker_brought_home" end
    end
    if state.tuckerReturned then return true, "reconciled" end
    local distance = territoryDistance(state, player)
    if state.stage == "unmet" and distance <= 25 then
        state.stage = "warned"
        state.warnedAt = now
        state.warningSession = SESSION
        group.discovered = true
        speak(group, "warn")
    elseif state.stage == "warned" and distance <= 25 then
        if state.warningSession ~= SESSION or now < (tonumber(state.warnedAt) or now) then
            state.warnedAt = now
            state.warningSession = SESSION
            return true, "purdy_warning_restarted_after_load"
        end
        if now - (tonumber(state.warnedAt) or now) < WARNING_MS then
            return true, "purdy_warning_pending"
        end
        local hostile, reason = setStanding(group, "Hostile")
        if not hostile then return false, reason end
        state.stage = "hostile"
        speak(group, "blame")
    end
    return true, state.stage
end

function Purdy.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    return { priority = group.standing == "Hostile" and 110 or 35,
        kind = "faction", mode = "purdy_perch", factionId = group.id }
end

function Purdy.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    local perch, member = memberPerch(group, actor)
    if not perch or not member then return false, "purdy_perch_unavailable" end
    if state.tuckerReturned == true and member.key == "member-1" then
        perch = state.site and state.site.tradePost
        if not perch then return false, "purdy_trade_post_unavailable" end
    end
    if U().distance(actor, perch) > 1.6 then
        local square = U().gridSquare(perch.x, perch.y, perch.z or 1)
        if square and SC.Navigation and type(SC.Navigation.request) == "function" then
            return SC.Navigation.request(actor, square, "walk", {
                action = "purdy_return_to_perch", targetSquare = square,
                arrivalDistance = 1.1 })
        end
        return false, "purdy_perch_unloaded"
    end
    if group.standing == "Hostile" and player
        and U().distance(actor, player) <= (FIRE_RANGE[member.key] or 12)
        and upperWindowSight(actor, player)
        and not friendlyShotBlocked(actor, player, group, player) then
        local weapon = select(1, U().call(actor, "getPrimaryHandItem"))
        if weapon and U().itemType(weapon) == GUNS[member.key] then
            local now = U().nowMs()
            if now >= (tonumber(state.nextFireLineAt) or 0) then
                state.nextFireLineAt = now + 20000
                speak(group, "fire")
            end
            return U().move(actor, "walk", { action = "attack_firearm",
                weapon = weapon, target = player, factionCombat = true })
        end
    end
    if player and U().distance(actor, player) <= 25 then
        return U().move(actor, "walk", { action = "face_alert",
            target = player, facingTarget = player, stableFacing = true,
            weaponReady = true, humanAnimationOnly = true })
    end
    U().stop(actor)
    return true, "purdy_at_window"
end

function Purdy.canRecruit(group)
    return false, "purdy_family_stays_at_farm"
end

function Purdy.menuOptions(group, player)
    local state = stateFor(group)
    if not state then return {} end
    local nearby = territoryDistance(state, player) <= 24
    local detail
    if state.tuckerStatus == "placed" and state.tuckerSquare then
        local anchor = siteAnchor(state)
        local dx = state.tuckerSquare.x - anchor.x
        local dy = state.tuckerSquare.y - anchor.y
        local direction = (dy < -20 and "north" or dy > 20 and "south" or "")
            .. (dx < -20 and "west" or dx > 20 and "east" or "")
        detail = "A roadside ditch about "
            .. tostring(math.floor(math.sqrt(dx * dx + dy * dy)))
            .. " tiles " .. direction .. " of the farm"
    elseif state.tuckerStatus == "attempted" then
        detail = "The roadside clue is still being verified"
    else
        detail = "Search loaded roadside ditches 100-200 tiles from the farm"
    end
    if state.tuckerReturned then return {} end
    return {
        { id = "ask_tucker", label = "Ask about Tucker", enabled = nearby,
            detail = detail },
        { id = "return_tucker", label = "Bring Tucker home",
            enabled = nearby and state.tuckerStatus == "placed",
            detail = "Bring his body, then leave it by the farmhouse" },
    }
end

function Purdy.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hurt" then
        if state.tuckerReturned then return false, "normal_faction_offense" end
        state.stage = "hostile"
        setStanding(group, "Hostile")
        return true, "purdy_defends_farm"
    elseif action == "ask_tucker" then
        if territoryDistance(state, player) > 24 then return false, "too_far_away" end
        speak(group, "clue")
        return true, "tucker_clue_told"
    elseif action == "return_tucker" then
        if territoryDistance(state, player) > 24 then return false, "too_far_away" end
        return returnTucker(group, state)
    end
    return false, "unsupported_purdy_action"
end

return Purdy
