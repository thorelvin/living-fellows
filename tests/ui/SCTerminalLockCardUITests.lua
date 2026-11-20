-- SPDX-License-Identifier: MIT
-- Real terminal submit/mouse/context paths, including narrow and unequal fonts.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local C,L,S,UI=SC.TerminalLockCard,SC.TerminalLocks,SC.TerminalSystem,SC.TerminalLockCardUI
local check,before=T.check,T.checks
local old={core=getCore,manager=getTextManager,specific=getSpecificPlayer,cell=getCell,sandbox=SandboxVars,
    mod=ModData,registry=SC.Registry,contains=SC.GameplayUtil.containerContainsIdentity,free=SC.GameplayUtil.isSquareFree,config=SCConfig,
    events=Events,transfer=ISTransferAction,queuedTransfer=ISInventoryTransferAction}
local bridge=SC.UIBridge
local oldMenu=type(bridge.inventoryMenuInstalled)=="function" and bridge.inventoryMenuInstalled() or false
bridge.removeTransferHook()
local eventAdds,eventRemoves,inventoryCallbacks=0,0,{}
Events={OnFillInventoryObjectContextMenu={
    Add=function(callback) eventAdds=eventAdds+1 inventoryCallbacks[#inventoryCallbacks+1]=callback end,
    Remove=function(callback)
        eventRemoves=eventRemoves+1
        for index=#inventoryCallbacks,1,-1 do if inventoryCallbacks[index]==callback then table.remove(inventoryCallbacks,index) end end
    end}}
local transferSentinel=function() return "vanilla-transfer" end
local queuedSentinel=function() return "vanilla-queued-transfer" end
ISTransferAction={transferItem=transferSentinel}
ISInventoryTransferAction={transferItem=queuedSentinel}
SandboxVars={LivingFellows={LockedComputerPercent=100,LockRealItems=false}}
SCConfig=SCConfig or {} local oldDebug=SCConfig.debugLockKind SCConfig.debugLockKind=nil
ModData={getOrCreate=function() return {} end} L.reset()
SC.Registry={living=function() return {} end,snapshot=function() return {} end}
SC.GameplayUtil.containerContainsIdentity=function(container,item)
    for _,candidate in ipairs(container.items or {}) do if candidate==item then return true end end return false
end
local measured=0
local function advance(value)
    local count=0 for digit in tostring(value):gmatch(".") do count=count+(digit=="1" and 5 or digit=="8" and 14 or digit==" " and 4 or 8) end return count
end
getTextManager=function() return {getFontHeight=function() return 16 end,
    MeasureStringX=function(_,_,value) measured=measured+1 return advance(value) end} end
getCore=function() return {getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end} end
local square=T.square(100,100,0,true)
local player=T.player(101,100,0) local inventory={items={}}
function inventory:getItems() return self.items end
function inventory:getFirstTypeRecurse(kind) for _,item in ipairs(self.items) do if item.kind==kind then return item end end end
function player:getInventory() return inventory end
function player:getPerkLevel() return 0 end
getSpecificPlayer=function() return player end
local function item(seed,service)
    local value={kind=C.ITEM,md={LF_LarchKey={seed=seed,service=service==true}},container=inventory}
    function value:getFullType() return self.kind end function value:getContainer() return self.container end
    function value:getModData() return self.md end function value:setName(name) self.name=name end
    function value:setCustomName(custom) self.custom=custom end
    inventory.items[#inventory.items+1]=value return value
end
local function open(seed)
    if SC.Terminal.window then SC.Terminal.window:close() end
    local pc=T.computer(square)
    local state=S.create(seed or 4701,"office",false,false,"card-ui:"..T.checks)
    state.archive="dispatch_bell" state.lock.kind="card" state.lock.settled=true
    C.ensure(state,player) state.lock.card.spawned=true state.lock.card.absent=true
    pc.data.movableData={LF_LarchOS=state}
    check(SC.Terminal.open(player,pc),"card terminal opens through production API")
    local w=SC.Terminal.window w:flush() return w,pc
end
local function bodyBounds(w)
    w:drawSecurity()
    for _,box in ipairs(w.securityHits) do
        check(box.x>=w.layout.left-.01 and box.x+box.width<=w.layout.left+w:transcriptWidth()+.01,"card hits fit the transcript width")
        check(box.y>=w:viewTop()-.01 and box.y+(box.height or w.rowHeight)<=w:viewTop()+w:visibleRows()*w.rowHeight+.01,"card hits fit the viewport height")
    end
    check(T.stencil==nil,"card rendering clears every stencil")
end
local wideSeed
for seed=4701,4800 do
    local state=S.create(seed,"office",false,false,"card-ui-wide-digit")
    state.archive="dispatch_bell" state.lock.kind="card" C.ensure(state,player)
    local board=C.board(state)
    for position=1,7 do if C.known(state,position,board) and board.digits:sub(position,position)=="8" then wideSeed=seed break end end
    if wideSeed then break end
end
check(wideSeed~=nil,"font fixture includes an already-read wide digit")
local w,pc=open(wideSeed)
check(eventAdds==1 and #inventoryCallbacks==1,"opening a card reader registers the existing inventory event without companions")
check(bridge.inventoryMenuInstalled()==true,"menu-only registration reports its lifecycle state")
check(bridge.installInventoryMenu()==true and bridge.installInventoryMenu()==true and eventAdds==1,
    "menu-only inventory registration is idempotent")
check(ISTransferAction.transferItem==transferSentinel and ISInventoryTransferAction.transferItem==queuedSentinel,
    "opening a card reader does not install unrelated transfer wrappers")
local strokes={}
local defaultArt=SC.TerminalLockUI.art local artBoxes={}
SC.TerminalLockUI.art=function(_,name,box) if name=="LarchKeyTitle" then artBoxes[#artBoxes+1]=box end return false end
w.drawTextZoomed=function(_,value,x,y,zoom) strokes[#strokes+1]={text=value,x=x,y=y,zoom=zoom,clip=T.stencil} end
bodyBounds(w)
check(UI.large(w),"normal terminal uses large stripe cells: "..w:columns().."x"..w:visibleRows())
check(#artBoxes==1,"default 1920 layout includes the selected small card/reader illustration")
for _,box in ipairs(artBoxes) do
    check(box.x>=w.layout.left-.01 and box.x+box.width<=w.layout.left+w:transcriptWidth()+.01,"default art rectangle fits the body width")
    for _,stroke in ipairs(strokes) do if stroke.clip then
        local clip=stroke.clip
        check(not (clip.x<box.x+box.width and clip.x+clip.width>box.x and clip.y<box.y+box.height and clip.y+clip.height>box.y),"default illustration never overlaps a text or digit stencil")
    end end
    for _,target in ipairs(w.securityHits) do
        check(not (target.x<box.x+box.width and target.x+target.width>box.x and target.y<box.y+box.height and target.y+(target.height or w.rowHeight)>box.y),"default illustration never overlaps a clickable control")
    end
end
SC.TerminalLockUI.art=defaultArt
local gaps={}
for _,box in ipairs(w.securityHits) do if box.value:match("^gap ") then gaps[#gaps+1]=box end end
check(#gaps==4,"every open stripe gap owns a hit box")
check(w:securityGrid().glyphs["1"]~=w:securityGrid().glyphs["8"],"native font fixture supplies unequal digit advances")
local digitStrokes=0
for _,stroke in ipairs(strokes) do if stroke.text:match("^%d$") and stroke.clip then
    digitStrokes=digitStrokes+1
    check(stroke.x>=stroke.clip.x-.01 and stroke.x+advance(stroke.text)*stroke.zoom<=stroke.clip.x+stroke.clip.width+.01,"each proportional digit is centered entirely inside its own painted cell")
    check(math.abs(stroke.x-(stroke.clip.x+(stroke.clip.width-advance(stroke.text)*stroke.zoom)/2))<.01,"proportional digits use their measured advance for centering")
end end
check(digitStrokes>=7,"known stripe digits and all candidates use measured cell rendering")
for _,box in ipairs(gaps) do
    check(box.height>w.rowHeight,"stripe target includes its full large-cell height")
    local found=false
    for _,stroke in ipairs(strokes) do if stroke.clip and stroke.clip.x==box.x and stroke.clip.y==box.y then
        found=true check(stroke.text=="_","an open stripe cell never paints its internal answer")
        check(stroke.x>=box.x and stroke.x+advance(stroke.text)*stroke.zoom<=box.x+box.width+.01,"unequal digit advances fit their cell")
    end end
    check(found,"each visible gap paints an underscore in its own stencil")
end
local calls=measured bodyBounds(w) check(measured==calls,"card painting reuses cached font metrics")
local target=gaps[#gaps] local position=tonumber(target.value:match("(%d+)$"))
local misses=w.system.lock.card.mismatches
w:onMouseDown(target.x+target.width/2,target.y+target.height-.1)
check(w.lockCardCursor==position and w.system.lock.card.mismatches==misses,"clicking the bottom edge selects a gap without submitting a digit")
bodyBounds(w)
local answer=C.board(w.system).digits:sub(position,position) local candidate
for _,box in ipairs(w.securityHits) do if box.value==answer then candidate=box break end end
check(candidate and candidate.height>w.rowHeight,"candidate target includes its complete large-cell height")
w:onMouseDown(candidate.x+candidate.width/2,candidate.y+candidate.height-.1)
check(w.system.lock.card.solved:sub(position,position)=="1","bottom-edge candidate click goes through real submit to solve the chosen gap")
check(not SC.TerminalLockUI.instantChoice(w,"1"),"typing a digit never invokes a card menu shortcut")

-- A 70 by 10 body keeps the big cells; below it, every choice is scrollable.
w,pc=open(4702)
local originalColumns,originalRows,originalWidth=w.columns,w.visibleRows,w.transcriptWidth
w.columns=function() return 70 end w.visibleRows=function() return 10 end
w.transcriptWidth=function() return math.min(70*w.charWidth,w.layout.right-w.layout.left) end
check(UI.large(w),"70 columns by 10 rows keeps the stripe workbench")
local art=SC.TerminalLockUI.art local artCalls=0
SC.TerminalLockUI.art=function() artCalls=artCalls+1 return false end
bodyBounds(w) check(artCalls==0,"exact 70 by 10 compact workbench drops the illustration")
w.columns=function() return 34 end w.visibleRows=function() return 5 end
w.transcriptWidth=function() return 34*w.charWidth end
check(not UI.large(w),"small body selects the compact text renderer")
local reachedDigits,reachedGaps={},{}
for scroll=0,UI.rowCount(w) do
    w.securityScroll=scroll bodyBounds(w)
    for _,box in ipairs(w.securityHits) do
        if box.value:match("^%d$") then reachedDigits[box.value]=true end
        if box.value:match("^gap ") then reachedGaps[box.value]=true end
    end
end
local view=C.view(w)
for _,digit in ipairs(view.positions[view.cursor].candidates) do check(reachedDigits[digit],"each compact candidate is reachable by scrolling") end
for i,p in ipairs(view.positions) do if p.open then check(reachedGaps["gap "..i],"each compact gap remains selectable") end end
check(artCalls==0,"compact card page drops the optional illustration")
local priorMetrics=measured bodyBounds(w) check(measured==priorMetrics,"compact repainting reuses measured wrapped rows")
w.system.lock.card.lockedUntil=T.hours+1
for scroll=0,UI.rowCount(w) do
    w.securityScroll=scroll bodyBounds(w)
    for _,box in ipairs(w.securityHits) do check(not box.value:match("^%d$") and not box.value:match("^gap "),"reader lockout removes digit and gap targets") end
end
SC.TerminalLockUI.art=art
w.columns,w.visibleRows,w.transcriptWidth=originalColumns,originalRows,originalWidth

-- Real existing inventory hook: selecting the wrong card must not silently use
-- a better carried card, and stale menus retain no authority over a new page.
inventory.items={}
w,pc=open(4703)
local owner=item(w.system.seed,false) local service=item(123,true) local other=item(456,false)
check(C.carried(player,w.system)==service,"fixture carries a higher-ranked service card")
local function options(selected)
    local context={options={}}
    function context:addOption(label,target,callback,...)
        local row={label=label,target=target,callback=callback,args={...}} self.options[#self.options+1]=row return row
    end
    for _,callback in ipairs(inventoryCallbacks) do callback(0,context,{selected}) end return context.options
end
local rows=options(other)
check(#rows==1 and rows[1].label=="Swipe at the computer" and rows[1].target==other,"player inventory gets a swipe row before companion-owner early return")
rows[1].callback(rows[1].target,unpack(rows[1].args))
check(w.system.lock.card.read=="none" and w.securityMessage:find("NOT ENROLLED",1,true),"inventory callback swipes the exact selected wrong card")
rows=options(owner) rows[1].callback(rows[1].target,unpack(rows[1].args))
check(w.system.lock.card.read=="owner","selected owner card is read even while a service card is carried")
local retained=rows[1]
owner.container=nil
check(retained.callback(retained.target,unpack(retained.args))==false,"dropping a selected card invalidates the stale inventory callback")
owner.container=inventory
w.lockPage="logins" check(#options(owner)==0,"inventory swipe row is absent on a different lock page") w.lockPage=nil
player.x=110 check(#options(owner)==0,"inventory swipe row disappears beyond terminal reach") player.x=101
pc.square.generatorPower=false check(#options(owner)==0,"inventory swipe row requires power") pc.square.generatorPower=true
player.dead=true check(#options(owner)==0,"inventory swipe row requires a living operator") player.dead=false
w:close()
check(SC.Terminal.cardWindow==nil and #options(owner)==0,"closing clears the open card-page reference")
local oldWindow=w w,pc=open(4704)
check(retained.callback(retained.target,unpack(retained.args))==false and w.system.lock.card.read=="none","old context callback cannot swipe at the replacement window")
check(oldWindow.closed,"replacement fixture leaves its previous terminal closed")

-- The unlocked menu dispatches the actual encode operation once.
inventory.items={} owner=item(w.system.seed,false)
w.system.locked=false w.payoff=nil w.system.lock.welcomed=true
local encode
for index,option in ipairs(w:menuOptions()) do if option.systemCommand=="encode_card" then encode=index end end
check(encode~=nil,"unlocked card terminal offers service-card encoding")
w:setFocusMode("menu") w:submit(tostring(encode))
check(w.system.lock.card.encoded and owner.md.LF_LarchKey.service and owner.name=="LARCH/KEY Service Card","menu choice encodes the owner's exact carried card")
for _,option in ipairs(w:menuOptions()) do check(option.systemCommand~="encode_card","encoded machine no longer offers encoding") end

local oldFeedback=SC.Terminal.playFeedbackSound local played={}
SC.Terminal.playFeedbackSound=function(name) played[#played+1]=name end
local previousNow=T.now w.lockCardReadSoundAt=T.now+400
w:advance(T.now+399) check(#played==0,"successful-read blip waits for the swipe to finish")
T.now=T.now+401 w:advance(T.now) w:advance(T.now+1)
check(#played==1 and played[1]=="LFCardRead","unlocked terminal advances the pending good-read blip exactly once")
T.now=previousNow SC.Terminal.playFeedbackSound=oldFeedback

-- Actual viewport sizes and every existing phosphor palette share the frame,
-- retain all footer commands and keep input targets above the input field.
for _,size in ipairs({{480,540},{640,480},{1280,720},{1920,1080},{2560,1440}}) do
    getCore=function() return {getScreenWidth=function() return size[1] end,getScreenHeight=function() return size[2] end} end
    for _,theme in ipairs({"green","sand","aqua","purple"}) do
        w,pc=open(4780+T.checks) w.colors=SC.TerminalPresentation.colors(theme)
        bodyBounds(w)
        for _,box in ipairs(w.securityHits) do
            check(box.y+(box.height or w.rowHeight)<=w:viewBottom()+.01,"actual viewport card hit remains above the input field")
        end
    end
end

getCore=function() return {getScreenWidth=function() return 1920 end,getScreenHeight=function() return 1080 end} end
w,pc=open(4799) bodyBounds(w)
local oldHit
for _,box in ipairs(w.securityHits) do if box.value:match("^%d$") then oldHit=box break end end
check(oldHit~=nil,"guard fixture has a visible candidate")
local progress=w.system.lock.card.solved
pc.data.movableData.LF_LarchOS=S.create(4800,"office",false,false,"replaced-card-ui")
w:onMouseDown(oldHit.x+1,oldHit.y+(oldHit.height or w.rowHeight)-.1)
check(w.closed and w.system.lock.card.solved==progress,"stale mouse hit closes after terminal ownership changes and cannot change progress")

check(eventAdds==1 and #inventoryCallbacks==1,"repeated card-page opens retain one inventory event owner")
bridge.removeTransferHook()
check(eventRemoves==1 and #inventoryCallbacks==0 and not bridge.inventoryMenuInstalled(),
    "existing transfer teardown also removes menu-only registration")
w,pc=open(4801)
check(eventAdds==2 and #inventoryCallbacks==1 and bridge.inventoryMenuInstalled(),
    "opening a later card page reinstalls the event after teardown")
check(ISTransferAction.transferItem==transferSentinel and ISInventoryTransferAction.transferItem==queuedSentinel,
    "menu-only teardown and rearm preserve both vanilla transfer functions")
bridge.removeTransferHook()
local menuEvent=Events.OnFillInventoryObjectContextMenu local eventAdd=menuEvent.Add
menuEvent.Add=function() error("fixture refuses inventory callback") end
local installed,installReason=bridge.installInventoryMenu()
check(installed==false and tostring(installReason):find("registration failed",1,true) and not bridge.inventoryMenuInstalled(),
    "failed native event registration returns a checked refusal without claiming an installed menu")
Events=nil installed,installReason=bridge.installInventoryMenu()
check(installed==false and installReason=="inventory context event unavailable" and not bridge.inventoryMenuInstalled(),
    "missing inventory event returns a checked refusal")
Events={OnFillInventoryObjectContextMenu=menuEvent} menuEvent.Add=eventAdd
check(bridge.installInventoryMenu()==true and #inventoryCallbacks==1,
    "a failed menu registration can be retried successfully")

-- The shared physical helper retains the manual's native placement geometry.
local surface=T.square(300,300,0,true) local machine=T.computer(surface)
surface.objects[#surface.objects+1]={getSurfaceOffsetNoTable=function() return 32 end}
local prop={getWorldItem=function(self) return self.world end}
function surface:AddWorldInventoryItem(value,x,y,z)
    self.receipt={x=x,y=y,z=z} value.world={getSquare=function() return self end} return value
end
check(SC.TerminalLockPhysical.place(prop,machine)==prop.world and surface.receipt.z==32/96,"physical props use the same surface height divided by 96")
surface.objects={machine} local floor=T.square(300,301,0,true)
function floor:TreatAsSolidFloor() return true end
floor.AddWorldInventoryItem=surface.AddWorldInventoryItem
getCell=function() return {getGridSquare=function(_,x,y,z) if x==300 and y==301 and z==0 then return floor end end} end
SC.GameplayUtil.isSquareFree=function(value) return value==floor end
prop.world=nil check(SC.TerminalLockPhysical.place(prop,machine)==prop.world and floor.receipt.z==0,"no surface falls back to the first free adjacent floor")
SC.GameplayUtil.isSquareFree=function() return false end prop.world=nil
check(SC.TerminalLockPhysical.place(prop,machine)==nil,"blocked adjacent floors leave the item unplaced")

if SC.Terminal.window then SC.Terminal.window:close() end
bridge.removeTransferHook()
Events,ISTransferAction,ISInventoryTransferAction=old.events,old.transfer,old.queuedTransfer
if oldMenu then bridge.installInventoryMenu() end
getCore,getTextManager,getSpecificPlayer,getCell,SandboxVars,ModData,SC.Registry=old.core,old.manager,old.specific,old.cell,old.sandbox,old.mod,old.registry
SC.GameplayUtil.containerContainsIdentity,SC.GameplayUtil.isSquareFree=old.contains,old.free
SCConfig.debugLockKind=oldDebug SCConfig=old.config L.reset()
SC_TEST_REPORT=(SC_TEST_REPORT or "").."; Card UI: "..(T.checks-before).." layout, mouse, exact inventory, encoding and physical checks passed"
