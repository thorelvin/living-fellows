-- SPDX-License-Identifier: MIT
-- Real terminal entry, shared ModData and action tickets, using existing UI fixtures.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local M,B,Terminal=SC.EmmaMind,SC.TerminalBrain,SC.Terminal
local check,before=T.check,T.checks
local old={mod=ModData,specific=getSpecificPlayer,world=SC.TerminalWorld.new,perks=Perks,
    services=SC.TerminalServices,tool=SC.ControlUtil.hasTool,contains=SC.GameplayUtil.containerContainsIdentity,
    clock=Terminal._clock}
local buckets={}
ModData={getOrCreate=function(key) buckets[key]=buckets[key] or {};return buckets[key] end}
local player=T.player(101,100,0);local data={}
function player:getModData() return data end
function player:getPerkLevel() return 2 end
getSpecificPlayer=function(index) return index==0 and player or nil end
Perks={Electricity="Electrical"}
Terminal._clock=function() return T.now end
local world={camp=function() return {configured=false} end,people=function() return {} end,
    power=function() return {source="grid"} end,clock=function() return {worldHours=T.hours} end}
SC.TerminalWorld.new=function() return world end
local function pc(id,x)
    local object=T.computer(T.square(x or 100,100,0,true))
    object.data.movableData={LF_LarchOS=SC.TerminalSystem.create(29,"home",true,true,id)}
    return object
end
local a,b=pc("mind-a"),pc("mind-b",102)
a.data.movableData.LF_Emma={operator="Scout",visits=3,lastSeen=99,notes={"gate key","water in shed"}}
local legacy=a.data.movableData.LF_Emma
local function open(object)
    check(Terminal.open(player,object),"shared terminal opens")
    Terminal.window:flush();return Terminal.window
end
local function say(w,text)
    local reply=B.respond(w.session,text,world)
    check(reply and not reply.error,"production shared reply: "..text)
    if reply.memoryChanged then Terminal.writeMemory(w.object,w.session,T.hours) end
    return reply
