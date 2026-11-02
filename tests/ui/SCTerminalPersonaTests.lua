-- SPDX-License-Identifier: MIT
-- Exercise the actual window, persistence and effects, not a second renderer.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local UI,P,S,L,D=SC.TerminalPersonaUI,SC.TerminalPersona,SC.TerminalSystem,SC.TerminalLocks,SC.TerminalDrawers
local check,before=T.check,T.checks
local old={find=D.find,debug=isDebugEnabled,config=SCConfig,claim=D.claim,open=D.open,release=D.release,
    mod=ModData,sandbox=SandboxVars,core=getCore,specific=getSpecificPlayer,
    moodle=SC.GameplayUtil.moodleLevel,char=CharacterStat,sound=addSound,world=getWorld,nativeConfig=SC.Config}
local book={} ModData={getOrCreate=function() return book end} L.reset()
SCConfig={debugPersona="spiffy"} isDebugEnabled=function() return true end
SandboxVars={LivingFellows={LockRealItems=true}}
local claims=0
D.find=function() return {x=100,y=100,z=0,type="desk"} end
D.claim=function(_,_,s) claims=claims+1 s.lock.drawer={x=100,y=100,z=0,type="desk"} end
local player=T.player(101,100,0) local pc=T.computer(T.square(100,100,0,true))
getSpecificPlayer=function() return player end
local legacy=S.create(100,"home",false,false,"old") legacy.fresh=nil
check(not SC.TerminalPersonaDiscovery.settle(legacy,player,pc) and SCConfig.debugPersona=="spiffy","old records cannot turn into personas")
local fresh=S.create(100,"home",false,false,"new")
check(SC.TerminalPersonaDiscovery.settle(fresh,player,pc) and SCConfig.debugPersona==nil and not fresh.fresh,"debug consumes one fresh record only")
check(fresh.lock.kind=="persona" and fresh.theme=="sand" and claims==1,"debug installs SPIFFY with native claim path")
SCConfig=nil SC.Config={debugPersona="spiffy"}
local native=S.create(101,"home",false,false,"native-config")
check(SC.TerminalPersonaDiscovery.settle(native,player,pc) and SC.Config.debugPersona==nil,"actual SC.Config namespace supports single-use override")
SC.Config=old.nativeConfig
SCConfig={debugPersona="spiffy"} isDebugEnabled=function() return false end
check(not SC.TerminalPersonaDiscovery.settle(S.create(102,"home",false,false,"not-debug"),player,pc),"public non-debug engine cannot create persona via override")
SCConfig={} isDebugEnabled=function() return true end
pc.data.movableData={LF_LarchOS=fresh}
fresh.lock.home={x=100,y=100,z=0}
fresh.lock.effects={noiseAt=98.5,reliefDay=3,cheerDay=4,weight=1}
fresh.lock.persona.gentleUntil=300
local normalized=S.normalize(fresh)
check(normalized.lock.persona.id=="spiffy" and normalized.lock.persona.gentleUntil==300
    and normalized.lock.effects.noiseAt==98.5 and normalized.lock.home.x==100,"save retains conversation safeguard, home and effect receipts")
local bad=S.normalize(fresh) bad.lock.persona.id="unknown"
check(S.normalize(bad).lock.kind=="word","unknown persona retains computer as an ordinary lock")
for _,seed in ipairs({0,-1,1/0,0/0}) do
    local malformed=S.normalize(fresh) malformed.lock.persona.seed=seed
    local repaired=S.normalize(malformed)
    check(repaired.lock.kind=="persona" and repaired.lock.persona.seed==1
        and #P.respond(repaired.lock.persona,P.session(),"hello",{moodles={}}).rows>0,
        "malformed saved seed drops one field while retaining a playable machine")
end
local normalizer=P.normalize P.normalize=function() error("damaged conversation extension") end
check(S.normalize(fresh).lock.kind=="word","normalizer failure cannot erase or crash a computer record")
P.normalize=normalizer
check(not L.WEIGHTS.persona and L.kind(fresh)=="persona","persona is outside lock Director weights")
L.markSeen(fresh) check(not book.seen.persona,"persona cannot pollute Recovery Log")
check(SC.Terminal.open(player,pc),"real window opens persona record")
local w=SC.Terminal.window
check(w.startupReady and w.state=="idle" and #w.rows==0 and #w.queue==0
    and not w.bootSoundStarted,"first contact is silent, without BIOS or boot audio")
