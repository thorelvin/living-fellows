-- SPDX-License-Identifier: MIT
-- Real survey engine, deterministic clock, native-shaped loaded chunks.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local B,D,U=SC.BuildingControls,SC.BuildingScan,SC.ControlUtil
local checks=0
local function check(ok,text) checks=checks+1 assert(ok,"building discovery "..checks..": "..text) end
local world,chunk,panel,pc,player,window,definition,buckets
local reads,chunkReads,pausedFlag,xpCount=0,0,false,0
SC.GameplayUtil.nowMs=function() return T.now end
SC.GameplayUtil.instanceOf=function(value,kind) return value and value.kind==kind end
Perks={Electricity="Electricity"}
function isGamePaused() return pausedFlag end
local function setup(skill,minZ,maxZ)
    B.reset() T.now=1000 pausedFlag=false reads,chunkReads,xpCount=0,0,0
    buckets={} ModData={getOrCreate=function(key) buckets[key]=buckets[key] or {} return buckets[key] end}
    world={}
    definition={minZ=minZ or 0,maxZ=maxZ or 0}
    function definition:getX() return 100 end function definition:getY() return 100 end
    function definition:getX2() return 104 end function definition:getY2() return 104 end
    function definition:getMinLevel() return self.minZ end function definition:getMaxLevel() return self.maxZ end
    function definition:getRooms() return {{getName=function() return "office" end}} end
    function definition:isAlarmed() return self.alarmed==true end
    chunk={maxZ=definition.maxZ}
    function chunk:getMaxLevel() return self.maxZ end
    getCell=function() return {getChunkForGridSquare=function(_,x,y,z)
        chunkReads=chunkReads+1
        if chunk.unloaded and chunk.unloaded(x,y,z) then return nil end
        return chunk
    end} end
    SC.GameplayUtil.gridSquare=function(x,y,z) reads=reads+1 return world[x..":"..y..":"..z] end
    local tile=T.square(100,100,0,true)
    function tile:getBuildingDef() return definition end
    world["100:100:0"]=tile
    pc=T.computer(tile)
    player=T.player(101,100,0)
    function player:getX() return self.x end function player:getY() return self.y end function player:getZ() return self.z end
    function player:getSquare() return {getX=function() return self.x end,getY=function() return self.y end,getZ=function() return self.z end} end
    function player:getPerkLevel() return skill or 0 end
    function player:getXp() return {AddXP=function(_,perk,amount) xpCount=xpCount+1 check(perk=="Electricity" and amount==5,"native XP uses its real perk and amount") end} end
    SC.BaseLife={active=function() return nil end,isInside=function() return false end}
    SC.Terminal._clock=function() return T.now end
    SC.Terminal.computerState(player,pc).locked=false
    panel=B.panel(pc,true)
    panel.connections[B.computerId(pc)]={x=100,y=100,z=0}
    window={object=pc,player=player,closed=false,state="idle"}
    SC.Terminal.window=window
    return tile
end
local function add(kind,x,y,z)
    local key=x..":"..y..":"..z
    local tile=world[key]
    if not tile then tile=T.square(x,y,z,true) function tile:getBuildingDef() return definition end world[key]=tile end
    local object=T.computer(tile,kind)
    object.kind=kind
    if kind=="IsoDoor" then function object:IsOpen() return false end end
    return object
end
local function tick(ms)
    T.now=T.now+ms D.observeWindow(window,T.now) D.pulse(function() return 10 end)
end
local function complete()
    for _=1,10000 do
        if D.state(pc).done then return end
        tick(100)
    end
    error("survey did not complete")
end

setup(0)
for _=1,3 do B.register(pc) B.pulse() end
check(reads==0 and D.state(pc)==nil,"register/services never start a hidden scan")
check(B.startScan(pc,player),"an explicitly connected computer can start discovery")
for _=1,10 do tick(100) end
check(D.state(pc).processed==64,"Electrical 0 processes exactly 64 tiles per real second")
local before=D.state(pc).processed
tick(100000)
check(D.state(pc).processed-before==32,"a stalled frame grants at most 32 tiles")
before=D.state(pc).processed tick(100)
check(D.state(pc).processed-before<=7,"the next call cannot spend a banked backlog")

