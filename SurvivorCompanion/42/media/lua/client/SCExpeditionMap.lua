-- SPDX-License-Identifier: MIT
require "ISUI/Maps/ISWorldMap"
require "ISUI/ISButton"
require "SCExpeditionTargets"
require "SCContextMenu"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ExpeditionMap = SC.ExpeditionMap or {}
local M = SC.ExpeditionMap
local serial = 0

local function tr(key, ...)
    return SC.UI and SC.UI.text(key, ...) or getText(key, ...)
end

function M.reason(reason)
    local key = "UI_SC_Map_Reason_" .. tostring(reason)
    local translated = tr(key)
    if translated ~= key then return translated end
    return SC.UI and SC.UI.baseFailureReason(reason) or tostring(reason or "")
end

local function usable(session)
    return session and session.owner and (not session.valid or session.valid())
end

function M.begin(owner, draft, context, accept, resume, valid)
    if not ISWorldMap or not ISWorldMap.IsAllowed() then return false, "map_disabled" end
    if M.session then return false, "map_picker_busy" end
    serial = serial + 1
    local ctx = context()
    local actor = ctx and ctx.actor
    if not actor then return false, "leader_unavailable" end
    local at = draft.mapTarget and draft.mapTarget.anchor
        or {x=actor:getX(),y=actor:getY()}
    M.session = { token=serial,owner=owner,draft=draft,context=context,
        accept=accept,resume=resume,valid=valid,kind=draft.kind }
    owner:setVisible(false)
    local previous=ISWorldMap_instance
    local zoom=previous and previous.mapAPI and previous.mapAPI:getZoomF() or nil
    ISWorldMap.ShowWorldMap(0,at.x,at.y,zoom)
    local map = ISWorldMap_instance
    if not map then M.closed() return false,"map_disabled" end
    M.session.map = map
    if SCBridge and SCBridge.loadedWorldMap then
        SC.ExpeditionTargets.mapData = SCBridge.loadedWorldMap(map.javaObject)
    end
    if draft.mapTarget and draft.mapTarget.kind==draft.kind then
        M.session.highlight = SC.ExpeditionTargets.validate(draft.mapTarget,context())
        if draft.kind=="wood" and draft.mapTarget.version==2 then
            M.session.bounds=draft.mapTarget.workBounds
            M.session.pendingPreview=M.session.highlight~=nil
        elseif draft.kind=="wood" then
            M.session.highlight=nil
        end
    end
    return true
end

function M.closed(map)
    local session = M.session
    if not session or map and session.map and session.map ~= map then return end
    M.session = nil
    for _,key in ipairs({"backButton","useButton","redrawButton"}) do
        if session[key] and session.map then session.map:removeChild(session[key]) end
    end
    if not usable(session) then return end
    session.owner:setVisible(true)
    session.owner:bringToTop()
    if session.resume then session.resume() end
    if session.chosen and usable(session) then session.accept(session.chosen) end
end

local function choose(session, target)
    if M.session ~= session or not usable(session) or session.draft.kind ~= session.kind then return end
    local fresh, reason = SC.ExpeditionTargets.validate(target,session.context())
    if not fresh then session.error=reason return end
    if fresh.version==2 and session.context().travelMode=="drive" and not session.workStop then return end
    session.chosen=SC.ExpeditionTargets.copy(fresh)
    session.map:close()
end

function M.redraw(map)
    local s=M.session
    if not s or s.map~=map then return end
    s.firstCorner,s.bounds,s.highlight,s.error,s.workStop,s.proposedStop=nil,nil,nil,nil,nil,nil
    s.routeChecked,s.routeError,s.pendingPreview=nil,nil,nil
end

function M.click(map,x,y)
    local s=M.session
    if not s or s.map~=map or s.kind~="wood" or not usable(s) then return false end
    if s.bounds then return true end
    local api=map.mapAPI
    local at={x=math.floor(api:uiToWorldX(x,y)),y=math.floor(api:uiToWorldY(x,y)),z=0}
    if not s.firstCorner then s.firstCorner=at s.error=nil return true end
    local a=s.firstCorner
    s.bounds={x1=math.min(a.x,at.x),y1=math.min(a.y,at.y),x2=math.max(a.x,at.x),y2=math.max(a.y,at.y),z=0}
    s.highlight,s.error=SC.ExpeditionTargets.resolveWoodArea(s.bounds,s.context())
    s.pendingPreview=s.highlight~=nil
    return true
