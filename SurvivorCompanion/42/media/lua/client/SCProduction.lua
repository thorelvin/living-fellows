-- SPDX-License-Identifier: MIT

if type(require) == "function" then
    pcall(require, "SCBaseLife")
    pcall(require, "SCWorkTransport")
    pcall(require, "SCDialogue")
    pcall(require, "SCNativeList")
end

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.Production = SC.Production or {}
local Production = SC.Production

-- Base production runs finite, player-visible orders (fell trees, saw planks,
-- dig graves, bury the dead) on top of the ordinary base job queue. Every
-- world, inventory, XP and wear effect comes from the real vanilla timed
-- action queued through SCNativeActions; this module only chooses targets,
-- supplies tools, proves post-conditions and keeps bounded runtime state.
Production.VERSION = 1
Production.CARGO_MARKER = "LF_ProductionOrderId"
Production.SAW_RECEIPT = "LF_ProductionSawReceipt"

local PRODUCTION_WORK_KINDS = {
    chop_tree = true, saw_logs = true, dig_grave = true, bury_body = true, fill_grave = true,
}
local TOOL_TAGS = { choptree = "CHOP_TREE", saw = "SAW", diggrave = "DIG_GRAVE" }
local TOOL_CATEGORIES = { "tools", "construction", "crafting", "general" }
local SPEECH = {
    ["work.fell.start"] = { chance = 35, actorMs = 45000 },
    ["work.fell.timber"] = { chance = 60, actorMs = 20000 },
    ["work.fell.tired"] = { chance = 50, actorMs = 120000 },
    ["work.tool.broken"] = { chance = 100, actorMs = 0 },
    ["work.saw.done"] = { chance = 25, actorMs = 60000 },
    ["burial.dig.start"] = { chance = 30, actorMs = 60000 },
    ["burial.dig.done"] = { chance = 40, actorMs = 60000 },
    ["burial.lower"] = { chance = 35, actorMs = 30000 },
}
local GALLOWS_CHANCE = { caring = 20, cautious = 35, practical = 50, brave = 50 }

local descriptors = {}
local descriptorOrder = {}
local actorStates = setmetatable({}, { __mode = "k" })
local scans = {}
local claims = {}
local burialOutcomes = {}
local burialOutcomeOrder = {}
local phases = {}
local ceremonies = {}
local ceremonyOrder = {}
local pendingAmen = nil
local lastProductionSpeechAt = -math.huge
local chopSession = { native = false, fallback = false }
local metrics = {
    treesFelled = 0, planksMade = 0, gravesDug = 0, bodiesBuried = 0, gravesClosed = 0,
    emulatedChopHits = 0, candidateFailures = 0, blocked = 0, errors = 0, lastError = nil,
}

local function U()
    return SC.GameplayUtil
end

local function now()
    return U().nowMs()
end

local function invoke(object, name, ...)
    return U().call(object, name, ...)
end

local function config(key, fallback)
    local value = U() and tonumber(U().config(key)) or nil
    if value == nil or value ~= value then return fallback end
    return value
end

local function actorId(actor)
    return U().idOf(actor)
end

local function natives()
    return SC.NativeActions
end

-- The native facade rejects ordinary dispatch while a human pacing pause, a
-- visual pose or another owned activity is in progress. Those are waits, not
-- failures: they must never cool down or exhaust a work target.
local TRANSIENT_PREFIXES = {
    "action_pacing", "visual_action_active", "visual_effect_pending",
    "actor_state_busy", "activity_",
}

