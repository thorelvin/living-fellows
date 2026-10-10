-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local banter, tales, gestures = SC.Banter, SC.Tales, SC.Gestures
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "comfort check " .. tostring(checks) .. ": " .. message)
end

local options = { chatter = "normal", coughSneezes = "normal", ordinaryColds = true }
SC.UserOptions = { get = function(key) return options[key] end }
check(banter.chatterMultiplier() == 1, "normal chatter keeps original timing")
options.chatter = "less"
check(banter.chatterMultiplier() == 2, "less chatter doubles incidental cooldowns")
options.chatter = "rare"
check(banter.chatterMultiplier() == 4, "rare chatter quadruples incidental cooldowns")

banter.reset()
local party = banter._partyForTests()
party.lastFlavorAt = 0
check(banter.budgetAllows(20000) and not banter.incidentalBudgetAllows(20000)
        and banter.incidentalBudgetAllows(80000),
    "urgent speech keeps its original budget while incidental speech waits longer")

local _, campConversation, advanceExchange = banter._socialForTests()
party.lastFlavorAt = -math.huge
party.lastCampConversationAt = 0
local _, beforeTable = campConversation({}, {}, 239999)
local _, afterTable = campConversation({}, {}, 240000)
check(beforeTable == "camp_conversation_cooldown"
        and afterTable == "camp_conversation_no_pair",
    "table-talk starts use the scaled party cooldown")

local first = { id = "first", commands = { recruited = true } }
local second = { id = "second", commands = { recruited = true } }
party.exchange = {
    first = first, second = second, secondCommands = second.commands,
    replyTopic = "banter.camp.reply", kind = "camp",
    nextAt = 1000, expiresAt = 9000,
}
local replied, replyTopic = advanceExchange({ { actor = first }, { actor = second } }, 1000)
check(replied and replyTopic == "banter.camp.reply"
        and party.exchange == nil,
    "an in-progress conversation replies on its original schedule")

tales.reset()
local taleParty = tales._partyForTests()
taleParty.lastTellAt = 0
local _, beforeTale = tales.update({}, {}, 7199999)
local _, afterTale = tales.update({}, {}, 7200000)
check(beforeTale == "tales_cooldown" and afterTale == "tales_no_teller",
    "rare chatter quadruples the delay before a new tale starts")
taleParty.telling = {
    teller = first, record = { actor = first },
    tale = { kills = 5, tellings = 0 },
    beats = { { actor = first, topic = "tales.body", args = {} } },
    index = 1, nextAt = 1000, spoken = 0,
}
local continued, beat = tales.update({}, {}, 1000)
check(continued and beat == "tales.body" and first.lastTopic == "tales.body",
    "an in-progress tale beat is not delayed by the chatter setting")

options.chatter = "normal"
SC.ComfortTestConfig.sneezeDustyChancePercent = 100
SC.ComfortTestConfig.gestureActorCooldownMs = 0
SC.ComfortTestConfig.gesturePartyGapMs = 0
local actor = { id = "sneezer", commands = { recruited = true }, moves = 0 }
function actor:isMoving() return false end
function actor:isAsleep() return false end
function actor:isSneaking() return false end
function actor:setCompanionSymptomMode(mode) self.symptomMode = mode end
function actor:setCompanionOrdinaryColdsEnabled(enabled) self.coldsEnabled = enabled end
function actor:canCompanionScriptedSymptom()
    if self.symptomMode == "off" then return false end
    local gap = self.symptomMode == "rare" and 300000 or 60000
    return SC.ComfortTestNow - (self.lastSymptomAt or -math.huge) >= gap
end
function actor:noteCompanionScriptedSymptom()
    self.lastSymptomAt = SC.ComfortTestNow
    return true
end
local list = { { actor = actor, recruited = true } }
gestures.reset()
SC.ComfortTestRoom = "storageunit"
SC.ComfortTestNow = 100000
gestures.update(nil, list, SC.ComfortTestNow)
check(#gestures._partyForTests().pending == 1, "dust entry queues one scripted sneeze")
SC.ComfortTestNow = 101500
gestures.update(nil, list, SC.ComfortTestNow)
check(actor.moves == 1 and actor.lastIntent.action == "ext_gesture"
        and actor.lastSymptomAt == 101500,
    "scripted sneeze plays and reserves the shared native symptom interval")

options.coughSneezes = "rare"
SC.ComfortTestNow = 110000
SC.ComfortTestRoom = nil
gestures.update(nil, list, SC.ComfortTestNow)
SC.ComfortTestRoom = "storageunit"
SC.ComfortTestConfig.sneezeDustyChancePercent = 500 -- rare scales this to 100
SC.ComfortTestNow = 110100
gestures.update(nil, list, SC.ComfortTestNow)
SC.ComfortTestNow = 111600
gestures.update(nil, list, SC.ComfortTestNow)
check(actor.moves == 1 and #gestures._partyForTests().pending == 0,
    "rare mode suppresses a scripted sneeze inside its five-minute gap")

SC.ComfortTestRoom = nil
SC.ComfortTestNow = 500000
gestures.update(nil, list, SC.ComfortTestNow)
SC.ComfortTestRoom = "storageunit"
SC.ComfortTestNow = 500100
gestures.update(nil, list, SC.ComfortTestNow)
check(#gestures._partyForTests().pending == 1,
    "a later dusty entry may queue another symptom")
options.coughSneezes = "off"
SC.ComfortTestNow = 500200
gestures.update(nil, list, SC.ComfortTestNow)
check(actor.symptomMode == "off" and #gestures._partyForTests().pending == 0
        and actor.moves == 1,
    "symptom off cancels a queued scripted sneeze immediately")

local body = { catchCold = 12, hasCold = true, strength = 48,
    knox = 73, foodSickness = 9, woundInfection = 4 }
function body:setCatchACold(value) self.catchCold = value end
function body:setHasACold(value) self.hasCold = value end
function body:setColdStrength(value) self.strength = value end
local resident = { id = "resident" }
function resident:getBodyDamage() return body end
options.ordinaryColds = false
gestures.applyNativeOptions({ { actor = resident, recruited = false } })
check(body.catchCold == 0 and body.hasCold == false and body.strength == 0
        and body.knox == 73 and body.foodSickness == 9 and body.woundInfection == 4,
    "cold off clears only an LF actor's ordinary cold, including unrecruited residents")
check(actor.coldsEnabled == true,
    "ordinary-cold option remains independent from cough/sneeze mode")

print("USER_COMFORT_PASS checks=" .. tostring(checks))
