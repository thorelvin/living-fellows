-- SPDX-License-Identifier: MIT
-- Real needs selection and camp transfers; only engine objects/actions are fixtures.
local SC,checks=SurvivorCompanion,0
local function check(value,message) checks=checks+1;assert(value,message) end
local now,scans,transfers,cancels,routes=1000,0,0,0,0
local atHome=true
local floorTransit=true
local cells,rows,roots,commands={}, {}, {}, {}
local action,active,token
local function key(x,y,z) return math.floor(x)..":"..math.floor(y)..":"..math.floor(z or 0) end
local function square(x,y,z)
    local value={x=x,y=y,z=z or 0,objects={}}
    cells[key(x,y,z)]=value;return value
end
local function pos(value) value=value and (value.square or value);if value then return value.x,value.y,value.z end end
local function distance(a,b)
    local ax,ay,az=pos(a);local bx,by,bz=pos(b)
    return ax and bx and math.sqrt((ax-bx)^2+(ay-by)^2+(az-bz)^2) or math.huge
end
local function inventory(items)
    local c={items=items or {}}
    function c:getItems() return self.items end
    for _,item in ipairs(c.items) do item.container=c end
    return c
end
local function actor(x,y,z)
    local a={square=square(x,y,z),inventory=inventory(),values={HUNGER=.76,THIRST=.2,FATIGUE=.2}}
    function a:getVehicle() return self.vehicle end
    function a:isMoving() return self.moving==true end
    roots[a]={};return a
end
local function food(kind)
    local f={kind=kind}
    function f:getHungerChange() return -.3 end
    function f:isFresh() return true end
    function f:getOffAge() return self.kind=="fresh" and 5 or 1000000000 end
    function f:getFoodType() return self.kind=="bait" and "Insect" or "Food" end
    function f:isSpice() return self.kind=="sauce" end
    function f:isRotten() return self.rotten==true end
    function f:getFullType() return "Test."..self.kind end
    return f
