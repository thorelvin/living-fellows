-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local Names = SC.Names
local settings = {
    nicknamesEnabled = true, nicknameMaxLength = 16,
    nicknameIntroChance = 1, nicknameAddressChance = 0.4,
    nicknameFamiliarity = 25, nicknameFriendlyOpinion = 15,
    nicknameRivalTension = 50, nicknameFamiliarForm = 60,
}
SC.Config = { get = function(key) return settings[key] end }
SC.GameplayUtil = {
    stableHash = function(value)
        return tostring(value):find(":player:Patch", 1, true) and 99 or 100
    end,
    call = function(actor, name, ...)
        local method = actor and actor[name]
        if type(method) ~= "function" then return nil, false end
        return method(actor, ...), true
    end,
}
local records = {}
SC.Registry = {
    byId = function(id) return records[id] end,
    idOf = function(actor) return actor and actor.id end,
}
local relation = { familiarity = 30, opinion = 20, tension = 0 }
SC.Community = { relation = function() return relation end }

assert(Names.normalize(" 10K ") == "10K")
assert(Names.normalize("Fix-It") == "Fix-It")
assert(Names.normalize("Mall Cop") == "Mall Cop")
assert(Names.normalize("") == nil)
assert(Names.normalize("%1") == nil)
assert(Names.normalize("A\nB") == nil)
assert(Names.normalize("12345678901234567") == nil)
assert(Names.normalizeRecord({ text = "Doc", source = "intro", since = "bad" }) == nil)

local sarah = { id = "sarah", identity = { forename = "Sarah", surname = "Shaw" } }
records.sarah = sarah
assert(Names.displayName(sarah) == "Sarah Shaw")
local set, reason, nickname = Names.setNickname(sarah, "Doc", "player")
assert(set and reason == "nickname_set" and nickname.text == "Doc")
assert(Names.displayName(sarah) == 'Sarah "Doc" Shaw')
assert(Names.displayName(sarah, false) == "Sarah Shaw")
assert(Names.callName("friend", sarah, { salt = "one" }) == "Doc")
assert(Names.callName("friend", sarah, { urgent = true }) == "Doc")
assert(Names.callName("friend", sarah, { about = true }) == "Sarah")
assert(Names.callName("friend", sarah, { about = true, usedBefore = true }) == "Doc")

local witness = { id = "witness",
    identity = { forename = "Tess", surname = "Baker" } }
records.witness = witness
assert(Names.callName(witness, sarah, { about = true }) == "Sarah")
assert(Names.callName(witness, sarah, { salt = "spoken" }) == "Doc")
assert(Names.callName(witness, sarah, { about = true }) == "Doc")
local savedUsage = Names.normalizeMeta(witness.nicknameMeta)
assert(savedUsage.used[Names.privateKey(sarah)] == "Doc")
witness.nicknameMeta = savedUsage
assert(Names.callName(witness, sarah, { about = true }) == "Doc")
assert(Names.setNickname(sarah, "Patches", "player") == true)
assert(Names.callName(witness, sarah, { about = true }) == "Sarah")
assert(Names.setNickname(sarah, "Doc", "player") == true)
assert(Names.setNickname(sarah, "Patch", "player") == true)
assert(sarah.nickname.likes == false)
assert(Names.displayName(sarah) == 'Sarah "Patch" Shaw')
assert(Names.setNickname(sarah, "Doc", "player") == true)

relation.tension = 70
assert(Names.callName("rival", sarah) == "Shaw")
sarah.nickname.likes = false
assert(Names.callName("rival", sarah) == "Doc")
relation.tension = 0
assert(Names.callName("friend", sarah) == "Sarah")
assert(Names.offer(sarah, "Patches", "earned") == false)

local player = { id = "player", modData = {} }
function player:getModData() return self.modData end
function player:getDescriptor()
    return { getForename = function() return "Jamie" end,
        getSurname = function() return "Taylor" end }
end
assert(Names.setPlayerNickname(player, "Roadrunner") == true)
assert(player.modData.SC_PlayerNickname == "Roadrunner")
assert(Names.callName("sarah", player) == "Roadrunner")
assert(Names.clearPlayerNickname(player) == true)
assert(Names.callName("sarah", player) == "Jamie")
assert(Names.setPlayerNickname(player, "%1") == false)
assert(Names.clearNickname(sarah) == true)
assert(Names.offer(sarah, "Patches", "earned") == true)
assert(sarah.nickname.source == "earned")
assert(Names.setNickname(sarah, "%1", "player") == false)
assert(Names.setNickname(sarah, "Nurse", "player") == true)
assert(Names.offer(sarah, "Patches", "earned") == false)

settings.nicknamesEnabled = false
assert(Names.callName("friend", sarah) == "Sarah")
assert(Names.displayName(sarah) == "Sarah Shaw")
settings.nicknamesEnabled = true

local profile = {
    id = "new-doctor", identity = { forename = "Rose", surname = "Baker" },
    state = { personality = { background = { profession = "doctor" } } },
}
local introduced = Names.ensureIntro(profile)
assert(introduced and introduced.source == "intro"
    and (introduced.text == "Doc" or introduced.text == "Scalpel"))
assert(Names.ensureIntro(profile).text == introduced.text)
local restored = { id = "old-doctor", restored = true,
    identity = { forename = "June", surname = "Baker" },
    state = profile.state }
assert(Names.ensureIntro(restored) == nil and restored.nickname == nil)

print("names_harness: OK")
