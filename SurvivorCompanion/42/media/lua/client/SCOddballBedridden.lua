-- SPDX-License-Identifier: MIT
-- Arthur stays in a real bedroom bed. The player can answer his request for
-- mercy, or leave him after meeting him; in the latter case his native body
-- moves to a clear bedroom floor tile before its final injury is applied.
local SC = SurvivorCompanion
SC.OddballBedridden = SC.OddballBedridden or {}
local Bedridden = SC.OddballBedridden

local ID = "bedridden_arthur_hale"
local COUGH_MIN_MS = 48000
local COUGH_SPREAD_MS = 32000
-- Includes the walk to the chosen entry and the game's full bed animation.
-- Tight bedrooms can require a slow turn before OnBedStarted becomes true.
local LIE_TIMEOUT_MS = 45000
local LIE_MAX_ATTEMPTS = 2
local lieEntries = setmetatable({}, { __mode = "k" })
local renderLiftApplied = setmetatable({}, { __mode = "k" })
local PLEAS = {
    "Close the door, please. Every draft finds the place that hurts.",
    "I have had enough mornings like this. Please, let this be the last one.",
    "I am asking you plainly. End it while I still know your face.",
    "Evelyn used to sit there and read the weather to me. I can barely hear the rain now.",
    "If you cannot do it, I understand. Just do not promise to come back.",
}
local COUGH_LINES = {
    "Sorry. It takes the words clean out of me.",
    "It is not the cold. I wish it were something so simple.",
    "Those pills bought me a week. The week has gone.",
    "Listen to that chest. Sounds like gravel in a tin pail.",
}
local function U() return SC.GameplayUtil end
local function coughMode()
    local options = SC.UserOptions
    if type(options) ~= "table" or type(options.get) ~= "function" then
        return "normal"
    end
    local okay, mode = pcall(options.get, "coughSneezes")
    return okay and (mode == "rare" or mode == "off") and mode
        or "normal"
end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    return type(value) == "table" and value.id == ID and value or nil
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function bedroom(value)
    local post = value and value.site and value.site.spawn
    local tile = post and U().gridSquare(post.x, post.y, post.z or 0)
    return tile and select(1, U().call(tile, "getRoom")) or nil
end
local function playerInBedroom(value, player)
    local room = bedroom(value)
    local tile = player and U().squareOf(player)
    return room ~= nil and tile ~= nil
        and select(1, U().call(tile, "getRoom")) == room
end
local function isBedObject(candidate)
    if not candidate then return false end
    local label = select(1, U().call(candidate, "getName"))
    local sprite = select(1, U().call(candidate, "getSprite"))
    local spriteName = sprite and select(1, U().call(sprite, "getName"))
    label = string.lower(tostring(label or ""))
    spriteName = string.lower(tostring(spriteName or ""))
    return (string.find(label, "bed", 1, true) ~= nil
            and string.find(label, "bedside", 1, true) == nil)
        or string.find(spriteName, "furniture_bedding", 1, true) ~= nil
end
local function bedObject(value)
    local post = value and value.site and value.site.bed
    local tile = post and U().gridSquare(post.x, post.y, post.z or 0)
    local objects = tile and select(1, U().call(tile, "getObjects"))
    local object = objects and SC.NativeList
        and SC.NativeList.get(objects, post.objectIndex)
    if not isBedObject(object) and objects and SC.NativeList then
        for index = 0, SC.NativeList.size(objects) - 1 do
            local candidate = SC.NativeList.get(objects, index)
            if isBedObject(candidate) then
                object = candidate
                post.objectIndex = index
                break
            end
        end
    end
    if not isBedObject(object) then return nil, tile end
    return object, tile
end
local function sameBedSegment(selected, selectedTile,
        candidate, candidateTile)
    if not selected or not selectedTile or not candidate
        or not candidateTile or not isBedObject(candidate) then return false end
    if selected == candidate then return true end
    local sx, sy, sz = U().position(selectedTile)
    local cx, cy, cz = U().position(candidateTile)
    local dx, dy = cx - sx, cy - sy
    -- A double bed is a 2x2 sprite grid. The selected object can sit
    -- diagonally across from the actor's native anchor after entering.
    if math.abs(dx) > 1 or math.abs(dy) > 1 or cz ~= sz then return false end
    local selectedSprite = select(1, U().call(selected, "getSprite"))
    local candidateSprite = select(1, U().call(candidate, "getSprite"))
    local selectedGrid = selectedSprite and select(1,
        U().call(selectedSprite, "getSpriteGrid"))
    local candidateGrid = candidateSprite and select(1,
        U().call(candidateSprite, "getSpriteGrid"))
    if not selectedGrid or selectedGrid ~= candidateGrid then return false end
    local sgx = select(1, U().call(selectedGrid,
        "getSpriteGridPosX", selectedSprite))
    local sgy = select(1, U().call(selectedGrid,
        "getSpriteGridPosY", selectedSprite))
    local cgx = select(1, U().call(candidateGrid,
        "getSpriteGridPosX", candidateSprite))
    local cgy = select(1, U().call(candidateGrid,
        "getSpriteGridPosY", candidateSprite))
    return type(sgx) == "number" and type(sgy) == "number"
        and type(cgx) == "number" and type(cgy) == "number"
        and cgx - sgx == dx and cgy - sgy == dy
