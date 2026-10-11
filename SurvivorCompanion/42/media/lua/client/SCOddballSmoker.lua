-- SPDX-License-Identifier: MIT
-- Mara Voss keeps one window open and watches the street from a real chair.
-- Her cigarette uses the stock timed action while the native furniture pose
-- remains active. The cleaver stays in her inventory until the player hits her.
local SC = SurvivorCompanion
SC.OddballSmoker = SC.OddballSmoker or {}
local Smoker = SC.OddballSmoker

local ID = "window_smoker_mara_voss"
local CLEAVER = "Base.MeatCleaver"
local CIGARETTE = "Base.CigaretteSingle"
local STYLE = {
    "Base.Jacket_Black", "Base.Glasses_Sun", "Base.Necklace_Choker",
}
local OPENING = {
    "I keep this window open so the smoke has somewhere to go. Come in if you like.",
    "There's a chair, a view, and the end of the world. You can have the view.",
    "You came through the door. That's rare enough to earn a conversation.",
}
local WINDOW_LINES = {
    "I used to watch people hurry home. Now I watch to see if anyone still remembers where home was.",
    "The street is the same shape. That's the cruelty of it. Everything important has changed.",
    "Rain makes the pavement look almost ordinary. Then one of them walks past.",
}
local PAST_LINES = {
    "I taught philosophy at the college. Ethics, mostly. Then the exam questions started walking in from the street.",
    "My sister called me the night the phones died. She asked whether I believed people were good. I told her I'd call back.",
    "I dressed for dinner the night the broadcasts stopped. This coat reminds me I expected a tomorrow.",
}
local BELIEF_LINES = {
    "The world went to shit. I still think a choice matters, even when every answer hurts.",
    "My whole world went to shit. I used to call courage a habit. Now it's opening a door while your hand shakes.",
    "Everything I called my world went to shit. A person still isn't their worst hour, or none of us gets to be a person.",
}
local AMBIENT = {
    "Everyone said civilization was fragile. Nobody mentioned how loud it would break.",
    "The smoke goes out. The thought stays.",
    "Maybe hope is just refusing to close the window.",
    "I can still picture my sister at the other end of that telephone.",
    "The dead are simple. The living have to explain themselves.",
    "Every philosophy starts with a question. Mine starts with who gets the last cigarette.",
}
local ATTACK_LINES = {
    "I gave you a seat, not permission to draw blood!",
    "So much for the civilized part of our conversation.",
    "You chose violence. I still get to choose what comes next.",
}
local smokeActions = setmetatable({}, { __mode = "k" })

local function U() return SC.GameplayUtil end
local function story(group)
    local value = group and group.oddball
    if type(value) ~= "table" or value.id ~= ID then return nil end
    value.stage = value.stage or "watching"
    value.asked = type(value.asked) == "table" and value.asked or {}
    return value
end
local function actorFor(group)
    local member = group and group.members and group.members[1]
    local record = member and member.actorId and SC.Registry
        and SC.Registry.byId(member.actorId)
    return record and record.actor and U().isValidActor(record.actor)
        and record.actor or nil
end
local function objectAt(post, predicate)
    if not post then return nil end
    local square = U().gridSquare(post.x, post.y, post.z or 0)
    local objects = square and select(1, U().call(square, "getObjects"))
    if not objects or not SC.NativeList then return nil, square end
    local candidate = post.objectIndex and SC.NativeList.get(objects,
        post.objectIndex) or nil
    if candidate and predicate(candidate) then return candidate, square end
    for index = 0, SC.NativeList.size(objects) - 1 do
        candidate = SC.NativeList.get(objects, index)
        if candidate and predicate(candidate) then
            post.objectIndex = index
            return candidate, square
        end
    end
    return nil, square
end
local function windowFor(value)
    return objectAt(value.site and value.site.window,
        function(candidate) return U().instanceOf(candidate, "IsoWindow") end)
