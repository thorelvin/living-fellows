-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TVWatching = SC.TVWatching or {}
local TV = SC.TVWatching
local installed = false
local mediaCache = setmetatable({}, { __mode = "k" })
local mediaCooldowns = setmetatable({}, { __mode = "k" })
local lastCommentAt = setmetatable({}, { __mode = "k" })
local lastScreenCommentAt = {}

local function U() return SC.GameplayUtil end

local function device(object)
    -- getDeviceData exists on world wave-signal objects, not on every
    -- fixture in a room. Avoid a failed Java method call for each cabinet,
    -- floor item and wall object during the bounded TV search.
    if type(object) ~= "table"
        and not U().instanceOf(object, "IsoWaveSignal") then return nil end
    local data = select(1, U().call(object, "getDeviceData"))
    return data and select(1, U().call(data, "getIsTelevision")) == true
        and data or nil
end

function TV.isOn(object)
    local data = object and device(object) or nil
    if not data then return false end
    local power = select(1, U().call(data, "getPower"))
    local volume = select(1, U().call(data, "getDeviceVolume"))
    return select(1, U().call(data, "getIsTurnedOn")) == true
        and (tonumber(power) or 0) > 0
        and (tonumber(volume) or 0) > 0
end

local function sameRoom(first, second)
    local a = select(1, U().call(U().squareOf(first), "getRoom"))
    local b = select(1, U().call(U().squareOf(second), "getRoom"))
    return a ~= nil and a == b
end

local function campFloorRoute(source, destination)
    return SC.BaseLife and type(SC.BaseLife.allowsFloorTransit) == "function"
        and SC.BaseLife.allowsFloorTransit(source, destination,
            { workCampOnly = true }) == true
end

local facingVectors = {
    N = { 0, -1 }, NE = { 1, -1 }, E = { 1, 0 },
    SE = { 1, 1 }, S = { 0, 1 }, SW = { -1, 1 },
    W = { -1, 0 }, NW = { -1, -1 },
}

local function facesScreen(direction, viewer, television)
    if direction == nil then return false end
    local name = tostring(direction):match("([NS][EW]?)$") or
        tostring(direction):match("([EW])$")
    local vector = facingVectors[name]
    local x, y = U().position(viewer)
    local tx, ty = U().position(television)
    if not vector or not x or not tx then return false end
    local dx, dy = tx - x, ty - y
    local dot = dx * vector[1] + dy * vector[2]
    return dot > 0 and dot * dot >= (dx * dx + dy * dy) * 0.35
end

local function seatDirection(object)
    if type(SeatingManager) ~= "table"
        or type(SeatingManager.getInstance) ~= "function" then return nil end
    local ok, manager = pcall(SeatingManager.getInstance)
    if not ok then return nil end
    return select(1, U().call(manager, "getFacingDirection", object))
end

local function viewingSeat(actor, television, hooks, state, now)
    local tx, ty, tz = U().position(television)
    if not tx then return nil end
    local best, bestScore
    for dx = -4, 4 do
        for dy = -4, 4 do
            local square = U().gridSquare(tx + dx, ty + dy, tz)
            if square and sameRoom(square, television)
                and U().canSee(square, U().squareOf(television)) then
                U().squareObjects(square, function(object)
                    if hooks.furnitureKind(object) ~= "sit"
                        or hooks.reserved(object, actor, now)
                        or hooks.cooling(state, object, now)
                        or select(1, U().call(object, "isFurnitureOccupied", actor)) == true
                        or not facesScreen(seatDirection(object), object, television) then
                        return true
                    end
                    local arrived, targets = hooks.freeAccess(actor, object)
                    if not arrived and #(targets or {}) == 0 then return true end
                    local distance = U().distance(actor, square)
                    if distance > 8 then return true end
                    local score = 38 - distance * 0.5
                    if not best or score > bestScore then
                        best, bestScore = {
                            kind = "sit", score = score, object = object,
                            square = square,
                            fact = { activity = "sit", seatingFor = "tv_watch" },
                        }, score
                    end
                    return true
                end, 24)
            end
        end
    end
    return best
end

