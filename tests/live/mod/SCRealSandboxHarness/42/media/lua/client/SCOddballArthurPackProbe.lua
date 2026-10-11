-- SPDX-License-Identifier: MIT
-- Real-room smoke tests on the live runner's disposable save clone.
-- Each invocation creates one authored encounter and observes native actors.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCOddballArthurPackProbe = Probe

local DEFINITIONS = {
    arthur = { id = "bedridden_arthur_hale", room = "bedroom" },
    pack = { id = "spiffo_dressup_ambush", room = "livingroom" },
}
local COSTUME = { "Base.SpiffoSuit", "Base.Hat_Spiffo",
    "Base.SpiffoTail" }

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    return okay and value or nil
end

local function actorFor(SC, group, index)
    local member = group and group.members and group.members[index]
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    return record and record.actor and SC.GameplayUtil.isValidActor(record.actor)
        and record.actor or nil
end

local function move(player, square)
    return square ~= nil and pcall(function()
        player:teleportTo(square:getX() + 0.5, square:getY() + 0.5,
            square:getZ())
    end)
end

local function roomName(square)
    local room = call(square, "getRoom")
    return string.lower(tostring(call(room, "getName") or ""))
end

local function bridgeFailure()
    local method = SCBridge and SCBridge.getLastFailure
    if not method then return nil end
    local okay, value = pcall(method)
    return okay and value or nil
end

