-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checks = 0

local function check(condition, message)
    checks = checks + 1
    if not condition then error("check " .. tostring(checks) .. " failed: " .. message) end
end

local nextNativeId = 1000
local makeItem
local originalInventoryItemFactory = InventoryItemFactory

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
    function inventory:hasRoomFor(actor, item) return self.room == true end
    function inventory:getCapacityWeight()
        local weight = 0
        for _, item in ipairs(self.items) do weight = weight + item:getActualWeight() end
        return weight
    end
    function inventory:getEffectiveCapacity() return self.capacity or 1000 end
    function inventory:getType() return self.kind end
    function inventory:AddItem(value)
        self.addCalls = (self.addCalls or 0) + 1
        if self.rejectAddAt == self.addCalls then return nil end
        if self.rejectAdd == true then return nil end
        local item = type(value) == "string" and makeItem(value) or value
        if item == nil or self.room ~= true then return nil end
        if not self:contains(item) then self.items[#self.items + 1] = item end
        item.container, item.worldItem = self, nil
        return item
    end
    function inventory:DoAddItemBlind(item) return self:AddItem(item) end
    function inventory:Remove(item)
        if self.rejectRemoveTypeOnce == item.fullType then
            self.rejectRemoveTypeOnce = nil
            return
        end
        if self.rejectRemove == true then return end
        if removeIdentity(self.items, item) and item.container == self then item.container = nil end
    end
    function inventory:DoRemoveItem(item) return self:Remove(item) end
    return inventory
end

makeItem = function(fullType, options)
    options = options or {}
    nextNativeId = nextNativeId + 1
    local item = {
        __class = "InventoryItem", fullType = fullType, nativeId = nextNativeId,
        modData = options.modData or {}, favorite = options.favorite == true,
        condition = options.condition or 100, category = options.category,
        offAgeMax = options.offAgeMax,
    }
    function item:getFullType() return self.fullType end
    function item:getType() return string.match(self.fullType, "[^%.]+$") end
    function item:getDisplayName() return self:getType() end
    function item:getID() return self.nativeId end
    function item:getCondition() return self.condition end
    function item:getCategory() return self.category end
    function item:getOffAgeMax() return self.offAgeMax end
    function item:setCondition(value) self.condition = value end
    function item:isFavorite() return self.favorite end
    function item:setFavorite(value) self.favorite = value == true end
    function item:getActualWeight() return self.fullType == "Base.Log" and 9 or 3 end
    function item:getModData() return self.modData end
    function item:getContainer() return self.container end
    function item:getWorldItem() return self.worldItem end
    function item:setWorldItem(value) self.worldItem = value end
    function item:getInventory() return nil end
    function item:getAllWeaponParts() return {} end
    return item
end

InventoryItemFactory = {
    CreateItem = function(itemType)
        return makeItem(itemType)
    end,
}

local function makeSquare(x, y, z)
    local square = { x = x, y = y, z = z or 0, objects = {}, worldItems = {} }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getObjects() return self.objects end
    function square:getWorldObjects()
        if self.worldListUnreadable then error("unreadable world list") end
        return self.worldItems
    end
    function square:transmitRemoveItemFromSquare(worldItem)
        if not self.rejectRemove then removeIdentity(self.worldItems, worldItem) end
    end
    function square:removeWorldObject(worldItem)
        if not self.rejectRemove then removeIdentity(self.worldItems, worldItem) end
    end
    function square:AddWorldInventoryItem(item)
        local wrapper = { item = item, square = self, x = self.x, y = self.y, z = self.z }
        function wrapper:getItem() return self.item end
        function wrapper:getSquare() return self.square end
        function wrapper:setSquare(value) self.square = value end
        function wrapper:removeFromWorld()
            if self.square and not self.square.rejectRemove then
                removeIdentity(self.square.worldItems, self)
            end
        end
        function wrapper:removeFromSquare()
            if not self.square or not self.square.rejectRemove then self.square = nil end
        end
        self.worldItems[#self.worldItems + 1] = wrapper
        item.container, item.worldItem = nil, wrapper
        return item
    end
    return square
end

local function putOnGround(square, item)
    square:AddWorldInventoryItem(item)
    return item.worldItem
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

local function makeActor(id, square)
    local actor = { __class = "IsoSurvivor", x = square.x, y = square.y,
        z = square.z, square = square, inventory = makeInventory("inventory"),
        modData = { SC_Id = id } }
    function actor:getX() return self.x end
    function actor:getY() return self.y end
    function actor:getZ() return self.z end
    function actor:getSquare() return self.square end
    function actor:getCurrentSquare() return self.square end
    function actor:getInventory() return self.inventory end
    function actor:getModData() return self.modData end
    function actor:isDead() return false end
    function actor:getPlayerNum() return 3 end
    return actor
end

local squares = {}
local function squareKey(x, y, z)
    return tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z or 0)
end
local function addSquare(x, y, z)
    local square = makeSquare(x, y, z)
    squares[squareKey(x, y, z)] = square
    return square
end
local cell = {}
function cell:getGridSquare(x, y, z) return squares[squareKey(x, y, z)] end
function getCell() return cell end

SC.Actor._isRegistryActor = function() return true end
SC.Actor.setMovement = function() return true, "visual_started" end
SC.NativeActions.visualStatus = function() return "completed" end
SC.NativeActions.clearVisual = function() return true end
SC.NativeActions.cancelVisual = function() return true end
SC.NativeActions.stopDirect = function() return true end
local navigationCancels = 0
local navigationStarts = 0
local rejectNavigation = false
SC.Navigation = {
    standingSquareClear = function() return true end,
    cancel = function()
        navigationCancels = navigationCancels + 1
        return true
    end,
    interactionTargets = function(actor, target)
        local square = SC.GameplayUtil.squareOf(target) or target
        local actorSquare = SC.GameplayUtil.squareOf(actor)
        if type(target) == "table" and type(target.getContainer) == "function"
            and actorSquare and square
            and math.abs(actorSquare.x - square.x) + math.abs(actorSquare.y - square.y) == 1 then
            -- The fixture has no walls: the actor's adjacent tile is a valid
            -- direct-use side, matching production interactionTargets().
            return { actorSquare }
        end
        return { square }
    end,
    requestAny = function(actor, candidates, _, intent)
        if rejectNavigation then return false, "fixture_unreachable" end
        local candidate = candidates and candidates[1]
        local target = SC.GameplayUtil.squareOf(candidate) or candidate
        if target and (intent and intent.requireSameSquare == false
            and SC.GameplayUtil.arrived(actor, target, {
                targetKind = "square", distance = intent.arrivalDistance,
            }) or (not intent or intent.requireSameSquare ~= false)
            and SC.GameplayUtil.sameSquare(actor, target)) then
            return true, "arrived", target
        end
        if not target then return false, "fixture_target_missing" end
        navigationStarts = navigationStarts + 1
        actor.square, actor.x, actor.y, actor.z =
            target, target.x + 0.5, target.y + 0.5, target.z
        return true, "fixture_path_started", target
    end,
}

local contextSerial = 0
local function setup(material, requested, workerCount)
    contextSerial = contextSerial + 1
    SC.BaseWork.reset()
    SC.BaseLife.reset()
    SC.Registry.reset()
    squares = {}
    local core = addSquare(0, 0, 0)
    local source = addSquare(0, 1, 0)
    local destinationSquare = addSquare(1, 0, 0)
    local ok, base = SC.BaseLife.create(core, "Harness Camp")
    check(ok == true and base ~= nil, "base creation must succeed")
    check(SC.BaseLife.beginZone("work", source) == true, "work zone must begin")
    local zoneOk, zone = SC.BaseLife.finishZone(source, "Gather test")
    check(zoneOk == true and zone ~= nil, "work zone must finish")
    local storageObject = makeStorage(destinationSquare)
    local storageOk, storage = SC.BaseLife.registerStorage(storageObject, "construction")
    check(storageOk == true and storage ~= nil, "destination storage must register")
    local actors = {}
    for index = 1, (workerCount or 1) do
        local id = "sc-work-" .. tostring(contextSerial) .. "-" .. tostring(index)
        local actor = makeActor(id, core)
        check(SC.Registry.register(actor, { id = id, recruited = true }) ~= nil,
            "worker must register")
        check(SC.BaseLife.assign(id, "generalist", true) == true,
            "worker must join base duty")
        actors[#actors + 1] = actor
    end
    local ids = {}
    for _, actor in ipairs(actors) do ids[#ids + 1] = actor.modData.SC_Id end
    local orderOk, order = SC.BaseLife.createGatherOrder({
        material = material or "logs", requested = requested or 1,
        zoneId = zone.id, destinationStorageId = storage.id, workers = ids,
    })
    check(orderOk == true and order ~= nil, "gather order must be created")
    return {
        base = base, source = source, destinationSquare = destinationSquare,
        storageObject = storageObject, storage = storage,
        actors = actors, actor = actors[1], order = order,
    }
end

local function reserveCandidate(ctx, actor, item)
    local candidate, reason = SC.GatherWork.nextCandidate(ctx.order, actor)
    check(candidate ~= nil, "candidate expected, got " .. tostring(reason))
    local job
    for _, value in ipairs(ctx.base.jobs) do
        if value.assignedId == actor.modData.SC_Id then job = value break end
    end
    local receipt, reserveReason = SC.WorkTransport.reserve(ctx.order, job, actor,
        candidate.item, candidate.worldItem, candidate.square)
    check(receipt ~= nil, "reservation expected, got " .. tostring(reserveReason))
    check(receipt.nativeId == item.nativeId and type(receipt.nativeId) == "number",
        "numeric native identity must remain numeric")
    return receipt, candidate
end

local function dispatchUntilTerminal(ctx, maximum)
    for _ = 1, maximum or 20 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 50
        SC.BaseWork.update(ctx.actor, nil, {})
        if ctx.order.state == "completed" or ctx.order.state == "blocked" then break end
    end
end

-- G01/G03/G18: the production dispatcher moves one exact floor log into the
-- registered storage, never counts existing stock, and leaves unrelated gear.
do
    local ctx = setup("logs", 1)
    local log = makeItem("Base.Log")
    putOnGround(ctx.source, log)
    local receipt = reserveCandidate(ctx, ctx.actor, log)
    -- Crossing into the log's tile is not yet close enough to pick it up.
    ctx.actor.square, ctx.actor.x, ctx.actor.y = ctx.source, 0.02, 1.02
    local startsBefore = navigationStarts
    local handled, reason = SC.GatherWork.update(ctx.actor, {}, ctx.base.jobs[1])
    check(handled == true and reason == "fixture_path_started"
            and navigationStarts == startsBefore + 1
            and receipt.phase == "selected" and #ctx.source.worldItems == 1,
        "ground pickup walks to the log instead of looting from the edge of its tile")
end

do
    local ctx = setup("logs", 1)
    local stock = makeItem("Base.Log")
    local hammer = makeItem("Base.Hammer")
    ctx.storageObject.container:AddItem(stock)
    ctx.actor.inventory:AddItem(hammer)
    local gathered = makeItem("Base.Log")
    putOnGround(ctx.source, gathered)
    local startsBefore, cancelsBefore = navigationStarts, navigationCancels
    SC_TEST_CLOCK = SC_TEST_CLOCK + 50
    SC.BaseWork.update(ctx.actor, nil, {})
    SC_TEST_CLOCK = SC_TEST_CLOCK + 50
    SC.BaseWork.update(ctx.actor, nil, {})
    local approachingReceipt = SC.BaseLife.workReceipts(ctx.order.id, false)[1]
    check(approachingReceipt and approachingReceipt.phase == "selected"
            and navigationStarts == startsBefore + 1
            and navigationCancels == cancelsBefore
            and #ctx.source.worldItems == 1,
        "accepted navigation remains pending until physical gather arrival")
    dispatchUntilTerminal(ctx)
    check(ctx.order.state == "completed" and ctx.order.delivered == 1,
        "one verified delivery must complete the order")
    check(#ctx.storageObject.container.items == 2
        and ctx.storageObject.container:contains(gathered),
        "existing stock plus the exact gathered item must remain")
    check(ctx.actor.inventory:contains(hammer), "unrelated worker inventory must remain")
    check(#ctx.source.worldItems == 0, "delivered floor wrapper must be absent")
    local completedReceipt = SC.BaseLife.workReceipts(ctx.order.id, true)[1]
    ctx.storageObject.container:Remove(gathered)
    check(SC.BaseLife.accountGatherDelivery(ctx.order.id, completedReceipt.id) == true
        and ctx.order.delivered == 1 and ctx.order.state == "completed",
        "G04 withdrawal and idempotent accounting must not restart or recount completion")
    check(SC.BaseLife.removeZone(ctx.order.zoneId) == true,
        "completed order must not pin its former work zone")
    check(SC.BaseLife.removeStorage(ctx.order.destinationStorageId) == true,
        "completed delivery must not pin its former storage")
    check(SC.BaseLife.restore(SC.BaseLife.export()) == true,
        "terminal historical references may outlive removed camp objects")
end

-- G07: a replacement of the same type at the same square never satisfies the
-- receipt for the original exact wrapper.
do
    local ctx = setup("logs", 1)
    local original, replacement = makeItem("Base.Log"), makeItem("Base.Log")
    local originalWrapper = putOnGround(ctx.source, original)
    local receipt = reserveCandidate(ctx, ctx.actor, original)
    ctx.source:transmitRemoveItemFromSquare(originalWrapper)
    putOnGround(ctx.source, replacement)
    check(SC.WorkTransport.collect(receipt, ctx.actor, original, originalWrapper) == false
        and ctx.source.worldItems[1].item == replacement
        and not ctx.actor.inventory:contains(original) and ctx.order.delivered == 0,
        "replacement type/location must not substitute for the reserved native item")
end

-- G03/G04: a 12-item order counts only its own verified deliveries. Existing
-- stock and later player withdrawal never affect the historical counter.
do
    local ctx = setup("logs", 12)
    for _ = 1, 7 do ctx.storageObject.container:AddItem(makeItem("Base.Log")) end
    for _ = 1, 12 do putOnGround(ctx.source, makeItem("Base.Log")) end
    dispatchUntilTerminal(ctx, 200)
    check(ctx.order.state == "completed" and ctx.order.delivered == 12
        and #ctx.storageObject.container.items == 19,
        "12-item order must add exactly 12 deliveries beyond seven old logs"
            .. " (state=" .. tostring(ctx.order.state)
            .. ", delivered=" .. tostring(ctx.order.delivered)
            .. ", stored=" .. tostring(#ctx.storageObject.container.items)
            .. ", blocker=" .. tostring(ctx.order.blocker) .. ")")
    ctx.storageObject.container:Remove(ctx.storageObject.container.items[19])
    check(ctx.order.state == "completed" and ctx.order.delivered == 12,
        "post-completion withdrawal must not change historical progress")
end

-- G02: exact material filtering.
do
    local ctx = setup("planks", 1)
    local log, plank = makeItem("Base.Log"), makeItem("Base.Plank")
    putOnGround(ctx.source, log)
    putOnGround(ctx.source, plank)
    dispatchUntilTerminal(ctx)
    check(ctx.storageObject.container:contains(plank), "plank order must deliver a plank")
    check(not ctx.storageObject.container:contains(log) and log.worldItem ~= nil,
        "plank order must ignore a log")
end

-- G10/G11/G12: insertion rejection rolls back to the exact worker owner;
-- rollback failure records detached proof, and destination-before-accounting
-- survives save/reload for exactly-once completion.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log", { condition = 82 })
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "insertion fault setup pickup must succeed")
    ctx.storageObject.container.rejectAdd = true
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == false
        and receipt.phase == "carried" and ctx.actor.inventory:contains(item)
        and not ctx.storageObject.container:contains(item),
        "rejected insertion must roll back to the verified worker owner")

    ctx.actor.inventory.rejectAdd = true
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == false
        and receipt.phase == "recovery" and receipt.owner == "detached"
        and receipt.detachedProof == true and ctx.order.delivered == 0,
        "failed insertion and rollback must retain explicit detached evidence")
    local detachedSave = SC.BaseLife.export()
    SC.WorkTransport.reset()
    ctx.actor.inventory.rejectAdd, ctx.storageObject.container.rejectAdd = false, false
    check(SC.BaseLife.restore(detachedSave) == true, "detached insertion fault must save")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == true
        and receipt.phase == "carried",
        "proven detached insertion fault must reconstruct one carried item")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log", { condition = 58 })
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "accounting fault setup pickup must succeed")
    local accountDelivery = SC.BaseLife.accountGatherDelivery
    SC.BaseLife.accountGatherDelivery = function() return false, "injected_accounting_fault" end
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == false
        and receipt.phase == "recovery" and receipt.owner == "destination"
        and ctx.storageObject.container:contains(item),
        "destination commit before accounting must remain recoverable")
    SC.BaseLife.accountGatherDelivery = accountDelivery
    local destinationSave = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(destinationSave) == true,
        "destination-before-accounting phase must save")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == true
        and SC.BaseLife.workOrder(ctx.order.id).delivered == 1,
        "destination receipt must account exactly once after reload")
