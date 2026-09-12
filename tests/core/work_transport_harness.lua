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
    function inventory:getType() return self.kind end
    function inventory:AddItem(value)
        if self.rejectAdd == true then return nil end
        local item = type(value) == "string" and makeItem(value) or value
        if item == nil or self.room ~= true then return nil end
        if not self:contains(item) then self.items[#self.items + 1] = item end
        item.container, item.worldItem = self, nil
        return item
    end
    function inventory:DoAddItemBlind(item) return self:AddItem(item) end
    function inventory:Remove(item)
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
        condition = options.condition or 100,
    }
    function item:getFullType() return self.fullType end
    function item:getType() return string.match(self.fullType, "[^%.]+$") end
    function item:getDisplayName() return self:getType() end
    function item:getID() return self.nativeId end
    function item:getCondition() return self.condition end
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
local rejectNavigation = false
SC.Navigation = {
    cancel = function()
        navigationCancels = navigationCancels + 1
        return true
    end,
    interactionTargets = function(_, target) return { target } end,
    requestAny = function()
        if rejectNavigation then return false, "fixture_unreachable" end
        return true, "fixture_path_started"
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
    local stock = makeItem("Base.Log")
    local hammer = makeItem("Base.Hammer")
    ctx.storageObject.container:AddItem(stock)
    ctx.actor.inventory:AddItem(hammer)
    local gathered = makeItem("Base.Log")
    putOnGround(ctx.source, gathered)
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
