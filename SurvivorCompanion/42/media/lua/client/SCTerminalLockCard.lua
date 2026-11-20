-- SPDX-License-Identifier: MIT
-- Seeded magnetic-stripe recovery. Saved data is bounded progress, never a board.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local C={} SC.TerminalLockCard=C
C.ITEM="LivingFellows.LarchKeyCard"
local function U() return SC.ControlUtil end
local function data() return SC.TerminalLockCardData end
local function shuffle(values,pick)
    for i=#values,2,-1 do local j=pick(i) values[i],values[j]=values[j],values[i] end
    return values
end
function C.random(state,offset) return SC.TerminalSystem.random(((state.seed+(offset or 0)-1)%2147483646)+1) end
function C.skill(player)
    return math.max(0,math.min(10,math.floor(tonumber(SC.Terminal.electricalSkill(player)) or 0)))
end
function C.settings(skill)
    skill=math.max(0,math.min(10,math.floor(tonumber(skill) or 0)))
    return skill<3 and 4 or skill<8 and 3 or 2,5+math.floor(skill/3)
end
function C.board(state)
    local profile=SC.TerminalFiles.get(state.archive)
    local pick=C.random(state,17389) local badge,sum="",0
    for _=1,5 do local digit=pick(10)-1 badge=badge..digit sum=sum+digit end
    local check=string.format("%02d",sum)
    local order=shuffle({1,2,3,4,5,6,7},pick) local checkSeen=false
    for i=1,4 do
        if order[i]>=6 then
            if checkSeen then
                for j=5,7 do if order[j]<=5 then order[i],order[j]=order[j],order[i] break end end
            else checkSeen=true end
        end
    end
    local name=tostring(profile and profile.owner or "Operator"):match("^[^,]+") or "Operator"
    local first=SC.TerminalPayoff.firstName(name)
    local owner=(first:sub(1,1)..". "..(name:match("(%S+)%s*$") or first)):upper()
    local entries=profile and profile.entries or {}
    local date=entries[#entries] and entries[#entries].date or "1993-07-09"
    local hint=entries[C.random(state,19711)(math.max(1,math.min(3,#entries)))]
    local site=data().sites[profile and profile.kind] or "GEN"
    return {site=site,badge=badge,check=check,digits=badge..check,rawStripe=site..badge..check,
        stripe=site.."-"..badge.."-"..check,gapOrder=order,owner=owner,lastDate=date,
        hintDate=hint and hint.date or "1993-07-03"}
end
function C.gapCount(state,skill)
    local read=state.lock.card and state.lock.card.read or "none"
    local count=read=="service" and 1 or read=="owner" and 2 or 4
    return math.max(1,count-((tonumber(skill) or 0)>=6 and 1 or 0))
end
function C.ensure(state,player)
    if not state.lock.card then
        state.lock.card={spawned=false,absent=false,read="none",solved="0000000",tried={"","","","","","",""},
            mismatches=0,hinted=false,gapsShown=4,encoded=false}
    end
    local card=state.lock.card
    card.gapsShown=math.min(card.gapsShown,C.gapCount(state,C.skill(player)))
    return card
end
function C.known(state,position,board)
    local card=state.lock.card if not card or position<1 or position>7 then return false end
    if card.solved:sub(position,position)=="1" then return true end
    board=board or C.board(state)
    for i=1,card.gapsShown do if board.gapOrder[i]==position then return false end end
    return true
end
function C.complete(state)
    if not state or not state.lock or not state.lock.card then return false end
    local board=C.board(state)
    for i=1,7 do if not C.known(state,i,board) then return false end end
    return true
end
function C.candidates(state,position,skill,board)
    board=board or C.board(state)
    local answer=board.digits:sub(position,position) local wrong={}
    for digit=0,9 do if tostring(digit)~=answer then wrong[#wrong+1]=tostring(digit) end end
    shuffle(wrong,C.random(state,23339+position*1297))
    local count=C.settings(skill) local result={answer}
    for i=1,count-1 do result[#result+1]=wrong[i] end
    table.sort(result) return result
end
function C.cursor(w)
    local board=C.board(w.system) local cursor=w.lockCardCursor
    if cursor and cursor>=1 and cursor<=7 and not C.known(w.system,cursor,board) then return cursor end
    for i=1,7 do if not C.known(w.system,i,board) then w.lockCardCursor=i return i end end
    w.lockCardCursor=nil
end
function C.select(w,position)
    position=tonumber(position)
    if position and position==math.floor(position) and position>=1 and position<=7 and not C.known(w.system,position) then
        w.lockCardCursor=position return true
    end
    return false
end
local function locked(w)
    local untilHours=w.system.lock.card.lockedUntil
    local now=U().hours()
    return untilHours and (not now or now<untilHours),now
end
local function usable(w,unlocked)
    return w and w.system and w.system.lock and w.system.lock.kind=="card"
        and (unlocked and not w.system.locked or not unlocked and w.system.locked)
        and not w.lockPage and not w.lockConfirm and not w.securityPanel
        and SC.Terminal.ownsState(w.object,w.system) and SC.Terminal.present(w.object)
        and SC.Terminal.near(w.player,w.object) and SC.Terminal.powered(w.object)
        and U().call(w.player,"isDead")~=true
end
function C.itemData(item)
    local md=U().data(item) local stripe=type(md)=="table" and md.LF_LarchKey
    if type(stripe)=="table" and type(stripe.seed)=="number" and stripe.seed==math.floor(stripe.seed)
        and stripe.seed>=1 and stripe.seed<=2147483646 then return stripe end
end
function C.carried(player,state,ownerOnly)
    local first=U().call(U().inventory(player),"getFirstTypeRecurse",C.ITEM)
    local best,rank local seen={}
    local function consider(item)
        if not item or seen[item] then return end seen[item]=true
        if U().call(item,"getFullType")~=C.ITEM or not U().owns(player,item) then return end
        local stripe=C.itemData(item) local owner=stripe and state and stripe.seed==state.seed
        if ownerOnly and not owner then return end
        local score=stripe and stripe.service==true and 3 or owner and 2 or 1
        if not rank or score>rank then best,rank=item,score end
    end
    consider(first)
    for _,item in ipairs(U().items(player)) do consider(item) end
    return best
end
function C.stripe(state,position,digit,mask)
    local board=C.board(state) local digits=""
    for i=1,7 do
        digits=digits..(i==position and digit or C.known(state,i,board) and board.digits:sub(i,i) or mask or "_")
    end
    return board.site.."-"..digits:sub(1,5).."-"..digits:sub(6)
end
function C.hint(w,commit,position)
    if not usable(w,false) then return nil end
    C.ensure(w.system,w.player)
    if locked(w) then return nil end
    position=position or C.cursor(w)
    if type(position)~="number" or position~=math.floor(position) or position<1 or position>7 or C.known(w.system,position) then return nil end
    local digit=C.board(w.system).digits:sub(position,position)
    if commit then
        local card=w.system.lock.card
        card.solved=card.solved:sub(1,position-1).."1"..card.solved:sub(position+1)
        w.lockCardCursor=nil
        if C.complete(w.system) then SC.TerminalLocks.finishUnlock(w,"card") end
    end
    return digit,position
end
function C.update(w)
    if not w.system or not w.system.lock or w.system.lock.kind~="card" then return end
    if w.lockCardReadSoundAt and SC.GameplayUtil.nowMs()>=w.lockCardReadSoundAt then
        w.lockCardReadSoundAt=nil SC.Terminal.playFeedbackSound("LFCardRead")
    end
    if not w.system.locked then return end
    local card=C.ensure(w.system,w.player)
    local waiting,now=locked(w)
    if card.lockedUntil and not waiting and now then
        card.lockedUntil=nil card.mismatches=0
        w.securityMessage="READER READY. VERIFIED DIGITS RETAINED."
    end
    if not waiting and C.complete(w.system) and usable(w,false) then SC.TerminalLocks.finishUnlock(w,"card") end
end
function C.swipe(w,item)
    if not usable(w,false) then return false,false end
    C.ensure(w.system,w.player)
    if item and not U().owns(w.player,item) then return false,false end
    item=item or C.carried(w.player,w.system)
    if not item then
        for _,candidate in ipairs(U().items(w.player)) do
            local kind=(tostring(U().call(candidate,"getFullType") or ""):match("[^.]+$") or ""):lower()
            if kind:match("^idcard") or kind:match("^creditcard") or kind=="badge" then item=candidate break end
        end
    end
    SC.Terminal.playFeedbackSound("LFCardSwipe")
    local stripe=item and U().call(item,"getFullType")==C.ITEM and C.itemData(item)
    local read=stripe and (stripe.service==true and "service" or stripe.seed==w.system.seed and "owner")
    if not read then
        w.securityMessage=stripe and "CARDHOLDER NOT ENROLLED ON THIS MACHINE."
            or item and "NO LARCH/KEY DATA ON STRIPE." or "NO CARD. SWIPE ONE TO READ IT."
        return true,false
    end
    local card=w.system.lock.card
    if card.read~="service" then card.read=read end
    C.ensure(w.system,w.player) w.lockCardCursor=nil
    w.securityMessage=read=="service" and "SERVICE CARD READ. ONE STRIPE GAP REMAINS."
        or "CARDHOLDER VERIFIED. OWNER STRIPE MERGED."
    w.lockCardReadSoundAt=SC.GameplayUtil.nowMs()+400
    if read=="owner" and SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"cardSwipe",50) end
    C.update(w) return true,true
end
function C.input(w,raw)
    if not usable(w,false) then return false end
    local text=tostring(raw or ""):lower():match("^%s*(.-)%s*$")
    if text=="swipe" or text=="swipe card" then return C.swipe(w) end
    local position=text:match("^gap ([1-7])$")
    if position then
        if not C.select(w,position) then w.securityMessage="THAT DIGIT IS ALREADY VERIFIED." end
        return true
    end
    C.update(w)
    if not w.system.locked then return true end
    local waiting,now=locked(w)
    if waiting then
        w.securityMessage=now and "READER LOCKED. TRY AGAIN IN "..math.ceil((w.system.lock.card.lockedUntil-now)*60).." MINUTES."
            or "READER LOCKED. CLOCK UNAVAILABLE."
        return true
    end
    if not now then w.securityMessage="CLOCK UNAVAILABLE." return true end
    if not text:match("^[%d%s%-]+$") then w.securityMessage="TYPE A DISPLAYED DIGIT, OR SWIPE A CARD." return true end
    text=text:gsub("[%s%-]","")
    for digit in text:gmatch("%d") do
        local cursor=C.cursor(w) if not cursor then break end
        local card=w.system.lock.card local listed=false
        for _,candidate in ipairs(C.candidates(w.system,cursor,C.skill(w.player))) do if digit==candidate then listed=true break end end
        if not listed then w.securityMessage="THE HEAD NEVER READ THAT." break end
        if card.tried[cursor]:find(digit,1,true) then w.securityMessage="THAT READ WAS ALREADY REJECTED AT GAP "..cursor.."." break end
        if digit==C.board(w.system).digits:sub(cursor,cursor) then
            card.solved=card.solved:sub(1,cursor-1).."1"..card.solved:sub(cursor+1)
            w.lockCardCursor=nil
            for i=cursor+1,7 do if not C.known(w.system,i) then w.lockCardCursor=i break end end
            w.securityMessage="GAP "..cursor.." VERIFIED."
            if C.complete(w.system) then SC.TerminalLocks.finishUnlock(w,"card") break end
        else
            card.tried[cursor]=card.tried[cursor]..digit card.mismatches=card.mismatches+1
            local _,limit=C.settings(C.skill(w.player)) local failed=card.mismatches>=limit
            SC.TerminalLocks.record(w,C.stripe(w.system,cursor,digit),failed and "failed" or "wrong")
            w.securityMessage="STRIPE MISMATCH AT GAP "..cursor.."."
            if failed then
                card.lockedUntil=now+1 w.system.lock.bypass=true
                w.securityMessage="READER LOCKED. TRY AGAIN IN 60 MINUTES. OTHER WAYS IN ARE AVAILABLE."
                if SC.TerminalLockCrew then SC.TerminalLockCrew.react(w,"failure",50) end
            elseif card.mismatches>=2 and not card.hinted then
                local open={} for i=1,7 do if not C.known(w.system,i) then open[#open+1]=i end end
                if #open>0 then
                    local pos=open[C.random(w.system,28183)(#open)]
                    card.hinted=true card.hintPos=pos
                    C.hint(w,true,pos)
                    local date=C.board(w.system).hintDate
                    w.securityMessage="READER LOG "..date:sub(6,7).."/"..date:sub(9,10).."/93 08:47: GAP "..pos.." READ CLEAN."
                end
            end
            break
        end
    end
    return true
end
function C.canEncode(w)
    return usable(w,true) and w.system.lock.card and not w.system.lock.slip and not w.system.lock.card.encoded
        and C.carried(w.player,w.system,true)~=nil
end
function C.encode(w)
    if not C.canEncode(w) then return false end
    local item=C.carried(w.player,w.system,true) local stripe=C.itemData(item)
    w.system.lock.card.encoded=true
    stripe.service=true
    U().call(item,"setName","LARCH/KEY Service Card") U().call(item,"setCustomName",true)
    if type(w.print)=="function" then w:print(data().encoded[C.random(w.system,30347)(#data().encoded)],"emma") end
    return true
end
function C.place(state,player,object)
    local card=C.ensure(state,player)
    if card.spawned then return nil end
    -- Commit before any native creation or insertion, including uncertain failures.
    card.spawned=true
    if C.random(state,32143)(5)==1 then card.absent=true return nil end
    local tile=U().square(object) local room=U().call(tile,"getRoom")
    local x,y,z=U().position(object) local cell=type(getCell)=="function" and getCell()
    local choices={} local allowed={desk=true,sidetable=true,filingcabinet=true,dresser=true,counter=true}
    local claimed=state.lock.drawer and SC.TerminalDrawers.container(state.lock.drawer)
    if x and room then for dx=-6,6 do for dy=-6,6 do
        local square=dx*dx+dy*dy<=36 and U().call(cell,"getGridSquare",x+dx,y+dy,z)
        if square and U().call(square,"getRoom")==room then
            for _,candidate in ipairs(U().list(U().call(square,"getObjects"),64)) do
                local container=U().call(candidate,"getContainer")
                if #choices<256 and allowed[U().call(container,"getType")] and container~=claimed
                    and not SC.TerminalDrawers.locked(container) then choices[#choices+1]=container end
            end
        end
    end end end
    local create=type(instanceItem)=="function" and instanceItem or InventoryItemFactory and InventoryItemFactory.CreateItem
    local okay,item=false,nil if create then okay,item=pcall(create,C.ITEM) end
    if not okay or not item then card.absent=true return nil end
    local md=U().data(item)
    if type(md)~="table" then card.absent=true return nil end
    md.LF_LarchKey={seed=state.seed,service=false}
    U().call(item,"setName","Access Card ("..C.board(state).owner..")") U().call(item,"setCustomName",true)
    if #choices>0 then
        local container=choices[C.random(state,35141)(#choices)]
        if U().call(container,"isExplored")~=true then
            if ItemPicker and type(ItemPicker.fillContainer)=="function" then pcall(ItemPicker.fillContainer,container,player) end
            U().call(container,"setExplored",true)
        end
        U().call(container,"AddItem",item)
        if U().call(item,"getContainer")==container then card.itemId=tostring(U().call(item,"getID")) return item end
        card.absent=true return nil
    end
    local world=SC.TerminalLockPhysical and SC.TerminalLockPhysical.place(item,object)
    if world then card.itemId=tostring(U().call(item,"getID")) return item end
    card.absent=true return nil
end
function C.open(w)
    C.ensure(w.system,w.player)
    local lock=w.system.lock lock.reactions=lock.reactions or {}
    if lock.reactions.cardSearch or C.carried(w.player,w.system) then return end
    lock.reactions.cardSearch=true
    local pool=lock.card.absent and data().absent or data().search
    local text=pool[C.random(w.system,37633)(#pool)] local date=C.board(w.system).lastDate
    text=text:gsub("%%1",date:sub(6,7).."/"..date:sub(9,10).."/93")
    if type(w.print)=="function" then w:print(text,"emma") end
end
function C.view(w)
    local state=w.system local card=state.lock.card local board=C.board(state)
    local function readStripe(missing)
        local digits="" for i=1,7 do digits=digits..(missing[i] and "?" or board.digits:sub(i,i)) end
        return board.site.."-"..digits:sub(1,5).."-"..digits:sub(6)
    end
    local ownerMissing={} for i=1,4 do ownerMissing[board.gapOrder[i]]=true end
    local swipeMissing={}
    for i=1,card.read=="service" and 1 or 2 do swipeMissing[board.gapOrder[i]]=true end
    swipeMissing[board.gapOrder[5]]=true
    if card.read=="service" then swipeMissing[board.gapOrder[6]]=true end
    local _,limit=C.settings(C.skill(w.player)) local waiting,now=locked(w)
    local result={board=board,positions={},cursor=C.cursor(w),mismatches=card.mismatches,attemptsLeft=math.max(0,limit-card.mismatches),
        read=card.read,lockedMinutes=waiting and (now and math.max(1,math.ceil((card.lockedUntil-now)*60)) or 60) or nil,
        message=w.securityMessage,canSwipe=C.carried(w.player,state)~=nil,stripe=C.stripe(state),lastRead=readStripe(ownerMissing)}
    result.yourRead=card.read~="none" and readStripe(swipeMissing) or nil
    result.ownerStripe,result.swipeStripe=result.lastRead,result.yourRead
    for i=1,7 do
        local known=C.known(state,i,board)
        result.positions[i]={position=i,digit=board.digits:sub(i,i),known=known,solved=card.solved:sub(i,i)=="1",open=not known,
            candidates=C.candidates(state,i,C.skill(w.player),board),tried=card.tried[i]}
    end
    return result
end
function C.lines(w)
    local view=C.view(w) local rows={"LARCH/KEY CARD READER / MISMATCHES LEFT: "..view.attemptsLeft,
        "CARDHOLDER: "..view.board.owner,"STRIPE  "..view.stripe,"CHECK: THE BADGE DIGITS ADD UP TO THE LAST TWO."}
    if view.cursor then rows[#rows+1]="GAP "..view.cursor.." READ AS  "..table.concat(view.positions[view.cursor].candidates,"   ") end
    if view.lockedMinutes then rows[#rows+1]="READER LOCKED. TRY AGAIN IN "..view.lockedMinutes.." MINUTES." end
    if view.message then rows[#rows+1]=view.message end
    if view.canSwipe then rows[#rows+1]="Swipe card" end
    if C.skill(w.player)>=3 then rows[#rows+1]="ELECTRICAL "..C.skill(w.player)..": YOU CLEAN THE READ HEAD." end
    return rows
end
return C