end

-- G05: quota reservation is atomic across two workers.
do
    local ctx = setup("logs", 1, 2)
    local first, second = makeItem("Base.Log"), makeItem("Base.Log")
    putOnGround(ctx.source, first)
    putOnGround(ctx.source, second)
    reserveCandidate(ctx, ctx.actors[1], first)
    local candidate = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actors[2]))
    check(candidate ~= nil and candidate.item == second, "second worker must see unreserved item")
    local receipt, reason = SC.WorkTransport.reserve(ctx.order, ctx.base.jobs[2],
        ctx.actors[2], candidate.item, candidate.worldItem, candidate.square)
    check(receipt == nil and reason == "gather_quota_reserved",
        "second worker must not over-reserve the final quota slot")
end


-- G06/G08: scans resume beyond one object slice, while unreadable collections
-- are incomplete evidence rather than proof that an area is empty.
do
    local ctx = setup("logs", 1)
    for _ = 1, 33 do putOnGround(ctx.source, makeItem("Base.Nails")) end
    local tail = makeItem("Base.Log")
    putOnGround(ctx.source, tail)
    local first, reason = SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(first == nil and reason == "gather_scan_pending", "first bounded scan must yield")
    local second = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actor))
    check(second ~= nil and second.item == tail, "resumed scan must reach tail candidate")
    local diagnostics = SC.GatherWork.diagnostics()
    check(diagnostics.scanYields >= 1 and diagnostics.examinedObjects >= 34,
        "scan diagnostics must expose bounded progress")

    ctx = setup("logs", 1)
    ctx.source.worldItems = nil
    ctx.source.worldListUnreadable = true
    local candidate, incompleteReason, complete = SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(candidate == nil and incompleteReason == "gather_area_scan_incomplete"
        and complete == false, "unreadable scan must remain pending")
end

-- G09/G10: native calls without ownership postconditions never count.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    ctx.source.rejectRemove = true
    local collected = SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem)
    check(collected == false and receipt.phase == "selected",
        "no-op floor removal must retain world ownership")
    check(item.worldItem ~= nil and not ctx.actor.inventory:contains(item)
        and ctx.order.delivered == 0, "failed pickup must not fabricate delivery")

    local source, destination, intruder = makeInventory(), makeInventory(), makeInventory()
    source:AddItem(item)
    item.container = intruder
    local moved, reason = SC.WorkTransport.transferVerified(source, destination, item, ctx.actor)
    check(moved == false and reason == "source_owner_pointer_conflict",
        "membership and owner pointer conflict must fail closed")
end

-- G11/G12: carrying survives save/restore, and only proven detached ownership
-- may reconstruct one exact item.
do
    local ctx = setup("logs", 1)
    local selectedItem = makeItem("Base.Log")
    putOnGround(ctx.source, selectedItem)
    local selectedReceipt = reserveCandidate(ctx, ctx.actor, selectedItem)
    local selectedSave = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(selectedSave) == true,
        "selected pre-pickup receipt must restore")
    selectedReceipt = SC.BaseLife.workReceipt(selectedReceipt.id)
    check(SC.WorkTransport.reconcile(selectedReceipt, ctx.actor) == true
        and selectedReceipt.phase == "selected",
        "selected receipt must reattach to the exact marked floor item")
    check(SC.WorkTransport.abandonSelected(selectedReceipt, "fixture_continue") == true,
        "selected restore fixture must release its exact marker")

    ctx = setup("logs", 1)
    local item = makeItem("Base.Log", { condition = 63 })
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "pickup must reach carried phase")
    local summary = SC.BaseLife.summary()
    check(summary.workOrders[1].workerPhases[1].phase == "carried",
        "Base summary must expose the worker's current transport phase")
    local saved = SC.BaseLife.export()
    check(type(saved) == "table", "work document must export while carrying")
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(saved) == true, "work document must restore while carrying")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == true
        and receipt.phase == "carried", "marked native cargo must reconcile after restore")
    local carried = SC.WorkTransport.runtimeItem(receipt.id)
    check(SC.WorkTransport.deposit(receipt, ctx.actor, carried) == true,
        "restored carried item must deposit")
    check(ctx.order.delivered == 1 or SC.BaseLife.workOrder(ctx.order.id).delivered == 1,
        "restored delivery must be accounted exactly once")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log", { condition = 47 })
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "detached setup pickup must succeed")
    ctx.actor.inventory:Remove(item)
    receipt.phase, receipt.owner, receipt.detachedProof = "recovery", "detached", true
    saved = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(saved) == true, "detached receipt must restore")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    local reconstructed, reconstructionReason = SC.WorkTransport.reconcile(receipt, ctx.actor)
    check(reconstructed == true,
        "proven detached receipt must reconstruct: " .. tostring(reconstructionReason)
            .. "; phase=" .. tostring(receipt.phase)
            .. "; owner=" .. tostring(receipt.owner))
    carried = SC.WorkTransport.runtimeItem(receipt.id)
    check(carried ~= nil and carried ~= item and carried.condition == 47
        and ctx.actor.inventory:contains(carried),
        "reconstruction must create one verified state-equivalent item")
end

-- G13: detached recovery is bounded, preserves its proof at exhaustion, and
-- only resumes after an explicit retry when the worker becomes available.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log", { condition = 71 })
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "bounded-recovery setup pickup must succeed")
    ctx.actor.inventory:Remove(item)
    receipt.phase, receipt.owner, receipt.detachedProof = "recovery", "detached", true
    local actorId = receipt.actorId
    receipt.actorId, receipt.nextRetryAt = "sc-work-unloaded", 0
    SC.WorkTransport.recoverPending(1)
    check(receipt.phase == "recovery" and receipt.attempts == 0,
        "unloaded ownership evidence must pause without consuming failure attempts")
    receipt.actorId, receipt.nextRetryAt = actorId, 0
    local restoreDetachedItem = SC.Persistence.restoreDetachedItem
    SC.Persistence.restoreDetachedItem = function()
        return nil, "injected_reconstruction_failure", nil, nil, true
    end
    local maximumAttempts = SC.GameplayUtil.config("workRecoveryMaxAttempts") or 8
    local maximumDelay = SC.GameplayUtil.config("workRecoveryRetryMaximumMs") or 5000
    for _ = 1, maximumAttempts do
        SC_TEST_CLOCK = SC_TEST_CLOCK + maximumDelay + 1
        SC.WorkTransport.recoverPending(1)
    end
    check(receipt.phase == "quarantined" and receipt.detachedProof == true,
        "recovery exhaustion must stop automatic retries without discarding proof")
    SC.Persistence.restoreDetachedItem = restoreDetachedItem
    local retried, retryReason = SC.WorkTransport.retryOrder(ctx.order.id)
    check(retried == true and receipt.phase == "recovery" and receipt.attempts == 0,
        "explicit retry must re-arm proven detached cargo: " .. tostring(retryReason))
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == true
        and receipt.phase == "carried",
        "re-armed detached cargo must reconstruct exactly once")
end

-- G14/G15/G17/G20/G22: ambiguous third owners quarantine, full storage keeps
-- cargo, protected items stay untouched, pause releases selections, and actor
-- retirement never duplicates carried cargo.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "third-owner setup pickup must succeed")
    local third = makeInventory("third")
    ctx.actor.inventory:Remove(item)
    third:AddItem(item)
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == false
        and receipt.phase == "quarantined" and #third.items == 1,
        "unknown third owner must quarantine without copying")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "full-destination setup pickup must succeed")
    ctx.storageObject.container.room = false
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == false
        and receipt.phase == "carried" and ctx.actor.inventory:contains(item)
        and ctx.order.delivered == 0, "full destination must retain carried cargo")

    ctx = setup("logs", 1)
    local quest = makeItem("Base.Log", { modData = { LF_QuestItem = true } })
    local favorite = makeItem("Base.Log", { favorite = true })
    putOnGround(ctx.source, quest)
    putOnGround(ctx.source, favorite)
    local candidate, _, complete = SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(candidate == nil and complete == true and #ctx.source.worldItems == 2,
        "quest and favorite items must be excluded")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.PersonalItems.isProtected(item, ctx.actor, "trade") == true
        and SC.PersonalItems.isProtected(item, ctx.actor, "base_haul") == true
        and SC.PersonalItems.isProtected(item, ctx.actor, "build_material") == true,
        "active work receipt must be visible to trade, hauling, and crafting consumers")
    SC.WorkTransport.abandonSelected(receipt, "fixture_continue")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    local cancelsBeforePause = navigationCancels
    check(SC.BaseLife.pauseGatherOrder(ctx.order.id) == true
        and receipt.phase == "cancelled" and SC.WorkTransport.marker(item) == nil,
        "pause must release a verified floor selection")
    check(navigationCancels > cancelsBeforePause,
        "pause must cancel the worker's owned gathering navigation")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "retirement setup pickup must succeed")
    SC.WorkTransport.prepareActorRetirement(ctx.actor)
    check(receipt.phase == "quarantined" and ctx.actor.inventory:contains(item)
        and #ctx.actor.inventory.items == 1,
        "retirement must quarantine the one native cargo owner")
    local released, releaseReason = SC.WorkTransport.releaseCarriedCargo(
        ctx.order.id, ctx.actor.modData.SC_Id)
    check(released == true and receipt.phase == "released"
        and SC.WorkTransport.marker(item) == nil and ctx.actor.inventory:contains(item),
        "explicit release must unmark quarantined native cargo without moving it: "
            .. tostring(releaseReason))
end


