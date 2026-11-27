-- SPDX-License-Identifier: MIT
-- Real logistics and route jobs; only the planner's supported clock boundary
-- is slowed down to model a slice that expires before it can expand a node.
local SC, f = LivingFellows, LivingFellows.TestFixture
local L, N, P, U = SC.Logistics, SC.Navigation, SC.PathSearch, SC.GameplayUtil
local checks, mode = 0, SC_PENDING_CASE or "stalled"
local function check(value, why)
    checks = checks + 1
    assert(value, "logistics pending " .. mode .. " " .. checks .. ": " .. why)
end
local cost, tick = 10, 0
local originalSlice = P.newSlice
P.newSlice = function(options, budget)
    options = U.copyShallow(options)
    options.clock = function() tick = tick + cost;return tick end
    return originalSlice(options, budget)
end
local extra = f.item("Test.SurplusParcel", "Item", {weight=8.5})
local worker = f.actor("sc-pending-quartermaster", 10, 10, {inventory=f.inventory({extra})})
worker.inventory.capacity=10
worker.modData.SC_Order = "base_duty"
worker.modData.SC_CommandSerial = 45
local shelf = f.containerObject(f.cell:getGridSquare(16,10,0), {})
local row = {id="storage:pending",category="general",deposits=true,withdrawals=false}
SC.BaseLife.isInside = function() return true end
SC.BaseLife.active = function() return {id="base:pending"} end
SC.BaseLife.resident = function(id)
    if id==worker.id then return {role="quartermaster",duty=true} end
end
SC.BaseLife.storageRows = function(category, withdrawals)
    return withdrawals ~= true and (category==nil or category=="general") and {row} or {}
end
SC.BaseLife.storage = function(id) return id==row.id and row or nil end
SC.BaseLife.resolveContainer = function(storage) if storage==row then return shelf,shelf.owner end end
local safe = {snapshot={threats={},threatCount=0,immediateCount=0,pressure=0}}
local started = f.clock

