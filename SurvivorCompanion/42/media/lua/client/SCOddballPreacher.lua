-- SPDX-License-Identifier: MIT
-- Dwayne Stidham ran the board for Reverend Lyle Mabry's Gospel Hour. The
-- Reverend died the first week; Dwayne keeps reading his last twelve taped
-- sermons from the station van on FM 103.4, three times a day. Each line is a
-- native ZomboidRadio transmission from the van, so any radio tuned and in
-- range hears it. A listener can bring him a book to read when the sermons
-- run out; otherwise he signs off and may come along.

local SC = SurvivorCompanion
SC.OddballPreacher = SC.OddballPreacher or {}
local Preacher = SC.OddballPreacher

local ID = "radio_preacher_dwayne"
local CHANNEL = 103400
local FIRST_SERMON = 41
local LAST_SERMON = 52
local SLOT_HOURS = { 8, 13, 19 }
local LINE_GAP_MS = 12000
-- The station van's Radio part takes a HamRadio1 (7.5 km) or HamRadio2.
-- Without a readable part, use the smaller set's range.
local FALLBACK_RANGE = 7500
local NEAR_DISTANCE = 8
local MENU_DISTANCE = 4
local BOOK_READINGS = 3
local seatAttempts = setmetatable({}, { __mode = "k" })

local SERMONS = {
    [41] = { "Sermon forty-one. On Neighbors.",
        "Love thy neighbor. Even the one who borrowed your hedge trimmer in nineteen eighty-eight.",
        "Your neighbor is not your enemy. Unless he is at the window. Then pray, and lock it.",
        "Go to him. Knock. If he does not answer, perhaps leave him be." },
    [42] = { "Sermon forty-two. On Hunger.",
        "Man shall not live by bread alone. He will want a casserole.",
        "There are hungers of the flesh, brothers and sisters. Do not give in to them.",
        "Feed the hungry. Within reason. Use a long spoon." },
    [43] = { "Sermon forty-three. On Rest.",
        "There is a time to rest. The Lord rested. The dead rest.",
        "Unless they do not. Then we take that up with the Lord directly.",
        "Sleep, and wake refreshed. Check your doors first." },
    [44] = { "Sermon forty-four. On Rising.",
        "The dead in Christ shall rise first. Paul wrote that to the Thessalonians.",
        "First, he says. Not last. Not at a convenient hour.",
        "Be ready. Put your affairs in order. Keep your shoes by the bed." },
    [45] = { "Sermon forty-five. On Patience.",
        "Patience is a virtue. So is a deadbolt.",
        "The Lord is slow to anger. The county is slow to answer the phone.",
        "Wait on the Lord. He is running late too." },
    [46] = { "Sermon forty-six. On Covetousness.",
        "Do not covet thy neighbor's riding mower.",
        "Do not covet his wife, his ox, or his canned peaches.",
        "The Reverend wrote in the margin: once he's gone, it isn't coveting. It's salvage." },
    [47] = { "Sermon forty-seven. On Pride.",
        "Pride goeth before a fall. So does a loose porch step.",
        "Humble yourselves. Get down low. Stay low until it passes.",
        "The meek shall inherit the earth. There may be more of it to go around." },
    [48] = { "Sermon forty-eight. On Fellowship.",
        "Do not forsake the gathering together. Potluck is the third Sunday.",
        "We are one body. Keep that body indoors after dark.",
        "Fellowship heals. So do bandages. Bring both." },
    [49] = { "Sermon forty-nine. On Fear.",
        "Fear not, the Book says. Some say it says so once for every day of the year.",
        "Today is one of those days.",
        "Courage is fear that has said its prayers. And checked the back door." },
    [50] = { "Sermon fifty. On Charity.",
        "Give to those who ask. If they are still asking, they are still alive.",
        "Charity begins at home. Board up home first.",
        "The Lord loves a cheerful giver. He has not met many lately." },
    [51] = { "Sermon fifty-one. On Endings.",
        "Every story ends. The good ones end with somebody still standing.",
        "Do not mourn as those who have no hope. Mourn quietly. Sound carries.",
        "Amen means so be it. It does not mean it's over." },
    [52] = { "Sermon fifty-two. The last one.",
        "This is the last of my recordings, Dwayne. If you are reading it aloud, I am gone.",
        "Keep the van running. Keep a light on. Somebody is always listening.",
        "And for heaven's sake, son, get some sleep." },
}
Preacher.SERMONS = SERMONS

