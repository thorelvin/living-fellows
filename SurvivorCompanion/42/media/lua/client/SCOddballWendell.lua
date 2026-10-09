-- SPDX-License-Identifier: MIT
-- Strange Folk: Wendell's warning, overnight watch, and farm animals.
-- All saved fields live under group.oddball; no process clock or Java object
-- is retained there. Navigation and human combat remain with their owners.

local SC = SurvivorCompanion
SC.OddballWendell = SC.OddballWendell or {}
local Wendell = SC.OddballWendell
local ID = "shotgun_farmer_wendell"
local SHELL_BOX = "Base.ShotgunShellsBox"
local SHELL = "Base.ShotgunShells"
local SHELLS_PER_BOX = 24
local NIGHT_START = 21
local NIGHT_HOURS = 8
local ABSENCE_GRACE_HOURS = 10 / 60

local function number(value)
    if type(value) == "number" then return value end
    if type(value) == "string" then return tonumber(value) end
    if value ~= nil then
        local ok, text = pcall(tostring, value)
        if ok then return tonumber(text) end
    end
    return nil
end

local lines = {
    warning = { "Back past the fence, damn it. This farm still has a keeper.",
        "Back past the fence. This farm still has a keeper." },
    shot = { "Next one won't go into the sky. Get off my land.",
        "Next one won't go into the sky. Please leave my land." },
    trespass = { "You came for the hens? Hell, you've picked a fight.",
        "You came for the hens? You've picked a fight." },
    shells_one = { "Shells. Good. The nights have teeth out here.",
        "Shells. Good. The nights have teeth out here." },
    shells_two = { "Two boxes. You kept your word. Now keep watch with me.",
        "Two boxes. You kept your word. Now keep watch with me." },
    watch_start = { "Nine to five. Stay close enough to hear the coop.",
        "Nine to five. Stay close enough to hear the coop." },
    watch_reset = { "You left the line too long. Damn it, we start tomorrow.",
        "You left the line too long. We start tomorrow." },
    watch_done = { "Sun's up. Those birds and I owe you a fair hearing.",
        "Sun's up. Those birds and I owe you a fair hearing." },
    recruit = { "All right. I'll walk with you. The chickens stay here.",
        "All right. I'll walk with you. The chickens stay here." },
}

local function U() return SC.GameplayUtil end

local function stateFor(group)
    if type(group) ~= "table" then return nil end
    local state = SC.Oddballs and type(SC.Oddballs.state) == "function"
        and SC.Oddballs.state(group) or group.oddball
    if type(state) ~= "table" or state.id ~= ID then return nil end
    state.stage = state.stage or "unmet"
    state.shellDeliveries = math.max(0,
        math.min(2, math.floor(number(state.shellDeliveries) or 0)))
    state.watch = type(state.watch) == "table" and state.watch or {}
    state.chickens = type(state.chickens) == "table" and state.chickens or {}
    state.chickens.slots = type(state.chickens.slots) == "table"
        and state.chickens.slots or {}
    return state
end

local function worldHour()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return nil end
    local hour = select(1, U().call(gameTime, "getWorldAgeHours"))
    return number(hour)
end

local function speak(group, topic)
    local actor = Wendell.actor(group)
    local choice = lines[topic]
    if not actor or not choice then return false end
    local clean = U().config and U().config("profanityEnabled") == false
    return U().say(actor, choice[clean and 2 or 1]) == true
end

function Wendell.actor(group)
    if type(group) ~= "table" then return nil end
    for _, member in ipairs(group.members or {}) do
        if member.alive ~= false and member.actorId and SC.Registry then
            local record = SC.Registry.byId(member.actorId)
            if record and record.actor and U().isValidActor(record.actor) then
                return record.actor
            end
        end
    end
    return nil
end

local function nearPoint(value, point, radius)
    if value == nil or point == nil then return false end
    local x, y, z = U().position(value)
    local px, py, pz
    if type(point) == "table" and point.x ~= nil then
        px, py, pz = number(point.x), number(point.y), number(point.z) or 0
    else
        px, py, pz = U().position(point)
    end
    if not x or not y or px == nil or py == nil or z ~= pz then return false end
    local dx, dy = x - px, y - py
    return dx * dx + dy * dy <= radius * radius
end

