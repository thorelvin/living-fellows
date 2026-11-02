-- SPDX-License-Identifier: MIT
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local P={} SC.TerminalPayoff=P
local containers={desk=true,filingcabinet=true,counter=true,shelves=true,metal_shelves=true,
    sidetable=true,locker=true,wardrobe=true,crate=true,dresser=true}
local pool={{"Base.Battery","Base.Battery"},{"Base.Bandage","Base.Bandage","Base.Bandage"},
    {"Base.TinnedBeans","Base.TinOpener"},{"Base.DuctTape"},
    {"Base.ElectronicsScrap","Base.ElectronicsScrap","Base.ElectronicsScrap"},{"Base.Matches"}}
local rewards={pool,{{"Base.Antibiotics"},{"Base.Hammer"},{"Base.Torch","Base.Battery"},{"Base.NailsBox"},{"Base.MechanicMag1"}},
    {{"Base.ElectronicsMag4"},{"Base.WalkieTalkie3"},{"Base.FirstAidKit"},{"Base.Whiskey","Base.Hammer"}}}
function P.rewardTier(state,forced)
    local kind=state.lock.kind
    local tier=state.lock.rewardTier or ((kind=="story" or kind=="phone" or kind=="radio" or kind=="rival") and 3 or (kind=="wheel" or kind=="emma" or kind=="search") and 2 or 1)
    return math.max(1,tier-(forced and 1 or 0))
