-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local Wade, F = SC.OddballWade, SC.WadeFixture
local group, wade, player, witness = F.group, F.wade, F.player, F.witness
local story = group.oddball

local function events(kind, detail)
    local count, latest = 0, nil
    for _, event in ipairs(F.events) do
        if event.kind == kind and (detail == nil or event.detail == detail) then
            count, latest = count + 1, event.detail
        end
    end
    return count, latest
end

local function latestSpeech(fragment)
    local _, line = events("say")
    return line and string.find(line, fragment, 1, true) ~= nil
end

local kit = {
    finite = function(value) return type(value) == "number" and value > -math.huge and value < math.huge end,
    fail = function(path, message) return false, path .. " " .. message end,
}

assert(F.radio.id == "wade_hensley" and F.radio.module == "OddballWade"
    and F.radio.labels.mapLabel == "Wade's fishing camp")
F.bankReady = false
assert(not Wade.onSpawn(group, wade) and story.rodId == nil and not story.radioSeeded)
F.bankReady = true
assert(Wade.onSpawn(group, wade) and Wade.onSpawn(group, wade) and story.radioSeeded
    and F.owned(wade, "Base.WalkieTalkie2") == 1 and F.rod.data.fishing_LineCondition == 0,
    "Wade starts with one powered radio and an unrigged rod")

local first = assert(Wade.radioOffer(group, player, 100))
assert(first.frequency == 90000 and first.text:find("red canoe", 1, true))
assert(Wade.radioOffer(group, player, 90099) == nil, "Wade repeated his call before the cooldown")
local reminder = assert(Wade.radioOffer(group, player, 90100))
assert(reminder.frequency == first.frequency and reminder.text ~= first.text
    and reminder.text:find("Wade again", 1, true), "Wade repeated the opening call instead of the reminder")
local answered, action, reply = Wade.radioRespond(group, player)
assert(answered and action == "wade_bank_marked" and reply:find("mark the bend", 1, true) and group.discovered)
story.radioAnswered = true -- The transport sets this after the response commits.
assert(not Wade.radioRespond(group, player) and Wade.radioOffer(group, player, 181000) == nil)

assert(F.pulse(group, player, 200000) and story.greeted and latestSpeech("My last line"))
local option = assert(Wade.menuOptions(group, player)[1])
assert(option.id == "offer_line" and not option.enabled and option.detail == "UI_SC_Wade_LineMissing")
assert(not Wade.action(group, "offer_line", player), "Wade accepted no spool")
local empty = F.add(player.inventory, "Base.PremiumFishingLine", 0)
assert(not Wade.menuOptions(group, player)[1].enabled and not Wade.action(group, "offer_line", player),
    "Wade accepted an empty spool")