local function distanceToBounds(value, bounds)
    if value == nil or type(bounds) ~= "table" then return math.huge end
    local x, y = U().position(value)
    if not x then return math.huge end
    local x1, y1 = number(bounds.x1), number(bounds.y1)
    local x2, y2 = number(bounds.x2), number(bounds.y2)
    if not x1 or not y1 or not x2 or not y2 then return math.huge end
    local dx = x < x1 and x1 - x or x > x2 and x - x2 or 0
    local dy = y < y1 and y1 - y or y > y2 and y - y2 or 0
    return math.sqrt(dx * dx + dy * dy)
end

local function propertyDistance(group, player)
    local state = stateFor(group)
    local site = state and state.site or nil
    if not site then return math.huge end
    local bounds = site.house and site.house.bounds
        or group.house and group.house.bounds
    local distance = distanceToBounds(player, bounds)
    if distance < math.huge then return distance end
    local x, y, z = U().position(player)
    local anchor = site.anchor
    if not x or type(anchor) ~= "table" or z ~= (number(anchor.z) or 0) then
        return math.huge
    end
    local dx, dy = x - (number(anchor.x) or 0), y - (number(anchor.y) or 0)
    return math.sqrt(dx * dx + dy * dy)
end

local function inConversationRange(group, player)
    return propertyDistance(group, player) <= 8
        and nearPoint(player, Wendell.actor(group), 10)
end

local function criticalTrespass(group, player)
    local state = stateFor(group)
    if not state then return false end
    local site = state.site or {}
    local x, y, z = U().position(player)
    if not x or not y or z ~= (number(site.anchor and site.anchor.z) or 0) then
        return false
    end
    if nearPoint(player, site.spawn, 4) then return true, "porch" end
    if nearPoint(player, site.coop or state.chickens.coop, 4) then
        return true, "coop"
    end
    if nearPoint(player, site.truck, 4) then return true, "truck" end
    return propertyDistance(group, player) <= 0, "house"
end

local function gunFor(actor)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local kind = primary and select(1, U().call(primary, "getFullType"))
    if kind == "Base.Shotgun" or kind == "Base.DoubleBarrelShotgun" then
        return primary
    end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        kind = select(1, U().call(item, "getFullType"))
        if kind == "Base.Shotgun" or kind == "Base.DoubleBarrelShotgun" then
            return item
        end
    end
    return nil
end

local function ammoAvailable(actor)
    local inventory = actor and U().inventory(actor)
    if not inventory then return nil end
    local count = 0
    local gun = gunFor(actor)
    if gun then count = math.max(0, number(select(1,
        U().call(gun, "getCurrentAmmoCount"))) or 0) end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        local kind = select(1, U().call(item, "getFullType"))
        if kind == SHELL then count = count + 1
        elseif kind == SHELL_BOX then count = count + SHELLS_PER_BOX end
    end
    return count
end

local function warningShot(group, performer)
    local state = stateFor(group)
    if not state or state.warningShotUsed == true then return false end
    local actor = performer or Wendell.actor(group)
    local gun = gunFor(actor)
    if not gun then return false end
    local count = number(select(1, U().call(gun, "getCurrentAmmoCount"))) or 0
    if count < 1 then return false end
    local _, changed = U().call(gun, "setCurrentAmmoCount", count - 1)
    if not changed then return false end
    state.warningShotUsed = true
    state.ammoEstimate = ammoAvailable(actor)
    local x, y, z = U().position(actor)
    -- This is deliberately sound-only: neither pressedAttack nor SCCombat is
    -- invoked, so the warning can never damage the player or another actor.
    U().call(actor, "playSound", "JS2000ShotgunShoot")
    if type(addSound) == "function" and x then
        pcall(addSound, actor, math.floor(x), math.floor(y), math.floor(z), 100, 100)
    end
    speak(group, "shot")
    return true
end

local function markHostile(group, reason)
    local state = stateFor(group)
    if not state or state.stage == "hostile" or state.stage == "recruited"
        or state.stage == "last_stand" then return false end
    state.stage = "hostile"
    state.hostileReason = reason
    group.lifecycle, group.standing = "hostile", "Hostile"
    group.permanentHostility = true
    speak(group, "trespass")
    return true
end

local function nightStartFor(hour)
    local day = math.floor(hour / 24)
    local start = day * 24 + NIGHT_START
    if hour > start then start = start + 24 end
    return start
end

