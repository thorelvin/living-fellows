-- SPDX-License-Identifier: MIT
-- Real terminal, real survey engine, real services and real scan page together.
local SC,T=SurvivorCompanion,TERMINAL_TEST
local B,D,UI=SC.BuildingControls,SC.BuildingScan,SC.TerminalScanUI
local check=T.check
local world,chunk,panel,pc,player,w,definition,buckets
SC.GameplayUtil.nowMs=function() return T.now end
SC.GameplayUtil.instanceOf=function(value,kind) return value and value.kind==kind end
SC.Terminal.playFeedbackSound=function() return true end
Perks={Electricity="Electricity"}
function isGamePaused() return false end
local function setup(camp,maxLevel,chunkLevel)
    if SC.Terminal.window then SC.Terminal.window:close() end
    B.reset() T.now=1000
    buckets={} ModData={getOrCreate=function(key) buckets[key]=buckets[key] or {} return buckets[key] end}
    world={}
    definition={maxZ=maxLevel or 0}
    function definition:getX() return 100 end function definition:getY() return 100 end
    function definition:getX2() return 104 end function definition:getY2() return 104 end
    function definition:getMinLevel() return 0 end function definition:getMaxLevel() return self.maxZ end
    function definition:getRooms() return {{getName=function() return "office" end}} end
    function definition:isAlarmed() return false end
    chunk={maxZ=chunkLevel or maxLevel or 0}
    function chunk:getMaxLevel() return self.maxZ end
    getCell=function() return {getChunkForGridSquare=function() return chunk end} end
    SC.GameplayUtil.gridSquare=function(x,y,z) return world[x..":"..y..":"..z] end
    local tile=T.square(100,100,0,true)
    function tile:getBuildingDef() return definition end
    world["100:100:0"]=tile
    pc=T.computer(tile)
    player=T.player(101,100,0)
    function player:getX() return self.x end function player:getY() return self.y end function player:getZ() return self.z end
    function player:getSquare() return {getX=function() return self.x end,getY=function() return self.y end,getZ=function() return self.z end} end
    function player:getPerkLevel() return 0 end
    function player:getXp() return {AddXP=function() end} end
    SC.BaseLife={active=function() return camp and {id="base"} or nil end,isInside=function() return camp==true end}
    SC.Terminal._clock=function() return T.now end
    SC.Terminal.computerState(player,pc).locked=false
    panel=B.panel(pc,true)
    panel.connections[B.computerId(pc)]={x=100,y=100,z=0}
    check(SC.Terminal.open(player,pc),"terminal opens")
    w=SC.Terminal.window w:flush()
    -- The real screen's shape: 70 columns by 10 rows.
    w.viewTop=function() return 0 end w.viewBottom=function() return 10*w.rowHeight end
    local layout={} for key,value in pairs(w.layout) do layout[key]=value end
    layout.left,layout.right=0,70*w.charWidth w.layout=layout
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
local function sample() w.scanSampleAt=nil UI.update(w,T.now) end
local function tick(ms) T.now=T.now+ms D.pulse(function() return 10 end) sample() end
local function complete()
    for _=1,5000 do
        local state=D.state(pc)
        if state and state.done then tick(200) return end
        tick(100)
    end
    error("survey did not complete")
