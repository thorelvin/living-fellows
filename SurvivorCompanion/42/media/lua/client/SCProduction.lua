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
    grab_body = true, drop_body = true, burn_body = true,
}
-- Written on a body before it is grabbed; the grapple respawns the body as a
-- new object but carries its modData, so the tag finds it after the drop.
Production.HAUL_TAG = "LF_CorpseHaul"
Production.BURNED_TAG = "LF_CorpseBurned"
Production.FALLEN_NAME = "LF_FallenName"
-- Collect/burn helpers live in one table so the module keeps its local count
-- and each function's upvalues well inside Kahlua's limits.
local Disposal = { urgentAt = {} }
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
    ["burial.haul.start"] = { chance = 35, actorMs = 60000 },
    ["burial.haul.drag"] = { chance = 20, actorMs = 45000 },
    ["burial.haul.drop"] = { chance = 25, actorMs = 30000 },
    -- Spoken exactly when danger forces the drop, so it ignores the usual
    -- silence-near-threats rule (still bounded by its actor cooldown).
    ["burial.haul.threat"] = { chance = 100, actorMs = 20000, urgent = true },
    ["burn.ignite"] = { chance = 60, actorMs = 30000 },
    ["burn.watch"] = { chance = 15, actorMs = 60000 },
    ["burn.rain"] = { chance = 50, actorMs = 60000 },
    ["burn.fire_spread"] = { chance = 100, actorMs = 20000, urgent = true },
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
    bodiesDragged = 0, bodiesBurned = 0, fallenBuried = 0,
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
    ["burial.haul.start"] = {
        common = {
            "Grab the ankles. Lift with the legs. Theirs, not yours.",
            "Come on, friend. One last walk. Well, drag.",
            "Room's ready for you. Let's go.",
            "Up you come. Nobody gets left in the yard.",
        },
        brave = { "On three. One... two... never mind, I've got you." },
        cautious = { "Checking twice. Still dead. Okay, moving." },
        caring = { "Easy now. I've got you. You're going somewhere quiet." },
        practical = { "Body secured. Moving." },
        stressed = { "Don't look at me. Don't look at me." },
    },
    ["burial.haul.drag"] = {
        common = {
            "Heavier than they look. They always are.",
            "You could help, you know. No? Figures.",
            "Nearly there. Don't wake up.",
            "Mind the bumps. Not that you'd complain.",
        },
        practical = { "Keep it steady. Almost there." },
        stressed = { "Just keep walking. Just keep walking." },
        low = { "Everybody gets dragged somewhere in the end." },
    },
    ["burial.haul.drop"] = {
        common = { "Your stop.", "Wait here. Not like you're going anywhere.", "And... down." },
        practical = { "Placed. Next." },
    },
    ["burial.haul.threat"] = {
        common = { "Dropping the body! Contact!", "Sorry, pal. Hold that thought." },
        brave = { "Put it down! We've got live ones!" },
        cautious = { "Contact! Leaving the body!" },
    },
    ["burn.ignite"] = {
        common = {
            "Burn, baby, burn!",
            "Disco inferno!",
            "Light 'em up.",
            "Ashes to ashes. We'll skip the dust.",
            "Warmest you've been in weeks, friend.",
            "Cremation. Cheaper than a plot, and no digging.",
        },
        brave = { "Let it burn. Nothing gets up from ash." },
        cautious = { "Stand back. Watch the grass!" },
        caring = { "Go up easy. Nothing down here can hurt you now." },
        practical = { "Fuel poured. Lighter lit. Stand clear." },
        stressed = { "Don't breathe it in. Don't breathe it in." },
        low = { "Used to be barbecues on Sundays." },
        hopeful = { "Up with the smoke, friend. Somewhere better." },
    },
    ["burn.watch"] = {
        common = { "Nobody poke it.", "Keep an eye on the embers.",
            "Smells like... no. Not finishing that sentence." },
        practical = { "Watching the burn. Nothing moves." },
    },
    ["burn.prayer"] = {
        common = {
            "From dust you came. We sped things up. Amen.",
            "Lord, take the smoke. It's all that's left of them.",
            "Let the fire keep what the world couldn't.",
            "Rise with the smoke. Stay up there this time.",
        },
        caring = { "Nothing left to hurt you now. Go on home." },
        cautious = { "Burned clean. Nothing comes back from that. Amen." },
    },
    ["burn.gallows"] = {
        common = {
            "Well done. And I mean that literally.",
            "Another satisfied customer of the Knox County Crematorium.",
            "*hums* Burn, baby, burn... disco inferno. ...Sorry. Someone had to.",
            "Smokey says only you can prevent forest fires. Smokey isn't here.",
            "Nobody gets up from that. Nobody.",
        },
        practical = { "Burn complete. Ash doesn't bite." },
        stressed = { "Okay. It's out. It's out. We're fine." },
    },
    ["burn.fire_spread"] = {
        common = { "Fire's spreading! Get back!", "That's not the pyre anymore! Move!" },
    },
    ["burn.rain"] = {
        common = { "Rain's got the fire. We'll try again later.", "Too wet to burn. Figures." },
    },
    -- A fallen companion's own grave. %1 is the name; never gallows humor.
    ["burial.fallen"] = {
        common = {
            "Rest easy, %1. You watched our backs. We've got it from here.",
            "%1. We'll remember. Every one of us.",
            "Sleep, %1. The road's quiet now.",
        },
        caring = { "Goodbye, %1. You were one of us. You always will be." },
        brave = { "%1 fought to the end. Nobody forgets that." },
    },
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
    if spec.urgent ~= true and threatNearby(actor, runtime) then return false end
    local current = now()
    if spec.urgent ~= true
        and current - lastProductionSpeechAt < config("productionSpeechGroupCooldownMs", 12000) then
        return false
    end
    -- An urgent line is bounded by its own per-actor cooldown, not by
    -- whatever the companion happened to say a moment before the danger.
    local urgentKey = spec.urgent == true and (tostring(actorId(actor)) .. ":" .. topic) or nil
    if urgentKey then
        if current - (Disposal.urgentAt[urgentKey] or -math.huge) < spec.actorMs then return false end
    elseif spec.actorMs > 0 and type(SC.Dialogue.lastSpokenAt) == "function"
        and current - (tonumber(SC.Dialogue.lastSpokenAt(actor)) or -math.huge) < spec.actorMs then
        return false
    end
    local key = tostring(actorId(actor)) .. ":" .. topic .. ":" .. tostring(salt or current)
    if stableHash(key) % 100 >= spec.chance then return false end
    local spoken = SC.Dialogue.say(actor, topic, nil, arguments, { recentLimit = 4, salt = key })
    if spoken == true then
        lastProductionSpeechAt = current
        if urgentKey then Disposal.urgentAt[urgentKey] = current end
    end
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

