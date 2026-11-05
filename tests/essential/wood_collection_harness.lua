-- SPDX-License-Identifier: MIT
-- The native chop/pickup adapters expose real objects; production owns claims and receipts.
local SC = SurvivorCompanion
local W, L, U, X = SC.ExpeditionWood, SC.LoggingWork, SC.GameplayUtil, assert(SC.WoodTestFixture)
local check = X.check
local cutter, hauler = X.actor("cutter", 20), X.actor("hauler", 10)
local axe, source = X.item("Base.Axe"), { id = "camp-tools", container = X.container() }
X.put(source.container, axe)
X.setStorages({ source })
local bag = X.item("Base.Bag")
bag.bag, bag.reduction = X.container(20), 70
X.put(hauler.bag, bag)
hauler.secondary = bag
local crew = { { id = cutter.id, actor = cutter }, { id = hauler.id, actor = hauler } }
local wood = W.createState({ mode = "count", quantity = 1 })
check(select(3, W.prepare(crew, wood, { sqlId = 42 })) == false and axe.owner == cutter.bag,
    "the cutter borrows the actual camp axe before work")
check(W.toolsPending(wood, cutter.id) and select(3, W.prepare(crew, wood, { sqlId = 42 })),
    "the exact tool obligation and usable cargo space permit departure")
local target = X.plant(-8, -8)
local context = X.context(wood, crew, 42)
X.pulse(cutter, context)
check(cutter.active and X.chops() == 1 and #wood.acquisitions == 0,
    "starting the native chop does not invent output")
