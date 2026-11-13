-- SPDX-License-Identifier: MIT
-- Two stock portals in a disposable save; no synthetic force/unlock effect.
local P={}
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCForceEntryProbe=P
local function call(o,m,...)
    if not o or not SurvivorCompanion.GameplayUtil.hasMethod(o,m) then return nil end
    local okay,value=pcall(function(...) return o[m](o,...) end,...)
    if okay then return value end
end
local function photo(H,label)
    pcall(function()
        for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
        getCore():TakeFullScreenshot(H.config.run_id.."-crowbar-"..label..".png")
    end)
end
local function finish(H,current,setPhase)
    local f,SC=H.forceEntry,SurvivorCompanion
    if f then
        SC.ForceEntry.cancel(f.actor,"probe_finished")
        if f.decision then SC.Decision.update=f.decision end
    end
    setPhase("finish",current)
end
local function fail(H,current,check,setPhase,label,why)
    photo(H,"blocked-"..label); check(label,false,tostring(why)); finish(H,current,setPhase)
end
function P.step(H,current,check,result,setPhase)
    local SC=SurvivorCompanion
    local U,F,N=SC.GameplayUtil,SC.ForceEntry,SC.NativeActions
    local f=H.forceEntry
    if not f then
        local record
        for _,r in ipairs(SC.Registry.snapshot()) do if r.actor and r.recruited and not U.isDead(r.actor) then record=r; break end end
        if not record and current-H.phaseStartedAt<12000 then return end
        if not record then return fail(H,current,check,setPhase,"force_worker","no living recruited actor") end
        f={actor=record.actor,id=record.id,at=current,index=0,step=1,tries=0,portals={}}
        H.forceEntry=f
        SC.Downtime.cancel(f.actor,"force_probe"); SC.BaseWork.cancel(f.actor,"force_probe")
        SC.Navigation.cancel(f.actor,"force_probe"); SC.Commands.issue(f.id,"stay",U.squareOf(f.actor),H.player)
        f.decision=SC.Decision.update; SC.Decision.update=function() return true,"force_probe_owns_fixture" end
        f.origin=U.squareOf(H.player)
        f.oldPrimary=f.actor:getPrimaryHandItem(); f.oldSecondary=f.actor:getSecondaryHandItem()
        f.playerEndurance=H.player:getStats():get(CharacterStat.ENDURANCE)
        f.bag=f.actor:getInventory():AddItem("Base.Bag_Schoolbag")
        f.tool=f.bag:getInventory():AddItem("Base.Crowbar")
        f.actor:getStats():set(CharacterStat.ENDURANCE,1)
        f.actor:getStats():set(CharacterStat.FATIGUE,0.05)
        H.clearZombiesNear(H.player,80)
        if SC.UI.instance then SC.UI.instance:setVisible(false) end
        getPlayerInventory(0):setVisible(false); getPlayerLoot(0):setVisible(false)
        setPhase("force_entry_work",current)
        return
    end
    if current-f.at>220000 then return fail(H,current,check,setPhase,"force_deadline",f.lastReason) end
    if f.index<1681 and (not f.portals[1] or not f.portals[2]) then
        for _=1,64 do
            local i=f.index; f.index=i+1
            if i>=1681 then break end
            local sq=U.gridSquare(f.origin:getX()+i%41-20,f.origin:getY()+math.floor(i/41)-20,f.origin:getZ())
            U.squareObjects(sq,function(o)
                local slot=instanceof(o,"IsoDoor") and 1 or instanceof(o,"IsoWindow") and 2 or nil
                if slot and not f.portals[slot] and call(o,"IsOpen")~=true and call(o,"isSmashed")~=true then
                    if slot==1 then call(o,"setLockedByKey",true) end
                    call(o,"setLocked",true)
                    if F.eligible(o) then f.portals[slot]=o end
                end
            end,32)
        end
        return
    end
    local object=f.portals[f.step==3 and 1 or f.step]
    if not object then return fail(H,current,check,setPhase,"force_portal_"..f.step,"no ordinary closed portal in loaded house") end
    if not f.state then
        local side,why=SC.Navigation.barricadeWorkSquare(f.actor,object,U.squareOf(object),nil,{})
        if not side then return fail(H,current,check,setPhase,"force_side",why) end
        H.placeCombatActor(f.actor,{x=side:getX()+0.5,y=side:getY()+0.5,z=side:getZ()})
        if f.step==3 then
            H.clearZombiesNear(f.actor,60)
            if call(object,"IsOpen") then call(object,"ToggleDoor",f.actor) end
            call(object,"setLockedByKey",true); call(object,"setLocked",true)
            if not f.loanRow then
                -- Make this a real camp borrowing scenario, independent of
                -- stale markings or reserved stock in an old seed save.
                SC.BaseLife.reset()
                assert(SC.BaseLife.create(U.squareOf(object),"Crowbar acceptance camp"))
                local ox,oy,oz=U.position(object)
                for dx=-6,6 do for dy=-6,6 do
                    U.squareObjects(U.gridSquare(ox+dx,oy+dy,oz),function(candidate)
                        local container=call(candidate,"getContainer")
                        if not f.loanRow and container and U.containerHasRoom(container,f.actor,f.tool) then
                            local registered,row=SC.BaseLife.registerStorage(candidate,"tools")
                            if registered then f.loanRow,f.loanSource=row,container end
                        end
                    end,24)
                end end
                if f.loanRow then
                    SC.BaseLife.setReserve(f.loanRow.id,"Base.Crowbar",0)
                end
                if not f.loanRow then return fail(H,current,check,setPhase,"force_loan_source","no permitted storage with room") end
                if not U.transferItemVerified(f.bag:getInventory(),f.loanSource,f.tool) then
                    return fail(H,current,check,setPhase,"force_loan_fixture","exact tool could not be put on shelf")
                end
                SC.BaseLife.noteWorkOwnershipMutation()
                print("SC_FORCE_LOAN|camp="..tostring(F.canBorrow(f.actor)).."|source="..tostring(f.loanRow.id)
                    .."|category="..tostring(f.loanRow.category))
            end
            SC.Decision.update=function(actor,player,runtime)
                if actor==f.actor then return f.decision(actor,player,runtime) end
                return true,"force_probe_other_actors_held"
            end
            local accepted,issue=SC.Commands.issue(f.id,"force_open",{object=object},H.player)
            if not accepted then return fail(H,current,check,setPhase,"force_manual_command",issue) end
        end
        f.target=SC.BaseLife.describeObject(object,true); f.state={}; f.stepAt=current; f.shot=false
        f.tries=f.tries+1
        check("force_native_portal_"..f.step.."_"..f.tries,object:isLocked() and F.eligible(object,f.actor),"real locked stock portal")
    end
    local okay,why,done
    if f.step==3 then
        local commands=SC.Commands.peek(f.actor)
        if commands.workTarget then f.state=commands.workTarget.forceEntry or f.state end
        why=f.state.result
        done=commands.order~="work" and N.workKind(f.actor)==nil
    else
        okay,why,done=F.step(f.actor,f.target,f.state,{object=object,snapshot={immediateCount=0,pressure=0},
            useId="live:"..f.step..":"..f.tries,borrow=false,current=function() return true end})
    end
    f.lastReason=why
    local queue=ISTimedActionQueue.getTimedActionQueue(f.actor)
    local native=queue and queue.current
    if native and native.Type=="ISForceOpen" and not native.scProbeTrace then
        native.scProbeTrace=true
        local attempt=native.attempt
        native.attempt=function(self)
            local value=attempt(self)
            print("SC_FORCE_ATTEMPT|step="..f.step.."|try="..f.tries.."|outcome="..tostring(value)
                .."|locked="..tostring(object:isLocked()).."|valid="..tostring(self:isValid()))
            return value
        end
    end
    if not f.shot and N.workKind(f.actor)=="force_open" and current-f.stepAt>700 then
        if f.step==3 then
            f.borrowed=f.actor:getPrimaryHandItem()
            local receipt=f.borrowed and f.borrowed:getModData().LF_ForceEntryTool
            local row=receipt and SC.BaseLife.storage(receipt.sourceId)
            f.borrowedSource=row and SC.BaseLife.resolveContainer(row)
            check("force_borrowed_native_tool",f.borrowedSource and not U.inventoryContains(f.borrowedSource,f.borrowed),
                "normal command borrowed a real marked-storage crowbar")
        end
        photo(H,"working-"..f.step.."-"..f.tries); f.shot=true
        print("SC_FORCE_TRACE|step="..f.step.."|state="..tostring(call(f.actor,"getCurrentState"))
            .."|tool="..tostring(call(f.actor:getPrimaryHandItem(),"getFullType")))
    end
    if not done then return end
    check("force_hands_"..f.step.."_"..f.tries,f.actor:getPrimaryHandItem()==f.oldPrimary
        and f.actor:getSecondaryHandItem()==f.oldSecondary,"prior equipment restored after native outcome")
    check("force_tool_return_"..f.step.."_"..f.tries,U.inventoryContains(f.step==3 and f.borrowedSource or f.bag:getInventory(),
        f.step==3 and f.borrowed or f.tool),
        f.step==3 and "borrowed crowbar returned to its permitted source" or "same crowbar returned to its original bag")
    check("force_player_isolation_"..f.step.."_"..f.tries,H.player:getStats():get(CharacterStat.ENDURANCE)>=f.playerEndurance-0.005,
        "main player stamina unchanged by companion forcing")
    if why~="force_open_succeeded" then
        photo(H,"blocked-native-"..f.step.."-"..f.tries)
        check("force_failure_stops_"..f.step.."_"..f.tries,not N.isWorkActive(f.actor),why)
        if f.tries>=5 or not F.eligible(object,f.actor) then
            return fail(H,current,check,setPhase,"force_native_outcome_"..f.step,why)
        end
        -- Deliberate manual Retry, never an automatic production retry.
        f.state=nil; return
    end
    check("force_unlocked_"..f.step,not object:isLocked(),"verified native portal effect")
    photo(H,"opened-"..f.step)
    if f.step==3 then
        result("PASS","force_entry_live_complete","real door/window plus normal manual order, camp borrowing, exact native tool return and actor isolation")
        finish(H,current,setPhase)
    else f.step=f.step+1; f.state=nil; f.tries=0 end
end
return P
