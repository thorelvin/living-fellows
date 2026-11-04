-- SPDX-License-Identifier: MIT
-- Extended timber cases; the essential gate retains the physical delivery chain.
local SC, T = SurvivorCompanion, INTEGRATION_TEST
local I, U, X = SC.ExpeditionIntegration, SC.GameplayUtil, assert(T.WoodDelivery)
local check, clone, clear, log, create = X.check, X.clone, X.clear, X.log, X.create
local yard, bagFor, carFor, transfer = X.yard, X.bagFor, X.carFor, X.transfer
local physicalWood, physicalLogging = X.physicalWood, X.physicalLogging

clear()
local item = log("walking:1")
local a = T.actor("a", "Alice", {})
local bag = bagFor(a, { item })
a.inventory.capacity = 1 -- root cannot stage the log out of the bag
local construction = T.storage("construction:1", "construction", {}, 1)
local record = create(a, { item })
I.refresh(record)
local status = I.summary(record)
check(status.kind == "wood" and status.version == 2 and status.tripId == "wood:1"
    and status.requestMode == "count" and status.requested == 12,
    "UI receives wood kind, trip and request mode")
check(status.collected == 1 and status.carried == 1 and status.returned == 1
    and status.stored == 0 and status.pending == 1 and not status.complete,
    "returned cargo does not count as stored")
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container and #bag.items == 0
    and #a.inventory.items == 1 and T.moves == 1 and T.animations == 1,
    "exact bag log deposits directly with native loot pose and no overloaded staging")
check(item.data.LF_ExpeditionWood == nil and I.summary(record).complete
    and not I.wants(record, a) and a.order == nil,
    "verified deposit clears cargo protection and does not require resume-duty option")

clear()
item = log("visual:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
local visualState, visualToken = "active", 7
SC.NativeActions.visualStatus = function() return visualState end
SC.NativeActions.visualToken = function() return visualToken end
check(select(2, I.update(record, a)) == "base_storage_looting" and T.moves == 0,
    "active storage pose keeps cargo in its exact original owner")
visualState, visualToken = "completed", 8
check(select(2, I.update(record, a)) == "wood_storage_visual_changed"
    and item.container == a.inventory and T.moves == 0,
    "another native animation cannot finish this deposit")
SC.NativeActions.visualStatus = function() return "completed" end
SC.NativeActions.visualToken = function() return 7 end

clear()
local logs = {}
for index = 1, 256 do logs[index] = log("limit:" .. index) end
a = T.actor("a", "Alice", logs)
record = create(a, logs, { request = { mode = "full" } })
check(record.requested == 256 and #I.copy(record).items == 256,
    "full-load ledger and copy support 256 exact receipts")
record.items[257] = clone(record.items[1])
record.items[257].id = "too-many"
check(not I.valid(record), "257th wood receipt is rejected")
record.items[257] = nil
record.version, record.kind = 1, nil
check(not I.valid(record), "ordinary receipt schema cannot inherit the wood ceiling")
record.requested = 8
while #record.items > 17 do table.remove(record.items) end
check(not I.valid(record), "ordinary 16-receipt ceiling is retained")
table.remove(record.items)
check(I.valid(record), "older 16-receipt records still load")

clear()
item = log("yard:log")
a = T.actor("a", "Alice", { item })
yard()
construction = T.storage("construction:1", "construction", {}, 2)
T.storage("general:1", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == nil and item.world == T.yard.worlds[1]
    and item.world:getItem() == item and #construction.container.items == 0
    and record.items[1].storageId == "yard:1"
    and T.arrangeCalls == 1 and T.arrangeVerified == true,
    "Log Yard is preferred and shares native pile arrangement only after exact world ownership proof")

clear()
item = log("general:log")
a = T.actor("a", "Alice", { item })
T.storage("construction:full", "construction", { T.item("existing", "construction") }, 1)
local denied = T.storage("general:denied", "general", {}, 2)
denied.deposits = false
local general = T.storage("general:1", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == general.container and #denied.container.items == 0,
    "wood falls through full Construction to deposit-permitted General")

clear()
item = log("route:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:blocked", "construction", {}, 2)
construction.unreachable = true
general = T.storage("general:reachable", "general", {}, 2)
record = create(a, { item })
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == general.container,
    "unreachable Construction does not starve reachable General")

