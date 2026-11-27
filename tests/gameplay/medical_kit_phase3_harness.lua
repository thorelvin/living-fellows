-- SPDX-License-Identifier: MIT
-- Actual kit decisions, camp rows, permissions and exact inventory identities.
-- Only the native packing animation boundary is replaced in this Lua harness.
local SC=LivingFellows
local K,B,L,P,M=SC.MedicKit,SC.BaseLife,SC.Logistics,SC.MedicalProcedures,SC.Medical
local F,T,C=SC.TestMedicalMedicines,SC.TestFixture,SC.TestMedicalProcedures
local checks,transfers=0,0
local function check(value,why) checks=checks+1;assert(value,'Phase3 kit '..checks..': '..why) end
local nativeWork={}
SC.NativeActions={
    stopDirect=function() return true end,needsStatus=function() return false end,
    isWorkActive=function() return false end,workKind=function(actor) return nativeWork[actor] and 'medic_kit' end,
    startMedicKitTransfer=function(actor,item,source,destination,kit,validate)
        check(source~=destination and kit:getInventory()==destination,'native packing keeps exact source and kit destination')
        nativeWork[actor]={item=item,source=source,destination=destination,validate=validate};return true
    end,
    finishWork=function(actor)
        local work=nativeWork[actor];if not work then return false,'missing_fixture_work' end
        if not work.validate() then nativeWork[actor]=nil;return false,'native_pack_context_changed' end
        local okay,why=SC.WorkTransport.transferVerified(work.source,work.destination,work.item,actor)
        nativeWork[actor]=nil;if okay then transfers=transfers+1 end;return okay,why
    end,
    cancelWork=function(actor) nativeWork[actor]=nil;return true end,
}
local function item(kind,options) return F.item(kind,options or {}) end
local function kit()
    local value=item('Base.FirstAidKit');value.category='Container';value.nestedInventory=T.inventory({})
    function value.nestedInventory:getContainingItem() return value end
    return value
end
local function setup(role)
    check(SC.BaseWork.reset(),'prior actual camp work releases')
    B.reset();SC.MedicalSupplies.reset()
    for x=4,7 do for y=4,6 do T.cell:getGridSquare(x,y,0).objects={} end end
    check(B.create(T.cell:getGridSquare(5,5,0),'Phase3 kit stock'),'actual camp is created')
    local actor=F.actor({C.part({})},{})
    actor.square=T.cell:getGridSquare(5,5,0);actor.moodles[MoodleType.PAIN]=0
    SC.Commands.peek(actor).order='base_duty'
    check(B.assign(actor.id,role or 'medic',true),'actual resident receives selected camp role')
    return actor
end
local function shelf(category,items,offset)
    local square=T.cell:getGridSquare(5+(offset or 0),5,0)
    local source,object=T.containerObject(square,items)
    function object:getObjectIndex()
        for index,candidate in ipairs(self.square.objects) do if candidate==self then return index-1 end end
        return -1
    end
    local okay,row=B.registerStorage(object,category)
    check(okay and B.resolveContainer(row)==source,'actual '..category..' shelf resolves exact container')
    return source,row,object
end
local function audit(actor) return L.audit(actor) end
local function tick(actor)
    T.clock=T.clock+100
    return K.step(actor,audit(actor))
end
local function run(actor,predicate,limit)
    local why
    for index=1,limit or 180 do
        local okay;okay,why=tick(actor)
        local facts=K.view(actor,audit(actor))
        if predicate(facts,okay,why,index) then return facts,why,index end
    end
    error('kit fixture did not settle: '..tostring(why))
end
local function basic(actor,withNeedle)
    local root=actor:getInventory();local case=kit();root:AddItem(case)
    for _=1,2 do case:getInventory():AddItem(item('Base.Bandage')) end
    case:getInventory():AddItem(item('Base.Splint'))
    case:getInventory():AddItem(item('Base.Pills'))
    if withNeedle then case:getInventory():AddItem(item('Base.Needle'));case:getInventory():AddItem(item('Base.Thread',{uses=20}))
    else case:getInventory():AddItem(item('Base.SutureNeedle')) end
    return case
