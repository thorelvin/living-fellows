-- SPDX-License-Identifier: MIT
-- Milli Wilson guards her grandson's room and two real, named baby animals.
-- Only native animal IDs and scalar scene state are saved. Missing animals are
-- unloaded, not dead, until the native animal ledger confirms a death.

local SC = SurvivorCompanion
SC.OddballMilli = SC.OddballMilli or {}
local Milli = SC.OddballMilli
local ID = "milli_tea_and_trouble"
local PETS = {
    { kind = "rabkitten", breed = "cottontail", name = "Dumpling" },
    { kind = "raccoonkit", breed = "grey", name = "Bandit" },
}
local NIGHT_SAT_KEYS = { "dumplingNightSat", "banditNightSat" }
local TOYS = { "Base.ToyBear", "Base.ToyCar", "Base.ToyPlane",
    "Base.Yoyo", "Base.Doll", "Base.Spiffo", "Base.FluffyfootBunny",
    "Base.Plushabug", "Base.CatToy" }
local KIT = { ["Base.PanchoDog"] = 1, ["Base.Money"] = 2,
    ["Base.PopBottle"] = 1, ["Base.MuffinGeneric"] = 2,
    ["Base.MuffinFruit"] = 1, ["Base.Kettle"] = 1,
    ["Base.Teabag2"] = 3 }
local SKILLS = { Strength = 9, Fitness = 4, Blunt = 8,
    SmallBlunt = 8, SmallBlade = 6, Sneak = 8, Lightfoot = 7,
    Nimble = 5 }
local LINES = {
    pet1 = "Who's a good boy? Bandit's a good boy. Yes he is.",
    pet2 = "Dumpling, don't chew Grandma's slipper. We talked about this.",
    startle = "Lord have mercy! I nearly brained you with this horse.",
    companionStartle = "Lord have mercy! You people knock worse than the dead.",
    invite = "Well, don't just stand there. You'll have tea. I insist.",
    tea = "It's cold tea, dear. The stove quit in July.",
    muffin = "Have a muffin. Not that one. That one's Bandit's.",
    decline = "Well. I'll ask again tomorrow, dear.",
    gentle = "Gentle! Support his bottom. He's only a baby.",
    hurt = "You hurt my baby. That'll be five dollars. Cash.",
    paid = "Thank you. I'll put it toward his medical bills.",
    money = "I've got two dollars and a dog named Pancho. I'm doing fine.",
    pancho = "Pancho was my grandson's. He'd want me to keep him company.",
    defend = "Not in front of the children!",
    killed = "You killed my baby. Now I'll kill you, you son of a bitch.",
    killedClean = "You killed my baby. Now I'll kill you, you son of a gun.",
    grief = "He was so small. He was so small.",
    griefQuestion = "You were right there. Why didn't you help him?",
    guest = "The guest room is yours, dear. Mind the toys.",
    grandson = "My grandson used to sit right there. Don't ask where he is.",
    join = "I'll come. Dumpling and Bandit come with me.",
    campTea = "Cold tea again. Come sit a spell; the kettle's making its rounds.",
}

local nextTalkAt = setmetatable({}, { __mode = "k" })
local heldBefore = setmetatable({}, { __mode = "k" })
local nextPoseAt = setmetatable({}, { __mode = "k" })
local nextDefenseAt = setmetatable({}, { __mode = "k" })
local nextNightSettleAt = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function number(value) return tonumber(value) end
local function config(key, fallback, minimum, maximum)
    local value = number(U().config and U().config(key)) or fallback
    return math.max(minimum, math.min(maximum, value))
end
local function hourNow()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    return number(clock and select(1, U().call(clock, "getWorldAgeHours")))
end
local function dayNow()
    local hour = hourNow()
    return hour and math.floor(hour / 24) or nil
end
local function clockHour()
    local clock = type(getGameTime) == "function" and getGameTime() or nil
    local hour = number(clock and select(1, U().call(clock, "getHour")))
    return hour and math.floor(hour) % 24 or nil
end
local function story(group)
    local value = type(group) == "table" and group.oddball or nil
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "unmet"
    value.teas = math.max(0, math.floor(number(value.teas) or 0))
    value.babyDead = type(value.babyDead) == "table" and value.babyDead or {}
    value.lastHealth = type(value.lastHealth) == "table" and value.lastHealth or {}
    value.lastAttacks = type(value.lastAttacks) == "table" and value.lastAttacks or {}
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local ids = { member and member.actorId,
        group and group.recruitment and group.recruitment.joinedActorId }
    for index = 1, 2 do
        local id = ids[index]
        local record = id and SC.Registry and SC.Registry.byId(id)
        if record and record.actor and U().isValidActor(record.actor) then
            return record.actor
        end
    end
    return nil
end
local function speak(group, key)
    local actor = actorFor(group)
    local line = LINES[key]
    if key == "killed" and U().config
        and U().config("profanityEnabled") == false then
        line = LINES.killedClean
    end
    return actor and line and U().say(actor, line) == true or false
end
local function point(square)
    local x, y, z = U().position(square)
    return x and { x = math.floor(x), y = math.floor(y),
        z = math.floor(z or 0) } or nil
