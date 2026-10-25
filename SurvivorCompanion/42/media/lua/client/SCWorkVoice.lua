-- SPDX-License-Identifier: MIT

-- Voice for expeditions and work orders. Short action lines mark real work
-- moments (a tree down, a trunk full, a job done, the turn for home), and two
-- crew members trade a few words while they travel or work. Speech only:
-- nothing here moves, faces, blocks or decides anything. Callers report what
-- already happened; this module picks whether, who and what to say.
--
-- Every line goes through SC.Dialogue in the speaker's own voice. Pacing is
-- bounded on four levels: one party gap between any two lines, a gap per
-- topic, a cooldown per speaker and topic, and a quiet period after anything
-- the speaker said. The Mod Options chatter level stretches all of them.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.Dialogue and type(require) == "function" then pcall(require, "SCDialogue") end
if not SC.WorkVoiceLines and type(require) == "function" then pcall(require, "SCWorkVoiceLines") end

SC.WorkVoice = SC.WorkVoice or {}
local Voice = SC.WorkVoice

local function U() return SC.GameplayUtil end
local function lines() return SC.WorkVoiceLines or {} end

local function config(key, fallback)
    local utility = U()
    local value = utility and tonumber(utility.config(key)) or nil
    if value == nil then return fallback end
    return value
end

local function enabled()
    local utility = U()
    return utility ~= nil and utility.config("workVoiceEnabled") ~= false
end

local function banterEnabled()
    return enabled() and U().config("banterEnabled") ~= false
end

local function chatter()
    if SC.Banter and type(SC.Banter.chatterMultiplier) == "function" then
        local ok, value = pcall(SC.Banter.chatterMultiplier)
        if ok and tonumber(value) then return math.max(1, tonumber(value)) end
    end
    return 1
end

-- ---------------------------------------------------------------------------
-- Events. chance is percent; cooldownMs is per speaker; topicGapMs is for
-- anyone. A failed roll still starts the speaker's cooldown, so a reason
-- reported every pulse is considered once, not rerolled until it lands.
-- ---------------------------------------------------------------------------

local DEFAULT_EVENT = { chance = 50, cooldownMs = 120000, topicGapMs = 30000 }
local EVENTS = {
    ["expedition.drive_out"] = { chance = 70, cooldownMs = 60000, topicGapMs = 60000 },
    ["expedition.drive_home"] = { chance = 70, cooldownMs = 60000, topicGapMs = 60000 },
    ["expedition.park_site"] = { chance = 60, cooldownMs = 60000, topicGapMs = 60000 },
    ["expedition.wood_arrive"] = { chance = 85, cooldownMs = 60000, topicGapMs = 60000 },
    ["expedition.near_home"] = { chance = 70, cooldownMs = 60000, topicGapMs = 60000 },
    ["expedition.turn_home"] = { chance = 85, cooldownMs = 60000, topicGapMs = 60000 },
    ["wood.chop"] = { chance = 35, cooldownMs = 150000, topicGapMs = 30000 },
    ["wood.timber"] = { chance = 65, cooldownMs = 40000, topicGapMs = 20000 },
    ["wood.haul"] = { chance = 25, cooldownMs = 150000, topicGapMs = 45000 },
    ["wood.load"] = { chance = 40, cooldownMs = 120000, topicGapMs = 45000 },
    ["wood.full"] = { chance = 100, cooldownMs = 300000, topicGapMs = 120000 },
    ["wood.rest"] = { chance = 60, cooldownMs = 240000, topicGapMs = 60000 },
    ["wood.wait"] = { chance = 30, cooldownMs = 300000, topicGapMs = 90000 },
    ["prep.fetch"] = { chance = 60, cooldownMs = 300000, topicGapMs = 60000 },
    ["prep.missing"] = { chance = 100, cooldownMs = 600000, topicGapMs = 300000 },
    ["prep.daylight"] = { chance = 80, cooldownMs = 900000, topicGapMs = 300000 },
    ["delivery.unload"] = { chance = 50, cooldownMs = 180000, topicGapMs = 60000 },
    ["delivery.stored"] = { chance = 30, cooldownMs = 120000, topicGapMs = 30000 },
    ["delivery.blocked"] = { chance = 100, cooldownMs = 600000, topicGapMs = 300000 },
    ["delivery.done"] = { chance = 100, cooldownMs = 60000, topicGapMs = 60000 },
    ["search.empty"] = { chance = 55, cooldownMs = 180000, topicGapMs = 45000 },
    ["search.blocked"] = { chance = 45, cooldownMs = 240000, topicGapMs = 60000 },
    ["field.chop"] = { chance = 35, cooldownMs = 150000, topicGapMs = 30000 },
    ["field.harvest"] = { chance = 35, cooldownMs = 150000, topicGapMs = 30000 },
    ["field.timber"] = { chance = 55, cooldownMs = 45000, topicGapMs = 20000 },
    ["field.picked"] = { chance = 25, cooldownMs = 90000, topicGapMs = 30000 },
    ["field.load"] = { chance = 35, cooldownMs = 120000, topicGapMs = 45000 },
    ["field.full"] = { chance = 80, cooldownMs = 300000, topicGapMs = 60000 },
    ["field.done"] = { chance = 70, cooldownMs = 300000, topicGapMs = 60000 },
    ["job.start"] = { chance = 40, cooldownMs = 360000, topicGapMs = 30000 },
    ["job.done"] = { chance = 55, cooldownMs = 240000, topicGapMs = 30000 },
    ["job.blocked"] = { chance = 35, cooldownMs = 600000, topicGapMs = 120000 },
}

