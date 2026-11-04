-- SPDX-License-Identifier: MIT
-- Public proof contracts only. Native preparation/driving remain live tests;
-- these cases reject unsafe audit assumptions without simulating a car trip.
local D=SCRealSandboxHarnessProbes.SCHomeDriveFixture
assert(type(D)=="table","load the live Drive fixture before its tests")
local priorSC,priorCell=SurvivorCompanion,getCell
local priorScriptManager=getScriptManager
local fixtureBody={width=2,length=5,halfWidth=1,halfLength=2.5}
local bodyScript={getFullName=function() return "Base.CarNormal" end,
    getExtents=function() return {x=function() return 2 end,z=function() return 5 end} end,
    getModelScale=function() error("native extents must not be scaled twice") end}
getScriptManager=function() return {getVehicle=function(_,name)
    assert(name=="Base.CarNormal") return bodyScript end} end
do
    local actual=assert(D._tests.carNormalBody())
    assert(actual.halfWidth==1 and actual.halfLength==2.5,"runtime CarNormal extents use native vector methods and half sizes")
    local direct=getScriptManager
    getScriptManager=function() return {getAllVehicleScripts=function()
        error("fixture setup must not enumerate all scripts in one poll") end} end
    local unsupported,unsupportedReason=D._tests.carNormalBody()
    assert(unsupported==nil and unsupportedReason=="car_normal_dimensions_unavailable",
        "an unsupported direct script getter must refuse instead of starting an unbounded script scan")
    getScriptManager=nil
    local missing,why=D._tests.carNormalBody()
    assert(missing==nil and why=="car_normal_dimensions_unavailable","unknown dimensions must refuse without a guessed fallback")
    getScriptManager=direct
end
do
    local nativeCall=assert(D._tests.call)
    local invocations=0
    local optional=setmetatable({},{__call=function() invocations=invocations+1 return "must not invoke" end})
    assert(nativeCall({},"getInventory")==nil and nativeCall({getInventory=optional},"getInventory")==nil
        and invocations==0,"missing or nonfunction optional native getters must not be invoked inside pcall")
    assert(nativeCall({getValue=function(_,value) return value+1 end},"getValue",4)==5,
        "guarded native calls preserve the actual receiver and arguments")
end
do
    local model=assert(D._tests.arrivalModel)
    for _,case in ipairs({
        {name="east",remote={x=-40,y=0,width=8},x=0,y=2},
        {name="west",remote={x=40,y=0,width=8},x=0,y=-2},
        {name="north",remote={x=0,y=40,width=8},x=2,y=0},
        {name="south",remote={x=0,y=-40,width=8},x=-2,y=0},
    }) do
        local arrival=model({points={{x=0,y=0,width=8},case.remote}},{x=0,y=0,z=0})
        assert(arrival.centre.x==case.x and arrival.centre.y==case.y and arrival.laneOffset==2
            and not arrival.driveway,"homeward "..case.name.." uses the signed right lane of the reversed mapped route")
    end
    local narrow=model({points={{x=0,y=0,width=5},{x=-40,y=0,width=5}}},{x=0,y=0,z=0})
    assert(narrow.laneOffset==0 and narrow.centre.x==0 and narrow.centre.y==0,
        "a width-five segment follows its centreline")
    local driveway=model({points={{x=0,y=0,width=8},{x=40,y=0,width=8}}},{x=0,y=-6,z=0})
    assert(driveway.driveway and driveway.width==5 and driveway.laneOffset==0
        and driveway.goal.x==0 and driveway.goal.y==-4 and driveway.heading.x==0 and driveway.heading.y==-1
        and driveway.centre.y==-4 and driveway.entryCentre.y==-2,
        "appended home driveway uses its actual final width-five goal and tangent rather than the mapped street lane")
    local nearby={points={{x=0,y=-4,width=2},{x=0,y=0,width=2},{x=40,y=0,width=8}}}
    local rejected,why,projection=D._tests.parkingLayouts(nearby,0,-2,fixtureBody)
    assert(#rejected==0 and why=="segment_short" and projection.segment==2 and projection.run==4 and projection.mappedWidth==2,
        "projection diagnostics identify a closer short connector instead of silently selecting a different road")