end

-- Owned by the picker's visible Back button update, never the render path or
-- an idle world service. Native route planning gets one attempt per 100 ms.
function M.update(map)
    local s=M.session
    if not s or s.map~=map or s.kind~="wood" or not usable(s) then return end
    local now=SC.GameplayUtil.nowMs()
    if now<(s.nextCheckAt or 0) then return end
    s.nextCheckAt=now+100
    if s.pendingPreview and s.highlight then
        local ctx=s.context()
        if ctx.travelMode=="drive" then
            local service=SC.ExpeditionPrototype
            local trip,why,stop
            if service and service.previewWoodAreaStop then
                trip,why,stop=service.previewWoodAreaStop(ctx.records,s.highlight,s.draft)
            else why="driving_unavailable" end
            s.workStop=trip and trip.exit or nil
            s.proposedStop=stop
            s.routeError=trip and nil or why
            s.routeChecked=trip~=nil or why~="wood_area_route_pending"
            if s.routeChecked then s.pendingPreview=nil end
        else s.routeChecked=true s.pendingPreview=nil end
    end
    if s.useButton then
        s.useButton:setEnable(s.highlight~=nil and (s.context().travelMode~="drive" or s.workStop~=nil))
    end
end

function M.fillContext(map, context, at)
    -- Stock may reuse a still-open menu at the same point. Replace only our
    -- options, retaining other mods' and vanilla entries.
    SC.ContextMenu.removeOwned(context,function(option)
        return option.scLFContext and (option.scExpeditionMapAction or option.scTaxiMapAction)
    end)
    if SCBridge and SCBridge.loadedWorldMap and map.javaObject then
        SC.ExpeditionTargets.mapData=SCBridge.loadedWorldMap(map.javaObject) or SC.ExpeditionTargets.mapData
    end
    local session = M.session
    if session and session.map == map then
        if not usable(session) then M.closed(map) return false end
        if session.kind=="wood" then
            local option=SC.ContextMenu.action(context,"map.redraw",tr("UI_SC_Map_WoodRedraw"),nil,function()
                if M.session==session and usable(session) then M.redraw(map) end
            end)
            option.scExpeditionMapAction=true
            return true
        end
        local target,reason = SC.ExpeditionTargets.resolveAtPoint(session.kind,at,session.context())
        session.highlight,session.error=target,reason
        if target then
            local option=SC.ContextMenu.action(context,"map.select",tr("UI_SC_Map_Select",target.label),nil,function() choose(session,target) end)
            option.scExpeditionMapAction=true
        else
            local option=SC.ContextMenu.action(context,"map.unavailable",M.reason(reason),nil,nil)
            option.notAvailable=true
            option.scExpeditionMapAction=true
        end
        return true
    end
    if not SC.UI or not SC.UIExpeditions or not SC.ExpeditionPrototype
        or SC.ExpeditionPrototype.current() then return false end
    local root=SC.UI.instance
    local row=root and root.selectedRow
    local actor=row and row.actor or getSpecificPlayer(0)
    local count=0
    local planning
    for _,kind in ipairs({"scout","search","fish","wood","fuel"}) do
        local ctx=SC.ExpeditionTargets.context(actor,"drive")
        local target
        if kind=="wood" then
            local x,y=math.floor(at.x),math.floor(at.y)
            target=SC.ExpeditionTargets.resolveWoodArea({x1=x,y1=y,x2=x,y2=y,z=0},ctx)
        else target=SC.ExpeditionTargets.resolveAtPoint(kind,at,ctx) end
        if target then
            local chosen=SC.ExpeditionTargets.copy(target)
            if not planning then
                planning=SC.ContextMenu.group(context,"map.plan",tr("UI_SC_Context_PlanExpedition"))
                for _,option in ipairs(context.options or {}) do
                    if option.scMenuKey=="map.plan" then option.scExpeditionMapAction=true break end
                end
            end
            local option=SC.ContextMenu.action(planning,"map.plan:"..kind,tr("UI_SC_Map_Plan_"..kind,target.label),nil,function()
                map:close()
                local window=SC.UI.open("expeditions")
                if window and window.detail then
                    if chosen.kind=="wood" then
                        SC.UIExpeditions.applyMapTarget(window.detail,chosen,false)
                        SC.UIExpeditions.onButton(window.detail,{scExpeditionAction="choose_map"})
                        if M.session and M.session.kind=="wood" then
                            M.redraw(M.session.map)
                            M.session.firstCorner=chosen.anchor
                            M.session.map.mapAPI:centerOn(chosen.anchor.x,chosen.anchor.y)
                        end
                    else SC.UIExpeditions.applyMapTarget(window.detail,chosen,false) end
                end
            end)
            option.scExpeditionMapAction=true
            count=count+1
        end
    end
    return count>0