local function standingSquare(actor, television)
    local tx, ty, tz = U().position(television)
    if not tx then return nil end
    local current = U().squareOf(actor)
    if current and sameRoom(current, television)
        and U().distance(actor, television) <= 5
        and U().canSee(current, U().squareOf(television)) then
        return current
    end
    local best, score
    for dx = -3, 3 do
        for dy = -3, 3 do
            if dx ~= 0 or dy ~= 0 then
                local square = U().gridSquare(tx + dx, ty + dy, tz)
                if square and sameRoom(square, television)
                    and U().isSquareFree(square)
                    and not U().movingBlocker(square, actor)
                    and U().canSee(square, U().squareOf(television)) then
                    local distance = U().distance(actor, square)
                    local value = distance + math.abs(math.sqrt(dx * dx + dy * dy) - 2)
                    if distance <= 8 and (not best or value < score) then
                        best, score = square, value
                    end
                end
            end
        end
    end
    return best
end

function TV.candidate(actor, state, now, hooks, desiredKind)
    if not actor or not hooks or (desiredKind and desiredKind ~= "tv_watch"
        and desiredKind ~= "sit") then return nil end
    local ax, ay, az = U().position(actor)
    if not ax then return nil end
    local seated = hooks.seatingStatus(actor) == "furniture"
    local currentFloor = math.floor(az)
    local camp = not seated and desiredKind ~= "sit" and SC.BaseLife
        and type(SC.BaseLife.active) == "function" and SC.BaseLife.active()
    local best, bestScore
    for floor = currentFloor - 1, currentFloor + 1 do
        local crossFloor = floor ~= currentFloor
        if not crossFloor or camp then
            local radius = crossFloor and 10 or 6
            for dx = -radius, radius do
                for dy = -radius, radius do
                    if not crossFloor or dx * dx + dy * dy <= 100 then
                        local square = U().gridSquare(ax + dx, ay + dy, floor)
                        if square and (crossFloor or sameRoom(actor, square)) then
                            U().squareObjects(square, function(object)
                                if not TV.isOn(object)
                                    or (crossFloor and not campFloorRoute(actor, square))
                                    or (not crossFloor and not U().canSee(actor, square)) then
                                    return true
                                end
                                local candidate
                                if seated then
                                    local direction = select(1, U().call(actor,
                                        "getSitOnFurnitureDirection"))
                                    if U().distance(actor, object) <= 5
                                        and facesScreen(direction, actor, object) then
                                        candidate = { kind = "tv_watch", score = 31,
                                            object = object, seated = true,
                                            durationMs = 90000,
                                            fact = { activity = "tv_watch", seated = true } }
                                    end
                                else
                                    local seat = desiredKind ~= "tv_watch"
                                        and viewingSeat(actor, object, hooks, state, now) or nil
                                    if seat then candidate = seat
                                    else
                                        local target = standingSquare(actor, object)
                                        if target and desiredKind ~= "sit" then
                                            candidate = { kind = "tv_watch",
                                                score = crossFloor and 18 or 24,
                                                object = object, square = target,
                                                crossFloor = crossFloor,
                                                originSquare = crossFloor
                                                    and U().squareOf(actor) or nil,
                                                durationMs = 90000,
                                                fact = { activity = "tv_watch",
                                                    seated = false } }
                                        end
                                    end
                                end
                                if candidate and (not best or candidate.score > bestScore) then
                                    best, bestScore = candidate, candidate.score
                                end
                                return true
                            end, 24)
                        end
                    end
                end
            end
        end
    end
    return best
end

