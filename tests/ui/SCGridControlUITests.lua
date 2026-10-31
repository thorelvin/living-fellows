-- SPDX-License-Identifier: MIT
local SC,T=SurvivorCompanion,TERMINAL_TEST
local G,UI=SC.GridControl,SC.TerminalGridUI
local check,before=T.check,T.checks
local bucket,shut={},26
ModData={getOrCreate=function() return bucket end,get=function() return bucket end}
function getSandboxOptions() return {getElecShutModifier=function() return shut end,
    set=function(_,_,value) shut=value end,toLua=function() end} end
function getWorld() return {getWorldAgeDays=function() return 40 end} end
function isClient() return false end
function isServer() return false end
SC.GameplayUtil.nowMs=function() return T.now end
SC.Terminal._clock=function() return T.now end
SC.BaseLife={active=function() return nil end,isInside=function(object) return object.home==true end}
local player=T.player(10384.5,10096.5,0)
getSpecificPlayer=function(index) return index==0 and player or nil end
local pc=T.computer(T.square(10384,10096,0,true))
pc.hardware={on=true,generation=0,radio={id=5}}
SC.TerminalHardware={state=function(object) return object.hardware end,
    powered=function(object) return object.square.generatorPower==true or G.yardSupply(object,object.hardware) end,
    beginUse=function() end,endUse=function() end,weight=function() return 0 end,
    beforePickup=function(object) return not G.pinned(object) end}
G.reset()
local system=SC.Terminal.computerState(player,pc) system.locked=false
local originalBrand=system.brand
check(SC.Terminal.open(player,pc),"open substation computer")
local w=SC.Terminal.window w:flush()
check(w.gridSite=="muldraugh" and w.brand=="KnoxValleyPower" and system.brand==originalBrand,
    "substation header is a display override preserving the portable owner")