end

do
    local previousSC=SurvivorCompanion
    local calls=0
    SurvivorCompanion={ExpeditionRoute={planFromPoint=function(origin,target)
        calls=calls+1
        return {points={{x=origin.x,y=origin.y,width=8},{x=target.x,y=target.y,width=8}}},nil,
            {exitX=target.x,exitY=target.y}
    end}}
    for _,case in ipairs({{name="east",x=350,y=100},{name="west",x=-150,y=100},
            {name="north",x=100,y=-150},{name="south",x=100,y=350}}) do
        local H={config={home_trip_direction=case.name,home_trip_distance=250}}
        local f={camp={core={x=100,y=100,z=0}}}
        local before=calls
        local target=D.departureTarget(H,f)
        assert(target and target.x==case.x and target.y==case.y and target.z==0,
            "drive fixture ignores the requested "..case.name.." departure direction or distance")
        D.departureTarget(H,f)
        assert(calls==before+1,"unchanged drive fixture polls must reuse their existing road plan")
    end
    local target=D.departureTarget({config={}},{camp={core={x=100,y=100,z=0}}})
    assert(target and target.x==300 and target.y==100,"drive fixture default must match the public fixture's east200m option")
    for _,config in ipairs({{home_trip_direction="invalid"},{home_trip_distance=149},{home_trip_distance=351}}) do
        local before=calls
        local rejected,why=D.departureTarget({config=config},{camp={core={x=100,y=100,z=0}}})
        assert(rejected==nil and why=="invalid_home_trip_departure_option" and calls==before,
            "invalid departure options cannot silently plan another direction or distance")
    end
    SurvivorCompanion=previousSC
