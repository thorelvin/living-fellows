-- SPDX-License-Identifier: MIT
-- One cloned-save run: real materials, water, native actions and downtime cleanup.
local P = {}
SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCNativeCareProbe = P
local function call(object, method, ...)
    if not object then return nil end
    local okay, value = pcall(function(...) return object[method](object, ...) end, ...)
    if okay then return value end
end
local function photo(H, label)
    pcall(function()
        for _ = 1, 8 do if getCore():getZoom(0) < 1.8 then getCore():doZoomScroll(0, 1) end end
        getCore():TakeFullScreenshot(H.config.run_id .. "-native-care-" .. label .. ".png")
    end)
end
local function finish(H, current, setPhase)
    if H.nativeCare and H.nativeCare.decision then SurvivorCompanion.Decision.update = H.nativeCare.decision end
    setPhase("finish", current)
end
local function fail(H, current, check, setPhase, label, reason)
    photo(H, "blocked-" .. label); check(label, false, tostring(reason)); finish(H, current, setPhase)
end
local function sourceNear(H, actor)
    local U = SurvivorCompanion.GameplayUtil
    local center = H.player:getCurrentSquare()
    for radius = 0, 16 do
        for dx = -radius, radius do for dy = -radius, radius do
            if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                local square = U.gridSquare(center:getX()+dx, center:getY()+dy, center:getZ())
                local found
                if square then U.squareObjects(square, function(object)
                    if (tonumber(call(object, "getFluidAmount")) or 0) < 80 or call(object, "isTaintedWater") == true then return true end
                    local _, access = U.directInteractionAccess(actor, object)
                    for _, side in ipairs(access or {}) do
                        if U.isSquareFree(side) and not U.squareOccupyingObject(side) then
                            found = { source = object, square = side }; return false
                        end
                    end
                    return true
                end, 24) end
                if found then return found end
            end
        end end
    end
end
local function setupStep(f)
    local SC, actor = SurvivorCompanion, f.actor
    local inventory, C = actor:getInventory(), SC.NativeCareActions
    local function add(kind) return assert(inventory:AddItem(kind), kind .. " not found") end
    if f.step == 1 then
        f.pan, f.tape = add("Base.Axe"), add("Base.DuctTape")
        f.adhesive = add("Base.Scotchtape")
        f.pan:setCondition(math.max(1, math.floor(f.pan:getConditionMax() * 0.2)))
        local activity = assert(C.repairCandidate(actor, { f.pan, f.tape, f.adhesive }), "native axe repair requirements not satisfied")
        f.material = activity.materials[1]
        f.uses = call(f.material, "getCurrentUses")
        return activity
    elseif f.step == 2 then
        f.bag = add("Base.Bag_Schoolbag")
        f.dirty = f.bag:getInventory():AddItem("Base.BandageDirty")
        return { kind="wash_bandage", item=f.dirty, itemContainer=f.bag:getInventory(),
            object=f.source, square=f.square, cleanType="Base.Bandage", fact={activity="wash_bandage"} }
    elseif f.step == 3 then
        f.soap = add("Base.Soap2")
        local visual = actor:getHumanVisual()
        for i=0,BloodBodyPartType.MAX:index()-1 do
            local part=BloodBodyPartType.FromIndex(i); visual:setBlood(part,0); visual:setDirt(part,0)
        end
        f.part=BloodBodyPartType.FromIndex(5); visual:setBlood(f.part,0.5); visual:setDirt(f.part,0.5)
        return {kind="wash_self",object=f.source,square=f.square,fact={activity="wash_self"}}
    elseif f.step == 4 then
        f.shirt = add("Base.Shirt_FormalWhite")
        local parts=BloodClothingType.getCoveredParts(f.shirt:getBloodClothingType())
        f.clothPart=assert(parts:get(0)); f.shirt:setBlood(f.clothPart,0.5); f.shirt:setDirt(f.clothPart,0.5)
        f.shirt:setDirtiness(20)
        return {kind="wash_equipment",item=f.shirt,object=f.source,square=f.square,fact={activity="wash_equipment"}}
    elseif f.step == 5 then
        f.rag,f.wood=add("Base.RippedSheets"),add("Base.TreeBranch2")
        return assert(C.craftCandidate(actor,{f.rag,f.wood}),"native splint candidate missing")
    elseif f.step == 6 then
        f.sheet=add("Base.Sheet")
        return assert(C.craftCandidate(actor,{f.sheet}),"native sheet-rope candidate missing")
    end
