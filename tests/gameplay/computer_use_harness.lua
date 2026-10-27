-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local Use,Down=SC.ComputerUse,SC.Downtime
local saved={}
for _,key in ipairs({"GameplayUtil","Terminal","BaseLife","Navigation","Commands",
    "NativeActions","ActionSupervisor","Medical","TerminalLore","Dialogue","Diary"}) do saved[key]=SC[key] end
local savedTraits=CharacterTrait
local checks,clock,reads,visited,moves,cancels,notes=0,100000,0,0,0,0,0
local function check(value,message) checks=checks+1 assert(value,"computer use "..checks..": "..message) end
local room,otherRoom={},{}
local function square(x,y,z)
    local p={x=x,y=y,z=z or 0,room=room}
    function p:getRoom() return self.room end
    return p
end
local keyboard=square(10,10)
local computer={square=square(11,10),powered=true,locked=false}
local base={id="computer-test",settings={routines=true}}
local function actor(id)
    local a={id=id,square=keyboard,serial=0}
    function a:faceThisObject(object) self.faced=object end
    function a:hasTrait() return self.illiterate==true end
    return a
end
local a,b=actor("a"),actor("b")
local navigation,window,visual,initCalls=nil,nil,"active",0
SC.BaseLife={active=function() return base end,isInside=function(v) return v and v.outside~=true end}
SC.GameplayUtil={
    call=function(o,m,...)
        if not o or type(o[m])~="function" then return nil,false end
        local okay,value=pcall(o[m],o,...) return value,okay
    end,
    isValidActor=function(v) return v and not v.removed end,isDead=function(v) return v.dead==true end,
    squareOf=function(v) return v and (v.square or v) end,
    position=function(v) local p=v.square or v return p.x,p.y,p.z end,
    sameFloor=function(v,o) return v.square.z==o.square.z end,
    distance=function(v,o) local p,q=v.square or v,o.square or o return math.sqrt((p.x-q.x)^2+(p.y-q.y)^2) end,
    gridSquare=function(x,y,z) reads=reads+1
        if x==11 and y==10 and z==0 then return computer.square end
    end,
    squareObjects=function(p,fn,limit) visited=visited+1 fn(computer) end,
    directInteractionAccess=function(v) return v.atKeyboard==true,v.blocked and {} or {keyboard} end,
    move=function() moves=moves+1 return visual~="reject" end,
    idOf=function(v) return v.id end,stableHash=function() return 7 end,
    actorState=function(_,r) return r end,nowMs=function() return clock end,
    config=function() return nil end,stop=function() cancels=cancels+1 return true end,
    copyShallow=function(t) local c={} for k,v in pairs(t) do c[k]=v end return c end,
}
SC.Terminal={isComputer=function(v) return v==computer end,
    companionAvailable=function(v) return v.powered and not v.locked and window~=v end,
    computerState=function() initCalls=initCalls+1 return {locked=computer.locked} end}
SC.Navigation={requestAny=function(_,targets,_,intent) navigation=intent return true,"moving" end,
    cancel=function() return true end}
SC.Commands={peek=function(v) return {recruited=true,order="stay",commandSerial=v.serial} end,
    noteDowntime=function(_,fact) notes=notes+1 end}
SC.NativeActions={seatingStatus=function() return "standing" end,
    visualStatus=function() return visual end,cancelVisual=function() return true end,
    clearVisual=function() return true end}
SC.ActionSupervisor,SC.Medical,SC.Diary=nil,nil,nil
SC.TerminalLore={REFERENCE={{id="county_notice",title="A dated notice",text="An original county notice."}}}
SC.Dialogue={say=function() return true end}
CharacterTrait={ILLITERATE="illiterate"}
local hooks={seatingStatus=function() return "standing" end,reserved=function() return false end}
local begin=select(4,Down._furnitureForTests())
local stateFor=select(12,Down._furnitureForTests())
local commands={recruited=true,order="stay",commandSerial=0}
local calm={snapshot={threatCount=0,immediateCount=0}}
local function candidate(who) return Use.candidate(who,{},clock,hooks) end
local function start(who)
    local c=candidate(who) check(c~=nil,"usable camp computer is offered")
    check(begin(who,stateFor(who),c,commands,clock)==true,"real downtime owns the computer activity")
    return c
end
local c=candidate(a)
check(c and c.kind=="computer_use" and reads==81 and visited==1,"discovery is bounded to loaded squares")
check(initCalls==0 and moves==0 and notes==0,"candidate probe has no session, action or reward side effects")
for _,key in ipairs({"powered","locked"}) do
    local old=computer[key] computer[key]=not old
    check(candidate(a)==nil,"unavailable or locked computer is excluded: "..key) computer[key]=old
