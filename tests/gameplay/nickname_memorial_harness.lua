-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Community = SC.Community
local survivor = SC_TEST_NICKNAME_SURVIVOR
local stranger = SC_TEST_NICKNAME_STRANGER
local fallen = {
    id = "sc-fallen", recruited = true,
    identity = { forename = "Sarah", surname = "Shaw", gender = "female" },
}
assert(SC.Names.setNickname(fallen, "Doc", "player") == true)
-- Freeze each survivor's own established address at death, before the actor
-- and its nickname can disappear from the registry.
local originalCallName = SC.Names.callName
SC.Names.callName = function(speaker, listener, context)
    if listener == fallen and context and context.about then
        return speaker == survivor and "Doc" or "Sarah"
    end
    return originalCallName(speaker, listener, context)
end
local noted, result = Community.noteCompanionDeath(fallen)
SC.Names.callName = originalCallName
assert(noted == true and result.affected == 2, "recruited death must create grief")
assert(result.subjectName == "Sarah Shaw"
    and result.subjectDisplayName == 'Sarah "Doc" Shaw',
    "death result keeps raw identity and decorated display separate")

local id, death = Community.deathMatching("Sarah Shaw")
assert(id == fallen.id and death.subjectName == "Sarah Shaw"
    and death.subjectDisplayName == 'Sarah "Doc" Shaw',
    "corpse matching uses raw descriptor name and exposes the grave label")
assert(Community.deathMatching('Sarah "Doc" Shaw') == nil,
    "decorated label must never identify a corpse")

local grief = Community.activeGrief(survivor)
assert(grief and grief.subjectName == "Sarah Shaw"
    and grief.subjectDisplayName == 'Sarah "Doc" Shaw',
    "mourning exposes the decorated name without changing the identity key")
assert(grief.subjectCallName == "Doc" and grief.subjectNicknameUsed == true,
    "established nickname is frozen for the survivor who used it")
local strangerGrief = Community.activeGrief(stranger)
assert(strangerGrief.subjectCallName == "Sarah"
    and strangerGrief.subjectNicknameUsed == false,
    "the same death keeps the first name for a survivor who never used Doc")
local mind = Community.peekMind(survivor)
assert(mind.thoughts[1].text == 'Sarah "Doc" Shaw died. I am still trying to take that in.',
    "mourning text names the fallen companion with their nickname")

local saved = Community.export()
assert(Community.restore(saved) == true, "decorated death state round trips")
local restored = Community.activeGrief(survivor)
assert(restored.subjectDisplayName == 'Sarah "Doc" Shaw'
    and restored.subjectCallName == "Doc"
    and restored.subjectNicknameUsed == true
    and select(2, Community.deathMatching("Sarah Shaw")).subjectDisplayName
        == 'Sarah "Doc" Shaw', "grief and grave labels survive restore")

-- Old saves have only subjectName. Their matching and visible labels remain safe.
saved.deaths[fallen.id].subjectDisplayName = nil
saved.minds[survivor.id].grief[1].subjectDisplayName = nil
saved.minds[survivor.id].grief[1].subjectCallName = nil
saved.minds[survivor.id].grief[1].subjectNicknameUsed = nil
assert(Community.restore(saved) == true, "legacy death state restores")
local legacy = Community.activeGrief(survivor)
local _, legacyDeath = Community.deathMatching("Sarah Shaw")
assert(legacy.subjectName == "Sarah Shaw" and legacy.subjectDisplayName == "Sarah Shaw"
    and legacy.subjectCallName == "Sarah" and legacy.subjectNicknameUsed == false
    and legacyDeath.subjectDisplayName == "Sarah Shaw",
    "legacy grief and grave labels fall back to the raw full name")

print("NICKNAME_MEMORIAL_KAHLUA_PASS checks=11")
