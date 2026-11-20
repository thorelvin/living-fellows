-- SPDX-License-Identifier: MIT
require 'ISUI/ISPanelJoypad'
require 'ISUI/ISScrollingListBox'
require 'ISUI/ISButton'
require 'ISUI/ISPostDeathUI'
require 'OptionScreens/CoopCharacterCreation'
local SC=SurvivorCompanion
local UI={} SC.HandoverUI=UI
local Panel=ISPanelJoypad:derive('LFHandoverPanel')
local window,lastDeath
local function button(panel,x,y,w,label,fn)
    local b=ISButton:new(x,y,w,30,label,panel,fn);b:initialise();panel:addChild(b);return b
end
local function act(fn,...)
    local called,okay,why=pcall(fn,...)
    if not called or okay==false then SC.Handover.reportError(called and why or okay) end
end
function Panel:createChildren()
    local w=self.width
    local listHeight=math.max(64,self.height-386);local shift=190-listHeight;self.bodyShift=shift
    self.newButton=button(self,20,90,w-40,'Start a new survivor at base',function() act(SC.Handover.startNew,false) end)
    self.list=ISScrollingListBox:new(20,166,w-40,listHeight)
    self.list:initialise();self.list:instantiate();self.list.itemheight=48;self.list.font=UIFont.Small
    self.list.doDrawItem=function(list,y,item,alt)
        local row=item.item
        if list.selected==item.index then list:drawRect(0,y,list.width-16,list.itemheight,.3,.43,.53,.36) end
        list:drawText(row.name,8,y+5,1,.93,.68,1,UIFont.Small)
        local pos=row.position;local x=pos and (pos.x or (pos.getX and pos:getX()))
        local py=pos and (pos.y or (pos.getY and pos:getY()))
        local detail=row.reason or ((row.health and string.format('Health: %.0f%% | ',row.health) or '')
            ..(x and ('Near '..math.floor(x)..', '..math.floor(py)) or 'Location unavailable'))
        list:drawText(detail,8,y+24,.82,.84,.8,1,UIFont.Small)
        return y+list.itemheight
    end
    self:addChild(self.list)
    self.takeButton=button(self,20,366-shift,w-40,'Take over selected companion',function()
        local item=self.list.items[self.list.selected]
        if item then act(SC.Handover.chooseCompanion,item.item.id) end
    end)
    self.normalButton=button(self,20,462-shift,(w-50)/2,'Ordinary respawn',function()
        local current=SC.Handover.current()
        if current and current.phase=='arrival-blocked' then act(SC.Handover.useOrdinaryArrival)
        else act(SC.Handover.startNew,true) end
    end)
    self.backButton=button(self,30+(w-50)/2,462-shift,(w-50)/2,'Back',function() UI.close() end)
    self.exitButton=button(self,20,502-shift,(w-50)/2,'Exit to menu',function()
        ISPostDeathUI.onExit(lastDeath or self)
    end)
    self.quitButton=button(self,30+(w-50)/2,502-shift,(w-50)/2,'Quit game',function()
        ISPostDeathUI.onQuitToDesktop(lastDeath or self)
    end)
    self:refresh()
end
function Panel:onGainJoypadFocus(joypad)
    ISPanelJoypad.onGainJoypadFocus(self,joypad)
    self:clearJoypadButtonsList()
    self:insertNewLineOfButtons(self.newButton);self:insertNewLineOfButtons(self.takeButton)
    self:insertNewLineOfButtons(self.normalButton,self.backButton);self:insertNewLineOfButtons(self.exitButton,self.quitButton)
    self.joypadIndex,self.joypadIndexY=1,1;self:setISButtonForB(self.backButton)
end
function Panel:onJoypadDirLeft(joypad)
    if self.joypadIndexY==2 and #self.list.items>0 then self.list.selected=((self.list.selected or 1)-2)%#self.list.items+1;return end
    ISPanelJoypad.onJoypadDirLeft(self,joypad)
end
function Panel:onJoypadDirRight(joypad)
    if self.joypadIndexY==2 and #self.list.items>0 then self.list.selected=(self.list.selected or 1)%#self.list.items+1;return end
    ISPanelJoypad.onJoypadDirRight(self,joypad)
end
function Panel:refresh()
    local selected=self.list.items[self.list.selected];local id=selected and selected.item.id
    self.list:clear()
    for _,row in ipairs(SC.Handover.options()) do
        self.list:addItem(row.name,row)
        if row.id==id then self.list.selected=#self.list.items end
    end
    if #self.list.items>0 and (not self.list.selected or self.list.selected<1) then self.list.selected=1 end
    self.refreshAt=getTimestampMs()+1500