function TV.valid(actor, activity, atViewpoint)
    if not actor or not activity or not TV.isOn(activity.object) then return false end
    if not sameRoom(actor, activity.object) then
        if atViewpoint or activity.crossFloor ~= true
            or not campFloorRoute(activity.originSquare, activity.square) then
            return false
        end
        local nav = SC.Navigation and type(SC.Navigation.peek) == "function"
            and SC.Navigation.peek(actor) or nil
        local lease = nav and nav.nativeLease or nil
        local onCampStairs = lease and lease.workCampOnly == true
            and lease.affordance == "multi_level"
            and ((SC.Navigation._betweenFloorHeights
                    and SC.Navigation._betweenFloorHeights(actor))
                or SC.BaseLife.admitsStairTransit(U().squareOf(actor), lease)
                or (SC.Navigation.isCampStairLanding
                    and SC.Navigation.isCampStairLanding(actor)))
        if not SC.BaseLife.isInside(actor) and not onCampStairs then return false end
    end
    if not atViewpoint then return true end
    if U().distance(actor, activity.object) > 5
        or not U().canSee(actor, U().squareOf(activity.object)) then return false end
    if activity.seated then
        local direction = select(1, U().call(actor,
            "getSitOnFurnitureDirection"))
        return facesScreen(direction, actor, activity.object)
    end
    return U().sameSquare(actor, activity.square)
end

function TV.approach(actor, activity)
    if activity.seated or U().sameSquare(actor, activity.square) then
        return true, "arrived"
    end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, activity.square, "walk", {
        action = "move_to_tv", targetSquare = activity.square,
        object = activity.object, requireSameSquare = true,
        arrivalDistance = 0.35, continuousApproach = true,
        workCampOnly = activity.crossFloor == true,
        supervisorToken = activity.supervisorToken,
    })
end

function TV.start(actor, activity, now)
    if not TV.valid(actor, activity, true) then return false, "tv_view_unavailable" end
    if not activity.seated then U().call(actor, "faceThisObject", activity.object) end
    activity.approaching = nil
    activity.actionAccepted = true
    activity.startedAt = now
    return true, "watching_tv"
end

function TV.isWatching(actor, x, y, z)
    if select(1, U().call(actor, "isAsleep")) == true then return false end
    local state = SC.Downtime and SC.Downtime.peek(actor) or nil
    local activity = state and state.active or nil
    if not activity or activity.kind ~= "tv_watch"
        or not activity.startedAt or not TV.valid(actor, activity, true) then
        return false
    end
    local tx, ty, tz = U().position(activity.object)
    return tx ~= nil and math.floor(tx) == math.floor(tonumber(x) or -1)
        and math.floor(ty) == math.floor(tonumber(y) or -1)
        and math.floor(tz or 0) == math.floor(tonumber(z) or -1)
end

local skillPerks = {
    SPR = "Sprinting", LFT = "Lightfoot", NIM = "Nimble", SNE = "Sneak",
    BAA = "Axe", BUA = "Blunt", CRP = "Woodwork", COO = "Cooking",
    FRM = "Farming", DOC = "Doctor", ELC = "Electricity",
    MTL = "MetalWelding", FKN = "FlintKnapping", CRV = "Carving",
    AIM = "Aiming", REL = "Reloading", FIS = "Fishing",
    TRA = "Trapping", FOR = "PlantScavenging", TAI = "Tailoring",
    MEC = "Mechanics", CMB = "Combat", SPE = "Spear",
    SBU = "SmallBlunt", LBA = "LongBlade", SBA = "SmallBlade",
    MAS = "Masonry", POT = "Pottery", BLA = "Blacksmith",
    GLA = "Glassmaking", HUS = "Husbandry", BUT = "Butchering",
    TRK = "Tracking",
}

local function mediaLedger(actor)
    local id = SC.Registry and SC.Registry.idOf and SC.Registry.idOf(actor)
    local record = id and SC.Registry.byId(id) or nil
    if not record then return nil end
    record.state = type(record.state) == "table" and record.state or {}
    record.state.downtime = type(record.state.downtime) == "table"
        and record.state.downtime or {}
    local downtime = record.state.downtime
    downtime.mediaLines = type(downtime.mediaLines) == "table"
        and downtime.mediaLines or {}
    local cache = mediaCache[actor]
    if not cache or cache.lines ~= downtime.mediaLines then
        cache = { lines = downtime.mediaLines, known = {} }
        for _, guid in ipairs(cache.lines) do cache.known[guid] = true end
        mediaCache[actor] = cache
    end
    return cache
end