end
local function storage(x,y,z,items)
    local object={square=square(x,y,z)}
    local c=inventory(items)
    function c:getParent() return object end
    function object:getContainer() return c end
    object.square.objects={object}
    local row={x=x,y=y,z=z or 0,category="food",container=c}
    rows[#rows+1]=row
    return row,object
end
function getGameTime() return nil end
Fluid={Water="Water",TaintedWater="TaintedWater"}
local function water()
    local f={getAmount=function() return .5 end,getCapacity=function() return 1 end,
        isEmpty=function() return false end,isTainted=function() return false end,
        isPoisonous=function() return false end,canPlayerEmpty=function() return true end,
        contains=function(_,fluid) return fluid==Fluid.Water end}
    return {getFluidContainer=function() return f end}
end
SC.Commands={effective=function(a) return commands[a] or {} end}
SC.PersonalItems={isProtected=function(item) return item.protected==true end}
SC.CleaningSupplies={containsCleaner=function(item) return item.cleaner==true end}
SC.BaseLife={
    isInside=function() return atHome end,
    allowsFloorTransit=function() return floorTransit end,
    storageRows=function(_,withdrawals)
        local result={}
        for _,row in ipairs(rows) do
            if not withdrawals or row.withdrawals~=false and row.category~="memorial" then result[#result+1]=row end
        end
        return result
    end,
    resolveContainer=function(row) return row.container end,
    availableCount=function(row) return row.reserved and 0 or 1 end,
}
SC.GameplayUtil={
    config=function() return nil end, nowMs=function() return now end,
    position=pos,distance=distance,
    sameFloor=function(a,b) local _,_,az=pos(a);local _,_,bz=pos(b);return az==bz end,
    squareOf=function(value) return value and (value.square or value.x and value) end,
    actorState=function(a,runtime) return runtime or roots[a] end,
    peekActorState=function(a) return roots[a] end,
    characterStatValue=function(a,stat) return a.values[stat] end,
    isValidActor=function() return true end,
    call=function(value,method,...)
        if value and type(value[method])=="function" then return value[method](value,...),true end
        return nil,false
    end,
    each=function(items,limit,callback,offset)
        for i=(offset or 0)+1,math.min(#items,(offset or 0)+limit) do
            if callback(items[i])==false then break end
        end
    end,
    listSize=function(items) return #items end,
    inventory=function(a) return a.inventory end,
    inventoryContains=function(c,item) for _,v in ipairs(c.items) do if v==item then return true end end;return false end,
    itemType=function(item) return item.kind or "unknown" end,
    instanceOf=function() return false end,
    hasMethod=function(value,method) return value and type(value[method])=="function" end,
    itemWeight=function() return 1 end,
    stop=function() return true end,
    modData=function(value) value.data=value.data or {};return value.data end,
    gridSquare=function(x,y,z) scans=scans+1;return cells[key(x,y,z)] end,
    squareObjects=function(s,callback) for _,o in ipairs(s.objects) do callback(o) end end,
    directInteractionAccess=function(_,object)
        if object.blocked then return false,{},"no_interaction_targets" end
        if object.approach then return false,{object.square},"approach" end
        return true,{},"arrived"
    end,
    transferItemVerified=function(from,to,item)
        for i,v in ipairs(from.items) do if v==item then
            table.remove(from.items,i);to.items[#to.items+1]=item;item.container=to
            transfers=transfers+1;return true
        end end
        return false,"missing"
    end,
    clamp=function(v,lo,hi) return math.max(lo,math.min(hi,v)) end,
    move=function(a,_,intent)
        if intent.action=="eat_food" or intent.action=="drink_item" or intent.action=="drink_source" then action={actor=a,intent=intent};active=true end
        return true,intent.action
    end,
}
SC.Navigation={cancel=function() routes=routes+1 end,requestAny=function() return true,"approaching" end}
SC.NativeActions={
    needsStatus=function() return active==true,active~=nil and "eat" or nil end,
    finishNeeds=function() active=nil end,
    cancelNeeds=function() cancels=cancels+1;active=nil;return true end,
}
SC.ActionSupervisor={current=function() return token end}
local N=SC.Needs
local fresh,normal,bait,sauce=food("fresh"),food("normal"),food("bait"),food("sauce")
check(N.foodTier(fresh)==1 and N.foodTier(normal)==2,"perishables precede shelf-stable native isFresh food")
check(N.foodTier(bait)==3 and N.foodTier(sauce)==3,"insect metadata and Spice flag are emergency food")
fresh.rotten=true;check(N.foodTier(fresh)==nil,"unsafe fresh food is never eligible");fresh.rotten=nil
local a,player=actor(10,10,0),actor(10,10,0)
local function reset()
    N.cancel(a);N.reset(a);SC.Encounter.cancelPlayerSupply(a)
    action,active,token=nil,nil,nil;rows={};cells={};roots[a]={};commands[a]={recruited=true,order="base_duty"}
    a.inventory=inventory();a.values={HUNGER=.76,THIRST=.2,FATIGUE=.2};a.vehicle=nil
    atHome,floorTransit=true,true
    player.square=square(10,10,0);a.square=square(10,10,0);player.moving=false;player.vehicle=nil
    player.moving=true;N.routineAllowed(a,player,{recruited=true,order="follow"},now);player.moving=false
end
local function update(options) return N.update(a,player,roots[a],options) end
local function tick(count,options) for i=1,count do now=now+100;update(options) end end
reset()
a.values.HUNGER=.699;check(not N.assess(a).hungry,"routine meals wait until 70 percent hunger")
a.values.HUNGER=.70;check(N.assess(a).hungry,"70 percent hunger admits a meal before starvation")
reset();a.inventory=inventory({sauce,bait,normal})
local fridge=storage(13,10,0,{fresh})
tick(2)
check(action and action.intent.item==fresh and transfers==1,"fridge food beats carried canned food, sauce and maggots")
check(normal.container==a.inventory and bait.container==a.inventory,"lower priority supplies keep exact ownership")
reset();a.inventory=inventory({sauce,bait,normal})
local junk={};for i=1,300 do junk[i]={} end;junk[300]=fresh
storage(13,10,0,junk)
update();check(action==nil,"an unfinished storage slice does not permit a carried inferior meal")
tick(5);check(action and action.intent.item==fresh,"fresh food beyond the first storage slice is found")
reset();a.inventory=inventory({sauce,bait});storage(13,10,0,{normal});tick(4)
check(action and action.intent.item==normal,"stored normal food beats owned emergency food")
reset();a.inventory=inventory({sauce,bait});tick(6)
check(action==nil,"routine hunger never eats bait or condiments")
a.values.HUNGER=.9;tick(5)
-- The missing-food cooldown is bounded; expire it before the emergency retry.
now=now+11000;tick(5)
check(action and (action.intent.item==bait or action.intent.item==sauce),"genuine hunger can use emergency-only food after normal food is exhausted")
reset();a.inventory=inventory({bait});a.values.THIRST=.9;tick(5)
check(action==nil,"dehydration cannot authorize an emergency insect meal")
reset();a.inventory=inventory({bait});a.values.HUNGER=.9
local denied=storage(11,10,0,{fresh});denied.withdrawals=false
local protected=food("fresh");protected.protected=true
storage(12,10,0,{protected,normal});tick(4)
check(action and action.intent.item==normal and fresh.container==denied.container,"withdrawal and personal protections remain intact")
reset();a.inventory=inventory({normal})
local blocked,ob=storage(11,10,0,{fresh});ob.blocked=true
local reachable=food("fresh");storage(13,10,0,{reachable});tick(4)
check(action and action.intent.item==reachable,"an inaccessible fridge does not hide another fresh source")
reset();a.inventory=inventory({normal})
local reserved,object=storage(12,10,0,{fresh});object.approach=true
local other=actor(10,10,0)
check(SC.Encounter.takePlayerSupply(other,"held",function(item) return item==fresh end,{markedOnly=true})=="in_progress","second worker reserves the fresh source")
tick(3);check(action==nil,"reserved fresh supplies are pending rather than missing")
SC.Encounter.cancelPlayerSupply(other);object.approach=false;tick(2)
check(action and action.intent.item==fresh,"release resumes selection without eating bait")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal,water()})
player.moving=true;a.values.THIRST=.6
local before=scans;check(not update() and action==nil and scans==before,"moving followers do no routine meal, drink or world scan")
check(not N.refill(a,player,roots[a],"home") and scans==before,"moving followers cannot start a refill")
player.moving=false;update();now=now+14999
check(not update() and action==nil,"the pause must last the complete fifteen seconds")
now=now+1;check(update() and action and action.intent.action=="drink_item","a fifteen-second pause permits nearby drinking")
player.moving=true;local beforeCancel=cancels;update()
check(cancels==beforeCancel+1 and active==nil,"moving again cancels only the owned needs action")
local afterCancel=cancels;update();check(cancels==afterCancel,"paused action is not cancelled or consumed twice")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal})
N.routineAllowed(a,player,commands[a],now);local follower=actor(10,10,0)
check(not N.routineAllowed(follower,player,commands[a],now+14000),"another follower does not restart or complete the shared pause")
check(N.routineAllowed(a,player,commands[a],now+15000),"shared pause reaches fifteen seconds once")
player.square.x=10.05;check(N.routineAllowed(a,player,commands[a],now+15100),"tiny position noise does not reset a stop")
player.square.x=10.15;check(not N.routineAllowed(a,player,commands[a],now+15200),"slow displacement accumulates and resets the pause")
check(not N.routineAllowed(a,player,commands[a],now-1000),"a clock reset never grants a pause")
player.vehicle={};check(not N.routineAllowed(a,player,commands[a],now+20000),"being seated in a car is not a travelling meal pause")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal});a.values.HUNGER=.9;player.moving=true
tick(3);check(action and action.intent.item==normal,"genuine hunger retains its survival override while moving")
local emergencyCancels=cancels;update();check(cancels==emergencyCancels and active,"survival consumption is not cancelled by movement")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal})
N.routineAllowed(a,player,commands[a],now);now=now+15000;tick(3)
check(action~=nil,"routine meal starts after a stopped leader")
active=nil;N.assess(a);token={owner="medical"};roots[a].decision={current="activity"};player.moving=true
local navBefore=routes;N.pauseRoutine(a,"leader_moving",N.assess(a))
check(routes==navBefore and token.owner=="medical","completed meals cannot cancel a later medical owner or route")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal})
storage(18,10,0,{fresh});N.routineAllowed(a,player,commands[a],now);now=now+15000;tick(4)
check(action and action.intent.item==normal,"paused followers ignore fridges beyond six tiles of the leader")
reset();commands[a]={recruited=true,order="base_duty"};a.inventory=inventory({normal});player.moving=true;tick(3)
check(action and action.intent.item==normal,"camp workers do not wait for a travelling player")
reset();a.inventory=inventory({normal});a.values.THIRST=.6
local deep={};for i=1,300 do deep[i]={} end;deep[300]=fresh
storage(12,10,0,deep);tick(6)
check(action and action.intent.item==fresh,"interleaved failed water searches retain the deep-fridge food cursor")
reset();a.inventory=inventory({bait});a.values.HUNGER=.9
local borrowed,bo=storage(11,10,0,{normal});bo.approach=true
update();update()
check(action==nil,"food withdrawal waits for physical contact")
borrowed.withdrawals=false;bo.approach=false;tick(3)
check(normal.container==borrowed.container,"revoked storage access is revalidated during the approach")
reset();a.inventory=inventory({normal})
local spoiling,so=storage(11,10,0,{fresh});so.approach=true;update();fresh.rotten=true
so.approach=false;tick(3)
check(action and action.intent.item==normal and fresh.container==spoiling.container,"food which spoils during approach is not withdrawn")
fresh.rotten=nil
reset();atHome=false;a.inventory=inventory({normal})
local wide={};for i=1,100 do wide[i]={} end;wide[100]=fresh
local world,wo=storage(12,10,0,wide);SC.Encounter.markPlayerOpened(world.container)
tick(3)
check(action and action.intent.item==fresh,"opened world storage scans past eighty items before falling back")
reset();atHome=false;a.inventory=inventory({normal})
local privateWorld=storage(12,10,0,{fresh});tick(3)
check(action and action.intent.item==normal and fresh.container==privateWorld.container,"unopened world containers stay private")
reset();commands[a]={recruited=true,order="follow"};a.inventory=inventory({normal})
N.routineAllowed(a,player,commands[a],now);now=now+15000;a.square.z=1
check(not N.routineAllowed(a,player,commands[a],now),"followers must reach the leader's floor before a routine stop")
a.square.z=0;a.square.x=20
check(not N.routineAllowed(a,player,commands[a],now),"lagging followers close formation before routine needs")
reset();a.inventory=inventory({normal})
local upstairs,up=storage(12,10,1,{fresh});up.approach=true
update();check(action==nil,"camp workers consider permitted fresh supplies on another floor before carried durable food")
a.square.z=1;up.approach=false;tick(2)
check(action and action.intent.item==fresh,"the same exact food is fetched after actual floor arrival")
reset();a.inventory=inventory({normal});floorTransit=false
storage(12,10,1,{fresh});tick(3)
check(action and action.intent.item==normal,"unapproved floor transit cannot pull a worker toward inaccessible food")
local explicitRuntime={}
N.assess(a,explicitRuntime);check(explicitRuntime.needs~=nil,"an explicit decision runtime owns its needs state")
N.reset(a);check(explicitRuntime.needs==nil,"reset clears the actual decision runtime as well as the fallback runtime")
-- Real Follow orders must not turn an emergency into a route to a remote leader.
local function sink(x,y)
    local o={square=square(x,y,0)}
    function o:hasFluid() return true end
    function o:getFluidAmount() return 10 end
    function o:isTaintedWater() return false end
    o.square.objects={o};return o
