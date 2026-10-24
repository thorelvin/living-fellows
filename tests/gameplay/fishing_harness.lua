-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local angling = SC.Fishing
local util = SC.GameplayUtil
local topology = SC.Topology
local oldLoaded, oldFree, oldWater = util.loadedSquare,
    util.isSquareFree, topology.squareIsWater
local squares = {}
local function square(x, y, hasWater, blocked)
    local value = { x = x, y = y, z = 0, water = hasWater, blocked = blocked }
    function value:getX() return self.x end
    function value:getY() return self.y end
    function value:getZ() return self.z end
    squares[x .. ":" .. y] = value
    return value
end
util.loadedSquare = function(value)
    return squares[value.x .. ":" .. value.y]
end
util.isSquareFree = function(value) return not value.blocked end
topology.squareIsWater = function(value) return value.water == true end

local bank = square(10, 10, false, false)
square(11, 10, true, false)
local deep = square(12, 10, true, false)
local selected = angling._usableBankForTests(bank)
assert(selected and selected.bank.x == 10 and selected.water.x == 12.5,
    "a dry bank with two loaded water tiles supports a visible cast")
deep.water = false
assert(angling._usableBankForTests(bank) == nil,
    "a shore without cast depth must not be treated as fishable")
deep.water, bank.blocked = true, true
assert(angling._usableBankForTests(bank) == nil,
    "a blocked standing tile must not be chosen")
bank.blocked, bank.water = false, true
assert(angling._usableBankForTests(bank) == nil,
    "the companion must stand on land rather than path into water")

local oldDistanceSq, oldMovingBlocker, oldActive = util.distanceSq,
    util.movingBlocker, SC.BaseLife.active
util.distanceSq = function(actor, point)
    return (actor.x - point.x) ^ 2 + (actor.y - point.y) ^ 2
end
util.movingBlocker = function() return nil end
local scout = { x = 100, y = 100 }
squares = {}
square(124, 124, false, false)
square(125, 124, true, false)
square(126, 124, true, false)
local searchState = {}
local found, reason
repeat
    found, reason = angling._siteForTests(scout, searchState, "expedition",
        { destination = { x = 100, y = 100 }, catchRadius = 27 })
until reason ~= "scanning_water"
assert(found == nil and reason == "no_fishing_water",
    "a cast outside the expedition receipt radius is not selected")
square(116, 100, false, false)
square(117, 100, true, false)
square(118, 100, true, false)
searchState = {}
repeat
    found, reason = angling._siteForTests(scout, searchState, "expedition",
        { destination = { x = 100, y = 100 }, catchRadius = 27 })
until reason ~= "scanning_water"
assert(found and found.bank.x == 116 and found.water.x == 118.5,
    "a cast inside the receipt radius remains eligible")
local oldCell = getCell
getCell = function()
    return { getGridSquare = function(_, x, y)
        return squares[x .. ":" .. y]
    end }
end
local banks, bankReason, bankCount = angling.bankCandidates(scout, 25, 32, 0)
assert(bankReason == nil and bankCount == 1 and #banks == 1
        and banks[1].kind == "fishing_bank" and banks[1].anchor.x == 116,
    "the fishing destination picker offers a loaded shore, not a building")
local selectedBank = angling.bankById(scout, banks[1].id, 25)
assert(selectedBank and selectedBank.id == banks[1].id,
    "departure rechecks the selected water bank")
local outOfRange, outReason = angling.bankById(scout, banks[1].id, 10)
assert(outOfRange == nil and outReason == "fishing_bank_out_of_range",
    "a stale bank outside the leader's range cannot launch a trip")

-- The map knows about a river beyond loaded chunks. The picker may offer it,
-- while the expedition still has to verify the real bank when it arrives.
local oldMiniMap = getPlayerMiniMap
local mapWorld = { bankLocations = "122:100",
    getCell = function() error("Lua must not read Java map feature fields") end }