local READINGS = {
    bible = {
        "A listener brought me the Good Book. Their Good Book. Thank you.",
        "Genesis. In the beginning. Seems like a long time ago.",
        "Psalm twenty-three. Yea, though I walk through the valley. That's every day now.",
        "Amen. That one's from the book, not me.",
    },
    cooking = {
        "Reading tonight from a cookbook. A listener sent it. Bless them.",
        "Pot roast. Three pounds of chuck. If anybody has three pounds of chuck, call in.",
        "Preheat the oven to three-fifty. If you have an oven. If you have power.",
        "Serves six. That's ambitious.",
    },
    growing = {
        "Tonight, a book about growing things.",
        "Plant potatoes when the ground can be worked. It can. Nobody's working it.",
        "Water deeply and less often. Same goes for crying.",
        "Harvest when it's ready. Not before. Sermon forty-five covered patience.",
    },
    engines = {
        "Reading from a book on engines. The listener has high hopes for me.",
        "Check the oil with the engine cold. Everything's cold now.",
        "If the starter clicks and won't turn, check the battery. Then pray.",
        "Tighten the lug nuts in a star. Like a church window.",
    },
    soldiering = {
        "Reading from a military book. Feels wrong. Reading anyway.",
        "Hold your position. Conserve ammunition. Maintain discipline.",
        "Know your sectors of fire. I don't know mine. I'm on the radio.",
        "That's the chapter. Out.",
    },
    other = {
        "Reading from what a listener gave me. It has pictures. Trust me.",
        "Chapter one. Somebody wants something. Somebody else is in the way.",
        "It goes on like that for a while. Most things do.",
        "I'll read more next time. Leave the radio on.",
    },
}
Preacher.READINGS = READINGS

local LINES = {
    intro = {
        "This is the Gospel Hour on one-oh-three point four. I'm Dwayne. I run the board.",
        "Gospel Hour. Reverend Mabry is unavailable. I'll read for him.",
        "You're listening to the Gospel Hour. Still here. Still reading.",
    },
    outro = {
        "That's the end of that one. Next broadcast at the usual time.",
        "If anybody's out there, I'm in the station van on the shoulder. I've got cold coffee.",
        "Reverend wrote that last spring. He didn't know. Nobody knew.",
        "Gospel Hour, signing off. Pray for batteries.",
    },
    signOff = {
        "That was the last tape. Reverend Mabry, signing off. And Dwayne. That's me.",
    },
    greet = { "Oh. Oh, Lord. A listener. In person." },
    greet2 = { "I'm Dwayne. I run the board. Ran it. Run it." },
    reverend = {
        "He went the first week. His heart, I think. Before anything bit him.",
        "Buried him by the road. Said words. Then I read his words. Seemed fair.",
    },
    why = {
        "Fifty-two sermons. He wrote one a week for a year. I'm on %d.",
        "When they run out, I guess I find out what I am without a script.",
    },
    whyDone = { "They ran out. Turns out without a script I'm mostly tired." },
    book = { "A book? For the air? I'll read it next broadcast. Can't be worse than silence." },
    noBook = { "Bring me something to read. Anything. The quiet is worse." },
    fellow = {
        "He's been reading a dead man's sermons to the dead. I respect it.",
        "I heard him on the radio. Didn't know he was real.",
    },
}
Preacher.LINES = LINES

local function U() return SC.GameplayUtil end