end
local function sameBedAt(value, tile)
    local selected, selectedTile = bedObject(value)
    if not tile or not selectedTile
        or select(1, U().call(tile, "getRoom")) ~= bedroom(value) then
        return false
    end
    local objects = select(1, U().call(tile, "getObjects"))
    if not objects or not SC.NativeList then return false end
    for index = 0, SC.NativeList.size(objects) - 1 do
        local candidate = SC.NativeList.get(objects, index)
        if sameBedSegment(selected, selectedTile, candidate, tile) then
            return true, candidate
        end
    end
    return false
end
local function onBedFootprint(actor, value)
    -- The native flag can be raised while the entry animation still has the
    -- actor beside the mattress. Require its physical square to be a segment
    -- of Arthur's selected bed, including a diagonal double-bed segment.
    local ax, ay, az = U().position(actor)
    if ax == nil or ay == nil then return false end
    local actorTile = U().gridSquare(math.floor(ax), math.floor(ay),
        math.floor(az or 0))
    local _, selectedTile = bedObject(value)
    return actorTile and selectedTile
        and U().distance(actorTile, selectedTile) <= 1.5
        and sameBedAt(value, actorTile) or false
end
local BODY_STEP = { N = { 0, -1 }, S = { 0, 1 },
    E = { 1, 0 }, W = { -1, 0 } }
local function gridNumber(value)
    if type(value) == "number" then return value end
    return value ~= nil and tonumber(tostring(value)) or nil
end
local function onBedLengthSupported(actor, value)
    if not onBedFootprint(actor, value) then return false end
    -- A two-tile body must remain on the same sprite grid in the direction
    -- the native on-bed action actually faced. A bed flag on one square alone
    -- also occurs for the bad poses beside a wall or along a double-bed edge.
    local direction = tostring(select(1, U().call(actor, "getDir")) or "")
    local step = BODY_STEP[direction]
    if not step then return false end
    local ax, ay, az = U().position(actor)
    local x, y, z = math.floor(ax), math.floor(ay), math.floor(az or 0)
    local anchor = U().gridSquare(x, y, z)
    local nextTile = U().gridSquare(x + step[1], y + step[2], z)
    local supported, segment = sameBedAt(value, anchor)
    if not supported or not sameBedAt(value, nextTile) then return false end
    local sprite = select(1, U().call(segment, "getSprite"))
    local grid = sprite and select(1, U().call(sprite, "getSpriteGrid"))
    if not grid then return false end
    local properties = select(1, U().call(segment, "getProperties"))
        or select(1, U().call(sprite, "getProperties"))
    local facing = tostring(select(1,
        U().call(properties, "get", "Facing")) or "")
    if BODY_STEP[facing] and facing ~= direction then return false end
    local width = gridNumber(select(1, U().call(grid, "getWidth")))
    local height = gridNumber(select(1, U().call(grid, "getHeight")))
    local gx = gridNumber(select(1,
        U().call(grid, "getSpriteGridPosX", sprite)))
    local gy = gridNumber(select(1,
        U().call(grid, "getSpriteGridPosY", sprite)))
    if not width or not height or not gx or not gy then return false end
    width, height = math.floor(width), math.floor(height)
    if width < 1 or height < 1 or width * height > 16
        or gx < 0 or gx >= width or gy < 0 or gy >= height then
        return false
    end
    if gx + step[1] < 0 or gx + step[1] >= width
        or gy + step[2] < 0 or gy + step[2] >= height then
        return false
    end
    -- A 2x2 bed has width neighbors too. Its Facing property determines the
    -- length axis; accepting either width row would sleep sideways. A modded
    -- grid with no Facing can only be inferred when one dimension is one.
    if not BODY_STEP[facing] then
        if width > 1 and height > 1 then return false end
        if width > height and step[1] == 0 then return false end
        if height > width and step[2] == 0 then return false end
    end
    for offsetX = 0, width - 1 do
        for offsetY = 0, height - 1 do
            local square = U().gridSquare(x - gx + offsetX,
                y - gy + offsetY, z)
            if not sameBedAt(value, square) then return false end
        end
    end
    return true
end
local function bedPose(actor, value)
    local status = SC.NativeActions
        and type(SC.NativeActions.bedStatus) == "function"
        and select(1, SC.NativeActions.bedStatus(actor)) or "none"
    local onBed = select(1, U().call(actor, "isOnBed")) == true
    if onBed then
        local started = select(1, U().call(actor,
            "getVariableBoolean", "OnBedStarted")) == true
        return started and onBedLengthSupported(actor, value)
            and "entered" or "entering"
    end
    local ground = select(1, U().call(actor, "isSitOnGround")) == true
    local seated = select(1, U().call(actor,
        "isSittingOnFurniture")) == true
    if seated then
        -- ISRestAction is an upright furniture seat, including on a bed.
        -- Arthur must use PlayerOnBedState's actual lying pose.
        return "failed"
    end
    if status == "entering" then return "entering" end
    if ground or status == "failed" then return "failed" end
    return "none"
end
local function nativeQueue(actor)
    local queues = ISTimedActionQueue
    if type(queues) ~= "table"
        or type(queues.getTimedActionQueue) ~= "function" then return nil end
    local okay, queue = pcall(queues.getTimedActionQueue, actor)
    return okay and type(queue) == "table" and queue or nil
end
local function cancelLie(actor)
    local entry = lieEntries[actor]
    lieEntries[actor] = nil
    if not entry then return false end
    local queue = entry.queue
    if queue and type(queue.queue) == "table" then
        local owned = queue.current == entry.pathAction
            or queue.current == entry.bedAction
        for _, action in ipairs(queue.queue) do
            if action == entry.pathAction or action == entry.bedAction then
                owned = true
                break
            end
        end
        if owned then
            if queue.current and type(queue.current.forceCancel) == "function" then
                pcall(queue.current.forceCancel, queue.current)
            end
            if type(queue.resetQueue) == "function" then
                pcall(queue.resetQueue, queue)
            end
        end
    end
    return true
