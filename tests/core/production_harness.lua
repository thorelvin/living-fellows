-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then error("check " .. tostring(checks) .. " failed: " .. message) end
end

-- ---------------------------------------------------------------------------
-- World fakes
-- ---------------------------------------------------------------------------

local nextNativeId = 5000
local makeItem

local function removeIdentity(values, target)
    for index, value in ipairs(values) do
        if value == target then table.remove(values, index) return true end
    end
    return false
end

local function makeInventory(kind)
    local inventory = { items = {}, kind = kind or "inventory", room = true }
    function inventory:getItems() return self.items end
    function inventory:contains(item)
        for _, value in ipairs(self.items) do if value == item then return true end end
        return false
    end
    function inventory:hasRoomFor() return self.room == true end
    function inventory:getType() return self.kind end
    function inventory:AddItem(value)
        local item = type(value) == "string" and makeItem(value) or value
        if item == nil or self.room ~= true then return nil end
        if not self:contains(item) then self.items[#self.items + 1] = item end
        item.container, item.worldItem = self, nil
        return item
    end
    function inventory:DoAddItemBlind(item) return self:AddItem(item) end
    function inventory:Remove(item)
        if removeIdentity(self.items, item) and item.container == self then item.container = nil end
    end
    function inventory:DoRemoveItem(item) return self:Remove(item) end
    function inventory:getFirstTagEvalRecurse(tag, predicate)
        for _, item in ipairs(self.items) do
            if item:hasTag(tag) and (predicate == nil or predicate(item)) then return item end
        end
        return nil
    end
    return inventory
end

makeItem = function(fullType, options)
    options = options or {}
    nextNativeId = nextNativeId + 1
    local item = {
        __class = "InventoryItem", fullType = fullType, nativeId = nextNativeId,
        modData = options.modData or {}, tags = options.tags or {},
        broken = options.broken == true, treeDamage = options.treeDamage or 5,
        twoHanded = options.twoHanded == true, favorite = options.favorite == true,
    }
    function item:getFullType() return self.fullType end
    function item:getType() return string.match(self.fullType, "[^%.]+$") end
    function item:getDisplayName() return self:getType() end
    function item:getID() return self.nativeId end
    function item:getModData() return self.modData end
    function item:getContainer() return self.container end
    function item:getWorldItem() return self.worldItem end
    function item:isBroken() return self.broken end
    function item:isFavorite() return self.favorite end
    function item:isTwoHandWeapon() return self.twoHanded end
    function item:hasTag(tag)
        local wanted = type(tag) == "table" and tag.tag or string.lower(tostring(tag))
        return self.tags[wanted] == true
    end
    function item:getActualWeight() return self.fullType == "Base.Log" and 9 or 1 end
    function item:getInventory() return nil end
    function item:getAllWeaponParts() return {} end
    return item
end

local squares = {}

local function squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
end

local function sq(x, y)
    return squares[squareKey(x, y, 0)]
end

local function makeSquare(x, y, z)
    local square = {
        __square = true, x = x, y = y, z = z or 0, objects = {}, worldItems = {},
        specialObjects = {}, staticMoving = {}, room = false,
        floorTexture = "floors_interior_tilesandwood_01_0",
    }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:isFree() return true end
    function square:getObjects() return self.objects end
    function square:getWorldObjects() return self.worldItems end
    function square:getSpecialObjects() return self.specialObjects end
    function square:getStaticMovingObjects() return self.staticMoving end
    function square:getTree() return self.tree end
    function square:isInARoom() return self.room == true end
    function square:haveFire() return self.fire == true end
    function square:getFloor()
        local floor = { owner = self }
        function floor:getTextureName() return self.owner.floorTexture end
        return floor
    end
    function square:transmitRemoveItemFromSquare(worldItem) removeIdentity(self.worldItems, worldItem) end
    function square:removeWorldObject(worldItem) removeIdentity(self.worldItems, worldItem) end
    function square:AddWorldInventoryItem(item)
        local wrapper = { item = item, square = self, x = self.x, y = self.y, z = self.z }
        function wrapper:getItem() return self.item end
        function wrapper:getSquare() return self.square end
        function wrapper:removeFromWorld()
            if self.square then removeIdentity(self.square.worldItems, self) end
        end
        function wrapper:removeFromSquare() self.square = nil end
        self.worldItems[#self.worldItems + 1] = wrapper
        item.container, item.worldItem = nil, wrapper
        return item
    end
    squares[squareKey(x, y, z)] = square
    return square
end

local cell = {}
function cell:getGridSquare(x, y, z) return squares[squareKey(x, y, z)] end
function getCell() return cell end

local function makeActor(id, square)
    local actor = {
        __class = "IsoPlayer", x = square.x, y = square.y, z = square.z, square = square,
        inventory = makeInventory("inventory"), modData = { SC_Id = id },
        enduranceOk = true, lines = {},
    }
    actor.characterActions = { values = {} }
    function actor.characterActions:add(value) self.values[#self.values + 1] = value end
    function actor.characterActions:remove(value) removeIdentity(self.values, value) end
    function actor.characterActions:contains(value)
        for _, candidate in ipairs(self.values) do if candidate == value then return true end end
        return false
    end
    function actor:getCharacterActions() return self.characterActions end
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getSquare() return self.square end
    function actor:getCurrentSquare() return self.square end
    function actor:getInventory() return self.inventory end
    function actor:getModData() return self.modData end
    function actor:isDead() return false end
    function actor:getPlayerNum() return 3 end
    function actor:getPrimaryHandItem() return self.primary end
    function actor:setPrimaryHandItem(item) self.primary = item end
    function actor:getSecondaryHandItem() return self.secondary end
    function actor:setSecondaryHandItem(item) self.secondary = item end
    function actor:isEnduranceSufficientForAction() return self.enduranceOk end
    function actor:addLineChatElement(line) self.lines[#self.lines + 1] = line end
    function actor:isMoving() return false end
    function actor:isDraggingCorpse() return self.draggedBody ~= nil end
    function actor:setDoGrappleLetGo()
        SC_TEST_LAND_DRAGGED(self, nil)
        return true
    end
    return actor
end

local function makeStorage(square)
    local object = { x = square.x, y = square.y, z = square.z,
        square = square, container = makeInventory("crate"), modData = {} }
    function object:getSquare() return self.square end
    function object:getContainer() return self.container end
    function object:getModData() return self.modData end
    function object:transmitModData() return true end
    function object:getObjectIndex()
        for index, value in ipairs(self.square.objects) do
            if value == self then return index - 1 end
        end
        return -1
    end
    function object:getObjectName() return "IsoObject" end
    square.objects[#square.objects + 1] = object
    return object
end

local function makeTree(square, health, options)
    options = options or {}
    local tree = { __class = "IsoTree", square = square, health = health or 12,
        size = options.size or 3, logYield = options.logs or 2 }
    function tree:getHealth() return self.health end
    function tree:getSize() return self.size end
    function tree:getObjectIndex() return self.removed and -1 or 0 end
    function tree:getSquare() return self.square end
    function tree:WeaponHit(character, weapon)
        if self.removed then return end
        self.health = self.health - (weapon and weapon.treeDamage or 5)
        if self.health <= 0 then
            self.removed = true
            self.square.tree = nil
            for _ = 1, self.logYield do self.square:AddWorldInventoryItem(makeItem("Base.Log")) end
        end
    end
    square.tree = tree
    return tree
end

local function makeGraveHalf(square, spriteType, north)
    local grave = { __class = "IsoThumpable", square = square, north = north == true,
        modData = { spriteType = spriteType, corpses = 0, filled = false } }
    function grave:getName() return "EmptyGraves" end
    function grave:getModData() return self.modData end
    function grave:getNorth() return self.north end
    function grave:getSquare() return self.square end
    square.specialObjects[#square.specialObjects + 1] = grave
    return grave
end

local function createGrave(x, y, z, north, halfOnly)
    local first = squares[squareKey(x, y, z)]
    local px, py = x - 1, y
    if north then px, py = x, y - 1 end
    local one = makeGraveHalf(first, "sprite1", north)
    if halfOnly then return one end
    local two = makeGraveHalf(squares[squareKey(px, py, z)], "sprite2", north)
    one.partner, two.partner = two, one
    return one, two
end

SC_TEST_CREATE_GRAVE = function(x, y, z, north, halfOnly) createGrave(x, y, z, north, halfOnly) end
SC_TEST_GRAVE_PARTNERS = function(grave) return grave.partner and { grave.partner } or {} end

local function makeBody(square, options)
    options = options or {}
    local body = { __class = "IsoDeadBody", square = square, x = square.x, y = square.y,
        z = square.z, modData = options.modData or {}, container = makeInventory("corpse"),
        fake = options.fake == true, animal = options.animal == true }
    function body:getModData() return self.modData end
    function body:getSquare() return self.square end
    function body:isFakeDead() return self.fake end
    function body:isAnimal() return self.animal end
    function body:getContainer() return self.container end
    if options.descriptor then
        local descriptor = options.descriptor
        function descriptor:getForename() return self.forename end
        function descriptor:getSurname() return self.surname end
        function descriptor:isFemale() return self.female == true end
        function body:getDescriptor() return descriptor end
    end
    if options.player == true then
        function body:isPlayer() return true end
    end
    for _, itemType in ipairs(options.items or {}) do body.container:AddItem(itemType) end
    square.staticMoving[#square.staticMoving + 1] = body
    return body
end

local function onSquare(square, body)
    for _, value in ipairs(square.staticMoving) do if value == body then return true end end
    return false
end

-- ---------------------------------------------------------------------------
-- Runtime seams: real SCNativeActions work family, stubbed movement/visuals
-- ---------------------------------------------------------------------------

local emotes = {}
local spokenTopics = {}
local directProvider = { directNative = true }

SC.Actor._isRegistryActor = function() return true end
SC.Actor.isCompanion = function() return true end
SC.Actor.stop = function() return true end
SC.Actor.setMovement = function(actor, mode, intent)
    local action = type(intent) == "table" and intent.action or nil
    if action and SC.NativeWorkActions.handles(action) then
        local ok, reason = SC.NativeWorkActions.dispatch(actor, action, intent, directProvider)
        return ok == true, reason
    end
    if action == "hand_signal" then
        emotes[#emotes + 1] = intent.emote
        return true, "emote_started"
    end
    return true, "visual_started"
end
SC.NativeActions.visualStatus = function() return "completed" end
SC.NativeActions.clearVisual = function() return true end
SC.NativeActions.cancelVisual = function() return true end
SC.NativeActions.stopDirect = function() return true end

local originalSay = SC.Dialogue.say
SC.Dialogue.say = function(actor, topic, specification, arguments, options)
    spokenTopics[#spokenTopics + 1] = { actor = actor, topic = topic }
    return originalSay(actor, topic, specification, arguments, options)
end

SC.Navigation = {
    cancel = function() return true end,
    interactionTargets = function(_, target)
        if type(target) == "table" and target.__square then
            local west = squares[squareKey(target.x - 1, target.y, target.z)]
            local east = squares[squareKey(target.x + 1, target.y, target.z)]
            return { west or east }
        end
        return { target }
    end,
    requestAny = function(actor, candidates)
        local target = SC.GameplayUtil.squareOf(candidates and candidates[1])
        if not target then return false, "fixture_target_missing" end
        if SC.GameplayUtil.sameSquare(actor, target) then return true, "arrived", target end
        actor.square, actor.x, actor.y, actor.z = target, target.x, target.y, target.z
        return true, "fixture_path_started", target
    end,
}

local contextSerial = 0

local function setup(options)
    options = options or {}
    contextSerial = contextSerial + 1
    SC.BaseWork.reset()
    SC.Production.reset()
    SC.BaseLife.reset()
    SC.Registry.reset()
    SC.NativeActions.resetWork()
    ISTimedActionQueue.queues = setmetatable({}, { __mode = "k" })
    SC_TEST_SAW_FAILS = false
    squares = {}
    for x = -6, 6 do
        for y = -6, 6 do makeSquare(x, y, 0) end
    end
    local core = sq(0, 0)
    local ok, base = SC.BaseLife.create(core, "Harness Camp")
    check(ok == true and base ~= nil, "base creation must succeed")
    local function zone(kind, x1, y1, x2, y2)
        check(SC.BaseLife.beginZone(kind, sq(x1, y1)) == true, kind .. " zone must begin")
        local zoneOk, value = SC.BaseLife.finishZone(sq(x2, y2), kind)
        check(zoneOk == true, kind .. " zone must finish: " .. tostring(value))
        return value
    end
    local lumber = zone("lumber", 2, 2, 4, 3)
    local burial = zone("burial", -4, -4, -1, -2)
    for x = -4, -1 do
        for y = -4, -2 do sq(x, y).floorTexture = "blends_natural_01_16" end
    end
    local toolsObject = makeStorage(sq(1, -1))
    local logsObject = makeStorage(sq(-1, 1))
    local planksObject = makeStorage(sq(1, 1))
    local toolsOk, tools = SC.BaseLife.registerStorage(toolsObject, "tools")
    local logsOk, logs = SC.BaseLife.registerStorage(logsObject, "general")
    local planksOk, planks = SC.BaseLife.registerStorage(planksObject, "construction")
    check(toolsOk == true and logsOk == true and planksOk == true, "storages must register")
    local actors = {}
    for index = 1, options.workers or 1 do
        local id = "sc-prod-" .. tostring(contextSerial) .. "-" .. tostring(index)
        local actor = makeActor(id, core)
        check(SC.Registry.register(actor, { id = id, recruited = true }) ~= nil,
            "worker must register")
        check(SC.BaseLife.assign(id, "generalist", true) == true, "worker must join base duty")
        actors[#actors + 1] = actor
    end
    emotes, spokenTopics = {}, {}
    return {
        base = base, lumber = lumber, burial = burial, tools = tools, logs = logs,
        planks = planks, toolsObject = toolsObject, logsObject = logsObject,
        planksObject = planksObject, actors = actors, actor = actors[1],
        id = actors[1] and actors[1].modData.SC_Id or nil,
    }
end

-- The default step outlasts the native facade's human pacing pause (at most
-- 2.75 s after a finished work action); timing-sensitive tests pass their own.
local function tick(ctx, runtime, actor, advance)
    SC_TEST_CLOCK = SC_TEST_CLOCK + (advance or 3000)
    return SC.BaseWork.update(actor or ctx.actor, nil, runtime or {})
end

local function current(actor)
    return ISTimedActionQueue.getTimedActionQueue(actor).current
end

local function start(ctx, spec)
    spec.workers = spec.workers or { ctx.id }
    local ok, order = SC.BaseLife.createProductionOrder(spec)
    check(ok == true and order ~= nil, "production order must be created: " .. tostring(order))
    return order
end

local function countType(container, fullType)
    local count = 0
    for _, item in ipairs(container.items) do
        if item.fullType == fullType then count = count + 1 end
    end
    return count
end

-- ---------------------------------------------------------------------------
-- Order schema, creation guards and persistence
-- ---------------------------------------------------------------------------

do
    local ctx = setup()
    local ok, reason = SC.BaseLife.createProductionOrder({
        operation = "smelt", workers = { ctx.id },
    })
    check(ok == false and reason == "unsupported_production_operation",
        "unknown production operations are rejected")
    ok, reason = SC.BaseLife.createProductionOrder({
        operation = "fell_trees", zoneId = ctx.burial.id, workers = { ctx.id },
        settings = { haulLogs = false },
    })
    check(ok == false and reason == "invalid_production_zone", "felling needs a lumber zone")
    ok, reason = SC.BaseLife.createProductionOrder({
        operation = "fell_trees", zoneId = ctx.lumber.id, workers = { ctx.id },
    })
    check(ok == false and reason == "invalid_production_destination",
        "hauling felled logs needs a registered destination")
    ok, reason = SC.BaseLife.createProductionOrder({
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.logs.id, workers = { ctx.id },
    })
    check(ok == false and reason == "production_storage_conflict",
        "sawing never deposits into its own source")
    SC.BaseLife.setDuty(ctx.id, false)
    ok, reason = SC.BaseLife.createProductionOrder({
        operation = "dig_graves", zoneId = ctx.burial.id, workers = { ctx.id },
    })
    check(ok == false and reason == "production_worker_off_duty",
        "an off-duty worker needs an explicit duty change")
    local order
    ok, order = SC.BaseLife.createProductionOrder({
        operation = "dig_graves", zoneId = ctx.burial.id, workers = { ctx.id },
        enableDuty = true, requested = 99,
    })
    check(ok == true and order.requested == 6, "requested quantity is clamped by the schema")
    check(SC.BaseLife.resident(ctx.id).duty == true, "creation enables duty when asked")
    local job
    for _, row in ipairs(SC.BaseLife.active().jobs) do
        if row.type == "production" then job = row end
    end
    check(job ~= nil and job.target.orderId == order.id and job.assignedId == ctx.id,
        "the production job targets its order and worker")
    local removed, removeReason = SC.BaseLife.removeZone(ctx.burial.id)
    check(removed == false and removeReason == "production_order_uses_zone",
        "an active production order pins its zone")
    local exported = SC.BaseLife.export()
    SC.BaseLife.reset()
    local restored, restoreReason = SC.BaseLife.restore(exported)
    check(restored == true, "production document restores: " .. tostring(restoreReason))
    local again = SC.BaseLife.productionOrder(order.id)
    check(again ~= nil and again.operation == "dig_graves" and again.requested == 6
        and again.state == "running", "a production order survives save/restore")
    local summary = SC.BaseLife.summary()
    check(#summary.productionOrders == 1 and summary.productionOrders[1].unit == "graves"
        and #summary.productionOrders[1].workerPhases == 1,
        "the base summary exposes production rows for the UI")
    check(SC.BaseLife.pauseProductionOrder(order.id, "player_paused") == true
        and SC.BaseLife.productionOrder(order.id).state == "paused", "orders pause")
    check(SC.BaseLife.resumeProductionOrder(order.id) == true
        and SC.BaseLife.productionOrder(order.id).state == "running", "orders resume")
    check(SC.BaseLife.completeProductionOrder(order.id) == false,
        "an order cannot complete before its quota is proven")
    check(SC.BaseLife.recordProductionProgress(order.id, 50) == true
        and SC.BaseLife.productionOrder(order.id).completed == 6,
        "progress is capped at the requested quantity")
    check(SC.BaseLife.completeProductionOrder(order.id, "graves_dug") == true,
        "a proven quota completes the order")
    local jobsLeft = 0
    for _, row in ipairs(SC.BaseLife.active().jobs) do
        if row.type == "production" then jobsLeft = jobsLeft + 1 end
    end
    check(jobsLeft == 0, "completion retires the production jobs")
end

do
    local ctx = setup()
    local order = start(ctx, {
        operation = "dig_graves", zoneId = ctx.burial.id, requested = 2,
    })
    local revision = SC.BaseLife.workConsistencyRevision()
    check(SC.BaseLife.recordProductionProgress(order.id, 1) == true
        and SC.BaseLife.workConsistencyRevision() > revision,
        "production progress advances the scheduled-save consistency revision")
    revision = SC.BaseLife.workConsistencyRevision()
    check(SC.BaseLife.noteProductionGrave(order.id, { x = -2, y = -3, z = 0 }) == true
        and SC.BaseLife.workConsistencyRevision() > revision,
        "tracked grave mutations advance the scheduled-save consistency revision")
    revision = SC.BaseLife.workConsistencyRevision()
    check(SC.BaseLife.noteProductionCounter("gravesDug", 1) == true
        and SC.BaseLife.workConsistencyRevision() > revision,
        "production counter mutations advance the scheduled-save consistency revision")
end

do
    local ctx = setup()
    local order = start(ctx, {
        operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        destinationStorageId = ctx.logs.id,
    })
    check(SC.BaseLife.linkProductionHaul(order.id, 98) == true,
        "the first linked hauling batch is created")
    check(SC.BaseLife.linkProductionHaul(order.id, 4) == true,
        "linked hauling accepts demand beyond one child cap")
    local total, active = 0, 0
    for _, gather in ipairs(SC.BaseLife.workOrders(false)) do
        if gather.material == "logs" and gather.zoneId == ctx.lumber.id then
            total, active = total + gather.requested, active + 1
        end
    end
    local saved = SC.BaseLife.productionOrder(order.id)
    check(total == 102 and active == 2 and saved.pendingHaul == 0,
        "98 + 4 logs remain represented as 100 + 2 linked demand")
    check(SC.BaseLife.workOrder(saved.linkedGatherOrderId).requested == 2,
        "the production order points at the newest overflow child")
end

do
    local ctx = setup()
    local exported = SC.BaseLife.export()
    local base = exported.bases[exported.activeBaseId]
    base.production = {
        version = 1, nextOrderSerial = 3,
        orders = {
            { id = "production-order:1", operation = "smelt_iron", requested = 2,
                workers = { ctx.id }, state = "running" },
        },
        counters = { treesFelled = 4 },
    }
    local ok, reason = SC.BaseLife.restore(exported)
    check(ok == true, "unknown operation rows restore: " .. tostring(reason))
    check(#SC.BaseLife.productionOrders(true) == 0, "an unknown operation never enters runtime work")
    local saved = SC.BaseLife.export().bases[exported.activeBaseId].production
    check(type(saved.quarantine) == "table" and type(saved.quarantine.orders) == "table"
        and saved.quarantine.orders[1].operation == "smelt_iron",
        "an unknown operation row is re-emitted unchanged")
    check(saved.counters.treesFelled == 4, "production counters survive restore")
    check(SC.BaseLife.registerProductionOperation("smelt_iron", {
        unit = "bars", maxRequested = 5, defaultRequested = 1, settings = {},
    }) == true, "a new operation schema registers")
    check(SC.BaseLife.restore(SC.BaseLife.export()) == true, "the quarantined document reloads")
    local promoted = SC.BaseLife.productionOrder("production-order:1")
    check(promoted ~= nil and promoted.operation == "smelt_iron" and promoted.state == "running",
        "a quarantined row returns to service once its operation is known")
    SC.BaseLife.PRODUCTION_OPERATIONS.smelt_iron = nil
    check(SC.BaseLife.registerProductionOperation("bad id!", { unit = "x",
        maxRequested = 1, defaultRequested = 1 }) == false, "operation ids are validated")
end

do
    local ctx = setup()
    local exported = SC.BaseLife.export()
    local base = exported.bases[exported.activeBaseId]
    base.production = {
        version = 1, nextOrderSerial = 2,
        orders = {
            { id = "production-order:1", operation = "dig_graves", zoneId = ctx.burial.id,
                requested = 1, workers = {}, state = "running" },
        },
    }
    check(SC.BaseLife.restore(exported) == false,
        "a running production order without workers blocks restore")
    base.production.orders[1].workers = { ctx.id }
    base.production.orders[1].zoneId = ctx.lumber.id
    check(SC.BaseLife.restore(exported) == false,
        "an active order bound to the wrong zone kind blocks restore")
    base.production = { version = 99, anything = { nested = true } }
    check(SC.BaseLife.restore(exported) == true, "a future production document is preserved")
    local saved = SC.BaseLife.export().bases[exported.activeBaseId].production
    check(type(saved.quarantine) == "table"
        and saved.quarantine.reason == "unsupported_production_version"
        and saved.quarantine.raw.version == 99,
        "a future production document is quarantined unchanged")
end

-- ---------------------------------------------------------------------------
-- Fell trees: native events, verified felling, linked hauling
-- ---------------------------------------------------------------------------

do
    local ctx = setup()
    local axe = makeItem("Base.Axe", { tags = { choptree = true }, twoHanded = true, treeDamage = 5 })
    ctx.actor.inventory:AddItem(axe)
    local tree = makeTree(sq(3, 2), 10, { logs = 2 })
    local order = start(ctx, {
        operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        destinationStorageId = ctx.logs.id,
    })
    local handled, reason = tick(ctx)
    check(handled == true and reason == "production_chop_started",
        "the worker starts the native chop: " .. tostring(reason))
    local action = current(ctx.actor)
    check(action ~= nil and action.Type == "ISChopTreeAction" and action.tree == tree,
        "vanilla ISChopTreeAction owns the tree")
    check(ctx.actor.primary == axe and ctx.actor.secondary == axe, "a two-handed axe is equipped")
    check(SC.NativeActions.workKind(ctx.actor) == "chop_tree", "the work family tracks the chop")
    action:animEvent("ChopTree")
    handled, reason = tick(ctx)
    check(handled == true and reason == "production_chopping", "chopping continues")
    check(SC.Production.diagnostics().chopNativeEvents == true,
        "a native hit proves the animation events reach the companion")
    action:animEvent("ChopTree")
    check(tree.removed == true and #sq(3, 2).worldItems == 2, "the felled tree drops its logs")
    action:perform()
    handled, reason = tick(ctx)
    check(reason == "production_order_completed", "felling completes the order: " .. tostring(reason))
    local saved = SC.BaseLife.productionOrder(order.id)
    check(saved.state == "completed" and saved.completed == 1, "the tree is counted once")
    check(ctx.actor.primary == nil and ctx.actor.secondary == nil, "hands are restored after work")
    local counters = SC.BaseLife.productionCounters()
    check(counters.treesFelled == 1 and counters.logsDropped == 2,
        "counters record the verified felling")
    local gather = SC.BaseLife.workOrder(saved.linkedGatherOrderId)
    check(gather ~= nil and gather.material == "logs" and gather.requested == 2
        and gather.zoneId == ctx.lumber.id and gather.destinationStorageId == ctx.logs.id,
        "felled logs link one gathering order over the lumber zone")
    local valid = SC.GatherWork.validateZone(gather)
    check(valid == true, "gathering accepts a lumber zone")
end

do
    local ctx = setup()
    local axe = makeItem("Base.Axe", { tags = { choptree = true }, treeDamage = 2 })
    ctx.actor.inventory:AddItem(axe)
    local tree = makeTree(sq(3, 2), 20)
    start(ctx, { operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        settings = { haulLogs = false } })
    local _, reason = tick(ctx)
    check(reason == "production_chop_started", "the fallback chop starts: " .. tostring(reason))
    local action = current(ctx.actor)
    tick(ctx, nil, nil, 3000)
    check(action.hits == nil, "no emulated hit inside the stall window")
    tick(ctx, nil, nil, 3500)
    check(action.hits == 1 and tree.health == 18, "a stalled chop receives one server-parity hit")
    check(SC.Production.diagnostics().chopFallback == true, "the fallback is enabled after a stall")
    tick(ctx, nil, nil, 500)
    check(action.hits == 1, "the fallback honours the 1500 ms cadence")
    tick(ctx, nil, nil, 1100)
    check(action.hits == 2, "a second emulated hit follows the cadence")
    action:animEvent("ChopTree")
    tick(ctx, nil, nil, 1600)
    local diagnostics = SC.Production.diagnostics()
    check(diagnostics.chopNativeEvents == true and diagnostics.chopFallback == false,
        "a native hit disables the fallback for the session")
    check(action.hits == 3, "no emulation runs once native events are proven")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Axe", { tags = { choptree = true }, treeDamage = 1 }))
    makeTree(sq(3, 2), 1000)
    local order = start(ctx, { operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        settings = { haulLogs = false } })
    local _, reason = tick(ctx)
    check(reason == "production_chop_started", "the capped chop starts")
    local _, timeoutReason = tick(ctx, nil, nil, 181000)
    check(timeoutReason == "chop_timeout" and SC.NativeActions.isWorkActive(ctx.actor) ~= true,
        "the hard cap cancels an endless chop: " .. tostring(timeoutReason))
    check(SC.BaseLife.productionOrder(order.id).completed == 0, "a timed-out tree is not counted")
    check(ctx.actor.primary == nil, "cancelled work restores the hands")
    ctx.actor.enduranceOk = false
    local handled, restReason = tick(ctx)
    check(handled == true and restReason == "production_resting",
        "a winded worker rests before chopping: " .. tostring(restReason))
    local _, exhaustedReason = tick(ctx, nil, nil, 61000)
    check(exhaustedReason == "worker_exhausted"
        and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "rest is bounded and then blocks with a reason")
end

do
    local ctx = setup()
    local runtime = { snapshot = { threats = { { distanceSq = 25 } } } }
    ctx.actor.inventory:AddItem(makeItem("Base.Axe", { tags = { choptree = true } }))
    makeTree(sq(3, 2), 10)
    start(ctx, { operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        settings = { haulLogs = false } })
    local _, reason = tick(ctx, runtime)
    check(reason == "unsafe_area" and current(ctx.actor) == nil,
        "loud work never starts with a visible threat nearby: " .. tostring(reason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Axe", { tags = { choptree = true } }))
    makeTree(sq(3, 2), 10)
    start(ctx, { operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        settings = { haulLogs = false } })
    local originalMove = SC.Actor.setMovement
    SC.Actor.setMovement = function(actor, mode, intent)
        if type(intent) == "table" and intent.action == "chop_tree" then
            return false, "action_pacing:dismantle"
        end
        return originalMove(actor, mode, intent)
    end
    local handled, reason = tick(ctx)
    SC.Actor.setMovement = originalMove
    check(handled == true and reason == "action_pacing:dismantle",
        "a pacing rejection is a wait, not a failure: " .. tostring(reason))
    local _, started = tick(ctx)
    check(started == "production_chop_started",
        "the same tree starts once the pause ends: " .. tostring(started))
end

do
    local ctx = setup()
    makeTree(sq(3, 2), 10)
    local order = start(ctx, { operation = "fell_trees", zoneId = ctx.lumber.id, requested = 1,
        settings = { haulLogs = false } })
    local _, reason = tick(ctx)
    check(reason == "missing_tool:choptree"
        and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "a missing axe blocks with a readable reason: " .. tostring(reason))
    local axe = makeItem("Base.Axe", { tags = { choptree = true } })
    ctx.toolsObject.container:AddItem(axe)
    tick(ctx, nil, nil, 11000)
    check(SC.BaseLife.productionOrder(order.id).state == "blocked",
        "a blocked order honours its bounded retry cadence")
    for _ = 1, 4 do
        tick(ctx, nil, nil, 21000)
        if axe.container == ctx.actor.inventory then break end
    end
    check(axe.container == ctx.actor.inventory,
        "the axe is fetched through the verified storage withdrawal")
end

-- ---------------------------------------------------------------------------
-- Lumber areas outside the camp: bounded reach band, admission, night pause
-- ---------------------------------------------------------------------------

local function outsideLumber(ctx)
    for x = 7, 42 do
        for y = -2, 4 do makeSquare(x, y, 0) end
    end
    check(SC.BaseLife.beginZone("lumber", sq(20, 0)) == true, "an outside lumber area begins")
    local ok, zone = SC.BaseLife.finishZone(sq(23, 2), "Forest")
    check(ok == true and zone.kind == "lumber",
        "a lumber area may lie outside the camp inside the reach band: " .. tostring(zone))
    return zone
end

do
    local ctx = setup()
    local outside = outsideLumber(ctx)
    check(SC.BaseLife.beginZone("lumber", sq(38, 0)) == true, "a far lumber draft begins")
    local far, farReason = SC.BaseLife.finishZone(sq(41, 1), "Too far")
    check(far == false and farReason == "lumber_zone_out_of_reach",
        "a lumber area beyond the reach band is refused: " .. tostring(farReason))
    SC.BaseLife.cancelZone()
    check(SC.BaseLife.beginZone("rest", sq(20, 0)) == true, "an outside rest draft begins")
    local rest, restReason = SC.BaseLife.finishZone(sq(21, 1), "rest")
    check(rest == false and restReason == "zone_outside_base_area",
        "every other zone kind stays inside the camp")
    SC.BaseLife.cancelZone()
    local reachIntent = { workCampOnly = true, workReach = true }
    check(SC.BaseLife.admitsWork(sq(20, 0), reachIntent) == true
        and SC.BaseLife.admitsWork(sq(20, 0), { workCampOnly = true }) == false
        and SC.BaseLife.admitsWork(sq(40, 0), reachIntent) == false
        and SC.BaseLife.admitsWork(sq(0, 0), { workCampOnly = true }) == true,
        "only lumber work crosses the bounded reach band")
    local axe = makeItem("Base.Axe", { tags = { choptree = true }, treeDamage = 20 })
    ctx.actor.inventory:AddItem(axe)
    makeTree(sq(21, 1), 10, { logs = 3 })
    local order = start(ctx, {
        operation = "fell_trees", zoneId = outside.id, requested = 1,
        destinationStorageId = ctx.logs.id,
    })
    local intents = {}
    local originalRequestAny = SC.Navigation.requestAny
    SC.Navigation.requestAny = function(actor, candidates, mode, intent)
        intents[#intents + 1] = intent
        return originalRequestAny(actor, candidates, mode, intent)
    end
    local _, reason = tick(ctx)
    check(reason == "production_chop_started",
        "the worker fells a tree outside the camp: " .. tostring(reason))
    check(intents[#intents].workCampOnly == true and intents[#intents].workReach == true,
        "the felling trip asks for reach-band admission")
    check(SC.BaseLife.isInside(ctx.actor) ~= true, "the worker stands outside the camp")
    local handled, still = tick(ctx)
    check(handled == true and still == "production_chopping",
        "base work never drags an outside lumber worker home: " .. tostring(still))
    current(ctx.actor):animEvent("ChopTree")
    current(ctx.actor):perform()
    local _, done = tick(ctx)
    check(done == "production_order_completed", "the outside tree counts: " .. tostring(done))
    local gather = SC.BaseLife.workOrder(SC.BaseLife.productionOrder(order.id).linkedGatherOrderId)
    check(gather ~= nil and gather.zoneId == outside.id and gather.requested == 3
        and SC.GatherWork.validateZone(gather) == true,
        "the linked haul gathers from the outside lumber area")
    local gatherTrip = false
    for _ = 1, 4 do
        tick(ctx)
        for _, intent in ipairs(intents) do
            if intent.action == "move_to_gather_item" and intent.workReach == true then
                gatherTrip = true
            end
        end
        if gatherTrip then break end
    end
    SC.Navigation.requestAny = originalRequestAny
    check(gatherTrip, "hauling logs from the lumber area also uses reach admission")
    check(SC.BaseLife.isInside(ctx.actor) ~= true,
        "a lumber-area gathering job may keep the worker outside the camp")
end

do
    local ctx = setup()
    local outside = outsideLumber(ctx)
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    ctx.actor.inventory:AddItem(makeItem("Base.Axe", { tags = { choptree = true } }))
    local requests = {}
    SC.Navigation.request = function(actor, square, mode, intent)
        requests[#requests + 1] = intent
        return true, "fixture_path_started", square
    end
    ctx.actor.square, ctx.actor.x, ctx.actor.y = sq(22, 1), 22, 1
    local dig = start(ctx, { operation = "dig_graves", zoneId = ctx.burial.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "fixture_path_started" and requests[1] ~= nil
        and requests[1].action == "return_to_base",
        "non-lumber work outside the camp walks home first: " .. tostring(reason))
    check(SC.BaseLife.cancelProductionOrder(dig.id) == true, "the dig order cancels")
    makeTree(sq(22, 2), 10)
    start(ctx, { operation = "fell_trees", zoneId = outside.id, requested = 1,
        settings = { haulLogs = false } })
    ctx.actor.square, ctx.actor.x, ctx.actor.y = sq(41, 1), 41, 1
    requests = {}
    tick(ctx)
    check(requests[1] ~= nil and requests[1].action == "return_to_base",
        "a worker beyond the reach band walks home even with lumber work")
    SC.Navigation.request = nil
end

do
    local ctx = setup()
    local outside = outsideLumber(ctx)
    ctx.actor.inventory:AddItem(makeItem("Base.Axe", { tags = { choptree = true } }))
    makeTree(sq(21, 1), 10)
    local order = start(ctx, { operation = "fell_trees", zoneId = outside.id, requested = 1,
        settings = { haulLogs = false } })
    local previousGameTime = getGameTime
    local hour = 23
    getGameTime = function()
        local gameTime = {}
        function gameTime:getTimeOfDay() return hour end
        return gameTime
    end
    local _, reason = tick(ctx)
    check(reason == "lumber_night" and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "outside the camp, felling starts no tree at night: " .. tostring(reason))
    hour = 9
    tick(ctx, nil, nil, 31000)
    getGameTime = previousGameTime
    check(SC.NativeActions.workKind(ctx.actor) == "chop_tree", "felling resumes in daylight")
end

-- ---------------------------------------------------------------------------
-- Saw planks: pinned inputs, proven outputs, verified deposits
-- ---------------------------------------------------------------------------

do
    local ctx = setup()
    local saw = makeItem("Base.Saw", { tags = { saw = true } })
    ctx.actor.inventory:AddItem(saw)
    ctx.logsObject.container:AddItem("Base.Log")
    ctx.logsObject.container:AddItem("Base.Log")
    local order = start(ctx, {
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.planks.id, requested = 3,
    })
    local reason
    for _ = 1, 4 do
        local _, value = tick(ctx)
        reason = value
        if SC.NativeActions.workKind(ctx.actor) == "saw_logs" then break end
    end
    check(SC.NativeActions.workKind(ctx.actor) == "saw_logs",
        "sawing starts after one verified log withdrawal: " .. tostring(reason))
    local action = current(ctx.actor)
    check(action.Type == "ISHandcraftAction" and action.craftRecipe == SC_TEST_SAW_RECIPE,
        "the vanilla SawLogs recipe drives the craft")
    local pinnedLog = action.manualInputs[0]:get(0)
    check(action.manualInputs[1]:get(0) == saw, "the saw is pinned as the kept input")
    check(pinnedLog.modData.LF_ProductionOrderId == order.id,
        "the withdrawn log carries the order marker")
    check(countType(ctx.logsObject.container, "Base.Log") == 1, "exactly one log left the source")
    action:perform()
    local _, madeReason = tick(ctx)
    check(madeReason == "production_planks_made", "three new planks are proven: " .. tostring(madeReason))
    for _ = 1, 10 do
        tick(ctx)
        if SC.BaseLife.productionOrder(order.id).state == "completed" then break end
    end
    local saved = SC.BaseLife.productionOrder(order.id)
    check(saved.state == "completed" and saved.completed == 3, "three planks are delivered")
    check(countType(ctx.planksObject.container, "Base.Plank") == 3, "the destination holds the planks")
    for _, item in ipairs(ctx.planksObject.container.items) do
        check(item.modData.LF_ProductionOrderId == nil, "a delivered plank loses its work marker")
    end
    check(SC.BaseLife.productionCounters().planksMade == 3, "planks are counted once")
end

do
    local ctx = setup()
    local saw = makeItem("Base.Saw", { tags = { saw = true } })
    ctx.actor.inventory:AddItem(saw)
    ctx.logsObject.container:AddItem("Base.Log")
    local order = start(ctx, {
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.planks.id, requested = 3,
    })
    local restoredLog = makeItem("Base.Log", { modData = { LF_ProductionOrderId = order.id } })
    ctx.actor.inventory:AddItem(restoredLog)
    local _, reason = tick(ctx)
    check(reason == "production_sawing" and countType(ctx.logsObject.container, "Base.Log") == 1,
        "a restored marked log is sawn without a second withdrawal: " .. tostring(reason))
    SC_TEST_SAW_FAILS = true
    local blocked
    for _ = 1, 8 do
        local queued = current(ctx.actor)
        if queued then queued:perform() end
        local _, value = tick(ctx)
        if SC.BaseLife.productionOrder(order.id).state == "blocked" then blocked = value break end
    end
    check(blocked == "saw_incomplete", "an unproven craft blocks after bounded attempts: "
        .. tostring(blocked))
    SC_TEST_SAW_FAILS = false
    check(SC.BaseLife.cancelProductionOrder(order.id) == true, "the saw order cancels")
    check(restoredLog.modData.LF_ProductionOrderId == nil,
        "cancellation clears the order marker from carried cargo")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Saw", { tags = { saw = true } }))
    ctx.logsObject.container:AddItem("Base.Log")
    ctx.logsObject.container:AddItem("Base.Log")
    local order = start(ctx, {
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.planks.id, requested = 3,
    })
    local revision = SC.BaseLife.workConsistencyRevision()
    for _ = 1, 4 do
        tick(ctx)
        if SC.NativeActions.workKind(ctx.actor) == "saw_logs" then break end
    end
    check(type(ctx.actor.modData.LF_ProductionSawReceipt) == "table"
        and SC.BaseLife.workConsistencyRevision() > revision,
        "a running saw action persists its precondition and invalidates staged saves")
    current(ctx.actor):perform()
    check(SC.BaseLife.pauseProductionOrder(order.id, "player_paused") == true,
        "a completed-but-unpolled saw action reconciles while pausing")
    local carried = 0
    for _, item in ipairs(ctx.actor.inventory.items) do
        if item.fullType == "Base.Plank" and item.modData.LF_ProductionOrderId == order.id then
            carried = carried + 1
        end
    end
    check(carried == 3 and ctx.actor.modData.LF_ProductionSawReceipt == nil
        and countType(ctx.logsObject.container, "Base.Log") == 1,
        "pause adopts each completed plank once without withdrawing a replacement log")
    check(SC.BaseLife.resumeProductionOrder(order.id) == true, "the reconciled saw order resumes")
    for _ = 1, 12 do
        tick(ctx)
        if SC.BaseLife.productionOrder(order.id).state == "completed" then break end
    end
    check(SC.BaseLife.productionOrder(order.id).state == "completed"
        and countType(ctx.logsObject.container, "Base.Log") == 1
        and countType(ctx.planksObject.container, "Base.Plank") == 3,
        "resume delivers reconciled output without consuming another source log")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Saw", { tags = { saw = true } }))
    ctx.logsObject.container:AddItem("Base.Log")
    local order = start(ctx, {
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.planks.id, requested = 3,
    })
    for _ = 1, 4 do
        tick(ctx)
        if SC.NativeActions.workKind(ctx.actor) == "saw_logs" then break end
    end
    local realCancelWork = SC.NativeActions.cancelWork
    SC.NativeActions.cancelWork = function() return false, "fixture_cancel_refused" end
    local paused, pauseReason = SC.BaseLife.pauseProductionOrder(order.id, "player_paused")
    SC.NativeActions.cancelWork = realCancelWork
    check(paused == false and pauseReason == "fixture_cancel_refused"
        and SC.BaseLife.productionOrder(order.id).state == "running"
        and SC.NativeActions.isWorkActive(ctx.actor) == true,
        "a refused native cancellation preserves both the running order and action state")
    check(SC.BaseLife.pauseProductionOrder(order.id, "player_paused") == true,
        "the same saw action can be cancelled cleanly on a later attempt")
    check(countType(ctx.actor.inventory, "Base.Log") == 1
        and countType(ctx.actor.inventory, "Base.Plank") == 0,
        "pausing before completion conserves the exact input and creates no output")
end

do
    local ctx = setup()
    local order = start(ctx, {
        operation = "saw_planks", sourceStorageId = ctx.logs.id,
        destinationStorageId = ctx.planks.id, requested = 3,
    })
    local oldA = ctx.actor.inventory:AddItem("Base.Plank")
    local oldB = ctx.actor.inventory:AddItem("Base.Plank")
    local made = {
        ctx.actor.inventory:AddItem("Base.Plank"),
        ctx.actor.inventory:AddItem("Base.Plank"),
        ctx.actor.inventory:AddItem("Base.Plank"),
    }
    ctx.actor.modData.LF_ProductionSawReceipt = {
        orderId = order.id, logKey = "native:gone", beforeCount = 2, startedAt = 10,
    }
    check(SC.Production.cancelActor(ctx.actor, "reload_teardown") == true,
        "an orphaned persisted saw receipt reconciles during cancellation")
    check(oldA.modData.LF_ProductionOrderId == nil and oldB.modData.LF_ProductionOrderId == nil,
        "receipt reconciliation never adopts planks that predated the action")
    check(made[1].modData.LF_ProductionOrderId == order.id
        and made[2].modData.LF_ProductionOrderId == order.id
        and made[3].modData.LF_ProductionOrderId == order.id,
        "receipt reconciliation adopts only the restored action's output delta")
end

-- ---------------------------------------------------------------------------
-- Graves: dig, bury, fill, ceremony
-- ---------------------------------------------------------------------------

do
    local ctx = setup()
    local shovel = makeItem("Base.Shovel", { tags = { diggrave = true } })
    ctx.actor.inventory:AddItem(shovel)
    start(ctx, { operation = "dig_graves", zoneId = ctx.burial.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "production_digging", "the worker digs on natural ground: " .. tostring(reason))
    local action = current(ctx.actor)
    check(action.Type == "SCCompanionGraveAction" and action.item.character == ctx.actor
        and action.x == -3 and action.y == -4,
        "the companion grave action carries its builder and the first valid site")
    check(action.bridgedPlayer == ctx.actor and getSpecificPlayer(3) == nil,
        "getSpecificPlayer is bridged only while the grave action starts")
    check(not (ctx.actor.x == -4 and ctx.actor.y == -4) and not (ctx.actor.x == -3 and ctx.actor.y == -4),
        "the digger never stands on either grave half")
    action:perform()
    local _, doneReason = tick(ctx)
    check(doneReason == "production_order_completed",
        "a verified grave completes the order: " .. tostring(doneReason))
    check(#sq(-3, -4).specialObjects == 1 and #sq(-4, -4).specialObjects == 1,
        "both grave halves exist")
    check(SC.BaseLife.productionCounters().gravesDug == 1, "the grave is counted")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local order = start(ctx, { operation = "dig_graves", zoneId = ctx.burial.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "production_digging", "the half-grave test starts digging")
    local action = current(ctx.actor)
    action.item.halfOnly = true
    action:perform()
    local _, incompleteReason = tick(ctx)
    check(incompleteReason == "dig_incomplete"
        and SC.BaseLife.productionOrder(order.id).completed == 0,
        "a single grave half is never counted: " .. tostring(incompleteReason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    for x = -4, -1 do
        for y = -4, -2 do sq(x, y).floorTexture = "floors_interior_tilesandwood_01_0" end
    end
    local order = start(ctx, { operation = "dig_graves", zoneId = ctx.burial.id, requested = 1 })
    local reason
    for _ = 1, 4 do
        local _, value = tick(ctx)
        reason = value
        if SC.BaseLife.productionOrder(order.id).state == "blocked" then break end
    end
    check(reason == "grave-site_area_empty" and current(ctx.actor) == nil,
        "graves are dug only on natural ground: " .. tostring(reason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local grave, partner = createGrave(-2, -3, 0, false)
    local carrying = makeBody(sq(-1, -3), { items = { "Base.Hat" } })
    local fake = makeBody(sq(-2, -4), { fake = true })
    local staleCarrying = makeBody(sq(-2, -2), { items = { "Base.Hat" },
        modData = { lastPlayerGrabbed = 3 } })
    local victim = makeBody(sq(-2, -2))
    local order = start(ctx, { operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "production_burying", "the worker buries a graveside body: " .. tostring(reason))
    check(victim.modData.lastPlayerGrabbed == 3 and staleCarrying.modData.lastPlayerGrabbed == nil,
        "exactly one body carries the burier tag")
    local action = current(ctx.actor)
    check(action.Type == "ISBuryCorpse" and action.grave == grave and action.bodySquare == sq(-2, -2),
        "vanilla ISBuryCorpse receives the grave and body square")
    action:perform()
    local _, buriedReason = tick(ctx)
    check(buriedReason == "production_body_buried" and not onSquare(sq(-2, -2), victim)
        and onSquare(sq(-2, -2), staleCarrying),
        "only the tagged body is buried: " .. tostring(buriedReason))
    check(grave.modData.corpses == 1 and partner.modData.corpses == 1, "both halves count the body")
    local _, fillReason = tick(ctx)
    check(fillReason == "production_filling", "the finished order fills its grave: " .. tostring(fillReason))
    current(ctx.actor):perform()
    local before = #spokenTopics
    local _, closedReason = tick(ctx)
    check(closedReason == "production_grave_closed" and grave.modData.filled == true,
        "a verified fill closes the grave: " .. tostring(closedReason))
    local ceremonyTopic = spokenTopics[#spokenTopics] and spokenTopics[#spokenTopics].topic or nil
    check(#spokenTopics == before + 1
        and (ceremonyTopic == "burial.prayer" or ceremonyTopic == "burial.gallows"),
        "the ceremony speaks one prayer or gallows line: " .. tostring(ceremonyTopic))
    local _, pacingReason = tick(ctx, nil, nil, 50)
    check(pacingReason == "production_pacing",
        "production waits out the native pacing pause: " .. tostring(pacingReason))
    local _, saluteReason = tick(ctx)
    check(saluteReason == "production_ceremony" and emotes[#emotes] == "salute",
        "the ceremony salutes after the pause: " .. tostring(saluteReason))
    local _, doneReason = tick(ctx)
    check(doneReason == "production_order_completed"
        and SC.BaseLife.productionOrder(order.id).state == "completed",
        "the burial order completes after closing: " .. tostring(doneReason))
    check(onSquare(sq(-1, -3), carrying) and onSquare(sq(-2, -4), fake),
        "bodies with belongings and fake-dead zombies are never buried")
    local counters = SC.BaseLife.productionCounters()
    check(counters.bodiesBuried == 1 and counters.gravesClosed == 1, "burial counters are exact")
end

do
    local ctx = setup({ workers = 2 })
    for _, actor in ipairs(ctx.actors) do
        actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    end
    local grave = createGrave(-2, -3, 0, false)
    makeBody(sq(-2, -2))
    local order = start(ctx, {
        operation = "bury_bodies", zoneId = ctx.burial.id, requested = 2,
        workers = { ctx.actors[1].modData.SC_Id, ctx.actors[2].modData.SC_Id },
        settings = { closeWhenDone = false, digIfNeeded = false },
    })
    local _, firstReason = tick(ctx, nil, ctx.actors[1])
    check(firstReason == "production_burying" and current(ctx.actors[1]) ~= nil,
        "the first burial worker owns the physical target")
    local secondHandled, secondReason = tick(ctx, nil, ctx.actors[2])
    check(secondHandled == true and current(ctx.actors[2]) == nil
        and (secondReason == "production_burial_pair_pending"
            or secondReason == "production_burial_targets_claimed"),
        "a second worker cannot queue the claimed body or grave: " .. tostring(secondReason))
    current(ctx.actors[1]):perform()
    local _, buriedReason = tick(ctx, nil, ctx.actors[1])
    tick(ctx, nil, ctx.actors[2])
    check(buriedReason == "production_body_buried"
        and SC.BaseLife.productionOrder(order.id).completed == 1
        and SC.BaseLife.productionCounters().bodiesBuried == 1
        and grave.modData.corpses == 1,
        "one physical burial produces exactly one order credit with two workers")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local empty = createGrave(-3, -4, 0, false)
    local usable = createGrave(-2, -2, 0, false)
    makeBody(sq(-2, -2))
    local realConfig = SC.GameplayUtil.config
    SC.GameplayUtil.config = function(key)
        if key == "productionBurialBodyRadius" then return 0 end
        return realConfig(key)
    end
    local order = start(ctx, {
        operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { closeWhenDone = false, digIfNeeded = false },
    })
    local _, firstReason = tick(ctx)
    local _, secondReason = tick(ctx)
    SC.GameplayUtil.config = realConfig
    check(firstReason == "production_burial_pair_pending"
        and secondReason == "production_burying" and current(ctx.actor) ~= nil
        and current(ctx.actor).grave == usable and current(ctx.actor).grave ~= empty,
        "an empty remembered grave cannot starve a later viable grave/body pair")
    current(ctx.actor):perform()
    tick(ctx)
    check(SC.BaseLife.productionOrder(order.id).completed == 1,
        "burial progresses at the viable grave")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    makeBody(sq(-1, -3), { items = { "Base.Hat" } })
    local order = start(ctx, { operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1 })
    local reason
    for _ = 1, 4 do
        local _, value = tick(ctx)
        reason = value
        if SC.BaseLife.productionOrder(order.id).state == "blocked" then break end
    end
    check(reason == "bodies_carry_items:1"
        and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "bodies carrying items block with a count: " .. tostring(reason))
    check(SC.BaseLife.cancelProductionOrder(order.id) == true, "the blocked burial cancels")
    local withBelongings = start(ctx, {
        operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { withBelongings = true, closeWhenDone = false },
    })
    local _, buryReason = tick(ctx)
    check(buryReason == "production_burying",
        "an explicit belongings order buries the body: " .. tostring(buryReason))
    current(ctx.actor):perform()
    tick(ctx)
    local _, doneReason = tick(ctx)
    check(doneReason == "production_order_completed"
        and SC.BaseLife.productionOrder(withBelongings.id).state == "completed",
        "without closing, the order completes after the burial: " .. tostring(doneReason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    local diary = makeItem("LivingFellows.PrivateDiary", { favorite = true, modData = {
        LF_Diary = { schema = 1, diaryId = "diary:sc-fallen:1", authorId = "sc-fallen",
            authorName = "Fallen Author", authoredLocale = "EN", volume = 1, revision = 0,
            entryCount = 0, entries = {} },
    } })
    local body = makeBody(sq(-1, -3))
    body.container:AddItem(diary)
    local order = start(ctx, {
        operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { withBelongings = true, closeWhenDone = false },
    })
    local buried = false
    for _ = 1, 4 do
        local _, value = tick(ctx)
        if value == "production_burying" then buried = true end
    end
    check(SC.DiaryItem ~= nil and not buried and body.container:contains(diary)
        and SC.BaseLife.productionOrder(order.id).completed == 0,
        "a body carrying a private diary is never buried, even with its belongings")
    SC.BaseLife.cancelProductionOrder(order.id)
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local victim = makeBody(sq(-2, -2))
    local order = start(ctx, { operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1 })
    local reason
    for _ = 1, 6 do
        local _, value = tick(ctx)
        reason = value
        if SC.NativeActions.workKind(ctx.actor) == "dig_grave" then break end
    end
    check(SC.NativeActions.workKind(ctx.actor) == "dig_grave",
        "burial digs a grave when none is open: " .. tostring(reason))
    current(ctx.actor):perform()
    tick(ctx)
    check(#SC.BaseLife.productionOrder(order.id).graves == 1
        and SC.BaseLife.productionOrder(order.id).completed == 0,
        "the dug grave is remembered without counting it as a burial")
    check(onSquare(sq(-2, -2), victim), "the body waits for its grave")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    local order = start(ctx, { operation = "bury_bodies", zoneId = ctx.burial.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "production_burial_pair_pending"
        and SC.BaseLife.productionOrder(order.id).state == "running",
        "one empty grave is skipped before the whole burial area is exhausted")
    for _ = 1, 8 do
        _, reason = tick(ctx, nil, nil, 31000)
        if SC.BaseLife.productionOrder(order.id).state == "blocked" then break end
    end
    local digs = 0
    for x = -4, -1 do
        for y = -4, -2 do
            for _, object in ipairs(sq(x, y).specialObjects) do
                if object.modData.spriteType == "sprite1" then digs = digs + 1 end
            end
        end
    end
    check(digs == 1 and SC.NativeActions.workKind(ctx.actor) ~= "dig_grave"
        and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "without any eligible body, burial blocks without digging an unrelated grave: "
            .. tostring(reason))
end

-- ---------------------------------------------------------------------------
-- Collect and burn the dead: grapple, drag, tag, then bury or burn
-- ---------------------------------------------------------------------------

local function makeLighter()
    return makeItem("Base.Lighter", { tags = { startfire = true } })
end

local function makePetrol(amount)
    local can = makeItem("Base.PetrolCan")
    can.fluid = { amount = amount or 1 }
    local fluid = { owner = can }
    function fluid:contains(kind) return kind == Fluid.Petrol and self.owner.fluid.amount > 0 end
    function fluid:getAmount() return self.owner.fluid.amount end
    function can:getFluidContainer() return fluid end
    return can
end

local function pyreArea()
    for x = 14, 30 do
        for y = -6, 8 do makeSquare(x, y, 0) end
    end
end

local function outsidePyre()
    pyreArea()
    check(SC.BaseLife.beginZone("pyre", sq(20, 0)) == true, "a pyre draft begins")
    local ok, zone = SC.BaseLife.finishZone(sq(22, 2), "Pyre")
    check(ok == true and zone.kind == "pyre",
        "a clear pyre in the reach band is accepted: " .. tostring(zone))
    return zone
end

local function tickUntil(ctx, predicate, limit, runtime, advance)
    local reason
    for _ = 1, limit or 12 do
        local _, value = tick(ctx, runtime, nil, advance)
        reason = value
        if predicate(value) then return true, value end
    end
    return false, reason
end

local function spoke(topic)
    for _, entry in ipairs(spokenTopics) do
        if entry.topic == topic then return true end
    end
    return false
end

local function fallenRegister()
    local previous = SC.Community
    SC.Community = {
        deathMatching = function(name)
            if name == "Ada Vance" then
                return "sc-ada", { subjectName = "Ada Vance", subjectGender = "female" }
            end
            return nil
        end,
    }
    return previous
end

local ADA = { forename = "Ada", surname = "Vance", female = true }

do
    local ctx = setup()
    local ok, reason = SC.BaseLife.createProductionOrder({
        operation = "burn_bodies", zoneId = ctx.burial.id, workers = { ctx.id },
    })
    check(ok == false and reason == "invalid_production_zone", "burning needs a pyre")
    ok, reason = SC.BaseLife.createProductionOrder({
        operation = "collect_bodies", zoneId = ctx.burial.id, workers = { ctx.id },
        settings = { fromCamp = false, fromLumber = false },
    })
    check(ok == false and reason == "collect_sources_missing", "collection needs a source area")
    check(SC.BaseLife.beginZone("pyre", sq(2, -2)) == true, "a pyre beside storage begins")
    ok, reason = SC.BaseLife.finishZone(sq(3, -1), "Too close")
    check(ok == false and reason == "pyre_unsafe:storage_near",
        "a pyre within reach of stored goods is refused: " .. tostring(reason))
    SC.BaseLife.cancelZone()
    pyreArea()
    makeTree(sq(24, 1), 10)
    check(SC.BaseLife.beginZone("pyre", sq(20, 0)) == true, "a pyre beside a tree begins")
    ok, reason = SC.BaseLife.finishZone(sq(22, 2), "By the tree")
    check(ok == false and reason == "pyre_unsafe:tree_near",
        "a pyre within its clearance of a tree is refused: " .. tostring(reason))
    SC.BaseLife.cancelZone()
    sq(24, 1).tree = nil
    sq(21, -1):AddWorldInventoryItem(makeItem("Base.Hat"))
    check(SC.BaseLife.beginZone("pyre", sq(20, 0)) == true, "a pyre beside loose items begins")
    ok, reason = SC.BaseLife.finishZone(sq(22, 2), "Cluttered")
    check(ok == false and reason == "pyre_unsafe:loose_items",
        "loose items within the clearance are refused: " .. tostring(reason))
    SC.BaseLife.cancelZone()
    check(SC.BaseLife.beginZone("pyre", sq(20, 0)) == true, "an oversized pyre begins")
    ok, reason = SC.BaseLife.finishZone(sq(23, 2), "Too big")
    check(ok == false and reason == "pyre_zone_too_large",
        "a pyre is at most nine tiles: " .. tostring(reason))
    SC.BaseLife.cancelZone()
    local pyre = outsidePyre()
    local order
    ok, order = SC.BaseLife.createProductionOrder({
        operation = "burn_bodies", zoneId = pyre.id, workers = { ctx.id },
    })
    check(ok == true and order.settings.requireDry == true,
        "a safe pyre takes a burn order that waits for dry weather")
    check(SC.BaseLife.jobAllowsWorkReach({ type = "production", target = { orderId = order.id } })
        == true, "a pyre outside the camp admits reach-band trips")
    local dig
    ok, dig = SC.BaseLife.createProductionOrder({
        operation = "dig_graves", zoneId = ctx.burial.id, workers = { ctx.id },
    })
    check(ok == true and SC.BaseLife.jobAllowsWorkReach({
        type = "production", target = { orderId = dig.id } }) == false,
        "a burial ground inside the camp keeps its work inside the camp")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local machete = ctx.actor.inventory:AddItem(makeItem("Base.Machete"))
    ctx.actor.primary = machete
    local grave, partner = createGrave(-2, -3, 0, false)
    local victim = makeBody(sq(4, -4))
    local order = start(ctx, {
        operation = "collect_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { fromLumber = false },
    })
    local intents = {}
    local originalRequestAny = SC.Navigation.requestAny
    SC.Navigation.requestAny = function(actor, candidates, mode, intent)
        intents[#intents + 1] = intent
        return originalRequestAny(actor, candidates, mode, intent)
    end
    local grabbing, reason = tickUntil(ctx, function(value) return value == "production_grabbing" end, 8)
    check(grabbing, "the collector takes hold of a camp body: " .. tostring(reason))
    local grab = current(ctx.actor)
    check(grab ~= nil and grab.Type == "ISGrabCorpseAction" and grab.corpseBody == victim,
        "vanilla ISGrabCorpseAction receives the body")
    check(ctx.actor.primary == nil, "the grapple starts with empty hands")
    local tag = victim.modData.LF_CorpseHaul
    check(type(tag) == "string" and string.find(tag, order.id, 1, true) == 1,
        "the body carries its haul tag before the grab")
    grab:perform()
    local _, dragReason = tick(ctx)
    check(dragReason == "production_dragging" and ctx.actor:isDraggingCorpse(),
        "a verified grab becomes a drag: " .. tostring(dragReason))
    local _, placeReason = tick(ctx)
    check(placeReason == "production_placing",
        "the drag reaches the graveside: " .. tostring(placeReason))
    check(intents[#intents].draggingBody == true and intents[#intents].action == "drag_body_to_grave",
        "the drag asks navigation for a route a dragged body can take")
    local drop = current(ctx.actor)
    check(drop ~= nil and drop.Type == "ISDropCorpseAction",
        "vanilla ISDropCorpseAction lays the body down")
    drop:perform()
    local _, buryReason = tick(ctx)
    check(buryReason == "production_burying",
        "the respawned body is found by its tag and buried: " .. tostring(buryReason))
    local bury = current(ctx.actor)
    check(bury.Type == "ISBuryCorpse" and bury.grave == grave and bury.bodySquare ~= sq(4, -4),
        "the burial uses the reserved grave and the body where it was laid")
    bury:perform()
    local _, buriedReason = tick(ctx)
    check(buriedReason == "production_body_buried" and grave.modData.corpses == 1
        and partner.modData.corpses == 1, "the collected body is buried: " .. tostring(buriedReason))
    check(ctx.actor.primary == machete, "the weapon put away for the grab comes back")
    local counters = SC.BaseLife.productionCounters()
    check(counters.bodiesCollected == 1 and counters.bodiesBuried == 1,
        "collection counters are exact")
    local _, fillReason = tick(ctx)
    check(fillReason == "production_filling",
        "a finished collection closes its grave: " .. tostring(fillReason))
    current(ctx.actor):perform()
    local done = tickUntil(ctx, function(value) return value == "production_order_completed" end, 5)
    SC.Navigation.requestAny = originalRequestAny
    check(done and SC.BaseLife.productionOrder(order.id).state == "completed"
        and grave.modData.filled == true, "the collection order completes after the grave closes")
end

do
    local ctx = setup()
    local pyre = outsidePyre()
    local lighter = ctx.actor.inventory:AddItem(makeLighter())
    local petrol = ctx.actor.inventory:AddItem(makePetrol(1))
    makeBody(sq(4, 0))
    local order = start(ctx, {
        operation = "collect_bodies", zoneId = pyre.id, requested = 1,
        settings = { fromLumber = false },
    })
    local grabbing, reason = tickUntil(ctx, function(value) return value == "production_grabbing" end, 8)
    check(grabbing, "the collector takes hold of a body bound for the pyre: " .. tostring(reason))
    current(ctx.actor):perform()
    tick(ctx)
    local _, placeReason = tick(ctx)
    check(placeReason == "production_placing" and ctx.actor.square == sq(21, 1),
        "the body is dragged onto the middle of the pyre: " .. tostring(placeReason))
    current(ctx.actor):perform()
    local _, burnReason = tick(ctx)
    local burn = current(ctx.actor)
    check(burnReason == "production_burning" and burn ~= nil and burn.Type == "ISBurnCorpseAction",
        "the body on the pyre is lit with the vanilla action: " .. tostring(burnReason))
    check(ctx.actor.primary == lighter and ctx.actor.secondary == petrol,
        "the lighter and the petrol can are in hand")
    burn:perform()
    local _, litReason = tick(ctx)
    check(litReason == "production_pyre_lit" and sq(21, 1).fire == true and petrol.fluid.amount < 1,
        "a verified fire lights the pyre: " .. tostring(litReason))
    check(SC.BaseLife.productionCounters().pyresLit == 1
        and SC.BaseLife.productionOrder(order.id).completed == 0,
        "lighting counts the fire, not yet the body")
    tick(ctx)
    local ring = math.max(0, 20 - ctx.actor.x, ctx.actor.x - 22, 0 - ctx.actor.y, ctx.actor.y - 2)
    check(ring >= 3, "the worker watches the fire from a safe distance")
    local body = sq(21, 1).staticMoving[1]
    check(body ~= nil and body.modData.LF_CorpseBurned == order.id,
        "a lit body is marked so it is never lit twice")
    sq(21, 1).fire = false
    table.remove(sq(21, 1).staticMoving, 1)
    local before = #spokenTopics
    local _, burnedReason = tick(ctx, nil, nil, 21000)
    check(burnedReason == "production_body_burned"
        and SC.BaseLife.productionOrder(order.id).completed == 1,
        "the burned body counts once the fire is out: " .. tostring(burnedReason))
    local topic = spokenTopics[#spokenTopics] and spokenTopics[#spokenTopics].topic or nil
    check(#spokenTopics > before and (topic == "burn.prayer" or topic == "burn.gallows"),
        "the pyre closes with a fire-side prayer or gallows line: " .. tostring(topic))
    local counters = SC.BaseLife.productionCounters()
    check(counters.bodiesBurned == 1 and counters.bodiesCollected == 1, "burn counters are exact")
    local done = tickUntil(ctx, function(value) return value == "production_order_completed" end, 4)
    check(done, "the collection completes after the pyre ceremony")
end

do
    local ctx = setup()
    local pyre = outsidePyre()
    ctx.actor.inventory:AddItem(makeLighter())
    ctx.actor.inventory:AddItem(makePetrol(1))
    makeBody(sq(21, 1))
    local order = start(ctx, { operation = "burn_bodies", zoneId = pyre.id, requested = 2 })
    local _, reason = tick(ctx)
    check(reason == "production_burning", "a body already on the pyre is lit: " .. tostring(reason))
    current(ctx.actor):perform()
    local _, litReason = tick(ctx)
    check(litReason == "production_pyre_lit", "the pyre burns: " .. tostring(litReason))
    sq(26, 1).fire = true
    local _, spreadReason = tick(ctx)
    check(spreadReason == "fire_spread" and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "fire beyond the pyre stops the order: " .. tostring(spreadReason))
    check(spoke("burn.fire_spread"), "the worker shouts a fire warning")
    tick(ctx, nil, nil, 31000)
    tick(ctx, nil, nil, 31000)
    check(SC.BaseLife.productionOrder(order.id).state == "blocked"
        and SC.BaseLife.productionOrder(order.id).blocker == "fire_spread",
        "a spreading fire never re-opens the order on its own")
    sq(26, 1).fire, sq(21, 1).fire = false, false
    check(SC.BaseLife.retryProductionOrder(order.id) == true
        and SC.BaseLife.productionOrder(order.id).state == "running",
        "the player's Retry re-opens it")
end

do
    local ctx = setup()
    local pyre = outsidePyre()
    makeBody(sq(21, 1))
    local order = start(ctx, { operation = "burn_bodies", zoneId = pyre.id, requested = 1 })
    local _, reason = tick(ctx)
    check(reason == "missing_lighter" and SC.BaseLife.productionOrder(order.id).state == "blocked",
        "no lighter blocks with a readable reason: " .. tostring(reason))
    local lighter = makeLighter()
    ctx.toolsObject.container:AddItem(lighter)
    check(SC.BaseLife.retryProductionOrder(order.id) == true, "retry after stocking a lighter")
    for _ = 1, 6 do
        local _, value = tick(ctx)
        reason = value
        if lighter.container == ctx.actor.inventory then break end
    end
    check(lighter.container == ctx.actor.inventory,
        "the lighter is fetched from camp storage: " .. tostring(reason))
    local _, fuelReason = tickUntil(ctx, function(value) return value == "missing_fuel" end, 3)
    check(fuelReason == "missing_fuel", "no petrol blocks with a readable reason: " .. tostring(fuelReason))
    ctx.actor.inventory:AddItem(makePetrol(0.05))
    SC.BaseLife.retryProductionOrder(order.id)
    _, reason = tick(ctx)
    check(reason == "missing_fuel", "a nearly empty can is not enough for one body: " .. tostring(reason))
    ctx.actor.inventory:AddItem(makePetrol(1))
    local previousClimate = getClimateManager
    getClimateManager = function()
        local climate = {}
        function climate:isRaining() return true end
        return climate
    end
    SC.BaseLife.retryProductionOrder(order.id)
    _, reason = tick(ctx)
    getClimateManager = previousClimate
    check(reason == "raining" and current(ctx.actor) == nil,
        "nothing is lit in the rain: " .. tostring(reason))
    SC.BaseLife.retryProductionOrder(order.id)
    _, reason = tick(ctx)
    check(reason == "production_burning", "dry weather lights the pyre: " .. tostring(reason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    local used = createGrave(-2, -4, 0, false)
    used.modData.corpses, used.partner.modData.corpses = 1, 1
    local own = createGrave(-2, -2, 0, false)
    makeBody(sq(4, -4), { descriptor = ADA })
    local previousCommunity = fallenRegister()
    start(ctx, {
        operation = "collect_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { fromLumber = false },
    })
    local grabbing, reason = tickUntil(ctx, function(value) return value == "production_grabbing" end, 8)
    check(grabbing, "a fallen companion is collected: " .. tostring(reason))
    current(ctx.actor):perform()
    tick(ctx)
    tick(ctx)
    current(ctx.actor):perform()
    local _, buryReason = tick(ctx)
    check(buryReason == "production_burying" and current(ctx.actor).grave == own,
        "a fallen companion gets an empty grave of their own: " .. tostring(buryReason))
    current(ctx.actor):perform()
    local _, buriedReason = tick(ctx)
    check(buriedReason == "production_body_buried" and own.modData.LF_FallenName == "Ada Vance"
        and own.partner.modData.LF_FallenName == "Ada Vance",
        "the grave keeps the companion's name: " .. tostring(buriedReason))
    check(SC.BaseLife.productionCounters().fallenBuried == 1, "named burials are counted")
    local _, fillReason = tick(ctx)
    check(fillReason == "production_filling", "a named grave closes at once: " .. tostring(fillReason))
    current(ctx.actor):perform()
    local before = #spokenTopics
    local _, closedReason = tick(ctx)
    local topic = spokenTopics[#spokenTopics] and spokenTopics[#spokenTopics].topic or nil
    SC.Community = previousCommunity
    check(closedReason == "production_grave_closed" and #spokenTopics == before + 1
        and topic == "burial.fallen", "the ceremony speaks the companion's name: " .. tostring(topic))
    check(used.modData.corpses == 1 and used.modData.filled == false and used.modData.LF_FallenName == nil,
        "the shared grave is left alone")
end

do
    local ctx = setup()
    local pyre = outsidePyre()
    ctx.actor.inventory:AddItem(makeLighter())
    ctx.actor.inventory:AddItem(makePetrol(1))
    makeBody(sq(21, 1), { descriptor = ADA })
    local previousCommunity = fallenRegister()
    start(ctx, { operation = "burn_bodies", zoneId = pyre.id, requested = 1 })
    local _, reason = tick(ctx)
    SC.Community = previousCommunity
    check(reason == "no_bodies_on_pyre" and current(ctx.actor) == nil and sq(21, 1).fire ~= true,
        "a fallen companion is never burned: " .. tostring(reason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    local player = makeBody(sq(4, -4), { player = true })
    local order = start(ctx, {
        operation = "collect_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { fromLumber = false },
    })
    local blocked, reason = tickUntil(ctx, function()
        return SC.BaseLife.productionOrder(order.id).state == "blocked"
    end, 10)
    check(blocked and reason == "no_bodies_in_collection_areas" and onSquare(sq(4, -4), player)
        and player.modData.LF_CorpseHaul == nil,
        "an unmatched player body is never touched: " .. tostring(reason))
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    local victim = makeBody(sq(4, -4))
    SC_TEST_GRAB_FAILS = true
    local order = start(ctx, {
        operation = "collect_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { fromLumber = false },
    })
    local reason
    for _ = 1, 40 do
        local queued = current(ctx.actor)
        if queued then queued:perform() end
        local _, value = tick(ctx, nil, nil, 21000)
        reason = value
        if SC.BaseLife.productionOrder(order.id).state == "blocked" then break end
    end
    SC_TEST_GRAB_FAILS = false
    check(reason == "drag_unavailable",
        "a grapple that never takes hold blocks after bounded attempts: " .. tostring(reason))
    check(onSquare(sq(4, -4), victim) and victim.modData.LF_CorpseHaul == nil,
        "a failed grab leaves the body where it lay, untagged")
end

do
    local ctx = setup()
    ctx.actor.inventory:AddItem(makeItem("Base.Shovel", { tags = { diggrave = true } }))
    createGrave(-2, -3, 0, false)
    makeBody(sq(4, -4))
    local order = start(ctx, {
        operation = "collect_bodies", zoneId = ctx.burial.id, requested = 1,
        settings = { fromLumber = false },
    })
    local grabbing = tickUntil(ctx, function(value) return value == "production_grabbing" end, 8)
    check(grabbing, "the danger test takes hold of a body")
    current(ctx.actor):perform()
    local _, dragReason = tick(ctx)
    check(dragReason == "production_dragging", "the danger test is dragging: " .. tostring(dragReason))
    local runtime = { snapshot = { threats = { { distanceSq = 25 } } } }
    local _, reason = tick(ctx, runtime)
    check(reason == "unsafe_area" and not ctx.actor:isDraggingCorpse(),
        "danger drops the body at once: " .. tostring(reason))
    check(#ctx.actor.square.staticMoving == 1, "the dropped body stays in the world where it fell")
    check(spoke("burial.haul.threat"), "the worker calls out the drop")
    check(SC.BaseLife.productionOrder(order.id).completed == 0, "an abandoned drag is not progress")
end

-- ---------------------------------------------------------------------------
-- Speech policy and native action guards
-- ---------------------------------------------------------------------------

do
    local ctx = setup()
    local originalPeek = SC.Commands.peek
    local caring = { personalityProfile = { archetype = "caring" }, stress = 0, morale = 55 }
    local practical = { personalityProfile = { archetype = "practical" }, stress = 0, morale = 55 }
    local gallows = { caring = 0, practical = 0 }
    for index = 1, 200 do
        local salt = "grave:" .. tostring(index)
        SC.Commands.peek = function() return caring end
        if SC.Production._ceremonyTopicForTests(ctx.actor, salt) == "burial.gallows" then
            gallows.caring = gallows.caring + 1
        end
        SC.Commands.peek = function() return practical end
        if SC.Production._ceremonyTopicForTests(ctx.actor, salt) == "burial.gallows" then
            gallows.practical = gallows.practical + 1
        end
    end
    check(gallows.caring > 0 and gallows.caring < gallows.practical,
        "caring companions pray more and practical ones joke more")
    local ritualState = { ritual = { id = "rubber_duck_oracle" } }
    SC.Commands.peek = function() return ritualState end
    local previousQuirks = SC.Quirks
    SC.Quirks = { normalize = function(value) return type(value) == "table" and value or {} end }
    local ritualLines = 0
    for index = 1, 40 do
        if SC.Production._ceremonyTopicForTests(ctx.actor, "duck:" .. tostring(index))
            == "burial.ritual.rubber_duck_oracle" then ritualLines = ritualLines + 1 end
    end
    SC.Quirks = previousQuirks
    SC.Commands.peek = originalPeek
    check(ritualLines > 0 and ritualLines < 40, "ritual quirks blend their own burial liturgy")
    for _, topic in ipairs({ "work.fell.start", "work.fell.timber", "work.saw.done",
        "burial.dig.start", "burial.lower", "burial.prayer", "burial.gallows", "burial.amen",
        "burial.haul.start", "burial.haul.threat", "burial.fallen", "burn.ignite",
        "burn.prayer", "burn.gallows", "burn.fire_spread" }) do
        check(SC.Dialogue.has(topic) and SC.Dialogue.poolSize(topic, ctx.actor) > 0,
            "dialogue pool registered: " .. topic)
    end
end

do
    local ctx = setup()
    local tree = makeTree(sq(3, 2), 10)
    local ok, reason = SC.NativeWorkActions.dispatch(ctx.actor, "chop_tree",
        { tree = tree }, directProvider)
    check(ok == false and reason == "companion needs an unbroken axe",
        "chopping without an axe fails closed: " .. tostring(reason))
    local emulated, emulateReason = SC.NativeActions.emulateWorkEvent(ctx.actor, "saw_logs", "ChopTree")
    check(emulated == false and emulateReason == "unsupported_work_event",
        "only the chop event can be emulated")
    local saw = makeItem("Base.Saw", { tags = { saw = true } })
    local log = makeItem("Base.Log")
    ctx.actor.inventory:AddItem(saw)
    ctx.actor.inventory:AddItem(log)
    SC_TEST_SAW_INPUTS[1].keep = true
    ok, reason = SC.NativeWorkActions.dispatch(ctx.actor, "saw_logs",
        { log = log, saw = saw }, directProvider)
    SC_TEST_SAW_INPUTS[1].keep = false
    check(ok == false and reason == "saw recipe inputs changed",
        "a changed saw recipe fails closed: " .. tostring(reason))
    local shovel = makeItem("Base.Shovel", { tags = { diggrave = true } })
    ctx.actor.inventory:AddItem(shovel)
    sq(-2, -3).diggable = false
    ok, reason = SC.NativeWorkActions.dispatch(ctx.actor, "dig_grave",
        { square = sq(-2, -3), tool = shovel }, directProvider)
    check(ok == false and reason == "grave site is not diggable" and ctx.actor.primary == nil,
        "an undiggable site restores the hands: " .. tostring(reason))
end

print("PRODUCTION_HARNESS_PASS checks=" .. tostring(checks))
