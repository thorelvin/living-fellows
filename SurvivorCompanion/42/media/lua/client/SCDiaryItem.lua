-- SPDX-License-Identifier: MIT
--
-- The physical diary. A book owns its committed pages in item ModData under
-- one versioned key, so it stays readable on a corpse, in storage, in a trade
-- or in a successor's hands with no live author record at all.
--
-- Build 42.20.4 saves every ModData string with a signed 16-bit length
-- (GameWindow.StringUTF.save uses putShort, and load() returns "" for a
-- non-positive length). One long text value would therefore load back empty
-- once it passed 32767 encoded bytes. Each entry is instead its own bounded
-- string: "<date line>\n<passage>". Entries are never rewritten; an append
-- replaces the whole payload table in one synchronous step and reads it back.
--
-- LivingFellows.PrivateDiary (scripts/LivingFellows_Diary.txt) is deliberately
-- an ordinary item, not Literature: vanilla offers no read, write or notebook
-- edit action for it, so this module stays the only author of its pages.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.DiaryItem = SC.DiaryItem or {}
local Item = SC.DiaryItem

Item.ITEM_TYPE = "LivingFellows.PrivateDiary"
Item.KEY = "LF_Diary"
Item.SCHEMA = 1
Item.MAX_ENTRY_BYTES = 1600
Item.HARD_MAX_ENTRIES = 60
Item.MAX_TOTAL_BYTES = 60000

local writingTypes = {
    ["base.pen"] = true, ["base.pencil"] = true, ["base.bluepen"] = true,
    ["base.redpen"] = true, ["base.greenpen"] = true,
}

local function U() return SC.GameplayUtil end

local function integer(value, minimum)
    return type(value) == "number" and value == value and value ~= math.huge
        and value == math.floor(value) and value >= (minimum or 0)
end

local function text(value, maximum, allowEmpty)
    return type(value) == "string" and (allowEmpty == true or value ~= "")
        and #value <= maximum
end

function Item.maxEntries()
    local configured = tonumber(U() and U().config("diaryMaxEntries")) or Item.HARD_MAX_ENTRIES
    return math.max(1, math.min(Item.HARD_MAX_ENTRIES, math.floor(configured)))
end

local function modData(item)
    if item == nil then return nil end
    local data, ok = U().call(item, "getModData")
    if ok and type(data) == "table" then return data end
    return nil
end

-- Validates without trusting or mutating the stored table and returns a
-- detached copy. Unknown or malformed payloads are left exactly as found.
function Item.readPayload(raw)
    if type(raw) ~= "table" then return nil, "no_diary_payload" end
    if raw.schema ~= Item.SCHEMA then return nil, "unsupported_diary_schema" end
    if not text(raw.diaryId, 160) or not text(raw.authorId, 80)
        or not text(raw.authorName, 80) or not text(raw.authoredLocale, 8)
        or not integer(raw.volume, 1) or not integer(raw.revision, 0)
        or not integer(raw.entryCount, 0) or type(raw.entries) ~= "table" then
        return nil, "malformed_diary_header"
    end
    local count = 0
    for key in pairs(raw.entries) do
        if not integer(key, 1) then return nil, "malformed_diary_entries" end
        count = count + 1
    end
    if count ~= #raw.entries or count ~= raw.entryCount or count > Item.HARD_MAX_ENTRIES then
        return nil, "diary_entry_count_mismatch"
    end
    local entries, total = {}, 0
    for index = 1, count do
        local entry = raw.entries[index]
        if not text(entry, Item.MAX_ENTRY_BYTES) or not string.find(entry, "\n", 1, true) then
            return nil, "malformed_diary_entry"
        end
        total = total + #entry
        entries[index] = entry
    end
    if total > Item.MAX_TOTAL_BYTES then return nil, "diary_too_large" end
    if count > 0 and not text(raw.lastEntryId, 200) then return nil, "malformed_diary_header" end
    return {
        schema = raw.schema, diaryId = raw.diaryId, authorId = raw.authorId,
        authorName = raw.authorName, authoredLocale = raw.authoredLocale,
        volume = raw.volume, revision = raw.revision, entryCount = raw.entryCount,
        lastEntryId = raw.lastEntryId, entries = entries, bytes = total,
    }
end

function Item.read(item)
    local data = modData(item)
    if not data then return nil, "item_mod_data_unavailable" end
    return Item.readPayload(data[Item.KEY])
end

-- Cheap enough for context menus and corpse scans: getModData() would create
-- an empty table on every item that has none, so ask hasModData() first.
function Item.hasPayload(item)
    if item == nil then return false end
    local present, known = U().call(item, "hasModData")
    if known and present ~= true then return false end
    local data = modData(item)
    return data ~= nil and type(data[Item.KEY]) == "table"
end

function Item.isDiaryItem(item)
    return item ~= nil and string.lower(U().itemType(item)) == string.lower(Item.ITEM_TYPE)
end

function Item.parseEntry(entry)
    if type(entry) ~= "string" then return nil, nil end
    local split = string.find(entry, "\n", 1, true)
    if not split then return nil, entry end
    return string.sub(entry, 1, split - 1), string.sub(entry, split + 1)
