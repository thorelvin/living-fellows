-- SPDX-License-Identifier: MIT
-- Foreground care entry points. No event hook, scan or background service.
require "SCEmmaCare"
require "SCEmmaUnderstand"
require "SCEmmaMissed"
local SC=SurvivorCompanion
local UI={} SC.EmmaTerminal=UI
local function call(object,key)
    if not object then return nil end
    local okay,value=pcall(function() return object[key](object) end)
    if okay then return value end
end
local function bucket(player)
    local data=call(player,"getModData")
    return type(data)=="table" and data or nil
end
local function operator(player)
    return call(call(player,"getDescriptor"),"getForename") or call(player,"getForename") or "operator"
end
function UI.remember(player,reply,hours)
    if not reply or not reply.careDetected or not tonumber(hours) then return end
    local data=bucket(player)
    -- One timestamp and a consumed flag per real character; never raw text,
    -- Y/N answers or a computer-wide flag belonging to somebody else.
    if data then data.LF_EmmaCareV1={at=hours,pending=true} end
end
function UI.checkin(player,session,hours)
    local data=bucket(player)
    local saved=data and data.LF_EmmaCareV1
    if type(saved)~="table" or saved.pending~=true then return nil end
    local age=tonumber(hours) and tonumber(saved.at) and hours-saved.at
    if not age then return nil end
    saved.pending=false
    if age<0 or age>72 then return nil end
    return SC.EmmaCare.checkin(session)
end
function UI.active(w) return w and w.careOverlay==true end
function UI.boot(w)
    local kind=w.system and w.system.lock and w.system.lock.kind
    if kind~="emma" and kind~="persona" then return false end
    local session=kind=="persona" and w.personaSession or SC.TerminalBrain.newSession({operator=operator(w.player)})
    session.operator=session.operator or operator(w.player)
    local reply=UI.checkin(w.player,session,w.gameHours)
    if not reply then return false end
    if kind=="emma" then w.careSession,w.careOverlay=session,true end
    w:setFocusMode("chat");w:startReply(reply)
    return true
end
function UI.input(w,raw)
    local lock=w.system and w.system.lock
    local persona=lock and lock.kind=="persona"
    local emma=lock and lock.kind=="emma"
    if w.system and w.system.locked and not persona and not emma then return false end
    local session=persona and w.personaSession or w.session or w.careSession
    local signal=SC.EmmaUnderstand.careSignal(raw)
    if not signal and not SC.EmmaCare.quiet(session) then
        if emma then w.careOverlay=nil end
        return false
    end
    if not session then
        session=SC.TerminalBrain.newSession({operator=operator(w.player)})
        w.careSession=session
    end
    local id=signal
    if not id and not (persona or emma) then
        -- This is a read-only preview: actual conversation context is consumed
        -- exactly once, by Brain.respond, if a live-data request passes through.
        id=SC.EmmaUnderstand.preview(session,raw,w.world)
    end
    local reply=SC.EmmaCare.respond(session,raw,id,persona or emma)
    if not reply then
        if emma and not SC.EmmaCare.quiet(session) then w.careOverlay=nil end
        return false
    end
    w:cancelRequest()
    w.personaEnding=nil
    if emma then w.careOverlay=true end
    UI.remember(w.player,reply,w.gameHours)
    w.readingAnchor,w.scroll=nil,0
    w:setFocusMode("chat")
    w:startReply(reply)
    return true
end
function UI.draw(w,at)
    w.securityHits={}
    local frame=w:readingRange(w:readingFrame(at))
    local y=w:viewTop()
    w:setStencilRect(w.layout.left-2,y,w:transcriptWidth()+4,w:viewBottom()-y+2)
    local okay,reason=pcall(function()
        for index=frame.first,frame.last do
            local row=frame.rows[index] or frame.extra[index-#frame.rows]
            if row and y+w.rowHeight<=w:viewBottom()+2 then w:drawRow(row.text,y,row.kind) end
            y=y+w.rowHeight
        end
    end)
    w:clearStencilRect()
    if not okay then error(reason) end
end
function UI.close(w)
    SC.EmmaCare.reset(w.session)
    SC.EmmaCare.reset(w.personaSession)
    SC.EmmaCare.reset(w.careSession)
end
return UI