end
reset();commands[a]={recruited=true,order="follow"};player.moving=true
a.square=square(30,10,0);a.values.HUNGER=.2;a.values.THIRST=.9
local nearby=sink(31,10)
tick(3)
check(action and action.intent.object==nearby,"emergency follower drinks from its own nearby sink with the leader far away")
reset();commands[a]={recruited=true,order="follow"};player.moving=true
a.square=square(30,10,0);a.values.HUNGER=.9
local localFood=food("fresh");storage(31,10,0,{localFood});tick(4)
check(action and action.intent.item==localFood,"starving follower fetches fresh food near itself instead of the distant leader")
reset();commands[a]={recruited=true,order="follow"};a.square=square(30,10,0);a.values.HUNGER=.2;a.values.THIRST=.6
sink(31,10);N.routineAllowed(a,player,commands[a],now);now=now+20000;tick(3)
check(not action,"routine follower still closes formation instead of taking a distant-source detour")
reset();commands[a]={recruited=true,order="follow",expeditionMember=true}
player.square=square(500,500,0);a.values.HUNGER=.2;a.values.THIRST=.6;a.inventory=inventory({water()})
check(update() and action and action.intent.action=="drink_item","stopped expedition drinks carried water with real Follow orders and a remote player")
reset();commands[a]={recruited=true,order="follow",expeditionMember=true}
player.square=square(500,500,0);a.inventory=inventory({normal})
storage(11,10,0,{fresh})
check(update() and action and action.intent.item==normal and fresh.container~=a.inventory,
    "stopped expedition uses carried food instead of starting a home resupply without options")