end
local function alignedEntry(bed, actor)
    local resolver = SC.Oddballs and SC.Oddballs.nativeBedFootEntry
    if type(resolver) ~= "function" then
        return nil, nil, "native_bed_entry_resolver_unavailable"
    end
    local normalized, point, reason = resolver(bed, actor)
    if not normalized or not point then
        return nil, nil, reason or "native_bed_entry_blocked"
    end
    return normalized, { point.x, point.y, point.z or 0,
        pillow = point.pillow },
        point.entryKind or "native"
end

local function pillowLieSupported(actor, value, pillow)
    if not pillow then return true end
    local ax, ay, az = U().position(actor)
    if not ax or math.floor(ax) ~= pillow.x
        or math.floor(ay) ~= pillow.y
        or math.floor(az or 0) ~= pillow.z then return false end
    local selected, selectedTile = bedObject(value)
    if not selected or not selectedTile then return false end
    for _, y in ipairs({ pillow.y, pillow.y + 1 }) do
        local tile = U().gridSquare(pillow.x, y, pillow.z)
        if not tile or select(1, U().call(tile, "getRoom"))
            ~= bedroom(value) then return false end
        local objects = select(1, U().call(tile, "getObjects"))
        local found = false
        for index = 0, (objects and SC.NativeList
                and SC.NativeList.size(objects) or 0) - 1 do
            if sameBedSegment(selected, selectedTile,
                    SC.NativeList.get(objects, index), tile) then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return true
end

local function applyBedRenderLift(actor)
    if renderLiftApplied[actor] == true then return true end
    if not SCBridge then return false end
    local called, applied = pcall(function()
        return SCBridge.setOnBedRenderLift(actor, 180)
    end)
    if not called or applied ~= true then return false end
    renderLiftApplied[actor] = true
    return true
end

local function clearBedRenderLift(actor)
    if renderLiftApplied[actor] ~= true then return end
    renderLiftApplied[actor] = nil
    if SCBridge then pcall(function()
        return SCBridge.setOnBedRenderLift(actor, 0)
    end) end
end

local function prepareBedAction(action, entry)
    if not action or type(action.waitToStart) ~= "function" then
        return false
    end
    local stockWait = action.waitToStart
    action.waitToStart = function(self)
        local x, y, z = U().position(self.character)
        if x == nil or math.floor(z or 0) ~= math.floor(entry[3])
            or math.abs(x - entry[1]) > 0.45
            or math.abs(y - entry[2]) > 0.45 then
            return true
        end
        return stockWait(self)
    end
    return true
