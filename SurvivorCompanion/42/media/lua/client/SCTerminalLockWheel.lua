-- SPDX-License-Identifier: MIT
-- Physical manual ownership and a deterministic, user-operated code wheel.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion
local Wheel={} SC.TerminalLockWheel=Wheel
Wheel.ITEM="LivingFellows.LarchfieldManual"
local function U() return SC.ControlUtil end
local function data() return SC.TerminalLockWheelData end
function Wheel.mod(value) return value-math.floor(value/26)*26 end
function Wheel.challenge(state,number)
    local pick=SC.TerminalSystem.random(state.seed+11939)
    local chosen,used
    used={}
    for _=1,number or state.lock.wheel.correct+1 do
        repeat
            chosen={marker=pick(4),letter=pick(26)-1,window=pick(3)}
            local key=chosen.marker..":"..chosen.letter..":"..chosen.window
            if not used[key] then used[key]=true break end
        until false
    end
    return chosen
end
function Wheel.rotationFor(challenge)
    return Wheel.mod(challenge.letter-data().markers[challenge.marker].position)
end
function Wheel.read(rotation,window)
    local index=Wheel.mod(data().windows[window]-rotation)+1
    return data().inner:sub(index,index)
end
function Wheel.answer(state,number)
    local c=Wheel.challenge(state,number)
    return Wheel.read(Wheel.rotationFor(c),c.window)
end
function Wheel.carried(player)
    local item,available=SC.GameplayUtil.call(U().inventory(player),"getFirstTypeRecurse",Wheel.ITEM)
    if available then return item and U().call(item,"getFullType")==Wheel.ITEM and U().owns(player,item) and item or nil end
    for _,item in ipairs(U().items(player)) do if U().call(item,"getFullType")==Wheel.ITEM then return item end end
end
function Wheel.nearby(player)
    local carried=Wheel.carried(player) if carried then return carried end
    local x,y,z=U().position(player) if not x then return nil end
    local cell=type(getCell)=="function" and getCell()
    for dx=-1,1 do for dy=-1,1 do
        local tile=cell and U().call(cell,"getGridSquare",math.floor(x)+dx,math.floor(y)+dy,math.floor(z))
        for _,worldItem in ipairs(U().list(U().call(tile,"getWorldObjects"),64)) do
            local item=U().call(worldItem,"getItem")
            if U().call(item,"getFullType")==Wheel.ITEM then return item end
        end
    end end
end
function Wheel.ensure(state,player,object)
    if not state.lock.wheel then
        state.lock.wheel={correct=0,required=Wheel.carried(player) and 1 or 3,wrong=0,rotation=0}
    end
    if state.lock.manualSpawned then return end
    state.lock.manualSpawned=true
    if Wheel.carried(player) then return end
    local tile=U().square(object) local surface=0
    for _,candidate in ipairs(U().list(U().call(tile,"getObjects"),64)) do
        if candidate~=object then surface=math.max(surface,tonumber(U().call(candidate,"getSurfaceOffsetNoTable")) or 0) end
    end
    if surface<=0 then
        local x,y,z=U().position(object) local cell=type(getCell)=="function" and getCell()
        tile=nil
        for _,d in ipairs({{0,1},{1,0},{0,-1},{-1,0},{1,1},{-1,1},{1,-1},{-1,-1}}) do
            local candidate=cell and U().call(cell,"getGridSquare",x+d[1],y+d[2],z)
            if candidate and U().call(candidate,"TreatAsSolidFloor")==true and SC.GameplayUtil.isSquareFree(candidate) then tile=candidate break end
        end
    end
    if not tile then return end
    local create=type(instanceItem)=="function" and instanceItem or InventoryItemFactory and InventoryItemFactory.CreateItem
    if not create then return end
    local okay,item=pcall(create,Wheel.ITEM)
    if not okay or not item then return end
    U().call(tile,"AddWorldInventoryItem",item,.5,.5,surface/96)
    local world=U().call(item,"getWorldItem")
    if world and U().square(world)==tile then state.lock.manualItemId=tostring(U().call(item,"getID")) end
end
function Wheel.turn(w,delta)
    if w.lockPage~="manual" or w.lockManualPage~=5 or not Wheel.nearby(w.player) then return false end
    local wheel=w.system.lock.wheel
    wheel.rotation=Wheel.mod(wheel.rotation+delta)
    return true