local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    if value.stage == nil or value.stage == "unmet" then value.stage = "broadcasting" end
    value.sermon = tonumber(value.sermon) or FIRST_SERMON
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

local function nextLine(value, pool)
    local list = LINES[pool]
    local index = tonumber(value.lines[pool]) or 0
    if index ~= index or index < 0 or index % 1 ~= 0 then index = 0 end
    index = index % #list + 1
    value.lines[pool] = index
    return list[index]
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    local okay, time = pcall(getGameTime)
    if not okay or not time then return nil end
    return tonumber((U().call(time, "getWorldAgeHours")))
end

local function vanFor(value)
    local sqlId = tonumber(value.vanSqlId)
    if not sqlId or not SC.Vehicle or type(SC.Vehicle.loadedBySqlId) ~= "function" then
        return nil
    end
    return SC.Vehicle.loadedBySqlId(sqlId)
end

local function seatedAtVan(actor, van)
    if not actor or not van or not SC.Vehicle or not SC.Vehicle.isNativeSeated then return false end
    local seated, vehicle, seat = SC.Vehicle.isNativeSeated(actor)
    return seated == true and vehicle == van and tonumber(seat) ~= nil and tonumber(seat) > 0
end

local function restoreEntryLock(value, van)
    local seat = tonumber(value.entryDoorRelockSeat)
    if not seat then return true end
    local part = select(1, U().call(van, "getPassengerDoor", seat))
    local door = part and select(1, U().call(part, "getDoor"))
    if not door then return false end
    U().call(door, "setLocked", true)
    U().call(van, "transmitPartDoor", part)
    if select(1, U().call(door, "isLocked")) ~= true then return false end
    value.entryDoorRelockSeat = nil
    return true
end

local function boardPassenger(value, actor, van, seat, prepared)
    local part = select(1, U().call(van, "getPassengerDoor", seat))
    local door = part and select(1, U().call(part, "getDoor"))
    if door then
        local locked, read = U().call(door, "isLocked")
        if not read then return false end
        if locked == true then
            value.entryDoorRelockSeat = seat
            U().call(door, "setLocked", false)
            U().call(van, "transmitPartDoor", part)
            if select(1, U().call(door, "isLocked")) ~= false then
                restoreEntryLock(value, van)
                return false
            end
        end
    end
    -- Only this encounter's saved van is passed here. As for Loretta, release
    -- its passenger lock for native entry and restore it even after an error.
    local called, boarded = pcall(SC.Vehicle.board, actor, van, seat,
        { allowVirtualSeat = false, preflight = prepared })
    if not called and SC.Vehicle.transactionStatus and SC.Vehicle.failTransaction then
        local transaction = SC.Vehicle.transactionStatus(actor)
        if transaction and transaction.action == "board_vehicle"
            and transaction.vehicle == van and transaction.seat == seat then
            SC.Vehicle.failTransaction(actor, "dwayne_native_boarding_error")
        end
    end
    if called and boarded == true then value.vanSeat = seat end
    local locked = restoreEntryLock(value, van)
    return called and boarded == true and locked
end

