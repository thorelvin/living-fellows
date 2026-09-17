-- SPDX-License-Identifier: MIT
--
-- Private diary text compiler. Pure: no game API, world write, item access,
-- global RNG or action dispatch. A trusted adapter (SCDiary) supplies an
-- allowlisted evidence view; this module only selects an authored, complete
-- passage whose declared prerequisites hold and renders its literal tokens.
-- It is not a truth detector for arbitrary prose: every packet in the catalog
-- carries its own reviewed truth contract.

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.DiaryText = SC.DiaryText or {}
local Text = SC.DiaryText

Text.VERSION = 1
Text.MAX_TOKEN_BYTES = 120
Text.MAX_TEMPLATE_BYTES = 1024
Text.MAX_ENTRY_BYTES = 1536
Text.HISTORY_WINDOW = 6

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function validString(value, maximum)
    return type(value) == "string" and value ~= "" and #value <= maximum
end

-- Deterministic and platform independent. Intermediate values stay far below
-- 2^53, the exact integer range of the doubles Kahlua uses for numbers.
function Text.stableHash(value)
    local hash = 17
    value = tostring(value or "")
    for index = 1, #value do
        hash = (hash * 131 + string.byte(value, index)) % 2147483647
    end
    return hash
end

local function requirementsPass(required, forbidden, evidence)
    for _, key in ipairs(required or {}) do
        if evidence[key] ~= true then return false end
    end
    for _, key in ipairs(forbidden or {}) do
        if evidence[key] == true then return false end
    end
    return true
end