end
do
    local actor=setup();local case=kit()
    local bandage1,bandage2=item('Base.Bandage'),item('Base.Bandage')
    local splint,pills,suture,tweezers=item('Base.Splint'),item('Base.Pills'),item('Base.SutureNeedle'),item('Base.Tweezers')
    local wipes,antibiotic=item('Base.AlcoholWipes',{drainable=true,alcoholPower=4,uses=3}),item('Base.Antibiotics')
    local source,row=shelf('medical',{case,bandage1,bandage2,splint,pills,suture,tweezers,wipes,antibiotic})
    check(K.needsWork(actor,audit(actor)),'medic with empty pack requests the physical kit and minimum resources')
    local facts=run(actor,function(f) return f.kit and f.kitDressings==2 and f.kitSplints==1
        and f.painkillerItem and f.stitchingKit and f.tweezersItem and f.disinfectantItem and f.antibioticItem
        and not K.busy(actor) and not K.needsWork(actor,audit(actor)) end)
    check(facts.kit==case and facts.painkillerItem==pills and facts.sutureItem==suture and facts.tweezersItem==tweezers,
        'actual stocking preserves exact chosen resource identities')
    check(case:getModData().LF_MedicKitLoan.actorId==actor.id and case:getModData().LF_MedicKitLoan.storageId==row.id,
        'borrowed physical kit records its exact actor and source shelf')
    for _,supply in ipairs({bandage1,bandage2,splint,pills,suture,tweezers,wipes,antibiotic}) do
        check(supply:getContainer()==case:getInventory() or supply==antibiotic and supply:getContainer()==actor.inventory
            and K.retained(actor,supply),'native packing or exact retained carry keeps '..supply:getFullType())
        check(P.itemAllowed(actor,supply,false),'own medic loan permits procedure consumption of kit contents')
    end
    check(K.mayUseContents(actor,case),'own medic-kit ancestor is the single permitted loan exception')
    check(SC.MedicalMedicines.itemAllowed(actor,pills),'own borrowed kit permits native painkiller consumption')
    check(row.category=='medical' and L.itemCategory(case)=='container','stocking preserves shelf category and ordinary kit classification')
    check(B.assign(actor.id,'generalist',true),'role change uses actual camp assignment')
    check(not K.mayUseContents(actor,case),'former medic cannot use the kit loan exception')
    check(K.retained(actor,case) and K.needsWork(actor,audit(actor)),'former medic retains exact borrowed kit until return')
    run(actor,function(_,_,why) return why=='medic_kit_returned' end)
    check(source:contains(case) and case:getModData().LF_MedicKitLoan==nil,'existing loan return settles exact kit and marker on source shelf')
end
do
    local actor=setup();local case=basic(actor,true)
    local facts=K.view(actor,audit(actor))
    check(facts.dressings==2 and facts.kitDressings==2 and facts.stitchingKit and facts.needleItem and facts.threadItem,
        'two dressings and native reusable needle plus thread satisfy stitching minimum')
    local needle,thread=facts.needleItem,facts.threadItem
    check(K.retained(actor,needle,case:getInventory()) and K.retained(actor,thread,case:getInventory()),'medic retains exact reusable stitching kit')
    local ordinary=setup('generalist');ordinary.inventory:AddItem(item('Base.Needle'));ordinary.inventory:AddItem(item('Base.Thread',{uses=20}))
    local ordinaryFacts=K.view(ordinary,audit(ordinary))
    check(not K.needsWork(ordinary,audit(ordinary)) and not K.retained(ordinary,ordinaryFacts.needleItem),
        'generalist receives no medic-only needle or thread keep rule')
