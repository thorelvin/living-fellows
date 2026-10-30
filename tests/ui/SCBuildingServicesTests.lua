-- SPDX-License-Identifier: MIT
-- Run the production services with a native-shaped world and explicit spies.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local U,B,H,S=SC.ControlUtil,SC.BuildingControls,SC.TerminalHardware,SC.TerminalServices
local check=T.check
SC.Terminal._clock=function() return T.now end
SC.GameplayUtil.nowMs=function() return T.now end
SC.GameplayUtil.instanceOf=function(value,kind) return value and value.kind==kind end
SC.GameplayUtil.containerContainsIdentity=function(container,item)
    for _,candidate in ipairs(container and container.items or {}) do if candidate==item then return true end end
    return false
end
local buckets={}
ModData={getOrCreate=function(key) buckets[key]=buckets[key] or {} return buckets[key] end}
local definition={}
function definition:getX() return 100 end function definition:getY() return 100 end
function definition:getX2() return 104 end function definition:getY2() return 104 end
function definition:getMinLevel() return 0 end function definition:getMaxLevel() return 0 end
function definition:getRooms() return {{getName=function() return "bankoffice" end}} end
local squares={}
for x=100,104 do for y=100,104 do local square=T.square(x,y,0,true)
    function square:getBuildingDef() return definition end
    function square:getMovingObjects() return {} end
    squares[x..":"..y]=square
