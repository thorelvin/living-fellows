-- SPDX-License-Identifier: MIT
-- Runs the central reader and the real lock input handlers; native effects are
-- replaced at their existing boundaries, not by a second parser in the test.
local SC=SurvivorCompanion
local L,S=SC.TerminalLocks,SC.TerminalSystem
local P,R,W,G,E,C=SC.TerminalLockPhone,SC.TerminalLockRadio,SC.TerminalLockWheel,
    SC.TerminalLockStory,SC.TerminalLockEmma,SC.TerminalLockCase
local passed,total,report=0,0,{}
local old={}
local function replace(t,k,v) old[#old+1]={t,k,t[k]} t[k]=v end
for _,name in ipairs({"ownsState","present","near","powered","normalPowered"}) do replace(SC.Terminal,name,function() return true end) end
replace(SC.Terminal,"electricalSkill",function() return 3 end)
replace(SC.TerminalLockCrew,"hint",function(w) w.polishHit="hint" return true end)
replace(C,"queue",function() return true,"component" end)
replace(W,"nearby",function() return true end)
replace(W,"turn",function(w,n) w.polishHit=n==-1 and "left" or "right" end)
replace(P,"dial",function(w) w.polishHit="dial" end)
replace(P,"code",function() return "123456" end)
replace(R,"code",function() return "123456" end)
replace(R,"heard",function() return true end)
replace(G,"start",function(w) w.polishHit="start" end)
replace(E,"offers",function(w) w.polishHit="argument" return {} end)
replace(L,"finishUnlock",function(w) w.polishHit="unlock" return true end)
replace(L,"record",function() end)
replace(SC.TerminalLockSearch,"input",function(w,raw) w.polishHit="search-preserved" w.polishRaw=raw return true end)
replace(SC.TerminalLockUI,"footer",function() return {{value="failed logins"},{value="log off"}} end)
local function window(row)
    local s=S.create(731,"police",false,false,"polish-input")
    s.lock={kind=row.kind,bypass=true,heard=true,serial="SAFE",wheel={rotation=0,correct=0,required=3},
        crack={doneHours=2,requiredHours=12,lastHours=100,powered=true},
        story={phase="title"},emma={round=0,conviction=0,patience=2,used={},history={}}}
    local w={system=s,player={},object={},gameHours=100,lockPage=row.page,lockConfirm=row.confirm,
        lockManualPage=2,securityScroll=0,securityHits={}}
    function w:close() self.polishHit="closed" end
    return w
end
local function evaluate(row,w)
    local want=row.want
    if want=="yes" then return not w.lockConfirm and w.system.lock.bypass end
    if want=="no" then return not w.lockConfirm and not w.system.lock.bypass end
    if want=="confirm" then return w.lockConfirm==true end
    if want=="back" then return w.lockPage==nil end
    if want=="logins" or want=="footer" then return w.lockPage=="logins" end
    if want=="manual" then return w.lockPage=="manual" end
    if want=="next" then return w.lockManualPage==3 end
    if want=="previous" then return w.lockManualPage==1 end
    if want=="wheel" then return w.lockManualPage==5 end
    if want=="component" then return w.polishHit=="closed" and w.securityMessage=="component" end
    if want=="search-preserved" then return w.polishRaw==row.input end
    local message=(w.securityMessage or ""):lower()
    if want=="battery" then return message:find("battery",1,true)~=nil end
    if want=="hours" then return message:find("hours",1,true)~=nil end
    if want=="phone-explain" then return message:find("six",1,true)~=nil end
    if want=="frequency" then return message:find("96.4",1,true)~=nil end
    return w.polishHit==want
end
for _,row in ipairs(SC.EmmaTalkPolishData.locks.rows) do
    local w=window(row) if row.confirm then w.system.lock.bypass=false end
    local ok=pcall(L.input,w,row.input)
    local fit=ok and evaluate(row,w)
    total=total+1 if fit then passed=passed+1 end
    report[#report+1]=(fit and "PASS " or "MISS ")..row.id
    local b=SC.EmmaTalkPolishBaseline
    assert(fit or not b or not b.passed[row.id],"previously passing lock input regressed: "..row.id)
end
-- Exact code checks, hearing requirements and password guesses remain owned by
-- their original handlers. A menu choice must never stand in for a code.
for _,kind in ipairs({"phone","radio"}) do
    for _,raw in ipairs({"999 999","999-999","12345","1","2?","1234567","123a456"}) do
        local w=window({kind=kind}) L.input(w,raw)
        assert(w.polishHit~="unlock",kind.." falsely unlocked on "..raw)
    end
end
for _,kind in ipairs({"word","remember"}) do
    local w=window({kind=kind})
    assert(L.input(w,"N0T-THE-PASSWORD?")==false,"password text must reach the unchanged exact guess handler")
end
for i=#old,1,-1 do local r=old[i] r[1][r[2]]=r[3] end
SC_TEST_REPORT=(SC_TEST_REPORT or "").."POLISH_SCORE locks "..passed.."/"..total.."\n"..table.concat(report,"\n").."\n"
local floor=SC.EmmaTalkPolishBaseline and SC.EmmaTalkPolishBaseline.floor
assert(not floor or not floor.locks or passed>=floor.locks,"lock input score regressed")
