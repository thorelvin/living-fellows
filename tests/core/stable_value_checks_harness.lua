-- SPDX-License-Identifier: MIT
-- The shared saved-document checks that the base, community, faction,
-- faction-world, infection and diary restores call instead of keeping copies.

local SC = SurvivorCompanion
local V = SC.StableValue
local checks = 0

local function check(value, message)
    checks = checks + 1
    assert(value, "check " .. tostring(checks) .. " failed: " .. tostring(message))
end

local function moduleFailure(path, detail)
    return false, "invalid test state at " .. tostring(path) .. ": " .. tostring(detail)
end

local nan = 0 / 0

-- isFinite: real numbers only.
check(V.isFinite(0) and V.isFinite(-2.5) and V.isFinite(4096), "ordinary numbers are finite")
check(not V.isFinite(nan), "NaN is not finite")
check(not V.isFinite(math.huge) and not V.isFinite(-math.huge), "infinities are not finite")
check(not V.isFinite("12") and not V.isFinite(nil) and not V.isFinite(true),
    "a numeric string, nil or a boolean is not a finite number")

-- denseArray: keys exactly 1..n.
local ok, count = V.denseArray({}, "$.empty", moduleFailure)
check(ok == true and count == 0, "an empty table is a dense array of zero")
ok, count = V.denseArray({ "a", "b", "c" }, "$.list", moduleFailure)
check(ok == true and count == 3, "a 1..3 list is dense and reports its count")

local reason
ok, reason = V.denseArray("list", "$.text", moduleFailure)
check(ok == false and reason == "invalid test state at $.text: expected dense array",
    "a non-table reports through the caller's wording: " .. tostring(reason))
ok, reason = V.denseArray({ [1] = "a", [3] = "c" }, "$.gap", moduleFailure)
check(ok == false and reason == "invalid test state at $.gap: sparse array",
    "a gap is a sparse array: " .. tostring(reason))
ok, reason = V.denseArray({ [1] = 1, [3] = 3, [5] = 5 }, "$.border", moduleFailure)
check(ok == false and reason == "invalid test state at $.border: sparse array",
    "three keys with a gap are sparse even where the length operator could report 3")
ok, reason = V.denseArray({ "a", label = "b" }, "$.mixed", moduleFailure)
check(ok == false and reason == "invalid test state at $.mixed[label]: non-array key",
    "a string key names itself in the path: " .. tostring(reason))
ok, reason = V.denseArray({ [1.5] = "a" }, "$.fraction", moduleFailure)
check(ok == false and string.find(reason, "non-array key", 1, true) ~= nil,
    "a fractional key is not an array key")
ok, reason = V.denseArray({ [math.huge] = "a" }, "$.infinite", moduleFailure)
check(ok == false and string.find(reason, "non-array key", 1, true) ~= nil,
    "an infinite key is not an array key")
ok, reason = V.denseArray({ [0] = "a" }, "$.zero", moduleFailure)
check(ok == false and string.find(reason, "$.zero[0]", 1, true) ~= nil,
    "index zero is not an array key")

ok, count = V.denseArray({ 1, 2 }, "$.max", moduleFailure, 2)
check(ok == true and count == 2, "a list at its maximum is accepted")
ok, reason = V.denseArray({ 1, 2, 3 }, "$.max", moduleFailure, 2)
check(ok == false and reason == "invalid test state at $.max: too many entries",
    "a list over its maximum is refused")
ok, reason = V.denseArray({ 1 }, "$.min", moduleFailure, nil, 2)
check(ok == false and reason == "invalid test state at $.min: too few entries",
    "a list under its minimum is refused")
ok, count = V.denseArray({ 1, 2 }, "$.min", moduleFailure, 4, 2)
check(ok == true and count == 2, "a list at its minimum is accepted")

ok, reason = V.denseArray({ [2] = "b" }, nil, nil, 8)
check(ok == false and reason == "sparse array",
    "without a failure function the check returns false and the detail")
ok, reason = V.denseArray({ x = 1 }, nil)
check(ok == false and reason == "non-array key", "a missing path does not break the key detail")

-- limit: whole numbers of zero or more.
check(V.limit(nil, 7) == 7, "no configured value keeps the fallback")
check(V.limit(12, 7) == 12 and V.limit("12", 7) == 12, "numbers and numeric text are read")
check(V.limit(3.9, 7) == 3, "a fractional limit rounds down")
check(V.limit(0, 7) == 0, "zero is a valid limit")
check(V.limit(-1, 7) == 7, "a negative limit keeps the fallback")
check(V.limit(nan, 7) == 7 and V.limit(math.huge, 7) == 7 and V.limit(-math.huge, 7) == 7,
    "NaN and infinities keep the fallback")
check(V.limit("many", 7) == 7 and V.limit(false, 7) == 7, "text and booleans keep the fallback")

print("STABLE_VALUE_CHECKS_PASS checks=" .. tostring(checks))
