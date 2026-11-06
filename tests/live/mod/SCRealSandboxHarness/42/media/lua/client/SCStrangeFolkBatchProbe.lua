-- SPDX-License-Identifier: MIT
-- Disposable cloned-save probe for the seven Strange Folk added together:
-- Miss Liberty, Hershel, Gary and Ron, Dwayne, Bob Kenley, Hatcher and
-- Ruth Ann. One run tests one of them. The production decision loop and
-- faction pulse stay scheduled; the probe only plays the player's part
-- (walking up, picking a menu line, working a radio, finishing off what
-- came through a window) and reads every result back from native objects.
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
local Probe = {}
SCRealSandboxHarnessProbes.SCStrangeFolkBatchProbe = Probe

local IDS = {
    firecracker = "firecracker_bernice_hupp",
    bitten = "bitten_hershel_combs",
    dads = "dad_joke_feud",
    preacher = "radio_preacher_dwayne",
    gunshop = "gunshop_bob_kenley",
    soldier = "forest_soldier_hatcher",
    hitchhiker = "hitchhiker_ruth_ann",
    throwlab = "firecracker_bernice_hupp",
    bittenkill = "bitten_hershel_combs",
}
local MODULES = {
    throwlab = "OddballFirecracker",
    bittenkill = "OddballBitten",
    firecracker = "OddballFirecracker", bitten = "OddballBitten",
    dads = "OddballDads", preacher = "OddballPreacher",
    gunshop = "OddballGunShop", soldier = "OddballSoldier",
    hitchhiker = "OddballHitchhiker",
}
local ROOMS = { bitten = "bathroom", bittenkill = "bathroom", dads = "livingroom",
    gunshop = "gunstore" }

local function SCX() return SurvivorCompanion end
local function U() return SurvivorCompanion.GameplayUtil end

local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...)
        return object[method](object, ...)
    end, ...)
    if okay then return value end
    return nil
end

local function clean(text)
    return (string.gsub(tostring(text or ""), "[|\r\n]", " "))
end

local function trace(tag, text)
    print("SC_REAL_SANDBOX|FOLK|" .. tostring(tag) .. "|" .. clean(text))
end

local function hours()
    local time = type(getGameTime) == "function" and getGameTime() or nil
    return tonumber(call(time, "getWorldAgeHours"))
end

local function round(value)
    value = tonumber(value)
    if not value then return "nil" end
    return string.format("%.1f", value)
end

local function sq(x, y, z)
    if not x or not y then return nil end
    return U().gridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
end

local function roomName(square)
    local name = call(call(square, "getRoom"), "getName")
    return type(name) == "string" and string.lower(name) or nil
end

local function outdoor(square)
    return square ~= nil and call(square, "getRoom") == nil
end

local function teleport(player, square)
    if not square then return false end
    return pcall(function()
        player:teleportTo(square:getX() + 0.5, square:getY() + 0.5, square:getZ())
    end)
end

local function dist(a, b)
    local d = U().distance(a, b)
    return tonumber(d) or math.huge
end

-- The first square on growing rings around (cx, cy) that `accept` likes.
local function ring(cx, cy, cz, minimum, maximum, accept)
    if not cx or not cy then return nil end
    cx, cy = math.floor(cx), math.floor(cy)
    for radius = minimum, maximum do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = sq(cx + dx, cy + dy, cz)
                    if square and accept(square) then return square end
                end
            end
        end
    end
    return nil
end