end
do
    local actor=setup();local case=basic(actor,false)
    local old=K.view(actor,audit(actor)).sutureItem;case:getInventory():Remove(old)
    local junk={};for index=1,90 do junk[index]=item('Base.Junk') end
    local needle=item('Base.Needle');junk[#junk+1]=needle
    local crafting,craftRow=shelf('crafting',junk)
    local thread=item('Base.Thread',{uses=20});local tools,toolRow=shelf('tools',{thread})
    local checksBefore=checks
    local facts,_,ticks=run(actor,function(f) return f.stitchingKit and f.needleItem==needle and f.threadItem==thread
        and needle:getContainer()==case:getInventory() and thread:getContainer()==case:getInventory() end)
    check(ticks>3 and facts.stitchingKit,'bounded suture-to-needle fallback continues beyond the first64 entries')
    check(not crafting:contains(needle) and not tools:contains(thread),'needle and thread withdraw from their exact permitted nonmedical shelves')
    check(craftRow.category=='crafting' and toolRow.category=='tools','medic-only wants never reassign sewing storage categories')
    check(checks>checksBefore,'native packing boundary ran for reusable alternative')
end
do
    local actor=setup();local case=basic(actor,false)
    local noMedical=item('Base.Tweezers');local medical=item('Base.Tweezers')
    local sourceA,rowA=shelf('tools',{noMedical})
    local sourceB,rowB=shelf('medical',{medical})
    run(actor,function(f) return f.tweezersItem~=nil end)
    check(K.view(actor,audit(actor)).tweezersItem==medical and sourceA:contains(noMedical),'medical shelf wins over ordinary tools when both hold exact valid tools')
    check(rowA.category=='tools' and rowB.category=='medical','source preference leaves all categories unchanged')
end
for _,mode in ipairs({'withdrawals','reserve','favorite','manual','loan','protected'}) do
    local actor=setup();local case=basic(actor,false);local tool=item('Base.Tweezers')
    local source,row=shelf('medical',{tool})
    if mode=='withdrawals' then row.withdrawals=false
    elseif mode=='reserve' then check(B.setReserve(row.id,'Base.Tweezers',1),'actual reserve is set')
    elseif mode=='favorite' then tool:setFavorite(true)
    elseif mode=='manual' then tool:getModData().SC_ManualEquipFor='player'
    elseif mode=='loan' then tool:getModData().SC_PlayerLoan='player'
    else tool.protected=true end
    local old=SC.PersonalItems.isProtected
    if mode=='protected' then SC.PersonalItems.isProtected=function(value,...) return value==tool or old(value,...) end end
    run(actor,function(_,_,why) return why=='medic_kit_ready' end)
    check(source:contains(tool) and K.view(actor,audit(actor)).tweezersItem==nil,'actual '..mode..' stock is never fetched')
    check(not K.needsWork(actor,audit(actor)),'missing optional tool uses bounded retry instead of monopolizing logistics')
    SC.PersonalItems.isProtected=old
end
do
    local actor=setup();local case=basic(actor,false)
    local _,why=run(actor,function(_,_,reason) return reason=='medic_kit_ready' end)
    check(why=='medic_kit_ready' and not K.needsWork(actor,audit(actor)),'missing optional tweezers/disinfectant/antibiotic probes cool down')
    T.clock=T.clock+179000
    check(not K.needsWork(actor,audit(actor)),'optional search stays asleep before three-minute retry')
    T.clock=T.clock+1100
    check(K.needsWork(actor,audit(actor)),'optional search resumes after three minutes')
    local part=C.part({isBleeding=true,scratchTime=8});actor.body.parts={part};F.refresh(actor)
    local okay=M.treat(actor,actor)
    check(okay and part:bandaged(),'missing optional tools never prevent urgent carried basic dressing')
end
do
    local actor=setup();local bandage=item('Base.Bandage');actor.inventory:AddItem(bandage)
    run(actor,function(_,_,why) return why=='medic_kit_unavailable' end)
    check(not K.needsWork(actor,audit(actor)),'no physical kit uses bounded supply retry')
    local part=C.part({isBleeding=true,scratchTime=8});actor.body.parts={part};F.refresh(actor)
    local okay=M.treat(actor,actor)
    check(okay and part:bandaged() and not actor.inventory:contains(bandage),'missing kit never blocks urgent own-pack dressing')
end
do
    local actor=setup();local case=basic(actor,false)
    local pills=K.view(actor,audit(actor)).painkillerItem
    case:getModData().LF_MedicKitLoan={actorId='someone-else',storageId='storage:other'}
    check(not K.mayUseContents(actor,case) and not P.itemAllowed(actor,pills,false)
        and not SC.MedicalMedicines.itemAllowed(actor,pills),'another actor kit loan never grants a consumption exception')
    case:getModData().LF_MedicKitLoan={actorId=actor.id,storageId='storage:own'}
    check(K.mayUseContents(actor,case) and SC.MedicalMedicines.itemAllowed(actor,pills),'exact own kit ancestor is eligible')
    case:getModData().SC_PlayerLoan='player'
    check(not SC.MedicalMedicines.itemAllowed(actor,pills),'own kit exception never swallows a distinct player-loan marker')
    case:getModData().SC_PlayerLoan=nil;case:setFavorite(true)
    check(not P.itemAllowed(actor,pills,false),'favorite kit ancestor remains protected despite own kit marker')
    case:setFavorite(false);actor:setPrimaryHandItem(case)
    local heldFacts=K.view(actor,audit(actor))
    check(heldFacts.kit==nil and heldFacts.painkillerItem==nil,'held physical kit is not selected as a usable resource ancestor')
    actor:setPrimaryHandItem(nil);pills:getModData().LF_MedicKitLoan={actorId=actor.id,storageId='storage:own'}
    check(not SC.MedicalMedicines.itemAllowed(actor,pills),'kit marker on the medicine itself is never an ancestor exception')
end
do
    local empty=item('Base.Thread',{uses=0});local broken=item('Base.Needle',{condition=0})
    check(not K.resourceMatches(empty,'thread') and not K.resourceMatches(broken,'needle'),'empty thread and broken reusable needle never satisfy stitching kit')
    local tagged=item('Other.FieldNeedle',{tags={SewingNeedle=true}})
    local spool=item('Other.ThreadSpool',{tags={Thread=true},uses=3})
    check(K.resourceMatches(tagged,'needle') and K.resourceMatches(spool,'thread'),'native sewing tags support compatible reusable alternatives')
    check(not K.resourceMatches(item('Base.Pills',{uses=0}),'painkiller'),'empty native painkiller stock never satisfies loadout')
end
do
    local actor=setup();basic(actor,false)
    local wipes=item('Base.AlcoholWipes',{drainable=true,alcoholPower=4,uses=3})
    local antibiotic=item('Base.Antibiotics');local source=shelf('medical',{wipes,antibiotic})
    local facts=run(actor,function(_,_,why) return why=='medic_kit_ready' end)
    check(facts.tweezersItem==nil and facts.disinfectantItem==wipes and facts.antibioticItem==antibiotic,
        'absent tweezers never starve later available disinfectant and antibiotic searches in the same probe')
    check(not source:contains(wipes) and not source:contains(antibiotic),'later optional resources withdraw before the shared cooldown')
    check(not K.needsWork(actor,audit(actor)),'all optional kinds share cooldown after the complete probe')
end
for _,kind in ipairs({'Base.Bandage','Base.Pills'}) do
    local actor=setup();local case=basic(actor,false)
    run(actor,function(_,_,why) return why=='medic_kit_ready' end)
    check(not K.needsWork(actor,audit(actor)),'optional-only scan is sleeping before required '..kind..' use')
    local consumed
    for _,record in ipairs(audit(actor).items) do if record.item:getFullType()==kind then consumed=record.item;break end end
    check(consumed~=nil,'required native-shaped stock exists before simulated use')
    consumed:getContainer():Remove(consumed)
    local replacement=item(kind);local source=shelf('medical',{replacement})
    check(K.needsWork(actor,audit(actor)),'optional cooldown cannot suppress a newly missing required '..kind)
    run(actor,function(f) return kind=='Base.Bandage' and f.dressings>=2 or kind=='Base.Pills' and f.painkillerItem==replacement end)
    check(not source:contains(replacement),'new required shortage refills from actual stock before optional retry expires')
end
for _,kind in ipairs({'Base.Pills','Base.SutureNeedle','Base.Needle','Base.Thread','Base.Tweezers'}) do
    for _,mode in ipairs({'favorite','manual','held'}) do
        local actor=setup();actor.inventory:AddItem(kit())
        local stock=item(kind,{uses=kind=='Base.Thread' and 20 or kind=='Base.Pills' and 10 or 1})
        actor.inventory:AddItem(stock)
        if mode=='favorite' then stock:setFavorite(true)
        elseif mode=='manual' then stock:getModData().SC_ManualEquipFor='player'
        else actor:setPrimaryHandItem(stock) end
        local purpose=({['Base.Pills']='painkiller',['Base.SutureNeedle']='suture',['Base.Needle']='needle',
            ['Base.Thread']='thread',['Base.Tweezers']='tweezers'})[kind]
        local facts=K.view(actor,audit(actor))
        check(facts[purpose..'Item']==nil and facts.retained[stock]==nil,
            'carried '..mode..' '..kind..' never satisfies a usable medic resource or exact keeper')
        check(not SC.MedicalMedicines.itemAllowed(actor,stock),'medical prepare also refuses carried '..mode..' '..kind)
    end
end
for _,mode in ipairs({'favorite','manual','held'}) do
    local actor=setup();local case=basic(actor,false)
    local stock=K.view(actor,audit(actor)).painkillerItem
    stock:getContainer():Remove(stock);actor.inventory:AddItem(stock)
    local okay,why=tick(actor)
    check(okay and why=='medic_kit_packing' and nativeWork[actor]~=nil,'native packing starts before late '..mode..' supply change')
    local before=transfers
    if mode=='favorite' then stock:setFavorite(true)
    elseif mode=='manual' then stock:getModData().SC_ManualEquipFor='player'
    else actor:setPrimaryHandItem(stock) end
    tick(actor)
    check(transfers==before and stock:getContainer()==actor.inventory and not case:getInventory():contains(stock),
        'late '..mode..' carried medicine is refused at native packing commit without transfer')
    check(K.cancel(actor,'late_protected_fixture_cleanup'),'late-protected native packing owner cancels cleanly')
end
SC_TEST_REPORT='MEDICAL_KIT_PHASE3_PASS checks='..checks..' native_fixture_transfers='..transfers
print(SC_TEST_REPORT)