-- G16: dependent storage removal is rejected, while an explicit destination
-- change updates the order and every unresolved receipt before work resumes.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.BaseLife.removeStorage(ctx.storage.id) == false,
        "active receipt must pin its exact registered destination")
    local alternateSquare = addSquare(1, 1, 0)
    local alternateObject = makeStorage(alternateSquare)
    local accepted, alternate = SC.BaseLife.registerStorage(alternateObject, "construction")
    check(accepted == true and alternate ~= nil, "alternate destination must register")
    check(SC.BaseLife.changeGatherDestination(ctx.order.id, alternate.id) == true
        and ctx.order.destinationStorageId == alternate.id
        and receipt.destinationStorageId == alternate.id,
        "explicit destination change must update unresolved ownership records")
end

-- G26/G29: bounded recovery cursor makes progress across receipts, old saves
-- receive an empty work document, and future work schemas are quarantined.
do
    local ctx = setup("logs", 2)
    local first, second = makeItem("Base.Log"), makeItem("Base.Log")
    putOnGround(ctx.source, first)
    putOnGround(ctx.source, second)
    local receipt = reserveCandidate(ctx, ctx.actor, first)
    local distant = addSquare(-2, 0, 0)
    ctx.actor.x, ctx.actor.y, ctx.actor.square = distant.x, distant.y, distant
    rejectNavigation = true
    local handled, failureReason, terminal = SC.GatherWork.update(
        ctx.actor, {}, ctx.base.jobs[1])
    rejectNavigation = false
    check(handled == false and terminal == true and failureReason == "fixture_unreachable"
        and receipt.phase == "cancelled" and SC.WorkTransport.marker(first) == nil,
        "unreachable first candidate must release only its own pre-pickup claim")
    ctx.actor.x, ctx.actor.y, ctx.actor.square = 0, 0, squares[squareKey(0, 0, 0)]
    local tail = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actor))
    check(tail ~= nil and tail.item == second,
        "failed first candidate must not starve a valid tail candidate")

    ctx = setup("logs", 2, 2)
    first, second = makeItem("Base.Log"), makeItem("Base.Log")
    putOnGround(ctx.source, first)
    putOnGround(ctx.source, second)
    local receiptOne = reserveCandidate(ctx, ctx.actors[1], first)
    local candidate = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actors[2]))
    local receiptTwo = SC.WorkTransport.reserve(ctx.order, ctx.base.jobs[2],
        ctx.actors[2], candidate.item, candidate.worldItem, candidate.square)
    check(receiptTwo ~= nil, "second recovery receipt must reserve")
    SC.WorkTransport.reset()
    SC.WorkTransport.recoverPending(1)
    SC_TEST_CLOCK = SC_TEST_CLOCK + 50
    SC.WorkTransport.recoverPending(1)
    check(SC.WorkTransport.runtimeItem(receiptOne.id) ~= nil
        and SC.WorkTransport.runtimeItem(receiptTwo.id) ~= nil,
        "fair recovery cursor must visit both receipts")

    local malformed = SC.BaseLife.export()
    malformed.bases[malformed.activeBaseId].work.receipts[1].snapshot = nil
    check(SC.BaseLife.restore(malformed) == false,
        "receipt restore must reject missing reconstruction evidence")
    malformed = SC.BaseLife.export()
    malformed.bases[malformed.activeBaseId].work.receipts[1].itemType = "Base.Plank"
    check(SC.BaseLife.restore(malformed) == false,
        "receipt restore must reject a parent-order material mismatch")

    local legacy = SC.BaseLife.export()
    legacy.bases[legacy.activeBaseId].work = nil
    check(SC.BaseLife.restore(legacy) == true
        and #SC.BaseLife.active().work.orders == 0,
        "legacy base document must default to empty work state")
    local future = SC.BaseLife.export()
    future.bases[future.activeBaseId].work = { version = 999, payload = { future = true } }
    check(SC.BaseLife.restore(future) == true
        and SC.BaseLife.active().work.quarantine.reason == "unsupported_work_version",
        "future work document must be preserved in quarantine")
end

-- Transactional ownership proof is not constrained by the routine 256-item AI
-- scan, and yielding one worker leaves the remaining gatherer on duty.
do
    local ctx = setup("logs", 1)
    for index = 1, 300 do
        ctx.storageObject.container:AddItem(makeItem("Base.Nails" .. tostring(index)))
    end
    local gathered = makeItem("Base.Log")
    putOnGround(ctx.source, gathered)
    dispatchUntilTerminal(ctx, 30)
    check(ctx.order.state == "completed" and ctx.order.delivered == 1
            and ctx.storageObject.container:contains(gathered),
        "delivery into a container above the routine scan cap remains exactly verified")

    ctx = setup("logs", 2, 2)
    local first, second = makeItem("Base.Log"), makeItem("Base.Log")
    putOnGround(ctx.source, first)
    putOnGround(ctx.source, second)
    local firstReceipt = reserveCandidate(ctx, ctx.actors[1], first)
    local secondCandidate = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actors[2]))
    local secondReceipt = SC.WorkTransport.reserve(ctx.order, ctx.base.jobs[2],
        ctx.actors[2], secondCandidate.item, secondCandidate.worldItem, secondCandidate.square)
    check(secondReceipt ~= nil, "second worker must own an independent selection")
    check(SC.BaseLife.setDuty(ctx.actors[1].modData.SC_Id, false) == true
            and firstReceipt.phase == "cancelled" and secondReceipt.phase == "selected"
            and ctx.order.state == "running" and #ctx.order.workers == 1
            and ctx.order.workers[1] == ctx.actors[2].modData.SC_Id,
        "taking one of two workers off duty releases only that worker's selection")
    local remainingGatherJobs, removedWorkerJobs = 0, 0
    for _, job in ipairs(ctx.base.jobs) do
        if job.type == "gather_materials" and job.target.orderId == ctx.order.id then
            remainingGatherJobs = remainingGatherJobs + 1
            if job.assignedId == ctx.actors[1].modData.SC_Id then
                removedWorkerJobs = removedWorkerJobs + 1
            end
        end
    end
    check(remainingGatherJobs == 1 and removedWorkerJobs == 0,
        "duty-off retires only the departing worker's live gather job")
    check(SC.BaseLife.setDuty(ctx.actors[1].modData.SC_Id, true) == true,
        "departing worker can return to ordinary base duty")
    local staleOk, staleJob = SC.BaseLife.enqueueJob({
        type = "gather_materials", assignedId = ctx.actors[1].modData.SC_Id,
        priority = 5, target = { orderId = ctx.order.id },
    })
    local otherOk, otherJob = SC.BaseLife.enqueueJob({
        type = "repair", assignedId = ctx.actors[1].modData.SC_Id, priority = 1,
    })
    local claimed = SC.BaseLife.claimJob(ctx.actors[1].modData.SC_Id)
    check(staleOk == true and otherOk == true and claimed == otherJob
            and SC.BaseLife.job(staleJob.id) == nil
            and SC.BaseLife.job(otherJob.id) == otherJob,
        "defensive claiming removes a restored stale gather row and permits legitimate work")
end

-- A finite candidate cooldown is waiting, not proof that the work area is
-- empty. The same item becomes eligible automatically when its timer expires.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    local candidate = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actor))
    check(candidate ~= nil and SC.GatherWork.noteCandidateFailure(
        ctx.order.id, candidate, "transient_path_failure") == true,
        "cooldown fixture records one transient candidate failure")
    SC_TEST_CLOCK = SC_TEST_CLOCK
        + (SC.GameplayUtil.config("baseJobRetryMs") or 10000) + 1
    local waiting, waitingReason, waitingComplete =
        SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(waiting == nil
            and waitingReason == "gather_candidates_temporarily_unavailable"
            and waitingComplete == false and ctx.order.state == "running",
        "candidate cooling beyond the job retry stays nonterminal and keeps the order running")
    SC_TEST_CLOCK = SC_TEST_CLOCK
        + math.max(1, (SC.GameplayUtil.config("workGatherCandidateCooldownMs") or 15000)
            - (SC.GameplayUtil.config("baseJobRetryMs") or 10000))
    local recovered, recoveredReason = SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(recovered ~= nil and recovered.item == item
            and recoveredReason == "gather_candidate_found",
        "cooling candidate becomes collectable without a manual order retry")

    ctx = setup("logs", 1)
    item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    candidate = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actor))
    for _ = 1, (SC.GameplayUtil.config("workGatherCandidateMaxAttempts") or 3) do
        SC.GatherWork.noteCandidateFailure(ctx.order.id, candidate, "permanent_path_failure")
    end
    SC_TEST_CLOCK = SC_TEST_CLOCK
        + (SC.GameplayUtil.config("workGatherCandidateCooldownMs") or 15000) + 1
    local exhausted, exhaustedReason, exhaustedComplete =
        SC.GatherWork.nextCandidate(ctx.order, ctx.actor)
    check(exhausted == nil and exhaustedReason == "gather_candidates_exhausted"
            and exhaustedComplete == true,
        "permanently exhausted candidates are distinct from a genuinely empty area")
end

-- Historical receipt ownership is independent from the current worker list.
-- Zero-worker paused orders and terminal/unresolved history must round-trip,
-- while malformed identities and active ownership shapes still fail closed.
do
    local ctx = setup("logs", 1)
    check(SC.BaseLife.setDuty(ctx.actor.modData.SC_Id, false) == true
            and ctx.order.state == "paused" and #ctx.order.workers == 0,
        "the last worker leaving must pause an otherwise valid empty order")
    local saved = SC.BaseLife.export()
    check(SC.BaseLife.restore(saved) == true
            and SC.BaseLife.workOrder(ctx.order.id).state == "paused",
        "a one-worker duty-off order must restore without quarantine")
    check(SC.BaseLife.restore(SC.BaseLife.export()) == true,
        "the empty paused assignment must survive a second save cycle")
    local resumed, resumeReason = SC.BaseLife.resumeGatherOrder(ctx.order.id)
    check(resumed == false and resumeReason == "gather_worker_missing",
        "an empty historical assignment must not become a running order")

    ctx = setup("logs", 2, 2)
    local delivered = makeItem("Base.Log")
    putOnGround(ctx.source, delivered)
    local receipt = reserveCandidate(ctx, ctx.actors[1], delivered)
    check(SC.WorkTransport.collect(receipt, ctx.actors[1], delivered,
            delivered.worldItem) == true
            and SC.WorkTransport.deposit(receipt, ctx.actors[1], delivered) == true,
        "terminal receipt history fixture must deliver once")
    check(SC.BaseLife.setDuty(ctx.actors[1].modData.SC_Id, false) == true
            and #ctx.order.workers == 1 and receipt.phase == "delivered",
        "removing a worker must not erase its terminal receipt history")
    check(SC.BaseLife.restore(SC.BaseLife.export()) == true
            and SC.BaseLife.workReceipt(receipt.id).actorId
                == ctx.actors[1].modData.SC_Id,
        "terminal receipt ownership may outlive live assignment")

    local invalid = SC.BaseLife.export()
    invalid.bases[invalid.activeBaseId].work.receipts[1].actorId = "not-a-companion"
    check(SC.BaseLife.restore(invalid) == false,
        "receipt history must still reject invalid actor identities")

    ctx = setup("logs", 1)
    local selected = makeItem("Base.Log")
    putOnGround(ctx.source, selected)
    reserveCandidate(ctx, ctx.actor, selected)
    local malformed = SC.BaseLife.export()
    malformed.bases[malformed.activeBaseId].work.receipts[1].owner = "actor"
    check(SC.BaseLife.restore(malformed) == false,
        "active selected ownership must still reject an actor-owner mismatch")

    ctx = setup("logs", 2, 2)
    local detached = makeItem("Base.Log")
    putOnGround(ctx.source, detached)
    receipt = reserveCandidate(ctx, ctx.actors[1], detached)
    check(SC.WorkTransport.collect(receipt, ctx.actors[1], detached,
        detached.worldItem) == true, "unresolved history fixture must collect")
    ctx.actors[1].inventory:Remove(detached)
    receipt.phase, receipt.owner, receipt.detachedProof = "recovery", "detached", true
    check(SC.BaseLife.setDuty(ctx.actors[1].modData.SC_Id, false) == true
            and #ctx.order.workers == 1,
        "unresolved detached ownership must not pin the live assignment")
    check(SC.BaseLife.restore(SC.BaseLife.export()) == true
            and SC.BaseLife.workReceipt(receipt.id).phase == "recovery",
        "unresolved detached ownership must remain recoverable after restore")
end

-- Proven native absence remains false, not unknown. If floor removal mutates
-- state and both immediate destinations reject the item, the exact recovery
-- record survives save/reload and wins over snapshot reconstruction.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log", { condition = 49 })
    local wrapper = putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    local addWorld = ctx.source.AddWorldInventoryItem
    ctx.source.AddWorldInventoryItem = function() return nil end
    ctx.actor.inventory.rejectAdd = true
    local collected = SC.WorkTransport.collect(receipt, ctx.actor, item, wrapper)
    check(collected == false and receipt.phase == "recovery"
            and receipt.owner == "detached" and receipt.detachedProof == true,
        "mutation-then-failure pickup must enter explicit detached recovery")
    check(SC.GameplayUtil.pendingWorldRecovery(item) ~= nil,
        "detached native item must retain one exact recovery owner")
    local saved = SC.BaseLife.export()
    SC.WorkTransport.reset()
    ctx.actor.inventory.rejectAdd = false
    ctx.source.AddWorldInventoryItem = addWorld
    check(SC.BaseLife.restore(saved) == true, "detached pickup must save and restore")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    check(SC.WorkTransport.reconcile(receipt, ctx.actor) == true
            and SC.WorkTransport.runtimeItem(receipt.id) == item
            and ctx.actor.inventory:contains(item),
        "retry must recover the exact native item instead of manufacturing a copy")
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == true
            and SC.BaseLife.workOrder(ctx.order.id).delivered == 1,
        "recovered pickup must deliver and account exactly once")