end
local function chairFor(group, value)
    local post = value.site and value.site.chair
    if not post then return nil, "smoker_chair_post_missing" end
    local windowPost = value.site and value.site.window
    if not windowPost or (post.z or 0) ~= (windowPost.z or 0)
        or math.abs(post.x - windowPost.x) > 1
        or math.abs(post.y - windowPost.y) > 1 then
        return nil, "smoker_chair_not_at_window"
    end
    local function matches(candidate)
        local data = U().modData(candidate)
        if data and data.lfSmokerChairGroupId == group.id then return true end
        if post.create ~= true then
            local sprite = select(1, U().call(candidate, "getSprite"))
            local name = sprite and select(1, U().call(sprite, "getName"))
            return name == post.spriteName and post.objectIndex ~= nil
        end
        return false
    end
    local chair, square = objectAt(post, matches)
    if not square then return nil, "smoker_chair_square_unloaded" end
    if not chair then
        local supportedSprite = type(post.spriteName) == "string"
            and (string.match(post.spriteName,
                "^furniture_seating_indoor_01_1[2-5]$")
                or string.match(post.spriteName,
                    "^furniture_seating_indoor_01_4[0-3]$"))
        if post.create ~= true or IsoObject == nil
            or not supportedSprite then
            return nil, "smoker_chair_unavailable"
        end
        local free, why = U().isClearActorSpawnSquare(square)
        if free ~= true then
            return nil, "smoker_chair_tile_blocked:"
                .. tostring(why or "occupied")
        end
        local okay, created = pcall(function()
            return IsoObject.new(square, post.spriteName, "Chair", false)
        end)
        if not okay or not created then return nil, "smoker_chair_create_failed" end
        local objects = select(1, U().call(square, "getObjects"))
        local insertAt = objects and SC.NativeList
            and SC.NativeList.size(objects) or nil
        if type(insertAt) ~= "number" then
            return nil, "smoker_chair_object_list_unavailable"
        end
        local _, added = U().call(square, "AddSpecialObject",
            created, insertAt)
        if not added then return nil, "smoker_chair_add_failed" end
        chair = created
        local data = U().modData(chair)
        if data then data.lfSmokerChairGroupId = group.id end
        if type(triggerEvent) == "function" then
            pcall(triggerEvent, "OnObjectAdded", chair)
        end
        local index = select(1, U().call(chair, "getObjectIndex"))
        if type(index) == "number" and index >= 0 then
            post.objectIndex = index
        end
    end
    if post.propertiesReady ~= true then
        local _, properties = U().call(square, "RecalcProperties")
        local _, neighbours = U().call(square,
            "RecalcAllWithNeighbours", true)
        if not properties or not neighbours then
            return nil, "smoker_chair_recalc_failed"
        end
        post.propertiesReady = true
    end
    local manager
    if type(SeatingManager) == "table"
        and type(SeatingManager.getInstance) == "function" then
        local okay, instance = pcall(SeatingManager.getInstance)
        if okay then manager = instance end
    end
    local count = manager and select(1,
        U().call(manager, "getTilePositionCount", chair))
    if type(count) ~= "number" or count < 1 then
        return nil, "smoker_chair_has_no_native_seat"
    end
    local look = value.site.lookOut
    if type(look) ~= "table" then return nil, "smoker_view_unavailable" end
    local dx, dy = look.x - post.x, look.y - post.y
    local expected = math.abs(dx) >= math.abs(dy)
        and (dx >= 0 and "E" or "W")
        or (dy >= 0 and "S" or "N")
    local facing = select(1,
        U().call(manager, "getFacingDirection", chair))
    if type(facing) ~= "string" and facing then
        facing = select(1, U().call(facing, "name")) or tostring(facing)
    end
    if facing ~= expected then return nil, "smoker_chair_faces_away" end
    return chair, nil
