-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local C, U = SC.SpeechColors, SC.GameplayUtil
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, message)
end
local keys = { "rose", "peach", "sand", "sage", "leaf", "mint", "aqua", "sky",
    "periwinkle", "lavender", "orchid", "pink" }
local function linear(value)
    return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
end
for _, key in ipairs(keys) do
    local r, g, b = C.rgb(key)
    local luminance = .2126 * linear(r) + .7152 * linear(g) + .0722 * linear(b)
    check(C.valid(key) and (luminance + .05) / .05 >= 12.3, "palette contrast: " .. key)
end
check(not C.valid({}) and not C.valid("red"), "malformed keys must be rejected")
C.reset()
local people, used = {}, {}
for i = 1, 48 do
    local record = { id = "sc-colour-" .. tostring(i) }
    people[i] = record
    local key = C.assign(record)
    if i <= 12 then check(not used[key], "palette should not repeat before exhaustion") end
    used[key] = (used[key] or 0) + 1
end
for _, count in pairs(used) do check(count == 4, "full palette reuse must stay balanced") end
local first = people[1]
local key = first.speechColorKey
first.identity, first.recruited = { forename = "Renamed" }, true
check(C.assign(first) == key and C.assign({ id = first.id }) == key,
    "recruitment, renaming and actor replacement must not shuffle a person")
check(C.assign({}) == nil, "missing identity uses white without storing an anonymous assignment")
local r, g, b = C.forRecord(nil)
check(r == 1 and g == 1 and b == 1, "missing identity must be white")
local function oldSave(order)
    local records = {}
    for _, id in ipairs(order) do records[#records + 1] = { id = "sc-" .. id } end
    records[#records + 1] = { id = "sc-existing", speechColorKey = "aqua" }
    C.prepare(records)
    local result = {}
    for _, record in ipairs(records) do result[record.id] = record.speechColorKey end
    return result
end
C.reset()
local normal = oldSave({ "one", "two", "three", "four" })
C.reset()
local reverse = oldSave({ "four", "three", "two", "one" })
for id, assigned in pairs(normal) do check(reverse[id] == assigned, "restore order changed " .. id) end
check(normal["sc-existing"] == "aqua", "existing saved assignments always win")
C.reset()
local small = {}
for i=1,4 do
    local key = C.assign({ id = "sc-small-" .. i })
    for index, value in ipairs(keys) do if value == key then small[i] = index end end
end
for i=1,4 do for j=i+1,4 do
    local gap = math.abs(small[i]-small[j])
    check(math.min(gap,12-gap) >= 3, "small casts need well-separated hues")
end end
local member = { actorId = "sc-household", speechColorKey = "lavender",
    snapshot = { id = "sc-household", speechColorKey = "lavender" } }
C.prepareFactions({ groups = { household = { members = { member } } } })
check(member.speechColorKey == "lavender" and member.snapshot.speechColorKey == "lavender",
    "household hibernation retains the same key")
local recruited = { id = member.actorId, speechColorKey = member.snapshot.speechColorKey }
C.prepareFactions({ groups = { household = { members = { member } } } }, { recruited })
check(recruited.speechColorKey == "lavender", "recruitment transfer retains its colour")
C.prepareFactions({ groups = { bad = false, other = { members = { false } } } })
check(C.assign({ id = "sc-malformed", speechColorKey = {} }) ~= nil,
    "malformed cosmetic data must not reject a person")

-- Exercise the production shared speech executor; old native builds remain
-- white, while any rejected/throwing modern call is final and never replayed.
local record = { id = "sc-speaking", speechColorKey = "rose" }
SC.Registry = { idOf = function() return record.id end, byId = function() return record end }
SC.Actor = { isCompanion = function(actor) return actor.owned == true end }
local mode = "speaker"
SC.UserOptions = { get = function() return mode end }
local fallback, calls = 0, 0
local actor = { owned = true }
function actor:isAsleep() return self.asleep == true end
function actor:addLineChatElement() fallback = fallback + 1 end
function actor:emitCompanionSpeech(text, cr, cg, cb, duration)
    calls = calls + 1
    self.emitted = { text, cr, cg, cb, duration }
    return true
end
check(U.say(actor, "Hello") and calls == 1 and fallback == 0, "one modern emission")
check(actor.emitted[2] == 242 / 255 and actor.emitted[3] == 184 / 255
    and actor.emitted[5] >= 8000, "production speech uses speaker RGB and readable duration")
mode = "white"
check(U.say(actor, "White") and actor.emitted[2] == 1 and actor.emitted[3] == 1
    and record.speechColorKey == "rose", "white option preserves the saved choice")
mode = "speaker"
check(U.say(actor, "Colour again") and actor.emitted[3] == 184 / 255, "switching back restores colour")
actor.asleep = true
local prior = calls
check(not U.say(actor, "Sleeping") and calls == prior, "sleep rejected before emission")
actor.asleep = false
actor.emitCompanionSpeech = function() return false end
check(not U.say(actor, "Rejected") and fallback == 0, "rejection must never replay")
actor.emitCompanionSpeech = function() error("after partial emission") end
check(not U.say(actor, "Throws") and fallback == 0, "exceptions must never replay")
actor.emitCompanionSpeech = nil
check(U.say(actor, "Older bridge") and fallback == 1, "older bridge keeps white speech")
check(not U.say({ owned = false }, "Real player"), "the real player and foreign actors retain ownership")
SC_TEST_REPORT = "Speech colours PASS: " .. checks .. " checks"