reset();commands[a]={recruited=true,order="follow",expeditionMember=true}
player.square=square(500,500,0);a.values.HUNGER=.2;a.values.THIRST=.9;nearby=sink(11,10)
tick(3);check(action and action.intent.object==nearby,"expedition emergency uses its own sink, never the remote player's scope")
reset();commands[a]={recruited=true,order="follow"}
local seated=actor(11,10,0);seated.vehicle={}
N.routineAllowed(a,player,commands[a],now)
for seconds=1,40 do
    now=now+1000
    check(not N.routineAllowed(seated,player,commands[a],now),"seated follower defers routine needs")
end
check(N.routineAllowed(a,player,commands[a],now),"seated follower never resets the standing follower's shared stop clock")
for _,formation in ipairs({1,2,3,5,8}) do
    reset();commands[a]={recruited=true,order="follow",followDistance=formation}
    a.values.HUNGER=.2;a.values.THIRST=.6
    nearby=sink(16,10);nearby.approach=true
    N.routineAllowed(a,player,commands[a],now);now=now+15000
    update();now=now+3100 -- allow the bounded outer-ring sample to reach its next phase
    check(update() and not action and N.peek(a).routineWork,"source at the six-tile boundary admits a real water errand")
    for _,offset in ipairs({5.5,6,7.4}) do
        a.square=square(10+offset,10,0)
        check(N.routineAllowed(a,player,commands[a],now),"admitted errand keeps its interaction margin at follow distance "..formation)
    end
    nearby.approach=false
    check(update() and action and action.intent.object==nearby,"boundary errand reaches its exact water source without returning to formation")
    local prior=cancels;player.moving=true;update()
    check(cancels==prior+1 and not active,"leader movement still cancels the admitted boundary errand")
