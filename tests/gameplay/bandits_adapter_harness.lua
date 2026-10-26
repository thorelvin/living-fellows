-- SPDX-License-Identifier: MIT
local A, SC = SurvivorCompanion.BanditsAdapter, SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "Bandits adapter check " .. checks .. ": " .. message)
end
local first, second = BANDITS_TEST_ACTOR("sc-bandits-first"), BANDITS_TEST_ACTOR("sc-bandits-second")
local originalID, originalList = BanditUtils.GetCharacterID, BanditPlayer.GetPlayers
local originalCommand, originalModel = sendClientCommand, PlayerDamageModel.BulletHit
check(originalID(first) == originalID(BANDITS_TEST_PLAYER), "foreign SP identity collision is reproduced")
check(A.initialize() and A.status().active, "available core profile activates")
check(BanditUtils.GetCharacterID(BANDITS_TEST_PLAYER) == 1, "real player identity preserved")
check(BanditUtils.GetCharacterID(first) == "lf:sc-bandits-first", "persistent namespaced alias")
check(BanditUtils.GetCharacterID(first) ~= BanditUtils.GetCharacterID(second), "NPC aliases differ")
check(BanditPlayer.GetPlayerById("lf:sc-bandits-first") == first, "NPC attack target resolves")
check(BanditPlayer.GetPlayerById(1) == BANDITS_TEST_PLAYER, "real target lookup unchanged")
check(BanditPlayer.GetPlayerById("lf:sc-does-not-exist") == nil, "unknown alias never becomes the player")
local view = BanditPlayer.GetPlayers()
check(view ~= BANDITS_TEST_REAL_LIST and view:size() == 3, "foreign list is a separate derived view")
check(BANDITS_TEST_REAL_LIST:size() == 1, "engine list is untouched")
check(BanditPlayer.GetPlayers() == view and A.status().listBuilds == 1, "hot queries share the view")
-- PZ can expose a fresh ArrayList wrapper for the same four player slots.
local sourceList, freshWrapper = BANDITS_TEST_REAL_LIST, ArrayList.new()
for index = 0, sourceList:size() - 1 do freshWrapper:add(sourceList:get(index)) end
BANDITS_TEST_REAL_LIST = freshWrapper
check(BanditPlayer.GetPlayers() == view and A.status().listBuilds == 1,
    "fresh native wrappers with identical slot membership do not rebuild the view")
SC.State = { active = false }
check(not A.status().active and BanditPlayer.GetPlayers():size() == 1 and A.resolve(A.idFor(first)) == nil,
    "a stopped LF runtime disables combat while retaining safe identities")
