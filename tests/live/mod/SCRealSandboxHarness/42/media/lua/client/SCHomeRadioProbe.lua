-- SPDX-License-Identifier: MIT
-- Clone-only native radio kit before departure; genuine public radio orders
-- afterwards. Never moves, heals or replaces travelling companions or cargo.
local R={}
local function S() return SurvivorCompanion end
local function call(object,method,...)
    if not object then return nil end
    local ok,fn=pcall(function() return object[method] end)
    if not ok or type(fn)~="function" then return nil end
    local good,value=pcall(fn,object,...) if good then return value end
end
local function point(actor)
    return {x=call(actor,"getX"),y=call(actor,"getY"),z=call(actor,"getZ")}
end
local function gap(a,b)
    return a and b and a.x and b.x and math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) or math.huge
end
function R.provision(H,f,check)
    if f.mode~="radio" or f.radio then return true end
    local records={} for _,member in ipairs(f.crew) do records[#records+1]=S().Registry.byId(member.id) end
    local ok,kit=pcall(S().ExpeditionPrototype.provisionTestRadios,f.primary,records)
    if not check("home_radio_real_equipped_kit",ok and kit and kit.player and #kit.team==#f.crew,
        "real native powered two-way radios, equipped before departure; "..tostring(ok and "ready" or kit)) then return false end
    -- A radio-recall fixture should be able to survive ordinary route threats.
    -- Provide real one-handed melee equipment before identity baselines and
    -- dispatch; keep the powered walkie in the other hand. No skill/health
    -- changes, artificial hits, world cleanup or post-departure stocking.
    for _,member in ipairs(f.crew) do
        local inventory=call(member.actor,"getInventory")
        local weapon=call(inventory,"AddItem","Base.Machete")
        if weapon then call(member.actor,"setPrimaryHandItem",weapon) end
        if not check("home_radio_real_melee_kit_"..member.id,weapon~=nil and call(weapon,"getContainer")==inventory
            and call(member.actor,"getPrimaryHandItem")==weapon,"real native Machete before departure; no skill/health changes or removed zombies") then return false end
        -- The deferred recruited-actor factory bypasses the ordinary Recruit
        -- command's final callback. Run that exact callback before baseline,
        -- rather than waiting for a load-throttled background diary pulse.
        local called,accepted,why=pcall(S().Diary.noteRecruited,member.actor,f.primary)
        if not check("home_radio_recruitment_diary_hook_"..member.id,called and (accepted==true or why=="not_a_diarist"
            or why=="diaries_disabled" and S().Config.get("diaryEnabled")~=true),
            "normal recruitment callback before baseline; "..tostring(called and why or accepted)) then return false end
    end
    f.radio={kit=kit,stage="outbound",orders=0}
    return true
end
function R.ready(f)
    if S().Config.get("diaryEnabled")~=true then return true end
    if not S().Diary or not S().Diary.writerFor then return false end
    -- Verify normal recruitment completed new-recruit initialization BEFORE
    -- the strict inventory baseline. Never mistake a newly authored diary or
    -- its pencil for a duplicated expedition item, and never drive the pulse.
    for _,member in ipairs(f.crew) do
        local writer=S().Diary.writerFor(member.id)
        if not writer or writer.diarist and (not writer.bookCreated or not writer.pencilGiven) then return false end
    end
    return true
end
function R.order(f,verb,t,check)
    local active=S().HomeTrip.current()
    local ok,why=S().HomeTrip.requestRadio(f.primary,verb,active and active.radioSession)
    if not check("home_radio_queue_"..verb.."_"..f.radio.orders,ok==true,tostring(why)) then return false end
    f.radio.orders=f.radio.orders+1 f.radio.pendingVerb=verb f.radio.sentAt=t
    local state=S().HomeTrip.radioState(f.primary)
    f.radio.pendingId=state.pending and state.pending.id
    local busy,reason=S().HomeTrip.requestRadio(f.primary,"status",active and active.radioSession)
    return check("home_radio_busy_"..f.radio.orders,busy~=true and reason=="home_radio_busy",tostring(reason))
end
function R.reply(f,check)
    local view=S().HomeTrip.describe(f.primary)
    local radio=view and view.radio
    if not radio or radio.pending then return nil end
    local reply=radio.lastReply
    if not reply then return nil end
    if reply.verb~=f.radio.pendingVerb or reply.id~=f.radio.pendingId then return nil end
    if not check("home_radio_native_ack_"..f.radio.orders,reply.acknowledged==true,
        tostring(reply.text or reply.reason)) then return false end
    return true
end
function R.cargo(f,check)
    if not f.drive then return true end
    local car=S().Vehicle.loadedBySqlId(f.drive.sqlId)
    if not check("home_radio_exact_stopped_car",car==f.drive.vehicle and S().Vehicle.isStationary(car)==true
        and call(car,"isEngineRunning")==false,"same SQL car stationary, engine off after radio recall") then return false end
    local part=call(car,"getPartById","TruckBed") or call(car,"getPartById","TrunkDoor")
    local container=call(part,"getItemContainer")
    if not container then
        for i=0,(tonumber(call(car,"getPartCount")) or 0)-1 do
            local candidate=call(call(car,"getPartByIndex",i),"getItemContainer")
            if candidate and call(candidate,"getType")=="TruckBed" then container=candidate break end
        end
    end
    local items=call(container,"getItems")
    if not items or items:size()>256 then return check("home_radio_cargo_readable",false,"exact trunk unavailable/unbounded") end
    local got={} for i=0,items:size()-1 do
        local item=items:get(i) local id=call(item,"getID")
        if id==nil or got[tostring(id)] then return check("home_radio_cargo_unique",false,"missing/duplicate native cargo ID") end
        got[tostring(id)]=item
    end
    for _,row in ipairs(f.drive.cargo or {}) do
        local item=got[tostring(row.nativeId or row.id)]
        if not check("home_radio_retained_cargo_"..tostring(row.nativeId or row.id),item~=nil
            and call(item,"getFullType")==row.itemType
            and S().GameplayUtil.itemStableId(item,false)==row.id,
            "original exact native cargo stays in recalled car; no invented delivery") then return false end
    end
    return true
end
function R.step(H,f,t,check,result,phase,D)
    local r=f.radio local active=S().HomeTrip.current()
    if t-H.phaseStartedAt>300000 then D.finish(H,f,t,result,phase,"home_radio_deadline",r.stage) return end
    if f.drive then
        local okay,why=D.drive.sample(H,f,t,active,check,result)
        if okay==false then D.finish(H,f,t,result,phase,"home_radio_car_continuity",why) return end
    end
    if active then
        local actor=active.leader and active.leader.actor local at=point(actor)
        if not D.healthy(actor,f.drive~=nil) then D.finish(H,f,t,result,phase,"home_radio_living_leader","native actor damaged/dead; no healing") return end
        if getSpecificPlayer(1)==actor then f.sawSecondView=true end
        if f.lastPoint then
            local distance=gap(at,f.lastPoint)
            if distance>math.max(4,(t-f.lastPointAt)*(f.drive and .06 or .006)) then D.finish(H,f,t,result,phase,"home_radio_continuity",distance) return end
            f.travelled=f.travelled+distance
        end
        f.lastPoint,f.lastPointAt=at,t
        if not D.primaryFixed(f) then D.finish(H,f,t,result,phase,"home_radio_primary_fixed","observer drifted during production radio recall") return end
    end
    if r.stage=="outbound" then
        if not active then D.finish(H,f,t,result,phase,"home_radio_departed_before_call","trip ended before 20m radio test") return end
        if f.travelled<20 then return end
        if f.drive and not check("home_radio_outbound_full_crew",f.drive.sawDriving==true and f.drive.sawCrewSeated==true,
            "real managed drive with native seat ownership for both exact crew") then D.finish(H,f,t,result,phase) return end
        check("home_radio_real_outbound",f.sawSecondView==true,"physical travel="..f.travelled.."m; real owned second view")
        local data=call(r.kit.player,"getDeviceData") local channel=call(data,"getChannel")
        if type(channel)~="number" then D.finish(H,f,t,result,phase,"home_radio_native_channel","channel unavailable") return end
        call(data,"setChannel",channel+1000)
        local changed=call(data,"getChannel")==channel+1000
        local accepted,why=S().HomeTrip.requestRadio(f.primary,"status",active.radioSession)
        call(data,"setChannel",channel)
        if not check("home_radio_mismatched_channel",changed and call(data,"getChannel")==channel
            and accepted~=true and why=="home_radio_needed",tostring(why)) then D.finish(H,f,t,result,phase) return end
        if not R.order(f,"status",t,check) then D.finish(H,f,t,result,phase) return end
        r.stage="status_reply"
    elseif r.stage=="status_reply" or r.stage=="hold_reply" or r.stage=="push_reply" or r.stage=="second_hold_reply" or r.stage=="recall_reply" then
        local received=R.reply(f,check)
        if received==false then D.finish(H,f,t,result,phase) return end
        if not received then return end
        if r.stage=="status_reply" then
            D.screenshot(H,"radio-status",result)
            if not R.order(f,"hold",t,check) then D.finish(H,f,t,result,phase) return end
            r.stage="hold_reply"
        elseif r.stage=="push_reply" then r.stage="resuming" r.resumeDistance=f.travelled
        elseif r.stage=="recall_reply" then r.stage="returning"
        else r.stage=r.stage=="hold_reply" and "holding" or "second_holding" r.heldAt=nil end
    elseif r.stage=="holding" or r.stage=="second_holding" then
        local home=active and active.scout.home
        if not home or home.radioHold~=true or home.radioHoldStopping then return end
        local car=f.drive and S().Vehicle.loadedBySqlId(f.drive.sqlId)
        if f.drive and (car~=f.drive.vehicle or S().Vehicle.isStationary(car)~=true or call(car,"isEngineRunning")~=false) then return end
        local at=point(active.leader.actor)
        if not r.heldAt then r.heldAt=t r.heldPosition=at return end
        if t-r.heldAt<2000 then return end
        if not check("home_radio_actual_"..r.stage,gap(at,r.heldPosition)<=.75,"2s stationary hold; displacement="..gap(at,r.heldPosition)) then D.finish(H,f,t,result,phase) return end
        D.screenshot(H,"radio-"..r.stage,result)
        if r.stage=="holding" then
            if not R.order(f,"push_on",t,check) then D.finish(H,f,t,result,phase) return end
            r.stage="push_reply"
        else
            r.recallPoint=point(f.primary)
            if not R.order(f,"come_back",t,check) then D.finish(H,f,t,result,phase) return end
            r.stage="recall_reply"
        end
    elseif r.stage=="resuming" then
        if f.travelled-r.resumeDistance<8 then return end
        if f.drive then
            for _,member in ipairs(f.crew) do
                local seat=call(f.drive.vehicle,"getSeat",member.actor)
                if not check("home_radio_same_car_resumed_"..member.id,call(member.actor,"getVehicle")==f.drive.vehicle
                    and type(seat)=="number" and seat>=0 and call(f.drive.vehicle,"getCharacter",seat)==member.actor,
                    "Push on retained same native chosen car and every actual crew seat") then D.finish(H,f,t,result,phase) return end
            end
        end
        check("home_radio_actual_resume",true,"physical movement after Push on="..(f.travelled-r.resumeDistance).."m")
        if not R.order(f,"hold",t,check) then D.finish(H,f,t,result,phase) return end
        r.stage="second_hold_reply"
    elseif r.stage=="returning" then
        if active then return end
        if not D.nativeSolo(f) then return end
        local counts,why=D.nativeCounts(f.crew)
        if not counts then D.finish(H,f,t,result,phase,"home_radio_native_crew_counts",why) return end
        for _,member in ipairs(f.crew) do
            local record=S().Registry.byId(member.id) local actor=record and record.actor
            local state=actor and S().Commands.peek(actor)
            if not actor or gap(point(actor),r.recallPoint)>12 or not state or state.order~="follow" then return end
            if not check("home_radio_original_unseated_crew_"..member.id,actor==member.actor
                and D.healthy(actor,false) and counts[member.id]==1,"same living unseated native actor, exactly one scheduler instance") then D.finish(H,f,t,result,phase) return end
            local current,why=D.captureActor(actor)
            local same,reason=D.sameItems(f.setupBaseline[member.id].items,current and current.items)
            if not check("home_radio_exact_return_items_"..member.id,same==true,reason or why) then D.finish(H,f,t,result,phase) return end
            local healthy,detail=D.healthSame(f.setupBaseline[member.id].vitals,current and current.vitals)
            if not check("home_radio_exact_return_health_"..member.id,healthy==true,detail) then D.finish(H,f,t,result,phase) return end
        end
        if not R.cargo(f,check) then D.finish(H,f,t,result,phase) return end
        if f.drive then
            local audited,holders=D.drive.auditDelivery(H,f)
            if audited==false then D.finish(H,f,t,result,phase,"home_radio_unique_cargo",holders) return end
            if audited~=true then return end
            for _,row in ipairs(f.drive.cargo) do
                if not check("home_radio_unique_trunk_"..row.nativeId,holders[row.nativeId]=="trunk",
                    "bounded audit: exactly one original native/stable cargo identity in the same trunk") then D.finish(H,f,t,result,phase) return end
            end
        end
        D.restoreObserver(f)
        check("home_radio_recall_complete",true,"whole exact crew Follow at captured player callpoint, solo view restored; no camp integration")
        r.stage,r.soloAt,r.soloFrame="returned_settle",t,f.frames
        if S().UI and S().UI.refresh then S().UI.refresh() end
    elseif r.stage=="returned_settle" then
        -- Native release commits before the old split-screen render is fully
        -- replaced. Capture actual solo pixels only after normal rendered
        -- frames and the ordinary UI refresh; never reset a camera here.
        if t-r.soloAt<1000 or f.frames-r.soloFrame<30 then return end
        if not check("home_radio_solo_render_settled",D.nativeSolo(f) and S().HomeTrip.current()==nil,
            "at least 1s/30 rendered frames after actual release; "..SCSplitScreenProbe.releaseDiagnostics()) then D.finish(H,f,t,result,phase) return end
        D.screenshot(H,"radio-recalled-solo",result)
        D.finish(H,f,t,result,phase)
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCHomeRadioProbe=R
return R