clear()
item = log("full:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:full", "construction", { T.item("existing", "construction") }, 1)
record = create(a, { item })
check(I.woodDestinationAvailable(a) == true, "full registered storage is permitted before departure")
local moved, reason = I.update(record, a)
check(not moved and reason == "matching_storage_full" and item.container == a.inventory
    and record.items[1].retryRemainingMs == 180000
    and record.retryRemainingMs == 180000 and not I.wants(record, a),
    "full storage preserves exact cargo and pauses for three minutes")
T.now = 60000
local saved = I.copy(record)
check(saved.retryRemainingMs == 120000 and saved.items[1].retryRemainingMs == 120000,
    "save stores remaining pause rather than process-clock deadline")
I.reset()
T.now = 0
construction.container.items = {}
check(not I.wants(saved, a) and not I.settle(saved), "reload preserves paused delivery obligation")
T.now = 120001
check(I.wants(saved, a) and select(2, I.update(saved, a)) == "expedition_supply_stored"
    and item.container == construction.container,
    "delivery automatically retries after the persisted pause")

clear()
item = log("manual:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
check(I.woodDestinationAvailable(a) == false, "missing permitted storage is a preparation blocker")
I.update(record, a)
construction = T.storage("construction:added", "construction", {}, 1)
check(not I.wants(record, a) and I.retry(record) == true and I.wants(record, a)
    and select(2, I.update(record, a)) == "expedition_supply_stored",
    "manual Retry clears the saved delay and attempts actual storage")

clear()
item = log("container:fault")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
T.transferFault = true
check(select(2, I.update(record, a)) == "expedition_supply_stored" and T.moves == 1
    and item.container == construction.container and record.items[1].stored,
    "native mutation followed by false return reconciles exact destination without copying")
check(I.update(record, a) == false and T.moves == 1, "reconciled container transaction cannot deliver twice")

clear()
item = log("yard:fault")
a = T.actor("a", "Alice", { item })
yard()
record = create(a, { item })
T.dropFault = true
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and #T.yard.worlds == 1 and T.moves == 1 and T.arrangeCalls == 1 and T.arrangeVerified == true,
    "native drop mutation followed by false return reconciles and arranges its same verified world wrapper")
saved = I.copy(record)
saved.items[1].stored, saved.items[1].returned, saved.items[1].storageId = false, false, nil
I.reset()
I.refresh(saved)
check(saved.items[1].stored and saved.items[1].storageId == "yard:1"
    and I.summary(saved).stored == 1 and T.moves == 1,
    "reload repairs a journalled ground deposit by exact ID and ownership proof")

clear()
item = log("yard:refused")
a = T.actor("a", "Alice", { item })
yard()
record = create(a, { item })
T.dropRefused = true
check(I.update(record, a) == false and not record.items[1].stored
    and item.container == a.inventory and #T.yard.worlds == 0 and T.moves == 0 and T.arrangeCalls == 0,
    "a refused native yard drop keeps cargo and receipts pending without cosmetic layout")

clear()
item = log("yard:ambiguous")
a = T.actor("a", "Alice", { item })
yard()
record = create(a, { item })
T.dropAmbiguous = true
check(I.update(record, a) == false and not record.items[1].stored and #T.yard.worlds == 1
    and T.moves == 1 and T.arrangeCalls == 0,
    "an ambiguous native world link cannot be arranged, duplicated or counted as delivered")