end
window=computer check(candidate(a)==nil,"player window has priority") window=nil
base.settings.routines=false check(candidate(a)==nil,"disabled camp routines are respected") base.settings.routines=true
a.illiterate=true check(candidate(a)==nil,"illiterate companions do not read terminal archives") a.illiterate=nil
a.outside=true check(candidate(a)==nil,"outdoor or visiting non-camp actor cannot use the terminal") a.outside=nil
computer.square.room=otherRoom check(candidate(a)==nil,"computer across a room boundary is excluded") computer.square.room=room
computer.square.z=1 check(candidate(a)==nil,"another floor is excluded") computer.square.z=0
a.blocked=true check(candidate(a)==nil,"no genuine interaction target prevents selection") a.blocked=nil
check(Use.candidate(a,{computerRetryAt=clock+1},clock,hooks)==nil,"failed route backoff is retained")
c=start(a)
check(c.approaching and navigation.action=="move_to_computer" and navigation.workCampOnly,
    "approach uses camp-limited navigation before starting any pose")
check(candidate(b)==nil and Use.claim(b,c)==false,"crew cannot take the same computer")
a.atKeyboard=true
check(Down.update(a,b,calm,"computer_use")==true and c.startedAt==clock and a.faced==computer,
    "arrival starts the verified native pose facing the real computer")
check(notes==0 and c.fact.referenceId==nil,"unfinished visit never records completed reading")
local realFiles=SC.TerminalLore.REFERENCE
SC.TerminalLore.REFERENCE={}
check(not Use.finish(a,c) and c.fact.referenceId==nil,"missing archive cannot produce a fictional reading receipt")
SC.TerminalLore.REFERENCE=realFiles
visual="completed" clock=clock+18000
check(Down.update(a,b,calm,"computer_use")==true and stateFor(a).active==nil,
    "verified completion retires the owned action")
check(notes==1 and stateFor(a).lastFact.referenceId=="county_notice"
    and stateFor(a).ambientLastAt.computer_use==clock,"only completion records the real archive and cooldown")
check(candidate(b)~=nil,"completion releases the computer for another companion")
visual="active" a.atKeyboard=nil
c=start(b)
check(Use.yieldToPlayer(computer)==true and stateFor(b).active==nil,"player access cancels the exact NPC visit")
c=start(a)
check(Down.update(a,b,{snapshot={immediateCount=1}},"computer_use")==false
    and stateFor(a).active==nil,"near danger cancels approach and releases ownership")
c=start(a) a.serial=1
check(Down.update(a,b,calm,"computer_use")==false and stateFor(a).active==nil,"new orders cancel the visit")
a.serial=0
c=start(a) computer.powered=false
check(Down.update(a,b,calm,"computer_use")==false and stateFor(a).active==nil,
    "power loss during approach fails without a completion")
computer.powered=true
check(candidate(b)~=nil,"power failure releases the shared terminal")
stateFor(a).computerRetryAt=nil c=start(a) a.dead=true
check(candidate(b)~=nil,"a dead actor cannot retain a terminal claim") a.dead=nil
Down.reset(a)
c=start(b) Use.reset()
check(not Use.valid(b,c,false),"world reset retires old ownership") Down.reset(b)
-- A crowded square cannot exceed the global object budget.
local originalGrid,originalObjects=SC.GameplayUtil.gridSquare,SC.GameplayUtil.squareObjects
reads,visited=0,0
SC.GameplayUtil.gridSquare=function() reads=reads+1 return computer.square end
SC.GameplayUtil.squareObjects=function(_,fn,limit)
    for _=1,limit do visited=visited+1 if fn({})==false then break end end
end
check(candidate(a)==nil and reads==81 and visited==256,"crowded discovery obeys its whole-probe object budget")
SC.GameplayUtil.gridSquare,SC.GameplayUtil.squareObjects=originalGrid,originalObjects
for _,key in ipairs({"GameplayUtil","Terminal","BaseLife","Navigation","Commands",
    "NativeActions","ActionSupervisor","Medical","TerminalLore","Dialogue","Diary"}) do SC[key]=saved[key] end
CharacterTrait=savedTraits
Use.reset()
print("COMPUTER_USE_PASS checks="..checks.." shared-claims=true interruption=true completion=true bounded=true")
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Camp computer downtime: "..checks.." checks passed"
