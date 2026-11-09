-- SPDX-License-Identifier: MIT
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local C={} SC.TerminalLockCrack=C
function C.password(state)
    local profile=SC.TerminalFiles.get(state.archive)
    local owner=(profile and profile.owner or "Operator"):gsub(",.*$","")
    return string.upper(owner:match("(%S+)%s*$") or "Operator"):gsub("[^A-Z]","").."93"
end
function C.catchUp(state,now,powered)
    local c=type(state.lock)=="table" and state.lock.crack
    if not c or not now then return end
    if now>=c.lastHours and c.powered and powered then
        c.doneHours=math.min(c.requiredHours,c.doneHours+now-c.lastHours)
    end
    c.lastHours,c.powered=math.max(c.lastHours,now),powered==true
end
function C.sealed(state)
    local c=state.lock.crack
    c.sealed=math.min(#C.password(state),math.max(c.sealed or 0,math.floor(#C.password(state)*c.doneHours/c.requiredHours)))
    return c.sealed
end
function C.open(w)
    if SC.EmmaJump and SC.EmmaJump.active(w.player,w.object) then
        w.securityMessage="Borrowed power cannot run background password recovery." return
    end
    local now=SC.ControlUtil.hours()
    if not now then w.securityMessage="Clock unavailable." return end
    if not w.system.lock.crack then
        local skill=SC.Terminal.electricalSkill(w.player)
        w.system.lock.crack={doneHours=0,lastHours=now,powered=(SC.Terminal.normalPowered or SC.Terminal.powered)(w.object),requiredHours=skill<4 and 12 or skill<8 and 9 or 6}
    end
    C.catchUp(w.system,now,(SC.Terminal.normalPowered or SC.Terminal.powered)(w.object))
    w.lockPage="crack" w.lockCrackOpened=SC.GameplayUtil.nowMs() w.crackSoundLetters=0 w.securityMessage=nil
end
function C.update(w,now)
    C.catchUp(w.system,SC.ControlUtil.hours(),(SC.Terminal.normalPowered or SC.Terminal.powered)(w.object))
    local c=w.system.lock.crack
    if not c then return end
    local elapsed=math.max(0,now-(w.lockCrackOpened or now))
    local sealed=math.floor(C.sealed(w.system)*math.min(1,elapsed/2000))
    if sealed>(w.crackSoundLetters or 0) then
        w.crackSoundLetters=sealed SC.Terminal.playFeedbackSound("LFReelClunk")
    end
    if elapsed>=2000 and c.doneHours>=c.requiredHours then SC.TerminalLocks.finishUnlock(w,"crack") end
end
function C.lines(w,now)
    local password=C.password(w.system) local c=w.system.lock.crack
    local sealed=math.floor(C.sealed(w.system)*math.min(1,math.max(0,now-(w.lockCrackOpened or now))/2000))
    local helper=SC.TerminalLockCrew.helper(w)
    local rows={"CRACK.EXE / LOCAL PASSWORD RECOVERY","USER: "..(SC.TerminalFiles.get(w.system.archive).owner or "Operator"),
        password:sub(1,sealed)..string.rep("_",#password-sealed),
        string.format("%.1f hours remaining. Progress is preserved.",math.max(0,c.requiredHours-c.doneHours)),
        w.securityMessage or "Type the complete password to try it early.","[1] Back to password"..(helper and "    [2] Ask "..SC.TerminalLockCrew.name(helper) or "")}
    local skill=SC.ControlUtil.skill(w.player)
    if skill>=4 then table.insert(rows,4,"ELECTRICAL "..skill..": YOU OPTIMISE THE WORDLIST.") end
    return rows
end
function C.input(w,raw)
    local lower=string.lower(raw)
    if lower=="1" or lower=="back" then w.lockPage=nil return true end
    if lower=="2" or lower=="ask for help" then return SC.TerminalLockCrew.hint(w) end
    if lower=="" then return true end
    C.catchUp(w.system,SC.ControlUtil.hours(),(SC.Terminal.normalPowered or SC.Terminal.powered)(w.object))
    local c=w.system.lock.crack local password=C.password(w.system)
    w.crackAnswerVerified=nil
    if string.upper(raw)==password then
        w.crackAnswerVerified=true
        SC.TerminalLocks.finishUnlock(w,c.doneHours<c.requiredHours and "crack_early" or "crack")
    else
        c.requiredHours=math.min(100000,c.requiredHours+1)
        w.securityMessage="Incorrect. Recovery needs one more hour."
        SC.TerminalLocks.record(w,raw,"crack_wrong")
    end
    return true
end
return C