local OFFSETS
local function offsets()
    if OFFSETS then return OFFSETS end
    OFFSETS = {}
    for dy = -40, 40 do
        for dx = -40, 40 do
            OFFSETS[#OFFSETS + 1] = { dx, dy, dx * dx + dy * dy }
        end
    end
    table.sort(OFFSETS, function(a, b) return a[3] < b[3] end)
    return OFFSETS
end

local function nameOf(actor)
    local forename = call(call(actor, "getDescriptor"), "getForename")
    return tostring(forename or "?")
end

local function itemType(item) return U().itemType(item) end

local function inventoryItems(actor)
    local inventory = actor and U().inventory(actor)
    -- A lived-in save's player carries hundreds of items; read them all.
    return inventory and U().inventoryItemsDeep(inventory, 4000, 6) or {}
end

local function countType(actor, kind)
    local total = 0
    for _, item in ipairs(inventoryItems(actor)) do
        if itemType(item) == kind then total = total + 1 end
    end
    return total
end

local function tagged(actor, key, value)
    local found = {}
    for _, item in ipairs(inventoryItems(actor)) do
        local data = U().modData(item)
        if type(data) == "table" and data[key] == value then found[#found + 1] = item end
    end
    return found
end

local function itemNamed(actor, name)
    for _, item in ipairs(inventoryItems(actor)) do
        if call(item, "getName") == name then return item end
    end
    return nil
end

local function pageCount(item)
    local pages = call(item, "getCustomPages")
    return tonumber(call(pages, "size")) or 0
end

local function scriptExists(kind)
    local manager = type(getScriptManager) == "function" and getScriptManager() or nil
    return call(manager, "FindItem", kind) ~= nil
end

local function firstExisting(kinds)
    for _, kind in ipairs(kinds) do
        if scriptExists(kind) then return kind end
    end
    return nil
end

-- A module's format line ("...%d...") as an anchored Lua pattern.
local function templatePattern(template)
    local escaped = string.gsub(template, "([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    escaped = string.gsub(escaped, "%%%%d", "(%%d+)")
    escaped = string.gsub(escaped, "%%%%s", "(.+)")
    return "^" .. escaped .. "$"
end

-- Lines in a module pool are plain strings or { profane, clean = ... }.
local function inPool(pool, text)
    for _, entry in ipairs(pool or {}) do
        if entry == text then return true end
        if type(entry) == "table" and (entry[1] == text or entry.clean == text) then
            return true
        end
    end
    return false
end

-- Recorders ---------------------------------------------------------------

local function recordSpeech(F)
    local utility = U()
    if F.originalSay then return end
    local original = utility.say
    F.originalSay = original
    F.speech = {}
    utility.say = function(actor, line, ...)
        local entry = { name = nameOf(actor), text = tostring(line), actor = actor,
            at = getTimestampMs and getTimestampMs() or 0 }
        F.speech[#F.speech + 1] = entry
        trace("SAY", entry.name .. ": " .. entry.text)
        return original(actor, line, ...)
    end
end

local function said(F, pool, from, actor)
    for index = from or 1, #(F.speech or {}) do
        local entry = F.speech[index]
        if (actor == nil or entry.actor == actor) and inPool(pool, entry.text) then
            return entry.text, index
        end
    end
    return nil
end

local function spokenCount(F, from, actor)
    local total = 0
    for index = from or 1, #(F.speech or {}) do
        if actor == nil or F.speech[index].actor == actor then total = total + 1 end
    end
    return total
end

local function recordRadio(F)
    if F.radioHandler then return true end
    if type(Events) ~= "table" or not Events.OnDeviceText then return false end
    F.radio = {}
    F.radioHandler = function(guid, codes, x, y, z, line)
        local entry = { guid = tostring(guid), codes = tostring(codes),
            text = tostring(line), x = x, y = y }
        F.radio[#F.radio + 1] = entry
        trace("RADIO", entry.guid .. " [" .. entry.codes .. "] @"
            .. tostring(x) .. "," .. tostring(y) .. ": " .. entry.text)
    end
    Events.OnDeviceText.Add(F.radioHandler)
    return true
end

local function heard(F, text, from)
    for index = from or 1, #(F.radio or {}) do
        local entry = F.radio[index]
        if entry.text == text or string.find(entry.text, text, 1, true) then
            return entry, index
        end
    end
    return nil
end

-- A firecracker explodes the moment it lands and is never placed as a tile
-- object; the engine's own OnThrowableExplode event is the evidence.
local function recordExplosions(F)
    if F.explosionHandler then return true end
    if type(Events) ~= "table" or not Events.OnThrowableExplode then return false end
    F.explosions = {}
    F.explosionHandler = function(trap, square)
        local weapon = call(trap, "getHandWeapon") or call(trap, "getItem")
        local entry = { item = tostring(itemType(weapon)), noise = call(trap, "getNoiseRange"),
            x = call(square, "getX"), y = call(square, "getY") }
        F.explosions[#F.explosions + 1] = entry
        trace("BANG", entry.item .. " noise=" .. tostring(entry.noise) .. " at "
            .. tostring(entry.x) .. "," .. tostring(entry.y))
    end
    Events.OnThrowableExplode.Add(F.explosionHandler)
    return true
end

local function restore(F)
    if F.originalSay then
        U().say = F.originalSay
        F.originalSay = nil
    end
    if F.explosionHandler then
        pcall(function() Events.OnThrowableExplode.Remove(F.explosionHandler) end)
        F.explosionHandler = nil
    end
    if F.radioHandler then
        pcall(function() Events.OnDeviceText.Remove(F.radioHandler) end)
        F.radioHandler = nil
    end
    if F.originalAmbient then
        SCX().Oddballs.pulse = F.originalAmbient
        F.originalAmbient = nil
    end
end

-- Shared fixture ------------------------------------------------------------

local function story(F) return F.group and F.group.oddball or nil end

local function memberActor(member)
    local SC = SCX()
    local record = member and member.actorId and SC.Registry.byId(member.actorId)
    local actor = record and record.actor
    return actor and U().isValidActor(actor) and actor or nil
end

local function actorByRole(F, role)
    for _, member in ipairs(F.group and F.group.members or {}) do
        if member.role == role then return memberActor(member) end
    end
    return nil
end

local function groupActors(group)
    local list = {}
    local ready = group ~= nil and type(group.members) == "table" and #group.members > 0
    for _, member in ipairs(group and group.members or {}) do
        local actor = memberActor(member)
        if actor then list[#list + 1] = actor else ready = false end
    end
    return list, ready
end

local function retiredAs(id)
    local ledger = SCX().Oddballs.export()
    return type(ledger) == "table" and ledger.retired and ledger.retired[id] or nil
end

local function giveRadio(player, kinds, channel)
    local kind = firstExisting(kinds)
    if not kind then return nil, "no radio item script" end
    local inventory = U().inventory(player)
    local radio = inventory and U().addItem(inventory, kind)
    if not radio then return nil, "radio item not added: " .. kind end
    call(player, "setPrimaryHandItem", radio)
    local data = call(radio, "getDeviceData")
    call(data, "setHasBattery", true)
    call(data, "setPower", 1.0)
    call(data, "setIsTurnedOn", true)
    call(data, "setChannel", channel)
    call(data, "setDeviceVolume", 0.8)
    call(data, "setMicIsMuted", false)
    call(data, "setNoTransmit", false)
    return radio, kind
end

local function radioState(radio)
    local data = call(radio, "getDeviceData")
    return "on=" .. tostring(call(data, "getIsTurnedOn"))
        .. " channel=" .. tostring(call(data, "getChannel"))
        .. " battery=" .. tostring(call(data, "getHasBattery"))
        .. " power=" .. round(call(data, "getPower"))
        .. " twoWay=" .. tostring(call(data, "getIsTwoWay"))
        .. " range=" .. tostring(call(data, "getTransmitRange"))
        .. " min=" .. tostring(call(data, "getMinChannelRange"))
        .. " max=" .. tostring(call(data, "getMaxChannelRange"))
end

local function zombiesNear(x, y, z, radius)
    local found = {}
    local cell = type(getCell) == "function" and getCell() or nil
    local list = call(cell, "getZombieList")
    local SC = SCX()
    local size = list and SC.NativeList.size(list) or 0
    for index = 0, math.min(size, 1024) - 1 do
        local zombie = SC.NativeList.get(list, index)
        local zx, zy, zz = U().position(zombie)
        if zx and math.floor(zz or 0) == math.floor(z or 0)
            and (zx - x) ^ 2 + (zy - y) ^ 2 <= radius * radius then
            found[#found + 1] = zombie
        end
    end
    return found
end

-- Explicit clone fixture: walkers near a roadside scene are removed so the
-- folk's own beats can be measured. Each removal is counted in the results.
local function clearWalkers(x, y, z, radius, keep)
    local removed = 0
    if not x then return 0 end
    for _, zombie in ipairs(zombiesNear(x, y, z, radius)) do
        if zombie ~= keep and not U().isDead(zombie) then
            pcall(function() zombie:removeFromWorld() end)
            pcall(function() zombie:removeFromSquare() end)
            removed = removed + 1
        end
    end
    return removed
end

local function spawnZombie(square, outfit)
    if not square or type(addZombiesInOutfit) ~= "function" then return nil end
    local okay, list = pcall(addZombiesInOutfit, square:getX(), square:getY(),
        square:getZ(), 1, outfit or "Redneck", 50)
    return okay and list and SCX().NativeList.get(list, 0) or nil
end

local function sitesNear(H, F, accept, budget)
    local SC = SCX()
    local list = offsets()
    F.scanIndex = F.scanIndex or 0
    F.visited = F.visited or {}
    for _ = 1, budget do
        F.scanIndex = F.scanIndex + 1
        local offset = list[F.scanIndex]
        if not offset then return nil, true end
        local square = sq(F.searchX + offset[1], F.searchY + offset[2], 0)
        if square then
            local site = accept(square)
            if site then return site, true end
        end
    end
    return nil, false
end

local bedroomHomeNear -- defined with Ruth Ann's flow below

-- Why no site turned up: road tiles, floor names and house rejections.
local function diagnoseSites(H, F)
    local SC = SCX()
    local counts = { outdoor = 0, road = 0, clearRoad = 0, rooms = 0 }
    local sprites, reasons, visited = {}, {}, {}
    local spriteCount = 0
    for _, offset in ipairs(offsets()) do
        local square = sq(F.searchX + offset[1], F.searchY + offset[2], 0)
        if square then
            if outdoor(square) then
                counts.outdoor = counts.outdoor + 1
                local name = call(call(call(square, "getFloor"), "getSprite"), "getName")
                name = type(name) == "string" and string.lower(name) or "nil"
                local prefix = string.match(name, "^(.-)_%d+$") or name
                if not sprites[prefix] and spriteCount < 10 then
                    sprites[prefix] = true
                    spriteCount = spriteCount + 1
                end
                if string.find(name, "street", 1, true) then
                    counts.road = counts.road + 1
                    if U().isClearActorSpawnSquare(square) then
                        counts.clearRoad = counts.clearRoad + 1
                    end
                end
            end
            local room = roomName(square)
            local building = room and call(square, "getBuilding")
            if building and not visited[building] and (room == ROOMS[F.target]
                or string.find(room, "butcher", 1, true) or string.find(room, "barn", 1, true)
                or string.find(room, "farmstorage", 1, true)) then
                visited[building] = true
                counts.rooms = counts.rooms + 1
                local house, why = SC.Factions.oddballHouseAt(square, H.player, true)
                local key = room .. ":" .. tostring(house and "ok" or why)
                reasons[key] = (reasons[key] or 0) + 1
                if house and F.target == "gunshop" then
                    local kinds = {}
                    for _, opening in ipairs(house.openings or {}) do
                        kinds[#kinds + 1] = tostring(opening.kind) .. "@" .. opening.x .. "," .. opening.y
                    end
                    local window = SC.Oddballs._shopWindowForTests(house,
                        { x = square:getX(), y = square:getY(), z = 0 })
                    local posts = window and SC.Oddballs._streetPostsForTests(window) or {}
                    reasons["shopWindow=" .. tostring(window and (window.x .. "," .. window.y
                        .. " out=" .. window.outX .. "," .. window.outY)) .. " posts=" .. #posts
                        .. " openings=" .. table.concat(kinds, ";")] = 1
                end
            end
        end
    end
    local parts = {}
    for key, value in pairs(counts) do parts[#parts + 1] = key .. "=" .. value end
    for key in pairs(sprites) do parts[#parts + 1] = "floor:" .. key end
    for key, value in pairs(reasons) do parts[#parts + 1] = key .. "=" .. value end
    return table.concat(parts, " ")
end

local function findSite(H, F)
    local SC = SCX()
    local target, player, definition = F.target, H.player, F.definition
    if target == "firecracker" or target == "hitchhiker" or target == "throwlab" then
        -- The debug spawner's roadside rule: any hour, seen or not.
        return sitesNear(H, F, function(square)
            if not outdoor(square) or dist(player, square) < 15 then return nil end
            local site = SC.Oddballs._siteForEbbForTests(square, player, true, true)
            if site and target == "hitchhiker" then
                -- Her stand-in home: a farmhouse with a bedroom by the road.
                local home = bedroomHomeNear(H, square:getX(), square:getY(), 14)
                if not home then return nil end
                F.standIn = home
            end
            return site
        end, 40)
    end
    if ROOMS[target] then
        return sitesNear(H, F, function(square)
            local name = roomName(square)
            if name ~= ROOMS[target] then return nil end
            local building = call(square, "getBuilding")
            if not building or F.visited[building] then return nil end
            F.visited[building] = true
            F.buildingsSeen = (F.buildingsSeen or 0) + 1
            return SC.Oddballs._siteForResidentForTests(square, player,
                definition, name, true)
        end, 400)
    end
    if target == "preacher" then
        return sitesNear(H, F, function(square)
            if not outdoor(square) or dist(player, square) < 14 then return nil end
            return SC.Oddballs._siteForRadioVanForTests(square, player, true)
        end, 300)
    end
    if target == "soldier" then
        return sitesNear(H, F, function(square)
            if not outdoor(square) or dist(player, square) < 10 then return nil end
            return SC.Oddballs._siteForForestSoldierForTests(square, player, true)
        end, 90)
    end
    return nil, true
end

-- Before the scene spawns, the observer waits somewhere sensible: outside a
-- resident's building, out of earshot of the soldier.
local function stageObserver(H, F)
    local site = F.site
    local spawn = site.spawn
    if ROOMS[F.target] then
        return teleport(H.player, ring(spawn.x, spawn.y, 0, 14, 24, function(square)
            return outdoor(square) and U().isSafeSpawnSquare(square)
        end))
    end
    if F.target == "soldier" then
        return teleport(H.player, ring(spawn.x, spawn.y, 0, 40, 60, function(square)
            return outdoor(square) and U().isSafeSpawnSquare(square)
        end))
    end
    return true
end

-- Target flows ----------------------------------------------------------------

local Flows = {}

-- Miss Liberty -------------------------------------------------------------

function Flows.firecracker(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballFirecracker
    if F.step == nil then
        F.step = "stock"
    end
    if (F.step == "stock" or F.step == "harass") and current >= (F.nextQuietAt or 0) then
        -- Keep the throws measurable; the walker step tests the flight.
        F.nextQuietAt = current + 1000
        local ax, ay, az = U().position(actor)
        F.quietRemoved = (F.quietRemoved or 0) + clearWalkers(ax, ay, az, 40)
    end
    if F.step == "stock" then
        local remaining = module.remaining(F.group)
        if remaining < 10 and current - F.stepAt < 15000 then return end
        if not need("firecracker_ten_tagged_firecrackers", remaining == 10
                and value.stockSeeded == true,
            "remaining=" .. tostring(remaining) .. " seeded=" .. tostring(value.stockSeeded)
                .. " lighter=" .. tostring(countType(actor, "Base.Lighter"))) then return end
        local ax, ay = U().position(actor)
        local stand = ring(ax, ay, 0, 9, 11, function(square)
            return outdoor(square) and U().isSafeSpawnSquare(square)
                and U().canSee(actor, square) == true
                and math.abs(math.sqrt((square:getX() + 0.5 - ax) ^ 2
                    + (square:getY() + 0.5 - ay) ^ 2) - 10) <= 1.2
        end)
        if not need("firecracker_observer_in_sight", teleport(H.player, stand),
            "clear outdoor square about 10 m from Bernice") then return end
        call(H.player, "faceThisObject", actor)
        if not need("firecracker_explosion_listener", recordExplosions(F),
            "Events.OnThrowableExplode") then return end
        F.step, F.stepAt = "harass", current
        return
    end
    if F.step == "harass" then
        if not F.toldStop and value.stage == "harass" and dist(actor, H.player) <= 10 then
            local before = #F.speech
            local accepted, reason = SC.Oddballs.storyAction(F.group.id,
                "tell_bernice_stop", H.player)
            F.toldStop = true
            check("firecracker_refuses_to_stop", accepted == true
                    and said(F, module.LINES.stop, before + 1, actor) ~= nil,
                "accepted=" .. tostring(accepted) .. " reason=" .. tostring(reason))
        end
        local trapCount = #F.explosions
        local thrown = tonumber(value.thrown) or 0
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 3000
            trace("FIRECRACKER", "stage=" .. tostring(value.stage)
                .. " thrown=" .. thrown .. " left=" .. module.remaining(F.group)
                .. " traps=" .. trapCount .. " distance=" .. round(dist(actor, H.player))
                .. " sight=" .. tostring(U().canSee(actor, H.player)))
        end
        if value.stage == "fleeing" and value.fleeReason ~= "zombies" then
            need("firecracker_harass_without_early_flight", false,
                "fled for " .. tostring(value.fleeReason) .. " after " .. thrown)
            return
        end
        if thrown >= 3 and trapCount >= 3 then
            local traps, near = {}, 0
            local px, py = U().position(H.player)
            for _, row in ipairs(F.explosions) do
                local miss = row.x and math.sqrt((row.x + 0.5 - px) ^ 2 + (row.y + 0.5 - py) ^ 2)
                if miss and miss <= 3 then near = near + 1 end
                traps[#traps + 1] = row.item .. " noise=" .. tostring(row.noise)
                    .. " miss=" .. round(miss)
            end
            if not need("firecracker_native_throws_land", module.remaining(F.group) == 10 - thrown
                    and near >= 1 and said(F, module.LINES.greet, 1, actor) ~= nil,
                "thrown=" .. thrown .. " left=" .. module.remaining(F.group)
                    .. " traps=" .. table.concat(traps, "; ") .. " walkersRemoved="
                    .. tostring(F.quietRemoved)) then return end
            F.step, F.stepAt = "zombie", current
            return
        end
        if value.stage == "fleeing" then
            -- Real walkers answered the noise before the probe sent one.
            check("firecracker_native_throws_land", thrown >= 1 and trapCount >= 1
                    and module.remaining(F.group) == 10 - thrown,
                "walkers came after " .. thrown .. " throws; traps=" .. trapCount)
            check("firecracker_flees_from_the_dead", value.fleeReason == "zombies"
                    and said(F, module.LINES.zombies, 1, actor) ~= nil,
                "reason=" .. tostring(value.fleeReason))
            F.step, F.stepAt = "flight", current
            F.naturalFlight = true
            return
        end
        if current - F.stepAt > 90000 then
            need("firecracker_native_throws_land", false, "thrown=" .. thrown
                .. " traps=" .. trapCount .. " stage=" .. tostring(value.stage)
                .. " distance=" .. round(dist(actor, H.player)))
        end
        return
    end
    if F.step == "zombie" then
        if value.stage ~= "fleeing" and not F.zombie then
            local ax, ay = U().position(actor)
            local px, py = U().position(H.player)
            local spot = ring(ax, ay, 0, 6, 9, function(square)
                return outdoor(square) and U().isSafeSpawnSquare(square)
                    and U().canSee(actor, square) == true
                    and (square:getX() - px) ^ 2 + (square:getY() - py) ^ 2 >= 36
            end)
            F.zombie = spawnZombie(spot, "Redneck")
            F.speechMark = #F.speech + 1
            if not need("firecracker_walker_spawned", F.zombie ~= nil,
                "outdoor square 6-9 m from Bernice") then return end
            return
        end
        if value.stage == "fleeing" then
            -- Her line comes with her first flight step, a beat after the stage.
            F.fledAt = F.fledAt or current
            local line = said(F, module.LINES.zombies, F.speechMark or 1, actor)
            if not line and current - F.fledAt < 8000 then return end
            local others = {}
            for index = F.speechMark or 1, #F.speech do
                if F.speech[index].actor == actor then others[#others + 1] = F.speech[index].text end
            end
            if not need("firecracker_flees_from_the_dead", value.fleeReason == "zombies"
                    and line ~= nil,
                "reason=" .. tostring(value.fleeReason) .. " thrown=" .. tostring(value.thrown)
                    .. " said=" .. table.concat(others, " | ")) then
                return
            end
            if F.zombie then pcall(function() F.zombie:Kill(H.player) end) end
            F.step, F.stepAt = "flight", current
            return
        end
        if current - F.stepAt > 20000 then
            need("firecracker_flees_from_the_dead", false, "stage=" .. tostring(value.stage)
                .. " zombie_distance=" .. round(dist(actor, F.zombie)))
        end
        return
    end
    if F.step == "flight" then
        if F.group.lifecycle == "destroyed" then
            local member = F.group.members and F.group.members[1]
            check("firecracker_runs_off_unseen", retiredAs(F.id) == "ran_off"
                    and member and member.hibernated == true,
                "retired=" .. tostring(retiredAs(F.id)) .. " natural="
                    .. tostring(F.naturalFlight == true))
            setPhase("folk_batch_done", current)
            return
        end
        if current >= (F.nextHideAt or 0) then
            -- Break the line of sight the way a player would: go indoors.
            F.nextHideAt = current + 12000
            F.hideTries = (F.hideTries or 0) + 1
            local ax, ay = U().position(actor)
            local tries = F.hideTries
            local hide = ring(ax, ay, 0, 14 + tries * 4, 40 + tries * 4, function(square)
                return not outdoor(square) and U().isSafeSpawnSquare(square)
            end)
            teleport(H.player, hide)
        end
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 3000
            local ax, ay, az = U().position(actor)
            trace("FIRECRACKER", "fleeing stage=" .. tostring(value.stage)
                .. " sight=" .. tostring(U().canSee(H.player, actor))
                .. " unseenSince=" .. tostring(value.unseenSince)
                .. " distance=" .. round(dist(actor, H.player))
                .. " walkers12m=" .. tostring(ax and #zombiesNear(ax, ay, az, 12)))
        end
        if current - F.stepAt > 75000 then
            need("firecracker_runs_off_unseen", false, "lifecycle=" .. tostring(F.group.lifecycle)
                .. " stage=" .. tostring(value.stage) .. " sight="
                .. tostring(U().canSee(H.player, actor)))
        end
        return
    end
end

-- Throw lab (diagnostic, not one of the seven): the same native Throw from
-- the player and from Bernice at open ground, each projectile traced per tick.
local function trackProjectiles(F)
    local cell = getCell()
    local list = call(cell, "getObjectList")
    local SC = SCX()
    local size = list and SC.NativeList.size(list) or 0
    F.projectiles = F.projectiles or {}
    for index = 0, math.min(size, 2048) - 1 do
        local object = SC.NativeList.get(list, index)
        if object and U().instanceOf(object, "IsoMolotovCocktail") then
            local key = tostring(object)
            if not F.projectiles[key] then
                F.projectiles[key] = { object = object, label = F.throwLabel, frames = 0 }
            end
        end
    end
    for key, row in pairs(F.projectiles) do
        if not row.done then
            local object = row.object
            row.frames = row.frames + 1
            local destroyed = call(object, "isDestroyed") == true
            if row.frames <= 40 or destroyed then
                trace("PROJECTILE", tostring(row.label) .. " f=" .. row.frames
                    .. " at=" .. round(call(object, "getX")) .. "," .. round(call(object, "getY"))
                    .. "," .. round(call(object, "getZ")) .. " next="
                    .. round(call(object, "getNextX")) .. "," .. round(call(object, "getNextY"))
                    .. " collided=" .. tostring(call(object, "isCollidedThisFrame"))
                    .. " N/S/E/W=" .. tostring(call(object, "isCollidedN")) .. "/"
                    .. tostring(call(object, "isCollidedS")) .. "/" .. tostring(call(object, "isCollidedE"))
                    .. "/" .. tostring(call(object, "isCollidedW")) .. " destroyed=" .. tostring(destroyed))
            end
            if destroyed or row.frames > 200 then row.done = true end
        end
    end
end

function Flows.throwlab(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local actor = F.actor
    if F.step == nil then
        F.step = "setup"
        if SC.Scheduler then SC.Scheduler.unregister("decision") end
    end
    trackProjectiles(F)
    if F.step == "setup" then
        if current - F.stepAt < 4000 then return end
        recordExplosions(F)
        local ax, ay = U().position(actor)
        local stand = ring(ax, ay, 0, 9, 11, function(square)
            return outdoor(square) and U().isSafeSpawnSquare(square)
                and U().canSee(actor, square) == true
        end)
        teleport(H.player, stand)
        F.shots = {}
        local px, py = stand:getX(), stand:getY()
        -- Player shot: across open ground away from Bernice.
        F.shots[#F.shots + 1] = { who = "player", dx = px - ax, dy = py - ay }
        for _, offset in ipairs({ { 8, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 } }) do
            F.shots[#F.shots + 1] = { who = "bernice", dx = offset[1], dy = offset[2] }
        end
        F.shots[#F.shots + 1] = { who = "bernice_at_player" }
        F.shotIndex, F.nextShotAt = 0, current + 2000
        F.step = "shots"
        return
    end
    if F.step == "shots" then
        if current < F.nextShotAt then return end
        F.shotIndex = F.shotIndex + 1
        local shot = F.shots[F.shotIndex]
        if not shot then
            local rows = {}
            for _, row in ipairs(F.explosions or {}) do
                rows[#rows + 1] = tostring(row.x) .. "," .. tostring(row.y)
            end
            result("PASS", "throwlab_complete", "explosions=" .. table.concat(rows, " "))
            setPhase("folk_batch_done", current)
            return
        end
        local thrower = shot.who == "player" and H.player or actor
        local tx, ty
        local sx, sy, sz = U().position(thrower)
        if shot.who == "bernice_at_player" then
            tx, ty = U().position(H.player)
        elseif shot.who == "player" then
            tx, ty = sx + shot.dx * 0.8, sy + shot.dy * 0.8
        else
            tx, ty = sx + shot.dx, sy + shot.dy
        end
        local target = sq(tx, ty, sz)
        if shot.who ~= "player" and not F.laneDumped then
            -- What stands on the first squares of her northern lane.
            F.laneDumped = true
            local SC = SCX()
            local fx, fy = math.floor(sx), math.floor(sy)
            local previous = sq(fx, fy, sz)
            for step = 0, 3 do
                local square = sq(fx, fy - step, sz)
                local names = {}
                local objects = call(square, "getObjects")
                for index = 0, math.min(objects and SC.NativeList.size(objects) or 0, 12) - 1 do
                    local object = SC.NativeList.get(objects, index)
                    names[#names + 1] = tostring(call(call(object, "getSprite"), "getName"))
                        .. "(" .. tostring(call(object, "getType")) .. ")"
                end
                trace("LANE", tostring(fx) .. "," .. tostring(fy - step)
                    .. " solid=" .. tostring(call(square, "isSolid"))
                    .. " solidTrans=" .. tostring(call(square, "isSolidTrans"))
                    .. " blockedTo=" .. tostring(step > 0 and call(previous, "isBlockedTo", square))
                    .. " collideN=" .. tostring(call(square, "testCollideAdjacent", actor, 0, -1, 0))
                    .. " vehicle=" .. tostring(call(square, "getVehicleContainer") ~= nil)
                    .. " objects=" .. table.concat(names, ";"))
                previous = square
            end
        end
        local inventory = U().inventory(thrower)
        local item = U().addItem(inventory, "Base.Firecracker")
        call(thrower, "setPrimaryHandItem", item)
        call(thrower, "setAttackTargetSquare", target)
        F.throwLabel = shot.who .. "->" .. tostring(target and target:getX()) .. ","
            .. tostring(target and target:getY())
        local okay, failure = pcall(function() thrower:Throw(item) end)
        trace("THROWLAB", F.throwLabel .. " from=" .. round(sx) .. "," .. round(sy)
            .. " ok=" .. tostring(okay) .. " " .. tostring(failure)
            .. " targetFree=" .. tostring(target and U().isSafeSpawnSquare(target)))
        F.nextShotAt = current + 4000
        return
    end
end

-- Hershel ------------------------------------------------------------------

local function forearm(actor)
    local body = call(actor, "getBodyDamage")
    return body and BodyPartType and call(body, "getBodyPart", BodyPartType.ForeArm_L) or nil
end

local function infectionDetail(actor)
    local body = call(actor, "getBodyDamage")
    return "infected=" .. tostring(call(body, "IsInfected"))
        .. " level=" .. round(call(body, "getInfectionLevel"))
        .. " started=" .. round(call(body, "getInfectionTime"))
        .. " duration=" .. round(call(body, "getInfectionMortalityDuration"))
        .. " survived=" .. round(call(actor, "getHoursSurvived"))
        .. " percent=" .. round(SCX().OddballBitten.infectionPercent(actor))
end

function Flows.bitten(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballBitten
    if F.step == nil then F.step = "setup" end
    if F.step == "setup" then
        if value.biteApplied ~= true and current - F.stepAt < 15000 then return end
        local part = forearm(actor)
        local notebook = itemNamed(actor, "Hershel's count")
        -- A dressing hides the bitten flag; the bite time is the native record.
        if not need("bitten_native_bite_and_notebook", (tonumber(call(part, "getBiteTime")) or 0) > 0
                and call(part, "bandaged") == true and notebook ~= nil
                and pageCount(notebook) == 9,
            "biteTime=" .. round(call(part, "getBiteTime")) .. " infectedPart="
                .. tostring(call(part, "IsInfected")) .. " bandaged="
                .. tostring(call(part, "bandaged")) .. " notebook=" .. tostring(notebook)
                .. " pages=" .. tostring(notebook and pageCount(notebook))) then return end
        check("bitten_zombie_shelter", call(actor, "isZombiesDontAttack") == true,
            "the dead leave him alone while he waits")
        F.step, F.stepAt = "sit", current
        return
    end
    if F.step == "sit" then
        if call(actor, "isSitOnGround") == true then
            check("bitten_sits_on_the_floor", true, "isSitOnGround after "
                .. tostring(current - F.stepAt) .. " ms")
            F.infectionStart = { at = current, percent = module.infectionPercent(actor),
                survived = tonumber(call(actor, "getHoursSurvived")) }
            trace("HERSHEL", infectionDetail(actor))
            local ax, ay, az = U().position(actor)
            local room = call(U().squareOf(actor), "getRoom")
            local stand = ring(ax, ay, az, 1, 4, function(square)
                return call(square, "getRoom") == room and U().isSafeSpawnSquare(square)
                    and U().canSee(actor, square) == true
                    and math.abs(square:getX() + 0.5 - ax) + math.abs(square:getY() + 0.5 - ay) >= 1
            end)
            if not need("bitten_observer_enters_bathroom", teleport(H.player, stand),
                "square in his room within 4 m") then return end
            call(H.player, "faceThisObject", actor)
            F.speechMark = #F.speech + 1
            F.step, F.stepAt = "greet", current
            return
        end
        if current - F.stepAt > 45000 then
            local queue = ISTimedActionQueue and ISTimedActionQueue.getTimedActionQueue
                and ISTimedActionQueue.getTimedActionQueue(actor)
            need("bitten_sits_on_the_floor", false, "sitOnGround="
                .. tostring(call(actor, "isSitOnGround")) .. " queue="
                .. tostring(queue and queue.current) .. " furniture="
                .. tostring(SC.NativeActions and SC.NativeActions.furnitureStatus
                    and SC.NativeActions.furnitureStatus(actor)))
        end
        return
    end
    if F.step == "greet" then
        local greeted = said(F, module.LINES.greet, F.speechMark, actor)
        local intro = said(F, module.LINES.intro, F.speechMark, actor)
        if greeted and intro then
            check("bitten_greets_and_introduces", value.stage == "pleading",
                "greet=" .. greeted .. " | intro=" .. intro)
            local options = SC.Oddballs.menuOptions(F.group, H.player) or {}
            local ids = {}
            for _, option in ipairs(options) do ids[#ids + 1] = tostring(option.id) end
            if not need("bitten_menu_offers_mercy", #options == 5,
                table.concat(ids, ",")) then return end
            local lines = {}
            for _, action in ipairs({ "ask_hershel_bite", "ask_hershel_count", "sit_with_hershel" }) do
                local before = #F.speech
                local accepted, reason = SC.Oddballs.storyAction(F.group.id, action, H.player)
                lines[#lines + 1] = action .. "=" .. tostring(accepted) .. "/" .. tostring(reason)
                    .. ":" .. tostring(F.speech[before + 1] and F.speech[before + 1].text)
                if accepted ~= true or #F.speech <= before then
                    need("bitten_answers_questions", false, table.concat(lines, "; "))
                    return
                end
            end
            check("bitten_answers_questions", true, table.concat(lines, "; "))
            F.step, F.stepAt = "infection", current
            return
        end
        if current - F.stepAt > 15000 then
            need("bitten_greets_and_introduces", false, "stage=" .. tostring(value.stage)
                .. " sight=" .. tostring(U().canSee(actor, H.player))
                .. " distance=" .. round(dist(actor, H.player)))
        end
        return
    end
    if F.step == "infection" then
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 10000
            trace("HERSHEL", infectionDetail(actor))
        end
        if current - F.infectionStart.at < 60000 then return end
        local percent = module.infectionPercent(actor)
        local survived = tonumber(call(actor, "getHoursSurvived"))
        if not need("bitten_infection_runs_on_engine_clock", percent > 0
                and percent > (F.infectionStart.percent or 0)
                and survived and F.infectionStart.survived
                and survived > F.infectionStart.survived
                and not U().isDead(actor),
            "start=" .. round(F.infectionStart.percent) .. "% now=" .. round(percent)
                .. "% " .. infectionDetail(actor)) then return end
        local before = #F.speech
        local ax, ay, az = U().position(actor)
        F.deathAt = { x = ax, y = ay, z = az }
        if F.target == "bittenkill" then
            -- Not his mercy: the player simply kills him. Only the death
            -- hook stands between this body and getting up.
            local killed = pcall(function() actor:Kill(H.player) end)
            if not need("bitten_killed_outright", killed, "IsoGameCharacter.Kill") then return end
        else
            local accepted, reason = SC.Oddballs.storyAction(F.group.id, "mercy_hershel", H.player)
            if not need("bitten_mercy_accepted", accepted == true and value.stage == "dying"
                    and said(F, module.LINES.mercy, before + 1, actor) ~= nil,
                "accepted=" .. tostring(accepted) .. " reason=" .. tostring(reason)) then return end
        end
        F.step, F.stepAt = "death", current
        return
    end
    if F.step == "death" then
        local dead = U().isDead(actor) or call(actor, "isDead") == true
        if not F.deadAt and dead then
            F.deadAt = current
            check("bitten_mercy_kills", true, "dead after " .. (current - F.stepAt) .. " ms")
        end
        if not F.deadAt then
            if current - F.stepAt > 8000 then
                need("bitten_mercy_kills", false, "isDead=" .. tostring(call(actor, "isDead")))
            end
            return
        end
        local p = F.deathAt
        local body
        for dx = -1, 1 do
            for dy = -1, 1 do
                body = body or call(sq(p.x + dx, p.y + dy, p.z), "getDeadBody")
            end
        end
        local risen = zombiesNear(p.x, p.y, p.z, 3)
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 5000
            local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or {}
            trace("HERSHEL", "body=" .. tostring(body ~= nil) .. " reanimateAt="
                .. round(call(body, "getReanimateTime")) .. " now=" .. round(hours())
                .. " fakeDead=" .. tostring(call(body, "isFakeDead"))
                .. " zombiesNear=" .. #risen .. " reanimateSetting=" .. tostring(lore.Reanimate)
                .. " transmission=" .. tostring(lore.Transmission)
                .. " lifecycle=" .. tostring(F.group.lifecycle))
        end
        if #risen > 0 then
            need("bitten_stays_down", false, "a walker stands where Hershel died after "
                .. (current - F.deadAt) .. " ms; laidToRest=" .. tostring(value.laidToRest))
            return
        end
        -- Unhooked, he rose two seconds after death live. Two minutes is ample.
        if current - F.deadAt > 120000 then
            check("bitten_stays_down", body ~= nil and value.laidToRest == true,
                "body still on the floor after 120 s; laidToRest=" .. tostring(value.laidToRest)
                    .. " reanimateAt=" .. round(call(body, "getReanimateTime"))
                    .. " story=" .. tostring(retiredAs(F.id)))
            setPhase("folk_batch_done", current)
        end
        return
    end
end

Flows.bittenkill = Flows.bitten

-- Gary and Ron ---------------------------------------------------------------

function Flows.dads(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local module = SC.OddballDads
    local gary, ron = actorByRole(F, "gary"), actorByRole(F, "ron")
    if F.step == nil then F.step = "setup" end
    if F.step == "setup" then
        local ready = value.garySeeded == true and value.ronSeeded == true
        if not ready and current - F.stepAt < 15000 then return end
        local standings = ron and tagged(ron, "lfDadsStandingsGroupId", F.group.id)[1]
        if not need("dads_kit_in_hand", ready and gary and ron
                and itemType(call(gary, "getPrimaryHandItem")) == "Base.Golfclub"
                and itemType(call(ron, "getPrimaryHandItem")) == "Base.BaseballBat"
                and #tagged(gary, "lfDadsBeerGroupId", F.group.id) == 1
                and #tagged(ron, "lfDadsBeerGroupId", F.group.id) == 1
                and standings ~= nil,
            "gary=" .. tostring(itemType(call(gary, "getPrimaryHandItem")))
                .. " ron=" .. tostring(itemType(call(ron, "getPrimaryHandItem")))
                .. " standings=" .. tostring(standings ~= nil)
                .. " page=" .. tostring(call(standings, "seePage", 1))) then return end
        local gx, gy, gz = U().position(gary)
        local rx, ry = U().position(ron)
        local room = call(U().squareOf(gary), "getRoom")
        local stand = ring((gx + rx) / 2, (gy + ry) / 2, gz, 1, 5, function(square)
            return call(square, "getRoom") == room and U().isSafeSpawnSquare(square)
                and U().canSee(gary, square) == true and U().canSee(ron, square) == true
                and dist(gary, square) >= 1.2 and dist(ron, square) >= 1.2
        end)
        if not need("dads_observer_enters_living_room", teleport(H.player, stand),
            "square in their room with both in sight") then return end
        call(H.player, "faceThisObject", gary)
        F.verdicts, F.speechMark = 0, #F.speech + 1
        F.step, F.stepAt = "contest", current
        return
    end
    if F.step == "contest" then
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 5000
            trace("DADS", "stage=" .. tostring(value.stage) .. " awaiting="
                .. tostring(value.awaitingVerdict) .. " jokes=" .. tostring(value.roundJokes)
                .. " score=" .. tostring(value.score and value.score.gary) .. "-"
                .. tostring(value.score and value.score.ron) .. " rounds="
                .. tostring(value.rounds and value.rounds.gary) .. "-"
                .. tostring(value.rounds and value.rounds.ron))
        end
        if not F.askedScore and value.stage == "contest" then
            local before = #F.speech
            local accepted = SC.Oddballs.storyAction(F.group.id, "ask_dads_score", H.player)
            F.askedScore = true
            check("dads_report_the_score", accepted == true and F.speech[before + 1] ~= nil
                    and F.speech[before + 1].actor == ron,
                tostring(F.speech[before + 1] and F.speech[before + 1].text))
        end
        if value.awaitingVerdict == true and current >= (F.nextVerdictAt or 0) then
            local ids = {}
            for _, option in ipairs(SC.Oddballs.menuOptions(F.group, H.player) or {}) do
                ids[option.id] = true
            end
            local setups, punches = 0, 0
            for index = F.speechMark, #F.speech do
                local text = F.speech[index].text
                for _, role in ipairs({ "gary", "ron" }) do
                    for _, joke in ipairs(module.JOKES[role]) do
                        if joke[1] == text then setups = setups + 1 end
                        if joke[2] == text then punches = punches + 1 end
                    end
                end
            end
            if not need("dads_round_of_jokes_then_verdict", ids.verdict_gary and ids.verdict_ron
                    and ids.verdict_tie and setups >= 2 and punches >= 2,
                "setups=" .. setups .. " punches=" .. punches) then return end
            local accepted, reason = SC.Oddballs.storyAction(F.group.id, "verdict_gary", H.player)
            if not need("dads_verdict_" .. (F.verdicts + 1), accepted == true,
                tostring(reason) .. " score=" .. tostring(value.score.gary)) then return end
            F.verdicts = F.verdicts + 1
            F.speechMark = #F.speech + 1
            F.nextVerdictAt = current + 1000
            if F.verdicts >= 3 then
                F.step, F.stepAt = "crowned", current
            end
            return
        end
        if current - F.stepAt > 150000 then
            need("dads_three_rounds_judged", false, "verdicts=" .. tostring(F.verdicts)
                .. " stage=" .. tostring(value.stage))
        end
        return
    end
    if F.step == "crowned" then
        if current - F.stepAt < 9000 then return end
        local beer = tagged(H.player, "lfDadsBeerGroupId", F.group.id)
        local standings = ron and tagged(ron, "lfDadsStandingsGroupId", F.group.id)[1]
        local page = tostring(call(standings, "seePage", 1))
        check("dads_champion_hands_over_his_beer", value.stage == "exhibition"
                and value.champion == "gary" and value.prizeGiven == true and #beer == 1
                and #tagged(gary, "lfDadsBeerGroupId", F.group.id) == 0,
            "stage=" .. tostring(value.stage) .. " champion=" .. tostring(value.champion)
                .. " prize=" .. tostring(value.prizeGiven) .. " playerBeer=" .. #beer)
        check("dads_standings_page_rewritten", string.find(page, "Gary 44", 1, true) ~= nil,
            page)
        check("dads_champion_and_loser_lines",
            said(F, module.LINES.garyChampion, F.speechMark - 1, gary) ~= nil
                and said(F, module.LINES.ronLoser, F.speechMark - 1, ron) ~= nil,
            "lines after the third verdict=" .. spokenCount(F, F.speechMark - 1))
        setPhase("folk_batch_done", current)
        return
    end
end

-- Dwayne ---------------------------------------------------------------------

function Flows.preacher(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballPreacher
    if F.step == nil then F.step = "van" end
    if F.step == "van" then
        if value.notebookSeeded ~= true and current - F.stepAt < 15000 then return end
        local van = value.vanSqlId and SC.Vehicle.loadedBySqlId(tonumber(value.vanSqlId))
        local vx, vy = U().position(van)
        local site = value.site and value.site.van or {}
        local part = call(van, "getPartById", "Radio")
        local data = call(part, "getDeviceData")
        if not need("preacher_station_van_spawned", van ~= nil
                and string.find(tostring(call(van, "getScriptName")), "VanRadio", 1, true) ~= nil
                and vx and (vx - site.x) ^ 2 + (vy - site.y) ^ 2 <= 16,
            "attempted=" .. tostring(value.vanAttempted) .. " sqlId=" .. tostring(value.vanSqlId)
                .. " script=" .. tostring(call(van, "getScriptName"))
                .. " at=" .. round(vx) .. "," .. round(vy) .. " site=" .. tostring(site.x)
                .. "," .. tostring(site.y)) then return end
        check("preacher_van_radio_sets_range", tonumber(call(data, "getTransmitRange")) ~= nil
                and module.transmitRange(value) == math.floor(tonumber(call(data, "getTransmitRange")) or -1),
            "partRange=" .. tostring(call(data, "getTransmitRange")) .. " used="
                .. tostring(module.transmitRange(value)))
        local binder = itemNamed(actor, "Reverend Mabry's last sermons")
        check("preacher_binder_of_sermons", binder ~= nil and pageCount(binder) == 12,
            "pages=" .. tostring(binder and pageCount(binder)))
        local radio, kind = giveRadio(H.player, { "Base.RadioRed", "Base.RadioBlack" }, 103400)
        F.radioItem = radio
        if not need("preacher_listener_radio_ready", radio ~= nil
                and tonumber(call(call(radio, "getDeviceData"), "getChannel")) == 103400
                and call(call(radio, "getDeviceData"), "getIsTurnedOn") == true,
            tostring(kind) .. " " .. radioState(radio)) then return end
        if not need("preacher_radio_listener", recordRadio(F), "Events.OnDeviceText") then return end
        F.step, F.stepAt = "slot", current
        return
    end
    if F.step == "slot" then
        if value.lastSlot == nil then
            if current - F.stepAt > 15000 then
                need("preacher_schedule_started", false, "lastSlot never set")
            end
            return
        end
        -- Skip the clock to his next slot: the schedule decides only when.
        value.lastSlot = value.lastSlot - 24
        F.radioMark = #F.radio + 1
        F.step, F.stepAt = "airing", current
        return
    end
    if F.step == "airing" then
        local airing = value.airing
        if airing and not F.airingLines then
            F.airingLines = {}
            for index, line in ipairs(airing.lines or {}) do F.airingLines[index] = line end
            F.airingCode = airing.code
        end
        local count = 0
        for _, line in ipairs(F.airingLines or {}) do
            if heard(F, line, F.radioMark) then count = count + 1 end
        end
        if count >= 2 then
            check("preacher_sermon_reaches_a_radio", true, tostring(F.airingCode) .. " heard "
                .. count .. " of " .. #F.airingLines .. " lines on 103.4 so far")
            F.step, F.stepAt = "meet", current
            return
        end
        if current - F.stepAt > 40000 then
            need("preacher_sermon_reaches_a_radio", false, "airing=" .. tostring(F.airingCode)
                .. " index=" .. tostring(airing and airing.index) .. " heardTotal="
                .. tostring(#F.radio) .. " " .. radioState(F.radioItem))
        end
        return
    end
    if F.step == "meet" then
        if not F.walkedUp then
            local ax, ay, az = U().position(actor)
            local stand = ring(ax, ay, az, 2, 4, function(square)
                return outdoor(square) and U().isSafeSpawnSquare(square)
                    and U().canSee(actor, square) == true
            end)
            if not need("preacher_observer_walks_up", teleport(H.player, stand),
                "outdoor square near Dwayne") then return end
            call(H.player, "faceThisObject", actor)
            F.walkedUp, F.speechMark = true, #F.speech + 1
            return
        end
        if not (value.met == true and said(F, module.LINES.greet2, F.speechMark, actor)) then
            if current - F.stepAt > 15000 then
                need("preacher_greets_in_person", false, "met=" .. tostring(value.met))
            end
            return
        end
        check("preacher_greets_in_person", true, said(F, module.LINES.greet, F.speechMark, actor))
        local kind = firstExisting({ "Base.BookCooking1", "Base.Book_Cooking1", "Base.BookMechanic1" })
        local book = kind and U().addItem(U().inventory(H.player), kind)
        local offered
        for _, option in ipairs(SC.Oddballs.menuOptions(F.group, H.player) or {}) do
            if option.id == "give_dwayne_book" then offered = option end
        end
        if not need("preacher_offers_to_read_a_book", book ~= nil and offered ~= nil
                and offered.enabled == true, tostring(kind) .. " label="
                .. tostring(offered and offered.label)) then return end
        -- He takes the first book the player carries, which in a lived-in
        -- save need not be the one the probe added. Count every book.
        local function books(holder)
            local total = 0
            for _, item in ipairs(inventoryItems(holder)) do
                local itemKind = tostring(itemType(item))
                if string.find(itemKind, "^Base%.Book") or string.find(itemKind, "^Base%.Paperback")
                    or string.find(itemKind, "^Base%.Magazine") or string.find(itemKind, "^Base%.Comic") then
                    total = total + 1
                end
            end
            return total
        end
        local dwayneBefore, playerBefore = books(actor), books(H.player)
        local accepted, reason = SC.Oddballs.storyAction(F.group.id, "give_dwayne_book", H.player)
        check("preacher_takes_the_book", accepted == true and books(actor) == dwayneBefore + 1
                and books(H.player) == playerBefore - 1 and value.bookCategory ~= nil,
            tostring(reason) .. " category=" .. tostring(value.bookCategory)
                .. " label=" .. tostring(offered.label))
        local asked = SC.Oddballs.storyAction(F.group.id, "ask_dwayne_reverend", H.player)
        check("preacher_answers_about_the_reverend", asked == true, "menu line")
        setPhase("folk_batch_done", current)
        return
    end
end

-- Bob Kenley -----------------------------------------------------------------

local function shopPosts(value, player)
    local seen, unseen = 0, 0
    local index = math.floor(tonumber(call(player, "getPlayerNum")) or 0)
    for _, post in ipairs(value.site and value.site.hordeSpawns or {}) do
        local square = sq(post.x, post.y, post.z)
        if square and (call(square, "isCanSee", index) == true
            or U().canSee(player, square) == true) then
            seen = seen + 1
        else
            unseen = unseen + 1
        end
    end
    return seen, unseen
end

local function taggedZombies(groupId)
    local found = {}
    local cell = type(getCell) == "function" and getCell() or nil
    local list = call(cell, "getZombieList")
    local SC = SCX()
    local size = list and SC.NativeList.size(list) or 0
    for index = 0, math.min(size, 1024) - 1 do
        local zombie = SC.NativeList.get(list, index)
        local data = zombie and U().modData(zombie)
        if type(data) == "table" and data.lfGunShopZombieGroupId == groupId
            and not U().isDead(zombie) then
            found[#found + 1] = zombie
        end
    end
    return found
end

function Flows.gunshop(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballGunShop
    if F.step == nil then F.step = "setup" end
    if F.step == "setup" then
        if value.rewardSeeded ~= true and current - F.stepAt < 15000 then return end
        local reward = tagged(actor, "lfGunShopGroupId", F.group.id)
        local function objectAt(post)
            local objects = post and call(sq(post.x, post.y, post.z), "getObjects")
            return objects and SC.NativeList.get(objects, post.objectIndex) or nil
        end
        local window = objectAt(value.site.partyWindow)
        local door = objectAt(value.site.partyDoor)
        F.locked = value.site.partyWindow == nil
        if not need("gunshop_bob_armed_and_stocked",
                itemType(call(actor, "getPrimaryHandItem")) == "Base.Shotgun" and #reward == 4,
                "primary=" .. tostring(itemType(call(actor, "getPrimaryHandItem")))
                    .. " reward=" .. #reward) then return end
        if F.locked then
            -- No sound glass in this store: he has locked himself in.
            if not need("gunshop_locked_himself_in", value.lockedIn == true
                    and door ~= nil and call(door, "isLocked") == true and call(door, "IsOpen") ~= true,
                "door=" .. tostring(door) .. " locked=" .. tostring(call(door, "isLocked"))
                    .. " doorsLocked=" .. tostring(value.doorsLocked)) then return end
        elseif not need("gunshop_front_glass", window ~= nil and U().instanceOf(window, "IsoWindow")
                and call(window, "isSmashed") ~= true, "window=" .. tostring(window)) then
            return
        end
        F.window, F.door = window, door
        local ax, ay, az = U().position(actor)
        local room = call(U().squareOf(actor), "getRoom")
        local stand = ring(ax, ay, az, 2, 6, function(square)
            return call(square, "getRoom") == room and U().isSafeSpawnSquare(square)
                -- The smallest gun store is three meters wide.
                and U().canSee(actor, square) == true and dist(actor, square) >= 1.5
        end)
        if not need("gunshop_observer_walks_in", teleport(H.player, stand),
            "square in the shop within 6 m of Bob") then return end
        if F.locked and F.door then
            -- The player forced his street door to get in and left it open.
            call(F.door, "setLockedByKey", false)
            call(F.door, "setLocked", false)
            if call(F.door, "IsOpen") ~= true then call(F.door, "ToggleDoorSilent") end
        end
        call(H.player, "faceThisObject", actor)
        F.speechMark = #F.speech + 1
        F.step, F.stepAt = "greet", current
        return
    end
    if F.step == "greet" then
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 3000
            local seen, unseen = shopPosts(value, H.player)
            trace("BOB", "stage=" .. tostring(value.stage) .. " smashAt="
                .. tostring(value.smashAt and value.smashAt - current) .. " attempts="
                .. tostring(value.smashAttempts) .. " posts seen=" .. seen .. " unseen=" .. unseen)
        end
        if value.stage == "siege" then
            local horde = taggedZombies(F.group.id)
            if F.locked then
                check("gunshop_dead_come_through_his_door", value.siegeVia == "door"
                        and value.spawned == 5 and #horde == 5
                        and said(F, module.LINES.safeLocked, F.speechMark, actor) ~= nil
                        and said(F, module.LINES.doorOpen, F.speechMark, actor) ~= nil,
                    "via=" .. tostring(value.siegeVia) .. " spawned=" .. tostring(value.spawned)
                        .. " live=" .. #horde)
            else
                check("gunshop_glass_gives_way", call(F.window, "isSmashed") == true
                        and value.spawned == 5 and #horde == 5
                        and said(F, module.LINES.smash, F.speechMark, actor) ~= nil
                        and said(F, module.LINES.safe, F.speechMark, actor) ~= nil,
                    "smashed=" .. tostring(call(F.window, "isSmashed")) .. " spawned="
                        .. tostring(value.spawned) .. " live=" .. #horde)
            end
            F.step, F.stepAt = "siege", current
            return
        end
        if value.stage == "quiet" then
            local seen, unseen = shopPosts(value, H.player)
            local post = value.site.partyWindow or value.site.partyDoor
            local objects = post and call(sq(post.x, post.y, post.z), "getObjects")
            local now = objects and SC.NativeList.get(objects, post.objectIndex) or nil
            need("gunshop_glass_gives_way", false, "stage went quiet after "
                .. tostring(value.smashAttempts) .. " attempts; posts seen=" .. seen
                .. " unseen=" .. unseen .. " smashed=" .. tostring(call(F.window, "isSmashed"))
                .. " barricaded=" .. tostring(call(F.window, "isBarricaded"))
                .. " sameObjectAtIndex=" .. tostring(now == F.window)
                .. " objectNow=" .. tostring(now))
            return
        end
        if current - F.stepAt > 70000 then
            need("gunshop_glass_gives_way", false, "stage=" .. tostring(value.stage))
        end
        return
    end
    if F.step == "siege" then
        local horde = taggedZombies(F.group.id)
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 4000
            local ammo = call(call(actor, "getPrimaryHandItem"), "getCurrentAmmoCount")
            local nearest = math.huge
            for _, zombie in ipairs(horde) do nearest = math.min(nearest, dist(actor, zombie)) end
            trace("BOB", "nearest walker=" .. round(nearest) .. " m inside="
                .. tostring(#horde > 0 and call(U().squareOf(horde[1]), "getRoom") ~= nil))
            trace("BOB", "siege killed=" .. tostring(value.killed) .. "/" .. tostring(value.spawned)
                .. " live=" .. #horde .. " bobAlive=" .. tostring(not U().isDead(actor))
                .. " ammo=" .. tostring(ammo) .. " health="
                .. round(call(call(actor, "getBodyDamage"), "getOverallBodyHealth")))
        end
        if U().isDead(actor) then
            need("gunshop_bob_survives_the_siege", false, "Bob died; killed="
                .. tostring(value.killed) .. " of " .. tostring(value.spawned))
            return
        end
        if not F.byBob and (#horde == 0 or current - F.stepAt > 90000) then
            F.byBob = tonumber(value.killed) or 0
            result("PASS", "gunshop_bob_fights_back", "Bob's own count of the dead after "
                .. (current - F.stepAt) .. " ms: " .. F.byBob .. " of " .. tostring(value.spawned))
            for _, zombie in ipairs(horde) do
                pcall(function() zombie:Kill(H.player) end)
            end
            F.killedAt = current
        end
        if value.stage == "survived" then
            F.step, F.stepAt = "reward", current
            return
        end
        if F.killedAt and current - F.killedAt > 20000 then
            need("gunshop_kills_are_counted", false, "killed=" .. tostring(value.killed)
                .. " spawned=" .. tostring(value.spawned) .. " live=" .. #horde)
        end
        return
    end
    if F.step == "reward" then
        if value.rewardGiven ~= true then
            if current - F.stepAt > 15000 then
                need("gunshop_reward_handed_over", false, "distance=" .. round(dist(actor, H.player)))
            end
            return
        end
        -- A lived-in save's player may carry .45 already; count Bob's own stock.
        local given = tagged(H.player, "lfGunShopGroupId", F.group.id)
        local kinds = {}
        for _, item in ipairs(given) do
            local kind = tostring(itemType(item))
            kinds[kind] = (kinds[kind] or 0) + 1
        end
        check("gunshop_reward_handed_over", #given == 4 and kinds["Base.Pistol2"] == 1
                and kinds["Base.45Clip"] == 2 and kinds["Base.Bullets45Box"] == 1
                and #tagged(actor, "lfGunShopGroupId", F.group.id) == 0,
            "given=" .. #given .. " pistol=" .. tostring(kinds["Base.Pistol2"])
                .. " clips=" .. tostring(kinds["Base.45Clip"]) .. " box=" .. tostring(kinds["Base.Bullets45Box"]))
        check("gunshop_bob_can_join_after", SC.Oddballs.canRecruit(F.group) == true,
            "stage=" .. tostring(value.stage))
        setPhase("folk_batch_done", current)
        return
    end
end

-- Hatcher --------------------------------------------------------------------

local function contextOption(context, prefix)
    for _, option in ipairs(context and context.options or {}) do
        if type(option) == "table" and type(option.name) == "string"
            and string.sub(option.name, 1, #prefix) == prefix then
            return option
        end
    end
    return nil
end

local function callFromMenu(H, F, label)
    local SC = SCX()
    local context = ISContextMenu and ISContextMenu.get(0, 200, 200)
    if not context then return false, "context menu unavailable" end
    SC.UIContext.fillRadioContextMenu(0, context, { F.radioItem })
    local option = contextOption(context, label)
    local names = {}
    for _, row in ipairs(context.options or {}) do
        if type(row) == "table" then names[#names + 1] = tostring(row.name) end
    end
    if not option then
        pcall(function() context:setVisible(false) end)
        return false, "options=" .. table.concat(names, " / ")
    end
    local okay, accepted, reason = pcall(option.onSelect, option.target, option.param1,
        option.param2, option.param3)
    pcall(function() context:setVisible(false) end)
    return okay and accepted == true, tostring(okay and reason or accepted)
end

local function nextDay(value)
    -- One day of contact passes between calls, and the hour's call count resets.
    value.lastTrustDay = (tonumber(value.lastTrustDay) or 0) - 1
    value.callsHour = nil
end

function Flows.soldier(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballSoldier
    if F.step == nil then F.step = "kit" end
    if F.step == "kit" then
        if value.kitSeeded ~= true and current - F.stepAt < 15000 then return end
        local worn = {}
        local wornItems = call(actor, "getWornItems")
        for index = 0, (tonumber(call(wornItems, "size")) or 0) - 1 do
            local item = call(call(wornItems, "get", index), "getItem")
            worn[tostring(itemType(item))] = true
        end
        if not need("soldier_well_kitted", itemType(call(actor, "getPrimaryHandItem")) == "Base.AssaultRifle"
                and countType(actor, "Base.556Clip") == 3 and countType(actor, "Base.WalkieTalkie5") == 1
                and countType(actor, "Base.Pistol") == 1 and countType(actor, "Base.EntrenchingTool") == 1
                and worn["Base.Vest_BulletArmy"] and worn["Base.Hat_BonnieHat_CamoGreen"],
            "primary=" .. tostring(itemType(call(actor, "getPrimaryHandItem")))
                .. " clips=" .. countType(actor, "Base.556Clip") .. " vest="
                .. tostring(worn["Base.Vest_BulletArmy"]) .. " hat="
                .. tostring(worn["Base.Hat_BonnieHat_CamoGreen"])) then return end
        local radio, kind = giveRadio(H.player, { "Base.WalkieTalkie5" }, 146600)
        F.radioItem, F.radioKind = radio, kind
        F.step, F.stepAt = "radio_ready", current
        return
    end
    if F.step == "radio_ready" then
        -- The player's equipped radio updates on its own tick after equipping.
        if module.playerRadio(H.player) == nil and current - F.stepAt < 6000 then return end
        if not need("soldier_listener_radio_ready", module.playerRadio(H.player) ~= nil,
            tostring(F.radioKind) .. " " .. radioState(F.radioItem) .. " equipped="
                .. tostring(call(H.player, "getEquipedRadio") == F.radioItem)
                .. " muted=" .. tostring(call(call(F.radioItem, "getDeviceData"), "getMicIsMuted"))
                .. " hatcherRange=" .. tostring(module.transmitRange(F.group))) then return end
        if not need("soldier_radio_listener", recordRadio(F), "Events.OnDeviceText") then return end
        F.step, F.stepAt = "identify", current
        return
    end
    if F.step == "identify" then
        local options = module.radioOptions(H.player)
        local accepted, reason = callFromMenu(H, F, "146.6: Ask who's broadcasting")
        if not need("soldier_radio_menu_calls_him", accepted and value.identified == true
                and value.trust == 1, tostring(reason) .. " options=" .. #options
                .. " distance=" .. round(dist(actor, H.player))) then return end
        F.radioMark = #F.radio + 1
        F.step, F.stepAt = "identify_reply", current
        return
    end
    if F.step == "identify_reply" then
        for index = F.radioMark, #F.radio do
            if inPool(module.LINES.identify, F.radio[index].text) then
                check("soldier_reply_on_146_6", true, F.radio[index].text)
                F.step, F.stepAt = "sitrep", current
                return
            end
        end
        if current - F.stepAt > 25000 then
            need("soldier_reply_on_146_6", false, "heard=" .. tostring(#F.radio)
                .. " pending=" .. tostring(#value.pending) .. " " .. radioState(F.radioItem))
        end
        return
    end
    if F.step == "sitrep" then
        if not F.sitrepForced then
            if value.lastSlot == nil then return end
            value.lastSlot = value.lastSlot - 24
            F.sitrepForced, F.radioMark = true, #F.radio + 1
            return
        end
        local count = templatePattern(module.LINES.count[1])
        for index = F.radioMark, #F.radio do
            local number = string.match(F.radio[index].text, count)
            if number then
                check("soldier_sitrep_counts_walkers", tonumber(number) ~= nil,
                    F.radio[index].text .. " now=" .. tostring(module.walkerCount(F.group))
                        .. " cutIn=" .. tostring(value.cutInDone))
                F.step, F.stepAt = "trust", current
                return
            end
        end
        if current - F.stepAt > 45000 then
            need("soldier_sitrep_counts_walkers", false, "pending=" .. tostring(#value.pending)
                .. " heard=" .. tostring(#F.radio))
        end
        return
    end
    if F.step == "trust" and not F.inTown then
        -- His cache goes in a house near the caller. Call from the edge of
        -- town, well inside his radio range, the way a player would.
        local spawn = value.site.spawn
        if not F.townTeleportAt then
            -- Go by coordinates first; the squares there load on arrival.
            pcall(function() H.player:teleportTo(spawn.x - 160 + 0.5, spawn.y + 0.5, 0) end)
            F.townTeleportAt = current
            return
        end
        if current - F.townTeleportAt < 3000 then return end
        local town = ring(spawn.x - 160, spawn.y, 0, 0, 30, function(square)
            return outdoor(square) and U().isSafeSpawnSquare(square)
        end)
        if not town then
            if current - F.townTeleportAt > 15000 then
                need("soldier_caller_in_town", false, "no clear square near "
                    .. tostring(spawn.x - 160) .. "," .. tostring(spawn.y))
            end
            return
        end
        teleport(H.player, town)
        F.inTown, F.townAt = true, current
        return
    end
    if F.step == "trust" then
        if current - F.townAt < 4000 then return end
        trace("HATCHER", "calling from " .. round(select(1, U().position(H.player))) .. ","
            .. round(select(2, U().position(H.player))) .. " distance=" .. round(dist(actor, H.player))
            .. " hatcherLoaded=" .. tostring(SCX().GameplayUtil.isValidActor(actor)))
        nextDay(value)
        local fence = callFromMenu(H, F, "146.6: Ask Hatcher about the fence")
        nextDay(value)
        local supplies, suppliesReason = callFromMenu(H, F, "146.6: Ask Hatcher about supplies")
        nextDay(value)
        local meet, meetReason = callFromMenu(H, F, "146.6: Ask Hatcher to meet")
        if not need("soldier_trust_grows_by_day", fence and supplies and meet
                and value.trust == 3 and value.invited == true,
            "fence=" .. tostring(fence) .. " supplies=" .. tostring(suppliesReason)
                .. " meet=" .. tostring(meetReason) .. " trust=" .. tostring(value.trust)) then
            return
        end
        F.radioMark = F.radioMark or 1
        F.step, F.stepAt = "cache_reply", current
        return
    end
    if F.step == "cache_reply" then
        local address
        local supplies = templatePattern(module.LINES.supplies[1])
        for index = F.radioMark, #F.radio do
            local text = F.radio[index].text
            if string.match(text, supplies) then address = text end
        end
        if (#value.pending == 0 or current - F.stepAt > 50000) and not F.cacheChecked then
            local heardLines = {}
            for index = F.radioMark, #F.radio do heardLines[#heardLines + 1] = F.radio[index].text end
            if not need("soldier_cache_address_on_air", address ~= nil and value.cacheGiven == true,
                tostring(address) .. " cache=" .. tostring(value.cacheGiven)
                    .. " heard=" .. table.concat(heardLines, " | ")) then return end
            F.cacheChecked = true
            -- Back to the woods by coordinates; his post loads on arrival.
            local spawn = value.site.spawn
            pcall(function() H.player:teleportTo(spawn.x - 15 + 0.5, spawn.y + 0.5, 0) end)
            F.backAt = current
            return
        end
        if F.cacheChecked and not F.backPlaced and current - F.backAt >= 3000 then
            local spawn = value.site.spawn
            F.backPlaced = teleport(H.player, ring(spawn.x, spawn.y, 0, 12, 20, function(square)
                return outdoor(square) and U().isSafeSpawnSquare(square)
            end))
        end
        if F.cacheChecked then
            local live = groupActors(F.group)[1]
            if not live or current - F.backAt < 3000 then
                if current >= (F.nextTraceAt or 0) or current - F.backAt > 45000 then
                    F.nextTraceAt = current + 5000
                    local member = F.group.members and F.group.members[1] or {}
                    local anchor = F.group.house and F.group.house.anchor
                    local detail = "hibernated=" .. tostring(member.hibernated)
                        .. " waking=" .. tostring(member.waking)
                        .. " spawnQueued=" .. tostring(member.spawnQueued)
                        .. " actorId=" .. tostring(member.actorId)
                        .. " record=" .. tostring(member.actorId and SC.Registry.byId(member.actorId) ~= nil)
                        .. " snapshot=" .. tostring(type(member.snapshot) == "table")
                        .. " spawnFailure=" .. tostring(member.spawnFailure)
                        .. " toAnchor=" .. round(anchor and dist(H.player, anchor))
                        .. " lifecycle=" .. tostring(F.group.lifecycle)
                    trace("HATCHER", detail)
                    if current - F.backAt > 45000 then
                        need("soldier_observer_walks_into_camp", false,
                            "Hatcher not back at his post; " .. detail)
                    end
                end
                return
            end
            local ax, ay, az = U().position(live)
            local stand = ring(ax, ay, az, 3, 6, function(square)
                return outdoor(square) and U().isSafeSpawnSquare(square)
                    and U().canSee(live, square) == true
            end)
            if not need("soldier_observer_walks_into_camp", teleport(H.player, stand),
                "outdoor square near Hatcher") then return end
            call(H.player, "faceThisObject", live)
            F.speechMark = #F.speech + 1
            F.step, F.stepAt = "meet", current
        end
        return
    end
    if F.step == "meet" then
        if value.met == true then
            check("soldier_invited_meeting", said(F, module.LINES.invited, F.speechMark, actor) ~= nil,
                "met=true")
            check("soldier_can_join_after_meeting", SC.Oddballs.canRecruit(F.group) == true,
                "trust=" .. tostring(value.trust))
            -- Radio discipline: four calls inside one hour earn silence.
            local ax, ay, az = U().position(actor)
            local far = ring(ax, ay, az, 40, 60, function(square)
                return outdoor(square) and U().isSafeSpawnSquare(square)
            end)
            teleport(H.player, far)
            F.step, F.stepAt = "discipline", current
            return
        end
        if current - F.stepAt > 15000 then
            need("soldier_invited_meeting", false, "met=" .. tostring(value.met)
                .. " sight=" .. tostring(U().canSee(actor, H.player)))
        end
        return
    end
    if F.step == "discipline" then
        if current - F.stepAt < 1500 then return end
        value.callsHour = nil
        local results = {}
        for _ = 1, 4 do
            local accepted, reason = callFromMenu(H, F, "146.6: Ask Hatcher for a sitrep")
            results[#results + 1] = tostring(accepted) .. "/" .. tostring(reason)
        end
        check("soldier_radio_discipline", (tonumber(value.silentUntilHour) or 0) > (hours() or 0)
                and #module.radioOptions(H.player) == 0,
            table.concat(results, "; ") .. " silentUntil=" .. round(value.silentUntilHour)
                .. " now=" .. round(hours()))
        setPhase("folk_batch_done", current)
        return
    end
end

-- Ruth Ann -------------------------------------------------------------------

local function carFootprintClear(cx, cy)
    for dx = -1, 1 do
        for dy = -2, 2 do
            local square = sq(cx + dx, cy + dy, 0)
            if not outdoor(square) or not U().isSafeSpawnSquare(square) then return false end
        end
    end
    return true
end

local function homeFromHouse(house)
    if type(house) ~= "table" or type(house.interior) ~= "table" then return nil end
    local floor, fallback
    for index = 1, math.min(#house.interior, 256) do
        local position = house.interior[index]
        local square = sq(position.x, position.y, position.z)
        if square and U().isSafeSpawnSquare(square) then
            fallback = fallback or position
            if roomName(square) == "bedroom" then floor = position break end
        end
    end
    local bedroom = floor ~= nil
    floor = floor or fallback
    if not floor or not house.anchor then return nil end
    local doors = {}
    for _, opening in ipairs(house.openings or {}) do
        if opening.kind == "door" and #doors < 6 then
            doors[#doors + 1] = { x = opening.x, y = opening.y, z = opening.z or 0,
                objectIndex = opening.objectIndex, kind = "door" }
        end
    end
    local bounds = house.bounds or {}
    return { anchor = { x = house.anchor.x, y = house.anchor.y, z = house.anchor.z or 0 },
        floor = { x = floor.x, y = floor.y, z = floor.z or 0 },
        doors = doors, bedroom = bedroom,
        bounds = { x1 = bounds.x1, y1 = bounds.y1, x2 = bounds.x2, y2 = bounds.y2 },
        address = "the house just up the road" }
end

-- A real house with a bedroom whose anchor lies within `reach` of (x, y).
bedroomHomeNear = function(H, x, y, reach)
    local seen = {}
    for radius = 1, reach do
        for dy = -radius, radius do
            for dx = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = sq(x + dx, y + dy, 0)
                    local building = call(square, "getBuilding")
                    if building and not seen[building] then
                        seen[building] = true
                        local house = SCX().Factions.oddballHouseAt(square, H.player, true)
                        local home = house and homeFromHouse(house)
                        if home and home.bedroom
                            and (home.anchor.x - x) ^ 2 + (home.anchor.y - y) ^ 2 <= reach * reach then
                            return home
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Flows.hitchhiker(H, F, current, check, result, setPhase, need)
    local SC = SCX()
    local value = story(F)
    local actor = F.actor
    local module = SC.OddballHitchhiker
    if F.step == nil then F.step = "car" end
    if actor and current >= (F.nextQuietAt or 0) then
        -- A walker in her sight blocks the unseen exit; keep the scene quiet.
        F.nextQuietAt = current + 1000
        local ax, ay, az = U().position(actor)
        F.quietRemoved = (F.quietRemoved or 0) + clearWalkers(ax, ay, az, 40)
    end
    if F.step == "car" then
        if current - F.stepAt < 3000 then return end
        check("hitchhiker_dead_ignore_her", call(actor, "isZombiesDontAttack") == true,
            "zombie shelter applied")
        local ax, ay = U().position(actor)
        local spot = ring(ax, ay, 0, 4, 7, function(square)
            return carFootprintClear(square:getX(), square:getY())
                and dist(actor, square) >= 3.5
        end)
        local okay, car = false, nil
        if spot and type(addVehicleDebug) == "function" then
            okay, car = pcall(addVehicleDebug, "Base.CarNormal", IsoDirections.N, nil, spot)
        end
        if not need("hitchhiker_fixture_car", okay and car and call(car, "getSquare") ~= nil,
            "spot=" .. tostring(spot and spot:getX()) .. "," .. tostring(spot and spot:getY())) then
            return
        end
        F.car = car
        call(car, "setAlarmed", false)
        for index = 0, (tonumber(call(car, "getPartCount")) or 0) - 1 do
            local door = call(call(car, "getPartByIndex", index), "getDoor")
            if door then call(door, "setLocked", false) end
        end
        if not need("hitchhiker_player_at_the_wheel", call(car, "enter", 0, H.player) == true
                and call(car, "getDriver") == H.player, "native driver seat") then return end
        F.speechMark = #F.speech + 1
        F.step, F.stepAt = "boarding", current
        return
    end
    if F.step == "boarding" then
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 3000
            local square, seat = SC.Vehicle.boardingSquare(actor, F.car)
            trace("RUTH", "stage=" .. tostring(value.stage) .. " distance="
                .. round(dist(actor, F.car)) .. " door=" .. round(square and dist(actor, square))
                .. " seat=" .. tostring(seat) .. " vehicle=" .. tostring(call(actor, "getVehicle") ~= nil)
                .. " nav=" .. tostring(SC.Navigation and SC.Navigation.status
                    and SC.Navigation.status(actor).phase))
        end
        if value.stage == "riding" and call(actor, "getVehicle") == F.car then
            local seat = call(F.car, "getSeat", actor)
            check("hitchhiker_boards_a_real_seat", seat ~= nil and seat ~= 0
                    and said(F, module.LINES.board, F.speechMark, actor) ~= nil,
                "seat=" .. tostring(seat) .. " after " .. (current - F.stepAt) .. " ms")
            F.step, F.stepAt = "directions", current
            return
        end
        if value.stage == "walking_off" then
            need("hitchhiker_boards_a_real_seat", false, "she gave up on the ride")
            return
        end
        if current - F.stepAt > 70000 then
            need("hitchhiker_boards_a_real_seat", false, "stage=" .. tostring(value.stage))
        end
        return
    end
    if F.step == "directions" then
        if value.home then
            local text = string.format(module.LINES.directions[1], value.home.address)
            check("hitchhiker_gives_a_real_address", said(F, { text }, F.speechMark, actor) ~= nil,
                text .. " anchor=" .. tostring(value.home.anchor.x) .. ","
                    .. tostring(value.home.anchor.y) .. " floor=" .. tostring(value.home.floor.x)
                    .. "," .. tostring(value.home.floor.y))
        elseif current - F.stepAt < 35000 then
            return
        else
            result("SKIP", "hitchhiker_gives_a_real_address", "no unclaimed house 60-160 m away")
        end
        -- The drive itself is the player's. Put her house beside the car so
        -- the arrival, the walk in and what is left there run for real.
        local cx, cy = U().position(F.car)
        local near
        if F.standIn and (F.standIn.anchor.x - cx) ^ 2 + (F.standIn.anchor.y - cy) ^ 2 <= 17 * 17 then
            near = F.standIn
        end
        local seenBuildings = {}
        for radius = 2, 17 do
            for dy = -radius, radius do
                for dx = -radius, radius do
                    if not (near and near.bedroom) and math.max(math.abs(dx), math.abs(dy)) == radius then
                        local square = sq(cx + dx, cy + dy, 0)
                        local building = call(square, "getBuilding")
                        if building and not seenBuildings[building] then
                            seenBuildings[building] = true
                            local house = SC.Factions.oddballHouseAt(square, H.player, true)
                            local home = house and homeFromHouse(house)
                            if home and (home.anchor.x - cx) ^ 2 + (home.anchor.y - cy) ^ 2 <= 17 * 17
                                and (not near or home.bedroom and not near.bedroom) then
                                near = home
                            end
                        end
                    end
                end
            end
        end
        if not need("hitchhiker_house_beside_the_car", near ~= nil
                and (near.anchor.x - cx) ^ 2 + (near.anchor.y - cy) ^ 2 <= 17 * 17,
            "house=" .. tostring(near and near.anchor.x) .. "," .. tostring(near and near.anchor.y)) then
            return
        end
        value.home = near
        F.speechMark = #F.speech + 1
        F.step, F.stepAt = "arrive", current
        return
    end
    if F.step == "arrive" then
        if current >= (F.nextTraceAt or 0) then
            F.nextTraceAt = current + 3000
            local ax, ay = U().position(actor)
            local floor = value.home and value.home.floor
            local nav = SC.Navigation and SC.Navigation.status and SC.Navigation.status(actor) or {}
            local intent = SC.Oddballs.intentFor(actor, H.player, { threats = {}, threatCount = 0 }, F.group)
            trace("RUTH", "stage=" .. tostring(value.stage) .. " inCar="
                .. tostring(call(actor, "getVehicle") ~= nil) .. " sight="
                .. tostring(U().canSee(H.player, actor)) .. " toFloor="
                .. round(ax and floor and math.sqrt((ax - floor.x) ^ 2 + (ay - floor.y) ^ 2))
                .. " intent=" .. tostring(intent and intent.mode)
                .. " nav=" .. tostring(nav.phase) .. "/" .. tostring(nav.action) .. "/" .. tostring(nav.reason)
                .. " unlocked=" .. tostring(value.doorsUnlocked) .. " bedroom=" .. tostring(value.home and value.home.bedroom)
                .. " at=" .. round(ax) .. "," .. round(ay) .. " floor=" .. tostring(floor and floor.x)
                .. "," .. tostring(floor and floor.y) .. " car=" .. round(select(1, U().position(F.car)))
                .. "," .. round(select(2, U().position(F.car)))
                .. " vehicleTx=" .. tostring(SC.Vehicle.transactionStatus and SC.Vehicle.transactionStatus(actor)
                    and SC.Vehicle.transactionStatus(actor).action))
            local navState = SC.Navigation.peek and SC.Navigation.peek(actor) or nil
            if navState then
                local search = navState.pathSearch
                local route = search and search.route
                trace("RUTHNAV", "reason=" .. tostring(navState.pathReason)
                    .. " yield=" .. tostring(navState.pathSearchYieldReason)
                    .. " expanded=" .. tostring(navState.expandedNodes)
                    .. " searchAge=" .. tostring(search and search.startedAt and current - search.startedAt)
                    .. " progressAge=" .. tostring(search and search.progressAt and current - search.progressAt)
                    .. " slice=" .. tostring(route and route.lastSliceBudgetMs) .. "/"
                    .. tostring(route and route.lastSliceBudgetReason)
                    .. " failure=" .. tostring(navState.pathFailure and navState.pathFailure.failureClass)
                    .. " plannedMs=" .. tostring(navState.lastPlanDurationMs)
                    .. " path=" .. tostring(navState.path and #navState.path)
                    .. " goal=" .. tostring(navState.goalSquare and (call(navState.goalSquare, "getX") .. ","
                        .. call(navState.goalSquare, "getY")))
                    .. " lease=" .. tostring(navState.nativeLease ~= nil)
                    .. " moveReason=" .. tostring(navState.lastMovementReason))
            end
        end
        if not F.decisionTraced and value.stage == "walking_home" and F.exitedAt and current - F.exitedAt > 5000 then
            F.decisionTraced = true
            local state = SC.Decision and type(SC.Decision.state) == "function"
                and SC.Decision.state(actor) or nil
            trace("RUTH", "decision current=" .. tostring(state and state.current)
                .. " intent=" .. tostring(state and state.intent))
        end
        if value.stage == "walking_home" and not F.exitedAt then
            F.exitedAt = current
            check("hitchhiker_gets_out_at_home", call(actor, "getVehicle") == nil
                    and said(F, module.LINES.arrive, F.speechMark, actor) ~= nil,
                "stationary car within 18 m of her house")
        end
        if value.stage == "gone_inside" or value.stage == "waiting_to_be_found" then
            local member = F.group.members and F.group.members[1]
            check("hitchhiker_gone_once_unseen", member and member.hibernated == true,
                "after " .. tostring(current - (F.exitedAt or current)) .. " ms")
            F.step, F.stepAt = "body", current
            return
        end
        if current - F.stepAt > 90000 then
            need("hitchhiker_gone_once_unseen", false, "stage=" .. tostring(value.stage)
                .. " sight=" .. tostring(actor and U().canSee(H.player, actor)))
        end
        return
    end
    if F.step == "body" then
        if value.stage ~= "waiting_to_be_found" then
            if current - F.stepAt > 70000 then
                need("hitchhiker_body_left", false, "stage=" .. tostring(value.stage)
                    .. " placed=" .. tostring(value.bodyPlaced))
            end
            return
        end
        local floor = value.home.floor
        local body
        for dx = -1, 1 do
            for dy = -1, 1 do
                body = body or call(sq(floor.x + dx, floor.y + dy, floor.z), "getDeadBody")
            end
        end
        local removal = type(SandboxVars) == "table" and tonumber(SandboxVars.HoursForCorpseRemoval) or nil
        local death = tonumber(call(body, "getDeathTime"))
        local expected = removal and removal > 0 and (hours() or 0) - removal * 0.66 or nil
        local letter
        local container = call(body, "getContainer")
        local items = call(container, "getItems")
        for index = 0, (tonumber(call(items, "size")) or 0) - 1 do
            local item = call(items, "get", index)
            if call(item, "getName") == "Ruth Ann's letter home" then letter = item end
        end
        if not need("hitchhiker_body_left", body ~= nil and value.bodyReady == true
                and letter ~= nil and call(letter, "seePage", 1) == module.LETTER,
            "body=" .. tostring(body ~= nil) .. " outfit=" .. tostring(call(body, "getOutfitName"))
                .. " letter=" .. tostring(letter ~= nil)) then return end
        check("hitchhiker_body_wears_her_clothes", call(body, "getOutfitName") == "Backpacker",
            tostring(call(body, "getOutfitName")))
        check("hitchhiker_body_already_old", expected == nil
                or (death and math.abs(death - expected) <= 1.5),
            "removalHours=" .. tostring(removal) .. " death=" .. round(death)
                .. " expected=" .. round(expected) .. " now=" .. round(hours()))
        F.body = body
        F.step, F.stepAt = "find", current
        return
    end
    if F.step == "find" then
        if not F.leftCar then
            if call(H.player, "getVehicle") ~= nil then
                if not F.exitQueued then
                    F.exitQueued = true
                    pcall(function()
                        require "Vehicles/TimedActions/ISExitVehicle"
                        ISTimedActionQueue.add(ISExitVehicle:new(H.player))
                    end)
                end
                if current - F.stepAt > 15000 then
                    need("hitchhiker_player_leaves_the_car", false, "still seated")
                end
                return
            end
            F.leftCar = true
            local floor = value.home.floor
            local room = call(sq(floor.x, floor.y, floor.z), "getRoom")
            local stand = ring(floor.x, floor.y, floor.z, 2, 4, function(square)
                return call(square, "getRoom") == room and U().isSafeSpawnSquare(square)
            end)
            if not need("hitchhiker_observer_walks_in", teleport(H.player, stand),
                "square in her room within 4 m") then return end
            F.stepAt = current
            return
        end
        -- Retiring the story stamps its stage with the reason.
        if value.stage == "found" or value.stage == "found_home" then
            check("hitchhiker_found_home", retiredAs(F.id) == "found_home"
                    and F.group.lifecycle == "destroyed",
                "retired=" .. tostring(retiredAs(F.id)))
            local floor = value.home.floor
            local still = call(sq(floor.x, floor.y, floor.z), "getDeadBody")
            for dx = -1, 1 do
                for dy = -1, 1 do
                    still = still or call(sq(floor.x + dx, floor.y + dy, floor.z), "getDeadBody")
                end
            end
            check("hitchhiker_body_not_removed", still ~= nil, "body still on the floor")
            setPhase("folk_batch_done", current)
            return
        end
        if current - F.stepAt > 15000 then
            need("hitchhiker_found_home", false, "stage=" .. tostring(value.stage))
        end
        return
    end
end

-- Driver ---------------------------------------------------------------------

function Probe.step(H, current, check, result, setPhase)
    local SC = SCX()
    H.folk = H.folk or {}
    local F = H.folk
    local function stop()
        restore(F)
        setPhase("finish", current)
    end
    local function need(name, condition, detail)
        if check(name, condition, detail) then return true end
        stop()
        return false
    end

    if H.phase == "folk_batch_prepare" then
        if current - H.phaseStartedAt < 1500 then return end
        F.target = tostring(H.config.strange_folk_batch_target or "")
        F.id = IDS[F.target]
        F.definition = F.id and SC.Oddballs.definition(F.id)
        if not need("folk_batch_definition_ready", F.definition ~= nil
                and type(SC[MODULES[F.target]]) == "table",
            "target=" .. F.target) then return end
        if (F.target == "bitten" or F.target == "bittenkill")
            and not SC.OddballBitten.bitesInfect() then
            local lore = type(SandboxVars) == "table" and SandboxVars.ZombieLore or {}
            result("SKIP", "folk_batch_bitten_sandbox", "bites are not fatal in this save: transmission="
                .. tostring(lore.Transmission) .. " mortality=" .. tostring(lore.Mortality))
            stop()
            return
        end
        require("SCOddballCoreyEarlProbe")
        local fixture = SCRealSandboxHarnessProbes.SCOddballCoreyEarlProbe
        local isolated, reason = fixture.clearExistingOddball(SC, F.id)
        if not need("folk_batch_clone_isolated", isolated, tostring(reason)) then return end
        -- The ambient spawner must not add a second stranger mid-scene.
        F.originalAmbient = SC.Oddballs.pulse
        SC.Oddballs.pulse = function() return false, "folk_batch_ambient_paused", false end
        recordSpeech(F)
        pcall(function() H.player:setGodMod(true) end)
        pcall(function() H.player:setInvisible(true) end)
        local x, y = tonumber(H.config.oddball_site_x) or 0, tonumber(H.config.oddball_site_y) or 0
        if x > 0 and y > 0 then
            if not need("folk_batch_search_area", pcall(function()
                H.player:teleportTo(x + 0.5, y + 0.5, 0)
            end), tostring(x) .. "," .. tostring(y)) then return end
        end
        trace("START", "target=" .. F.target .. " hour=" .. round(call(getGameTime(), "getTimeOfDay"))
            .. " day=" .. tostring(call(getGameTime(), "getDay")))
        setPhase("folk_batch_find_site", current)
        return
    end

    if H.phase == "folk_batch_find_site" then
        if current - H.phaseStartedAt < 3000 then return end
        if not F.searchX then
            local px, py, pz = U().position(H.player)
            F.searchX, F.searchY = math.floor(px), math.floor(py)
            -- No encounter picks the building the player stands in. Wait
            -- outdoors near the search point instead.
            if not outdoor(U().squareOf(H.player)) then
                teleport(H.player, ring(px, py, pz, 6, 30, function(square)
                    return outdoor(square) and U().isSafeSpawnSquare(square)
                end))
            end
        end
        local site, finished = findSite(H, F)
        if not site then
            if finished then
                if current - H.phaseStartedAt < 45000 then
                    F.scanIndex, F.visited = 0, {}
                    return
                end
            end
            if current - H.phaseStartedAt > 60000 then
                need("folk_batch_real_site", false, "no eligible loaded site near "
                    .. F.searchX .. "," .. F.searchY .. " buildings="
                    .. tostring(F.buildingsSeen or 0) .. " " .. diagnoseSites(H, F))
            end
            return
        end
        F.site = site
        check("folk_batch_real_site", true, "spawn=" .. tostring(site.spawn.x) .. ","
            .. tostring(site.spawn.y) .. " room=" .. tostring(site.room) .. " kind="
            .. tostring(site.kind))
        if not need("folk_batch_observer_staged", stageObserver(H, F),
            "observer placed before the spawn") then return end
        if F.target == "firecracker" or F.target == "hitchhiker" or F.target == "throwlab" then
            F.quietRemoved = clearWalkers(site.spawn.x, site.spawn.y, 0, 45)
            result("PASS", "folk_batch_quiet_site_fixture", "walkers removed within 45 m: "
                .. tostring(F.quietRemoved))
        end
        local group, reason = SC.Factions.createOddballGroup(site, F.definition, true)
        if not need("folk_batch_group_created", group ~= nil, tostring(reason)) then return end
        F.group = group
        setPhase("folk_batch_spawn", current)
        return
    end

    if H.phase == "folk_batch_spawn" then
        local actors, ready = groupActors(F.group)
        if not ready then
            if current - H.phaseStartedAt > 40000 then
                need("folk_batch_native_actors", false, "spawned=" .. #actors)
            end
            return
        end
        F.actor = actors[1]
        F.actors = actors
        local names = {}
        for _, actor in ipairs(actors) do names[#names + 1] = nameOf(actor) end
        local secureScene = type(F.definition.scene) == "table"
        if secureScene and F.group.oddball.sceneSecured ~= true
            and current - H.phaseStartedAt < 45000 then
            return
        end
        check("folk_batch_native_actors", true, table.concat(names, ", "))
        if secureScene then
            check("folk_batch_scene_secured", F.group.oddball.sceneSecured == true,
                "radius=" .. tostring(F.definition.scene.radius) .. " closeDoors="
                    .. tostring(F.definition.scene.closeDoors))
        end
        F.stepAt = current
        setPhase("folk_batch_run", current)
        return
    end

    if H.phase == "folk_batch_run" then
        -- A member that unloads and wakes again is a new native actor.
        local live = groupActors(F.group)
        local mortal = F.target == "bitten" or F.target == "bittenkill"
        if live[1] and not mortal then F.actor = live[1] end
        if F.actor and U().isDead(F.actor) and not mortal then
            need("folk_batch_" .. F.target .. "_alive", false, "the encounter's actor died")
            return
        end
        local okay, failure = pcall(Flows[F.target], H, F, current, check, result, setPhase, need)
        if not okay then
            need("folk_batch_" .. F.target .. "_flow", false, tostring(failure))
        end
        return
    end

    if H.phase == "folk_batch_done" then
        restore(F)
        result("PASS", "folk_batch_" .. tostring(F.target) .. "_complete",
            "lines spoken=" .. tostring(#(F.speech or {})) .. " radio lines heard="
                .. tostring(#(F.radio or {})))
        setPhase("finish", current)
        return
    end
end

return Probe
