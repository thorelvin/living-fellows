-- SPDX-License-Identifier: MIT
--
-- Private companion diaries: the controller.
--
-- A minority of recruited companions are chosen once to keep a diary. They
-- receive a real book, collect a bounded inbox of verified experiences from
-- the owning subsystems, and occasionally turn one into a short first-person
-- entry during safe downtime. A page exists only after the supervised writing
-- action completes and the exact book in the author's inventory accepts the
-- append. The book carries its own pages; this controller keeps only what is
-- needed to write the next one (voice, inbox, anchors, receipts).
--
-- Knowledge discipline: every candidate is the writer's own perception or a
-- recorded knowledge path. Hidden Knox infection is never read; only the
-- apparent (felt) fever level, the writer's own visible wounds, and crisis
-- facts the writer took part in reach the text compiler.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end
if not SC.DiaryText and type(require) == "function" then pcall(require, "SCDiaryText") end
if not SC.DiaryCatalog and type(require) == "function" then pcall(require, "SCDiaryCatalog") end
if not SC.DiaryItem and type(require) == "function" then pcall(require, "SCDiaryItem") end

SC.Diary = SC.Diary or {}
local Diary = SC.Diary

Diary.VERSION = 1

local document
local runtime = {}
local contentRevision = 0
local pulseCursor = 0
local preparedPackets, catalogReported

local MONTHS = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

local PART_LABELS = {
    Hand_L = "left hand", Hand_R = "right hand",
    ForeArm_L = "left forearm", ForeArm_R = "right forearm",
    UpperArm_L = "left upper arm", UpperArm_R = "right upper arm",
    Torso_Upper = "chest", Torso_Lower = "stomach", Head = "head", Neck = "neck",
    Groin = "groin", UpperLeg_L = "left thigh", UpperLeg_R = "right thigh",
    LowerLeg_L = "left shin", LowerLeg_R = "right shin",
    Foot_L = "left foot", Foot_R = "right foot",
}
local LEG_PARTS = { Groin = true, UpperLeg_L = true, UpperLeg_R = true, LowerLeg_L = true,
    LowerLeg_R = true, Foot_L = true, Foot_R = true }

-- Wound letters, most severe first. A part's snapshot is a compact string of
-- these letters so the persisted body view stays small and shallow.
local WOUND_KINDS = {
    { letter = "b", fact = "wound.bite", importance = 95 },
    { letter = "p", fact = "wound.bullet", importance = 75 },
    { letter = "f", fact = "wound.fracture", importance = 70 },
    { letter = "d", fact = "wound.deep", importance = 68 },
    { letter = "g", fact = "wound.glass", importance = 55 },
    { letter = "u", fact = "wound.burn", importance = 55 },
    { letter = "c", fact = "wound.laceration", importance = 50 },
    { letter = "s", fact = "wound.scratch", importance = 42 },
}

local SCENE_ANCHORS = {
    trust = "first_reason_to_stay", healed = "scratch_worry",
    symptoms = "scratch_worry", bite = "bite_secret",
}
local CALLBACK_DUE_HOURS = { trust = 48, healed = 72 }
local TIER_RANK = { cautious = 1, ally = 2, trusted = 3, close = 4, family = 5 }

local function U() return SC.GameplayUtil end
local function Text() return SC.DiaryText end
local function DiaryItem() return SC.DiaryItem end

local function finite(value, fallback)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

local function cfg(key, fallback)
    local utility = U()
    local value = utility and utility.config(key)
    if value == nil then return fallback end
    return value
end

local function report(message, detail, id)
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        pcall(SC.Diagnostics.report, "diary", id, message, detail)
    end
end

local function emptyDocument()
    return { version = Diary.VERSION, writers = {} }
end

local function ensure()
    if type(document) ~= "table" then document = emptyDocument() end
    return document
end

local function bumpContentRevision()
    contentRevision = contentRevision + 1
    if contentRevision >= 9007199254740000 then contentRevision = 1 end
    return contentRevision
end

-- Scheduled persistence binds item-content capture to this revision: a page
-- committed after the diary controller was staged forces a fresh capture.
function Diary.contentRevision()
    return contentRevision
end

------------------------------------------------------------------ clock

-- Calendar and world age come from the native game clock only. Without a valid
-- clock there is no honest date line, so nothing is written.
function Diary.clock()
    if type(getGameTime) ~= "function" then return nil end
    local ok, gameTime = pcall(getGameTime)
    if not ok or gameTime == nil then return nil end
    local utility = U()
    local hours = finite(select(1, utility.call(gameTime, "getWorldAgeHours")), nil)
    local year = finite(select(1, utility.call(gameTime, "getYear")), nil)
    local month = finite(select(1, utility.call(gameTime, "getMonth")), nil)
    local day = finite(select(1, utility.call(gameTime, "getDay")), nil)
    local hour = finite(select(1, utility.call(gameTime, "getHour")), nil)
    if hours == nil or hours < 0 or year == nil or month == nil or day == nil or hour == nil
        or month < 0 or month > 11 or day < 0 or day > 30 or hour < 0 or hour > 23 then
        return nil
    end
    month, day, year = math.floor(month), math.floor(day), math.floor(year)
    return {
        hours = hours, hour = math.floor(hour),
        dayKey = year * 10000 + (month + 1) * 100 + day + 1,
        label = tostring(day + 1) .. " " .. MONTHS[month + 1] .. " " .. tostring(year),
    }
end

---------------------------------------------------------------- identity

local function firstName(name)
    local value = type(name) == "string" and string.match(name, "^%s*(%S+)") or nil
    if value and SC.DiaryText.validToken(value) then return value end
    return nil
end

local function identity(character)
    local utility = U()
    local name = utility.nameOf(character)
    local result = { name = name, first = firstName(name) }
    local descriptor, ok = utility.call(character, "getDescriptor")
    if ok and descriptor ~= nil then
        local female, known = utility.call(descriptor, "isFemale")
        if known then result.sex = female == true and "she" or "he" end
    end
    return result
end

local function commandsState(actor)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, actor)
        if ok and type(state) == "table" then return state end
    end
    return nil
end

local function isRecruited(actor)
    local state = commandsState(actor)
    return state ~= nil and state.recruited == true and state.factionId == nil
end

local function aliveActor(actor)
    return actor ~= nil and U().isValidActor(actor) and not U().isDead(actor)
end

local function illiterate(actor)
    if type(CharacterTrait) ~= "table" or CharacterTrait.ILLITERATE == nil then return false end
    local value, ok = U().call(actor, "hasTrait", CharacterTrait.ILLITERATE)
    return ok and value == true
end

local function assess(actor)
    if not SC.Medical or type(SC.Medical.assess) ~= "function" then return nil end
    local ok, value = pcall(SC.Medical.assess, actor)
    return ok and type(value) == "table" and value or nil
end

------------------------------------------------------------------ catalog

local function packets()
    if preparedPackets then return preparedPackets end
    local catalog = SC.DiaryCatalog
    if type(catalog) ~= "table" or type(catalog.packets) ~= "table" then return {} end
    local valid, problems = Text().prepareCatalog(catalog.packets, catalog.VOICES)
    if not catalogReported then
        catalogReported = true
        for _, problem in ipairs(problems) do report("diary passage disabled", problem) end
    end
    preparedPackets = valid
    return valid
end

------------------------------------------------------------------ writers

local function writerCount()
    local count = 0
    for _ in pairs(ensure().writers) do count = count + 1 end
    return count
end

local function pruneWriters()
    local limit = math.max(1, math.floor(finite(cfg("diaryMaxWriters", 64), 64)))
    while writerCount() >= limit do
        local oldestId, oldestHours
        for id, writer in pairs(ensure().writers) do
            if writer.status ~= "active" or writer.diarist ~= true then
                local hours = finite(writer.decidedHours, 0)
                if oldestHours == nil or hours < oldestHours
                    or (hours == oldestHours and id < oldestId) then
                    oldestId, oldestHours = id, hours
                end
            end
        end
        if not oldestId then return false end
        ensure().writers[oldestId] = nil
        runtime[oldestId] = nil
    end
    return true
end

