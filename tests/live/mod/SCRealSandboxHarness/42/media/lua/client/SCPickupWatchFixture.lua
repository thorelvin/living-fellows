-- SPDX-License-Identifier: MIT
local W={}
local function call(o,name,...) return (SurvivorCompanion.GameplayUtil.call(o,name,...)) end
function W.prepare(H,t,check)
    local SC=SurvivorCompanion
    local x,y=math.floor(t.vehicle:getX()),math.floor(t.vehicle:getY())
    local best,gap
    for dx=-35,10 do for dy=-35,35 do
        local square=SC.GameplayUtil.gridSquare(x+dx,y+dy,0)
        local distance=dx*dx+dy*dy
        if square and call(square,"getRoom")~=nil and call(square,"isOutside")==false
            and SC.GameplayUtil.isSquareFree(square) and not SC.GameplayUtil.squareStaticBlocker(square)
            and (not gap or distance<gap) then best,gap=square,distance end
    end end
    if not check("pickup_watch_indoor_fixture",best~=nil,"nearest real indoor camp floor") then return false end
    local watcher
    for _,record in ipairs(SC.Registry.snapshot()) do
        local state=record.actor and SC.Commands.peek(record.actor)
        if record.actor and record.actor~=t.actor and call(record.actor,"isDead")==false
            and state and state.recruited==true and SC.Actor.validateNative(record.actor) then watcher=record break end
    end
    if not check("pickup_watch_actual_resident",watcher~=nil,"existing recruited companion; no replacement actor") then return false end
    local placed,reason=H.placeCombatActor(watcher.actor,{x=best:getX()+.5,y=best:getY()+.5,z=0})
    if not check("pickup_watch_fixture_placed",placed,tostring(reason)) then return false end
    t.pickupWatcher=watcher
    t.pickupWatchCore={x=best:getX(),y=best:getY(),z=0}
    return true
end
function W.join(H,t,current,check)
    local SC=SurvivorCompanion
    if not SC.BaseWatch.current() then
        local started,reason=SC.BaseWatch.start(t.pickupWatcher.id)
        if not started then t.pickupWatchReason=reason return nil end
    end
    local watch=SC.BaseWatch.current()
    if watch.joining or watch.restoring or getSpecificPlayer(1)~=t.pickupWatcher.actor then return nil end
    local slot=SCSplitScreenProbe.persistJoinedLeaderSlotForReuse()
    SC.ViewSession.rememberSlotSqlId(slot)
    t.pickupWatchSlot=slot
    return check("pickup_watch_native_started",SC.ViewSession.owner()=="base_watch" and slot>=2,
        "actual indoor Watch and reusable slot="..slot)
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCPickupWatchFixture=W
return W