check(I.settle(record) and not record.items[1].stored and #T.yard.worlds == 1 and T.moves == 1,
    "a log that left every holder ends the obligation without being counted as stored")

-- Settlement follows the supply-record rule: an exact log stays owed while a
-- holder cannot be inspected, and is released, never replaced, once none can.
clear()
item = log("missing:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
record.items[1].destination = { kind = "container", id = "construction:1" }
construction = T.storage("construction:1", "construction", { log("different:native:id") }, 2)
a.inventory.items, item.container = {}, nil
I.refresh(record)
check(not record.items[1].stored and I.summary(record).carried == 0
    and record.items[1].reason == "cargo_pending" and T.moves == 0,
    "missing cargo never becomes a different log")
saved = I.copy(record)
T.actors.a = nil
SC.Persistence = { isPending = function(id) return id == "a" end }
check(not I.settle(saved), "a crew member still loading keeps the exact log owed")
SC.Persistence = nil
check(I.settle(saved) and not saved.items[1].stored, "a dismissed crew member's log is released")
T.actors.a = a
check(I.settle(record) and not record.items[1].stored and record.items[1].reason == "item_not_found"
    and T.moves == 0 and #construction.container.items == 1,
    "a log no inspected holder carries ends the obligation without a replacement")

clear()
item = log("dead:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 2)
record = create(a, { item })
a.dead = true
check(I.settle(record) and not record.items[1].stored and item.container == a.inventory
    and #construction.container.items == 0 and T.moves == 0 and not I.wants(record, a),
    "a dead carrier's log stays on the body and releases the record")

clear()
do
    local kept, taken = log("trunk:kept"), log("trunk:taken")
    a = T.actor("a", "Alice", {})
    local trunkCar = carFor(kept)
    trunkCar.trunk.items[2], taken.container = taken, trunkCar.trunk
    construction = T.storage("construction:1", "construction", {}, 4)
    record = create(a, { kept, taken }, { car = trunkCar })
    table.remove(trunkCar.trunk.items, 2)
    local playerBag = T.container({ taken })
    check(not I.settle(record) and taken.container == playerBag,
        "an exact log still in the loaded expedition trunk keeps the record open")
    record.items[1].destination = { kind = "container", id = "construction:1" }
    table.remove(trunkCar.trunk.items, 1)
    construction.container.items[1], kept.container = kept, construction.container
    check(I.settle(record) and record.items[1].stored and not record.items[2].stored
        and record.items[2].reason == "item_not_found",
        "a log the player took from the trunk no longer holds the delivery record open")
end

clear()
do
    a = T.actor("a", "Alice", {})
    local axe = T.item("axe:held", "tools", "Base.Axe")
    a.inventory.items[1], axe.container = axe, a.inventory
    record = create(a, {}, { loans = { a = { itemId = "axe:held", storageId = "tools:1" } } })
    check(not I.settle(record), "a borrower still carrying the exact axe keeps the loan")
    T.loanUnreadable = true
    a.inventory.items, axe.container = {}, nil
    check(not I.settle(record), "an uninspectable borrower keeps the loan")
    T.loanUnreadable = nil
    check(I.settle(record), "an axe the borrower no longer carries cannot hold the record forever")
    a.inventory.items[1], axe.container = axe, a.inventory
    SC.BaseLife.storage = function(id)
        for _, row in ipairs(T.storages) do if row.id == id then return row end end
    end
    local tools = T.storage("tools:1", "tools", {}, 2)
    check(not I.settle(record), "a carried axe with its marked source keeps the loan")
    T.storages = {}
    check(I.settle(record) and axe.container == a.inventory,
        "an axe whose source storage was unmarked stays with its borrower and ends the loan")
    SC.BaseLife.storage = nil
    T.storages = { tools }
    T.actors.a = nil
    check(I.settle(record), "a gone borrower ends the loan")
end

clear()
item = log("ambiguous:log")
a = T.actor("a", "Alice", { item })
record = create(a, { item })
record.items[1].destination = { kind = "container", id = "construction:1" }
construction = T.storage("construction:1", "construction", { log("ambiguous:log") }, 2)
I.refresh(record)
check(not record.items[1].stored and item.container == a.inventory
    and #construction.container.items == 1 and T.moves == 0,
    "duplicate stable ID in a destination is ambiguous while the original is still carried")

clear()
item = log("yard:blocked")
a = T.actor("a", "Alice", { item })
yard()
a.x = 11
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item })
local requestAny = SC.Navigation.requestAny
SC.Navigation.requestAny = function() return false, "path_blocked:wall" end
check(I.update(record, a) == false and item.container == a.inventory,
    "blocked Log Yard keeps the physical log")
