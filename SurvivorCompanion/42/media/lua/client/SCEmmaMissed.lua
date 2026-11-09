-- SPDX-License-Identifier: MIT
-- One bounded write on an explicit misunderstood input; no service or upload.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.EmmaMissed = SC.EmmaMissed or {}
local Log = SC.EmmaMissed
local fileIndex,count,initialized,failed=1,0,false,false
local paths={"LivingFellows/emma_missed_a.txt","LivingFellows/emma_missed_b.txt"}
local misses={fallback=true,fallback_echo=true,did_you_mean=true}
local private={remember=true,callme=true,forget=true,care=true,comfort=true,recall=true,notes=true}
local function enabled()
    return not (SC.UserOptions and SC.UserOptions.get and SC.UserOptions.get("emmaMissedLog")==false)
end
local function clean(raw)
    return tostring(raw or ""):gsub("[^ -~]"," "):gsub("%s+"," "):sub(1,160)
end
local function readCount(path)
    if type(getFileReader)~="function" then return 0 end
    local okay,reader=pcall(getFileReader,path,false)
    if not okay or not reader then return 0 end
    local n=0
    pcall(function() while n<301 and reader:readLine() do n=n+1 end end)
    pcall(function() reader:close() end)
    return n
end
local function write(path,text,append)
    local okay,writer=pcall(getFileWriter,path,true,append)
    if not okay or not writer then return false end
    local written=pcall(function() writer:write(text) end)
    pcall(function() writer:close() end)
    return written
end
function Log.record(session,raw,reply,world)
    local id=reply and reply.intent
    local unsafe=private[id] or reply and reply.private or SC.EmmaCare and SC.EmmaCare.quiet(session)
        or SC.EmmaCare and SC.EmmaCare.assess(raw)~=nil
        or clean(raw):lower():find("^remember%s") or clean(raw):lower():find("^call me%s")
    local previous=session.emmaLogPrevious
    session.emmaLogPrevious=not unsafe and {text=clean(raw),allowed=true} or {allowed=false}
    if unsafe or not enabled() or failed or type(getFileWriter)~="function" then return end
    local text=misses[id] and clean(raw) or nil
    if (id=="did_you_mean_no" or id=="chat_misunderstood") and previous and previous.allowed then text=previous.text end
    if not text then return end
    if not initialized then
        count=readCount(paths[1]);fileIndex=1
        if count>=300 then fileIndex=2;count=readCount(paths[2]) end
        initialized=true
    end
    local append=true
    if count>=300 then fileIndex=3-fileIndex;count=0;append=false end
    local stamp="clock unavailable"
    if world and type(world.clock)=="function" then
        local okay,clock=pcall(world.clock)
        if okay and type(clock)=="table" then
            stamp=string.format("%04d-%02d-%02d %02d:%02d",tonumber(clock.year) or 0,
                (tonumber(clock.month) or 0)+1,tonumber(clock.day) or 1,
                tonumber(clock.hour) or 0,tonumber(clock.minute) or 0)
        end
    end
    if write(paths[fileIndex],stamp.." | "..tostring(id).." | "..text.."\n",append) then count=count+1
    else failed=true end
end
function Log.reset() fileIndex,count,initialized,failed=1,0,false,false end
return Log