end

-- Chore delegates preserve both return values instead of collapsing the reason
-- through boolean expressions.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    ctx.base.settings.routines = false
    local oldMedical = SC.Medical
    local calls = 0
    SC.Medical = {
        replaceDirtyBandage = function()
            calls = calls + 1
            return true, "bandaged"
        end,
        peek = function() return nil end,
    }
    local accepted, job = SC.BaseLife.enqueueJob({
        type = "replace_bandage", assignedId = ctx.actor.modData.SC_Id, priority = 5,
    })
    check(accepted == true and select(1, SC.BaseWork.update(ctx.actor, nil, {})) == true
            and SC.BaseLife.job(job.id) == nil and calls == 1,
        "successful bandaging must complete exactly once")
    SC.BaseWork.update(ctx.actor, nil, {})
    check(calls == 1, "completed bandage work must not run again")
    SC.Medical = oldMedical

    ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    oldMedical = SC.Medical
    SC.Medical = {
        replaceDirtyBandage = function() return false, "no_treatable_wound" end,
        peek = function() return nil end,
    }
    accepted, job = SC.BaseLife.enqueueJob({
        type = "replace_bandage", assignedId = ctx.actor.modData.SC_Id, priority = 5,
    })
    handled, reason = SC.BaseWork.update(ctx.actor, nil, {})
    check(accepted == true and handled == true and reason == "already_treated"
            and SC.BaseLife.job(job.id) == nil,
        "a stale bandage job completes after another care path treated the wound")
    SC.Medical = oldMedical

    ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    oldMedical = SC.Medical
    SC.Medical = {
        replaceDirtyBandage = function() return true, "treating" end,
        peek = function() return { phase = "active" } end,
    }
    accepted, job = SC.BaseLife.enqueueJob({
        type = "replace_bandage", assignedId = ctx.actor.modData.SC_Id, priority = 5,
    })
    local handled, reason = SC.BaseWork.update(ctx.actor, nil, {})
    check(accepted == true and handled == true and reason == "treating"
            and SC.BaseLife.job(job.id) ~= nil,
        "intermediate medical state must stay active with its reason intact")
    SC.Medical = oldMedical

    ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    oldMedical = SC.Medical
    SC.Medical = nil
    accepted, job = SC.BaseLife.enqueueJob({
        type = "replace_bandage", assignedId = ctx.actor.modData.SC_Id, priority = 5,
    })
    handled, reason = SC.BaseWork.update(ctx.actor, nil, {})
    check(accepted == true and handled == false and reason == "medical_unavailable"
            and SC.BaseLife.job(job.id).state == "blocked",
        "missing medical module must fail once with an explicit blocker")
    SC.Medical = oldMedical

    ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local oldDowntime = SC.Downtime
    SC.Downtime = { update = function() return false, "stable_idle" end }
    accepted, job = SC.BaseLife.enqueueJob({
        type = "repair", assignedId = ctx.actor.modData.SC_Id, priority = 1,
    })
    handled, reason = SC.BaseWork.update(ctx.actor, nil, {})
    SC_TEST_CLOCK = SC_TEST_CLOCK
        + (SC.GameplayUtil.config("downtimeSafeMs") or 5000) + 3001
    handled, reason = SC.BaseWork.update(ctx.actor, nil, {})
    check(accepted == true and handled == false and reason == "stable_idle"
            and SC.BaseLife.job(job.id).state == "blocked",
        "stable idle after the chore deadline must exhaust instead of looping forever")
    SC.Downtime = oldDowntime
end

-- Sort/haul selection and the authoritative post-animation commit both honor
-- live reserves. Two workers may select distinct items, but cannot collectively
-- withdraw below the configured reserve.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    SC.BaseLife.setStorageCategory(ctx.storage.id, "general")
    local pantryObject = makeStorage(addSquare(2, 0, 0))
    local fridgeObject = makeStorage(addSquare(3, 0, 0))
    local pantryOk, pantry = SC.BaseLife.registerStorage(pantryObject, "food")
    local fridgeOk, fridge = SC.BaseLife.registerStorage(fridgeObject, "fresh_food")
    local tomato = makeItem("Base.Tomato", { category = "Food", offAgeMax = 7 })
    local canned = makeItem("Base.CannedBeans", { category = "Food" })
    local cured = makeItem("Base.CuredMeat", { category = "Food", offAgeMax = 280 })
    check(pantryOk == true and fridgeOk == true
            and select(1, SC.BaseWork.destinationForCarItem(ctx.actor, tomato)) == fridge
            and select(1, SC.BaseWork.destinationForCarItem(ctx.actor, canned)) == pantry
            and select(1, SC.BaseWork.destinationForCarItem(ctx.actor, cured)) == pantry,
        "fresh food uses the fresh marker while canned and long-lived food use the pantry")
    SC.BaseLife.setStorageCategory(pantry.id, "general")
    check(select(1, SC.BaseWork.destinationForCarItem(ctx.actor, canned)) == fridge,
        "the fresh marker accepts all food when it is the only food store")
    SC.BaseLife.setStorageCategory(pantry.id, "food")
    SC.BaseLife.setStorageCategory(fridge.id, "general")
    check(select(1, SC.BaseWork.destinationForCarItem(ctx.actor, tomato)) == pantry,
        "the regular marker accepts fresh food when it is the only food store")
end

do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    SC.BaseLife.setStorageCategory(ctx.storage.id, "general")
    local pantryObject = makeStorage(addSquare(2, 0, 0))
    local fridgeObject = makeStorage(addSquare(3, 0, 0))
    SC.BaseLife.registerStorage(pantryObject, "food")
    SC.BaseLife.registerStorage(fridgeObject, "fresh_food")
    local tomato = makeItem("Base.Tomato", { category = "Food", offAgeMax = 7 })
    local canned = makeItem("Base.CannedBeans", { category = "Food" })
    ctx.storageObject.container:AddItem(tomato)
    ctx.storageObject.container:AddItem(canned)
    local oldVisualStatus = SC.NativeActions.visualStatus
    SC.NativeActions.visualStatus = function() return "completed" end
    for _ = 1, 2 do
        SC.BaseLife.enqueueJob({ type = "sort", assignedId = ctx.actor.modData.SC_Id,
            priority = 2 })
        for _ = 1, 8 do
            SC_TEST_CLOCK = SC_TEST_CLOCK + 50
            SC.BaseWork.update(ctx.actor, nil, {})
            if pantryObject.container:contains(canned)
                and fridgeObject.container:contains(tomato) then break end
        end
    end
    SC.NativeActions.visualStatus = oldVisualStatus
    check(pantryObject.container:contains(canned)
            and fridgeObject.container:contains(tomato),
        "automatic sorting separates fresh food from shelf-stable food")
end

do
    local ctx = setup("logs", 1, 2)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    SC.BaseLife.setStorageCategory(ctx.storage.id, "general")
    local destinationObject = makeStorage(ctx.actor.square)
    local destinationOk, destination = SC.BaseLife.registerStorage(
        destinationObject, "medical")
    check(destinationOk == true, "sorted destination fixture must register")
    local first, second = makeItem("Base.Bandage"), makeItem("Base.Bandage")
    ctx.storageObject.container:AddItem(first)
    ctx.storageObject.container:AddItem(second)
    SC.BaseLife.setReserve(ctx.storage.id, "Base.Bandage", 1)
    local firstJobOk = SC.BaseLife.enqueueJob({
        type = "sort", assignedId = ctx.actors[1].modData.SC_Id, priority = 2,
    })
    local secondJobOk, secondJob = SC.BaseLife.enqueueJob({
        type = "sort", assignedId = ctx.actors[2].modData.SC_Id, priority = 2,
    })
    check(firstJobOk == true and secondJobOk == true, "two sort jobs must queue")
    local oldProtected = SC.PersonalItems.isProtected
    SC.PersonalItems.isProtected = function(item, actor, operation)
        if operation == "base_haul" and actor == ctx.actors[2] and item == first then
            return true
        end
        return oldProtected and oldProtected(item, actor, operation) or false
    end
    local oldVisualStatus = SC.NativeActions.visualStatus
    local started = {}
    SC.NativeActions.visualStatus = function(actor)
        if not started[actor] then started[actor] = true return "active" end
        return "completed"
    end
    check(select(2, SC.BaseWork.update(ctx.actors[1], nil, {})) == "base_storage_looting"
            and select(2, SC.BaseWork.update(ctx.actors[2], nil, {}))
                == "base_storage_looting",
        "both workers may begin against the same pre-commit availability")
    check(select(1, SC.BaseWork.update(ctx.actors[1], nil, {})) == true,
        "the first worker may withdraw the one unreserved item")
    local secondHandled, secondReason = SC.BaseWork.update(ctx.actors[2], nil, {})
    check(secondHandled == false and secondReason == "base_supply_reserved"
            and SC.BaseLife.job(secondJob.id).state == "blocked"
            and #ctx.storageObject.container.items == 1
            and #destinationObject.container.items == 1,
        "the second authoritative commit must preserve the final reserved item")
    SC.NativeActions.visualStatus = oldVisualStatus
    SC.PersonalItems.isProtected = oldProtected
end