end
local function roomName(room)
    local name = room and select(1, U().call(room, "getName"))
    return type(name) == "string" and string.lower(name) or nil
end
local function listRows(list, limit)
    local rows = {}
    local size = list and SC.NativeList and SC.NativeList.size(list) or 0
    for index = 0, math.min(limit or 128, size) - 1 do
        local row = SC.NativeList.get(list, index)
        if row then rows[#rows + 1] = row end
    end
    return rows
end
local function bedOn(square)
    local found = false
    U().squareObjects(square, function(object)
        if found then return end
        local label = string.lower(tostring(select(1,
            U().call(object, "getName")) or ""))
        local sprite = select(1, U().call(object, "getSprite"))
        local texture = string.lower(tostring(sprite and select(1,
            U().call(sprite, "getName")) or ""))
        found = string.find(label, "bed", 1, true) ~= nil
            or string.find(texture, "furniture_bedding", 1, true) ~= nil
    end, 64)
    return found
end
local function roomTiles(def, house)
    local iso = select(1, U().call(def, "getIsoRoom"))
    local loaded = iso and select(1, U().call(iso, "getSquares"))
    local result = listRows(loaded, 256)
    if #result > 0 then return result end
    -- The small fallback also handles a partially loaded room after a save.
    -- It is bounded to the descriptor's already scanned interior tiles.
    local expected = iso or def
    for _, position in ipairs(house.interior or {}) do
        local tile = U().gridSquare(position.x, position.y, position.z or 0)
        local room = tile and select(1, U().call(tile, "getRoom"))
        if room == expected or roomName(room) == roomName(def) then
            result[#result + 1] = tile
        end
    end
    return result
end
local function roomDefs(house)
    local anchor = house and house.anchor
    local square = anchor and U().gridSquare(anchor.x, anchor.y,
        anchor.z or 0)
    local building = square and select(1, U().call(square, "getBuilding"))
    local definition = building and select(1, U().call(building, "getDef"))
    local list = definition and select(1, U().call(definition,
        "getRooms")) or building and select(1,
            U().call(building, "getRooms"))
    local rows = listRows(list, 96)
    if #rows > 0 then return rows end
    -- Offline fixtures and maps with no loaded BuildingDef still use room
    -- identity from the candidate descriptor, without accepting a tiny house.
    local seen = {}
    for _, position in ipairs(house.interior or {}) do
        local squareAt = U().gridSquare(position.x, position.y,
            position.z or 0)
        local room = squareAt and select(1, U().call(squareAt, "getRoom"))
        if room and not seen[room] then
            seen[room] = true
            rows[#rows + 1] = room
        end
    end
    return rows
end

function Milli.siteFor(house, player, allowSeen)
    if type(house) ~= "table" then return nil end
    local definitions = roomDefs(house)
    local bedrooms, candidates = 0, {}
    for _, def in ipairs(definitions) do
        local name = roomName(def)
        local kids = name == "kidsbedroom"
            or select(1, U().call(def, "isKidsRoom")) == true
        local bedroom = kids or name == "bedroom"
        if bedroom then bedrooms = bedrooms + 1 end
        if bedroom then candidates[#candidates + 1] = {
            def = def, name = name or "bedroom", kids = kids } end
    end
    if #definitions < 8 and bedrooms < 2 then return nil end
    table.sort(candidates, function(a, b) return a.kids and not b.kids end)
    for _, candidate in ipairs(candidates) do
        local tiles = roomTiles(candidate.def, house)
        local hasBed, free = false, {}
        for _, tile in ipairs(tiles) do
            if tile then
                hasBed = hasBed or bedOn(tile)
                if U().isSafeSpawnSquare(tile) and U().isSquareFree(tile)
                    and (allowSeen == true or player == nil
                        or U().canSee(player, tile) ~= true) then
                    local p = point(tile)
                    if p and #free < 32 then free[#free + 1] = p end
                end
            end
        end
        if hasBed and #free >= 3 then
            return { kind = "resident", room = candidate.name,
                house = house, anchor = house.anchor,
                spawn = free[1], petSpawns = { free[2], free[3] },
                toySpawns = free }
        end
    end
    return nil
end

local function inventoryItems(actor)
    local inventory = actor and U().inventory(actor)
    return inventory, inventory and U().inventoryItemsDeep(inventory,
        160, 8) or {}
end
local function itemsOf(actor, kind)
    local matches = {}
    for _, item in ipairs(select(2, inventoryItems(actor))) do
        if U().itemType(item) == kind then matches[#matches + 1] = item end
    end
    return matches
end
local function seedKit(group, actor, value)
    if value.milliKitSeeded == true then return true end
    local inventory = U().inventory(actor)
    if not inventory then return false, "milli_inventory_unavailable" end
    local seed = U().stableHash and U().stableHash(group.id .. ":milli-weapon") or 0
    value.weapon = value.weapon or (seed % 2 == 0
        and "Base.HobbyHorse" or "Base.SmashedBottle")
    local weapon = itemsOf(actor, value.weapon)[1]
        or U().addItem(inventory, value.weapon)
    if not weapon then return false, "milli_weapon_unavailable" end
    if value.weapon == "Base.HobbyHorse" then
        U().call(weapon, "setWeaponSprite", "HobbyHorse_Pink")
    end
    for kind, wanted in pairs(KIT) do
        local current = #itemsOf(actor, kind)
        while current < wanted do
            if not U().addItem(inventory, kind) then
                return false, "milli_kit_unavailable:" .. kind
            end
            current = current + 1
        end
    end
    U().call(actor, "setPrimaryHandItem", weapon)
    value.milliKitSeeded = true
    return true
end
local function tintClothing(actor)
    if ImmutableColor == nil and Color == nil then
        return false, "color_api_unavailable"
    end
    local colors = { ["Base.Jumper_DiamondPatternTINT"] = { 0.94, 0.53, 0.68 },
        ["Base.Trousers_WhiteTINT"] = { 0.98, 0.74, 0.80 },
        ["Base.Shoes_Slippers"] = { 0.98, 0.24, 0.54 } }
    local touched = false
    for _, item in ipairs(select(2, inventoryItems(actor))) do
        local rgb = colors[U().itemType(item)]
        if rgb then
            local class = ImmutableColor or Color
            local okay, color = pcall(function()
                return class.new(rgb[1], rgb[2], rgb[3])
            end)
            local visual = select(1, U().call(item, "getVisual"))
            if okay and visual then
                local _, set = U().call(visual, "setTint", color)
                touched = touched or set
            end
        end
    end
    if touched then U().call(actor, "resetModelNextFrame") end
    return touched
end
local function seedSkills(actor, value)
    if value.skillsSeeded == true then return true end
    if Perks == nil then return false, "vanilla_perks_unavailable" end
    for name, target in pairs(SKILLS) do
        local okay, perk = pcall(function() return Perks[name] end)
        if not okay then perk = nil end
        if perk == nil then return false, "vanilla_perk_unavailable:" .. name end
        local current, read = U().call(actor, "getPerkLevel", perk)
        if not read then return false, "vanilla_perk_unreadable:" .. name end
        if number(current) ~= target then
            local _, set = U().call(actor, "setPerkLevelDebug", perk, target)
            if not set then
                _, set = U().call(actor, "setPerkLevel", perk, target)
            end
            if not set then return false, "vanilla_perk_set_failed:" .. name end
        end
    end
    local trait = CharacterTrait and select(2, pcall(function()
        return CharacterTrait.STRONG
    end)) or nil
    if trait == nil and CharacterTrait and ResourceLocation then
        trait = select(2, pcall(function()
            return CharacterTrait.get(ResourceLocation.of("base:strong"))
        end))
    end
    if trait == nil then return false, "vanilla_strong_trait_unavailable" end
    local traits = select(1, U().call(actor, "getCharacterTraits"))
        or select(1, U().call(actor, "getTraits"))
    if not traits then return false, "vanilla_trait_container_unavailable" end
    local _, added = U().call(traits, "add", trait)
    if not added then return false, "vanilla_strong_trait_failed" end
    U().call(actor, "modifyTraitXPBoost", trait, false)
    value.skillsSeeded = true
    return true
end
local function seedPets(group, value)
    if not SC.OddballAnimals then return false, "animal_system_unavailable" end
    local posts = value.site and value.site.petSpawns
    if type(posts) ~= "table" or #posts ~= 2 then
        return false, "milli_pet_posts_unavailable"
    end
    for slot, spec in ipairs(PETS) do
        local okay, reason = SC.OddballAnimals.spawn(group, slot,
            spec, posts[slot])
        if not okay then return false, reason end
    end
    value.petsSpawned = true
    return true
end
local function seedToys(group, value)
    if value.toysPlaced == true then return true end
    local posts = value.site and value.site.toySpawns or {}
    if #posts == 0 then return false, "milli_toy_posts_unavailable" end
    local minimum = config("oddballMilliToysMin", 5, 5, 8)
    local maximum = config("oddballMilliToysMax", 8, minimum, 8)
    local seed = U().stableHash and U().stableHash(group.id .. ":milli-toys") or 0
    value.toysWanted = value.toysWanted or math.min(maximum,
        minimum + seed % (maximum - minimum + 1))
    value.toysCount = number(value.toysCount) or 0
    while value.toysCount < value.toysWanted do
        local index = value.toysCount + 1
        local post = posts[(index - 1) % #posts + 1]
        local square = U().gridSquare(post.x, post.y, post.z or 0)
        if not square then return false, "milli_toy_square_unloaded" end
        local kind = TOYS[(seed + index - 1) % #TOYS + 1]
        local added, called = U().call(square, "AddWorldInventoryItem",
            kind, 0.25 + (index % 3) * 0.15,
            0.25 + (math.floor(index / 3) % 3) * 0.15, 0)
        if not called or added == nil then
            return false, "milli_toy_placement_failed" end
        value.toysCount = index
    end
    value.toysPlaced = true
    return true
end

function Milli.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "milli_unavailable" end
    value.keeperActorId = U().idOf(actor)
    local ready, reason = seedKit(group, actor, value)
    if not ready then return false, reason end
    ready, reason = seedSkills(actor, value)
    if not ready then return false, reason end
    tintClothing(actor)
    ready, reason = seedPets(group, value)
    if not ready then return false, reason end
    ready, reason = seedToys(group, value)
    if not ready then return false, reason end
    if value.guardReleased ~= true and SC.OddballRoomGuard then
        SC.OddballRoomGuard.register(group, nil, U().nowMs())
    end
    return true, "milli_ready"
end

local function near(group, player, distance)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= distance
end
local function teaReady(value, hour)
    local cooldown = config("oddballMilliTeaCooldownHours", 24, 1, 168)
    return hour and value.lastDeclinedDay ~= math.floor(hour / 24)
        and (value.lastTeaHour == nil
            or hour - value.lastTeaHour >= cooldown)
end
local quietCampAction = { sit = true, rest_bed = true,
    rest_floor = true, read = true, write_diary = true,
    tidy_camp = true, weather_recovery = true }
local function atCampDowntime(actor)
    if not SC.BaseLife or type(SC.BaseLife.isInside) ~= "function"
        or SC.BaseLife.isInside(actor) ~= true
        or select(1, U().call(actor, "isMoving")) == true then return false end
    local supervisor = SC.ActionSupervisor
    local token = supervisor and type(supervisor.current) == "function"
        and supervisor.current(actor) or nil
    if token ~= nil then
        return type(token) == "table" and token.owner == "downtime"
            and quietCampAction[token.action] == true
    end
    -- Stable idle is also downtime, but it has no supervisor token.
    local downtime = SC.Downtime
    local state = downtime and type(downtime.peek) == "function"
        and downtime.peek(actor) or nil
    return type(state) == "table" and number(state.safeSince) ~= nil
        and U().nowMs() - state.safeSince >= 5000
        and select(1, U().call(actor, "isMoving")) ~= true
end
local function campTeaOffer(group, value, actor, player)
    local hour, today = hourNow(), dayNow()
    if not player or not today or value.lastCampOfferDay == today
        or not teaReady(value, hour) or not atCampDowntime(actor)
        or U().distance(actor, player) > 6
        or select(1, U().call(actor, "isAsleep")) == true
        or select(1, U().call(player, "isAsleep")) == true then
        return false
    end
    if U().say(actor, LINES.campTea) ~= true then return false end
    value.lastCampOfferDay = today
    return true
end
local function settleBabyAtNight(group, value, slot, actor, current)
    local animal = SC.OddballAnimals.find(group, slot)
    if not animal or select(1, U().call(animal, "getContainer")) ~= nil
        or current < (nextNightSettleAt[animal] or 0) then return false end
    if U().distance(animal, actor) > 1.75 then
        nextNightSettleAt[animal] = current + 15000
        local _, requested = U().call(animal, "pathToCharacter", actor)
        return requested == true
    end
    if select(1, U().call(animal, "isAnimalSitting")) == true then
        return true
    end
    -- The native animal behavior owns sitting and its wake-up time. This
    -- asks that behavior to settle once near Milli without faking a sleep flag.
    nextNightSettleAt[animal] = current + 30000
    local _, requested = U().call(animal, "debugForceSit")
    local settled = requested == true
        and select(1, U().call(animal, "isAnimalSitting")) == true
    if settled then value[NIGHT_SAT_KEYS[slot]] = true end
    return settled
end
local function wakeSettledBaby(group, value, slot)
    local key = NIGHT_SAT_KEYS[slot]
    if value[key] ~= true then return false end
    local animal = SC.OddballAnimals.find(group, slot)
    if not animal then return false end
    if select(1, U().call(animal, "isAnimalSitting")) == true then
        U().call(animal, "debugForceSit")
    end
    if select(1, U().call(animal, "isAnimalSitting")) == true then
        return false
    end
    value[key] = nil
    nextNightSettleAt[animal] = nil
    return true
end
local function inRoom(group, person)
    local site = story(group).site
    local spawn = site and site.spawn
    local actorSquare = spawn and U().gridSquare(spawn.x, spawn.y,
        spawn.z or 0)
    local personSquare = person and U().squareOf(person)
    local room = actorSquare and select(1, U().call(actorSquare, "getRoom"))
    return room and personSquare and select(1,
        U().call(personSquare, "getRoom")) == room or false
end
local function roomEnteredByFellow(group)
    if not SC.Registry or type(SC.Registry.living) ~= "function" then return false end
    for _, fellow in ipairs(SC.Registry.living()) do
        if fellow ~= actorFor(group) and inRoom(group, fellow) then
            return true
        end
    end
    return false
end
local function releaseGuard(group, value)
    if value.guardReleased == true then return false end
    if SC.OddballRoomGuard then
        SC.OddballRoomGuard.release(group.id)
    end
    value.guardReleased = true
    return true
end
local function stand(actor)
    if actor and SC.Actor and type(SC.Actor.setMovement) == "function" then
        return SC.Actor.setMovement(actor, "walk", { action = "stand_ground" })
    end
    return false
end
local function personHolding(person, petId, pet)
    if not person or not petId then return false end
    if pet and pet.holder == person then return true end
    local inventory = U().inventory(person)
    for _, item in ipairs(inventory and U().inventoryItemsDeep(inventory,
        220, 8) or {}) do
        local held = select(1, U().call(item, "getAnimal"))
        local id = held and number(select(1,
            U().call(held, "getAnimalID")))
        if id == petId then return true, held end
    end
    for _, method in ipairs({ "getPrimaryHandItem", "getSecondaryHandItem" }) do
        local item = select(1, U().call(person, method))
        local held = item and select(1, U().call(item, "getAnimal"))
        local id = held and number(select(1,
            U().call(held, "getAnimalID")))
        if id == petId then return true, held end
    end
    return false
end
local function holderFor(group, player, record, pet)
    if not record then return nil end
    local held, animal = personHolding(player, number(record.id), pet)
    if held then return player, animal or pet end
    if SC.Registry and type(SC.Registry.living) == "function" then
        for _, companion in ipairs(SC.Registry.living()) do
            local held, animal = personHolding(companion, number(record.id), pet)
            if held then return companion, animal or pet end
        end
    end
    return nil, pet
end
local function isResponsible(person, player)
    if not person then return false end
    if person == player or type(getPlayer) == "function"
        and person == getPlayer() then return true end
    local id = U().idOf(person)
    local record = id and SC.Registry and SC.Registry.byId(id)
    return record and record.recruited == true or false
end
local function hostile(group, value)
    if value.grudge == true then return true end
    value.grudge, value.stage = true, "hostile"
    value.guestAccess = false
    group.permanentHostility = true
    if SC.Factions then SC.Factions.forceStanding(group.id, "Hostile") end
    speak(group, "killed")
    stand(actorFor(group))
    return true
end
local function injury(group, value, slot, day)
    if value.grudge == true or value.reimbursement then return false end
    -- The shared 'damage' offense would demand 110 restitution and seven
    -- days before reconciliation. Pet injury is its own five-dollar debt.
    value.nextDebtSerial = (number(value.nextDebtSerial) or 0) + 1
    local offense = { kind = "milli_pet_injury", day = day or 0,
        milliDebtSerial = value.nextDebtSerial,
        restitution = config("oddballMilliReimbursement", 5, 1, 20),
        forgiven = false, permanent = false }
    group.offenses = type(group.offenses) == "table" and group.offenses or {}
    if #group.offenses >= 64 then
        for index, prior in ipairs(group.offenses) do
            if prior.forgiven == true then
                table.remove(group.offenses, index)
                break
            end
        end
    end
    if #group.offenses < 64 then
        group.offenses[#group.offenses + 1] = offense
    end
    value.reimbursement = { slot = slot, day = day,
        offenseSerial = offense.milliDebtSerial,
        amount = offense.restitution,
        priorReputation = number(group.reputation) or -20 }
    local reputation = number(group.reputation) or -20
    if reputation > -20 and SC.Factions then
        SC.Factions.adjustStanding(group.id, -math.min(10,
            reputation + 20), "milli_pet_injury")
    end
    speak(group, "hurt")
    return true
end
local function petSample(group, value, player, current)
    local held = heldBefore[group] or {}
    heldBefore[group] = held
    for slot = 1, 2 do
        local status, animal = SC.OddballAnimals.status(group, slot, player)
        local record = value.animals and value.animals.slots
            and value.animals.slots[slot]
        local holder, heldAnimal = holderFor(group, player, record,
            status == "alive" and animal or nil)
        local health = heldAnimal and number(select(1,
            U().call(heldAnimal, "getHealth")))
        if status == "alive" or holder then
            if holder and not held[slot] and not value.grudge then
                speak(group, "gentle")
            end
            local attack = value.lastAttacks[slot]
            local recentPartyHit = attack and attack.responsible == true
                and current - (number(attack.at) or -math.huge) <= 10000
            if health and value.lastHealth[slot]
                and health < value.lastHealth[slot] - 0.01
                and (isResponsible(holder, player) or recentPartyHit) then
                if health <= 0 then
                    value.babyDead[slot] = true
                    hostile(group, value)
                else
                    injury(group, value, slot, dayNow())
                end
            end
            if health then value.lastHealth[slot] = health end
            held[slot] = holder ~= nil
        elseif status == "dead" and not value.babyDead[slot] then
            held[slot] = false
            value.babyDead[slot] = true
            local attack = value.lastAttacks[slot]
            if value.grudge == true then
                -- A direct hit already delivered the hostile line.
            elseif attack and current - (number(attack.at) or -math.huge) <= 10000
                and attack.responsible == true then
                hostile(group, value)
            else
                speak(group, "grief")
                value.griefDay = dayNow()
                if player and inRoom(group, player) then
                    speak(group, "griefQuestion")
                end
            end
        elseif status == "unloaded" then
            -- Absence has no death semantics, even after save/load.
            held[slot] = false
        end
    end
end

-- Native OnCharacterDeath runs before the animal leaves the native ID map.
-- Once it has been removed, an unloaded pet and a dead pet look identical.
function Milli.onAnimalDeath(animal, attacker)
    local data = animal and U().modData(animal)
    local groupId = data and data.lfOddballGroupId
    local slot = data and number(data.lfOddballAnimalSlot)
    if type(groupId) ~= "string" or slot == nil or slot < 1 or slot > 2
        or not SC.Factions or type(SC.Factions.group) ~= "function" then
        return false, "untracked_animal"
    end
    local group = SC.Factions.group(groupId)
    local value = story(group)
    local record = value and value.animals and value.animals.slots
        and value.animals.slots[slot]
    local id = number(select(1, U().call(animal, "getAnimalID")))
    if not record or id == nil or number(record.id) ~= id then
        return false, "not_milli_baby"
    end
    if value.babyDead[slot] == true then return true, "death_already_recorded" end
    local player = type(getPlayer) == "function" and getPlayer() or nil
    local holder = select(1, holderFor(group, player, record, animal))
    local attack = value.lastAttacks[slot]
    local recentPartyHit = not attacker and attack
        and attack.responsible == true
        and U().nowMs() - (number(attack.at) or -math.huge) <= 1500
    local responsible = isResponsible(attacker, player)
        or not attacker and isResponsible(holder, player)
        or recentPartyHit == true
    record.dead = true
    value.babyDead[slot] = true
    if responsible then
        hostile(group, value)
        return true, "milli_baby_killed_by_party"
    end
    speak(group, "grief")
    value.griefDay = dayNow()
    if player and inRoom(group, player) then speak(group, "griefQuestion") end
    return true, "milli_baby_killed_by_other"
end

function Milli.onKeeperDeath(actor, knownGroup)
    local group = knownGroup or actor and SC.Oddballs
        and type(SC.Oddballs.groupForActor) == "function"
        and SC.Oddballs.groupForActor(actor) or nil
    local value = story(group)
    local first = group and group.members and group.members[1]
    local keeperId = first and first.actorId or group and group.recruitment
        and group.recruitment.joinedActorId or value and value.keeperActorId
    if not value or keeperId == nil or U().idOf(actor) ~= keeperId then
        return false, "not_milli"
    end
    if value.keeperDead == true then
        return true, value.caregiverActorId
            and "milli_babies_taken_in" or "milli_babies_left_alive"
    end
    value.keeperDead = true
    value.stage = "orphaned"
    releaseGuard(group, value)
    for slot = 1, 2 do wakeSettledBaby(group, value, slot) end
    local best, bestScore
    if SC.Registry and type(SC.Registry.living) == "function"
        and SC.Community and type(SC.Community.relation) == "function" then
        for _, companion in ipairs(SC.Registry.living()) do
            local candidateId = U().idOf(companion)
            local record = candidateId and SC.Registry.byId(candidateId)
            local relation = candidateId and SC.Community.relation(
                keeperId, candidateId, false)
            if companion ~= actor and candidateId ~= keeperId
                and record and record.recruited == true
                and U().isValidActor(companion)
                and U().distance(actor, companion) <= 12
                and type(relation) == "table"
                and (number(relation.familiarity) or 0) >= 20
                and (number(relation.trust) or 0) >= 20
                and (number(relation.opinion) or 0) >= 10
                and (number(relation.tension) or 0) <= 40 then
                local score = (number(relation.familiarity) or 0)
                    + (number(relation.trust) or 0)
                    + (number(relation.opinion) or 0)
                    - (number(relation.tension) or 0)
                if bestScore == nil or score > bestScore
                    or score == bestScore and candidateId < best then
                    best, bestScore = candidateId, score
                end
            end
        end
    end
    value.caregiverActorId = best
    -- Ownership and native IDs stay with the original encounter. With no
    -- trusted nearby companion, no new keeper moves the babies away.
    if best then return true, "milli_babies_taken_in" end
    return true, "milli_babies_left_alive"
end

function Milli.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    current = number(current) or U().nowMs()
    if value.grudge == true then return true, "milli_hostile" end
    local actor = actorFor(group)
    if not actor then return true, "milli_unloaded" end
    local close = near(group, player,
        config("oddballMilliGuardReleaseTiles", 12, 3, 20))
    if value.roomGuardDone == true then value.guardReleased = true end
    if value.guardReleased ~= true and (close or inRoom(group, player)) then
        releaseGuard(group, value)
    end
    local fellowEntered = roomEnteredByFellow(group)
    local interrupted = player and (inRoom(group, player)
        or near(group, player,
            config("oddballMilliStartleTiles", 3, 1, 8))
        or U().canSee(actor, player) == true) or fellowEntered
    if interrupted and value.startled ~= true then
        value.startled = true
        value.stage = "met"
        group.discovered = true
        releaseGuard(group, value)
        stand(actor)
        local weapon = itemsOf(actor, value.weapon or "Base.HobbyHorse")[1]
        if weapon then U().call(actor, "setPrimaryHandItem", weapon) end
        speak(group, fellowEntered and not inRoom(group, player)
            and "companionStartle" or "startle")
        value.inviteAt = current + 1100
    end
    if value.inviteAt and current >= value.inviteAt then
        value.inviteAt = nil
        speak(group, "invite")
    end
    if value.startled ~= true and not close and not fellowEntered
        and not inRoom(group, player)
        and current >= (nextTalkAt[group] or 0) then
        nextTalkAt[group] = current
            + config("oddballMilliPetTalkMs", 20000, 5000, 120000)
        speak(group, (math.floor(current / 20000) % 2) == 0
            and "pet1" or "pet2")
    end
    if SC.OddballAnimals then petSample(group, value, player, current) end
    local debt = value.reimbursement
    local today = dayNow()
    if debt and today and today > (number(debt.day) or today) then
        local last = number(debt.lastPenaltyDay) or number(debt.day) or today
        local steps = math.min(30, today - last)
        for _ = 1, steps do
            local reputation = number(group.reputation) or -20
            if reputation <= -20 then break end
            SC.Factions.adjustStanding(group.id,
                -math.min(10, reputation + 20), "milli_unpaid_pet_injury")
        end
        debt.lastPenaltyDay = today
    end
    if value.teas >= 3 and (group.standing == "Tolerated"
        or group.standing == "Trusted") then
        value.guestAccess = true
    end
    if value.guestAccess == true and value.guestRoomOffered ~= true then
        value.guestRoomOffered = true
        speak(group, "guest")
    end
    return true, value.stage
end

function Milli.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.grudge == true or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then
        return { mode = "zombie_defense", priority = 60 }
    end
    return { mode = "milli_floor", priority = 30 }
end

function Milli.update(actor, player, runtime, intent, group)
    if not intent or intent.mode ~= "milli_floor" then return false end
    local value = story(group)
    if not value or value.grudge then return false end
    if player and (inRoom(group, player) or near(group, player, 6)) then
        return true, "milli_hosting"
    end
    if select(1, U().call(actor, "isSitOnGround")) == true then
        return true, "milli_sitting"
    end
    local current = U().nowMs()
    if current < (nextPoseAt[actor] or 0) then return true, "milli_pose_pending" end
    nextPoseAt[actor] = current + 15000
    if SC.Actor and type(SC.Actor.setMovement) == "function" then
        local accepted = SC.Actor.setMovement(actor, "walk",
            { action = "sit_ground" })
        return accepted == true, accepted and "milli_sitting"
            or "milli_pose_unavailable"
    end
    return false, "native_sit_unavailable"
end

function Milli.canRecruit(group)
    local value = story(group)
    if not value or value.grudge or group.standing ~= "Trusted"
        or value.reimbursement then return false, "earn_milli_trust" end
    for slot = 1, 2 do
        local status = SC.OddballAnimals.status(group, slot)
        if status == "dead" or status == "unseeded" then
            return false, "milli_will_not_leave_babies"
        end
    end
    return true, "milli_and_babies_ready"
end

function Milli.menuOptions(group, player)
    local value = story(group)
    if not value or value.grudge or value.keeperDead then return {} end
    local nearby = near(group, player, 6)
    local hour = hourNow()
    local ready = teaReady(value, hour)
    local options = {
        { id = "have_tea", label = "Have tea with Milli",
            enabled = nearby and value.startled == true and ready == true,
            detail = ready and "Cold tea and a little company"
                or "Milli will ask again tomorrow" },
        { id = "decline_tea", label = "Decline tea",
            enabled = nearby and value.startled == true and ready == true },
        { id = "ask_pancho", label = "Ask about Pancho",
            enabled = nearby and value.startled == true },
    }
    if value.reimbursement then
        options[#options + 1] = { id = "pay_damage",
            label = "Pay five dollars for the baby",
            enabled = nearby, detail = "Give Milli five real dollars" }
    end
    if group.standing == "Trusted" and value.stage ~= "recruited" then
        local canJoin, reason = Milli.canRecruit(group)
        options[#options + 1] = { id = "recruit",
            label = "Invite Milli and the babies",
            enabled = nearby and canJoin, detail = reason }
    end
    return options
end

function Milli.action(group, action, player, payload)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if action == "animal_hurt" then
        local target = type(payload) == "table" and payload.target or nil
        local data = target and U().modData(target)
        local slot = data and number(data.lfOddballAnimalSlot)
        if not slot or (data.lfOddballGroupId ~= group.id)
            or slot < 1 or slot > 2 then return false, "not_milli_baby" end
        if not isResponsible(player, type(getPlayer) == "function"
            and getPlayer() or nil) then return false, "not_player_party" end
        value.lastAttacks[slot] = { at = U().nowMs(), responsible = true }
        if payload.killed == true then
            return Milli.onAnimalDeath(target, player)
        end
        -- OnWeaponHitCharacter is emitted before damage is calculated. A swing
        -- that the native engine blocks must not create a debt or a death.
        local health = number(select(1, U().call(target, "getHealth")))
        if health then value.lastHealth[slot] = health end
        return true, "milli_baby_hit_pending_damage"
    end
    if action == "hurt" then
        speak(group, "startle")
        return true, "milli_warned"
    end
    if value.grudge then return false, "milli_grudge" end
    if value.keeperDead then return false, "milli_dead" end
    if not near(group, player, 6) then return false, "milli_too_far" end
    if action == "ask_pancho" then
        if value.startled ~= true then return false, "milli_unmet" end
        speak(group, "pancho")
        return true, "pancho_remembered"
    end
    if action == "decline_tea" then
        local today = dayNow()
        if not today or value.lastDeclinedDay == today then
            return false, "tea_declined_today"
        end
        speak(group, "decline")
        value.lastDeclinedDay = today
        return true, "milli_tea_declined"
    end
    if action == "pay_damage" then
        local debt = value.reimbursement
        if not debt then return false, "nothing_to_repay" end
        if not SC.Trade or type(SC.Trade.deliverRequirements)
            ~= "function" then return false, "trade_unavailable" end
        local paid, reason = SC.Trade.deliverRequirements(group, player,
            { { type = "Base.Money", count = debt.amount or 5 } })
        if paid ~= true then return false, reason end
        for _, offense in ipairs(group.offenses or {}) do
            if offense.kind == "milli_pet_injury"
                and offense.forgiven ~= true
                and (offense.milliDebtSerial == debt.offenseSerial
                    or debt.offenseSerial == nil
                        and offense == group.offenses[debt.offenseIndex]) then
                offense.forgiven = true
                break
            end
        end
        value.reimbursement = nil
        if group.standing ~= "Hostile" and SC.Factions then
            local reputation = number(group.reputation) or -20
            local recovery = math.max(0,
                (number(debt.priorReputation) or -20) - reputation)
            if recovery > 0 then
                SC.Factions.adjustStanding(group.id, recovery,
                    "milli_pet_injury_repaid")
            end
        end
        speak(group, "paid")
        return true, "milli_repaid"
    end
    if action == "have_tea" then
        if value.startled ~= true then return false, "milli_unmet" end
        local hour = hourNow()
        if not teaReady(value, hour) then
            return false, "tea_not_due"
        end
        local actor = actorFor(group)
        local muffin = itemsOf(actor, "Base.MuffinGeneric")[1]
            or itemsOf(actor, "Base.MuffinFruit")[1]
        if muffin then
            local source = U().inventory(actor)
            local destination = U().inventory(player)
            local moved, reason = U().transferItemVerified(source,
                destination, muffin)
            if not moved then return false, reason end
        end
        if value.sodaShared ~= true then
            local soda = itemsOf(actor, "Base.PopBottle")[1]
            if soda then
                local moved = U().transferItemVerified(U().inventory(actor),
                    U().inventory(player), soda)
                if moved then value.sodaShared = true end
            end
        end
        U().call(player, "reportEvent", "EventSitOnGround")
        stand(actor)
        if SC.Actor and type(SC.Actor.setMovement) == "function" then
            SC.Actor.setMovement(actor, "walk", { action = "sit_ground" })
        end
        value.teas = value.teas + 1
        value.lastTeaHour = hour
        speak(group, muffin and "muffin" or "tea")
        if value.teas >= 3 and value.grandsonHinted ~= true then
            value.grandsonHinted = true
            speak(group, "grandson")
        end
        if SC.Registry and type(SC.Registry.living) == "function" then
            for _, fellow in ipairs(SC.Registry.living()) do
                if fellow ~= actor and U().distance(fellow, actor) <= 6 then
                    U().say(fellow, "I've been to worse tea parties. Not many.")
                    break
                end
            end
        end
        SC.Factions.adjustStanding(group.id, 8, "milli_tea_shared")
        if value.teas >= 3 and (group.standing == "Tolerated"
            or group.standing == "Trusted") then
            value.guestAccess = true
        end
        return true, "tea_shared"
    end
    if action == "recruit" then
        local allowed, reason = Milli.canRecruit(group)
        if not allowed then return false, reason end
        local recruited = SC.FactionRecruitment
            and SC.FactionRecruitment.ask
            and SC.FactionRecruitment.ask(group.id, player, false)
        if recruited then
            speak(group, "join")
            return true, "milli_recruitment_started"
        end
        return false, "milli_recruitment_unavailable"
    end
    return false, "unknown_milli_action"
end

function Milli.pulseRecruited(group, actor, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    if value.keeperDead then
        if value.caregiverActorId ~= U().idOf(actor) then
            return false, "milli_no_caregiver"
        end
    else
        value.stage = "recruited"
        campTeaOffer(group, value, actor, player)
    end
    local hour = clockHour()
    local resting = not value.keeperDead and hour
        and (hour >= 21 or hour < 6)
        and (select(1, U().call(actor, "isAsleep")) == true
            or atCampDowntime(actor))
    if not resting then
        for slot = 1, 2 do wakeSettledBaby(group, value, slot) end
    end
    for slot = 1, 2 do
        SC.OddballAnimals.follow(group, slot, actor, current)
    end
    if resting then
        for slot = 1, 2 do
            settleBabyAtNight(group, value, slot, actor, current)
        end
    end
    if value.keeperDead then return true, "milli_babies_with_caregiver" end
    if current >= (nextDefenseAt[group] or 0) then
        local danger = false
        for slot = 1, 2 do
            local animal = SC.OddballAnimals.find(group, slot)
            local square = animal and U().squareOf(animal)
            local moving = square and select(1, U().call(square,
                "getMovingObjects"))
            for _, target in ipairs(listRows(moving, 64)) do
                if U().isZombie and U().isZombie(target)
                    and U().distance(animal, target) <= 3 then
                    danger = true
                    break
                end
            end
            if danger then break end
        end
        if danger then
            nextDefenseAt[group] = current + 60000
            speak(group, "defend")
        end
    end
    return true, "milli_babies_follow"
end

return Milli