end
reset()
a.values.HUNGER=.95
local meals={food("fresh"),food("fresh"),food("fresh"),food("fresh")}
for _,meal in ipairs(meals) do function meal:getHungerChange() return -.2 end end
a.inventory=inventory(meals)
check(update() and action and action.intent.action=="eat_food","base duty starts a real meal when hungry")
for portion=1,4 do
    local eating=action and action.intent
    check(eating and eating.item==meals[1],"meal continues selecting an actual carried food item")
    a.values.HUNGER=math.max(0,a.values.HUNGER+eating.item:getHungerChange()*eating.percentage)
    table.remove(a.inventory.items,1)
    active=false;action=nil;now=now+1000
    local handled=update()
    if portion<4 then
        check(handled and action and N.assess(a).hungry,
            "base meal keeps eating below the admission threshold")
    else
        check(not action and not N.assess(a).hungry and a.values.HUNGER<.30,
            "meal releases base duty only after real consumption lowers hunger below thirty percent")
    end
end
reset();a.inventory=inventory({fresh});check(update() and action,"meal boundary fixture starts")
active=false;action=nil;a.values.HUNGER=.30;now=now+1000
check(update() and action,"exactly thirty percent still needs the final portion")
active=false;action=nil;a.values.HUNGER=.299;now=now+1000
check(not update() and not action,"below thirty percent ends the meal")
reset();a.inventory=inventory({fresh});check(update() and action,"second meal fixture starts")
active=false;action=nil;a.values.HUNGER=.55;now=now+1000
commands[a]={recruited=true,order="follow"};player.moving=true
check(not update() and not action and not N.assess(a).hungry,
    "switching to a moving Follow order ends the base meal latch without an extra snack")