setup(10) B.startScan(pc,player)
for _=1,10 do tick(100) end
check(D.state(pc).processed==128,"Electrical 10 processes exactly 128 tiles per real second")
local originalRate=D.state(pc).rate
function player:getPerkLevel() return 0 end
tick(100)
check(D.state(pc).rate==originalRate,"skill is sampled once, not on every pulse")

setup(0) B.startScan(pc,player) tick(100)
local cursor=D.state(pc).processed
window.closed=true D.observeWindow(window,T.now)
local readCount=reads
T.now=T.now+600000 D.pulse()
check(reads==readCount and D.state(pc).status=="paused","closed terminals do zero survey work")
window.closed=false
check(B.startScan(pc,player),"closing preserves an explicitly resumable cursor")
D.pulse() check(D.state(pc).processed==cursor,"resuming never counts time while closed")
tick(100) check(D.state(pc).processed-cursor<=7,"resumed discovery uses a normal slice")
pausedFlag=true D.observeWindow(window,T.now) T.now=T.now+600000 D.pulse()
before=D.state(pc).processed
pausedFlag=false D.observeWindow(window,T.now) D.pulse()
check(D.state(pc).processed==before,"game pause cannot become real-time scan credit")
check(B.abortScan(pc) and D.state(pc).status=="aborted","Abort ends the pass")
check(B.startScan(pc,player) and D.state(pc).processed==0,"the next pass after Abort starts fresh")

