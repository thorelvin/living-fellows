-- SPDX-License-Identifier: MIT
-- Disposable clone: real marked storage, exact native food and timed actions.
local Probe={}
local function call(object,method,...)
    return select(1,SurvivorCompanion.GameplayUtil.call(object,method,...))
end
local function finish(H,current,result,setPhase,okay,name,detail)
    result(okay and "PASS" or "FAIL",name,detail)
    if H.needsFood and H.needsFood.actor then SurvivorCompanion.Needs.cancel(H.needsFood.actor,"probe_finished") end
    setPhase("finish",current)
end
local function emptyFood(container,SC)
    local items=container:getItems()
    for index=items:size()-1,0,-1 do
        local item=items:get(index)
        local bag=call(item,"getInventory")
        if bag then emptyFood(bag,SC) end
        if SC.Needs.isSafeFoodItem(item) then container:Remove(item) end
    end
end
function Probe.step(H,current,check,result,setPhase)
    local SC,U=SurvivorCompanion,SurvivorCompanion.GameplayUtil
    local function done(okay,name,detail) return finish(H,current,result,setPhase,okay,name,detail) end
    if H.phase=="needs_food_setup" then
        if #SC.Registry.records()==0 and current-H.phaseStartedAt<10000 then return end
        local selected,best
        for _,row in ipairs(SC.BaseLife.storageRows(nil,true)) do
            local container=SC.BaseLife.resolveContainer(row)
            local object=container and call(container,"getParent")
            if object and U.squareOf(object) then
                local x,y,z=U.position(object)
                for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                    local stand=U.gridSquare(math.floor(x)+offset[1],math.floor(y)+offset[2],math.floor(z))
                    local d=U.distance(H.player,object)
                    if stand and U.isSquareFree(stand) and d<=100 and (not best or d<best) then
                        selected={row=row,container=container,object=object,stand=stand};best=d
                    end
                end
            end
        end
        if not selected then
            if current-H.phaseStartedAt<20000 then return end
            return done(false,"needs_food_fixture","no resident near permitted real storage; records="
                ..#SC.Registry.records().." loaded="..#SC.Registry.living()
                .." storages="..#SC.BaseLife.storageRows(nil,true))
        end
        H.needsFood=selected
        for _,other in ipairs(SC.Registry.living()) do SC.Actor.remove(other) end
        local ticket,why=SC.Actor.beginSpawn(selected.stand,{recruited=true,
            identity={forename="Meal",surname="Tester",gender="woman",outfit="Generic01"}})
        if not ticket then return done(false,"needs_food_spawn",tostring(why)) end
        selected.ticket=ticket
        setPhase("needs_food_spawn",current);return
    elseif H.phase=="needs_food_spawn" then
        local selected=H.needsFood
        local actor,why=SC.Actor.pollSpawn(selected.ticket)
        if not actor then
            if why=="spawn_pending" and current-H.phaseStartedAt<12000 then return end
            return done(false,"needs_food_spawn",tostring(why))
        end
        selected.actor=actor
        SC.Commands.issue(SC.Registry.idOf(actor),"stay",nil,H.player)
        SC.Needs.cancel(actor,"fixture_reset");SC.Navigation.cancel(actor,"fixture_reset")
        emptyFood(actor:getInventory(),SC);emptyFood(selected.container,SC)
        SC.BaseLife.active().storages={selected.row}
        selected.row.reserve,selected.row.reserves=0,{}
        selected.apple=selected.container:AddItem("Base.Apple")
        selected.normal=actor:getInventory():AddItem("Base.Crackers")
        selected.bait=actor:getInventory():AddItem("Base.Maggots")
        selected.sauce=actor:getInventory():AddItem("Base.Ketchup")
        if not selected.apple or not selected.normal or not selected.bait or not selected.sauce then
            return done(false,"needs_food_items","native food fixture unavailable")
        end
        selected.apple:setAge(0)
        if not check("needs_food_metadata",SC.Needs.foodTier(selected.apple)==1
            and SC.Needs.foodTier(selected.normal)==2 and SC.Needs.foodTier(selected.bait)==3
            and SC.Needs.foodTier(selected.sauce)==3,"Apple="..tostring(SC.Needs.foodTier(selected.apple))
                .." Crackers="..tostring(SC.Needs.foodTier(selected.normal))
                .." Maggots="..tostring(SC.Needs.foodTier(selected.bait))
                .." Ketchup="..tostring(SC.Needs.foodTier(selected.sauce))) then
            setPhase("finish",current);return
        end
        actor:getStats():set(CharacterStat.HUNGER,.76)
        actor:getStats():set(CharacterStat.THIRST,0)
        actor:getStats():set(CharacterStat.FATIGUE,.2)
        selected.baitBefore=selected.bait:getHungerChange()
        selected.normalBefore=selected.normal:getHungerChange()
        selected.appleBefore=selected.apple:getHungerChange()
        selected.options={commands={recruited=true,order="base_duty"}}
        SC.Needs.reset(actor)
        result("PASS","needs_food_fixture","actor="..SC.Registry.idOf(actor).." storage="..U.squareKey(selected.object))
        setPhase("needs_food_meal",current);return
    end
    local s=H.needsFood
    if not s then return done(false,"needs_food_state","missing fixture") end
    if current-(s.nextAt or 0)<100 then return end
    s.nextAt=current
    local record=SC.Registry.byId(SC.Registry.idOf(s.actor))
    local runtime=record and record.runtime or U.actorState(s.actor)
    if H.phase=="needs_food_meal" then
        local handled,why=SC.Needs.update(s.actor,H.player,runtime,s.options)
        s.lastReason=why
        local hunger=U.characterStatValue(s.actor,"HUNGER",0)
        if hunger<.72 then
            if not check("needs_food_native_meal",call(s.apple,"getContainer")~=s.container
                and (call(s.apple,"getContainer")==nil or s.apple:getHungerChange()>s.appleBefore)
                and s.normal:getHungerChange()==s.normalBefore and s.bait:getHungerChange()==s.baitBefore,
                "hunger=.76->"..hunger.." fresh eaten; carried crackers/maggots untouched") then
                setPhase("finish",current);return
            end
            if select(1,SC.NativeActions.needsStatus(s.actor)) then return end
            SC.Needs.reset(s.actor);emptyFood(s.actor:getInventory(),SC)
            s.normal=s.actor:getInventory():AddItem("Base.Crackers")
            s.actor:getStats():set(CharacterStat.HUNGER,.2)
            s.actor:getStats():set(CharacterStat.THIRST,0)
            local square=U.squareOf(s.actor)
            H.player:teleportTo(square:getX()+.5,square:getY()+.5,square:getZ())
            s.placeAt=current
            setPhase("needs_food_follow",current);return
        end
        if current-H.phaseStartedAt>45000 then return done(false,"needs_food_native_meal",
            "timeout hunger="..hunger.." reason="..tostring(why)) end
    elseif H.phase=="needs_food_follow" then
        if current-s.placeAt<500 then return end
        local accepted,why=SC.Commands.issue(SC.Registry.idOf(s.actor),"follow",nil,H.player)
        s.options={commands=SC.Commands.effective(s.actor)}
        if not check("needs_food_follow_command",accepted==true and s.options.commands.recruited==true
            and s.options.commands.order=="follow",tostring(why).." order="..tostring(s.options.commands.order)) then
            setPhase("finish",current);return
        end
        SC.Needs.reset(s.actor)
        s.actor:getStats():set(CharacterStat.HUNGER,.76)
        SC.Needs.routineAllowed(s.actor,H.player,s.options.commands,current)
        s.pauseAt=current;s.beforePause=U.characterStatValue(s.actor,"HUNGER",0)
        setPhase("needs_food_pause",current);return
    elseif H.phase=="needs_food_pause" then
        local handled,why=SC.Needs.update(s.actor,H.player,runtime,s.options)
        local active=select(1,SC.NativeActions.needsStatus(s.actor))
        local elapsed=current-s.pauseAt
        if elapsed<14500 and (active or U.characterStatValue(s.actor,"HUNGER",0)<s.beforePause-.01) then
            local _,kind=SC.NativeActions.needsStatus(s.actor)
            return done(false,"needs_food_pause","routine food began too soon at "..elapsed.."ms"
                .." hunger="..U.characterStatValue(s.actor,"HUNGER",0).." active="..tostring(active)
                .." kind="..tostring(kind).." order="..tostring(s.options.commands.order))
        end
        if active then
            result("PASS","needs_food_pause","native meal began after "..elapsed.."ms of standing still")
            local x,y,z=H.player:getX(),H.player:getY(),H.player:getZ()
            local destination
            for _,offset in ipairs({{2,0},{0,2},{-2,0},{0,-2}}) do
                local square=U.gridSquare(math.floor(x)+offset[1],math.floor(y)+offset[2],math.floor(z))
                if square and U.isSquareFree(square) then destination=square;break end
            end
            if not destination then return done(false,"needs_food_move_fixture","no free leader destination") end
            H.player:teleportTo(destination:getX()+.5,destination:getY()+.5,destination:getZ())
            -- Native teleportTo is applied on the next engine update.
            s.moveAt=current
            setPhase("needs_food_moving",current);return
        end
        if elapsed>22000 then return done(false,"needs_food_pause","meal did not begin: "..tostring(why)) end
    elseif H.phase=="needs_food_moving" then
        if current-s.moveAt<500 then return end
            local allowed=SC.Needs.routineAllowed(s.actor,H.player,s.options.commands,current)
            local cancelled,reason=SC.Needs.pauseRoutine(s.actor,"leader_moving",SC.Needs.assess(s.actor))
            if not check("needs_food_move_cancel",not allowed and cancelled==true
                and not select(1,SC.NativeActions.needsStatus(s.actor)),"allowed="..tostring(allowed)
                    .." cancelled="..tostring(cancelled).." active="
                    ..tostring(select(1,SC.NativeActions.needsStatus(s.actor))).." reason="..tostring(reason)) then
                setPhase("finish",current);return
            end
            s.cancelAt=current;s.afterCancel=U.characterStatValue(s.actor,"HUNGER",0)
            setPhase("needs_food_cancelled",current);return
    elseif H.phase=="needs_food_cancelled" then
        -- Keep moving the fixture leader a little so no fresh stop elapses.
        H.player:teleportTo(H.player:getX()+.02,H.player:getY(),H.player:getZ())
        SC.Needs.update(s.actor,H.player,runtime,s.options)
        if current-s.cancelAt>2000 then
            return done(U.characterStatValue(s.actor,"HUNGER",0)>=s.afterCancel-.001
                and call(s.normal,"getContainer")~=nil,"needs_food_no_replay",
                "cancelled meal did not consume food or change hunger afterward")
        end
    end
end
SCRealSandboxHarnessProbes=SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCNeedsPriorityProbe=Probe
return Probe