-- Results that callers already return. Mapping them here keeps every work
-- module free of speech decisions.
local WOOD_RESULTS = {
    wood_chopping = "wood.chop", wood_tree_felled = "wood.timber",
    wood_log_collected = "wood.haul", wood_cargo_loaded = "wood.load",
    wood_trunk_full = "wood.full", wood_capacity_reached = "wood.full",
    wood_resting = "wood.rest",
    wood_waiting_for_cutter = "wood.wait", wood_waiting_for_hauler = "wood.wait",
    wood_preparing_axe = "prep.fetch", wood_preparing_axes = "prep.fetch",
    wood_axe_missing = "prep.missing", wood_waiting_for_daylight = "prep.daylight",
}
local FISHING_PREP_RESULTS = {
    fishing_preparing_rod = "prep.fetch", fishing_preparing_bait = "prep.fetch",
    fishing_rod_missing = "prep.missing", fishing_bait_missing = "prep.missing",
}
local FIELD_RESULTS = {
    field_cargo_loaded = "field.load", field_carry_limit_reached = "field.full",
    field_worker_done = "field.done",
}
local DELIVERY_BLOCKED = {
    matching_storage_missing = true, matching_storage_full = true,
    matching_storage_unreachable = true, matching_storage_unloaded = true,
    destination_full = true, expedition_storage_approach_timeout = true,
}
local JOB_GROUPS = {
    haul = "store", sort = "store", sort_floor = "store", fetch = "store",
    unload_vehicle = "unload", refuel_vehicle = "fuel", refuel_generator = "generator",
    inflate_tires = "tires", wash_vehicle = "wash",
    repair = "repair", maintain = "repair", craft_supply = "repair",
    build = "build", barricade = "barricade", clean = "clean", cook = "cook",
    gather_materials = "gather",
}
-- Why a crew turned home decides how it sounds.
local RETURN_CLASSES = {
    quantity_met = "done", wood_quantity_met = "done", observed = "done",
    wood_finished = "done",
    wood_forest_empty = "empty", wood_forest_unloaded = "empty",
    wood_logs_unreachable = "empty", site_unreachable = "empty",
    site_entry_blocked = "empty", no_fishing_water = "empty",
    capacity_full = "full", wood_capacity_reached = "full", wood_trunk_full = "full",
    return_time_reached = "time", arrival_reserve_reached = "time",
    search_deadline = "time",
    wood_night = "night",
    wood_unsafe = "danger", horde_no_safe_detour = "danger", squad_wounded = "danger",
    wood_injured = "danger", wood_worker_dead = "danger",
    wood_exhausted = "spent", wood_axe_unavailable = "spent",
    radio_return = "radio",
}
local DRIVING = { driving_out = "drive_out", driving_home = "drive_home" }

-- ---------------------------------------------------------------------------
-- State. Nothing here is saved: a reload starts with fresh, silent timers.
-- ---------------------------------------------------------------------------

local function freshState()
    return {
        actors = setmetatable({}, { __mode = "k" }),
        missions = setmetatable({}, { __mode = "k" }),
        topicNextAt = {},
        partyNextAt = -math.huge,
        exchange = nil,
        recentBeats = {},
        campBanterNextAt = nil,
        deliveredTrips = {},
        deliveredCount = 0,
        fieldSeen = setmetatable({}, { __mode = "k" }),
    }
