-- SPDX-License-Identifier: MIT
require "ISUI/ISButton"
require "SCGuidance"
local SC=SurvivorCompanion
SC.UIGuidance=SC.UIGuidance or {}
local UI=SC.UIGuidance
local tracker,closePointer,noticeAt
local function label(key,fallback) return SC.GameplayUtil.text(key,fallback) end
local function fit(text,width,font)
    local manager=getTextManager()
    if manager:MeasureStringX(font,text)<=width then return text end
    local short=text
    while #short>0 and manager:MeasureStringX(font,short.."...")>width do short=short:sub(1,-2) end
    return short.."..."
end
local function action(_,button)
    local G=SC.Guidance
    if button.scGuideAction=="expand" then G.expanded=not G.expanded
    elseif button.scGuideAction=="tips" then G.tipsExpanded=not G.tipsExpanded
    elseif button.scGuideAction=="dismiss" then G.dismiss()
    elseif button.scGuideAction=="skip" then G.skip()
    elseif button.scGuideAction=="close_pointer" then G.dismissPointer()
    elseif button.scGuideAction=="guide" and type(openUrl)=="function" then openUrl("https://thorelvin.github.io/living-fellows/") end
end
local function button(panel,x,y,width,height,title,kind)
    local b=ISButton:new(x,y,width,height,title,nil,action)
    b:initialise();b.scGuideAction=kind;panel:addChild(b)
    b:setTitle(fit(title,width-12,b.font or UIFont.Small));b.tooltip=title
    return b
end
function UI.build(detail,panel,y)
    local G=SC.Guidance;local v=G.view()
    if not v then return y end
    local parent,top=panel,y
    local card=ISPanel:new(6,y,math.max(100,panel:getWidth()-12),100)
    card:initialise();card.backgroundColor={r=.11,g=.13,b=.10,a=.5}
    card.borderColor={r=.5,g=.5,b=.32,a=.5};parent:addChild(card)
    panel,y=card,4
    if UI.lastStep~=v.id then UI.lastStep=v.id;card.scSlideAt=SC.GameplayUtil.nowMs() end
    card.prerender=function(self)
        ISPanel.prerender(self)
        if self.scSlideAt then
            local fraction=math.min(1,(SC.GameplayUtil.nowMs()-self.scSlideAt)/180)
            self:setY(top+6*(1-fraction))
        end
        -- Drawn on screen: only now does a nudge count as seen.
        if v.kind=="nudge" then G.shown(v.id) end
    end
    local metrics=detail.metrics or SC.UI.layoutMetrics()
    y=detail:addSection(panel,y,"UI_SC_Guide_FirstSteps")
    y=detail:addInformationLine(panel,y,"UI_SC_Info_Message",v.title)
    y=detail:addInformationLine(panel,y,"UI_SC_Info_Message",v.text)
    if G.expanded then
        local done={};for _,item in ipairs(G.list()) do done[item.id]=item.done end
        for _,id in ipairs(G.steps) do
            y=detail:addInformationLine(panel,y,"UI_SC_Info_Message",
                (done[id] and label("UI_SC_Guide_Done","Done: ") or "- ")..G.text(id,"title"))
        end
    end
    local w=math.max(60,(panel:getWidth()-24)/2);local h=metrics.buttonHeight
    button(panel,8,y,w,h,label("UI_SC_Guide_Checklist","Checklist"),"expand")
    button(panel,12+w,y,w,h,label("UI_SC_Guide_Dismiss","Dismiss"),"dismiss")
    y=y+h+4
    button(panel,8,y,math.max(100,panel:getWidth()-20),h,
        label("UI_SC_Guide_Veteran","I've done this before - turn tips off"),"skip")
    card:setHeight(y+h+6)
    return top+card:getHeight()+12
end
function UI.buildTips(detail,panel,y)
    y=detail:addSection(panel,y,"UI_SC_Guide_Tips")
    local h=(detail.metrics or SC.UI.layoutMetrics()).buttonHeight
    button(panel,8,y,math.max(100,panel:getWidth()-20),h,label("UI_SC_Guide_SeenTips","Tips you've seen"),"tips")
    y=y+h+4
    for _,tip in ipairs(SC.Guidance.tipsExpanded and SC.Guidance.list() or {}) do
        y=detail:addInformationLine(panel,y,"UI_SC_Info_Message",tip.title..": "..tip.text)
    end
    y=detail:addInformationLine(panel,y,"UI_SC_Info_Message","thorelvin.github.io/living-fellows")
    if type(openUrl)=="function" then
        button(panel,8,y,math.max(100,panel:getWidth()-20),h,label("UI_SC_Guide_FieldGuide","Open Field Guide"),"guide")
        y=y+h+4
    end
    return y