context.wood = W.copy(wood)
X.nativeFell(cutter, 1)
X.pulse(cutter, context)
wood = context.wood
check(#wood.pendingLogs == 1 and #wood.acquisitions == 0, "reload reconciles only the native raw log")
X.pulse(hauler, context)
local original = bag.bag.items[1] or hauler.bag.items[2]
check(original and original.kind == "Base.Log" and #wood.acquisitions == 1,
    "the hauler claims the exact physical log while retaining its held bag")
for _ = 1, 6 do X.pulse(cutter, context) X.pulse(hauler, context) end
check(original.owner == X.car.cargo and #X.car.cargo.items == 1 and X.chops() == 1,
    "quota loads the same object into the selected trunk and stops further chopping")
check(#target.world == 2 and target.world[1].item.kind ~= "Base.Log"
    and target.world[2].item.kind ~= "Base.Log", "branches and twigs remain native ground debris")
local returned, _, done = W.returnTools(cutter, { wood = W.copy(wood) })
check(returned and done and axe.owner == source.container, "the original borrowed tool physically returns to its source")

local full = X.actor("full", 2)
X.put(full.bag, X.item("Base.Axe"))
local fullWork = W.createState({ mode = "full" })
local before = X.chops()
X.pulse(full, X.context(fullWork, { { id = full.id, actor = full } }), 2)
check(W.status(fullWork).done and X.chops() == before, "a full walking crew stops before creating more cargo")

local recovering, log = X.actor("recovering", 30), X.item("Base.Log")
X.drop(X.square(4, 4, 0), log)
local pending = W.createState({ mode = "count", quantity = 1 })
pending.pendingLogs = { { id = log.id, source = { x = 4, y = 4, z = 0 } } }
local retry = X.context(pending, { { id = recovering.id, actor = recovering } })
U.pickupFault = true
X.pulse(recovering, retry)
check(log.owner == recovering.bag and #pending.acquisitions == 0,
    "an ambiguous native result retains physical ownership without a fabricated receipt")
retry.wood = W.copy(pending)
X.pulse(recovering, retry)
check(#retry.wood.acquisitions == 1 and retry.wood.acquisitions[1].id == log.id
    and #recovering.bag.items == 1, "reload reconciles that same native object exactly once")
local shuttle, ground = X.actor("remote-shuttle", 30), X.square(20, 20, 0)
local remoteLog = X.item("Base.Log")
X.drop(ground, remoteLog)
local remote = W.createState({ mode = "count", quantity = 1 })
remote.pendingLogs = { { id = remoteLog.id, source = { x = 20, y = 20, z = 0 } } }
local remoteContext, approached = X.context(remote, { { id = shuttle.id, actor = shuttle } }), 0
remoteContext.approachSource = function(actor, point, transient)
    check(actor == shuttle and point.x == 20 and point.y == 20 and type(transient) == "table",
        "an unloaded pickup approaches its recorded source using transient travel state")
    approached = approached+1
    return true, "wood_ground_reloading"
end
local gridSquare = U.gridSquare
U.gridSquare = function() return nil end
X.pulse(shuttle, remoteContext)
U.gridSquare = gridSquare
check(approached == 1 and #remote.pendingLogs == 1 and #remote.acquisitions == 0
    and #ground.world == 1, "streaming recovery neither loses nor recreates an unverified log")
X.pulse(shuttle, remoteContext)
check(#remote.acquisitions == 1 and remote.acquisitions[1].id == remoteLog.id
    and remoteLog.owner == shuttle.bag and #ground.world == 0,
    "after loading, pickup revalidates and acquires the exact original log")
-- Unlocking has cleared the latch, but native exit still needs another pulse.
local unlocker = X.actor("unlocker", 20, 20, 100)
local cargoCar = SC.Vehicle.loadedBySqlId(42)
local oldField, unlockPolls = SC.FieldWork, 0
SC.FieldWork = { unlockTrunkFor = function(value, vehicle)
    check(value == unlocker and vehicle == cargoCar, "cargo resumes only its exact actor and car")
    unlockPolls = unlockPolls + 1
    return true, unlockPolls == 1 and "field_trunk_exiting" or "field_trunk_unlocked"
end }
local unlockState = { unlock = {} }
local vehicle, _, unlockReason = SC.LoggingWork.cargo(unlocker, 42, unlockState)
check(not vehicle and unlockReason == "field_trunk_exiting" and unlockState.unlock,
    "an open latch does not discard a pending safe-exit transaction")
vehicle = SC.LoggingWork.cargo(unlocker, 42, unlockState)
check(vehicle == cargoCar and unlockPolls == 2 and not unlockState.unlock,
    "cargo access begins only after unlock and native exit both complete")
SC.FieldWork = oldField
do
    local carrier=X.actor("streamed-car-hauler",30)
    local nativeLog=X.item("Base.Log")
    X.drop(X.square(0,0,0),nativeLog)
    local state=W.createState({mode="count",quantity=1})
    state.pendingLogs={{id=nativeLog.id,source={x=0,y=0,z=0}}}
    local ctx=X.context(state,{{id=carrier.id,actor=carrier}},42)
    ctx.carStop={x=20.5,y=20.5,z=0}
    local loaded,approaches,expected=SC.Vehicle.loadedBySqlId,0,carrier
    SC.Vehicle.loadedBySqlId=function()return nil end
    ctx.approachSource=function(actor,target)
        check(actor==expected and target.x==20 and target.y==20 and target.z==0 and nativeLog.owner==carrier.bag,
            "streamed-out car approach retains the exact carried log")
        approaches=approaches+1 return true,"moving"
    end
    X.pulse(carrier,ctx,3)
    check(approaches>0 and not state.acquisitions[1].carrierKind,
        "no trunk receipt is recorded before the real car reloads")
    local leader=X.actor("streaming-escort",30)
    table.insert(ctx.roster,1,{id=leader.id,actor=leader}) ctx.leaderId=leader.id expected=leader
    X.pulse(leader,ctx)
    check(state.workers[leader.id].phase=="approach" and nativeLog.owner==carrier.bag,
        "the view-owning leader escorts the final hauler without taking or duplicating cargo")
    SC.Vehicle.loadedBySqlId=loaded
    X.pulse(carrier,ctx,3)
    check(nativeLog.owner==X.car.cargo and state.acquisitions[1].carrierKind=="trunk",
        "only the verified physical transfer after reload records trunk cargo")
end
do
    local loaded=SC.Vehicle.loadedBySqlId
    SC.Vehicle.loadedBySqlId=function()return nil end
    for _,stop in ipairs({{x=200,y=200,z=0},false}) do
        local state=W.createState({mode="count",quantity=1})
        local ctx=X.context(state,crew,42)
        ctx.areaBounds={x1=0,y1=0,x2=16,y2=16,z=0}
        ctx.carStop=stop or nil
        local before=X.chops()
        local _,reason=W.update(cutter,ctx)
        check(reason=="wood_area_car_reach" and X.chops()==before and #state.acquisitions==0,
            "an unloaded car needs an actual in-range parked receipt before new cutting")
    end
    SC.Vehicle.loadedBySqlId=loaded
end
SC_TEST_REPORT = "Essential wood collection: " .. X.checks() .. " checks passed"
