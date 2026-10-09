-- SPDX-License-Identifier: MIT
-- Production strike geometry with mocked native LOS, map squares and weapon API.
local Topology, checks = SurvivorCompanion.Topology, 0

local function check(value, message)
    checks = checks + 1
    assert(value, "strike barrier regression " .. checks .. ": " .. message)
end

local activeCell, nativeLos
function getCell() return activeCell end
LosUtil = {
    lineClear = function() return nativeLos end,
}

local function square(x, y)
    local value = { x = x, y = y, z = 0, objects = {} }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getObjects() return self.objects end
    function value:getSpecialObjects() return self.objects end
    function value:isFree() return true end
    function value:isSolid() return false end
    function value:isSolidTrans() return false end
    function value:TreatAsSolidFloor() return true end
    function value:isBlockedTo(other) return self.neighbour == other and self.blocked == true end
    function value:getDoorTo(other) return self.neighbour == other and self.door or nil end
    function value:getWindowTo(other) return self.neighbour == other and self.window or nil end
    function value:getHoppableTo(other) return self.neighbour == other and self.lowFence or nil end
    function value:getWallHoppableTo(other) return self.neighbour == other and self.highFence or nil end
    function value:getTransparentWallTo(other)
        return self.neighbour == other and self.transparentWall or nil
    end
    function value:isHoppableTo(other) return self.neighbour == other and self.lowFence ~= nil end
    function value:getDoor() return self.door end
    function value:getWindow() return self.window end
    function value:getDoorOrWindow() return self.door or self.window end
    function value:testPathFindAdjacent() return self.blocked == true end
    return value
end

local function character(x, y, tile)
    local value = { x = x, y = y, z = 0, tile = tile }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    function value:getSquare() return self.tile end
    function value:getCurrentSquare() return self.tile end
    function value:CanSee() return self.nativeCanSee end
    function value:isTransparentWallTo(other)
        return self.transparentWallTo == other
    end
    return value
end

local function weapon(pierces, itemType)
    local value = { pierces = pierces, itemType = itemType, pierceCalls = 0 }
    function value:getFullType() return self.itemType end
    function value:canAttackPierceTransparentWall(actor, item)
        self.pierceCalls = self.pierceCalls + 1
        self.pierceActor, self.pierceItem = actor, item
        return self.pierces == true
    end
    return value
end

local function fixture(kind, options)
    options = options or {}
    local from = square(0, 0)
    local to = kind == "diagonal" and square(1, 1)
        or kind == "same" and from or square(1, 0)
    from.neighbour, to.neighbour = to, from
    local cells = { ["0:0"] = from, ["1:0"] = to }
    if kind == "diagonal" then cells["1:1"] = to end
    activeCell = {
        getGridSquare = function(_, x, y, z)
            if math.floor(z or 0) ~= 0 then return nil end
            return cells[tostring(math.floor(x)) .. ":" .. tostring(math.floor(y))]
        end,
    }
    local actor = character(0.5, 0.5, from)
    local target = character(kind == "same" and 0.65 or 1.5,
        kind == "diagonal" and 1.5 or 0.5, to)
    nativeLos = options.los or "Clear"
    actor.nativeCanSee = options.canSee ~= false
    if kind == "wall" then
        from.blocked, to.blocked = true, true
    elseif kind == "door" then
        local door = { __class = "IsoDoor", opened = options.open == true }
        function door:IsOpen() return self.opened end
        from.door, to.door = door, door
        from.blocked, to.blocked = not door.opened, not door.opened
    elseif kind == "window" then
        local pane = { __class = "IsoWindow", opened = options.open == true,
            smashed = options.smashed == true,
            barricaded = options.barricaded == true }
        function pane:IsOpen() return self.opened end
        function pane:isSmashed() return self.smashed end
        function pane:isBarricaded() return self.barricaded end
        from.window, to.window = pane, pane
        from.blocked, to.blocked = not pane.opened, not pane.opened
    elseif kind == "high_fence" then
        local fence = { __class = "IsoObject" }
        function fence:isTallHoppable() return true end
        function fence:isHoppable() return false end
        function fence:isTransparent() return true end
        from.highFence, to.highFence = fence, fence
        from.transparentWall, to.transparentWall = fence, fence
        target.transparentWallTo = actor
        from.blocked, to.blocked = true, true
    elseif kind == "low_fence" then
        local fence = { __class = "IsoObject" }
        function fence:isTallHoppable() return false end
        function fence:isHoppable() return true end
        from.lowFence, to.lowFence = fence, fence
        from.blocked, to.blocked = true, true
    end
    return actor, target, from, to
