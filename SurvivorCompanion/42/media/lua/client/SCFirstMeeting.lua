-- SPDX-License-Identifier: MIT
require "SCNamespace"
require "SCGameplayUtil"
local SC=SurvivorCompanion
SC.FirstMeeting=SC.FirstMeeting or {}
local F=SC.FirstMeeting
local state={phase="new",attempts=0,rearms=0,called=false,hadRecruit=false}
local lastAttempt,holdUntil=-math.huge,-math.huge
local restoreBlocked=false
-- After the call-out the visitor stays near the player who heard it. The
-- leash leaves room for scavenging within reach of the usual 12-14 m spot.
local LEASH,WAIT_HOURS,RETURN_HOLD_MS=25,2,60000
local phases={new=true,seeking=true,approaching=true,contact=true,waiting=true,done=true,lapsed=true,legacy=true}
local function met(phase) return phase=="approaching" or phase=="contact" or phase=="waiting" end
local function U() return SC.GameplayUtil end
local function hours()
    local t=type(getGameTime)=="function" and getGameTime() or nil
    return tonumber((U().call(t,"getWorldAgeHours")))
end
local function enabled()
    return not restoreBlocked and SC.Config.get("productionEncounterEnabled")==true and SC.Config.get("firstMeetingEnabled")~=false
end
local function history()
    if SC.BaseLife and SC.BaseLife.active() then return true end
    for _,r in ipairs(SC.Registry.records()) do if r.recruited or r.factionId then return true end end
    return SC.Persistence and SC.Persistence.hasWorldHistory and SC.Persistence.hasWorldHistory() or false
end
function F.pending() return enabled() and (state.phase=="seeking" or state.phase=="approaching") end
function F.wants()
    if not enabled() then return false end
    if state.phase=="new" then
        if history() then state.phase="legacy"
        else state.phase="seeking";state.startedHours=hours() end
    end
    return state.phase=="seeking"
end
function F.ready(current)
    if not F.wants() then return false,"first_meeting_inactive" end
    if state.attempts>=10 then state.phase="lapsed";return false,"first_meeting_lapsed" end
    if current-lastAttempt<60000 then return false,"first_meeting_retry_wait" end
    local t=type(getGameTime)=="function" and getGameTime() or nil
    local time=tonumber((U().call(t,"getTimeOfDay")))
    local h=hours()
    if time and (time<6 or time>=21) and h and state.startedHours and h-state.startedHours<.25 then
        return false,"first_meeting_prefers_daylight"
    end
    return true
end
function F.attempted(current)
    state.attempts=state.attempts+1;lastAttempt=current
end
function F.spawned(actor)
    if state.phase~="seeking" then return end
    local id=SC.Registry.idOf(actor)
    if type(id)~="string" then return end
    state.actorId=id;state.phase="approaching";state.called=false
    state.deadlineHours=(hours() or state.startedHours or 0)+2
end
function F.recruited()
    state.hadRecruit=true;state.phase="done"
end
function F.retired(id)
    if state.actorId~=id or state.phase~="approaching" then return end
    if state.rearms<2 and state.attempts<10 then
        state.rearms=state.rearms+1;state.phase="seeking";state.actorId=nil
        state.called=false;lastAttempt=U().nowMs()
    else state.phase="lapsed" end
end
function F.pulse()
    if not enabled() then return true end
    if state.phase=="new" then F.wants() end
    if state.actorId and met(state.phase) and not SC.Registry.byId(state.actorId) then
        if state.phase=="approaching" then F.retired(state.actorId) else state.phase="done" end
    end
    if met(state.phase) and hours() and state.deadlineHours and hours()>=state.deadlineHours then
        -- A visitor who already called out has met the player; only an
        -- unfinished approach counts as a lapsed guarantee.
        state.phase=state.phase=="waiting" and "done" or "lapsed"
    end
    return true
end
local function toward(actor,player,distance,seen,snapshot)
    -- A point on a twelve-metre circle can sit behind the same opaque wall
    -- forever. Out of sight, route toward the actual player; stop short as
    -- soon as sight is established, using the normal door/window safeguards.
    if not seen and SC.Navigation then
        local square=U().squareOf(player)
        if square then
            return SC.Navigation.request(actor,square,"sneak",{
                action="approach_player_cautiously",neutral=true,snapshot=snapshot})
        end
    end
    local ax,ay,az=U().position(actor);local px,py=U().position(player)
    if not ax or not px or distance<=1 then return nil end
    for _,radius in ipairs({12,13,14}) do
        local sq=U().gridSquare(px+(ax-px)/distance*radius,py+(ay-py)/distance*radius,az)
        if sq and U().isSquareFree(sq) and SC.Navigation then
            return SC.Navigation.request(actor,sq,"sneak",{action="approach_player_cautiously",neutral=true,snapshot=snapshot})
        end
    end
    return nil