end
function Panel:prerender()
    ISPanelJoypad.prerender(self)
    local current=SC.Handover.current()
    if not current then UI.close();return end
    if getTimestampMs()>=(self.refreshAt or 0) then self:refresh() end
    self:drawText('The Handover',20,15,.94,.9,.74,1,UIFont.Large)
    self:drawText('The camp carries on. Choose who you play next.',20,50,.84,.86,.81,1,UIFont.Small)
    self:drawText('Take over a living recruit',20,140,.94,.9,.74,1,UIFont.Medium)
    local shift=self.bodyShift or 0
    self:drawText('Their skills, gear, wounds and current location are kept.',20,404-shift,.84,.86,.81,1,UIFont.Small)
    self:drawText('Takeover is permanent. They leave the companion roster.',20,420-shift,.84,.86,.81,1,UIFont.Small)
    local point,why=SC.Handover.basePoint()
    local choosing=current.phase=='choosing'
    self.newButton:setEnable(choosing and point~=nil)
    self.newButton.tooltip=why or 'Use the normal character creator. The camp may still be dangerous.'
    local selected=self.list.items[self.list.selected]
    self.takeButton:setEnable(choosing and selected~=nil and selected.item.reason==nil)
    self.normalButton:setEnable(choosing or current.phase=='arrival-blocked');self.backButton:setEnable(choosing)
    self.normalButton:setTitle(current.phase=='arrival-blocked' and 'Use ordinary spawn' or 'Ordinary respawn')
    local message=SC.Handover.error() or (not choosing and 'Finishing Handover. The world is paused.' or 'The world is paused while you choose. Camp danger remains when play resumes.')
    self:drawText(message:sub(1,100),20,440-shift,.86,.78,.59,1,UIFont.Small)
    if JoypadState and JoypadState.players[1] then self:drawText('On takeover: D-pad left/right chooses a companion. A selects; B goes back.',20,self.height-22,.7,.74,.69,1,UIFont.Small) end
end
function UI.close()
    if window then
        local joypad=JoypadState and JoypadState.players[1]
        if joypad and joypad.focus==window then
            local current=SC.Handover.current()
            setJoypadFocus(0,current and current.phase=='choosing' and lastDeath or nil)
        end
        window:removeFromUIManager();window=nil
    end
    if lastDeath and ISPostDeathUI.instance[0]==lastDeath then lastDeath:setVisible(true) end
    if setShowPausedMessage then setShowPausedMessage(true) end
end
function UI.open()
    if not SC.Handover.current() then return end
    if window then window:bringToTop();return window end
    local w=math.min(640,getCore():getScreenWidth()-30);local h=math.min(576,getCore():getScreenHeight()-30)
    lastDeath=ISPostDeathUI.instance[0] or lastDeath
    if lastDeath then lastDeath:setVisible(false) end
    window=Panel:new((getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-h)/2,w,h)
    window.backgroundColor={r=.055,g=.07,b=.06,a=.98};window.borderColor={r=.39,g=.43,b=.31,a=1}
    window:initialise();window:addToUIManager();window:setAlwaysOnTop(true)
    window.javaObject:setIgnoreLossControl(true)
    window.playerIndex=0
    if setShowPausedMessage then setShowPausedMessage(false) end
    if JoypadState and JoypadState.players[1] then setJoypadFocus(0,window) end
    return window
end
function UI.install()
    if ISPostDeathUI.LFHandoverWrapped then return true end
    ISPostDeathUI.LFHandoverWrapped=true
    local respawn=ISPostDeathUI.onRespawn
    ISPostDeathUI.onRespawn=function(self,...)
        if self.playerIndex==0 and SC.Handover.current() then return UI.open() end
        return respawn(self,...)
    end
    local render=ISPostDeathUI.prerender
    ISPostDeathUI.prerender=function(self,...)
        render(self,...)
        if self.playerIndex==0 and SC.Handover.current() and self.waitOver then
            self.buttonRespawn:setTitle('Continue: The Handover')
            self.buttonExit:setVisible(true);self.buttonQuit:setVisible(true)
        end
    end
    local accept=CoopCharacterCreation.accept1
    CoopCharacterCreation.accept1=function(self,...)
        local okay=accept(self,...);if not okay then return okay end
        local point=SC.Handover.creatorPoint()
        if point then
            SC.Handover.noteOrdinaryPoint({x=getWorld():getLuaPosX(),y=getWorld():getLuaPosY(),z=getWorld():getLuaPosZ()})
            local fresh,why=SC.Handover.basePoint()
            if not fresh or fresh.baseId~=point.baseId then SC.Handover.reportError(why or 'The selected camp changed.');return false end
            getWorld():setLuaPosX(fresh.x);getWorld():setLuaPosY(fresh.y);getWorld():setLuaPosZ(fresh.z)
        end
        return okay
    end
    local finish=CoopCharacterCreation.accept
    CoopCharacterCreation.accept=function(self,...)
        local result=finish(self,...)
        if SC.Handover.isPaused() then setGameSpeed(0) end
        return result
    end
    local cancel=CoopCharacterCreation.cancel
    CoopCharacterCreation.cancel=function(self,...)
        local result=cancel(self,...);SC.Handover.cancelCreation()
        if SC.Handover.current() then UI.open() end
        return result
    end
    return true
end
function UI.installResume()
    if not MainScreen or not MainScreen.continueLatestSaveAux or MainScreen.LFHandoverResumeWrapped then return end
    MainScreen.LFHandoverResumeWrapped=true
    local continue=MainScreen.continueLatestSaveAux
    MainScreen.continueLatestSaveAux=function(...)
        if SCBridge and type(SCBridge.resumeHandoverBeforeLoad)=='function' then
            local okay,why=pcall(SCBridge.resumeHandoverBeforeLoad)
            if not okay then
                SC.Diagnostics.report('handover',nil,'saved successor recovery failed',why)
                local modal=ISModalDialog:new((getCore():getScreenWidth()-480)/2,(getCore():getScreenHeight()-140)/2,
                    480,140,'Handover recovery could not finish. The saved transfer has been kept. Check the Living Fellows installation and try again.',false,nil,nil)
                modal:initialise();modal:addToUIManager();modal:setAlwaysOnTop(true)
                return
            end
        end
        return continue(...)
    end
end
return UI