end
local function startLie(actor, bed)
    -- Resolve the same bed segment and approach used by the game's Get On
    -- Bed menu, then queue its path action and untouched bed action.
    if type(ISGetOnBedAction) ~= "table" then
        pcall(require, "TimedActions/ISGetOnBedAction")
    end
    if type(ISPathFindAction) ~= "table" then
        pcall(require, "Vehicles/TimedActions/ISPathFindAction")
    end
    if type(ISGetOnBedAction) ~= "table" then
        return false, "native_get_on_bed_unavailable"
    end
    local sprite = select(1, U().call(bed, "getSprite"))
    if not sprite or not select(1, U().call(sprite, "getSpriteGrid")) then
        return false, "bed_has_no_native_lie_pose"
    end
    -- The vanilla OnBed animation graph only renders its awake/asleep body
    -- when OnBedAnim has one of those values. Without it the actor can have
    -- isOnBed=true while the mattress appears empty.
    local _, animationSet = U().call(actor, "setVariable", "OnBedAnim", "Awake")
    if not animationSet then return false, "native_bed_anim_unavailable" end
    local queue = nativeQueue(actor)
    if not queue then return false, "native_bed_queue_unavailable" end
    if queue.current ~= nil or type(queue.queue) ~= "table"
        or #queue.queue > 0 then return false, "native_bed_queue_busy" end
    -- A precise entry prevents pathToNearest from stopping beside a blocked
    -- bed; the stock action retains full control of turning and root motion.
    local entryBed, entry, entryKind = alignedEntry(bed, actor)
    if not entryBed then
        return false, entryKind or "native_bed_entry_blocked", "native"
    end
    local okay = false
    local approach = entryKind
    if type(ISPathFindAction) == "table"
        and type(ISPathFindAction.pathToLocationF) == "function"
        and type(ISTimedActionQueue.add) == "function"
        and type(ISGetOnBedAction.new) == "function" then
        -- LocationF makes Arthur walk to the selected native entry himself.
        local pathOk, path = pcall(ISPathFindAction.pathToLocationF,
            ISPathFindAction, actor, entry[1], entry[2], entry[3])
        local bedOk, bedAction = pcall(ISGetOnBedAction.new,
            ISGetOnBedAction, actor, entryBed)
        if pathOk and path and bedOk and bedAction
            and prepareBedAction(bedAction, entry) then
            local addedPath = pcall(ISTimedActionQueue.add, path)
            local addedBed = addedPath
                and pcall(ISTimedActionQueue.add, bedAction)
            okay = addedPath and addedBed
        end
    end
    if not okay or #queue.queue < 2 then
        -- The queue was empty before our call, so any partial action belongs
        -- to this failed entry request.
        if #queue.queue > 0 and type(queue.resetQueue) == "function" then
            pcall(queue.resetQueue, queue)
        end
        return false, "native_get_on_bed_not_queued", approach
    end
    lieEntries[actor] = { queue = queue,
        pathAction = queue.queue[1], bedAction = queue.queue[#queue.queue],
        startedAt = U().nowMs(), pillow = entry.pillow }
    return true, "arthur_getting_on_bed", approach,
        entry.pillow ~= nil
end
local function floorSquare(value)
    local post = value and value.site
        and (value.floorFallback == true and value.site.spawn
            or value.site.floor)
    local tile = post and U().gridSquare(post.x, post.y, post.z or 0)
    if tile and select(1, U().call(tile, "getRoom")) == bedroom(value) then
        return tile
    end
    return nil
end
local function correctFailedLiePosition(actor, value)
    if value.lieRecovery ~= true then return false, "no_failed_lie" end
    clearBedRenderLift(actor)
    local ax, ay, az = U().position(actor)
    local physical = ax and ay and U().gridSquare(math.floor(ax),
        math.floor(ay), math.floor(az or 0)) or nil
    if physical and select(1, U().call(physical, "getRoom"))
        == bedroom(value) then return false, "already_in_bedroom" end
    if not SC.Actor or type(SC.Actor.recover) ~= "function" then
        return false, "native_recovery_unavailable"
    end
    if (tonumber(value.lieCorrectionAttempts) or 0) >= 3 then
        return false, "native_recovery_exhausted"
    end
    value.lieCorrectionAttempts =
        (tonumber(value.lieCorrectionAttempts) or 0) + 1
    for _, post in ipairs({ value.site and value.site.spawn,
            value.site and value.site.floor }) do
        local tile = post and U().gridSquare(post.x, post.y, post.z or 0)
        if tile and select(1, U().call(tile, "getRoom")) == bedroom(value)
            and type(U().isClearActorSpawnSquare) == "function"
            and U().isClearActorSpawnSquare(tile)
            and (ax == nil or U().distance(actor, tile) <= 5) then
            local recovered = SC.Actor.recover(actor, tile)
            if recovered == true then
                value.lieRecovery = nil
                value.lieCorrected = true
                return true, "arthur_recovered_failed_bed_entry"
            end
        end
    end
    return false, "native_recovery_failed"
end
local function leaveArthurBed(actor, value)
    clearBedRenderLift(actor)
    if select(1, U().call(actor, "isOnBed")) == true then
        -- Keep the native on-bed state until its own from-bed clip ends.
        -- Generic furniture cleanup clears isOnBed before that transition.
        local _, requested = U().call(actor, "setVariable",
            "forceGetUp", true)
        if requested then
            value.nativeBedExitRequested = true
            value.nativeBedPoseStarted = true
        end
        return requested, requested and "arthur_getting_out_of_bed"
            or "arthur_native_bed_exit_refused"
    end
    if not SC.NativeActions
        or type(SC.NativeActions.leaveSeating) ~= "function" then
        return false, "arthur_bed_exit_unavailable"
    end
    return SC.NativeActions.leaveSeating(actor)
end
local function finishArthurBedExit(actor, value)
    if value.nativeBedExitRequested ~= true then return true end
    local owner = select(1,
        U().call(actor, "getCompanionMovementOwner"))
    if select(1, U().call(actor, "isOnBed")) == true
        or owner == "seating" or owner == "reaction" then
        return false, "arthur_finishing_bed_exit"
    end
    -- PlayerOnBedState disables collision. The non-local bridge omits the
    -- normal local-player update which would restore it after getting up.
    local _, restored = U().call(actor, "setCollidable", true)
    if not restored then return false, "arthur_collision_restore_failed" end
    local collidable, readable = U().call(actor, "isCollidable")
    if readable and collidable ~= true then
        return false, "arthur_collision_restore_unverified"
    end
    value.nativeBedExitRequested = nil
    value.nativeBedPoseStarted = nil
    value.bedPoseNeedsLift = nil
    value.nativeBedExited = true
    return true
end
local function stepOffBedAfterGetUp(actor, value, player)
    if value.nativeBedExited ~= true then
        return false, "no_bed_exit_recovery"
    end
    local ax, ay, az = U().position(actor)
    local physical = ax and ay and U().gridSquare(math.floor(ax),
        math.floor(ay), math.floor(az or 0)) or nil
    local currentRoom = bedroom(value)
    local physicalRoom = physical and select(1,
        U().call(physical, "getRoom")) or nil
    if physicalRoom == currentRoom and not onBedFootprint(actor, value) then
        value.nativeBedExited = nil
        return false, "no_bed_exit_recovery"
    end
    -- Get Up can complete without displacing a non-local companion off the
    -- occupied mattress, or can move the actor into the adjacent wall tile.
    -- Navigation cannot start from either tile.
    -- The player has already left this room; place Arthur once on the clear
    -- floor post selected when the encounter was created.
    if playerInBedroom(value, player) then
        return false, "arthur_waiting_for_private_bed_exit"
    end
    if not SC.Actor or type(SC.Actor.recover) ~= "function" then
        return false, "arthur_bed_exit_recovery_unavailable"
    end
    if (tonumber(value.bedExitRecoveryAttempts) or 0) >= 3 then
        return false, "arthur_bed_exit_recovery_exhausted"
    end
    value.bedExitRecoveryAttempts =
        (tonumber(value.bedExitRecoveryAttempts) or 0) + 1
    for _, post in ipairs({ value.site and value.site.floor,
            value.site and value.site.spawn }) do
        local tile = post and U().gridSquare(post.x, post.y, post.z or 0)
        if tile and select(1, U().call(tile, "getRoom")) == currentRoom
            and type(U().isClearActorSpawnSquare) == "function"
            and U().isClearActorSpawnSquare(tile)
            and U().distance(actor, tile) <= 5 then
            local moved = SC.Actor.recover(actor, tile)
            if moved == true then
                local ax, ay, az = U().position(actor)
                local tx, ty, tz = U().position(tile)
                if math.floor(ax) == math.floor(tx)
                    and math.floor(ay) == math.floor(ty)
                    and math.floor(az or 0) == math.floor(tz or 0) then
                    value.nativeBedExited = nil
                    return true, "arthur_stepped_clear_of_bed"
                end
                return false, "arthur_bed_exit_recovery_unverified"
            end
        end
    end
    return false, "arthur_bed_exit_clear_floor_unavailable"
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor ~= nil and player ~= nil
        and U().distance(actor, player) <= radius
end
local function sayNext(actor, value, list, key)
    local index = ((tonumber(value[key]) or 0) % #list) + 1
    value[key] = index
    return U().say(actor, list[index])
end
local function syncShelter(actor, wanted)
    if not actor or not SC.Oddballs
        or type(SC.Oddballs.setZombieShelter) ~= "function" then
        return false
    end
    local actual, readable = U().call(actor, "isZombiesDontAttack")
    if readable and actual == wanted then return true end
    return SC.Oddballs.setZombieShelter(actor, wanted) == true
end
local function confirmDeath(group, actor, nativeConfirmed)
    local value = story(group)
    if not value or not actor or not (nativeConfirmed or U().isDead(actor)) then
        return false
    end
    if value.deathConfirmed ~= true then
        clearBedRenderLift(actor)
        value.deathConfirmed = true
        value.stage = "dead"
        syncShelter(actor, false)
        if SC.Oddballs and type(SC.Oddballs.retire) == "function" then
            SC.Oddballs.retire(group, value.outcome == "mercy"
                and "mercy_granted" or "died_alone")
        end
    end
    return true
end
local function seedLetter(group, actor)
    local value = story(group)
    if value.letterSeeded == true then return true end
    local inventory = U().inventory(actor)
    if not inventory then return false end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 120, 6)) do
        local data = U().modData(item)
        if data and data.lfArthurLetterGroupId == group.id then
            value.letterSeeded = true
            return true
        end
    end
    local letter = U().addItem(inventory, "Base.LetterHandwritten")
    if not letter then return false end
    U().call(letter, "setName", "Arthur's unsent letter to Evelyn")
    local data = U().modData(letter)
    if data then data.lfArthurLetterGroupId = group.id end
    value.letterSeeded = true
    return true
