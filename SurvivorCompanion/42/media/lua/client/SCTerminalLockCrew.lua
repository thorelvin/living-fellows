-- SPDX-License-Identifier: MIT
-- Speech only: never interrupts, assigns or moves a companion.
SurvivorCompanion=SurvivorCompanion or {}
local SC=SurvivorCompanion local C={} SC.TerminalLockCrew=C
local lines={
    persona_spiffy={"Customer service outlived the customers.","I think it still wants us to buy something.","That was almost cheerful. Almost."},
    persona_ellis={"We can leave whenever you want.","I might let you do the talking here.","She sounds very sure of us for someone we just met."},
    persona_duty={"Someone has had a very long shift.","I don't think anyone told it to stand down.","Keep your voice down. It sounds official."},
    storyDeath={"I object to that version of events.","I was carrying the torch. That should count for something.","That is a very unfair game.","I would like to appeal to Dennis."},
    storyWin={"We made it. Even the fictional version of me is relieved.","Keep the treasure. I want my boots back.","Dennis owes us fifteen dollars.","A dungeon with a working exit. Novel idea."},
    first={"That machine has kept its secrets longer than most people.","Try the files. People write down what they cannot remember.","I used to complain about passwords. I miss having smaller problems.","Take your time. I will listen for the other problem."},
    failure={"It has had years to practise saying no.","There is usually another way into an old machine.","The computer seems very sure of itself.","I would not take that personally. It does this to everyone."},
    lamp={"That light means something is moving.","The light has picked something up. Keep an ear out.","Whatever that lamp sees, I would rather it stayed outside.","Keep typing. I will watch the room."},
    unlock={"There. One less locked thing in the county.","I hope the files were worth the suspense.","That was a remarkably polite break-in.","It let us in. I will take the small victories."},
    clutch={"You picked a very particular moment to finish that.","Next time, perhaps before the footsteps.","That was close enough for one evening.","You can breathe now. Briefly.","I was about to suggest a crowbar.","Good timing. Alarming timing, but good."},
    hint={"Not that one. Trust me.","I have spent too long with machines like this. Let me help.","There. One less possibility to worry about.","Try it that way. These things are stubborn, not clever."},
    phone={"Is that a telephone? Here?","That is the internal line. It had better be.","It rings. I had forgotten that sound.","Go on. I will listen for the other noise."},
    radio={"Turn that down when it finishes.","Someone kept the transmitter running.","That voice does not know when to stop working.","Write it down. I would rather not hear that twice."},
}
local hintLines={story={"Not choice %1. Kobolds love that one.","I would avoid choice %1. That has Dennis written all over it.","Choice %1 looks unwise. Even for us."},wheel={"That window reads %1. I had one of these.","I make that %1. The old wheel still works.","Read %1 from that window. Carefully.","It is %1. I used to keep the handbook."},
    phone={"I caught the end: %1.","The last three digits were %1.","It finished with %1. Write that down.","I heard %1 at the end."},
    radio={"I caught the end: %1.","The last group was %1.","The final three were %1.","I heard %1 at the end."},
    search={"Try %1. That looks like an index.","I would search for %1 next.","The next file mentions %1. Try that.","Try %1. People leave themselves clues."},
    emma={"Try %1. She seems to respect that.","I would use %1 with her.","Her weak spot sounds like %1.","Try %1. Listen to the way she answers."}}
local function speak(w,actor,moment,kind,value)
    if not SC.Dialogue or not SC.Banter then return false end
    local now=SC.GameplayUtil.nowMs()
    if not SC.Banter.budgetAllows(now) then return false end
    local topic="terminal.lock."..moment..(kind and "."..kind or "")
    if not SC.Dialogue.has(topic) then SC.Dialogue.register(topic,{common=kind and hintLines[kind] or lines[moment]}) end
    local spoken,line=SC.Dialogue.say(actor,topic,nil,value and {value} or {}, {player=w.player})
    if spoken then SC.Banter.spendBudget(now) end
    return spoken==true,line