end
local function openView(actor, value, allowUnlock)
    local window = windowFor(value)
    if not window then return false, "smoker_window_unavailable" end
    if select(1, U().call(window, "isSmashed")) == true
        or select(1, U().call(window, "isBarricaded")) == true
        or select(1, U().call(window, "isPermaLocked")) == true then
        return false, "smoker_window_blocked"
    end
    local curtain, curtainKnown = U().call(window, "HasCurtains")
    if not curtainKnown then return false, "smoker_curtain_lookup_unavailable" end
    if curtain then
        local curtainOpen, read = U().call(curtain, "IsOpen")
        if not read then return false, "smoker_curtain_state_unavailable" end
        if curtainOpen ~= true then
            local _, changed = U().call(window, "openCloseCurtain", actor)
            if not changed or select(1,
                U().call(curtain, "IsOpen")) ~= true then
                return false, "smoker_curtain_cannot_open"
            end
        end
    end
    local locked, lockKnown = U().call(window, "isLocked")
    if not lockKnown then return false, "smoker_window_lock_unknown" end
    if locked == true then
        if allowUnlock ~= true then return false, "smoker_window_relocked" end
        local actorSquare = U().squareOf(actor)
        local chairPost = value.site and value.site.chair
        local chairSquare = chairPost and U().gridSquare(chairPost.x,
            chairPost.y, chairPost.z or 0)
        local actorRoom = actorSquare and select(1,
            U().call(actorSquare, "getRoom"))
        local chairRoom = chairSquare and select(1,
            U().call(chairSquare, "getRoom"))
        if not actorRoom or actorRoom ~= chairRoom then
            return false, "smoker_not_inside_to_unlock"
        end
        local _, unlocked = U().call(window, "setIsLocked", false)
        if not unlocked or select(1, U().call(window,
            "isLocked")) ~= false then
            return false, "smoker_window_cannot_unlock"
        end
    end
    local open, read = U().call(window, "IsOpen")
    if not read then return false, "smoker_window_state_unavailable" end
    if open ~= true then
        local _, changed = U().call(window, "ToggleWindow", actor)
        if not changed or select(1, U().call(window,
            "IsOpen")) ~= true then
            return false, "smoker_window_cannot_open"
        end
    end
    return true, "smoker_view_open"
end
local function itemFor(actor, kind)
    local inventory = actor and U().inventory(actor)
    for _, item in ipairs(inventory
        and U().inventoryItemsDeep(inventory, 180, 10) or {}) do
        if U().itemType(item) == kind then return item end
    end
    return nil
end
local function ensureItem(actor, inventory, kind)
    return itemFor(actor, kind) or U().addItem(inventory, kind)
end
local function wear(actor, item)
    local location, known = U().call(item, "getBodyLocation")
    if not known or not location then return false, "smoker_style_slot_unknown" end
    local current, checked = U().call(actor, "getWornItem", location)
    if not checked then return false, "smoker_style_slot_unavailable" end
    if current == item then return true end
    -- An existing outfit may be better than these optional accessories. We
    -- only fill empty slots, never discard a garment from a spawned outfit.
    if current then return true end
    local _, applied = U().call(actor, "setWornItem", location, item)
    if not applied or select(1, U().call(actor,
        "getWornItem", location)) ~= item then
        return false, "smoker_style_wear_failed"
    end
    return true