end
do
    local previousSC,previousPrint,previousWriter=SurvivorCompanion,print,getFileWriter
    local lines,requests={},{}
    local native={status="INCOMPLETE_MAP_DATA",reason="unnamed_or_missing_connector"}
    SurvivorCompanion={BaseLife={active=function() return {zones={}} end},
        ExpeditionRoute={planFromPoint=function(_,target)
            requests[#requests+1]={x=target.x,y=target.y,z=target.z}
            return nil,native.status,native
        end}}
    print=function(line) lines[#lines+1]=line end
    getFileWriter=nil
    local H={config={home_trip_stop="parking",home_trip_direction="east",home_trip_distance=200}}
    local f={camp={core={x=100,y=100,z=0}},_homeDrive={removedParking=true,storageReady=true}}
    local function poll(at)
        local ready,why=D.prepareCamp(H,f,at,function() error("unavailable route cannot pass a check") end,
            function() error("unavailable route cannot claim a parking fixture") end)
        assert(ready==nil and why=="INCOMPLETE_MAP_DATA","route diagnostics changed the native failure result")
    end
    poll(100) poll(200)
    assert(#lines==1 and string.find(lines[1],"nativeStatus=INCOMPLETE_MAP_DATA",1,true)
        and string.find(lines[1],"nativeReason=unnamed_or_missing_connector",1,true)
        and string.find(lines[1],"target=300,100,0",1,true),
        "missing-route diagnostics lost the native failure/actual target or logged every poll")
    poll(10100)
    native.reason="different_connector_evidence" poll(10101)
    assert(#lines==3 and #lines[3]<2048 and #requests==4,
        "unchanged route failures must log at ten seconds; changed evidence must log immediately")
    for _,target in ipairs(requests) do
        assert(target.x==300 and target.y==100,"diagnostics silently substituted an unrequested direction")
    end
    SurvivorCompanion,print,getFileWriter=previousSC,previousPrint,previousWriter
end
do
    local previousSC,previousSplit=SurvivorCompanion,SCSplitScreenProbe
    local mode,baseChecks,edgeChecks="clear",0,0
    local function square(x,y)
        local value={x=x,y=y}
        function value:isOutside() baseChecks=baseChecks+1 return true end
        function value:HasTree()
            return (mode=="tree" and self.x==8 or mode=="rect_tree" and self.x==0) and self.y==0
                or mode=="unused_corner" and self.x==-5 and self.y==-3
                or mode=="entry_tree" and self.x==3 and self.y==-2
                or mode=="retry_tree" and self.x==4 and self.y==2
                or mode=="turn_tree" and self.x==2 and self.y==-5
        end
        function value:TreatAsSolidFloor() return not ((mode=="hole" and self.x==8 or mode=="rect_hole" and self.x==0) and self.y==0) end
        function value:isBlockedTo(other)
            edgeChecks=edgeChecks+1
            return (mode=="edge" and self.x==8 and other.x==9 or mode=="rect_edge" and self.x==0 and other.x==1) and self.y==0
        end
        return value
    end
    SurvivorCompanion={GameplayUtil={gridSquare=function(x,y,z)
        if z~=0 or (mode=="unloaded" and x==8 or mode=="rect_unloaded" and x==0) and y==0 then return nil end return square(x,y)
    end,isSquareFree=function() return true end,squareOccupyingObject=function() end,movingBlocker=function() end}}
    SCSplitScreenProbe={primaryAreaContains=function() return true end}
    local function scan()
        local state={x=0,y=0,maximum=0}
        for tick=1,32 do
            baseChecks,edgeChecks=0,0
            local ready,reason=D._tests.patch(state,function() return true,{x=0,y=0,z=0} end)
            assert(baseChecks<=64 and edgeChecks<=128,"manoeuvre circle work must remain sliced with bounded edge checks")
            if ready~=nil then return ready,reason,tick end
        end
        error("bounded manoeuvre fixture scan did not terminate")
    end
    for _,blocked in ipairs({"tree","hole","edge","unloaded"}) do
        mode=blocked
        local ready,reason=scan()
        assert(ready==false and reason=="no_existing_clear_manoeuvre_room",
            "a clear 7x7 bay must reject real manoeuvre-room "..blocked.." eight metres outside it")
    end
    mode="clear"
    local ready,at,ticks=scan()
    assert(ready==true and at.room.x==0 and at.room.y==0 and ticks>1 and D._tests.manoeuvreRadius==12,
        "an explicitly requested alignment-room scan checks the whole circle across several polls")
    local route={points={{x=0,y=0,width=8},{x=-40,y=0,width=8}}}
    local layouts=D._tests.parkingLayouts(route,0,0,fixtureBody)
    assert(#layouts>0 and layouts[1].rationale=="normal_arrival_body_fits"
        and layouts[1].length==11 and layouts[1].width==7,
        "a straight road gets a long bay containing the signed lane's normal body and stop margin")
    local forward=D._tests.parkingLayouts(route,7,0,fixtureBody)
    assert(#forward>0 and forward[1].arrival.driveway and forward[1].arrival.width==5,
        "a target beyond the road end models the appended forward driveway")
    assert(#D._tests.parkingLayouts(route,6,6,fixtureBody)==0,
        "an unmodelled diagonal approach is not mislabeled as a cardinal parking fixture")
    local function rectangle(chosen)
        local state={x=0,y=0,maximum=0}
        for tick=1,32 do
            baseChecks,edgeChecks=0,0
            local ready,why=D._tests.patch(state,function() return true,nil,chosen or layouts[1] end)
            assert(baseChecks<=64 and edgeChecks<=128,"straight-bay floor and edge checks must remain sliced")
            if ready~=nil then return ready,why,tick,state end
        end
        error("straight parking scan did not terminate")
    end
    mode="tree"
    ready,at,ticks=rectangle()
    assert(ready==true and at.layout==layouts[1] and ticks>=1 and mode=="tree",
        "an untouched tree outside the straight body/approach corridor must not require a full turning circle")
    for _,blocked in ipairs({"rect_tree","rect_hole","rect_edge","rect_unloaded"}) do
        mode=blocked
        local accepted,why=rectangle()
        assert(accepted==false and why=="no_existing_clear_straight_parking_bay",
            "a real obstruction inside the selected straight parking corridor must reject it: "..blocked)
    end
    mode="unused_corner"
    ready,at=rectangle()
    assert(ready==true and not D._tests.corridorCell(layouts[1],-5,-3),
        "an untouched obstacle in an unused marked-zone corner must not reject the actual body and approach corridor")
    local driveway=D._tests.parkingLayouts({points={{x=0,y=0,width=8},{x=40,y=0,width=8}}},0,-8,fixtureBody)
    assert(#driveway>0,"runtime dimensions admit a short native forward approach after the planned driveway")
    mode="entry_tree"
    ready,at=rectangle(driveway[1])
    assert(ready==false and at=="no_existing_clear_straight_parking_bay",
        "a real obstacle in the entry body's corridor must still reject the parking fixture")
    local turn=D._tests.parkingLayouts({points={{x=0,y=0,width=8},{x=40,y=0,width=8}}},0,-16,fixtureBody)[1]
    assert(turn and turn.turnRadius==math.sqrt(fixtureBody.halfLength^2+fixtureBody.halfWidth^2)+.15
        and D._tests.corridorCell(turn,2,-5),
        "a tree outside the ideal north strip must remain inside the rotating body's actual corner-radius sweep")
    mode="turn_tree"
    ready,at=rectangle(turn)
    assert(ready==false and at=="no_existing_clear_straight_parking_bay" and square(2,-5):HasTree(),
        "a real tree struck only during driveway rotation must reject the fixture without being removed")
    local final=turn.corridors[#turn.corridors]
    assert(final.left==-1.25 and final.right==1.25,
        "turn clearance must not widen the subsequent straight forward corridor")
    local sameHeading=D._tests.parkingLayouts({points={{x=0,y=.5,width=8},{x=-40,y=.5,width=8}}},7,0,fixtureBody)[1]
    assert(sameHeading and sameHeading.arrival.driveway and sameHeading.turnRadius==nil,
        "an already aligned native straight approach keeps its ordinary half-body/access width")
    mode="clear"
    assert(rectangle(turn)==true,"a fully clear rotated entry keeps the real long-forward profile eligible")
    mode="retry_tree"
    local alternatives=D._tests.parkingLayouts(route,1,2,fixtureBody)
    local retryScan={x=1,y=2,maximum=0} local admits=0
    for tick=1,32 do
        baseChecks,edgeChecks=0,0
        ready,at=D._tests.patch(retryScan,function()
            admits=admits+1 return true,nil,alternatives[1],alternatives
        end)
        assert(baseChecks<=64 and edgeChecks<=128,"all layout retries share the same64-unit poll budget")
        if ready~=nil then break end
    end
    assert(ready==true and admits==1 and at.layout.length==13 and at.layout.rationale=="normal_arrival_body_fits"
        and retryScan.diagnostics.layoutAttempts>1 and square(4,2):HasTree(),
        "a rejected first layout must try every remaining legal layout at the same center without clearing the real obstacle")
    mode="rect_tree"
    local accepted,why,_,diagnosed=rectangle()
    local areas={} for index=1,10 do areas[index]={kind="area",x1=index,y1=-20,x2=index+4,y2=-10,z=0} end
    local diagnostic=D._tests.parkingDiagnostic(diagnosed,route,{x=0,y=0},"exhausted",{zones=areas})
    assert(accepted==false and diagnosed.diagnostics.counts["corridor:tree"]==1
        and diagnosed.diagnostics.candidates==1 and diagnosed.diagnostics.admitted==1
        and #diagnosed.diagnostics.samples<=8 and #diagnostic<8192
        and string.find(diagnostic,"corridor@0,0:tree:11x7",1,true)
        and string.find(diagnostic,"segment2=0,0>-40,0:width=8:run=40",1,true)
        and string.find(diagnostic,"area8=",1,true) and not string.find(diagnostic,"area9=",1,true),
        "bounded parking diagnostics must retain the actual failed cell/layout, route and first-eight camp areas")
    -- Run actual camp preparation through the public zone boundary. A north
    -- right lane fits; a fictitious second lane would cross the same limit.
    mode="clear"
    local originalArea={kind="area",x1=-5,x2=5,y1=-24,y2=-20,z=0}
    local zones={originalArea} local denied=false local zoneChecks,starts=0,0 local first
    SurvivorCompanion.BaseLife={active=function() return {zones=zones} end,
        withinWorkReach=function(at) return at.y>=-54 and at.y<=10 end,
        parkingZoneValid=function(zone)
            zoneChecks=zoneChecks+1
            return not denied and zone.x1>=-25 and zone.x2<=25 and zone.y1>=-44 and zone.y2<=0
        end,
        beginZone=function(kind,at) assert(kind=="parking") starts=starts+1 first=at return true end,
        finishZone=function(last)
            local zone={kind="parking",id="fixture:public",x1=first.x,y1=first.y,x2=last.x,y2=last.y,z=0}
            assert(SurvivorCompanion.BaseLife.parkingZoneValid(zone),"fixture expanded the public parking limit")
            zones[#zones+1]=zone return true,zone
        end}
    local west={points={{x=0,y=0,width=8},{x=40,y=0,width=8}}}
    local function camp(profile,y)
        local f={camp={core={x=0,y=-20,z=0}},_homeDrive={route=west,native={entryX=0,entryY=0,exitX=40,exitY=0},
            removedParking=true,storageReady=true,campScan={x=0,y=y or -3,maximum=0}}}
        local H={config={home_trip_stop="parking",home_trip_parking_profile=profile or "any"}}
        if profile==false then H.config.home_trip_parking_profile=nil end
        for tick=1,32 do
            local ready,why=D.prepareCamp(H,f,tick*100,function() error("unexpected check") end,function(status) assert(status=="PASS") end)
            if ready~=nil then return ready,why,f end
        end
        error("public parking boundary scan did not terminate")
    end
    local accepted,_,campFixture=camp()
    assert(accepted==true and starts==1 and zoneChecks>0 and zones[2].y2==0
        and campFixture.drive.parkingLayout.arrival.centre.y==-2 and originalArea.y2==-20,
        "signed lane bay must fit the unchanged public parking boundary without expanding camp")
    denied=true starts=0
    assert(camp()==false and starts==0,"public parking refusal must remain authoritative over a clear signed-lane corridor")
    denied=false starts=0
    local short,_,shortFixture=camp(false,-3)
    assert(short==false and starts==0 and shortFixture._homeDrive.campScan.diagnostics.counts["profile:requires_forward_7_to_12m"],
        "the default happy parking profile must reject a shorter otherwise-valid bay without silently falling back")
    local long,_,longFixture=camp("long_forward",-16)
    local selected=longFixture.drive.parkingLayout
    assert(long==true and starts==1 and selected.rationale=="clear_forward_approach"
        and selected.forwardDistance>=7 and selected.forwardDistance<=12 and selected.lateralDistance<=.75
        and longFixture.drive.parkingProfile=="long_forward" and originalArea.y2==-20,
        "the marked-parking happy scene must select a genuine long forward leg inside unchanged public bounds")
    local shortModel=D._tests.parkingLayouts(west,0,-8,fixtureBody)
    assert(#shortModel>0 and shortModel[1].forwardDistance>=.5 and shortModel[1].forwardDistance<7,
        "the general geometry model must retain native-legal short approaches for other tests")
    SurvivorCompanion,SCSplitScreenProbe=previousSC,previousSplit
end
local reads,adapterCalls,rawSetCalls,passed=0,0,0,0
local function container()
    local value={items={}}
    function value:getItems()
        return {size=function() return #value.items end,get=function(_,index)
            reads=reads+1 return value.items[index+1]
        end}
    end
    return value
end
local function item(id,kind)
    local value={nativeId=id,stableId="native-proof:"..id,itemType=kind or "Base.NailsBox"}
    function value:getID() return self.nativeId end
    function value:getFullType() return self.itemType end
    function value:getContainer() return self.holder end
    return value
end
local function move(value,target)
    if value.holder then for index,child in ipairs(value.holder.items) do
        if child==value then table.remove(value.holder.items,index) break end
    end end
    target.items[#target.items+1],value.holder=value,target
end
local function actor(inventory) return {getInventory=function() return inventory end} end
local function nativeReceipt()
    return {version=1,sqlId=99,tagUUID="native-car-save",x=200,y=100,z=0,
        worldVersion=240,byteLength=500,sha256=string.rep("a",64)}
end
local function cargoRows()
    return {{id="native-proof:501",nativeId=501,itemType="Base.NailsBox",stored=false},
        {id="native-proof:502",nativeId=502,itemType="Base.NailsBox",stored=false}}
end
local function setup(variant)
    reads,adapterCalls,rawSetCalls=0,0,0
    local carInventory,crewInventory,mainInventory,storage=container(),container(),container(),container()
    local first,second=item(501),item(502)
    move(first,carInventory) move(second,carInventory)
    -- Enough unrelated stock to require several bounded audit polls.
    for index=1,130 do move(item(1000+index,"Base.Plank"),storage) end
    local car={sqlId=99,trunk=carInventory,getX=function() return 200 end,
        getY=function() return 100 end,getZ=function() return 0 end,
        isEngineRunning=function() return false end}
    local crew,main=actor(crewInventory),actor(mainInventory)
    local row={id="construction:actual",category="construction",container=storage,deposits=true}
    local ledger=cargoRows()
    local summary={stored=0,trunkPending=2,items=ledger}
    local report={kind="home",vehicleSqlId=99,carSaveReceipt=nativeReceipt(),integration={items=ledger}}
    getCell=function() return {getVehicles=function()
        rawSetCalls=rawSetCalls+1
        return {size=function() return 1 end,get=function() error("native Set has no indexed get") end}
    end} end
    SurvivorCompanion={
        Vehicle={loadedVehicles=function() adapterCalls=adapterCalls+1 return {car} end,
            loadedBySqlId=function(id) return id==99 and car or nil end,
            cargoPart=function(value) return {},value.trunk end,
            isStationary=function() return true end},
        GameplayUtil={itemStableId=function(value,create)
                assert(create==false,"read-only proof never assigns an item identity") return value.stableId
            end,inventoryContains=function(inventory,value)
                for _,child in ipairs(inventory.items) do if child==value then return true end end return false
            end},
        Registry={snapshot=function() return {{id="crew",actor=crew}} end},
        BaseLife={active=function() return {storages={row}} end,
            resolveContainer=function(value) return value.container end,
            storageAcceptsDeposit=function(value,expected)
                return value.deposits==true and value.container==expected
            end},
        HomeTrip={validCarReceipt=function(receipt,sqlId)
            return type(receipt)=="table" and receipt.version==1 and receipt.sqlId==sqlId
                and receipt.tagUUID=="native-car-save" and type(receipt.sha256)=="string" and #receipt.sha256==64
                and type(receipt.x)=="number" and type(receipt.y)=="number" and type(receipt.z)=="number"
        end},
        ExpeditionPrototype={lastDebrief=function() return report end},
        ExpeditionIntegration={summary=function() return summary end},
    }
    function car:getSqlId() return self.sqlId end
    local H={player=main,config={home_trip_transport="drive"}}
    local f={primary=main,crew={{id="crew",actor=crew}},drive={variant=variant,sqlId=99,
        cargo=cargoRows(),
        beforeCommit={position={x=200,y=100,z=0},cargo=cargoRows(),carSaveReceipt=nativeReceipt()},
        sawDriving=true,sawCrewSeated=true,travelled=100,maximumDisplacement=100}}
    return H,f,{first=first,second=second,trunk=carInventory,crew=crewInventory,
        storage=storage,summary=summary,row=row,report=report,ledger=ledger}
end
local function result(status) assert(status=="PASS") passed=passed+1 end
local function check() error("audit must not manufacture a separate check result") end
local function poll(method,H,f,stopReason)
    for tick=1,32 do
        reads=0
        local ready,reason=method(H,f,tick*100,check,result)
        assert(reads<=64,"each public audit poll enumerates at most 64 native items")
        if ready~=nil or reason==stopReason then return ready,reason,tick end
    end
    error("bounded audit did not reach an observable outcome")
end

local H,f,objects=setup("parking")
move(objects.first,objects.crew)
local ready,reason,ticks=poll(D.afterRestored,H,f)
assert(ready==true and ticks>1 and adapterCalls>0 and rawSetCalls==0,
    "restore audits use the dense vehicle adapter across a native Set boundary and allow actual crew transit")
do
    local owners
    local okay,holders=poll(function(...)
        local ready,where,who=D.auditDelivery(...)
        owners=who
        return ready,where
    end,H,f)
    assert(okay==true and holders[501]=="crew" and owners[501]=="crew" and holders[502]=="trunk" and owners[502]==nil,
        "bounded delivery audit reports the exact registered carrier ID only for cargo physically in that inventory")
end
ready,reason=poll(D.checkFinal,H,f,"waiting_exact_cargo_storage")
assert(ready==nil and reason=="waiting_exact_cargo_storage",
    "a parking run cannot finish while exact cargo remains in the car or a crew inventory")
move(objects.first,objects.storage) move(objects.second,objects.storage)
ready,reason=poll(D.checkFinal,H,f,"waiting_verified_storage_receipts")
assert(ready==nil and reason=="waiting_verified_storage_receipts",
    "physical permitted storage alone does not invent verified deposit receipts")
objects.summary.stored,objects.summary.trunkPending=2,0
objects.ledger[1].stored=true
ready,reason=poll(D.checkFinal,H,f,"waiting_verified_storage_receipts")
assert(ready==nil and reason=="waiting_verified_storage_receipts",
    "an aggregate stored count cannot replace each exact native cargo's verified receipt")
for _,receipt in ipairs(objects.ledger) do receipt.stored=true end
ready=poll(D.checkFinal,H,f)
assert(ready==true and objects.first:getID()==501 and objects.second:getID()==502,
    "same exact native cargo in permitted construction storage plus actual receipts completes the parking proof")

H,f,objects=setup("roadside")
assert(poll(D.afterRestored,H,f)==true and poll(D.checkFinal,H,f)==true,
    "roadside proof keeps all exact roots in the real trunk and all unloading receipts pending")
objects.summary.stored,objects.summary.trunkPending=1,1
ready,reason=poll(D.afterRestored,H,f)
assert(ready==false and reason=="roadside_receipt_claimed_unloading",
    "roadside proof rejects a stored receipt when the actual exact roots remain in the trunk")

H,f,objects=setup("roadside")
local duplicate=item(501)
move(duplicate,objects.storage)
ready,reason=poll(D.afterRestored,H,f)
assert(ready==false and reason=="duplicate_live_cargo_native_id:501",
    "two different live native items with one expected ID are a concrete restore failure")

for _,method in ipairs({D.afterRestored,D.checkFinal}) do
    H,f,objects=setup("roadside")
    f.drive.beforeCommit=nil
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_capture_missing",
        "both restore and fresh final proofs require the stopped-car observation before production commit")
    H,f,objects=setup("roadside")
    f.drive.commitCaptureFailure="later native receipt failed"
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_capture_failed:later native receipt failed",
        "an earlier successful capture cannot conceal a later failed wrapped-commit observation")
    H,f,objects=setup("roadside")
    f.drive.beforeCommit.carSaveReceipt.sha256=string.rep("b",64)
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_native_receipt_stale",
        "a valid-looking old receipt must match the exact receipt on the completed home report")
    H,f,objects=setup("roadside")
    f.drive.beforeCommit.carSaveReceipt.sqlId=100
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_native_receipt_invalid",
        "a receipt for a different real car cannot prove this car's commit")
    H,f,objects=setup("roadside")
    f.drive.beforeCommit.cargo[2].nativeId=777
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_exact_cargo_mismatch",
        "the observed pre-commit trunk must contain every exact originally prepared native root")
    H,f,objects=setup("roadside")
    objects.ledger[2].nativeId=777
    ready,reason=method(H,f,100,check,result)
    assert(ready==false and reason=="drive_commit_exact_cargo_mismatch",
        "aggregate counts cannot conceal a completed home ledger for different cargo IDs")
end
assert(passed==4,"only complete positive proof cases emit PASS")
SurvivorCompanion,getCell,getScriptManager=priorSC,priorCell,priorScriptManager
print("HOME_DRIVE_FIXTURE_PASS")