-- Reconcile the exact saved van and a real passenger seat, like Loretta's
-- vehicle recovery. Never replace an unloaded van or use a virtual seat.
local function returnToVan(group, actor, runtime, player)
    local value = story(group)
    if not value or actorFor(group) ~= actor then return false, "dwayne_actor_unavailable" end
    local van = vanFor(value)
    if van and not restoreEntryLock(value, van) then
        return true, "Restoring the station van's door lock"
    end
    if seatedAtVan(actor, van) then
        local route = SC.Navigation and SC.Navigation.peek and SC.Navigation.peek(actor)
        if route and route.goalAction == "dwayne_return_to_van" then
            SC.Navigation.cancel(actor, "dwayne_seated")
        end
        seatAttempts[actor] = nil
        return true, "Reading in the station van"
    end
    if not van then return true, "Waiting for the station van to load" end
    if select(1, U().call(actor, "getVehicle")) ~= nil then
        return true, "Waiting to return to the station van"
    end
    local now = U().nowMs()
    if now < (seatAttempts[actor] or 0) then return true, "Returning to the station van" end
    seatAttempts[actor] = now + 1000
    if not SC.Vehicle.isStationary or SC.Vehicle.isStationary(van) ~= true then
        return true, "Waiting for the station van to stop"
    end
    if not SC.Vehicle.boardingSquares or not SC.Vehicle.preflightBoard or not SC.Vehicle.board then
        return true, "Dwayne cannot enter the station van"
    end
    local targets, seat = SC.Vehicle.boardingSquares(actor, van, value.vanSeat, false)
    if not targets or not seat then return true, "The station van has no accessible passenger seat" end
    local prepared = SC.Vehicle.preflightBoard(actor, van, seat, false)
    -- Distant residents do not run the walking scheduler. As with Loretta,
    -- correct a hidden recovery to a clear exterior door square, then use
    -- ordinary native entry. Never move a visible, nearby or threatened actor.
    if not prepared and player and U().distance(actor, player) > 12
        and U().canSee(player, actor) == false and SC.Actor and SC.Actor.recover
        and SC.Senses and SC.Senses.isCompleteObservation and SC.Senses.snapshot then
        local record = SC.Registry.byId(U().idOf(actor))
        local actorRuntime = record and record.runtime
        local snapshot = actorRuntime and SC.Senses.snapshot(actor, player, actorRuntime)
        if snapshot and SC.Senses.isCompleteObservation(snapshot) == true
            and (tonumber(snapshot.threatCount) or 0) == 0
            and not actorRuntime.combatTarget and not actorRuntime.combatAction then
            for _, square in ipairs(targets) do
                if U().canSee(player, square) == false and U().isSafeSpawnSquare(square) then
                    local route = SC.Navigation and SC.Navigation.peek and SC.Navigation.peek(actor)
                    if route and route.goalAction ~= "dwayne_return_to_van" then break end
                    if route and SC.Navigation.cancel(actor, "dwayne_hidden_door_recovery") ~= true then break end
                    if SC.Actor.recover(actor, square) == true then
                        prepared = SC.Vehicle.preflightBoard(actor, van, seat, false)
                    end
                    break
                end
            end
        end
    end
    if prepared then
        local boarded = boardPassenger(value, actor, van, seat, prepared)
        if boarded and seatedAtVan(actor, van) then
            value.vanSeat = seat
            seatAttempts[actor] = nil
            return true, "Reading in the station van"
        end
    end
    if not SC.Navigation or not SC.Navigation.requestAny then return true, "Dwayne cannot reach the van" end
    local snapshot = runtime and (runtime.senses and runtime.senses.current or runtime.snapshot) or {}
    local accepted = SC.Navigation.requestAny(actor, targets, "walk", {
        action = "dwayne_return_to_van", vehicle = van, seat = seat, snapshot = snapshot,
        arrivalDistance = 0.15, desiredDistance = 0, continuousApproach = true,
    })
    if not accepted then seatAttempts[actor] = now + 3000 end
    return true, accepted and "Returning to the station van" or "Dwayne cannot reach the van"
end

function Preacher.canTalkFromVehicle(group, player)
    local value = story(group)
    local actor = value and actorFor(group)
    local van = value and vanFor(value)
    local square = van and select(1, U().call(van, "getSquare"))
    return player ~= nil and seatedAtVan(actor, van) and U().sameFloor(actor, player)
        and U().distance(van, player) <= 6
        and square ~= nil and U().canSee(player, square) == true or false
end

-- The transmitter is the van's own Radio part when it can be read.
function Preacher.transmitRange(value)
    local van = vanFor(value)
    local part = van and select(1, U().call(van, "getPartById", "Radio"))
    local data = part and select(1, U().call(part, "getDeviceData"))
    local range = data and tonumber((U().call(data, "getTransmitRange")))
    if range and range > 0 then return math.floor(range) end
    return FALLBACK_RANGE