local oldBridge = SCBridge
local mapWidget = {}
local mapReads = 0
SCBridge = { loadedWorldMap = function(widget)
    assert(widget == mapWidget, "the bridge receives the minimap's Java widget")
    return mapWorld
end,
mappedFishingBanks = function(world)
    assert(world == mapWorld, "the Java map lookup receives the loaded map")
    mapReads = mapReads + 1
    return world.bankLocations
end,
mappedFishingBankPlausible = function(world, x, y)
    return world == mapWorld and string.find(world.bankLocations,
        tostring(x) .. ":" .. tostring(y), 1, true) ~= nil
end }
getPlayerMiniMap = function()
    return { inner = { javaObject = mapWidget } }
end
squares = {}
local remoteBanks, remoteReason, remoteCount =
    angling.bankCandidates(scout, 40, 32, 0)
assert(remoteReason == nil and remoteCount > 0
        and remoteBanks[1].knowledge == "map_water_unconfirmed"
        and mapReads > 0,
    "a mapped river offers a remote shore without loading its game squares")
local remoteSelected = angling.bankById(scout, remoteBanks[1].id, 40)
assert(remoteSelected and remoteSelected.id == remoteBanks[1].id,
    "a mapped remote shore remains selectable at departure")
mapWorld.bankLocations = "100:700"
local longScanReads = 0
local localCell = getCell
getCell = function()
    local inner = localCell()
    return { getGridSquare = function(_, x, y, z)
        longScanReads = longScanReads + 1
        return inner:getGridSquare(x, y, z)
    end }
end
local distantBanks, distantReason, distantCount =
    angling.bankCandidates(scout, 1000, 32, 0)
assert(distantReason == nil and distantCount > 0
        and distantBanks[1].distance > 200 and longScanReads < 200000,
    "a mapped shore within 1,000 appears without scanning millions of game squares")
getCell = localCell
local distantSelected = angling.bankById(scout, distantBanks[1].id, 1000)
assert(distantSelected and distantSelected.id == distantBanks[1].id,
    "a distant mapped shoreline passes the departure range check")
mapWorld.bankLocations = "7502:6050"
local riverside = { x = 7350, y = 6050 }
local riversideBanks, riversideReason, riversideCount =
    angling.bankCandidates(riverside, 200, 32, 0)
assert(riversideReason == nil and riversideCount > 0
        and riversideBanks[1].anchor.x >= 7500,
    "world map cells use 300 tile coordinates at the Riverside shoreline")
-- Paging through the same shoreline list reuses one 200-tile scan; the
-- picker's Refresh asks for a new one.
local squareReads = 0
local listedCell = getCell
getCell = function()
    local inner = listedCell()
    return { getGridSquare = function(_, x, y, z)
        squareReads = squareReads + 1
        return inner:getGridSquare(x, y, z)
    end }
end
local _, _, pagedCount = angling.bankCandidates(riverside, 200, 32, 32)
local pagedReads = squareReads
local _, _, refreshedCount = angling.bankCandidates(riverside, 200, 32, 0, true)
assert(pagedReads == 0 and squareReads > 0
        and pagedCount == riversideCount and refreshedCount == riversideCount,
    "fishing bank pages reuse one scan and Refresh rescans: "
        .. tostring(pagedReads) .. "/" .. tostring(squareReads))
SCBridge = nil
local noBridgeRows, noBridgeReason, noBridgeCount =
    angling.bankCandidates(riverside, 200, 32, 0, true)
assert(noBridgeReason == nil and noBridgeCount == 0
        and #noBridgeRows == 0,
    "Refresh stays safe if the native map accessor is unavailable")
SCBridge = oldBridge
getCell = listedCell
getPlayerMiniMap = oldMiniMap
getCell = oldCell

local oldAudit, oldItemTag, oldItemType, oldFishing =
    SC.Logistics.audit, util.itemHasTag, util.itemType, Fishing
local fishingRod = { data = {} }
function fishingRod:getModData() return self.data end
local bait = { kind = "bait" }
local fisher = { primary = nil, auditItems = {} }
function fisher:getPrimaryHandItem() return self.primary end
function fisher:getInventory() return {} end
SC.Logistics.audit = function(value)
    return { items = value.auditItems }
end
util.itemHasTag = function(value, tag)
    return tag == "FISHING_ROD" and value == fishingRod
end
util.itemType = function(value)
    return value == bait and "Base.Worm" or "Base.FishingRod"