-- F2: a full destination must not strand cargo. The worker picks a store
-- with room, keeps one exact cargo receipt when every store is full, and
-- never withdraws a second item while still holding the first.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    SC.BaseLife.setStorageCategory(ctx.storage.id, "general")
    local fullObject = makeStorage(addSquare(2, 0, 0))
    local fullOk, full = SC.BaseLife.registerStorage(fullObject, "medical")
    local roomyObject = makeStorage(addSquare(3, 0, 0))
    local roomyOk, roomy = SC.BaseLife.registerStorage(roomyObject, "medical")
    check(fullOk == true and roomyOk == true and full.id ~= roomy.id,
        "two sorted destinations must register")
    fullObject.container.room = false
    local function carried()
        local count = 0
        for _, item in ipairs(ctx.actor.inventory.items) do
            if item.fullType == "Base.Bandage" then count = count + 1 end
        end
        return count
    end
    local first, second = makeItem("Base.Bandage"), makeItem("Base.Bandage")
    ctx.storageObject.container:AddItem(first)
    ctx.storageObject.container:AddItem(second)
    local queued = SC.BaseLife.enqueueJob({
        type = "sort", assignedId = ctx.actor.modData.SC_Id, priority = 2,
    })
    local oldVisualStatus = SC.NativeActions.visualStatus
    SC.NativeActions.visualStatus = function() return "completed" end
    check(queued == true, "a sort job must queue")
    local trace = {}
    for _ = 1, 6 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 50
        local handled, value = SC.BaseWork.update(ctx.actor, nil, {})
        trace[#trace + 1] = tostring(handled) .. ":" .. tostring(value)
        if #roomyObject.container.items > 0 then break end
    end
    check(#roomyObject.container.items == 1 and #fullObject.container.items == 0
            and carried() == 0,
        "a full destination is skipped for one that has room: " .. table.concat(trace, ", "))

    -- Every destination full: the cargo goes back where it came from.
    roomyObject.container.room = false
    SC.BaseLife.enqueueJob({ type = "sort", assignedId = ctx.actor.modData.SC_Id, priority = 2 })
    local fullReason
    for _ = 1, 5 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 50
        local _, value = SC.BaseWork.update(ctx.actor, nil, {})
        fullReason = value
    end
    check(carried() == 0 and #ctx.storageObject.container.items == 1,
        "with every store full the cargo is returned to its source, not stranded: "
            .. tostring(fullReason))

    -- A deposit refused after pickup must not pile up more cargo, and
    -- cancelling base work returns whatever the worker still holds.
    roomyObject.container.room = true
    local oldTransfer = SC.WorkTransport.transferVerified
    SC.WorkTransport.transferVerified = function(source, destination, item, actor)
        if destination == roomyObject.container or destination == fullObject.container then
            return false, "fixture_deposit_refused"
        end
        return oldTransfer(source, destination, item, actor)
    end
    SC.BaseLife.enqueueJob({ type = "sort", assignedId = ctx.actor.modData.SC_Id, priority = 2 })
    for _ = 1, 6 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 50
        SC.BaseWork.update(ctx.actor, nil, {})
    end
    check(carried() <= 1, "a refused deposit never lets the worker accumulate cargo: "
        .. tostring(carried()))
    SC.WorkTransport.transferVerified = oldTransfer
    SC.BaseWork.cancel(ctx.actor, "harness_cleanup")
    check(carried() == 0, "cancelling base work returns any cargo the worker still holds")
    SC.NativeActions.visualStatus = oldVisualStatus
end

-- F3: a build is complete only with a real completion receipt and the
-- requested object actually present.
do
    local square = addSquare(7, 7, 0)
    local function object(spriteName)
        local sprite = { getName = function() return spriteName end }
        return { getSprite = function() return sprite end }
    end
    local outcome = SC.BaseWork._buildOutcomeForTests
    local cancelled = { action = { scStopped = true }, buildSpriteName = "walls_01",
        initialObjectCount = 0 }
    check(outcome(cancelled, square) == "cancelled",
        "a cancelled action with nothing built is never complete")
    square.objects[#square.objects + 1] = object("unrelated_02")
    check(outcome(cancelled, square) == "cancelled",
        "an unrelated object appearing is not the requested build")
    local performed = { action = { scCompleted = true }, buildSpriteName = "walls_01",
        initialObjectCount = 0 }
    check(outcome(performed, square) == "missing",
        "a finished action without its object reports a missing result, not success")
    square.objects[#square.objects + 1] = object("walls_01")
    check(outcome(performed, square) == "complete",
        "the requested sprite at the target square completes the job")
end

-- F4: supplies inside a bag count, and are staged where the build action
-- can use them.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local bag = makeItem("Base.Bag_Normal")
    bag.nested = makeInventory("bag")
    function bag:getInventory() return self.nested end
    local hammer = makeItem("Base.Hammer")
    ctx.actor.inventory:AddItem(bag)
    bag.nested:AddItem(hammer)
    local counted = SC.BaseWork._carriedSuppliesForTests(ctx.actor, "Base.Hammer")
    check(counted == 1, "a hammer inside a bag is carried, not missing: " .. tostring(counted))
    local staged, stagedReason = SC.BaseWork._stageCarriedSupplyForTests(ctx.actor, "Base.Hammer", 1)
    check(staged == true and ctx.actor.inventory:contains(hammer)
            and not bag.nested:contains(hammer),
        "the nested hammer is staged into the worker's own hands: " .. tostring(stagedReason))
    local again = select(2, SC.BaseWork._stageCarriedSupplyForTests(ctx.actor, "Base.Hammer", 1))
    check(again == "supply_at_hand", "an already staged supply needs no second move")
    check(SC.BaseWork._carriedSuppliesForTests(ctx.actor, "Base.Saw") == 0,
        "a tool nobody carries is still missing")
end

-- Terminal deliveries release live item references immediately. If marker
-- removal itself fails, only that bounded cleanup record retains the item and
-- remains durable through pruning, actor reset and save/reload.
do
    local ctx = setup("logs", 1)
    local receiptIds = {}
    for iteration = 1, 40 do
        if iteration > 1 then
            local accepted, order = SC.BaseLife.createGatherOrder({
                material = "logs", requested = 1, zoneId = ctx.order.zoneId,
                destinationStorageId = ctx.storage.id,
                workers = { ctx.actor.modData.SC_Id },
            })
            check(accepted == true, "history stress order must fit after pruning")
            ctx.order = order
        end
        local item = makeItem("Base.Log")
        putOnGround(ctx.source, item)
        dispatchUntilTerminal(ctx, 30)
        local rows = SC.BaseLife.workReceipts(ctx.order.id, true)
        check(ctx.order.state == "completed" and #rows == 1,
            "history stress delivery must terminate")
        receiptIds[#receiptIds + 1] = rows[1].id
        check(SC.WorkTransport.runtimeItem(rows[1].id) == nil,
            "successful terminal delivery must release its live item reference")
    end
    for _, receiptId in ipairs(receiptIds) do
        check(SC.WorkTransport.runtimeItem(receiptId) == nil,
            "pruned terminal histories must not orphan strong references")
    end
    check(#ctx.base.work.orders <= (SC.GameplayUtil.config("workOrderRecordLimit") or 32)
            and #ctx.base.work.receipts
                <= (SC.GameplayUtil.config("workRecoveryMaxEntries") or 32),
        "work history stress must remain bounded by configured caps")

    ctx = setup("logs", 1)
    local rejectClear = false
    local backing = {}
    local proxy = setmetatable({}, {
        __index = function(_, key) return backing[key] end,
        __newindex = function(_, key, value)
            if rejectClear and value == nil
                and (key == SC.WorkTransport.MARKERS.id
                    or key == SC.WorkTransport.MARKERS.state) then return end
            backing[key] = value
        end,
    })
    local item = makeItem("Base.Log", { modData = proxy })
    putOnGround(ctx.source, item)
    local receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "marker cleanup fixture must collect")
    rejectClear = true
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == true
            and receipt.phase == "delivered" and receipt.markerCleanupPending == true
            and SC.WorkTransport.runtimeItem(receipt.id) == item,
        "failed marker removal must retain only its terminal cleanup record")
    check(SC.BaseLife.removeWorkReceipt(receipt.id) == false,
        "pruning must refuse a receipt whose marker cleanup is unresolved")
    check(SC.BaseLife.removeStorage(ctx.storage.id) == false,
        "unresolved marker cleanup must pin its exact destination storage")
    SC.WorkTransport.reset(ctx.actor)
    check(SC.WorkTransport.runtimeItem(receipt.id) == item,
        "actor reset must not orphan destination marker cleanup")
    local saved = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(saved) == true
            and SC.BaseLife.workReceipt(receipt.id).markerCleanupPending == true,
        "unresolved marker cleanup must survive save and restore")
    rejectClear = false
    SC_TEST_CLOCK = SC_TEST_CLOCK
        + (SC.GameplayUtil.config("workRecoveryRetryMaximumMs") or 5000) + 1
    SC.WorkTransport.recoverPending(1)
    receipt = SC.BaseLife.workReceipt(receipt.id)
    check(receipt.markerCleanupPending == false
            and SC.WorkTransport.marker(item) == nil
            and SC.WorkTransport.runtimeItem(receipt.id) == nil,
        "bounded marker retry must clear the stale marker and strong reference")

    ctx = setup("logs", 1)
    rejectClear, backing = false, {}
    proxy = setmetatable({}, {
        __index = function(_, key) return backing[key] end,
        __newindex = function(_, key, value)
            if rejectClear and value == nil
                and (key == SC.WorkTransport.MARKERS.id
                    or key == SC.WorkTransport.MARKERS.state) then return end
            backing[key] = value
        end,
    })
    item = makeItem("Base.Log", { modData = proxy })
    putOnGround(ctx.source, item)
    receipt = reserveCandidate(ctx, ctx.actor, item)
    check(SC.WorkTransport.collect(receipt, ctx.actor, item, item.worldItem) == true,
        "bounded cleanup fixture must collect")
    rejectClear = true
    check(SC.WorkTransport.deposit(receipt, ctx.actor, item) == true
            and receipt.markerCleanupPending == true,
        "bounded cleanup fixture must enter marker recovery")
    local maximumAttempts = SC.GameplayUtil.config("workRecoveryMaxAttempts") or 8
    local maximumDelay = SC.GameplayUtil.config("workRecoveryRetryMaximumMs") or 5000
    for _ = 1, maximumAttempts do
        SC_TEST_CLOCK = SC_TEST_CLOCK + maximumDelay + 1
        SC.WorkTransport.recoverPending(1)
    end
    check(receipt.markerCleanupAttempts == maximumAttempts
            and receipt.blocker == "work_marker_cleanup_exhausted"
            and SC.WorkTransport.runtimeItem(receipt.id) == item,
        "marker cleanup must stop automatically while retaining its exact item")
    SC_TEST_CLOCK = SC_TEST_CLOCK + maximumDelay + 1
    SC.WorkTransport.recoverPending(1)
    check(receipt.markerCleanupAttempts == maximumAttempts,
        "exhausted marker cleanup must consume no further automatic attempts")
    local cleanupSummary = SC.BaseLife.summary().workOrders[1]
    check(cleanupSummary and cleanupSummary.cleanupPending == 1
            and cleanupSummary.cleanupExhausted == 1,
        "terminal marker cleanup is visible through the public base summary")
    local cleanupSave = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(cleanupSave) == true,
        "exhausted terminal cleanup must survive save and restore")
    receipt = SC.BaseLife.workReceipt(receipt.id)
    rejectClear = false
    local retried, retryReason = SC.BaseLife.retryGatherOrder(ctx.order.id)
    local terminalOrder = SC.BaseLife.workOrder(ctx.order.id)
    check(retried == true and retryReason == "work_marker_cleanup_retried"
            and terminalOrder.state == "completed" and terminalOrder.delivered == 1,
        "public retry re-arms terminal cleanup without reopening its order")
    SC.WorkTransport.recoverPending(1)
    check(receipt.markerCleanupPending == false
            and SC.WorkTransport.runtimeItem(receipt.id) == nil,
        "explicit marker retry must release the retained exact item on success")
end

-- Repeated failures keep one FIFO entry for the identity. Trimming unrelated
-- candidates must not erase a newer permanent cooldown through an old duplicate.
do
    local ctx = setup("logs", 1)
    local item = makeItem("Base.Log")
    putOnGround(ctx.source, item)
    local function nextCandidate()
        for _ = 1, 3 do
            local value = select(1, SC.GatherWork.nextCandidate(ctx.order, ctx.actor))
            if value ~= nil then return value end
        end
        return nil
    end
    local candidate = nextCandidate()
    check(candidate ~= nil, "cooldown candidate must be discovered")
    for attempt = 1, 3 do
        check(SC.GatherWork.noteCandidateFailure(
            ctx.order.id, candidate, "fixture_failure"),
            "candidate failure must be recorded")
        if attempt < 3 then
            SC_TEST_CLOCK = SC_TEST_CLOCK + 100000
            candidate = nextCandidate()
            check(candidate ~= nil, "expired finite cooldown permits its bounded retry")
        end
    end
    for index = 1, 30 do
        SC.GatherWork.noteCandidateFailure(ctx.order.id,
            { key = "fixture-noise:" .. tostring(index) }, "noise")
    end
    local dormant = nextCandidate()
    check(dormant == nil,
        "queue trimming cannot wake a permanently dormant duplicated identity")
end

-- A guard on shift keeps watch around the square it was told to guard and
-- leaves generic chores to the other residents.
do
    local ctx = setup("logs", 1)
    local guard = ctx.actor
    local guardId = guard.modData.SC_Id
    check(SC.BaseLife.assign(guardId, "guard", true) == true, "guard joins base duty")
    for _, offset in ipairs({ { 0, 0 }, { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 } }) do
        addSquare(3 + offset[1], -2 + offset[2], 0)
    end
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local priorCommands = SC.Commands
    SC.Commands = {
        peek = function(actor)
            if actor ~= guard then return nil end
            return { order = "base_duty", anchor = { x = 3, y = -2, z = 0 } }
        end,
    }
    local post = SC.BaseWork._guardPostForTests(guard)
    local originalInside = SC.BaseLife.isInside
    SC.BaseLife.isInside = function(value)
        if type(value) == "table" and value.x ~= nil then return true end
        return originalInside(value)
    end
    SC.Commands.peek = function(actor)
        if actor ~= guard then return nil end
        return { order = "base_duty", anchor = { x = 0, y = 0, z = 1 } }
    end
    local aboveCore = SC.BaseWork._guardPostForTests(guard)
    SC.Commands.peek = function(actor)
        if actor ~= guard then return nil end
        return { order = "base_duty", anchor = { x = 0, y = 0, z = -1 } }
    end
    local belowCore = SC.BaseWork._guardPostForTests(guard)
    SC.Commands.peek = function(actor)
        if actor ~= guard then return nil end
        return { order = "base_duty", anchor = { x = 0, y = 0, z = 0 } }
    end
    local exactCore = SC.BaseWork._guardPostForTests(guard)
    SC.BaseLife.isInside = originalInside
    SC.Commands.peek = function(actor)
        if actor ~= guard then return nil end
        return { order = "base_duty", anchor = { x = 3, y = -2, z = 0 } }
    end
    local queued, chore = SC.BaseLife.enqueueJob({ type = "sort", priority = 2 })
    local priorRequest = SC.Navigation.request
    local patrolTarget
    SC.Navigation.request = function(_, square)
        patrolTarget = square
        return true, "patrol_started"
    end
    SC_TEST_CLOCK = SC_TEST_CLOCK + 50
    local _, reason = SC.BaseWork.update(guard, nil, {})
    local claimed = SC.BaseLife.jobFor(guardId)
    SC.Navigation.request = priorRequest
    SC.Commands = priorCommands
    local px, py = patrolTarget and patrolTarget.x, patrolTarget and patrolTarget.y
    check(post ~= nil and post.x == 3 and post.y == -2
            and aboveCore ~= nil and aboveCore.z == 1
            and belowCore ~= nil and belowCore.z == -1 and exactCore == nil
            and queued == true and chore ~= nil and chore.state == "pending" and claimed == nil
            and px ~= nil and math.abs(px - 3) <= 2 and math.abs(py + 2) <= 2,
        "a guard on shift patrols its own post and leaves generic chores to others: "
            .. tostring(reason))
end

