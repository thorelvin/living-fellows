-- SPDX-License-Identifier: MIT
require "ISUI/ISButton"
require "SCGuidance"
local SC=SurvivorCompanion
SC.UIGuidance=SC.UIGuidance or {}
local UI=SC.UIGuidance
local tracker,closePointer,noticeAt
local function label(key,fallback) return SC.GameplayUtil.text(key,fallback) end
local function action(_,button)
    local G=SC.Guidance
    if button.scGuideAction=="expand" then G.expanded=not G.expanded
    elseif button.scGuideAction=="tips" then G.tipsExpanded=not G.tipsExpanded
    elseif button.scGuideAction=="dismiss" then G.dismiss()
    elseif button.scGuideAction=="skip" then G.skip()
    elseif button.scGuideAction=="close_pointer" then G.clearPointer()
    elseif button.scGuideAction=="guide" and type(openUrl)=="function" then openUrl("https://thorelvin.github.io/living-fellows/") end
end
local function button(panel,x,y,width,height,title,kind)
    local b=ISButton:new(x,y,width,height,title,nil,action)
    b:initialise();b.scGuideAction=kind;panel:addChild(b)
    return b
end
function UI.build(detail,panel,y)
    local G=SC.Guidance;local v=G.view()
    if not v then return y end
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
    return y+h+12
end
function UI.buildTips(detail,panel,y)
    y=detail:addSection(panel,y,"UI_SC_Guide_Tips")
    local h=(detail.metrics or SC.UI.layoutMetrics()).buttonHeight
    button(panel,8,y,math.max(100,panel:getWidth()-20),h,label("UI_SC_Guide_SeenTips","Tips shown on this computer"),"tips")
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
function UI.launcher(launcher)
    local G=SC.Guidance
    local message=G.notice() or G.tracker()
    if not message or not launcher:isVisible() then
        if tracker then tracker:setVisible(false) end
        return
    end
    if not tracker then
        tracker=ISButton:new(0,0,250,30,"",nil,function()
            G.report("panel");SC.UI.open("status")
        end)
        tracker:initialise();tracker:instantiate();tracker:addToUIManager()
        tracker:setAlwaysOnTop(true)
    end
    local screen=getCore():getScreenWidth()
    local width=math.max(100,math.min(300,screen-launcher:getWidth()-16))
    tracker:setWidth(width)
    local x=launcher.dockSide=="left" and launcher:getX()+launcher:getWidth()+4 or launcher:getX()-width-4
    tracker:setX(math.max(0,math.min(screen-width,x)));tracker:setY(launcher:getY())
    if tracker.scText~=message then
        tracker.scText=message
        local manager=getTextManager();local display=message
        while #display>0 and manager:MeasureStringX(UIFont.Small,display)>width-20 do display=display:sub(1,-2) end
        tracker:setTitle(display~=message and display.."..." or display)
        tracker.tooltip=message
    end
    tracker:setVisible(true)
    if G.notice() and not noticeAt then noticeAt=SC.GameplayUtil.nowMs() end
    if noticeAt then
        local age=SC.GameplayUtil.nowMs()-noticeAt
        if age<900 then launcher:drawRectBorder(0,0,launcher:getWidth(),launcher:getHeight(),
            math.sin(age/900*math.pi),1,.83,.3) end
    end
end
function UI.draw(root)
    if tracker then tracker:setVisible(false) end
    local p=SC.Guidance.pointer()
    if not p or p.menu then if closePointer then closePointer:setVisible(false) end;return end
    local c=p.control
    local x=c:getAbsoluteX()-root:getAbsoluteX();local y=c:getAbsoluteY()-root:getAbsoluteY()
    if x<0 or y<0 or x+c:getWidth()>root:getWidth() or y+c:getHeight()>root:getHeight() then return end
    root:drawRectBorder(x-1,y-1,c:getWidth()+2,c:getHeight()+2,.95,1,.83,.3)
    if not closePointer or closePointer.parent~=root then
        closePointer=button(root,0,0,18,18,"x","close_pointer")
    end
    closePointer:setX(math.max(0,x+c:getWidth()-18));closePointer:setY(math.max(0,y-18));closePointer:setVisible(true)
end
function UI.reset()
    if tracker then tracker:removeFromUIManager() end
    if closePointer and closePointer.parent then closePointer.parent:removeChild(closePointer) end
    tracker,closePointer,noticeAt=nil,nil,nil
end
return UI
