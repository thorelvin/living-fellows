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
local ring = { points = { { 119, 94 }, { 145, 94 },
    { 145, 110 }, { 119, 110 } } }
function ring:numPoints() return #self.points end
function ring:getX(i) return self.points[i + 1][1] end
function ring:getY(i) return self.points[i + 1][2] end
local feature = { geometry = { points = {
    size = function() return 1 end,
    get = function() return ring end } },
    properties = { get = function(_, key)
        return key == "water" and "river" or nil
    end } }
function feature:hasPolygon() return true end
function feature:containsPoint(x, y)
    return x >= 119 and x <= 145 and y >= 94 and y <= 110
end
local cellFeatures = { size = function() return 1 end,
    get = function() return feature end }
local mapWorld = { isDataLoaded = function() return true end,
    getCell = function(_, cx, cy)
        if cx == 0 and cy == 0 then
            return { features = cellFeatures }
        end
    end }
getPlayerMiniMap = function()
    return { inner = { javaObject = {
        getWorldMap = function() return mapWorld end } } }
end
squares = {}
local remoteBanks, remoteReason, remoteCount =
    angling.bankCandidates(scout, 40, 32, 0)
assert(remoteReason == nil and remoteCount > 0
        and remoteBanks[1].knowledge == "map_water_unconfirmed",
    "a mapped river offers a remote shore without loading its game squares")
local remoteSelected = angling.bankById(scout, remoteBanks[1].id, 40)
assert(remoteSelected and remoteSelected.id == remoteBanks[1].id,
    "a mapped remote shore remains selectable at departure")
ring.points = { { 172, 4 }, { 212, 4 }, { 212, 26 }, { 172, 26 } }
function feature:containsPoint(x, y)
    return x >= 172 and x <= 212 and y >= 4 and y <= 26
end
mapWorld.getCell = function(_, cx, cy)
    if cx == 28 and cy == 24 then return { features = cellFeatures } end
end
local riverside = { x = 7350, y = 6050 }
local riversideBanks, riversideReason, riversideCount =
    angling.bankCandidates(riverside, 200, 32, 0)
assert(riversideReason == nil and riversideCount > 0
        and riversideBanks[1].anchor.y >= 6144,
    "world map cells use 256 tile coordinates at the Riverside shoreline")
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
local storage = { id = "upstairs-food", category = "food" }
local rows = {}
SC.BaseLife.depositStorageRows = function(category)
    assert(category == "food", "camp fish only targets marked food storage")
    return rows
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