end
function P.items(state,forced)
    if state.lock.kind=="persona" and not forced then return SC.TerminalPersona.rewardItems(state.lock.persona) end
    local tier=P.rewardTier(state,forced) local profile=SC.TerminalFiles.get(state.archive)
    local kind=state.lock.machineKind or profile and profile.kind
    local selected=rewards[tier][state.seed%#rewards[tier]+1]
    if tier>=2 and (kind=="police" or kind=="security") then
        selected=tier==3 and {"Base.Bullets9mmBox","Base.ShotgunShellsBox"} or {"Base.Bullets9mmBox"}
    elseif tier==2 and (kind=="clinic" or kind=="pharmacy") then selected={"Base.Antibiotics"}
    elseif tier==2 and (kind=="hardware" or kind=="industry") then selected={"Base.Hammer"} end
    local row=SC.TerminalLockStashes[state.archive] local choices={}
    for _,name in ipairs(row and row.items or selected) do choices[#choices+1]=name end
    if row and tier>1 then for _,name in ipairs(selected) do choices[#choices+1]=name end end
    return choices
end
local releaseLines={"Drawer released. Whatever is in there was not my idea.","Interlock released. I have no opinion on the previous owner's filing system.",
    "The drawer is open. That concludes the difficult part of opening a drawer.","Released. Please leave the drawer attached to the desk.",
    "You have access. The contents have not been reviewed by civil defence.","Drawer open. A small administrative victory."}
local clutchLines={"Excellent. Now attend to the footsteps.","Access restored with very little margin for error.",
    "Your timing is impressive. Your risk assessment needs work.","That was close. I have recorded the useful part.",
    "You may now stop typing and start reconsidering your surroundings.","Password accepted. Please survive long enough to appreciate it."}
local function U() return SC.ControlUtil end
local oldGuesses={
    {"SECRET","SECRET1","SECRET2"},{"MONDAY","FRIDAY"},{"FOLDER","FOLDERS","OFFICE"},{"COUNTY","COUNTY1"},
    {"WELCOME","WELCOME1","WELCOME2"},{"CHANGE","CHANGED"},{"SUMMER","SUMMER92","SUMMER93"},{"PAYDAY","PAYDAY1"},
    {"SECURE","SECURE1","SECURED"},{"SYSTEM","SYSTEM1"},{"RECORD","RECORDS","PAPER"},{"ACCESS","ACCESS1"},
    {"JULY","JULY93","JULY1993"},{"RETURN","RETURN1"},{"BACKUP","BACKUP1","BACKUP2"},{"PLEASE","PLEASE1"},
    {"PENCIL","PENCILS","PAPER"},{"HOLIDAY","HOLIDAY1"},{"DINNER","DINNER1","DINNER2"},{"LARCH","LARCHOS"},
}
function P.failedLogins(state)
    local rows={"FAILED LOGINS"}
    for _,record in ipairs(state.lock and state.lock.attempts or {}) do
        rows[#rows+1]="Day "..record.day.." / "..record.name.." / "..record.guess.." / "..record.result
    end
    if state.archive~="_factory" and state.seed%4==0 then
        local owner=SC.TerminalFiles.get(state.archive).owner
        for _,guess in ipairs(oldGuesses[state.seed%#oldGuesses+1]) do rows[#rows+1]="1993-07-08 / "..owner.." / "..guess.." / wrong" end
    end
    if #rows==1 then rows[#rows+1]="No failed attempts recorded." end
    rows[#rows+1]="[1] Back to password"
    return rows
end
function P.wantsNote(state)
    local row=SC.TerminalLockStashes[state.archive]
    return row and not row.drawer or false
end
function P.drawerMessage(state) return releaseLines[state.seed%#releaseLines+1] end
function P.place(player,object,state,container,forced)
    local lock=state.lock
    if not lock or lock.realItems==false or not SC.TerminalDrawers.enabled() or lock.slip or lock.stash and lock.stash.committed then return false end
    local parent=U().call(container,"getParent") local where=parent and U().position(parent)
    if not where or not SC.Terminal.ownsState(object,state) then return false end
    -- Persona rewards have their own contents. An unrelated previous owner's
    -- water/child-item recipe must not alter those exact native items.
    local row=(lock.kind~="persona" or forced) and SC.TerminalLockStashes[state.archive] or nil
    local choices=P.items(state,forced)
    local x,y,z=U().position(parent)
    local kind=U().call(container,"getType")
    local room=U().call(U().call(parent,"getSquare"),"getRoom")
    local roomName=tostring(U().call(room,"getName") or "outside"):sub(1,32)
    local stash={committed=true,items={},location={x=x,y=y,z=z,type=kind,
        sprite=U().call(U().call(parent,"getSprite"),"getName")}}
    lock.stash=stash
    local complete,names=true,{}
    for _,name in ipairs(choices) do
        local item=U().call(container,"AddItem",name)
        if not item or U().call(item,"getContainer")~=container then complete=false break end
        local id,actual=U().call(item,"getID"),U().call(item,"getFullType")
        if (type(id)~="number" and type(id)~="string") or tostring(id)==""
            or type(actual)~="string" or actual=="" then complete=false break end
        stash.items[#stash.items+1]={id=tostring(id),type=actual}
        if actual~=name then complete=false end
        names[#names+1]=tostring(U().call(item,"getDisplayName") or name:gsub("^Base%.",""))
        if row and row.water then
            local fc=U().call(item,"getFluidContainer")
            if fc then
                U().call(fc,"Empty") U().call(fc,"addFluid",FluidType.Water,math.min(.5,tonumber(U().call(fc,"getCapacity")) or 0))
            end
            if not fc or (tonumber(U().call(fc,"getAmount")) or 0)<.1 then complete=false end
        end
        if row and row.child then
            local bag=U().call(item,"getInventory") local child=bag and U().call(bag,"AddItem",row.child)
            local childId=child and U().call(child,"getID")
            local childType=child and U().call(child,"getFullType")
            if not child or U().call(child,"getContainer")~=bag
                or (type(childId)~="number" and type(childId)~="string") or tostring(childId)==""
                or type(childType)~="string" or childType=="" then complete=false
            else
                stash.items[#stash.items+1]={id=tostring(childId),type=childType}
                if childType~=row.child then complete=false end
            end
        end
    end
    if #names==0 or forced or lock.kind=="persona" then return #names>0 end
    local suffix=" ("..string.upper(tostring(kind))..", "..string.upper(roomName)..")"
    local note=complete and row and row.quote or "NOTE TO SELF: SPARE "..table.concat(names,", ").."."
    stash.note=note:sub(1,math.max(1,200-#suffix))..suffix
    return true
end
local function search(w)
    local f=w.payoffSearch
    if not f then return end
    local cell=type(getCell)=="function" and getCell()
    for _=1,64 do
        if f.index>=1681 then break end
        local i=f.index f.index=i+1
        local dx,dy=i%41-20,math.floor(i/41)-20
        local tile=dx*dx+dy*dy<=400 and U().call(cell,"getGridSquare",f.x+dx,f.y+dy,f.z)
        if tile and U().call(tile,"getBuildingDef")==f.building then
            for _,object in ipairs(U().list(U().call(tile,"getObjects"),32)) do
                local c=U().call(object,"getContainer") local kind=U().call(c,"getType")
                if containers[kind] and not f.blocked[c] then
                    local distance=math.abs(f.x-tile:getX())+math.abs(f.y-tile:getY())
                    local score=distance+(kind==f.preferred and 0 or 100)
                    if not f.score or score<f.score then f.score,f.where=score,{x=tile:getX(),y=tile:getY(),z=f.z,type=kind,
                        sprite=U().call(U().call(object,"getSprite"),"getName")} end
                end
            end
        end
    end
    if f.index>=1681 then
        local c=f.where and SC.TerminalDrawers.container(f.where)
        if c and not SC.TerminalDrawers.locked(c) then
            if U().call(c,"isExplored")~=true and ItemPicker and ItemPicker.fillContainer then pcall(ItemPicker.fillContainer,c,w.player) U().call(c,"setExplored",true) end
            P.place(w.player,w.object,w.system,c,false)
        else w.system.lock.stash={committed=true,items={}} end
        w.payoffSearch=nil
    end
end
local function dayNumber(y,m,d)
    if m<=2 then y=y-1 end
    local era=math.floor(y/400) local yy=y-era*400
    return era*146097+yy*365+math.floor(yy/4)-math.floor(yy/100)
        +math.floor((153*(m+(m>2 and -3 or 9))+2)/5)+d-1
end
function P.daysSinceOutbreak()
    local clock=type(getGameTime)=="function" and getGameTime()
    local y,m,d=U().call(clock,"getYear"),U().call(clock,"getMonth"),U().call(clock,"getDay")
    if y and m and d then return math.max(0,dayNumber(y,m+1,d+1)-dayNumber(1993,7,9)) end
end
function P.firstName(owner)
    local titles={dr=true,mr=true,mrs=true,ms=true,miss=true,prof=true,professor=true,rev=true,
        reverend=true,officer=true,sgt=true,sergeant=true,capt=true,captain=true,chief=true,doctor=true}
    local count=0
    for word in tostring(owner or "Operator"):gmatch("%S+") do
        count=count+1
        if not titles[string.lower(word):gsub("%.","")] or count>=4 then return word end
    end
    return "Operator"
end
function P.welcome(state)
    local profile=SC.TerminalFiles.get(state.archive)
    if state.archive=="_factory" then return {name="NO USER PROFILE.",days=0,mail=0,document="DISK ERRORS CORRECTED: ALL OF THEM."} end
    local owner=P.firstName(profile.owner)
    local last=profile.entries[#profile.entries] local document=""
    for sentence in (last and last.text or ""):gmatch("[^.!?]+[.!?]?") do
        sentence=sentence:match("^%s*(.-)%s*$") if #sentence>=24 then document=sentence break end
    end
    local cut=math.floor(#document*.6) document=document:sub(1,cut):match("^(.*)%s+%S*$") or document:sub(1,cut)
    local days=P.daysSinceOutbreak() or 0
    return {name="WELCOME BACK, "..string.upper(owner:match("^%S+") or "OPERATOR")..".",days=days,
        mail=math.floor(state.seed%37+days/3),document='"'..document.."_"}
end
function P.begin(w,how)
    local lock=w.system.lock
    if lock.slip and SC.TerminalDrawers then SC.TerminalDrawers.release(w.object) end
    if lock.welcomed then w:startEmma() return end
    if w.headless or not SC.Terminal.powered(w.object) then return end
    w.payoff={started=SC.GameplayUtil.nowMs(),how=how,welcome=P.welcome(w.system)}
    if lock.realItems~=false and not lock.drawer and not lock.slip and not (lock.stash and lock.stash.committed) then
        local x,y,z=U().position(w.object) local tile=U().square(w.object)
        local row=SC.TerminalLockStashes[w.system.archive] local quote=row and string.lower(row.quote) or ""
        local preferred=quote:find("shelf",1,true) and "shelves" or quote:find("locker",1,true) and "locker" or quote:find("cupboard",1,true) and "counter" or "desk"
        local building=U().call(tile,"getBuildingDef")
        if building and type(getCell)=="function" then
            w.payoffSearch={index=0,x=x,y=y,z=z,building=building,preferred=preferred,blocked=SC.TerminalDrawers.snapshot()}
        else lock.stash={committed=true,items={}} end
    end
    w.payoff.flash=not lock.grantedShown
    if lock.grantedShown then w.payoff.started=w.payoff.started-1000
    else lock.grantedShown=true SC.Terminal.playFeedbackSound("LFTerminalGranted") end
end
function P.update(w,now)
    if not w.payoff then return end
    local lock=w.system.lock
    if w.payoffSearch then search(w) end
    local elapsed=now-w.payoff.started
    if (elapsed>=1000 or w.payoff.skip) and not w.payoff.login then w.payoff.login=true SC.Terminal.playFeedbackSound(SC.Terminal.LOGIN_SOUND) end
    if not w.payoffSearch and (w.payoff.skip or elapsed>=2800) then
        local data=w.payoff.welcome w.system.lock.welcomed=true w.payoff=nil
        w:print(data.name,"system")
        if w.system.archive=="_factory" then w:print(data.document,"system")
        elseif data.days>0 then w:print("LAST SIGN-IN: "..data.days.." DAYS AGO.","system") else w:print("LAST SIGN-IN: THIS MORNING.","system") end
        if w.system.archive~="_factory" then
            w:print("UNREAD MAIL: "..data.mail,"system")
            w:print("OPENING LAST DOCUMENT...","system") w:print(data.document,"system")
        end
        w:startEmma()
        if w.licenseAwarded then w:print("RECOVERY LOG COMPLETE. LICENSED TO "..SC.TerminalLocks.ledger().licensee,"system") end
        if lock.rival and lock.rival.message then w:print(lock.rival.message,"system") end
        if w.system.archive~="_factory" then w:print("That was not your name. I'll allow it.","emma") end
        if w.lockClutch then w:print(clutchLines[w.system.seed%#clutchLines+1],"emma") end
        if w.system.lock.stash and w.system.lock.stash.note then w:print(w.system.lock.stash.note,"system") end
        SC.TerminalLockCrew.react(w,w.lockClutch and "clutch" or "unlock",w.lockClutch and 100 or 50)
    end
end
function P.lines(w,now)
    local p=w.payoff local d=p.welcome local elapsed=now-p.started
    if w.licenseAwarded then return {"RECOVERY LOG COMPLETE", "LICENSED TO "..SC.TerminalLocks.ledger().licensee,"LARCHFIELD / ACCOUNT RECOVERY"} end
    if elapsed<1000 then return {"ACCESS GRANTED"} end
    if w.system.archive=="_factory" then return {d.name,d.document} end
    return {d.name,d.days>0 and "LAST SIGN-IN: "..d.days.." DAYS AGO." or "LAST SIGN-IN: THIS MORNING.",
        "UNREAD MAIL: "..math.floor(d.mail*math.min(1,(elapsed-1000)/1500)),"OPENING LAST DOCUMENT...",d.document}
end
return P