check(w.closeButton.visible==false and w.entry.x==-10000 and w.entry.focused and w.entry.maxLength==160,"hidden native child retains focused input")
check(not SC.TerminalLamp.active(w),"blank screen has no threat lamp")
w.entry:setText("123") w:entryChanged()
check(#w.rows==0 and w.entry:getText()=="123","digits never trigger menu or a lock page")
w:otherKey(Keyboard.KEY_TAB) check(w.focusMode=="chat" and w.lockPage==nil,"Tab leaves conversation input alone")
w.entry.javaObject={getInternalText=function() return "hello123" end}
check(UI.entryText(w)=="hello123","native input buffer wins over a stale widget string")
w.entry.javaObject=nil w.entry:setText("hello") w:submit()
check(w.state=="thinking" and #w.queue>0 and w.personaSession.turns==1,"actual Enter path reaches supplied engine")
local frame=w:readingFrame(T.now)
check(#frame.extra==0,"thinking pause paints no spinner or diagnostic caption")
w:flush() check(w.state=="idle" and w.personaFinishedAt==T.now,"skip finishes reply and starts pause clock")
local session=w.personaSession w:close() SC.Terminal.open(player,pc) w=SC.Terminal.window
check(w.personaSession~=session and w.system.lock.persona.met,"reopening makes a new session and retains machine memory")
local count=0 SC.GameplayUtil.moodleLevel=function(_,key) check(key==string.upper(key),"moodle uses actual native uppercase name") count=count+1 return 2 end
local f=UI.facts(w,T.now,true)
check(count==8 and f.moodles.tired==2 and f.moodles.unhappy==2,"all moodles read through native helper")
SC.GameplayUtil.moodleLevel=old.moodle
local opened=0 D.open=function(_,_,_,forced,granted) check(not forced and granted,"persona requests its own granted drawer") opened=opened+1 return false end
UI.reply(w,{rows={{text="PROMISED DRAWER"}},effects={drawer=true},speed=80,thinkMs=0},{hours=T.hours})
check(opened==1 and not w.system.lock.persona.flags.drawer_done and w.queue[1].text~="PROMISED DRAWER","failed native release replaces promised success")
w:flush()
local values={STRESS=.6,UNHAPPINESS=50,BOREDOM=60}
CharacterStat={STRESS="STRESS",UNHAPPINESS="UNHAPPINESS",BOREDOM="BOREDOM"}
function player:getStats() return {remove=function(_,key,value) values[key]=math.max(0,values[key]-value) end,
    add=function(_,key,value) values[key]=values[key]+value end} end
w.system.lock.effects={}
local sounds=0 addSound=function(_,_,_,_,radius,volume) check(radius==40 and volume==40,"native sound radius is 40") sounds=sounds+1 end
getWorld=function() return {getFreeEmitter=function() return {playSound=function(_,name) check(name=="LFSpiffyJingle","real jingle event") end} end} end
for _=1,4 do UI.effects(w,{noise=true,relief=true,cheer=true,weight=true},{hours=120}) end
check(sounds==1 and math.abs(values.STRESS-.45)<.001 and values.UNHAPPINESS==30 and values.BOREDOM==35,"effects apply correct amounts and cooldowns; weight capped twice")
local reload=S.normalize(w.system) w.system.lock.effects=reload.lock.effects
UI.effects(w,{noise=true,relief=true,cheer=true,weight=true},{hours=120.9})
check(sounds==1 and values.BOREDOM==35,"reload preserves sound and daily effect cooldowns")
UI.effects(w,{noise=true,cheer=true},{hours=144})
check(sounds==2 and values.BOREDOM==10,"cooldowns resume after game time advances")
-- Previous-owner stash modifiers must not inject child items or water into a
-- persona reward. Crowbars must still receive ordinary contents, never the suit.
local recipe
for id,row in pairs(SC.TerminalLockStashes) do if row.child or row.water then recipe=id break end end
check(recipe~=nil,"real stash recipe fixture available")
w.system.archive=recipe w.system.lock.persona.flags.hired=true w.system.lock.stash=nil
local stock,serial,children={},0,0
local desk={getSquare=function() return pc:getSquare() end}
local c={getType=function() return "desk" end,getParent=function() return desk end}
function c:AddItem(kind)
    serial=serial+1
    local item={getID=function() return serial end,getFullType=function() return kind end,
        getContainer=function() return c end,getDisplayName=function() return kind end,
        getInventory=function() children=children+1 return nil end}
    stock[#stock+1]=item return item
end
check(SC.TerminalPayoff.place(player,pc,w.system,c,false) and #stock==4 and children==0
    and not w.system.lock.stash.note,"persona reward keeps exact contents without unrelated recipe or owner note")
local forced=SC.TerminalPayoff.items(w.system,true)
for _,kind in ipairs(forced) do check(kind~="Base.SpiffoSuit","crowbar cannot award the manager suit") end
-- Compare available lines and painted coordinates at compact/full resolutions.
for _,size in ipairs({{1024,768},{1280,720},{1920,1080},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    w:refreshLayout() w.queue,w.typing,w.rows={},nil,{} w.state="idle" w.entry:setText("typed prompt")
    check(w.entry.x==-10000 and w:viewTop()==w.layout.titleY and w:viewBottom()>w.layout.bottom,"resize keeps input hidden and reclaims header/hint rows")
    local draw=w.drawRow local rows={}
    w.drawRow=function(self,line,y,kind)
        check(y>=self:viewTop() and y+self.rowHeight<=self:viewBottom()+2,"persona text stays on glass") rows[#rows+1]=line
    end
    w:prerender() w.drawRow=draw
    check(#rows==1 and rows[1]:find("typed prompt",1,true),"blank persona paints prompt only at each resolution")
end
getCore=old.core
local release=0 D.release=function() release=release+1 end
w.system.lock.drawer={open=false,forced=false} w.personaEnding="shutdown"
UI.powerCut(w,T.now)
check(w.state=="closing" and w.personaEnding==nil and w.system.locked and release==0,"power loss cancels pending shutdown without unlocking or releasing reward")
w:close()
D.find,D.claim,D.open,D.release=old.find,old.claim,old.open,old.release
isDebugEnabled,SCConfig,ModData,SandboxVars,getSpecificPlayer=old.debug,old.config,old.mod,old.sandbox,old.specific
SC.Config=old.nativeConfig
CharacterStat,addSound,getWorld=old.char,old.sound,old.world
L.reset()
SC_TEST_REPORT=SC_TEST_REPORT.."; Persona native UI glue: "..(T.checks-before).." checks passed"