end

local function strike(kind, options, action, item, expected, label, strikeOptions)
    local actor, target, from, to = fixture(kind, options)
    local blocked, reason = Topology.strikeBarrier(actor, target, action, item,
        strikeOptions)
    check(blocked == expected,
        label .. " blocked=" .. tostring(blocked) .. " reason=" .. tostring(reason))
    return actor, target, item, from, to, reason
end

local ordinary = weapon(false, "Base.SpearNamedButBlunt")
strike("wall", { los = "Blocked", canSee = false }, "melee", ordinary, true,
    "solid cardinal wall blocks melee")
strike("door", { open = false, los = "Clear" }, "melee", ordinary, true,
    "closed visible door blocks melee")
strike("door", { open = true, los = "Clear" }, "melee", ordinary, false,
    "open door permits melee")
strike("window", { open = false, los = "Clear" }, "melee", ordinary, true,
    "closed visible window blocks melee")
local freeFire = { allowClosedWindow = true }
strike("window", { open = false, los = "Clear" }, "melee", ordinary, false,
    "Free Fire melee may strike through an intact unbarricaded window", freeFire)
strike("window", { open = false, los = "Clear" }, "shove", ordinary, true,
    "Free Fire never allows a shove through a closed window", freeFire)
strike("window", { open = false, los = "Clear" }, "stomp", ordinary, true,
    "Free Fire never allows a stomp through a closed window", freeFire)
strike("window", { open = false, barricaded = true, los = "Clear" },
    "melee", ordinary, true,
    "a barricaded window blocks Free Fire melee", freeFire)
strike("window", { open = true, los = "Clear" }, "melee", ordinary, false,
    "open window permits melee")
strike("window", { smashed = true, los = "Clear" }, "melee", ordinary, false,
    "smashed window permits melee")

ordinary.pierceCalls = 0
strike("high_fence", { los = "Clear" }, "melee", ordinary, true,
    "transparent high fence blocks an ordinary melee weapon")
check(ordinary.pierceCalls > 0,
    "high-fence exception consults native canAttackPierceTransparentWall, not weapon name")
local spear = weapon(true, "Base.Spear")
local spearActor, _, spearItem = strike("high_fence", { los = "Clear" },
    "melee", spear, false, "native piercing spear reaches through transparent high fence")
check(spear.pierceCalls > 0 and spear.pierceActor == spearActor
        and spear.pierceItem == spearItem,
    "spear passes actor and weapon to native pierce query")
local knife = weapon(true, "Base.HuntingKnife")
strike("high_fence", { los = "Clear" }, "melee", knife, false,
    "native piercing knife reaches through transparent high fence")
check(knife.pierceCalls > 0, "knife uses the native pierce query")
strike("high_fence", { los = "Clear" }, "attack_melee", spear, false,
    "native melee action name preserves the piercing exception")
strike("high_fence", { los = "Clear" }, "attack_melee", ordinary, true,
    "native melee action name still blocks an ordinary weapon")
strike("high_fence", { los = "Clear" }, "shove", spear, true,
    "shove cannot pierce a high fence")
strike("high_fence", { los = "Clear" }, "stomp", spear, true,
    "stomp cannot pierce a high fence")
strike("low_fence", { los = "Clear" }, "melee", ordinary, false,
    "standing melee reaches across a low fence with clear native LOS")