end

function Bedridden.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "arthur_unavailable" end
    if not bedObject(value) or not floorSquare(value) or not bedroom(value) then
        return false, "arthur_bedroom_unavailable"
    end
    if value.stage == nil or value.stage == "unmet" then
        value.stage = "waiting"
    end
    value.actorId = U().idOf(actor)
        or group.members and group.members[1] and group.members[1].actorId
    if value.nextCoughAt == nil then
        value.nextCoughAt = U().nowMs()
            + (coughMode() == "rare" and 300000 or 30000)
    end
    seedLetter(group, actor)
    -- The openings may be released once the player reaches the room, but
    -- Arthur cannot defend himself. Keep zombies off him until native death
    -- confirms his authored ending on the bedroom floor.
    syncShelter(actor, value.deathConfirmed ~= true
        and not U().isDead(actor))
    return true, "arthur_in_bedroom"
end

function Bedridden.onKeeperDeath(actor, group)
    local value = story(group)
    local id = actor and U().idOf(actor)
    if not value or id == nil or value.actorId ~= id then
        return false, "not_arthur"
    end
    return confirmDeath(group, actor, true), "arthur_native_death_confirmed"
end

function Bedridden.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.deathConfirmed == true then return true, "arthur_dead" end
    local actor = actorFor(group)
    if not actor then
        return true, value.stage == "dying" and "arthur_death_pending"
            or "arthur_unloaded"
    end
    current = tonumber(current) or U().nowMs()
    if confirmDeath(group, actor) then return true, "arthur_dead" end
    if value.deathConfirmed == true or value.stage == "dying" then
        return true, value.stage
    end
    local inRoom = playerInBedroom(value, player)
    local close = inRoom and near(group, player, 6)
    if value.stage == "waiting" and close then
        value.stage = "pleading"
        group.discovered = true
        U().say(actor,
            "I am Arthur Hale. The pain will not stop. Please, give me a kind ending.")
        value.nextPleaAt = current + 22000
    elseif value.stage == "pleading" and not inRoom
        and (player == nil or U().distance(actor, player) >= 8) then
        value.stage = "left_alone"
        value.leftAt = current
    elseif value.stage == "pleading" and close
        and current >= (tonumber(value.nextPleaAt) or 0) then
        sayNext(actor, value, PLEAS, "pleaIndex")
        value.nextPleaAt = current + 44000
    end
    if value.stage == "left_alone" and inRoom then
        -- A brief trip across the threshold is not a departure. The floor
        -- route will already be underway if the player was actually away.
        if current - (tonumber(value.leftAt) or current) < 6000 then
            value.stage = "pleading"
        end
    end
    if value.stage == "waiting" or value.stage == "pleading" then
        if current >= (tonumber(value.nextCoughAt) or 0) then
            local mode = coughMode()
            value.nextCoughAt = current
                + (mode == "rare" and 300000 or COUGH_MIN_MS)
                + ((tonumber(value.coughIndex) or 0) * 7919)
                    % COUGH_SPREAD_MS
            if mode ~= "off" then
                local nativeAllowed, nativeRead = U().call(actor,
                    "canCompanionScriptedSymptom")
                if not nativeRead or nativeAllowed == true then
                    local accepted = SC.Actor
                        and type(SC.Actor.setMovement) == "function"
                        and SC.Actor.setMovement(actor, "walk", {
                            action = "ext_gesture", ext = "Cough",
                            humanAnimationOnly = true })
                    if accepted == true then
                        value.coughIndex = (tonumber(value.coughIndex) or 0) + 1
                        U().call(actor, "noteCompanionScriptedSymptom")
                        if close and value.coughIndex % 2 == 0 then
                            sayNext(actor, value, COUGH_LINES,
                                "coughLineIndex")
                        end
                    end
                end
            end
        end
    end
    syncShelter(actor, value.deathConfirmed ~= true)
    return true, value.stage