local function bedPerimeterDetail(SC, bedRoom)
    local U = SC.GameplayUtil
    local parts = {}
    for y = 5491, 5494 do
        for x = 6473, 6476 do
            if x == 6473 or x == 6476 or y == 5491
                or y == 5494 then
                local square = U.gridSquare(x, y, 0)
                parts[#parts + 1] = tostring(x) .. "," .. tostring(y)
                    .. ":" .. tostring(square ~= nil)
                    .. "/room=" .. tostring(square
                        and call(square, "getRoom") == bedRoom)
                    .. "/clear=" .. tostring(square
                        and U.isClearActorSpawnSquare(square) == true)
            end
        end
    end
    return table.concat(parts, ";")
end

local function keepArthurSceneQuiet(SC, H, current)
    if current < (H.encounterNextQuietAt or 0) then return end
    H.encounterNextQuietAt = current + 500
    local bx, by
    if H.encounterObserveBedSquare then
        bx, by = call(H.encounterObserveBedSquare, "getX"),
            call(H.encounterObserveBedSquare, "getY")
    else
        bx, by = SC.GameplayUtil.position(H.player)
    end
    call(H.player, "setGodMod", true)
    call(H.player, "setInvincible", true)
    call(H.player, "setGhostMode", true)
    call(H.player, "setInvisible", true)
    local cell = type(getCell) == "function" and getCell() or nil
    local zombies = call(cell, "getZombieList")
    local removed = 0
    if zombies and bx and by and SC.NativeList then
        for index = SC.NativeList.size(zombies) - 1, 0, -1 do
            local zombie = SC.NativeList.get(zombies, index)
            local x, y = SC.GameplayUtil.position(zombie)
            if x and math.abs(x - bx) <= 35
                and math.abs(y - by) <= 35 then
                call(zombie, "setTarget", nil)
                call(zombie, "removeFromWorld")
                call(zombie, "removeFromSquare")
                removed = removed + 1
            end
        end
    end
    H.encounterClearedZombies = (H.encounterClearedZombies or 0) + removed
    -- The disposable seed observer carries test supplies above the normal
    -- limit. Heavy-load damage can continue even with the native cheats.
    call(H.player, "setHealth", 100.0)
    local damage = call(H.player, "getBodyDamage")
    call(damage, "setOverallBodyHealth", 100.0)
    call(damage, "setInfected", false)
end

local function pinnedArthurPoseSite(SC, target, house)
    if not target or not house or roomName(target) ~= "bedroom" then
        return nil
    end
    local U = SC.GameplayUtil
    local tx, ty = call(target, "getX"), call(target, "getY")
    local spawnTile = tx and ty and U.gridSquare(tx - 1, ty + 1, 0)
    if not spawnTile or call(spawnTile, "getRoom")
        ~= call(target, "getRoom")
        or not U.isClearActorSpawnSquare(spawnTile) then return nil end
    local list = call(target, "getObjects")
    local bedIndex
    for index = 0, (list and SC.NativeList.size(list) or 0) - 1 do
        local object = SC.NativeList.get(list, index)
        local sprite = call(object, "getSprite")
        local name = tostring(call(sprite, "getName") or "")
        if string.find(name, "furniture_bedding", 1, true)
            and SC.Oddballs.nativeBedFootEntry(object) then
            bedIndex = index
            break
        end
    end
    if bedIndex == nil then return nil end
    local doorPost
    for _, opening in ipairs(house.openings or {}) do
        if opening.kind == "door" then
            doorPost = { x = opening.x, y = opening.y,
                z = opening.z or 0, objectIndex = opening.objectIndex }
            break
        end
    end
    doorPost = doorPost or { x = tx - 1, y = ty + 1,
        z = 0, objectIndex = -1 }
    local spawn = { x = tx - 1, y = ty + 1, z = 0 }
    return { kind = "resident", room = "bedroom", house = house,
        anchor = house.anchor, spawn = spawn, floor = spawn,
        bed = { x = tx, y = ty, z = 0, objectIndex = bedIndex },
        bedroomDoor = doorPost }
end

local function scanSite(SC, H, key)
    local definition = DEFINITIONS[key]
    local U = SC.GameplayUtil
    local x0 = tonumber(H.config.oddball_site_x) or 0
    local y0 = tonumber(H.config.oddball_site_y) or 0
    if x0 <= 0 or y0 <= 0 then
        local x, y = U.position(H.player)
        x0, y0 = math.floor(x or 0), math.floor(y or 0)
    end
    local targetX = tonumber(H.config.oddball_bed_x) or 0
    local targetY = tonumber(H.config.oddball_bed_y) or 0
    if key == "arthur" and targetX > 0 and targetY > 0 then
        local target = U.gridSquare(targetX, targetY, 0)
        local house, rejected
        if target then
            house, rejected = SC.Factions.oddballHouseAt(target,
                H.player, true)
        end
        local direct
        if key == "arthur" and H.config.oddball_pose_only == "true" then
            direct = pinnedArthurPoseSite(SC, target, house)
        else
            direct = target and roomName(target) == definition.room
                and SC.Oddballs._siteForResidentForTests(target, H.player,
                    SC.Oddballs.definition(definition.id),
                    definition.room, true) or nil
        end
        H.encounterPinnedDetail = "target=" .. targetX .. "," .. targetY
            .. " loaded=" .. tostring(target ~= nil)
            .. " room=" .. roomName(target)
            .. " building=" .. tostring(call(target, "getBuilding") ~= nil)
            .. " house=" .. tostring(house ~= nil)
            .. " rejected=" .. tostring(rejected)
            .. " directBed=" .. tostring(direct and direct.bed
                and direct.bed.x) .. "," .. tostring(direct and direct.bed
                and direct.bed.y)
        if direct and key == "arthur"
            and H.config.oddball_pose_only == "true" then
            return direct, true
        end
    end
    H.encounterBuildings = H.encounterBuildings or {}
    for _ = 1, 220 do
        local index = H.encounterScanIndex or 0
        if index >= 81 * 81 then return nil, true end
        H.encounterScanIndex = index + 1
        for z = 0, 1 do
            local square = U.gridSquare(x0 + index % 81 - 40,
                y0 + math.floor(index / 81) - 40, z)
            if square and roomName(square) == definition.room then
                H.encounterRoomsSeen = (H.encounterRoomsSeen or 0) + 1
                local building = call(square, "getBuilding")
                if building and not H.encounterBuildings[building] then
                    H.encounterBuildings[building] = true
                    H.encounterBuildingsSeen = (H.encounterBuildingsSeen or 0) + 1
                    local site = SC.Oddballs._siteForResidentForTests(square,
                        H.player, SC.Oddballs.definition(definition.id),
                        definition.room, true)
                    if key == "arthur" and targetX > 0 and site
                        and #(H.encounterAlternateBeds or {}) < 5 then
                        H.encounterAlternateBeds = H.encounterAlternateBeds or {}
                        H.encounterAlternateBeds[#H.encounterAlternateBeds + 1]
                            = tostring(site.bed and site.bed.x) .. ","
                                .. tostring(site.bed and site.bed.y)
                    end
                    if site and (key ~= "arthur" or targetX <= 0
                        or site.bed and site.bed.x == targetX
                            and site.bed.y == targetY) then
                        return site, true
                    end
                end
            end
        end
    end
    return nil, false
end

local function waitingSquare(SC, site, minimum, maximum)
    local U, post = SC.GameplayUtil, site.spawn
    for radius = minimum or 14, maximum or 22 do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(post.x + dx,
                        post.y + dy, post.z or 0)
                    if square and call(square, "getRoom") == nil
                        and U.isSafeSpawnSquare(square) then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function roomObserverSquare(SC, site, leader, maxDistance)
    local U = SC.GameplayUtil
    local origin = U.gridSquare(site.spawn.x, site.spawn.y,
        site.spawn.z or 0)
    local room = call(origin, "getRoom")
    local ax, ay = U.position(leader)
    if not room or not ax then return nil end
    ax, ay = math.floor(ax), math.floor(ay)
    for radius = 1, maxDistance do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(ax + dx, ay + dy,
                        site.spawn.z or 0)
                    if square and call(square, "getRoom") == room
                        and U.isClearActorSpawnSquare(square) then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function bedObserverSquare(SC, bedSquare, maxDistance)
    local U = SC.GameplayUtil
    local room = call(bedSquare, "getRoom")
    local bx, by, bz = call(bedSquare, "getX"),
        call(bedSquare, "getY"), call(bedSquare, "getZ")
    if not room or not bx or not by then return nil end
    -- Keep the floor next to the bed free for Arthur's native entry action.
    -- The observer should see that action without standing on its approach.
    local radii = {}
    for radius = 2, maxDistance do radii[#radii + 1] = radius end
    radii[#radii + 1] = 1
    for _, radius in ipairs(radii) do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U.gridSquare(bx + dx, by + dy, bz or 0)
                    if square and call(square, "getRoom") == room
                        and U.isClearActorSpawnSquare(square) == true then
                        return square
                    end
                end
            end
        end
    end
    return nil
end

local function playerAtObserver(SC, player, observer, bedSquare)
    local U = SC.GameplayUtil
    local px, py, pz = U.position(player)
    local ox, oy, oz = call(observer, "getX"),
        call(observer, "getY"), call(observer, "getZ")
    local bx, by = call(bedSquare, "getX"), call(bedSquare, "getY")
    local square = call(player, "getSquare")
    local room = call(bedSquare, "getRoom")
    local atTile = px and ox and math.floor(px) == ox
        and math.floor(py) == oy and math.floor(pz or 0) == (oz or 0)
    local inRoom = room ~= nil and call(square, "getRoom") == room
    local close = px and bx and math.abs(px - bx) <= 4.5
        and math.abs(py - by) <= 4.5
    return atTile and inRoom and close,
        "player=" .. tostring(px) .. "," .. tostring(py) .. ","
            .. tostring(pz) .. " square=" .. tostring(call(square, "getX"))
            .. "," .. tostring(call(square, "getY"))
            .. " room=" .. roomName(square)
            .. " observer=" .. tostring(ox) .. "," .. tostring(oy)
            .. "," .. tostring(oz)
            .. " bed=" .. tostring(bx) .. "," .. tostring(by)
            .. " atTile=" .. tostring(atTile)
            .. " inRoom=" .. tostring(inRoom)
            .. " close=" .. tostring(close)
end

local function withSpeech(SC, action)
    local U, lines = SC.GameplayUtil, {}
    local original = U.say
    U.say = function(actor, line, ...)
        lines[#lines + 1] = tostring(line)
        return original(actor, line, ...)
    end
    local okay, accepted, reason = pcall(action)
    U.say = original
    return okay and accepted, okay and reason or tostring(accepted), lines
end

local function beginPackSpeech(H, SC)
    if H.encounterOriginalSay then return end
    H.encounterSpeech = {}
    H.encounterOriginalSay = SC.GameplayUtil.say
    SC.GameplayUtil.say = function(speaker, line, ...)
        for _, actor in ipairs(H.encounterActors or {}) do
            if speaker == actor then
                H.encounterSpeech[#H.encounterSpeech + 1] = tostring(line)
                break
            end
        end
        return H.encounterOriginalSay(speaker, line, ...)
    end
end

local function endPackSpeech(H, SC)
    if H.encounterOriginalSay then
        SC.GameplayUtil.say = H.encounterOriginalSay
        H.encounterOriginalSay = nil
    end
end

local function lineContains(lines, text)
    for _, line in ipairs(lines or {}) do
        if string.find(line, text, 1, true) then return true end
    end
    return false
end

local function hasOption(options, id)
    for _, option in ipairs(options or {}) do
        if option.id == id and option.enabled == true then return true end
    end
    return false
end

local function isBedFixture(object)
    if not object then return false end
    local name = string.lower(tostring(call(object, "getName") or ""))
    local sprite = call(object, "getSprite")
    local spriteName = string.lower(tostring(call(sprite, "getName") or ""))
    return (string.find(name, "bed", 1, true) ~= nil
            and string.find(name, "bedside", 1, true) == nil)
        or string.find(spriteName, "furniture_bedding", 1, true) ~= nil
end

local function seatedOnSelectedBed(SC, actor, bedObject, bedSquare)
    local seatedObject = call(actor, "getSitOnFurnitureObject")
    if not seatedObject or not bedObject then return false end
    if seatedObject == bedObject then return true end
    local square = SC.GameplayUtil.squareOf(seatedObject)
    return isBedFixture(seatedObject)
        and square ~= nil and bedSquare ~= nil
        and SC.GameplayUtil.distance(square, bedSquare) <= 1.5
        and call(square, "getRoom") == call(bedSquare, "getRoom")
end

local function actorOnBedFootprint(SC, actor, bedSquare)
    local U = SC.GameplayUtil
    local x, y, z = U.position(actor)
    if not x or not bedSquare then return false end
    local tile = U.gridSquare(math.floor(x), math.floor(y),
        math.floor(z or 0))
    if not tile or U.distance(tile, bedSquare) > 1.5
        or call(tile, "getRoom") ~= call(bedSquare, "getRoom") then
        return false
    end
    local objects = call(tile, "getObjects")
    for index = 0, (objects and SC.NativeList.size(objects) or 0) - 1 do
        if isBedFixture(SC.NativeList.get(objects, index)) then return true end
    end
    return false
end

local function nativeBedEntryDetail(SC, bedObject, bedSquare)
    local manager
    pcall(function() manager = SeatingManager.getInstance() end)
    local facing = tostring(call(manager, "getFacingDirection", bedObject))
    local sprite = call(bedObject, "getSprite")
    local grid = call(sprite, "getSpriteGrid")
    local gx = tonumber(call(grid, "getSpriteGridPosX", sprite))
    local gy = tonumber(call(grid, "getSpriteGridPosY", sprite))
    local nx = tonumber(call(bedSquare, "getX")) or 0
    local ny = tonumber(call(bedSquare, "getY")) or 0
    if facing == "N" and gy == 0 then ny = ny + 1 end
    if facing == "S" and gy == 1 then ny = ny - 1 end
    if facing == "W" and gx == 0 then nx = nx + 1 end
    if facing == "E" and gx == 1 then nx = nx - 1 end
    local normalized = bedObject
    if nx ~= (tonumber(call(bedSquare, "getX")) or 0)
        or ny ~= (tonumber(call(bedSquare, "getY")) or 0) then
        normalized = nil
        local otherSquare = SC.GameplayUtil.gridSquare(nx, ny,
            call(bedSquare, "getZ") or 0)
        local otherObjects = call(otherSquare, "getObjects")
        for index = 0, (otherObjects
            and SC.NativeList.size(otherObjects) or 0) - 1 do
            local other = SC.NativeList.get(otherObjects, index)
            local otherSprite = call(other, "getSprite")
            if call(otherSprite, "getSpriteGrid") == grid
                and tonumber(call(grid, "getSpriteGridPosX", otherSprite))
                    == gx + nx - (tonumber(call(bedSquare, "getX")) or 0)
                and tonumber(call(grid, "getSpriteGridPosY", otherSprite))
                    == gy + ny - (tonumber(call(bedSquare, "getY")) or 0) then
                normalized = other
                break
            end
        end
    end
    local actionFacing = tostring(call(manager, "getFacingDirection",
        normalized))
    local normalizedSprite = call(normalized, "getSprite")
    local actionX = tonumber(call(normalized, "getX"))
    local actionY = tonumber(call(normalized, "getY"))
    local actionFX, actionFY = actionX, actionY
    if actionX and actionY then
        if actionFacing == "N" then
            actionFX, actionFY = actionX + 0.5, actionY - 1.3
        elseif actionFacing == "S" then
            actionFX, actionFY = actionX + 0.5, actionY + 2.3
        elseif actionFacing == "W" then
            actionFX, actionFY = actionX - 1.3, actionY + 0.5
        elseif actionFacing == "E" then
            actionFX, actionFY = actionX + 2.3, actionY + 0.5
        end
    end
    local actionFoot = actionFX and actionFY
        and SC.GameplayUtil.gridSquare(math.floor(actionFX),
            math.floor(actionFY), call(bedSquare, "getZ") or 0) or nil
    local actionFootClear, actionFootReason
    if actionFoot then
        actionFootClear, actionFootReason =
            SC.GameplayUtil.isClearActorSpawnSquare(actionFoot)
    end
    local rawX = tonumber(call(bedSquare, "getX"))
    local rawY = tonumber(call(bedSquare, "getY"))
    local rawFX, rawFY = rawX, rawY
    if rawX and rawY then
        if facing == "N" then
            rawFX, rawFY = rawX + 0.5, rawY - 1.3
        elseif facing == "S" then
            rawFX, rawFY = rawX + 0.5, rawY + 2.3
        elseif facing == "W" then
            rawFX, rawFY = rawX - 1.3, rawY + 0.5
        elseif facing == "E" then
            rawFX, rawFY = rawX + 2.3, rawY + 0.5
        end
    end
    local rawFoot = rawFX and rawFY
        and SC.GameplayUtil.gridSquare(math.floor(rawFX),
            math.floor(rawFY), call(bedSquare, "getZ") or 0) or nil
    local rawFootClear, rawFootReason
    if rawFoot then
        rawFootClear, rawFootReason =
            SC.GameplayUtil.isClearActorSpawnSquare(rawFoot)
    end
    local fx, fy = nx, ny
    if facing == "N" then fx, fy = nx + 0.5, ny - 1.3 end
    if facing == "S" then fx, fy = nx + 0.5, ny + 2.3 end
    if facing == "W" then fx, fy = nx - 1.3, ny + 0.5 end
    if facing == "E" then fx, fy = nx + 2.3, ny + 0.5 end
    local foot = SC.GameplayUtil.gridSquare(math.floor(fx),
        math.floor(fy), call(bedSquare, "getZ") or 0)
    local sidePosts
    if facing == "W" or facing == "E" then
        sidePosts = { { nx, ny - 1 }, { nx, ny + 1 } }
    else
        sidePosts = { { nx - 1, ny }, { nx + 1, ny } }
    end
    local headSides = {}
    for _, post in ipairs(sidePosts) do
        local side = SC.GameplayUtil.gridSquare(post[1], post[2],
            call(bedSquare, "getZ") or 0)
        local clear, reason
        if side then
            clear, reason = SC.GameplayUtil.isClearActorSpawnSquare(side)
        end
        headSides[#headSides + 1] = tostring(post[1]) .. ","
            .. tostring(post[2]) .. ":" .. tostring(clear)
            .. "/" .. tostring(reason)
    end
    local footClear, footReason
    if foot then
        footClear, footReason = SC.GameplayUtil.isClearActorSpawnSquare(foot)
    end
    return " sprite=" .. tostring(call(sprite, "getName"))
        .. " facing=" .. facing .. " grid=" .. tostring(gx)
        .. "," .. tostring(gy) .. " normalized=" .. tostring(nx)
        .. "," .. tostring(ny)
        .. " actionSprite=" .. tostring(call(normalizedSprite, "getName"))
        .. " actionFacing=" .. actionFacing
        .. " sameFacing=" .. tostring(actionFacing == facing)
        .. " actionFoot=" .. tostring(actionFX and math.floor(actionFX))
        .. "," .. tostring(actionFY and math.floor(actionFY))
        .. " actionFootRoom=" .. roomName(actionFoot)
        .. " actionFootClear=" .. tostring(actionFootClear)
        .. "/" .. tostring(actionFootReason)
        .. " rawFoot=" .. tostring(rawFX and math.floor(rawFX))
        .. "," .. tostring(rawFY and math.floor(rawFY))
        .. " rawFootRoom=" .. roomName(rawFoot)
        .. " rawFootClear=" .. tostring(rawFootClear)
        .. "/" .. tostring(rawFootReason)
        .. " foot=" .. tostring(math.floor(fx))
        .. "," .. tostring(math.floor(fy)) .. " footRoom="
        .. roomName(foot) .. " footClear="
        .. tostring(footClear) .. "/" .. tostring(footReason)
        .. " headSides=" .. table.concat(headSides, ";"),
        footClear == true, actionFacing == facing,
        actionFootClear == true and actionFoot
            and roomName(actionFoot) == roomName(bedSquare),
        rawFootClear == true and rawFoot
            and roomName(rawFoot) == roomName(bedSquare)
end

local function arthurPoseDetail(actor, bedObject)
    local forward = call(actor, "getForwardDirection")
    local x, y = call(actor, "getX"), call(actor, "getY")
    local sprite = call(bedObject, "getSprite")
    return " actor=" .. tostring(x) .. "," .. tostring(y)
        .. " dir=" .. tostring(call(actor, "getDir"))
        .. " animAngleRadians=" .. tostring(call(actor,
            "getAnimAngleRadians"))
        .. " forward=" .. tostring(call(forward, "getX")
            or forward and forward.x) .. ","
            .. tostring(call(forward, "getY") or forward and forward.y)
        .. " onBedDirection=" .. tostring(call(actor,
            "getVariableString", "OnBedDirection"))
        .. " onBedAnim=" .. tostring(call(actor,
            "getVariableString", "OnBedAnim"))
        .. " selectedSprite=" .. tostring(call(sprite, "getName"))
end

local function bedActionAnchorDetail(actor, bed)
    local manager
    pcall(function() manager = SeatingManager.getInstance() end)
    return "actor=" .. tostring(call(actor, "getX"))
        .. "," .. tostring(call(actor, "getY"))
        .. " bed=" .. tostring(call(bed, "getX"))
        .. "," .. tostring(call(bed, "getY"))
        .. " facing=" .. tostring(call(manager,
            "getFacingDirection", bed))
        .. " direction=" .. tostring(call(actor,
            "getVariableString", "OnBedDirection"))
end

local function bedActionRuntimeDetail(actor, bed)
    local path = call(actor, "getPathFindBehavior2")
    local function observed(method, ...)
        local okay, value = pcall(function(...)
            return actor[method](actor, ...)
        end, ...)
        if okay then return value end
        return nil
    end
    return bedActionAnchorDetail(actor, bed)
        .. " moving=" .. tostring(observed("isPlayerMoving"))
        .. " turning=" .. tostring(observed("shouldBeTurning"))
        .. " path=" .. tostring(call(actor, "getCompanionPathStatus"))
        .. " pathNext=" .. tostring(path and path.pathNextIsSet)
        .. " bPathfind=" .. tostring(observed(
            "getVariableBoolean", "bPathfind"))
        .. " owner=" .. tostring(call(actor,
            "getCompanionMovementOwner"))
        .. " aim=" .. tostring(observed("hasCompanionAimTarget"))
        .. " forward=" .. tostring(call(actor,
            "getForwardDirectionX")) .. ","
            .. tostring(call(actor, "getForwardDirectionY"))
        .. " forwardAngle=" .. tostring(call(actor,
            "getDirectionAngleRadians"))
        .. " animAngle=" .. tostring(call(actor,
            "getAnimAngleRadians"))
        .. " onBed=" .. tostring(observed("isOnBed"))
        .. " started=" .. tostring(observed(
            "getVariableBoolean", "OnBedStarted"))
end

local function instrumentArthurBedAction(H)
    if H.encounterBedActionInstrumented then return end
    if type(ISGetOnBedAction) ~= "table" then
        pcall(require, "TimedActions/ISGetOnBedAction")
    end
    local actionClass = ISGetOnBedAction
    if type(actionClass) ~= "table"
        or type(actionClass.new) ~= "function"
        or type(actionClass.setBeforeSitDirection) ~= "function" then
        return
    end
    H.encounterBedActionInstrumented = true
    local function trace(stage, actor, bed)
        if H.encounterActors and H.encounterActors[1] ~= actor then
            return
        end
        local detail = stage .. " " .. bedActionRuntimeDetail(actor, bed)
        H.encounterBedActionTrace = H.encounterBedActionTrace or {}
        if #H.encounterBedActionTrace < 24 then
            H.encounterBedActionTrace[#H.encounterBedActionTrace + 1] =
                detail
        end
        print("SC_ARTHUR_BED_TRACE|" .. detail)
    end
    local originalNew = actionClass.new
    actionClass.new = function(self, actor, bed)
        local action = originalNew(self, actor, bed)
        if not H.encounterActors or H.encounterActors[1] == actor then
            H.encounterBedActionCreated = bedActionAnchorDetail(actor,
                bed)
        end
        return action
    end
    local originalBefore = actionClass.setBeforeSitDirection
    actionClass.setBeforeSitDirection = function(self)
        local actor, bed = self.character, self.bed
        local watch = not H.encounterActors
            or H.encounterActors[1] == actor
        local before = watch and bedActionAnchorDetail(actor, bed)
            or nil
        local value = originalBefore(self)
        if watch then
            H.encounterBedBeforeSitCalls =
                (H.encounterBedBeforeSitCalls or 0) + 1
            local detail = "pre=" .. before
                .. " post=" .. bedActionAnchorDetail(actor, bed)
            if not H.encounterBedBeforeSitFirst then
                H.encounterBedBeforeSitFirst = detail
            end
            H.encounterBedBeforeSitLast = detail
        end
        return value
    end
    local originalWait = actionClass.waitToStart
    actionClass.waitToStart = function(self)
        local sample = (H.encounterBedWaitSamples or 0) < 8
        if sample then
            H.encounterBedWaitSamples =
                (H.encounterBedWaitSamples or 0) + 1
            trace("wait_pre", self.character, self.bed)
        end
        local waiting = originalWait(self)
        if sample then
            trace("wait_post=" .. tostring(waiting),
                self.character, self.bed)
        end
        return waiting
    end
    local originalStart = actionClass.start
    actionClass.start = function(self)
        trace("start_pre", self.character, self.bed)
        local value = originalStart(self)
        trace("start_post", self.character, self.bed)
        return value
    end
    local originalUpdate = actionClass.update
    actionClass.update = function(self)
        if not H.encounterBedStartedSampled
            and call(self.character, "getVariableBoolean",
                "OnBedStarted") == true then
            H.encounterBedStartedSampled = true
            trace("on_bed_started", self.character, self.bed)
        end
        return originalUpdate(self)
    end
end

local function bedActionQueueDetail(actor)
    local queues = ISTimedActionQueue
    local queue
    if type(queues) == "table"
        and type(queues.getTimedActionQueue) == "function" then
        local okay, value = pcall(queues.getTimedActionQueue, actor)
        if okay then queue = value end
    end
    local action = queue and queue.current or nil
    local goal = action and action.goal or nil
    local bed = action and action.bed or nil
    return " queueCurrent=" .. tostring(action and action.Type)
        .. " queueSize=" .. tostring(queue and queue.queue
            and #queue.queue)
        .. " queueFirst=" .. tostring(queue and queue.queue
            and queue.queue[1] and queue.queue[1].Type)
        .. " actionStarted=" .. tostring(call(action, "isStarted"))
        .. " goal=" .. tostring(goal and goal[1])
        .. "/" .. tostring(goal and goal[2])
        .. "/" .. tostring(goal and goal[3])
        .. " bed=" .. tostring(call(bed, "getX"))
        .. "," .. tostring(call(bed, "getY"))
        .. " turning=" .. tostring(call(actor, "shouldBeTurning"))
        .. " onBedDirection=" .. tostring(call(actor,
            "getVariableString", "OnBedDirection"))
end

local function nearbyBedEntryDetails(SC, H)
    local U = SC.GameplayUtil
    local x0 = tonumber(H.config.oddball_site_x) or 0
    local y0 = tonumber(H.config.oddball_site_y) or 0
    local rawCandidates, compatible, mismatched, blocked, seen =
        {}, {}, {}, {}, {}
    for dy = -45, 45 do
        for dx = -45, 45 do
            local square = U.gridSquare(x0 + dx, y0 + dy, 0)
            if square and roomName(square) == "bedroom" then
                local objects = call(square, "getObjects")
                for index = 0, (objects and SC.NativeList.size(objects) or 0) - 1 do
                    local object = SC.NativeList.get(objects, index)
                    if isBedFixture(object) then
                        local detail, footClear, sameFacing, _, rawClear =
                            nativeBedEntryDetail(SC, object, square)
                        local key = tostring(call(square, "getX")) .. ","
                            .. tostring(call(square, "getY"))
                        if not seen[key] then
                            seen[key] = true
                            local row = key .. detail
                            if rawClear and #rawCandidates < 12 then
                                rawCandidates[#rawCandidates + 1] = row
                            end
                            if footClear and sameFacing then
                                if #compatible < 8 then
                                    compatible[#compatible + 1] = row
                                end
                            elseif footClear then
                                if #mismatched < 8 then
                                    mismatched[#mismatched + 1] = row
                                end
                            elseif #blocked < 8 then
                                blocked[#blocked + 1] = row
                            end
                        end
                    end
                end
            end
        end
    end
    local rows = {}
    for _, row in ipairs(rawCandidates) do
        rows[#rows + 1] = "raw_foot_clear " .. row
    end
    for _, row in ipairs(compatible) do
        rows[#rows + 1] = "compatible_clear " .. row
    end
    for _, row in ipairs(mismatched) do
        rows[#rows + 1] = "mismatched_clear " .. row
    end
    for _, row in ipairs(blocked) do
        rows[#rows + 1] = "blocked " .. row
    end
    return rows
end

local function costumeState(SC, actor)
    local U, inventory = SC.GameplayUtil, SC.GameplayUtil.inventory(actor)
    local found, worn = {}, 0
    for _, item in ipairs(inventory and U.inventoryItemsDeep(inventory,
        240, 10) or {}) do
        found[U.itemType(item)] = item
    end
    for _, kind in ipairs(COSTUME) do
        local item = found[kind]
        local location = call(item, "getBodyLocation")
        if item and location and call(actor, "getWornItem", location) == item then
            worn = worn + 1
        end
    end
    local primary = call(actor, "getPrimaryHandItem")
    local secondary = call(actor, "getSecondaryHandItem")
    return worn, primary and U.itemType(primary) or nil,
        secondary and U.itemType(secondary) or nil
end

local function stop(H, result, setPhase, current, name, detail)
    endPackSpeech(H, SurvivorCompanion)
    result("FAIL", name, detail)
    setPhase("finish", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local U = SC.GameplayUtil
    local key = H.config.oddball_arthur_probe == "true"
        and "arthur" or "pack"
    local label = key == "arthur" and "arthur" or "pack"
    local definition = DEFINITIONS[key]
    if key == "arthur" then keepArthurSceneQuiet(SC, H, current) end

    if H.phase == "encounter_prepare" then
        if key == "arthur"
            and H.config.oddball_arthur_player_baseline ~= "true" then
            instrumentArthurBedAction(H)
        end
        if key == "arthur" then
            -- The clone's observer must survive long enough for visual QA.
            -- God mode stays on through capture; only this disposable save
            -- and this private harness ever receive the flag.
            pcall(function() H.player:setGodMod(true) end)
            pcall(function() H.player:setInvincible(true) end)
            pcall(function() H.player:setHealthCheat(true) end)
            pcall(function() H.player:setUnlimitedCarry(true) end)
            pcall(function() H.player:setMaxWeight(1000) end)
            if H.config.oddball_pose_only == "true" then
                -- Leave the scene open for a live visual inspection after
                -- the automatic screenshot is taken.
                H.config.internal_timeout_ms = "600000"
            end
        end
        if not check(label .. "_definition_ready",
            SC.Oddballs.definition(definition.id) ~= nil
                and type(SC.Oddballs._siteForResidentForTests) == "function"
                and (key == "arthur" and SC.OddballBedridden ~= nil
                    or key == "pack" and SC.OddballFurryPack ~= nil),
            definition.id .. " native scene registered") then
            setPhase("finish", current) return
        end
        require("SCOddballCoreyEarlProbe")
        local fixture = SCRealSandboxHarnessProbes.SCOddballCoreyEarlProbe
        local isolated, reason = fixture.clearExistingOddball(SC,
            definition.id)
        if not check(label .. "_clone_scene_isolated", isolated,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        pcall(function() H.player:setInvisible(true) end)
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
        local x = tonumber(H.config.oddball_site_x) or 0
        local y = tonumber(H.config.oddball_site_y) or 0
        if x > 0 and y > 0 then
            local moved = pcall(function()
                H.player:teleportTo(x + 0.5, y + 0.5, 0)
            end)
            if not check(label .. "_search_area_loaded", moved,
                tostring(x) .. "," .. tostring(y)) then
                setPhase("finish", current) return
            end
        end
        setPhase("encounter_find_site", current)
        return
    end

    if H.phase == "encounter_find_site" then
        if current < (H.encounterRetryAt or 0) then return end
        if current - H.phaseStartedAt < 2000 then return end
        if key == "arthur" and H.config.oddball_pose_only == "true"
            and not H.encounterMovedOutsideForSite then
            local tx = tonumber(H.config.oddball_bed_x)
            local ty = tonumber(H.config.oddball_bed_y)
            local target = tx and ty and U.gridSquare(tx, ty, 0)
            local building = target and call(target, "getBuilding")
            local playerSquare = U.squareOf(H.player)
            if building and call(playerSquare, "getBuilding") == building then
                local outside
                for radius = 2, 25 do
                    for dx = -radius, radius do
                        for dy = -radius, radius do
                            if math.max(math.abs(dx), math.abs(dy))
                                == radius then
                                local candidate = U.gridSquare(tx + dx,
                                    ty + dy, 0)
                                if candidate and call(candidate, "getRoom")
                                    == nil and call(candidate, "getBuilding")
                                    ~= building
                                    and U.isClearActorSpawnSquare(candidate)
                                    then outside = candidate break end
                            end
                        end
                        if outside then break end
                    end
                    if outside then break end
                end
                if outside then
                    move(H.player, outside)
                    H.encounterMovedOutsideForSite = true
                    H.encounterOutsideForSite = outside
                    H.encounterOutsideMovedAt = current
                    H.encounterRetryAt = current + 2500
                    result("SKIP", "arthur_house_scan_observer_outside",
                        "player moved to " .. tostring(call(outside,
                            "getX")) .. "," .. tostring(call(outside,
                            "getY")) .. " before selecting the house")
                    return
                end
            end
        end
        if key == "arthur" and H.encounterMovedOutsideForSite then
            local tx = tonumber(H.config.oddball_bed_x)
            local ty = tonumber(H.config.oddball_bed_y)
            local target = tx and ty and U.gridSquare(tx, ty, 0)
            local building = target and call(target, "getBuilding")
            if building and call(U.squareOf(H.player), "getBuilding")
                == building then
                if current - (H.encounterOutsideMovedAt or current)
                    > 10000 then
                    stop(H, result, setPhase, current,
                        "arthur_house_scan_outside",
                        "observer remained inside the candidate house")
                else
                    move(H.player, H.encounterOutsideForSite)
                    H.encounterRetryAt = current + 500
                end
                return
            end
        end
        if key == "arthur"
            and (H.config.oddball_pose_only == "true"
                or H.config.oddball_arthur_bed_survey_only == "true")
            and not H.encounterBedSurveyLogged then
            H.encounterBedSurveyLogged = true
            local rows = nearbyBedEntryDetails(SC, H)
            for _, detail in ipairs(rows) do
                result("SKIP", "arthur_nearby_bed_entry", detail)
            end
            if H.config.oddball_arthur_bed_survey_only == "true" then
                result("PASS", "arthur_bed_survey_complete",
                    "bed_tiles_logged=" .. tostring(#rows))
                setPhase("finish", current)
                return
            end
        end
        local site, finished = scanSite(SC, H, key)
        if not site then
            if finished and current - H.phaseStartedAt <= 45000 then
                -- A remote teleport can expose room metadata before every
                -- room tile and opening is fully streamed. Re-evaluate the
                -- same buildings after a short delay instead of rejecting a
                -- temporarily incomplete house for the whole run.
                H.encounterScanIndex = 0
                H.encounterBuildings = {}
                H.encounterRetryAt = current + 2500
                return
            end
            if current - H.phaseStartedAt > 45000 then
                stop(H, result, setPhase, current,
                    label .. "_real_" .. definition.room,
                    "no eligible loaded furnished room within 40 tiles; scanned="
                        .. tostring(H.encounterScanIndex or 0)
                        .. " named_squares="
                        .. tostring(H.encounterRoomsSeen or 0)
                        .. " buildings="
                        .. tostring(H.encounterBuildingsSeen or 0)
                        .. " " .. tostring(H.encounterPinnedDetail or "")
                        .. " alternateBeds=" .. table.concat(
                            H.encounterAlternateBeds or {}, ";"))
            end
            return
        end
        H.encounterSite = site
        if key == "arthur"
            and H.config.oddball_arthur_player_baseline == "true" then
            local bed = site.bed or {}
            local square = bed.x and U.gridSquare(bed.x, bed.y,
                bed.z or 0) or nil
            local objects = call(square, "getObjects")
            local bedObject = objects and SC.NativeList.get(objects,
                bed.objectIndex) or nil
            local stand = U.gridSquare(site.spawn.x, site.spawn.y,
                site.spawn.z or 0)
            if not check("arthur_player_baseline_bed",
                bedObject ~= nil and move(H.player, stand),
                nativeBedEntryDetail(SC, bedObject, square)) then
                setPhase("finish", current) return
            end
            call(H.player, "setInvisible", false)
            call(H.player, "setVariable", "OnBedAnim", "Awake")
            local menu = ISWorldObjectContextMenu
            if type(menu) ~= "table"
                or type(menu.onGetOnBed) ~= "function" then
                pcall(require, "ISUI/ISWorldObjectContextMenu")
                menu = ISWorldObjectContextMenu
            end
            local queued = type(menu) == "table"
                and type(menu.onGetOnBed) == "function"
                and pcall(menu.onGetOnBed, H.player, bedObject)
            if not check("arthur_player_baseline_queued", queued,
                "stock ISWorldObjectContextMenu.onGetOnBed") then
                setPhase("finish", current) return
            end
            H.encounterBedObject = bedObject
            H.encounterBedSquare = square
            setPhase("encounter_arthur_player_pose", current)
            return
        end
        if key == "arthur" then
            local bed = site.bed or {}
            local bedSquare = H.config.oddball_arthur_head_side_trial == "true"
                and U.gridSquare(6475, 5492, 0)
                or bed.x and U.gridSquare(bed.x, bed.y, bed.z or 0)
                or nil
            -- This four-sprite double bed has its head at y=5492 and foot
            -- at y=5493. Let the player watch from the clear bedroom tile
            -- immediately past the foot, leaving Arthur's east entry free.
            local observer = (H.config.oddball_arthur_head_side_trial
                    == "true" or (H.config.oddball_pose_only == "true"
                    and call(bedSquare, "getX") == 6474
                    and call(bedSquare, "getY") == 5492))
                and U.gridSquare(6475, 5494, 0)
                or bedObserverSquare(SC, bedSquare, 4)
            local observerRoom = observer
                and call(observer, "getRoom") == call(bedSquare, "getRoom")
            local observerClear = observer
                and U.isClearActorSpawnSquare(observer) == true
            if not check("arthur_bedroom_observer_available",
                observer ~= nil and observerRoom == true
                    and observerClear == true,
                "bed=" .. tostring(call(bedSquare, "getX")) .. ","
                    .. tostring(call(bedSquare, "getY"))
                    .. " room=" .. roomName(bedSquare)
                    .. " foot_observer=" .. tostring(call(observer,
                        "getX")) .. "," .. tostring(call(observer, "getY"))
                    .. " same_room=" .. tostring(observerRoom)
                    .. " clear=" .. tostring(observerClear)) then
                setPhase("finish", current) return
            end
            H.encounterObserveBedSquare = bedSquare
            H.encounterObserveSquare = observer
            if H.config.oddball_pose_only ~= "true"
                and H.config.oddball_arthur_head_side_trial ~= "true" then
                -- Normal encounter timing: the player is outside the house
                -- while Arthur enters the bed, then approaches only after the
                -- native pose is settled. Production scans 35–90 tiles away.
                local waiting = waitingSquare(SC, site, 35, 42)
                    or waitingSquare(SC, site)
                local distance = waiting and U.distance(waiting, bedSquare)
                local unseen = waiting and move(H.player, waiting)
                    and call(U.squareOf(H.player), "getRoom") == nil
                    and call(bedSquare, "isCanSee", 0) ~= true
                    and U.canSee(H.player, bedSquare) ~= true
                if not check("arthur_normal_arrival_unseen",
                    unseen == true,
                    "player_to_bed=" .. tostring(distance)
                        .. " room=" .. roomName(U.squareOf(H.player))) then
                    setPhase("finish", current) return
                end
                H.encounterNormalArrival = true
                local group, reason = SC.Factions.createOddballGroup(site,
                    SC.Oddballs.definition(definition.id), true)
                if not check("arthur_group_created", group ~= nil,
                    tostring(reason)) then
                    setPhase("finish", current) return
                end
                H.encounterGroup = group
                H.encounterCreatedAt = current
                setPhase("encounter_spawn", current)
                return
            end
            if H.config.oddball_arthur_head_side_trial == "true" then
                -- Cache clearance before Arthur spawns. Once his body is on
                -- this tile, the occupancy-aware spawn predicate says false.
                H.encounterTrialSideClear = U.isClearActorSpawnSquare(
                    U.gridSquare(6473, 5493, 0)) == true
                result("SKIP", "arthur_bed_perimeter",
                    bedPerimeterDetail(SC, call(bedSquare, "getRoom")))
            end
            move(H.player, observer)
            H.encounterLastObserverMove = current
            setPhase("encounter_observer_position", current)
            return
        end
        local waiting = waitingSquare(SC, site)
        if not check(label .. "_observer_waiting_outside",
            move(H.player, waiting),
            "native encounter is seeded in a real " .. definition.room) then
            setPhase("finish", current) return
        end
        local group, reason = SC.Factions.createOddballGroup(site,
            SC.Oddballs.definition(definition.id), true)
        if not check(label .. "_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.encounterGroup = group
        setPhase("encounter_spawn", current)
        return
    end

    if H.phase == "encounter_observer_position" then
        local placed, detail = playerAtObserver(SC, H.player,
            H.encounterObserveSquare, H.encounterObserveBedSquare)
        if not placed then
            if current - H.phaseStartedAt > 12000 then
                stop(H, result, setPhase, current,
                    "arthur_observer_in_bedroom", detail)
                return
            end
            if current - (H.encounterLastObserverMove or 0) >= 900 then
                move(H.player, H.encounterObserveSquare)
                H.encounterLastObserverMove = current
            end
            return
        end
        if current - H.phaseStartedAt < 2000 then return end
        if not check("arthur_observer_in_bedroom", placed, detail) then
            setPhase("finish", current) return
        end
        if IsoCamera then
            pcall(function() IsoCamera.SetCharacterToFollow(H.player) end)
        end
        local core = type(getCore) == "function" and getCore() or nil
        local zoom = tonumber(call(core, "getZoom", 0)) or 0
        if zoom > 0.5 then
            for _ = 1, math.min(6,
                math.ceil((zoom - 0.5) / 0.25)) do
                call(core, "doZoomScroll", 0, -1)
            end
        end
        if not check("arthur_observer_preview_ready",
            H.encounterSignals.write(
                "SurvivorCompanionHarness/oddball-observer-ready.txt",
                { "ready=true", "kind=arthur", detail }),
            detail) then
            setPhase("finish", current) return
        end
        setPhase("encounter_observer_preview", current)
        return
    end

    if H.phase == "encounter_observer_preview" then
        local placed, detail = playerAtObserver(SC, H.player,
            H.encounterObserveSquare, H.encounterObserveBedSquare)
        if not placed then
            if current - H.phaseStartedAt > 12000 then
                stop(H, result, setPhase, current,
                    "arthur_observer_stayed_in_bedroom", detail)
                return
            end
            if current - (H.encounterLastObserverMove or 0) >= 900 then
                move(H.player, H.encounterObserveSquare)
                H.encounterLastObserverMove = current
            end
            return
        end
        local previewMs = H.config.oddball_pose_only == "true"
            and 18000 or 2000
        if current - H.phaseStartedAt < previewMs then return end
        local group, reason = SC.Factions.createOddballGroup(
            H.encounterSite, SC.Oddballs.definition(definition.id), true)
        if not check("arthur_group_created", group ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.encounterGroup = group
        setPhase("encounter_spawn", current)
        return
    end

    if H.phase == "encounter_spawn" then
        local group = H.encounterGroup
        local expected = key == "arthur" and 1 or 4
        local actors = {}
        for index = 1, expected do
            actors[index] = actorFor(SC, group, index)
        end
        local ready = #group.members == expected
        for index = 1, expected do
            if not actors[index] then ready = false end
        end
        if not ready then
            if current - H.phaseStartedAt > 30000 then
                stop(H, result, setPhase, current,
                    label .. "_native_actors_spawned",
                    "members=" .. tostring(#group.members)
                        .. " first=" .. tostring(actors[1]))
            end
            return
        end
        H.encounterActors = actors
        if key == "arthur" and H.encounterNormalArrival then
            H.encounterSpawnReadyAt = current
        end
        local room = call(U.gridSquare(H.encounterSite.spawn.x,
            H.encounterSite.spawn.y, H.encounterSite.spawn.z or 0),
            "getRoom")
        local allInRoom = room ~= nil
        for index = 1, expected do
            allInRoom = allInRoom
                and call(call(actors[index], "getSquare"), "getRoom") == room
        end
        if not check(label .. "_native_actors_spawned", allInRoom,
            "members=" .. tostring(#group.members)
                .. " room=" .. tostring(call(room, "getName"))) then
            setPhase("finish", current) return
        end
        if key == "arthur"
            and H.config.oddball_arthur_head_side_trial == "true" then
            -- The literal pillow-row side tile is obstructed. Select the
            -- pillow-row bed object itself, entering from the nearest clear
            -- west-side bedroom tile beside the foot row.
            local trialBedSquare = U.gridSquare(6474, 5492, 0)
            local objects = call(trialBedSquare, "getObjects")
            local trialBed
            for index = 0, (objects
                and SC.NativeList.size(objects) or 0) - 1 do
                local candidate = SC.NativeList.get(objects, index)
                if isBedFixture(candidate) then
                    trialBed = candidate
                    break
                end
            end
            local approach = U.gridSquare(6473, 5493, 0)
            local clear = approach and (H.encounterTrialSideClear
                or U.isClearActorSpawnSquare(approach) == true)
            local sameRoom = approach and call(approach, "getRoom")
                == call(trialBedSquare, "getRoom")
            if not check("arthur_head_side_trial_bed",
                trialBed ~= nil and clear == true and sameRoom == true,
                "bed=" .. tostring(trialBed)
                    .. " approach_clear=" .. tostring(clear)
                    .. " same_room=" .. tostring(sameRoom)
                    .. " room=" .. roomName(approach)) then
                setPhase("finish", current) return
            end
            pcall(require, "Vehicles/TimedActions/ISPathFindAction")
            pcall(require, "TimedActions/ISGetOnBedAction")
            local actor = actors[1]
            local staging = U.gridSquare(6473, 5493, 0)
            local stagingClear = staging and (H.encounterTrialSideClear
                or U.isClearActorSpawnSquare(staging) == true)
            local stagingRoom = staging
                and call(staging, "getRoom")
                    == call(trialBedSquare, "getRoom")
            if not check("arthur_trial_staging_available",
                stagingClear and stagingRoom,
                "staging_clear=" .. tostring(stagingClear)
                    .. " same_room=" .. tostring(stagingRoom)
                    .. " room=" .. roomName(staging)) then
                setPhase("finish", current) return
            end
            local placed, placementError = pcall(function()
                actor:teleportTo(staging:getX() + 0.5,
                    staging:getY() + 0.5, staging:getZ())
            end)
            local membership = "not_needed"
            if actor.ensureWorldMembership then
                local membershipOk, membershipError = pcall(function()
                    actor:ensureWorldMembership()
                end)
                membership = membershipOk and "ok"
                    or tostring(membershipError)
            end
            if not check("arthur_trial_teleported",
                placed,
                "teleport=" .. tostring(placed)
                    .. " error=" .. tostring(placementError)
                    .. " membership=" .. membership) then
                setPhase("finish", current) return
            end
            H.encounterBedObject = trialBed
            H.encounterBedSquare = trialBedSquare
            H.encounterTrialStaging = staging
            H.encounterLastTrialMove = current
            setPhase("encounter_trial_stage_wait", current)
            return
        end
        if key == "arthur" and H.config.oddball_pose_only == "true"
            and tonumber(H.config.oddball_bed_x) == 6474
            and tonumber(H.config.oddball_bed_y) == 5492 then
            local trialBedSquare = U.gridSquare(6474, 5492, 0)
            local staging = U.gridSquare(6473, 5493, 0)
            local placed = staging and call(staging, "getRoom")
                == call(trialBedSquare, "getRoom")
                and move(actors[1], staging)
            call(actors[1], "ensureWorldMembership")
            if not check("arthur_production_actor_teleported",
                placed == true,
                "staging=" .. tostring(staging ~= nil)
                    .. " same_room=" .. tostring(staging and
                        call(staging, "getRoom")
                            == call(trialBedSquare, "getRoom"))) then
                setPhase("finish", current) return
            end
            H.encounterProductionStage = true
            H.encounterBedSquare = trialBedSquare
            H.encounterTrialStaging = staging
            H.encounterLastTrialMove = current
            setPhase("encounter_trial_stage_wait", current)
            return
        end
        setPhase(key == "arthur" and "encounter_arthur_pose"
            or "encounter_pack_costumes", current)
        return
    end

    if H.phase == "encounter_trial_stage_wait" then
            local actor = H.encounterActors[1]
            local staging = H.encounterTrialStaging
            local trialBed = H.encounterBedObject
            local trialBedSquare = H.encounterBedSquare
            local ax, ay, az = U.position(actor)
            local actorSquare = call(actor, "getSquare")
            local squareX, squareY = call(actorSquare, "getX"),
                call(actorSquare, "getY")
            local physical = ax and ay and U.gridSquare(math.floor(ax),
                math.floor(ay), math.floor(az or 0))
            local staged = ax and math.floor(ax) == staging:getX()
                and math.floor(ay) == staging:getY()
                and math.floor(az or 0) == staging:getZ()
                and squareX == staging:getX()
                and squareY == staging:getY()
                and call(actorSquare, "getRoom")
                    == call(trialBedSquare, "getRoom")
                and call(physical, "getRoom")
                    == call(trialBedSquare, "getRoom")
            local detail = "actor=" .. tostring(ax) .. "," .. tostring(ay)
                .. "," .. tostring(az) .. " actorSquare="
                .. tostring(squareX) .. "," .. tostring(squareY)
                .. " actorRoom=" .. roomName(actorSquare)
                .. " physicalRoom=" .. roomName(physical)
                .. " sameRoom=" .. tostring(call(actorSquare, "getRoom")
                    == call(trialBedSquare, "getRoom"))
            if not staged then
                if current - H.phaseStartedAt > 12000 then
                    stop(H, result, setPhase, current,
                        "arthur_trial_actor_staged_in_bedroom", detail)
                    return
                end
                if current - (H.encounterLastTrialMove or 0) >= 1000 then
                    move(actor, staging)
                    call(actor, "ensureWorldMembership")
                    H.encounterLastTrialMove = current
                end
                return
            end
            if current - H.phaseStartedAt < 500 then return end
            if not check("arthur_trial_actor_staged_in_bedroom",
                staged, detail) then
                setPhase("finish", current) return
            end
            if H.encounterProductionStage == true then
                setPhase("encounter_arthur_pose", current)
                return
            end
            call(actor, "setVariable", "OnBedAnim", "Awake")
            local pathOk, path = pcall(ISPathFindAction.pathToLocationF,
                ISPathFindAction, actor, 6473.7, 5493.5, 0)
            local bedOk, bedAction = pcall(ISGetOnBedAction.new,
                ISGetOnBedAction, actor, trialBed)
            if bedOk and bedAction and type(bedAction.waitToStart)
                == "function" then
                local stockWait = bedAction.waitToStart
                bedAction.waitToStart = function(self)
                    local x, y, z = U.position(self.character)
                    if x == nil or math.floor(z or 0) ~= 0
                        or math.abs(x - 6473.7) > 0.45
                        or math.abs(y - 5493.5) > 0.45 then
                        return true
                    end
                    return stockWait(self)
                end
            end
            local queued = pathOk and path and bedOk and bedAction
                and pcall(ISTimedActionQueue.add, path)
                and pcall(ISTimedActionQueue.add, bedAction)
            if not check("arthur_head_side_trial_queued", queued,
                "target=6473.7,5493.5 actionBed="
                    .. bedActionAnchorDetail(actor, trialBed)) then
                setPhase("finish", current) return
            end
            setPhase("encounter_arthur_head_side_trial", current)
            return
    end

    if H.phase == "encounter_arthur_head_side_trial" then
        local actor = H.encounterActors[1]
        local onBed = call(actor, "isOnBed") == true
        local started = call(actor, "getVariableBoolean",
            "OnBedStarted") == true
        if onBed and started then
            local footprint = actorOnBedFootprint(SC, actor,
                H.encounterBedSquare)
            call(actor, "setVariable", "OnBedAnim", "Asleep")
            result("SKIP", "arthur_head_side_trial_pose",
                arthurPoseDetail(actor, H.encounterBedObject)
                    .. " footprint=" .. tostring(footprint)
                    .. " nativeBedIdentity=" .. tostring(call(actor,
                        "isSitOnFurnitureObject",
                        H.encounterBedObject))
                    .. " beforeCalls="
                    .. tostring(H.encounterBedBeforeSitCalls)
                    .. " before="
                    .. tostring(H.encounterBedBeforeSitFirst)
                    .. " queue=" .. bedActionQueueDetail(actor))
            if H.config.oddball_scene_screenshot == "true" then
                local core = type(getCore) == "function" and getCore()
                    or nil
                local zoom = tonumber(call(core, "getZoom", 0)) or 0
                if zoom > 0.5 then
                    for _ = 1, math.min(6,
                        math.ceil((zoom - 0.5) / 0.25)) do
                        call(core, "doZoomScroll", 0, -1)
                    end
                end
                H.encounterZoomBefore = zoom
                setPhase("encounter_arthur_zoom", current)
            else
                setPhase("finish", current)
            end
            return
        end
        if current - H.phaseStartedAt >= 14000
            and not H.encounterLieTimeoutLogged then
            H.encounterLieTimeoutLogged = true
            result("SKIP", "arthur_head_side_trial_pending",
                arthurPoseDetail(actor, H.encounterBedObject)
                    .. " onBed=" .. tostring(onBed)
                    .. " started=" .. tostring(started)
                    .. " before="
                    .. tostring(H.encounterBedBeforeSitFirst)
                    .. bedActionQueueDetail(actor))
        end
        if current - H.phaseStartedAt > 28000 then
            stop(H, result, setPhase, current,
                "arthur_head_side_trial_pose",
                arthurPoseDetail(actor, H.encounterBedObject)
                    .. " onBed=" .. tostring(onBed)
                    .. " started=" .. tostring(started)
                    .. " before="
                    .. tostring(H.encounterBedBeforeSitLast)
                    .. bedActionQueueDetail(actor))
        end
        return
    end

    if H.phase == "encounter_arthur_player_pose" then
        local actor = H.player
        if call(actor, "isOnBed") ~= true
            or call(actor, "getVariableBoolean", "OnBedStarted") ~= true then
            if current - H.phaseStartedAt > 30000 then
                stop(H, result, setPhase, current,
                    "arthur_player_baseline_native_pose",
                    arthurPoseDetail(actor, H.encounterBedObject)
                        .. " onBed=" .. tostring(call(actor, "isOnBed")))
            end
            return
        end
        call(actor, "setVariable", "OnBedAnim", "Asleep")
        result("PASS", "arthur_player_baseline_native_pose",
            arthurPoseDetail(actor, H.encounterBedObject)
                .. nativeBedEntryDetail(SC, H.encounterBedObject,
                    H.encounterBedSquare))
        local core = type(getCore) == "function" and getCore() or nil
        local zoom = tonumber(call(core, "getZoom", 0)) or 0
        if zoom > 0.5 then
            for _ = 1, math.min(6, math.ceil((zoom - 0.5) / 0.25)) do
                call(core, "doZoomScroll", 0, -1)
            end
        end
        if H.config.oddball_scene_screenshot == "true" then
            local signaled = H.encounterSignals.write(
                "SurvivorCompanionHarness/oddball-scene-ready.txt",
                { "ready=true", "kind=arthur_player_baseline" })
            if not check("arthur_player_baseline_capture_ready", signaled,
                "stock player bed pose ready for screenshot") then
                setPhase("finish", current) return
            end
            setPhase("encounter_arthur_player_capture", current)
        else
            setPhase("finish", current)
        end
        return
    end

    if H.phase == "encounter_arthur_player_capture" then
        if H.encounterSignals.exists(
            "SurvivorCompanionHarness/oddball-scene-captured.txt") then
            result("PASS", "arthur_player_baseline_capture",
                "stock player bed pose captured")
            setPhase("finish", current)
        elseif current - H.phaseStartedAt > 15000 then
            stop(H, result, setPhase, current,
                "arthur_player_baseline_capture",
                "runner did not capture player bed scene")
        end
        return
    end

    if H.phase == "encounter_arthur_pose" then
        local actor = H.encounterActors[1]
        local nativeStatus = SC.NativeActions.bedStatus(actor)
        local onBed = call(actor, "isOnBed") == true
        local bedStarted = call(actor, "getVariableBoolean",
            "OnBedStarted") == true
        local furniture = call(actor, "isSittingOnFurniture") == true
        local seatedObject = call(actor, "getSitOnFurnitureObject")
        local bed = H.encounterGroup.oddball.site.bed or {}
        local bedSquare = bed.x and U.gridSquare(bed.x, bed.y,
            bed.z or 0) or nil
        local bedObjects = call(bedSquare, "getObjects")
        local bedObject = bedObjects and SC.NativeList.get(bedObjects,
            bed.objectIndex) or nil
        local x, y, z = U.position(actor)
        local story = H.encounterGroup.oddball
        if onBed and bedStarted
            and story.nativeBedPoseStarted ~= true then
            H.encounterLastUpdate = current
            local handled, reason = SC.OddballBedridden.update(actor,
                H.player, nil,
                { mode = "bedridden_arthur" }, H.encounterGroup)
            H.encounterLastUpdateReason = tostring(handled)
                .. "/" .. tostring(reason)
            -- The production update can move the settled pose to the pillow
            -- square in this same tick. Never judge persistence using the
            -- coordinates sampled before that move.
            x, y, z = U.position(actor)
            nativeStatus = SC.NativeActions.bedStatus(actor)
            onBed = call(actor, "isOnBed") == true
            bedStarted = call(actor, "getVariableBoolean",
                "OnBedStarted") == true
            furniture = call(actor, "isSittingOnFurniture") == true
            seatedObject = call(actor, "getSitOnFurnitureObject")
        end
        if current - (H.encounterLastNativePoseTraceAt or 0) >= 700
            and (onBed or H.encounterFirstNativeLie) then
            H.encounterLastNativePoseTraceAt = current
            result("SKIP", "arthur_native_pose_timeline",
                "actor=" .. tostring(x) .. "," .. tostring(y)
                    .. " onBed=" .. tostring(onBed)
                    .. " started=" .. tostring(bedStarted)
                    .. " anim=" .. tostring(call(actor,
                        "getVariableString", "OnBedAnim"))
                    .. " update=" .. tostring(H.encounterLastUpdateReason)
                    .. " bridgeFailure=" .. tostring(bridgeFailure()))
        end
        if onBed and bedStarted and not H.encounterFirstNativeLie then
            H.encounterFirstNativeLie = current
            if H.config.oddball_pose_only == "true" then
                -- Visual experiment only: stock Sleep does not use the bed
                -- action, so hold its real OnBed state in the Asleep clip
                -- before the encounter's strict footprint recovery runs.
                call(actor, "setVariable", "OnBedAnim", "Asleep")
            end
            result("SKIP", "arthur_bed_action_created",
                tostring(H.encounterBedActionCreated))
            result("SKIP", "arthur_bed_action_prepost",
                "calls=" .. tostring(H.encounterBedBeforeSitCalls)
                    .. " first=" .. tostring(H.encounterBedBeforeSitFirst)
                    .. " last=" .. tostring(H.encounterBedBeforeSitLast))
            result("PASS", "arthur_native_lie_transition",
                "actor=" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z)
                    .. " bed=" .. tostring(bed.x) .. ","
                    .. tostring(bed.y)
                    .. " approach=" .. tostring(story.lieApproach)
                    .. " owner=" .. tostring(call(actor,
                        "getCompanionMovementOwner"))
                    .. " anim=" .. tostring(call(actor,
                        "getVariableString", "OnBedAnim"))
                    .. " fallback=" .. tostring(story.lieFallback)
                    .. " reason=" .. tostring(story.lieFallbackReason)
                    .. arthurPoseDetail(actor, bedObject))
        end
        if current - H.phaseStartedAt >= 14000
            and not H.encounterLieTimeoutLogged then
            H.encounterLieTimeoutLogged = true
            if not H.encounterFirstNativeLie then
                result("SKIP", "arthur_bed_action_pending",
                    "created=" .. tostring(H.encounterBedActionCreated)
                        .. " calls="
                        .. tostring(H.encounterBedBeforeSitCalls)
                        .. " last="
                        .. tostring(H.encounterBedBeforeSitLast))
            end
            result("PASS", "arthur_lie_fourteen_second_state",
                "actor=" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z)
                    .. " onBed=" .. tostring(onBed)
                    .. " started=" .. tostring(bedStarted)
                    .. " approach=" .. tostring(story.lieApproach)
                    .. " owner=" .. tostring(call(actor,
                        "getCompanionMovementOwner"))
                    .. " anim=" .. tostring(call(actor,
                        "getVariableString", "OnBedAnim"))
                    .. " fallback=" .. tostring(story.lieFallback)
                    .. " reason=" .. tostring(story.lieFallbackReason)
                    .. " update=" .. tostring(H.encounterLastUpdateReason)
                    .. " bridgeFailure=" .. tostring(bridgeFailure())
                    .. bedActionQueueDetail(actor))
        end
        local closeToBed = x and bed.x
            and math.abs(x - bed.x) <= 2.5
            and math.abs(y - bed.y) <= 2.5
            and math.floor(z or 0) == (bed.z or 0)
        local settledBedRest = nativeStatus == "entered"
            and furniture and closeToBed and bedObject ~= nil
            and seatedOnSelectedBed(SC, actor, bedObject, bedSquare)
        local pillowAligned = x and bed.x and bed.y
            and math.floor(x) == bed.x and math.floor(y) == bed.y
        if H.config.oddball_pose_only == "true"
            and story.nativeBedPoseStarted == true
            and pillowAligned == true
            and not H.encounterRenderLiftApplied then
            local method = SCBridge and SCBridge.setOnBedRenderLift
            local invoked, lifted = false, false
            if method then
                invoked, lifted = pcall(method, actor, 180)
            end
            if not invoked or lifted ~= true then
                stop(H, result, setPhase, current,
                    "arthur_render_only_lift",
                    "invoked=" .. tostring(invoked)
                        .. " lifted=" .. tostring(lifted)
                        .. " bridgeFailure=" .. tostring(bridgeFailure()))
                return
            end
            H.encounterRenderLiftApplied = true
            result("PASS", "arthur_render_only_lift",
                "milliTiles=180 onBed=" .. tostring(onBed)
                    .. " started=" .. tostring(bedStarted)
                    .. " sitting="
                    .. tostring(call(actor, "isSittingOnFurniture"))
                    .. " actor=" .. tostring(x) .. "," .. tostring(y))
        end
        local lyingOnBed = onBed and bedStarted
            and actorOnBedFootprint(SC, actor, bedSquare)
        if H.config.oddball_pose_only == "true"
            and (story.nativeBedPoseStarted ~= true
                or pillowAligned ~= true) then lyingOnBed = false
        end
        if H.config.oddball_pose_only == "true"
            and story.nativeBedPoseStarted == true then
            if not lyingOnBed then
                stop(H, result, setPhase, current,
                    "arthur_aligned_pose_persistence",
                    "actor=" .. tostring(x) .. "," .. tostring(y)
                        .. " onBed=" .. tostring(onBed)
                        .. " started=" .. tostring(bedStarted)
                        .. " anim=" .. tostring(call(actor,
                            "getVariableString", "OnBedAnim"))
                        .. " bridgeFailure=" .. tostring(bridgeFailure()))
                return
            end
            H.encounterAlignedAt = H.encounterAlignedAt or current
        end
        if H.config.oddball_pose_only == "true"
            and onBed and bedStarted
            and story.nativeBedPoseStarted == true
            and current - (H.encounterAlignedAt or current) >= 5000
            and current - (H.encounterFirstNativeLie or current) >= 3000 then
            result("SKIP", "arthur_visual_pose_observation",
                arthurPoseDetail(actor, bedObject)
                    .. " footprint=" .. tostring(lyingOnBed)
                    .. " nativeBedIdentity=" .. tostring(call(actor,
                        "isSitOnFurnitureObject", bedObject))
                    .. " nativeStatus=" .. tostring(nativeStatus)
                    .. " entry=" .. tostring(story.lieApproach)
                    .. " recovery=" .. tostring(story.lieRecovery)
                    .. " stableMs=" .. tostring(current
                        - (H.encounterAlignedAt or current))
                    .. " bridgeFailure=" .. tostring(bridgeFailure())
                    .. " renderLift="
                    .. tostring(H.encounterRenderLiftApplied)
                    .. nativeBedEntryDetail(SC, bedObject, bedSquare))
            H.encounterBedObject = bedObject
            H.encounterBedSquare = bedSquare
            if H.config.oddball_scene_screenshot == "true" then
                local core = type(getCore) == "function" and getCore()
                    or nil
                local zoom = tonumber(call(core, "getZoom", 0)) or 0
                if zoom > 0.5 then
                    for _ = 1, math.min(6,
                        math.ceil((zoom - 0.5) / 0.25)) do
                        call(core, "doZoomScroll", 0, -1)
                    end
                end
                H.encounterZoomBefore = zoom
                setPhase("encounter_arthur_zoom", current)
            else
                setPhase("finish", current)
            end
            return
        end
        if H.config.oddball_pose_only == "true"
            and story.nativeBedPoseStarted == true
            and (current - (H.encounterAlignedAt or current) < 5000
                or current - (H.encounterFirstNativeLie or current) < 3000) then
            return
        end
        if not lyingOnBed and not settledBedRest then
            if current - H.phaseStartedAt > 35000 then
                local _, checked = U.call(actor, "isOnBed")
                local navigation = SC.Navigation
                    and SC.Navigation.status(actor) or {}
                stop(H, result, setPhase, current, "arthur_native_bed_pose",
                    "isOnBed=" .. tostring(onBed)
                        .. " OnBedStarted=" .. tostring(bedStarted)
                        .. " callable=" .. tostring(checked)
                        .. " bedStatus=" .. tostring(nativeStatus)
                        .. " sittingOnFurniture=" .. tostring(furniture)
                        .. " seatedObject=" .. tostring(seatedObject)
                        .. " selectedBed=" .. tostring(bedObject)
                        .. " sitOnGround="
                        .. tostring(call(actor, "isSitOnGround"))
                        .. " actor=" .. tostring(x) .. "," .. tostring(y)
                        .. "," .. tostring(z)
                        .. " bed=" .. tostring(bed.x) .. ","
                        .. tostring(bed.y) .. "," .. tostring(bed.z)
                        .. nativeBedEntryDetail(SC, bedObject, bedSquare)
                        .. " update="
                        .. tostring(H.encounterLastUpdateReason)
                        .. " bridgeFailure=" .. tostring(bridgeFailure())
                        .. " nav=" .. tostring(navigation.phase)
                        .. "/" .. tostring(navigation.action)
                        .. "/" .. tostring(navigation.reason))
                return
            end
            if current - (H.encounterLastUpdate or 0) >= 500 then
                H.encounterLastUpdate = current
                local handled, reason = SC.OddballBedridden.update(actor,
                    H.player, nil,
                    { mode = "bedridden_arthur" }, H.encounterGroup)
                H.encounterLastUpdateReason = tostring(handled)
                    .. "/" .. tostring(reason)
            end
            return
        end
        if H.encounterNormalArrival and not H.encounterArrivalMoved then
            local playerSquare = U.squareOf(H.player)
            local unseen = playerSquare
                and call(playerSquare, "getRoom") == nil
                and call(bedSquare, "isCanSee", 0) ~= true
                and U.canSee(H.player, bedSquare) ~= true
            if not check("arthur_settled_before_arrival",
                unseen == true and story.nativeBedPoseStarted == true
                    and onBed and bedStarted and pillowAligned == true,
                "spawn_to_pose_ms=" .. tostring(current
                    - (H.encounterSpawnReadyAt or current))
                    .. " player_to_actor="
                    .. tostring(U.distance(H.player, actor))
                    .. " unseen=" .. tostring(unseen)
                    .. " actor=" .. tostring(x) .. "," .. tostring(y)
                    .. " anim=" .. tostring(call(actor,
                        "getVariableString", "OnBedAnim"))) then
                setPhase("finish", current) return
            end
            H.encounterArrivalMoved = true
            move(H.player, H.encounterObserveSquare)
            H.encounterLastObserverMove = current
            setPhase("encounter_arthur_arrival", current)
            return
        end
        local handled, reason = SC.OddballBedridden.update(actor,
            H.player, nil, { mode = "bedridden_arthur" }, H.encounterGroup)
        H.encounterLastUpdateReason = tostring(handled)
            .. "/" .. tostring(reason)
        result("PASS", "arthur_settled_native_orientation",
            arthurPoseDetail(actor, bedObject)
                .. " correction=" .. tostring(story.lieRecovery)
                .. " approach=" .. tostring(story.lieApproach)
                .. " transitionAt=" .. tostring(H.encounterFirstNativeLie)
                .. " settleReason=" .. tostring(reason))
        result("PASS", "arthur_bed_entry_geometry",
            nativeBedEntryDetail(SC, bedObject, bedSquare))
        if not check("arthur_native_bed_pose", true,
            "isOnBed=" .. tostring(onBed)
                .. " OnBedStarted=" .. tostring(bedStarted)
                .. " bedStatus=" .. tostring(nativeStatus)
                .. " sittingOnFurniture=" .. tostring(furniture)
                .. " selectedBed=" .. tostring(bedObject)
                .. " seatedObject=" .. tostring(seatedObject)
                .. " actor=" .. tostring(x) .. "," .. tostring(y)
                .. "," .. tostring(z)
                .. " selectedTile=" .. tostring(bed.x) .. ","
                .. tostring(bed.y) .. "," .. tostring(bed.z)
                .. " footprint=" .. tostring(lyingOnBed)
                .. " seatedTile=" .. tostring(call(U.squareOf(
                    seatedObject), "getX")) .. ","
                .. tostring(call(U.squareOf(seatedObject), "getY"))
                .. " alpha=" .. tostring(call(actor, "getAlpha", 0))
                .. " update=" .. H.encounterLastUpdateReason
                .. " owner=" .. tostring(call(actor,
                    "getCompanionMovementOwner"))
                .. " anim=" .. tostring(call(actor,
                    "getVariableString", "OnBedAnim"))
                .. " approach=" .. tostring(story.lieApproach)
                .. " fallback=" .. tostring(story.lieFallback)
                .. " fallbackReason=" .. tostring(story.lieFallbackReason)
                .. nativeBedEntryDetail(SC, bedObject, bedSquare)) then
            setPhase("finish", current) return
        end
        check("arthur_native_lying_pose", lyingOnBed,
            "onBed=" .. tostring(onBed)
                .. " started=" .. tostring(bedStarted)
                .. " physical_bed_tile=" .. tostring(lyingOnBed)
                .. " owner=" .. tostring(call(actor,
                    "getCompanionMovementOwner"))
                .. " anim=" .. tostring(call(actor,
                    "getVariableString", "OnBedAnim"))
                .. " furniture_fallback=" .. tostring(settledBedRest)
                .. " approach=" .. tostring(story.lieApproach)
                .. " fallback_reason=" .. tostring(story.lieFallbackReason))
        H.encounterBedObject = bedObject
        H.encounterBedSquare = bedSquare
        check("arthur_observer_enters_bedroom",
            playerAtObserver(SC, H.player, H.encounterObserveSquare,
                H.encounterObserveBedSquare))
        if H.config.oddball_scene_screenshot == "true" then
            local core = type(getCore) == "function" and getCore() or nil
            local zoom = tonumber(call(core, "getZoom", 0)) or 0
            if zoom > 0.5 then
                local steps = math.min(6,
                    math.ceil((zoom - 0.5) / 0.25))
                for _ = 1, steps do call(core, "doZoomScroll", 0, -1) end
            end
            H.encounterZoomBefore = zoom
            setPhase("encounter_arthur_zoom", current)
        else
            setPhase(H.config.oddball_pose_only == "true" and "finish"
                or "encounter_arthur_dialogue", current)
        end
        return
    end

    if H.phase == "encounter_arthur_arrival" then
        local placed, detail = playerAtObserver(SC, H.player,
            H.encounterObserveSquare, H.encounterObserveBedSquare)
        if placed then
            result("PASS", "arthur_normal_arrival_at_bedside", detail)
            setPhase("encounter_arthur_pose", current)
        elseif current - H.phaseStartedAt > 12000 then
            stop(H, result, setPhase, current,
                "arthur_normal_arrival_at_bedside", detail)
        elseif current - (H.encounterLastObserverMove or 0) >= 900 then
            move(H.player, H.encounterObserveSquare)
            H.encounterLastObserverMove = current
        end
        return
    end

    if H.phase == "encounter_arthur_zoom" then
        local placed, observerDetail = playerAtObserver(SC, H.player,
            H.encounterObserveSquare, H.encounterObserveBedSquare)
        if not placed then
            if current - H.phaseStartedAt > 12000 then
                stop(H, result, setPhase, current,
                    "arthur_capture_observer_in_bedroom", observerDetail)
                return
            end
            if current - (H.encounterLastObserverMove or 0) >= 900 then
                move(H.player, H.encounterObserveSquare)
                H.encounterLastObserverMove = current
            end
            return
        end
        if current - H.phaseStartedAt < 2500 then return end
        if IsoCamera then
            pcall(function() IsoCamera.SetCharacterToFollow(H.player) end)
        end
        local core = type(getCore) == "function" and getCore() or nil
        local zoom = call(core, "getZoom", 0)
        if not check("arthur_closeup_camera_ready", core ~= nil,
            "zoom_before=" .. tostring(H.encounterZoomBefore)
                .. " zoom_after=" .. tostring(zoom)
                .. " " .. observerDetail) then
            setPhase("finish", current) return
        end
        local signaled = H.encounterSignals.write(
            "SurvivorCompanionHarness/oddball-scene-ready.txt",
            { "ready=true", "kind=arthur" })
        if not check("arthur_capture_ready", signaled,
            "bed pose ready for native screenshot") then
            setPhase("finish", current) return
        end
        setPhase("encounter_arthur_capture", current)
        return
    end

    if H.phase == "encounter_arthur_capture" then
        if H.encounterSignals.exists(
            "SurvivorCompanionHarness/oddball-scene-captured.txt") then
            result("PASS", "arthur_live_capture", "native bed scene captured")
            setPhase(H.config.oddball_pose_only == "true"
                and "encounter_arthur_watch"
                or "encounter_arthur_dialogue", current)
        elseif current - H.phaseStartedAt > 15000 then
            stop(H, result, setPhase, current, "arthur_live_capture",
                "runner did not capture the ready scene")
        end
        return
    end

    if H.phase == "encounter_arthur_watch" then
        if H.encounterSignals.exists(
            "SurvivorCompanionHarness/oddball-scene-release.txt") then
            setPhase("finish", current)
        end
        return
    end

    if H.phase == "encounter_arthur_dialogue" then
        SC.Oddballs.pulseGroup(H.encounterGroup, H.player, current)
        local options = SC.Oddballs.menuOptions(H.encounterGroup, H.player)
        if not check("arthur_bedside_menu",
            hasOption(options, "ask_arthur")
                and hasOption(options, "stay_arthur")
                and hasOption(options, "mercy_arthur"),
            "all three bedside responses available") then
            setPhase("finish", current) return
        end
        local accepted, reason, lines = withSpeech(SC, function()
            return SC.Oddballs.storyAction(H.encounterGroup.id,
                "ask_arthur", H.player)
        end)
        if not check("arthur_native_bedside_dialogue",
            accepted == true and reason == "arthur_explained"
                and lineContains(lines, "The doctor called it")
                and H.encounterGroup.oddball.stage == "pleading"
                and (call(H.encounterActors[1], "isOnBed") == true
                    and call(H.encounterActors[1],
                        "getVariableBoolean", "OnBedStarted") == true
                    and actorOnBedFootprint(SC, H.encounterActors[1],
                        H.encounterBedSquare)
                    or SC.NativeActions.bedStatus(H.encounterActors[1])
                        == "entered"
                        and seatedOnSelectedBed(SC, H.encounterActors[1],
                            H.encounterBedObject, H.encounterBedSquare)),
            "action=" .. tostring(reason) .. " stage="
                .. tostring(H.encounterGroup.oddball.stage)
                .. " speech=" .. table.concat(lines, " | ")) then
            setPhase("finish", current) return
        end
        local waiting = waitingSquare(SC, H.encounterSite)
        if not check("arthur_observer_leaves_bedroom",
            move(H.player, waiting)
                and U.distance(H.player, H.encounterActors[1]) >= 8,
            "outside bedroom and at least eight tiles from Arthur") then
            setPhase("finish", current) return
        end
        setPhase("encounter_arthur_departure", current)
        return
    end

    if H.phase == "encounter_arthur_departure" then
        SC.Oddballs.pulseGroup(H.encounterGroup, H.player, current)
        local value = H.encounterGroup.oddball
        if value.stage ~= "left_alone" then
            if current - H.phaseStartedAt > 5000 then
                stop(H, result, setPhase, current,
                    "arthur_unattended_departure",
                    "stage=" .. tostring(value.stage)
                        .. " distance=" .. tostring(U.distance(
                            H.player, H.encounterActors[1])))
            end
            return
        end
        if not check("arthur_unattended_departure", true,
            "stage=left_alone; observer outside bedroom") then
            setPhase("finish", current) return
        end
        setPhase("encounter_arthur_death", current)
        return
    end

    if H.phase == "encounter_arthur_death" then
        local actor = H.encounterActors[1]
        local group = H.encounterGroup
        local value = group.oddball
        local dead = U.isDead(actor)
        local ready = call(actor, "isCorpseReady") == true
        local body = ready and call(actor, "getCompanionCorpse") or nil
        if dead and ready and body then
            H.encounterCorpse = body
            H.encounterFinalFloor = value.floorFallback == true
                and value.site.spawn or value.site.floor
            H.encounterRoom = call(U.gridSquare(value.site.spawn.x,
                value.site.spawn.y, value.site.spawn.z or 0), "getRoom")
            H.encounterReturnSquare = roomObserverSquare(SC,
                H.encounterSite, actor, 4)
                or U.gridSquare(value.site.spawn.x,
                    value.site.spawn.y, value.site.spawn.z or 0)
            if not check("arthur_native_death_and_corpse_ready",
                H.encounterReturnSquare ~= nil
                    and value.deathConfirmed == true
                    and value.stage == "died_alone"
                    and value.outcome == "died_alone",
                "stage=" .. tostring(value.stage)
                    .. " confirmed=" .. tostring(value.deathConfirmed)
                    .. " corpseReady=" .. tostring(ready)) then
                setPhase("finish", current) return
            end
            move(H.player, H.encounterReturnSquare)
            setPhase("encounter_arthur_return", current)
            return
        end
        if current - H.phaseStartedAt > 65000 then
            local x, y, z = U.position(actor)
            local navigation = SC.Navigation
                and SC.Navigation.status(actor) or {}
            stop(H, result, setPhase, current,
                "arthur_return_finds_native_floor_corpse",
                "stage=" .. tostring(value.stage)
                    .. " dead=" .. tostring(dead)
                    .. " corpseReady=" .. tostring(ready)
                    .. " body=" .. tostring(body)
                    .. " update=" .. tostring(H.encounterLastUpdateReason)
                    .. " onBed=" .. tostring(call(actor, "isOnBed"))
                    .. " OnBedStarted=" .. tostring(call(actor,
                        "getVariableBoolean", "OnBedStarted"))
                    .. " bedStatus=" .. tostring(SC.NativeActions.bedStatus(
                        actor))
                    .. " actor=" .. tostring(x) .. "," .. tostring(y)
                    .. "," .. tostring(z)
                    .. " floor=" .. tostring(value.site and value.site.floor
                        and value.site.floor.x) .. ","
                        .. tostring(value.site and value.site.floor
                        and value.site.floor.y)
                    .. " spawn=" .. tostring(value.site and value.site.spawn
                        and value.site.spawn.x) .. ","
                        .. tostring(value.site and value.site.spawn
                        and value.site.spawn.y)
                    .. " owner=" .. tostring(call(actor,
                        "getCompanionMovementOwner"))
                    .. " collidable=" .. tostring(call(actor,
                        "isCollidable"))
                    .. " exitRequested=" .. tostring(value.nativeBedExitRequested)
                    .. " floorFallback=" .. tostring(value.floorFallback)
                    .. " room=" .. tostring(roomName(call(actor,
                        "getSquare")))
                    .. " nav=" .. tostring(navigation.phase)
                    .. "/" .. tostring(navigation.action)
                    .. "/" .. tostring(navigation.reason))
            return
        end
        SC.Oddballs.pulseGroup(group, H.player, current)
        if not dead and value.deathConfirmed ~= true
            and current - (H.encounterLastUpdate or 0) >= 500 then
            H.encounterLastUpdate = current
            local handled, reason = SC.OddballBedridden.update(actor,
                H.player, nil, { mode = "bedridden_arthur" }, group)
            H.encounterLastUpdateReason = tostring(handled)
                .. "/" .. tostring(reason)
            if reason == "arthur_stepped_clear_of_bed"
                and not H.encounterBedExitLogged then
                H.encounterBedExitLogged = true
                local x, y, z = U.position(actor)
                result("PASS", "arthur_stepped_clear_of_bed",
                    "actor=" .. tostring(x) .. "," .. tostring(y)
                        .. "," .. tostring(z)
                        .. " collidable=" .. tostring(call(actor,
                            "isCollidable"))
                        .. " owner=" .. tostring(call(actor,
                            "getCompanionMovementOwner")))
            end
        end
        return
    end

    if H.phase == "encounter_arthur_return" then
        local playerSquare = call(H.player, "getSquare")
        local returned = call(playerSquare, "getRoom") == H.encounterRoom
        if not returned and current - H.phaseStartedAt < 5000 then
            if current - (H.encounterLastReturnMove or 0) >= 1000 then
                H.encounterLastReturnMove = current
                move(H.player, H.encounterReturnSquare)
            end
            return
        end
        local value = H.encounterGroup.oddball
        local floor = H.encounterFinalFloor
        local square = call(H.encounterCorpse, "getSquare")
        local objects = call(square, "getStaticMovingObjects")
        local native = objects
            and call(objects, "contains", H.encounterCorpse) == true
        -- The native fall animation may settle the corpse one square from
        -- the clear floor post where its fatal injury was applied.
        local onBedroomFloor = square and floor
            and math.abs((call(square, "getX") or -999) - floor.x) <= 1
            and math.abs((call(square, "getY") or -999) - floor.y) <= 1
            and call(square, "getZ") == (floor.z or 0)
            and call(square, "getRoom") == H.encounterRoom
        check("arthur_return_finds_native_floor_corpse",
            returned and native and onBedroomFloor,
            "returned=" .. tostring(returned)
                .. " native=" .. tostring(native)
                .. " bedroom_floor=" .. tostring(onBedroomFloor)
                .. " corpse=" .. tostring(call(square, "getX"))
                .. "," .. tostring(call(square, "getY"))
                .. " injury_post=" .. tostring(floor and floor.x)
                .. "," .. tostring(floor and floor.y)
                .. " stage=" .. tostring(value.stage))
        setPhase("finish", current)
        return
    end

    if H.phase == "encounter_pack_costumes" then
        local allDressed, allUnarmed, detail = true, true, {}
        for index, actor in ipairs(H.encounterActors) do
            local worn, primary, secondary = costumeState(SC, actor)
            allDressed = allDressed and worn == #COSTUME
            allUnarmed = allUnarmed and primary == nil and secondary == nil
            detail[#detail + 1] = tostring(index) .. ":" .. tostring(worn)
                .. "/" .. tostring(primary)
                .. "/" .. tostring(secondary)
        end
        if not check("pack_four_native_costumes", allDressed,
            table.concat(detail, ","))
            or not check("pack_shivs_hidden_before_reveal", allUnarmed,
                "all four native hands empty") then
            setPhase("finish", current) return
        end
        local square = roomObserverSquare(SC, H.encounterSite,
            H.encounterActors[1], 2)
        beginPackSpeech(H, SC)
        if not check("pack_observer_enters_den", move(H.player, square),
            "same native room within reveal range") then
            endPackSpeech(H, SC)
            setPhase("finish", current) return
        end
        if H.config.oddball_scene_screenshot == "true" then
            local signaled = H.encounterSignals.write(
                "SurvivorCompanionHarness/oddball-scene-ready.txt",
                { "ready=true", "kind=pack" })
            if not check("pack_capture_ready", signaled,
                "four native costumes ready for screenshot") then
                endPackSpeech(H, SC)
                setPhase("finish", current) return
            end
            setPhase("encounter_pack_capture", current)
        else
            setPhase("encounter_pack_dialogue", current)
        end
        return
    end

    if H.phase == "encounter_pack_capture" then
        if H.encounterSignals.exists(
            "SurvivorCompanionHarness/oddball-scene-captured.txt") then
            result("PASS", "pack_live_capture",
                "four native costumes captured before reveal")
            setPhase("encounter_pack_dialogue", current)
        elseif current - H.phaseStartedAt > 15000 then
            stop(H, result, setPhase, current, "pack_live_capture",
                "runner did not capture the ready scene")
        end
        return
    end

    if H.phase == "encounter_pack_dialogue" then
        local group = H.encounterGroup
        withSpeech(SC, function()
            return SC.Oddballs.pulseGroup(group, H.player, current)
        end)
        local options = SC.Oddballs.menuOptions(group, H.player)
        if not check("pack_lures_guest",
            group.oddball.stage == "luring"
                and tonumber(group.oddball.invitedAt) ~= nil
                and (lineContains(H.encounterSpeech, "den")
                    or lineContains(H.encounterSpeech, "kingdom")
                    or lineContains(H.encounterSpeech, "adventure"))
                and hasOption(options, "ask_costumes")
                and hasOption(options, "join_game"),
            "stage=" .. tostring(group.oddball.stage)
                .. " invitation="
                .. table.concat(H.encounterSpeech or {}, " | ")) then
            endPackSpeech(H, SC)
            setPhase("finish", current) return
        end
        local accepted, reason, lines = withSpeech(SC, function()
            return SC.Oddballs.storyAction(group.id, "ask_costumes",
                H.player)
        end)
        if not check("pack_costume_dialogue",
            accepted == true and reason == "costumes_explained"
                and lineContains(lines, "costume show"),
            "action=" .. tostring(reason)
                .. " speech=" .. table.concat(lines, " | ")) then
            endPackSpeech(H, SC)
            setPhase("finish", current) return
        end
        setPhase("encounter_pack_reveal", current)
        return
    end

    if H.phase == "encounter_pack_reveal" then
        local group = H.encounterGroup
        if current - (H.encounterLastPackPulseAt or 0) >= 500 then
            H.encounterLastPackPulseAt = current
            local accepted, reason = withSpeech(SC, function()
                return SC.Oddballs.pulseGroup(group, H.player, current)
            end)
            H.encounterLastPackPulse = tostring(accepted)
                .. "/" .. tostring(reason)
        end
        if group.oddball.stage ~= "hostile" then
            if current - H.phaseStartedAt > 16000 then
                stop(H, result, setPhase, current,
                    "pack_den_entry_reveal_timeout",
                    "stage=" .. tostring(group.oddball.stage)
                        .. " pulse=" .. tostring(H.encounterLastPackPulse)
                        .. " speech="
                        .. table.concat(H.encounterSpeech or {}, " | "))
            end
            return
        end
        local armed, costumeStillWorn = 0, true
        for _, actor in ipairs(H.encounterActors) do
            local worn, primary = costumeState(SC, actor)
            costumeStillWorn = costumeStillWorn and worn == #COSTUME
            if primary == "Base.KnifeShiv" then armed = armed + 1 end
        end
        local revealed = check("pack_native_reveal_and_shivs",
            group.oddball.stage == "hostile"
                and group.oddball.revealReason == "guest_entered_den"
                and group.standing == "Hostile"
                and armed == 4 and costumeStillWorn
                and (lineContains(H.encounterSpeech, "Shivs out")
                    or lineContains(H.encounterSpeech, "Get the knives")
                    or lineContains(H.encounterSpeech,
                        "guest doesn't leave")),
            "stage=" .. tostring(group.oddball.stage)
                .. " standing=" .. tostring(group.standing)
                .. " armed=" .. tostring(armed)
                .. " pulse=" .. tostring(H.encounterLastPackPulse)
                .. " speech="
                .. table.concat(H.encounterSpeech or {}, " | "))
        endPackSpeech(H, SC)
        if revealed then
            pcall(function() H.player:setInvisible(false) end)
            local leader = H.encounterActors[1]
            local px, py = U.position(H.player)
            if px and py then call(leader, "faceLocationF", px, py) end
            local intent = SC.Oddballs.intentFor(leader, H.player,
                { threats = {}, threatCount = 0 }, group)
            local target = SC.Factions.hostileTargetFor(leader, H.player)
            check("pack_hostile_player_target",
                intent and intent.mode == "hostile"
                    and SC.Factions.isHostileBetween(leader, H.player,
                        H.player) == true
                    and target and target.actor == H.player,
                "intent=" .. tostring(intent and intent.mode)
                    .. " target=" .. tostring(target and target.actor)
                    .. " player=" .. tostring(H.player))
        end
        setPhase("finish", current)
    end
end

return Probe