end
local function has(reply,text) return table.concat(reply.lines," "):find(text,1,true)~=nil end
Terminal.reset()
local wa=open(a)
check(wa.session.emmaMind and wa.session.operator=="Scout" and #wa.session.notes==2,"first boot migrates name and notes")
check(M.state().fragmentCount==1 and a.data.movableData.LF_Emma==legacy and legacy.visits==3,"migration leaves legacy record untouched")
say(wa,"remember spare axe in garage");wa:close()
local wb=open(b)
check(wb.session.operator=="Scout" and has(say(wb,"notes"),"spare axe in garage"),"another PC knows this operator and shared notes")
check(has(say(wb,"are you the same emma"),"shared notebook"),"one-mind questions explain the actual shared scope")
check(M.state().fragmentCount==2 and wb.session.noteLimit==12,"second fragment expands notebook")
M.enter(player,Terminal.peekState(a),a.data.movableData,{hours=100,name="Thor",kind="clinic"},legacy)
check(M.state().domains.body==0,"moving a previously credited home computer to a clinic cannot unlock a domain")
local proposal=say(wb,"forget everything")
check(not proposal.proposal and #M.state().notes==3 and has(proposal,"Which shared note"),"generic forget asks which notes")
local request=say(wb,"forget note 1")
local ticket=SC.TerminalActions.prepare(wb,request.proposal)
check(ticket~=nil,"specific shared note needs a real confirmation")
say(wb,"remember new note while confirmation waits")
check(SC.TerminalActions.execute(wb,ticket)==false and #M.state().notes==4,"stale revision cannot erase a different shared note")
request=say(wb,"forget note 1");ticket=SC.TerminalActions.prepare(wb,request.proposal)
check(SC.TerminalActions.execute(wb,ticket)==true and M.state().notes[1]=="water in shed","confirmed deletion erases only selected note")
check(SC.TerminalActions.execute(wb,ticket)==false,"delete confirmation cannot replay")
local count=M.state().fragmentCount
check(Terminal.factoryReset(wb) and M.state().fragmentCount==count and #M.state().notes==3,"factory reset preserves shared mind")
wb:boot();wb:flush();wb:close()
a.square.x=99
wa=open(a)
check(M.state().fragmentCount==count and #M.state().notes==3,"moving/reopening cannot duplicate fragment or resurrect deleted legacy note")
wa:close();Terminal.reset()
wa=open(a)
check(#wa.session.notes==3 and M.state().fragmentCount==2,"runtime reset preserves world memory")
wa:close()
-- A new character has a separate identity; the world notes and fragments survive.
local first=player;player=T.player(101,100,0);local newData={}
function player:getModData() return newData end
wa=open(a)
check(wa.session.operator=="Thor" and wa.session.emmaMind.operator~=data[M.OPERATOR_KEY]
    and #wa.session.notes==3,"new character inherits county memory without the dead operator's alias or thread")
wa:close();player=first
local state=M.state()
for index=3,25 do
    local portable={};local kind=index==3 and "clinic" or "home"
    M.enter(player,{identity="fragment-"..index,locked=false},portable,{hours=100,name="Thor",kind=kind},{})
end
check(M.state().fragmentCount==25 and M.tier(25)==6 and M.noteLimit(25)==20,"all planned tier thresholds fit within a long run")
check(M.state().domains.body>0 and M.state().domains.calendar>0,"specialist kind and twelve-fragment fallback unlock indexes")
local persona={}
check(M.enter(player,{identity="persona",locked=false,lock={kind="persona"}},persona,{kind="clinic"},{})==nil
    and M.state().fragmentCount==25,"persona never contributes a fragment")
check(M.enter(player,{identity="persona",locked=false},persona,{kind="clinic"},{})==nil,"factory-cleaned persona remains excluded")
local malformed=M.normalize({notes={false,"ok"},operators="broken",fragments="broken",domains={body="bad"}})
check(#malformed.notes==1 and malformed.fragmentCount==0 and malformed.domains.body==0,"malformed buckets normalize independently")
local large={};for index=1,513 do large["pc-"..index]={kind="home",day=1} end
check(M.normalize({fragments=large,fragmentCount=99999}).fragmentCount==512,"fragment ledger is bounded and does not trust a saved count")
-- Native-shaped battery values verify charge accounting and foreground lease expiry.
local inventory={items={}}
function inventory:getItems() return {size=function() return #inventory.items end,get=function(_,i) return inventory.items[i+1] end} end
function player:getInventory() return inventory end
local battery={charge=.8}
function battery:getFullType() return "Base.CarBattery2" end
function battery:getCondition() return 100 end
function battery:getContainer() return inventory end
function battery:getCurrentUsesFloat() return self.charge end
function battery:setCurrentUsesFloat(value) self.charge=value end
inventory.items={battery}
SC.GameplayUtil.containerContainsIdentity=function(container,item) for _,v in ipairs(container.items) do if v==item then return true end end return false end
SC.ControlUtil.hasTool=function() return true end
local dark=pc("jump-pc");dark.square.generatorPower=false
local identity=Terminal.peekState(dark).identity
battery.charge=.04
check(SC.EmmaJump.connect(player,dark,battery,identity)==false and battery.charge==.04,"insufficient charge cannot start or consume a connection")
battery.charge=.8
check(SC.EmmaJump.connect(player,dark,battery,identity)==true and math.abs(battery.charge-.75)<.00001,"connection consumes exactly five percent once")
local w=Terminal.window;w:flush()
check(Terminal.powered(dark) and not Terminal.normalPowered(dark) and not Terminal.companionAvailable(dark),"lease powers UI but not companion services")
check(SC.EmmaJump.connect(player,dark,battery,identity)==false and math.abs(battery.charge-.75)<.00001,"repeated connection cannot charge twice")
local denied=SC.TerminalActions.prepare(w,{kind="refuel_generator"})
check(not denied,"jump session cannot submit camp work or building effects")
local os=Terminal.peekState(dark)
os.locked=true
os.lock={kind="word",settled=true,crack={doneHours=0,lastHours=T.hours,powered=false,requiredHours=12}}
local oldHours=T.hours
for _=1,2 do
    T.hours=T.hours+1
    SC.TerminalLocks.settle(os,player,dark,false)
end
check(os.lock.crack.doneHours==0 and not os.lock.crack.powered,"reopening a jump-powered lock cannot credit background cracking")
os.locked=false;os.lock.crack=nil;T.hours=oldHours
T.now=T.now+SC.EmmaJump.SESSION_MS+1
SC.EmmaJump.watch(w,T.now)
check(w.state=="closing" and not Terminal.powered(dark),"ten real minutes end borrowed power")
w:close()
check(not SC.EmmaJump.active(player,dark) and math.abs(battery.charge-.75)<.00001,"close clears lease without refund or further deduction")
check(SC.EmmaJump.connect(player,dark,battery,identity)==true,"a second paid connection can boot again")
Terminal.window:close();check(not Terminal.powered(dark),"early close ends borrowed power immediately")
Terminal.reset()
ModData,getSpecificPlayer,SC.TerminalWorld.new,Perks=old.mod,old.specific,old.world,old.perks
SC.TerminalServices,SC.ControlUtil.hasTool,SC.GameplayUtil.containerContainsIdentity=old.services,old.tool,old.contains
Terminal._clock=old.clock
print("EMMA_MIND_PASS checks="..(T.checks-before))