end

function Bedridden.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.deathConfirmed == true or value.stage == "dying" then
        return { mode = "oddball_idle", priority = 28 }
    end
    return { mode = "bedridden_arthur", priority = 94 }
end

function Bedridden.update(actor, player, runtime, intent, group)
    local value = story(group)
    if renderLiftApplied[actor] == true
        and select(1, U().call(actor, "isOnBed")) ~= true then
        clearBedRenderLift(actor)
    end
    if not value or value.deathConfirmed == true or not intent
        or intent.mode ~= "bedridden_arthur" then
        return false, "arthur_no_special_move"
    end
    if value.stage == "left_alone" then
        if U().nowMs() - (tonumber(value.leftAt) or U().nowMs())
            < 6000 then
            return true, "arthur_waiting_after_departure"
        end
        if cancelLie(actor) then
            value.lieRecovery = true
        end
        local pose = bedPose(actor, value)
        if pose ~= "none" then
            local left, reason = leaveArthurBed(actor, value)
            return true, left and "arthur_leaving_bed"
                or reason or "arthur_standing_from_bed"
        end
        local exitReady, exitReason = finishArthurBedExit(actor, value)
        if not exitReady then return true, exitReason end
        local stepped, stepReason = stepOffBedAfterGetUp(actor, value,
            player)
        if stepped or stepReason == "arthur_waiting_for_private_bed_exit" then
            return true, stepReason
        end
        if stepReason ~= "no_bed_exit_recovery" then
            return false, stepReason
        end
        local corrected, correctionReason = correctFailedLiePosition(actor,
            value)
        if corrected then return true, correctionReason end
        if correctionReason ~= "no_failed_lie"
            and correctionReason ~= "already_in_bedroom" then
            return false, correctionReason
        end
        local tile = floorSquare(value)
        if not tile then return false, "arthur_floor_unavailable" end
        local ax, ay, az = U().position(actor)
        local fx, fy, fz = U().position(tile)
        if ax == nil or fx == nil then return false, "arthur_position_unavailable" end
        if math.floor(ax) ~= math.floor(fx)
            or math.floor(ay) ~= math.floor(fy)
            or math.floor(az or 0) ~= math.floor(fz or 0) then
            if not SC.Navigation
                or type(SC.Navigation.request) ~= "function" then
                return false, "arthur_floor_route_unavailable"
            end
            local reached, reason = SC.Navigation.request(actor, tile, "walk", {
                action = "oddball_arthur_floor",
                requireSameSquare = true, arrivalDistance = 0.3 })
            if reached then
                value.floorRouteFailures = 0
                return reached, reason
            end
            value.floorRouteFailures = (tonumber(value.floorRouteFailures) or 0) + 1
            if value.floorFallback ~= true and value.floorRouteFailures >= 3 then
                local fallbackPost = value.site and value.site.spawn
                local fallback = fallbackPost and U().gridSquare(
                    fallbackPost.x, fallbackPost.y, fallbackPost.z or 0)
                if fallback and fallback ~= tile
                    and select(1, U().call(fallback, "getRoom")) == bedroom(value)
                    and type(U().isClearActorSpawnSquare) == "function"
                    and U().isClearActorSpawnSquare(fallback) then
                    value.floorFallback = true
                    value.floorRouteFailures = 0
                    return true, "arthur_replanning_to_clear_floor"
                end
            end
            return false, reason
        end
        if not SC.Actor or type(SC.Actor.endLife) ~= "function" then
            return false, "native_life_end_unavailable"
        end
        if U().nowMs() < (tonumber(value.nextDeathAttemptAt) or 0) then
            return true, "arthur_final_injury_pending"
        end
        value.nextDeathAttemptAt = U().nowMs() + 2500
        local previousOutcome = value.outcome
        value.outcome = "died_alone"
        local ended, reason = SC.Actor.endLife(actor)
        if ended == true then
            if value.deathConfirmed == true then
                return true, "arthur_died_on_bedroom_floor"
            end
            value.stage = "dying"
            return true, "arthur_died_on_bedroom_floor"
        end
        if value.deathConfirmed == true then
            return true, "arthur_native_death_confirmed"
        end
        value.outcome = previousOutcome
        return false, reason
    end
    local lieEntry = lieEntries[actor]
    if lieEntry then
        local ax, ay, az = U().position(actor)
        local physical = ax and ay and U().gridSquare(math.floor(ax),
            math.floor(ay), math.floor(az or 0)) or nil
        if physical and select(1, U().call(physical, "getRoom"))
            ~= bedroom(value) then
            cancelLie(actor)
            value.lieFailureReason = "native_lie_left_bedroom"
            value.lieRecovery = true
            value.nextBedRetryAt = U().nowMs() + 2500
            return true, "arthur_recovering_from_lie_entry"
        end
        local onBed = select(1, U().call(actor, "isOnBed")) == true
        local started = select(1,
            U().call(actor, "getVariableBoolean", "OnBedStarted")) == true
        if onBed and started and lieEntry.pillow
            and lieEntry.pillowAligned ~= true then
            local now = U().nowMs()
            local px, py = U().position(actor)
            if not lieEntry.poseStartedAt then
                lieEntry.poseStartedAt = now
                -- OnBedStarted is the end event of the stock get-on-bed clip.
                -- Align on that first frame so the sleeping body is never
                -- rendered at the low foot-row anchor before moving up.
                U().call(actor, "setVariable", "OnBedAnim", "Asleep")
                U().call(actor, "setAsleep", false)
                local footX = px and math.floor(px) or nil
                local footY = py and math.floor(py) or nil
                local oneTileBelowPillow = footX == lieEntry.pillow.x
                    and footY == lieEntry.pillow.y + 1
                local method = SCBridge
                    and SCBridge.shiftOnBedPoseTowardPillow
                if oneTileBelowPillow and method then
                    local invoked, shifted = pcall(method, actor,
                        lieEntry.pillow.x, lieEntry.pillow.y,
                        lieEntry.pillow.z)
                    if invoked and shifted == true
                        and pillowLieSupported(actor, value,
                            lieEntry.pillow) then
                        lieEntry.pillowAligned = true
                        px, py = U().position(actor)
                    end
                end
            end
            if lieEntry.pillowAligned ~= true then
                if not lieEntry.poseX or not lieEntry.poseY
                    or not px or not py
                    or math.abs(px - lieEntry.poseX)
                        + math.abs(py - lieEntry.poseY) > 0.015 then
                    lieEntry.poseStableAt = now
                end
                lieEntry.poseX, lieEntry.poseY = px, py
                if now - (lieEntry.poseStableAt or now) < 1000 then
                    return true, "arthur_settling_on_bed"
                end
                if pillowLieSupported(actor, value, lieEntry.pillow) then
                    lieEntry.pillowAligned = true
                else
                    local footX = px and math.floor(px) or nil
                    local footY = py and math.floor(py) or nil
                    local oneTileBelowPillow = footX == lieEntry.pillow.x
                        and footY == lieEntry.pillow.y + 1
                    local method = SCBridge
                        and SCBridge.shiftOnBedPoseTowardPillow
                    local invoked, shifted = false, false
                    if oneTileBelowPillow and method then
                        invoked, shifted = pcall(method, actor,
                            lieEntry.pillow.x, lieEntry.pillow.y,
                            lieEntry.pillow.z)
                    end
                    if invoked and shifted == true
                        and pillowLieSupported(actor, value,
                            lieEntry.pillow) then
                        lieEntry.pillowAligned = true
                    else
                        cancelLie(actor)
                        value.lieFailureReason = oneTileBelowPillow
                            and "native_pillow_alignment_failed"
                            or "native_pillow_alignment_unsupported"
                        value.lieRecovery = true
                        value.lieFailed = true
                        return true, "arthur_recovering_from_lie_entry"
                    end
                end
            end
        end
        if onBed and started and onBedLengthSupported(actor, value)
            and pillowLieSupported(actor, value, lieEntry.pillow) then
            if lieEntry.pillow and not applyBedRenderLift(actor) then
                return true, "arthur_waiting_for_bed_render"
            end
            lieEntries[actor] = nil
            U().call(actor, "setVariable", "OnBedAnim", "Asleep")
            U().call(actor, "setAsleep", false)
            value.nativeBedPoseStarted = true
            value.bedPoseNeedsLift = lieEntry.pillow ~= nil
            return true, "arthur_lying_on_bed"
        end
        if U().nowMs() - lieEntry.startedAt < LIE_TIMEOUT_MS then
            return true, "arthur_entering_lie_pose"
        end
        cancelLie(actor)
        value.lieFailureReason = "native_lie_entry_timeout"
        value.lieRecovery = true
        value.nextBedRetryAt = U().nowMs() + 2500
    end
    if value.lieRecovery == true then
        clearBedRenderLift(actor)
        value.bedPoseNeedsLift = nil
        local pose = bedPose(actor, value)
        if pose ~= "none" then
            local left, reason = leaveArthurBed(actor, value)
            if not left then return false, reason end
            return true, "arthur_recovering_from_lie_entry"
        end
        local exitReady, exitReason = finishArthurBedExit(actor, value)
        if not exitReady then return true, exitReason end
        local corrected, correctionReason = correctFailedLiePosition(actor,
            value)
        if corrected then return true, correctionReason end
        if correctionReason ~= "already_in_bedroom"
            and correctionReason ~= "no_failed_lie" then
            return false, correctionReason
        end
        value.lieRecovery = nil
    end
    local pose = bedPose(actor, value)
    if pose == "entered" then
        if value.bedPoseNeedsLift == true
            and not applyBedRenderLift(actor) then
            return true, "arthur_waiting_for_bed_render"
        end
        U().call(actor, "setVariable", "OnBedAnim", "Asleep")
        U().call(actor, "setAsleep", false)
        value.nativeBedPoseStarted = true
        return true, "arthur_bedridden"
    end
    if pose == "entering" then
        value.lieEntryDeadlineAt = value.lieEntryDeadlineAt
            or U().nowMs() + LIE_TIMEOUT_MS
        if U().nowMs() < value.lieEntryDeadlineAt then
            return true, "arthur_entering_bed"
        end
        value.lieRecovery = true
        value.lieFailureReason = "native_lie_entry_unsettled"
        return true, "arthur_recovering_from_lie_entry"
    end
    value.lieEntryDeadlineAt = nil
    if pose == "failed" then
        value.lieRecovery = true
        value.lieFailureReason = "native_lie_pose_failed"
        local left, reason = leaveArthurBed(actor, value)
        if not left then return false, reason end
        return true, "arthur_recovering_from_lie_entry"
    end
    if value.lieFailed == true
        or (tonumber(value.lieAttempts) or 0) >= LIE_MAX_ATTEMPTS then
        value.lieFailed = true
        return false, "arthur_sleep_entry_failed"
    end
    if U().nowMs() < (tonumber(value.nextBedRetryAt) or 0) then
        return true, "arthur_waiting_to_retry_bed"
    end
    local bed = bedObject(value)
    if not bed then return false, "arthur_bed_unavailable" end
    local attempt = (tonumber(value.lieAttempts) or 0) + 1
    local started, reason, approach, needsLift = startLie(actor, bed)
    value.lieApproach = approach
    if reason == "native_bed_queue_busy" then
        value.lieQueueBusyAt = value.lieQueueBusyAt or U().nowMs()
        if U().nowMs() - value.lieQueueBusyAt < LIE_TIMEOUT_MS then
            return true, "arthur_waiting_for_native_bed_queue"
        end
    end
    value.lieQueueBusyAt = nil
    value.lieAttempts = attempt
    if started then value.bedPoseNeedsLift = needsLift == true end
    value.lieEntryDeadlineAt = U().nowMs() + LIE_TIMEOUT_MS
    value.liePlacementAttempted = nil
    value.liePlaceAt = nil
    if started then return true, reason end
    value.lieFailureReason = reason
    value.nextBedRetryAt = U().nowMs() + 2500
    if attempt >= LIE_MAX_ATTEMPTS then
        value.lieFailed = true
        return false, "arthur_sleep_entry_failed"
    end
    return true, "arthur_retrying_native_bed_entry"