end

local function line(map,x1,y1,x2,y2,a,r,g,b)
    if type(map.drawLine2)=="function" then map:drawLine2(x1,y1,x2,y2,a,r,g,b) end
end

function M.reset()
    local session=M.session
    M.session=nil
    for _,key in ipairs({"backButton","useButton","redrawButton"}) do
        if session and session[key] and session.map then session.map:removeChild(session[key]) end
    end
end

function M.render(map)
    local session=M.session
    if not session or session.map~=map then return end
    if not usable(session) then M.closed(map) return end
    local font=UIFont.Medium or UIFont.Small
    local height=getTextManager():getFontHeight(font)
    local right=map:getWidth()-16
    if map.symbolsUI and map.symbolsUI:isVisible() then right=map.symbolsUI:getX()-12 end
    local headerX=16
    if map.keyUI and map.keyUI:isVisible() then headerX=map.keyUI:getX()+map.keyUI:getWidth()+12 end
    if right-headerX<240 then headerX=16 end
    local width=math.max(160,math.min(650,right-32))
    local function panelText(text,y,x,panelWidth)
        x,panelWidth=x or 16,panelWidth or width
        local lines={}
        for paragraph in (text.."\n"):gmatch("(.-)\n") do
            local wrapped=SC.UI and SC.UI.wrapText(font,paragraph,panelWidth-24) or {paragraph}
            for _,value in ipairs(wrapped) do lines[#lines+1]=value end
        end
        map:drawRect(x,y,panelWidth,#lines*(height+3)+16,0.9,0.025,0.035,0.03)
        for _,value in ipairs(lines) do
            map:drawText(value,x+12,y+8,0.94,0.94,0.86,1,font)
            y=y+height+3
        end
    end
    local ctx=session.context()
    panelText(tr(session.kind=="wood" and "UI_SC_Map_WoodInstructions" or "UI_SC_Map_Instructions",
        tr("UI_SC_Map_Kind_"..session.kind),SC.ExpeditionTargets.limit(ctx.travelMode)),
        16,headerX,math.max(240,right-headerX))
    if not session.backButton then
        local button=ISButton:new(math.max(16,map:getWidth()-156),math.max(16,map:getHeight()-102),
            140,math.max(32,height+14),tr(session.kind=="wood" and "UI_SC_Map_WoodCancel" or "UI_SC_Map_Back"),map,function(target) target:close() end)
        button:initialise()
        local update=button.update
        button.update=function(self) if update then update(self) end M.update(map) end
        map:addChild(button)
        session.backButton=button
    end
    session.backButton:setX(math.max(16,map:getWidth()-156))
    session.backButton:setY(math.max(16,map:getHeight()-102))
    local api=map.mapAPI
    if session.kind=="wood" and not session.useButton then
        local use=ISButton:new(16,16,140,math.max(32,height+14),tr("UI_SC_Map_WoodUse"),map,
            function() if M.session==session and session.highlight then choose(session,session.highlight) end end)
        use:initialise() use:setEnable(false) map:addChild(use) session.useButton=use
        local redraw=ISButton:new(16,16,140,math.max(32,height+14),tr("UI_SC_Map_WoodRedraw"),map,function() M.redraw(map) end)
        redraw:initialise() map:addChild(redraw) session.redrawButton=redraw
    end
    if session.useButton then
        session.useButton:setX(math.max(16,map:getWidth()-464)) session.useButton:setY(session.backButton:getY())
        session.redrawButton:setX(math.max(16,map:getWidth()-310)) session.redrawButton:setY(session.backButton:getY())
    end
    local actor=ctx.actor
    if actor and api then
        local radius=SC.ExpeditionTargets.limit(ctx.travelMode)
        local ax,ay=actor:getX(),actor:getY()
        local previous
        for index=0,64 do
            local angle=index*math.pi*2/64
            local x,y=ax+math.cos(angle)*radius,ay+math.sin(angle)*radius
            local px,py=api:worldToUIX(x,y),api:worldToUIY(x,y)
            if previous then line(map,previous.x,previous.y,px,py,0.65,0.88,0.77,0.35) end
            previous={x=px,y=py}
        end
    end
    local raw=session.bounds
    if not raw and session.firstCorner and api then
        local a=session.firstCorner
        local mx,my=map:getMouseX(),map:getMouseY()
        local x,y=math.floor(api:uiToWorldX(mx,my)),math.floor(api:uiToWorldY(mx,my))
        raw={x1=math.min(a.x,x),x2=math.max(a.x,x),y1=math.min(a.y,y),y2=math.max(a.y,y),z=0}
    end
    if raw and api then
        local valid=SC.ExpeditionTargets.validWoodBounds(raw) and not session.error and not session.routeError
        local points={{raw.x1,raw.y1},{raw.x2+1,raw.y1},{raw.x2+1,raw.y2+1},{raw.x1,raw.y2+1},{raw.x1,raw.y1}}
        for i=2,#points do local a,b=points[i-1],points[i]
            line(map,api:worldToUIX(a[1],a[2]),api:worldToUIY(a[1],a[2]),
                api:worldToUIX(b[1],b[2]),api:worldToUIY(b[1],b[2]),1,valid and 0.4 or 1,valid and 0.95 or 0.3,0.3)
        end
    end
    if (session.workStop or session.proposedStop) and api then
        local stop=session.workStop or session.proposedStop
        local previous
        for i=0,64 do
            local angle=i*math.pi*2/64
            local x,y=api:worldToUIX(stop.x+math.cos(angle)*64,stop.y+math.sin(angle)*64),
                api:worldToUIY(stop.x+math.cos(angle)*64,stop.y+math.sin(angle)*64)
            if previous then line(map,previous.x,previous.y,x,y,0.9,0.3,0.8,1) end
            previous={x=x,y=y}
        end
        map:drawRect(api:worldToUIX(stop.x,stop.y)-5,api:worldToUIY(stop.x,stop.y)-5,10,10,1,0.3,0.8,1)
    end
    if session.kind=="wood" then
        local message=tr(session.firstCorner and "UI_SC_Map_WoodSecondCorner" or "UI_SC_Map_WoodFirstCorner")
        if raw then message=tr("UI_SC_Map_WoodDimensions",raw.x2-raw.x1+1,raw.y2-raw.y1+1) end
        if session.highlight then message=message.." | "..tr("UI_SC_Map_WoodDistance",session.highlight.distance) end
        local reason=session.error or session.routeError
        if reason then message=message.."\n"..M.reason(reason)
        elseif session.pendingPreview and ctx.travelMode=="drive" then message=message.."\n"..M.reason("wood_area_route_pending")
        elseif session.highlight then message=message.."\n"..tr(ctx.travelMode=="drive" and "UI_SC_Map_WoodCarHint" or "UI_SC_Map_WoodTreesHint") end
        panelText(message,math.max(height*5+50,map:getHeight()-height*6-140))
        return
    end
    local target=session.highlight
    if target and api then
        local bounds=target.workBounds or target.place and target.place.bounds
        if bounds then
            local x1,y1=bounds.x1 or bounds.x,bounds.y1 or bounds.y
            local corners={{x1,y1},{bounds.x2,y1},{bounds.x2,bounds.y2},{x1,bounds.y2},{x1,y1}}
            for index=2,#corners do
                local a,b=corners[index-1],corners[index]
                line(map,api:worldToUIX(a[1],a[2]),api:worldToUIY(a[1],a[2]),
                    api:worldToUIX(b[1],b[2]),api:worldToUIY(b[1],b[2]),1,0.95,0.8,0.25)
            end
        end
        local x,y=api:worldToUIX(target.anchor.x,target.anchor.y),api:worldToUIY(target.anchor.x,target.anchor.y)
        map:drawRect(x-5,y-5,10,10,1,0.95,0.8,0.25)
        panelText(tr("UI_SC_Map_TargetSummary",target.label,target.distance or "?",
            tr(target.mapKnown and "UI_SC_Map_Known" or "UI_SC_Map_Unconfirmed")),
            math.max(height*5+50,map:getHeight()-height*5-120))
    elseif session.error then
        panelText(M.reason(session.error),math.max(height*5+50,map:getHeight()-height*5-120))
    end
end

return M
