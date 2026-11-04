-- SPDX-License-Identifier: MIT
-- Extended physical timber permutations; essential cargo retains the complete effect chain.
local SC = SurvivorCompanion
local Wood, Logging, U, X = SC.ExpeditionWood, SC.LoggingWork, SC.GameplayUtil, assert(SC.WoodTestFixture)
local check, actor, item, container = X.check, X.actor, X.item, X.container
local put, remove, weight, plant, square, drop = X.put, X.remove, X.weight, X.plant, X.square, X.drop
local pulse, nativeFell, context, car, actors = X.pulse, X.nativeFell, X.context, X.car, X.actors

check(Wood.normalizeRequest({ mode = "count" }).quantity == 12, "default request")
check(Wood.normalizeRequest({ mode = "full" }).quantity == nil, "full has no invented count")
check(not Wood.normalizeRequest({ mode = "count", quantity = 257 }), "bound request")
check(not Wood.normalizeRequest({ mode = "count", quantity = 1.5 }), "integer request")

-- A root inventory can physically hold a log but a walking actor may not
-- safely carry it. A real worn bag with weight reduction changes that.
local walker = actor("walker", 10)
put(walker.bag, item("Base.Axe"))
check(not Wood._tests.carryDestination(walker, nil, false), "walking strength preflight")
local bag = item("Base.Bag") bag.bag, bag.reduction = container(20), 70
put(walker.bag, bag) walker.worn = bag
check(Wood._tests.carryDestination(walker, nil, false) == bag.bag, "real reduced-weight bag admitted")
walker.worn, walker.secondary = nil, bag
check(Wood._tests.carryDestination(walker, nil, false) == bag.bag, "secondary-hand bag uses native weight reduction")
walker.secondary, walker.primary = nil, bag
check(Wood._tests.carryDestination(walker, nil, false) == bag.bag, "primary-hand bag uses native weight reduction")
walker.primary = nil
check(not Wood._tests.carryDestination(walker, nil, false), "putting a bag away removes its carrying benefit")
walker.worn = bag
local rejected = item("Base.Log") bag.bag.reject = true
check(not Wood._tests.carryDestination(walker, rejected, false), "native bag admission required")
bag.bag.reject = nil
check(Wood._tests.carryDestination(walker, rejected, true), "short car shuttle admits physical load")
do
    remove(walker.bag, bag)
    walker.worn, walker.x, walker.y = nil, 20, 20
    check(not Wood.carryDestination(walker, rejected), "axe plus log exceeds walking limit of ten")
    check(not Wood.carryDestination(walker, rejected, true), "unvalidated boolean cannot bypass walking capacity")
    check(Wood.carryDestination(walker, rejected, { carId = 42, target = { x = 21, y = 20, z = 0 } }) == walker.bag,
        "public return helper admits real nearby car-to-storage shuttle with axe three and log nine")
    check(not Wood.carryDestination(walker, rejected, { carId = 42, target = { x = 50, y = 20, z = 0 } }),
        "distant storage cannot use heavy short shuttle")
    walker.x = 50
    check(not Wood.carryDestination(walker, rejected, { carId = 42, target = { x = 21, y = 20, z = 0 } }),
        "actor must also be close to stopped car")
    walker.x, walker.bag.capacity = 20, 10
    check(not Wood.carryDestination(walker, rejected, { carId = 42, target = { x = 21, y = 20, z = 0 } }),
        "short shuttle never bypasses physical inventory capacity")
    walker.bag.capacity, walker.limit = 50, 20
    check(Wood.carryDestination(walker, rejected) == walker.bag, "ordinary under-limit walking remains available")
    walker.limit = 10
    local w, members = Wood.createState({ mode = "count", quantity = 1 }), { { id = walker.id, actor = walker } }
    local integration = SC.ExpeditionIntegration
    SC.ExpeditionIntegration = { woodReturnShuttleAvailable = function() return false end }
    local _, why, ready = Wood.prepare(members, w, { sqlId = 42 })
    check(not ready and why == "wood_return_carry_capacity", "heavy-only crew cannot depart without a short home delivery path")
    SC.ExpeditionIntegration.woodReturnShuttleAvailable = function() return true end
    local _, _, readyNear = Wood.prepare(members, w, { sqlId = 42 })
    check(readyNear == true, "nearby permitted home destination admits heavy car crew")
    SC.ExpeditionIntegration = integration
end