check(#w:menuOptions()==3 and w:menuOptions()[1].gridAction=="connect","yard has compact connection menu")
local function choose(index)
    w:setFocusMode("menu") w.entry:setText(tostring(index)) w:submit() w:flush()
end
choose(1)
check(w.requestTicket~=nil,"connecting asks for confirmation")
w.entry:setText("n") w:submit() w:flush()
check(w.requestTicket==nil and pc.data.movableData[G.CONNECT_KEY]==nil,"declining connection changes nothing")
choose(1) w.entry:setText("y") w:submit() w:flush()
check(pc.data.movableData[G.CONNECT_KEY]~=nil,"confirmed connection starts")
check(not SC.TerminalHardware.beforePickup(pc),"accepted permanent installation cannot be picked up during setup")
T.hours=T.hours+0.5 G.sample(pc)
check(G.pinned(pc) and G.yardSupply(pc,pc.hardware),"finished computer is bound to its own yard")
check(#w:menuOptions()==2,"connected yard retains status and logoff")
choose(1)
check(UI.active(w) and w:sidebarWidth()==0,"grid program uses the whole screen")
UI.update(w,T.now)
local clocks,reads,queries=0,0,0
local oldSnapshot=G.snapshot
G.snapshot=function(...) queries=queries+1 return oldSnapshot(...) end
for index=1,60 do UI.draw(w,index*16) end
check(queries==0,"sixty redraws never query world or grid state")
UI.update(w,T.now+500)
check(queries==0,"status polling is limited to once per second while open")
UI.update(w,T.now+1000)
check(queries==1,"open program refreshes on its bounded interaction poll")
G.snapshot=oldSnapshot
for _,height in ipairs({360,500,760}) do
    local oldTop,oldBottom=w.viewTop,w.viewBottom
    w.viewTop=function() return 10 end w.viewBottom=function() return height end
    UI.draw(w,T.now)
    check(#w.gridHits<=5,"status keeps at most five numbered controls")
    for _,hit in ipairs(w.gridHits) do
        check(hit.y>=10 and hit.y+hit.height<=height,"grid menu stays inside the readable screen")
    end
    w.viewTop,w.viewBottom=oldTop,oldBottom
end
w:otherKey(Keyboard.KEY_ESCAPE)
check(not UI.active(w) and w.menuPage==nil,"Escape returns the yard to its read-only home menu")
w.menuPage="home_services"
local found
for _,option in ipairs(w:menuOptions()) do if option.gridAction=="open" then found=true end end
check(found,"grid control remains available through local services")
local oldRadioUI=SC.TerminalRadioUI
SC.TerminalRadioUI={active=function() return false end,update=function() end}
local services=w:menuOptions()
check(#services==5 and services[4].label=="More services","fitted radio and grid keep local services within five shortcuts")
w.menuPage="home_services_more"
check(#w:menuOptions()==3 and w:menuOptions()[2].label=="Expedition station","overflow retains upgrades and expedition station")
SC.TerminalRadioUI=oldRadioUI
w:close()
player.x,player.y=11000.5,10000.5
local home=T.computer(T.square(11000,10000,0,true)) home.home=true
home.hardware={on=true,generation=0,radio={id=6}}
SC.Terminal.computerState(player,home).locked=false
check(SC.Terminal.open(player,home),"open a normal camp computer")
w=SC.Terminal.window w:flush()
check(w.gridSite==nil,"ordinary computers retain their normal home menu")
UI.open(w) w.gridPage="sites" UI.update(w,T.now+2000)
check(#UI.options(w)<=5,"substation list paginates within five shortcuts")
UI.input(w,"",{gridAction="site",gridValue="muldraugh"})
check(w.requestTicket~=nil,"linked site offers its own crack confirmation")
local ticket=w.requestTicket
home.hardware.radio=nil
local okay=SC.TerminalActions.execute(w,ticket)
check(not okay and pc.data.movableData[G.CRACK_KEY]==nil,"confirmation revalidates mounted radio")
w:cancelRequest() home.hardware.radio={id=6}
UI.input(w,"",{gridAction="site",gridValue="muldraugh"})
ticket=w.requestTicket
check(SC.TerminalActions.execute(w,ticket),"confirmed base crack starts")
check(not SC.Terminal.companionAvailable(home),"companions leave a cracking computer alone")
check(not SC.TerminalActions.execute(w,ticket),"confirmation cannot replay")
local oldTop,oldBottom,oldDraw=w.viewTop,w.viewBottom,w.drawText
local drawn={}
w.viewTop=function() return 0 end w.viewBottom=function() return w.rowHeight*8 end
w.drawText=function(_,value) drawn[#drawn+1]=value end
w.gridSnapshot={visible=true,on=false,heat=0,online=0,linked=1,
    crack={label="Muldraugh",percent=40,requiredHours=96,doneHours=38.4}}
w.requestTicket=nil w.gridPage="status"
UI.draw(w,T.now)
check(table.concat(drawn," "):find("CRACK 40.0%",1,true)~=nil,
    "large-font viewport shows critical crack progress before optional status decoration")
drawn={}
w.gridSnapshot={visible=true,on=false,heat=100,locked=true,coolingHours=168,cooldownDays=7}
UI.draw(w,T.now)
check(table.concat(drawn," "):find("COOLING: 7d 0h",1,true)~=nil,
    "small viewport retains the tripped breaker's restart wait")
w.viewTop,w.viewBottom,w.drawText=oldTop,oldBottom,oldDraw
w:cancelRequest() w:close()

-- A camp computer beside a substation keeps its screen; it connects from the grid page.
player.x,player.y=14780.5,4080.5
local beside=T.computer(T.square(14780,4080,0,true)) beside.home=true
beside.hardware={on=true,generation=0,radio={id=7}}
SC.Terminal.computerState(player,beside).locked=false
check(SC.Terminal.open(player,beside),"open a camp computer beside a substation")
w=SC.Terminal.window w:flush()
check(w.gridSite==nil and w.brand~="KnoxValleyPower","a camp computer near a substation keeps its header")
local yardOnly=false
for _,row in ipairs(w:menuOptions()) do if row.gridAction=="connect" then yardOnly=true end end
check(not yardOnly and w:menuOptions()[1].label~="Substation status","its home menu is the ordinary one")
UI.open(w) UI.update(w,T.now+3000)
local first=UI.options(w)[1]
check(first.gridAction=="connect" and #UI.options(w)<=5,"the grid page offers the connection within five shortcuts")
check(UI.input(w,"",first) and w.requestTicket~=nil,"choosing it asks for confirmation")

-- A notice arriving during that question must not replace it.
local function screen()
    local rows={}
    local oldTop,oldBottom,oldDraw=w.viewTop,w.viewBottom,w.drawText
    w.viewTop=function() return 0 end w.viewBottom=function() return w.rowHeight*12 end
    w.drawText=function(_,value) rows[#rows+1]=value end
    UI.draw(w,T.now)
    w.viewTop,w.viewBottom,w.drawText=oldTop,oldBottom,oldDraw
    return table.concat(rows," ")
end
check(screen():find("Permanently connect",1,true)~=nil,"the question is on screen")
bucket.unread={"Grid heat 75%. Switch off early to shorten the cooling wait."}
UI.update(w,T.now+5000)
check(screen():find("Permanently connect",1,true)~=nil and screen():find("Grid heat",1,true)==nil,
    "a notice during a confirmation leaves the question on screen")
check(w.gridNotice:find("Grid heat 75",1,true)==1,"that notice is kept for the status line")
w.entry:setText("n") w:submit() w:flush()
check(w.requestTicket==nil and beside.data.movableData[G.CONNECT_KEY]==nil,"declining still changes nothing")

-- Notices reach any open page, not only LARCH/GRID.
UI.back(w) w.menuPage=nil
check(not UI.active(w),"back on the home menu")
local before_rows=#w.rows
bucket.unread={"The grid breaker tripped. It must cool completely before restart."}
UI.update(w,T.now+6000)
local printed=false
for index=before_rows+1,#w.rows do
    if tostring(w.rows[index].text):find("breaker tripped",1,true) then printed=true end
end
check(printed,"EMMA reads the warning out on the home screen")
check(#G.takeNotices()==0,"it is read out once")

-- The site list offers a lost machine's crack instead of refusing it.
local realPrepare=SC.TerminalActions.prepare
local proposed=0
SC.TerminalActions.prepare=function() proposed=proposed+1 return nil,"stubbed" end
local lostRow={id="muldraugh",label="Muldraugh",linked=true,crack={lost=true,doneHours=30,requiredHours=120}}
w.gridSnapshot={visible=true,sites={lostRow}}
w.gridPage="sites" w.gridOffset=0
check(UI.options(w)[1].label=="Muldraugh / Interrupted","the site list names an interrupted crack")
UI.input(w,"",{gridAction="site",gridValue="muldraugh"})
check(proposed==1,"choosing it offers to resume")
lostRow.crack.lost=nil
check(UI.options(w)[1].label=="Muldraugh / Cracking","a working crack still reads as cracking")
UI.input(w,"",{gridAction="site",gridValue="muldraugh"})
check(proposed==1,"a working crack is left to its own computer")
SC.TerminalActions.prepare=realPrepare
w.gridPage=nil
w:close()

-- Pinning a computer must not freeze other things on its tile.
local oldProps,oldHook=ISMoveableSpriteProps,SC.Terminal._moveHook
ISMoveableSpriteProps={spriteName="lamp",pickUpMoveableInternal=function() end,
    canPickUpMoveable=function() return true end,
    findOnSquare=function(_,square,name)
        for _,object in ipairs(square.objects) do if object.sprite==name then return object end end
    end}
SC.Terminal._moveHook=nil
check(SC.Terminal.installMoveHook(),"the pickup check installs")
local lamp={sprite="lamp"}
pc.sprite="computer" pc.square.objects[#pc.square.objects+1]=lamp
check(G.pinned(pc),"the fixture computer is pinned")
local props=ISMoveableSpriteProps
check(props:canPickUpMoveable(player,pc.square,nil)==true,"a wall item on a pinned computer's tile can still move")
check(props:canPickUpMoveable(player,pc.square,lamp)==true,"so can furniture beside it")
check(props:canPickUpMoveable(player,pc.square,pc)==false,"the pinned computer cannot")
props.spriteName="computer"
check(props:canPickUpMoveable(player,pc.square,nil)==false,"the pinned computer cannot, even with no object given")
ISMoveableSpriteProps,SC.Terminal._moveHook=oldProps,oldHook
SC_TEST_REPORT="GRID_UI_PASS checks="..(T.checks-before)