end
local state = freshState()

local function actorState(actor)
    local entry = state.actors[actor]
    if not entry then
        entry = { nextAt = {} }
        state.actors[actor] = entry
    end
    return entry
end

local registered = false
local function registerPools()
    if registered then return true end
    if type(lines().register) ~= "function" or lines().register() ~= true then return false end
    registered = true
    return true
end
registerPools()

-- ---------------------------------------------------------------------------
-- Eligibility
-- ---------------------------------------------------------------------------

local function roll(percent, actor, current, salt)
    percent = tonumber(percent) or 0
    if percent >= 100 then return true end
    if percent <= 0 then return false end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, 100)
        if ok and tonumber(value) then return tonumber(value) < percent end
    end
    local hash = U().stableHash(tostring(U().idOf(actor)) .. ":" .. tostring(salt or "")
        .. ":" .. tostring(math.floor((tonumber(current) or 0) / 1000)))
    return math.abs(tonumber(hash) or 0) % 100 < percent
end

local function pick(count, actor, current, salt)
    if count <= 1 then return 1 end
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, count)
        if ok and tonumber(value) then return math.floor(tonumber(value)) % count + 1 end
    end
    local hash = U().stableHash(tostring(U().idOf(actor)) .. ":" .. tostring(salt or "")
        .. ":" .. tostring(current))
    return math.abs(tonumber(hash) or 0) % count + 1
end

local function snapshotFor(actor)
    local registry = SC.Registry
    local record = registry and type(registry.byId) == "function"
        and registry.byId(U().idOf(actor)) or nil
    local runtime = type(record) == "table" and record.runtime or nil
    if type(runtime) ~= "table" then return nil end
    return type(runtime.senses) == "table" and runtime.senses.current or runtime.snapshot
end

local function calm(snapshot)
    if type(snapshot) ~= "table" then return true end
    if (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) > 0 then return false end
    if (tonumber(snapshot.immediateCount) or 0) > 0 then return false end
    if (tonumber(snapshot.pressure) or 0) > 0 then return false end
    return true
end

local function primaryPlayer()
    if type(getSpecificPlayer) == "function" then
        local ok, player = pcall(getSpecificPlayer, 0)
        if ok and player ~= nil then return player end
    end
    if type(getPlayer) == "function" then
        local ok, player = pcall(getPlayer)
        if ok then return player end
    end
    return nil
end

-- Overhead speech reaches the player near the speaker, or through an open
-- companion view (an expedition or Base Watch). Elsewhere it is not said.
local function audible(actor)
    local view = SC.ViewSession
    if view and type(view.owner) == "function" and view.owner() ~= nil then return true end
    local player = primaryPlayer()
    if player == nil or U().isDead(player) then return false end
    return U().sameFloor(actor, player)
        and (U().distance(actor, player) or math.huge) <= config("workVoiceAudibleDistance", 40)
end

local function lastSpokenAt(actor)
    if SC.Dialogue and type(SC.Dialogue.lastSpokenAt) == "function" then
        return tonumber(SC.Dialogue.lastSpokenAt(actor)) or -math.huge
    end
    return -math.huge
end

local function ready(actor, current)
    local utility = U()
    if actor == nil or not utility.isValidActor(actor) or utility.isDead(actor) then
        return false, "work_voice_no_speaker"
    end
    local asleep, known = utility.call(actor, "isAsleep")
    if known and asleep == true then return false, "work_voice_asleep" end
    if not calm(snapshotFor(actor)) then return false, "work_voice_danger" end
    if current - lastSpokenAt(actor) < config("workVoiceQuietMs", 12000) then
        return false, "work_voice_speaker_busy"
    end
    if not audible(actor) then return false, "work_voice_unheard" end
    return true
end

local function say(actor, topic, specification, arguments, salt)
    if not SC.Dialogue or type(SC.Dialogue.say) ~= "function" then return false end
    registerPools()
    local ok, spoken, line, detail = pcall(SC.Dialogue.say, actor, topic, specification,
        arguments, { salt = salt })
    return ok and spoken == true, line, detail
end

-- ---------------------------------------------------------------------------
-- Action chat
-- ---------------------------------------------------------------------------