setup(0,-1,1)
local door=add("IsoDoor",101,100,1)
local fridge=add("Fridge",102,100,-1)
local dataReads=0
function fridge:getModData() dataReads=dataReads+1 return self.data end
function fridge:getContainerByType(kind) return (kind=="fridge" or kind=="freezer") and {} end
add("IsoTelevision",103,100,0) add("IsoRadio",104,100,0)
definition.alarmed=true
B.startScan(pc,player) complete()
local state=D.state(pc)
check(state.processed==state.total and #state.floors==3,"all real floors, including a basement, are covered")
check(state.outOfRange==0,"empty upper squares inside a loaded chunk are not out of range")
check(state.controls==1 and state.finds==5,"native controls, fridge/freezer, TV, radio, terminal and one building alarm stay distinct")
check(dataReads==0 and fridge.data.LF_ControlId==nil,"read-only finds never touch object ModData")
check(#B.list(pc)==1 and B.list(pc)[1].kind=="door","read-only equipment never enters controllable lists")
check(xpCount==1 and panel.scanXpAwarded,"a completed pass awards Electrical XP once")
local foundId="fridge:102:100:-1"
check(panel.finds[foundId]~=nil,"a fridge-freezer produces one stable passive row")
check(B.prepare(pc,"open",foundId,player)==nil,"passive rows cannot be used as control commands")
B.startScan(pc,player,true) complete()
check(xpCount==1,"rediscovery cannot repeat the building award")
for _,row in ipairs(D.state(pc).feed) do check(not row.new,"previously known rows have no NEW flag") end
fridge.square.objects={} definition.alarmed=false
chunk.unloaded=function(x,y,z) return x==102 and y==100 and z==-1 end
world["102:100:-1"]=nil
B.startScan(pc,player,true) complete()
check(D.state(pc).status=="partial" and D.state(pc).outOfRange==1,"unloaded coverage reports Partial rather than Complete")
check(panel.finds[foundId]~=nil,"unloaded old finds are preserved")
check(panel.finds["alarm:"..panel.id]==nil,"an absent building alarm does not leave duplicate or stale singleton rows")
chunk.unloaded=nil
B.startScan(pc,player,true) complete()
check(panel.finds[foundId]==nil,"a vanished find is pruned only after its tile is actually covered")
local known=panel.devices
D.reset()
check(D.state(pc)==nil and panel.devices==known,"reload loses only the cursor, retaining saved equipment")

setup(0)
local neighbour=add("IsoRadio",105,100,0)
local otherDef={getX=function() return 105 end,getY=function() return 100 end,getX2=function() return 110 end,getY2=function() return 104 end}
function neighbour.square:getBuildingDef() return otherDef end
B.startScan(pc,player) complete()
check(panel.finds["radio:105:100:0"]==nil,"survey padding never leaks a neighbouring building's read-only finds")

setup(0)
local secondary=T.computer(world["100:100:0"])
SC.Terminal.computerState(player,secondary).locked=false
panel.connections[B.computerId(secondary)]={x=100,y=100,z=0}
B.startScan(pc,player) tick(100)
check(not B.startScan(secondary,player,true),"a second terminal cannot replace a live scan generation")
D.pause(pc) window.object=secondary
check(B.startScan(secondary,player),"a second connected terminal can explicitly resume a paused building scan")
local progress=D.state(secondary).processed
D.pause(pc)
D.observeWindow({object=pc,closed=true},T.now)
check(not D.abort(pc),"a stale abort from the former computer cannot cancel the new owner's pass")
tick(100)
check(D.state(secondary).processed>progress,"a stale close callback from the first terminal cannot pause the new owner")
secondary.square=T.square(101,100,0,true)
tick(100)
check(D.state(pc).status=="paused","moving a computer invalidates its original connection and stops scanning")

setup(0)
SC.BaseLife={active=function() return {id="base"} end,isInside=function() return true end}
chunk.maxZ=2
B.startScan(pc,player) complete()
check(#D.state(pc).floors==1,"empty camp roof/chunk levels do not become reported inhabited floors")
add("IsoDoor",101,100,1)
B.startScan(pc,player,true) complete()
check(#D.state(pc).floors==2,"a player-built upper level with real equipment is included")

setup(0)
for i=1,256 do panel.devices["old:"..i]={id="old:"..i,kind="light",x=100,y=100,z=0,label="Old"} end
for i=1,256 do panel.finds=panel.finds or {} panel.finds["oldfind:"..i]={id="oldfind:"..i,kind="tv",x=999,y=999,z=0} end
local cappedDoor=add("IsoDoor",101,100,0)
add("IsoRadio",102,100,0)
B.startScan(pc,player) complete()
check(D.state(pc).cappedControls and D.state(pc).cappedFinds and D.state(pc).status=="limited",
    "both independent 256-entry ceilings are visible and truthful")
local controlledCount,findCount=0,0
for _ in pairs(panel.devices) do controlledCount=controlledCount+1 end
for _ in pairs(panel.finds) do findCount=findCount+1 end
check(controlledCount==256 and findCount==256,"neither saved collection grows past its own 256-entry ceiling")
check(cappedDoor.data.LF_ControlId==nil,"a rejected over-cap control does not acquire a phantom control identity")

setup(0)
function player:getXp() return {AddXP=function() xpCount=xpCount+1 error("native XP failure") end} end
B.startScan(pc,player) complete()
B.startScan(pc,player,true) complete()
check(xpCount==1 and panel.scanXpAwarded,"an ambiguous native XP exception is never replayed")
setup(0) B.startScan(pc,player) tick(100) B.abortScan(pc)
check(xpCount==0 and not panel.scanXpAwarded,"Abort never awards completion XP")
setup(0) B.startScan(pc,player)
local loadedReads=reads
T.now=T.now+100 -- admit a real due slice before exhausting its budget
D.pulse(function() return 0 end)
check(reads==loadedReads,"an exhausted scheduler budget performs zero tile reads")
pc.square.generatorPower=false tick(100)
check(D.state(pc).status=="paused","loss of real computer power pauses its scan")

print("BUILDING_SCAN_ENGINE_PASS checks="..checks)