if mode == "stalled" then
    local audit = L.status(worker)
    check(audit.shouldUnload and audit.surplus.item==extra and not audit.lootReturnCleanup,
        "ordinary base-duty surplus selects the reported logistics lane: unload=" .. tostring(audit.shouldUnload)
        .. " ratio=" .. tostring(audit.gearRatio) .. " soft=" .. tostring(audit.softRatio)
        .. " category=" .. tostring(L.itemCategory(extra)) .. " surplus=" .. tostring(audit.surplus and audit.surplus.item))
    local pending, why = L.update(worker,nil,safe)
    check(pending and why=="storage_route_pending" and not SC.ActionSupervisor.current(worker),
        "real planner yields before any transfer action starts")
    for _=1,22 do
        f.clock=f.clock+750
        pending,why=L.update(worker,nil,safe)
        if why~="storage_route_pending" then break end
    end
    check(not pending and why=="storage_route_unknown" and f.clock-started<=16500,
        "a zero-progress ordinary storage survey releases logistics within its bounded wait; got " .. tostring(why))
    check(worker.inventory:contains(extra) and not shelf:contains(extra)
        and not L.busy(worker) and not SC.ActionSupervisor.current(worker),
        "unknown reach keeps exact cargo with its carrier and releases all action ownership")
    worker.inventory:AddItem(f.item("Test.SecondParcel","Item",{weight=0.2}))
    worker.inventory:AddItem(f.item("Test.ThirdParcel","Item",{weight=0.2}))
    f.clock=f.clock+750
    check(not L.status(worker).shouldManage,
        "failed storage item cools down so another base duty can run")
    cost=0
    f.clock=f.clock+31000
    local resumed,reason=L.update(worker,nil,safe)
    check(reason~="storage_route_pending" and resumed and L.busy(worker),
        "a healthy planner can retry the same exact item after cooldown: " .. tostring(reason))
    local route=N.peek(worker)
    check(route and route.path and #route.path>0, "successful retry owns a real walking route to storage")
    worker.square=route.path[#route.path]
    for _=1,20 do
        f.clock=f.clock+100
        L.update(worker,nil,safe)
        if shelf:contains(extra) then break end
    end
    check(shelf:contains(extra) and not worker.inventory:contains(extra),
        "retried logistics finishes the exact deposit after walking to storage")
elseif mode == "retry" then
    worker.modData.LF_LootReturnPending=true
    local pending,why=L.update(worker,nil,safe)
    check(pending and why=="storage_route_pending", "loot delivery starts its real storage survey")
    f.clock=f.clock+15100
    pending,why=L.update(worker,nil,safe)
    check(not pending and why=="storage_route_unknown" and worker.modData.LF_LootReturnRetryAt,
        "failed loot routing retains its obligation and ordinary retry backoff")
    cost=0
    check(L.retryLootDelivery(worker), "manual retry accepts the retained delivery")
    f.clock=f.clock+750
    local resumed,reason=L.update(worker,nil,safe)
    check(resumed and L.busy(worker) and reason~="storage_route_pending",
        "manual retry clears the retained delivery's backoff")
elseif mode == "expiry" then
    local owner={}
    local choices={{id=row.id,object=shelf.owner}}
    local selected,why=N.selectInteraction(worker,owner,"expiry",choices,{retainRoute=true})
    check(not selected and why=="pending" and owner.navigationChoice.job.search.expanded==0,
        "actual route search remains unexpanded when its time slice expires")
    local initial=owner.navigationChoice
    f.clock=f.clock+90001
    selected,why=N.selectInteraction(worker,owner,"expiry",choices,{retainRoute=true})
    check(not selected and why=="unknown" and owner.navigationChoice==initial,
        "expired unfinished survey terminates as unknown instead of silently restarting")
    check(initial.job==nil and initial.bestReceipt==nil,
        "terminal survey releases its search and never grants an unproved route")
elseif mode == "progress" then
    cost=0
    shelf.owner.square=f.cell:getGridSquare(34,10,0)
    local owner, selected, why={},nil,nil
    for _=1,10 do
        selected,why=N.selectInteraction(worker,owner,"slow-real-progress",{{id=row.id,object=shelf.owner}},
            {retainRoute=true,nodeQuota=8})
        if selected then break end
        check(why=="pending" and owner.navigationChoice.lastProgressSerial>0,
            "real search makes bounded progress while it yields")
        f.clock=f.clock+8000
    end
    check(selected and why=="selected" and f.clock-started>15000,
        "a progressing survey can finish beyond fifteen seconds without a false stall")
    check(owner.navigationChoice.bestReceipt and owner.navigationChoice.bestReceipt.path,
        "progressing survey retains its proved physical route")
elseif mode == "diagnostics" then
    f.registry[worker.id]=worker
    local pending,why=L.update(worker,nil,safe)
    check(pending and why=="storage_route_pending", "diagnostic starts on the reported pending state")
    f.clock=f.clock+750
    local oldAudit=L.audit
    L.audit=function() error("Support must not start an inventory audit") end
    local progress=L.progress(worker)
    local report=SC.Support.summary(true)
    L.audit=oldAudit
    check(progress.phase=="route_search" and progress.itemType=="Test.SurplusParcel"
        and progress.candidates==1 and progress.expandedNodes==0 and progress.yieldReason=="deadline"
        and progress.ageMs==750 and progress.progressAgeMs==750,
        "read-only evidence names the actual item, candidate count, age and zero-progress deadline")
    check(report:find("Companion logistics " .. worker.id .. ": route_search",1,true)
        and report:find("item Test.SurplusParcel",1,true), "copied Support report includes the logistics survey")
    check(worker.inventory:contains(extra) and not shelf:contains(extra)
        and not SC.ActionSupervisor.current(worker), "copying diagnostics neither moves cargo nor starts an action")
elseif mode == "evaluation" then
    cost=0
    local owner,selected,why={},nil,nil
    local oldEdge=SC.Topology.classifyEdge
    SC.Topology.classifyEdge=function(...)
        local job=owner.navigationChoice and owner.navigationChoice.job
        if job and job.search.complete then tick=tick+10 end
        return oldEdge(...)
    end
    local expanded,continuations=nil,0
    for _=1,10 do
        selected,why=N.selectInteraction(worker,owner,"slow-evaluation",{{id=row.id,object=shelf.owner}},
            {retainRoute=true})
        check(selected or why=="pending", "evaluation-only progress stays live instead of timing out")
        if selected then break end
        local survey=owner.navigationChoice
        check(survey.job.search.complete and survey.job.pendingEvaluation,
            "real planner is yielding in completed-path geometry evaluation")
        if expanded then
            check(survey.lastExpanded==expanded and survey.progressAt==f.clock,
                "evaluation cursor progress renews the lease without new A-star expansions")
            continuations=continuations+1
        end
        expanded=survey.lastExpanded
        f.clock=f.clock+8000
    end
    SC.Topology.classifyEdge=oldEdge
    check(selected and continuations>=2 and f.clock-started>15000,
        "slow completed-path evaluation eventually selects a proved storage route")
elseif mode == "clock" then
    P.newSlice=originalSlice
    local oldWall, oldBridge=getTimestampMs,SCBridge
    local coarse, precise, preciseReads=100000,1000000000,0
    function getTimestampMs() coarse=coarse+16;return coarse end
    SCBridge={nowMsPrecise=function()
        preciseReads=preciseReads+1;precise=precise+0.01;return precise
    end}
    local owner,selected,why={},nil,nil
    for _=1,30 do
        selected,why=N.selectInteraction(worker,owner,"coarse-clock",{{id=row.id,object=shelf.owner}},
            {retainRoute=true})
        if selected then break end
    end
    check(selected and why=="selected" and preciseReads>0,
        "coarse wall-clock ticks cannot starve a route while the bridge duration clock is available")
    check(owner.navigationChoice.startedAt<1000000 and owner.navigationChoice.progressAt<1000000,
        "survey expiry and progress ages stay in the wall-clock domain")
    SCBridge=oldBridge;getTimestampMs=oldWall
elseif mode == "churn" then
    local pending,why=L.update(worker,nil,safe)
    check(pending and why=="storage_route_pending", "candidate churn starts with a genuine pending search")
    for i=1,13 do
        row.id="storage:pending-" .. i
        f.clock=f.clock+7500
        pending,why=L.update(worker,nil,safe)
        if why~="storage_route_pending" then break end
    end
    check(not pending and why=="storage_route_unknown" and f.clock-started<=97500,
        "changing storage candidates cannot restart one item's absolute wait forever")
    check(worker.inventory:contains(extra) and not shelf:contains(extra),
        "candidate churn never invents a transfer or discards the item")
else
    error("unknown logistics pending case " .. tostring(mode))
end
P.newSlice=originalSlice
SC_TEST_REPORT="LOGISTICS_PENDING_PASS case=" .. mode .. " checks=" .. checks