-- event selects pacing; topic (default "voice." .. event) selects the lines.
function Voice.cue(actor, event, topic, current)
    if not enabled() then return false, "work_voice_disabled" end
    if type(event) ~= "string" then return false, "work_voice_unknown_event" end
    topic = topic or ("voice." .. event)
    if not SC.Dialogue or not SC.Dialogue.has or not (registerPools() and SC.Dialogue.has(topic)) then
        return false, "work_voice_unknown_topic"
    end
    current = tonumber(current) or U().nowMs()
    local spec = EVENTS[event] or DEFAULT_EVENT
    local stretch = chatter()
    if current < state.partyNextAt then return false, "work_voice_party_gap" end
    if current < (state.topicNextAt[topic] or -math.huge) then
        return false, "work_voice_topic_gap"
    end
    local speaker = actor ~= nil and actorState(actor) or nil
    if speaker and current < (speaker.nextAt[topic] or -math.huge) then
        return false, "work_voice_cooldown"
    end
    local okay, why = ready(actor, current)
    if not okay then return false, why end
    speaker.nextAt[topic] = current + (spec.cooldownMs or DEFAULT_EVENT.cooldownMs) * stretch
    if not roll(spec.chance, actor, current, topic) then return false, "work_voice_roll" end
    local spoken = say(actor, topic, nil, nil, event .. ":" .. tostring(current))
    if not spoken then return false, "work_voice_speech_rejected" end
    state.topicNextAt[topic] = current + (spec.topicGapMs or DEFAULT_EVENT.topicGapMs) * stretch
    state.partyNextAt = current + config("workVoicePartyGapMs", 6000) * stretch
    return true, topic
end

function Voice.woodResult(actor, reason)
    local event = WOOD_RESULTS[reason]
    if not event then return false, "work_voice_no_event" end
    return Voice.cue(actor, event)
end

function Voice.fishingPrepResult(actor, reason)
    local event = FISHING_PREP_RESULTS[reason]
    if not event then return false, "work_voice_no_event" end
    return Voice.cue(actor, event)
end

function Voice.fieldResult(actor, handled, reason, kind)
    if actor ~= nil and handled == true then state.fieldSeen[actor] = U().nowMs() end
    if handled ~= true then return false, "work_voice_no_event" end
    if reason == "field_action_started" then
        return Voice.cue(actor, kind == "harvest" and "field.harvest" or "field.chop")
    elseif reason == "field_target_completed" then
        return Voice.cue(actor, kind == "harvest" and "field.picked" or "field.timber")
    end
    local event = FIELD_RESULTS[reason]
    if not event then return false, "work_voice_no_event" end
    return Voice.cue(actor, event)
end

function Voice.deliveryResult(actor, record, handled, reason)
    if handled == true and (reason == "car_trunk_looting" or reason == "car_item_carried") then
        return Voice.cue(actor, "delivery.unload")
    end
    if handled ~= true and DELIVERY_BLOCKED[reason] then
        return Voice.cue(actor, "delivery.blocked")
    end
    if handled ~= true or reason ~= "expedition_supply_stored" then
        return false, "work_voice_no_event"
    end
    local integration = SC.ExpeditionIntegration
    local summary = type(record) == "table" and integration
        and type(integration.summary) == "function" and integration.summary(record) or nil
    local trip = type(record) == "table" and record.tripId or nil
    if summary and (tonumber(summary.pending) or 1) == 0 and trip ~= nil
        and not state.deliveredTrips[trip] then
        if state.deliveredCount >= 64 then state.deliveredTrips, state.deliveredCount = {}, 0 end
        state.deliveredTrips[trip] = true
        state.deliveredCount = state.deliveredCount + 1
        local spoken, why = Voice.cue(actor, "delivery.done")
        if spoken then return spoken, why end
    end
    return Voice.cue(actor, "delivery.stored")
end

function Voice.searchResult(actor, reason)
    if reason == "nothing_needed" then return Voice.cue(actor, "search.empty") end
    if reason == "approach_timeout" or reason == "no_interaction_targets" then
        return Voice.cue(actor, "search.blocked")
    end
    return false, "work_voice_no_event"
end