local function resetWatch(group, state, hour)
    state.watch = { completed = false, startHour = nightStartFor(hour + 0.001),
        resetCount = (number(state.watch.resetCount) or 0) + 1 }
    state.stage = "watch_pending"
    speak(group, "watch_reset")
end

local function watchPulse(group, player, state, hour)
    local watch = state.watch
    if type(watch) ~= "table" or watch.completed == true
        or number(watch.startHour) == nil then return end
    local start = number(watch.startHour)
    if hour < start then return end
    local endHour = start + NIGHT_HOURS
    local present = propertyDistance(group, player) <= 18
    if watch.lastObservedHour then
        local elapsed = hour - watch.lastObservedHour
        if elapsed < -0.001 or elapsed > ABSENCE_GRACE_HOURS then
            resetWatch(group, state, hour)
            return
        end
    elseif hour - start > ABSENCE_GRACE_HOURS then
        resetWatch(group, state, hour)
        return
    end
    if present then
        watch.absenceSinceHour = nil
    else
        watch.absenceSinceHour = watch.absenceSinceHour or hour
        if hour - watch.absenceSinceHour >= ABSENCE_GRACE_HOURS then
            resetWatch(group, state, hour)
            return
        end
    end
    watch.lastObservedHour = hour
    if hour >= endHour and present then
        watch.completed = true
        watch.finishedHour = hour
        state.stage = state.shellDeliveries >= 2 and "ready" or "supplied"
        speak(group, "watch_done")
    elseif hour > endHour + ABSENCE_GRACE_HOURS then
        resetWatch(group, state, hour)
    else
        state.stage = "watch"
    end
end

local function inventoryBox(player)
    local inventory = player and U().inventory(player)
    if not inventory then return nil end
    for _, item in ipairs(U().inventoryItemsDeep(inventory, 240, 12)) do
        if select(1, U().call(item, "getFullType")) == SHELL_BOX then
            return item
        end
    end
end

local function applyPendingShells(group, actor)
    local state = stateFor(group)
    local inventory = actor and U().inventory(actor)
    if not state or not inventory then return false end
    local pending = math.max(0, math.floor(number(state.pendingShells) or 0))
    for _ = 1, pending do
        local item = select(1, U().call(inventory, "AddItem", SHELL))
        if not item then break end
        state.pendingShells = (number(state.pendingShells) or 0) - 1
    end
    state.ammoEstimate = ammoAvailable(actor)
    return (number(state.pendingShells) or 0) == 0
end

local function animalCoop(group, state, hour)
    local site = state.site or {}
    if type(state.chickens.coop) == "table" then return state.chickens.coop end
    if type(site.coop) == "table" and (site.coop.enclosed == true
        or site.coop.kind == "hutch" or site.coop.kind == "barn") then
        state.chickens.coop = { x = site.coop.x, y = site.coop.y,
            z = site.coop.z or 0, kind = site.coop.kind or "designated" }
        return state.chickens.coop
    end
    if hour < (number(state.chickens.nextSearchHour) or 0) then return nil end
    state.chickens.nextSearchHour = hour + 1
    local anchor = site.anchor
    if type(anchor) ~= "table" then return nil end
    local cx, cy, z = math.floor(number(anchor.x) or 0),
        math.floor(number(anchor.y) or 0), math.floor(number(anchor.z) or 0)
    for radius = 0, 16 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = U().gridSquare(cx + dx, cy + dy, z)
                    if square then
                        local hutch
                        if type(getHutch) == "function" then
                            local ok, value = pcall(getHutch, cx + dx, cy + dy, z)
                            if ok then hutch = value end
                        end
                        local room = select(1, U().call(square, "getRoom"))
                        local name = room and tostring(select(1,
                            U().call(room, "getName")) or ""):lower() or ""
                        if hutch or name:find("barn", 1, true)
                            or name:find("coop", 1, true)
                            or name:find("stall", 1, true) then
                            state.chickens.coop = { x = cx + dx, y = cy + dy,
                                z = z, kind = hutch and "hutch" or "barn" }
                            return state.chickens.coop
                        end
                    end
                end
            end
        end
    end
end

local birdKinds = { "hen", "hen", "hen", "cockerel" }
local birdOffsets = { {0.30,0.30}, {0.70,0.30}, {0.30,0.70}, {0.70,0.70} }