end

function Bedridden.menuOptions(group, player)
    local value = story(group)
    if not value or value.deathConfirmed == true or value.stage == "dying"
        or not playerInBedroom(value, player)
        or not near(group, player, 4) then return {} end
    return {
        { id = "ask_arthur", label = "Ask Arthur about his pain",
            enabled = true },
        { id = "stay_arthur", label = "Sit with Arthur a while",
            enabled = true },
        { id = "mercy_arthur", label = "Grant Arthur's request for mercy",
            enabled = true },
    }
end

function Bedridden.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if actor and not U().isDead(actor) then
            U().say(actor,
                "Yes... please. If you have started, do not leave me halfway.")
        end
        -- He does not retaliate or acquire hostile standing for being struck.
        return true, "arthur_does_not_fight_back"
    end
    if not actor or not player or not playerInBedroom(value, player)
        or not near(group, player, 4) then
        return false, "arthur_out_of_reach"
    end
    if value.deathConfirmed == true or value.stage == "dying" then
        return false, "arthur_already_dying"
    end
    if action == "ask_arthur" then
        value.stage = "pleading"
        group.discovered = true
        U().say(actor,
            "The doctor called it a long illness. Now each breath cuts like wire. Evelyn went first. I am tired of counting the hours after her.")
        return true, "arthur_explained"
    elseif action == "stay_arthur" then
        value.stage = "pleading"
        group.discovered = true
        U().say(actor,
            "Then stay until the room goes quiet. Tell me something ordinary. Tell me if the rain has stopped.")
        value.nextPleaAt = U().nowMs() + 60000
        return true, "arthur_not_alone_yet"
    elseif action == "mercy_arthur" then
        if not SC.Actor or type(SC.Actor.endLife) ~= "function" then
            return false, "native_life_end_unavailable"
        end
        U().say(actor,
            "Thank you. Tell Evelyn I was brave, even if you have to lie.")
        local previousOutcome = value.outcome
        value.outcome = "mercy"
        clearBedRenderLift(actor)
        local ended, reason = SC.Actor.endLife(actor)
        if ended ~= true then
            if value.deathConfirmed == true then
                return true, "arthur_native_death_confirmed"
            end
            value.outcome = previousOutcome
            return false, reason
        end
        if value.deathConfirmed ~= true then value.stage = "dying" end
        group.discovered = true
        if SC.OddballRoomGuard then
            SC.OddballRoomGuard.release(group.id)
        end
        return true, "arthur_mercy_granted"
    end
    return false, "unknown_arthur_action"
end

function Bedridden.zombiesIgnore(actor, group)
    local value = story(group)
    return value ~= nil and value.deathConfirmed ~= true
        and not U().isDead(actor)
end

function Bedridden.avoidsZombieCombat(actor, group)
    local value = story(group)
    return value ~= nil and value.deathConfirmed ~= true
end

function Bedridden.canRecruit()
    return false, "arthur_is_too_ill_to_leave"
end

return Bedridden