-- LF-31: an expired active job is reclaimed only after the former worker is
-- proven idle. The old active state must not strand an otherwise valid chore.
do
    local ctx = setup("logs", 1, 2)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local queued, job = SC.BaseLife.enqueueJob({ type = "maintain", priority = 2 })
    local firstId = ctx.actors[1].modData.SC_Id
    local secondId = ctx.actors[2].modData.SC_Id
    job.state, job.reservedBy, job.leaseUntil = "active", firstId, SC_TEST_CLOCK - 1
    local claimed = SC.BaseLife.claimJob(secondId)
    check(queued == true and claimed == job and job.reservedBy == secondId
            and job.state == "reserved",
        "a safely idle expired active owner releases the job to another worker")

    job.state, job.reservedBy, job.leaseUntil = "active", firstId, SC_TEST_CLOCK - 1
    local originalActive = SC.NativeActions.isWorkActive
    SC.NativeActions.isWorkActive = function(actor)
        return actor == ctx.actors[1] or (originalActive and originalActive(actor) == true)
    end
    claimed = SC.BaseLife.claimJob(secondId)
    SC.NativeActions.isWorkActive = originalActive
    check(claimed == nil and job.state == "active" and job.reservedBy == firstId
            and job.blocker == "expired_job_native_active",
        "an expired job with live native work remains owned for recovery")

    local originalPeek = SC.Navigation.peek
    SC.Navigation.peek = function(actor)
        return actor == ctx.actors[1] and { goalSquare = ctx.source } or nil
    end
    job.blocker = nil
    claimed = SC.BaseLife.claimJob(secondId)
    SC.Navigation.peek = originalPeek
    check(claimed == nil and job.state == "active" and job.reservedBy == firstId
            and job.blocker == "expired_job_navigation_active",
        "an expired job still approaching its target is not assigned twice")
end

-- LF-32: a real false guard-status result means off shift. Lua's `or`
-- fallback must not turn the resident's guard role back into an active shift.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local guard, guardId = ctx.actor, ctx.actor.modData.SC_Id
    SC.BaseLife.assign(guardId, "guard", true)
    local queued, job = SC.BaseLife.enqueueJob({ type = "maintain", priority = 2 })
    local originalGuardStatus = SC.BaseLife.guardStatus
    local originalDowntime = SC.Downtime
    SC.BaseLife.guardStatus = function() return false, "off_shift" end
    SC.Downtime = { update = function() return true, "fixture_cleaning" end }
    SC_TEST_CLOCK = SC_TEST_CLOCK + 50
    local handled, reason = SC.BaseWork.update(guard, nil, {})
    SC.BaseLife.guardStatus, SC.Downtime = originalGuardStatus, originalDowntime
    check(queued == true and handled == true and reason == "fixture_cleaning"
            and job.state == "active" and job.reservedBy == guardId,
        "an off-shift guard claims ordinary camp work")
end

-- LF-37: cargo produced for an unfinished production order cannot be consumed
-- as an unrelated construction requirement.
do
    local ctx = setup("logs", 1)
    local originalLive = SC.BaseLife.productionOrderLive
    SC.BaseLife.productionOrderLive = function(id)
        return id == "production:foreign"
    end
    local plank = makeItem("Base.Plank", {
        modData = { LF_ProductionOrderId = "production:foreign" },
    })
    ctx.actor.inventory:AddItem(plank)
    check(SC.PersonalItems.isProtected(plank, ctx.actor, "base_build") == true
            and SC.BaseWork._carriedSuppliesForTests(ctx.actor, "Base.Plank") == 0,
        "production-marked output is invisible to unrelated construction")
    SC.BaseLife.productionOrderLive = function() return false end
    check(SC.PersonalItems.isProtected(plank, ctx.actor, "base_build") == false
            and plank.modData.LF_ProductionOrderId == nil,
        "terminal production cargo marker releases ordinary supplies")
    SC.BaseLife.productionOrderLive = originalLive
end

-- Productive fields share the bounded maintenance rotation instead of
-- suppressing every other audit family on every pulse.
do
    setup("logs", 1)
    local priorFarm = SC.FarmWork
    local farmCalls = 0
    SC.FarmWork = {
        audit = function()
            farmCalls = farmCalls + 1
            return true, "farm_always_productive"
        end,
        reset = function() return true end,
    }
    SC.BaseWork.reset()
    local nonFarmResults = 0
    for _ = 1, 10 do
        local _, auditReason = SC.BaseWork.auditMaintenance(nil)
        if auditReason ~= "farm_always_productive" then nonFarmResults = nonFarmResults + 1 end
    end
    SC.FarmWork = priorFarm
    check(farmCalls == 1 and nonFarmResults == 9,
        "productive farming receives one fair slot while other maintenance families run")
end

-- Camp chores reserve one exact item by job id. The reservation counts in
-- every camp system only while its open job still names that item, and a
-- worker who died mid-chore never leaves its job or the camp uncancellable.
do
    local ctx = setup("logs", 1)
    local pump = makeItem("Base.TirePump")
    ctx.storageObject.container:AddItem(pump)
    local queued, upkeep = SC.BaseLife.enqueueJob({ type = "inflate_tires", priority = 2,
        target = { vehicleId = 7, x = 0, y = 0, z = 0,
            sourceStorageId = ctx.storage.id, itemId = pump.nativeId } })
    check(queued == true and upkeep ~= nil, "an upkeep chore queues")
    pump.modData.LF_UpkeepJobId = upkeep.id
    check(SC.WorkTransport.foreignProtected(pump, ctx.actor) == true
            and SC.BaseWork.choreReserved(pump) == true,
        "a live upkeep reservation protects its exact pump from other camp work")
    upkeep.target.itemId = nil
    check(not SC.WorkTransport.foreignProtected(pump, ctx.actor)
            and not SC.BaseWork.choreReserved(pump),
        "a marker whose job no longer names the item reserves nothing")
    local can = makeItem("Base.PetrolCan")
    can.modData.LF_RefuelJobId = "job:999"
    check(not SC.WorkTransport.foreignProtected(can, ctx.actor)
            and not SC.BaseWork.choreReserved(can),
        "a refuel marker left by a finished job no longer hides the can")

    -- The worker carrying a can for a refuel job dies and leaves the registry.
    -- Until the save restore commits, and while a saved companion waits to be
    -- respawned, an unregistered worker is not yet known to be gone.
    local dead = "sc-work-dead-" .. tostring(contextSerial)
    local priorStatus, priorPending = SC.Persistence.restoreStatus, SC.Persistence.isPending
    local restoring, waiting = false, nil
    SC.Persistence.restoreStatus = function() return not restoring end
    SC.Persistence.isPending = function(id) return id == waiting end
    local refuelQueued, refuel = SC.BaseLife.enqueueJob({ type = "refuel_vehicle",
        priority = 2, assignedId = dead,
        target = { vehicleId = 8, x = 0, y = 0, z = 0, stage = "carrying",
            sourceStorageId = ctx.storage.id, itemId = can.nativeId } })
    check(refuelQueued == true and refuel.assignedId == dead,
        "a refuel receipt names its carrying worker")
    can.modData.LF_RefuelJobId = refuel.id
    refuel.state, refuel.reservedBy, refuel.leaseUntil = "active", dead, 0
    restoring = true
    check(SC.BaseWork.reconcileExpiredJob(refuel, dead) == false
            and refuel.target.stage == "carrying",
        "a worker is not presumed dead while the save is still restoring")
    restoring, waiting = false, dead
    check(SC.BaseWork.reconcileExpiredJob(refuel, dead) == false
            and refuel.target.stage == "carrying",
        "a saved companion waiting to be respawned keeps its receipt")
    waiting = nil
    local settled, settledReason = SC.BaseWork.reconcileExpiredJob(refuel, dead)
    check(settled == true and refuel.target.stage == nil and refuel.assignedId == nil,
        "an expired receipt whose worker died is released for another worker: "
            .. tostring(settledReason))
    refuel.state, refuel.reservedBy = "active", dead
    refuel.target.stage, refuel.assignedId = "carrying", dead
    refuel.target.sourceStorageId, refuel.target.itemId = ctx.storage.id, can.nativeId
    ctx.storageObject.container:AddItem(can)
    check(SC.BaseLife.cancelJob(refuel.id) == true and can.modData.LF_RefuelJobId == nil,
        "the player can cancel a dead worker's refuel job, and its stored can is unmarked")

    -- A dormant worker keeps its record and may still bring the can back.
    local sleeper = ctx.actor.modData.SC_Id
    local record = SC.Registry.byId(sleeper)
    local _, kept = SC.BaseLife.enqueueJob({ type = "refuel_vehicle", priority = 2,
        assignedId = sleeper,
        target = { vehicleId = 9, x = 0, y = 0, z = 0, stage = "carrying",
            sourceStorageId = ctx.storage.id, itemId = can.nativeId } })
    kept.state, kept.reservedBy, kept.leaseUntil = "active", sleeper, 0
    local liveActor = record.actor
    record.actor = nil
    check(SC.BaseWork.reconcileExpiredJob(kept, sleeper) == false
            and kept.target.stage == "carrying" and kept.assignedId == sleeper,
        "an unloaded worker keeps its receipt until it can settle it")
    record.actor = liveActor

    local _, sorting = SC.BaseLife.enqueueJob({ type = "sort", priority = 2 })
    sorting.state, sorting.reservedBy, sorting.leaseUntil = "active", dead, 0
    check(SC.BaseWork.reconcileExpiredJob(sorting, dead) == true,
        "an expired ordinary job of a dead worker is released instead of held forever")
    SC.Persistence.restoreStatus, SC.Persistence.isPending = priorStatus, priorPending
end

-- The marked yard must preserve four exact logs through bundling and
-- unbundling. With no rope, the four loose logs remain usable in place.
do
    local ctx = setup("logs", 1)
    local id = ctx.actor.modData.SC_Id
    ctx.base.jobs = {}
    check(SC.BaseLife.assign(id, "guard", true) == true,
        "idle guard joins watch")
    local oldGuardStatus = SC.BaseLife.guardStatus
    local oldNightRestricted = SC.BaseLife.outdoorNightRestricted
    local oldBundle = SC.LogYard.updateBundle
    local bundleCalls = 0
    SC.BaseLife.guardStatus = function() return true end
    SC.BaseLife.outdoorNightRestricted = function() return false end
    SC.LogYard.updateBundle = function()
        bundleCalls = bundleCalls + 1
        return true, "log_yard_bundled"
    end
    SC.BaseWork.update(ctx.actor, nil, {})
    check(bundleCalls == 0, "idle on-shift guard does not leave watch to bundle")
    check(SC.BaseLife.assign(id, "generalist", true) == true,
        "idle worker leaves guard role")
    SC.BaseLife.guardStatus = function() return false end
    SC.BaseWork.update(ctx.actor, nil, {})
    check(bundleCalls == 1, "idle non-guard can bundle yard logs")
    SC.BaseLife.guardStatus = oldGuardStatus
    SC.BaseLife.outdoorNightRestricted = oldNightRestricted
    SC.LogYard.updateBundle = oldBundle
end

-- The marked yard must preserve four exact logs through bundling and
-- unbundling. With no rope, the four loose logs remain usable in place.
do
    local ctx = setup("logs", 1)
    local id = ctx.actor.modData.SC_Id
    local _, job = SC.BaseLife.enqueueJob({ type = "unload_vehicle", priority = 2 })
    local priorGetPlayer = getPlayer
    local speech = 0
    local player = makeActor("fixture-player", ctx.actor.square)
    getPlayer = function() return player end
    function ctx.actor:addLineChatElement(line)
        speech = speech + 1
        self.lastSpeech = line
    end
    function ctx.actor:Say() error("companion speech must not use IsoPlayer:Say") end
    job.state, job.reservedBy = "active", id
    check(SC.BaseLife.blockJob(job.id, id, "car_unload_storage_full_or_missing") == true
            and speech == 1 and job.fullAlertSpoken == true
            and ctx.actor.lastSpeech ~= nil,
        "first full-storage interval anchors speech to companion")
    job.state, job.reservedBy = "active", id
    check(SC.BaseLife.blockJob(job.id, id, "car_unload_storage_full_or_missing") == true
            and speech == 1,
        "repeated full-storage retry does not repeat speech")
    job.state, job.reservedBy = "active", id
    check(SC.BaseLife.noteJobStorageProgress(job.id, id) == true
            and job.fullAlertSpoken == false,
        "verified item storage rearms the full-storage warning")
    check(SC.BaseLife.blockJob(job.id, id, "car_unload_storage_full_or_missing") == true
            and speech == 2,
        "a later full-storage interval speaks again")
    ctx.actor.__class = "IsoPlayer"
    ctx.actor.addLineChatElement = nil
    check(SC.GameplayUtil.say(ctx.actor, "fixture warning") == false,
        "non-local IsoPlayer speech does not fall back to player-anchored Say")
    getPlayer = priorGetPlayer
end

