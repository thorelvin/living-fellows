-- SPDX-License-Identifier: MIT
local A, SC = SurvivorCompanion.BanditsAdapter, SurvivorCompanion
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "Bandits hardening check " .. checks .. ": " .. message)
end
local utils, players, models, server, bandits = BanditUtils, BanditPlayer, PlayerDamageModel, BanditServer, Bandit
local originals = { id = utils.GetCharacterID, list = players.GetPlayers, lookup = players.GetPlayerById,
    fire = players.CheckFriendlyFire, bullet = models.BulletHit, melee = models.MeleeHit,
    hand = models.BareHandHit, handler = server.Commands.PlayerDamage, program = bandits.SetProgram }
local command = sendClientCommand
local victim = BANDITS_TEST_ACTOR("sc-hardened-victim")
local enemy = BANDITS_TEST_ACTOR()
enemy.bandit = true
enemy.md.brain = { id = 51, clan = "official", program = {}, hostile = true, hostileP = false }
BanditZombie.Cache[51] = enemy
local function fresh()
    A.reset()
    BanditUtils, BanditPlayer, PlayerDamageModel, BanditServer, Bandit = utils, players, models, server, bandits
    utils.GetCharacterID, players.GetPlayers, players.GetPlayerById = originals.id, originals.list, originals.lookup
    players.CheckFriendlyFire = originals.fire
    models.BulletHit, models.MeleeHit, models.BareHandHit = originals.bullet, originals.melee, originals.hand
    server.Commands.PlayerDamage, bandits.SetProgram = originals.handler, originals.program
    sendClientCommand = command
    SC.State = { active = true }
    SC.UserOptions.get = function() return true end
    BanditZombie.CacheLightB = {}
    victim.damage = 0
    SC_TEST_CLOCK = SC_TEST_CLOCK + 2000
end

fresh()
for _, invalid in ipairs({ false, 7, "not an actor", function() end }) do
    local okay, owned = pcall(A.owns, invalid)
    check(okay and owned == false, "invalid ownership inputs cannot crash perception")
    check(A.idFor(invalid) == nil, "invalid identity input is rejected")
end
check(A.initialize(), "normal profile initializes")
victim.removed = true
check(A.idFor(victim) == "lf:sc-hardened-victim" and A.resolve("lf:sc-hardened-victim") == nil,
    "native removal rejects a retained live-health/square reference before registry notification")
local removedList = players.GetPlayers()
local listedRemoved = false
for index = 0, removedList:size() - 1 do if removedList:get(index) == victim then listedRemoved = true end end
check(not listedRemoved, "despawn gap does not publish the removed actor to Bandits")
models.BulletHit(enemy, { damage = 4 }, victim)
check(victim.damage == 0, "a native-removed actor cannot receive a stock wound during registry cleanup")
victim.removed = false
A.invalidate()
fresh()
players.GetPlayerById = function() return BANDITS_TEST_PLAYER end
check(A.initialize(), "retained fallback lookup fixture initializes")
local retainedLookup = players.GetPlayerById
A.reset()
check(retainedLookup("lf:sc-hardened-victim") == nil,
    "a retired alias lookup cannot fall through another mod's default player fallback")
check(retainedLookup(1) == BANDITS_TEST_PLAYER, "retired lookup preserves ordinary player identities")
check(A.initialize() and retainedLookup("lf:sc-hardened-victim") == nil,
    "a retired lookup cannot resolve aliases in a newly initialized world")
fresh()
check(A.initialize(), "retained damage fixture initializes")
local retainedModel, commandCount = models.BulletHit, #BANDITS_TEST_COMMANDS
A.reset()
local accepted, why = retainedModel(enemy, { damage = 4 }, victim)
check(accepted == false and why == "lf_victim_unavailable" and #BANDITS_TEST_COMMANDS == commandCount,
    "a retired damage wrapper never sends an LF wound through an unrouted player command")