local function learnLine(actor, guid)
    if type(guid) ~= "string" or guid == "" then return true end
    local cache = mediaLedger(actor)
    if not cache or cache.known[guid]
        or select(1, U().call(actor, "isKnownMediaLine", guid)) == true then
        return false
    end
    cache.known[guid] = true
    cache.lines[#cache.lines + 1] = guid
    if #cache.lines > 2048 then
        cache.known[table.remove(cache.lines, 1)] = nil
    end
    U().call(actor, "addKnownMediaLine", guid)
    return true
end

local function applyCodes(actor, codes)
    local perks = Perks
    local cooldown = mediaCooldowns[actor] or {}
    mediaCooldowns[actor] = cooldown
    local now = U().nowMs()
    for value in tostring(codes or ""):gmatch("[^,]+") do
        local code, operation, raw = value:match("^%s*(%u%u%u)([+%-=])(.+)%s*$")
        local perkName = code and skillPerks[code] or nil
        local perk = perkName and perks and perks[perkName] or nil
        if perk and now >= (cooldown[code] or 0) then
            local amount = tonumber(raw)
            local level = select(1, U().call(actor, "getPerkLevel", perk))
            local cutoff = SandboxVars and tonumber(SandboxVars.LevelForMediaXPCutoff)
            if amount and amount > 0 and (not cutoff
                or (tonumber(level) or 0) < cutoff) then
                local awarded = false
                if type(addXp) == "function" then
                    awarded = pcall(addXp, actor, perk, amount * 50)
                end
                if not awarded then
                    local xp = select(1, U().call(actor, "getXp"))
                    U().call(xp, "AddXP", perk, amount * 50)
                end
                cooldown[code] = now + 500
            end
        elseif code == "RCP" and operation == "=" and raw then
            U().call(actor, "learnRecipe", raw)
        end
    end
end

local function commentOnBroadcast(actor, guid, codes, x, y, z)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    local state = SC.Downtime and SC.Downtime.peek(actor) or nil
    local activity = state and state.active
    if not activity or activity.lastCommentGuid == guid then return false end
    -- One reaction per broadcast line, even when the game delivers it twice.
    activity.lastCommentGuid = guid
    local current = U().nowMs()
    if current - (lastCommentAt[actor] or -math.huge) < 45000 then return false end
    local screenKey = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    if current - (lastScreenCommentAt[screenKey] or -math.huge) < 8000 then
        return false
    end
    local lastSpeech = type(SC.Dialogue.lastSpokenAt) == "function"
        and SC.Dialogue.lastSpokenAt(actor) or -math.huge
    if current - lastSpeech < 12000 then return false end
    if type(ZombRand) == "function" and ZombRand(100) >= 45 then return false end
    local teaches = type(codes) == "string"
        and codes:match("%u%u%u[%+%-=]") ~= nil
    local topic = teaches and "downtime.tv.learn" or "downtime.tv.comment"
    local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, nil,
        { recentLimit = 5, salt = tostring(guid) })
    if ok and spoken == true then
        lastCommentAt[actor] = current
        lastScreenCommentAt[screenKey] = current
        return true
    end
    return false
end

function TV.onDeviceText(guid, codes, x, y, z)
    if tonumber(x) == -1 or tonumber(y) == -1 or tonumber(z) == -1
        or not SC.Registry or type(SC.Registry.living) ~= "function" then
        return
    end
    for _, actor in ipairs(SC.Registry.living()) do
        if TV.isWatching(actor, x, y, z) then
            local localPlayer = false
            if type(getSpecificPlayer) == "function" then
                for slot = 0, 3 do
                    if getSpecificPlayer(slot) == actor then
                        localPlayer = true
                        break
                    end
                end
            end
            if not localPlayer and learnLine(actor, guid) then
                applyCodes(actor, codes)
            end
            commentOnBroadcast(actor, guid, codes, x, y, z)
        end
    end
end

function TV.install()
    if installed or not Events or not Events.OnDeviceText
        or type(Events.OnDeviceText.Add) ~= "function" then return false end
    Events.OnDeviceText.Add(TV.onDeviceText)
    installed = true
    return true
end

function TV.reset()
    mediaCache = setmetatable({}, { __mode = "k" })
    mediaCooldowns = setmetatable({}, { __mode = "k" })
    lastCommentAt = setmetatable({}, { __mode = "k" })
    lastScreenCommentAt = {}
    return true
end

TV.install()