end
function Wheel.input(w,raw)
    local lower=raw:lower():match("^%s*(.-)%s*$")
    local wheel=w.system.lock.wheel
    if lower=="open manual" or lower=="manual" or lower=="1" and w.lockPage~="manual" then
        if not Wheel.nearby(w.player) then w.securityMessage="Bring the manual, or stand next to the copy beside this computer." return true end
        w.lockPage="manual" w.lockManualPage=w.lockManualPage or 1 w.securityScroll=0 return true
    end
    if w.lockPage=="manual" then
        if not Wheel.nearby(w.player) then w.lockPage=nil w.securityMessage="The manual is out of reach." return true end
        if lower=="1" or lower=="previous page" then w.lockManualPage=math.max(1,w.lockManualPage-1) w.securityScroll=0 return true end
        if lower=="2" or lower=="next page" then w.lockManualPage=math.min(5,w.lockManualPage+1) w.securityScroll=0 return true end
        if lower=="3" or lower=="back" then w.lockPage=nil w.securityScroll=0 return true end
        if lower=="wheel" or lower=="4" then w.lockManualPage=5 w.securityScroll=0 return true end
        if w.lockManualPage==5 and (lower=="5" or lower=="6") then Wheel.turn(w,lower=="5" and -1 or 1) return true end
        if w.lockManualPage==5 and (lower=="7" or lower=="8" or lower=="9") then
            lower="answer "..Wheel.read(wheel.rotation,tonumber(lower)-6):lower()
        end
        if lower=="left" or lower=="right" then Wheel.turn(w,lower=="left" and -1 or 1) return true end
    end
    local answer=lower:match("^answer ([a-z])$") or lower:match("^([a-z])$")
    if not answer then w.securityMessage="Open the manual or submit the letter from the requested window." return true end
    local now=U().hours()
    if not now then w.securityMessage="Game clock unavailable." return true end
    if wheel.retryUntil and now<wheel.retryUntil then w.securityMessage="Recovery paused. Retry in "..math.ceil((wheel.retryUntil-now)*60).." game minutes." return true end
    if wheel.retryUntil then wheel.retryUntil=nil wheel.wrong=0 end
    if answer:upper()==Wheel.answer(w.system) then
        wheel.correct=wheel.correct+1 w.securityMessage="Window verified." w.securityScroll=0
        if wheel.correct>=wheel.required then SC.TerminalLocks.finishUnlock(w,"wheel") end
    else
        wheel.wrong=wheel.wrong+1 w.securityMessage="That window does not match."
        SC.TerminalLocks.record(w,answer:upper(),"wrong")
        if wheel.wrong>=3 then
            wheel.retryUntil=now+1/6 w.system.lock.bypass=true
            w.securityMessage="Three mismatches. Recovery pauses for 10 game minutes. Other ways in are available."
            SC.TerminalLockCrew.react(w,"failure",50)
        end
    end
    return true
end
function Wheel.lines(w)
    local wheel=w.system.lock.wheel local c=Wheel.challenge(w.system)
    local rows={"CHALLENGE "..math.min(wheel.required,wheel.correct+1).." / "..wheel.required,
        "ALIGN "..data().markers[c.marker].name.." TO "..data().outer:sub(c.letter+1,c.letter+1)..". READ WINDOW "..c.window..".",
        w.securityMessage or (w.system.lock.manualItemId and "A handbook was left beside this computer. A carried copy shortens recovery."
            or wheel.required==1 and "Your carried handbook reduces this recovery to one challenge."
            or "Find a Larchfield handbook, or use the printed wheel.")}
    if SC.Terminal.electricalSkill(w.player)>=3 then rows[#rows+1]="Electrical training: first window highlighted." end
    local clue=w.system.lock.crewClue
    if clue and clue.kind=="wheel" then rows[#rows+1]="Companion's note: challenge "..clue.stage.." reads "..clue.value.."." end
    rows[#rows+1]="[1] Open manual"
    rows[#rows+1]="Type the window's letter to submit."
    return rows
end
function Wheel.manualLines(w)
    local page=data().pages[w.lockManualPage or 1]
    local rows={page.title}
    if w.lockManualPage==5 then
        local challenge=Wheel.challenge(w.system)
        rows[#rows+1]="ALIGN "..data().markers[challenge.marker].name.." TO "..data().outer:sub(challenge.letter+1,challenge.letter+1)..". WINDOW "..challenge.window.."."
    end
    for _,line in ipairs(page.text) do rows[#rows+1]=line end
    if w.securityMessage then rows[#rows+1]=w.securityMessage end
    return rows,page.art
end
return Wheel
