-- SPDX-License-Identifier: MIT
-- Private diaries: text compiler, physical book payload and controller
-- lifecycle, run inside the game's own Kahlua VM.

local SC = SurvivorCompanion
local Text, Catalog, Item, Diary = SC.DiaryText, SC.DiaryCatalog, SC.DiaryItem, SC.Diary
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "diary check " .. checks .. " failed: " .. tostring(message))
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function contains(haystack, needle)
    return type(haystack) == "string" and string.find(haystack, needle, 1, true) ~= nil
end

----------------------------------------------------------------- catalog

local ok, firstProblem, problems = Text.validateCatalog(Catalog.packets, Catalog.VOICES)
check(ok, "production catalog validates: " .. tostring(firstProblem))
local packetCount, variantCount, scenes = 0, 0, {}
for _, packet in ipairs(Catalog.packets) do
    packetCount = packetCount + 1
    variantCount = variantCount + #packet.variants
    scenes[packet.scene] = scenes[packet.scene] or {}
    for voice, weight in pairs(packet.voiceWeights) do
        if weight > 0 then scenes[packet.scene][voice] = true end
    end
    check(type(packet.asserts) == "string" and packet.asserts ~= "",
        "every packet documents what it asserts: " .. packet.id)
end
check(packetCount >= 60 and variantCount >= 120,
    "a substantial authored library: " .. packetCount .. "/" .. variantCount)
for scene, voices in pairs(scenes) do
    for voice in pairs(Catalog.VOICES) do
        check(voices[voice] == true, "scene " .. scene .. " has a passage for voice " .. voice)
    end
end
for _, scene in ipairs({ "wound", "bite", "symptoms", "crisis_self", "crisis_other" }) do
    check(scenes[scene] ~= nil, "wound and Knox family present: " .. scene)
end

----------------------------------------------------------- text compiler

local sample = {
    version = 7,
    {
        id = "care.sample", scene = "water_help", ideaId = "accepting_help", shape = "admission",
        voiceWeights = { guarded_practical = 8 },
        requires = { "water.given_to_writer" },
        variants = {
            { id = "a", requires = { "player.he" },
                text = "{player} gave me water. Keep wondering what he expects in return." },
            { id = "b", text = "Water from {player}. I needed it." },
        },
    },
    {
        id = "loss.sample", scene = "known_loss", ideaId = "loss", shape = "bare",
        voiceWeights = { guarded_practical = 8 },
        requires = { "death.known_to_writer" },
        variants = { { id = "a", text = "{subject} is dead." } },
    },
}
local function context(overrides)
    local value = {
        diaryId = "d1", entryId = "d1:entry:2", sourceKey = "care:water:1",
        voice = "guarded_practical", scene = "water_help", seed = "seed-1",
        evidence = { ["water.given_to_writer"] = true, ["player.he"] = true },
        tokens = { player = "Jonah" },
    }
    for key, entry in pairs(overrides or {}) do value[key] = entry end
    return value
end

local base = context()
local before = { context = clone(base), catalog = clone(sample) }
local draft = Text.generate(base, {}, sample)
check(draft and contains(draft.text, "Jonah"), "a truthful passage renders")
check(equal(Text.generate(context(), {}, sample), draft), "same inputs give the same draft")
check(equal(base, before.context) and equal(sample, before.catalog), "generation is pure")
local noGift = context({ evidence = { ["player.he"] = true } })
check(Text.generate(noGift, {}, sample) == nil, "no unproven gift")
check(Text.generate(context({ scene = "known_loss", evidence = {}, tokens = { subject = "Ruth" } }),
    {}, sample) == nil, "having a name does not imply knowing a death")
local neutral = Text.generate(context({ evidence = { ["water.given_to_writer"] = true } }), {}, sample)
check(neutral and neutral.variantId == "care.sample:b", "unknown pronouns choose the neutral variant")
check(Text.generate(context({ tokens = {} }), {}, sample) == nil, "missing names never leak placeholders")
check(Text.generate(context({ tokens = { player = "Jonah\nnew entry" } }), {}, sample) == nil,
    "control characters cannot forge a date line")
check(Text.generate(context({ tokens = { player = string.rep("x", 121) } }), {}, sample) == nil,
    "an oversize token is rejected rather than truncated")
local percent = Text.generate(context({ tokens = { player = "A%1 <b>" } }), {}, sample)
check(percent and contains(percent.text, "A%1 <b>"), "literal percent and markup stay plain text")
local unicode = Text.generate(context({ tokens = { player = "S\195\184ren" } }), {}, sample)
check(unicode and contains(unicode.text, "S\195\184ren"), "UTF-8 names survive unchanged")
check(Text.generate(context({ maxBytes = 4 }), {}, sample) == nil, "byte budget fails without truncation")
check(Text.generate(context({ voice = "unimplemented" }), {}, sample) == nil, "no arbitrary voice fallback")
local reversed = { version = 7, sample[2], sample[1] }
check(equal(Text.generate(context(), {}, reversed), draft), "catalog order does not change selection")
check(Text.generate(context(), { { ideaId = "accepting_help", variantId = "x", shape = "y" } }, sample) == nil,
    "the same meaning is suppressed even with different wording")
local broken = clone(sample)
broken[#broken + 1] = { id = "broken", scene = "water_help", ideaId = "x", shape = "y",
    voiceWeights = { guarded_practical = 8 }, variants = { { id = "a", text = "Unclosed {name" } } }