SC.State.active = true
check(BanditPlayer.GetPlayers():size() == 3, "runtime activation invalidates the derived view")
BANDITS_TEST_REAL_LIST:add(first)
SC_TEST_CLOCK = SC_TEST_CLOCK + 251
check(BanditPlayer.GetPlayers():size() == 3, "owned second-view leader is deduplicated")
local wrapperID = BanditUtils.GetCharacterID
check(A.initialize() and BanditUtils.GetCharacterID == wrapperID, "initialization is idempotent")
local enemy, friendly = BANDITS_TEST_ACTOR(), BANDITS_TEST_ACTOR()
enemy.bandit, friendly.bandit = true, true
enemy.md.brain = { id = 40, clan = "raiders", program = {}, hostile = true, hostileP = false }
friendly.md.brain = { id = 41, clan = "locals", program = {}, hostile = false, hostileP = false }
BanditZombie.Cache[40], BanditZombie.Cache[41] = enemy, friendly
check(A.owns(enemy) and A.relationship(enemy, first) == "hostile", "hostile human recognition")
check(A.relationship(friendly, first) == "neutral", "friendlies are protected, not party allies")
local incomplete = BANDITS_TEST_ACTOR()
incomplete.bandit = true
check(A.owns(incomplete) and A.relationship(incomplete, first) == "unknown", "initializing Bandit remains protected")
local zombie = BANDITS_TEST_ACTOR()
zombie.md.brain = { id = 42, clan = 2, program = {} }
check(not A.owns(zombie), "another mod's brain alone is not ownership")
BanditZombie.Cache[42] = zombie
check(A.owns(zombie), "verified early brain/cache identity recognized")
zombie.md.brain = nil
check(not A.owns(zombie), "zombified/reused actor loses foreign human ownership")
local r1, r2, r3 = PlayerDamageModel.BulletHit(enemy, { damage = 8 }, first)
check(r1 == "landed" and r2 == nil and r3 == 9, "all callback return values preserved")
check(first.damage == 8 and first.wound and not BANDITS_TEST_PLAYER.damage, "native request reaches only NPC victim")
check(sendClientCommand == originalCommand and #BANDITS_TEST_COMMANDS == 0, "NPC damage never sends a player command")
PlayerDamageModel.MeleeHit(enemy, second, { damage = 12 })
PlayerDamageModel.BareHandHit(enemy, second)
check(second.damage == 15 and A.status().routedDamage == 3, "all three model signatures route once")
PlayerDamageModel.BulletHit(enemy, { damage = 5 }, BANDITS_TEST_PLAYER)
check(#BANDITS_TEST_COMMANDS == 1 and BANDITS_TEST_COMMANDS[1][1] == BANDITS_TEST_PLAYER,
    "actual player commands retain their original path")
first.god = true
PlayerDamageModel.BulletHit(enemy, { damage = 30 }, first)
check(first.damage == 8 and A.resolve(A.idFor(first)) == nil, "explicit immunity is respected")
first.god = false
BanditZombie.CacheLightB[41] = { x = 5, y = 5 }
local c1, c2, c3 = BanditPlayer.CheckFriendlyFire(friendly, first)
check(friendly.md.brain.hostileP and friendly.syncCount == 1, "confirmed NPC attack escalates using foreign APIs")
check(c1 == "original" and c2 == nil and c3 == 7, "friendly-fire hook retains original returns")
first.dead = true
check(A.resolve(A.idFor(first)) == nil, "dead target cannot resolve")
SC_TEST_CLOCK = SC_TEST_CLOCK + 251
check(BanditPlayer.GetPlayers():size() == 2, "dead owned slot entry is removed from derived view")
first.dead = false
BANDITS_TEST_REMOVE(first)
check(BanditPlayer.GetPlayerById("lf:sc-bandits-first") == nil, "despawn removes resolution immediately")
check(BanditUtils.GetCharacterID(first) == "lf:sc-bandits-first", "stale reference retains collision-safe tombstone")
local restored = BANDITS_TEST_ACTOR("sc-bandits-first")
check(A.resolve("lf:sc-bandits-first") == restored and A.resolve(A.idFor(first)) ~= first,
    "reload reconstructs the alias from the current native actor, never an old instance")
BANDITS_TEST_REMOVE(restored)
check(A.status().bulletHits == 1 and A.status().meleeHits == 1 and A.status().bareHandHits == 1,
    "diagnostics identify the stock damage models without additional health deductions")
SC.UserOptions.get = function() return false end
check(not A.initialize() and A.status().state == "disabled", "Off disables combat integration")
check(A.owns(enemy), "Off retains human classification for enabled Bandits")
check(A.resolve(A.idFor(second)) == nil and BanditPlayer.GetPlayers():size() == 1,
    "Off conceals NPCs, including an owned view slot, while retaining identity safety")
PlayerDamageModel.BulletHit(enemy, { damage = 30 }, second)
check(second.damage == 15 and sendClientCommand == originalCommand, "Off cannot misroute NPC wounds")
SC.UserOptions.get = function() return true end
check(A.initialize(), "integration can re-enable")
check(A.reset() and BanditUtils.GetCharacterID == originalID and BanditPlayer.GetPlayers == originalList,
    "world reset restores only owned bindings")

-- Nested damage and failures must restore the global command binding even if
-- foreign callbacks raise after committing an effect; never replay a model.
local nestedCalls = 0
PlayerDamageModel.BulletHit = function(shooter, weapon, victim)
    PlayerDamageModel.BareHandHit(shooter, second)
    sendClientCommand(victim, "OtherMod", "Unrelated", {})
    sendClientCommand(victim, "Commands", "PlayerDamage", { healthDrop = 4 })
    nestedCalls = nestedCalls + 1
    error("model failed after native commit")
end
local third = BANDITS_TEST_ACTOR("sc-bandits-third")
check(A.initialize(), "new world binds the current foreign chain")
local beforeSecond, beforeCommands = second.damage, #BANDITS_TEST_COMMANDS
local okay = pcall(PlayerDamageModel.BulletHit, enemy, {}, third)
check(not okay and nestedCalls == 1 and third.damage == 4, "post-commit error does not replay damage")
check(second.damage == beforeSecond + 3, "nested callback routes its own victim")
check(sendClientCommand == originalCommand, "nested failure restores command binding")
check(#BANDITS_TEST_COMMANDS == beforeCommands + 1
    and BANDITS_TEST_COMMANDS[#BANDITS_TEST_COMMANDS][2] == "OtherMod", "unrelated commands are delegated")
A.reset()
PlayerDamageModel.BulletHit = function(shooter, weapon, victim)
    victim.god = true
    sendClientCommand(victim, "Commands", "PlayerDamage", { healthDrop = 99 })
end
check(A.initialize(), "application-time protection fixture binds")
local priorDamage = third.damage
PlayerDamageModel.BulletHit(enemy, {}, third)
check(third.damage == priorDamage and sendClientCommand == originalCommand,
    "immunity gained during a callback is revalidated before applying damage")
third.god = false
A.reset()
PlayerDamageModel.BulletHit = function(shooter, weapon, victim)
    BANDITS_TEST_REMOVE(victim)
    sendClientCommand(victim, "Commands", "PlayerDamage", { healthDrop = 99 })
end
check(A.initialize(), "application-time despawn fixture binds")
PlayerDamageModel.BulletHit(enemy, {}, third)
check(third.damage == priorDamage and sendClientCommand == originalCommand,
    "an actor removed during a model callback cannot receive damage or fall through to the main player")
A.reset()
PlayerDamageModel.BulletHit = originalModel
BANDITS_TEST_MODS.Bandits2 = nil
check(not A.initialize() and A.status().state == "absent", "absent optional dependency is inert")
BANDITS_TEST_MODS.Bandits2 = true
local savedHandler = BanditServer.Commands.PlayerDamage
BanditServer.Commands.PlayerDamage = nil
check(not A.initialize() and A.status().state == "unsupported", "missing damage capability fails closed")
check(BanditUtils.GetCharacterID(second) == "lf:sc-bandits-second"
    and BanditPlayer.GetPlayers():size() == 1 and A.resolve(A.idFor(second)) == nil,
    "unsupported activation retains identity guards without exposing NPC combat targets")
BanditServer.Commands.PlayerDamage = savedHandler
isClient = function() return true end
check(not A.initialize() and A.status().state == "unsupported", "multiplayer profile is rejected")
isClient = function() return false end
check(A.initialize(), "load order retry succeeds when dependencies are ready")
local outer = function(actor) return wrapperID(actor) end
BanditUtils.GetCharacterID = outer
check(not A.initialize() and A.status().state == "unsupported", "changed hooks are diagnosed")
A.reset()
check(BanditUtils.GetCharacterID == outer, "teardown does not erase another mod's replacement")
SC_TEST_REPORT = "BANDITS_ADAPTER_PASS checks=" .. checks