T.now = 180001
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container,
    "after its pause, unreachable Log Yard yields to reachable Construction")
SC.Navigation.requestAny = requestAny

clear()
item = log("claim:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 2)
record = create(a, { item })
item.data.LF_ExpeditionWood.tripId = "another:trip"
check(select(2, I.update(record, a)) == "wood_cargo_ownership_changed"
    and item.container == a.inventory and #construction.container.items == 0
    and item.data.LF_ExpeditionWood.tripId == "another:trip",
    "changed mission claim prevents deposit and marker cleanup")

clear()
item = log("car:log")
a = T.actor("a", "Alice", {})
bag = bagFor(a, {})
a.carry, a.inventory.capacity = bag, 1
local car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
I.refresh(record)
check(record.items[1].returned and I.wants(record, a),
    "stopped mission car within camp work reach can unload after actual crew return")
a.inside = false
check(I.wants(record, a), "authorized roadside route remains active while hauler leaves camp boundary")
check(select(2, I.update(record, a)) == "car_trunk_looting" and item.container == car.trunk
    and T.cargoOptions.workReach == true and T.cargoOptions.workCampOnly == true,
    "roadside extraction approaches through bounded camp work navigation and plays native loot")
check(select(2, I.update(record, a)) == "car_item_carried" and item.container == bag
    and T.moves == 1 and #a.inventory.items == 1,
    "roadside trunk log physically transfers into the admitted bag")
check(select(2, I.update(record, a)) == "expedition_supply_stored"
    and item.container == construction.container and T.moves == 2,
    "roadside fallback cargo still requires a separate verified storage transfer")

clear()
item = log("unsafe:car")
a = T.actor("a", "Alice", {})
car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
car.running = true
check(not I.wants(record, a), "running roadside engine prevents timber unloading")
car.running, car.moving = false, true
check(not I.wants(record, a), "moving roadside car cannot be a delivery source")
car.moving, car.reach = false, false
check(not I.wants(record, a), "car beyond camp work reach remains cargo pending")
car.reach, a.inside = true, false
check(not I.wants(record, a), "outbound crew in reach band do not count as having returned")
a.inside = true
car.locked = true
check(select(2, I.update(record, a)) == "unlock_car_door"
    and record.items[1].retryRemainingMs == 0 and I.wants(record, a),
    "accepted trunk unlocking retains its lease without starting failure cooldown")
car.locked = false
local actual = car
T.car = { id = 73, trunk = actual.trunk }
check(not I.wants(record, a), "another loaded car cannot substitute for the expedition car")
T.car = nil
I.refresh(record)
check(record.items[1].reason == "cargo_pending" and not I.settle(record),
    "unloaded expedition car retains exact delivery obligation")

clear()
item = log("trunk:claim")
a = T.actor("a", "Alice", {})
car = carFor(item)
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { car = car })
item.data.LF_ExpeditionWood.tripId = "another:trip"
check(select(2, I.update(record, a)) == "wood_cargo_ownership_changed"
    and item.container == car.trunk and T.moves == 0 and T.animations == 0,
    "a changed trunk cargo claim is checked before any extraction")

