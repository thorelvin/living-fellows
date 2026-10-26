-- SPDX-License-Identifier: MIT
function require() return true end
SC_TEST_CLOCK = 1000
function getTimestampMs() return SC_TEST_CLOCK end
function isClient() return false end
function isServer() return false end
ALIFE_TEST_MODS = { ProjectALifeNPCs = true }
function getActivatedMods() return { contains = function(_, id) return ALIFE_TEST_MODS[id] == true end } end
function instanceof(value, name) return type(value) == "table" and value.class == name end
ALIFE_TEST_OPTIONS = { alifeCompatibility = true }
ALIFE_TEST_RECORDS, ALIFE_TEST_REPUTATION = {}, {}
ALIFE_TEST_VERSION, ALIFE_TEST_ENUMERATIONS = 1, 0
ALIFE_TEST_LIFECYCLE, ALIFE_TEST_POPUPS, ALIFE_TEST_SYNCS = 0, 0, {}
Events = {}
for _, name in ipairs({ "ProjectALife_NpcSpawned", "ProjectALife_NpcDied", "ProjectALife_NpcHit" }) do
    local callbacks = {}
    Events[name] = {
        callbacks = callbacks,
        Add = function(callback) callbacks[#callbacks + 1] = callback end,
        Remove = function(callback)
            for index = #callbacks, 1, -1 do if callbacks[index] == callback then table.remove(callbacks, index) end end
        end,
    }
end
SurvivorCompanion = {
    State = { active = true },
    UserOptions = { get = function(key) return ALIFE_TEST_OPTIONS[key] end },
    Actor = { _isRegistryActor = function(actor) return actor.lf == true end },
    Registry = {
        idOf = function(actor) return actor and actor.lf and actor.md.SC_Id end,
        byId = function(id) return ALIFE_TEST_RECORDS[id] end,
        isActive = function(actor, id) return ALIFE_TEST_RECORDS[id] and ALIFE_TEST_RECORDS[id].actor == actor end,
        version = function() return ALIFE_TEST_VERSION end,
        snapshot = function()
            ALIFE_TEST_ENUMERATIONS = ALIFE_TEST_ENUMERATIONS + 1
            local rows = {}
            for _, record in pairs(ALIFE_TEST_RECORDS) do rows[#rows + 1] = record end
            table.sort(rows, function(a, b) return a.id < b.id end)
            return rows
        end,
    },
    BaseLife = { resident = function(id) return ALIFE_TEST_RECORDS[id] and ALIFE_TEST_RECORDS[id].resident end },
    Diagnostics = { report = function(_, _, _, reason) ALIFE_TEST_DIAGNOSTIC = reason end },
}
function ALIFE_TEST_ACTOR(id, recruited)
    local actor = { lf = id ~= nil, class = "IsoPlayer", md = id and { SC_Id = id } or {}, x = 5, y = 5,
        health = 100, square = {}, slot = -1, variables = {} }
    function actor:hasModData() return true end
    function actor:getModData() return self.md end
    function actor:getSquare() return self.square end
    actor.getCurrentSquare = actor.getSquare
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return 0 end
    function actor:getHealth() return self.health end
    function actor:isDead() return self.dead == true end
    function actor:isAlive() return not self:isDead() end
    function actor:isExistInTheWorld() return self.removed ~= true end
    function actor:isGodMod() return self.god == true end
    function actor:isInvincible() return self.invincible == true end
    function actor:isGhostMode() return self.ghost == true end
    function actor:isInvisible() return self.invisible == true end
    function actor:getVariableString(key) return self.variables[key] end
    function actor:getOnlineID() return -1 end
    function actor:getPlayerNum() return self.slot end
    function actor:getUsername() return "Bob" end
    function actor:isZombie() return self.class == "IsoZombie" end
    function actor:CanSee() return true end
    function actor:getHumanVisual() return {} end
    function actor:getBodyDamage() return self.body end
    actor.body = { owner = actor, hits = 0, damage = 0 }
    function actor.body:getParentChar() return self.owner end
    function actor.body:AddDamage(_, damage) self.damage = self.damage + damage self.hits = self.hits + 1 end
    if id then
        ALIFE_TEST_RECORDS[id] = { id = id, actor = actor, recruited = recruited == true }
        ALIFE_TEST_VERSION = ALIFE_TEST_VERSION + 1
    end
    return actor
end
function ALIFE_TEST_REMOVE(actor)
    ALIFE_TEST_RECORDS[actor.md.SC_Id] = nil
    ALIFE_TEST_VERSION = ALIFE_TEST_VERSION + 1
end
ALIFE_TEST_PLAYER = ALIFE_TEST_ACTOR()
ALIFE_TEST_PLAYER.slot = 0
ALIFE_TEST_PLAYERS = { ALIFE_TEST_PLAYER }
function getSpecificPlayer() return ALIFE_TEST_PLAYER end
function getPlayer() return ALIFE_TEST_PLAYER end
ProjectALife = { ActorRegistry = {}, Watchdog = { bindings = {} }, Perception = { adapters = {}, engagements = {} },
    Reputation = {}, Relations = {}, TargetPolicy = {}, PersonalRep = {}, CharacterReset = {}, RepTrack = {},
    HostileAct = {}, Fairness = {}, Combat = {}, LineOfFire = {}, Wounds = {}, Interop = { VERSION = 1 } }
ALIFE_TEST_FOREIGN_RECORDS = {}
function ProjectALife.ActorRegistry.peek(uid) return ALIFE_TEST_FOREIGN_RECORDS[uid] end
ProjectALife.ActorRegistry.read = ProjectALife.ActorRegistry.peek
function ALIFE_TEST_NPC(uid)
    local actor = ALIFE_TEST_ACTOR()
    actor.class = "IsoZombie"
    actor.md = { ProjectALifeOwned = true, ProjectALifeUID = uid, ProjectALifeGeneration = 3 }
    local record = { uid = uid, generation = 3, lifecycle = "active", factionId = "hostile", memory = {} }
    ALIFE_TEST_FOREIGN_RECORDS[uid] = record
    ProjectALife.Watchdog.bindings[uid] = { shell = actor, generation = 3 }
    return actor, record
end
ProjectALife.PlayerLocator = { list = function(adapter) return adapter and adapter() or ALIFE_TEST_PLAYERS end }
function ProjectALife.Perception.configure(adapters) ProjectALife.Perception.adapters = adapters or {} end
function ProjectALife.Reputation.playerKey(actor)
    if type(actor) == "string" then return actor end
    return "sp:" .. tostring(math.max(0, actor:getPlayerNum()))
end
function ProjectALife.Reputation.baselineFor(_, faction)
    return type(faction) == "table" and faction.factionId or faction
end
function ProjectALife.Reputation.recordedStatus(actor, faction)
    local key = ProjectALife.Reputation.playerKey(actor)
    local rows = ALIFE_TEST_REPUTATION[key] or {}
    return rows[type(faction) == "table" and faction.factionId or faction]
end
function ProjectALife.Reputation.escalate(actor, faction)
    local key = ProjectALife.Reputation.playerKey(actor)
    ALIFE_TEST_REPUTATION[key] = ALIFE_TEST_REPUTATION[key] or {}
    ALIFE_TEST_REPUTATION[key][type(faction) == "table" and faction.factionId or faction] = "hostile"
    ProjectALife.Reputation.sync(actor)
    return true, "escalated"
end
function ProjectALife.Reputation.sync(actor) ALIFE_TEST_SYNCS[#ALIFE_TEST_SYNCS + 1] = actor return true end
function ProjectALife.Relations.baselineStance(record, actor)
    return ProjectALife.Reputation.baselineFor(actor, record), "faction"
end
function ProjectALife.HostileAct.live(memory, key, now)
    return type(memory.hostileAct) == "table" and (memory.hostileAct[key] or 0) > now
end
function ProjectALife.HostileAct.restraint(record, key, now)
    return record.memory.robberyTruce and (record.memory.robberyTruce[key] or 0) > now and "truce" or nil
end
function ProjectALife.Fairness.underAttack(record, actor) return record.attacker == actor end
function ProjectALife.Relations.wasAggressor(record, actor) return record.victim == actor end
function ProjectALife.Relations.actorRecord(value)
    if type(value) == "table" and value.uid then return value end
    return value and ALIFE_TEST_FOREIGN_RECORDS[value.md.ProjectALifeUID]
end
function ProjectALife.Relations.isSelfDefence(actor, record) return record.victim == actor end
function ProjectALife.Relations.hostileToPlayer(record, actor)
    local key = ProjectALife.Reputation.playerKey(actor)
    if ProjectALife.HostileAct.restraint(record, key, SC_TEST_CLOCK) then return false, "truce" end
    if record.memory.hostileToPlayerKeys and record.memory.hostileToPlayerKeys[key] then return true end
    if record.attacker == actor then return true end
    if ProjectALife.HostileAct.live(record.memory, key, SC_TEST_CLOCK) then return true end
    return ProjectALife.Reputation.recordedStatus(actor, record) == "hostile"
        or record.memory.hostileOverride == true or ProjectALife.Relations.baselineStance(record, actor) == "hostile"
end
function ProjectALife.Relations.basePlayerStance(record, actor)
    return ProjectALife.Relations.hostileToPlayer(record, actor) and "hostile" or "neutral"
end
function ProjectALife.Relations.playerStance(record, actor) return ProjectALife.Relations.basePlayerStance(record, actor) end
function ProjectALife.TargetPolicy.identityOf(actor) return nil, nil, actor:getOnlineID() end
function ProjectALife.TargetPolicy.canAttack(actor) return not actor:isDead(), "original_policy" end
function ProjectALife.Interop.isNpc(actor) return actor.md.ProjectALifeOwned == true end
local function lifecycle() ALIFE_TEST_LIFECYCLE = ALIFE_TEST_LIFECYCLE + 1 return "original", nil, 9 end
ProjectALife.Reputation.onPlayerDied, ProjectALife.Reputation.forgetPlayer = lifecycle, lifecycle
ProjectALife.PersonalRep.onPlayerDied, ProjectALife.PersonalRep.forgetPlayer = lifecycle, lifecycle
ProjectALife.CharacterReset.check, ProjectALife.CharacterReset.onPlayerDied, ProjectALife.CharacterReset.forget = lifecycle, lifecycle, lifecycle
ProjectALife.RepTrack.onPlayerDied = lifecycle
function ProjectALife.PersonalRep.announce() ALIFE_TEST_POPUPS = ALIFE_TEST_POPUPS + 1 return true end
function ProjectALife.Combat.friendlyBody() return false end
function ProjectALife.Combat.hostileToActor() return true end
function ProjectALife.LineOfFire.liveBystander(body) return body.class == "IsoZombie" end
function ProjectALife.Wounds.damagePlayer(body, weapon)
    body.hits, body.damage = body.hits + 1, body.damage + weapon.damage
    return true, nil, 17
end
function ProjectALife.Combat.resolveAttack(record, shell, target, weapon)
    if ALIFE_TEST_BEFORE_WOUND then ALIFE_TEST_BEFORE_WOUND(target) end
    local damaged = ProjectALife.Wounds.damagePlayer(target:getBodyDamage(), weapon or { damage = 7 })
    if not damaged then target:getBodyDamage():AddDamage("torso", 99) end
    return damaged, nil, 13
end
