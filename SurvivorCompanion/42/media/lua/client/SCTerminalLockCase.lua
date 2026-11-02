-- SPDX-License-Identifier: MIT
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local C={} SC.TerminalLockCase=C
function C.risk(state,skill,battery)
    local risk=math.max(10,math.min(60,60-5*skill))
    if state.lock.crewHint then risk=math.max(10,risk-10) end
    return battery and risk/2 or risk
end
function C.soldered(state) return state.seed%4==0 end
function C.roll(state)
    -- Theme, Director and hardware failures use different PRNG positions.
    -- Reusing the Director's draw would make one lock almost always slip.
    local pick=SC.TerminalSystem.random(state.seed)
    for _=1,4 do pick(100) end
    return pick(100)
end
function C.open(w) w.lockPage="case" w.securityMessage=nil end
function C.complete(player,object,battery)
    local w=SC.Terminal.window
    local state
    if w and w.object==object and SC.Terminal.ownsState(object,w.system) then state=w.system
    else state=SC.Terminal.computerState(player,object) w=nil end
    if not state or not state.locked or not state.lock or not state.lock.bypass or state.lock.caseFinished
        or not SC.Terminal.present(object) or not SC.Terminal.near(player,object)
        or not SC.Terminal.ownsState(object,state)
        or SC.ControlUtil.call(player,"isDead")==true then return false,"Case recovery is no longer available." end
    if not SC.ControlUtil.hasTool(player,"Base.Screwdriver") then return false,"Bring a screwdriver." end
    if battery and C.soldered(state) then return false,"The battery is soldered to this board." end
    local okay,reason=SC.ControlUtil.consume(player,{["Base.ElectronicsScrap"]=1})
    if not okay then return false,reason end
    state.lock.caseFinished=true
    local slip=C.roll(state)<=C.risk(state,SC.ControlUtil.skill(player),battery)
    if slip then
        state.archive="_factory" state.lock.slip=true
        local body=SC.ControlUtil.call(player,"getBodyDamage")
        local hand=body and SC.ControlUtil.call(body,"getBodyPart",BodyPartType.Hand_L)
        if hand then SC.ControlUtil.call(hand,"setBurnTime",.2) SC.ControlUtil.call(hand,"AddDamage",1) end
    end
    if not w then w={player=player,object=object,system=state,headless=true} end
    if SC.TerminalLamp then w.healthBaseline=SC.TerminalLamp.health(player) end
    local unlocked=SC.TerminalLocks.finishUnlock(w,slip and "slip" or "case")
    return unlocked,slip and "Reset complete. The owner's files were erased; a small hand burn needs attention." or "Hardware reset complete. The files survived."
end
function C.queue(player,object,battery)
    local clock=type(getGameTime)=="function" and getGameTime()
    local minutes=tonumber(SC.ControlUtil.call(clock,"getMinutesPerDay")) or 60
    local duration=300+(battery and 5*minutes*2.5 or 0)
    -- Native duration is captured when the queue creates its first action.
    -- Set it before add(), rather than editing the Lua object afterwards.
    return SC.TerminalServices.install(player,object,function() return C.complete(player,object,battery) end,duration)
end
function C.lines(w)
    local skill=SC.ControlUtil.skill(w.player)
    local rows={"486 / HARDWARE RECOVERY","Screwdriver + 1 Scrap Electronics.",
        "[1] CLR CMOS jumper: "..C.risk(w.system,skill,false).."% slip risk",
        C.soldered(w.system) and "[2] Battery soldered: unavailable" or "[2] CMOS battery: "..C.risk(w.system,skill,true).."% risk (+5 game min)",
        "[3] Back to password"}
    local helper=SC.TerminalLockCrew.helper(w)
    if helper then rows[#rows+1]="[4] Ask "..SC.TerminalLockCrew.name(helper) end
    if skill>=3 then rows[#rows+1]="ELECTRICAL "..skill..": YOU HAVE SEEN THIS BOARD BEFORE." end
    rows[#rows+1]=w.securityMessage or "A slip opens the computer but erases its old files."
    return rows
end
function C.input(w,raw)
    local lower=string.lower(raw)
    if lower=="3" or lower=="back" then w.lockPage=nil return true end
    if lower=="ask for help" or lower=="4" then return SC.TerminalLockCrew.hint(w) end
    if lower=="1" or lower=="2" then
        if lower=="2" and C.soldered(w.system) then w.securityMessage="The battery is soldered in place." return true end
        local okay,reason=C.queue(w.player,w.object,lower=="2")
        w.securityMessage=reason
        if okay then w:close() end
        return true
    end
    w.securityMessage="Choose a component or return to the password." return true
end
function C.context(context,player,object)
    local active=SC.Terminal.window
    local state=active and active.object==object and active.system or SC.Terminal.peekState(object)
    if not state or not state.locked or type(state.lock)~="table" or not state.lock.bypass then return end
    if not SC.ControlUtil.hasTool(player,"Base.Screwdriver") then return end
    local option=context:addOption("Computer: open the case",nil,nil)
    local submenu=ISContextMenu:getNew(context) context:addSubMenu(option,submenu)
    local skill=SC.ControlUtil.skill(player)
    submenu:addOption("Move CLR CMOS jumper ("..C.risk(state,skill,false).."% slip risk)",player,function(actor) C.queue(actor,object,false) end)
    if not C.soldered(state) then submenu:addOption("Remove CMOS battery ("..C.risk(state,skill,true).."% risk; +5 game min)",player,function(actor) C.queue(actor,object,true) end) end
end
return C