local function transientRejection(reason)
    reason = tostring(reason or "")
    for _, prefix in ipairs(TRANSIENT_PREFIXES) do
        if string.sub(reason, 1, #prefix) == prefix then return true end
    end
    return false
end

local function actorPacing(actor)
    local native = natives()
    if native and type(native.pacingStatus) == "function" then
        local ok, pacing = pcall(native.pacingStatus, actor)
        return ok and pacing == true
    end
    return false
end

local function pointKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
end

local function stableHash(text)
    local utility = U()
    if utility and type(utility.stableHash) == "function" then
        return math.abs(tonumber(utility.stableHash(text)) or 0)
    end
    return #tostring(text) * 7919
end

-- ---------------------------------------------------------------------------
-- Dialogue: short prayers mixed with bleak, public-service gallows humor.
-- Lines stay ASCII so Kahlua and every font render them unchanged.
-- ---------------------------------------------------------------------------

local POOLS = {
    ["work.fell.start"] = {
        common = {
            "Stand clear. This one's coming down.",
            "Axe, tree, sweat. In that order.",
            "Trees don't bite. Best thing I can say about anything out here.",
            "Honest work. Loud work. Keep an eye on the treeline.",
            "If anything shambles out of the woods, yell before I do.",
        },
        brave = { "Let them hear it. Let them come.",
            "Hundred-year oak against one stubborn survivor. My money's on me." },
        cautious = { "Every swing rings the dinner bell. Keep watch.",
            "I stop the second something moves. Promise." },
        caring = { "Sorry, old tree. We need walls more than shade now.",
            "Stay back a bit. I don't want to catch anyone on the backswing." },
        practical = { "Planks don't grow on trees. Well. They do. Slowly.",
            "Working from the camp side out. Shorter hauls." },
    },
    ["work.fell.timber"] = {
        common = {
            "Timber!", "Timber! ...Old habits.", "Down she goes.",
            "That's walls, firewood and a bad back. Mostly the back.",
            "Tree's down. The birds can file a complaint.",
        },
        brave = { "Timber! Next!", "Tell the forest it's losing." },
        cautious = { "Down. Loud, though. Let's see who heard that.",
            "Timber. Now we wait and listen." },
        caring = { "There. Rest now, big fella.", "Nobody under it. Good." },
        practical = { "Logs on the ground. Fetch them before the rain does.",
            "One tree. Adding it to the ledger." },
        stressed = { "Timber! God, that was loud." },
        low = { "Stood a hundred years. Gone in an afternoon. Sounds familiar." },
    },
    ["work.fell.tired"] = {
        common = {
            "Arms are jelly. Give me a minute.",
            "I need to breathe or I'll swing wide.",
            "The tree's winning on stamina.",
        },
        caring = { "Taking a breather. Don't worry about me." },
        practical = { "Resting before I hurt myself. Efficient, not lazy." },
    },
    ["work.tool.broken"] = {
        common = {
            "%1's done. Died doing what it loved.",
            "That's the end of this %1. Anyone got a spare?",
            "Broke the %1. Put it on my tab.",
        },
        practical = { "%1 failed. I need a replacement from storage." },
    },
    ["work.saw.done"] = {
        common = {
            "Planks. Stack them where the rats can't nest.",
            "Three planks from one log. The math still works.",
            "Sawdust in my teeth. Worth it.",
            "There's your wall. Some assembly required.",
        },
        brave = { "Keep them coming. I'll saw the whole county." },
        cautious = { "Stacked and stored. Nothing lying around to trip on." },
        caring = { "These'll keep someone warm or safe. Maybe both." },
        practical = { "Logs converted. Construction stock updated." },
    },
    ["burial.dig.start"] = {
        common = {
            "Six feet. Or as close as this clay allows.",
            "Digging. Somebody has to.",
            "Shovel's heavier than it looks today.",
            "Every town needs a graveyard. Ours is just newer.",
        },
        brave = { "Deep enough that they don't walk out of this one." },
        cautious = { "Deep enough that nothing digs its way back. That's the standard." },
        caring = { "They deserve better than the roadside. This is better." },
        practical = { "Natural soil, good drainage. It'll do." },
        low = { "I used to dig flower beds." },
    },
    ["burial.dig.done"] = {
        common = {
            "Grave's ready. Wish it wasn't.",
            "Room for five. No reservations needed.",
            "Done. Nobody tell me how many more we need.",
        },
        practical = { "Grave complete. Five places." },
    },
    ["burial.lower"] = {
        common = {
            "Easy. Down you go.",
            "No more walking for you, friend.",
            "You're off shift now.",
            "Lie still. That's all we ask.",
            "Whoever you were, you're done carrying it.",
        },
        brave = { "Stay down this time. That's an order." },
        cautious = { "Checked twice. It's not getting up." },
        caring = { "Somebody loved you once. Go easy." },
        practical = { "Interred. Next." },
        stressed = { "Don't look at the face. Don't look at the face." },
        low = { "Sometimes I think they're the lucky ones. Then I remember the smell." },
    },
    ["burial.prayer"] = {
        common = {
            "Lord, take this one home. And lock the door behind them.",
            "May the ground hold you better than the world did.",
            "We give you back to the earth. Please let the earth keep you.",
            "Rest now. Whatever you were carrying, you can put it down.",
            "Heaven, one more coming up. Please don't send them back.",
            "Amen. Please stay down. Also, amen.",
        },
        brave = { "Go on ahead. Save us a seat, not a fight.",
            "You fought. You fell. Now you rest. We'll handle the fighting." },
        cautious = { "Lord, keep them sleeping. We'll keep the shovels handy.",
            "Rest in peace. Mostly rest." },
        caring = { "Whoever you were waiting for, I hope they found you first.",
            "Sleep now. You're not alone out here anymore." },
        practical = { "Short prayer, long day. Amen.",
            "Grave filled, soil packed. Lord, the rest is yours." },
        stressed = { "Please stay down. I can't do this twice." },
        low = { "Somebody's kid. Somebody's everything. Now just somebody under the dirt." },
        hopeful = { "One day there'll be headstones, names and flowers. One day.",
            "Rest. The rest of us are still trying." },
    },
    ["burial.gallows"] = {
        common = {
            "Ashes to ashes, dust to dust. Kentucky keeps the rest.",
            "Rest easy. The world ended. You just caught up.",
            "Here lies somebody. That's more than most get now.",
            "Remember, folks: a buried neighbor is a neighbor who stays put.",
            "Please remain calm and horizontal.",
            "Good news, friend. No more taxes, no more bills, no more walking.",
            "This burial brought to you by the good people still breathing.",
        },
        brave = { "Civil defense says six feet. We gave you six feet and a speech." },
        cautious = { "Stay put, stay quiet, stay dead. Three simple rules." },
        caring = { "I'd bring flowers, but the florist is one of them now." },
        practical = { "Another resident with permanent housing." },
        stressed = { "Amen. Amen. Okay. Walking away now." },
        low = { "The end of the world has terrible funeral arrangements." },
    },
    ["burial.amen"] = {
        common = { "Amen.", "...Amen.", "Amen. Stay down.", "What they said.", "Rest easy." },
        practical = { "Amen. Shovels back in storage." },
    },
    ["burial.ritual.rubber_duck_oracle"] = { common = {
        "By yellow wing and squeaking beak, keep this one down and quiet.",
        "The Duck has reviewed the deceased. Approved for rest.",
    } },
    ["burial.ritual.bourbon_blessing"] = { common = {
        "Here's to you. I'd pour one out, but Kentucky's rationing.",
    } },
    ["burial.ritual.spiffo_salute"] = { common = {
        "*salutes* Colonel Spiffo, another customer has left the building.",
    } },
    ["burial.ritual.gnome_commander"] = { common = {
        "Gnome Command, one more soldier reporting below ground.",
    } },
    ["burial.ritual.sports_pep_talk"] = { common = {
        "Final whistle, champ. You played the whole game.",
    } },
    ["burial.ritual.mannequin_apology"] = { common = {
        "Sorry. You were real, weren't you? I'm so sorry.",
    } },
}

local function registerDialogue()
    if not SC.Dialogue or type(SC.Dialogue.register) ~= "function" then return false end
    for topic, pool in pairs(POOLS) do SC.Dialogue.register(topic, pool) end
    return true
end

local function commandState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return {}
end

local function threatNearby(actor, runtime)
    local state = type(runtime) == "table" and runtime
        or (U().peekActorState and U().peekActorState(actor)) or nil
    local snapshot = type(state) == "table" and state.snapshot or nil
    if type(snapshot) ~= "table" or type(snapshot.threats) ~= "table" then return false end
    local radius = config("productionLoudThreatRadius", 20)
    local limitSq = radius * radius
    for index = 1, math.min(#snapshot.threats, 32) do
        local threat = snapshot.threats[index]
        if type(threat) == "table" and (tonumber(threat.distanceSq) or math.huge) <= limitSq then
            return true
        end
    end
    return false
end

-- Outside the camp boundary, felling starts no new tree at night. Missing game
-- time (headless tests, early boot) never invents a night.
local function lumberNight()
    if type(getGameTime) ~= "function" then return false end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return false end
    local value, called = invoke(gameTime, "getTimeOfDay")
    local hour = called and tonumber(value) or nil
    if hour == nil then return false end
    hour = hour % 24
    local startHour = config("productionLumberNightStartHour", 21)
    local endHour = config("productionLumberNightEndHour", 6)
    if startHour > endHour then return hour >= startHour or hour < endHour end
    return hour >= startHour and hour < endHour
end

-- Occasional lines only: chance, per-actor and party cooldowns, and never
-- while a threat is visible. Speech never gates or delays work state.
local function speak(actor, topic, arguments, salt, runtime)
    local spec = SPEECH[topic]
    if not spec or not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    if threatNearby(actor, runtime) then return false end
    local current = now()
    if current - lastProductionSpeechAt < config("productionSpeechGroupCooldownMs", 12000) then
        return false
    end
    if spec.actorMs > 0 and type(SC.Dialogue.lastSpokenAt) == "function"
        and current - (tonumber(SC.Dialogue.lastSpokenAt(actor)) or -math.huge) < spec.actorMs then
        return false
    end
    local key = tostring(actorId(actor)) .. ":" .. topic .. ":" .. tostring(salt or current)
    if stableHash(key) % 100 >= spec.chance then return false end
    local spoken = SC.Dialogue.say(actor, topic, nil, arguments, { recentLimit = 4, salt = key })
    if spoken == true then lastProductionSpeechAt = current end
    return spoken == true
end

local function ceremonyTopic(actor, salt)
    local state = commandState(actor)
    local ritual = SC.Quirks and type(SC.Quirks.normalize) == "function"
        and SC.Quirks.normalize(state.ritual) or nil
    if type(ritual) == "table" and ritual.id and SC.Dialogue.has
        and SC.Dialogue.has("burial.ritual." .. ritual.id)
        and stableHash(salt .. ":ritual") % 100 < 50 then
        return "burial.ritual." .. ritual.id
    end
    local profile = type(state.personalityProfile) == "table" and state.personalityProfile or {}
    local voice = tostring(profile.archetype or state.personality or "practical")
    local chance = GALLOWS_CHANCE[voice] or 40
    local stress, morale = tonumber(state.stress) or 0, tonumber(state.morale) or 55
    if stress >= 65 then chance = chance + 15
    elseif morale <= 28 then chance = chance + 10
    elseif morale >= 72 then chance = chance - 10 end
    chance = math.max(0, math.min(100, chance + config("burialGallowsBias", 0)))
    return stableHash(salt .. ":gallows") % 100 < chance and "burial.gallows" or "burial.prayer"
end

local function processPendingAmen()
    if not pendingAmen or now() < pendingAmen.dueAt then return end
    local entry = pendingAmen
    pendingAmen = nil
    if entry.actor and not U().isDead(entry.actor) and SC.Dialogue
        and type(SC.Dialogue.say) == "function" then
        SC.Dialogue.say(entry.actor, "burial.amen", nil, nil, { recentLimit = 3, salt = entry.key })
    end
end

local function scheduleAmen(speaker, key)
    if stableHash(key .. ":amen") % 100 >= config("burialAmenChancePercent", 50) then return nil end
    local maximum = config("burialAmenDistance", 8)
    local speakerId = actorId(speaker)
    local ids = SC.BaseLife and type(SC.BaseLife.dutyResidentIds) == "function"
        and SC.BaseLife.dutyResidentIds() or {}
    for _, id in ipairs(ids) do
        if id ~= speakerId then
            local responder = U().resolveActor(id)
            if responder and not U().isDead(responder) and U().distance(speaker, responder) <= maximum then
                pendingAmen = { actor = responder, key = key,
                    dueAt = now() + 2000 + stableHash(key .. ":delay") % 2000 }
                return responder
            end
        end
    end
    return nil
end

-- One guaranteed closing line per grave: prayer or gallows humor by
-- personality and mood, sometimes an amen. Returns true when the ceremony
-- ran; the caller then queues the effect-free salute for after the native
-- pacing pause that follows the fill action.
local function ceremony(actor, grave, runtime)
    local key = grave.key
    if ceremonies[key] then return false end
    ceremonies[key] = true
    ceremonyOrder[#ceremonyOrder + 1] = key
    while #ceremonyOrder > 32 do ceremonies[table.remove(ceremonyOrder, 1)] = nil end
    if threatNearby(actor, runtime) or not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then
        return false
    end
    local spoken = SC.Dialogue.say(actor, ceremonyTopic(actor, key), nil, nil, {
        recentLimit = 4, salt = key,
    })
    if spoken == true then lastProductionSpeechAt = now() end
    scheduleAmen(actor, key)
    return true
end

-- ---------------------------------------------------------------------------
-- Shared bounded helpers
-- ---------------------------------------------------------------------------

local function zoneFor(order)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active() or nil
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.id == order.zoneId then return zone end
    end
    return nil
end

local function storageById(id)
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, false)) do
        if storage.id == id then return storage end
    end
    return nil
end

local function assigned(order, id)
    for _, workerId in ipairs(order.workers or {}) do
        if workerId == id then return true end
    end
    return false
end

local function blockOrder(order, reason)
    metrics.blocked = metrics.blocked + 1
    SC.BaseLife.blockProductionOrder(order.id, reason)
    return false, reason, true
end

local function completeOrder(order, result)
    if order.operation == "fell_trees" and type(order.settings) == "table"
        and order.settings.haulLogs == true and (tonumber(order.pendingHaul) or 0) > 0 then
        local flushed, flushReason = SC.BaseLife.flushProductionHaul(order.id)
        if flushed ~= true then return blockOrder(order, flushReason or "production_haul_pending") end
    end
    local ok, reason = SC.BaseLife.completeProductionOrder(order.id, result)
    if ok ~= true then return false, reason or "production_completion_failed", false end
    return false, "production_order_completed", true
end

local function claimActive(key, id)
    local entry = claims[key]
    return entry ~= nil and entry.actorId ~= id and entry.expiresAt > now()
end

local function claim(key, orderId, id)
    claims[key] = {
        orderId = orderId, actorId = id,
        expiresAt = now() + config("productionActionMaxMs", 120000),
    }
end

local function releaseClaim(key, id)
    local entry = key and claims[key] or nil
    if entry and (id == nil or entry.actorId == id) then claims[key] = nil end
end

local function scanKey(order, purpose)
    return tostring(order.id) .. ":" .. purpose
end

local function resetScan(order, purpose)
    local scan = scans[scanKey(order, purpose)]
    if scan then
        local zone = zoneFor(order)
        if zone then scan.x, scan.y = zone.x1, zone.y1 end
        scan.incomplete, scan.exhausted, scan.temporary = false, false, false
    end
end

local function scanFor(order, purpose, zone)
    local key = scanKey(order, purpose)
    local scan = scans[key]
    if not scan or scan.zoneId ~= zone.id then
        scan = {
            zoneId = zone.id, x = zone.x1, y = zone.y1, waitUntil = 0,
            incomplete = false, exhausted = false, temporary = false,
            cooldowns = {}, failures = {}, cooldownOrder = {},
        }
        scans[key] = scan
    end
    return scan
end

local function onCooldown(order, purpose, key)
    local scan = scans[scanKey(order, purpose)]
    local expires = scan and tonumber(scan.cooldowns[key]) or 0
    return expires > now(), expires == math.huge
end

local function noteCandidateFailure(order, purpose, key, reason)
    local zone = zoneFor(order)
    if not zone or key == nil then return false end
    local scan = scanFor(order, purpose, zone)
    if scan.cooldowns[key] == nil then scan.cooldownOrder[#scan.cooldownOrder + 1] = key end
    local failures = (scan.failures[key] or 0) + 1
    scan.failures[key] = failures
    metrics.candidateFailures = metrics.candidateFailures + 1
    if failures >= config("productionCandidateMaxAttempts", 3) then
        scan.cooldowns[key] = math.huge
        scan.exhausted = true
    else
        scan.cooldowns[key] = now() + config("productionCandidateCooldownMs", 20000)
            * (2 ^ math.max(0, failures - 1))
        -- The cursor has already passed this candidate; keep the current pass
        -- from concluding that the area is empty while it cools down.
        scan.temporary = true
    end
    while #scan.cooldownOrder > 32 do
        local removed = table.remove(scan.cooldownOrder, 1)
        scan.cooldowns[removed], scan.failures[removed] = nil, nil
    end
    scan.lastFailure = tostring(reason or "candidate_failed")
    return true
end

-- Resumable row-major scan of one zone. Unloaded squares mark the pass
-- incomplete instead of proving absence; the per-call square budget keeps
-- each update bounded regardless of zone size.
local function nextZoneCandidate(order, purpose, zone, inspect, id, shared)
    local scan = scanFor(order, purpose, zone)
    local current = now()
    if current < scan.waitUntil then return nil, "production_candidates_waiting", false end
    local budget = math.max(1, math.floor(config("productionScanSquaresPerSlice", 16)))
    for _ = 1, budget do
        local x, y = scan.x, scan.y
        local square = U().gridSquare(x, y, zone.z)
        local found
        if not square then
            scan.incomplete = true
        else
            local candidate = inspect(square, x, y, zone.z)
            if candidate then
                local expires = tonumber(scan.cooldowns[candidate.key]) or 0
                if expires == math.huge then scan.exhausted = true
                elseif expires > current then scan.temporary = true
                elseif not shared and claimActive(candidate.key, id) then scan.temporary = true
                else found = candidate end
            end
        end
        scan.x = scan.x + 1
        local wrapped = false
        if scan.x > zone.x2 then
            scan.x, scan.y = zone.x1, scan.y + 1
            if scan.y > zone.y2 then scan.y, wrapped = zone.y1, true end
        end
        if found then return found, "production_candidate_found", false end
        if wrapped then
            local incomplete, exhausted, temporary = scan.incomplete, scan.exhausted, scan.temporary
            scan.incomplete, scan.exhausted, scan.temporary = false, false, false
            if incomplete then
                scan.waitUntil = current + 2000
                return nil, "production_area_scan_incomplete", false
            end
            if temporary then
                scan.waitUntil = current + 2000
                return nil, "production_candidates_waiting", false
            end
            if exhausted then return nil, purpose .. "_candidates_exhausted", true end
            return nil, purpose .. "_area_empty", true
        end
    end
    return nil, "production_scan_pending", false
end

local function notBroken(item)
    if item == nil then return false end
    local broken, ok = invoke(item, "isBroken")
    return not ok or broken ~= true
end

local function hasToolTag(item, key)
    return U().itemHasTag(item, key) == true
end

local function protectedItem(item, actor)
    if SC.WorkTransport and type(SC.WorkTransport.foreignProtected) == "function" then
        local protected = SC.WorkTransport.foreignProtected(item, actor)
        if protected then return true end
    end
    local data = U().modData(item)
    return type(data) == "table" and data[Production.CARGO_MARKER] ~= nil
end

local function findInventoryTool(actor, key)
    local inventory = U().inventory(actor)
    if inventory == nil then return nil end
    local itemTags = type(_G) == "table" and rawget(_G, "ItemTag") or nil
    local tag = itemTags and TOOL_TAGS[key] and itemTags[TOOL_TAGS[key]] or nil
    if tag ~= nil then
        local found, ok = invoke(inventory, "getFirstTagEvalRecurse", tag, notBroken)
        if ok then return found end
    end
    for _, item in ipairs(U().inventoryItems(inventory, 256)) do
        if hasToolTag(item, key) and notBroken(item) then return item end
    end
    return nil
end

local function toolSource(actor, key)
    for _, category in ipairs(TOOL_CATEGORIES) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
            local container = SC.BaseLife.resolveContainer(storage)
            if container then
                for _, item in ipairs(U().inventoryItems(container,
                    config("campStorageItemBudget", 80))) do
                    if hasToolTag(item, key) and notBroken(item) and not protectedItem(item, actor)
                        and SC.BaseLife.availableCount(storage, U().itemType(item)) > 0 then
                        return storage, container, item
                    end
                end
            end
        end
    end
    return nil
end

local function fetchTool(actor, order, state, key)
    if not SC.BaseWork or type(SC.BaseWork.withdrawFromStorage) ~= "function" then
        return blockOrder(order, "base_work_unavailable")
    end
    local pending = state.toolFetch
    if pending and (pending.key ~= key or U().inventoryContains(pending.container, pending.item) ~= true) then
        pending, state.toolFetch = nil, nil
    end
    if not pending then
        local storage, container, item = toolSource(actor, key)
        if not storage then return blockOrder(order, "missing_tool:" .. key) end
        pending = { key = key, storage = storage, container = container, item = item }
        state.toolFetch = pending
    end
    state.phase = "fetching_tool"
    local ok, reason = SC.BaseWork.withdrawFromStorage(actor, state, pending.storage,
        pending.container, pending.item)
    if ok == true and reason == "base_supply_taken" then
        state.toolFetch = nil
        return true, "production_tool_taken"
    end
    if ok ~= true then
        state.toolFetch = nil
        return false, reason or "production_tool_fetch_failed"
    end
    return true, reason
end

local function cargoOrder(item)
    local data = U().modData(item)
    return type(data) == "table" and data[Production.CARGO_MARKER] or nil
end

local function noteOwnershipMutation()
    if SC.BaseLife and type(SC.BaseLife.noteWorkOwnershipMutation) == "function" then
        SC.BaseLife.noteWorkOwnershipMutation()
    end
end

local function markCargo(item, orderId)
    local data = U().modData(item)
    if type(data) ~= "table" then return false end
    if data[Production.CARGO_MARKER] == orderId then return true end
    data[Production.CARGO_MARKER] = orderId
    if data[Production.CARGO_MARKER] ~= orderId then return false end
    noteOwnershipMutation()
    return true
end

local function clearCargo(item, orderId)
    local data = U().modData(item)
    if type(data) == "table" and data[Production.CARGO_MARKER] == orderId then
        data[Production.CARGO_MARKER] = nil
        noteOwnershipMutation()
        return true
    end
    return false
end

local function markedCargo(inventory, orderId, itemType)
    for _, item in ipairs(U().inventoryItems(inventory, 256)) do
        if cargoOrder(item) == orderId and (itemType == nil or U().itemType(item) == itemType) then
            return item
        end
    end
    return nil
end

local function itemKey(item)
    local id, ok = invoke(item, "getID")
    if ok and id ~= nil then return "native:" .. tostring(id) end
    return tostring(item)
end

local function sawReceiptFor(actor, orderId)
    local data = actor and U().modData(actor) or nil
    local receipt = type(data) == "table" and data[Production.SAW_RECEIPT] or nil
    if type(receipt) ~= "table" or receipt.orderId ~= orderId
        or tonumber(receipt.beforeCount) == nil then return nil end
    return receipt
end

local function writeSawReceipt(actor, order, log, before)
    local data = U().modData(actor)
    if type(data) ~= "table" then return false end
    local count = 0
    for _, present in pairs(type(before) == "table" and before or {}) do
        if present == true then count = count + 1 end
    end
    data[Production.SAW_RECEIPT] = {
        orderId = order.id, logKey = itemKey(log), beforeCount = count, startedAt = now(),
    }
    noteOwnershipMutation()
    return true
end

local function clearSawReceipt(actor, orderId)
    local data = actor and U().modData(actor) or nil
    local receipt = type(data) == "table" and data[Production.SAW_RECEIPT] or nil
    if type(receipt) == "table" and (orderId == nil or receipt.orderId == orderId) then
        data[Production.SAW_RECEIPT] = nil
        noteOwnershipMutation()
        return true
    end
    return false
end

local function workActive(actor, kind)
    local native = natives()
    return native and type(native.isWorkActive) == "function" and native.isWorkActive(actor) == true
        and type(native.workKind) == "function" and native.workKind(actor) == kind
end

local function finishWork(actor)
    local native = natives()
    if not native or type(native.finishWork) ~= "function" then return false, "work_finish_unavailable" end
    local called, finished, reason = pcall(native.finishWork, actor)
    if not called then return false, tostring(finished) end
    return finished == true, reason
end

local function cancelWork(actor, reason)
    local native = natives()
    if not native or type(native.cancelWork) ~= "function" then return false, "work_cancel_unavailable" end
    local called, cancelled, detail = pcall(native.cancelWork, actor, reason)
    if not called then return false, tostring(cancelled) end
    return cancelled == true, detail
end

local function actionTimedOut(state)
    return now() - (state.work.startedAt or now()) > config("productionActionMaxMs", 120000)
end

local function enduranceSufficient(actor)
    local value, ok = invoke(actor, "isEnduranceSufficientForAction")
    return not ok or value ~= false
end

local function rest(actor, order, state, topic, runtime)
    local current = now()
    if state.restUntil == nil then
        state.restUntil = current + config("productionRestMaxMs", 60000)
        U().stop(actor)
        if topic then speak(actor, topic, nil, "rest:" .. tostring(current), runtime) end
    end
    if enduranceSufficient(actor) then
        state.restUntil = nil
        return nil
    end
    if current >= state.restUntil then
        state.restUntil = nil
        return blockOrder(order, "worker_exhausted")
    end
    state.phase = "resting"
    return true, "production_resting"
end

local function avoided(value, avoid)
    local x, y, z = U().position(value)
    if x == nil then return false end
    for _, point in ipairs(avoid or {}) do
        if math.floor(x) == point.x and math.floor(y) == point.y
            and math.floor(z or 0) == (point.z or 0) then
            return true
        end
    end
    return false
end

local function freeAdjacent(square, actor, avoid)
    local x, y, z = U().position(square)
    if x == nil then return nil end
    local best, bestDistance
    for _, offset in ipairs({
        { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }) do
        local candidate = U().gridSquare(x + offset[1], y + offset[2], z)
        if candidate and U().isSquareFree(candidate) and not avoided(candidate, avoid) then
            local distance = U().distance(actor, candidate)
            if bestDistance == nil or distance < bestDistance then
                best, bestDistance = candidate, distance
            end
        end
    end
    return best
end

local function adjacentTo(actor, square)
    local ax, ay, az = U().position(actor)
    local sx, sy, sz = U().position(square)
    if ax == nil or sx == nil then return false end
    if math.floor(az or 0) ~= math.floor(sz or 0) then return false end
    local dx = math.abs(math.floor(ax) - math.floor(sx))
    local dy = math.abs(math.floor(ay) - math.floor(sy))
    return math.max(dx, dy) == 1
end

-- Work stands beside its target square: trees and grave pits are never the
-- worker's own square, and callers may exclude further squares (a grave's
-- second half). Paths stay inside the camp area like gathering; lumber work
-- (reach) may also cross the bounded band around it.
local function approachSquare(actor, square, action, avoid, reach)
    if adjacentTo(actor, square) and not avoided(actor, avoid) then
        return "arrived", "production_in_range"
    end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return "failed", "navigation_unavailable"
    end
    local offered = type(SC.Navigation.interactionTargets) == "function"
        and SC.Navigation.interactionTargets(actor, square) or {}
    local targets = {}
    for _, target in ipairs(type(offered) == "table" and offered or {}) do
        if not avoided(target, avoid) then targets[#targets + 1] = target end
    end
    if #targets == 0 then
        local free = freeAdjacent(square, actor, avoid)
        targets = free and { free } or {}
    end
    if #targets == 0 then return "failed", "production_approach_missing" end
    local accepted, reason = SC.Navigation.requestAny(actor, targets, "walk", {
        action = action, targetSquare = square, arrivalDistance = 0.8, workCampOnly = true,
        workReach = reach == true,
    })
    if accepted ~= true then
        if transientRejection(reason) then return "pending", reason end
        return "failed", reason or "production_approach_failed"
    end
    if adjacentTo(actor, square) then return "arrived", "production_in_range" end
    return "pending", reason or "production_approaching"
end

local function visualStatus(actor)
    local native = natives()
    if native and type(native.visualStatus) == "function" then
        local ok, value = pcall(native.visualStatus, actor, "loot_container")
        if ok then return value end
    end
    return nil
end

local function clearVisual(actor)
    local native = natives()
    if native and type(native.clearVisual) == "function" then pcall(native.clearVisual, actor) end
end

-- The same effect-free loot pose base hauling plays before a verified
-- storage transfer. Returns "done", "pending" or "failed".
local function lootPose(actor, state, context)
    if state.visualAt ~= nil then
        local status = visualStatus(actor)
        if status == "active" then return "pending", "production_storage_looting" end
        state.visualAt = nil
        if status == "completed" then clearVisual(actor) return "done" end
        if status == nil or status == "none" then return "done" end
        return "failed", "production_storage_animation_" .. tostring(status)
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, actor, "production_storage_interaction")
    end
    local native = natives()
    if native and type(native.stopDirect) == "function" then pcall(native.stopDirect, actor)
    else U().stop(actor) end
    local accepted = U().move(actor, "walk", context)
    if accepted ~= true then return "failed", "production_storage_action_rejected" end
    local status = visualStatus(actor)
    if status == "active" then
        state.visualAt = now()
        return "pending", "production_storage_looting"
    end
    if status == "completed" then clearVisual(actor) end
    return "done"
end

local function depositCargo(actor, order, state, item, runtime)
    local storage = storageById(order.destinationStorageId)
    if not storage or storage.deposits == false then
        return blockOrder(order, "destination_storage_invalid")
    end
    local container, object = SC.BaseLife.resolveContainer(storage)
    if not container or not object then return blockOrder(order, "destination_storage_unloaded") end
    local room, roomReason = SC.WorkTransport.hasRoom(container, actor, item)
    if not room then return blockOrder(order, roomReason or "destination_full") end
    state.phase = "depositing"
    if U().distance(actor, object) > 1.5 then
        local targets = SC.Navigation.interactionTargets(actor, object)
        local accepted, reason = SC.Navigation.requestAny(actor, targets, "walk", {
            action = "move_to_base_storage", targetSquare = U().squareOf(object),
            object = object, arrivalDistance = 1.0,
        })
        if accepted ~= true then return blockOrder(order, reason or "production_storage_unreachable") end
        return true, reason or "production_moving_to_storage"
    end
    local pose, poseReason = lootPose(actor, state, {
        action = "loot_container", container = container, item = item, baseStorage = true,
    })
    if pose == "pending" then return true, poseReason end
    if pose == "failed" then return false, poseReason end
    local moved, reason = SC.WorkTransport.transferVerified(U().inventory(actor), container, item, actor)
    if moved ~= true then return false, reason or "production_deposit_failed" end
    clearCargo(item, order.id)
    SC.BaseLife.recordProductionProgress(order.id, 1)
    if order.operation == "saw_planks" then
        speak(actor, "work.saw.done", nil, itemKey(item), runtime)
    end
    return true, "production_deposited"
end

local function countItems(square, itemType, limit)
    local list, ok = invoke(square, "getWorldObjects")
    if not ok and type(square) == "table" then list, ok = square.worldItems, true end
    if not ok or list == nil then return 0 end
    local count = 0
    U().each(list, limit or 64, function(worldItem)
        local item, itemOk = invoke(worldItem, "getItem")
        if not itemOk and type(worldItem) == "table" then item = worldItem.item end
        if item and U().itemType(item) == itemType then count = count + 1 end
    end)
    return count
end

-- ---------------------------------------------------------------------------
-- Fell trees
-- ---------------------------------------------------------------------------

local function treeOn(square)
    local tree, ok = invoke(square, "getTree")
    if ok and tree ~= nil then return tree end
    return nil
end

local function treeInWorld(tree)
    local index, ok = invoke(tree, "getObjectIndex")
    return ok and tonumber(index) ~= nil and tonumber(index) >= 0
end

local function treeHealth(tree)
    local value, ok = invoke(tree, "getHealth")
    return ok and tonumber(value) or nil
end

local function inspectTree(square, x, y, z)
    local tree = treeOn(square)
    if not tree or not treeInWorld(tree) then return nil end
    local size, sizeOk = invoke(tree, "getSize")
    if sizeOk and tonumber(size) ~= nil
        and tonumber(size) < config("productionMinimumTreeSize", 2) then return nil end
    return { key = "tree:" .. pointKey(x, y, z), x = x, y = y, z = z, tree = tree }
end

local function pollChop(actor, order, state, context)
    local work = state.work
    local current = now()
    if workActive(actor, "chop_tree") then
        local health = treeHealth(work.tree)
        if health ~= nil and work.lastHealth ~= nil and health < work.lastHealth then
            -- Our own emulated hit already moved lastHealth; any further drop
            -- came from vanilla's animation event, so native events work.
            chopSession.native, chopSession.fallback = true, false
            work.lastProgressAt = current
        end
        if health ~= nil then work.lastHealth = health end
        claim(work.key, order.id, context.actorId)
        if current - work.startedAt > config("productionChopMaxMs", 180000) then
            local cancelled, cancelReason = cancelWork(actor, "production_chop_timeout")
            if cancelled ~= true then return false, cancelReason or "chop_cancel_failed" end
            state.work, state.target = nil, nil
            releaseClaim(work.key, context.actorId)
            noteCandidateFailure(order, "tree", work.key, "chop_timeout")
            return false, "chop_timeout"
        end
        if not chopSession.native
            and current - work.lastProgressAt >= config("productionChopStallMs", 6000) then
            chopSession.fallback = true
        end
        if chopSession.fallback and not chopSession.native
            and current - (work.lastEmulatedAt or 0) >= config("productionChopFallbackHitMs", 1500) then
            work.lastEmulatedAt = current
            local native = natives()
            local emulated = native and type(native.emulateWorkEvent) == "function"
                and native.emulateWorkEvent(actor, "chop_tree", "ChopTree")
            if emulated == true then
                metrics.emulatedChopHits = metrics.emulatedChopHits + 1
                local after = treeHealth(work.tree)
                if after ~= nil and (work.lastHealth == nil or after < work.lastHealth) then
                    work.lastProgressAt = current
                end
                if after ~= nil then work.lastHealth = after end
            end
        end
        return true, "production_chopping"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "chop_finish_failed" end
    state.work = nil
    releaseClaim(work.key, context.actorId)
    local square = U().gridSquare(work.x, work.y, work.z)
    local felled = not treeInWorld(work.tree) or (square ~= nil and treeOn(square) ~= work.tree)
    if work.tool and not notBroken(work.tool) then
        speak(actor, "work.tool.broken", { U().itemName(work.tool) },
            "broken:" .. tostring(work.startedAt), context.runtime)
    end
    if not felled then
        state.target = nil
        if not enduranceSufficient(actor) then
            local handled, reason, terminal = rest(actor, order, state, "work.fell.tired",
                context.runtime)
            if handled ~= nil then return handled, reason, terminal end
        end
        noteCandidateFailure(order, "tree", work.key, "chop_interrupted")
        return false, "chop_interrupted"
    end
    state.target = nil
    local logs = square and math.max(0, countItems(square, "Base.Log", 64) - (work.logsBefore or 0)) or 0
    metrics.treesFelled = metrics.treesFelled + 1
    SC.BaseLife.recordProductionProgress(order.id, 1)
    SC.BaseLife.noteProductionCounter("treesFelled", 1)
    if logs > 0 then
        SC.BaseLife.noteProductionCounter("logsDropped", logs)
        if type(order.settings) == "table" and order.settings.haulLogs == true then
            local linked, linkReason = SC.BaseLife.linkProductionHaul(order.id, logs)
            state.haulBlocker = linked == true and nil or linkReason
        end
    end
    speak(actor, "work.fell.timber", nil, work.key, context.runtime)
    resetScan(order, "tree")
    if order.completed >= order.requested then return completeOrder(order, "trees_felled") end
    return true, "production_tree_felled"
end

local function updateFell(actor, order, state, context)
    if state.work and state.work.kind == "chop_tree" then
        return pollChop(actor, order, state, context)
    end
    if order.completed >= order.requested then return completeOrder(order, "trees_felled") end
    if state.restUntil ~= nil or not enduranceSufficient(actor) then
        local handled, reason, terminal = rest(actor, order, state, "work.fell.tired", context.runtime)
        if handled ~= nil then return handled, reason, terminal end
    end
    local axe = findInventoryTool(actor, "choptree")
    if not axe then return fetchTool(actor, order, state, "choptree") end
    local zone = zoneFor(order)
    if not zone then return blockOrder(order, "invalid_production_zone") end
    local target = state.target
    if target then
        local square = U().gridSquare(target.x, target.y, target.z)
        if not square or not treeInWorld(target.tree) or treeOn(square) ~= target.tree then
            releaseClaim(target.key, context.actorId)
            target, state.target = nil, nil
        end
    end
    if not target then
        state.phase = "seeking"
        local candidate, reason, terminal = nextZoneCandidate(order, "tree", zone, inspectTree,
            context.actorId, false)
        if not candidate then
            if terminal then return blockOrder(order, reason) end
            return true, reason
        end
        claim(candidate.key, order.id, context.actorId)
        state.target, target = candidate, candidate
    end
    local square = U().gridSquare(target.x, target.y, target.z)
    if not square then return false, "production_target_unloaded" end
    if lumberNight() and SC.BaseLife.isInside(square) ~= true then
        -- Not a failure: rewind so the same tree is found again at dawn.
        releaseClaim(target.key, context.actorId)
        state.target = nil
        resetScan(order, "tree")
        return blockOrder(order, "lumber_night")
    end
    state.phase = "approaching"
    local approach, approachReason = approachSquare(actor, square, "move_to_production_tree",
        nil, true)
    if approach == "failed" then
        noteCandidateFailure(order, "tree", target.key, approachReason)
        releaseClaim(target.key, context.actorId)
        state.target = nil
        return false, approachReason
    end
    if approach ~= "arrived" then return true, approachReason end
    if threatNearby(actor, context.runtime) then return false, "unsafe_area" end
    local health = treeHealth(target.tree)
    local accepted, reason = U().move(actor, "walk", {
        action = "chop_tree", tree = target.tree, tool = axe, targetSquare = square,
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "chop_tree") then
        noteCandidateFailure(order, "tree", target.key, reason)
        releaseClaim(target.key, context.actorId)
        state.target = nil
        return false, reason or "production_chop_rejected"
    end
    local current = now()
    state.work = {
        kind = "chop_tree", tree = target.tree, tool = axe, key = target.key,
        x = target.x, y = target.y, z = target.z, startedAt = current,
        lastHealth = health, lastProgressAt = current,
        logsBefore = countItems(square, "Base.Log", 64),
    }
    state.phase = "working"
    if state.spokeStart ~= true then
        state.spokeStart = true
        speak(actor, "work.fell.start", nil, order.id, context.runtime)
    end
    return true, "production_chop_started"
end

-- ---------------------------------------------------------------------------
-- Saw planks
-- ---------------------------------------------------------------------------

local function plankKeys(inventory)
    local keys = {}
    for _, item in ipairs(U().inventoryItems(inventory, 256)) do
        if U().itemType(item) == "Base.Plank" then keys[itemKey(item)] = true end
    end
    return keys
end

local function withdrawLog(actor, order, state)
    if not SC.BaseWork or type(SC.BaseWork.withdrawFromStorage) ~= "function" then
        return blockOrder(order, "base_work_unavailable")
    end
    local storage = storageById(order.sourceStorageId)
    if not storage or storage.withdrawals == false then
        return blockOrder(order, "production_source_invalid")
    end
    local container = SC.BaseLife.resolveContainer(storage)
    if not container then return blockOrder(order, "production_source_unloaded") end
    local log = state.pendingLog
    if log and U().inventoryContains(container, log) ~= true then log, state.pendingLog = nil, nil end
    if not log then
        if SC.BaseLife.availableCount(storage, "Base.Log") <= 0 then
            return blockOrder(order, "no_logs_in_storage")
        end
        for _, item in ipairs(U().inventoryItems(container, config("campStorageItemBudget", 80))) do
            if U().itemType(item) == "Base.Log" and not protectedItem(item, actor) then
                log = item
                break
            end
        end
        if not log then return blockOrder(order, "no_logs_in_storage") end
        state.pendingLog = log
    end
    state.phase = "withdrawing"
    local ok, reason = SC.BaseWork.withdrawFromStorage(actor, state, storage, container, log)
    if ok == true and reason == "base_supply_taken" then
        state.pendingLog = nil
        if not markCargo(log, order.id) then return false, "production_marker_failed" end
        return true, "production_log_taken"
    end
    if ok ~= true then
        state.pendingLog = nil
        return false, reason or "production_log_withdrawal_failed"
    end
    return true, reason
end

local function sawFailure(order, state, reason)
    state.sawFailures = (state.sawFailures or 0) + 1
    if state.sawFailures >= config("productionCandidateMaxAttempts", 3) then
        state.sawFailures = 0
        return blockOrder(order, reason)
    end
    return false, reason
end

-- Reconcile the vanilla recipe's committed inventory effect exactly once. The
-- actor ModData receipt survives interruption/save and carries the pre-action
-- plank identities, while production cargo markers make an already-adopted
-- result idempotent.
local function reconcileSaw(actor, order, work)
    local inventory = U().inventory(actor)
    if inventory == nil then return false, "saw_inventory_unavailable", true end
    local logGone
    if work.log ~= nil then
        logGone = U().containerContainsIdentity(inventory, work.log, 4096) == false
    else
        logGone = markedCargo(inventory, order.id, "Base.Log") == nil
    end
    local before = type(work.before) == "table" and work.before or nil
    local allPlanks, created, attributed = {}, {}, 0
    for _, item in ipairs(U().inventoryItems(inventory, 256)) do
        if U().itemType(item) == "Base.Plank" then
            allPlanks[#allPlanks + 1] = item
            if cargoOrder(item) == order.id then attributed = attributed + 1
            elseif cargoOrder(item) == nil and (before == nil or not before[itemKey(item)]) then
                created[#created + 1] = item
            end
        end
    end
    if before == nil then
        local produced = math.max(0, #allPlanks - math.max(0,
            math.floor(tonumber(work.beforeCount) or 0)))
        local needed = math.max(0, produced - attributed)
        local selected = {}
        for index = #created, math.max(1, #created - needed + 1), -1 do
            selected[#selected + 1] = created[index]
        end
        created = selected
    end
    if not logGone then return false, "saw_not_committed", false end
    if #created == 0 and attributed == 0 then return false, "saw_incomplete", true end
    for _, item in ipairs(created) do
        if not markCargo(item, order.id) then return false, "production_marker_failed", true end
    end
    if #created > 0 then
        metrics.planksMade = metrics.planksMade + #created
        SC.BaseLife.noteProductionCounter("planksMade", #created)
    end
    clearSawReceipt(actor, order.id)
    return true, "production_planks_made", true
end

local function pollSaw(actor, order, state, context)
    local work = state.work
    if workActive(actor, "saw_logs") then
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_saw_timeout")
            if cancelled ~= true then return false, cancelReason or "saw_cancel_failed" end
            state.work = nil
            clearSawReceipt(actor, order.id)
            return blockOrder(order, "saw_timeout")
        end
        return true, "production_sawing"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "saw_finish_failed" end
    if work.saw and not notBroken(work.saw) then
        speak(actor, "work.tool.broken", { U().itemName(work.saw) },
            "broken:" .. tostring(work.startedAt), context.runtime)
    end
    local reconciled, reason = reconcileSaw(actor, order, work)
    if reconciled ~= true then
        return sawFailure(order, state, reason == "saw_not_committed" and "saw_incomplete" or reason)
    end
    state.work = nil
    state.sawFailures = 0
    return true, reason
end

local function updateSaw(actor, order, state, context)
    if state.work and state.work.kind == "saw_logs" then
        return pollSaw(actor, order, state, context)
    end
    local inventory = U().inventory(actor)
    local plank = markedCargo(inventory, order.id, "Base.Plank")
    if plank then return depositCargo(actor, order, state, plank, context.runtime) end
    local receipt = sawReceiptFor(actor, order.id)
    if receipt then
        local log = markedCargo(inventory, order.id, "Base.Log")
        if workActive(actor, "saw_logs") then
            state.work = {
                kind = "saw_logs", log = log, saw = findInventoryTool(actor, "saw"),
                beforeCount = receipt.beforeCount,
                startedAt = tonumber(receipt.startedAt) or now(),
            }
            return pollSaw(actor, order, state, context)
        end
        if log ~= nil then
            -- The saved action never committed; the marked input remains the
            -- exact retry candidate and no output attribution is necessary.
            clearSawReceipt(actor, order.id)
        else
            local recovered, recoveryReason = reconcileSaw(actor, order, {
                beforeCount = receipt.beforeCount, log = nil, startedAt = receipt.startedAt,
            })
            if recovered == true then return true, recoveryReason end
            return sawFailure(order, state, recoveryReason)
        end
    end
    if order.completed >= order.requested then
        local leftover = markedCargo(inventory, order.id, "Base.Log")
        if leftover then clearCargo(leftover, order.id) end
        return completeOrder(order, "planks_delivered")
    end
    local log = markedCargo(inventory, order.id, "Base.Log")
    if not log then return withdrawLog(actor, order, state) end
    local saw = findInventoryTool(actor, "saw")
    if not saw then return fetchTool(actor, order, state, "saw") end
    local _, capacity, ratio = U().inventoryLoad(actor)
    if (tonumber(capacity) or 0) > 0 and (tonumber(ratio) or 0) > 0.85 then
        return blockOrder(order, "worker_overloaded")
    end
    local before = plankKeys(inventory)
    if not writeSawReceipt(actor, order, log, before) then
        return false, "production_saw_receipt_failed"
    end
    state.phase = "working"
    local accepted, reason = U().move(actor, "walk", { action = "saw_logs", log = log, saw = saw })
    if accepted ~= true and transientRejection(reason) then
        clearSawReceipt(actor, order.id)
        return true, reason
    end
    if accepted ~= true or not workActive(actor, "saw_logs") then
        clearSawReceipt(actor, order.id)
        return sawFailure(order, state, reason or "saw_rejected")
    end
    state.work = { kind = "saw_logs", log = log, saw = saw, before = before, startedAt = now() }
    return true, "production_sawing"
end

-- ---------------------------------------------------------------------------
-- Graves
-- ---------------------------------------------------------------------------

local function naturalFloor(square)
    local floor, ok = invoke(square, "getFloor")
    if not ok or floor == nil then return false end
    local name, nameOk = invoke(floor, "getTextureName")
    name = nameOk and tostring(name or "") or ""
    return string.sub(name, 1, 23) == "floors_exterior_natural"
        or string.sub(name, 1, 17) == "blends_natural_01"
end

local function inRoom(square)
    local value, ok = invoke(square, "isInARoom")
    return ok and value == true
end

local function graveObjects(square)
    local result = {}
    U().squareSpecialObjects(square, function(object)
        local name, ok = invoke(object, "getName")
        if ok and name == "EmptyGraves" then result[#result + 1] = object end
    end, 16)
    return result
end

local function graveCapacity(object)
    if type(ISEmptyGraves) == "table" and type(ISEmptyGraves.getMaxCorpses) == "function" then
        local ok, value = pcall(ISEmptyGraves.getMaxCorpses, object)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 5
end

local function graveInfo(object)
    local data = U().modData(object) or {}
    local x, y, z = U().position(U().squareOf(object))
    if x == nil then return nil end
    local north, northOk = invoke(object, "getNorth")
    return {
        object = object, x = x, y = y, z = z or 0,
        corpses = tonumber(data.corpses) or 0, filled = data.filled == true,
        spriteType = data.spriteType, north = northOk and north == true,
        key = "grave:" .. pointKey(x, y, z or 0),
    }
end

local function primaryGraveAt(point)
    local square = point and U().gridSquare(point.x, point.y, point.z) or nil
    if not square then return nil end
    for _, object in ipairs(graveObjects(square)) do
        local info = graveInfo(object)
        if info and info.spriteType == "sprite1" then return info end
    end
    return nil
end

local function graveOpen(info)
    return info ~= nil and not info.filled and info.corpses < graveCapacity(info.object)
end

local function gravePartner(info)
    if info.north then return info.x, info.y - 1 end
    return info.x - 1, info.y
end

local burialBodyNear
local burialBodyCandidate

local function graveSiteInspector(zone, bodyAnchor)
    return function(square, x, y, z)
        if tonumber(z) ~= 0 or x - 1 < zone.x1 then return nil end
        local partner = U().gridSquare(x - 1, y, z)
        if not partner then return nil end
        if inRoom(square) or inRoom(partner) then return nil end
        if not naturalFloor(square) or not naturalFloor(partner) then return nil end
        if #graveObjects(square) > 0 or #graveObjects(partner) > 0 then return nil end
        if not U().isSquareFree(square) or not U().isSquareFree(partner) then return nil end
        if bodyAnchor then
            local radius = math.max(0, math.floor(config("productionBurialBodyRadius", 2)))
            if bodyAnchor.z ~= z or bodyAnchor.x < x - 1 - radius
                or bodyAnchor.x > x + radius or bodyAnchor.y < y - radius
                or bodyAnchor.y > y + radius then return nil end
        end
        return { key = "grave-site:" .. pointKey(x, y, z), x = x, y = y, z = z }
    end
end

local function pollDig(actor, order, state, context)
    local work = state.work
    if workActive(actor, "dig_grave") then
        if work.bodyKey then claim(work.bodyKey, order.id, context.actorId) end
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_dig_timeout")
            if cancelled ~= true then return false, cancelReason or "dig_cancel_failed" end
            state.work, state.digTarget = nil, nil
            releaseClaim(work.key, context.actorId)
            releaseClaim(work.bodyKey, context.actorId)
            state.burialDigBody = nil
            noteCandidateFailure(order, "grave-site", work.key, "dig_timeout")
            return false, "dig_timeout"
        end
        return true, "production_digging"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "dig_finish_failed" end
    state.work, state.digTarget = nil, nil
    releaseClaim(work.key, context.actorId)
    releaseClaim(work.bodyKey, context.actorId)
    state.burialDigBody = nil
    local square = U().gridSquare(work.x, work.y, work.z)
    local partner = U().gridSquare(work.x - 1, work.y, work.z)
    if not square or not partner or #graveObjects(square) == 0 or #graveObjects(partner) == 0 then
        noteCandidateFailure(order, "grave-site", work.key, "dig_incomplete")
        return false, "dig_incomplete"
    end
    metrics.gravesDug = metrics.gravesDug + 1
    SC.BaseLife.noteProductionCounter("gravesDug", 1)
    SC.BaseLife.noteProductionGrave(order.id, { x = work.x, y = work.y, z = work.z })
    speak(actor, "burial.dig.done", nil, work.key, context.runtime)
    resetScan(order, "grave-site")
    resetScan(order, "grave")
    resetScan(order, "burial-body")
    if work.forBurial ~= true then
        SC.BaseLife.recordProductionProgress(order.id, 1)
        if order.completed >= order.requested then return completeOrder(order, "graves_dug") end
    end
    return true, "production_grave_dug"
end

local function digNext(actor, order, state, context, forBurial)
    local shovel = findInventoryTool(actor, "diggrave")
    if not shovel then return fetchTool(actor, order, state, "diggrave") end
    local zone = zoneFor(order)
    if not zone then return blockOrder(order, "invalid_production_zone") end
    local bodyAnchor = forBurial == true and state.burialDigBody or nil
    if bodyAnchor then
        local present = false
        U().squareStaticMovingObjects(bodyAnchor.square, function(object)
            if object == bodyAnchor.body then present = true end
        end, 16)
        if not present then
            releaseClaim(bodyAnchor.key, context.actorId)
            state.burialDigBody, bodyAnchor = nil, nil
        else claim(bodyAnchor.key, order.id, context.actorId) end
    end
    if forBurial == true and not bodyAnchor then
        local candidate, reason, terminal = nextZoneCandidate(order, "burial-body", zone,
            function(square, x, y, z)
                return burialBodyCandidate and burialBodyCandidate(square, x, y, z,
                    order, actor) or nil
            end, context.actorId, false)
        if not candidate then
            if terminal then return blockOrder(order, "no_bodies_in_burial_area") end
            return true, reason
        end
        claim(candidate.key, order.id, context.actorId)
        state.burialDigBody, bodyAnchor = candidate, candidate
    end
    local target = state.digTarget
    if not target then
        state.phase = "seeking"
        local candidate, reason, terminal = nextZoneCandidate(order, "grave-site", zone,
            graveSiteInspector(zone, bodyAnchor), context.actorId, false)
        if not candidate then
            if terminal then
                releaseClaim(bodyAnchor and bodyAnchor.key, context.actorId)
                state.burialDigBody = nil
                return blockOrder(order, forBurial and "no_grave_site_near_body" or reason)
            end
            return true, reason
        end
        claim(candidate.key, order.id, context.actorId)
        state.digTarget, target = candidate, candidate
    end
    claim(target.key, order.id, context.actorId)
    local square = U().gridSquare(target.x, target.y, target.z)
    if not square then
        releaseClaim(target.key, context.actorId)
        releaseClaim(bodyAnchor and bodyAnchor.key, context.actorId)
        state.digTarget, state.burialDigBody = nil, nil
        return false, "production_target_unloaded"
    end
    state.phase = "approaching"
    -- Never stand on either half of the grave being dug: the vanilla site
    -- check rejects an occupied square.
    local approach, approachReason = approachSquare(actor, square, "move_to_production_grave", {
        { x = target.x, y = target.y, z = target.z }, { x = target.x - 1, y = target.y, z = target.z },
    })
    if approach == "failed" then
        noteCandidateFailure(order, "grave-site", target.key, approachReason)
        releaseClaim(target.key, context.actorId)
        state.digTarget = nil
        return false, approachReason
    end
    if approach ~= "arrived" then return true, approachReason end
    local accepted, reason = U().move(actor, "walk", {
        action = "dig_grave", square = square, tool = shovel, north = false, targetSquare = square,
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "dig_grave") then
        noteCandidateFailure(order, "grave-site", target.key, reason)
        releaseClaim(target.key, context.actorId)
        state.digTarget = nil
        return false, reason or "production_dig_rejected"
    end
    state.work = {
        kind = "dig_grave", x = target.x, y = target.y, z = target.z, key = target.key,
        startedAt = now(), forBurial = forBurial == true,
        bodyKey = bodyAnchor and bodyAnchor.key or nil,
    }
    state.phase = "digging"
    speak(actor, "burial.dig.start", nil, target.key, context.runtime)
    return true, "production_digging"
end

local function updateDig(actor, order, state, context)
    if state.work and state.work.kind == "dig_grave" then
        return pollDig(actor, order, state, context)
    end
    if order.completed >= order.requested then return completeOrder(order, "graves_dug") end
    return digNext(actor, order, state, context, false)
end

-- ---------------------------------------------------------------------------
-- Bury the dead
-- ---------------------------------------------------------------------------

local function bodyKey(body)
    return "body:" .. tostring(body)
end

local function commitBurialOutcome(orderId, key)
    local outcome = tostring(orderId) .. ":" .. tostring(key)
    if burialOutcomes[outcome] then return false end
    burialOutcomes[outcome] = true
    burialOutcomeOrder[#burialOutcomeOrder + 1] = outcome
    while #burialOutcomeOrder > 256 do
        burialOutcomes[table.remove(burialOutcomeOrder, 1)] = nil
    end
    return true
end

local function bodyPlayerNumber(actor)
    local number, ok = invoke(actor, "getPlayerNum")
    return ok and tonumber(number) or nil
end

local function bodyEligible(body, order, actor)
    if not U().instanceOf(body, "IsoDeadBody") then return false end
    local fake, fakeOk = invoke(body, "isFakeDead")
    if fakeOk and fake == true then return false, "fake_dead" end
    local animal, animalOk = invoke(body, "isAnimal")
    if animalOk and animal == true then return false, "animal" end
    local _, _, z = U().position(body)
    if tonumber(z) ~= 0 then return false, "not_ground_level" end
    local container = invoke(body, "getContainer")
    local items = container and U().inventoryItems(container, 64) or {}
    if #items > 0 then
        if type(order.settings) ~= "table" or order.settings.withBelongings ~= true then
            return false, "carries_items"
        end
        for _, item in ipairs(items) do
            if SC.WorkTransport and type(SC.WorkTransport.foreignProtected) == "function" then
                local protected, reason = SC.WorkTransport.foreignProtected(item, actor)
                if protected and reason ~= "favorite_item" then return false, "protected_items" end
            end
        end
    end
    return true
end

burialBodyCandidate = function(square, x, y, z, order, actor)
    local found
    U().squareStaticMovingObjects(square, function(object)
        if found then return end
        local eligible = bodyEligible(object, order, actor)
        if eligible then
            found = {
                key = bodyKey(object), body = object, square = square,
                x = x, y = y, z = z,
            }
        end
    end, 16)
    return found
end

burialBodyNear = function(order, grave, actor, id)
    local zone = zoneFor(order)
    if not zone then return nil, nil, "invalid_production_zone" end
    local radius = math.max(0, math.floor(config("productionBurialBodyRadius", 2)))
    local px, py = gravePartner(grave)
    local carrying, claimed = 0, 0
    for y = math.min(grave.y, py) - radius, math.max(grave.y, py) + radius do
        for x = math.min(grave.x, px) - radius, math.max(grave.x, px) + radius do
            if x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2 then
                local square = U().gridSquare(x, y, grave.z)
                if square then
                    local found
                    U().squareStaticMovingObjects(square, function(object)
                        if found then return end
                        local key = bodyKey(object)
                        local cooling = onCooldown(order, "body", key)
                        if not cooling then
                            local eligible, why = bodyEligible(object, order, actor)
                            if eligible and claimActive(key, id) then claimed = claimed + 1
                            elseif eligible then found = object
                            elseif why == "carries_items" then carrying = carrying + 1 end
                        end
                    end, 16)
                    if found then return found, square end
                end
            end
        end
    end
    if carrying > 0 then return nil, nil, "bodies_carry_items:" .. tostring(carrying) end
    if claimed > 0 then return nil, nil, "burial_targets_claimed" end
    return nil, nil, "no_bodies_near_grave"
end

-- ISBuryCorpse removes the body whose lastPlayerGrabbed matches the burier.
-- Vanilla writes that value when a player drags a body; companions bury a
-- body already lying at the graveside, so write it for exactly one body.
local function tagBody(body, square, actor)
    local number = bodyPlayerNumber(actor)
    if number == nil then return false end
    U().squareStaticMovingObjects(square, function(other)
        if other ~= body then
            local data = U().modData(other)
            if type(data) == "table" and tonumber(data.lastPlayerGrabbed) == number then
                data.lastPlayerGrabbed = nil
            end
        end
    end, 16)
    local data = U().modData(body)
    if type(data) ~= "table" then return false end
    data.lastPlayerGrabbed = number
    return tonumber(data.lastPlayerGrabbed) == number
end

local function untagBody(body, actor)
    local data = body and U().modData(body) or nil
    local number = bodyPlayerNumber(actor)
    if type(data) == "table" and number ~= nil and tonumber(data.lastPlayerGrabbed) == number then
        data.lastPlayerGrabbed = nil
    end
end

local function headSquare(grave)
    local candidates = grave.north
        and { { grave.x, grave.y + 1 }, { grave.x, grave.y - 2 } }
        or { { grave.x + 1, grave.y }, { grave.x - 2, grave.y } }
    for _, point in ipairs(candidates) do
        local square = U().gridSquare(point[1], point[2], grave.z)
        if square and U().isSquareFree(square) and #graveObjects(square) == 0 then
            return { x = point[1], y = point[2], z = grave.z }
        end
    end
    return nil
end

local function placeMarker(order, grave)
    if type(order.settings) ~= "table" or order.settings.marker ~= "wood" then return false end
    if not SC.BaseWork or type(SC.BaseWork.recipeForKind) ~= "function"
        or type(SC.BaseWork.recipeInfo) ~= "function" then return false end
    local recipeId = SC.BaseWork.recipeForKind("grave_marker")
    if not recipeId or not SC.BaseWork.recipeInfo(recipeId) then
        SC.BaseLife.noteHistory("grave_marker_unavailable", { orderId = order.id })
        return false
    end
    local head = headSquare(grave)
    if not head then
        SC.BaseLife.noteHistory("grave_marker_no_space", { orderId = order.id })
        return false
    end
    local ok = SC.BaseLife.enqueueJob({
        type = "build", priority = 2, recipeId = recipeId, face = 1, target = head,
    })
    return ok == true
end

local function pollFill(actor, order, state, context)
    local work = state.work
    if workActive(actor, "fill_grave") then
        claim(work.graveKey, order.id, context.actorId)
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_fill_timeout")
            if cancelled ~= true then return false, cancelReason or "fill_cancel_failed" end
            state.work = nil
            releaseClaim(work.graveKey, context.actorId)
            return blockOrder(order, "fill_timeout")
        end
        return true, "production_filling"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "fill_finish_failed" end
    state.work = nil
    releaseClaim(work.graveKey, context.actorId)
    local info = primaryGraveAt(work.grave)
    if not info or not info.filled then
        state.fillFailures = (state.fillFailures or 0) + 1
        if state.fillFailures >= config("productionCandidateMaxAttempts", 3) then
            state.fillFailures = 0
            return blockOrder(order, "fill_unverified")
        end
        return false, "fill_unverified"
    end
    state.fillFailures = 0
    metrics.gravesClosed = metrics.gravesClosed + 1
    SC.BaseLife.noteProductionCounter("gravesClosed", 1)
    SC.BaseLife.forgetProductionGrave(order.id, work.grave)
    if ceremony(actor, info, context.runtime) then state.pendingSalute = true end
    placeMarker(order, info)
    return true, "production_grave_closed"
end

local function fillGrave(actor, order, state, grave, context)
    if claimActive(grave.key, context.actorId) then return true, "production_grave_claimed" end
    claim(grave.key, order.id, context.actorId)
    local shovel = findInventoryTool(actor, "diggrave")
    if not shovel then
        local handled, reason, terminal = fetchTool(actor, order, state, "diggrave")
        if terminal == true or handled ~= true then releaseClaim(grave.key, context.actorId) end
        return handled, reason, terminal
    end
    local square = U().gridSquare(grave.x, grave.y, grave.z)
    if not square then
        releaseClaim(grave.key, context.actorId)
        return false, "production_target_unloaded"
    end
    state.phase = "approaching"
    local approach, approachReason = approachSquare(actor, square, "move_to_production_grave")
    if approach == "failed" then
        releaseClaim(grave.key, context.actorId)
        return blockOrder(order, approachReason)
    end
    if approach ~= "arrived" then return true, approachReason end
    local accepted, reason = U().move(actor, "walk", {
        action = "fill_grave", grave = grave.object, tool = shovel, targetSquare = square,
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "fill_grave") then
        releaseClaim(grave.key, context.actorId)
        state.fillFailures = (state.fillFailures or 0) + 1
        if state.fillFailures >= config("productionCandidateMaxAttempts", 3) then
            state.fillFailures = 0
            return blockOrder(order, reason or "fill_rejected")
        end
        return false, reason or "fill_rejected"
    end
    state.work = {
        kind = "fill_grave", startedAt = now(),
        grave = { x = grave.x, y = grave.y, z = grave.z },
        graveKey = grave.key,
    }
    state.phase = "filling"
    return true, "production_filling"
end

local function pollBury(actor, order, state, context)
    local work = state.work
    if workActive(actor, "bury_body") then
        claim(work.key, order.id, context.actorId)
        claim(work.graveKey, order.id, context.actorId)
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_bury_timeout")
            if cancelled ~= true then return false, cancelReason or "bury_cancel_failed" end
            untagBody(work.body, actor)
            state.work = nil
            releaseClaim(work.key, context.actorId)
            releaseClaim(work.graveKey, context.actorId)
            noteCandidateFailure(order, "body", work.key, "bury_timeout")
            return false, "bury_timeout"
        end
        return true, "production_burying"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "bury_finish_failed" end
    state.work = nil
    local stillThere = false
    U().squareStaticMovingObjects(work.bodySquare, function(object)
        if object == work.body then stillThere = true end
    end, 16)
    local info = primaryGraveAt(work.grave)
    local corpses = info and info.corpses or work.corpsesBefore
    if stillThere or corpses <= work.corpsesBefore then
        if stillThere then untagBody(work.body, actor) end
        releaseClaim(work.key, context.actorId)
        releaseClaim(work.graveKey, context.actorId)
        noteCandidateFailure(order, "body", work.key, "burial_unverified")
        return false, "burial_unverified"
    end
    local outcomeKey = tostring(order.id) .. ":" .. tostring(work.key)
    if burialOutcomes[outcomeKey] then
        releaseClaim(work.key, context.actorId)
        releaseClaim(work.graveKey, context.actorId)
        return true, "production_body_already_credited"
    end
    local progressed, progressReason = SC.BaseLife.recordProductionProgress(order.id, 1)
    if progressed ~= true then
        releaseClaim(work.key, context.actorId)
        releaseClaim(work.graveKey, context.actorId)
        return false, progressReason or "burial_progress_failed"
    end
    commitBurialOutcome(order.id, work.key)
    metrics.bodiesBuried = metrics.bodiesBuried + 1
    SC.BaseLife.noteProductionCounter("bodiesBuried", 1)
    if info then SC.BaseLife.noteProductionGrave(order.id, { x = info.x, y = info.y, z = info.z }) end
    releaseClaim(work.key, context.actorId)
    releaseClaim(work.graveKey, context.actorId)
    speak(actor, "burial.lower", nil, work.key, context.runtime)
    return true, "production_body_buried"
end

-- Inspect at most one remembered grave plus the ordinary square-budgeted zone
-- slice per update. A no-body result advances this pass instead of pinning the
-- order forever to the first open grave.
local function burialPairFor(order, state, context, actor)
    local search = state.burialSearch
    if type(search) ~= "table" then
        search = { checked = {}, carrying = 0, busy = false }
        state.burialSearch = search
    end
    local function inspect(info)
        if not graveOpen(info) or search.checked[info.key] then return nil end
        search.checked[info.key] = true
        if claimActive(info.key, context.actorId) then
            search.busy = true
            return nil, "production_grave_claimed"
        end
        local body, square, reason = burialBodyNear(order, info, actor, context.actorId)
        if body then return info, body, square end
        local count = tonumber(string.match(tostring(reason or ""), "^bodies_carry_items:(%d+)$"))
        if count then search.carrying = search.carrying + count end
        if reason == "burial_targets_claimed" then search.busy = true end
        return nil, reason
    end
    for _, point in ipairs(order.graves or {}) do
        local info = primaryGraveAt(point)
        if graveOpen(info) and not search.checked[info.key] then
            local grave, body, square = inspect(info)
            if grave then
                state.burialSearch = nil
                return grave, body, square, "production_candidate_found", false
            end
            return nil, nil, nil, "production_burial_pair_pending", false
        end
    end
    local zone = zoneFor(order)
    if not zone then
        state.burialSearch = nil
        return nil, nil, nil, "invalid_production_zone", true
    end
    local grave, reason, terminal = nextZoneCandidate(order, "grave", zone, function(square)
        for _, object in ipairs(graveObjects(square)) do
            local info = graveInfo(object)
            if info and info.spriteType == "sprite1" and graveOpen(info)
                and not search.checked[info.key] then
                if claimActive(info.key, context.actorId) then
                    search.checked[info.key], search.busy = true, true
                else return info end
            end
        end
        return nil
    end, context.actorId, true)
    if grave then
        SC.BaseLife.noteProductionGrave(order.id, { x = grave.x, y = grave.y, z = grave.z })
        local viable, body, square = inspect(grave)
        if viable then
            state.burialSearch = nil
            return viable, body, square, reason, false
        end
        return nil, nil, nil, "production_burial_pair_pending", false
    end
    if terminal then
        state.burialSearch = nil
        if search.busy then return nil, nil, nil, "production_burial_targets_claimed", false end
        if search.carrying > 0 then
            return nil, nil, nil, "bodies_carry_items:" .. tostring(search.carrying), true
        end
        return nil, nil, nil, "no_bodies_near_open_grave", true
    end
    return nil, nil, nil, reason or "production_scan_pending", false
end

local function updateBury(actor, order, state, context)
    local work = state.work
    if work and work.kind == "bury_body" then return pollBury(actor, order, state, context) end
    if work and work.kind == "fill_grave" then return pollFill(actor, order, state, context) end
    if work and work.kind == "dig_grave" then return pollDig(actor, order, state, context) end
    local settings = type(order.settings) == "table" and order.settings or {}
    -- Close any grave this order filled to capacity before taking more work.
    for _, point in ipairs(order.graves or {}) do
        local info = primaryGraveAt(point)
        if info and not info.filled and info.corpses >= graveCapacity(info.object) then
            return fillGrave(actor, order, state, info, context)
        end
    end
    if order.completed >= order.requested then
        if settings.closeWhenDone == true then
            for _, point in ipairs(order.graves or {}) do
                local info = primaryGraveAt(point)
                if info and not info.filled and info.corpses > 0 then
                    return fillGrave(actor, order, state, info, context)
                end
            end
        end
        return completeOrder(order, "bodies_buried")
    end
    local target = state.buryTarget
    if target then
        local info = primaryGraveAt(target.grave)
        local stillThere = false
        U().squareStaticMovingObjects(target.bodySquare, function(object)
            if object == target.body then stillThere = true end
        end, 16)
        if not graveOpen(info) or not stillThere then
            releaseClaim(target.key, context.actorId)
            releaseClaim(target.graveKey, context.actorId)
            state.buryTarget, target = nil, nil
        else
            target.graveInfo = info
            claim(target.key, order.id, context.actorId)
            claim(target.graveKey, order.id, context.actorId)
        end
    end
    if not target then
        local grave, body, bodySquare, reason, terminal = burialPairFor(order, state, context, actor)
        if not grave then
            if terminal then
                if reason == "no_bodies_near_open_grave" and settings.digIfNeeded == true then
                    return digNext(actor, order, state, context, true)
                end
                return blockOrder(order, reason or "no_open_grave")
            end
            return true, reason or "production_scan_pending"
        end
        local key = bodyKey(body)
        claim(key, order.id, context.actorId)
        claim(grave.key, order.id, context.actorId)
        target = {
            body = body, bodySquare = bodySquare, key = key,
            grave = { x = grave.x, y = grave.y, z = grave.z },
            graveInfo = grave, graveKey = grave.key,
        }
        state.buryTarget = target
    end
    local grave = target.graveInfo
    if not grave then
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return false, "production_grave_unavailable"
    end
    local square = U().gridSquare(grave.x, grave.y, grave.z)
    if not square then
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return false, "production_target_unloaded"
    end
    state.phase = "approaching"
    local approach, approachReason = approachSquare(actor, square, "move_to_production_grave")
    if approach == "failed" then
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return blockOrder(order, approachReason)
    end
    if approach ~= "arrived" then return true, approachReason end
    if not tagBody(target.body, target.bodySquare, actor) then
        noteCandidateFailure(order, "body", target.key, "body_tag_failed")
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return false, "body_tag_failed"
    end
    local accepted, moveReason = U().move(actor, "walk", {
        action = "bury_body", grave = grave.object, bodySquare = target.bodySquare,
        targetSquare = square,
    })
    if accepted ~= true and transientRejection(moveReason) then
        untagBody(target.body, actor)
        return true, moveReason
    end
    if accepted ~= true or not workActive(actor, "bury_body") then
        untagBody(target.body, actor)
        noteCandidateFailure(order, "body", target.key, moveReason)
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return false, moveReason or "production_bury_rejected"
    end
    state.work = {
        kind = "bury_body", body = target.body, bodySquare = target.bodySquare,
        key = target.key, graveKey = target.graveKey,
        grave = { x = grave.x, y = grave.y, z = grave.z }, corpsesBefore = grave.corpses,
        startedAt = now(),
    }
    state.buryTarget = nil
    state.phase = "burying"
    return true, "production_burying"
end

-- ---------------------------------------------------------------------------
-- Registry and public API
-- ---------------------------------------------------------------------------

local FAMILIES = { harvest = true, craft = true, earthwork = true, disposal = true }

function Production.register(descriptor)
    if type(descriptor) ~= "table" or type(descriptor.id) ~= "string"
        or not FAMILIES[descriptor.family] or type(descriptor.update) ~= "function" then
        return false, "invalid_production_descriptor"
    end
    if descriptors[descriptor.id] then return false, "duplicate_production_descriptor" end
    if not SC.BaseLife or type(SC.BaseLife.PRODUCTION_OPERATIONS) ~= "table" then
        return false, "base_life_unavailable"
    end
    if SC.BaseLife.PRODUCTION_OPERATIONS[descriptor.id] == nil then
        if type(descriptor.schema) ~= "table" then return false, "production_schema_missing" end
        local registered, reason = SC.BaseLife.registerProductionOperation(
            descriptor.id, descriptor.schema)
        if registered ~= true then return false, reason end
    end
    descriptors[descriptor.id] = descriptor
    descriptorOrder[#descriptorOrder + 1] = descriptor.id
    return true
end

function Production.descriptor(id)
    return descriptors[id]
end

function Production.operations()
    local result = {}
    for _, id in ipairs(descriptorOrder) do
        local descriptor = descriptors[id]
        local schema = SC.BaseLife.PRODUCTION_OPERATIONS[id] or {}
        result[#result + 1] = {
            id = id, family = descriptor.family, unit = schema.unit,
            zoneKinds = schema.zoneKinds, source = schema.source == true,
            destination = schema.destination, maxRequested = schema.maxRequested,
            defaultRequested = schema.defaultRequested,
        }
    end
    return result
end

local function stateFor(actor, orderId)
    local state = actorStates[actor]
    if not state or state.orderId ~= orderId then
        state = { orderId = orderId, phase = "seeking" }
        actorStates[actor] = state
    end
    return state
end

local function notePhase(orderId, id, phase)
    phases[orderId] = phases[orderId] or {}
    phases[orderId][id] = phase
end

function Production.workerPhase(orderId, workerId)
    return phases[orderId] and phases[orderId][workerId] or nil
end

function Production.update(actor, baseState, job, runtime)
    processPendingAmen()
    local orderId = type(job) == "table" and type(job.target) == "table"
        and job.target.orderId or nil
    local order = SC.BaseLife.productionOrder(orderId)
    if not order then return false, "production_order_missing", true end
    if order.state == "paused" then return false, "production_order_paused", false end
    if order.state == "cancelled" or order.state == "completed" then
        return false, "production_order_" .. order.state, true
    end
    -- A blocked order re-checks its blocker on a bounded cadence (missing
    -- tool, empty area, no bodies yet) instead of retrying the failed action.
    if order.state == "blocked" and (tonumber(order.retryAt) or 0) <= now()
        and (job.state ~= "blocked" or (tonumber(job.retryAt) or 0) <= now()) then
        SC.BaseLife.reopenProductionOrder(order.id)
    end
    if order.state ~= "running" then return false, order.blocker or "production_blocked", false end
    local id = actorId(actor)
    if not assigned(order, id) then return false, "production_worker_not_assigned", true end
    local descriptor = descriptors[order.operation]
    if not descriptor then return blockOrder(order, "production_operation_unavailable") end
    local state = stateFor(actor, order.id)
    -- A finished native action starts the facade's human pacing pause. Never
    -- dispatch into it; active work is still polled so its result is claimed.
    if state.work == nil and actorPacing(actor) then return true, "production_pacing" end
    if state.pendingSalute == true then
        state.pendingSalute = nil
        if SC.Relationship and type(SC.Relationship.playEmote) == "function"
            and not threatNearby(actor, runtime) then
            pcall(SC.Relationship.playEmote, actor, "salute")
            return true, "production_ceremony"
        end
    end
    local context = { runtime = runtime, job = job, actorId = id, baseState = baseState }
    local ok, handled, reason, terminal = pcall(descriptor.update, actor, order, state, context)
    if not ok then
        metrics.errors = metrics.errors + 1
        metrics.lastError = tostring(handled)
        Production.cancelActor(actor, "production_error")
        return blockOrder(order, "production_error")
    end
    notePhase(order.id, id, state.phase)
    return handled == true, reason, terminal == true
end

-- A finished or cancelled order leaves no work claim behind: clear its cargo
-- markers from the assigned workers so the items become ordinary stock.
function Production.forgetOrder(orderId, workers)
    Production.retryOrder(orderId)
    phases[orderId] = nil
    for key, entry in pairs(claims) do
        if entry.orderId == orderId then claims[key] = nil end
    end
    for _, workerId in ipairs(type(workers) == "table" and workers or {}) do
        local actor = U().resolveActor(workerId)
        local inventory = actor and U().inventory(actor) or nil
        if inventory then
            for _, item in ipairs(U().inventoryItems(inventory, 256)) do
                clearCargo(item, orderId)
            end
        end
        clearSawReceipt(actor, orderId)
    end
    return true
end

function Production.retryOrder(orderId)
    for key in pairs(scans) do
        if string.sub(key, 1, #tostring(orderId) + 1) == tostring(orderId) .. ":" then
            scans[key] = nil
        end
    end
    return true
end

function Production.cancelActor(actor, reason)
    local state = actor and actorStates[actor] or nil
    local receipt = actor and U().modData(actor) or nil
    receipt = type(receipt) == "table" and receipt[Production.SAW_RECEIPT] or nil
    if not state and type(receipt) ~= "table" then return true end
    local native = natives()
    local work = state and state.work or nil
    local orderId = state and state.orderId or (type(receipt) == "table" and receipt.orderId or nil)
    local order = SC.BaseLife and type(SC.BaseLife.productionOrder) == "function"
        and SC.BaseLife.productionOrder(orderId) or nil
    if work and native and type(native.workKind) == "function"
        and PRODUCTION_WORK_KINDS[native.workKind(actor)] then
        local active = workActive(actor, work.kind)
        local settled, settleReason
        if active then settled, settleReason = cancelWork(actor, reason or "production_cancelled")
        else settled, settleReason = finishWork(actor) end
        if settled ~= true then return false, settleReason or "production_work_cancel_failed" end
    end
    if order and ((work and work.kind == "saw_logs") or type(receipt) == "table") then
        local sawWork = work
        if not sawWork and type(receipt) == "table" then
            sawWork = {
                beforeCount = receipt.beforeCount,
                log = markedCargo(U().inventory(actor), order.id, "Base.Log"),
                startedAt = receipt.startedAt,
            }
        end
        local reconciled, reconcileReason, committed = reconcileSaw(actor, order, sawWork)
        if reconciled ~= true and committed == true then
            return false, reconcileReason or "saw_reconciliation_failed"
        end
        if committed ~= true then clearSawReceipt(actor, order.id) end
    elseif type(receipt) == "table" then
        clearSawReceipt(actor, orderId)
    end
    if work and work.kind == "bury_body" then untagBody(work.body, actor) end
    if state and state.visualAt ~= nil and native and type(native.cancelVisual) == "function" then
        pcall(native.cancelVisual, actor, reason or "production_cancelled")
    end
    local id = actorId(actor)
    for key, entry in pairs(claims) do
        if entry.actorId == id then claims[key] = nil end
    end
    actorStates[actor] = nil
    return true
end

function Production.diagnostics()
    local result = {}
    for key, value in pairs(metrics) do result[key] = value end
    result.chopNativeEvents = chopSession.native == true
    result.chopFallback = chopSession.fallback == true
    result.activeScans, result.claims = 0, 0
    for _ in pairs(scans) do result.activeScans = result.activeScans + 1 end
    for _ in pairs(claims) do result.claims = result.claims + 1 end
    result.pendingAmen = pendingAmen ~= nil
    return result
end

function Production.reset(actor)
    if actor then return Production.cancelActor(actor, "production_reset") end
    local actors = {}
    for value in pairs(actorStates) do actors[#actors + 1] = value end
    for _, value in ipairs(actors) do
        local cancelled, reason = Production.cancelActor(value, "production_reset")
        if cancelled ~= true then return false, reason or "production_reset_failed" end
    end
    actorStates = setmetatable({}, { __mode = "k" })
    scans, claims, phases, ceremonies, ceremonyOrder = {}, {}, {}, {}, {}
    burialOutcomes, burialOutcomeOrder = {}, {}
    pendingAmen = nil
    lastProductionSpeechAt = -math.huge
    chopSession = { native = false, fallback = false }
    for key in pairs(metrics) do
        metrics[key] = type(metrics[key]) == "number" and 0 or nil
    end
    return true
end

-- Test seams: the harness drives session state and time-dependent speech.
function Production._chopSessionForTests()
    return chopSession
end

function Production._ceremonyTopicForTests(actor, salt)
    return ceremonyTopic(actor, salt)
end

Production.register({ id = "fell_trees", family = "harvest", update = updateFell })
Production.register({ id = "saw_planks", family = "craft", update = updateSaw })
Production.register({ id = "dig_graves", family = "earthwork", update = updateDig })
Production.register({ id = "bury_bodies", family = "disposal", update = updateBury })
registerDialogue()

return Production