-- One guaranteed closing line per grave or pyre fire: prayer or gallows humor by
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
    -- A fallen companion's grave closes with their name, never a joke; a
    -- pyre gets the fire-side version of the same prayer or gallows line.
    local topic, arguments = ceremonyTopic(actor, key), nil
    if grave.fallenName then
        topic, arguments = "burial.fallen", { grave.fallenName }
    elseif grave.pyre == true then
        if topic == "burial.prayer" then topic = "burn.prayer"
        elseif topic == "burial.gallows" then topic = "burn.gallows" end
    end
    local spoken = SC.Dialogue.say(actor, topic, nil, arguments, {
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

local function noteCandidateFailure(order, purpose, key, reason, zone)
    zone = zone or zoneFor(order)
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
local function nextZoneCandidate(order, purpose, zone, inspect, id, shared, budget)
    local scan = scanFor(order, purpose, zone)
    local current = now()
    if current < scan.waitUntil then return nil, "production_candidates_waiting", false end
    budget = math.max(1, math.floor(tonumber(budget)
        or config("productionScanSquaresPerSlice", 16)))
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

local function toolScore(item, key)
    if key ~= "choptree" then return 0 end
    local damage, ok = invoke(item, "getTreeDamage")
    return ok and math.max(0, tonumber(damage) or 0) or 0
end

local function betterTool(candidate, selected, key)
    if candidate == nil then return false end
    if selected == nil then return true end
    return toolScore(candidate, key) > toolScore(selected, key)
end

local function findInventoryTool(actor, key)
    local inventory = U().inventory(actor)
    if inventory == nil then return nil end
    local best
    for _, item in ipairs(U().inventoryItems(inventory, 256)) do
        if hasToolTag(item, key) and notBroken(item) and betterTool(item, best, key) then
            best = item
        end
    end
    return best
end

local function toolSource(actor, key)
    local bestStorage, bestContainer, bestItem
    for _, category in ipairs(TOOL_CATEGORIES) do
        for _, storage in ipairs(SC.BaseLife.storageRows(category, true)) do
            local container = SC.BaseLife.resolveContainer(storage)
            if container then
                for _, item in ipairs(U().inventoryItems(container,
                    config("campStorageItemBudget", 80))) do
                    if hasToolTag(item, key) and notBroken(item) and not protectedItem(item, actor)
                        and SC.BaseLife.availableCount(storage, U().itemType(item)) > 0
                        and betterTool(item, bestItem, key) then
                        bestStorage, bestContainer, bestItem = storage, container, item
                    end
                end
            end
        end
    end
    return bestStorage, bestContainer, bestItem
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
        if key == "diggrave" then
            state.borrowedTools = state.borrowedTools or {}
            state.borrowedTools[key] = {
                key = key, storage = pending.storage,
                container = pending.container, item = pending.item,
            }
        end
        state.toolFetch = nil
        return true, "production_tool_taken"
    end
    if ok ~= true then
        pending.failures = (pending.failures or 0) + 1
        pending.lastFailure = reason or "production_tool_fetch_failed"
        local authoritative = pending.lastFailure == "base_storage_unloaded"
            or pending.lastFailure == "base_storage_changed"
            or pending.lastFailure == "base_storage_withdrawals_disabled"
            or pending.lastFailure == "base_supply_moved"
            or pending.lastFailure == "base_supply_reserved"
            or pending.lastFailure == "destination_full"
        if authoritative or pending.failures >= config("productionCandidateMaxAttempts", 3) then
            state.toolFetch = nil
            return blockOrder(order, pending.lastFailure)
        end
        return false, pending.lastFailure
    end
    pending.failures, pending.lastFailure = 0, nil
    return true, reason
end

local function scheduleToolReturn(state, key, completion)
    local borrowed = type(state.borrowedTools) == "table" and state.borrowedTools[key] or nil
    if not borrowed then return false end
    state.toolReturn = { key = key, completion = completion }
    return true
end

local function returnBorrowedTool(actor, order, state)
    local pending = state.toolReturn
    if type(pending) ~= "table" then return nil end
    local borrowed = type(state.borrowedTools) == "table"
        and state.borrowedTools[pending.key] or nil
    if not borrowed then
        state.toolReturn = nil
        if pending.completion then return completeOrder(order, pending.completion) end
        return true, "production_tool_already_returned"
    end
    if not SC.BaseWork or type(SC.BaseWork.returnToStorage) ~= "function" then
        return blockOrder(order, "base_work_unavailable")
    end
    state.phase = "returning_tool"
    local ok, reason = SC.BaseWork.returnToStorage(actor, state, borrowed.storage,
        borrowed.container, borrowed.item)
    if ok == true and reason == "base_supply_returned" then
        state.borrowedTools[pending.key] = nil
        state.toolReturn = nil
        if pending.blocker then return blockOrder(order, pending.blocker) end
        if pending.completion then return completeOrder(order, pending.completion) end
        return true, "production_tool_returned"
    end
    if ok ~= true then
        pending.failures = (pending.failures or 0) + 1
        pending.lastFailure = reason or "base_supply_return_failed"
        local authoritative = pending.lastFailure == "base_storage_unloaded"
            or pending.lastFailure == "base_storage_changed"
            or pending.lastFailure == "borrowed_supply_missing"
            or pending.lastFailure == "destination_full"
        if authoritative or pending.failures >= config("productionCandidateMaxAttempts", 3) then
            return blockOrder(order, pending.lastFailure)
        end
        return false, pending.lastFailure
    end
    pending.failures, pending.lastFailure = 0, nil
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
    for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
        if cargoOrder(item) == orderId and (itemType == nil or U().itemType(item) == itemType) then
            return item
        end
    end
    return nil
end

local function itemKey(item)
    local stable = type(U().itemStableId) == "function" and U().itemStableId(item, true) or nil
    if stable ~= nil then return "stable:" .. tostring(stable) end
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
    local count, ids = 0, {}
    for key, present in pairs(type(before) == "table" and before or {}) do
        if present == true then
            count = count + 1
            ids[#ids + 1] = "|" .. tostring(key)
        end
    end
    table.sort(ids)
    data[Production.SAW_RECEIPT] = {
        orderId = order.id, logKey = itemKey(log), beforeCount = count,
        beforeIds = table.concat(ids) .. (#ids > 0 and "|" or ""), startedAt = now(),
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
-- second half). Paths stay inside the camp area like gathering; work bound to
-- an area in the reach band (reach) may also cross the bounded band around
-- it. A worker dragging a body asks for a route without climbs or stairs.
local function approachSquare(actor, square, action, avoid, reach, dragging)
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
        workReach = reach == true, draggingBody = dragging == true or nil,
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

local function standingTreeCount(zone)
    local count = 0
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            local square = U().gridSquare(x, y, zone.z)
            if square and inspectTree(square, x, y, zone.z) then count = count + 1 end
        end
    end
    return count
end

-- A new logging order chooses from all Lumber areas without making the player
-- micromanage an area selector.  Visible standing trees are supply; unfinished
-- tree counts on existing orders are commitments.  The stable id tie-break is
-- deliberate so the same world state produces the same choice after reload.
function Production.selectProductionZone(operation, zones, orders)
    if operation ~= "fell_trees" then return nil end
    local commitments = {}
    for _, order in ipairs(type(orders) == "table" and orders or {}) do
        if order.operation == "fell_trees"
            and order.state ~= "completed" and order.state ~= "cancelled" then
            commitments[order.zoneId] = (commitments[order.zoneId] or 0)
                + math.max(0, (tonumber(order.requested) or 0)
                    - (tonumber(order.completed) or 0))
        end
    end
    local best, bestAvailable, bestCommitment, bestTrees
    for _, zone in ipairs(type(zones) == "table" and zones or {}) do
        local trees = standingTreeCount(zone)
        local commitment = commitments[zone.id] or 0
        local available = trees - commitment
        if best == nil or available > bestAvailable
            or (available == bestAvailable and commitment < bestCommitment)
            or (available == bestAvailable and commitment == bestCommitment
                and trees > bestTrees)
            or (available == bestAvailable and commitment == bestCommitment
                and trees == bestTrees and tostring(zone.id) < tostring(best.id)) then
            best, bestAvailable, bestCommitment, bestTrees =
                zone, available, commitment, trees
        end
    end
    return best
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
    if SC.Diary and type(SC.Diary.noteWork) == "function" then
        pcall(SC.Diary.noteWork, actor, "trees", 1)
    end
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
    if not axe or state.toolFetch then
        return fetchTool(actor, order, state, "choptree")
    end
    -- Tagged improvised tools can have only one point of tree damage.  Compare
    -- a newly selected carried tool with camp storage once, then fetch the
    -- stronger option before committing to what may otherwise be dozens of
    -- native chop cycles.
    if state.evaluatedChopTool ~= axe then
        state.evaluatedChopTool = axe
        local storage, container, stored = toolSource(actor, "choptree")
        if betterTool(stored, axe, "choptree") then
            state.toolFetch = {
                key = "choptree", storage = storage, container = container, item = stored,
            }
            return fetchTool(actor, order, state, "choptree")
        end
    end
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
    for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
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
    if before == nil and type(work.beforeIds) == "string" then
        before = {}
        for key in string.gmatch(work.beforeIds, "|([^|]+)") do before[key] = true end
    end
    local created, attributed = {}, 0
    for _, item in ipairs(U().inventoryItems(inventory, math.huge)) do
        if U().itemType(item) == "Base.Plank" then
            if cargoOrder(item) == order.id then attributed = attributed + 1
            elseif cargoOrder(item) == nil and (before == nil or not before[itemKey(item)]) then
                created[#created + 1] = item
            end
        end
    end
    if not logGone then return false, "saw_not_committed", false end
    if before == nil then return false, "saw_baseline_unresolved", true end
    if #created == 0 and attributed == 0 then return false, "saw_incomplete", true end
    for _, item in ipairs(created) do
        if not markCargo(item, order.id) then return false, "production_marker_failed", true end
    end
    if #created > 0 then
        metrics.planksMade = metrics.planksMade + #created
        SC.BaseLife.noteProductionCounter("planksMade", #created)
        if SC.Diary and type(SC.Diary.noteWork) == "function" then
            pcall(SC.Diary.noteWork, actor, "planks", #created)
        end
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
        if reason == "saw_not_committed" then
            -- finishWork proved the native action ended and the exact marked
            -- log proves it did not commit. Retire this dead attempt so Retry
            -- can create a replacement instead of polling it forever.
            state.work = nil
            state.sawRetryAt = now() + config("productionRetryBaseMs", 750)
            clearSawReceipt(actor, order.id)
        end
        return sawFailure(order, state, reason == "saw_not_committed" and "saw_incomplete" or reason)
    end
    state.work = nil
    state.sawRetryAt = nil
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
                beforeCount = receipt.beforeCount, beforeIds = receipt.beforeIds,
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
                beforeCount = receipt.beforeCount, beforeIds = receipt.beforeIds,
                log = nil, startedAt = receipt.startedAt,
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
    if state.sawRetryAt and now() < state.sawRetryAt then
        return true, "production_saw_retry_wait"
    end
    state.sawRetryAt = nil
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
    local fallenName = data[Production.FALLEN_NAME]
    return {
        object = object, x = x, y = y, z = z or 0,
        corpses = tonumber(data.corpses) or 0, filled = data.filled == true,
        spriteType = data.spriteType, north = northOk and north == true,
        key = "grave:" .. pointKey(x, y, z or 0),
        fallenName = type(fallenName) == "string" and fallenName or nil,
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

-- A fallen companion's grave belongs to them alone: never open for others.
local function graveOpen(info)
    return info ~= nil and not info.filled and info.fallenName == nil
        and info.corpses < graveCapacity(info.object)
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
            scheduleToolReturn(state, "diggrave")
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
    scheduleToolReturn(state, "diggrave")
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
        if order.completed >= order.requested then
            if state.toolReturn then
                state.toolReturn.completion = "graves_dug"
                return true, "production_tool_return_pending"
            end
            return completeOrder(order, "graves_dug")
        end
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
                return blockOrder(order, forBurial == true and "no_grave_site_near_body" or reason)
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
    }, Disposal.reach(order, zone))
    if approach == "failed" then
        noteCandidateFailure(order, "grave-site", target.key, approachReason)
        releaseClaim(target.key, context.actorId)
        state.digTarget = nil
        scheduleToolReturn(state, "diggrave")
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
        scheduleToolReturn(state, "diggrave")
        return false, reason or "production_dig_rejected"
    end
    state.work = {
        kind = "dig_grave", x = target.x, y = target.y, z = target.z, key = target.key,
        -- "capacity" digs ahead of a body collection: the grave is never
        -- counted as order progress, exactly like a grave dug for a burial.
        startedAt = now(), forBurial = forBurial == true or forBurial == "capacity",
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

-- Everything a body carries, bags included. Burial and burning are
-- irreversible, so an incomplete look is never treated as "nothing there":
-- the scan reports "pending" and the body waits for a later pass.
-- Returns "clear", a blocking reason, or "pending".
local function bodyContentsStatus(body, actor)
    local container = invoke(body, "getContainer")
    if container == nil then return "clear", 0 end
    local budget = math.max(16, math.floor(tonumber(
        U().config("productionDisposalScanBudget")) or 256))
    local blocked, count = nil, 0
    local complete = true
    local function inspect(item)
        count = count + 1
        -- A private diary is never buried or burned by automation, wherever
        -- it sits: the body waits until the book is recovered.
        if SC.DiaryItem and type(SC.DiaryItem.hasPayload) == "function"
            and SC.DiaryItem.hasPayload(item) then
            blocked = "carries_diary"
            return true
        end
        if SC.PersonalItems and type(SC.PersonalItems.personalRecord) == "function"
            and SC.PersonalItems.personalRecord(item) ~= nil then
            blocked = "carries_personal_item"
            return true
        end
        if SC.WorkTransport and type(SC.WorkTransport.foreignProtected) == "function" then
            local protected, reason = SC.WorkTransport.foreignProtected(item, actor)
            if protected and reason ~= "favorite_item" then
                blocked = "protected_items"
                return true
            end
        end
        return false
    end
    if SC.PersonalItems and type(SC.PersonalItems.walkContainer) == "function" then
        local _, scanned = SC.PersonalItems.walkContainer(container, function(item)
            if inspect(item) then return false end
        end, { budget = budget })
        complete = scanned
    else
        for _, item in ipairs(U().inventoryItems(container, budget)) do
            if inspect(item) then break end
        end
        complete = false
    end
    if blocked then return blocked, count end
    if not complete then return "pending", count end
    return "clear", count
end

local function bodyEligible(body, order, actor)
    if not U().instanceOf(body, "IsoDeadBody") then return false end
    local fake, fakeOk = invoke(body, "isFakeDead")
    if fakeOk and fake == true then return false, "fake_dead" end
    local animal, animalOk = invoke(body, "isAnimal")
    if animalOk and animal == true then return false, "animal" end
    local _, _, z = U().position(body)
    if tonumber(z) ~= 0 then return false, "not_ground_level" end
    local status, count = bodyContentsStatus(body, actor)
    if count > 0 and (type(order.settings) ~= "table" or order.settings.withBelongings ~= true) then
        return false, "carries_items"
    end
    if status == "pending" then return false, "belongings_scan_incomplete" end
    if status ~= "clear" then return false, status end
    return true
end

-- Re-checked immediately before an irreversible action, because the body's
-- contents can change between selection and the burial or the lit pyre.
local function disposalStillPermitted(body, order, actor)
    local eligible, reason = bodyEligible(body, order, actor)
    return eligible == true, reason
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
    -- A fallen companion's grave always gets a cross, whatever the order says.
    local fallen = type(grave) == "table" and grave.fallenName ~= nil
    if not fallen and (type(order.settings) ~= "table" or order.settings.marker ~= "wood") then
        return false
    end
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
            scheduleToolReturn(state, "diggrave")
            return blockOrder(order, "fill_timeout")
        end
        return true, "production_filling"
    end
    local finished, finishReason = finishWork(actor)
    if finished ~= true then return false, finishReason or "fill_finish_failed" end
    state.work = nil
    releaseClaim(work.graveKey, context.actorId)
    scheduleToolReturn(state, "diggrave")
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
    local approach, approachReason = approachSquare(actor, square, "move_to_production_grave",
        nil, Disposal.reach(order, zoneFor(order)))
    if approach == "failed" then
        releaseClaim(grave.key, context.actorId)
        scheduleToolReturn(state, "diggrave")
        return blockOrder(order, approachReason)
    end
    if approach ~= "arrived" then return true, approachReason end
    local accepted, reason = U().move(actor, "walk", {
        action = "fill_grave", grave = grave.object, tool = shovel, targetSquare = square,
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "fill_grave") then
        releaseClaim(grave.key, context.actorId)
        scheduleToolReturn(state, "diggrave")
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
        if stillThere then
            untagBody(work.body, actor)
            if work.haulTag then Disposal.clearTag(work.body) end
        end
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
    if order.operation == "collect_bodies" then
        SC.BaseLife.noteProductionCounter("bodiesCollected", 1)
    end
    if info then SC.BaseLife.noteProductionGrave(order.id, { x = info.x, y = info.y, z = info.z }) end
    if work.fallen and info then Disposal.markFallenGrave(info, work.fallen) end
    if SC.Diary and type(SC.Diary.noteWork) == "function" then
        if type(work.fallen) == "table" then
            pcall(SC.Diary.noteFallenBurial, actor, work.fallen.name)
        else
            pcall(SC.Diary.noteWork, actor, "buried", 1)
        end
    end
    releaseClaim(work.key, context.actorId)
    releaseClaim(work.graveKey, context.actorId)
    if not work.fallen then speak(actor, "burial.lower", nil, work.key, context.runtime) end
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
    return Disposal.startBurial(actor, order, state, context, target)
end

-- ---------------------------------------------------------------------------
-- Collect and burn the dead
-- ---------------------------------------------------------------------------
-- One worker moves one body at a time: picked in a camp or lumber area, taken
-- hold of with the stock grapple, dragged to the order's burial ground or
-- pyre, laid down and found again by its haul tag (the drop respawns the body
-- as a new object that keeps its modData). A burial ground buries it; a pyre
-- burns it. Nothing is ever set alight except on a pyre the player marked
-- that passes the fire-safety check. Danger drops the body at once.

-- Classes and sprite families that must not stand near a pyre. Ground cover
-- is judged separately (productionPyreRejectGrass): whether fire crosses
-- grass is the sandbox's call, and the watch stops everyone when it does.
Disposal.HAZARD_CLASSES = {
    IsoTree = "tree_near", IsoDoor = "structure_near", IsoWindow = "structure_near",
    IsoThumpable = "structure_near", IsoBarricade = "structure_near",
    IsoCurtain = "structure_near", IsoGenerator = "generator_near",
}
Disposal.STRUCTURE_PREFIXES = {
    "walls_", "fencing_", "fixtures_", "furniture_", "appliances_", "location_",
    "construction_", "industry_", "carpentry_", "crafted_", "lighting_",
    "recreational_", "street_", "security_",
}
Disposal.VEGETATION_PREFIXES = {
    "vegetation_farming", "vegetation_foliage", "vegetation_ornamental",
    "vegetation_trees", "f_bushes", "f_flowerbed",
}
Disposal.GRASS_PREFIXES = {
    "e_newgrass", "blends_grassoverlays", "vegetation_groundcover", "d_plants",
}
Disposal.tagSerial = 0

-- Areas ----------------------------------------------------------------------

function Disposal.zones()
    local base = SC.BaseLife and type(SC.BaseLife.active) == "function"
        and SC.BaseLife.active() or nil
    return base and base.zones or {}
end

function Disposal.inside(zone, x, y, z)
    if type(zone) ~= "table" or x == nil or y == nil then return false end
    x, y = math.floor(x), math.floor(y)
    return x >= zone.x1 and x <= zone.x2 and y >= zone.y1 and y <= zone.y2
        and math.floor(tonumber(z) or 0) == (tonumber(zone.z) or 0)
end

-- Chebyshev distance from a tile to the zone rectangle; 0 inside it.
function Disposal.ringDistance(zone, x, y)
    return math.max(0, zone.x1 - x, x - zone.x2, zone.y1 - y, y - zone.y2)
end

-- Burial grounds and pyres are destinations, never sources.
function Disposal.inDisposalArea(x, y, z)
    for _, zone in ipairs(Disposal.zones()) do
        if (zone.kind == "burial" or zone.kind == "pyre") and Disposal.inside(zone, x, y, z) then
            return true
        end
    end
    return false
end

-- A burial ground or pyre in the reach band needs reach admission for its
-- trips; collection that includes lumber areas always may cross the band.
function Disposal.zoneNeedsReach(zone)
    if type(zone) ~= "table" then return false end
    if zone.kind == "lumber" then return true end
    if type(SC.BaseLife.zoneInsideAreaUnion) ~= "function" then return false end
    return SC.BaseLife.zoneInsideAreaUnion(zone, Disposal.zones()) ~= true
end

function Disposal.reach(order, zone)
    if order.operation == "collect_bodies" and type(order.settings) == "table"
        and order.settings.fromLumber == true then
        return true
    end
    return Disposal.zoneNeedsReach(zone)
end

-- Bodies ---------------------------------------------------------------------

function Disposal.bodyData(body)
    local data = body ~= nil and U().modData(body) or nil
    return type(data) == "table" and data or nil
end

function Disposal.bodyAt(body, square)
    local present = false
    U().squareStaticMovingObjects(square, function(object)
        if object == body then
            present = true
            return false
        end
    end, 16)
    return present
end

function Disposal.hasBody(square)
    local found = false
    U().squareStaticMovingObjects(square, function(object)
        if U().instanceOf(object, "IsoDeadBody") then
            found = true
            return false
        end
    end, 16)
    return found
end

function Disposal.descriptorName(body)
    local descriptor, ok = invoke(body, "getDescriptor")
    if not ok or descriptor == nil then return nil end
    local first, firstOk = invoke(descriptor, "getForename")
    local last, lastOk = invoke(descriptor, "getSurname")
    first = firstOk and type(first) == "string" and first or ""
    last = lastOk and type(last) == "string" and last or ""
    local name = first .. ((first ~= "" and last ~= "") and " " or "") .. last
    if name == "" then return nil end
    local female, femaleOk = invoke(descriptor, "isFemale")
    return name, femaleOk and (female == true and "female" or "male") or "unknown"
end

-- Only an exact, unique match in the companion death register names a body;
-- anything uncertain stays an unnamed stranger. A player body that matches
-- no fallen companion (the player's own) is never touched.
function Disposal.identity(body)
    local name, gender = Disposal.descriptorName(body)
    local community = SC.Community
    if name and type(community) == "table" and type(community.deathMatching) == "function" then
        local ok, subjectId, row = pcall(community.deathMatching, name)
        if ok and subjectId ~= nil and type(row) == "table" then
            local known = row.subjectGender or "unknown"
            if known == "unknown" or gender == "unknown" or known == gender then
                return "fallen", { name = row.subjectName or name, subjectId = subjectId }
            end
        end
    end
    local player, playerOk = invoke(body, "isPlayer")
    if playerOk and player == true then return "protected" end
    return "ordinary"
end

-- Returns the identity and the fallen record, or nil and a reason. Burning
-- never takes a fallen companion; nothing ever takes an unmatched player.
function Disposal.candidate(body, order, actor, burning)
    if not U().instanceOf(body, "IsoDeadBody") then return nil end
    local data = Disposal.bodyData(body)
    if data and data[Production.BURNED_TAG] ~= nil then return nil, "burned" end
    local eligible, why = bodyEligible(body, order, actor)
    if not eligible then return nil, why end
    local kind, fallen = Disposal.identity(body)
    if kind == "protected" then return nil, "protected_body" end
    if kind == "fallen" and burning then return nil, "fallen_companion" end
    return kind, fallen
end

function Disposal.newTag(order, id)
    Disposal.tagSerial = Disposal.tagSerial + 1
    return tostring(order.id) .. "|" .. tostring(id) .. "|" .. tostring(now()) .. "|"
        .. tostring(Disposal.tagSerial)
end

function Disposal.setTag(body, tag)
    local data = Disposal.bodyData(body)
    if not data then return false end
    data[Production.HAUL_TAG] = tag
    return data[Production.HAUL_TAG] == tag
end

function Disposal.clearTag(body)
    local data = Disposal.bodyData(body)
    if data and data[Production.HAUL_TAG] ~= nil then
        data[Production.HAUL_TAG] = nil
        return true
    end
    return false
end

-- Find a laid-down body by its haul tag, nearest ring first.
function Disposal.findTagged(origin, tag, radius)
    local x, y, z = U().position(origin)
    if x == nil or tag == nil then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    for ring = 0, radius do
        for dy = -ring, ring do
            for dx = -ring, ring do
                if math.max(math.abs(dx), math.abs(dy)) == ring then
                    local square = U().gridSquare(x + dx, y + dy, z)
                    local found
                    U().squareStaticMovingObjects(square, function(object)
                        local data = Disposal.bodyData(object)
                        if data and data[Production.HAUL_TAG] == tag then
                            found = object
                            return false
                        end
                    end, 16)
                    if found then return found, square end
                end
            end
        end
    end
    return nil
end

function Disposal.sources(order, zone)
    local settings = type(order.settings) == "table" and order.settings or {}
    local result = {}
    -- Bodies already inside the burial ground only need the last few steps.
    if zone.kind == "burial" then result[1] = zone end
    for _, source in ipairs(Disposal.zones()) do
        if (source.kind == "area" and settings.fromCamp == true)
            or (source.kind == "lumber" and settings.fromLumber == true) then
            result[#result + 1] = source
        end
    end
    return result
end

-- Round robin over the source areas, each with its own resumable scan. Only
-- a full pass over every area without an eligible body is terminal.
function Disposal.nextSource(actor, order, state, context, zone)
    local sources = Disposal.sources(order, zone)
    if #sources == 0 then return nil, "no_collection_areas", true end
    local search = state.collect
    if type(search) ~= "table" then
        search = { index = 1, done = {}, carrying = 0, seen = {} }
        state.collect = search
    end
    local burning = zone.kind == "pyre"
    local budget = config("productionCorpseScanSquaresPerSlice", 48)
    for _ = 1, #sources do
        if search.index > #sources then search.index = 1 end
        local source = sources[search.index]
        if not search.done[source.id] then
            local purpose = "corpse:" .. tostring(source.id)
            local candidate, reason, terminal = nextZoneCandidate(order, purpose, source,
                function(square, x, y, z)
                    if source.kind ~= "burial" and Disposal.inDisposalArea(x, y, z) then return nil end
                    local found
                    U().squareStaticMovingObjects(square, function(object)
                        local kind, detail = Disposal.candidate(object, order, actor, burning)
                        if kind then
                            found = {
                                key = bodyKey(object), body = object, square = square,
                                x = x, y = y, z = z, identity = kind, fallen = detail,
                                purpose = purpose, sourceZone = source,
                            }
                            return false
                        end
                        local key = bodyKey(object)
                        if detail == "carries_items" and not search.seen[key]
                            and search.carrying < 99 then
                            search.seen[key] = true
                            search.carrying = search.carrying + 1
                        end
                    end, 16)
                    return found
                end, context.actorId, false, budget)
            if candidate then return candidate, reason, false end
            if not terminal then return nil, reason, false end
            search.done[source.id] = true
        end
        search.index = search.index + 1
    end
    local carrying = search.carrying
    state.collect = nil
    if carrying > 0 then return nil, "bodies_carry_items:" .. tostring(carrying), true end
    return nil, "no_bodies_in_collection_areas", true
end

-- Graves ---------------------------------------------------------------------

-- An open grave for the next body: remembered graves first, then any grave in
-- the burial ground. A fallen companion needs an empty one of their own.
function Disposal.openGrave(order, context, needEmpty)
    local function usable(info)
        return info ~= nil and info.spriteType == "sprite1" and graveOpen(info)
            and (needEmpty ~= true or info.corpses == 0)
            and not claimActive(info.key, context.actorId)
    end
    for _, point in ipairs(order.graves or {}) do
        local info = primaryGraveAt(point)
        if usable(info) then return info end
    end
    local zone = zoneFor(order)
    if not zone then return nil end
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            for _, object in ipairs(graveObjects(U().gridSquare(x, y, zone.z))) do
                local info = graveInfo(object)
                if usable(info) then
                    SC.BaseLife.noteProductionGrave(order.id, { x = info.x, y = info.y, z = info.z })
                    return info
                end
            end
        end
    end
    return nil
end

-- A fallen companion's grave keeps their name on both halves: nobody else is
-- ever buried in it, its ceremony speaks the name and a cross is always
-- queued. The base history remembers where they lie.
function Disposal.markFallenGrave(info, fallen)
    local name = type(fallen) == "table" and fallen.name or nil
    if type(name) ~= "string" or name == "" then return false end
    local halves = { info.object }
    local px, py = gravePartner(info)
    for _, object in ipairs(graveObjects(U().gridSquare(px, py, info.z))) do
        local data = U().modData(object)
        if type(data) == "table" and data.spriteType == "sprite2" then
            halves[#halves + 1] = object
        end
    end
    for _, object in ipairs(halves) do
        local data = U().modData(object)
        if type(data) == "table" then data[Production.FALLEN_NAME] = name end
    end
    info.fallenName = name
    noteOwnershipMutation()
    metrics.fallenBuried = metrics.fallenBuried + 1
    SC.BaseLife.noteProductionCounter("fallenBuried", 1)
    SC.BaseLife.noteHistory("fallen_buried", {
        name = name, subjectId = fallen.subjectId, x = info.x, y = info.y, z = info.z,
    })
    return true
end

-- Lower one body into its reserved grave. Shared by graveside burial and body
-- collection; a collected body carries its haul tag and, for a fallen
-- companion, the name its grave will keep.
function Disposal.startBurial(actor, order, state, context, target)
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
    local approach, approachReason = approachSquare(actor, square, "move_to_production_grave",
        nil, Disposal.reach(order, zoneFor(order)))
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
    -- Burial is irreversible: prove again, here, that nothing protected is
    -- still on this body.
    local permitted, permittedReason = disposalStillPermitted(target.body, order, actor)
    if not permitted then
        untagBody(target.body, actor)
        noteCandidateFailure(order, "body", target.key, permittedReason or "belongings_changed")
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return false, permittedReason or "belongings_changed"
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
        startedAt = now(), fallen = target.fallen, haulTag = target.haulTag,
    }
    state.buryTarget = nil
    state.phase = "burying"
    return true, "production_burying"
end

-- A collected body laid at the graveside keeps its burial target until the
-- burial starts; a vanished body or a full grave returns it to the pool.
function Disposal.resumeBurial(actor, order, state, context)
    local target = state.buryTarget
    local info = primaryGraveAt(target.grave)
    if not Disposal.bodyAt(target.body, target.bodySquare) or not graveOpen(info)
        or (target.fallen ~= nil and info.corpses > 0) then
        releaseClaim(target.key, context.actorId)
        releaseClaim(target.graveKey, context.actorId)
        state.buryTarget = nil
        return nil
    end
    target.graveInfo = info
    claim(target.key, order.id, context.actorId)
    claim(target.graveKey, order.id, context.actorId)
    return Disposal.startBurial(actor, order, state, context, target)
end

-- A grave closes when it is full, at once when it holds a fallen companion,
-- and (all) when the order is done.
function Disposal.closeGraves(actor, order, state, context, all)
    for _, point in ipairs(order.graves or {}) do
        local info = primaryGraveAt(point)
        if info and not info.filled and info.corpses > 0 and (all == true
            or info.fallenName ~= nil or info.corpses >= graveCapacity(info.object)) then
            return fillGrave(actor, order, state, info, context)
        end
    end
    return nil
end

-- Pyre safety ----------------------------------------------------------------

function Disposal.spriteName(object)
    local name, ok = invoke(object, "getSpriteName")
    if ok and type(name) == "string" then return name end
    local sprite, spriteOk = invoke(object, "getSprite")
    if spriteOk and sprite ~= nil then
        local spriteName, nameOk = invoke(sprite, "getName")
        if nameOk and type(spriteName) == "string" then return spriteName end
    end
    return ""
end

function Disposal.prefixed(name, prefixes)
    for _, prefix in ipairs(prefixes) do
        if string.sub(name, 1, #prefix) == prefix then return true end
    end
    return false
end

function Disposal.objectHazard(object)
    for className, reason in pairs(Disposal.HAZARD_CLASSES) do
        if U().instanceOf(object, className) then return reason end
    end
    local container, containerOk = invoke(object, "getContainer")
    if containerOk and container ~= nil then return "container_near" end
    local name = Disposal.spriteName(object)
    if Disposal.prefixed(name, Disposal.STRUCTURE_PREFIXES) then return "structure_near" end
    if Disposal.prefixed(name, Disposal.VEGETATION_PREFIXES) then return "vegetation_near" end
    if U().config("productionPyreRejectGrass") == true
        and Disposal.prefixed(name, Disposal.GRASS_PREFIXES) then
        return "grass"
    end
    return nil
end

function Disposal.squareHazard(square, onPyre)
    if onPyre then
        local outside, outsideOk = invoke(square, "isOutside")
        if (outsideOk and outside == false) or inRoom(square) then return "indoors" end
    end
    local vehicle, vehicleOk = invoke(square, "getVehicleContainer")
    if vehicleOk and vehicle ~= nil then return "vehicle_near" end
    if treeOn(square) then return "tree_near" end
    local items, itemsOk = invoke(square, "getWorldObjects")
    if itemsOk and items ~= nil and U().listSize(items) > 0 then return "loose_items" end
    local floor = invoke(square, "getFloor")
    local hazard
    U().squareObjects(square, function(object)
        if object ~= floor then hazard = Disposal.objectHazard(object) end
        if hazard then return false end
    end, 32)
    return hazard
end

-- The only place anything is set alight. Checked when the zone is drawn,
-- when an order is created and again before every ignition.
function Production.validatePyreZone(zone)
    if type(zone) ~= "table" or tonumber(zone.x1) == nil then return false, "invalid_zone" end
    if (tonumber(zone.z) or 0) ~= 0 then return false, "not_ground_level" end
    local clearance = math.max(0, math.floor(config("productionPyreClearance", 2)))
    local distance = math.max(clearance,
        math.floor(config("productionPyreStructureDistance", 4)))
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, false)) do
        local sx, sy = tonumber(storage.x), tonumber(storage.y)
        if sx and sy and (tonumber(storage.z) or 0) == zone.z
            and Disposal.ringDistance(zone, math.floor(sx), math.floor(sy)) <= distance then
            return false, "storage_near"
        end
    end
    for y = zone.y1 - distance, zone.y2 + distance do
        for x = zone.x1 - distance, zone.x2 + distance do
            local ring = Disposal.ringDistance(zone, x, y)
            local square = U().gridSquare(x, y, zone.z)
            if square == nil then
                if ring <= clearance then return false, "area_unloaded" end
            else
                local building, buildingOk = invoke(square, "getBuilding")
                if (buildingOk and building ~= nil) or inRoom(square) then
                    return false, ring == 0 and "indoors" or "building_near"
                end
                if ring <= clearance then
                    local hazard = Disposal.squareHazard(square, ring == 0)
                    if hazard then return false, hazard end
                end
            end
        end
    end
    return true
end

function Disposal.squareOnFire(square)
    if square == nil then return false end
    local fire, ok = invoke(square, "haveFire")
    return ok and fire == true
end

function Disposal.pyreBurning(zone)
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            if Disposal.squareOnFire(U().gridSquare(x, y, zone.z)) then return true end
        end
    end
    return false
end

-- Fire on any tile beyond the pyre and its margin is a spreading fire.
function Disposal.fireSpread(zone)
    local margin = math.max(0, math.floor(config("productionBurnFireSpreadMargin", 1)))
    local reach = margin + 3
    for y = zone.y1 - reach, zone.y2 + reach do
        for x = zone.x1 - reach, zone.x2 + reach do
            if Disposal.ringDistance(zone, x, y) > margin
                and Disposal.squareOnFire(U().gridSquare(x, y, zone.z)) then
                return true
            end
        end
    end
    return false
end

-- Supplies, weather and bystanders ---------------------------------------------

function Disposal.petrolFluid()
    local fluids = type(_G) == "table" and rawget(_G, "Fluid") or nil
    if fluids == nil then return nil end
    local ok, petrol = pcall(function() return fluids.Petrol end)
    return ok and petrol or nil
end

function Disposal.petrolAmount(item)
    local petrol = Disposal.petrolFluid()
    if item == nil or petrol == nil then return 0 end
    local fluid, fluidOk = invoke(item, "getFluidContainer")
    if not fluidOk or fluid == nil then return 0 end
    local contains, containsOk = invoke(fluid, "contains", petrol)
    if not containsOk or contains ~= true then return 0 end
    local amount, amountOk = invoke(fluid, "getAmount")
    return amountOk and tonumber(amount) or 0
end

-- ISBurnCorpseAction takes ZomboidGlobals.BurnCorpsePetrolAmount per body.
function Disposal.fuelPerBody()
    local globals = type(_G) == "table" and rawget(_G, "ZomboidGlobals") or nil
    local ok, amount = pcall(function() return globals.BurnCorpsePetrolAmount end)
    return ok and tonumber(amount) or 0.1
end

function Disposal.isLighter(item)
    if item == nil or not notBroken(item) then return false end
    local fullType = U().itemType(item)
    if fullType ~= "Base.Lighter" and fullType ~= "Base.Matches"
        and U().itemHasTag(item, "StartFire") ~= true then
        return false
    end
    local uses, usesOk = invoke(item, "getCurrentUsesFloat")
    return not usesOk or tonumber(uses) == nil or tonumber(uses) > 0
end

function Disposal.supplyMatches(item, kind)
    if kind == "lighter" then return Disposal.isLighter(item) end
    return Disposal.petrolAmount(item) >= Disposal.fuelPerBody() - 0.001
end

function Disposal.inventorySupply(actor, kind)
    for _, item in ipairs(U().inventoryItems(U().inventory(actor), 256)) do
        if Disposal.supplyMatches(item, kind) then return item end
    end
    return nil
end

function Disposal.missingSupply(actor)
    if not Disposal.inventorySupply(actor, "lighter") then return "lighter" end
    if not Disposal.inventorySupply(actor, "petrol") then return "petrol" end
    return nil
end

function Disposal.storageSupply(actor, kind)
    for _, storage in ipairs(SC.BaseLife.storageRows(nil, true)) do
        local container = SC.BaseLife.resolveContainer(storage)
        if container then
            for _, item in ipairs(U().inventoryItems(container,
                config("campStorageItemBudget", 80))) do
                if Disposal.supplyMatches(item, kind) and not protectedItem(item, actor)
                    and SC.BaseLife.availableCount(storage, U().itemType(item)) > 0 then
                    return storage, container, item
                end
            end
        end
    end
    return nil
end

-- Same verified storage withdrawal as tools; a missing supply blocks with a
-- readable reason and re-checks on the ordinary retry cadence.
function Disposal.fetchSupply(actor, order, state, kind)
    if not SC.BaseWork or type(SC.BaseWork.withdrawFromStorage) ~= "function" then
        return blockOrder(order, "base_work_unavailable")
    end
    local pending = state.supplyFetch
    if pending and (pending.kind ~= kind
        or U().inventoryContains(pending.container, pending.item) ~= true) then
        pending, state.supplyFetch = nil, nil
    end
    if not pending then
        local storage, container, item = Disposal.storageSupply(actor, kind)
        if not storage then
            return blockOrder(order, kind == "lighter" and "missing_lighter" or "missing_fuel")
        end
        pending = { kind = kind, storage = storage, container = container, item = item }
        state.supplyFetch = pending
    end
    state.phase = "fetching_tool"
    local ok, reason = SC.BaseWork.withdrawFromStorage(actor, state, pending.storage,
        pending.container, pending.item)
    if ok == true and reason == "base_supply_taken" then
        state.supplyFetch = nil
        return true, "production_supply_taken"
    end
    if ok ~= true then
        state.supplyFetch = nil
        return false, reason or "production_supply_fetch_failed"
    end
    return true, reason
end

function Disposal.raining()
    if type(getClimateManager) ~= "function" then return false end
    local ok, manager = pcall(getClimateManager)
    if not ok or manager == nil then return false end
    local raining, called = invoke(manager, "isRaining")
    return called and raining == true
end

function Disposal.requireDry(order)
    return type(order.settings) ~= "table" or order.settings.requireDry ~= false
end

-- Nobody but the igniter stands within reach of the body being lit.
function Disposal.bystanderNear(actor, square)
    local limit = config("productionPyreBystanderDistance", 2)
    local function near(other)
        return other ~= nil and other ~= actor and not U().isDead(other)
            and U().distance(other, square) <= limit
    end
    if type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok and near(player) then return true end
    end
    for _, other in ipairs(U().registryLiving(32)) do
        if near(other) then return true end
    end
    return false
end

-- Burning --------------------------------------------------------------------

function Disposal.watchSquare(actor, zone)
    local distance = math.max(1, math.floor(config("productionPyreWatchDistance", 3)))
    local cx, cy = math.floor((zone.x1 + zone.x2) / 2), math.floor((zone.y1 + zone.y2) / 2)
    local best, bestDistance
    for _, point in ipairs({
        { zone.x1 - distance, cy }, { zone.x2 + distance, cy },
        { cx, zone.y1 - distance }, { cx, zone.y2 + distance },
    }) do
        local square = U().gridSquare(point[1], point[2], zone.z)
        if square and U().isSquareFree(square) and not Disposal.squareOnFire(square) then
            local value = U().distance(actor, square)
            if bestDistance == nil or value < bestDistance then best, bestDistance = square, value end
        end
    end
    return best
end

-- Stand clear of a burning pyre: at least the watch distance from every tile.
function Disposal.keepWatch(actor, order, zone)
    local distance = math.max(1, math.floor(config("productionPyreWatchDistance", 3)))
    local x, y = U().position(actor)
    if x ~= nil and Disposal.ringDistance(zone, math.floor(x), math.floor(y)) >= distance then
        return "production_watching_fire"
    end
    local square = Disposal.watchSquare(actor, zone)
    if not square or not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return "production_watching_fire"
    end
    local accepted, reason = SC.Navigation.requestAny(actor, { square }, "walk", {
        action = "move_to_pyre_watch", targetSquare = square, arrivalDistance = 0.8,
        workCampOnly = true, workReach = Disposal.reach(order, zone),
    })
    if accepted == true then return reason or "production_moving_to_watch" end
    return "production_watching_fire"
end

-- The free pyre tile nearest the middle, so a body laid there lands inside.
function Disposal.freePyreSquare(zone)
    local cx, cy = (zone.x1 + zone.x2) / 2, (zone.y1 + zone.y2) / 2
    local best, bestScore
    for y = zone.y1, zone.y2 do
        for x = zone.x1, zone.x2 do
            local square = U().gridSquare(x, y, zone.z)
            if square and U().isSquareFree(square) and not Disposal.squareOnFire(square)
                and not Disposal.hasBody(square) then
                local score = math.abs(x - cx) + math.abs(y - cy)
                if bestScore == nil or score < bestScore then best, bestScore = square, score end
            end
        end
    end
    return best
end

function Disposal.releaseBurnTarget(state, context)
    local target = state.burnTarget
    state.burnTarget = nil
    if target then releaseClaim(target.key, context.actorId) end
end

-- Fire beyond the pyre: every worker stops (the order blocks), nobody lights
-- anything again until the player presses Retry.
function Disposal.fireEmergency(actor, order, state, context)
    local native = natives()
    if state.work and workActive(actor, state.work.kind) then
        cancelWork(actor, "production_fire_spread")
    end
    if native and type(native.isDraggingCorpse) == "function" and native.isDraggingCorpse(actor) then
        pcall(native.releaseCorpse, actor)
    end
    speak(actor, "burn.fire_spread", nil, tostring(order.id) .. ":" .. tostring(now()),
        context.runtime)
    SC.BaseLife.noteHistory("pyre_fire_spread", { orderId = order.id, zoneId = order.zoneId })
    Disposal.abandonHaul(state, context)
    Disposal.releaseBurnTarget(state, context)
    state.work, state.burn = nil, nil
    releaseClaim("pyre:" .. tostring(order.zoneId), context.actorId)
    U().stop(actor)
    return blockOrder(order, "fire_spread")
end

-- One body, one fire. The igniter stands beside the body with the lighter and
-- the petrol can in hand, then watches from a distance.
function Disposal.ignite(actor, order, state, context, zone, target)
    local pyreKey = "pyre:" .. tostring(zone.id)
    if claimActive(pyreKey, context.actorId) then
        state.phase = "watching"
        return true, Disposal.keepWatch(actor, order, zone)
    end
    claim(pyreKey, order.id, context.actorId)
    claim(target.key, order.id, context.actorId)
    local safe, unsafe = Production.validatePyreZone(zone)
    if safe ~= true then
        Disposal.releaseBurnTarget(state, context)
        releaseClaim(pyreKey, context.actorId)
        return blockOrder(order, "pyre_unsafe:" .. tostring(unsafe))
    end
    if Disposal.requireDry(order) and Disposal.raining() then
        Disposal.releaseBurnTarget(state, context)
        releaseClaim(pyreKey, context.actorId)
        speak(actor, "burn.rain", nil, pyreKey, context.runtime)
        return blockOrder(order, "raining")
    end
    local missing = Disposal.missingSupply(actor)
    if missing then return Disposal.fetchSupply(actor, order, state, missing) end
    state.phase = "approaching"
    local approach, approachReason = approachSquare(actor, target.square, "move_to_pyre_body",
        nil, Disposal.reach(order, zone))
    if approach == "failed" then
        noteCandidateFailure(order, "pyre-body", target.key, approachReason, zone)
        Disposal.releaseBurnTarget(state, context)
        releaseClaim(pyreKey, context.actorId)
        return false, approachReason
    end
    if approach ~= "arrived" then return true, approachReason end
    if threatNearby(actor, context.runtime) then return false, "unsafe_area" end
    if Disposal.bystanderNear(actor, target.square) then
        state.phase = "watching"
        return true, "pyre_bystander_near"
    end
    -- Lighting the pyre is irreversible: prove again that this body carries
    -- nothing protected, and never light on an incomplete look.
    local permitted, permittedReason = disposalStillPermitted(target.body, order, actor)
    if not permitted then
        noteCandidateFailure(order, "pyre-body", target.key,
            permittedReason or "belongings_changed", zone)
        Disposal.releaseBurnTarget(state, context)
        releaseClaim(pyreKey, context.actorId)
        return false, permittedReason or "belongings_changed"
    end
    local accepted, reason = U().move(actor, "walk", {
        action = "burn_body", body = target.body,
        lighter = Disposal.inventorySupply(actor, "lighter"),
        petrol = Disposal.inventorySupply(actor, "petrol"), targetSquare = target.square,
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "burn_body") then
        noteCandidateFailure(order, "pyre-body", target.key, reason, zone)
        Disposal.releaseBurnTarget(state, context)
        releaseClaim(pyreKey, context.actorId)
        return false, reason or "production_burn_rejected"
    end
    local x, y, z = U().position(target.square)
    state.work = {
        kind = "burn_body", body = target.body, key = target.key, zoneId = zone.id,
        x = x, y = y, z = z or 0, startedAt = now(),
    }
    state.burnTarget = nil
    state.phase = "burning"
    return true, "production_burning"
end

-- The vanilla action starts a real fire on the corpse tile; only that fire
-- proves the ignition. The lit body is marked so it is never lit twice.
function Disposal.pollBurn(actor, order, state, context)
    local work = state.work
    local pyreKey = "pyre:" .. tostring(work.zoneId)
    claim(pyreKey, order.id, context.actorId)
    claim(work.key, order.id, context.actorId)
    if workActive(actor, "burn_body") then
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_burn_timeout")
            if cancelled ~= true then return false, cancelReason or "burn_cancel_failed" end
            state.work = nil
            releaseClaim(pyreKey, context.actorId)
            releaseClaim(work.key, context.actorId)
            return blockOrder(order, "burn_timeout")
        end
        return true, "production_burning"
    end
    if work.finishedAt == nil then
        local finished, finishReason = finishWork(actor)
        if finished ~= true then return false, finishReason or "burn_finish_failed" end
        work.finishedAt = now()
    end
    local lit = Disposal.squareOnFire(U().gridSquare(work.x, work.y, work.z))
    if not lit and now() - work.finishedAt < config("productionBurnIgniteVerifyMs", 6000) then
        return true, "production_burn_verifying"
    end
    state.work = nil
    if not lit then
        releaseClaim(pyreKey, context.actorId)
        releaseClaim(work.key, context.actorId)
        noteCandidateFailure(order, "pyre-body", work.key, "burn_unverified", zoneFor(order))
        if Disposal.raining() then return blockOrder(order, "raining") end
        state.burnFailures = (state.burnFailures or 0) + 1
        if state.burnFailures >= config("productionCandidateMaxAttempts", 3) then
            state.burnFailures = 0
            return blockOrder(order, "burn_unverified")
        end
        return false, "burn_unverified"
    end
    state.burnFailures = 0
    local data = Disposal.bodyData(work.body)
    if data then data[Production.BURNED_TAG] = tostring(order.id) end
    Disposal.clearTag(work.body)
    SC.BaseLife.noteProductionCounter("pyresLit", 1)
    speak(actor, "burn.ignite", nil, work.key, context.runtime)
    state.burn = {
        key = work.key, body = work.body, x = work.x, y = work.y, z = work.z, litAt = now(),
    }
    state.phase = "watching"
    return true, "production_pyre_lit"
end

-- Watch from a distance until the fire is out (bounded). The body counts once
-- it burned long enough or is gone; a fire the rain put out early is retried
-- later instead.
function Disposal.pollWatch(actor, order, state, context)
    local burn = state.burn
    local zone = zoneFor(order)
    if not zone then
        state.burn = nil
        return blockOrder(order, "invalid_production_zone")
    end
    local pyreKey = "pyre:" .. tostring(zone.id)
    claim(pyreKey, order.id, context.actorId)
    claim(burn.key, order.id, context.actorId)
    state.phase = "watching"
    local current = now()
    if current - (burn.checkedAt or 0) >= 1000 then
        burn.checkedAt = current
        if Disposal.fireSpread(zone) then return Disposal.fireEmergency(actor, order, state, context) end
    end
    local burning = Disposal.pyreBurning(zone)
    local burnedFor = current - burn.litAt
    if burning and burnedFor < config("productionBurnWatchMaxMs", 240000) then
        speak(actor, "burn.watch", nil, burn.key .. ":" .. tostring(math.floor(burnedFor / 30000)),
            context.runtime)
        return true, Disposal.keepWatch(actor, order, zone)
    end
    state.burn = nil
    releaseClaim(pyreKey, context.actorId)
    releaseClaim(burn.key, context.actorId)
    if not burning and burnedFor < config("productionBurnCreditMs", 20000)
        and Disposal.bodyAt(burn.body, U().gridSquare(burn.x, burn.y, burn.z)) then
        local data = Disposal.bodyData(burn.body)
        if data then data[Production.BURNED_TAG] = nil end
        noteCandidateFailure(order, "pyre-body", burn.key, "burn_went_out", zone)
        if Disposal.raining() then
            speak(actor, "burn.rain", nil, burn.key, context.runtime)
            return blockOrder(order, "raining")
        end
        return false, "burn_went_out"
    end
    local progressed, progressReason = SC.BaseLife.recordProductionProgress(order.id, 1)
    if progressed ~= true then return false, progressReason or "burn_progress_failed" end
    metrics.bodiesBurned = metrics.bodiesBurned + 1
    SC.BaseLife.noteProductionCounter("bodiesBurned", 1)
    if SC.Diary and type(SC.Diary.noteWork) == "function" then
        pcall(SC.Diary.noteWork, actor, "burned", 1)
    end
    if order.operation == "collect_bodies" then
        SC.BaseLife.noteProductionCounter("bodiesCollected", 1)
    end
    if ceremony(actor, { key = "pyre:" .. tostring(burn.key) .. ":" .. tostring(burn.litAt),
        pyre = true }, context.runtime) then
        state.pendingSalute = true
    end
    return true, "production_body_burned"
end

-- Burn the next body lying on the pyre. While the pyre burns, workers keep
-- their distance and watch for spreading fire instead.
function Disposal.burnOnPyre(actor, order, state, context, zone, optional)
    if Disposal.pyreBurning(zone) then
        state.phase = "watching"
        if Disposal.fireSpread(zone) then return Disposal.fireEmergency(actor, order, state, context) end
        return true, Disposal.keepWatch(actor, order, zone)
    end
    local target = state.burnTarget
    if target and not Disposal.bodyAt(target.body, target.square) then
        Disposal.releaseBurnTarget(state, context)
        target = nil
    end
    if not target then
        local carrying = 0
        for y = zone.y1, zone.y2 do
            for x = zone.x1, zone.x2 do
                local square = U().gridSquare(x, y, zone.z)
                U().squareStaticMovingObjects(square, function(object)
                    local key = bodyKey(object)
                    local kind, why = Disposal.candidate(object, order, actor, true)
                    if kind and not claimActive(key, context.actorId)
                        and not onCooldown(order, "pyre-body", key) then
                        target = { body = object, square = square, key = key }
                        return false
                    end
                    if why == "carries_items" then carrying = carrying + 1 end
                end, 16)
                if target then break end
            end
            if target then break end
        end
        if not target then
            if optional then return nil end
            if carrying > 0 then
                return blockOrder(order, "bodies_carry_items:" .. tostring(carrying))
            end
            return blockOrder(order, "no_bodies_on_pyre")
        end
        state.burnTarget = target
    end
    return Disposal.ignite(actor, order, state, context, zone, target)
end

-- Hauling --------------------------------------------------------------------

function Disposal.abandonHaul(state, context)
    local haul = state.haul
    state.haul = nil
    if not haul then return end
    releaseClaim(haul.key, context.actorId)
    if type(haul.destination) == "table" and haul.destination.key then
        releaseClaim(haul.destination.key, context.actorId)
    end
    if haul.pyreKey then releaseClaim(haul.pyreKey, context.actorId) end
end

-- A grab that never becomes a drag cools the body down; repeated failures
-- mean the grapple does not work for this companion at all.
function Disposal.dragFailure(order, state, context, reason)
    local haul = state.haul
    if haul then
        if Disposal.bodyAt(haul.body, haul.square) then Disposal.clearTag(haul.body) end
        noteCandidateFailure(order, haul.purpose, haul.key, reason, haul.sourceZone)
    end
    Disposal.abandonHaul(state, context)
    state.dragFailures = (state.dragFailures or 0) + 1
    if state.dragFailures >= config("productionCandidateMaxAttempts", 3) then
        state.dragFailures = 0
        return blockOrder(order, "drag_unavailable")
    end
    return false, reason
end

-- Let go where the worker stands. The body stays in the world; its stale
-- haul tag is harmless and is overwritten by the next grab.
function Disposal.dropHere(actor, order, state, context, reason, block)
    local native = natives()
    if native and type(native.releaseCorpse) == "function" then pcall(native.releaseCorpse, actor) end
    Disposal.abandonHaul(state, context)
    if block == true then return blockOrder(order, reason) end
    return false, reason
end

function Disposal.emergencyDrop(actor, order, state, context)
    speak(actor, "burial.haul.threat", nil, tostring(now()), context.runtime)
    return Disposal.dropHere(actor, order, state, context, "unsafe_area")
end

-- Reserve where the body goes before touching it: the pyre (one haul at a
-- time) or an open grave, dug first when none is free.
function Disposal.reserveDestination(actor, order, state, context, zone, haul)
    if zone.kind == "pyre" then
        local pyreKey = "pyre:" .. tostring(zone.id)
        if claimActive(pyreKey, context.actorId) then
            state.phase = "watching"
            return true, "production_pyre_claimed"
        end
        claim(pyreKey, order.id, context.actorId)
        haul.pyreKey, haul.destination = pyreKey, { kind = "pyre" }
        return nil
    end
    local grave = Disposal.openGrave(order, context, haul.identity == "fallen")
    if grave then
        claim(grave.key, order.id, context.actorId)
        haul.destination = { kind = "grave", x = grave.x, y = grave.y, z = grave.z, key = grave.key }
        return nil
    end
    -- The new grave is capacity for the collection, never order progress.
    return digNext(actor, order, state, context, "capacity")
end

-- Choose a body, reserve where it goes, walk over and take hold of it.
-- Everything a trip needs is checked before a body is touched.
function Disposal.beginHaul(actor, order, state, context, zone)
    local haul = state.haul
    if threatNearby(actor, context.runtime) then
        Disposal.abandonHaul(state, context)
        return false, "unsafe_area"
    end
    if not haul then
        if zone.kind == "pyre" then
            if claimActive("pyre:" .. tostring(zone.id), context.actorId) then
                state.phase = "watching"
                return true, Disposal.keepWatch(actor, order, zone)
            end
            local safe, unsafe = Production.validatePyreZone(zone)
            if safe ~= true then return blockOrder(order, "pyre_unsafe:" .. tostring(unsafe)) end
            if Disposal.requireDry(order) and Disposal.raining() then
                return blockOrder(order, "raining")
            end
            local missing = Disposal.missingSupply(actor)
            if missing then return Disposal.fetchSupply(actor, order, state, missing) end
        end
        state.phase = "seeking"
        local candidate, reason, terminal = Disposal.nextSource(actor, order, state, context, zone)
        if not candidate then
            if terminal then return blockOrder(order, reason) end
            return true, reason
        end
        if lumberNight() and SC.BaseLife.isInside(candidate.square) ~= true then
            state.collect = nil
            return blockOrder(order, "lumber_night")
        end
        claim(candidate.key, order.id, context.actorId)
        candidate.stage = "destination"
        state.haul, haul = candidate, candidate
    end
    claim(haul.key, order.id, context.actorId)
    if not Disposal.bodyAt(haul.body, haul.square) then
        Disposal.abandonHaul(state, context)
        return false, "body_moved"
    end
    if haul.stage == "destination" then
        local handled, reason, terminal = Disposal.reserveDestination(actor, order, state,
            context, zone, haul)
        if handled ~= nil then return handled, reason, terminal end
        haul.stage = "approach"
    end
    state.phase = "approaching"
    local reach = Disposal.reach(order, zone) or SC.BaseLife.isInside(haul.square) ~= true
    local approach, approachReason = approachSquare(actor, haul.square,
        "move_to_production_body", nil, reach)
    if approach == "failed" then
        noteCandidateFailure(order, haul.purpose, haul.key, approachReason, haul.sourceZone)
        Disposal.abandonHaul(state, context)
        return false, approachReason
    end
    if approach ~= "arrived" then return true, approachReason end
    local tag = Disposal.newTag(order, context.actorId)
    if not Disposal.setTag(haul.body, tag) then
        noteCandidateFailure(order, haul.purpose, haul.key, "body_tag_failed", haul.sourceZone)
        Disposal.abandonHaul(state, context)
        return false, "body_tag_failed"
    end
    local accepted, reason = U().move(actor, "walk", {
        action = "grab_body", body = haul.body, targetSquare = haul.square,
    })
    if accepted ~= true and transientRejection(reason) then
        Disposal.clearTag(haul.body)
        return true, reason
    end
    if accepted ~= true or not workActive(actor, "grab_body") then
        Disposal.clearTag(haul.body)
        return Disposal.dragFailure(order, state, context, reason or "production_grab_rejected")
    end
    haul.tag = tag
    state.work = { kind = "grab_body", key = haul.key, startedAt = now() }
    state.phase = "grabbing"
    return true, "production_grabbing"
end

-- The grab is proven only by a real grapple (isDraggingCorpse) shortly after
-- the vanilla action finishes.
function Disposal.pollGrab(actor, order, state, context)
    local work, haul = state.work, state.haul
    if workActive(actor, "grab_body") then
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_grab_timeout")
            if cancelled ~= true then return false, cancelReason or "grab_cancel_failed" end
            state.work = nil
            return Disposal.dragFailure(order, state, context, "grab_timeout")
        end
        return true, "production_grabbing"
    end
    if work.finishedAt == nil then
        local finished, finishReason = finishWork(actor)
        if finished ~= true then return false, finishReason or "grab_finish_failed" end
        work.finishedAt = now()
    end
    local native = natives()
    local dragging = native ~= nil and type(native.isDraggingCorpse) == "function"
        and native.isDraggingCorpse(actor) == true
    if not dragging then
        if haul and now() - work.finishedAt < config("productionCorpseDragStartMs", 4000) then
            return true, "production_grab_verifying"
        end
        state.work = nil
        return Disposal.dragFailure(order, state, context, "grab_unverified")
    end
    state.work = nil
    if not haul then return Disposal.dropHere(actor, order, state, context, "production_haul_missing") end
    state.dragFailures = 0
    haul.stage, haul.dragStartedAt = "dragging", now()
    metrics.bodiesDragged = metrics.bodiesDragged + 1
    state.phase = "dragging"
    speak(actor, "burial.haul.start", nil, haul.tag, context.runtime)
    return true, "production_dragging"
end

-- Where a dragged body is laid down: beside its reserved grave (switching to
-- another open grave if that one filled up), or on the free pyre tile
-- nearest the middle of the pyre.
function Disposal.dropTarget(order, context, zone, haul)
    if zone.kind == "pyre" then
        local square = haul.dropSquare
        if square and (Disposal.hasBody(square) or Disposal.squareOnFire(square)) then square = nil end
        if not square then
            square = Disposal.freePyreSquare(zone)
            haul.dropSquare = square
        end
        return square, nil
    end
    local info = primaryGraveAt(haul.destination)
    if not graveOpen(info) or (haul.identity == "fallen" and info.corpses > 0) then
        if type(haul.destination) == "table" then
            releaseClaim(haul.destination.key, context.actorId)
        end
        info = Disposal.openGrave(order, context, haul.identity == "fallen")
        if not info then return nil end
        claim(info.key, order.id, context.actorId)
        haul.destination = { kind = "grave", x = info.x, y = info.y, z = info.z, key = info.key }
    end
    local px, py = gravePartner(info)
    return U().gridSquare(info.x, info.y, info.z), {
        { x = info.x, y = info.y, z = info.z }, { x = px, y = py, z = info.z },
    }
end

-- Drag onto a pyre tile itself: the body lands behind the worker.
function Disposal.dragInto(actor, square, reach)
    if U().sameSquare(actor, square) then return "arrived", "production_in_range" end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function" then
        return "failed", "navigation_unavailable"
    end
    local accepted, reason = SC.Navigation.requestAny(actor, { square }, "walk", {
        action = "drag_body_to_pyre", targetSquare = square, arrivalDistance = 0.5,
        workCampOnly = true, workReach = reach == true, draggingBody = true,
    })
    if accepted ~= true then
        if transientRejection(reason) then return "pending", reason end
        return "failed", reason or "drag_route_blocked"
    end
    if U().sameSquare(actor, square) then return "arrived", "production_in_range" end
    return "pending", reason or "production_dragging"
end

function Disposal.continueDrag(actor, order, state, context, zone)
    local haul = state.haul
    local native = natives()
    if not (native and type(native.isDraggingCorpse) == "function"
        and native.isDraggingCorpse(actor)) then
        -- The grapple ended on its own; the body lies wherever it fell.
        Disposal.abandonHaul(state, context)
        return false, "drag_lost"
    end
    if threatNearby(actor, context.runtime) then
        return Disposal.emergencyDrop(actor, order, state, context)
    end
    if type(haul.destination) == "table" and haul.destination.key then
        claim(haul.destination.key, order.id, context.actorId)
    end
    if haul.pyreKey then claim(haul.pyreKey, order.id, context.actorId) end
    local elapsed = now() - (haul.dragStartedAt or now())
    if elapsed > config("productionCorpseDragTimeoutMs", 90000) then
        return Disposal.dropHere(actor, order, state, context, "drag_timeout")
    end
    state.phase = "dragging"
    speak(actor, "burial.haul.drag", nil,
        tostring(haul.tag) .. ":" .. tostring(math.floor(elapsed / 15000)), context.runtime)
    local target, avoid = Disposal.dropTarget(order, context, zone, haul)
    if not target then
        return Disposal.dropHere(actor, order, state, context, "drag_destination_missing")
    end
    local reach = Disposal.reach(order, zone) or SC.BaseLife.isInside(actor) ~= true
    local result, moveReason
    if zone.kind == "pyre" then
        result, moveReason = Disposal.dragInto(actor, target, reach)
    else
        result, moveReason = approachSquare(actor, target, "drag_body_to_grave", avoid, reach, true)
    end
    if result == "failed" then
        return Disposal.dropHere(actor, order, state, context, "drag_route_blocked", true)
    end
    if result ~= "arrived" then return true, moveReason end
    local accepted, reason = U().move(actor, "walk", {
        action = "drop_body", targetSquare = U().squareOf(actor),
    })
    if accepted ~= true and transientRejection(reason) then return true, reason end
    if accepted ~= true or not workActive(actor, "drop_body") then
        return Disposal.dropHere(actor, order, state, context, reason or "production_drop_rejected")
    end
    state.work = { kind = "drop_body", startedAt = now() }
    state.phase = "placing"
    return true, "production_placing"
end

-- The drop is proven only by the tagged body lying near the worker again.
function Disposal.pollDrop(actor, order, state, context)
    local work, haul = state.work, state.haul
    local native = natives()
    if workActive(actor, "drop_body") then
        if actionTimedOut(state) then
            local cancelled, cancelReason = cancelWork(actor, "production_drop_timeout")
            if cancelled ~= true then return false, cancelReason or "drop_cancel_failed" end
            state.work = nil
            return Disposal.dropHere(actor, order, state, context, "drop_timeout")
        end
        return true, "production_placing"
    end
    if work.finishedAt == nil then
        local finished, finishReason = finishWork(actor)
        if finished ~= true then return false, finishReason or "drop_finish_failed" end
        work.finishedAt = now()
    end
    local stillDragging = native ~= nil and type(native.isDraggingCorpse) == "function"
        and native.isDraggingCorpse(actor) == true
    local body, square
    if not stillDragging and haul then body, square = Disposal.findTagged(actor, haul.tag, 2) end
    if not body then
        if now() - work.finishedAt < config("productionCorpseDropVerifyMs", 4000) then
            return true, "production_drop_verifying"
        end
        state.work = nil
        return Disposal.dropHere(actor, order, state, context, "drop_unverified")
    end
    state.work = nil
    if native and type(native.settleDrag) == "function" then pcall(native.settleDrag, actor) end
    haul.body, haul.square, haul.key = body, square, bodyKey(body)
    haul.stage = "placed"
    claim(haul.key, order.id, context.actorId)
    speak(actor, "burial.haul.drop", nil, haul.tag, context.runtime)
    return Disposal.disposePlaced(actor, order, state, context, zoneFor(order))
end

-- A body laid at its destination is buried in its reserved grave or burned on
-- the pyre. One that landed beside the pyre is taken hold of again, bounded.
function Disposal.disposePlaced(actor, order, state, context, zone)
    local haul = state.haul
    if not zone then
        Disposal.abandonHaul(state, context)
        return blockOrder(order, "invalid_production_zone")
    end
    if not Disposal.bodyAt(haul.body, haul.square) then
        Disposal.abandonHaul(state, context)
        return false, "body_moved"
    end
    if zone.kind == "pyre" then
        local x, y, z = U().position(haul.square)
        if not Disposal.inside(zone, x, y, z) then
            haul.attempts = (haul.attempts or 0) + 1
            if haul.attempts >= config("productionCorpsePlacementAttempts", 2) then
                Disposal.clearTag(haul.body)
                Disposal.abandonHaul(state, context)
                return blockOrder(order, "pyre_placement_failed")
            end
            haul.stage, haul.dropSquare = "approach", nil
            return true, "production_replacing_body"
        end
        Disposal.clearTag(haul.body)
        state.haul = nil
        state.burnTarget = { body = haul.body, square = haul.square, key = haul.key }
        return Disposal.burnOnPyre(actor, order, state, context, zone, false)
    end
    local grave = primaryGraveAt(haul.destination)
    if not graveOpen(grave) or (haul.identity == "fallen" and grave.corpses > 0) then
        -- The grave filled up meanwhile; the body waits here for another trip.
        Disposal.clearTag(haul.body)
        Disposal.abandonHaul(state, context)
        return false, "production_grave_unavailable"
    end
    local target = {
        body = haul.body, bodySquare = haul.square, key = haul.key,
        grave = { x = grave.x, y = grave.y, z = grave.z }, graveInfo = grave, graveKey = grave.key,
        fallen = haul.identity == "fallen" and haul.fallen or nil, haulTag = haul.tag,
    }
    state.haul = nil
    state.buryTarget = target
    return Disposal.startBurial(actor, order, state, context, target)
end

-- Orders ---------------------------------------------------------------------

-- A grapple that outlived its haul (cancellation, an emergency drop, a lost
-- record) is let go, and the hand items put away at the grab come back.
function Disposal.settleIdle(actor)
    local state = actorStates[actor]
    if state and state.haul then return end
    local native = natives()
    if not native or type(native.dragSessionActive) ~= "function" then return end
    if type(native.isDraggingCorpse) == "function" and native.isDraggingCorpse(actor) then
        pcall(native.releaseCorpse, actor)
    end
    if native.dragSessionActive(actor) then pcall(native.settleDrag, actor) end
end

function Disposal.finishCollect(actor, order, state, context, zone)
    if zone.kind == "burial" then
        local handled, reason, terminal = Disposal.closeGraves(actor, order, state, context, true)
        if handled ~= nil then return handled, reason, terminal end
    end
    return completeOrder(order, "bodies_collected")
end

function Disposal.updateCollect(actor, order, state, context)
    local work = state.work
    if work then
        if work.kind == "grab_body" then return Disposal.pollGrab(actor, order, state, context) end
        if work.kind == "drop_body" then return Disposal.pollDrop(actor, order, state, context) end
        if work.kind == "burn_body" then return Disposal.pollBurn(actor, order, state, context) end
        if work.kind == "bury_body" then return pollBury(actor, order, state, context) end
        if work.kind == "fill_grave" then return pollFill(actor, order, state, context) end
        if work.kind == "dig_grave" then return pollDig(actor, order, state, context) end
    end
    if state.burn then return Disposal.pollWatch(actor, order, state, context) end
    local zone = zoneFor(order)
    if not zone then return blockOrder(order, "invalid_production_zone") end
    local haul = state.haul
    if haul and haul.stage == "dragging" then
        return Disposal.continueDrag(actor, order, state, context, zone)
    end
    if haul and haul.stage == "placed" then
        return Disposal.disposePlaced(actor, order, state, context, zone)
    end
    if not haul then
        if state.buryTarget then
            local handled, reason, terminal = Disposal.resumeBurial(actor, order, state, context)
            if handled ~= nil then return handled, reason, terminal end
        end
        if zone.kind == "burial" then
            local handled, reason, terminal = Disposal.closeGraves(actor, order, state, context, false)
            if handled ~= nil then return handled, reason, terminal end
        end
        if order.completed >= order.requested then
            return Disposal.finishCollect(actor, order, state, context, zone)
        end
        if zone.kind == "pyre" then
            local handled, reason, terminal = Disposal.burnOnPyre(actor, order, state, context,
                zone, true)
            if handled ~= nil then return handled, reason, terminal end
        end
    end
    return Disposal.beginHaul(actor, order, state, context, zone)
end

function Disposal.updateBurn(actor, order, state, context)
    local work = state.work
    if work and work.kind == "burn_body" then return Disposal.pollBurn(actor, order, state, context) end
    if state.burn then return Disposal.pollWatch(actor, order, state, context) end
    if order.completed >= order.requested then return completeOrder(order, "bodies_burned") end
    local zone = zoneFor(order)
    if not zone or zone.kind ~= "pyre" then return blockOrder(order, "no_pyre_site") end
    return Disposal.burnOnPyre(actor, order, state, context, zone, false)
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
    Disposal.settleIdle(actor)
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
    -- A fire that spread beyond its pyre waits for the player's Retry.
    if order.state == "blocked" and order.blocker ~= "fire_spread"
        and (tonumber(order.retryAt) or 0) <= now()
        and (job.state ~= "blocked" or (tonumber(job.retryAt) or 0) <= now()) then
        SC.BaseLife.reopenProductionOrder(order.id)
    end
    if order.state ~= "running" then return false, order.blocker or "production_blocked", false end
    local id = actorId(actor)
    if not assigned(order, id) then return false, "production_worker_not_assigned", true end
    local descriptor = descriptors[order.operation]
    if not descriptor then return blockOrder(order, "production_operation_unavailable") end
    local state = stateFor(actor, order.id)
    local returnHandled, returnReason, returnTerminal = returnBorrowedTool(actor, order, state)
    if returnHandled ~= nil then return returnHandled, returnReason, returnTerminal end
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
    -- A blocked/cancelled attempt must not strand a borrowed shovel in the
    -- worker's bag. Reopen only long enough to make the verified return trip,
    -- then restore the original blocker for the management UI.
    if terminal == true and order.state == "blocked"
        and type(state.borrowedTools) == "table"
        and next(state.borrowedTools) ~= nil then
        local key = next(state.borrowedTools)
        SC.BaseLife.reopenProductionOrder(order.id)
        scheduleToolReturn(state, key)
        state.toolReturn.blocker = reason or order.blocker or "production_blocked"
        notePhase(order.id, id, "returning_tool")
        return true, "production_tool_return_pending", false
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
    -- Completed native work may already have changed inventory or the world.
    -- Reuse each ordinary poller before teardown so its proof, counters and
    -- follow-up work are committed exactly once. A poller still inside a
    -- bounded verification window keeps ownership and refuses cancellation.
    if work and work.kind ~= "saw_logs" and order
        and not workActive(actor, work.kind) then
        local context = { actorId = actorId(actor), runtime = nil }
        local reconciled, reconcileReason
        if work.kind == "chop_tree" then
            reconciled, reconcileReason = pollChop(actor, order, state, context)
        elseif work.kind == "dig_grave" then
            reconciled, reconcileReason = pollDig(actor, order, state, context)
        elseif work.kind == "fill_grave" then
            reconciled, reconcileReason = pollFill(actor, order, state, context)
        elseif work.kind == "bury_body" then
            reconciled, reconcileReason = pollBury(actor, order, state, context)
        elseif work.kind == "burn_body" then
            reconciled, reconcileReason = Disposal.pollBurn(actor, order, state, context)
        elseif work.kind == "grab_body" then
            reconciled, reconcileReason = Disposal.pollGrab(actor, order, state, context)
        elseif work.kind == "drop_body" then
            reconciled, reconcileReason = Disposal.pollDrop(actor, order, state, context)
        end
        if state.work ~= nil then
            return false, reconcileReason or "production_reconciliation_pending"
        end
        work = nil
    end
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
                beforeCount = receipt.beforeCount, beforeIds = receipt.beforeIds,
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
    -- Never leave a companion holding a body: let go, then hand back the
    -- items the grab put away once the grapple has ended.
    if native and type(native.isDraggingCorpse) == "function" and native.isDraggingCorpse(actor) then
        pcall(native.releaseCorpse, actor)
    end
    if native and type(native.settleDrag) == "function" then pcall(native.settleDrag, actor) end
    if state and state.visualAt ~= nil and native and type(native.cancelVisual) == "function" then
        pcall(native.cancelVisual, actor, reason or "production_cancelled")
    end
    if state and type(state.borrowedTools) == "table" and SC.BaseWork
        and type(SC.BaseWork.restoreToStorage) == "function" then
        for _, borrowed in pairs(state.borrowedTools) do
            pcall(SC.BaseWork.restoreToStorage, actor, borrowed.storage,
                borrowed.container, borrowed.item)
        end
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
    Disposal.urgentAt = {}
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
Production.register({ id = "collect_bodies", family = "disposal", update = Disposal.updateCollect })
Production.register({ id = "burn_bodies", family = "disposal", update = Disposal.updateBurn })
registerDialogue()

return Production