local function spawnBird(group, state, coop, slot)
    local offset = birdOffsets[slot]
    -- Keep all four birds on the verified enclosure square. Adjacent tiles may
    -- be outside a narrow hutch or barn stall, even when the coop itself loads.
    local x, y, z = coop.x, coop.y, coop.z
    local square = U().gridSquare(x, y, z)
    if not square then return false, "coop_square_unloaded" end
    local animal, ok
    local breed = "rhodeisland"
    if AnimalDefinitions and AnimalDefinitions.getDef then
        local found, definition = pcall(AnimalDefinitions.getDef,
            birdKinds[slot])
        if found and definition then
            breed = select(1, U().call(definition, "getBreedByName", breed)) or breed
        end
    end
    if type(addAnimal) == "function" and type(getCell) == "function" then
        ok, animal = pcall(addAnimal, getCell(), x + offset[1], y + offset[2], z,
            birdKinds[slot], breed)
    end
    if (not ok or not animal) and IsoAnimal and IsoAnimal.new
        and type(getCell) == "function" then
        ok, animal = pcall(IsoAnimal.new, getCell(), x + offset[1], y + offset[2], z,
            birdKinds[slot], "rhodeisland")
    end
    if not ok or not animal then return false, "animal_spawn_unavailable" end
    U().call(animal, "setWild", false)
    local modData = select(1, U().call(animal, "getModData"))
    if type(modData) == "table" then
        modData.lfWendellGroupId, modData.lfWendellSlot = group.id, slot
    end
    local hutch
    if coop.kind == "hutch" and type(getHutch) == "function" then
        local found, value = pcall(getHutch, coop.x, coop.y, coop.z)
        if found then hutch = value end
    end
    local _, added
    if hutch then
        _, added = U().call(hutch, "addAnimalInside", animal)
    else
        _, added = U().call(animal, "addToWorld")
    end
    if not added then return false, "animal_world_add_failed" end
    local id = number(select(1, U().call(animal, "getAnimalID")))
    state.chickens.slots[slot] = { type = birdKinds[slot], id = id,
        x = x, y = y, z = z, spawned = true }
    return true
end

local function chickenPulse(group, state, hour)
    if state.chickens.spawned == true then return end
    local coop = animalCoop(group, state, hour)
    if not coop then return end
    for slot = 1, 4 do
        if not state.chickens.slots[slot] then
            local ok = spawnBird(group, state, coop, slot)
            if not ok then return end
        end
    end
    state.chickens.spawned = true
end

function Wendell.onSpawn(group, actor)
    local state = stateFor(group)
    if not state or not actor then return false, "wendell_unavailable" end
    if state.stage == "last_stand" or state.stage == "recruited" then
        return false, "wendell_no_longer_resident"
    end
    local inventory = U().inventory(actor)
    if not inventory then return false, "inventory_unavailable" end
    local gun = gunFor(actor)
    if not gun and state.loadoutSeeded ~= true then
        gun = select(1, U().call(inventory, "AddItem", "Base.Shotgun"))
        if not gun then return false, "shotgun_unavailable" end
        U().call(actor, "setPrimaryHandItem", gun)
        U().call(actor, "setSecondaryHandItem", gun)
    end
    if gun and state.loadoutSeeded ~= true then
        U().call(gun, "setCurrentAmmoCount", 6)
        state.loadoutSeeded = true
    end
    if gun and select(1, U().call(actor, "getPrimaryHandItem")) ~= gun then
        U().call(actor, "setPrimaryHandItem", gun)
        U().call(actor, "setSecondaryHandItem", gun)
    end
    applyPendingShells(group, actor)
    if state.warningShotPending and propertyDistance(group, type(getPlayer) == "function"
        and getPlayer() or nil) <= 18 then
        state.warningShotPending = nil
        warningShot(group, actor)
    end
    return true, "wendell_ready"
end