-- The marked yard must preserve four exact logs through bundling and
-- unbundling. With no rope, the four loose logs remain usable in place.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "outdoor log yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Test log yard")
    check(marked == true and zone.kind == "log_yard", "outdoor log yard registers")
    for _ = 1, 4 do putOnGround(yardSquare, makeItem("Base.Log")) end
    check(SC.LogYard.contents(yardSquare).units == 4
            and SC.LogYard.select(ctx.actor) == nil,
        "four loose logs fill exactly one yard tile")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    check(select(2, SC.LogYard.bundleAt(ctx.actor, yardSquare))
            == "log_yard_rope_missing"
            and SC.LogYard.contents(yardSquare).units == 4,
        "missing rope leaves all four loose logs untouched")
    local ropeObject = makeStorage(addSquare(3, 0, 0))
    local ropeOk = SC.BaseLife.registerStorage(ropeObject, "crafting")
    check(ropeOk == true, "rope storage registers")
    ropeObject.container:AddItem(makeItem("Base.Rope"))
    ropeObject.container:AddItem(makeItem("Base.Rope"))
    local claimed = SC.LogYard.contents(yardSquare).logs[1].item
    claimed.modData[SC.WorkTransport.MARKERS.id] = "work-receipt-test"
    check(select(2, SC.LogYard.bundleAt(ctx.actor, yardSquare))
            == "log_yard_bundle_not_ready"
            and SC.LogYard.contents(yardSquare).units == 4,
        "a pending work receipt prevents the yard from consuming its log")
    claimed.modData[SC.WorkTransport.MARKERS.id] = nil
    local bundled, bundleReason = SC.LogYard.bundleAt(ctx.actor, yardSquare)
    local afterBundle = SC.LogYard.contents(yardSquare)
    check(bundled == true and bundleReason == "log_yard_bundled"
            and afterBundle.units == 4 and #afterBundle.bundles == 1
            and #afterBundle.logs == 0 and #ropeObject.container.items == 0
            and afterBundle.bundles[1].item.modData.ropeItems[0] == "Base.Rope"
            and afterBundle.bundles[1].item.modData.ropeItems[1] == "Base.Rope",
        "two ropes and four logs become one vanilla tied bundle")
    local taken, takeReason, log = SC.LogYard.takeOne(ctx.actor,
        { x = 2, y = 1, z = 0, zoneId = zone.id })
    local afterTake = SC.LogYard.contents(yardSquare)
    local returnedRopes = 0
    for _, item in ipairs(ctx.actor.inventory.items) do
        if item.fullType == "Base.Rope" then returnedRopes = returnedRopes + 1 end
    end
    check(taken == true and takeReason == "log_yard_log_taken"
            and ctx.actor.inventory:contains(log)
            and afterTake.units == 3 and #afterTake.logs == 3
            and returnedRopes == 2,
        "building opens one bundle, leaves three logs and returns both ropes")
end

-- A refused bundle drop must restore the exact original items regardless of
-- whether its ropes came from the worker, storage, or both.
for carried = 0, 2 do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "failed-bundle yard begins")
    check(SC.BaseLife.finishZone(yardSquare, "Drop-fault yard") == true,
        "failed-bundle yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    local logs, ropes = {}, {}
    for index = 1, 4 do
        logs[index] = makeItem("Base.Log")
        putOnGround(yardSquare, logs[index])
    end
    local ropeObject = makeStorage(addSquare(3, 0, 0))
    check(SC.BaseLife.registerStorage(ropeObject, "crafting") == true,
        "failed-bundle rope storage registers")
    for index = 1, 2 do
        ropes[index] = makeItem("Base.Rope")
        local home = index <= carried and ctx.actor.inventory or ropeObject.container
        home:AddItem(ropes[index])
    end
    local originalDrop = yardSquare.AddWorldInventoryItem
    yardSquare.AddWorldInventoryItem = function(self, item)
        if item.fullType == "Base.LogStacks4" then return nil end
        return originalDrop(self, item)
    end
    local bundled, reason = SC.LogYard.bundleAt(ctx.actor, yardSquare)
    yardSquare.AddWorldInventoryItem = originalDrop
    local contents = SC.LogYard.contents(yardSquare)
    check(bundled == false and reason == "log_yard_bundle_drop_failed"
            and #contents.logs == 4 and #contents.bundles == 0,
        "failed bundle drop leaves four exact ground logs: carried=" .. carried)
    for _, log in ipairs(logs) do
        check(log.worldItem and SC.GameplayUtil.worldItemPresent(yardSquare,
                log.worldItem) == true,
            "failed bundle drop restores exact log identity")
    end
    for index, rope in ipairs(ropes) do
        local home = index <= carried and ctx.actor.inventory or ropeObject.container
        check(home:contains(rope), "failed bundle drop restores exact rope owner")
    end
    check(SC.LogYard.bundleAt(ctx.actor, yardSquare) == true,
        "bundle retries successfully after drop fault")
end

-- Yard withdrawal must refuse a log before moving its exact world item when
-- Rope selection rotates through late container entries, recognizes the
-- construction category, and combines a carried rope with stored stock.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "late-rope yard begins")
    local marked = SC.BaseLife.finishZone(yardSquare, "Late-rope yard")
    check(marked == true, "late-rope yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    for _ = 1, 4 do putOnGround(yardSquare, makeItem("Base.Log")) end
    local ropeObject = makeStorage(addSquare(3, 0, 0))
    check(SC.BaseLife.registerStorage(ropeObject, "construction") == true,
        "construction storage registers for rope")
    for _ = 1, 120 do ropeObject.container:AddItem(makeItem("Base.Nails")) end
    ropeObject.container:AddItem(makeItem("Base.Rope"))
    ctx.actor.inventory:AddItem(makeItem("Base.Rope"))
    local bundled = false
    for _ = 1, 3 do
        bundled = SC.LogYard.bundleAt(ctx.actor, yardSquare)
        if bundled == true then break end
    end
    check(bundled == true and SC.LogYard.contents(yardSquare).units == 4
            and #SC.LogYard.contents(yardSquare).bundles == 1,
        "one carried and one late construction rope make the tied bundle")
end

-- Yard withdrawal must refuse a log before moving its exact world item when
-- the builder would cross the saw action's 85% load limit.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "overload yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Overload yard")
    check(marked == true, "overload yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    ctx.actor.inventory.capacity = 20
    for _ = 1, 3 do ctx.actor.inventory:AddItem(makeItem("Base.Nails")) end
    local log = makeItem("Base.Log")
    local wrapper = putOnGround(yardSquare, log)
    local taken, reason = SC.LogYard.takeOne(ctx.actor,
        { x = 2, y = 1, z = 0, zoneId = zone.id })
    check(taken == false and reason == "worker_overloaded"
            and log.worldItem == wrapper and not ctx.actor.inventory:contains(log)
            and SC.LogYard.contents(yardSquare).units == 1,
        "overloaded worker leaves exact loose log on its tile")
    ctx.actor.inventory.capacity = 30
    taken = SC.LogYard.takeOne(ctx.actor,
        { x = 2, y = 1, z = 0, zoneId = zone.id })
    check(taken == true and ctx.actor.inventory:contains(log),
        "worker with enough room takes the same loose log")
end

-- A rejected remainder drop must not consume the original tied stack or
-- The same preflight applies before a tied stack is ever opened.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "bundle overload yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Bundle overload yard")
    check(marked == true, "bundle overload yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    ctx.actor.inventory.capacity = 20
    for _ = 1, 3 do ctx.actor.inventory:AddItem(makeItem("Base.Nails")) end
    local bundle = makeItem("Base.LogStacks4", {
        modData = { ropeItems = { [0] = "Base.Rope", [1] = "Base.Rope" } },
    })
    local wrapper = putOnGround(yardSquare, bundle)
    local taken, reason = SC.LogYard.takeOne(ctx.actor,
        { x = 2, y = 1, z = 0, zoneId = zone.id })
    check(taken == false and reason == "worker_overloaded"
            and bundle.worldItem == wrapper
            and bundle.modData.LF_LogYardSplit == nil
            and SC.LogYard.contents(yardSquare).units == 4,
        "overloaded worker leaves tied stack and rope metadata untouched")
end

-- A rejected remainder drop must not consume the original tied stack or
-- leave provisional split outputs in the world or worker inventory.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "split failure yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Split failure yard")
    check(marked == true, "split failure yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    local bundle = makeItem("Base.LogStacks4", {
        modData = { ropeItems = { [0] = "Base.Rope", [1] = "Base.Rope" } },
    })
    local wrapper = putOnGround(yardSquare, bundle)
    local originalDrop = yardSquare.AddWorldInventoryItem
    local logDrops = 0
    yardSquare.AddWorldInventoryItem = function(self, item)
        if item.fullType == "Base.Log" then
            logDrops = logDrops + 1
            if logDrops == 2 then return nil end
        end
        return originalDrop(self, item)
    end
    local taken, reason = SC.LogYard.takeOne(ctx.actor,
        { x = 2, y = 1, z = 0, zoneId = zone.id })
    yardSquare.AddWorldInventoryItem = originalDrop
    local contents = SC.LogYard.contents(yardSquare)
    local carriedLogs, carriedRopes = 0, 0
    for _, item in ipairs(ctx.actor.inventory.items) do
        if item.fullType == "Base.Log" then carriedLogs = carriedLogs + 1 end
        if item.fullType == "Base.Rope" then carriedRopes = carriedRopes + 1 end
    end
    check(taken == false and reason == "log_yard_unbundle_drop_failed"
            and bundle.worldItem == wrapper and contents.units == 4
            and #contents.bundles == 1 and #contents.logs == 0
            and carriedLogs == 0 and carriedRopes == 0,
        "failed split rolls back to the exact original bundle")
end

-- A gather receipt can be retargeted from its original container to the yard
-- Every supported vanilla stack size must be retrievable, with exact rope
-- restitution and without treating a counted yard tile as unusable stock.
for _, size in ipairs({ 2, 3 }) do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "small-stack yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Small-stack yard")
    check(marked == true, "small-stack yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    local bundle = makeItem("Base.LogStacks" .. size, {
        modData = { ropeItems = { [0] = "Base.Rope", [1] = "Base.Rope" } },
    })
    putOnGround(yardSquare, bundle)
    local destination = SC.LogYard.source(ctx.actor, zone.id)
    check(destination ~= nil and SC.LogYard.contents(yardSquare).units == size,
        "small tied stack is counted and selected")
    local taken, reason, log = SC.LogYard.takeOne(ctx.actor, destination)
    local ropes = 0
    for _, item in ipairs(ctx.actor.inventory.items) do
        if item.fullType == "Base.Rope" then ropes = ropes + 1 end
    end
    check(taken == true and reason == "log_yard_log_taken"
            and ctx.actor.inventory:contains(log)
            and SC.LogYard.contents(yardSquare).units == size - 1
            and ropes == 2,
        "small tied stack splits into one carried and remaining ground logs")
end

-- Failed output creation and failed source consumption leave the original
-- identity in place; a world-removal failure may require one recovery pulse.
for _, failure in ipairs({ "create", "consume", "world" }) do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "fault yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Fault yard")
    check(marked == true, "fault yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    local bundle = makeItem("Base.LogStacks4", {
        modData = { ropeItems = { [0] = "Base.Rope", [1] = "Base.Rope" } },
    })
    local wrapper = putOnGround(yardSquare, bundle)
    if failure == "create" then
        ctx.actor.inventory.rejectAddAt = (ctx.actor.inventory.addCalls or 0) + 2
    elseif failure == "consume" then
        ctx.actor.inventory.rejectRemoveTypeOnce = "Base.LogStacks4"
    else
        yardSquare.rejectRemove = true
    end
    local destination = { x = 2, y = 1, z = 0, zoneId = zone.id }
    local taken, reason = SC.LogYard.takeOne(ctx.actor, destination)
    check(taken == false, "injected split fault is reported")
    if reason == "log_yard_split_recovery_pending" then
        check(SC.LogYard.select(ctx.actor) == nil
                and SC.LogYard.contents(yardSquare).splitPending == true,
            "a split awaiting recovery reserves its yard tile")
    end
    yardSquare.rejectRemove = false
    if reason == "log_yard_split_recovery_pending" then
        SC.LogYard.takeOne(ctx.actor, destination)
    end
    local contents = SC.LogYard.contents(yardSquare)
    check(bundle.worldItem ~= nil
            and SC.GameplayUtil.worldItemPresent(yardSquare, bundle.worldItem) == true
            and contents.units == 4
            and #contents.bundles == 1 and #contents.logs == 0,
        "injected split fault recovers the exact original bundle: " .. failure
            .. "/" .. tostring(reason) .. "/" .. tostring(contents.units)
            .. "/" .. tostring(#contents.bundles) .. "/" .. tostring(#contents.logs)
            .. "/" .. tostring(bundle.worldItem == wrapper))
end

-- A gather receipt can be retargeted from its original container to the yard
-- and still account for exactly one delivered world item after save/load.
do
    local ctx = setup("logs", 1)
    local first, second = addSquare(2, 1, 0), addSquare(3, 1, 0)
    function first:isOutside() return true end
    function second:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", first) == true,
        "split-locked yard begins")
    local marked, zone = SC.BaseLife.finishZone(second, "Two-tile yard")
    check(marked == true, "split-locked yard registers")
    local log = makeItem("Base.Log")
    putOnGround(ctx.source, log)
    local receipt = reserveCandidate(ctx, ctx.actor, log)
    check(receipt.destinationPoint.x == first.x,
        "receipt initially chooses nearest yard tile")
    local function lock(square, suffix)
        local pending = makeItem("Base.Log", { modData = {
            LF_LogYardSplit = { v = 1, id = "pending-" .. suffix,
                role = "log", index = 1, ownerId = "missing",
                zoneId = zone.id, x = square.x, y = square.y, z = square.z,
                count = 2, ropeCount = 0 },
        } })
        putOnGround(square, pending)
        return pending
    end
    lock(first, "first")
    local destination, _, reason = SC.WorkTransport.destinationFor(
        ctx.order, receipt, ctx.actor, log)
    check(destination and destination.x == second.x
            and receipt.destinationPoint.x == second.x,
        "receipt retargets away from a split-locked tile: " .. tostring(reason))
    check(SC.WorkTransport.collect(receipt, ctx.actor, log, log.worldItem) == true,
        "retargeted log is collected")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = second, 3.5, 1.5
    check(SC.WorkTransport.deposit(receipt, ctx.actor, log) == true
            and SC.LogYard.contents(second).units == 1,
        "retargeted log reaches the open yard tile")
    lock(second, "second")
    ctx.storage.deposits = false
    destination, _, reason = SC.WorkTransport.destinationFor(ctx.order,
        receipt, ctx.actor, makeItem("Base.Log"))
    check(destination == nil and reason == "log_yard_split_pending",
        "all split-locked yard tiles report recovery rather than full capacity")