end
Fishing = { lure = { All = { ["Base.Worm"] = true } } }
local ready, missing = angling.checkGear(fisher)
assert(not ready and missing == "fishing_rod_missing",
    "fishing departure rejects a squad member with no rod")
fisher.primary = fishingRod
ready, missing = angling.checkGear(fisher)
assert(not ready and missing == "fishing_bait_missing",
    "fishing departure rejects a rod without bait")
fisher.auditItems = { { item = bait } }
assert(angling.checkGear(fisher) == true,
    "fishing departure accepts a rod and carried bait")
SC.Logistics.audit, util.itemHasTag, util.itemType, Fishing =
    oldAudit, oldItemTag, oldItemType, oldFishing

squares = {}
square(30, 30, false, false)
square(31, 30, true, false)
square(32, 30, true, false)
SC.BaseLife.active = function()
    return { zones = {
        { kind = "fishing", z = 0, x1 = 10, y1 = 10, x2 = 10, y2 = 10 },
        { kind = "fishing", z = 0, x1 = 30, y1 = 30, x2 = 30, y2 = 30 },
    } }
end
searchState = {}
repeat
    found, reason = angling._siteForTests(scout, searchState, "camp")
until reason ~= "scanning_water"
assert(found and found.bank.x == 30,
    "camp fishing searches a usable second zone after a dry first zone")

util.loadedSquare, util.isSquareFree = oldLoaded, oldFree
topology.squareIsWater = oldWater
util.distanceSq, util.movingBlocker, SC.BaseLife.active = oldDistanceSq,
    oldMovingBlocker, oldActive
local oldSay, oldLast, oldRand = SC.Dialogue.say,
    SC.Dialogue.lastSpokenAt, ZombRand
