-- SPDX-License-Identifier: MIT

if type(require) == "function" then require "SCNamespace" end

-- Cosmetic person identities, independent of actor instances, names and views.
-- Palette order follows hue; all entries exceed 12:1 against black. The native
-- outline/backdrop is still required over the changing world behind the text.
local Colors = {}
SurvivorCompanion.SpeechColors = Colors
local palette = {
    { "rose", 0xF2, 0xB8, 0xB8 }, { "peach", 0xF2, 0xD0, 0xAE },
    { "sand", 0xE6, 0xDC, 0xA3 }, { "sage", 0xCF, 0xDF, 0xA4 },
    { "leaf", 0xB9, 0xDF, 0xAF }, { "mint", 0xAE, 0xE0, 0xCA },
    { "aqua", 0xA9, 0xDD, 0xE0 }, { "sky", 0xB5, 0xD6, 0xF2 },
    { "periwinkle", 0xC0, 0xC9, 0xF2 }, { "lavender", 0xD3, 0xC2, 0xEF },
    { "orchid", 0xE0, 0xBC, 0xE4 }, { "pink", 0xED, 0xBE, 0xD4 },
}
local indices, assigned, counts = {}, {}, {}
for i, entry in ipairs(palette) do indices[entry[1]], counts[i] = i, 0 end

function Colors.valid(key)
    return type(key) == "string" and indices[key] ~= nil
end

function Colors.normalize(key)
    return Colors.valid(key) and key or nil
end

local function validId(id)
    return type(id) == "string" and #id > 0 and #id <= 128
end

local function hash(id)
    -- Exact in Lua doubles. Do not change GameplayUtil's gameplay hash.
    local result = 0
    for i = 1, #id do result = (result * 131 + string.byte(id, i)) % 2147483647 end
    return result
end

local function reserve(id, key)
    if assigned[id] == key then return key end
    local old = indices[assigned[id]]
    if old then counts[old] = counts[old] - 1 end
    assigned[id] = key
    local index = indices[key]
    counts[index] = counts[index] + 1
    return key
end

function Colors.assign(record)
    if type(record) ~= "table" or not validId(record.id) then return nil end
    local key = Colors.normalize(record.speechColorKey) or assigned[record.id]
    if not key then
        local candidates, least, widest = {}, math.huge, -1
        for i = 1, #palette do
            local separation = #palette
            for j = 1, #palette do
                if counts[j] > 0 then
                    local distance = math.abs(i - j)
                    separation = math.min(separation, distance, #palette - distance)
                end
            end
            if counts[i] < least or (counts[i] == least and separation > widest) then
                candidates, least, widest = { i }, counts[i], separation
            elseif counts[i] == least and separation == widest then
                candidates[#candidates + 1] = i
            end
        end
        key = palette[candidates[hash(record.id) % #candidates + 1]][1]
    end
    record.speechColorKey = reserve(record.id, key)
    return key
end

-- Reserve existing choices before assigning missing ones in stable person-ID
-- order. Call at restore, before asynchronous actor spawning can change order.
-- The caller supplies only owned person records, never arbitrary save tables.
function Colors.prepare(records)
    local ordered = {}
    for _, record in pairs(records or {}) do
        if type(record) == "table" and validId(record.id) then ordered[#ordered + 1] = record end
    end
    table.sort(ordered, function(a, b) return a.id < b.id end)
    for _, record in ipairs(ordered) do
        local key = Colors.normalize(record.speechColorKey)
        if key then reserve(record.id, key) end
    end
    for _, record in ipairs(ordered) do Colors.assign(record) end
end

function Colors.prepareFactions(document, records)
    local people, mirrors = {}, {}
    for _, record in pairs(records or {}) do
        if type(record) == "table" and validId(record.id) then people[record.id] = record end
    end
    local groups = type(document) == "table" and type(document.groups) == "table"
        and document.groups or {}
    for _, group in pairs(groups) do
        for _, member in ipairs(type(group) == "table" and type(group.members) == "table"
                and group.members or {}) do
            if type(member) == "table" then
                local snapshot = type(member.snapshot) == "table" and member.snapshot or nil
                local id = snapshot and snapshot.id or member.actorId or member.departedActorId
                if validId(id) then
                    if not people[id] then
                        people[id] = { id = id, speechColorKey = Colors.normalize(
                            snapshot and snapshot.speechColorKey) or Colors.normalize(member.speechColorKey) }
                    end
                    mirrors[#mirrors + 1] = { member = member, snapshot = snapshot, id = id }
                end
            end
        end
    end
    Colors.prepare(people)
    for _, mirror in ipairs(mirrors) do
        local key = people[mirror.id].speechColorKey
        mirror.member.speechColorKey = key
        if mirror.snapshot then mirror.snapshot.speechColorKey = key end
    end
end

function Colors.rgb(key)
    local entry = palette[indices[key]]
    if not entry then return 1, 1, 1 end
    return entry[2] / 255, entry[3] / 255, entry[4] / 255
end

function Colors.forRecord(record)
    local key = Colors.assign(record)
    local options = SurvivorCompanion.UserOptions
    if options and options.get("speechColors") == "white" then return 1, 1, 1 end
    return Colors.rgb(key)
end

function Colors.reset()
    assigned = {}
    for i = 1, #palette do counts[i] = 0 end
end

return Colors