end
local function wait(actor,player,snapshot)
    local current=U().nowMs()
    if not U().sameFloor(actor,player) then U().stop(actor);return true,"first_meeting_waiting" end
    local distance=U().distance(actor,player)
    local seen=U().canSee(player,actor)==true
    if distance>LEASH then
        -- Walk back before scavenging again, so a far container cannot pull
        -- the visitor to and fro across the leash.
        holdUntil=current+RETURN_HOLD_MS
        if SC.Encounter and SC.Encounter.cancelScavenge then SC.Encounter.cancelScavenge(actor,"first_meeting_return") end
        local handled,why=toward(actor,player,distance,seen,snapshot)
        if handled~=nil then return handled,why end
        U().stop(actor);return true,"first_meeting_waiting"
    end
    if current<holdUntil then
        if distance>14 then
            local handled,why=toward(actor,player,distance,seen,snapshot)
            if handled~=nil then return handled,why end
        end
        U().stop(actor);return true,"first_meeting_waiting"
    end
    -- Within reach: Encounter may scavenge close by, but must not wander off.
    return nil,"first_meeting_nearby"
end
function F.approach(actor,player,snapshot)
    if not enabled() or SC.Registry.idOf(actor)~=state.actorId or not met(state.phase) then return nil end
    F.pulse()
    if not met(state.phase) or not player then return nil end
    snapshot=type(snapshot)=="table" and snapshot or {}
    if (tonumber(snapshot.threatCount) or 0)>0 or (tonumber(snapshot.immediateCount) or 0)>0
        or (tonumber(snapshot.pressure) or 0)>0 then return nil end
    if state.phase=="waiting" then return wait(actor,player,snapshot) end
    if not U().sameFloor(actor,player) then return nil end
    local distance=U().distance(actor,player)
    local seen=U().canSee(player,actor)==true
    if seen and distance<=20 then
        state.phase="contact"
        if SC.Guidance then SC.Guidance.report("met") end
    end
    if seen and distance<=15 and not state.called and SC.Dialogue then
        local okay=SC.Dialogue.say(actor,"guidance.first_meeting")
        if okay then
            state.called=true;state.phase="waiting"
            state.deadlineHours=(hours() or state.deadlineHours or 0)+WAIT_HOURS
        end
    end
    if distance<=13 and seen then U().stop(actor);return true,"first_meeting_waiting" end
    return toward(actor,player,distance,seen,snapshot)
end
function F.export()
    local copy={schema=1}
    for k,v in pairs(state) do copy[k]=v end
    return copy
end
function F.restore(raw)
    if raw==nil then F.reset();return true end
    restoreBlocked=true
    if type(raw)~="table" or raw.schema~=1 or not phases[raw.phase]
        or type(raw.attempts)~="number" or raw.attempts%1~=0 or raw.attempts<0 or raw.attempts>10
        or type(raw.rearms)~="number" or raw.rearms%1~=0 or raw.rearms<0 or raw.rearms>2
        or type(raw.called)~="boolean" or type(raw.hadRecruit)~="boolean" then
        return false,"invalid first-meeting receipt"
    end
    local copy={phase=raw.phase,attempts=raw.attempts,rearms=raw.rearms,called=raw.called,hadRecruit=raw.hadRecruit}
    if raw.actorId~=nil then
        if type(raw.actorId)~="string" or #raw.actorId>96 or not raw.actorId:match("^sc%-%S+$") then return false,"invalid first-meeting actor" end
        copy.actorId=raw.actorId
    end
    for _,key in ipairs({"startedHours","deadlineHours"}) do
        local value=raw[key]
        if value~=nil then
            if type(value)~="number" or value~=value or value<0 or value==math.huge then return false,"invalid first-meeting clock" end
            copy[key]=value
        end
    end
    if met(copy.phase) and (not copy.actorId or not copy.deadlineHours) then return false,"incomplete first-meeting receipt" end
    state=copy;lastAttempt,holdUntil=-math.huge,-math.huge;restoreBlocked=false
    return true
end
function F.reset()
    state={phase="new",attempts=0,rearms=0,called=false,hadRecruit=false}
    lastAttempt,holdUntil=-math.huge,-math.huge;restoreBlocked=false
end
return F