-- Entries since the newest history row whose field equals value; a huge age
-- when it does not occur inside the bounded window.
local function ageOf(history, field, value, window)
    local age = 0
    local lowest = math.max(1, #history - (window or Text.HISTORY_WINDOW) + 1)
    for index = #history, lowest, -1 do
        local row = history[index]
        if type(row) == "table" and row[field] == value then return age end
        age = age + 1
    end
    return math.huge
end

-- A token is a literal display value: a name, a body part label, a stored
-- quote or a number. It may not carry control characters (a newline would
-- forge a new date line in the stored entry) or placeholder braces.
function Text.validToken(value)
    if finite(value) then value = tostring(value) end
    if not validString(value, Text.MAX_TOKEN_BYTES) then return false end
    return string.find(value, "[%c{}]") == nil
end

local function render(template, tokens, maximumBytes)
    local reason
    local text = string.gsub(template, "{([%w_]+)}", function(key)
        local value = tokens[key]
        if not Text.validToken(value) then
            reason = "missing_or_invalid_token:" .. key
            return ""
        end
        -- A function replacement keeps a literal '%' in a name literal. Tokens
        -- are substituted once and never expanded again.
        return tostring(value)
    end)
    if reason then return nil, reason end
    if #text == 0 or #text > maximumBytes then return nil, "empty_or_oversize_entry" end
    return text
end

local function choose(rows, seed)
    table.sort(rows, function(left, right) return left.id < right.id end)
    local total = 0
    for _, row in ipairs(rows) do total = total + row.weight end
    if total < 1 then return nil end
    local roll = Text.stableHash(seed) % total
    for _, row in ipairs(rows) do
        if roll < row.weight then return row end
        roll = roll - row.weight
    end
    return nil
end

local function stringList(value, maximum)
    if value == nil then return true end
    if type(value) ~= "table" then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" then return false end
        count = count + 1
    end
    if count ~= #value or count > (maximum or 16) then return false end
    for _, entry in ipairs(value) do
        if not validString(entry, 100) then return false end
    end
    return true
end

local function packetProblem(packet, voices)
    if type(packet) ~= "table" then return "packet_not_table" end
    if not validString(packet.id, 100) then return "invalid_packet_id" end
    for _, field in ipairs({ "scene", "ideaId", "shape" }) do
        if not validString(packet[field], 100) then return "invalid_" .. field end
    end
    if type(packet.voiceWeights) ~= "table" then return "invalid_voice_weights" end
    local voiced = false
    for voice, weight in pairs(packet.voiceWeights) do
        if type(voice) ~= "string" or not finite(weight) or weight < 0 then
            return "invalid_voice_weight"
        end
        if voices ~= nil and voices[voice] == nil then return "unknown_voice:" .. voice end
        if weight > 0 then voiced = true end
    end
    if not voiced then return "no_voice_weight" end
    if not stringList(packet.requires) or not stringList(packet.forbids) then
        return "invalid_requirements"
    end
    if packet.cooldownEntries ~= nil and (not finite(packet.cooldownEntries)
        or packet.cooldownEntries < 0) then
        return "invalid_cooldown"
    end
    if type(packet.variants) ~= "table" or #packet.variants == 0 then return "no_variants" end
    local seen = {}
    for _, variant in ipairs(packet.variants) do
        if type(variant) ~= "table" or not validString(variant.id, 40) or seen[variant.id] then
            return "invalid_or_duplicate_variant"
        end
        seen[variant.id] = true
        local label = "variant:" .. variant.id
        if not validString(variant.text, Text.MAX_TEMPLATE_BYTES) then
            return "invalid_text:" .. label
        end
        if string.find(variant.text, "\r", 1, true) then return "reserved_text:" .. label end
        if not stringList(variant.requires) or not stringList(variant.forbids) then
            return "invalid_requirements:" .. label
        end
        local stripped = string.gsub(variant.text, "{([%w_]+)}", "")
        if string.find(stripped, "[{}]") then return "malformed_placeholder:" .. label end
        if variant.anchorKey ~= nil or variant.anchorQuote ~= nil then
            -- A callback quote is literal authored text that must genuinely occur
            -- in this exact variant; later pages quote what was really written.
            if not validString(variant.anchorKey, 60) or not validString(variant.anchorQuote, 160)
                or string.find(variant.anchorQuote, "[{}%c]")
                or not string.find(variant.text, variant.anchorQuote, 1, true) then
                return "anchor_quote_missing_from_variant:" .. label
            end
        end
    end
    return nil
end

-- Returns the valid packets plus a list of diagnosed problems. An invalid
-- optional passage is disabled; it never takes the companion runtime down.
function Text.prepareCatalog(catalog, voices)
    local packets, problems, ids = {}, {}, {}
    if type(catalog) ~= "table" then
        return packets, { "catalog_not_table" }
    end
    packets.version = catalog.version
    for index, packet in ipairs(catalog) do
        local problem = packetProblem(packet, voices)
        if problem == nil and ids[packet.id] then problem = "duplicate_packet_id" end
        if problem then
            problems[#problems + 1] = tostring(type(packet) == "table" and packet.id
                or ("#" .. index)) .. ":" .. problem
        else
            ids[packet.id] = true
            packets[#packets + 1] = packet
        end
    end
    return packets, problems
end

function Text.validateCatalog(catalog, voices)
    local _, problems = Text.prepareCatalog(catalog, voices)
    if #problems > 0 then return false, problems[1], problems end
    return true
end

-- Returns a draft or nil plus a reason. Generation never commits anything: the
-- caller records history and anchors only after a supervised writing action
-- and a verified append to the exact physical book.
function Text.generate(context, history, catalog)
    if type(context) ~= "table" or type(history) ~= "table" or type(catalog) ~= "table"
        or type(context.evidence) ~= "table" or type(context.tokens) ~= "table" then
        return nil, "invalid_context"
    end
    for _, key in ipairs({ "diaryId", "entryId", "sourceKey", "voice", "scene", "seed" }) do
        if not validString(context[key], 240) then return nil, "invalid_" .. key end
    end
    local maximum = context.maxBytes or Text.MAX_ENTRY_BYTES
    if not finite(maximum) or maximum < 1 or maximum > Text.MAX_ENTRY_BYTES then
        return nil, "invalid_byte_budget"
    end
    local seed = tostring(Text.VERSION) .. "|" .. tostring(catalog.version or 1) .. "|"
        .. context.diaryId .. "|" .. context.entryId .. "|" .. context.sourceKey
        .. "|" .. context.seed
    local packets = {}
    for _, packet in ipairs(catalog) do
        local weight = packet.voiceWeights[context.voice]
        if packet.scene == context.scene and finite(weight) and weight > 0
            and requirementsPass(packet.requires, packet.forbids, context.evidence)
            and ageOf(history, "ideaId", packet.ideaId) >= (packet.cooldownEntries
                or Text.HISTORY_WINDOW) then
            local variants = {}
            for _, variant in ipairs(packet.variants) do
                local variantId = packet.id .. ":" .. variant.id
                if requirementsPass(variant.requires, variant.forbids, context.evidence)
                    and ageOf(history, "variantId", variantId) >= Text.HISTORY_WINDOW then
                    local rendered = render(variant.text, context.tokens, maximum)
                    if rendered then
                        variants[#variants + 1] = {
                            id = variantId, weight = 1, text = rendered,
                            anchorKey = variant.anchorKey, anchorQuote = variant.anchorQuote,
                        }
                    end
                end
            end
            if #variants > 0 then
                -- Repeated structure is penalized; factual gates never relax.
                if ageOf(history, "shape", packet.shape) < 2 then weight = weight / 2 end
                packets[#packets + 1] = {
                    id = packet.id, weight = math.max(1, math.floor(weight)),
                    variants = variants, ideaId = packet.ideaId, shape = packet.shape,
                    threads = packet.threads,
                }
            end
        end
    end
    local packet = choose(packets, seed .. "|packet")
    if not packet then return nil, "no_truthful_nonrepetitive_variant" end
    local variant = choose(packet.variants, seed .. "|variant")
    return {
        entryId = context.entryId, sourceKey = context.sourceKey, scene = context.scene,
        text = variant.text, packetId = packet.id, variantId = variant.id,
        ideaId = packet.ideaId, shape = packet.shape, bytes = #variant.text,
        anchorKey = variant.anchorKey, anchorQuote = variant.anchorQuote,
        generatorVersion = Text.VERSION, catalogVersion = catalog.version or 1,
    }
end

return Text