clear()
item = log("loan:log")
a = T.actor("a", "Alice", { item })
construction = T.storage("construction:1", "construction", {}, 1)
record = create(a, { item }, { loans = { a = { itemId = "axe:1", storageId = "tools:1" } } })
check(T.toolCalls == 0 and select(2, I.update(record, a)) == "expedition_supply_stored"
    and T.toolCalls == 0 and I.summary(record).stored == 1 and not I.summary(record).complete,
    "tool return waits for wood deposit and keeps completed-log delivery record alive")
saved = I.copy(record)
I.reset()
check(saved.woodWork.loans.a.itemId == "axe:1" and I.wants(saved, a),
    "loan exact identity survives view release and reload")
check(select(2, I.update(saved, a)) == "wood_axe_returned" and T.toolCalls == 1
    and T.toolContext.missionId == "wood:1" and T.toolContext.roster[1].actor == a
    and I.summary(saved).complete and a.order == nil and not I.wants(saved, a),
    "loan resolves before completion without enabling optional restock or base duty")

clear()
a = T.actor("a", "Alice", {})
record = create(a, {}, { restock = true, loans = { a = { itemId = "axe:2", storageId = "tools:2" } } })
T.blockToolReturn = true
check(I.update(record, a) == false and I.summary(record).toolReason == "wood_tool_source_unavailable"
    and not I.wants(record, a) and a.order == nil and not I.settle(record),
    "unavailable axe destination pauses delivery and cannot resume base duty")
T.blockToolReturn = false
check(I.retry(record) == true and I.wants(record, a), "manual retry also resumes tool return")
for _ = 1, 6 do I.update(record, a) end
check(a.order == "base_duty" and I.summary(record).complete,
    "optional restock and base duty run only after borrowed tool delivery")

-- A missing receipt is terminal cargo, not a fabricated storage deposit, and
-- cannot keep independent borrowed-tool or return-to-duty work unreachable.
clear()
item = log("released:with-axe")
local borrowed = T.item("released:axe", "tools", "Base.Axe")
a = T.actor("a", "Alice", { item, borrowed })
record = create(a, { item }, { loans = { a = { itemId = borrowed.id, storageId = "tools:1" } } })
table.remove(a.inventory.items, 1)
item.container = T.container({ item }) -- the player took the exact item
check(not I.settle(record) and record.items[1].released and not record.items[1].stored,
    "confirmed missing log releases cargo but keeps the carried borrowed axe owed")
check(I.wants(record, a) and select(2, I.update(record, a)) == "wood_axe_returned"
    and T.toolCalls == 1 and I.settle(record), "released cargo allows independent axe return and settlement")
status = I.summary(record)
check(status.stored == 0 and status.released == 1 and status.pending == 0 and status.complete,
    "released wood is reported separately from actual stored wood")
saved = I.copy(record)
I.reset()
check(I.valid(saved) and saved.items[1].released and I.settle(saved) and not I.wants(saved, a),
    "terminal cargo persists across reload without recreating its circular wait")
saved.items[1].released = nil
check(I.valid(saved) and I.settle(saved) and saved.items[1].released,
    "old records without the additive terminal field are inspected and upgraded")
saved.items[1].stored = true
check(not I.valid(saved), "a released receipt cannot also claim verified storage")

clear()
item = log("released:duty")
a = T.actor("a", "Alice", { item })
record = create(a, { item }, { restock = true })
a.inventory.items, item.container = {}, nil
for _ = 1, 7 do I.update(record, a); T.now = T.now + 180001 end
check(record.items[1].released and a.order == "base_duty" and I.settle(record)
    and T.toolCalls == 0 and I.summary(record).stored == 0,
    "missing cargo alone allows restock and duty without a borrowed axe or a manual reset")