local function chooseVoice(id, state)
    local catalog = SC.DiaryCatalog
    local profile = type(state) == "table" and type(state.personalityProfile) == "table"
        and state.personalityProfile or {}
    local weights = catalog.voiceWeightsFor(profile.archetype or state and state.personality)
    local rows, total = {}, 0
    for voice, weight in pairs(weights) do
        if catalog.VOICES[voice] and finite(weight, 0) > 0 then
            rows[#rows + 1] = { voice = voice, weight = math.floor(weight) }
            total = total + math.floor(weight)
        end
    end
    table.sort(rows, function(left, right) return left.voice < right.voice end)
    if total < 1 then return "guarded_practical" end
    local roll = Text().stableHash(id .. ":diary-voice:v1") % total
    for _, row in ipairs(rows) do
        if roll < row.weight then return row.voice end
        roll = roll - row.weight
    end
    return rows[1].voice
end

-- The diarist decision is made once per companion and saved. Loads, failed
-- spawns and later sandbox changes never reroll a decided companion.
local function decideWriter(actor, clock)
    if cfg("diaryEnabled", true) ~= true then return nil, "diaries_disabled" end
    local id = U().idOf(actor)
    if type(id) ~= "string" or id == "" then return nil, "companion_id_unavailable" end
    local existing = ensure().writers[id]
    if existing then return existing, "already_decided" end
    if not pruneWriters() then return nil, "writer_limit" end
    local state = commandsState(actor) or {}
    local who = identity(actor)
    local chance = math.max(0, math.min(100, finite(cfg("diaryWriterChancePercent", 35), 35)))
    local roll = Text().stableHash(id .. ":diarist:v1") % 100
    local diarist, reason = roll < chance, roll < chance and "selected" or "not_selected"
    if diarist and illiterate(actor) then diarist, reason = false, "illiterate" end
    local writer = {
        id = id, name = string.sub(tostring(who.name or "Survivor"), 1, 80),
        firstName = who.first, diarist = diarist, reason = reason,
        decidedHours = clock and clock.hours or 0, status = "active",
        seed = tostring(Text().stableHash(id .. ":diary-seed:v1")),
        voice = diarist and chooseVoice(id, state) or nil,
        diaryId = "diary:" .. id .. ":1", bookKey = id .. ":diary:1",
        bookCreated = false, bookAttempts = 0, bookRetryHours = 0, pencilGiven = false,
        entrySeq = 0, entryCount = 0, lastWrittenHours = 0, lastWrittenDay = 0,
        nextWriteHours = clock and clock.hours or 0,
        candidates = {}, anchors = {}, recent = {}, receipts = {},
        trustQueued = false,
    }
    ensure().writers[id] = writer
    return writer, reason
end

local function activeDiarist(writer)
    return type(writer) == "table" and writer.diarist == true and writer.status == "active"
end

function Diary.writerFor(actorOrId)
    local id = type(actorOrId) == "string" and actorOrId or (actorOrId and U().idOf(actorOrId))
    return id and ensure().writers[id] or nil
end

--------------------------------------------------------------------- book

local function transientFor(id)
    local value = runtime[id]
    if value == nil then
        value = {}
        runtime[id] = value
    end
    return value
end

local function bookPayload(item, writer)
    if item == nil then return nil end
    local payload = DiaryItem().read(item)
    if not payload or payload.diaryId ~= writer.diaryId then return nil end
    return payload
end

-- The exact book, found without ever scanning a whole inventory in one go.
-- A previously found book is re-validated cheaply; otherwise a bounded,
-- resumable search continues where the last one stopped, so a book behind a
-- large bag is located over a few passes instead of never.
-- Returns item, payload, status ("found", "pending" or "absent").
local function findBook(actor, writer)
    local personal = SC.PersonalItems
    if type(personal) ~= "table" then return nil, nil, "absent" end
    local transient = transientFor(writer.id)
    local cached = transient.book
    if cached ~= nil and personal.ownedBy(cached, actor) == true then
        local payload = bookPayload(cached, writer)
        if payload then return cached, payload, "found" end
    end
    transient.book = nil
    if type(personal.searchResumable) ~= "function" then
        local item = personal.find(actor, writer.bookKey)
        local payload = bookPayload(item, writer)
        if payload then transient.book = item end
        return payload and item or nil, payload, payload and "found" or "absent"
    end
    local item, cursor, status = personal.searchResumable(actor, function(candidate)
        local record = personal.personalRecord(candidate)
        return record ~= nil and record.key == writer.bookKey
    end, transient.bookCursor)
    transient.bookCursor = cursor
    if status ~= "found" then return nil, nil, status end
    local payload = bookPayload(item, writer)
    if not payload then return nil, nil, "absent" end
    transient.book = item
    return item, payload, "found"
end

local function giveWritingImplement(actor, writer)
    if writer.pencilGiven == true then return true end
    local existing, _, status = DiaryItem().findWritingImplement(actor)
    -- Only a completed search proves they have nothing to write with.
    if existing ~= nil or status == "pending" then
        writer.pencilGiven = existing ~= nil
        return existing ~= nil
    end
    writer.pencilGiven = true
    local pencil = U().addItem(U().inventory(actor), "Base.Pencil")
    if not pencil then return false end
    local marked = SC.PersonalItems.restoreMarker(pencil, {
        ownerId = writer.id, key = writer.id .. ":diary:pencil", kind = "writing_implement",
    }, false)
    if not marked then
        U().call(U().inventory(actor), "Remove", pencil)
        return false
    end
    return true
end

-- Optional equipment. A failure never harms a healthy companion, and once a
-- book has been created it is never recreated: a search that cannot find it
-- proves nothing about where it went.
local function ensureBook(actor, writer, clock)
    if not activeDiarist(writer) or writer.bookCreated == true then return true end
    if not SC.PersonalItems or type(SC.PersonalItems.restoreMarker) ~= "function" then
        return false, "personal_items_unavailable"
    end
    local existing, _, bookStatus = findBook(actor, writer)
    if existing then
        writer.bookCreated = true
        giveWritingImplement(actor, writer)
        return true
    end
    -- An unfinished search is not proof that there is no book yet. Creating
    -- one now could hand the same companion a second diary.
    if bookStatus == "pending" then return false, "book_search_incomplete" end
    local maximum = math.floor(finite(cfg("diaryBookCreateMaxAttempts", 3), 3))
    if writer.bookAttempts >= maximum or (clock and clock.hours < finite(writer.bookRetryHours, 0)) then
        return false, "book_creation_deferred"
    end
    writer.bookAttempts = writer.bookAttempts + 1
    writer.bookRetryHours = (clock and clock.hours or 0) + 1
    local inventory = U().inventory(actor)
    local item, reason = U().addItem(inventory, DiaryItem().ITEM_TYPE)
    if not item then return false, "book_create_failed:" .. tostring(reason) end
    local function discard(failure)
        U().call(inventory, "Remove", item)
        return false, failure
    end
    local marked = SC.PersonalItems.restoreMarker(item, {
        ownerId = writer.id, key = writer.bookKey, kind = "diary",
    }, true)
    if not marked then return discard("book_marker_failed") end
    local initialized, detail = DiaryItem().initialize(item, {
        diaryId = writer.diaryId, authorId = writer.id, authorName = writer.name,
        authoredLocale = "EN",
    })
    if not initialized then return discard(detail) end
    writer.bookCreated = true
    giveWritingImplement(actor, writer)
    return true
end

-------------------------------------------------------------- candidates

local function receiptSeen(writer, key)
    for _, value in ipairs(writer.receipts) do
        if value == key then return true end
    end
    return false
end

local function addReceipt(writer, key)
    if receiptSeen(writer, key) then return end
    writer.receipts[#writer.receipts + 1] = key
    local limit = math.max(8, math.floor(finite(cfg("diaryReceiptLimit", 48), 48)))
    while #writer.receipts > limit do table.remove(writer.receipts, 1) end
end

local function candidateScore(candidate, clock)
    local age = clock and math.max(0, clock.hours - finite(candidate.occurredHours, clock.hours)) or 0
    return finite(candidate.importance, 0) - age * 0.4
end

local function cleanFacts(source)
    local facts, count = {}, 0
    for key, value in pairs(type(source) == "table" and source or {}) do
        if type(key) == "string" and #key <= 64 and value == true then
            facts[key] = true
            count = count + 1
            if count >= 24 then break end
        end
    end
    return facts
end

local function cleanTokens(source)
    local tokens, count = {}, 0
    for key, value in pairs(type(source) == "table" and source or {}) do
        if type(key) == "string" and string.match(key, "^[%w_]+$") and #key <= 32
            and Text().validToken(value) then
            tokens[key] = value
            count = count + 1
            if count >= 8 then break end
        end
    end
    return tokens
end

-- Admits one verified experience into a diarist's bounded inbox. Durable
-- source keys make a replayed or re-observed outcome a no-op.
local function admit(writer, specification, clock)
    if not activeDiarist(writer) or cfg("diaryEnabled", true) ~= true then
        return false, "not_an_active_diarist"
    end
    if clock == nil then return false, "game_clock_unavailable" end
    local key = type(specification.sourceKey) == "string" and specification.sourceKey or nil
    if not key or #key > 160 then return false, "invalid_source_key" end
    for _, candidate in ipairs(writer.candidates) do
        if candidate.sourceKey == key then
            -- Repeated low-value outcomes aggregate into one unwritten
            -- experience with a true running total, never ten entries.
            if specification.accumulate == true then
                candidate.tokens.count = math.min(9999, finite(candidate.tokens.count, 0)
                    + math.max(1, math.floor(finite(specification.count, 1))))
                return true, candidate
            end
            return false, "duplicate_source"
        end
    end
    if receiptSeen(writer, key) then return false, "duplicate_source" end
    if specification.accumulate == true then
        specification.tokens = type(specification.tokens) == "table" and specification.tokens or {}
        specification.tokens.count = math.max(1, math.floor(finite(specification.count, 1)))
    end
    local candidate = {
        sourceKey = key, scene = specification.scene,
        importance = math.max(0, math.min(100, finite(specification.importance, 40))),
        occurredHours = clock.hours, occurredDay = clock.dayKey,
        facts = cleanFacts(specification.facts), tokens = cleanTokens(specification.tokens),
        subjectId = type(specification.subjectId) == "string" and string.sub(specification.subjectId, 1, 80) or nil,
        partKey = type(specification.partKey) == "string" and string.sub(specification.partKey, 1, 32) or nil,
        supersedes = type(specification.supersedes) == "string" and specification.supersedes or nil,
        attempts = 0,
    }
    if type(candidate.scene) ~= "string" or #candidate.scene > 32 then return false, "invalid_scene" end
    if candidate.supersedes then
        for index = #writer.candidates, 1, -1 do
            if writer.candidates[index].supersedes == candidate.supersedes then
                table.remove(writer.candidates, index)
            end
        end
    end
    writer.candidates[#writer.candidates + 1] = candidate
    addReceipt(writer, key)
    local limit = math.max(1, math.floor(finite(cfg("diaryMaxCandidates", 8), 8)))
    while #writer.candidates > limit do
        local lowest, lowestScore = 1, nil
        for index, row in ipairs(writer.candidates) do
            local score = candidateScore(row, clock)
            if lowestScore == nil or score < lowestScore then lowest, lowestScore = index, score end
        end
        table.remove(writer.candidates, lowest)
    end
    return true, candidate
end

local function writerForActor(actor, clock)
    if actor == nil or not aliveActor(actor) or not isRecruited(actor) then return nil end
    local writer = decideWriter(actor, clock)
    return activeDiarist(writer) and writer or nil
end

local function guarded(label, callback, ...)
    local ok, first, second = pcall(callback, ...)
    if not ok then
        report("diary observer failed: " .. label, first)
        return false, "diary_observer_failed"
    end
    return first, second
end

---------------------------------------------------------------- observers

local function playerTokens(tokens, facts, player)
    if player == nil then return end
    local who = identity(player)
    tokens.player = who.first
    if who.sex then facts["player." .. who.sex] = true end
end

function Diary.noteRecruited(actor, player)
    return guarded("recruited", function()
        local clock = Diary.clock()
        if actor == nil or not aliveActor(actor) or not isRecruited(actor) then
            return false, "not_recruited"
        end
        local writer = decideWriter(actor, clock)
        if not activeDiarist(writer) then return false, "not_a_diarist" end
        ensureBook(actor, writer, clock)
        local facts, tokens = { ["recruitment.committed"] = true }, {}
        playerTokens(tokens, facts, player)
        if clock and writer.joinedHours == nil then writer.joinedHours = clock.hours end
        return admit(writer, {
            scene = "joined", importance = 70, facts = facts, tokens = tokens,
            sourceKey = "joined:" .. writer.id .. ":" .. tostring(clock and math.floor(clock.hours) or 0),
        }, clock)
    end)
end

-- One verified bandage. The helper and patient are live characters; either
-- may be the local player. Care entries aggregate to one per writer per day.
function Diary.noteBandage(helper, patient, player, woundName, options)
    return guarded("bandage", function()
        options = type(options) == "table" and options or {}
        local clock = Diary.clock()
        if clock == nil or helper == nil or patient == nil then return false, "invalid_bandage" end
        local part = PART_LABELS[tostring(woundName or "")]
        local helperIsPlayer = player ~= nil and helper == player
        local patientIsPlayer = player ~= nil and patient == player
        local admitted = false
        local patientWriter = not patientIsPlayer and writerForActor(patient, clock) or nil
        if patientWriter then
            local facts, tokens = {}, { part = part }
            local scene
            if helper == patient then
                scene = "care_self"
                facts["care.writer_bandaged_self"] = true
                if options.tornClothing == true then facts["care.used_torn_clothing"] = true end
            elseif helperIsPlayer then
                scene = "care_player"
                facts["care.player_bandaged_writer"] = true
                playerTokens(tokens, facts, player)
            else
                scene = "care_companion"
                facts["care.companion_bandaged_writer"] = true
                local who = identity(helper)
                tokens.subject = who.first
                if who.sex then facts["subject." .. who.sex] = true end
            end
            if options.bleeding == true then facts["care.wound_bleeding"] = true end
            admitted = admit(patientWriter, {
                scene = scene, importance = scene == "care_player" and 65
                    or scene == "care_companion" and 60 or 40,
                facts = facts, tokens = tokens,
                subjectId = not helperIsPlayer and helper ~= patient and U().idOf(helper) or nil,
                sourceKey = scene .. ":" .. patientWriter.id .. ":" .. tostring(clock.dayKey),
            }, clock) == true or admitted
        end
        local helperWriter = helper ~= patient and not helperIsPlayer
            and writerForActor(helper, clock) or nil
        if helperWriter then
            local facts, tokens = {}, { part = part }
            if patientIsPlayer then
                facts["care.writer_bandaged_player"] = true
                playerTokens(tokens, facts, player)
            else
                facts["care.writer_bandaged_companion"] = true
                local who = identity(patient)
                tokens.subject = who.first
                if who.sex then facts["subject." .. who.sex] = true end
            end
            admitted = admit(helperWriter, {
                scene = "care_other", importance = 55, facts = facts, tokens = tokens,
                subjectId = not patientIsPlayer and U().idOf(patient) or nil,
                sourceKey = "care_other:" .. helperWriter.id .. ":" .. tostring(clock.dayKey),
            }, clock) == true or admitted
        end
        return admitted
    end)
end

function Diary.noteSharedEscape(actor, player)
    return guarded("escape", function()
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        local facts, tokens = { ["danger.escape_with_player"] = true }, {}
        playerTokens(tokens, facts, player)
        return admit(writer, {
            scene = "escape", importance = 50, facts = facts, tokens = tokens,
            sourceKey = "escape:" .. writer.id .. ":" .. tostring(clock and clock.dayKey or 0),
        }, clock)
    end)
end

-- The author's confirmed native death. The book keeps exactly what was
-- already written: no final entry, no completed draft, no eulogy.
function Diary.noteAuthorDeath(recordOrId)
    return guarded("author_death", function()
        local id = type(recordOrId) == "table" and recordOrId.id or recordOrId
        local writer = type(id) == "string" and ensure().writers[id] or nil
        if not writer or writer.status ~= "active" then return false, "no_active_writer" end
        writer.status = "dead"
        writer.candidates = {}
        runtime[id] = nil
        return true
    end)
end

-- Another companion's death, for diarists whose grief proves they know.
function Diary.noteCompanionDeath(record)
    return guarded("companion_death", function()
        if type(record) ~= "table" or type(record.id) ~= "string" then return false, "invalid_record" end
        local clock = Diary.clock()
        local admitted = 0
        for _, actor in ipairs(U().registryLiving(false)) do
            local id = U().idOf(actor)
            local writer = id ~= record.id and ensure().writers[id] or nil
            if activeDiarist(writer) and aliveActor(actor) and isRecruited(actor)
                and SC.Community and type(SC.Community.peekMind) == "function" then
                local mind = SC.Community.peekMind(id)
                for _, grief in ipairs(type(mind) == "table" and mind.grief or {}) do
                    if grief.subjectId == record.id then
                        local facts = { ["death.known_to_writer"] = true }
                        if grief.witnessed == true then facts["death.witnessed"] = true end
                        local pair = type(SC.Community.relation) == "function"
                            and SC.Community.relation(id, record.id, false) or nil
                        if type(pair) == "table" and (finite(pair.familiarity, 0) >= 35
                            or finite(pair.trust, 0) >= 40) then
                            facts["death.subject_close"] = true
                        end
                        if grief.subjectGender == "female" then facts["subject.she"] = true
                        elseif grief.subjectGender == "male" then facts["subject.he"] = true end
                        if admit(writer, {
                            scene = "loss", importance = facts["death.subject_close"] and 90 or 75,
                            facts = facts, tokens = { subject = firstName(grief.subjectName) },
                            subjectId = record.id, sourceKey = "death:" .. record.id,
                        }, clock) then admitted = admitted + 1 end
                        break
                    end
                end
            end
        end
        return admitted > 0, admitted
    end)
end

-- A participant confirmed another person's bite through a recorded path.
function Diary.noteCrisisKnowledge(crisis, observerId, path, stance)
    return guarded("crisis_knowledge", function()
        if type(crisis) ~= "table" or type(observerId) ~= "string"
            or observerId == crisis.subjectId then return false, "not_applicable" end
        local writer = ensure().writers[observerId]
        if not activeDiarist(writer) then return false, "not_a_diarist" end
        local actor = U().resolveActor(observerId)
        if not actor or not aliveActor(actor) or not isRecruited(actor) then return false, "writer_unavailable" end
        local clock = Diary.clock()
        local facts = { ["crisis.other_bitten_known"] = true }
        if type(path) == "string" then facts["crisis.learned." .. path] = true end
        if type(stance) == "string" then facts["stance." .. stance] = true end
        local subject = firstName(crisis.subjectName)
        return admit(writer, {
            scene = "crisis_other", importance = 78, facts = facts, tokens = { subject = subject },
            subjectId = crisis.subjectId,
            sourceKey = "crisis:" .. tostring(crisis.id) .. ":known:" .. observerId,
        }, clock)
    end)
end

-- The group's decision about a bitten diarist. Only the subject writes here;
-- the others already have their own knowledge entry.
function Diary.noteCrisisOutcome(crisis, player)
    return guarded("crisis_outcome", function()
        if type(crisis) ~= "table" or type(crisis.outcome) ~= "string" then return false, "no_outcome" end
        local writer = ensure().writers[crisis.subjectId]
        if not activeDiarist(writer) then return false, "not_a_diarist" end
        local actor = U().resolveActor(crisis.subjectId)
        if not actor or not aliveActor(actor) then return false, "writer_unavailable" end
        local clock = Diary.clock()
        local facts, tokens = { ["crisis.outcome." .. crisis.outcome] = true,
            ["infection.bite_known"] = true }, {}
        playerTokens(tokens, facts, player)
        return admit(writer, {
            scene = "crisis_self", importance = 92, facts = facts, tokens = tokens,
            sourceKey = "crisis:" .. tostring(crisis.id) .. ":outcome",
        }, clock)
    end)
end

-------------------------------------------------- everyday life observers

local function actorById(id)
    if type(id) ~= "string" or id == "" then return nil end
    local actor = U().resolveActor(id)
    return actor
end

local function writerById(id, clock)
    local writer = type(id) == "string" and ensure().writers[id] or nil
    if not activeDiarist(writer) then return nil end
    local actor = actorById(id)
    if not actor or not aliveActor(actor) or not isRecruited(actor) then return nil end
    return writer, actor
end

local function subjectTokens(tokens, facts, character)
    if character == nil then return end
    local who = identity(character)
    tokens.subject = who.first
    if who.sex then facts["subject." .. who.sex] = true end
end

local function localPlayer()
    if type(getPlayer) ~= "function" then return nil end
    local ok, value = pcall(getPlayer)
    return ok and value or nil
end

local function participantsOf(row)
    local result = {}
    for _, id in ipairs(type(row.participants) == "table" and row.participants or {}) do
        if type(id) == "string" then result[#result + 1] = id end
    end
    return result
end

-- A non-draining observer of the flat life-event bus. It only admits facts
-- for diarists named in the event; SCCommunity remains the queue's owner.
function Diary.observeLifeEvent(row)
    return guarded("life_event", function()
        if type(row) ~= "table" or type(row.kind) ~= "string" then return false end
        local clock = Diary.clock()
        if clock == nil or cfg("diaryEnabled", true) ~= true then return false end
        local kind, source, target = row.kind, row.sourceId, row.targetId
        local day = tostring(clock.dayKey)
        local admitted = false
        local function offer(writer, specification)
            if admit(writer, specification, clock) == true then admitted = true end
        end
        if kind == "witnessed_injury" then
            local hurt = actorById(source)
            for _, id in ipairs(participantsOf(row)) do
                local writer = id ~= source and writerById(id, clock) or nil
                if writer and hurt then
                    local facts, tokens = { ["witness.saw_hurt"] = true }, {}
                    if finite(row.severity, 0) >= 20 then facts["witness.badly"] = true end
                    subjectTokens(tokens, facts, hurt)
                    offer(writer, { scene = "witnessed_hurt", importance = facts["witness.badly"] and 60 or 42,
                        facts = facts, tokens = tokens, subjectId = source,
                        sourceKey = "hurt:" .. writer.id .. ":" .. tostring(source) .. ":" .. day })
                end
            end
        elseif kind == "argument" or kind == "social_fight" then
            for _, pair in ipairs({ { source, target, true }, { target, source, false } }) do
                local writer = writerById(pair[1], clock)
                local other = actorById(pair[2])
                if writer and other then
                    local facts, tokens = {}, {}
                    if kind == "argument" then
                        facts[pair[3] and "conflict.started_argument" or "conflict.was_confronted"] = true
                    else
                        facts[pair[3] and "conflict.shoved_them" or "conflict.got_shoved"] = true
                        if row.injury == true then facts["conflict.someone_hurt"] = true end
                    end
                    subjectTokens(tokens, facts, other)
                    offer(writer, { scene = "conflict", importance = kind == "argument" and 50 or 68,
                        facts = facts, tokens = tokens, subjectId = pair[2],
                        supersedes = "conflict:" .. writer.id .. ":" .. day,
                        sourceKey = kind .. ":" .. writer.id .. ":" .. day })
                end
            end
        elseif kind == "breakdown_finished" then
            local writer = writerById(source, clock)
            if writer and row.completed ~= false and type(row.episode) == "string"
                and row.episode ~= "argument" and row.episode ~= "unknown" then
                offer(writer, { scene = "breakdown", importance = 55,
                    facts = { ["breakdown." .. row.episode] = true }, tokens = {},
                    sourceKey = "breakdown:" .. writer.id .. ":" .. day })
            end
        elseif kind == "joy_shared" then
            local lifter = actorById(source)
            for _, id in ipairs(participantsOf(row)) do
                local writer = writerById(id, clock)
                if writer then
                    local facts, tokens = {}, {}
                    if id == source then
                        facts["joy." .. tostring(row.response or "rallying")] = true
                    elseif lifter then
                        facts["joy.lifted_by_someone"] = true
                        subjectTokens(tokens, facts, lifter)
                    end
                    offer(writer, { scene = "joy", importance = 28, facts = facts, tokens = tokens,
                        sourceKey = "joy:" .. writer.id .. ":" .. day })
                end
            end
        elseif kind == "promise_broken" then
            for _, id in ipairs(participantsOf(row)) do
                local writer = writerById(id, clock)
                if writer then
                    local facts, tokens = { ["promise.supply_run_missed"] = true }, {}
                    playerTokens(tokens, facts, localPlayer())
                    offer(writer, { scene = "promise_broken", importance = 55, facts = facts,
                        tokens = tokens, sourceKey = "promise:" .. writer.id .. ":" .. day })
                end
            end
        end
        return admitted
    end)
end

local REVEALED_FIELDS = { "occupation", "history", "home", "value", "fear", "habit", "keepsake" }

-- A conversation that changed the relationship: praise accepted, a piece of
-- the past shared with the player, or encouragement that landed.
function Diary.noteConversation(actor, player, action, state)
    return guarded("conversation", function()
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer or type(state) ~= "table" then return false, "not_a_diarist" end
        local facts, tokens = {}, {}
        playerTokens(tokens, facts, player)
        if action == "praise" then
            facts["talk.praised"] = true
            for index = #(state.memories or {}), 1, -1 do
                local memory = state.memories[index]
                if type(memory) == "table" and memory.praised == true and type(memory.kind) == "string" then
                    facts["talk.praised_for." .. memory.kind] = true
                    break
                end
            end
        elseif action == "background" then
            local revealed = math.floor(finite(type(state.reveals) == "table" and state.reveals.background, 0))
            local field = REVEALED_FIELDS[revealed]
            if not field then return false, "nothing_revealed" end
            facts["talk.shared_past"] = true
            facts["talk.revealed." .. field] = true
        elseif action == "encourage" then
            facts["talk.encouraged"] = true
        else
            return false, "unsupported_conversation"
        end
        return admit(writer, { scene = "talk", importance = action == "background" and 42 or 36,
            facts = facts, tokens = tokens,
            sourceKey = "talk:" .. action .. ":" .. writer.id .. ":" .. tostring(clock.dayKey) }, clock)
    end)
end

-- Ambient engine-state observations are admitted as small private moments.
-- The caller has already proven the transition; the diary never reinterprets
-- native stress as relationship stress.
function Diary.noteInteriorState(actor, kind)
    return guarded("interior_state", function()
        local factsByKind = {
            dread = "interior.dread",
            panic = "interior.panic",
            nicotine = "interior.nicotine",
        }
        local fact = factsByKind[kind]
        if fact == nil then return false, "invalid_interior_state" end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        return admit(writer, {
            scene = "interior",
            importance = kind == "panic" and 28 or kind == "dread" and 20 or 16,
            facts = { [fact] = true }, tokens = {},
            sourceKey = "interior:" .. kind .. ":" .. writer.id .. ":"
                .. tostring(clock and clock.dayKey or 0),
        }, clock)
    end)
end

local DOWNTIME_SCENES = {
    study_corpse = { scene = "study", importance = 26 },
    pay_respects = { scene = "respects", importance = 36 },
    workout = { scene = "workout", importance = 14 },
    read = { scene = "reading", importance = 14 },
    wash_self = { scene = "washed", importance = 12 },
    repair = { scene = "repair", importance = 16 },
}

-- A completed, verified downtime activity (never a started or cancelled one).
function Diary.noteDowntime(actor, activity, extra)
    return guarded("downtime", function()
        if type(activity) ~= "table" then return false end
        local spec = DOWNTIME_SCENES[activity.kind]
        if not spec then return false, "not_diary_material" end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        extra = type(extra) == "table" and extra or {}
        local facts, tokens = {}, {}
        if activity.kind == "study_corpse" then
            local outfit = type(activity.fact) == "table" and activity.fact.outfit or nil
            if type(outfit) == "string" and string.match(outfit, "^[%w_]+$") then
                facts["study.outfit." .. outfit] = true
            end
        elseif activity.kind == "pay_respects" and type(extra.memento) == "string" then
            facts["respects.memento_seen"] = true
            tokens.memento = extra.memento
        elseif (activity.kind == "read" or activity.kind == "repair") and activity.item ~= nil then
            local name = U().itemName(activity.item)
            if Text().validToken(name) then tokens.item = name end
        end
        return admit(writer, { scene = spec.scene, importance = spec.importance, facts = facts,
            tokens = tokens, sourceKey = spec.scene .. ":" .. writer.id .. ":" .. tostring(clock.dayKey) }, clock)
    end)
end

local ZONE_PHRASES = {
    ["the woods"] = "in the woods", ["a farm"] = "on a farm", ["the road"] = "on the road",
    ["the middle of town"] = "in the middle of town", ["out in the open"] = "out in the open",
}

local function placePhrase(tale)
    local place = type(tale) == "table" and tale.place or nil
    if type(place) ~= "string" or place == "that building" then return nil end
    if tale.placeKind == "open" then return "out in the open" end
    return ZONE_PHRASES[place] or ("at " .. place)
end

-- A fight that became a tale: the real kill count, and whether it was close.
function Diary.noteTale(actor, tale)
    return guarded("tale", function()
        if type(tale) ~= "table" or type(tale.id) ~= "string" then return false end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        local kills = math.max(0, math.floor(finite(tale.kills, 0)))
        local facts = { ["fight.survived"] = true }
        if kills >= 4 then facts["fight.many_kills"] = true end
        if tale.closeCall == "grabbed" then facts["fight.grabbed"] = true end
        if tale.closeCall == "hurt" then facts["fight.hurt"] = true end
        if tale.playerThere == true then facts["fight.player_there"] = true end
        if tale.weapon == "bare hands" then facts["fight.bare_hands"] = true end
        local tokens = { kills = kills, place = placePhrase(tale),
            weapon = tale.weapon ~= "bare hands" and tale.weapon or nil }
        if tale.playerThere == true then playerTokens(tokens, facts, localPlayer()) end
        return admit(writer, { scene = "fight_story",
            importance = tale.closeCall == "grabbed" and 72 or 58, facts = facts, tokens = tokens,
            sourceKey = "tale:" .. tale.id }, clock)
    end)
end

-- The tale was told again, bigger. The real count stays on the page.
function Diary.noteTaleTold(actor, tale, told, telling, title)
    return guarded("tale_told", function()
        if type(tale) ~= "table" or type(tale.id) ~= "string" then return false end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        told = math.max(0, math.floor(finite(told, 0)))
        telling = math.max(1, math.floor(finite(telling, 1)))
        local kills = math.max(0, math.floor(finite(tale.kills, 0)))
        local facts = { ["tale.told"] = true }
        if told > kills then facts["tale.inflated"] = true end
        if telling == 1 then facts["tale.first_telling"] = true end
        if telling >= 5 then facts["tale.legend"] = true end
        return admit(writer, { scene = "tale_told", importance = 30, facts = facts,
            tokens = { told = told, kills = kills, title = title },
            supersedes = "told:" .. tale.id,
            sourceKey = "told:" .. tale.id .. ":" .. tostring(telling) }, clock)
    end)
end

-- The first time this companion walked into a notable kind of place.
function Diary.notePlace(actor, group, oldWorkplace)
    return guarded("place", function()
        if type(group) ~= "string" or not string.match(group, "^[%w_]+$") then return false end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        local facts = { ["place." .. group] = true }
        if oldWorkplace == true then facts["place.old_workplace"] = true end
        return admit(writer, { scene = "place", importance = oldWorkplace and 40 or 24,
            facts = facts, tokens = {}, sourceKey = "place:" .. writer.id .. ":" .. group }, clock)
    end)
end

-- Committed base production credited to this exact worker.
function Diary.noteWork(actor, kind, count)
    return guarded("work", function()
        if kind ~= "planks" and kind ~= "trees" and kind ~= "burned" and kind ~= "buried" then
            return false
        end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        local scene = (kind == "burned" or kind == "buried") and "burial" or "work"
        local facts = { [(scene == "burial" and "burial." or "work.") .. kind] = true }
        return admit(writer, { scene = scene, importance = scene == "burial" and 42 or 28,
            facts = facts, tokens = {}, accumulate = true, count = count,
            sourceKey = scene .. ":" .. kind .. ":" .. writer.id .. ":" .. tostring(clock.dayKey) }, clock)
    end)
end

-- A fallen companion laid in their own grave by this worker.
function Diary.noteFallenBurial(actor, fallenName)
    return guarded("fallen_burial", function()
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        local subject = firstName(fallenName)
        if not subject then return false, "unnamed" end
        return admit(writer, { scene = "burial", importance = 88,
            facts = { ["burial.friend"] = true }, tokens = { subject = subject },
            sourceKey = "fallen_burial:" .. writer.id .. ":" .. subject }, clock)
    end)
end

-- This diarist carried out a mercy decision on a bitten person.
function Diary.noteMercyKilling(actor, crisis)
    return guarded("mercy", function()
        if type(crisis) ~= "table" then return false end
        local clock = Diary.clock()
        local writer = writerForActor(actor, clock)
        if not writer then return false, "not_a_diarist" end
        return admit(writer, { scene = "mercy", importance = 97,
            facts = { ["mercy.performed"] = true }, tokens = { subject = firstName(crisis.subjectName) },
            subjectId = crisis.subjectId,
            sourceKey = "mercy:" .. tostring(crisis.id) .. ":" .. writer.id }, clock)
    end)
end

------------------------------------------------------- body observation

local function woundCode(wound)
    local letters = {}
    if wound.bitten then letters[#letters + 1] = "b" end
    if wound.bullet then letters[#letters + 1] = "p" end
    if wound.fractured then letters[#letters + 1] = "f" end
    if wound.deepWound then letters[#letters + 1] = "d" end
    if wound.glass then letters[#letters + 1] = "g" end
    if wound.burned then letters[#letters + 1] = "u" end
    if wound.cut then letters[#letters + 1] = "c" end
    if wound.scratched then letters[#letters + 1] = "s" end
    return table.concat(letters)
end

local function symptomTier(level)
    level = finite(level, 0)
    if level >= finite(cfg("diarySymptomsLateLevel", 75), 75) then return 3 end
    if level >= finite(cfg("diarySymptomsMidLevel", 45), 45) then return 2 end
    if level >= finite(cfg("diarySymptomsEarlyLevel", 20), 20) then return 1 end
    return 0
end

local function infectionKnowledge(writer, clock, facts)
    local body = writer.body or {}
    if body.knownBite == true then
        facts["infection.bite_known"] = true
    elseif clock and finite(body.scratchHours, -1) >= 0
        and clock.hours - body.scratchHours <= finite(cfg("diaryScratchMemoryHours", 96), 96) then
        facts["infection.scratch_known"] = true
    else
        facts["infection.cause_unknown"] = true
    end
end

-- Compares the writer's own visible body with the last saved snapshot. The
-- first look only records a baseline: old wounds are never written up as new.
local function observeBody(actor, writer, clock, player)
    local assessment = assess(actor)
    if not assessment or assessment.alive == false then return false end
    local parts, count = {}, 0
    for _, wound in ipairs(assessment.wounds or {}) do
        local code = woundCode(wound)
        if code ~= "" and type(wound.name) == "string" and count < 32 then
            parts[wound.name] = code
            count = count + 1
        end
    end
    local tier = symptomTier(assessment.infectionLevel)
    local previous = writer.body
    if type(previous) ~= "table" then
        writer.body = { parts = parts, tier = tier, episode = 1,
            knownBite = (assessment.bites or 0) > 0, scratchHours = -1 }
        return false
    end
    local fresh, freshCount, primary = {}, 0, nil
    for name, code in pairs(parts) do
        local before = previous.parts[name] or ""
        for _, kind in ipairs(WOUND_KINDS) do
            if string.find(code, kind.letter, 1, true) and not string.find(before, kind.letter, 1, true) then
                freshCount = freshCount + 1
                fresh[#fresh + 1] = { part = name, kind = kind }
            end
        end
    end
    table.sort(fresh, function(left, right)
        if left.kind.importance == right.kind.importance then return left.part < right.part end
        return left.kind.importance > right.kind.importance
    end)
    primary = fresh[1]
    writer.body.parts = parts
    for _, row in ipairs(fresh) do
        if row.kind.letter == "b" then writer.body.knownBite = true end
        if row.kind.letter == "s" or row.kind.letter == "c" then writer.body.scratchHours = clock.hours end
    end
    if primary then
        local facts = { [primary.kind.fact] = true }
        if freshCount > 1 then facts["wound.multiple"] = true end
        if LEG_PARTS[primary.part] then facts["wound.part_leg"] = true end
        local scene = primary.kind.letter == "b" and "bite" or "wound"
        local tokens = { part = PART_LABELS[primary.part] }
        playerTokens(tokens, facts, player)
        admit(writer, {
            scene = scene, importance = primary.kind.importance, facts = facts,
            tokens = tokens, partKey = primary.part,
            sourceKey = scene .. ":" .. writer.id .. ":" .. primary.part .. ":"
                .. primary.kind.letter .. ":" .. tostring(clock.dayKey),
        }, clock)
    end
    if tier == 0 and finite(previous.tier, 0) > 0 then
        writer.body.episode = finite(previous.episode, 1) + 1
    end
    if tier > finite(previous.tier, 0) then
        local facts = {}
        facts[tier == 3 and "symptoms.late" or tier == 2 and "symptoms.mid" or "symptoms.early"] = true
        infectionKnowledge(writer, clock, facts)
        local episode = tostring(writer.body.episode or 1)
        local tokens = {}
        playerTokens(tokens, facts, player)
        admit(writer, {
            scene = "symptoms", importance = tier == 3 and 94 or tier == 2 and 86 or 80,
            facts = facts, tokens = tokens, supersedes = "symptoms:" .. writer.id .. ":" .. episode,
            sourceKey = "symptoms:" .. writer.id .. ":" .. episode .. ":" .. tostring(tier),
        }, clock)
    end
    writer.body.tier = tier
    return true
end

local function observeRelationship(actor, writer, clock, player)
    local state = commandsState(actor)
    if not state or not SC.Relationship or type(SC.Relationship.tier) ~= "function" then return end
    local rank = TIER_RANK[SC.Relationship.tier(state)] or 1
    if rank >= TIER_RANK.trusted then
        if writer.trustedSinceHours == nil then writer.trustedSinceHours = clock.hours end
    elseif rank <= TIER_RANK.ally then
        -- Hysteresis: a brief dip inside the trusted band does not reset.
        writer.trustedSinceHours = nil
    end
    local anchor = writer.anchors.first_reason_to_stay
    local sustained = writer.trustedSinceHours ~= nil and clock.hours - writer.trustedSinceHours
        >= finite(cfg("diaryTrustSustainHours", 24), 24)
    if anchor and sustained and writer.trustQueued ~= true
        and clock.hours - finite(anchor.hours, clock.hours) >= CALLBACK_DUE_HOURS.trust then
        writer.trustQueued = true
        local facts, tokens = {}, {}
        playerTokens(tokens, facts, player)
        admit(writer, {
            scene = "trust", importance = 58, facts = facts, tokens = tokens,
            sourceKey = "trust:" .. tostring(anchor.entryId),
        }, clock)
    end
    local scratch = writer.anchors.scratch_worry
    local body = writer.body
    if scratch and writer.healedQueued ~= scratch.entryId and type(body) == "table"
        and finite(body.tier, 0) == 0 and body.knownBite ~= true
        and clock.hours - finite(scratch.hours, clock.hours) >= CALLBACK_DUE_HOURS.healed then
        local wounded = false
        for _ in pairs(body.parts or {}) do wounded = true break end
        if not wounded then
            writer.healedQueued = scratch.entryId
            admit(writer, {
                scene = "healed", importance = 30, facts = {}, tokens = {},
                sourceKey = "healed:" .. tostring(scratch.entryId),
            }, clock)
        end
    end
end

local MILESTONES = { { days = 100, fact = "milestone.hundred" }, { days = 30, fact = "milestone.month" },
    { days = 7, fact = "milestone.week" } }

-- Time itself: an anniversary of joining, or an ordinary quiet day when
-- nothing else has been written for a while. A quiet page is still true: its
-- passage is chosen from what the writer can see and feel at writing time.
local function observeTime(actor, writer, clock, player)
    if writer.joinedHours ~= nil then
        local days = math.floor((clock.hours - writer.joinedHours) / 24)
        for _, milestone in ipairs(MILESTONES) do
            if days >= milestone.days and finite(writer.milestoneDays, 0) < milestone.days then
                writer.milestoneDays = milestone.days
                local facts, tokens = { [milestone.fact] = true }, { days = milestone.days }
                playerTokens(tokens, facts, player)
                admit(writer, { scene = "milestone", importance = 40, facts = facts, tokens = tokens,
                    sourceKey = "milestone:" .. writer.id .. ":" .. tostring(milestone.days) }, clock)
                break
            end
        end
    end
    if #writer.candidates > 0 then return end
    local since = writer.entryCount > 0 and writer.lastWrittenHours or finite(writer.decidedHours, 0)
    if clock.hours - since < finite(cfg("diaryQuietAfterHours", 40), 40) then return end
    if Text().stableHash(writer.id .. ":quiet:" .. tostring(clock.dayKey)) % 100
        >= finite(cfg("diaryQuietChancePercent", 50), 50) then
        return
    end
    admit(writer, { scene = "quiet", importance = 8, facts = {}, tokens = {},
        sourceKey = "quiet:" .. writer.id .. ":" .. tostring(clock.dayKey) }, clock)
end

-- One recruited companion per pulse: decide once, provide the book, notice
-- new wounds and fever, and queue callbacks that became true.
function Diary.pulse(player, current)
    if cfg("diaryEnabled", true) ~= true then return false, "diaries_disabled" end
    local clock = Diary.clock()
    if clock == nil then return false, "game_clock_unavailable" end
    local actors = {}
    for _, actor in ipairs(U().registryLiving(false)) do
        if aliveActor(actor) and isRecruited(actor) then actors[#actors + 1] = actor end
    end
    if #actors == 0 then return false, "no_recruited_companions" end
    pulseCursor = (pulseCursor % #actors) + 1
    local actor = actors[pulseCursor]
    local writer = decideWriter(actor, clock)
    if not activeDiarist(writer) then return true, "not_a_diarist" end
    ensureBook(actor, writer, clock)
    observeBody(actor, writer, clock, player)
    observeRelationship(actor, writer, clock, player)
    observeTime(actor, writer, clock, player)
    local transient = transientFor(writer.id)
    if writer.bookCreated and clock.hours >= finite(transient.nameAuditHours, 0) then
        transient.nameAuditHours = clock.hours + 1
        local item, payload = findBook(actor, writer)
        if item then DiaryItem().applyName(item, payload) end
    end
    return true, writer.id
end

---------------------------------------------------------- writing context

local function anchorOnPage(payload, anchor)
    if type(anchor) ~= "table" or type(anchor.quote) ~= "string" then return nil end
    for index, entry in ipairs(payload.entries) do
        if string.find(entry, anchor.quote, 1, true) then return index end
    end
    return nil
end

local function climate()
    if type(getClimateManager) ~= "function" then return nil end
    local ok, manager = pcall(getClimateManager)
    return ok and manager or nil
end

-- What the writer can see and feel right now, at the moment of writing:
-- weather, season, hour, their own moodles, where they are, how many are with
-- them, and a loss still being grieved. Never anything they could not know.
local HOME_NAMES = {
    muldraugh = "Muldraugh", rosewood = "Rosewood", riverside = "Riverside",
    west_point = "West Point", louisville = "Louisville", brandenburg = "Brandenburg",
}

local function worldFacts(actor, writer, state, clock, evidence, tokens)
    local utility = U()
    local background = type(state.background) == "table" and state.background or {}
    if HOME_NAMES[background.home] then
        evidence["home_known"] = true
        tokens.home_name = HOME_NAMES[background.home]
    end
    local month = math.floor(clock.dayKey / 100) % 100
    if month >= 6 and month <= 8 then evidence["season.summer"] = true
    elseif month >= 9 and month <= 11 then evidence["season.autumn"] = true
    elseif month == 12 or month <= 2 then evidence["season.winter"] = true
    else evidence["season.spring"] = true end
    if clock.hour >= 5 and clock.hour < 11 then evidence["time.morning"] = true
    elseif clock.hour >= 17 and clock.hour < 20 then evidence["time.evening"] = true end
    local weather = climate()
    if weather then
        local rain = finite(select(1, utility.call(weather, "getPrecipitationIntensity")), 0)
        local snow = select(1, utility.call(weather, "getPrecipitationIsSnow")) == true
        local fog = finite(select(1, utility.call(weather, "getFogIntensity")), 0)
        local temperature = finite(select(1, utility.call(weather, "getTemperature")), nil)
        if rain > 0.15 then evidence[snow and "weather.snow" or "weather.rain"] = true end
        if fog > 0.5 then evidence["weather.fog"] = true end
        if rain <= 0.15 and fog <= 0.5 then evidence["weather.dry"] = true end
        if temperature ~= nil and temperature <= 3 then evidence["weather.cold"] = true end
        if temperature ~= nil and temperature >= 28 then evidence["weather.hot"] = true end
    end
    for moodle, fact in pairs({ HUNGRY = "writer.hungry", THIRST = "writer.thirsty",
        TIRED = "writer.tired", BORED = "writer.bored", UNHAPPY = "writer.unhappy",
        WET = "writer.wet", HAS_A_COLD = "writer.has_cold", DRUNK = "writer.drunk",
        PAIN = "writer.in_pain" }) do
        if finite(utility.moodleLevel(actor, moodle, 0), 0) >= 2 then evidence[fact] = true end
    end
    if SC.BaseLife and type(SC.BaseLife.active) == "function" and SC.BaseLife.active()
        and type(SC.BaseLife.isInside) == "function" then
        local ok, inside = pcall(SC.BaseLife.isInside, actor)
        if ok and inside == true then evidence["place.at_base"] = true end
    end
    local companions = 0
    for _, other in ipairs(utility.registryLiving(false)) do
        if other ~= actor and aliveActor(other) and isRecruited(other) then companions = companions + 1 end
    end
    if companions == 0 then evidence["group.just_us"] = true
    elseif companions >= 3 then evidence["group.crowd"] = true end
    if SC.Relationship and type(SC.Relationship.mood) == "function" then
        local mood = SC.Relationship.mood(state)
        if mood == "low" then evidence["writer.low"] = true end
        if mood == "hopeful" or mood == "loyal" then evidence["writer.hopeful"] = true end
    end
    if SC.Community and type(SC.Community.activeGrief) == "function" then
        local ok, grief = pcall(SC.Community.activeGrief, writer.id)
        local name = ok and type(grief) == "table" and firstName(grief.subjectName) or nil
        if name then
            evidence["grief.active"] = true
            if grief.stage == "recovering" then evidence["grief.recovering"] = true end
            tokens.grieved = name
        end
    end
    if writer.joinedHours ~= nil then
        local days = math.floor((clock.hours - writer.joinedHours) / 24)
        if days >= 2 then
            evidence["time.days_together"] = true
            tokens.days = days
        end
    end
    if writer.entryCount >= 20 then evidence["diary.well_used"] = true end
end

local function breachRecent(writerId, clock)
    if not SC.Community or type(SC.Community.peekMind) ~= "function" then return false end
    local mind = SC.Community.peekMind(writerId)
    local nowMs = clock.hours * 3600000
    for _, expectation in ipairs(type(mind) == "table" and mind.expectations or {}) do
        if expectation.status == "broken" and nowMs - finite(expectation.dueAt, 0) <= 72 * 3600000 then
            return true
        end
    end
    return false
end

local function buildContext(actor, writer, candidate, payload, clock, seq)
    local evidence, tokens = {}, {}
    for key in pairs(candidate.facts) do evidence[key] = true end
    for key, value in pairs(candidate.tokens) do tokens[key] = value end
    tokens.writer = writer.firstName
    -- Grammatical number is a fact too: never "1 trees".
    if tokens.count ~= nil then
        evidence[finite(tokens.count, 0) == 1 and "count.one" or "count.many"] = true
    end
    if candidate.occurredDay == clock.dayKey then evidence["time.same_day"] = true end
    if clock.hour >= 20 or clock.hour < 5 then evidence["time.night"] = true end
    local state = commandsState(actor) or {}
    if state.recruited == true then evidence["writer.still_with_player"] = true end
    if SC.Relationship and type(SC.Relationship.tier) == "function" then
        local rank = TIER_RANK[SC.Relationship.tier(state)] or 1
        if rank <= TIER_RANK.ally then evidence["relationship.guarded"] = true
        elseif rank == TIER_RANK.trusted then evidence["relationship.warming"] = true
        else evidence["relationship.close"] = true end
        local mood = type(SC.Relationship.mood) == "function" and SC.Relationship.mood(state) or nil
        if mood == "shaken" or mood == "uneasy" then evidence["writer.shaken"] = true end
    end
    if writer.trustedSinceHours ~= nil and clock.hours - writer.trustedSinceHours
        >= finite(cfg("diaryTrustSustainHours", 24), 24) then
        evidence["relationship.trusted_sustained"] = true
    end
    if breachRecent(writer.id, clock) then evidence["relationship.recent_major_breach"] = true end
    local background = type(state.background) == "table" and state.background or {}
    for _, field in ipairs({ "fear", "value", "habit", "home" }) do
        if type(background[field]) == "string" and string.match(background[field], "^[%w_]+$") then
            evidence["background." .. field .. "." .. background[field]] = true
        end
    end
    worldFacts(actor, writer, state, clock, evidence, tokens)
    local assessment = assess(actor)
    if assessment then
        local tier = symptomTier(assessment.infectionLevel)
        evidence[tier == 3 and "symptoms.late" or tier == 2 and "symptoms.mid"
            or tier == 1 and "symptoms.early" or "symptoms.none"] = true
        local woundedParts = {}
        for _, wound in ipairs(assessment.wounds or {}) do
            if woundCode(wound) ~= "" then woundedParts[wound.name] = wound end
        end
        local anyWound = false
        for _ in pairs(woundedParts) do anyWound = true break end
        if not anyWound then evidence["wound.all_healed"] = true end
        if candidate.partKey then
            local wound = woundedParts[candidate.partKey]
            if not wound then evidence["wound.healed"] = true
            elseif wound.bandaged == true then evidence["wound.dressed"] = true end
        end
        if (assessment.bites or 0) > 0 then evidence["wound.bite_present"] = true end
    end
    if candidate.scene == "healed" or candidate.scene == "symptoms" then
        -- Writing-time knowledge replaces the occurrence snapshot for these.
        evidence["infection.bite_known"] = nil
        evidence["infection.scratch_known"] = nil
        evidence["infection.cause_unknown"] = nil
        infectionKnowledge(writer, clock, evidence)
    end
    if candidate.scene == "bite" and SC.InfectionCrisis
        and type(SC.InfectionCrisis.peekForSubject) == "function" then
        local crisis = SC.InfectionCrisis.peekForSubject(writer.id)
        if type(crisis) == "table" then
            if crisis.confessed == true then evidence["bite.confessed"] = true
            elseif crisis.strategy == "self_exile" then evidence["bite.self_exile_planned"] = true
            elseif crisis.strategy == "conceal" and crisis.othersConfirmed ~= true then
                evidence["bite.hidden"] = true
            end
        end
    end
    for key, anchor in pairs(writer.anchors) do
        local page = anchorOnPage(payload, anchor)
        if page then
            evidence["anchor." .. key .. ".committed"] = true
            if page == 1 then evidence["anchor." .. key .. ".on_first_page"] = true end
            if string.find(anchor.quote, "better idea", 1, true) then
                evidence["anchor." .. key .. ".mentions_better_idea"] = true
            end
        end
    end
    local anchorKey = SCENE_ANCHORS[candidate.scene]
    local anchor = anchorKey and writer.anchors[anchorKey] or nil
    if anchor and evidence["anchor." .. anchorKey .. ".committed"] then
        tokens.earlier_quote = anchor.quote
        local due = CALLBACK_DUE_HOURS[candidate.scene]
        if due == nil or clock.hours - finite(anchor.hours, clock.hours) >= due then
            evidence["time.callback_due"] = true
        end
    end
    return {
        diaryId = writer.diaryId, entryId = writer.diaryId .. ":entry:" .. tostring(seq),
        sourceKey = candidate.sourceKey, voice = writer.voice, scene = candidate.scene,
        seed = writer.seed, evidence = evidence, tokens = tokens,
        maxBytes = Text().MAX_ENTRY_BYTES,
    }
end

local function writeEligible(writer, clock)
    if writer.lastWrittenDay == clock.dayKey then return false, "already_wrote_today" end
    if #writer.candidates == 0 then return false, "nothing_to_write" end
    if clock.hours >= finite(writer.nextWriteHours, 0) then return true end
    local top = 0
    for _, candidate in ipairs(writer.candidates) do
        top = math.max(top, finite(candidate.importance, 0))
    end
    if top >= finite(cfg("diaryMajorImportance", 85), 85) and clock.hours
        >= finite(writer.lastWrittenHours, 0) + finite(cfg("diaryMajorGapHours", 6), 6) then
        return true
    end
    return false, "not_due"
end

local function pruneStale(writer, clock)
    local maximumAge = finite(cfg("diaryCandidateMaxAgeHours", 120), 120)
    for index = #writer.candidates, 1, -1 do
        local candidate = writer.candidates[index]
        if clock.hours - finite(candidate.occurredHours, clock.hours) > maximumAge
            or finite(candidate.attempts, 0) >= 3 then
            table.remove(writer.candidates, index)
        end
    end
end

-- Offers a writing activity to SCDowntime when this diarist is due, safe
-- downtime has been granted, the exact book and a pen are carried, and a
-- truthful passage exists. Preparing a draft never commits anything.
function Diary.writeActivity(actor, current)
    local utility = U()
    if cfg("diaryEnabled", true) ~= true or actor == nil then return nil end
    local id = utility.idOf(actor)
    local writer = id and ensure().writers[id] or nil
    if not activeDiarist(writer) or writer.bookCreated ~= true then return nil end
    local transient = transientFor(id)
    current = finite(current, utility.nowMs())
    if current < finite(transient.nextCheckMs, 0) then return nil end
    transient.nextCheckMs = current + finite(cfg("diaryWriteCheckIntervalMs", 30000), 30000)
    local clock = Diary.clock()
    if clock == nil or not aliveActor(actor) or not isRecruited(actor) then return nil end
    if writer.entryCount >= DiaryItem().maxEntries() then return nil end
    pruneStale(writer, clock)
    if not writeEligible(writer, clock) then return nil end
    local item, payload = findBook(actor, writer)
    if not item then return nil end
    local pen, penCursor = DiaryItem().findWritingImplement(actor, transient.penCursor, transient.pen)
    transient.penCursor, transient.pen = penCursor, pen
    if not pen then return nil end
    if payload.entryCount >= DiaryItem().maxEntries() then return nil end
    local ordered = {}
    for _, candidate in ipairs(writer.candidates) do ordered[#ordered + 1] = candidate end
    table.sort(ordered, function(left, right)
        local leftScore, rightScore = candidateScore(left, clock), candidateScore(right, clock)
        if leftScore == rightScore then return left.sourceKey < right.sourceKey end
        return leftScore > rightScore
    end)
    local seq = math.max(writer.entrySeq, payload.entryCount) + 1
    for index = 1, math.min(3, #ordered) do
        local candidate = ordered[index]
        local context = buildContext(actor, writer, candidate, payload, clock, seq)
        local draft = Text().generate(context, writer.recent, packets())
        if draft then
            local plan = {
                writerId = writer.id, diaryId = writer.diaryId, entryId = draft.entryId,
                seq = seq, sourceKey = candidate.sourceKey, dayKey = clock.dayKey,
                dateLabel = clock.label, draft = draft, revision = payload.revision, item = item,
            }
            transient.plan = plan
            return {
                kind = "write_diary",
                score = finite(candidate.importance, 0) >= 85 and 48 or 36,
                item = item, diary = plan,
                durationMs = cfg("diaryWriteDurationMs", 6000),
                fact = { activity = "write_diary" },
            }
        end
        candidate.attempts = finite(candidate.attempts, 0) + 1
    end
    return nil
end

-- Commits a prepared page after the supervised action finished. Everything
-- is rechecked: the author, the calendar day, the candidate, and the exact
-- book's identity and revision. Controller state changes only after the book
-- verifiably holds the new entry.
function Diary.commitWrite(actor, plan)
    local id = actor and U().idOf(actor)
    local transient = id and runtime[id] or nil
    if type(plan) ~= "table" or not transient or transient.plan ~= plan then
        return false, "stale_diary_plan"
    end
    transient.plan = nil
    local writer = ensure().writers[plan.writerId]
    if not activeDiarist(writer) or writer.id ~= id then return false, "writer_inactive" end
    if not aliveActor(actor) or not isRecruited(actor) then return false, "author_unavailable" end
    local clock = Diary.clock()
    if clock == nil or clock.dayKey ~= plan.dayKey then return false, "calendar_day_changed" end
    local candidateIndex
    for index, candidate in ipairs(writer.candidates) do
        if candidate.sourceKey == plan.sourceKey then candidateIndex = index break end
    end
    if not candidateIndex then return false, "candidate_withdrawn" end
    local item, _, bookStatus = findBook(actor, writer)
    if item ~= plan.item then
        return false, bookStatus == "pending" and "book_not_located" or "book_not_carried"
    end
    local appended, payload, detail = DiaryItem().append(item, {
        diaryId = writer.diaryId, revision = plan.revision, entryId = plan.entryId,
        dateLabel = plan.dateLabel, text = plan.draft.text,
    })
    if not appended then return false, payload end
    table.remove(writer.candidates, candidateIndex)
    addReceipt(writer, plan.sourceKey)
    local recent = writer.recent
    recent[#recent + 1] = { variantId = plan.draft.variantId, ideaId = plan.draft.ideaId,
        shape = plan.draft.shape }
    while #recent > Text().HISTORY_WINDOW do table.remove(recent, 1) end
    if plan.draft.anchorKey then
        writer.anchors[plan.draft.anchorKey] = {
            entryId = plan.entryId, seq = plan.seq, quote = plan.draft.anchorQuote,
            hours = clock.hours, day = clock.dayKey,
        }
        local limit = math.max(1, math.floor(finite(cfg("diaryMaxAnchors", 6), 6)))
        local count, oldestKey, oldestHours = 0, nil, nil
        for key, anchor in pairs(writer.anchors) do
            count = count + 1
            if oldestHours == nil or anchor.hours < oldestHours then oldestKey, oldestHours = key, anchor.hours end
        end
        if count > limit and oldestKey then writer.anchors[oldestKey] = nil end
    end
    writer.entrySeq = math.max(writer.entrySeq, plan.seq)
    writer.entryCount = payload.entryCount
    writer.lastWrittenHours = clock.hours
    writer.lastWrittenDay = clock.dayKey
    local minimum = finite(cfg("diaryMinGapHours", 16), 16)
    local maximum = math.max(minimum, finite(cfg("diaryMaxGapHours", 60), 60))
    writer.nextWriteHours = clock.hours + minimum
        + Text().stableHash(plan.entryId .. ":gap") % (math.floor(maximum - minimum) + 1)
    DiaryItem().applyName(item, payload)
    bumpContentRevision()
    return true, detail or "appended"
end

-- Test seam: the exact evidence view a candidate would be written from.
function Diary._contextForTests(actor, sourceKey)
    local id = actor and U().idOf(actor)
    local writer = id and ensure().writers[id] or nil
    local clock = Diary.clock()
    if not writer or not clock then return nil end
    local item, payload = findBook(actor, writer)
    payload = payload or { entries = {}, entryCount = 0 }
    for _, candidate in ipairs(writer.candidates) do
        if candidate.sourceKey == sourceKey then
            return buildContext(actor, writer, candidate, payload, clock, writer.entrySeq + 1)
        end
    end
    return nil
end

function Diary.abandonWrite(actor, plan)
    local id = actor and U().idOf(actor)
    local transient = id and runtime[id] or nil
    if transient and (plan == nil or transient.plan == plan) then transient.plan = nil end
    return true
end

-- Reader support: whether the book's author is still alive, from saved
-- controller state only. Reading never needs this record to exist.
function Diary.authorAlive(authorId)
    local writer = type(authorId) == "string" and ensure().writers[authorId] or nil
    if not writer or writer.status ~= "active" then return false end
    local actor = U().resolveActor(authorId)
    return actor ~= nil and aliveActor(actor)
end

-------------------------------------------------------------- persistence

local function restoreFailure(path, detail)
    return false, "invalid diary state at " .. tostring(path) .. ": " .. tostring(detail)
end

local function isString(value, maximum, allowEmpty)
    return type(value) == "string" and (allowEmpty or value ~= "") and #value <= maximum
end

local function isNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function denseArray(value, maximum)
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
        count = count + 1
    end
    return count == #value and count <= maximum
end

local function validateCandidate(candidate, path)
    if type(candidate) ~= "table" then return restoreFailure(path, "expected candidate") end
    if not isString(candidate.sourceKey, 160) or not isString(candidate.scene, 32)
        or not isNumber(candidate.importance) or not isNumber(candidate.occurredHours)
        or not isNumber(candidate.occurredDay) or type(candidate.facts) ~= "table"
        or type(candidate.tokens) ~= "table" then
        return restoreFailure(path, "malformed candidate")
    end
    for key, value in pairs(candidate.facts) do
        if not isString(key, 64) or value ~= true then return restoreFailure(path .. ".facts", "malformed fact") end
    end
    for key, value in pairs(candidate.tokens) do
        if not isString(key, 32) or not Text().validToken(value) then
            return restoreFailure(path .. ".tokens", "malformed token")
        end
    end
    for _, field in ipairs({ "subjectId", "partKey", "supersedes" }) do
        if candidate[field] ~= nil and not isString(candidate[field], 160) then
            return restoreFailure(path .. "." .. field, "expected string")
        end
    end
    if candidate.attempts ~= nil and not isNumber(candidate.attempts) then
        return restoreFailure(path .. ".attempts", "expected number")
    end
    return true
end

local function validateWriter(writer, id, path)
    if type(writer) ~= "table" or writer.id ~= id then return restoreFailure(path, "writer id mismatch") end
    if type(writer.diarist) ~= "boolean" or not isString(writer.name, 80)
        or not isString(writer.status, 16) or not isString(writer.seed, 32)
        or not isString(writer.diaryId, 160) or not isString(writer.bookKey, 160) then
        return restoreFailure(path, "malformed writer header")
    end
    if writer.status ~= "active" and writer.status ~= "dead" then
        return restoreFailure(path .. ".status", "unknown status")
    end
    if writer.diarist and not (isString(writer.voice, 40) and SC.DiaryCatalog.VOICES[writer.voice]) then
        return restoreFailure(path .. ".voice", "unknown voice")
    end
    if writer.firstName ~= nil and not Text().validToken(writer.firstName) then
        return restoreFailure(path .. ".firstName", "invalid token")
    end
    for _, field in ipairs({ "decidedHours", "bookAttempts", "bookRetryHours", "entrySeq",
        "entryCount", "lastWrittenHours", "lastWrittenDay", "nextWriteHours" }) do
        if not isNumber(writer[field]) then return restoreFailure(path .. "." .. field, "expected number") end
    end
    for _, field in ipairs({ "trustedSinceHours", "joinedHours", "milestoneDays" }) do
        if writer[field] ~= nil and not isNumber(writer[field]) then
            return restoreFailure(path .. "." .. field, "expected number")
        end
    end
    if type(writer.bookCreated) ~= "boolean" or type(writer.pencilGiven) ~= "boolean"
        or type(writer.trustQueued) ~= "boolean" then
        return restoreFailure(path, "malformed writer flags")
    end
    if writer.healedQueued ~= nil and not isString(writer.healedQueued, 200) then
        return restoreFailure(path .. ".healedQueued", "expected string")
    end
    if not denseArray(writer.candidates, 16) then return restoreFailure(path .. ".candidates", "expected dense array") end
    for index, candidate in ipairs(writer.candidates) do
        local ok, reason = validateCandidate(candidate, path .. ".candidates[" .. index .. "]")
        if not ok then return false, reason end
    end
    if not denseArray(writer.recent, 16) then return restoreFailure(path .. ".recent", "expected dense array") end
    for _, row in ipairs(writer.recent) do
        if type(row) ~= "table" or not isString(row.variantId, 160) or not isString(row.ideaId, 100)
            or not isString(row.shape, 100) then
            return restoreFailure(path .. ".recent", "malformed history")
        end
    end
    if not denseArray(writer.receipts, 128) then return restoreFailure(path .. ".receipts", "expected dense array") end
    for _, value in ipairs(writer.receipts) do
        if not isString(value, 160) then return restoreFailure(path .. ".receipts", "expected string") end
    end
    if type(writer.anchors) ~= "table" then return restoreFailure(path .. ".anchors", "expected table") end
    for key, anchor in pairs(writer.anchors) do
        if not isString(key, 60) or type(anchor) ~= "table" or not isString(anchor.entryId, 200)
            or not isString(anchor.quote, 160) or not isNumber(anchor.seq)
            or not isNumber(anchor.hours) or not isNumber(anchor.day) then
            return restoreFailure(path .. ".anchors", "malformed anchor")
        end
    end
    if writer.body ~= nil then
        local body = writer.body
        if type(body) ~= "table" or type(body.parts) ~= "table" or not isNumber(body.tier)
            or not isNumber(body.episode) or type(body.knownBite) ~= "boolean"
            or not isNumber(body.scratchHours) then
            return restoreFailure(path .. ".body", "malformed body snapshot")
        end
        for name, code in pairs(body.parts) do
            if not isString(name, 40) or not isString(code, 8) or not string.match(code, "^[bpfdgucs]+$") then
                return restoreFailure(path .. ".body.parts", "malformed wound code")
            end
        end
    end
    return true
end

local function copyPlain(value, depth)
    if type(value) ~= "table" then return value end
    if depth > 8 then error("diary state is too deep") end
    local result = {}
    for key, child in pairs(value) do result[key] = copyPlain(child, depth + 1) end
    return result
end

function Diary.export()
    if SC.StableValue and type(SC.StableValue.copyStrict) == "function" then
        return SC.StableValue.copyStrict(ensure(), {
            maxDepth = 8, maxEntries = 16384, path = "$.diaries",
        })
    end
    return copyPlain(ensure(), 1)
end

-- Validates the complete candidate document before publishing any of it.
function Diary.restore(source)
    if source == nil then
        document = emptyDocument()
        runtime = {}
        return true
    end
    if type(source) ~= "table" then return restoreFailure("$.diaries", "expected table") end
    if source.version ~= Diary.VERSION then return restoreFailure("$.diaries.version", "unsupported version") end
    if type(source.writers) ~= "table" then return restoreFailure("$.diaries.writers", "expected table") end
    local count = 0
    for id, writer in pairs(source.writers) do
        if not isString(id, 80) then return restoreFailure("$.diaries.writers", "invalid writer id") end
        local ok, reason = validateWriter(writer, id, "$.diaries.writers[" .. id .. "]")
        if not ok then return false, reason end
        count = count + 1
        if count > 256 then return restoreFailure("$.diaries.writers", "too many writers") end
    end
    local ok, copied = pcall(copyPlain, source, 1)
    if not ok or type(copied) ~= "table" then return restoreFailure("$.diaries", tostring(copied)) end
    document = copied
    runtime = {}
    pulseCursor = 0
    return true
end

function Diary.reset()
    document = nil
    runtime = {}
    pulseCursor = 0
    preparedPackets, catalogReported = nil, nil
    return true
end

return Diary
