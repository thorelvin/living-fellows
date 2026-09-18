-- Runs inside the real Kahlua VM. Verifies the codec's behaviour and prints the
-- frames Python must agree with byte for byte.

local Codec = PZRL.Codec
local failures = 0

local function check(name, condition)
    if condition then
        print("  ok   " .. name)
    else
        failures = failures + 1
        print("  FAIL " .. name)
    end
end

print("checksum")
check("empty", Codec.checksum("") == 5381)
check("deterministic", Codec.checksum("abc") == Codec.checksum("abc"))
check("order matters", Codec.checksum("ab") ~= Codec.checksum("ba"))
check("stays in 32 bits", Codec.checksum(string.rep("x", 4000)) < 4294967296)

-- Cross-language contract. These constants come from pzrl_host.checksum(). If
-- Kahlua's number handling ever diverges from Python's, the mailbox stops
-- validating in the field -- so it has to fail here instead.
check("matches Python on 'abc'", Codec.checksum("abc") == 193485963)
check("matches Python on a long string",
    Codec.checksum(string.rep("The quick brown fox. ", 50)) == 4094903511)

print("sanitize")
check("drops separators", Codec.sanitize("a;b=c") == "abc")
check("keeps pipe", Codec.sanitize("a|b") == "a|b")
check("drops control chars", Codec.sanitize("a\nb\tc") == "abc")
check("drops non-ascii", Codec.sanitize("Rad\195\184") == "Rad")
check("truncates", #Codec.sanitize(string.rep("y", 200), 24) == 24)

print("round trip")
local pairs_ = {
    { "epoch", "g123" }, { "binding", "b1" }, { "rev", 3 },
    { "status", "linked" }, { "ch", 93400 },
    { "presets", "WKTV:88500|Noise Maker:91200", 512 },
}
local text = Codec.frame(41, pairs_)
local lines = {}
for line in string.gmatch(text, "([^\n]*)\n") do lines[#lines + 1] = line end
check("three lines", #lines == 3)
local fields, seq = Codec.parse(lines[1], lines[2], lines[3])
check("parsed", fields ~= nil)
check("seq", seq == 41)
check("value", fields and fields.ch == "93400")
check("presets intact", fields and fields.presets == "WKTV:88500|Noise Maker:91200")

-- Byte-for-byte agreement with the frame pzrl_host.frame() produces for the
-- same input. Field order, separators, length and checksum all have to match.
check("header matches Python", lines[1] == "PZRL2 seq=41 len=87 crc=1139857419")
check("payload matches Python",
    lines[2] == "epoch=g123;binding=b1;rev=3;status=linked;ch=93400;presets=WKTV:88500|Noise Maker:91200")

print("rejection")
check("bad footer", Codec.parse(lines[1], lines[2], "NOPE") == nil)
check("bad header", Codec.parse("garbage", lines[2], lines[3]) == nil)
check("length mismatch", Codec.parse(lines[1], lines[2] .. "x", lines[3]) == nil)
check("checksum mismatch",
    Codec.parse(lines[1], string.gsub(lines[2], "93400", "93401"), lines[3]) == nil)
check("missing payload", Codec.parse(lines[1], nil, lines[3]) == nil)

print("numbers")
local f = Codec.decodePayload("a=12;b=1.5;c=;d=abc;e=1e400;f=0;g=-3")
check("integer", Codec.integer(f, "a") == 12)
check("float rejected as integer", Codec.integer(f, "b") == nil)
check("float ok as number", Codec.number(f, "b") == 1.5)
check("empty rejected", Codec.number(f, "c") == nil)
check("text rejected", Codec.number(f, "d") == nil)
check("infinity rejected", Codec.number(f, "e") == nil)
check("zero accepted", Codec.integer(f, "f") == 0)
check("negative accepted", Codec.integer(f, "g") == -3)
check("absent rejected", Codec.number(f, "zz") == nil)

local b = Codec.decodePayload("t=1;f=0;x=true")
check("bool true", Codec.boolean(b, "t") == true)
check("bool false", Codec.boolean(b, "f") == false)
check("bool strict", Codec.boolean(b, "x") == nil)

if failures > 0 then
    error(tostring(failures) .. " codec check(s) failed")
end
print("ALL CODEC CHECKS PASSED")

--[[ ------------------------------------------- protocol 2 and tuning grid ]]

print("protocol")
check("codec declares protocol 2", Codec.PROTOCOL == 2)
check("magic changed with it", Codec.MAGIC == "PZRL2")
-- A v1 document must not parse: protocol 1 dispatch ignored the proto field,
-- so a mixed install has to fail loudly rather than act on the wrong schema.
local v1 = "PZRL1 seq=1 len=7 crc=" .. tostring(Codec.checksum("proto=1"))
check("v1 framing rejected", Codec.parse(v1, "proto=1", "PZRLEND") == nil)

print("tuning grid (BF-10)")
-- A device whose saved frequency sits off the 200-unit grid. Adding 200 keeps
-- the invalid remainder, so the nudge used to produce a value the mod itself
-- rejects and the button appeared dead.
local fakeData = {
    getMinChannelRange = function() return 88000 end,
    getMaxChannelRange = function() return 108000 end,
}
local D = PZRL.Device
check("off-grid steps up to a legal point",
    D.nextGridChannel(fakeData, 88500, 1) == 88600)
check("off-grid steps down to a legal point",
    D.nextGridChannel(fakeData, 88500, -1) == 88400)
check("on-grid steps by exactly one step",
    D.nextGridChannel(fakeData, 93400, 1) == 93600)
check("on-grid steps down by one step",
    D.nextGridChannel(fakeData, 93400, -1) == 93200)
check("clamps to the top legal point",
    D.nextGridChannel(fakeData, 108000, 1) == nil)
check("clamps to the bottom legal point",
    D.nextGridChannel(fakeData, 88000, -1) == nil)
check("result is always on the grid",
    D.nextGridChannel(fakeData, 88500, 1) % 200 == 0)

-- A band whose edges are themselves off-grid must clamp to legal points inside
-- it, not to the raw endpoints.
local oddBand = {
    getMinChannelRange = function() return 88050 end,
    getMaxChannelRange = function() return 107950 end,
}
check("odd band clamps to an interior grid point",
    D.nextGridChannel(oddBand, 88050, -1) == 88200)
check("odd band top clamps inside the band",
    D.nextGridChannel(oddBand, 107900, 1) == nil
        or D.nextGridChannel(oddBand, 107900, 1) <= 107950)

local unreadable = {
    getMinChannelRange = function() error("no range") end,
    getMaxChannelRange = function() error("no range") end,
}
check("unreadable range yields no step",
    D.nextGridChannel(unreadable, 93400, 1) == nil)
check("unreadable range is not a 0..0 band",
    select(1, D.channelRange(unreadable)) == nil)

if failures > 0 then
    error(tostring(failures) .. " check(s) failed")
end
print("PROTOCOL AND GRID CHECKS PASSED")