broken[#broken + 1] = { id = "falsequote", scene = "water_help", ideaId = "z", shape = "y",
    voiceWeights = { guarded_practical = 8 },
    variants = { { id = "a", text = "Real words.", anchorKey = "k", anchorQuote = "Never written." } } }
broken[#broken + 1] = clone(sample[1])
local valid, found = Text.prepareCatalog(broken, Catalog.VOICES)
check(#valid == 2 and #found == 3, "invalid passages are disabled and diagnosed, valid ones remain: "
    .. #valid .. "/" .. #found)
check(Text.generate(context(), {}, valid) ~= nil, "a disabled optional passage never breaks generation")

------------------------------------------------------------ book payload

local function newItem(fullType)
    local item = { __class = "InventoryItem", fullType = fullType, name = fullType, favorite = false }
    function item:getFullType() return self.fullType end
    function item:getType() return (string.gsub(self.fullType, "^[^%.]+%.", "")) end
    function item:getModData() self.data = self.data or {} return self.data end
    function item:hasModData() return self.data ~= nil end
    function item:setFavorite(value) self.favorite = value == true end
    function item:isFavorite() return self.favorite end
    function item:getName() return self.name end
    function item:setName(value) self.name = value end
    function item:setCustomName(value) self.customName = value end
    function item:getDisplayName() return self.name end
    return item
end

local function newInventory()
    local inventory = { items = {}, rejected = {} }
    function inventory:getItems() return self.items end
    function inventory:AddItem(itemType)
        if self.rejected[itemType] then return nil end
        local item = newItem(itemType)
        self.items[#self.items + 1] = item
        return item
    end
    function inventory:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then table.remove(self.items, index) return end
        end
    end
    function inventory:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    return inventory
end

local book = newItem(Item.ITEM_TYPE)
local header = { diaryId = "diary:test:1", authorId = "sc-test", authorName = "Mara Ellis" }
check(Item.initialize(book, header), "a new book receives its header")
check(book.name == "Mara Ellis's diary", "the book is named for its author")
local appended, payload = Item.append(book, { diaryId = header.diaryId, revision = 0,
    entryId = "diary:test:1:entry:1", dateLabel = "9 July 1993", text = "First words." })
check(appended and payload.entryCount == 1 and payload.revision == 1, "one entry appends")
local again, _, detail = Item.append(book, { diaryId = header.diaryId, revision = 0,
    entryId = "diary:test:1:entry:1", dateLabel = "9 July 1993", text = "First words." })
check(again and detail == "already_committed" and Item.read(book).entryCount == 1,
    "a retried commit never writes the same page twice")
check(not Item.append(book, { diaryId = header.diaryId, revision = 0,
    entryId = "diary:test:1:entry:2", dateLabel = "10 July 1993", text = "Stale." }),
    "a draft prepared against an old revision is refused")
check(not Item.append(book, { diaryId = "diary:other:1", revision = 1,
    entryId = "diary:other:1:entry:1", dateLabel = "10 July 1993", text = "Wrong book." }),
    "another diary's page cannot land in this book")
check(not Item.append(book, { diaryId = header.diaryId, revision = 1,
    entryId = "diary:test:1:entry:2", dateLabel = "10 July\n1993", text = "Forged." }),
    "a date line cannot contain a newline")
local date, passage = Item.parseEntry(Item.read(book).entries[1])
check(date == "9 July 1993" and passage == "First words.", "entries parse into date and passage")
local snapshot = clone(book.data)
Item.read(book)
Item.read(book)
check(equal(snapshot, book.data), "reading never mutates the book")
local corrupt = newItem(Item.ITEM_TYPE)
corrupt:getModData()[Item.KEY] = { schema = 1, diaryId = "x", authorId = "y", authorName = "Z",
    authoredLocale = "EN", volume = 1, revision = 2, entryCount = 3, entries = { "a\nb" } }
local corruptBefore = clone(corrupt.data)
check(Item.read(corrupt) == nil and not Item.append(corrupt, { diaryId = "x", revision = 2,
    entryId = "x:4", dateLabel = "1 July 1993", text = "More." }) and equal(corrupt.data, corruptBefore),
    "a malformed book is unreadable and left exactly as found")
local future = newItem(Item.ITEM_TYPE)
future:getModData()[Item.KEY] = { schema = 99, entries = {} }
check(Item.read(future) == nil and future.data[Item.KEY].schema == 99, "an unknown schema is preserved")
local full = newItem(Item.ITEM_TYPE)
Item.initialize(full, { diaryId = "diary:full:1", authorId = "sc-full", authorName = "Full" })
for index = 1, Item.maxEntries() do
    local done = Item.append(full, { diaryId = "diary:full:1", revision = index - 1,
        entryId = "diary:full:1:entry:" .. index, dateLabel = "9 July 1993", text = "Entry " .. index })
    check(done, "volume fills to its bound: " .. index)
end
local overflow, reason = Item.append(full, { diaryId = "diary:full:1", revision = Item.maxEntries(),
    entryId = "diary:full:1:entry:overflow", dateLabel = "9 July 1993", text = "One more." })
check(not overflow and reason == "diary_volume_full" and Item.read(full).entryCount == Item.maxEntries(),
    "a full volume keeps every page and accepts no silent overwrite")
for _, entry in ipairs(Item.read(full).entries) do
    check(#entry < 32767, "every stored string stays inside the 16-bit ModData string length")
end

-------------------------------------------------------- controller world

SC.Config.refreshSandbox({ LivingFellows = { DiaristChance = 100 } })

local square = { x = 1, y = 1, z = 0 }
local registryList, registryById = {}, {}
local states, minds, relations, crises = {}, {}, {}, {}

local function newActor(id, forename, surname, female)
    local actor = { __class = "IsoPlayer", id = id, square = square, x = 1, y = 1, z = 0,
        data = { SC_Id = id }, inventory = newInventory(), dead = false,
        wounds = {}, bites = 0, infection = 0, knox = false }
    actor.descriptor = {
        getForename = function() return actor.forename end,
        getSurname = function() return actor.surname end,
        isFemale = function() return female == true end,
    }
    actor.forename, actor.surname = forename, surname
    function actor:getModData() return self.data end
    function actor:getInventory() return self.inventory end
    function actor:isDead() return self.dead end
    function actor:getSquare() return self.square end
    function actor:getDescriptor() return self.descriptor end
    function actor:hasTrait() return self.illiterate == true end
    return actor
end

local function register(actor, state)
    registryList[#registryList + 1] = actor
    registryById[actor.id] = actor
    states[actor] = state
end

SC.Registry = {
    living = function() local result = {} for _, actor in ipairs(registryList) do result[#result + 1] = actor end return result end,
    byId = function(id) return registryById[id] end,
}
SC.Commands = { peek = function(actor) return states[actor] end }
SC.Relationship = {
    tier = function(state) return state.tier or "cautious" end,
    mood = function(state) return state.mood or "steady" end,
}
SC.Medical = {
    assess = function(actor)
        return { alive = not actor.dead, wounds = actor.wounds, woundCount = #actor.wounds,
            bites = actor.bites, infectionLevel = actor.infection, knoxInfected = actor.knox }
    end,
}
SC.Community = {
    peekMind = function(id) return minds[id] end,
    relation = function(first, second) return relations[first .. "|" .. second] end,
}
SC.InfectionCrisis = { peekForSubject = function(id) return crises[id] end }

local function setHours(hours) DIARY_TEST_HOURS = hours end
local function dayKey(hours)
    local year, month, day = DIARY_TEST_CALENDAR(hours)
    return year * 10000 + (month + 1) * 100 + day + 1
end
local function tryWrite(actor)
    SC_TEST_CLOCK = SC_TEST_CLOCK + 60000
    return Diary.writeActivity(actor, SC_TEST_CLOCK)
end
local function countType(actor, fullType)
    local count = 0
    for _, item in ipairs(actor.inventory.items) do
        if item.fullType == fullType then count = count + 1 end
    end
    return count
end
-- Move to the earliest hour this writer may write again (a new calendar day,
-- at or after its saved next-write hour), optionally at a given hour of day.
local function advanceToWritable(writer, hourOfDay)
    local target = math.max(DIARY_TEST_HOURS + 1, writer.nextWriteHours)
    while dayKey(target) == writer.lastWrittenDay do target = target + 1 end
    if hourOfDay then
        local _, _, _, hour = DIARY_TEST_CALENDAR(target)
        target = target + ((hourOfDay - hour) % 24)
    end
    setHours(target)
end

local player = newActor("player", "Jonah", "Reed", false)
local mara = newActor("sc-mara", "Mara", "Ellis", true)
local maraState = { recruited = true, tier = "cautious", mood = "steady",
    personalityProfile = { archetype = "practical" },
    background = { fear = "being_alone", value = "honesty", habit = "counts_supplies" } }
register(mara, maraState)

setHours(3)
local revisionBefore = Diary.contentRevision()
check(Diary.noteRecruited(mara, player), "recruitment admits a joining experience")
local writer = Diary.writerFor(mara)
check(writer and writer.diarist and writer.reason == "selected" and writer.bookCreated,
    "a selected companion becomes a diarist with a real book")
check(Catalog.VOICES[writer.voice] ~= nil, "the diarist has a persisted voice")
writer.voice = "guarded_practical"
check(countType(mara, Item.ITEM_TYPE) == 1 and countType(mara, "Base.Pencil") == 1,
    "the new diarist carries exactly one diary and a pencil")
local maraBook
for _, item in ipairs(mara.inventory.items) do
    if item.fullType == Item.ITEM_TYPE then maraBook = item end
end
local personal = SC.PersonalItems.personalRecord(maraBook)
check(personal and personal.kind == "diary" and personal.key == writer.bookKey and maraBook.favorite,
    "the book is a protected personal item under its own key")
check(SC.PersonalItems.isProtected(maraBook, "sc-other", "base_haul"),
    "automation may not haul the diary away")
check(Diary.noteRecruited(mara, player) == false, "a repeated recruitment signal is not a new page")

local first = tryWrite(mara)
check(first and first.kind == "write_diary" and first.item == maraBook, "a due diarist offers a writing activity")
check(Item.read(maraBook).entryCount == 0, "preparing a draft writes nothing")
check(Diary.contentRevision() == revisionBefore, "no content revision before a commit")
check(Diary.commitWrite(mara, first.diary), "the finished writing action commits the page")
check(Diary.contentRevision() == revisionBefore + 1, "a commit advances the save barrier revision")
local maraPayload = Item.read(maraBook)
check(maraPayload.entryCount == 1 and contains(maraPayload.entries[1], "9 July 1993\n"),
    "the page carries the game-calendar date line")
check(contains(maraPayload.entries[1], "Jonah"), "the page names the real player character")
check(#writer.candidates == 0 and writer.lastWrittenDay == dayKey(3), "the experience was consumed")
check(writer.anchors.first_reason_to_stay ~= nil
    and contains(maraPayload.entries[1], writer.anchors.first_reason_to_stay.quote),
    "the committed first page anchors its exact reason to stay")
check(not Diary.commitWrite(mara, first.diary), "a plan commits at most once")

-- A shared escape the same day stays queued: at most one entry per day.
maraState.mood = "shaken"
check(Diary.noteSharedEscape(mara, player), "a shared escape is admitted")
check(tryWrite(mara) == nil, "no second entry on the same calendar day")
maraState.mood = "steady"
writer.candidates = {}

----------------------------------------------------------- knowledge gates

-- The first look at a body is only a baseline: old wounds are not news.
mara.wounds = { { name = "Foot_R", scratched = true } }
Diary.pulse(player)
check(#writer.candidates == 0 and writer.body ~= nil, "existing wounds only set the baseline")
mara.wounds = {}
Diary.pulse(player)

-- Hidden Knox infection is never read.
mara.knox = true
mara.infection = 0
Diary.pulse(player)
check(#writer.candidates == 0, "native hidden infection never becomes diary knowledge")
mara.knox = false

-- A new scratch on the writer's own body.
setHours(DIARY_TEST_HOURS + 30)
mara.wounds = { { name = "Hand_L", scratched = true } }
Diary.pulse(player)
check(#writer.candidates == 1 and writer.candidates[1].scene == "wound"
    and writer.candidates[1].tokens.part == "left hand", "a new scratch is noticed with its body part")
Diary.pulse(player)
check(#writer.candidates == 1, "the same wound is not admitted twice")

-- Care attribution: only a verified helper is credited, aggregated per day.
check(Diary.noteBandage(player, mara, player, "Hand_L", { bleeding = false }),
    "a verified player bandage is admitted")
check(not Diary.noteBandage(player, mara, player, "Hand_L", {}), "repeat care the same day aggregates")
player.forename = "Nadia"
local careCandidate
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "care_player" then careCandidate = candidate end
end
check(careCandidate and careCandidate.tokens.player == "Jonah",
    "a later player character never inherits credit for Jonah's care")
player.forename = "Jonah"
local ruth = newActor("sc-ruth", "Ruth", "Park", true)
registryById[ruth.id] = ruth
check(Diary.noteBandage(ruth, ruth, player, "Hand_L", {}) == false, "a non-diarist's care writes nothing")

-- Symptoms: apparent fever only, with the cause the writer can know.
mara.infection = 25
Diary.pulse(player)
local symptom
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "symptoms" then symptom = candidate end
end
check(symptom and symptom.facts["symptoms.early"] and symptom.facts["infection.scratch_known"]
    and not symptom.facts["infection.bite_known"], "early fever after a scratch is known as a scratch worry, not a bite")
mara.infection = 50
Diary.pulse(player)
mara.infection = 80
Diary.pulse(player)
local symptomCount, lateSymptom = 0, nil
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "symptoms" then symptomCount, lateSymptom = symptomCount + 1, candidate end
end
check(symptomCount == 1 and lateSymptom.facts["symptoms.late"], "a worse fever supersedes older fever notes")
check(#writer.candidates <= 8, "the inbox stays bounded")

-- Death knowledge requires grief; crisis knowledge requires a recorded path.
check(not Diary.noteCompanionDeath({ id = "sc-ruth" }), "an unmourned death is not known")
check(not Diary.noteCrisisKnowledge({ id = "crisis:9", subjectId = "sc-mara", subjectName = "Mara Ellis" },
    "sc-mara", "confession", "protective"), "a bitten writer is not their own crisis witness")

-- Midnight: a draft prepared before midnight never commits after it.
writer.candidates = {}
mara.infection = 0
Diary.pulse(player)
mara.wounds = {}
Diary.noteSharedEscape(mara, player)
advanceToWritable(writer, 23)
local lateNight = tryWrite(mara)
check(lateNight ~= nil, "a late-night draft is prepared")
setHours(DIARY_TEST_HOURS + 2)
local committed, why = Diary.commitWrite(mara, lateNight.diary)
check(not committed and why == "calendar_day_changed" and Item.read(maraBook).entryCount == 1
    and #writer.candidates == 1, "crossing midnight rejects the stale draft and keeps the experience")

-- Interruption and a missing pen leave no page.
local interrupted = tryWrite(mara)
check(interrupted ~= nil, "a fresh draft is prepared after midnight")
Diary.abandonWrite(mara, interrupted.diary)
check(not Diary.commitWrite(mara, interrupted.diary) and Item.read(maraBook).entryCount == 1,
    "an interrupted writing action commits nothing")
local pencil
for _, item in ipairs(mara.inventory.items) do if item.fullType == "Base.Pencil" then pencil = item end end
mara.inventory:Remove(pencil)
check(tryWrite(mara) == nil, "no writing implement, no writing")
mara.inventory.items[#mara.inventory.items + 1] = pencil

-- The exact book: moved away, it is neither written remotely nor recreated.
local moved = tryWrite(mara)
check(moved ~= nil, "a draft is prepared with the book carried")
mara.inventory:Remove(maraBook)
check(not Diary.commitWrite(mara, moved.diary), "a book that left the author is not written remotely")
Diary.pulse(player)
check(countType(mara, Item.ITEM_TYPE) == 0 and writer.bookCreated, "a missing book is never recreated")
mara.inventory.items[#mara.inventory.items + 1] = maraBook
writer.candidates = {}

-- Illiteracy and a zero chance decide once and are never rerolled.
local reader = newActor("sc-lee", "Lee", "Ward", false)
reader.illiterate = true
register(reader, { recruited = true, personalityProfile = { archetype = "brave" } })
Diary.noteRecruited(reader, player)
check(not Diary.writerFor(reader).diarist and Diary.writerFor(reader).reason == "illiterate",
    "an illiterate companion does not keep a diary")
SC.Config.refreshSandbox({ LivingFellows = { DiaristChance = 0 } })
local skipped = newActor("sc-sam", "Sam", "Hill", false)
register(skipped, { recruited = true, personalityProfile = { archetype = "caring" } })
Diary.noteRecruited(skipped, player)
SC.Config.refreshSandbox({ LivingFellows = { DiaristChance = 100 } })
Diary.noteRecruited(skipped, player)
check(Diary.writerFor(skipped).diarist == false, "a decided companion is never rerolled")
check(countType(skipped, Item.ITEM_TYPE) == 0, "a non-diarist receives no book")
states[reader], states[skipped] = { recruited = false }, { recruited = false }

------------------------------------------------------------- persistence

local exported = Diary.export()
check(type(exported) == "table" and exported.writers["sc-mara"] ~= nil, "controller state exports")
check(Diary.restore(clone(exported)) == true and equal(Diary.export(), exported),
    "export and restore round trip exactly")
local badVoice = clone(exported)
badVoice.writers["sc-mara"].voice = "no_such_voice"
check(not Diary.restore(badVoice) and equal(Diary.export(), exported),
    "an unknown voice is rejected without publishing any of the document")
local sparse = clone(exported)
sparse.writers["sc-mara"].candidates = { [2] = clone(exported.writers["sc-mara"].candidates[1] or {}) }
check(not Diary.restore(sparse), "a sparse inbox is rejected")
local badWound = clone(exported)
badWound.writers["sc-mara"].body.parts = { Hand_L = "zz" }
check(not Diary.restore(badWound), "a malformed body snapshot is rejected")
check(Diary.restore(clone(exported)), "the valid document restores again")
writer = Diary.writerFor(mara)

--------------------------------------------------------- ten-entry arc

local report = { "Mara Ellis, guarded_practical voice (constructed harness arc)", "" }
local function writeNow(label, hourOfDay)
    advanceToWritable(writer, hourOfDay)
    local activity = tryWrite(mara)
    check(activity ~= nil, "arc entry is writable: " .. label)
    local done, failure = Diary.commitWrite(mara, activity.diary)
    check(done, "arc entry commits: " .. label .. " " .. tostring(failure))
    local stored = Item.read(maraBook)
    report[#report + 1] = "[" .. label .. " -> " .. activity.diary.draft.packetId .. "]"
    report[#report + 1] = stored.entries[stored.entryCount]
    report[#report + 1] = ""
    return activity.diary.draft
end
report[#report + 1] = "[joined]"
report[#report + 1] = Item.read(maraBook).entries[1]
report[#report + 1] = ""

-- 2. A scratch, noticed on her own body.
mara.wounds = { { name = "Hand_L", scratched = true } }
Diary.pulse(player)
local scratchDraft = writeNow("scratch")
check(not contains(scratchDraft.text, "bite") and not contains(scratchDraft.text, "Bitten"),
    "a scratch entry never claims a bite")

-- 3. Jonah dresses it.
mara.wounds[1].bandaged = true
Diary.noteBandage(player, mara, player, "Hand_L", {})
local careDraft = writeNow("player bandage")
check(contains(careDraft.text, "Jonah"), "care is credited to the historical helper")

-- 4. Out of danger together, at night, shaken.
maraState.mood = "shaken"
Diary.noteSharedEscape(mara, player)
writeNow("escape", 22)
maraState.mood = "steady"

-- 5. Relationship becomes trusted and holds; the first page is quoted.
maraState.tier = "trusted"
Diary.pulse(player)
setHours(DIARY_TEST_HOURS + 30)
mara.wounds = {}
Diary.pulse(player)
local trustCandidate
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "trust" then trustCandidate = candidate end
end
check(trustCandidate ~= nil, "a sustained trusted relationship queues the callback")
local keep = {}
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "trust" then keep[#keep + 1] = candidate end
end
writer.candidates = keep
minds["sc-mara"] = { expectations = { { status = "broken", dueAt = DIARY_TEST_HOURS * 3600000 } } }
advanceToWritable(writer)
check(tryWrite(mara) == nil, "a recent broken promise blocks the warm callback")
minds["sc-mara"] = nil
local trustDraft = writeNow("trust callback")
check(contains(trustDraft.text, writer.anchors.first_reason_to_stay.quote),
    "the callback quotes the line actually written on the earlier page")

-- 6. The scratch has healed with no fever; an earlier worry is revisited.
Diary.pulse(player)
for _, candidate in ipairs(writer.candidates) do
    if candidate.scene == "healed" then
        writeNow("healed callback")
        break
    end
end

-- 7. Ruth dies; Mara grieves, so she knows.
minds["sc-mara"] = { grief = { { subjectId = "sc-ruth", subjectName = "Ruth Park",
    subjectGender = "female", witnessed = false } } }
check(Diary.noteCompanionDeath({ id = "sc-ruth" }), "a mourned death is admitted")
local lossDraft = writeNow("loss")
check(contains(lossDraft.text, "Ruth"), "the loss names the person who died")
minds["sc-mara"] = nil

-- 8. A bite she has told no one about.
mara.wounds = { { name = "Hand_R", bitten = true, bleeding = true } }
mara.bites = 1
crises["sc-mara"] = { id = "crisis:1", strategy = "conceal", confessed = false, othersConfirmed = false }
Diary.pulse(player)
local biteDraft = writeNow("bite")
check(not contains(biteDraft.text, "I told them"), "a hidden bite is not written as confessed")

-- 9. The group decides to keep her apart.
crises["sc-mara"] = { id = "crisis:1", strategy = "conceal", confessed = true, othersConfirmed = true,
    outcome = "quarantine" }
check(Diary.noteCrisisOutcome({ id = "crisis:1", subjectId = "sc-mara", outcome = "quarantine" }, player),
    "the group's decision reaches the bitten diarist")
writeNow("quarantine")

-- 10. The fever, felt, near the end.
mara.infection = 50
Diary.pulse(player)
mara.infection = 82
Diary.pulse(player)
local lateDraft = writeNow("late fever")
check(lateDraft.packetId ~= nil and string.find(lateDraft.packetId, "symptoms.late", 1, true) == 1,
    "late fever with a known bite writes a late passage")

local arcPayload = Item.read(maraBook)
check(arcPayload.entryCount >= 9, "the arc filled the book: " .. arcPayload.entryCount)

-- Death: the book stops exactly where it is.
mara.dead = true
Diary.noteAuthorDeath({ id = "sc-mara" })
check(writer.status == "dead" and #writer.candidates == 0, "author death freezes the diary controller")
mara.dead = false
states[mara].recruited = true
check(tryWrite(mara) == nil, "no page is ever written for a dead author")
local finalPayload = clone(Item.read(maraBook))
Diary.reset()
check(Diary.writerFor("sc-mara") == nil and equal(Item.read(maraBook), finalPayload),
    "the recovered book reads the same with no author record at all")

------------------------------------------- everyday life: light and dark

-- Every scene renders in every voice from a minimal true evidence set, so no
-- voice is ever silently left with nothing to say about something real.
local sceneSamples = {
    joined = { "recruitment.committed" },
    wound = { "wound.scratch", "symptoms.none" },
    bite = { "wound.bite" },
    symptoms = { "symptoms.early", "infection.bite_known" },
    crisis_self = { "crisis.outcome.quarantine" },
    crisis_other = { "crisis.other_bitten_known", "stance.fearful" },
    loss = { "death.known_to_writer" },
    care_player = { "care.player_bandaged_writer", "relationship.guarded" },
    care_companion = { "care.companion_bandaged_writer" },
    care_self = { "care.writer_bandaged_self" },
    care_other = { "care.writer_bandaged_player" },
    escape = { "danger.escape_with_player" },
    witnessed_hurt = { "witness.saw_hurt" },
    conflict = { "conflict.started_argument" },
    breakdown = { "breakdown.vent" },
    joy = { "joy.rallying" },
    promise_broken = { "promise.supply_run_missed" },
    talk = { "talk.encouraged" },
    study = { "study.outfit.santa" },
    respects = {},
    workout = {},
    reading = {},
    washed = {},
    repair = {},
    fight_story = { "fight.many_kills" },
    tale_told = { "tale.told", "tale.inflated" },
    place = { "place.police" },
    work = { "work.planks", "count.many" },
    burial = { "burial.buried", "count.many" },
    mercy = { "mercy.performed" },
    milestone = { "milestone.week" },
    quiet = {},
}
local sampleTokens = { player = "Jonah", writer = "Tom", subject = "Ruth", part = "left hand",
    kills = 5, told = 9, title = "the Battle of the Gas Station", place = "at the gas station",
    weapon = "baseball bat", count = 6, days = 8, item = "hunting knife" }
local sampler = { "", "--- one passage per new scene, per voice ---" }
local voices = {}
for voice in pairs(Catalog.VOICES) do voices[#voices + 1] = voice end
table.sort(voices)
for _, scene in ipairs({ "witnessed_hurt", "conflict", "breakdown", "joy", "promise_broken", "talk",
    "study", "respects", "workout", "reading", "washed", "repair", "fight_story", "tale_told", "place",
    "work", "burial", "mercy", "milestone", "quiet", "joined", "wound", "bite", "symptoms",
    "crisis_self", "crisis_other", "loss", "care_player", "care_companion", "care_self",
    "care_other", "escape" }) do
    for _, voice in ipairs(voices) do
        local evidence = {}
        for _, key in ipairs(sceneSamples[scene]) do evidence[key] = true end
        local rendered = Text.generate({ diaryId = "sampler", entryId = "sampler:" .. scene,
            sourceKey = scene .. ":" .. voice, voice = voice, scene = scene, seed = "sampler",
            evidence = evidence, tokens = sampleTokens }, {}, Catalog.packets)
        check(rendered ~= nil, "scene " .. scene .. " renders for voice " .. voice)
        check(rendered and not string.find(rendered.text, "[{}]"), "no placeholder survives: " .. scene)
        if rendered and (voice == "blunt_brave" or voice == "warm_candid") and scene ~= "joined"
            and scene ~= "wound" and scene ~= "bite" and scene ~= "symptoms" and scene ~= "crisis_self"
            and scene ~= "crisis_other" and scene ~= "loss" and scene ~= "care_player"
            and scene ~= "care_companion" and scene ~= "care_self" and scene ~= "care_other"
            and scene ~= "escape" then
            sampler[#sampler + 1] = "[" .. scene .. " / " .. voice .. "] "
                .. string.gsub(rendered.text, "\n\n", " / ")
        end
    end
end
for _, group in ipairs({ "police", "prison", "church", "bar", "liquor", "whiskey", "brewery", "school",
    "library", "gunstore", "pharmacy", "hospital", "morgue", "dentist", "spiffos", "jays", "grocery",
    "gas", "garage", "firehouse", "army", "theatre", "bowling", "stripclub", "lab", "motel",
    "laundry", "gym", "music", "books", "zippee" }) do
    local rendered = Text.generate({ diaryId = "sampler", entryId = "sampler:place", sourceKey = group,
        voice = "wry_watchful", scene = "place", seed = "sampler",
        evidence = { ["place." .. group] = true }, tokens = sampleTokens }, {}, Catalog.packets)
    check(rendered ~= nil and rendered.packetId == "place." .. group,
        "every notable place the party remarks on has its own passage: " .. group)
end
for _, outfit in ipairs({ "santa", "wedding", "clergy", "party", "jockey", "hazmat", "military", "law",
    "medic", "inmate", "food", "sports", "office", "raider", "home", "patient", "fire", "reporter" }) do
    local packets = Text.prepareCatalog(Catalog.packets, Catalog.VOICES)
    local found = false
    for _, packet in ipairs(packets) do
        if packet.id == "study.outfits" then
            for _, variant in ipairs(packet.variants) do
                if variant.id == outfit then found = true end
            end
        end
    end
    check(found, "a studied corpse's outfit group has a passage: " .. outfit)
end

-- The hooks: a fresh world with one brave diarist.
Diary.reset()
states[mara].recruited = false
local climateState = { rain = 0.8, snow = false, fog = 0, temperature = 12 }
function getClimateManager()
    return {
        getPrecipitationIntensity = function() return climateState.rain end,
        getPrecipitationIsSnow = function() return climateState.snow end,
        getFogIntensity = function() return climateState.fog end,
        getTemperature = function() return climateState.temperature end,
    }
end
MoodleType = { HUNGRY = "HUNGRY", THIRST = "THIRST", TIRED = "TIRED", BORED = "BORED",
    UNHAPPY = "UNHAPPY", WET = "WET", HAS_A_COLD = "HAS_A_COLD", DRUNK = "DRUNK", PAIN = "PAIN" }
local tom = newActor("sc-tom", "Tom", "Hale", false)
tom.moodles = { HUNGRY = 2 }
function tom:getMoodles()
    local owner = self
    return { getMoodleLevel = function(_, moodle) return owner.moodles[moodle] or 0 end }
end
local tomState = { recruited = true, tier = "ally", mood = "steady",
    personalityProfile = { archetype = "brave" },
    background = { habit = "makes_tea", home = "rosewood", fear = "the_dark", value = "courage" } }
register(tom, tomState)
registryById[ruth.id] = ruth
setHours(DIARY_TEST_HOURS + 48)
check(Diary.noteRecruited(tom, player), "a second diarist joins")
local tomWriter = Diary.writerFor(tom)
tomWriter.candidates = {}
local function onlyCandidate(scene)
    for _, candidate in ipairs(tomWriter.candidates) do
        if candidate.scene == scene then return candidate end
    end
    return nil
end
local function resetInbox() tomWriter.candidates = {} tomWriter.receipts = {} end

Diary.observeLifeEvent({ kind = "witnessed_injury", sourceId = "sc-ruth",
    participants = { "sc-ruth", "sc-tom" }, severity = 25 })
local hurt = onlyCandidate("witnessed_hurt")
check(hurt and hurt.facts["witness.badly"] and hurt.tokens.subject == "Ruth",
    "a nearby diarist writes about watching someone get badly hurt")
Diary.observeLifeEvent({ kind = "witnessed_injury", sourceId = "sc-tom", participants = { "sc-tom" } })
check(#tomWriter.candidates == 1, "your own injury is not something you witnessed")
resetInbox()
Diary.observeLifeEvent({ kind = "argument", sourceId = "sc-tom", targetId = "sc-ruth",
    participants = { "sc-tom", "sc-ruth" } })
Diary.observeLifeEvent({ kind = "social_fight", sourceId = "sc-tom", targetId = "sc-ruth",
    participants = { "sc-tom", "sc-ruth" }, injury = true })
local conflict = onlyCandidate("conflict")
local conflictCount = 0
for _, candidate in ipairs(tomWriter.candidates) do
    if candidate.scene == "conflict" then conflictCount = conflictCount + 1 end
end
check(conflictCount == 1 and conflict.facts["conflict.shoved_them"] and conflict.facts["conflict.someone_hurt"],
    "a fight that follows an argument the same day replaces it with the worse truth")
resetInbox()
Diary.observeLifeEvent({ kind = "breakdown_finished", sourceId = "sc-tom", episode = "bottle_smash",
    completed = true, participants = { "sc-tom" } })
Diary.observeLifeEvent({ kind = "joy_shared", sourceId = "sc-ruth", participants = { "sc-ruth", "sc-tom" },
    response = "rallying" })
Diary.observeLifeEvent({ kind = "promise_broken", sourceId = "player:local", participants = { "sc-tom" } })
check(onlyCandidate("breakdown") and onlyCandidate("breakdown").facts["breakdown.bottle_smash"]
    and onlyCandidate("joy") and onlyCandidate("joy").tokens.subject == "Ruth"
    and onlyCandidate("promise_broken") ~= nil,
    "breakdowns, shared good moods and a broken promise are admitted for the diarist involved")
Diary.observeLifeEvent({ kind = "breakdown_finished", sourceId = "sc-tom", episode = "vent", completed = false })
resetInbox()
check(Diary.noteConversation(tom, player, "praise", { memories = { { kind = "rescued_player", praised = true } } })
    and onlyCandidate("talk").facts["talk.praised_for.rescued_player"], "praise records what it was for")
resetInbox()
check(Diary.noteConversation(tom, player, "background", { reveals = { background = 5 } })
    and onlyCandidate("talk").facts["talk.revealed.fear"], "sharing the past records which part was shared")
resetInbox()
check(Diary.noteDowntime(tom, { kind = "study_corpse", fact = { outfit = "santa" } })
    and onlyCandidate("study").facts["study.outfit.santa"], "a studied corpse keeps its outfit group")
check(Diary.noteDowntime(tom, { kind = "pay_respects" }, { memento = "locket" })
    and onlyCandidate("respects").tokens.memento == "locket", "a noticed keepsake is named, never taken")
check(Diary.noteDowntime(tom, { kind = "sit" }) == false, "ordinary sitting is not diary material")
resetInbox()
local tale = { id = "tale:harness", kills = 5, place = "the gas station", placeKind = "room",
    weapon = "baseball bat", playerThere = true }
check(Diary.noteTale(tom, tale) and onlyCandidate("fight_story").tokens.place == "at the gas station"
    and onlyCandidate("fight_story").tokens.kills == 5, "a fight worth telling keeps its real count and place")
Diary.noteTaleTold(tom, tale, 9, 2, "the Battle of the Gas Station")
Diary.noteTaleTold(tom, tale, 12, 3, "the Battle of the Gas Station")
local told, toldCount = nil, 0
for _, candidate in ipairs(tomWriter.candidates) do
    if candidate.scene == "tale_told" then told, toldCount = candidate, toldCount + 1 end
end
check(toldCount == 1 and told.tokens.told == 12 and told.tokens.kills == 5 and told.facts["tale.inflated"],
    "only the latest retelling waits to be written, with both the true and the told number")
resetInbox()
check(Diary.notePlace(tom, "police", false) and onlyCandidate("place").facts["place.police"],
    "a first visit to a notable place is admitted")
Diary.noteWork(tom, "planks", 3)
Diary.noteWork(tom, "planks", 2)
check(onlyCandidate("work").tokens.count == 5, "repeated sawing aggregates into one true running total")
check(Diary.noteFallenBurial(tom, "Ruth Park") and onlyCandidate("burial").tokens.subject == "Ruth",
    "burying a fallen companion names them")
check(Diary.noteMercyKilling(tom, { id = "crisis:7", subjectId = "sc-ruth", subjectName = "Ruth Park" })
    and onlyCandidate("mercy").tokens.subject == "Ruth", "carrying out a mercy decision is admitted")
local workContext = Diary._contextForTests(tom, onlyCandidate("work").sourceKey)
check(workContext.evidence["count.many"] and workContext.evidence["weather.rain"]
    and workContext.evidence["writer.hungry"] and workContext.evidence["home_known"]
    and workContext.tokens.home_name == "Rosewood" and workContext.evidence["background.habit.makes_tea"]
    and not workContext.evidence["weather.snow"],
    "writing-time facts come from the weather, the writer's own moodles and fixed canon")

-- Time: a week together, and a quiet day when nothing else happened.
resetInbox()
tomWriter.joinedHours = DIARY_TEST_HOURS - 8 * 24
Diary.pulse(player)
local milestone = onlyCandidate("milestone")
check(milestone and milestone.facts["milestone.week"] and milestone.tokens.days == 7,
    "a week together is noticed once")
Diary.pulse(player)
local milestones = 0
for _, candidate in ipairs(tomWriter.candidates) do
    if candidate.scene == "milestone" then milestones = milestones + 1 end
end
check(milestones == 1, "a milestone is never admitted twice")
resetInbox()
local realConfig = SC.GameplayUtil.config
SC.GameplayUtil.config = function(key)
    if key == "diaryQuietChancePercent" then return 100 end
    return realConfig(key)
end
tomWriter.decidedHours = DIARY_TEST_HOURS - 100
Diary.pulse(player)
check(onlyCandidate("quiet") ~= nil, "a long quiet stretch admits a quiet-day page")
SC.GameplayUtil.config = realConfig
local tomBook
for _, item in ipairs(tom.inventory.items) do if item.fullType == Item.ITEM_TYPE then tomBook = item end end
advanceToWritable(tomWriter)
local quietWrite = tryWrite(tom)
check(quietWrite ~= nil and Diary.commitWrite(tom, quietWrite.diary), "a quiet day becomes a page")
local quietEntry = Item.read(tomBook).entries[Item.read(tomBook).entryCount]
check(not string.find(quietEntry, "[{}]"), "the quiet page renders completely")
sampler[#sampler + 1] = "[quiet page written by the controller] " .. string.gsub(quietEntry, "\n", " / ")

SC_TEST_REPORT = table.concat(report, "\n") .. table.concat(sampler, "\n")
    .. "\nDiary harness PASS: " .. checks .. " checks"
print("Diary harness PASS: " .. checks .. " checks")