end
function C.candidates(w,higher,force)
    local result={} local now=SC.GameplayUtil.nowMs()
    local key=higher and "higher" or "all"
    w.lockCrewCache=w.lockCrewCache or {}
    local cached=w.lockCrewCache[key]
    if not force and cached and now>=cached.at and now-cached.at<500 then return cached.actors end
    local records=SC.Registry and type(SC.Registry.records)=="function" and SC.Registry.records() or {}
    for i=1,math.min(#records,256) do
        local r=records[i]
        if r.recruited==true and not r.factionId and SC.Banter and SC.Banter.availableSpeaker(r,w.player,now,12)
            and (not higher or SC.ControlUtil.skill(r.actor)>SC.ControlUtil.skill(w.player)) then
            result[#result+1]=r.actor if #result>=8 then break end
        end
    end
    w.lockCrewCache[key]={at=now,actors=result} return result
end
function C.name(actor)
    local desc=SC.ControlUtil.call(actor,"getDescriptor")
    local name=SC.ControlUtil.call(desc,"getForename")
    if type(name)~="string" then return "companion" end
    local count,cut=0,#name
    for i=1,#name do
        local byte=name:byte(i)
        if byte<128 or byte>=192 then count=count+1 if count>16 then cut=i-1 break end end
    end
    return name:sub(1,cut)
end
function C.storyReact(w,id,moment)
    local records=SC.Registry and SC.Registry.records() or {}
    for i=1,math.min(#records,256) do
        local r=records[i]
        if r.id==id and r.recruited==true and r.actor and SC.Banter
            and SC.ControlUtil.call(r.actor,"isDead")~=true
            and SC.Banter.availableSpeaker(r,w.player,SC.GameplayUtil.nowMs(),12) then
            return speak(w,r.actor,moment)
        end
    end
    return false
end
function C.react(w,moment,chance)
    local lock=w.system and w.system.lock if not lock then return false end
    lock.reactions=lock.reactions or {}
    local persona=moment:sub(1,8)=="persona_"
    if moment=="lamp" then if w.lampReaction then return false end w.lampReaction=true
    else if lock.reactions[moment] then return false end
        if not persona then lock.reactions[moment]=true end
    end
    local pick=SC.TerminalSystem.random(w.system.seed+#moment*71)
    if pick(100)>(chance or 100) then
        if persona then lock.reactions[moment]=true end
        return false
    end
    local actors=C.candidates(w,false,true)
    if #actors==0 then return false end
    local actor=actors[pick(#actors)]
    local spoken,line=speak(w,actor,moment)
    if spoken and persona then
        lock.reactions[moment]=true
        -- The full-screen CRT covers native overhead bubbles. Echo only the
        -- line the nearby companion actually said, once, in the transcript.
        if type(line)=="string" and type(w.print)=="function" then
            w:print(C.name(actor)..", nearby: "..line,"system")
        end
    end
    return spoken
end
function C.helper(w)
    if w.system.lock and not w.system.lock.crewHint then return C.candidates(w,true)[1] end
end
function C.hint(w)
    local lock=w.system.lock local actor=not lock.crewHint and C.candidates(w,true,true)[1]
    if not actor then w.securityMessage="No available companion has higher Electrical training." return true end
    local word,kind,value
    local primary=SC.TerminalLocks.kind(w.system)
    if (not w.lockPage or w.lockPage=="manual") and primary=="wheel" then kind="wheel" value=SC.TerminalLockWheel.answer(w.system)
    elseif not w.lockPage and primary=="search" then kind="search" value=SC.TerminalLockSearch.nextIndex(w.system)
    elseif not w.lockPage and primary=="emma" then kind="emma" value=SC.TerminalLockEmma.temperament(w.system)
    elseif not w.lockPage and primary=="story" then
        value=SC.TerminalLockStory.worst(w.system)
        if not value then w.securityMessage="Choose a scene before asking for advice." return true end
        kind="story"
    elseif not w.lockPage and (primary=="radio" or primary=="phone") then
        local heard=primary=="phone" and lock.heard or primary=="radio" and SC.TerminalLockRadio.heard(w.system)
        if not heard then w.securityMessage="Your companion has not heard this code yet." return true end
        kind=primary value=(primary=="phone" and SC.TerminalLockPhone.code(w.system) or SC.TerminalLockRadio.code(w.system.seed,lock.serial)):sub(-3)
    elseif not w.lockPage then
        for _,v in ipairs(w.system.puzzle.words) do
            if v~=w.system.puzzle.answer and not w.system.puzzle.removed[v] and w.system.puzzle.guessed[v]==nil then word=v break end
        end
        if not word then w.securityMessage="There are no unused wrong candidates to remove." return true end
    end
    if not speak(w,actor,"hint",kind,value) then w.securityMessage="Your companion cannot talk just now." return true end
    lock.crewHint=true
    if kind then lock.crewClue={kind=kind,value=value,stage=kind=="wheel" and lock.wheel.correct+1 or kind=="story" and lock.story.step or 0} end
    if word then w.system.puzzle.removed[word]=true w.securityBoard=nil
    elseif w.lockPage=="crack" then lock.crack.requiredHours=math.max(1,lock.crack.requiredHours-1) end
    w.securityMessage=C.name(actor).." helped. "..(kind and (kind=="story" and "Avoid choice " or kind=="wheel" and "Window: " or kind=="search" and "Index: " or "Try ")..value
        or w.lockPage=="case" and "Hardware reset risk is lower." or w.lockPage=="crack" and "One hour removed." or "One wrong word removed.")
    return true
end
return C
