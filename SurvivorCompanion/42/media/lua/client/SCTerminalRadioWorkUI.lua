-- SPDX-License-Identifier: MIT
-- Visible-only survivor-watch instruments. Cosmetic samples never tune the
-- handset, advance work, invent a reception, or run a background callback.
local SC = SurvivorCompanion
SC.TerminalRadioWorkUI = SC.TerminalRadioWorkUI or {}
local P = SC.TerminalRadioWorkUI
local BINS, HISTORY = 32, 12
local stages = { "SWEEP", "FILTER", "LISTEN", "LOG" }
local activity = {
    "Sweeping the channel bank...", "Narrowing the receive filter...",
    "Listening for a human voice...", "Logging this pass. Search continues.",
}
local function clamp(n, a, b) return math.max(a, math.min(b, n)) end
local function append(s, message)
    s.log[#s.log+1] = { text = message, at = s.time }
    if #s.log > 8 then table.remove(s.log, 1) end
end
function P.frame(w, now, view)
    local s = w.radioWorkDisplay
    local key = tostring(view.jobId or s and s.jobId or "") .. ":" .. tostring(view.operator or "")
    if not s or s.key ~= key then
        s = { key = key, time = 0, lastAt = now, sampled = -1000, log = {}, history = {}, bins = {} }
        w.radioWorkDisplay = s
        s.jobId = view.jobId
        append(s, view.operator and (view.operator .. " / operator signed in") or "Receiver standing by.")
    end
    local active = view.status == "working"
    local dt = clamp(now-s.lastAt, 0, 250)
    s.lastAt = now
    if active then s.time = s.time+dt end
    local stage = math.floor(s.time/4000)%4+1
    if s.status ~= view.status then
        s.status = view.status
        append(s, active and "Search resumed. Monitoring for survivors."
            or view.status == "found" and "Human contact confirmed. Awaiting your decision."
            or view.status == "quiet" and "Shift complete. No survivor contact this time."
            or view.status == "approaching" and "Operator approaching the radio desk."
            or (view.status == "cancelling" or view.status == "finishing") and "Signing off. Releasing the keyboard."
            or view.jobId and "Search paused. Work already done is saved." or "No active search shift.")
    end
    if active and stage ~= s.stage then append(s, activity[stage]) end
    s.stage = stage
    if active and s.time-s.sampled >= 160 then
        s.sampled = s.time
        local cursor = (s.time/600)%BINS
        local samples = {}
        for i=1,BINS do
            local noise = .07+.11*math.abs(math.sin(i*2.17+s.time/410))
            local carrier = math.max(0,1-math.abs(i-10)/2.8)*(.3+.16*math.sin(s.time/950))
                +math.max(0,1-math.abs(i-24)/1.8)*.22
            samples[i] = clamp(noise+carrier+math.max(0,1-math.abs(i-cursor)/2)*.3, 0, 1)
        end
        s.bins = samples
        table.insert(s.history, 1, samples)
        if #s.history > HISTORY then table.remove(s.history) end
    end
    return s
end

function P.draw(w, now, view, boxes, bottom)
    local s = P.frame(w, now, view)
    local left, top, width = w.layout.left, w:viewTop(), w.layout.right-w.layout.left
    local row, cw, ink, title = w.rowHeight, w.charWidth, w.colors.emma, w.colors.title
    local function text(value, x, y, maxWidth, color)
        if y+row > bottom then return end
        color = color or ink
        value = tostring(value)
        local limit = math.max(1, math.floor(maxWidth/cw)-1)
        if #value > limit then value = value:sub(1,math.max(1,limit-3)).."..." end
        w:drawText(value,x,y,color[2],color[3],color[4],1,w.font)
    end
    local function rect(x,y,ww,hh,a,color)
        if ww > 0 and hh > 0 then w:drawRect(x,y,ww,hh,a,color[2],color[3],color[4]) end
    end
    local live = view.status == "working"
    local status = live and stages[s.stage] or (view.status or "idle"):upper()
    local statusWidth = (#status+4)*cw
    text("SURVIVOR WATCH",left,top,width-statusWidth,title)
    text((live and math.floor(now/500)%2 == 0 and "* " or "  ")..status,
        left+width-statusWidth,top,statusWidth,title)
    text("OPERATOR / "..(view.operator or "Awaiting assignment"),left,top+row,width)
    local fraction = clamp((view.progress or 0)/math.max(.01,view.goal or 4),0,1)
    local y = top+row*2+2
    local meterWidth = math.max(40,width*.48)
    local meterHeight = math.max(6,math.floor(row*.44))
    w:drawRectBorder(left,y+3,meterWidth,meterHeight,.5,title[2],title[3],title[4])
    rect(left+2,y+5,(meterWidth-4)*fraction,meterHeight-4,.7,ink)
    if live and fraction < 1 then
        rect(left+2+(meterWidth-8)*fraction,y+5,4,meterHeight-4,.5+.25*math.sin(now/200),title)
    end
    text(string.format("%d%% / %.1fh remaining",math.floor(fraction*100),
        math.max(0,(view.goal or 4)-(view.progress or 0))),left+meterWidth+cw,y-3,width-meterWidth-cw,title)
    y = y+math.max(row*.7,meterHeight+8)
    local notice = w.radioNoticeAt and now>=w.radioNoticeAt and now-w.radioNoticeAt<9000 and w.radioNotice
    local footer = view.blocker and SC.RadioWork.message(view.blocker) or notice
    if not footer and view.status == "finishing" then
        footer = SC.RadioWork.message("radio_work_finishing")
    elseif not footer and w.radioPage == "operators" then
        footer = #(w.radioWorkCrew or {}) == 0 and "No available base-duty companions. Assign base duty first."
            or "Choose an operator. Needs and danger take priority."
    elseif not footer then
        footer = view.contact and ("CONTACT / "..tostring(view.contact.name or "Unknown survivor").." / "
            ..(view.contact.status == "found" and "Awaiting invitation" or view.contact.status == "invited"
                and "Directions sent" or "Checking arrival"))
            or view.jobId and "Progress pauses for needs, danger or lost power."
            or "4 game hours per shift / 35% chance of a survivor contact."
    end
    local bodyBottom = bottom-row-5
    local bodyHeight = math.max(0,bodyBottom-y)
    local wide = width/cw >= 65 and bodyHeight >= row*3
    local gap = cw*1.5
    local plotWidth = wide and math.floor(width*.59) or width
    local plotBottom = wide and bodyBottom or bodyBottom-row
    if bodyHeight >= row then
        text("CHANNEL BANK / "..string.format("%03d",math.floor(s.time/550)%128+1),left,y,plotWidth-90,title)
        local peak = .05
        for _,level in ipairs(s.bins) do peak=math.max(peak,level) end
        for segment=1,12 do
            rect(left+plotWidth-80+(segment-1)*6,y+row*.32,4,row*.3,
                live and segment/12<=peak and .85 or .12,segment>9 and title or ink)
        end
    end
    local graphY, graphH = y+row, bodyHeight>=row*2 and math.max(0,(plotBottom-y-row)*.42) or 0
    local waterY = graphY+graphH+2
    local waterH = graphH>0 and math.max(0,plotBottom-waterY) or 0
    if graphH >= 10 then
        for tick=0,4 do rect(left+tick*(plotWidth-1)/4,graphY,1,graphH,.12,title) end
        rect(left,graphY+graphH*.5,plotWidth,1,.14,title)
        for i=1,BINS do
            local value = s.bins[i] or .04
            local h = value*(graphH-2)
            rect(left+(i-1)*plotWidth/BINS,graphY+graphH-h,math.max(1,plotWidth/BINS-1),2,.9,ink)
        end
        if live then
            local x = left+(s.time/600%BINS)/BINS*(plotWidth-2)
            rect(x,graphY,2,graphH,.5,title)
        end
        rect(left,graphY+graphH,plotWidth,1,.45,title)
    end
    if waterH >= 8 then
        local rh, bw = waterH/HISTORY, plotWidth/BINS
        for age,sample in ipairs(s.history) do
            for bin=1,BINS do
                local level = sample[bin]
                rect(left+(bin-1)*bw,waterY+(age-1)*rh,bw-1,math.max(1,rh-1),
                    .07+level*.7, level>.5 and title or ink)
            end
        end
        rect(left,waterY+waterH,plotWidth,1,.3,title)
    end
    local logX, logY, logWidth = wide and left+plotWidth+gap or left, wide and y or bodyBottom-row,
        wide and width-plotWidth-gap or width
    if wide then
        rect(logX-gap/2,y,1,bodyHeight,.25,title)
        text("OPERATOR LOG",logX,logY,logWidth,title);logY=logY+row
    end
    local visible = bodyHeight>=row*2 and math.max(0,math.floor((bodyBottom-logY)/row)) or 0
    local logLines = {}
    for index=math.max(1,#s.log-visible+1),#s.log do
        local entry = s.log[index]
        local value = entry.text
        if index == #s.log and live then
            local n = math.floor((s.time-entry.at)/28)
            value = value:sub(1,math.max(0,n))..(math.floor(now/450)%2==0 and "_" or "")
        end
        for _,line in ipairs(SC.Terminal.wrap("> "..value,math.max(4,math.floor(logWidth/cw)-1))) do
            logLines[#logLines+1] = { text=line, color=index==#s.log and title or ink }
        end
    end
    for index=math.max(1,#logLines-visible+1),#logLines do
        text(logLines[index].text,logX,logY,logWidth,logLines[index].color)
        logY=logY+row
    end
    text(footer,left,bottom-row,width,view.blocker and w.colors.alert or ink)
    for _,box in ipairs(boxes) do
        w:drawRectBorder(box.x,box.y,box.width,box.height,.6,title[2],title[3],title[4])
        if w.focusMode == "menu" and w.menuSelection == box.index then
            rect(box.x,box.y,box.width,box.height,.12,title)
        end
        local label = "["..box.index.."] "..box.option.label
        local limit = math.max(4,math.floor(box.width/cw)-1)
        if #label > limit then label=label:sub(1,limit-3).."..." end
        w:drawText(label,box.x+2,box.y+1,title[2],title[3],title[4],1,w.font)
    end
end
return P