end

-- Missing-owner split receipts are discovered on the ground. A second worker
-- reconciles only when every output identity is present; otherwise the tile
-- stays protected and reports the orphan explicitly.
local priorSplitRestoreStatus = SC.Persistence.restoreStatus
SC.Persistence.restoreStatus = function() return true end
for _, sourcePresent in ipairs({ true, false }) do
    local ctx = setup("logs", 1)
    local square = addSquare(2, 1, 0)
    function square:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", square) == true,
        "orphan yard begins")
    local marked, zone = SC.BaseLife.finishZone(square, "Orphan yard")
    check(marked == true, "orphan yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = square, 2.5, 1.5
    local receipt = { v = 1, id = "orphan-" .. tostring(contextSerial),
        ownerId = "retired-worker", zoneId = zone.id,
        x = square.x, y = square.y, z = square.z, count = 2, ropeCount = 0 }
    local source
    if sourcePresent then
        source = makeItem("Base.LogStacks2", { modData = {
            LF_LogYardSplit = { v = 1, id = receipt.id, role = "source",
                index = 0, ownerId = receipt.ownerId, zoneId = zone.id,
                x = square.x, y = square.y, z = square.z,
                count = 2, ropeCount = 0 },
        } })
        putOnGround(square, source)
    end
    local outputs = {}
    for index = 1, 2 do
        outputs[index] = makeItem("Base.Log", { modData = {
            LF_LogYardSplit = { v = 1, id = receipt.id, role = "log",
                index = index, ownerId = receipt.ownerId, zoneId = zone.id,
                x = square.x, y = square.y, z = square.z,
                count = 2, ropeCount = 0 },
        } })
        putOnGround(square, outputs[index])
    end
    local destination = SC.LogYard.source(ctx.actor, zone.id)
    check(destination ~= nil, "orphaned marked outputs remain discoverable")
    local recovered, reason = SC.LogYard.takeOne(ctx.actor, destination)
    if sourcePresent then
        check(recovered == false and reason == "log_yard_split_rolled_back"
                and source.modData.LF_LogYardSplit == nil
                and SC.LogYard.contents(square).units == 2,
            "complete orphan with source restores original stack: "
                .. tostring(reason) .. "/"
                .. tostring(source.modData.LF_LogYardSplit == nil) .. "/"
                .. tostring(SC.LogYard.contents(square).units))
    else
        check(recovered == true and reason == "log_yard_log_taken"
                and ctx.actor.inventory:contains(outputs[1])
                and outputs[1].modData.LF_LogYardSplit == nil
                and outputs[2].modData.LF_LogYardSplit == nil,
            "complete orphan without source commits exact outputs")
    end
end

do
    local ctx = setup("logs", 1)
    local square = addSquare(2, 1, 0)
    function square:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", square) == true,
        "incomplete-orphan yard begins")
    local marked, zone = SC.BaseLife.finishZone(square, "Incomplete orphan")
    check(marked == true, "incomplete-orphan yard registers")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = square, 2.5, 1.5
    local partial = makeItem("Base.Log", { modData = {
        LF_LogYardSplit = { v = 1, id = "incomplete-orphan", role = "log",
            index = 2, ownerId = "retired-worker", zoneId = zone.id,
            x = square.x, y = square.y, z = square.z,
            count = 2, ropeCount = 0 },
    } })
    putOnGround(square, partial)
    local destination = SC.LogYard.source(ctx.actor, zone.id)
    local recovered, reason = SC.LogYard.takeOne(ctx.actor, destination)
    check(recovered == false and reason == "log_yard_split_orphaned"
            and partial.modData.LF_LogYardSplit ~= nil
            and SC.LogYard.contents(square).splitPending == true,
        "incomplete orphan stays protected and reports its blocker")
end
SC.Persistence.restoreStatus = priorSplitRestoreStatus

-- A gather receipt can be retargeted from its original container to the yard
-- and still account for exactly one delivered world item after save/load.
do
    local ctx = setup("logs", 1)
    local yardSquare = addSquare(2, 1, 0)
    function yardSquare:isOutside() return true end
    check(SC.BaseLife.beginZone("log_yard", yardSquare) == true,
        "gather yard begins")
    local marked, zone = SC.BaseLife.finishZone(yardSquare, "Gather yard")
    check(marked == true, "gather yard registers")
    local log = makeItem("Base.Log")
    putOnGround(ctx.source, log)
    local receipt = reserveCandidate(ctx, ctx.actor, log)
    check(receipt.destinationZoneId == zone.id
            and receipt.destinationStorageId == nil,
        "gather reservation chooses marked yard before construction storage")
    check(SC.WorkTransport.collect(receipt, ctx.actor, log, log.worldItem) == true,
        "reserved yard log is collected")
    ctx.actor.square, ctx.actor.x, ctx.actor.y = yardSquare, 2.5, 1.5
    check(SC.WorkTransport.deposit(receipt, ctx.actor, log) == true
            and receipt.phase == "delivered"
            and SC.LogYard.contents(yardSquare).units == 1,
        "one exact log reaches the yard and is accounted for")
    local saved = SC.BaseLife.export()
    SC.WorkTransport.reset()
    check(SC.BaseLife.restore(saved) == true
            and SC.BaseLife.workReceipt(receipt.id).phase == "delivered"
            and SC.LogYard.contents(yardSquare).units == 1,
        "yard delivery and its exact world item survive save/load")
end

-- Loose valuables use the dedicated marker when present, including another
-- marker of the same category after the first fills.
do
    local ctx = setup("logs", 1)
    local ring = makeItem("Base.Ring_Gold", { category = "Clothing" })
    check(SC.BaseLife.isValuableItem(ring) == true,
        "vanilla loose jewelry is recognized")
    check(SC.BaseLife.isValuableItem(makeItem("Base.NecklaceLong_Gold")) == true,
        "long necklaces use the same valuables storage")
    local firstObject = makeStorage(addSquare(2, 0, 0))
    local secondObject = makeStorage(addSquare(3, 0, 0))
    local firstOk, first = SC.BaseLife.registerStorage(firstObject, "valuables")
    local secondOk, second = SC.BaseLife.registerStorage(secondObject, "valuables")
    check(firstOk == true and secondOk == true, "two valuables markers register")
    firstObject.container.room = false
    check(select(1, SC.BaseWork.destinationForCarItem(ctx.actor, ring)) == second,
        "a full valuables marker falls through to another valuables marker")
    secondObject.container.room = false
    check(select(1, SC.BaseWork.destinationForCarItem(ctx.actor, ring)) == nil,
        "loose jewelry waits when every valuables marker is full")
end

-- A cleaner borrows the exact tool and liquid from marked storage, performs
-- the targeted action, then returns those same objects. Personal inventory
-- must remain separate from the loan receipt.
do
    local ctx = setup("logs", 1)
    SC.BaseLife.cancelGatherOrder(ctx.order.id)
    local target = ctx.actor.square
    target.stained = true
    function target:haveStains() return self.stained end
    local mop = makeItem("Base.Mop")
    function mop:hasTag(tag) return tag == ItemTag.CLEAN_STAINS end
    function mop:isBroken() return false end
    local bleach = makeItem("Base.Bleach")
    local liquid = { amount = 1 }
    function liquid:contains(fluid)
        return fluid == Fluid.Bleach
    end
    function liquid:getAmount() return self.amount end
    function bleach:getFluidContainer() return liquid end
    local priorTag, priorFluid, priorGlobals, priorDowntime =
        ItemTag, Fluid, ZomboidGlobals, SC.Downtime
    ItemTag = { CLEAN_STAINS = "clean_stains" }
    Fluid = { Bleach = "bleach", CleaningLiquid = "cleaning" }
    ZomboidGlobals = { CleanBloodBleachAmount = 0.25 }
    ctx.storageObject.container:AddItem(mop)
    ctx.storageObject.container:AddItem(bleach)
    SC.Downtime = {
        canCleanAt = function(actor, square, suppliesStaged)
            if actor ~= ctx.actor or square ~= target then return false, "wrong_target" end
            if suppliesStaged then return true end
            if actor.inventory:contains(mop) and actor.inventory:contains(bleach) then
                return true
            end
            return false, "cleaning_supplies_missing"
        end,
        peek = function() return nil end,
        update = function(actor, _, _, kind, square)
            check(actor == ctx.actor and kind == "clean_base" and square == target
                and actor.inventory:contains(mop) and actor.inventory:contains(bleach),
                "cleaning begins only after both verified withdrawals")
            target.stained, liquid.amount = false, liquid.amount - 0.25
            return true, "cleaned"
        end,
    }
    local accepted, job = SC.BaseLife.requestCleaning(target)
    check(accepted == true and job.type == "clean",
        "stored supplies make a stained camp tile actionable: " .. tostring(job)
            .. " stock=" .. tostring(SC.BaseWork.cleaningSuppliesAvailable(ctx.actor))
            .. " duty=" .. tostring(#SC.BaseLife.dutyResidentIds())
            .. " recruited=" .. tostring((SC.Registry.byId(ctx.actor.modData.SC_Id) or {}).recruited))
    local sawLoan = false
    for _ = 1, 40 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if job.target.cleanLoans then sawLoan = true end
        if not SC.BaseLife.job(job.id) then break end
    end
    check(sawLoan and target.stained == false
        and SC.BaseLife.job(job.id) == nil,
        "cleaning job completes after the stain is removed and loans settle")
    check(ctx.storageObject.container:contains(mop)
        and ctx.storageObject.container:contains(bleach)
        and not ctx.actor.inventory:contains(mop)
        and not ctx.actor.inventory:contains(bleach)
        and liquid.amount == 0.75,
        "the exact mop and partially used bleach return to their marked source")
    check(mop.modData.LF_CleanToolJobId == nil
        and bleach.modData.LF_CleanLiquidJobId == nil,
        "completed cleaning clears both item reservations")
    target.stained, liquid.amount = true, 1
    local secondOk, secondJob = SC.BaseLife.requestCleaning(target)
    check(secondOk == true, "another stain can start after both loans return")
    for _ = 1, 25 do
        SC_TEST_CLOCK = SC_TEST_CLOCK + 100
        SC.BaseWork.update(ctx.actor, nil, {})
        if ctx.actor.inventory:contains(mop)
            and ctx.actor.inventory:contains(bleach) then break end
    end
    check(ctx.actor.inventory:contains(mop)
        and ctx.actor.inventory:contains(bleach)
        and secondJob.target.cleanLoans.tool
        and secondJob.target.cleanLoans.liquid,
        "both borrowed identities are saved before scrubbing begins")
    local saved = SC.BaseLife.export()
    check(SC.BaseLife.restore(saved) == true,
        "a cleaning loan survives base save and restore")
    mop.nativeId, bleach.nativeId = mop.nativeId + 100000,
        bleach.nativeId + 100000
    local restored = SC.BaseLife.job(secondJob.id)
    check(restored and restored.assignedId == ctx.actor.modData.SC_Id,
        "restored cleaning loan keeps its assigned worker")
    local stainAtCancel, amountAtCancel = target.stained, liquid.amount
    local cancelled, cancelReason = SC.BaseLife.cancelJob(secondJob.id)
    check(cancelled == true and SC.BaseLife.job(secondJob.id) == nil,
        "cancelling a restored job settles its loan: " .. tostring(cancelReason))
    check(ctx.storageObject.container:contains(mop)
        and ctx.storageObject.container:contains(bleach)
        and mop.modData.LF_CleanToolJobId == nil
        and bleach.modData.LF_CleanLiquidJobId == nil
        and target.stained == stainAtCancel
        and liquid.amount == amountAtCancel,
        "cancellation returns both exact supplies without changing the stain"
            .. " mop=" .. tostring(ctx.storageObject.container:contains(mop))
            .. " bleach=" .. tostring(ctx.storageObject.container:contains(bleach))
            .. " marks=" .. tostring(mop.modData.LF_CleanToolJobId)
            .. "," .. tostring(bleach.modData.LF_CleanLiquidJobId)
            .. " stain=" .. tostring(target.stained))
    ItemTag, Fluid, ZomboidGlobals, SC.Downtime =
        priorTag, priorFluid, priorGlobals, priorDowntime
end

local gatherMetrics = SC.GatherWork.diagnostics()
local transportMetrics = SC.WorkTransport.diagnostics()
check(type(transportMetrics.pendingReceipts) == "number"
    and type(transportMetrics.oldestWaitingMs) == "number"
    and transportMetrics.oldestWaitingMs >= 0
    and type(transportMetrics.deliveriesPerMinute) == "number"
    and transportMetrics.deliveriesPerMinute >= 0,
    "transport diagnostics must expose bounded backlog age and delivery throughput")
print("WORK_TRANSPORT_PASS checks=" .. tostring(checks)
    .. " scanned=" .. tostring(gatherMetrics.examinedObjects)
    .. " recovery=" .. tostring(transportMetrics.recoveryAttempts))
InventoryItemFactory = originalInventoryItemFactory