strike("low_fence", { los = "Blocked", canSee = false }, "melee", ordinary, true,
    "native blocked LOS still rejects a low-fence melee attempt")
strike("diagonal", { los = "Blocked", canSee = false }, "melee", ordinary, true,
    "diagonal blocked native LOS rejects a melee attempt")
strike("same", { los = "Clear" }, "melee", ordinary, false,
    "same-square target has no intervening strike barrier")
strike("wall", { los = "Unknown" }, "melee", ordinary, true,
    "unknown native LOS falls back to a definite wall")
strike("open", { los = "Unknown" }, "melee", ordinary, false,
    "unknown native LOS without a definite blocker remains open")

-- Exercise the combat action seam as well: geometry must remove a tempting
-- in-range swing and offer navigation an explicit route instead.
local Combat = SurvivorCompanion.Combat
local oldSpacing = Combat.meleeSpacing
Combat.meleeSpacing = function()
    return { minimum = 0.3, maximum = 1.5, nativeMinimum = 0.45,
        defend = 0.55, desired = 1.3 }
end
local readiness = {
    health = 100, woundPressure = 0, endurance = 1, panic = 0, stress = 0,
    pain = 0, heavyLoad = 0, escapeDanger = 0, staminaCritical = false,
    occupiedSectors = 0, footing = { crowd = 0 }, support = 0,
    close = 1, immediate = 1, strength = 5, nimble = 5, fitness = 5,
    combatSkill = 5, weaponQuality = 1, weaponCost = 1, confidence = 50,
    escapeClearance = 3,
}
local function plannedActions(kind, options, item, doctrine)
    local actor, target = fixture(kind, options)
    local chosenWeapon = { item = item, ranged = false, damage = 1,
        conditionRatio = 1, equipped = true }
    local record = { actor = target, distanceSq = 1, score = 20, bearing = "front" }
    local snapshot = { pressure = 0, encircled = false, escapeSquares = { square(-1, 0) } }
    local actions = Combat._actionUtilitiesForTests(actor, nil, snapshot,
        record, chosenWeapon, nil,
        { holdFire = false, combatDoctrine = doctrine }, readiness)
    local melee, route
    for _, action in ipairs(actions) do
        if action.kind == "melee" then melee = action end
        if action.kind == "approach" and action.requiresRoute == true then route = action end
    end
    return melee, route
end
local blockedMelee, blockedRoute = plannedActions("wall", { los = "Clear" }, ordinary)
check(blockedMelee == nil and blockedRoute ~= nil,
    "planner substitutes a routed approach for an in-range swing through a wall")
local openMelee, openRoute = plannedActions("open", { los = "Clear" }, ordinary)
check(openMelee ~= nil and openRoute == nil,
    "planner retains in-range melee when there is no physical barrier")
local spearMelee, spearRoute = plannedActions("high_fence", { los = "Clear" }, spear)
check(spearMelee ~= nil and spearRoute == nil,
    "planner preserves native piercing melee through transparent high fence")
local defenseMelee, defenseRoute = plannedActions("window",
    { open = false, los = "Clear" }, ordinary, "close_defense")
check(defenseMelee == nil and defenseRoute ~= nil,
    "Close Defense routes around an intact window instead of swinging")
local freeMelee, freeRoute = plannedActions("window",
    { open = false, los = "Clear" }, ordinary, "weapons_free")
check(freeMelee ~= nil and freeRoute == nil,
    "Free Fire offers melee through an intact unbarricaded window")
local barricadedMelee, barricadedRoute = plannedActions("window",
    { open = false, barricaded = true, los = "Clear" }, ordinary, "weapons_free")
check(barricadedMelee == nil and barricadedRoute ~= nil,
    "Free Fire routes around a barricaded window")
Combat.meleeSpacing = oldSpacing

SC_TEST_REPORT = "STRIKE_BARRIER_REGRESSION_PASS checks=" .. tostring(checks)