reset();a.inventory=inventory({fresh});check(update() and action,"interrupted meal fixture starts")
active=false;action=nil;a.values.HUNGER=.55;now=now+1000
roots[a].snapshot={immediateCount=1}
check(not update() and not action,"combat interrupts a base meal between native food actions")
roots[a].snapshot={};check(update() and action,"safe base meal resumes after the interruption")
reset();a.inventory=inventory({fresh});check(update() and action,"camp boundary fixture starts")
active=false;action=nil;a.values.HUNGER=.55;atHome=false;now=now+1000
check(not update() and not N.assess(a).hungry,"leaving camp clears the duty-only meal episode")
SC_TEST_SUPPLY_BUDGET={}
function SC_TEST_SUPPLY_BUDGET.run()
    local P=SC.Performance
    local inspected,resolved,exactCounts=0,0,0
    local originalEach,originalResolve=SC.GameplayUtil.each,SC.BaseLife.resolveContainer
    local oldReserve,oldExact,oldCount=SC.BaseLife.storageReserve,SC.BaseLife.availableCountExact,SC.BaseLife.availableCount
    SC.GameplayUtil.each=function(items,limit,callback,offset)
        return originalEach(items,limit,function(value)
            if value and value.supplyAudit then inspected=inspected+1 end
            return callback(value)
        end,offset)
    end
    SC.BaseLife.resolveContainer=function(row)
        resolved=resolved+1
        return not row.unloaded and originalResolve(row) or nil
    end
    SC.BaseLife.storageReserve=function(row) return row.reserved and 1 or 0 end
    SC.BaseLife.availableCountExact=function(row) exactCounts=exactCounts+1;return row.reserved and 0 or 1 end
    SC.BaseLife.availableCount=function() error("bounded reserve counts cannot authorize withdrawals") end
    local function setup()
        P.endFrame(0,false);reset();SC.Encounter.reset()
        P.reset();P._setClock(function() return now end)
        inspected,resolved,exactCounts=0,0,0
    end
    local function contents(n)
        local list={}
        for index=1,n do list[index]={supplyAudit=true,index=index} end
        return list
    end
    local function query(who,key,predicate,options)
        return SC.Encounter.takePlayerSupply(who,key,predicate,options or {
            markedOnly=true,completeSearch=true,revalidatePredicate=true,campFloors=true,
            preferredCategories={"fresh_food","food"}})
    end
    local function frame() now=now+100;P.beginFrame(3,now) end
    setup()
    for index=1,32 do storage(10+index,10,index%2,contents(300)) end
    frame()
    for index=1,4 do
        local worker=actor(10,10,0)
        local before=inspected
        local status,_,phase=query(worker,"empty",function() return false end)
        check(status=="in_progress" and phase=="searching","an exhausted discovery slice is pending, not missing")
        check(inspected-before<=64,"one request examines at most sixty-four items across all storages")
    end
    check(inspected==128 and resolved<=4,"all companions share the frame's 128-item/four-container allowance")
    P.endFrame(0,false)
    setup()
    for index=1,32 do storage(10+index,10,0,{}) end
    frame()
    query(a,"empty-markers",function() return false end)
    check(resolved==2,"one request resolves at most two empty containers")
    query(a,"empty-markers",function() return false end)
    query(a,"empty-markers",function() return false end)
    check(resolved==4,"empty containers also consume the shared metadata allowance")
    P.endFrame(0,false)
    local status
    for _=1,20 do
        frame();status=query(a,"empty-markers",function() return false end);P.endFrame(0,false)
        if status=="missing" then break end
    end
    check(status=="missing" and resolved==32,"retained container progress finishes without revisiting the first markers")
    setup()
    local grid=SC.GameplayUtil.gridSquare
    local geometry=0
    SC.GameplayUtil.gridSquare=function(...) geometry=geometry+1;return grid(...) end
    frame();status=query(a,"empty-home",function() return false end,{radius=6});P.endFrame(0,false)
    SC.GameplayUtil.gridSquare=grid
    check(status=="missing" and geometry==0,"an empty camp search never falls through to a geometric world scan")
    setup()
    for index=1,28 do local row=storage(20+index,10,0,contents(300));row.category="crafting" end
    local wanted=food("fresh")
    storage(12,10,1,{wanted})
    frame();status=query(a,"food-first",function(value) return value==wanted end)
    check(status=="taken" and inspected==0 and wanted.container==a.inventory and exactCounts==0,
        "food storage and cross-floor access avoid inspecting thousands of unrelated crafting items")
    P.endFrame(0,false)
    setup()
    for index=1,28 do local row=storage(10+index,10,0,contents(300));row.category="crafting" end
    local wanted=food("fresh")
    storage(40,10,1,{wanted})
    frame();update();P.endFrame(0,false)
    frame();update();P.endFrame(0,false)
    check(action and action.intent.item==wanted and inspected==0,
        "actual needs requests prioritize food storage without reading unrelated crafting inventories")
    setup()
    local wanted=food("fresh")
    local list=contents(300);list[300]=wanted
    local row,object=storage(12,10,1,list);object.approach=true
    local seen={}
    local function predicate(value) seen[value]=(seen[value] or 0)+1;return value==wanted end
    for _=1,8 do
        frame();query(a,"deep-food",predicate);P.endFrame(0,false)
        if seen[wanted] then break end
    end
    check(seen[wanted] and inspected==299 and wanted.container==row.container,
        "a deep fridge cursor examines each preceding item once before starting the physical errand")
    local other=actor(10,10,0)
    local beforeHeld=inspected
    frame();status=query(other,"deep-food",predicate);P.endFrame(0,false)
    check(status=="in_progress" and inspected==beforeHeld and #other.inventory.items==0,
        "known reserved food waits without re-reading the busy fridge or stealing its item")
    SC.Encounter.cancelPlayerSupply(a)
    frame();status=query(other,"deep-food",function() return false end);P.endFrame(0,false)
    check(status=="in_progress" and wanted.container==row.container,
        "a different actor's predicate is rechecked before using a shared candidate")
    row.withdrawals=false
    frame();status=query(other,"deep-food",predicate);P.endFrame(0,false)
    check(status=="missing" and #other.inventory.items==0,"cached candidates cannot bypass revoked withdrawals")
    row.withdrawals=true
    local previousSeen=seen[wanted]
    for _=1,8 do
        frame();query(a,"deep-food",predicate);P.endFrame(0,false)
        if seen[wanted]>previousSeen then break end
    end
    SC.Encounter.cancelPlayerSupply(a)
    wanted.protected=true
    frame();status=query(other,"deep-food",predicate);P.endFrame(0,false)
    check(status=="in_progress" and wanted.container==row.container,"cached personal items remain protected")
    wanted.protected=false;row.reserved=true
    frame();status=query(other,"deep-food",predicate);P.endFrame(0,false)
    check(status=="in_progress" and wanted.container==row.container and exactCounts>0,"cached food cannot consume reserved stock")
    row.reserved=false;object.approach=false
    local before=inspected
    frame();status=query(other,"deep-food",predicate);P.endFrame(0,false)
    check(status=="taken" and wanted.container==other.inventory and inspected==before,
        "another companion reuses the validated candidate without repeating the fridge scan")
    local third=actor(10,10,0)
    frame();status=query(third,"deep-food",predicate);P.endFrame(0,false)
    check(status=="in_progress" and #third.inventory.items==0 and wanted.container==other.inventory,
        "a consumed or moved cached item cannot be taken from another actor")
    setup()
    local wanted=food("fresh")
    local list=contents(100);list[65]=wanted
    local row=storage(11,10,0,list)
    frame();status=query(a,"shifting-stock",function(value) return value==wanted end);P.endFrame(0,false)
    check(status=="in_progress","first slice stops before the boundary item")
    table.remove(row.container.items,1)
    frame();status=query(a,"shifting-stock",function(value) return value==wanted end);P.endFrame(0,false)
    check(status=="taken" and wanted.container==a.inventory,"stock removal cannot shift an unexamined food behind the cursor")
    setup()
    local row,object=storage(11,10,0,contents(300))
    frame();query(a,"reload-stock",function(value) return value.kind=="fresh" end);P.endFrame(0,false)
    local oldContainer=row.container
    local wanted=food("fresh");row.container=inventory({wanted})
    function row.container:getParent() return object end
    frame();status=query(a,"reload-stock",function(value) return value.kind=="fresh" end);P.endFrame(0,false)
    check(status=="taken" and wanted.container==a.inventory and #oldContainer.items==300,
        "a replaced native container restarts only that storage's cursor and preserves the old contents")
    setup()
    local row=storage(11,10,0,{food("fresh")});row.unloaded=true
    frame();status=query(a,"unloaded",function() return true end);P.endFrame(0,false)
    check(status=="in_progress" and #a.inventory.items==0,"unloaded storage remains uncertain rather than licensing food fallback")
    setup()
    storage(11,10,0,contents(100))
    local precise=now
    P._setClock(function() return precise end)
    local seen={}
    local function slow(value)
        seen[value.index]=(seen[value.index] or 0)+1;precise=precise+.4;return false
    end
    P.beginFrame(3,now);query(a,"slow",slow);P.endFrame(.8,false)
    check(seen[1]==1 and seen[2]==1 and seen[3]==nil,"expensive predicates yield at the short time deadline")
    P.beginFrame(3,now);query(a,"slow",slow);P.endFrame(.8,false)
    check(seen[1]==1 and seen[2]==1 and seen[3]==1 and seen[4]==1,
        "time-sliced searches resume after processed items rather than redoing their predicates")
    setup();storage(11,10,0,contents(100));precise=now
    P._setClock(function() return precise end);P.beginFrame(3,now);precise=precise+4
    status=query(a,"expired-frame",function() return false end)
    check(status=="in_progress" and inspected==0 and resolved==0,"an exhausted scheduler frame starts no supply scan")
    P.endFrame(4,false);P._setClock(nil)
    SC.GameplayUtil.each,SC.BaseLife.resolveContainer=originalEach,originalResolve
    SC.BaseLife.storageReserve,SC.BaseLife.availableCountExact,SC.BaseLife.availableCount=oldReserve,oldExact,oldCount
    SC_TEST_REPORT="CAMP_SUPPLY_BUDGET_PASS checks="..checks
end
SC_TEST_REPORT="NEEDS_PRIORITY_PASS checks="..checks
