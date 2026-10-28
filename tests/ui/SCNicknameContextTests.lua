-- SPDX-License-Identifier: MIT
local T, SC = MEDICAL_CONTEXT_TEST, SurvivorCompanion
local subject = T.patient
local directCalls, sharedCalls = 0, 0
local dialogueAccepts = false
function subject:Say() directCalls = directCalls + 1 end
SC.Names = {
    normalize = function(value) return value end,
    setNickname = function(record, value)
        record.nickname = { text = value, likes = true }
        return true
    end,
}
SC.Dialogue = {
    has = function() return true end,
    say = function() return dialogueAccepts end,
}
SC.GameplayUtil.say = function(actor, line)
    sharedCalls = sharedCalls + 1
    if actor.asleep then return false end
    actor.lastSpeech = line
    return true
end
local row = { id = subject.id, actor = subject }
local button = { internal = "OK", parent = {
    entry = { getText = function() return "Doc" end },
} }
subject.asleep = true
SC.UIContext.onNicknameTextBox(nil, button, row, T.doctor)
T.check(T.records[subject.id].nickname.text == "Doc" and subject.lastSpeech == nil
        and directCalls == 0 and sharedCalls == 1,
    "a sleeping companion accepts its nickname without bypassing the shared speech gate")
subject.asleep = false
SC.UIContext.onNicknameTextBox(nil, button, row, T.doctor)
T.check(subject.lastSpeech == "Doc? Alright. I'll answer to it."
        and directCalls == 0 and sharedCalls == 2,
    "an awake nickname fallback uses actor-local speech")
dialogueAccepts = true
SC.UIContext.onNicknameTextBox(nil, button, row, T.doctor)
T.check(sharedCalls == 2 and directCalls == 0,
    "an accepted dialogue acknowledgement does not get a second fallback line")
SC_TEST_REPORT = "Nickname context speech isolation: " .. T.checks .. " checks passed"
