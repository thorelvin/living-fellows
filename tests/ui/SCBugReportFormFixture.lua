-- SPDX-License-Identifier: MIT
-- Model the widgets' public callbacks. Native menu and text rendering are checked in PZO.
function require() end
UIFont = {Small="Small", Large="Large"}
Joypad = {YButton="Y", LBumper="LB", RBumper="RB", Texture={YButton="Y"}}
JoypadState = {getMainMenuJoypad=function() return nil end}
function getTextManager()
    return {getFontHeight=function(_, font) return font == UIFont.Large and 28 or 16 end,
        MeasureStringX=function(_, font, text) return #text * 8 end}
end
local Widget = {}
function Widget:derive() return setmetatable({}, {__index=self}) end
function Widget:new(x, y, w, h)
    return setmetatable({x=x,y=y,width=w,height=h,visible=true,children={}}, {__index=self})
end
function Widget:initialise() end
function Widget:addChild(child)
    child.parent = self
    self.children[#self.children+1] = child
    if child.createChildren then child:createChildren() end
end
function Widget:removeChild(child)
    for i, existing in ipairs(self.children) do
        if existing == child then table.remove(self.children, i); break end
    end
    child.parent = nil
end
function Widget:getWidth() return self.width end
function Widget:getHeight() return self.height end
function Widget:getY() return self.y end
function Widget:getScrollAreaHeight() return self.height end
function Widget:getScrollHeight() return self.height * 2 end
function Widget:getYScroll() return self.yScroll or 0 end
function Widget:setYScroll(value) self.yScroll = value end
function Widget:getRight() return self.x + self.width end
function Widget:isVisible() return self.visible end
function Widget:setVisible(value) self.visible = value end
function Widget:setTitle(value) self.title = value end
function Widget:setText(value)
    self.text = value
    if self.onTextChangeFunction then self.onTextChangeFunction(self.target, self) end
end
function Widget:getText() return self.text end
function Widget:setEditable(value) self.editable = value end
function Widget:setMultipleLine(value) self.multiline = value end
function Widget:focus() self.focused = true end
function Widget:unfocus() self.focused = false end
function Widget:setMaxTextLength(value) self.limit = value end
function Widget:forceClick()
    if self.visible then return self.onclick(self.target, self) end
end
for _, name in ipairs({"setAnchorLeft","setAnchorTop","setAnchorRight","setAnchorBottom","addScrollBars",
    "setCursorPos","clearJoypadButtonsList","insertNewLineOfButtons","setISButtonForB","prerender"}) do
    Widget[name] = function() end
end
ISPanelJoypad = Widget:derive()
ISButton = Widget:derive()
function ISButton:new(x, y, w, h, title, target, onclick)
    local item = Widget.new(self, x, y, w, h)
    item.title, item.target, item.onclick = title, target, onclick
    return item
end
ISTextEntryBox = Widget:derive()
function ISTextEntryBox:new(text, x, y, w, h)
    local item = Widget.new(self, x, y, w, h)
    item.text = text
    return item
end
function SC_TEST_REPORT_SCREEN(inGame)
    local screen = Widget:new(0, 0, 1280, 720)
    screen.inGame = inGame
    screen.bottomPanel = Widget:new(0, 0, 300, 320)
    screen.modListDetail = Widget:new(970, 600, 240, 27)
    screen.onJoypadDown = function() screen.stockJoypad = true end
    return screen
end
SurvivorCompanion = {BugReport={}}