-- BaseLife reports claim, verified completion and a block. Production and
-- farm jobs already speak through their own work; medical jobs stay quiet.
function Voice.jobEvent(event, job, actorId)
    local group = type(job) == "table" and JOB_GROUPS[job.type] or nil
    if not group or actorId == nil then return false, "work_voice_no_event" end
    local utility = U()
    local actor = type(utility.resolveActor) == "function" and utility.resolveActor(actorId) or nil
    if not actor then return false, "work_voice_no_speaker" end
    if event == "start" then return Voice.cue(actor, "job.start", "voice.job.start." .. group) end
    if event == "done" then return Voice.cue(actor, "job.done", "voice.job.done." .. group) end
    if event == "blocked" then return Voice.cue(actor, "job.blocked", "voice.job.blocked") end
    return false, "work_voice_no_event"
end

-- ---------------------------------------------------------------------------
-- Crew banter: opener now, a reply a few seconds later, sometimes a close.
-- ---------------------------------------------------------------------------

local function callName(speaker, listener, salt)
    if SC.Names and type(SC.Names.callName) == "function" then
        local ok, name = pcall(SC.Names.callName, speaker, listener, { salt = salt })
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    local name = tostring(U().nameOf(listener) or "")
    return string.match(name, "^(%S+)") or "friend"
end