clear()
do
    local stored, carried, missing = log("mixed:stored"), log("mixed:carried"), log("mixed:missing")
    a = T.actor("a", "Alice", { stored, carried, missing })
    construction = T.storage("construction:1", "construction", {}, 4)
    record = create(a, { stored, carried, missing })
    check(select(2, I.update(record, a)) == "expedition_supply_stored", "mixed fixture stores one real log")
    table.remove(a.inventory.items, 2)
    missing.container = nil
    check(not I.settle(record) and record.items[3].released and not record.items[2].released,
        "a live receipt protects its delivery while another absent receipt becomes terminal")
    status = I.summary(record)
    check(status.collected == 3 and status.stored == 1 and status.carried == 1
        and status.released == 1 and status.pending == 1,
        "mixed stored, carried and released totals remain truthful")
end

-- Exercise the real controller's report/export pruning with a cached main
-- inventory location, then a player moving the same log into a carried bag.
clear()
do
    local E = assert(SC.ExpeditionPrototype, "real expedition controller must be loaded")
    SC.ViewSession = { slotSqlId = function() return 2 end, rememberSlotSqlId = function() return true end }
    item = log("cache:player-bag-move")
    a = T.actor("a", "Alice", { item })
    bag = bagFor(a, {})
    record = create(a, { item })
    check(E.restore({ schema = 7, state = "idle", slotSqlId = 2, deliveries = { record } }),
        "real pending delivery list accepts the saved wood trip")
    check(#E.pendingDeliveryReports() == 1, "real report path primes the holder cache")
    transfer(a.inventory, bag, item)
    T.now = 100
    saved = E.export()
    check(saved and #saved.deliveries == 1 and not saved.deliveries[1].items[1].released
        and E.receiptPending(item), "save-triggered pruning retains cargo moved into a bag inside750ms")
    T.now = 5100
    check(E.integrationFor(a) ~= nil, "normal decision can locate the same nested log")
    transfer(bag, a.inventory, item)
    T.now = 5200
    check(#E.pendingDeliveryReports() == 1 and E.receiptPending(item),
        "periodic pruning also retains a fresh rearrangement across tracked containers")
    construction = T.storage("construction:1", "construction", {}, 4)
    check(select(2, E.updateIntegration(a)) == "expedition_supply_stored"
        and item.container == construction.container and #E.export().deliveries == 0,
        "fresh ownership recovery permits normal physical delivery and releases its queue slot")
end

for _, failure in ipairs({ "unreadable", "oversized", "broken-list" }) do
    clear()
    item = log("unknown:" .. failure)
    a = T.actor("a", "Alice", {})
    record = create(a, { item })
    if failure == "unreadable" then a.inventory.getItems = function() error("unreadable inventory") end
    elseif failure == "oversized" then
        for index = 1, 4097 do
            local other = T.item("over-budget:" .. index, "general")
            a.inventory.items[index], other.container = other, a.inventory
        end
    else a.inventory.getItems = function() return { size = function() error("unreadable size") end } end end
    check(not I.settle(record) and not record.items[1].released and not record.items[1].stored,
        failure .. " inspection cannot prove absence or discard the record")
    saved = I.copy(record)
    I.reset()
    check(not I.settle(saved) and not saved.items[1].released,
        failure .. " remains unknown after delivery save and retry reset")
end

do
    clear()
    local E = SC.ExpeditionPrototype
    SC.ViewSession = { slotSqlId = function() return 2 end, rememberSlotSqlId = function() return true end }
    item = log("released:protected")
    local axe = T.item("released:protected-axe", "tools", "Base.Axe")
    a = T.actor("a", "Alice", { axe })
    record = create(a, { item }, { loans = { a = { itemId = axe.id, storageId = "tools:1" } } })
    check(not I.settle(record) and record.items[1].released, "missing cargo can finish while a tool keeps trip open")
    check(E.restore({ schema = 7, state = "idle", slotSqlId = 2, deliveries = { record } }),
        "partly completed trip restores with its terminal cargo and outstanding loan")
    check(not E.receiptPending(item) and not E.woodMarkerLive(item.data.LF_ExpeditionWood, nil)
        and E.woodMarkerLive(nil, { memberId = a.id, id = axe.id }),
        "released log loses cargo protection while the exact borrowed axe remains protected")
    check(select(2, E.updateIntegration(a)) == "wood_axe_returned" and #E.export().deliveries == 0,
        "normal worker returns outstanding axe then export pruning frees the completed trip slot")
end

-- Use the production carry helper in the actual trunk-to-storage dispatcher,
-- including the public argument contract that previously dropped `true`.
do
    local oldCarry, oldRoom = SC.ExpeditionWood.carryDestination, SC.WorkTransport.hasRoom
    local oldLoad, oldWeight = U.carryLoad, U.itemWeight
    local oldEntries, oldPoint = SC.LoggingWork.inventoryEntries, SC.LoggingWork.point
    SC.ExpeditionWood.carryDestination = physicalWood.carryDestination
    SC.LoggingWork.inventoryEntries, SC.LoggingWork.point = physicalLogging.inventoryEntries, physicalLogging.point
    U.itemWeight = function(value) return value.fullType == "Base.Log" and 9 or 3 end
    U.carryLoad = function(actor)
        local total = 0
        for _, value in ipairs(actor.inventory.items) do total = total + U.itemWeight(value) end
        return total, 10
    end
    local function setupShuttle(distance, physicalCapacity)
        clear()
        item = log("heavy:shuttle")
        a = T.actor("a", "Alice", { T.item("heavy:axe", "tools", "Base.Axe") })
        a.x, a.y = 10, 10
        function a.inventory:getFreeCapacity() return physicalCapacity - U.carryLoad(a) end
        local car = carFor(item)
        car.x, car.y, car.z = 10, 10, 0
        construction = T.storage("construction:near-car", "construction", {}, 5)
        construction.x, construction.y = 10 + distance, 10
        record = create(a, { item }, { car = car })
        SC.WorkTransport.hasRoom = function(destination, actor, value)
            if destination == a.inventory then return destination:getFreeCapacity() >= U.itemWeight(value) end
            return oldRoom(destination, actor, value)
        end
        return car
    end
    local car = setupShuttle(2, 50)
    check(I.woodReturnShuttleAvailable(a, car.id), "dispatch sees permitted home storage within short shuttle reach")
    check(select(2, I.update(record, a)) == "car_trunk_looting", "heavy car unload begins native loot pose")
    check(select(2, I.update(record, a)) == "car_item_carried" and item.container == a.inventory,
        "real dispatcher and real capacity helper carry exact nine-weight log with three-weight axe")
    construction.x = 50
    check(I.update(record, a) == false and item.container == a.inventory and not record.items[1].stored,
        "a storage change after pickup cannot send the heavy carrier on a long walk")
    construction.x = 12
    I.retry(record)
    check(select(2, I.update(record, a)) == "expedition_supply_stored"
        and item.container == construction.container and I.summary(record).stored == 1,
        "nearby heavy delivery deposits exact item and completes with truthful storage count")
    car = setupShuttle(40, 50)
    check(not I.woodReturnShuttleAvailable(a, car.id) and I.update(record, a) == false
        and item.container == car.trunk, "distant home storage blocks heavy unloading before trunk removal")
    car = setupShuttle(2, 10)
    check(I.update(record, a) == false and item.container == car.trunk,
        "physical inventory limit blocks actual trunk pickup despite nearby storage")
    SC.ExpeditionWood.carryDestination, SC.WorkTransport.hasRoom = oldCarry, oldRoom
    U.carryLoad, U.itemWeight = oldLoad, oldWeight
    SC.LoggingWork.inventoryEntries, SC.LoggingWork.point = oldEntries, oldPoint
end

SC_TEST_REPORT = "Wood expedition integration: " .. X.checks() .. " checks passed"