end

local function sourcePoint(value)
    local van = vanFor(value)
    local x, y
    if van then x, y = U().position(van) end
    if x and y then return math.floor(x), math.floor(y) end
    local site = value.site
    local point = site and (site.van or site.spawn)
    if point then return point.x, point.y end
    return nil
end

function Preacher.transmit(value, text, code)
    if type(getZomboidRadio) ~= "function" then return false, "native_radio_unavailable" end
    local api = getZomboidRadio()
    if not api then return false, "native_radio_unavailable" end
    local x, y = sourcePoint(value)
    if not x then return false, "radio_van_position_unavailable" end
    local range = Preacher.transmitRange(value)
    local okay, failure = pcall(function()
        api:SendTransmission(x, y, CHANNEL, text, "LF-GOSPEL-HOUR", code,
            0.95, 0.85, 0.55, range, false)
    end)
    return okay, okay and "transmitted" or tostring(failure)
end

local ENGINE_LITERATURE = {
    ["base.magazine_car"] = true, ["base.magazine_car_new"] = true,
    ["base.bookmechanic1"] = true, ["base.bookmechanic2"] = true,
    ["base.bookmechanic3"] = true, ["base.bookmechanic4"] = true,
    ["base.bookmechanic5"] = true,
    ["base.mechanicmag1"] = true, ["base.mechanicmag2"] = true,
    ["base.mechanicmag3"] = true,
}

local function bookCategory(kind)
    kind = string.lower(tostring(kind or ""))
    if string.find(kind, "bible", 1, true) then return "bible" end
    if string.find(kind, "cook", 1, true) or string.find(kind, "recipe", 1, true) then
        return "cooking"
    end
    if string.find(kind, "farm", 1, true) or string.find(kind, "garden", 1, true) then
        return "growing"
    end
    if ENGINE_LITERATURE[kind] then return "engines" end
    if string.find(kind, "military", 1, true) then return "soldiering" end
    return "other"
end
Preacher.bookCategory = bookCategory

local function isLiterature(kind)
    kind = tostring(kind or "")
    return ENGINE_LITERATURE[string.lower(kind)] == true
        or string.find(kind, "^Base%.Book") ~= nil
        or string.find(kind, "^Base%.Paperback") ~= nil
        or string.find(kind, "^Base%.Magazine") ~= nil
        or string.find(kind, "^Base%.Comic") ~= nil
end

local function firstBook(player)
    local inventory = player and U().inventory(player)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory, 200, 4) or {}) do
        if isLiterature(U().itemType(item)) then return item end
    end
    return nil
end

