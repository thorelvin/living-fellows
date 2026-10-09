-- SPDX-License-Identifier: MIT

SurvivorCompanion = {}
local SC = SurvivorCompanion
SC_TEST_CLOCK = { ms = 0, hour = 0, rain = false, nav = 0, cancel = 0,
    squares = {}, visual = {}, moves = 0 }
local C = SC_TEST_CLOCK
function getGameTime() return { getWorldAgeHours = function() return C.hour end } end
function getClimateManager() return { isRaining = function() return C.rain end } end

local U = {}
SC.GameplayUtil = U
function U.call(object, method, ...)
    if object == nil or type(object[method]) ~= "function" then return nil, false end
    return object[method](object, ...), true
end
function U.nowMs() return C.ms end
function U.config(key)
    local values = { oddballGoreCloakHours = 18, oddballGoreRainMultiplier = 4,
        oddballPoseStepCooldownMs = 4000, oddballPoseWatchAngle = 60,
        oddballPoseRevealDistance = 2, zombieTargetRadius = 18,
        zombieTargetMaxChecks = 128 }
    return values[key]
end
function U.position(value)
    return value and value.x, value and value.y, value and value.z or 0
end
function U.squareOf(value) return value and (value.square or value) end
function U.loadedSquare(value) return value end
function U.gridSquare(x, y, z)
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
    if not C.squares[key] then
        C.squares[key] = { x = x, y = y, z = z, square = true, bodies = {} }
    end
    return C.squares[key]
end
function U.distance(a, b)
    if not a or not b then return math.huge end
    local ax, ay, az = U.position(a)
    local bx, by, bz = U.position(b)
    return math.sqrt((ax - bx)^2 + (ay - by)^2 + ((az - bz) * 3)^2)
end
function U.distanceSq(a, b) return U.distance(a, b)^2 end
function U.isSquareFree() return true end
function U.roomName() return "spiffo_dining" end
function U.edgeBlocked() return false end
function U.canSee(observer, target)
    if not observer or not target then return false end
    local x, y = U.position(target)
    return observer.visible and observer.visible[tostring(x) .. ":" .. tostring(y)] == true
