-- SPDX-License-Identifier: MIT
-- Run after SCNames.lua and SCNicknameLife.lua in the game's Kahlua VM.

local SC = SurvivorCompanion
local hour = 500
local millis = 1000
local records, actors, spoken = {}, {}, {}
local likeHash, failCoin, chanceBlocked = 0, false, false
local settings = { nicknamesEnabled = true, nicknamePlaceChance = 1,
    nicknameCoinCooldownHours = 168, famousNamesakes = false }

getGameTime = function()
    return { getWorldAgeHours = function() return hour end }
end

SC.Config = { get = function(key) return settings[key] end }
SC.GameplayUtil = {
    stableHash = function(value)
        if tostring(value):find(":chance", 1, true) then
            return chanceBlocked and 9999 or 0
        end
        if tostring(value):find(":call", 1, true) then return 0 end
        if tostring(value):find(":likes", 1, true) then return likeHash end
        local result = 0
        for index = 1, #value do
            result = (result * 33 + string.byte(value, index)) % 2147483647
        end
        return result
    end,
    position = function(actor) return actor.x, actor.y end,
    idOf = function(actor) return actor.id end,
    nameOf = function(actor) return actor.name end,
    itemStableId = function(item) return item.stableId end,
    nowMs = function() return millis end,
    call = function(object, method)
        if object and type(object[method]) == "function" then
            return object[method](object), true
        end
        return nil, false
    end,
}
SC.Registry = {
    byId = function(id) return records[id] end,
    idOf = function(actor) return actor and actor.id end,
    records = function()
        local list = {}
        for _, record in pairs(records) do list[#list + 1] = record end
        return list
    end,
}
SC.Dialogue = { say = function(actor, topic, specification, args)
    if topic == "nickname.coin" and failCoin then return false end
    spoken[#spoken + 1] = { actor = actor, topic = topic, args = args }
    return true
end }
local rival = false
SC.Community = { relation = function()
    return { familiarity = 80, opinion = rival and -40 or 50,
        tension = rival and 60 or 0 }
end }
SC.Commands = { peek = function(actor)
    return { trust = 70, bond = 70, combatDoctrine = actor.doctrine }
end }

local function companion(id, first, x, y)
    local actor = { id = id, name = first .. " Test", x = x, y = y }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getPrimaryHandItem() return self.item end
    function actor:getModData() self.data = self.data or {}; return self.data end
    local record = { id = id, actor = actor, identity = { forename = first,
        surname = "Test" }, recruited = true }
    records[id], actors[id] = record, actor
    return actor, record
end

assert(SC.NicknameLife.townAt(10800, 9800) == "Muldraugh")
assert(SC.NicknameLife.townAt(13600, 1800) == "Louisville")
assert(SC.NicknameLife.townAt(9500, 8000) == nil)

local introActor, intro = companion("intro", "Ada", 10800, 9800)
intro.nickname = SC.Names.make("Doc", "intro", true)
local spokenIntro = SC.NicknameLife.onRecruit(introActor)
assert(spokenIntro == true and #spoken == 1 and spoken[1].topic == "nickname.intro")
assert(SC.NicknameLife.onRecruit(introActor) == false and #spoken == 1)

local placeActor, place = companion("place", "Ben", 10800, 9800)
assert(SC.NicknameLife.onRecruit(placeActor) == true)
assert(place.nickname.text == "Muldraugh")
local duplicateActor, duplicate = companion("duplicate", "Cal", 10800, 9800)
assert(SC.NicknameLife.onRecruit(duplicateActor) == false)
assert(duplicate.nickname == nil)

local friendActor, friend = companion("friend", "Dee", 9200, 9200)
local earnedActor, earned = companion("earned", "Eli", 9200, 9200)
assert(SC.NicknameLife.noteEvent(earnedActor, "rescued",
    { patientHealth = 20, crisisKey = "crisis-one" }) == true)
assert(SC.NicknameLife.noteEvent(earnedActor, "rescued",
    { patientHealth = 20, crisisKey = "crisis-one" }) == false)
assert(SC.NicknameLife.noteEvent(earnedActor, "rescued",
    { patientHealth = 20, crisisKey = "crisis-two" }) == true)
assert(earned.nicknameMeta.lastEventKey == "earned.rescued")
assert(earned.nickname == nil)
chanceBlocked = true
assert(SC.NicknameLife.maybeCoin(friendActor, earnedActor, "harness") == true)
chanceBlocked = false
assert(earned.nickname.text == "Nine Lives")
assert(earned.nicknameMeta.offered["earned.rescued"] == true)
assert(spoken[#spoken].topic == "nickname.coin")
assert(SC.NicknameLife.pulse(millis + 2799) == false)
assert(SC.NicknameLife.pulse(millis + 2800) == true)
assert(spoken[#spoken].topic == "nickname.coin.accept")
assert(SC.NicknameLife.maybeCoin(friendActor, earnedActor, "again") == false)

local rejectingSpeaker = companion("rejecter", "Kim", 9200, 9200)
local rejectedActor, rejected = companion("rejected", "Lou", 9200, 9200)
likeHash = 90
assert(SC.NicknameLife.maybeCoin(rejectingSpeaker, rejectedActor, "reject") == true)
assert(rejected.nickname == nil)
local privateKey = SC.Names.privateKey(rejectedActor)
local privateName = records.rejecter.nicknameMeta.private[privateKey]
assert(SC.Names.normalize(privateName) ~= nil)
assert(SC.Names.normalizeMeta(records.rejecter.nicknameMeta).private[privateKey]
    == privateName)
records.rejecter.nicknameMeta = SC.Names.normalizeMeta(records.rejecter.nicknameMeta)
rival = true
assert(SC.Names.callName(rejectingSpeaker, rejectedActor, { salt = "call" })
    == privateName)
assert(SC.Names.callName(friendActor, rejectedActor, { salt = "call" })
    ~= privateName)
rival = false
assert(SC.NicknameLife.pulse(millis + 2800) == true)
assert(spoken[#spoken].topic == "nickname.coin.reject")
likeHash = 0

local blockedSpeaker = companion("blocked-speaker", "Mae", 9200, 9200)
local blockedActor, blocked = companion("blocked", "Ned", 9200, 9200)
assert(SC.NicknameLife.noteEvent(blockedActor, "burn", { verified = true }) == true)
failCoin = true
assert(SC.NicknameLife.maybeCoin(blockedSpeaker, blockedActor, "blocked") == false)
assert(blocked.nicknameMeta.lastEventKey == "earned.burn")
assert(blocked.nicknameMeta.offered["earned.burn"] == nil)
failCoin = false
assert(SC.NicknameLife.maybeCoin(blockedSpeaker, blockedActor, "retry") == true)
assert(blocked.nickname.text == "Toast")

local failedOfferSpeaker = companion("failed-offer-speaker", "Ona", 9200, 9200)
local failedOfferActor, failedOffer = companion("failed-offer", "Pia", 9200, 9200)
assert(SC.NicknameLife.noteEvent(failedOfferActor, "burn", { verified = true }) == true)
local originalOffer = SC.Names.offer
SC.Names.offer = function() return false, "forced_offer_failure" end
assert(SC.NicknameLife.maybeCoin(failedOfferSpeaker, failedOfferActor,
    "offer-failure") == false)
SC.Names.offer = originalOffer
assert(failedOffer.nickname == nil)
assert(failedOffer.nicknameMeta.lastEventKey == "earned.burn")
assert(failedOffer.nicknameMeta.offered["earned.burn"] == nil)

local player = { id = "player", name = "Player Test" }
function player:getModData() self.data = self.data or {}; return self.data end
getPlayer = function() return player end
hour = 900
assert(SC.NicknameLife.maybeCoin(friendActor, player, "player") == true)
assert(SC.Names.normalize(player.data.SC_PlayerNickname) ~= nil)

local killerActor, killer = companion("killer", "Fran", 9200, 9200)
killerActor.item = { stableId = "same-pan",
    getFullType = function() return "Base.FryingPan" end }
for _ = 1, 25 do assert(SC.NicknameLife.noteKill(killerActor, nil, 999999) == true) end
assert(killer.nicknameMeta.lastEventKey == "earned.pan")
assert(killer.nickname == nil)

local reaperActor, reaper = companion("reaper", "Gia", 9200, 9200)
for _ = 1, 50 do assert(SC.NicknameLife.noteKill(reaperActor, nil) == true) end
assert(reaper.nicknameMeta.lastEventKey == "earned.reaper")

local fishActor, fish = companion("fish", "Hal", 9200, 9200)
assert(SC.NicknameLife.noteEvent(fishActor, "fish", { size = 12.5 }) == true)
assert(fish.nicknameMeta.lastEventKey == "earned.fish")
local smallerActor, smaller = companion("smaller", "Ian", 9200, 9200)
assert(SC.NicknameLife.noteEvent(smallerActor, "fish", { size = 12.4 }) == false)
assert(smaller.nicknameMeta.lastEventKey == nil)

local stealthActor, stealth = companion("stealth", "Jay", 9200, 9200)
stealthActor.doctrine = "stealth"
for _ = 1, 25 do assert(SC.NicknameLife.noteKill(stealthActor, nil) == true) end
assert(stealth.nicknameMeta.lastEventKey == "earned.stealth")

print("nickname life harness passed")