end
local function ensureKit(actor, value)
    local inventory = U().inventory(actor)
    if not inventory then return false, "smoker_inventory_unavailable" end
    local firstSpawn = value.kitSeeded ~= true
    if firstSpawn then
        if not ensureItem(actor, inventory, CLEAVER) then
            return false, "smoker_cleaver_unavailable"
        end
        if not ensureItem(actor, inventory, "Base.Lighter") then
            return false, "smoker_lighter_unavailable"
        end
        if not ensureItem(actor, inventory, "Base.CigarettePack") then
            return false, "smoker_pack_unavailable"
        end
        if not itemFor(actor, CIGARETTE) then
            for _ = 1, 3 do
                if not U().addItem(inventory, CIGARETTE) then
                    return false, "smoker_cigarettes_unavailable"
                end
            end
        end
        local book = ensureItem(actor, inventory, "Base.Book_Philosophy")
        if not book then return false, "smoker_book_unavailable" end
        U().call(book, "setName",
            "Mara's annotated copy of The Good Life")
        if not ensureItem(actor, inventory, "Base.Lipstick") then
            return false, "smoker_lipstick_unavailable"
        end
    end
    local changed = false
    for _, kind in ipairs(STYLE) do
        local item = firstSpawn and ensureItem(actor, inventory, kind)
            or itemFor(actor, kind)
        if firstSpawn and not item then
            return false, "smoker_style_unavailable"
        end
        if item then
            local location = select(1, U().call(item, "getBodyLocation"))
            local before = location and select(1,
                U().call(actor, "getWornItem", location)) or nil
            local dressed, reason = wear(actor, item)
            if not dressed then return false, reason end
            if before ~= item and before == nil then changed = true end
        end
    end
    if changed then U().call(actor, "resetModelNextFrame") end
    value.kitSeeded = true
    return true
end
local function clearHands(actor)
    local primary = select(1, U().call(actor, "getPrimaryHandItem"))
    local secondary = select(1, U().call(actor, "getSecondaryHandItem"))
    if primary then U().call(actor, "setPrimaryHandItem", nil) end
    if secondary then U().call(actor, "setSecondaryHandItem", nil) end
    return select(1, U().call(actor,
        "getPrimaryHandItem")) == nil
        and select(1, U().call(actor,
            "getSecondaryHandItem")) == nil
end
local function cancelSmoke(actor)
    local action = smokeActions[actor]
    smokeActions[actor] = nil
    if action and type(action.forceCancel) == "function" then
        pcall(action.forceCancel, action)
    end
end
local function arm(actor)
    local cleaver = itemFor(actor, CLEAVER)
    if not cleaver then return false, "smoker_cleaver_missing" end
    if not clearHands(actor) then return false, "smoker_hands_busy" end
    local _, set = U().call(actor, "setPrimaryHandItem", cleaver)
    if not set or select(1, U().call(actor,
        "getPrimaryHandItem")) ~= cleaver then
        return false, "smoker_cleaver_equip_failed"
    end
    return true, "smoker_cleaver_equipped"
end
local function near(group, player, radius)
    local actor = actorFor(group)
    return actor and player and U().distance(actor, player) <= radius
        and U().canSee(player, actor) == true