local function chooseBeat(context, actor, current)
    local beats = lines().BANTER and lines().BANTER[context]
    if type(beats) ~= "table" or #beats == 0 then return nil end
    local recent = state.recentBeats[context] or {}
    local fresh = {}
    for index = 1, #beats do
        local used = false
        for _, prior in ipairs(recent) do if prior == index then used = true break end end
        if not used then fresh[#fresh + 1] = index end
    end
    if #fresh == 0 then fresh = { 1 } end
    local index = fresh[pick(#fresh, actor, current, context)]
    recent[#recent + 1] = index
    while #recent > math.min(6, #beats - 1) do table.remove(recent, 1) end
    state.recentBeats[context] = recent
    return beats[index], index
end

local function pairReady(first, second, current)
    local utility = U()
    return utility.sameFloor(first, second)
        and (utility.distance(first, second) or math.huge) <= config("workBanterDistance", 10)
        and ready(first, current) and ready(second, current)
end

local function beginExchange(first, second, context, current)
    local beat = chooseBeat(context, first, current)
    if not beat then return false, "work_banter_no_beat" end
    local salt = context .. ":" .. tostring(current)
    local spoken = say(first, "voice.banter." .. context .. ".open", { common = { beat.open } },
        { callName(first, second, salt) }, salt)
    if not spoken then return false, "work_banter_speech_rejected" end
    local replyMs = config("workBanterReplyMs", 3000)
    state.exchange = { first = first, second = second, beat = beat, context = context,
        stage = "reply", nextAt = current + replyMs,
        expiresAt = current + replyMs + 9000,
        firstSpokenAt = lastSpokenAt(first), secondSpokenAt = lastSpokenAt(second) }
    state.partyNextAt = current + config("workVoicePartyGapMs", 6000) * chatter()
    return true, context
end

local function advanceExchange(current)
    local exchange = state.exchange
    if type(exchange) ~= "table" then return false, "work_banter_idle" end
    if current >= exchange.expiresAt then
        state.exchange = nil
        return false, "work_banter_expired"
    end
    if current < exchange.nextAt then return false, "work_banter_waiting" end
    local replying = exchange.stage == "reply"
    local speaker = replying and exchange.second or exchange.first
    local listener = replying and exchange.first or exchange.second
    local utility = U()
    -- Anything else either of them said since the opener ends the exchange.
    if not utility.isValidActor(speaker) or utility.isDead(speaker)
        or not utility.isValidActor(listener) or utility.isDead(listener)
        or lastSpokenAt(exchange.first) > exchange.firstSpokenAt
        or lastSpokenAt(exchange.second) > exchange.secondSpokenAt
        or not utility.sameFloor(speaker, listener)
        or (utility.distance(speaker, listener) or math.huge)
            > config("workBanterDistance", 10) + 2
        or not calm(snapshotFor(speaker)) then
        state.exchange = nil
        return false, "work_banter_interrupted"
    end
    local salt = exchange.context .. ":" .. exchange.stage .. ":" .. tostring(current)
    local topic = "voice.banter." .. exchange.context .. "." .. exchange.stage
    local source = replying and exchange.beat.reply or { exchange.beat.close }
    local spoken = say(speaker, topic, { common = source },
        { callName(speaker, listener, salt) }, salt)
    if not spoken then
        state.exchange = nil
        return false, "work_banter_speech_rejected"
    end
    if replying and exchange.beat.close ~= nil then
        local replyMs = config("workBanterReplyMs", 3000)
        exchange.stage = "close"
        exchange.nextAt = current + replyMs
        exchange.expiresAt = current + replyMs + 9000
        exchange.firstSpokenAt = lastSpokenAt(exchange.first)
        exchange.secondSpokenAt = lastSpokenAt(exchange.second)
        return true, topic
    end
    state.exchange = nil
    state.partyNextAt = current + config("workVoicePartyGapMs", 6000) * chatter()
    return true, topic
end

-- Try one pair from a list of actors in the same context.
local function tryBanter(actors, context, current)
    if #actors < 2 then return false, "work_banter_no_pair" end
    local start = pick(#actors, actors[1], current, context .. ":first")
    for offset = 0, #actors - 1 do
        local first = actors[(start + offset - 1) % #actors + 1]
        for _, second in ipairs(actors) do
            if second ~= first and pairReady(first, second, current) then
                return beginExchange(first, second, context, current)
            end
        end
    end
    return false, "work_banter_no_pair"
end

-- ---------------------------------------------------------------------------
-- Expedition pulse: phase changes become lines, quiet stretches become talk.
-- ---------------------------------------------------------------------------

local function livingCrew(mission)
    local result = {}
    for _, record in ipairs(mission.roster or {}) do
        local actor = record.actor
        if actor ~= nil and mission.members and mission.members[actor]
            and U().isValidActor(actor) and not U().isDead(actor) then
            result[#result + 1] = actor
        end
    end
    return result
end

local function passenger(mission, crew)
    local trip = mission.scout and mission.scout.vehicle
    for _, record in ipairs(mission.roster or {}) do
        if record.actor ~= nil and type(trip) == "table" and type(trip.seats) == "table"
            and trip.seats[record.id] ~= nil and trip.seats[record.id] ~= 0 then
            for _, actor in ipairs(crew) do if actor == record.actor then return actor end end
        end
    end
    return mission.leader and mission.leader.actor or crew[1]
end

local function returnClass(scout)
    local reason = scout.wood and (scout.wood.endReason or scout.wood.doneReason)
        or scout.search and scout.search.endReason or scout.endReason
    return RETURN_CLASSES[reason] or "generic"
end

local function contextFor(scout)
    local trip = scout.vehicle
    local vehicleState = type(trip) == "table" and trip.state or nil
    if DRIVING[vehicleState] then return "drive" end
    if scout.phase == "wood_working" then return "wood" end
    if scout.phase == "searching" then
        local request = scout.search and scout.search.request
        return type(request) == "table" and request.category == "fish" and "fishing" or "search"
    end
    if (scout.phase == "outbound" or scout.phase == "inbound")
        and (vehicleState == nil or vehicleState == "abandoned") then
        return "march"
    end
    return nil
end

function Voice.expeditionPulse(mission, current)
    if not enabled() then return false, "work_voice_disabled" end
    if type(mission) ~= "table" or mission.terminal or mission.restoring then
        return false, "work_voice_no_mission"
    end
    local scout = mission.scout
    if type(scout) ~= "table" then return false, "work_voice_no_itinerary" end
    current = tonumber(current) or U().nowMs()
    advanceExchange(current)
    local trip = type(scout.vehicle) == "table" and scout.vehicle or nil
    local vehicleState = trip and trip.state or nil
    local homeward = scout.phase == "inbound" or scout.phase == "awaiting_player"
        or trip ~= nil and trip.leg == "home"
    local memory = state.missions[mission]
    if not memory then
        -- First sight (a start or a reload) only records where things stand.
        state.missions[mission] = { phase = scout.phase, vehicleState = vehicleState,
            homeward = homeward, nearHome = homeward, context = contextFor(scout),
            banterAt = current + config("workBanterFirstDelayMs", 45000) }
        return false, "work_voice_observing"
    end
    -- This runs every tick; the crew list is built only when someone speaks.
    local leader = mission.leader and mission.leader.actor or nil
    local spoken, why = false, nil
    if vehicleState ~= memory.vehicleState then
        memory.vehicleState = vehicleState
        if DRIVING[vehicleState] then
            spoken, why = Voice.cue(passenger(mission, livingCrew(mission)),
                "expedition." .. DRIVING[vehicleState])
        elseif vehicleState == "parked_at_site" and not homeward then
            spoken, why = Voice.cue(leader, "expedition.park_site")
        end
    end
    if scout.phase ~= memory.phase then
        memory.phase = scout.phase
        if scout.phase == "wood_working" then
            spoken, why = Voice.cue(leader, "expedition.wood_arrive")
        end
    end
    if homeward and not memory.homeward then
        memory.homeward = true
        spoken, why = Voice.cue(leader, "expedition.turn_home",
            "voice.expedition.turn_home." .. returnClass(scout))
    end
    if scout.phase == "inbound" and not memory.nearHome and leader ~= nil
        and type(scout.returnPoint) == "table" then
        local x, y, z = U().position(leader)
        local point = scout.returnPoint
        if x ~= nil and math.floor(z or 0) == math.floor(point.z or 0)
            and (x - point.x) ^ 2 + (y - point.y) ^ 2 <= config("workVoiceNearHomeTiles", 40) ^ 2 then
            memory.nearHome = true
            spoken, why = Voice.cue(leader, "expedition.near_home")
        end
    end
    local context = contextFor(scout)
    if context ~= memory.context then
        memory.context = context
        memory.banterAt = math.max(memory.banterAt or -math.huge,
            current + config("workBanterSettleMs", 20000))
    end
    if spoken or not banterEnabled() or context == nil or state.exchange ~= nil
        or current < (memory.banterAt or -math.huge) then
        return spoken, why or "work_banter_waiting"
    end
    memory.banterAt = current + config("workBanterIntervalMs", 150000) * chatter()
    if not roll(config("workBanterChancePercent", 60), leader, current, "expedition_banter") then
        return false, "work_banter_roll"
    end
    return tryBanter(livingCrew(mission), context, current)
end

-- ---------------------------------------------------------------------------
-- Party pulse (runtime banter lane): replies, then camp and field talk.
-- ---------------------------------------------------------------------------

local function recruited(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, commands = pcall(SC.Commands.peek, actor)
        return ok and type(commands) == "table" and commands.recruited == true
    end
    return false
end

local function onCampJob(actor)
    local life = SC.BaseLife
    if not life or type(life.jobFor) ~= "function" then return false end
    local job = life.jobFor(tostring(U().idOf(actor) or ""))
    return type(job) == "table" and (job.state == "reserved" or job.state == "active")
        and type(life.isInside) == "function" and life.isInside(actor) == true
end

function Voice.update(player, records, current)
    if not enabled() then return false, "work_voice_disabled" end
    current = tonumber(current) or U().nowMs()
    local advanced, advanceReason = advanceExchange(current)
    if advanced or state.exchange ~= nil then return advanced, advanceReason end
    if not banterEnabled() then return false, "work_banter_disabled" end
    if state.campBanterNextAt == nil then
        state.campBanterNextAt = current + config("workBanterFirstDelayMs", 45000)
    end
    if current < state.campBanterNextAt then return false, "work_banter_waiting" end
    local field, camp = {}, {}
    local seenWindow = config("workBanterFieldSeenMs", 10000)
    for _, record in ipairs(type(records) == "table" and records or {}) do
        local actor = type(record) == "table" and record.actor or nil
        if actor ~= nil and recruited(actor) then
            if current - (state.fieldSeen[actor] or -math.huge) <= seenWindow then
                field[#field + 1] = actor
            elseif onCampJob(actor) then
                camp[#camp + 1] = actor
            end
        end
    end
    if #field < 2 and #camp < 2 then
        state.campBanterNextAt = current + config("workBanterRetryMs", 15000)
        return false, "work_banter_no_pair"
    end
    state.campBanterNextAt = current + config("workCampBanterIntervalMs", 210000) * chatter()
    if not roll(config("workCampBanterChancePercent", 50), field[1] or camp[1], current,
        "camp_banter") then return false, "work_banter_roll" end
    if #field >= 2 then
        local spoken, why = tryBanter(field, "field", current)
        if spoken then return spoken, why end
    end
    return tryBanter(camp, "camp_work", current)
end

function Voice.reset()
    state = freshState()
    return true
end

-- Test seams.
function Voice._stateForTests() return state end
function Voice._eventsForTests() return EVENTS, JOB_GROUPS, RETURN_CLASSES end
function Voice._registerForTests()
    registered = false
    return registerPools()
end

return Voice