local said = {}
SC.Dialogue.say = function(_, topic)
    said[#said + 1] = topic
    return true
end
SC.Dialogue.lastSpokenAt = function() return -math.huge end
local actor = { stage = nil, finished = false }
function actor:getPerkLevel() return 0 end
function actor:setFishingStage(value) self.stage = value end
function actor:setVariable(key, value)
    if key == "FishingFinished" then self.finished = value end
end
local fishItem = {}
local lostBobber = { fish = { fishItem = fishItem, isTrash = false } }
function lostBobber:destroy() self.destroyed = true end
local rod = {}
function rod:missFish() self.missed = true self.bobber.fish = nil end
local lost = { bobber = lostBobber, rodSim = rod, phase = "waiting" }
ZombRand = function() return 0 end
assert(angling._handleBiteForTests(actor, lost)
        and rod.missed and lostBobber.destroyed and lost.phase == "ready"
        and said[1] == "fishing.lost" and actor.finished,
    "a missed native bite clears the bobber and speaks a loss line")
local caughtBobber = { fish = { fishItem = fishItem, isTrash = false } }
local caught = { bobber = caughtBobber, rodSim = rod, phase = "waiting" }
ZombRand = function() return 99 end
assert(angling._handleBiteForTests(actor, caught)
        and caught.phase == "pickup" and caught.catch == fishItem
        and caughtBobber.catchFishStarted and actor.stage == "PickUp",
    "a held bite enters the pickup animation without losing the fish")
assert(#SC.Dialogue._poolForTests("fishing.lost").common >= 5
        and #SC.Dialogue._poolForTests("fishing.catch").common >= 5,
    "miss and catch reactions have enough varied lines")

local baitAction = { action = {}, character = actor }
function baitAction:forceStop() self.stopped = true end
local foreignAction = {}
local baitQueue = { current = baitAction, queue = { baitAction, foreignAction } }
function baitQueue:indexOf(action)
    for index, queued in ipairs(self.queue) do
        if queued == action then return index end
    end
    return -1
end
function baitQueue:removeFromQueue(action)
    local index = self:indexOf(action)
    if index ~= -1 then table.remove(self.queue, index) end
end
function actor:cancelCompanionPendingAction() self.pendingBaitCancelled = true end
function actor:getPrimaryHandItem() return nil end
angling._setStateForTests(actor, { mode = "camp", phase = "baiting",
    baitAction = baitAction, baitQueue = baitQueue })
assert(angling.cancel(actor, "combat_preempted") and baitAction.stopped
        and actor.pendingBaitCancelled and baitQueue.queue[1] == foreignAction
        and not angling.active(actor),
    "preemption stops only the owned bait action and releases fishing state")

local oldNow = util.nowMs
util.nowMs = function() return 1000 end
local brokenBobber = {}
function brokenBobber:update() error("native bobber failed") end
function brokenBobber:destroy() self.destroyed = true end
angling._setStateForTests(actor, { mode = "camp", phase = "waiting",
    bobber = brokenBobber })
angling.onTick()
local retryAllowed, retryReason = angling.update(actor, "camp")
assert(brokenBobber.destroyed and not angling.active(actor)
        and retryAllowed == false and retryReason == "fishing_engine_cooldown",
    "a native bobber error stops camp fishing rather than recasting every beat")

local oldExpedition, unableReason = SC.ExpeditionPrototype, nil
SC.ExpeditionPrototype = { fishingUnable = function(_, reason)
    unableReason = reason
    return true
end }
local expeditionActor = {}
function expeditionActor:setFishingStage() end
function expeditionActor:setVariable() end
angling._setStateForTests(expeditionActor, { mode = "expedition",
    phase = "waiting", bobber = brokenBobber })
angling.onTick()
assert(unableReason == "fishing_engine_failed"
        and not angling.active(expeditionActor),
    "a native bobber error is reported to the expedition return flow")
SC.ExpeditionPrototype = oldExpedition
util.nowMs = oldNow

local function inventory()
    local result = { items = {} }
    function result:getItems() return self.items end
    function result:contains(item)
        for _, value in ipairs(self.items) do
            if value == item then return true end
        end
        return false
    end
    function result:AddItem(item)
        self.items[#self.items + 1] = item
        item.container = self
        return item
    end
    function result:Remove(item)
        for index, value in ipairs(self.items) do
            if value == item then
                table.remove(self.items, index)
                item.container = nil
                break
            end
        end
    end
    function result:hasRoomFor() return true end
    return result
end
local function item()
    local result = { data = {} }
    function result:getModData() return self.data end
    function result:getContainer() return self.container end
    function result:getFullType() return "Base.Fish" end
    function result:getOffAgeMax() return 5 end
    return result
end
local foodActor = { inventory = inventory(), data = {}, x = 10, y = 10, z = 0 }
function foodActor:getInventory() return self.inventory end
function foodActor:getModData() return self.data end
function foodActor:getX() return self.x end
function foodActor:getY() return self.y end
function foodActor:getZ() return self.z end
function foodActor:getPrimaryHandItem() return self.hand end
function foodActor:setPrimaryHandItem(value) self.hand = value end
function foodActor:setFishingStage(value) self.stage = value end
function foodActor:setVariable() end
local oldInventoryLoad = util.inventoryLoad
local loadRatio = 0.2
util.inventoryLoad = function() return 5, 25, loadRatio end
local caughtState = { mode = "camp", phase = "pickup" }
angling._setStateForTests(foodActor, caughtState)
local fish = {}
for index = 1, 3 do
    fish[index] = item()
    caughtState.catch = fish[index]
    local caught, catchReason = angling._finishCatchForTests(foodActor, caughtState)
    assert(caught and catchReason == "fish_caught"
            and fish[index].data.SC_CampFishingCatch == true,
        "a real camp catch is tracked for later food storage")
end
local unrelated = item()
foodActor.inventory:AddItem(unrelated)
local oldRows, oldResolveContainer, oldResolveObject, oldAccept =
    SC.BaseLife.depositStorageRows, SC.BaseLife.resolveContainer,
    SC.BaseLife.resolveObject, SC.BaseLife.storageAcceptsDeposit
local oldDeposit = SC.BaseWork.depositToStorage
local store = inventory()
local storage = { id = "upstairs-fresh-food", category = "fresh_food" }
local rows = {}
SC.BaseLife.depositStorageRows = function(category)
    assert(category == "food" or category == "fresh_food",
        "camp fish only targets marked food storage")
    return category == "fresh_food" and rows or {}
end
SC.BaseLife.resolveContainer = function() return store end
SC.BaseLife.resolveObject = function() return { x = 10, y = 10, z = 1 } end
SC.BaseLife.storageAcceptsDeposit = function() return true end
local deposits = 0
SC.BaseWork.depositToStorage = function(worker, _, destination, container, value)
    assert(destination == storage and container == store,
        "the marked upper-floor food container is selected")
    deposits = deposits + 1
    local moved = util.transferItemVerified(worker.inventory, container, value)
    assert(moved == true, "the exact caught fish moves into storage")
    return true, "base_supply_returned"
end
local delivered, deliveryReason = angling.update(foodActor, "camp")
assert(delivered == false and deliveryReason == "fishing_food_storage_missing"
        and deposits == 0 and #foodActor.inventory.items == 4,
    "camp fishing pauses with its catch when no food store is marked")
rows[1] = storage
for index = 1, 3 do
    delivered, deliveryReason = angling.update(foodActor, "camp")
    assert(delivered == true and deliveryReason == "fishing_catch_stored",
        "each catch completes its own verified storage transfer")
end
assert(deposits == 3 and #store.items == 3
        and #foodActor.inventory.items == 1
        and foodActor.inventory.items[1] == unrelated,
    "the angler stores all three catches and leaves unrelated food alone")
for _, value in ipairs(fish) do
    assert(value.data.SC_CampFishingCatch == nil,
        "a deposited fish no longer counts as carried camp catch")
end
local loadedActor = { inventory = inventory(), data = {}, x = 10, y = 10, z = 0 }
setmetatable(loadedActor, { __index = foodActor })
local bag = item()
local bagInventory = inventory()
function bag:getItemContainer() return bagInventory end
loadedActor.inventory:AddItem(bag)
local bagFish = item()
bagFish.data.SC_CampFishingCatch = true
bagInventory:AddItem(bagFish)
loadRatio = 0.75
local stored, storedReason = angling.update(loadedActor, "camp")
assert(stored and storedReason == "fishing_catch_stored"
        and store:contains(bagFish) and not bagInventory:contains(bagFish)
        and bagFish.data.SC_CampFishingCatch == nil,
    "a heavily loaded angler retrieves one bagged catch and stores it")
SC.BaseLife.depositStorageRows, SC.BaseLife.resolveContainer,
    SC.BaseLife.resolveObject, SC.BaseLife.storageAcceptsDeposit =
    oldRows, oldResolveContainer, oldResolveObject, oldAccept
SC.BaseWork.depositToStorage = oldDeposit
util.inventoryLoad = oldInventoryLoad
angling.reset()
local oldRequestTool, oldAudit, oldItemHasTag =
    SC.Dialogue.requestMissingTool, SC.Logistics.audit, util.itemHasTag
local toolRequests = {}
SC.Dialogue.requestMissingTool = function(_, partner, kind, snapshot, _, stillMissing)
    toolRequests[#toolRequests + 1] = { partner = partner, kind = kind,
        snapshot = snapshot, stillMissing = stillMissing }
    return true, "conversation_staged"
end
SC.Logistics.audit = function() return { items = {} } end
local player = { id = "fishing-listener" }
local safe = { threatCount = 0 }
local working, shortage = angling.update(foodActor, "camp", nil, player, safe)
assert(working == false and shortage == "fishing_rod_missing"
        and toolRequests[1].kind == "rod"
        and toolRequests[1].partner == player
        and toolRequests[1].snapshot == safe
        and toolRequests[1].stillMissing(),
    "a camp angler without a rod seeks the player with a specific request")
local rodItem = { data = {} }
function rodItem:getModData() return self.data end
SC.Logistics.audit = function() return { items = { { item = rodItem } } } end
util.itemHasTag = function(value, tag)
    return value == rodItem and tag == "FISHING_ROD"
end
assert(toolRequests[1].stillMissing() == false,
    "a rod request is withdrawn if the angler finds a rod en route")
working, shortage = angling.update(foodActor, "camp", nil, player, safe)
assert(working == false and shortage == "fishing_bait_missing"
        and toolRequests[2].kind == "bait"
        and toolRequests[2].stillMissing(),
    "a rod without a lure asks the player for bait instead")
rodItem.data.fishing_Lure = true
assert(toolRequests[2].stillMissing() == false,
    "a bait request is withdrawn when the rod is baited en route")
SC.Dialogue.requestMissingTool, SC.Logistics.audit, util.itemHasTag =
    oldRequestTool, oldAudit, oldItemHasTag
SC.Dialogue.say, SC.Dialogue.lastSpokenAt, ZombRand = oldSay, oldLast, oldRand
print("FISHING_VOICE_PASS checks=24")

do
    local saved = { base = SC.BaseLife, transport = SC.WorkTransport,
        personal = SC.PersonalItems, native = SC.NativeActions,
        navigation = SC.Navigation, expedition = SC.ExpeditionPrototype,
        audit = SC.Logistics.audit, tag = util.itemHasTag,
        access = util.directInteractionAccess, move = util.move,
        stop = util.stop, clock = util.nowMs, chore = SC.BaseWork.choreReserved,
        fishing = Fishing }
    local clock, rows, registered = 1000, {}, {}
    local visuals, navigation = {}, {}
    local starts, cancellations, navigationCancellations = 0, 0, 0
    local function gearItem(kind, baited)
        local value = item()
        value.kind = kind
        value.data.fishing_Lure = baited and true or nil
        function value:getFullType()
            return self.kind == "rod" and "Base.FishingRod"
                or self.kind == "bait" and "Base.Worm" or "Base.Stone"
        end
        return value
    end
    local function worker()
        local value = { inventory = inventory() }
        function value:getInventory() return self.inventory end
        function value:getPrimaryHandItem() return nil end
        function value.inventory:hasRoomFor() return self.accepts ~= false end
        return value
    end
    local function shelf(id, contents, options)
        local storage = options or {}
        storage.id, storage.container = id, inventory()
        storage.object = { id = id, square = bank, blocked = storage.blocked,
            wait = storage.wait }
        function storage.object:getSquare() return self.square end
        for _, value in ipairs(contents or {}) do storage.container:AddItem(value) end
        rows[#rows + 1], registered[id] = storage, storage
        return storage
    end
    SC.BaseLife = {
        storage = function(id) return registered[id] end,
        withdrawable = function(storage)
            return storage.withdrawals ~= false and storage.category ~= "memorial"
        end,
        storageRows = function(category, withdrawals)
            assert(category == nil and withdrawals == true,
                "fishing considers only registered permitted camp supplies")
            local result = {}
            for _, storage in ipairs(rows) do
                if SC.BaseLife.withdrawable(storage) then result[#result + 1] = storage end
            end
            return result
        end,
        resolveContainer = function(storage) return storage.container end,
        resolveObject = function(storage) return storage.object end,
        availableCountExact = function(storage, fullType)
            local count = 0
            for _, value in ipairs(storage.container.items) do
                if value:getFullType() == fullType then count = count + 1 end
            end
            return math.max(0, count - (storage.reserve or 0))
        end,
    }
    SC.WorkTransport = { foreignProtected = function(value) return value.foreign == true end }
    SC.PersonalItems = { isProtected = function(value) return value.personal == true end }
    SC.BaseWork.choreReserved = function(value) return value.chore == true end
    Fishing = { lure = { All = { ["Base.Worm"] = true } } }
    util.itemHasTag = function(value, tag)
        return value ~= nil and value.kind == "rod" and tag == "FISHING_ROD"
    end
    SC.Logistics.audit = function(actor)
        local result = {}
        for _, value in ipairs(util.inventoryItemsDeep(actor.inventory, 512, 24)) do
            result[#result + 1] = { item = value }
        end
        return { items = result }
    end
    util.nowMs = function() return clock end
    util.directInteractionAccess = function(_, object)
        return not (object.blocked or object.wait), { bank },
            object.blocked and "blocked_static" or nil
    end
    util.stop = function() end
    SC.Navigation = {
        peek = function(actor) return navigation[actor] end,
        requestAny = function(actor, _, _, intent)
            local previous = navigation[actor]
            local serial = previous and previous.approachRequestSerial + 1 or 1
            navigation[actor] = { goalAction = intent.action,
                approachRequestSerial = serial, lastApproachRequest = { intent = intent } }
            return not intent.object.blocked, "blocked_static"
        end,
        cancel = function(actor)
            navigationCancellations = navigationCancellations + 1
            navigation[actor] = nil
            return true
        end,
    }
    util.move = function(actor, _, intent)
        assert(intent.action == "loot_container", "gear pickup uses the storage loot action")
        starts = starts + 1
        visuals[actor] = { token = {}, state = "active" }
        return true
    end
    SC.NativeActions = {
        stopDirect = function() end,
        visualStatus = function(actor)
            return visuals[actor] and visuals[actor].state or nil
        end,
        visualToken = function(actor) return visuals[actor] and visuals[actor].token end,
        clearVisual = function(actor) visuals[actor] = nil end,
        cancelVisualOwned = function(actor, token)
            if visuals[actor] and visuals[actor].token == token then
                cancellations = cancellations + 1
                visuals[actor] = nil
            end
            return true
        end,
    }
    SC.ExpeditionPrototype = nil
    local fisher = worker()
    local contents = {}
    for index = 1, 81 do contents[index] = gearItem("junk") end
    local bare, baited = gearItem("rod"), gearItem("rod", true)
    contents[82], contents[83] = bare, baited
    local source = shelf("tools", contents)
    local preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_preparing_rod" and starts == 0,
        "a bounded scan continues beyond its first eighty entries")
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_preparing_rod" and starts == 1
            and source.container:contains(baited) and #fisher.inventory.items == 0,
        "the baited rod wins over a bare rod and stays in storage during its loot pose")
    visuals[fisher].state = "completed"
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and fisher.inventory:contains(baited)
            and not source.container:contains(baited) and source.container:contains(bare),
        "preparation moves the exact real rod once through the verified storage transaction")
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_gear_ready" and starts == 1,
        "an already baited carried rod finishes preparation without another pickup")
    angling.cancelPreparation(fisher)
    assert(fisher.inventory:contains(baited), "cancelling never deletes acquired gear")

    rows, registered = {}, {}
    fisher = worker()
    local blockedRod, reachableRod = gearItem("rod", true), gearItem("rod", true)
    shelf("blocked", { blockedRod }, { blocked = true })
    local reachable = shelf("reachable", { reachableRod })
    preparing, explanation = angling.prepareGear(fisher)
    assert(not preparing and explanation == "blocked_static",
        "an unreachable shelf reports a bounded physical failure")
    angling.cancelPreparation(fisher)
    clock = clock + 30000
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and visuals[fisher] and reachable.container:contains(reachableRod),
        "a failed shelf cools down so a reachable alternative is tried next")
    visuals[fisher].state = "completed"
    angling.prepareGear(fisher)
    assert(fisher.inventory:contains(reachableRod)
            and registered.blocked.container:contains(blockedRod),
        "alternative-source recovery never takes the blocked shelf's rod")
    angling.cancelPreparation(fisher)

    rows, registered = {}, {}
    fisher = worker()
    bare = gearItem("rod")
    fisher.inventory:AddItem(bare)
    local personal, foreign, chore = gearItem("bait"), gearItem("bait"), gearItem("bait")
    personal.personal, foreign.foreign, chore.chore = true, true, true
    source = shelf("shared", { personal, foreign, chore })
    shelf("reserved", { gearItem("bait") }, { reserve = 1 })
    shelf("memorial", { gearItem("bait") }, { category = "memorial" })
    shelf("closed", { gearItem("bait") }, { withdrawals = false })
    preparing, explanation = angling.prepareGear(fisher)
    assert(not preparing and explanation == "fishing_bait_missing"
            and #fisher.inventory.items == 1,
        "personal, foreign work cargo, chore tools, reserves and forbidden stores stay untouched")
    local firstBait, spareBait = gearItem("bait"), gearItem("bait")
    source.container:AddItem(firstBait)
    source.container:AddItem(spareBait)
    assert(angling.prepareGear(fisher) and visuals[fisher],
        "a newly available permitted bait starts a real pickup")
    source.withdrawals = false
    visuals[fisher].state = "completed"
    preparing, explanation = angling.prepareGear(fisher)
    assert(not preparing and explanation == "fishing_bait_missing"
            and source.container:contains(firstBait) and not fisher.inventory:contains(firstBait),
        "revoking withdrawals during the pose prevents its transfer")
    source.withdrawals = true
    angling.prepareGear(fisher)
    firstBait.personal = true
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and source.container:contains(firstBait)
            and not fisher.inventory:contains(firstBait),
        "an item becoming personal during pickup is replaced without moving it")
    local replacementVisual = {}
    visuals[fisher] = { token = replacementVisual, state = "active" }
    local cancelledBefore = cancellations
    angling.cancelPreparation(fisher)
    assert(visuals[fisher].token == replacementVisual and cancellations == cancelledBefore,
        "cancellation cannot stop another controller's newer loot pose")
    visuals[fisher] = nil
    angling.prepareGear(fisher)
    visuals[fisher].state = "completed"
    angling.prepareGear(fisher)
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_gear_ready"
            and fisher.inventory:contains(spareBait) and source.container:contains(firstBait)
            and #fisher.inventory.items == 2,
        "a bare rod needs exactly one permitted bait, without creating extras")
    local mission = { leader = { actor = fisher }, scout = { phase = "outbound",
        search = { request = { category = "fish" } } } }
    SC.ExpeditionPrototype = { current = function() return mission end }
    angling.cancelPreparation(fisher)
    assert(angling.gearReserved(fisher, bare) and angling.gearReserved(fisher, spareBait)
            and not angling.gearReserved(fisher, firstBait),
        "active mission gear protection reconstructs exact carried items after cancel or reload")
    local startsBefore = starts
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_gear_ready" and starts == startsBefore,
        "reconstructed preparation does not withdraw a second rod or bait")
    angling.cancelPreparation(fisher)
    mission.scout.phase = "inbound"
    assert(not angling.gearReserved(fisher, bare) and not angling.gearReserved(fisher, spareBait),
        "mission-derived protection ends on the return journey")

    rows, registered = {}, {}
    fisher = worker()
    for index = 1, 8 do shelf("empty-" .. index, {}) end
    source = shelf("ninth", { gearItem("rod", true) })
    preparing, explanation = angling.prepareGear(fisher)
    assert(preparing and explanation == "fishing_preparing_rod" and not visuals[fisher],
        "one preparation step never scans more than eight storage containers")
    fisher.inventory.accepts = false
    preparing, explanation = angling.prepareGear(fisher)
    assert(not preparing and #fisher.inventory.items == 0 and #source.container.items == 1,
        "native capacity rejection leaves the gear in its original container")
    angling.cancelPreparation(fisher)

    rows, registered = {}, {}
    fisher = worker()
    shelf("approach", { gearItem("rod", true) }, { wait = true })
    angling.prepareGear(fisher)
    local ownedNavigation = navigation[fisher]
    local cancelledNavigationBefore = navigationCancellations
    angling.cancelPreparation(fisher)
    assert(ownedNavigation and navigation[fisher] == nil
            and navigationCancellations == cancelledNavigationBefore + 1,
        "cancellation releases the preparation's exact active storage approach")
    angling.prepareGear(fisher)
    local foreignNavigation = { goalAction = "combat_approach", approachRequestSerial = 2 }
    navigation[fisher] = foreignNavigation
    cancelledNavigationBefore = navigationCancellations
    angling.cancelPreparation(fisher)
    assert(navigation[fisher] == foreignNavigation
            and navigationCancellations == cancelledNavigationBefore,
        "cancellation leaves a replacement navigation owner alone")
    SC.BaseLife, SC.WorkTransport, SC.PersonalItems = saved.base, saved.transport, saved.personal
    SC.NativeActions, SC.Navigation, SC.ExpeditionPrototype = saved.native, saved.navigation, saved.expedition
    SC.Logistics.audit, SC.BaseWork.choreReserved = saved.audit, saved.chore
    util.itemHasTag, util.directInteractionAccess, util.move = saved.tag, saved.access, saved.move
    util.stop, util.nowMs, Fishing = saved.stop, saved.clock, saved.fishing
    print("FISHING_PREPARATION_PASS checks=21")
end