function Wendell.pulse(group, player, current)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if state.recruitmentStarted == true and state.stage ~= "recruited"
        and SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function" then
        local summary = SC.FactionRecruitment.summary(group.id)
        if summary and summary.status == "joined" then state.stage = "recruited" end
    end
    local hour = worldHour()
    if not hour then return false, "game_time_unavailable" end
    chickenPulse(group, state, hour)
    if state.stage ~= "recruited" and state.stage ~= "last_stand"
        and state.stage ~= "hostile" then
        local distance = propertyDistance(group, player)
        if distance <= 18 and state.stage == "unmet" then
            state.stage = "warned"
            state.firstWarnedHour = hour
            group.discovered = true
            speak(group, "warning")
            if not warningShot(group) then state.warningShotPending = true end
        end
        if distance <= 18 and state.shellDeliveries == 0 then
            local trespass, reason = criticalTrespass(group, player)
            if trespass then markHostile(group, reason) end
        end
        if state.warningShotPending and distance <= 18 then
            local shot = warningShot(group)
            if shot then state.warningShotPending = nil end
        end
        watchPulse(group, player, state, hour)
    end
    local actor = Wendell.actor(group)
    if actor then
        if (number(state.pendingShells) or 0) > 0 then
            applyPendingShells(group, actor)
        else
            state.ammoEstimate = ammoAvailable(actor)
        end
    end
    local ammo = number(state.ammoEstimate)
    if state.stage ~= "recruited" and state.stage ~= "last_stand" then
        if ammo ~= nil and ammo <= 0 and (number(state.pendingShells) or 0) <= 0 then
            state.noAmmoSinceHour = state.noAmmoSinceHour or hour
        else
            state.noAmmoSinceHour = nil
        end
        if state.noAmmoSinceHour and hour - state.noAmmoSinceHour >= 120
            and actor == nil and propertyDistance(group, player) > 30
            and state.lastStandTriggered ~= true then
            state.lastStandTriggered = true
            state.stage = "last_stand"
            group.lifecycle = "destroyed"
            for _, member in ipairs(group.members or {}) do member.alive = false end
            return true, "unseen_last_stand"
        end
    end
    return true, state.stage
end

