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
    if H.nativeCare and H.nativeCare.logisticsStatus then SurvivorCompanion.Logistics.status = H.nativeCare.logisticsStatus end
    if H.config.hygiene_probe == "true" and H.nativeCare and H.nativeCare.finishedAt and not H.nativeCare.failed then
        setPhase("hygiene_setup", current)
        return
    end
    setPhase("finish", current)
end
local function fail(H, current, check, setPhase, label, reason)
    if H.nativeCare then H.nativeCare.failed=true end
    photo(H, "blocked-" .. label); check(label, false, tostring(reason)); finish(H, current, setPhase)
end
local function sourceNear(H, actor, predicate)
    local U = SurvivorCompanion.GameplayUtil
    local center = H.player:getCurrentSquare()
    for radius = 0, 16 do
        for dx = -radius, radius do for dy = -radius, radius do
            if radius == 0 or math.abs(dx) == radius or math.abs(dy) == radius then
                local square = U.gridSquare(center:getX()+dx, center:getY()+dy, center:getZ())
                local found
                if square then U.squareObjects(square, function(object)
                    if predicate and not predicate(object) then return true end
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
local function setupStep(f,H)
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
    elseif f.step == 7 then
        f.towel=f.bag:getInventory():AddItem("Base.BathTowel")
        f.towel:setCurrentUses(2)
        actor:getBodyDamage():increaseBodyWetness(80)
        f.wetness=actor:getStats():get(CharacterStat.WETNESS)
        f.playerWetness=SurvivorCompanion.GameplayUtil.characterStatValue(getSpecificPlayer(0),"WETNESS",0)
        return {kind="weather_recovery",item=f.towel,square=actor:getCurrentSquare(),fact={activity="weather_recovery"}}
    elseif f.step>=10 then
        local site=assert(sourceNear(H,actor,function(object)
            local properties=call(call(object,"getSprite"),"getProperties")
            return string.find(string.lower(tostring(call(properties,"get","CustomName") or "")),"shower",1,true)~=nil
        end),"no real loaded shower with water and clear access")
        f.source,f.square=site.source,site.square
        assert(H.placeCombatActor(actor,{x=site.square:getX()+0.5,y=site.square:getY()+0.5,z=site.square:getZ()}))
        local room=site.source:getSquare():getRoom()
        local watched=false
        for dx=-2,2 do for dy=-2,2 do
            local side=SC.GameplayUtil.gridSquare(site.square:getX()+dx,site.square:getY()+dy,site.square:getZ())
            if not watched and side and side~=site.square and side~=site.source:getSquare() and side:getRoom()==room
                and math.max(math.abs(side:getX()-site.source:getX()),math.abs(side:getY()-site.source:getY()))>=2
                and SC.GameplayUtil.isSquareFree(side) and not SC.GameplayUtil.squareOccupyingObject(side) then
                H.player:teleportTo(side:getX()+0.5,side:getY()+0.5,side:getZ()); watched=true
            end
        end end
        SC.Commands.issue(f.id,"stay",site.square,H.player)
        f.outfit,f.playerOutfit={},{}
        for _,pair in ipairs({{actor,f.outfit},{H.player,f.playerOutfit}}) do
            local worn=pair[1]:getWornItems()
            for i=0,worn:size()-1 do local entry=worn:get(i)
                pair[2][#pair[2]+1]={item=entry:getItem(),location=entry:getLocation()}
            end
        end
        f.primary=actor:getPrimaryHandItem(); f.secondary=actor:getSecondaryHandItem()
        local visual=actor:getHumanVisual()
        for i=0,BloodBodyPartType.MAX:index()-1 do
            local part=BloodBodyPartType.FromIndex(i); visual:setBlood(part,0.5); visual:setDirt(part,0.5)
        end
        f.showerPhotos={}; f.interruptRequested=nil; f.showerSnapshot=nil
        return {kind="shower",object=f.source,square=f.square,fact={activity="shower"}}
    end
end
local function clothingStep(H,f,current,check,result,setPhase)
    local SC, actor=SurvivorCompanion,f.actor
    if not f.wearItem then
        local kind=f.step==8 and "Base.Shirt_FormalWhite" or "Base.Bag_ALICEpack"
        f.wearItem=assert(f.bag:getInventory():AddItem(kind))
        f.wearSlot=f.step==8 and f.wearItem:getBodyLocation() or f.wearItem:canBeEquipped()
        f.playerWear=H.player:getWornItem(f.wearSlot)
        f.logisticsStatus=SC.Logistics.status
        -- Control only candidate selection. Real logistics owns the timed
        -- action, item staging, slot replacement, verification and cleanup.
        SC.Logistics.status=function(who)
            if who~=actor then return f.logisticsStatus(who) end
            local row={item=f.wearItem,source=f.bag:getInventory(),location=f.wearSlot}
            return f.step==8 and {clothingUpgrade=row} or {bagUpgrade=row}
        end
        f.stepAt=current; f.photo=false
    end
    local okay,why=SC.Logistics.update(actor,H.player,{snapshot={threatCount=0,immediateCount=0,pressure=0}})
    if not f.photo and SC.NativeActions.visualToken(actor,"wear_clothing") then
        f.photo=true; photo(H,"wear-"..f.step)
        check("care_stock_wear_"..f.step,SC.NativeActions.visualToken(actor,"wear_clothing").Type=="ISWearClothing","stock clothing action on the companion")
    end
    if current-f.stepAt>30000 then return fail(H,current,check,setPhase,"care_wear_timeout_"..f.step,why) end
    if actor:getWornItem(f.wearSlot)~=f.wearItem then return end
    check("care_wear_"..f.step,not SC.Logistics.busy(actor) and f.wearItem:getContainer()==actor:getInventory(),"exact bagged item equipped and transaction released")
    check("care_player_wardrobe_"..f.step,H.player:getWornItem(f.wearSlot)==f.playerWear,"main player's worn slot unchanged")
    SC.Logistics.status=f.logisticsStatus; f.logisticsStatus=nil; f.wearItem=nil
    f.step=f.step+1
end
local function outfitMatches(who,rows)
    for _,row in ipairs(rows) do if who:getWornItem(row.location)~=row.item then return false end end
    return true
end
local function savedOutfitMatches(saved,rows)
    if not saved or not saved.inventory then return false end
    local ids={}
    local function visit(nodes)
        for _,node in ipairs(nodes or {}) do ids[node.nativeId]=node.id; visit(node.children) end
    end
    visit(saved.inventory.roots)
    for _,row in ipairs(rows) do
        local id=ids[row.item:getID()]; local found=false
        for _,entry in ipairs(saved.inventory.equipment.worn) do
            if entry.id==id and entry.location==tostring(row.location) then found=true; break end
        end
        if not found then return false end
    end
    return true
end
local function cancelledShower(H,f,current,check,result,setPhase)
    local SC=SurvivorCompanion
    if current-f.interruptAt>15000 then return fail(H,current,check,setPhase,"care_shower_cancel_timeout_"..f.step,"native action or clothing rollback still owned") end
    if SC.Downtime.peek(f.actor).active then SC.Downtime.cancel(f.actor,"live_shower_interruption"); return end
    check("care_shower_interrupted_"..f.step,not f.activity.nativeCompleted and not f.activity.showerClothes,"interrupted shower ended without replaying a washing effect")
    check("care_shower_outfit_"..f.step,outfitMatches(f.actor,f.outfit),"exact original outfit and bags restored after interruption")
    check("care_shower_hands_"..f.step,f.actor:getPrimaryHandItem()==f.primary and f.actor:getSecondaryHandItem()==f.secondary,"original held gear restored")
    check("care_shower_player_"..f.step,outfitMatches(H.player,f.playerOutfit),"player wardrobe unchanged")
    check("care_shower_release_"..f.step,SC.NativeActions.workKind(f.actor)==nil and SC.NativeActions.visualToken(f.actor)==nil,"no native action or inventory owner retained")
    photo(H,"interruption-restored-"..f.step)
    if f.step==12 then
        check("care_worker_alive",f.actor:getHealth()>0 and not f.actor:isDead(),"ordinary living worker")
        result("PASS","native_care_live_complete","native washing, drying, wardrobe, shower and both interruption paths")
        f.finishedAt=current
    else f.step=f.step+1; f.activity=nil end
end
function P.step(H,current,check,result,setPhase)
    if not H.nativeCareZoom then
        H.nativeCareZoom=true
        for _=1,8 do if getCore():getZoom(0)<1.8 then getCore():doZoomScroll(0,1) end end
    end
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
        f={actor=record.actor,id=record.id,source=site.source,square=site.square,step=1,lastAt=0,startedAt=current,
            observerHome={x=H.player:getX(),y=H.player:getY(),z=H.player:getZ()}}
        H.nativeCare=f
        local survey=sourceNear(H,record.actor,function(object)
            return tostring(call(call(call(object,"getSprite"),"getProperties"),"get","CustomName")):lower():find("shower",1,true)~=nil
        end)
        if survey then
            local object=survey.source; local square=object:getSquare()
            local props=object:getSprite():getProperties(); local names=call(props,"getPropertyNames")
            local values={}
            for i=0,math.min(80,SC.NativeList.size(names))-1 do
                local key=SC.NativeList.get(names,i); values[#values+1]=tostring(key).."="..tostring(call(props,"get",key))
            end
            print("SC_SHOWER_FIXTURE|sprite="..tostring(object:getSprite():getName()).."|at="..square:getX()..","..square:getY()
                .."|access="..survey.square:getX()..","..survey.square:getY().."|free="..tostring(square:isFree(true))
                .."|solid="..tostring(square:isSolid()).."|trans="..tostring(square:isSolidTrans()).."|props="..table.concat(values,","))
        end
        D.cancel(f.actor,"native_care_probe"); SC.BaseWork.cancel(f.actor,"native_care_probe")
        SC.Navigation.cancel(f.actor,"native_care_probe")
        SC.Commands.issue(f.id,"stay",site.square,H.player)
        if not H.placeCombatActor(f.actor,{x=site.square:getX()+0.5,y=site.square:getY()+0.5,z=site.square:getZ()}) then
            return fail(H,current,check,setPhase,"care_actor_position","placement failed")
        end
        f.actor:getStats():set(CharacterStat.FATIGUE,0.1)
        f.actor:getStats():set(CharacterStat.ENDURANCE,1)
        H.clearZombiesNear(H.player,80)
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
        if not f.resumeAt then
            H.player:teleportTo(f.observerHome.x,f.observerHome.y,f.observerHome.z)
            f.resumeAt=current; f.resumeRoom=f.actor:getCurrentSquare():getRoom()
        end
        local root=U.actorState(f.actor)
        root.senses={current={threats={},threatCount=0,immediateCount=0,pressure=0,player={danger=0}}}
        local handled,why=f.decision(f.actor,H.player,root,current)
        if f.actor:getCurrentSquare():getRoom()~=f.resumeRoom then
            check("care_shower_follow_resumed",not f.actor:isDead(),"real Follow left the bathroom after clothing restoration")
            photo(H,"finished"); finish(H,current,setPhase)
        elseif current-f.resumeAt>30000 then
            fail(H,current,check,setPhase,"care_shower_follow_timeout",tostring(handled)..":"..tostring(why))
        end
        return
    end
    if f.step==8 or f.step==9 then return clothingStep(H,f,current,check,result,setPhase) end
    if not f.activity then
        local okay, activity=pcall(setupStep,f,H)
        if not okay or not activity then return fail(H,current,check,setPhase,"care_step_"..f.step,activity) end
        f.activity=activity; f.stepAt=current; f.water=f.source:getFluidAmount(); f.photo=false
        local started,why=f.begin(f.actor,D.peek(f.actor),activity,SC.Commands.peek(f.actor),current)
        if not started then return fail(H,current,check,setPhase,"care_start_"..f.step,why) end
        return
    end
    if f.interruptRequested then return cancelledShower(H,f,current,check,result,setPhase) end
    local okay,why=D.update(f.actor,H.player,{snapshot={immediateCount=0,pressure=0,zombies={}}},f.activity.kind)
    if f.step>=10 then
        local stage=f.activity.showerPhase
        if stage and not f.showerPhotos[stage] then f.showerPhotos[stage]=true; photo(H,stage.."-"..f.step) end
        if f.step==10 and stage=="washing" and not f.showerSnapshot then
            check("care_shower_inside_fixture",U.sameSquare(f.actor,f.source:getSquare()),
                "the companion physically entered the real shower tile before washing")
            local saved,reason=SC.Persistence.captureRecord(SC.Registry.byId(f.id),nil,{preserveNativeIds=true})
            check("care_shower_save_outfit",savedOutfitMatches(saved,f.outfit),"snapshot references the real inventory item identities in their original worn slots: "..tostring(reason))
            check("care_shower_save_continues",D.peek(f.actor).active==f.activity and not f.activity.cancelRequestedReason,"capturing does not cancel the active shower")
            f.showerSnapshot=true
        end
        local unequipped=false
        for _,row in ipairs(f.outfit) do if not f.actor:isEquippedClothing(row.item) then unequipped=true; break end end
        if f.step==11 and stage=="washing" and SC.NativeActions.isWorkActive(f.actor) then
            f.interruptRequested=true; f.interruptAt=current; photo(H,"combat-interruption")
            D.update(f.actor,H.player,{snapshot={immediateCount=1,threatCount=1,pressure=2,zombies={}}},"shower")
            check("care_shower_combat_cancel",f.activity.cancelRequestedReason=="danger_or_order","danger handling requested cancellation")
            return
        elseif f.step==12 and stage=="undressing" and unequipped then
            f.interruptRequested=true; f.interruptAt=current; photo(H,"order-interruption")
            SC.Commands.issue(f.id,"follow",nil,H.player)
            check("care_shower_follow_order",SC.Commands.peek(f.actor).order=="follow","new Follow order accepted during undressing")
            return
        end
    end
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
    elseif f.step<=6 then
        check("care_craft_output_"..f.step,a.nativeOutput and a.nativeOutput:getFullType()==a.outputType,
            "native recipe output identity recorded")
        check("care_craft_consumed_"..f.step,not U.inventoryContains(f.actor:getInventory(),a.scraps[1]),"exact native ingredient consumed")
    elseif f.step==7 then
        check("care_native_drying",(a.nativeDrySteps or 0)>0 and f.actor:getStats():get(CharacterStat.WETNESS)<f.wetness,
            "stock incremental drying reduces the companion's real wetness")
        check("care_wet_towel_bag",a.nativeOutput and a.nativeOutput:getFullType()=="Base.BathTowelWet"
            and a.nativeOutput:getContainer()==f.bag:getInventory(),"real wet towel replacement returned to the original bag")
        check("care_player_wetness",H.player:getStats():get(CharacterStat.WETNESS)<=f.playerWetness+0.01,"no wetness transferred to player")
    elseif f.step==10 then
        check("care_shower_clean",f.actor:getHumanVisual():getBlood(f.part)==0 and f.actor:getHumanVisual():getDirt(f.part)==0,"stock body wash cleaned the actor in a real shower")
        check("care_shower_dressed",not a.showerClothes and outfitMatches(f.actor,f.outfit),"native dressing restored every original worn item and bag")
        check("care_shower_player",outfitMatches(H.player,f.playerOutfit),"player wardrobe unchanged")
    end
    f.step=f.step+1; f.activity=nil
end
return P
