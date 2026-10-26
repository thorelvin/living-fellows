-- SPDX-License-Identifier: MIT
function require() return true end
SC_TEST_CLOCK = 1000
function getTimestampMs() return SC_TEST_CLOCK end
function isClient() return false end
function isServer() return false end
local mods = { Bandits2 = true }
function getActivatedMods() return { contains = function(_, id) return mods[id] == true end } end
BANDITS_TEST_MODS = mods
ArrayList = { new = function()
    local list = { values = {} }
    function list:add(value) self.values[#self.values + 1] = value end
    function list:size() return #self.values end
    function list:get(index) return self.values[index + 1] end
    return list
end }
local records, byActor, revision = {}, {}, 1
SurvivorCompanion = {
    UserOptions = { get = function() return true end },
    Actor = { _isRegistryActor = function(actor) return actor.lf == true end },
    Registry = {
        idOf = function(actor) return byActor[actor] end,
        byId = function(id) return records[id] end,
        isActive = function(actor, id) return records[id] and records[id].actor == actor end,
        version = function() return revision end,
        snapshot = function()
            local rows = {}
            for _, record in pairs(records) do rows[#rows + 1] = record end
            table.sort(rows, function(a, b) return a.id < b.id end)
            return rows
        end,
    },
    Diagnostics = { report = function() end },
}
function BANDITS_TEST_ACTOR(id)
    local actor = { lf = id ~= nil, dead = false, x = 5, y = 5, md = id and { SC_Id = id } or {} }
    function actor:hasModData() return true end
    function actor:getModData() return self.md end
    function actor:getSquare() return self.square end
    actor.square = {}
    function actor:isDead() return self.dead end
    function actor:isAlive() return not self.dead end
    function actor:isExistInTheWorld() return self.removed ~= true end
    function actor:getHealth() return self.dead and 0 or 100 end
    function actor:isInvisible() return self.invisible == true end
    function actor:isGodMod() return self.god == true end
    function actor:isGhostMode() return self.ghost == true end
    function actor:getVariableBoolean(key) return key == "Bandit" and self.bandit == true end
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return 0 end
    function actor:CanSee() return self.canSee ~= false end
    if id then
        records[id], byActor[actor] = { id = id, actor = actor }, id
        revision = revision + 1
    end
    return actor
end
function BANDITS_TEST_REMOVE(actor)
    local id = byActor[actor]
    records[id], byActor[actor] = nil, nil
    revision = revision + 1
end
BANDITS_TEST_PLAYER = BANDITS_TEST_ACTOR()
BANDITS_TEST_REAL_LIST = ArrayList.new()
BANDITS_TEST_REAL_LIST:add(BANDITS_TEST_PLAYER)
BanditUtils = { GetCharacterID = function(actor) return actor.bandit and actor.md.brain.id or 1 end }
BanditPlayer = {
    GetPlayers = function() return BANDITS_TEST_REAL_LIST end,
    GetPlayerById = function(id) return id == 1 and BANDITS_TEST_PLAYER or nil end,
    CheckFriendlyFire = function() return "original", nil, 7 end,
}
BanditZombie = { Cache = {}, CacheLightB = {} }
Bandit = {
    SetHostileP = function(actor, value) actor.md.brain.hostileP = value end,
    SetProgram = function(actor, program) actor.md.brain.program = { name = program } end,
    ForceSyncPart = function(actor) actor.syncCount = (actor.syncCount or 0) + 1 end,
}
BanditServer = { Commands = { PlayerDamage = function(actor, args)
    actor.damage = (actor.damage or 0) + args.healthDrop
    actor.wound = args.cut
end } }
BANDITS_TEST_COMMANDS = {}
function sendClientCommand(player, module, command, args)
    BANDITS_TEST_COMMANDS[#BANDITS_TEST_COMMANDS + 1] = { player, module, command, args }
    return "sent"
end
local function model(shooter, weapon, victim)
    sendClientCommand(victim, "Commands", "PlayerDamage", { healthDrop = weapon.damage, cut = true })
    return "landed", nil, 9
end
PlayerDamageModel = {
    BulletHit = model,
    MeleeHit = function(shooter, victim, weapon) return model(shooter, weapon, victim) end,
    BareHandHit = function(shooter, victim)
        return model(shooter, { damage = 3 }, victim)
    end,
}