-- All logging controllers contend for the same tree and an active native
-- chop keeps ownership even if its ordinary ten-second heartbeat elapsed.
local target = plant(-8, -8)
local cutter, hauler = actor("cutter"), actor("hauler")
put(cutter.bag, item("Base.Axe"))
check(Logging.claimTree("field", "cutter", target, cutter), "field claim")
check(not Logging.claimTree("wood", "hauler", target, hauler), "cross-controller isolation")
cutter.kind, cutter.active = "chop_tree", true
Logging.releaseTree("field", "cutter")
check(not Logging.claimTree("wood", "hauler", target, hauler), "release cannot erase an unsettled native chop claim")
X.advanceClock(11000)
check(not Logging.claimTree("wood", "hauler", target, hauler), "active chop retains claim")
cutter.kind, cutter.active = nil, false
check(Logging.claimTree("wood", "hauler", target, hauler), "inactive expired claim released")
Logging.reset()

local wood = Wood.createState({ mode = "count", quantity = 2 })
local roster = { { id = "cutter", actor = cutter }, { id = "hauler", actor = hauler } }
local ctx = context(wood, roster, 42)
local prepared, _, ready = Wood.prepare(roster, wood, { sqlId = 42 })
check(prepared and ready, "car capacity and carried axe preflight")
pulse(cutter, ctx, 1)
check(cutter.active and X.chops() == 1 and #wood.acquisitions == 0, "native action starts without fake output")
local saved = Wood.copy(wood)
check(saved and saved.workers.cutter.work.point.x == -8, "active physical work serializes")
check(saved.workers.cutter ~= wood.workers.cutter, "save is isolated copy")
nativeFell(cutter, 2)
ctx.wood, wood = saved, saved
pulse(cutter, ctx, 1)
check(#wood.pendingLogs == 2 and #wood.acquisitions == 0, "reload reconciles actual new raw logs only")
pulse(hauler, ctx, 1)
check(#wood.acquisitions == 1 and Wood.reserved(hauler.bag.items[1]), "hauler claims exact physical log")
check(Wood.cargoCounts(wood, roster, nil, 42).carried == 1, "read-only progress counts actual carried cargo")
local acquired = hauler.bag.items[1]
pulse(hauler, ctx, 2)
check(acquired.owner == car.cargo and acquired.data.LF_ExpeditionWood.tripId == "wood-trip", "trunk loads same protected object")
pulse(cutter, ctx, 1)
check(#wood.acquisitions == 2, "second raw log pickup counts once")
check(not Wood.status(wood).done, "quota waits for crew and cargo settlement")
for _ = 1, 6 do pulse(cutter, ctx) pulse(hauler, ctx) end
check(Wood.status(wood).done and Wood.status(wood).loaded == 2, "quota stops after all cargo loaded")
local debris=0
for _,wrapper in ipairs(target.world) do
    if wrapper.item.kind=="Base.TreeBranch" or wrapper.item.kind=="Base.Twigs" then
        debris=debris+1
        check(wrapper.item.owner==nil and not Wood.reserved(wrapper.item),
            "expedition leaves native branches and twigs on the ground without cargo claims")
    end
end
check(debris==2,"both debris types remain after the expedition's real logs reach the trunk")
check(Wood.cargoCounts(wood, roster, nil, 42).loaded == 2
    and Wood.cargoCounts(wood, roster, { "cutter" }, 42).complete == false, "cargo progress respects actual trunk and visibility")
check(X.chops() == 1 and #car.cargo.items == 2, "no extra trees chopped once quantity reached")
local copied = Wood.copy(wood)
check(copied and #copied.acquisitions == 2, "loaded receipts survive save")
copied.acquisitions[2].id = copied.acquisitions[1].id
check(not Wood.valid(copied), "duplicate exact receipts rejected")
copied = Wood.copy(wood) copied.workers.cutter.scan = -1
check(not Wood.valid(copied), "malformed worker rejected")
copied = Wood.copy(wood) copied.loans.bad = { itemId = "tool", storageId = "source" }
check(Wood.valid(copied), "plain unstarted loan survives save")
copied.extra = function() end
check(not Wood.valid(copied), "native/function references rejected")

-- The original base axe is fetched and repaid, with an exact serialized
-- obligation. A replacement of the same type cannot discharge that loan.
local borrower = actor("borrower", 20)
local borrowed = item("Base.Axe")
local source = { id = "axe-source", container = container() }
put(source.container, borrowed) X.setStorages({ source })
local loanWood = Wood.createState({ mode = "count", quantity = 1 })
local loanRoster = { { id = "borrower", actor = borrower } }
local handled, reason, loanReady = Wood.prepare(loanRoster, loanWood)
check(handled and not loanReady and borrowed.owner == borrower.bag, "borrow physical base axe")
check(Wood.toolsPending(loanWood, "borrower") and Wood.reserved(borrowed), "loan obligation protected")
local loanSaved = Wood.copy(loanWood)
check(loanSaved and loanSaved.loans.borrower.itemId == borrowed.id, "exact loan survives reload")
local returned, _, returnedDone = Wood.returnTools(borrower, { wood = loanSaved })
check(returned and returnedDone and borrowed.owner == source.container, "exact borrowed axe physically returned")
check(not Wood.reserved(borrowed) and not Wood.toolsPending(loanSaved), "return clears only own tool protection")
local missing = Wood.createState({ mode = "full" })
missing.loans.borrower = { itemId = "missing-original", storageId = source.id }
put(borrower.bag, item("Base.Axe"))
local _, missingReason, missingDone = Wood.returnTools(borrower, { wood = missing })
check(not missingDone and missingReason == "wood_borrowed_axe_missing", "same-type substitute cannot settle loan")
-- Delivery settlement may release a loan only once the borrower's whole
-- inventory was read without the exact axe.
check(Wood.loanState(missing, "borrower", borrower) == "missing"
    and Wood.loanState(missing, "nobody", borrower) == "none",
    "a fully read inventory without the exact axe proves the loan cannot be repaid")
local keptAxe = item("Base.Axe") put(borrower.bag, keptAxe)
local keptLoan = Wood.createState({ mode = "full" })
keptLoan.loans.borrower = { itemId = keptAxe.id, storageId = source.id }
check(Wood.loanState(keptLoan, "borrower", borrower) == "carried"
    and Wood.loanState(keptLoan, "borrower", nil) == "unknown",
    "a carried or uninspectable axe keeps its loan")
local stuffed = actor("stuffed", 20)
for _ = 1, 4097 do put(stuffed.bag, item("Base.Nail")) end
check(Wood.loanState(keptLoan, "stuffed", stuffed) == "none", "loan lookup is by borrower")
keptLoan.loans.stuffed = { itemId = keptAxe.id, storageId = source.id }
check(Wood.loanState(keptLoan, "stuffed", stuffed) == "unknown",
    "an inventory past the scan limit is not proof the axe is gone")
-- A marker is only as live as its trip. Leftover protection from a settled
-- trip must not keep a log or axe away from camp work forever.
local leftover = item("Base.Axe")
leftover.data.LF_ExpeditionWoodTool = { id = leftover.id, memberId = "borrower" }
local leftoverLog = item("Base.Log")
leftoverLog.data.LF_ExpeditionWood = { tripId = "settled-trip", id = leftoverLog.id, memberId = "borrower" }
check(Wood.reserved(leftover) and Wood.reserved(leftoverLog),
    "without the expedition owner every marker stays protective")
local liveTrips = {}
SC.ExpeditionPrototype = { woodMarkerLive = function(cargo, tool)
    return cargo and liveTrips[cargo.tripId] or tool and liveTrips[tool.id] or false
end }
check(not Wood.reserved(leftover) and not Wood.reserved(leftoverLog),
    "a settled trip's markers no longer reserve the log or axe")
check(Wood._tests.toolAllowed(leftover, "borrower", Wood.createState({ mode = "full" })),
    "a stale loan marker does not stop its holder using that axe on a new trip")
liveTrips["settled-trip"], liveTrips[leftover.id] = true, true
check(Wood.reserved(leftover) and Wood.reserved(leftoverLog)
    and not Wood._tests.toolAllowed(leftover, "borrower", Wood.createState({ mode = "full" })),
    "a live trip's markers still reserve its cargo and borrowed axe")
SC.ExpeditionPrototype = nil

-- Full walking crews stop before felling, and a full trunk stops further
-- felling while preserving already acquired raw cargo on its real carrier.
local full = actor("full", 2) put(full.bag, item("Base.Axe"))
plant(-8, -8)
local fullWood = Wood.createState({ mode = "full" })
local fullCtx = context(fullWood, { { id = "full", actor = full } })
local beforeChops = X.chops()
pulse(full, fullCtx, 2)
check(Wood.status(fullWood).done and X.chops() == beforeChops, "full walkers stop before cutting")
local protectedLog = item("Base.Log")
put(hauler.bag, protectedLog)
protectedLog.data.LF_ExpeditionWood = { tripId = "wood-trip", id = protectedLog.id, memberId = "hauler" }
local trunkFull = Wood.createState({ mode = "full" })
trunkFull.acquisitions = { { id = protectedLog.id, itemType = "Base.Log", memberId = "hauler", source = { x = 0, y = 0, z = 0 } } }
trunkFull.workers.hauler = { phase = "loading", scan = 0 }
car.cargo.capacity = weight(car.cargo)
pulse(hauler, context(trunkFull, { { id = "hauler", actor = hauler } }, 42), 2)
check(Wood.status(trunkFull).done and protectedLog.owner == hauler.bag, "full trunk retains real cargo for return")
check(X.chops() == beforeChops, "full trunk does not resume clearing trees")

-- A failed native invocation receipt is not an ownership fact. Reconcile
-- the original moved object after reload instead of losing it or duplicating.
local recoverer = actor("recoverer", 30)
local physical = item("Base.Log")
drop(square(4, 4, 0), physical)
local recovery = Wood.createState({ mode = "count", quantity = 1 })
recovery.pendingLogs = { { id = physical.id, source = { x = 4, y = 4, z = 0 } } }
local recoveryCtx = context(recovery, { { id = "recoverer", actor = recoverer } })
U.pickupFault = true
pulse(recoverer, recoveryCtx)
check(physical.owner == recoverer.bag and #recovery.acquisitions == 0, "ambiguous native pickup does not fabricate receipt")
recoveryCtx.wood = Wood.copy(recovery)
pulse(recoverer, recoveryCtx)
check(#recoveryCtx.wood.acquisitions == 1 and recoveryCtx.wood.acquisitions[1].id == physical.id,
    "reload reconciles same marked native object with proven owner and cleared world link")
check(#recoverer.bag.items == 1, "pickup reconciliation never duplicates original log")
local originalGrid = U.gridSquare
U.gridSquare = function() return nil end
local absent, absentReason = Logging.groundLog({ x = 4, y = 4, z = 0 }, "unloaded-log")
check(not absent and absentReason == "wood_ground_unloaded", "unstreamed ground is not declared missing")
U.gridSquare = originalGrid

-- Preparation owns only a pose/path until BaseWork's synchronous commit.
-- Recall before that commit cannot leave a delayed, unrecorded axe transfer.
local pendingBorrower = actor("pending-borrower", 20)
local pendingRoster = { { id = "pending-borrower", actor = pendingBorrower } }
local pendingWood = Wood.createState({ mode = "count", quantity = 1 })
local originalWithdraw, originalStop = SC.BaseWork.withdrawFromStorage, U.stop
local stoppedGear, clearedGear = 0, 0
U.stop = function(value) if value == pendingBorrower then stoppedGear = stoppedGear + 1 end return true end
SC.NativeActions.clearVisual = function(value) if value == pendingBorrower then clearedGear = clearedGear + 1 end return true end
SC.BaseWork.withdrawFromStorage = function() return true, "base_storage_looting" end
local preparing, _, preparedLoan = Wood.prepare(pendingRoster, pendingWood)
check(preparing and not preparedLoan and borrowed.owner == source.container, "pending pose never transfers axe early")
check(Wood.stop(pendingWood, "radio_recall") and stoppedGear == 1 and clearedGear == 1,
    "recall cancels only owned preparation movement/pose")
check(borrowed.owner == source.container and not Wood.toolsPending(pendingWood), "precommit recall leaves original axe at source without loan")
SC.BaseWork.withdrawFromStorage = function(value, _, storage, owner, tool)
    U.transferItemVerified(owner, value.bag, tool)
    return false, "native_receipt_failed"
end
local ambiguous = Wood.createState({ mode = "count", quantity = 1 })
Wood.prepare(pendingRoster, ambiguous)
check(borrowed.owner == pendingBorrower.bag and Wood.toolsPending(ambiguous, pendingBorrower.id),
    "verified physical axe commit is loaned despite failed invocation receipt")
check(Wood.returnTools(pendingBorrower, { wood = ambiguous }) and borrowed.owner == source.container,
    "ambiguous committed axe returns as the exact original")
SC.BaseWork.withdrawFromStorage, U.stop = originalWithdraw, originalStop

-- A handoff retains roster order. Preparation must use living registered
-- members rather than the dead original first member or their usable axe.
do
    local dead, nextLeader = actor("dead-preparer"), actor("next-preparer")
    dead.dead = true
    local corpseAxe = item("Base.Axe")
    put(dead.bag, corpseAxe)
    local members = { { id = dead.id, actor = dead }, { id = nextLeader.id, actor = nextLeader } }
    local w = Wood.createState({ mode = "count", quantity = 1 })
    local _, _, ready = Wood.prepare(members, w, nil, nextLeader.id)
    check(not ready and borrowed.owner == nextLeader.bag and w.loans[nextLeader.id],
        "new leader borrows exact axe while original corpse's usable axe is ignored")
    local _, _, readyNext = Wood.prepare(members, w, nil, nextLeader.id)
    check(readyNext == true and w.cutterId == nextLeader.id and corpseAxe.owner == dead.bag,
        "living replacement cutter is selected without reordering roster")
    nextLeader.dead = true
    local _, why, readyDead = Wood.prepare(members, w, nil, nextLeader.id)
    check(not readyDead and why == "wood_worker_unavailable" and w.loans[nextLeader.id],
        "no viable actor fails safely and preserves already committed tool loan")
    nextLeader.dead = false
    Wood.returnTools(nextLeader, { wood = w })
    actors[nextLeader.id] = nil
    local _, unknownWhy = Wood.prepare(members, Wood.createState({ mode = "count", quantity = 1 }))
    check(unknownWhy == "wood_worker_unavailable", "unregistered live roster object cannot prepare")
    actors[nextLeader.id] = nextLeader
    local waiting = actor("waiting-preparer")
    members[#members + 1] = { id = waiting.id, actor = waiting }
    local pendingState = Wood.createState({ mode = "count", quantity = 1 })
    SC.BaseWork.withdrawFromStorage = function() return true, "base_storage_looting" end
    Wood.prepare(members, pendingState, nil, nextLeader.id)
    nextLeader.dead = true
    SC.BaseWork.withdrawFromStorage = originalWithdraw
    Wood.prepare(members, pendingState, nil, waiting.id)
    check(borrowed.owner == waiting.bag and pendingState.loans[waiting.id]
        and not pendingState.loans[nextLeader.id], "pending gear transaction is replaced after borrower death")
    local savedState = Wood.copy(pendingState)
    check(savedState.loans[waiting.id].itemId == borrowed.id, "handoff tool ownership persists across reload")
    Wood.returnTools(waiting, { wood = pendingState })
    local interrupted = Wood.createState({ mode = "count", quantity = 1 })
    SC.BaseWork.withdrawFromStorage = function(value, _, _, owner, tool)
        U.transferItemVerified(owner, value.bag, tool)
        error("interrupted native receipt")
    end
    check(not pcall(Wood.prepare, members, interrupted, nil, waiting.id), "fixture interrupts after physical axe commit")
    waiting.dead = true
    check(Wood.stop(interrupted, "leader_dead") and interrupted.loans[waiting.id]
        and Wood.copy(interrupted).loans[waiting.id].itemId == borrowed.id,
        "handoff teardown journals an already committed axe before clearing transient preparation")
    waiting.dead = false
    SC.BaseWork.withdrawFromStorage = originalWithdraw
    Wood.returnTools(waiting, { wood = interrupted })
    local daylight = Wood.createState({ mode = "count", quantity = 1 })
    put(nextLeader.bag, item("Base.Axe"))
    nextLeader.dead = false
    Wood.prepare(members, daylight, nil, nextLeader.id)
    nextLeader.dead = true
    put(waiting.bag, item("Base.Axe"))
    local _, _, resumed = Wood.prepare(members, daylight, nil, waiting.id)
    check(resumed == true and daylight.cutterId == waiting.id,
        "prepared daylight-wait state revalidates cutter after leader death")
end

-- Carrying an axe does not elect every member as a cutter. Persist the
-- elected member and hand the role over only when their tool is unusable.
Logging.reset()
local first, second = actor("first-cutter"), actor("second-hauler")
local firstAxe, secondAxe = item("Base.Axe"), item("Base.Axe")
put(first.bag, firstAxe) put(second.bag, secondAxe)
plant(-8, -8)
local roleWood = Wood.createState({ mode = "count", quantity = 8 })
local roleCtx = context(roleWood, { { id = first.id, actor = first }, { id = second.id, actor = second } })
local oldChops = X.chops()
pulse(second, roleCtx)
check(roleWood.cutterId == first.id and not second.active and X.chops() == oldChops,
    "first usable roster axe elects one cutter even when another member updates first")
pulse(first, roleCtx)
check(first.active and X.chops() == oldChops + 1 and Wood.copy(roleWood).cutterId == first.id,
    "only selected cutter starts native work and role survives save")
firstAxe.broken = true
pulse(first, roleCtx)
check(roleWood.cutterId == second.id and first.active == false, "broken axe hands off role and cancels former native action")
pulse(second, roleCtx)
check(second.active and X.chops() == oldChops + 2, "replacement cutter acquires released tree rather than contending")
Wood.stop(roleWood, "test_complete")
local malformed = Wood.copy(wood)
malformed.workers = "corrupt"
check(Wood.valid(malformed) == false, "scalar worker state fails closed without exception")
SC_TEST_REPORT = "Wood expedition: " .. X.checks() .. " physical ownership/capacity/reload/loan/claim checks passed"