end
local function lineFor(group, lines, salt)
    local hash = type(U().stableHash) == "function"
        and U().stableHash(tostring(group.id) .. ":" .. salt) or 0
    return lines[(hash % #lines) + 1]
end
local function maybeTrust(group, value)
    if value.asked.view and value.asked.past
        and value.asked.belief and value.stage ~= "open" then
        value.stage = "open"
        if SC.Factions and type(SC.Factions.forceStanding) == "function" then
            SC.Factions.forceStanding(group.id, "Trusted")
        end
    end
end
local function createNativeSmokeAction(actor, cigarette)
    -- B42's stock ISEatFoodAction constructor asks the *local player's*
    -- inventory panes whether a smokable item has a nearby open flame.
    -- Companion actors have no such UI, so getContainers() throws. Replace
    -- only that synchronous lookup for this actor and restore it immediately,
    -- including when the stock constructor raises an error. The returned
    -- action remains vanilla: it animates, uses a carried lighter, and
    -- consumes the cigarette through ISEatFoodAction:complete().
    local pane = ISInventoryPaneContextMenu
    if type(pane) ~= "table" then
        return false, "smoker_fire_lookup_unavailable"
    end
    local original = pane.hasOpenFlame
    local override = function(target)
        if target ~= actor then
            return type(original) == "function" and original(target) or nil
        end
        local square = U().squareOf(actor)
        local fire = square and select(1,
            U().call(square, "hasAdjacentFireObject")) or nil
        return type(fire) == "boolean" and nil or fire
    end
    pane.hasOpenFlame = override
    local okay, action = pcall(ISEatFoodAction.new,
        ISEatFoodAction, actor, cigarette, 1)
    if pane.hasOpenFlame == override then
        pane.hasOpenFlame = original
    end
    return okay, action
end
local function queueSmoke(actor, value, current)
    local prior = smokeActions[actor]
    if prior then
        local queue = type(ISTimedActionQueue) == "table"
            and type(ISTimedActionQueue.getTimedActionQueue) == "function"
            and ISTimedActionQueue.getTimedActionQueue(actor) or nil
        if queue and queue.current == prior then
            value.smokeActionActive = true
            return true, "smoker_native_cigarette_active"
        end
        smokeActions[actor] = nil
        value.smokeActionActive = false
        value.nextSmokeAt = current + 45000
        return true, "smoker_finished_cigarette"
    end
    if current < (tonumber(value.nextSmokeAt) or 0) then
        value.smokeActionActive = false
        return true, "smoker_between_cigarettes"
    end
    if type(ISEatFoodAction) ~= "table"
        or type(ISEatFoodAction.new) ~= "function"
        or type(ISTimedActionQueue) ~= "table"
        or type(ISTimedActionQueue.getTimedActionQueue) ~= "function"
        or type(ISTimedActionQueue.add) ~= "function" then
        return false, "smoker_native_smoke_unavailable"
    end
    local cigarette = itemFor(actor, CIGARETTE)
    if not cigarette then return true, "smoker_cigarettes_exhausted" end
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if type(queue) ~= "table" or queue.current ~= nil
        or type(queue.queue) ~= "table" or #queue.queue ~= 0 then
        return true, "smoker_native_queue_busy"
    end
    local okay, action = createNativeSmokeAction(actor, cigarette)
    if not okay or not action then
        local reason = "smoker_smoke_action_failed:"
            .. tostring(okay and "no_action" or action)
        if type(U().diagnostic) == "function" then
            U().diagnostic("oddball_smoker", actor, reason)
        end
        return false, reason
    end
    if type(action.isValidStart) == "function" then
        local validOk, valid = pcall(action.isValidStart, action)
        if not validOk or valid ~= true then
            return false, "smoker_smoke_start_rejected"
        end
    end
    if type(action.isValid) == "function" then
        local validOk, valid = pcall(action.isValid, action)
        if not validOk or valid ~= true then
            return false, "smoker_cigarette_not_in_inventory"
        end
    end
    local queued = pcall(ISTimedActionQueue.add, action)
    queue = ISTimedActionQueue.getTimedActionQueue(actor)
    if not queued or not queue or queue.current ~= action then
        return false, "smoker_native_smoke_not_queued"
    end
    smokeActions[actor] = action
    value.smokeActionActive = true
    value.lastSmokeAt = current
    value.nextSmokeAt = current + 90000
        + ((tonumber(value.smokeCount) or 0) % 3) * 15000
    value.smokeCount = (tonumber(value.smokeCount) or 0) + 1
    return true, "smoker_native_cigarette_started"
end
local function seatFailure(actor, value, reason)
    value.seatFailures = (tonumber(value.seatFailures) or 0) + 1
    value.seatRequestedAt = nil
    value.seatRetryAt = U().nowMs()
        + math.min(30000, 5000 * value.seatFailures)
    if type(U().diagnostic) == "function" then
        U().diagnostic("oddball_smoker", actor,
            tostring(reason) .. " attempt=" .. tostring(value.seatFailures))
    end
    return false, reason
end

function Smoker.onSpawn(group, actor)
    local value = story(group)
    if not value or not actor then return false, "smoker_unavailable" end
    local open, reason = openView(actor, value, true)
    if not open then return false, reason end
    local chair, chairReason = chairFor(group, value)
    if not chair then return false, chairReason end
    local stocked, stockReason = ensureKit(actor, value)
    if not stocked then return false, stockReason end
    if value.stage == "hostile" then
        local armed, reason = arm(actor)
        value.armed, value.armFailure = armed, armed and nil or reason
        -- The player may have taken the cleaver before saving. Mara remains
        -- hostile on reload and fights with what she still carries.
        return true, armed and "smoker_cleaver_equipped"
            or "smoker_hostile_unarmed"
    end
    if not clearHands(actor) then return false, "smoker_hands_not_clear" end
    return true, "smoker_window_chair_ready"
end
function Smoker.pulse(group, player, current)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if not actor then return true, "smoker_unloaded" end
    current = tonumber(current) or U().nowMs()
    if value.stage == "hostile" then return true, "smoker_hostile" end
    if near(group, player, 8) and value.greeted ~= true then
        value.greeted = true
        group.discovered = true
        value.nextAmbientAt = current + 45000
        U().say(actor, lineFor(group, OPENING, "hello"))
        return true, "smoker_greeted"
    end
    if value.greeted == true and near(group, player, 7)
        and current >= (tonumber(value.nextAmbientAt) or math.huge) then
        local index = ((tonumber(value.ambientIndex) or 0) % #AMBIENT) + 1
        value.ambientIndex = index
        value.nextAmbientAt = current + 55000
        U().say(actor, AMBIENT[index])
        return true, "smoker_reflected"
    end
    return true, value.stage
end
function Smoker.intentFor(actor, player, snapshot, group)
    local value = story(group)
    if not value then return nil end
    if value.stage == "hostile" or group.standing == "Hostile" then
        return { mode = "hostile", priority = 110 }
    end
    local threats = type(snapshot) == "table"
        and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) or 0
    if threats > 0 then
        cancelSmoke(actor)
        value.smokeActionActive = false
        return { mode = "zombie_defense", priority = 18 }
    end
    return { mode = "smoker_chair", priority = 45 }
end
function Smoker.update(actor, player, runtime, intent, group)
    local value = story(group)
    if not value or not intent or intent.mode ~= "smoker_chair" then
        return false, "smoker_not_seating"
    end
    local opened, reason = openView(actor, value, false)
    if not opened then return false, reason end
    local chair, chairReason = chairFor(group, value)
    if not chair then return false, chairReason end
    local current = U().nowMs()
    local seating = SC.NativeActions
    local posture = seating and type(seating.seatingStatus) == "function"
        and seating.seatingStatus(actor) or nil
    if posture == "ground" then
        if value.groundSeatRecovery ~= true then
            value.groundSeatRecovery = true
            if seating and type(seating.leaveSeating) == "function" then
                seating.leaveSeating(actor)
            end
            return seatFailure(actor, value, "smoker_native_seat_fell_to_ground")
        end
        return false, "smoker_ground_getup_pending"
    end
    value.groundSeatRecovery = false
    if select(1, U().call(actor,
        "isSittingOnFurniture")) == true then
        if select(1, U().call(actor,
            "getSitOnFurnitureObject")) ~= chair then
            return false, "smoker_in_different_chair"
        end
        if seating and type(seating.furnitureStatus) == "function"
            and seating.furnitureStatus(actor) == "entering" then
            return true, "smoker_chair_pose_entering"
        end
        value.seatFailures, value.seatRequestedAt = 0, nil
        return queueSmoke(actor, value, current)
    end
    if (tonumber(value.seatFailures) or 0) >= 3 then
        return false, "smoker_native_seat_unreachable"
    end
    if current < (tonumber(value.seatRetryAt) or 0) then
        return true, "smoker_chair_retry_backoff"
    end
    local furnitureStatus = seating and type(seating.furnitureStatus) == "function"
        and seating.furnitureStatus(actor) or nil
    if furnitureStatus == "entering" then
        if current - (tonumber(value.seatRequestedAt) or current) >= 12000 then
            if seating and type(seating.leaveSeating) == "function" then
                seating.leaveSeating(actor)
            end
            return seatFailure(actor, value, "smoker_native_seat_timeout")
        end
        return true, "smoker_chair_path_pending"
    end
    if furnitureStatus == "entered" and value.seatRequestedAt
        and current - value.seatRequestedAt >= 2000 then
        return seatFailure(actor, value, "smoker_native_seat_not_attached")
    end
    cancelSmoke(actor)
    value.smokeActionActive = false
    local arrived, targets = U().directInteractionAccess(actor, chair)
    if not arrived then
        if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function"
            or #targets == 0 then return false, "smoker_chair_access_missing" end
        return SC.Navigation.requestAny(actor, targets, "walk", {
            action = "smoker_approach_chair", object = chair,
            targetSquare = U().squareOf(chair),
            requireSameSquare = true, continuousApproach = true })
    end
    local moving, reason = U().move(actor, "walk", { action = "sit",
        object = chair, targetSquare = U().squareOf(chair) })
    if moving then value.seatRequestedAt = current end
    return moving, reason
end
function Smoker.canRecruit(group)
    local value = story(group)
    return value and value.stage == "open"
        and group.standing == "Trusted" or false,
        "ask_mara_about_her_world_first"
end
function Smoker.menuOptions(group, player)
    local value = story(group)
    if not value or value.stage == "hostile"
        or not near(group, player, 6) then return {} end
    local options = {
        { id = "ask_view", label = "Ask Mara about the view",
            enabled = true },
        { id = "ask_past", label = "Ask about her life before",
            enabled = true },
        { id = "ask_belief", label = "Ask what she still believes",
            enabled = true },
    }
    if Smoker.canRecruit(group) == true then
        options[#options + 1] = { id = "recruit",
            label = "Ask Mara to leave the window with you",
            enabled = true }
    end
    return options
end
function Smoker.action(group, action, player)
    local value = story(group)
    if not value then return false, "wrong_oddball" end
    local actor = actorFor(group)
    if action == "hurt" then
        if value.stage ~= "hostile" then
            cancelSmoke(actor)
            value.smokeActionActive = false
            value.stage = "hostile"
            value.attackedAt = U().nowMs()
            group.discovered = true
            group.permanentHostility = true
            if actor and SC.NativeActions
                and type(SC.NativeActions.leaveSeating) == "function" then
                SC.NativeActions.leaveSeating(actor)
            end
            local armed, reason = arm(actor)
            value.armed = armed == true
            value.armFailure = armed and nil or reason
            U().say(actor, lineFor(group, ATTACK_LINES, "attacked"))
            if SC.Factions and type(SC.Factions.forceStanding) == "function" then
                SC.Factions.forceStanding(group.id, "Hostile")
            end
        end
        return true, value.armed and "smoker_cleaver_drawn"
            or value.armFailure or "smoker_hostile_unarmed"
    end
    if not actor or not near(group, player, 6)
        or value.stage == "hostile" then
        return false, "smoker_too_far"
    end
    local answers = { ask_view = WINDOW_LINES,
        ask_past = PAST_LINES, ask_belief = BELIEF_LINES }
    local lines = answers[action]
    if lines then
        local key = action == "ask_view" and "view"
            or action == "ask_past" and "past" or "belief"
        value.asked[key] = true
        group.discovered = true
        U().say(actor, lineFor(group, lines, action))
        value.nextAmbientAt = U().nowMs() + 55000
        maybeTrust(group, value)
        return true, "smoker_answered_" .. key
    end
    if action == "recruit" and Smoker.canRecruit(group) == true
        and SC.FactionRecruitment then
        local asked, reason = SC.FactionRecruitment.ask(group.id,
            player, false)
        if not asked then return false, reason end
        return SC.FactionRecruitment.startTrial(group.id,
            player, false)
    end
    return false, "smoker_choice_unavailable"
end

return Smoker
