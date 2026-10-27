-- SPDX-License-Identifier: MIT
-- Minimal stand-ins for the vanilla UI and timed-action classes the camp
-- computer uses, a fake clock, a computer on a powered desk, and a player.
-- Drawing calls are counted, never rendered.
function require() return true end
TERMINAL_TEST = { checks = 0, now = 1000, hours = 100, queued = {}, walked = {}, performed = 0,
    uiAdds = 0, uiRemoves = 0, draws = 0 }
local T = TERMINAL_TEST
function T.check(value, message)
    T.checks = T.checks + 1
    assert(value, "terminal ui " .. T.checks .. ": " .. tostring(message))
end

-- Every pick takes the first open line, so greetings are exact.
function ZombRand() return 0 end
UIFont = { Code = "Code", Small = "Small" }
Keyboard = { KEY_ESCAPE = 1, KEY_TAB = 15, KEY_PRIOR = 201, KEY_NEXT = 209 }
function getCore()
    return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end }
end
function getTextManager()
    return { getFontHeight = function() return 16 end,
        MeasureStringX = function(_, _, value) return #tostring(value) * 8 end }
end
function getGameTime()
    return { getWorldAgeHours = function() return T.hours end }
end

local function element(object)
    object.children = {}
    function object:getWidth() return self.width end
    function object:getHeight() return self.height end
    function object:setWidth(value) self.width = value end
    function object:setHeight(value) self.height = value end
    function object:setX(value) self.x = value end
    function object:setY(value) self.y = value end
    function object:setFont(value) self.font = value end
    function object:initialise() end
    function object:instantiate() end
    function object:addChild(child) self.children[#self.children + 1] = child end
    function object:setVisible(value) self.visible = value end
    function object:setAlwaysOnTop(value) self.onTop = value end
    return object
end

ISPanel = {}
ISPanel.__index = ISPanel
function ISPanel:derive(name)
    local class = { Type = name }
    class.__index = class
    return setmetatable(class, self)
end
function ISPanel.new(class, x, y, width, height)
    local object = element({ x = x, y = y, width = width, height = height, visible = true })
    return setmetatable(object, class)
end
function ISPanel:initialise() end
function ISPanel:createChildren() end
function ISPanel:update() end
function ISPanel:onMouseDown() self.mouseDowns = (self.mouseDowns or 0) + 1 end
function ISPanel:addToUIManager()
    T.uiAdds = T.uiAdds + 1
    self.inUI = true
    self:createChildren()
end
function ISPanel:removeFromUIManager()
    T.uiRemoves = T.uiRemoves + 1
    self.inUI = false
end
function ISPanel:drawRect() T.draws = T.draws + 1 end
function ISPanel:drawRectBorder() T.draws = T.draws + 1 end
function ISPanel:drawText(value)
    T.draws = T.draws + 1
    T.lastDrawn = value
end
function ISPanel:drawTextZoomed(value,x,y,zoom)
    T.lastTextZoom = zoom
    ISPanel.drawText(self,value,x,y)
end
function ISPanel:drawTextureScaled(texture,x,y,width,height,a,r,g,b)
    T.draws = T.draws + 1
    T.lastTextureDraw = {texture=texture,x=x,y=y,width=width,height=height,a=a,r=r,g=g,b=b,clip=T.stencil}
end
function ISPanel:setStencilRect(x,y,width,height) T.stencil={x=x,y=y,width=width,height=height} end
function ISPanel:clearStencilRect() T.stencil=nil end

ISButton = {}
function ISButton:new(x, y, width, height, title, target, onClick)
    return element({ x = x, y = y, width = width, height = height, title = title, target = target,
        onClick = onClick })
end

ISTextEntryBox = {}
function ISTextEntryBox:new(title, x, y, width, height)
    local entry = element({ text = title or "", x = x, y = y, width = width, height = height })
    function entry:getText() return self.text end
    function entry:setText(value) self.text = value end
    function entry:focus() self.focused = true end
    function entry:unfocus() self.focused = false end
    function entry:setTextRGBA() end
    function entry:setMaxTextLength(value) self.maxLength = value end
    function entry:setPlaceholderText(value) self.placeholder = value end
    return entry
end

ISBaseTimedAction = {}
ISBaseTimedAction.__index = ISBaseTimedAction
function ISBaseTimedAction:derive(name)
    local class = { Type = name }
    class.__index = class
    return setmetatable(class, self)
end
function ISBaseTimedAction.new(class, character)
    return setmetatable({ character = character }, class)
end
function ISBaseTimedAction:perform() T.performed = T.performed + 1 end
function ISBaseTimedAction:setActionAnim(value) self.anim = value end
ISTimedActionQueue = { add = function(action) T.queued[#T.queued + 1] = action end }
luautils = { walkAdj = function(player, square)
    T.walked[#T.walked + 1] = { player = player, square = square }
    return T.walkable ~= false
end }
ISWorldObjectContextMenu = { addToolTip = function() return {} end }

function T.square(x, y, z, powered)
    local square = { x = x, y = y, z = z or 0, generatorPower = powered ~= false, objects = {} }
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:haveElectricity() return self.generatorPower == true end
    function square:hasGridPower() return self.gridPower == true end
    function square:getRoom() return self.room end
    function square:getObjects()
        local list = self.objects
        return { size = function() return #list end, get = function(_, index) return list[index + 1] end }
    end
    return square
end

function T.computer(square, name)
    local data = {}
    local computer = { square = square, index = 3, data = data, custom = name or "Computer" }
    function computer:getSquare() return self.square end
    function computer:getObjectIndex() return self.index end
    function computer:getModData() return self.data end
    function computer:getProperties()
        local custom = self.custom
        return { get = function(_, key) return key == "CustomName" and custom or nil end }
    end
    square.objects[#square.objects + 1] = computer
    return computer
end

function T.player(x, y, z)
    local player = { x = x, y = y, z = z or 0, dead = false, faced = 0 }
    function player:getDescriptor() return { getForename = function() return "Thor" end } end
    function player:isDead() return self.dead end
    function player:faceThisObject() self.faced = self.faced + 1 end
    function player:shouldBeTurning() return false end
    function player:SetVariable(key, value) self[key] = value end
    return player
end

SurvivorCompanion = SurvivorCompanion or {}
SurvivorCompanion.GameplayUtil = {
    call = function(object, method, ...)
        if object == nil then return nil, false end
        local member = object[method]
        if type(member) ~= "function" then return nil, false end
        local ok, value = pcall(member, object, ...)
        return value, ok
    end,
    position = function(value)
        if type(value) ~= "table" then return nil end
        return value.x, value.y, value.z
    end,
    text = function(_, fallback) return fallback end,
}