end end
SC.GameplayUtil.gridSquare=function(x,y,z) return z==0 and squares[x..":"..y] or nil end
local pc=T.computer(squares["100:100"])
local player=T.player(101,100,0)
function player:getX() return self.x end function player:getY() return self.y end function player:getZ() return self.z end
function player:getPerkLevel() return self.skill or 4 end
function player:getSquare() return squares[math.floor(self.x)..":"..math.floor(self.y)] end
getSpecificPlayer=function(index) return index==0 and player or nil end
Perks={Electricity="Electricity"}
SC.BaseLife={active=function() return nil end,isInside=function() return false end}
local function container()
    local value={items={}}
    function value:getItems() return self.items end
    function value:AddItem(item) self.items[#self.items+1]=item item.container=self return item end
    function value:Remove(item)
        if self.refuse==item then return end
        for i,candidate in ipairs(self.items) do if candidate==item then table.remove(self.items,i) item.container=nil return end end
    end
    function value:hasRoomFor() return self.full~=true end
    return value
end
local inventory=container()
function player:getInventory() return inventory end
local nextId=100
local function item(kind,id)
    nextId=nextId+1
    local value={fullType=kind,id=id or nextId,condition=100,charge=1,weight=1}
    function value:getID() return self.id end function value:getFullType() return self.fullType end
    function value:getDisplayName() return self.fullType end function value:getActualWeight() return self.weight end
    function value:getContainer() return self.container end function value:getCondition() return self.condition end
    function value:getConditionMax() return 100 end function value:getCurrentUsesFloat() return self.charge end
    function value:getMaxUses() return 100000 end
    function value:setCurrentUsesFloat(amount) self.charge=amount end
    return value
end
local function parts(wire,scrap)
    for _=1,wire or 1 do inventory:AddItem(item("Base.ElectricWire")) end
    for _=1,scrap or 8 do inventory:AddItem(item("Base.ElectronicsScrap")) end
end
inventory:AddItem(item("Base.Screwdriver")) parts(12,40)
local os=SC.Terminal.computerState(player,pc) os.locked=false
check(B.panel(pc,false)==nil,"opening an ordinary PC does not invent security access")
SC.BaseLife.active=function() return {id="claimed-bank"} end
SC.BaseLife.isInside=function() return true end
check(B.connect(player,pc)==true,"electrical hookup installs the local connection")
local panel=B.panel(pc,false)
check(panel.label=="Bank" and panel.security.locked,"claiming camp inside a bank cannot bypass its building security")
SC.BaseLife.active=function() return nil end SC.BaseLife.isInside=function() return false end
local pc2=T.computer(squares["100:101"])
SC.Terminal.computerState(player,pc2).locked=false
check(B.connect(player,pc2)==true and B.panel(pc2,false)==panel,"another PC sees the same building password")
local pc3=T.computer(squares["104:104"])
player.x,player.y=103,104
check(B.connect(player,pc3) and type(B.computerId(pc3))=="string" and B.connected(pc3,panel),"a never-opened PC receives one durable connection identity")
player.x,player.y=101,100
check(B.prepare(pc,"unlock","missing",player)==nil,"unhacked panel cannot authorize commands")
SC.TerminalSystem.ensurePuzzle(panel.security,4)
check(B.security(pc,panel.security.puzzle.answer,4)==true,"existing recovery engine authorizes building access")
local door=T.computer(squares["101:101"],"Door") door.kind="IsoDoor" door.locked=true
function door:IsOpen() return self.open==true end function door:isLocked() return self.locked end
function door:isLockedByKey() return self.locked end function door:isBarricaded() return self.barricaded==true end
local light=T.computer(squares["102:101"],"Switch") light.kind="IsoLightSwitch"
function light:isActivated() return self.on==true end function light:canSwitchLight() return self.bulb~=false end
function light:setActive(value) self.on=value end
local foreign=T.computer(squares["103:101"],"Door") foreign.kind="IsoDoor" foreign.data.CustomLock=true
local nativeCalls=0
SCBridge={
    isControlDoorObstructed=function(object) return object.obstructed==true end,
    setControlDoorLocked=function(object,value) nativeCalls=nativeCalls+1 object.locked=value return true end,
    setControlDoorOpen=function(object,value) nativeCalls=nativeCalls+1 object.open=value return true end,
}
B.discover(pc,true)
local scan={panel=panel,bounds={x=100,y=100,x2=104,y2=104,z=0,z2=0},x=100,y=100,z=0}
B.scanStep(scan,25)
local rows=B.list(pc)
check(#rows==2,"bounded scan includes native doors/lights and excludes another mod's lock")
local doorRow,lightRow
for _,row in ipairs(rows) do if row.kind=="door" then doorRow=row else lightRow=row end end
check(B.status(doorRow)=="Locked","status observes the actual lock")
local ticket=B.prepare(pc,"unlock",doorRow.id,player)
check(ticket~=nil and B.execute(ticket)==true and not door.locked,"unlock changes only the captured device")
check(B.execute(ticket)==false and nativeCalls==1,"a confirmation is consumed exactly once")
ticket=B.prepare(pc,"lock",doorRow.id,player)
door.open=true
check(B.execute(ticket)==false and nativeCalls==1,"a changed door state invalidates confirmation")
door.open=false
ticket=B.prepare(pc,"lock",doorRow.id,player)
T.now=T.now+120001
check(B.execute(ticket)==false,"expired confirmations cannot operate equipment")
ticket=B.prepare(pc,"lock",doorRow.id,player)
pc.square=squares["104:104"]
check(not B.connected(pc,panel) and B.execute(ticket)==false,"moving a PC disconnects its building links")
pc.square=squares["100:100"]
doorRow.motor=true door.obstructed=true
ticket=B.prepare(pc,"open",doorRow.id,player)
check(B.execute(ticket)==false and not door.open,"occupied openings refuse motor operation")
door.obstructed=false
ticket=B.prepare(pc,"open",doorRow.id,player)
check(B.execute(ticket)==true and door.open,"clear motorized doors use native opening")
ticket=B.prepare(pc,"close",doorRow.id,player)
squares["101:101"].generatorPower=false
check(B.execute(ticket)==false and door.open,"controller power is separate from PC power")
squares["101:101"].generatorPower=true
ticket=B.prepare(pc,"on",lightRow.id,player)
check(B.execute(ticket)==true and light.on,"light relay updates a native switch")
light.bulb=false ticket=B.prepare(pc,"off",lightRow.id,player)
check(B.execute(ticket)==false and light.on,"missing bulb cannot produce a false success")
for i=1,300 do B.log(panel,"entry "..i) end
check(#panel.history==256 and panel.history[256].text=="entry 300","security history is bounded")

local blobs,blobSerial={},0
local function radioData()
    local d={battery=true,has=true,power=0.37,on=true,channel=88000,range=1200}
    function d:getIsTwoWay() return true end function d:getIsPortable() return true end
    function d:getTransmitRange() return self.range end function d:getIsTurnedOn() return self.on end
    function d:getMicIsMuted() return false end function d:isNoTransmit() return false end
    function d:getIsTelevision() return self.television==true end
    function d:getIsBatteryPowered() return self.battery end function d:setIsBatteryPowered(v) self.battery=v end
    function d:getHasBattery() return self.has end function d:setHasBattery(v) self.has=v end
    function d:getPower() return self.power end function d:setPower(v) self.power=v end
    function d:setIsTurnedOn(v) self.on=v end function d:getChannel() return self.channel end function d:setChannel(v) self.channel=v end
    function d:getMinChannelRange() return 200 end function d:getMaxChannelRange() return 1000000 end
    return d
end
SCBridge.packTerminalItem=function(value)
    blobSerial=blobSerial+1 local key="blob:"..blobSerial
    local saved={kind=value.fullType,id=value.id,condition=value.condition,charge=value.charge}
    if value.device then saved.radio={battery=value.device.battery,has=value.device.has,power=value.device.power,on=value.device.on,channel=value.device.channel,range=value.device.range} end
    blobs[key]=saved return key
end
SCBridge.unpackTerminalItem=function(key)
    local saved=blobs[key] if not saved then return nil end
    local value=item(saved.kind,saved.id) value.condition=saved.condition value.charge=saved.charge
    if saved.radio then value.kind="Radio" value.device=radioData() for k,v in pairs(saved.radio) do value.device[k]=v end function value:getDeviceData() return self.device end end
    return value
end
SCBridge.createTerminalReceiver=function(value)
    return {getDeviceData=function() return value.device end,removeFromWorld=function(self) self.removed=true end}
end
local radio=item("Base.WalkieTalkie2") radio.kind="Radio" radio.device=radioData()
function radio:getDeviceData() return self.device end
inventory:AddItem(radio)
local originalId=radio.id
radio.device.television=true
check(not H.install(player,pc,"radio",radio) and U.owns(player,radio),"a TV cannot be mounted even if its other flags resemble a transmitter")
radio.device.television=false
check(H.install(player,pc,"radio",radio)==true and not U.owns(player,radio),"mount transfers the exact handset out of inventory")
local hardware=H.state(pc,false)
do
    for _,row in ipairs({{hardware,"generation",math.huge},{hardware.radio,"id",math.huge},
        {hardware.radio,"weight",0/0},{hardware.radio,"monitorVolume",math.huge}}) do
        local target,key,bad=row[1],row[2],row[3]
        local previous=target[key] target[key]=bad
        check(H.state(pc,false)==nil and not H.flush(pc),
            "invalid saved hardware scalars cannot reach native transfers or serialization")
        target[key]=previous
    end
    local radioModule=SC.TerminalRadio
    SC.TerminalRadio={stop=function() return false,"fixture restoration failed" end}
    check(not H.beforePickup(pc) and hardware.radio~=nil,
        "failed radio restoration blocks furniture pickup without transferring parts")
    SC.TerminalRadio=radioModule
end
check(hardware.radio.id==originalId,"mounted payload retains native identity")
local receiver,data=H.receiver(pc)
check(receiver and data.power==1,"native world receiver uses station power")
check(H.flush(pc)==true,"powered receiver can be saved")
local savedRadio=H.restorePart(hardware.radio)
check(savedRadio.device.power==0.37 and savedRadio.id==originalId,"station supply does not charge or replace the original handset battery")
local endpoint=SC.RadioEndpoints.station(player,pc)
check(endpoint and SC.RadioEndpoints.validate(player,endpoint)==true,"station endpoint validates real hardware")
data.television=true
check(not SC.RadioEndpoints.validate(player,endpoint),"station cannot transmit through a receiver changed to television")
data.television=false
check(SC.RadioEndpoints.validate(player,endpoint),"unchanged real handset retains station authority")
local sourceX,sourceY,sourceZ=SC.RadioEndpoints.origin(endpoint)
check(sourceX==100 and sourceY==100 and sourceZ==0,"station origin preserves all three native coordinates")
check(SC.RadioEndpoints.validate(player,{kind="station",owner=player})==false,"caller tables cannot forge radio endpoints")
local battery=item("Base.CarBattery1") inventory:AddItem(battery)
check(SC.Terminal.open(player,pc),"native-mounted radio opens before adding backup power")
local upgradeWindow=SC.Terminal.window upgradeWindow:flush()
check(SC.TerminalRadio.scan(upgradeWindow,"band") and data.channel==200,
    "scanner is active while the backup component is installed")
do
    local originalSetter, originalBlob = data.setChannel, hardware.radio.blob
    data.setChannel = function(self, channel)
        if channel ~= 88000 then originalSetter(self, channel) end
    end
    local saved, reason = H.save()
    check(saved == false and type(reason) == "string" and hardware.radio.blob == originalBlob
        and SC.TerminalRadio.snapshot(upgradeWindow).scan.restoring,
        "saving reports a failed channel restore without serializing the temporary scan channel")
    data.setChannel = originalSetter
    check(H.save() and data.channel == 88000
        and H.restorePart(hardware.radio).device.channel == 88000
        and not SC.TerminalRadio.snapshot(upgradeWindow).scan,
        "retrying save restores and persists the exact original radio channel")
    check(SC.TerminalRadio.scan(upgradeWindow,"band") and data.channel == 200,
        "a recovered save does not prevent a fresh scanner session")
    local originalRaw = data.setChannelRaw
    data.setChannel = function() end
    data.setChannelRaw = function(self, channel) self.channel = channel end
    check(H.save() == true and data.channel == 88000
        and not SC.TerminalRadio.snapshot(upgradeWindow).scan,
        "a handset that refuses its own earlier channel still gets it back, so a scan cannot strand stops")
    data.setChannel, data.setChannelRaw = originalSetter, originalRaw
    check(SC.TerminalRadio.scan(upgradeWindow,"band") and data.channel == 200,
        "the scanner still starts after a raw channel restore")
end
check(H.install(player,pc,"ups",battery)==true,"charged real battery installs as backup")
check(data.channel==88000 and not SC.TerminalRadio.snapshot(upgradeWindow).scan,
    "adding backup power restores the radio channel before changing receiver generation")
upgradeWindow:close()
check(SC.RadioEndpoints.validate(player,endpoint)==false,"changing hardware invalidates old radio authority")
squares["100:100"].generatorPower=false
check(H.powered(pc)==true,"backup powers only this PC")
check(squares["100:100"].generatorPower==false,"backup never grants electricity to the square")
local start=T.hours hardware.lastHours=start T.hours=start+3 T.now=T.now+2000 H.pulse()
check(math.abs(hardware.ups.charge-0.5)<0.001,"three game hours consume half of a full healthy backup")
inventory.full=true
check(H.remove(player,pc,"radio")==false and hardware.radio~=nil,"full inventory preserves mounted cargo")
inventory.full=false
check(SC.Terminal.open(player,pc),"mounted handset opens for a removal-during-scan regression")
local scanWindow=SC.Terminal.window scanWindow:flush()
check(SC.TerminalRadio.tune(scanWindow,99000),"fixture saves an explicit listening channel")
check(SC.TerminalRadio.scan(scanWindow,"band") and data.channel==200,
    "native-mounted handset moves onto its temporary scan channel")
check(H.remove(player,pc,"radio")==true and hardware.radio==nil,"removal returns the original handset")
local restored
for _,candidate in ipairs(inventory.items) do if candidate.id==originalId then restored=candidate end end
check(restored and restored.device.power==0.37,"unmounted battery charge remains exact")
check(restored.device.channel==99000,"removing a scanning handset restores its original channel before transfer")
scanWindow:close()
local count=0 for _,candidate in ipairs(inventory.items) do if candidate.id==originalId then count=count+1 end end
check(count==1,"no duplicate handset exists after transfer")
check(H.remove(player,pc,"radio")==false,"repeated remove cannot replay transfer")
check(SC.RadioEndpoints.validate(player,endpoint)==false,"removed radios never remain command sources")

SC.Terminal.window=nil squares["100:100"].generatorPower=true
check(SC.Terminal.open(player,pc)==true,"native-shaped UI opens with the new modules")
local window=SC.Terminal.window window:flush()
check(#window:menuOptions()==4 and window:menuOptions()[1].systemCommand=="files"
    and window:menuOptions()[4].serviceValue=="home_services",
    "outside computers retain numbered local services while hiding Camp report")
S.input(window,"building services")
check(window.menuPage=="services" and #window:menuOptions()<=9,"building services have bounded numbered controls")
window.menuPage="device" window.serviceDevice=doorRow.id
check(#window:menuOptions()<=9,"device menus remain selectable with single digit keys")
window.menuPage="services"
local liveOS=window.system
check(B.connect(player,pc),"reconnecting an open terminal keeps its current identity")
SC.BuildingSecurity.pulse()
check(pc:getModData().movableData.LF_LarchOS==liveOS,"background services preserve the exact open OS session table")
local controlTicket=SC.TerminalActions.prepare(window,{kind="control",request={operation="device",verb="unlock",id=doorRow.id}})
check(controlTicket~=nil,"outside-camp building controls use their own permission domain")
check(SC.TerminalActions.prepare(window,{kind="medic",query="Ann"})==nil,"local building access does not grant camp medical authority")
window:close()
check(SC.TerminalActions.execute(window,controlTicket)==false,"closed sessions cannot execute queued consent")
check(SC.BuildingCircuits.prepare(pc,"fridge",false,player)==nil,"unavailable refrigeration cannot fabricate a native circuit")
do
    local square=player:getSquare() local previous=square.canReachTo
    local effects=0 local access=false
    square.canReachTo=function() return access end
    local action={character=player,object=pc,effect=function() effects=effects+1 return true end}
    function action:isValid() return SCComputerInstallAction.isValid(self) end
    check(not SCComputerInstallAction.complete(action) and effects==0,"nearby equipment behind a barrier cannot be installed through the wall")
    access=true
    check(SCComputerInstallAction.complete(action) and effects==1,"reachable equipment completes one physical installation")
    check(not SCComputerInstallAction.complete(action) and effects==1,"physical installation effects cannot replay")
    square.canReachTo=previous
end
do
    local updates=0
    light.bulb=true
    light.setActive=function(self,value) updates=updates+1 self.on=value end
    check(B.operate(panel,lightRow,light,"on",player) and updates==0,"unchanged lighting does not issue another native redraw")
    check(B.operate(panel,lightRow,light,"off",player) and updates==1,"a changed light issues one native switch")
    definition.getKeyId=function() return 41 end
    panel.security.locked=true
    check(not B.authorizeKey(pc,player),"building access requires a matching physical key")
    local key=item("Base.Key1") key.kind="Key" key.getKeyId=function() return 41 end inventory:AddItem(key)
    check(B.authorizeKey(pc,player) and not panel.security.locked,"the real building key authorizes the separate panel")
    local flood=T.computer(squares["102:102"],"Floodlight") flood.kind="IsoThumpable"
    function flood:getLightSourceRadius() return 6 end
    function flood:isLightSourceOn() return self.on==true end
    function flood:haveFuel() return self.fuel~=false end
    function flood:toggleLightSource(value) self.on=value end
    B.scanStep({panel=panel,bounds={x=102,y=102,x2=102,y2=102,z=0,z2=0},x=102,y=102,z=0},1)
    local floodRow
    for _,row in ipairs(B.list(pc)) do if B.resolve(row)==flood then floodRow=row end end
    check(floodRow and floodRow.kind=="light","constructed floodlights use the native light lane")
    check(B.operate(panel,floodRow,flood,"on",player) and flood.on,"a fueled constructed floodlight switches on")
    flood.fuel=false
    check(not B.operate(panel,floodRow,flood,"off",player) and flood.on,"missing floodlight fuel cannot fabricate success")
    definition.setAlarmed=function(self,value) self.alarmed=value end
    check(SC.BuildingSecurity.operate(panel,pc,"arm",player) and definition.alarmed,"arming uses the native building alarm flag")
    check(SC.BuildingSecurity.operate(panel,pc,"disarm",player) and not definition.alarmed,"disarming updates the same native building")
    panel.history={}
    local before=#panel.history
    SC.BuildingSecurity.pulse()
    squares["100:100"].generatorPower=false SC.BuildingSecurity.pulse()
    check(#panel.history==before+1 and panel.history[#panel.history].text:find("supply",1,true),"power transition is logged once")
    SC.BuildingSecurity.pulse()
    check(#panel.history==before+1,"an unchanged outage does not flood history")
    squares["100:100"].generatorPower=true SC.BuildingSecurity.pulse()
    check(#panel.history==before+2,"restored building power is recorded")
    local oldTime=getGameTime
    getGameTime=function() return {getWorldAgeHours=function() return T.hours end,getHour=function() return 21 end} end
    flood.fuel=true
    check(SC.BuildingSecurity.routine(panel,pc,"night",player),"night routine requires an explicit request")
    SC.BuildingSecurity.pulse()
    check(light.on and flood.on,"night routine applies the captured lights")
    updates=0 SC.BuildingSecurity.pulse()
    check(updates==0,"repeated night ticks do not flash unchanged lights")
    B.disconnect(pc,panel)
    check(panel.routines.night.suspended,"moving or disconnecting the owner suspends automatic actions")
    check(B.connect(player,pc) and not panel.routines.night.suspended,"a physical reconnection resumes that PC's routine")
    getGameTime=oldTime
end
do
    local circuits=SC.BuildingCircuits.list(pc)
    check(#circuits>0,"LF builds its own native circuit list without another mod")
    local circuit=circuits[1]
    local pending=SC.BuildingCircuits.prepare(pc,circuit.id,false,player)
    check(pending~=nil,"native circuit confirmation captures each exact relay")
    local oldGroup=lightRow.group lightRow.group="Changed group"
    check(not SC.BuildingCircuits.execute(pc,pending),"changing circuit membership invalidates its pending confirmation")
    lightRow.group=oldGroup
    pending=SC.BuildingCircuits.prepare(pc,circuit.id,false,player)
    check(SC.BuildingCircuits.execute(pc,pending),"LF circuits delegate effects to native devices")
    check(not SC.BuildingCircuits.execute(pc,pending),"circuit confirmations cannot replay their native operations")
end
do
    local openOS=pc:getModData().movableData.LF_LarchOS
    local station={object=pc,player=player,system=openOS,stationDraft={kind="wood",travelMode="road",quantity=12,category="food",hours=4,crew={"first"}}}
    function station:setFocusMode(value) self.focusMode=value end
    function station:startReply(reply) self.reply=reply end
    check(H.install(player,pc,"radio",restored),"station planning uses an actually mounted handset")
    local record={id="first",name="First companion",actor=player}
    SC.Registry={byId=function(id) return id=="first" and record end}
    SC.Commands={describe=function() return {recruited=true,available=true,alive=true} end}
    SC.BaseLife={active=function() return {id="camp"} end,isInside=function() return true end}
    SC.GameplayUtil.nameOf=function() return "First companion" end
    SC.Config={get=function() return nil end}
    local starts=0
    SC.ExpeditionPrototype={current=function() return nil end,previewWoodCollection=function() return {} end,
        previewAtPlace=function() return {} end,startAtPlace=function(_,_,kind,options)
            starts=starts+1 check(kind=="search" and options.request.quantity==4,"normal search request keeps the existing 1-8 item limit")
            return true,{} end}
    SC.ExpeditionPlaces={targetableById=function(x,y,_,id)
        check(x==math.floor(x) and y==math.floor(y),"station lookup floors live actor coordinates for the native place API")
        return {id=id,label="Store"}
    end}
    S.input(station,"",{serviceAction="cycle",serviceValue="kind"})
    check(station.stationDraft.kind=="search" and station.stationDraft.quantity==4,"switching from wood clamps the independent search quota")
    station.stationDraft.placeId="store"
    local x,y=player.x,player.y player.x,player.y=101.25,100.25
    check(S.review(station),"normal search is reviewed against the production planner boundary")
    local pending=S.prepare(station,{request={operation="launch"}})
    station.stationDraft.hours=8
    check(not S.execute(station,pending) and starts==0,"changing reviewed details requires a new review before launch")
    station.stationDraft.hours=4
    check(S.review(station),"unchanged valid plan can be reviewed again")
    pending=S.prepare(station,{request={operation="launch"}})
    local accepted,message=S.execute(station,pending)
    check(accepted and starts==1 and message:find("Expedition launched",1,true),"successful station launch reports the expedition instead of a base job")
    S.input(station,"",{serviceAction="review"})
    check(station.focusMode=="chat","the review remains visible before choosing launch")
    local carId=5
    SC.ExpeditionPrototype.previewDrive=function() return {carSqlId=carId,carName="Test car",fuel="8",fuelRequired="1"} end
    station.stationDraft.travelMode="drive"
    check(S.review(station) and station.stationReviewed.carSqlId==5,"driving review captures the exact selected native car")
    pending=S.prepare(station,{request={operation="launch"}}) carId=6
    check(not S.execute(station,pending) and starts==1 and station.stationReviewed==nil,"a different car invalidates review and cannot be accepted by repeating Launch")
    player.x,player.y=x,y
end
do
    local G=SC.GeneratorServices
    local generator=T.computer(squares["101:102"],"Generator") generator.kind="IsoGenerator" generator.condition=100
    function generator:isActivated() return self.on==true end function generator:isConnected() return true end
    function generator:getFuel() return 8 end function generator:getCondition() return self.condition end
    local helper=T.player(101,101,0) helper.serial=7
    function helper:getSquare() return squares["101:101"] end
    function helper:getPerkLevel() return 4 end
    SC.Registry={living=function() return {helper} end,idOf=function() return "helper" end,byId=function() return {actor=helper} end}
    SC.GameplayUtil.idOf=function() return "helper" end
    SC.GameplayUtil.nameOf=function() return "Test helper" end
    SC.Commands={describe=function() return {recruited=true,order="follow",available=true,alive=true} end,
        peek=function() return {commandSerial=helper.serial} end}
    SC.BaseLife={active=function() return nil end,withinWorkReach=function() return false end,job=function() return nil end,
        describeObject=function() return {objectId="native-generator",x=101,y=102,z=0} end,resolveObject=function() return generator end}
    local work,starts,cancels=nil,0,0
    SC.ActionSupervisor={current=function() return nil end}
    SC.GameplayUtil.directInteractionAccess=function() return true end
    SC.NativeActions={isWorkActive=function() return work=="active" end,workKind=function() return work and "generator_service" end,
        startGeneratorService=function() starts=starts+1 work="active" return true,"started" end,
        finishWork=function() work=nil return true end,cancelWork=function() work=nil cancels=cancels+1 return true end}
    check(G.requestLocal(player,generator,"start"),"local generator work chooses an idle recruited companion")
    local job=G.fieldPending(helper)
    check(job and job.commandSerial==7,"field request binds the actual command generation")
    check(G.requestLocal(player,generator,"start") and G.fieldPending(helper)==job,"repeated request reuses one service job")
    check(not G.requestLocal(player,generator,"stop"),"conflicting service requests cannot share a generator")
    G.updateField(helper,{commandSerial=7},false)
    check(starts==1 and G.canContinue(helper,generator,job.id),"native work validates the exact generator and owned job")
    check(G.cancel(helper,{id="older-job",target={}}) and work=="active" and cancels==0,"an obsolete service job cannot cancel a newer native action")
    work="finished" G.updateField(helper,{commandSerial=7},false)
    check(job.retryHour and job.retryHour>T.hours,"failed native start pauses for a game-time retry")
    local deadline=job.retryHour
    T.hours=deadline-0.01 G.updateField(helper,{commandSerial=7},false)
    check(starts==1,"a paused request does not repeatedly start the generator")
    T.hours=deadline+0.001 G.updateField(helper,{commandSerial=7},false)
    check(starts==2,"three game minutes automatically retry the local service")
    local routeCancels=0 local goal="move_to_generator_service"
    SC.Navigation={peek=function() return {goalAction=goal} end,cancel=function() routeCancels=routeCancels+1 return true end}
    G.updateField(helper,{commandSerial=8},false)
    check(not G.fieldPending(helper) and cancels>0 and routeCancels==1,"a new player order releases this job's native work and navigation")
    goal="combat_retreat"
    G.cancel(helper,job)
    check(routeCancels==1,"stale service cleanup leaves unrelated movement intact")
end
print("PASS building services checks="..T.checks)
