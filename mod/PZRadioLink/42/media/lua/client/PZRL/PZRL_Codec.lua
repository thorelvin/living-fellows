--[[
PZ Radio Link -- framed key/value codec.

Deliberately not JSON. Kahlua has no bitwise operators and no JSON parser, and a
hand-rolled JSON parser is a larger attack surface than this feature needs. The
mailbox carries one line of `key=value` pairs separated by ';', wrapped in a frame
that carries a sequence number, an exact byte length and a checksum.

Frame layout (exactly three lines, LF-terminated):

    PZRL1 seq=<n> len=<bytes> crc=<n>
    <payload>
    PZRLEND

A reader that cannot see all three lines, or whose payload length or checksum does
not match the header, must discard the document and keep its previous state. The
checksum detects torn writes and truncation. It is not authentication.
]]

PZRL = PZRL or {}

local Codec = {}
PZRL.Codec = Codec

Codec.MAGIC = "PZRL1"
Codec.FOOTER = "PZRLEND"
Codec.MAX_PAYLOAD_BYTES = 16384

-- djb2, reduced mod 2^32. Uses only multiplication, addition and modulo so it
-- behaves identically under Kahlua (no bit library) and Python. Intermediate
-- values peak near 1.4e11, far below the 2^53 exact-integer range of a double.
function Codec.checksum(s)
    if type(s) ~= "string" then return 0 end
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 4294967296
    end
    return h
end

-- Values may only contain characters that cannot collide with the framing or the
-- pair separators. Anything else is dropped rather than escaped: this codec never
-- needs to round-trip arbitrary text, and dropping keeps the grammar trivial.
--
-- '|' is permitted because the preset list uses it to separate entries. Preset
-- names have it stripped where they are built (Runtime.presetPairs), so a name
-- can never split an entry.
function Codec.sanitize(value, maxBytes)
    if value == nil then return "" end
    local s = tostring(value)
    s = string.gsub(s, "[^A-Za-z0-9_%.%:%-%+%| ]", "")
    maxBytes = maxBytes or 64
    if #s > maxBytes then s = string.sub(s, 1, maxBytes) end
    return s
end

function Codec.validKey(key)
    return type(key) == "string" and string.find(key, "^[a-z][a-z0-9_]*$") ~= nil
end

-- Encodes an ordered list of {key, value} pairs. An ordered list rather than a
-- table because the payload must be byte-identical for a given input, so that the
-- checksum a writer computes is the checksum a reader recomputes.
function Codec.encodePayload(pairs_)
    local parts = {}
    for _, pair in ipairs(pairs_) do
        local key, value = pair[1], pair[2]
        if Codec.validKey(key) then
            parts[#parts + 1] = key .. "=" .. Codec.sanitize(value, pair[3] or 64)
        end
    end
    return table.concat(parts, ";")
end

function Codec.decodePayload(payload)
    local out = {}
    if type(payload) ~= "string" then return out end
    for chunk in string.gmatch(payload, "[^;]+") do
        local key, value = string.match(chunk, "^([a-z][a-z0-9_]*)=(.*)$")
        if key then out[key] = value end
    end
    return out
end

function Codec.frame(seq, pairs_)
    local payload = Codec.encodePayload(pairs_)
    if #payload > Codec.MAX_PAYLOAD_BYTES then return nil, "payload_too_large" end
    local header = string.format("%s seq=%d len=%d crc=%d",
        Codec.MAGIC, seq, #payload, Codec.checksum(payload))
    return header .. "\n" .. payload .. "\n" .. Codec.FOOTER .. "\n"
end

-- Returns (fields, seq) on a fully validated document, or (nil, reason).
function Codec.parse(headerLine, payloadLine, footerLine)
    if type(headerLine) ~= "string" or type(payloadLine) ~= "string" then
        return nil, "incomplete"
    end
    if footerLine ~= Codec.FOOTER then
        return nil, "bad_footer"
    end
    local seq, len, crc = string.match(headerLine,
        "^" .. Codec.MAGIC .. " seq=(%d+) len=(%d+) crc=(%d+)$")
    if not seq then return nil, "bad_header" end
    seq, len, crc = tonumber(seq), tonumber(len), tonumber(crc)
    if #payloadLine ~= len then return nil, "length_mismatch" end
    if Codec.checksum(payloadLine) ~= crc then return nil, "checksum_mismatch" end
    return Codec.decodePayload(payloadLine), seq
end

-- Numeric accessors that reject the shapes a text transport makes easy to send by
-- accident: empty strings, "nan", "1e400", and integers that arrived as floats.
function Codec.number(fields, key)
    local raw = fields[key]
    if type(raw) ~= "string" or raw == "" then return nil end
    local n = tonumber(raw)
    if n == nil then return nil end
    if n ~= n then return nil end             -- NaN
    if n == math.huge or n == -math.huge then return nil end
    return n
end

function Codec.integer(fields, key)
    local n = Codec.number(fields, key)
    if n == nil then return nil end
    if math.floor(n) ~= n then return nil end
    return n
end

function Codec.boolean(fields, key)
    local raw = fields[key]
    if raw == "1" then return true end
    if raw == "0" then return false end
    return nil
end

return Codec