end
function P.step(H,current,check,result,setPhase)
    local SC = SurvivorCompanion
    local U, D = SC.GameplayUtil, SC.Downtime
    local f = H.nativeCare
    if not f then
        local record
        for _, row in ipairs(SC.Registry.snapshot()) do if row.actor and row.recruited and not U.isDead(row.actor) then record=row; break end end
        if not record and current-H.phaseStartedAt<12000 then return end
        if not record then return fail(H,current,check,setPhase,"care_worker","no loaded recruited companion") end
        local site=sourceNear(H,record.actor)
        if not site then return fail(H,current,check,setPhase,"care_water_source","no loaded clean tap with 80 native water units") end
        f={actor=record.actor,id=record.id,source=site.source,square=site.square,step=1,lastAt=0,startedAt=current}
        H.nativeCare=f
        D.cancel(f.actor,"native_care_probe"); SC.BaseWork.cancel(f.actor,"native_care_probe")
        SC.Navigation.cancel(f.actor,"native_care_probe")
        SC.Commands.issue(f.id,"stay",site.square,H.player)
        if not H.placeCombatActor(f.actor,{x=site.square:getX()+0.5,y=site.square:getY()+0.5,z=site.square:getZ()}) then
            return fail(H,current,check,setPhase,"care_actor_position","placement failed")
        end
        f.actor:getStats():set(CharacterStat.FATIGUE,0.1)
        f.actor:getStats():set(CharacterStat.ENDURANCE,1)
        getGameTime():setTimeOfDay(12)
        f.decision=SC.Decision.update
        SC.Decision.update=function() return true,"native_care_fixture_owned" end
        f.begin=select(4,D._furnitureForTests())
        local stateFor=select(12,D._furnitureForTests())
        stateFor(f.actor)
        if SC.UI.instance then SC.UI.instance:setVisible(false) end
        getPlayerInventory(0):setVisible(false); getPlayerLoot(0):setVisible(false)
        check("care_real_source",true,"real loaded water fixture; unrelated decisions held in the disposable clone")
        setPhase("native_care_work",current)
        return
    end
    if current-f.lastAt<100 then return end
    f.lastAt=current
    if f.finishedAt then
        if current-f.finishedAt>1000 then photo(H,"finished"); finish(H,current,setPhase) end
        return
    end
    if not f.activity then
        local okay, activity=pcall(setupStep,f)
        if not okay or not activity then return fail(H,current,check,setPhase,"care_step_"..f.step,activity) end
        f.activity=activity; f.stepAt=current; f.water=f.source:getFluidAmount(); f.photo=false
        local started,why=f.begin(f.actor,D.peek(f.actor),activity,SC.Commands.peek(f.actor),current)
        if not started then return fail(H,current,check,setPhase,"care_start_"..f.step,why) end
        return
    end
    local okay,why=D.update(f.actor,H.player,{snapshot={immediateCount=0,pressure=0,zombies={}}},f.activity.kind)
    if not f.photo and current-f.stepAt>700 and SC.NativeActions.ownsDowntimeAction(f.actor,f.activity) then
        f.photo=true; photo(H,tostring(f.step).."-"..f.activity.kind)
    end
    if current-f.stepAt>120000 then return fail(H,current,check,setPhase,"care_timeout_"..f.step,why) end
    local active=D.peek(f.actor)
    if active and active.active then return end
    local a=f.activity
    if a.nativeCompleted~=true or a.nativeSettled~=true then
        print("SC_CARE_EFFECT_TRACE|step="..f.step.."|attempt="..tostring(a.nativeAttempted).."|completed="..tostring(a.nativeCompleted)
            .."|reason="..tostring(a.nativeFailure).."|cancel="..tostring(a.cancelRequestedReason)
            .."|dark="..tostring(f.actor:tooDarkToRead()).."|out="..tostring(a.nativeOutput))
        return fail(H,current,check,setPhase,"care_effect_"..f.step,why)
    end
    check("care_native_"..f.step,true,a.kind.." completed through stock timed action and downtime release")
    local nativeWork=SC.NativeActions.workKind(f.actor)
    check("care_release_"..f.step,nativeWork==nil,"no retained native work after completion")
    if f.step==1 then
        check("care_native_repair_uses",not U.inventoryContains(f.actor:getInventory(),f.material)
            or (tonumber(call(f.material,"getCurrentUses")) or 0)<(tonumber(f.uses) or 0),"real repair consumables spent by the native repair recipe/action; failed repair rolls allowed")
    elseif f.step==2 then
        check("care_bandage_bag",a.nativeOutput and f.bag:getInventory():contains(a.nativeOutput)
            and not f.bag:getInventory():contains(f.dirty),"native replacement returned to the exact original bag")
        check("care_bandage_water",f.source:getFluidAmount()<=f.water,
            "native source before="..tostring(f.water).." after="..tostring(f.source:getFluidAmount()).."; municipal supply may retain its displayed level")
    elseif f.step==3 then
        check("care_self_clean",f.actor:getHumanVisual():getBlood(f.part)==0
            and f.actor:getHumanVisual():getDirt(f.part)==0,"real actor visual cleaned by ISWashYourself")
    elseif f.step==4 then
        check("care_clothing_clean",f.shirt:getBlood(f.clothPart)==0 and f.shirt:getDirt(f.clothPart)==0
            and f.shirt:getWetness()>0,"native clothing wash clears stains and wets the same shirt")
    else
        check("care_craft_output_"..f.step,a.nativeOutput and a.nativeOutput:getFullType()==a.outputType,
            "native recipe output identity recorded")
        check("care_craft_consumed_"..f.step,not U.inventoryContains(f.actor:getInventory(),a.scraps[1]),"exact native ingredient consumed")
    end
    if f.step==6 then
        check("care_worker_alive",f.actor:getHealth()>0 and not f.actor:isDead(),"ordinary living worker")
        result("PASS","native_care_live_complete","repair, bagged bandage, body wash, clothing wash, splint and sheet rope")
        f.finishedAt=current
    else f.step=f.step+1; f.activity=nil end
end
return P