end

function Item.displayName(authorName)
    local fallback = tostring(authorName or "") .. "'s diary"
    if not text(authorName, 80) then fallback = "Private diary" end
    return U().text("UI_SC_Diary_ItemName", fallback, tostring(authorName or ""))
end

-- Companion inventory reconstruction does not restore custom item names, so
-- the owner re-applies the title from the book's own header when needed.
function Item.applyName(item, payload)
    if item == nil or type(payload) ~= "table" then return false end
    local wanted = Item.displayName(payload.authorName)
    local current, ok = U().call(item, "getName")
    if ok and current == wanted then return true end
    U().call(item, "setName", wanted)
    U().call(item, "setCustomName", true)
    return true
end

-- Writes an empty header onto a freshly created book. Never overwrites a
-- payload that already exists.
function Item.initialize(item, header)
    local data = modData(item)
    if not data then return false, "item_mod_data_unavailable" end
    if data[Item.KEY] ~= nil then
        local existing = Item.readPayload(data[Item.KEY])
        if existing and existing.diaryId == header.diaryId then return true, existing end
        return false, "diary_payload_already_present"
    end
    local payload = {
        schema = Item.SCHEMA, diaryId = header.diaryId, authorId = header.authorId,
        authorName = header.authorName, authoredLocale = header.authoredLocale or "EN",
        volume = 1, revision = 0, entryCount = 0, entries = {},
    }
    if not Item.readPayload(payload) then return false, "invalid_diary_header" end
    data[Item.KEY] = payload
    local verified = Item.read(item)
    if not verified or verified.diaryId ~= header.diaryId then
        data[Item.KEY] = nil
        return false, "diary_header_not_retained"
    end
    Item.applyName(item, verified)
    return true, verified
end

-- Appends exactly one entry to the exact book when its current revision is
-- the one the draft was prepared against. A book already ending with the same
-- entry id reports success without writing it twice.
function Item.append(item, request)
    local data = modData(item)
    if not data then return false, "item_mod_data_unavailable" end
    if type(request) ~= "table" or not text(request.entryId, 200)
        or not text(request.dateLabel, 60) or not text(request.text, Item.MAX_ENTRY_BYTES)
        or string.find(request.dateLabel, "%c") then
        return false, "invalid_append_request"
    end
    local previous = data[Item.KEY]
    local current, reason = Item.readPayload(previous)
    if not current then return false, reason end
    if current.diaryId ~= request.diaryId then return false, "diary_identity_mismatch" end
    if current.lastEntryId == request.entryId then return true, current, "already_committed" end
    if current.revision ~= request.revision then return false, "diary_revision_changed" end
    if current.entryCount >= Item.maxEntries() then return false, "diary_volume_full" end
    local entry = request.dateLabel .. "\n" .. request.text
    if #entry > Item.MAX_ENTRY_BYTES or current.bytes + #entry > Item.MAX_TOTAL_BYTES then
        return false, "diary_entry_too_large"
    end
    local entries = {}
    for index, value in ipairs(current.entries) do entries[index] = value end
    entries[#entries + 1] = entry
    local payload = {
        schema = Item.SCHEMA, diaryId = current.diaryId, authorId = current.authorId,
        authorName = current.authorName, authoredLocale = current.authoredLocale,
        volume = current.volume, revision = current.revision + 1,
        entryCount = #entries, lastEntryId = request.entryId, entries = entries,
    }
    data[Item.KEY] = payload
    local verified = Item.read(item)
    if not verified or verified.revision ~= payload.revision
        or verified.lastEntryId ~= request.entryId
        or verified.entries[verified.entryCount] ~= entry then
        data[Item.KEY] = previous
        return false, "diary_append_not_retained"
    end
    return true, verified, "appended"
end

function Item.isWritingImplement(item)
    if item == nil then return false end
    local itemType = string.lower(U().itemType(item))
    if writingTypes[itemType] then return true end
    -- Tag iteration is a native walk; only consult it for plausible modded pens.
    if not string.find(itemType, "pen", 1, true) then return false end
    local utility = U()
    return utility.itemHasTag(item, "write") or utility.itemHasTag(item, "pen")
        or utility.itemHasTag(item, "pencil")
end

-- Bounded and resumable: a pen in the twelfth bag is found eventually rather
-- than never. `cursor` comes back for the caller to hand in next time, and a
-- previously found implement is re-validated cheaply before a new search.
function Item.findWritingImplement(actor, cursor, cached)
    local personal = SC.PersonalItems
    if type(personal) ~= "table" then return nil, 0, "absent" end
    if cached ~= nil and Item.isWritingImplement(cached)
        and personal.ownedBy(cached, actor) == true then
        return cached, cursor or 0, "found"
    end
    if type(personal.searchResumable) ~= "function" then
        local found
        personal.walkActorInventory(actor, function(item)
            if Item.isWritingImplement(item) then found = item return false end
        end)
        return found, 0, found and "found" or "absent"
    end
    return personal.searchResumable(actor, function(item)
        return Item.isWritingImplement(item)
    end, cursor)
end

return Item