end
-- Word-wrapped lines, at most `limit`, the last one cut with "..." if needed.
local function wrap(text,width,font,limit)
    local manager=getTextManager()
    local lines,line,cut={}, "", false
    for word in tostring(text or ""):gmatch("%S+") do
        local candidate=line=="" and word or line.." "..word
        if line=="" or manager:MeasureStringX(font,candidate)<=width then line=candidate
        elseif #lines+1>=limit then cut=true;break
        else lines[#lines+1]=line;line=word end
    end
    if line~="" then lines[#lines+1]=cut and line.." ..." or line end
    for i,value in ipairs(lines) do lines[i]=fit(value,width,font) end
    return lines
end
local function trackerPanel()
    local panel=ISPanel:new(0,0,250,30)
    panel:initialise();panel:instantiate();panel:addToUIManager();panel:setAlwaysOnTop(true)
    panel.backgroundColor={r=.08,g=.09,b=.07,a=.82};panel.borderColor={r=.52,g=.56,b=.43,a=.9}
    panel.onMouseUp=function(self)
        local item=self.scItem
        SC.Guidance.report("panel")
        SC.UI.open(item and item.tab or "status")
        return true
    end
    panel.render=function(self)
        local lineHeight=getTextManager():getFontHeight(UIFont.Small)
        for i,line in ipairs(self.scLines or {}) do
            if i==1 then self:drawText(line,8,4,.94,.91,.69,1,UIFont.Small)
            else self:drawText(line,8,4+(i-1)*lineHeight,.86,.86,.82,1,UIFont.Small) end
        end
    end
    return panel
end
function UI.launcher(launcher)
    if SC.UIAttention and SC.UIAttention.bannerVisible() then
        if tracker then tracker:setVisible(false) end
        return
    end
    local G=SC.Guidance
    local notice=G.notice()
    local item=notice and {id="first_notice",title=notice} or G.tracker()
    if not item or not launcher:isVisible() then
        if tracker then tracker:setVisible(false) end
        return
    end
    if not tracker then tracker=trackerPanel() end
    local screen=getCore():getScreenWidth()
    local width=math.max(100,math.min(300,screen-launcher:getWidth()-16))
    local key=tostring(item.id)..":"..tostring(item.title)..":"..tostring(item.text)..":"..width
    if tracker.scKey~=key then
        tracker.scKey,tracker.scItem=key,item
        local lines={fit(item.title,width-16,UIFont.Small)}
        if item.kind=="nudge" then
            for _,line in ipairs(wrap(item.text,width-16,UIFont.Small,3)) do lines[#lines+1]=line end
        end
        tracker.scLines=lines
        tracker:setWidth(width)
        tracker:setHeight(8+#lines*getTextManager():getFontHeight(UIFont.Small))
    end
    local x=launcher.dockSide=="left" and launcher:getX()+launcher:getWidth()+4 or launcher:getX()-width-4
    tracker:setX(math.max(0,math.min(screen-width,x)));tracker:setY(launcher:getY())
    tracker:setVisible(true)
    if item.kind=="nudge" then G.shown(item.id) end
    if G.notice() and not noticeAt then noticeAt=SC.GameplayUtil.nowMs() end
    if noticeAt then
        local age=SC.GameplayUtil.nowMs()-noticeAt
        -- The rounded launcher owns its border and attention treatment.
    end
end
function UI.draw(root)
    if tracker then tracker:setVisible(false) end
    for _,b in ipairs(root.tabButtons or {}) do
        if SC.Guidance.dot(b.scTab) then root:drawRect(b:getX()+b:getWidth()-10,b:getY()+4,5,5,.9,1,.83,.3) end
    end
    local p=SC.Guidance.pointer()
    if not p or p.menu then if closePointer then closePointer:setVisible(false) end;return end
    local c=p.control
    local x=c:getAbsoluteX()-root:getAbsoluteX();local y=c:getAbsoluteY()-root:getAbsoluteY()
    if x<0 or y<0 or x+c:getWidth()>root:getWidth() or y+c:getHeight()>root:getHeight() then
        if closePointer then closePointer:setVisible(false) end;return
    end
    root:drawRectBorder(x-1,y-1,c:getWidth()+2,c:getHeight()+2,.95,1,.83,.3)
    if not closePointer or closePointer.parent~=root then
        closePointer=button(root,0,0,18,18,"x","close_pointer")
    end
    closePointer:setX(math.max(0,x+c:getWidth()-18));closePointer:setY(math.max(0,y-18));closePointer:setVisible(true)
end
function UI.reset()
    if tracker then tracker:removeFromUIManager() end
    if closePointer and closePointer.parent then closePointer.parent:removeChild(closePointer) end
    tracker,closePointer,noticeAt,UI.lastStep=nil,nil,nil,nil
end
return UI