end
local function drawn()
    local out,old={},w.drawText
    w.drawText=function(_,value,x,y,r,g,b,a) out[#out+1]={value=value,x=x,y=y,a=a} end
    UI.draw(w,T.now) w.drawText=old
    return out
end
local function overlaps(rows)
    for i=1,#rows do for j=i+1,#rows do
        if rows[i].x==rows[j].x and rows[i].y==rows[j].y then return rows[i].value.." OVER "..rows[j].value end
    end end
end
local function isDrawn(rows,text)
    for _,row in ipairs(rows) do if row.value==text then return true end end
    return false
end
local function drawnWith(rows,fragment)
    for _,row in ipairs(rows) do if row.value:find(fragment,1,true) then return row.value end end
end
local function option(key)
    for i,o in ipairs(w:menuOptions()) do if o.key==key then return o,i end end
end

-- The list column before anything has been found.
setup()
UI.open(w,false)
check(not overlaps(drawn()),"an empty Equipment page draws no text over other text")
check(drawnWith(drawn(),"No equipment recorded"),"an empty Equipment page says so")
UI.notice(w,"A failed start.") sample()
check(not overlaps(drawn()) and isDrawn(drawn(),"A failed start."),"a notice on an empty page sits below its message")
setup()
add("IsoDoor",102,102,0)
UI.open(w,true) tick(100)
check(#D.rows(pc,true)==0,"the sweep has found nothing yet")
local rows=drawn()
check(not overlaps(rows),"the first ticks of a scan draw no text over other text")
check(not drawnWith(rows,"No equipment recorded"),"a running scan never claims there is no equipment")
check(drawnWith(rows,"PROBE"),"the probe line shows from the first tick")
complete()
UI.input(w,"",(option("start")))
tick(100)
check(#D.rows(pc,true)==0 and not drawnWith(drawn(),"No equipment recorded"),"a rescan does not deny its saved rows")

-- The probe line stays through notices; short notices fade, EMMA's report does not.
setup(false,2)
add("IsoDoor",102,102,0)
UI.open(w,false)
UI.input(w,"",(option("start")))
for _=1,10 do tick(100) end
rows=drawn()
check(w.scanNotice=="Building discovery started." and isDrawn(rows,w.scanNotice),"the start notice shows")
check(drawnWith(rows,"PROBE"),"a start from the page's own button keeps the probe line")
check(not overlaps(rows),"probe and notice take separate rows")
for _=1,80 do tick(100) end
rows=drawn()
check(w.scanNotice==nil and not drawnWith(rows,"discovery started"),"a short notice fades")
check(drawnWith(rows,"PROBE") or drawnWith(rows,"ACK"),"the probe line carries on after it")
setup()
local fridge=add("Fridge",102,102,0)
function fridge:getContainerByType(kind) return kind=="fridge" and {} or nil end
UI.open(w,true)
while #D.rows(pc,true)==0 do tick(100) end
UI.input(w,"",{scanAction="row",scanValue=D.rows(pc,true)[1]})
for _=1,3 do tick(100) end
rows=drawn()
check(drawnWith(rows,"no control"),"a read-only row explains itself")
check(drawnWith(rows,"PROBE") or drawnWith(rows,"ACK"),"and the probe line stays")

-- The whole report is on the page, with true numbers and grammar.
setup()
add("IsoDoor",102,102,0)
UI.open(w,true) complete()
for pass=1,3 do
    local parts={}
    local x=w.scanSnapshot.geometry.listX
    local top=w.scanSnapshot.geometry.contentTop+w.scanSnapshot.dataCount*w.rowHeight
    for _,row in ipairs(drawn()) do
        if row.x==x and row.y>=top and row.y<w.scanSnapshot.geometry.footer then parts[#parts+1]=row.value end
    end
    local shown=table.concat(parts," ")
    check(shown==w.scanNotice,"pass "..pass.." shows all of the report, got: "..shown)
    check(w.scanNotice:find("1 control",1,true) and not w.scanNotice:find("1 controls",1,true),"one control is singular")
    check(w.scanNotice:find("1 floor",1,true) and not w.scanNotice:find("1 floors",1,true),"one floor is singular")
    check(not w.scanNotice:find("{",1,true),"no template field is left unfilled")
    check(w.scanSnapshot.header:find("1 CONTROL /",1,true) and w.scanSnapshot.header:find("/ 1 FLOOR",1,true) and not w.scanSnapshot.header:find("FLOORS",1,true),"header grammar")
    check(not drawnWith(drawn(),"PROBE"),"a finished scan has no live probe line")
    local kept=w.scanNotice
    for _=1,10 do tick(3000) end
    check(w.scanNotice==kept,"EMMA's report stays on the page")
    if pass<3 then UI.input(w,"",(option("start"))) complete() end
end
setup(false,1)
add("IsoDoor",102,102,0) add("IsoDoor",103,102,0) add("IsoDoor",102,102,1)
UI.open(w,true) complete()
check(w.scanSnapshot.header:find("3 CONTROLS",1,true) and w.scanSnapshot.header:find("2 FLOORS",1,true),"several stay plural")
check(w.scanNotice:find("3 controls",1,true) and w.scanNotice:find("2 floors",1,true),"the report agrees")
setup()
UI.open(w,true) complete()
check(D.state(pc).controls==0 and D.state(pc).finds==0,"a building with nothing in it finds nothing, not the computer")
local answered=false
for _,line in ipairs(SC.TerminalLines.BUILDING_SCAN.empty) do answered=answered or line==w.scanNotice end
check(answered,"so EMMA's nothing-answered line can fire")

-- A one-storey camp looks like one.
setup(true,0,2)
add("IsoDoor",102,102,0)
UI.open(w,true) tick(100)
check(w.scanSnapshot.header:find("/ 1 FLOOR",1,true),"the header counts the planned level")
check(#w.scanSnapshot.floors==1 and not option("floor"),"no bars or Floor button for empty levels")
complete()
check(w.scanSnapshot.header:find("COMPLETE 100%",1,true),"and it finishes at 100")

-- The radar never stays on a level that is not listed.
setup(false,1)
add("IsoDoor",102,102,0) add("IsoDoor",102,102,1)
UI.open(w,true) complete()
UI.input(w,"",(option("floor")))
check(w.scanFloorManual==true,"Floor takes manual control")
w.scanFloor=7 sample()
check(not w.scanFloorManual and w.scanFloor~=7 and #w.scanSnapshot.blips>0,"a level that left the list hands the radar back")
UI.input(w,"",(option("floor")))
w.scanFloor=7 w.scanFloorManual=nil
UI.input(w,"",(option("floor")))
check(w.scanFloor==0,"Floor from an unlisted level goes to the first one")
UI.input(w,"",(option("start")))
check(not w.scanFloorManual,"a new scan follows the sweep again")

-- The mouse wheel turns the way it looks. A positive delta is down, as in vanilla list boxes.
setup()
for i=1,12 do add("IsoDoor",100+i%5,101+math.floor(i/5),0) end
UI.open(w,true) complete()
UI.open(w,false)
local page=w.scanSnapshot.geometry.capacity
w.scanOffset=page w.scanUserSelected=true w.scanSelectedKey=nil sample()
w:onMouseWheel(1)
check(w.scanOffset==page*2,"wheel down goes to the next page")
w:onMouseWheel(-1)
check(w.scanOffset==page,"wheel up goes back")
w:otherKey(Keyboard.KEY_NEXT)
check(w.scanOffset==page*2,"PgDn agrees with the wheel")
UI.back(w)
local wheel={}
SC.TerminalGridUI={active=function() return false end,scroll=function(_,delta) wheel.grid=delta return true end}
w:onMouseWheel(1)
SC.TerminalGridUI=nil
SC.TerminalRadioUI={active=function() return false end,scroll=function(_,delta) wheel.radio=delta return true end}
w:onMouseWheel(1)
SC.TerminalRadioUI=nil
check(wheel.grid>0 and wheel.radio>0,"grid and radio pages get the same direction")

-- Esc from a device prompt never carries a live Y/N to a page that can't show it.
setup()
add("IsoDoor",102,102,0)
UI.open(w,true) complete()
local row for _,candidate in ipairs(D.rows(pc,false)) do if not candidate.readonly then row=candidate end end
UI.input(w,"",{scanAction="row",scanValue=row})
check(w.menuPage=="device" and w.scanReturn~=nil,"the device page opened from the scan")
w.requestTicket={kind="test"}
w:otherKey(Keyboard.KEY_ESCAPE)
check(UI.active(w) and w.requestTicket==nil,"Esc cancels the request and returns to the radar")
check(w.scanNotice=="Request cancelled." and #w:menuOptions()>0,"and says so, with the page usable")
w.requestTicket={kind="test"}
local hint
local oldDrawText=w.drawText
w.drawText=function(_,value) hint=hint or value:find("Y/N",1,true) and value or nil end
w:drawHints()
w.drawText=oldDrawText w.requestTicket=nil
check(hint~=nil,"a prompt on this page never hints at numbered choices")

-- The rain can be seen while the sweep runs.
setup()
add("IsoDoor",102,102,0)
UI.open(w,true) tick(100)
local bright=0
for n=0,14 do
    T.now=T.now+100
    for _,value in ipairs(drawn()) do
        if value.x==w.scanSnapshot.geometry.left and value.y>=w.scanSnapshot.geometry.contentTop then bright=math.max(bright,value.a) end
    end
end
check(bright==1,"the head of the rain is at full brightness while running")

w:close()
print("BUILDING_SCAN_SCREEN_PASS")