check(retainedModel(enemy, { damage = 4 }, BANDITS_TEST_PLAYER) == "landed"
    and #BANDITS_TEST_COMMANDS == commandCount + 1, "retired damage wrapper preserves real-player calls")
models.BulletHit = function(...) return retainedModel(...) end
check(A.initialize(), "a new world chains another mod retaining the retired model")
local routedBefore = A.status().routedDamage
check(models.BulletHit(enemy, { damage = 4 }, victim) == "landed"
    and victim.damage == 4 and A.status().routedDamage == routedBefore + 1,
    "a fresh scoped wrapper passes through a retired inner model and routes exactly once")
check(retainedModel(enemy, { damage = 4 }, victim) == false and victim.damage == 4,
    "a standalone retained model cannot borrow a completed callback's authority")
fresh()
check(A.initialize(), "normal profile restores after retained-wrapper checks")
local opaqueOkay, opaqueOwned = pcall(A.owns, SC_TEST_JAVA_OBJECT)
check(opaqueOkay and not opaqueOwned and A.idFor(SC_TEST_JAVA_OBJECT) == nil,
    "opaque Java userdata is rejected without exposing it to native actor queries")
local hostileProxy = setmetatable({}, { __index = function() error("uninitialized actor proxy") end })
local proxyOkay, proxyOwned = pcall(A.owns, hostileProxy)
check(proxyOkay and not proxyOwned, "a partial proxy cannot throw from ownership lookup")
enemy.md.brain.tasks = { false }
check(not A.isAttacking(enemy, victim), "partial task initialization is not an attack")
enemy.md.brain.tasks = nil
local brain = enemy.md.brain
enemy.md.brain = { hostile = true, hostileP = false }
check(A.owns(enemy) and A.relationship(enemy, victim) == "unknown",
    "marker protects a partially initialized Bandit without declaring hostility")
enemy.md.brain = brain
local current = BanditZombie.Cache[51]
BanditZombie.Cache[51] = BANDITS_TEST_ACTOR()
check(A.relationship(enemy, victim) == "unknown", "stale brain/cache identity is not a hostile contact")
BanditZombie.Cache[51] = current

-- An outer mod may legitimately retain our old wrapper in its own chain.
local retiredList = players.GetPlayers
players.GetPlayers = function() return retiredList() end
A.reset()
check(retiredList() == originals.list(), "retired list wrapper is inert after world teardown")
A.pulse(SC_TEST_CLOCK)
check(not A.status().active, "a reset stops the watchdog until a new explicit initialization")
check(A.initialize(), "a new world chains the current outer mod")
players.GetPlayers()
local builds = A.status().listBuilds
players.GetPlayers()
check(A.status().listBuilds == builds, "retired inner wrapper cannot rebuild the current cache repeatedly")

fresh()
local heldUtils = BanditUtils
BanditUtils = nil
check(not A.initialize(), "deferred dependency is initially unavailable")
BanditUtils = heldUtils
A.pulse(SC_TEST_CLOCK)
check(A.status().active, "runtime pulse activates a late dependency without toggling options")
local replacement = { GetPlayers = originals.list, GetPlayerById = originals.lookup,
    CheckFriendlyFire = originals.fire }
BanditPlayer = replacement
SC_TEST_CLOCK = SC_TEST_CLOCK + 1001
A.pulse(SC_TEST_CLOCK)
check(not A.status().active and A.status().state == "unsupported", "replaced interface owner is detected")
check(replacement.GetPlayers == originals.list, "watchdog never overwrites another mod's replacement")

fresh()
check(A.initialize(), "damage handler drift fixture initializes")
server.Commands.PlayerDamage = nil
local okay = pcall(models.BulletHit, enemy, { damage = 9 }, victim)
check(okay and victim.damage == 0 and not A.status().active, "lost damage handler rejects the wound safely")
check(sendClientCommand == command, "handler loss restores command routing")
server.Commands.PlayerDamage = originals.handler
SC_TEST_CLOCK = SC_TEST_CLOCK + 1001
A.pulse(SC_TEST_CLOCK)
check(A.status().active, "restored required interface is automatically revalidated")
models.BulletHit(enemy, { damage = 2 }, victim)
check(A.isAttacking(enemy, victim) and A.status().lastVictim == "lf:sc-hardened-victim"
    and A.status().lastModel == "BulletHit", "damage receipt identifies its exact victim and model")
enemy.dead = true
check(not A.isAttacking(enemy, victim), "a dead Bandit cannot sustain a remembered attack")
enemy.dead = false
SC_TEST_CLOCK = SC_TEST_CLOCK + 5001
A.pulse(SC_TEST_CLOCK)
check(not A.isAttacking(enemy, victim), "expired wound contacts cannot prolong defensive combat")

fresh()
models.BulletHit = function(shooter, weapon, target)
    A.reset()
    A.initialize()
    sendClientCommand(target, "Commands", "PlayerDamage", { healthDrop = 99 })
end
check(A.initialize(), "callback crossing a world reset fixture initializes")
models.BulletHit(enemy, {}, victim)
check(victim.damage == 0 and sendClientCommand == command,
    "a callback from a retired world cannot damage a target after reinitialization")

fresh()
models.BulletHit = function(shooter, weapon, target)
    local retained = sendClientCommand
    sendClientCommand = function(...) return retained(...) end
    sendClientCommand(target, "Commands", "PlayerDamage", { healthDrop = 3 })
end
check(A.initialize(), "foreign command wrapper fixture initializes")
models.BulletHit(enemy, {}, victim)
local afterScope = sendClientCommand
local requestsBefore = #BANDITS_TEST_COMMANDS
sendClientCommand(victim, "Commands", "PlayerDamage", { healthDrop = 88 })
check(victim.damage == 3 and #BANDITS_TEST_COMMANDS == requestsBefore + 1,
    "a retained command closure stops intercepting after the synchronous callback")
models.BulletHit(enemy, {}, victim)
check(victim.damage == 6 and afterScope ~= command,
    "the adapter preserves the foreign wrapper and routes the next attack exactly once")

fresh()
server.Commands.PlayerDamage = function(target, args)
    originals.handler(target, args)
    A.reset()
    A.initialize()
    error("old world failed after committing its wound")
end
check(A.initialize(), "handler teardown fixture initializes")
okay = pcall(models.BulletHit, enemy, { damage = 4 }, victim)
check(not okay and victim.damage == 4 and sendClientCommand == command and A.status().active,
    "a retired handler failure neither replays damage nor disables the new world")

fresh()
models.BulletHit = function(shooter, weapon, target)
    sendClientCommand(target, "Commands", "PlayerDamage", false)
end
check(A.initialize(), "malformed request fixture initializes")
okay = pcall(models.BulletHit, enemy, {}, victim)
check(okay and victim.damage == 0 and sendClientCommand == command,
    "a malformed foreign damage request is rejected without leaking command routing")

fresh()
players.GetPlayers = function() return false end
check(not A.initialize(), "invalid native-list contract disables integration")
local safeList = players.GetPlayers()
check(safeList and safeList:size() == 0, "a broken list interface yields no LF targets instead of throwing")

fresh()
local badList = { size = function() return 1 end, get = function() return 9 end }
players.GetPlayers = function() return badList end
check(not A.initialize() and players.GetPlayers():size() == 0,
    "non-actor source entries are rejected before foreign AI consumes them")
fresh()
badList = { size = function() return 1 end, get = function() return BANDITS_TEST_PLAYER end }
players.GetPlayers = function() return badList end
check(A.initialize(), "source getter drift fixture initializes")
badList.get = function() error("foreign list changed") end
local safe, list = pcall(players.GetPlayers)
check(safe and list:size() == 0 and not A.status().active,
    "a list getter that starts throwing is contained and diagnosed")

for _, invalid in ipairs({ 0/0, math.huge, -1, "9" }) do
    fresh()
    models.BulletHit = function(shooter, weapon, target)
        sendClientCommand(target, "Commands", "PlayerDamage", { healthDrop = invalid })
    end
    check(A.initialize(), "invalid numeric damage fixture initializes")
    okay = pcall(models.BulletHit, enemy, {}, victim)
    check(okay and victim.damage == 0 and sendClientCommand == command,
        "invalid wound numbers cannot corrupt native health")
end

fresh()
local lateModels = PlayerDamageModel
PlayerDamageModel = nil
check(not A.initialize(), "missing models retain identity guards")
PlayerDamageModel = lateModels
A.pulse(SC_TEST_CLOCK)
check(A.status().active, "models loaded after identity guards activate automatically")

fresh()
check(A.initialize(), "witness validation fixture initializes")
local neutral = BANDITS_TEST_ACTOR()
neutral.bandit = true
neutral.md.brain = { id = 52, clan = "official", program = {}, hostile = false, hostileP = false }
BanditZombie.Cache[52] = neutral
BanditZombie.CacheLightB[1] = false
BanditZombie.CacheLightB[2] = { x = 5, y = 5 }
local r1, r2, r3 = players.CheckFriendlyFire(neutral, victim)
check(r1 == "original" and r2 == nil and r3 == 7 and neutral.md.brain.hostileP,
    "malformed witnesses are skipped while preserving the original callback")
neutral.md.brain.hostileP = false
bandits.SetProgram = function() error("foreign escalation failed") end
okay, r1 = pcall(players.CheckFriendlyFire, neutral, victim)
check(okay and r1 == "original" and not A.status().active,
    "optional retaliation errors preserve the completed original hit and disable integration")
bandits.SetProgram = originals.program
fresh()
local retiredActor = BANDITS_TEST_ACTOR("sc-retired-world")
check(A.initialize(), "retired identity fixture initializes")
local alias, retainedID = A.idFor(retiredActor), utils.GetCharacterID
BANDITS_TEST_REMOVE(retiredActor)
retiredActor.lf = false
A.reset()
check(A.initialize() and utils.GetCharacterID(retiredActor) == alias and retainedID(retiredActor) == alias
    and A.resolve(alias) == nil and utils.GetCharacterID(BANDITS_TEST_PLAYER) == 1,
    "weak identity tombstones survive reset without exposing old actors or colliding with the real player")
fresh()
SC_TEST_REPORT = "BANDITS_HARDENING_PASS checks=" .. checks