end
function U.each(list, limit, callback)
    for index = 1, math.min(#list, limit) do callback(list[index], index - 1) end
end
function U.isValidActor(actor) return actor and not actor.dead end
function U.isZombie(actor) return actor and actor.zombie == true end
function U.isDead(actor) return actor and actor.dead == true end
function U.isALifeHordeHeld() return false end
function U.sameFloor(a, b) return a.z == b.z end
function U.say(actor, line) actor.lastLine = line end
function U.stop() return true end
function U.move(actor, mode, intent)
    C.moves = C.moves + 1
    C.lastMove = intent
    if intent and intent.action == "study_corpse" then
        C.visual[actor] = { startedAt = C.ms, action = "study_corpse" }
    end
    return true
end
function U.squareStaticMovingObjects(square, callback, limit)
    for index, body in ipairs(square and square.bodies or {}) do
        if index > (limit or 12) then break end
        callback(body)
    end
end
function U.instanceOf(value, name) return value and value.className == name end
function U.objectLabel() return "" end
function U.squareObjects() end
function U.inventory(actor) return actor and actor.inventory end
function U.inventoryItemsDeep(inventory)
    local result = {}
    for _, item in ipairs(inventory or {}) do result[#result + 1] = item end
    return result
end
function U.itemType(item) return item and item.fullType end
function U.addItem(inventory, kind)
    if not inventory then return nil, "inventory_unavailable" end
    inventory[#inventory + 1] = { type = kind, fullType = kind }
    return inventory[#inventory]
end

SC.Registry = { actors = {}, byId = function(id) return SC.Registry.actors[id] end }
SC.Factions = {
    member = function(group, key) return group.members[key] end,
    markDiscovered = function() return true end,
    adjustStanding = function() return true end,
    resolveQuestContainer = function(locator) return locator.container end,
}
SC.Navigation = {
    request = function(actor, square, mode, intent)
        C.nav = C.nav + 1
        C.lastTarget = square
        return true, "navigation_requested"
    end,
    cancel = function(actor, reason) C.cancel = C.cancel + 1 return true end,
}
SC.Commands = { peek = function(actor) return actor and actor.commands end }
SC.NativeActions = {
    visualStatus = function(actor, expected)
        local visual = C.visual[actor]
        if not visual then return "none" end
        if visual.action ~= expected then return "different" end
        return C.ms - visual.startedAt >= 10000 and "completed" or "active"
    end,
    clearVisual = function(actor) C.visual[actor] = nil end,
    cancelVisual = function(actor)
        C.visual[actor] = nil
        return true, "visual_action_cancelled"
    end,
}
SC.ActionSupervisor = { Priority = { PLAYER = 400 }, owners = {} }
local S = SC.ActionSupervisor
function S.current(actor) return S.owners[actor] end
function S.isCurrent(token)
    return token and S.owners[token.actor] == token
end
function S.begin(actor, spec)
    if S.current(actor) then return nil, "actor_owned" end
    local token = { actor = actor, spec = spec, phase = "selected" }
    S.owners[actor] = token
    return token, "started"
end
function S.reserve(token, resource)
    if not S.isCurrent(token) then return false, "stale_token" end
    return true
end
function S.transition(token, phase)
    if not S.isCurrent(token) then return false, "stale_token" end
    token.phase = phase
    return true
end
function S.expectVisual(token)
    if not S.isCurrent(token) then return false, "stale_token" end
    return true
end
function S.markVisualVerified(token)
    if not S.isCurrent(token) then return false, "stale_token" end
    return true
end
function S.commit(token, action)
    if not S.isCurrent(token) then return false, "stale_token" end
    return action()
end
function S.complete(token)
    if not S.isCurrent(token) then return false, "stale_token" end
    S.owners[token.actor] = nil
    return true
end
function S.fail(token)
    if not S.isCurrent(token) then return false, "stale_token" end
    S.owners[token.actor] = nil
    return true
end
function S.progress() return true end
SC.Senses = { cached = function(actor) return { threats = actor.threats or {} } end }
SC.ZombieAttack = { reset = function() return true end }
SC.Oddballs = {
    state = function(group) return group.oddball end,
    actorGroups = {},
    isZombieIgnored = function(actor)
        local group = SC.Oddballs.actorGroups[actor]
        if not group then return false end
        local module = group.oddball.id == "gut_cloaked_red"
            and SC.OddballRed or SC.OddballSpiffo
        return module.zombiesIgnore(actor, group)
    end,
}

function SC_TEST_ACTOR(x, y)
    local actor = { x = x, y = y, z = 0, immunity = false,
        variables = {}, events = {},
        square = { x = x, y = y, z = 0,
            isOutside = function() return true end } }
    function actor:setVariable(name, value) self.variables[name] = value end
    function actor:clearVariable(name) self.variables[name] = nil end
    function actor:reportEvent(name) self.events[#self.events + 1] = name end
    function actor:setZombiesDontAttack(value) self.immunity = value end
    function actor:isRunning() return false end
    function actor:isSprinting() return false end
    function actor:isAttackStarted() return false end
    function actor:isOutside() return true end
    function actor:isGhostMode() return false end
    function actor:isInvisible() return false end
    function actor:getForwardDirectionX() return self.fx or 0 end
    function actor:getForwardDirectionY() return self.fy or 1 end
    return actor
end

function SC_TEST_CORPSE(x, y, z)
    local square = U.gridSquare(x, y, z or 0)
    local body = { className = "IsoDeadBody", x = x, y = y,
        z = z or 0, square = square,
        isAnimal = function() return false end }
    square.bodies[#square.bodies + 1] = body
    return body
end
