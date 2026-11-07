-- SPDX-License-Identifier: MIT
local SC=SurvivorCompanion
local checks=0
local function check(v,message) checks=checks+1;assert(v,message) end
local clock,hour,age=0,10,0
local rows,zombies,squares={}, {}, {}
local spawned,moved,said,lastGoal=0,0,0,nil
local function list(items)
    return {size=function() return #items end,get=function(_,i) return items[i+1] end}
end
local cell={}
local function square(x,y,z)
    local key=x..":"..y..":"..z
    if squares[key] then return squares[key] end
    local sq={x=x,y=y,z=z or 0}
    function sq:getX() return self.x end;function sq:getY() return self.y end;function sq:getZ() return self.z end
    function sq:getCell() return cell end;function sq:getChunk() return {} end
    function sq:isSolid() return false end;function sq:isSolidTrans() return false end
    function sq:TreatAsSolidFloor() return true end;function sq:isSafeToSpawn() return true end
    function sq:isFree() return true end;function sq:getRoom() return nil end
    function sq:isCanSee() return self.visible==true end
    function sq:getMovingObjects()
        local found={};for _,v in ipairs(zombies) do if not v.removed and v.x==x and v.y==y and v.z==z then found[#found+1]=v end end
        return list(found)
    end
    squares[key]=sq;return sq
end
function cell:getGridSquare(x,y,z) return square(x,y,z) end
local function character(x,y,z,kind)
    local a={x=x,y=y,z=z or 0,kind=kind}
    function a:getX() return self.x end;function a:getY() return self.y end;function a:getZ() return self.z end
    function a:getCell() return cell end;function a:getCurrentSquare() return square(self.x,self.y,self.z) end
    function a:getPlayerNum() return 0 end;function a:isDead() return false end
    function a:getTarget() return self.target end
    function a:removeFromWorld() self.removed=true end;function a:removeFromSquare() self.offSquare=true end
    return a
end
local player=character(0,0,0,"player")
SC.GameplayUtil={
    nowMs=function() return clock end,position=function(a) if a then return a.x,a.y,a.z end end,
    call=function(a,k,...) if a and type(a[k])=="function" then return a[k](a,...),true end return nil,false end,
    isZombie=function(a) return a and a.kind=="zombie" and not a.foreign end,
    isDead=function(a) return not a end,isCorpseProxy=function(a) return a.proxy end,
    canSee=function(_,a) return a.visible==true end,squareOf=function(a) return a and a:getCurrentSquare() end,
    sameFloor=function(a,b) return a.z==b.z end,
    distance=function(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end,
    gridSquare=function(x,y,z) return square(math.floor(x),math.floor(y),z) end,
    isSquareFree=function() return true end,stop=function() return true end,
}
SC.Registry={records=function() return rows end,living=function() return rows end,
    idOf=function(a) return a and a.id end,byId=function(id) for _,r in ipairs(rows) do if r.id==id then return r end end end}
SC.BaseLife={active=function() return nil end}
local history=false
SC.Persistence={hasWorldHistory=function() return history end}
SC.Vehicle={storedCount=function() return 0 end}
SC.Encounter={chooseSpawnSquare=function() return square(60,0,0) end}
SC.Navigation={request=function(_,goal,mode,options) moved=moved+1;lastGoal=goal;check(mode=="sneak" and options.action=="approach_player_cautiously","first meeting uses native cautious pathing");return true,"path" end}
SC.Dialogue={say=function(_,topic) check(topic=="guidance.first_meeting","call-out uses a dialogue pool");said=said+1;return true end}
getGameTime=function() return {getTimeOfDay=function() return hour end,getWorldAgeHours=function() return age end} end
local actor=character(60,0,0,"companion");actor.id="sc-first"
SC.Actor={checkBridge=function() return true end,isCompanion=function(a) return a.kind=="companion" end,
    beginSpawn=function() spawned=spawned+1;return "ticket" end,
    pollSpawn=function() rows={{id=actor.id,actor=actor,recruited=false}};return actor end}
local F,S=SC.FirstMeeting,SC.SpawnSafety
local indoor=square(60,1,0);indoor.getRoom=function() return {} end
SC.Navigation.spawnAccessible=function() return true end
SC.Encounter.chooseSpawnSquare=function() return indoor end
check(SC.Spawn.chooseSquare(player,{},true)==indoor,"ordinary encounters retain accessible indoor placements")
local outdoor=SC.Spawn.chooseSquare(player,{},true,true)
check(outdoor and outdoor~=indoor and outdoor:getRoom()==nil,"first arrivals choose outside an unfamiliar house")
SC.Encounter.chooseSpawnSquare=function() return square(60,0,0) end
SC.Spawn.reset();F.reset()
SC.Spawn.productionPulse(player,{active=true},0)
zombies={character(61,0,0,"zombie"),character(85,0,0,"zombie"),character(91,0,0,"zombie"),character(61,0,1,"zombie")}
clock=60000
check(SC.Spawn.productionPulse(player,{active=true},60000)==false and spawned==0,"safety preparation happens before actor creation")
local status,detail
for i=1,80 do clock=60000+i*100;status,detail=SC.Spawn.pollPending();if status=="spawned" or status=="failed" then break end end
check(status=="spawned" and spawned==1,"bounded safety slices complete the real spawn path: "..tostring(status)..":"..tostring(detail))
check(zombies[1].removed and zombies[2].removed and not zombies[3].removed and not zombies[4].removed,"first arrival clears thirty metres on its own floor only")
check(F.export().attempts==1 and F.export().phase=="approaching","first meeting retains its attempt and actor identity")
F.approach(actor,player,{threatCount=1});check(moved==0,"a threat keeps normal survival AI in charge")
F.approach(actor,player,{});check(moved==1,"first survivor approaches rather than wandering away")
check(lastGoal==player:getCurrentSquare(),"opaque walls do not strand the visitor at a blind twelve-metre circle")
actor.x=12;actor.visible=true;F.approach(actor,player,{})
F.approach(actor,player,{})
check(said==1 and F.export().phase=="waiting","call-out plays once and the visitor stays to be met")
local handled,why=F.approach(actor,player,{})
check(handled==nil and why=="first_meeting_nearby","a waiting visitor may scavenge within reach")
local cancelled,before=0,moved
SC.Encounter.cancelScavenge=function() cancelled=cancelled+1;return true end
actor.x=40;F.approach(actor,player,{})
check(moved==before+1 and cancelled==1,"a visitor beyond reach drops the search and walks back")
actor.x=18;clock=clock+1000;F.approach(actor,player,{})
check(moved==before+2,"the walk back ends at the usual waiting distance")
actor.x=12;handled,why=F.approach(actor,player,{})
check(handled==true and why=="first_meeting_waiting","a returned visitor holds still before searching again")
clock=clock+60000;handled,why=F.approach(actor,player,{})
check(handled==nil and why=="first_meeting_nearby","nearby scavenging resumes after the return hold")
actor.z=1;handled,why=F.approach(actor,player,{});actor.z=0
check(handled==true and why=="first_meeting_waiting","a visitor on another floor waits rather than wandering")
handled=F.approach(actor,player,{threatCount=1})
check(handled==nil,"danger hands a waiting visitor back to survival AI")
local waiting=F.export();F.reset();check(F.restore(waiting) and F.export().phase=="waiting","waiting survives reload")
age=1.9;F.pulse();check(F.export().phase=="waiting","the visitor waits up to two game hours")
age=2;F.pulse();handled,why=F.approach(actor,player,{})
check(F.export().phase=="done" and handled==nil and why==nil,"after two game hours the visitor returns to its own routine")
age=0;check(F.restore(waiting),"the waiting receipt can be recovered")
F.recruited();local receipt=F.export();F.reset();check(F.restore(receipt) and not F.wants(),"recruitment stays finished across reload")
local bad=F.export();bad.rearms=3
check(not F.restore(bad) and not F.wants(),"corrupt receipts fail closed without new clearing")
check(F.restore(receipt),"a valid receipt can be recovered")
F.reset();history=true;check(not F.wants(),"existing LF history is never treated as a new world")
history=false;F.reset();check(F.wants(),"a fresh world arms the guarantee")
for i=1,10 do clock=i*60000;check(F.ready(clock),"bounded retry becomes due");F.attempted(clock) end
clock=660000;check(not F.ready(clock) and F.export().phase=="lapsed","ten failed attempts end the guarantee")
F.reset();F.wants();F.spawned(actor);F.retired(actor.id);check(F.export().rearms==1,"unloading before contact rearms once")
F.spawned(actor);F.retired(actor.id);F.spawned(actor);F.retired(actor.id)
check(F.export().rearms==2 and F.export().phase=="lapsed","unload rearming is capped at two")
F.reset();F.wants();F.spawned(actor);age=3;F.pulse();check(F.export().phase=="lapsed","approach expires after two game hours")
SC.Config.refreshSandbox({LivingFellows={EncountersEnabled=true,FirstMeetingEnabled=false}})
F.reset();check(not F.wants(),"sandbox switch disables the guarantee")
SC.Config.refreshSandbox({LivingFellows={EncountersEnabled=false,FirstMeetingEnabled=true}})
check(not F.wants(),"independent encounters off also disables the guarantee")
SC.Config.refreshSandbox({LivingFellows={EncountersEnabled=true,FirstMeetingEnabled=true}})
local function protected(flag)
    local zombie=character(61,0,0,"zombie");zombie[flag]=true
    if flag=="target" then zombie.target=player end
    zombies={zombie}
    local job=S.begin(square(60,0,0),player,8);local result
    for i=1,10 do result=S.step(job);if result~="pending" then break end end
    check(not zombie.removed,"protected actor is not removed: "..flag)
    if flag=="visible" or flag=="target" then check(result=="failed","active danger rejects placement") end
end
for _,flag in ipairs({"visible","target","foreign","proxy"}) do protected(flag) end
print("FIRST_MEETING_KAHLUA_PASS checks="..checks)
