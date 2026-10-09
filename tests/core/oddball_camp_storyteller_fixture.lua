-- SPDX-License-Identifier: MIT
SurvivorCompanion = { GameplayUtil = {}, Registry = {}, Factions = {},
    FactionRecruitment = {}, Navigation = {} }
local SC = SurvivorCompanion
local U = SC.GameplayUtil
CampFixture = { now = 1000, lines = {}, fires = {}, reputation = 0,
    trial = false, players = {}, client = false, commands = {}, stores = {} }
local F = CampFixture
function isClient() return F.client end
Events = { OnClientCommand = { Add = function(callback)
    F.serverCommandHandler = callback
end } }
ModData = { getOrCreate = function(key)
    F.stores[key] = F.stores[key] or {}
    return F.stores[key]
end }

function U.call(object, method, ...)
    local fn = object and object[method]
    if type(fn) ~= "function" then return nil, false end
    return fn(object, ...), true
end
function U.position(object) return object.x, object.y, object.z end
function U.isValidActor(actor) return actor ~= nil end
function U.canSee(player, target) return target.actor == true end
function U.distance(left, right)
    local x, y = U.position(left)
    local a, b = U.position(right)
    return math.sqrt((x - a) ^ 2 + (y - b) ^ 2)
end
function U.say(actor, line)
    F.lines[#F.lines + 1] = { speaker = actor, line = line }
    return true
end
function U.nowMs() return F.now end
function U.isSafeSpawnSquare(square)
    return square ~= nil and square.tree == false
end

local squares = {}
function U.gridSquare(x, y, z)
    if z ~= 0 or math.abs(x) > 10 or math.abs(y) > 10 then return nil end
    local key = tostring(x) .. ":" .. tostring(y)
    if squares[key] then return squares[key] end
    -- A forest clearing at the origin with 33 real trees on the test grid.
    local tree = (math.abs(x) >= 3 or math.abs(y) >= 3)
        and (x + y) % 3 ~= 0
    local square = { x = x, y = y, z = z, tree = tree }
    function square:getRoom() return nil end
    function square:getBuilding() return nil end
    function square:isOutside() return true end
    function square:getTree() return self.tree and {} or nil end
    function square:getPlayerNum() return 0 end
    function square:isCanSee() return false end
    function square:getFloor()
        return { getSprite = function()
            return { getName = function() return "blends_natural_01_0" end }
        end }
    end
    function square:isSolid() return false end
    function square:isSolidTrans() return false end
    function square:TreatAsSolidFloor() return true end
    function square:isFree() return not self.tree end
    function square:isSafeToSpawn() return not self.tree end
    squares[key] = square
    return square
end
function getCell() return { getGridSquare = function(_, x, y, z)
    return U.gridSquare(x, y, z)
end } end

F.player = { x = 1, y = 0, z = 0 }
function F.player:getPlayerNum() return 0 end
function F.player:getX() return self.x end
function F.player:getY() return self.y end
function F.player:getZ() return self.z end
function F.player:Say(line)
    F.lines[#F.lines + 1] = { speaker = self, line = line }
end

SCampfireSystem = { instance = {} }
CCampfireSystem = { instance = {} }
function SCampfireSystem.instance:getLuaObjectOnSquare(square)
    return F.fires[tostring(square.x) .. ":" .. tostring(square.y)]
end
CCampfireSystem.instance.getLuaObjectOnSquare =
    SCampfireSystem.instance.getLuaObjectOnSquare
function SCampfireSystem.instance:addCampfire(square)
    local key = tostring(square.x) .. ":" .. tostring(square.y)
    local fire = { fuel = 0, lit = false }
    function fire:addFuel(amount) self.fuel = self.fuel + amount end
    function fire:lightFire() self.lit = self.fuel > 0 end
    F.fires[key] = fire
    F.fireBuilt = (F.fireBuilt or 0) + 1
    return fire
end
function sendClientCommand(player, module, command, args)
    F.commands[#F.commands + 1] = { player = player, module = module,
        command = command, args = args }
end
function getSpecificPlayer() return F.player end

SC.Factions.adjustStanding = function(id, delta)
    F.reputation = F.reputation + delta
    F.group.standing = F.reputation >= 40 and "Trusted" or "Wary"
    return true
end
SC.Factions.forceStanding = function(id, standing)
    F.group.standing = standing
    return true
end
SC.FactionRecruitment.summary = function()
    return { status = "candidate", canDecide = false }
end
SC.FactionRecruitment.ask = function() F.asked = true; return true end
SC.FactionRecruitment.startTrial = function()
    F.trial = true
    return true, "trial_started"
end
SC.Registry.byId = function() return { actor = F.actor } end
SC.Navigation.request = function()
    F.routeRequested = true
    return true
end