function Wendell.intentFor(actor, player, snapshot, group)
    local state = stateFor(group)
    if not state then return nil end
    if state.stage == "recruited" or state.stage == "last_stand" then return nil end
    if state.stage == "hostile" or group.lifecycle == "hostile"
        or group.standing == "Hostile" then
        if state.stage ~= "hostile" then markHostile(group, "faction_hostility") end
        return { priority = 110, kind = "faction", mode = "hostile",
            factionId = group.id }
    end
    local threatCount = type(snapshot) == "table"
        and (number(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threatCount > 0 then
        return { priority = 18, kind = "faction", mode = "zombie_defense",
            factionId = group.id }
    end
    return { priority = 30, kind = "faction", mode = "wendell_guard",
        factionId = group.id }
end

function Wendell.update(actor, player, runtime, intent, group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if intent and intent.mode == "hostile" then
        return false, "delegate_native_human_combat"
    end
    if intent and intent.mode == "zombie_defense" then
        return false, "delegate_native_zombie_combat"
    end
    local spawn = state.site and state.site.spawn
    if type(spawn) ~= "table" then return true, "watching_property" end
    if nearPoint(actor, spawn, 2.5) then return true, "watching_property" end
    local target = U().gridSquare(spawn.x, spawn.y, spawn.z or 0)
    if not target then return true, "guard_square_unloaded" end
    if not SC.Navigation or type(SC.Navigation.request) ~= "function" then
        return false, "navigation_unavailable"
    end
    return SC.Navigation.request(actor, target, "walk", {
        action = "faction_guard", arrivalDistance = 1.5 })
end

function Wendell.canRecruit(group)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if state.stage == "hostile" or state.stage == "last_stand"
        or state.stage == "recruited" then
        return false, "wendell_hostile_or_gone"
    end
    if state.shellDeliveries < 2 then return false, "two_shell_boxes_required" end
    if state.watch.completed ~= true then return false, "overnight_watch_required" end
    return true, "ready"
end

function Wendell.menuOptions(group, player)
    local state = stateFor(group)
    if not state then return {} end
    local nearby = inConversationRange(group, player)
    local eligible, reason = Wendell.canRecruit(group)
    local recruitment = SC.FactionRecruitment
        and type(SC.FactionRecruitment.summary) == "function"
        and SC.FactionRecruitment.summary(group.id) or nil
    local status = recruitment and recruitment.status
    if status == "joined" then
        state.stage = "recruited"
        return {}
    end
    local options = {
        { id = "offer_shells", label = "Give Wendell a box of shotgun shells",
            enabled = nearby and state.shellDeliveries < 2
                and state.stage ~= "hostile" and inventoryBox(player) ~= nil,
            detail = tostring(state.shellDeliveries) .. "/2 boxes delivered" },
        { id = "start_watch", label = "Stand the 21:00-05:00 farm watch",
            enabled = nearby and state.shellDeliveries >= 2
                and state.stage ~= "hostile" and state.watch.completed ~= true,
            detail = state.watch.completed and "Watch completed"
                or "Leaving for ten consecutive minutes resets the watch" },
        { id = "recruit", label = "Ask Wendell to join",
            enabled = nearby and eligible and (status == nil or status == "available"
                or status == "candidate"),
            detail = eligible and "Chickens remain at the farm" or reason },
    }
    if status == "trial" then
        options[#options + 1] = { id = "recruitment_decide",
            label = "Ask Wendell for his decision",
            enabled = nearby and recruitment.canDecide == true,
            detail = recruitment.reason }
        options[#options + 1] = { id = "recruitment_return",
            label = "Tell Wendell to return to the farm",
            enabled = recruitment.canReturn == true,
            detail = "Ends the trial" }
    end
    return options
end

function Wendell.action(group, action, player, payload)
    local state = stateFor(group)
    if not state then return false, "wrong_oddball" end
    if action == "hurt" then
        if state.stage == "recruited" or state.stage == "last_stand" then
            return false, "wendell_no_longer_resident"
        end
        if state.stage ~= "hostile" then markHostile(group, "player_attack") end
        return true, "wendell_defends_himself"
    elseif action == "offer_shells" then
        if state.stage == "hostile" or state.stage == "last_stand" then
            return false, "wendell_hostile_or_gone"
        end
        if not inConversationRange(group, player) then return false, "too_far_away" end
        if state.shellDeliveries >= 2 then return false, "shells_complete" end
        local item = inventoryBox(player)
        if not item then return false, "shotgun_shell_box_required" end
        local container = select(1, U().call(item, "getContainer"))
        if not container then return false, "shell_box_container_unavailable" end
        local _, removed = U().call(container, "Remove", item)
        if not removed then return false, "shell_box_transfer_failed" end
        if U().containerContainsIdentity(container, item) ~= false then
            return false, "shell_box_transfer_unverified"
        end
        state.shellDeliveries = state.shellDeliveries + 1
        state.accessGranted = true
        state.warningShotPending = nil
        state.pendingShells = (number(state.pendingShells) or 0) + SHELLS_PER_BOX
        local actor = Wendell.actor(group)
        if actor then applyPendingShells(group, actor) end
        state.noAmmoSinceHour = nil
        if state.shellDeliveries >= 2 then
            state.stage = state.watch.completed and "ready" or "supplied"
            speak(group, "shells_two")
        else
            state.stage = "helping"
            speak(group, "shells_one")
        end
        return true, "shell_box_delivered"
    elseif action == "start_watch" then
        if state.stage == "hostile" or state.stage == "last_stand" then
            return false, "wendell_hostile_or_gone"
        end
        if state.shellDeliveries < 2 then return false, "two_shell_boxes_required" end
        if state.watch.completed then return false, "watch_already_completed" end
        if not inConversationRange(group, player) then return false, "too_far_away" end
        local hour = worldHour()
        if not hour then return false, "game_time_unavailable" end
        state.watch = { completed = false, startHour = nightStartFor(hour),
            resetCount = number(state.watch.resetCount) or 0 }
        state.stage = "watch_pending"
        speak(group, "watch_start")
        return true, "watch_scheduled"
    elseif action == "recruit" then
        local eligible, reason = Wendell.canRecruit(group)
        if not eligible then return false, reason end
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        local summary = type(SC.FactionRecruitment.summary) == "function"
            and SC.FactionRecruitment.summary(group.id) or nil
        if not summary or summary.status ~= "candidate" then
            local asked, askReason = SC.FactionRecruitment.ask(group.id, player, false)
            if not asked then return false, askReason end
        end
        local started, startReason = SC.FactionRecruitment.startTrial(
            group.id, player, false)
        if not started then return false, startReason end
        state.recruitmentStarted = true
        speak(group, "recruit")
        return true, startReason or "trial_started"
    elseif action == "recruitment_decide" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.decide(group.id, player)
    elseif action == "recruitment_return" then
        if not SC.FactionRecruitment then return false, "recruitment_unavailable" end
        return SC.FactionRecruitment.returnNow(group.id, player, false)
    end
    return false, "unsupported_wendell_action"
end

return Wendell