-- Build one broadcast as a fixed list of lines, saved so a reload resumes it.
local function nextProgram(value)
    if value.sermon <= LAST_SERMON then
        local sermon = SERMONS[value.sermon]
        local lines = { nextLine(value, "intro") }
        for _, line in ipairs(sermon) do lines[#lines + 1] = line end
        if value.sermon == LAST_SERMON and not value.bookCategory then
            lines[#lines + 1] = LINES.signOff[1]
        else
            lines[#lines + 1] = nextLine(value, "outro")
        end
        local code = "SERMON-" .. tostring(value.sermon)
        value.sermon = value.sermon + 1
        return lines, code
    end
    local readings = tonumber(value.readings) or 0
    if value.bookCategory and readings < BOOK_READINGS then
        value.readings = readings + 1
        local lines = { nextLine(value, "intro") }
        for _, line in ipairs(READINGS[value.bookCategory] or READINGS.other) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = value.readings >= BOOK_READINGS and LINES.signOff[1]
            or nextLine(value, "outro")
        return lines, "READING-" .. tostring(value.readings)
    end
    return nil
end

-- The latest schedule slot already reached, as an absolute hour number.
local function dueSlot(hours)
    if not hours then return nil end
    local day = math.floor(hours / 24)
    local hour = hours - day * 24
    local best
    for _, slot in ipairs(SLOT_HOURS) do
        if hour >= slot then best = day * 24 + slot end
    end
    if best then return best end
    return (day - 1) * 24 + SLOT_HOURS[#SLOT_HOURS]
end

function Preacher.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = tonumber(current) or U().nowMs()
    local actor = actorFor(group)
    if actor and group.standing ~= "Hostile" and group.lifecycle ~= "hostile"
        and group.permanentHostility ~= true then
        local record = SC.Registry.byId(U().idOf(actor))
        returnToVan(group, actor, record and record.runtime, player)
    end
    if actor and value.met ~= true and player and U().sameFloor(actor, player)
        and U().distance(actor, player) <= NEAR_DISTANCE
        and (U().canSee(actor, player) == true or Preacher.canTalkFromVehicle(group, player)) then
        value.met = true
        group.discovered = true
        U().say(actor, LINES.greet[1])
        value.pendingGreet = current + 2500
    end
    if actor and value.pendingGreet and current >= value.pendingGreet then
        value.pendingGreet = nil
        U().say(actor, LINES.greet2[1])
        Preacher.fellowLine(group, player)
    end
    if type(value.airing) == "table" then
        if current < (tonumber(value.airing.nextAt) or 0) then return true, "gospel_hour_on_air" end
        local index = tonumber(value.airing.index) or 1
        local line = value.airing.lines[index]
        if line then
            Preacher.transmit(value, line, value.airing.code .. "-" .. tostring(index))
            value.airing.index = index + 1
            value.airing.nextAt = current + LINE_GAP_MS
            return true, "gospel_hour_line"
        end
        value.airing = nil
        if value.sermon > LAST_SERMON
            and (not value.bookCategory or (tonumber(value.readings) or 0) >= BOOK_READINGS) then
            value.stage = "silent"
        end
        return true, "gospel_hour_ended"
    end
    if value.stage == "silent" then return true, "gospel_hour_off_air" end
    local slot = dueSlot(worldHours())
    if not slot then return true, "gospel_hour_clock_unavailable" end
    if value.lastSlot == nil then
        -- The first slot he sees is the one already passed: start fresh at the next.
        value.lastSlot = slot
        return true, "gospel_hour_waiting"
    end
    if slot <= value.lastSlot then return true, "gospel_hour_waiting" end
    value.lastSlot = slot
    local lines, code = nextProgram(value)
    if not lines then
        value.stage = "silent"
        return true, "gospel_hour_off_air"
    end
    value.airing = { lines = lines, index = 1, code = code, nextAt = current }
    -- The first line goes out as the slot opens; the rest follow on the gap.
    return Preacher.pulse(group, player, current)
end

function Preacher.fellowLine(group, player)
    local value = story(group)
    if not value or value.fellowSpoke == true or not player or not SC.Registry
        or type(SC.Registry.living) ~= "function" then return false end
    local dwayne = actorFor(group)
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= dwayne and U().distance(fellow, player) <= 10 then
            local id = U().idOf(fellow)
            local record = id and SC.Registry.byId(id) or nil
            if record and record.recruited == true then
                U().say(fellow, nextLine(value, "fellow"))
                value.fellowSpoke = true
                return true
            end
        end
    end
    return false
end

function Preacher.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "dwayne_unavailable" end
    if value.vanAttempted ~= true then
        -- One attempt only. A second station van must never appear because a
        -- setup retry ran after the first spawn succeeded.
        value.vanAttempted = true
        local point = value.site and value.site.van
        local square = point and U().gridSquare(point.x, point.y, point.z or 0)
        if square and type(addVehicleDebug) == "function" then
            local facing = IsoDirections and IsoDirections.N or nil
            local okay, van = pcall(addVehicleDebug, "Base.VanRadio", facing, nil, square)
            local sqlId = okay and van and tonumber((U().call(van, "getSqlId"))) or nil
            value.vanSqlId = sqlId
        end
    end
    if value.notebookSeeded ~= true then
        local inventory = U().inventory(actor)
        local binder = inventory and U().addItem(inventory, "Base.Notebook")
        if not binder then return false, "dwayne_binder_unavailable" end
        U().call(binder, "setName", "Reverend Mabry's last sermons")
        local page = 1
        for number = FIRST_SERMON, LAST_SERMON do
            U().call(binder, "addPage", page, SERMONS[number][1] .. " " .. SERMONS[number][2])
            page = page + 1
        end
        value.notebookSeeded = true
    end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    returnToVan(group, actor, nil, player)
    return true, "dwayne_on_the_air"
end

function Preacher.intentFor(actor, player, snapshot, group)
    if not story(group) then return nil end
    if group.standing == "Hostile" or group.lifecycle == "hostile"
        or group.permanentHostility == true then
        return { mode = "hostile", priority = 110 }
    end
    return { mode = "preacher_by_the_van", priority = 60 }
end

function Preacher.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "preacher_by_the_van" then return false end
    return returnToVan(group, actor, runtime, player)
end

local function near(group, player, radius)
    local actor = actorFor(group)
    return actor ~= nil and player ~= nil and U().sameFloor(actor, player)
        and (U().distance(actor, player) <= radius or Preacher.canTalkFromVehicle(group, player))
end

function Preacher.menuOptions(group, player)
    local value = story(group)
    if not value or value.met ~= true or not near(group, player, MENU_DISTANCE) then
        return {}
    end
    local options = {
        { id = "ask_dwayne_reverend", label = "Ask about the Reverend", enabled = true },
        { id = "ask_dwayne_why", label = "Ask why he keeps reading", enabled = true },
    }
    if value.bookCategory == nil and value.stage ~= "silent" then
        local book = firstBook(player)
        options[#options + 1] = { id = "give_dwayne_book",
            label = book and ("Give him " .. tostring(U().itemName and U().itemName(book)
                or "a book") .. " to read on air") or "Give him a book to read on air",
            enabled = book ~= nil }
    end
    return options
end

function Preacher.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then return false, "dwayne_standing_changes" end
    if not actor or not near(group, player, MENU_DISTANCE) then return false, "dwayne_out_of_reach" end
    if action == "ask_dwayne_reverend" then
        U().say(actor, nextLine(value, "reverend"))
        return true, action
    elseif action == "ask_dwayne_why" then
        if value.sermon > LAST_SERMON then
            U().say(actor, LINES.whyDone[1])
        else
            local line = nextLine(value, "why")
            U().say(actor, string.find(line, "%%d") and string.format(line, value.sermon) or line)
        end
        return true, action
    elseif action == "give_dwayne_book" then
        if value.bookCategory ~= nil or value.stage == "silent" then
            return false, "dwayne_already_has_reading"
        end
        local book = firstBook(player)
        if not book then
            U().say(actor, LINES.noBook[1])
            return false, "player_has_no_book"
        end
        local kind = U().itemType(book)
        if not SC.OddballExchange or type(SC.OddballExchange.take) ~= "function" then
            return false, "exchange_unavailable"
        end
        local moved = SC.OddballExchange.take(player, actor, { [kind] = 1 })
        if moved ~= true then return false, "book_transfer_failed" end
        value.bookCategory = bookCategory(kind)
        U().say(actor, LINES.book[1])
        return true, action
    end
    return false, "unknown_dwayne_choice"
end

function Preacher.canRecruit(group)
    local value = story(group)
    if value and value.stage == "silent" then return true end
    return false, "dwayne_has_tapes_left"
end

function Preacher.avoidsZombieCombat(actor, group)
    local value = story(group)
    return value ~= nil and group.standing ~= "Hostile" and group.lifecycle ~= "hostile"
        and group.permanentHostility ~= true and seatedAtVan(actor, vanFor(value)) or false
end

function Preacher.reset() seatAttempts = setmetatable({}, { __mode = "k" }) end

return Preacher
