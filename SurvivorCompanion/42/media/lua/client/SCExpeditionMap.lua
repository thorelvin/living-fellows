-- SPDX-License-Identifier: MIT
require "ISUI/Maps/ISWorldMap"
require "ISUI/ISButton"
require "SCExpeditionTargets"
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
    end
    return true
end

function M.closed(map)
    local session = M.session
    if not session or map and session.map and session.map ~= map then return end
    M.session = nil
    if session.backButton and session.map then session.map:removeChild(session.backButton) end
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
    session.chosen=SC.ExpeditionTargets.copy(fresh)
    session.map:close()
end

function M.fillContext(map, context, at)
    -- Stock may reuse a still-open menu at the same point. Replace only our
    -- options, retaining other mods' and vanilla entries.
    for index=#(context.options or {}),1,-1 do
        local option=context.options[index]
        if option.scExpeditionMapAction or option.scTaxiMapAction then
            if type(context.removeOptionByName)=="function" then context:removeOptionByName(option.name)
            else table.remove(context.options,index) end
        end
    end
    if SCBridge and SCBridge.loadedWorldMap and map.javaObject then
        SC.ExpeditionTargets.mapData=SCBridge.loadedWorldMap(map.javaObject) or SC.ExpeditionTargets.mapData
    end
    local session = M.session
    if session and session.map == map then
        if not usable(session) then M.closed(map) return false end
        local target,reason = SC.ExpeditionTargets.resolveAtPoint(session.kind,at,session.context())
        session.highlight,session.error=target,reason
        if target then
            local option=context:addOption(tr("UI_SC_Map_Select",target.label),nil,function() choose(session,target) end)
            option.scExpeditionMapAction=true
        else
            local option=context:addOption(M.reason(reason),nil,nil)
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
    for _,kind in ipairs({"scout","search","fish","wood"}) do
        local target=SC.ExpeditionTargets.resolveAtPoint(kind,at,SC.ExpeditionTargets.context(actor,"drive"))
        if target then
            local chosen=SC.ExpeditionTargets.copy(target)
            local option=context:addOption(tr("UI_SC_Map_Plan_"..kind,target.label),nil,function()
                map:close()
                local window=SC.UI.open("expeditions")
                if window and window.detail then SC.UIExpeditions.applyMapTarget(window.detail,chosen,false) end
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
    if session and session.backButton and session.map then session.map:removeChild(session.backButton) end
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
        local lines=SC.UI and SC.UI.wrapText(font,text,panelWidth-24) or {text}
        map:drawRect(x,y,panelWidth,#lines*(height+3)+16,0.9,0.025,0.035,0.03)
        for _,value in ipairs(lines) do
            map:drawText(value,x+12,y+8,0.94,0.94,0.86,1,font)
            y=y+height+3
        end
    end
    local ctx=session.context()
    panelText(tr("UI_SC_Map_Instructions",tr("UI_SC_Map_Kind_"..session.kind),
        SC.ExpeditionTargets.limit(ctx.travelMode)),16,headerX,math.max(240,right-headerX))
    if not session.backButton then
        local button=ISButton:new(math.max(16,map:getWidth()-156),math.max(16,map:getHeight()-102),
            140,math.max(32,height+14),tr("UI_SC_Map_Back"),map,function(target) target:close() end)
        button:initialise()
        map:addChild(button)
        session.backButton=button
    end
    session.backButton:setX(math.max(16,map:getWidth()-156))
    session.backButton:setY(math.max(16,map:getHeight()-102))
    local api=map.mapAPI
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