local line = F.add(player.inventory, "Base.FishingLine", 0.7)
local spareLine = F.add(player.inventory, "Base.PremiumFishingLine", 1)
assert(Wade.menuOptions(group, player)[1].enabled)
player.z = 1
assert(#Wade.menuOptions(group, player) == 0 and not Wade.action(group, "offer_line", player))
player.z = 0
F.blockTransfer = line
assert(not Wade.action(group, "offer_line", player) and story.stage == "unmet" and story.lineId == nil)
F.blockTransfer = nil
assert(Wade.action(group, "offer_line", player) and story.stage == "accepted"
    and story.playerSlot == player.slot and F.find(wade, story.lineId) == line
    and F.owned(player, "Base.PremiumFishingLine") == 2 and events("transfer", line) == 1,
    "Wade did not take exactly the first usable spool")
assert(empty.container == player.inventory and spareLine.container == player.inventory
    and not Wade.action(group, "offer_line", player) and events("transfer") == 1)

assert(F.pulse(group, player, 201000) and latestSpeech("Let me thread it") and F.cast == nil)
assert(F.pulse(group, player, 201250) and F.cast == nil, "Wade cast over his rigging line")
assert(F.pulse(group, player, 201500) and F.cast and story.stage == "accepted")
assert(F.rod.data.fishing_LineCondition == 0.7 and events("rig", line) == 1
    and events("rig", F.hook) == 1 and events("rig", F.worm) == 1)
local fillet = assert(F.find(wade, story.filletId))
assert(fillet.kind == "Base.FishFillet" and F.owned(wade, "Base.SmallmouthBass") == 0)

local firstCast = F.cast
firstCast.callback(wade, firstCast.token .. "-foreign")
assert(story.stage == "accepted", "a foreign callback claimed Wade's catch")
player.x = 25
assert(F.pulse(group, player, 202000) and events("cancel-cast", "wade_witness_left") == 1)
player.x = 13
assert(F.pulse(group, player, 202500) and F.cast ~= firstCast and events("rig", line) == 1)
firstCast.callback(wade, firstCast.token)
assert(story.stage == "accepted", "a cancelled cast could still claim Wade's catch")

F.cast.phase, F.cast.didHook = "hooked", true
F.cast.callback(wade, F.cast.token)
assert(story.stage == "hooked", "the stock hook callback did not advance the saved story")
assert(F.pulse(group, player, 203000) and story.stage == "hooked" and story.bassId == nil,
    "the authored catch appeared before its native pose finished")
assert(Wade.storyRules.validate(story, "$.wade", kit))

-- A cold save keeps only the authored catch receipt and the issued inventory.
-- No native cast or Lua callback can be recovered from the old process.
group, F.cast = F.clone(group), nil
story = group.oddball
assert(Wade.onSpawn(group, wade) and F.owned(wade, "Base.WalkieTalkie2") == 1)
local otherBass = F.add(wade.inventory, "Base.SmallmouthBass")
local otherFillet = F.add(wade.inventory, "Base.FishFillet")
F.state.immediateCount = 1
assert(F.pulse(group, player, 204000) and story.stage == "hooked" and story.bassId == nil)
F.state.immediateCount = 0
assert(F.pulse(group, player, 205000) and story.stage == "release" and latestSpeech("There's my lure"),
    "the saved hook could not resume without native cast state")
local bass, lure = assert(F.find(wade, story.bassId)), assert(F.find(wade, story.lureId))
assert(bass ~= otherBass and bass.kind == "Base.SmallmouthBass" and lure.kind == "Base.JigLure"
    and F.find(wade, story.filletId) == fillet and events("cast") == 2,
    "reloading a hooked fish recast or changed its exact inventory receipts")
assert(F.pulse(group, player, 205250) and story.stage == "release" and events("release-attempt") == 0,
    "the bass release interrupted the lure line")

F.blockRelease = bass
assert(not F.pulse(group, player, 205500) and story.stage == "release" and events("sound") == 0)
F.blockRelease = nil
assert(F.pulse(group, player, 205750) and story.stage == "supper" and latestSpeech("are even now")
    and events("sound", "LureHitWater") == 1 and F.owned(wade, "Base.SmallmouthBass") == 1
    and otherBass.container == wade.inventory and lure.container == wade.inventory,
    "Wade must release the exact bass once and keep the recovered lure")
assert(F.pulse(group, player, 206000) and story.stage == "supper" and F.owned(player, "Base.FishFillet") == 0,
    "the supper interrupted the separate release line")

player.x = 21
assert(F.pulse(group, witness, 206500) and story.stage == "supper" and #witness.inventory == 0)
player.x = 13
F.blockTransfer = fillet
assert(not F.pulse(group, player, 207000) and story.stage == "supper" and F.owned(player, "Base.FishFillet") == 0)
F.blockTransfer = nil
-- Complete the exact transfer before its saved stage flag. Retry must recognize
-- that item in the donor's inventory and must not replace it with another fillet.
assert(SC.GameplayUtil.transferItemVerified(wade.inventory, player.inventory, fillet))
assert(F.pulse(group, player, 207500) and story.stage == "complete" and latestSpeech("Cleaned this one")
    and F.find(player, story.filletId) == fillet and events("transfer", fillet) == 1
    and F.owned(player, "Base.FishFillet") == 1 and otherFillet.container == wade.inventory,
    "the reward must reconcile the exact already delivered fillet")
assert(Wade.storyRules.validate(story, "$.wade", kit))
local malformed = F.clone(story)
malformed.lureId = "wrong"
assert(not Wade.storyRules.validate(malformed, "$.wade", kit), "invalid saved item receipt was admitted")

assert(F.pulse(group, player, 208500) and not story.laterGreeted)
player.x = 26
assert(F.pulse(group, player, 209000) and story.leftAfterSupper and not story.laterGreeted)
player.x = 13
assert(F.pulse(group, player, 210000) and story.laterGreeted and latestSpeech("Sit if you like"))
player.x = 26
assert(F.pulse(group, player, 211000))
player.x = 13
assert(F.pulse(F.clone(group), player, 212000) and events("say", "I'll be here awhile. Sit if you like.") == 1,
    "Wade's later invitation played again after save restore")
print("WADE_STORY_PASS")
