-- SPDX-License-Identifier: MIT
-- Keep stock checkbox and UIElement layout methods; stand in for Java windows.
BasePolicyFixture = { classes = {}, remote = false, calls = {}, accepts = true,
    screenWidth = 1920, screenHeight = 1080, fontHeight = 16 }
local fixture = BasePolicyFixture
function require() end
UIFont = { Small = 1 }
Keyboard = {}
Events = nil
function getTexture() end
function getCore()
    return { getScreenWidth = function() return fixture.screenWidth end,
        getScreenHeight = function() return fixture.screenHeight end }
end
function getTextManager()
    return {
        getFontHeight = function() return fixture.fontHeight end,
        MeasureStringX = function(_, _, text) return #text * fixture.fontHeight / 2 end,
    }
end
function getSoundManager() return { playUISound = function() end } end
local player = {}
function getSpecificPlayer() return player end
SurvivorCompanion = {
    UIBounds = { clamp = function(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end },
    Interaction = { descriptor = function(action) return { key = action } end },
    BaseWatch = { isRemote = function() return fixture.remote end },
    BaseLife = { setPolicy = function(key, selected)
        fixture.calls[#fixture.calls + 1] = { key = key, selected = selected }
        if fixture.throws then error("policy unavailable") end
        return fixture.accepts, "policy_rejected"
    end },
}
ISPanel = {}
function ISPanel:derive(name)
    local class = setmetatable({ Type = name }, { __index = self })
    class.__index = class
    fixture.classes[name] = class
    return class
end
function ISPanel:new(x, y, width, height)
    return setmetatable({ x = x, y = y, width = width, height = height,
        childrenInOrder = {}, yScroll = 0 }, { __index = self })
end
function ISPanel:initialise() end
function ISPanel:instantiate() end
function ISPanel:getWidth() return self.width end
function ISPanel:getHeight() return self.height end
function ISPanel:setWidth(value) self.width = value end
-- ISUIElement is loaded from the installed game after this fixture. Retain its
-- exact unattached-element screen clamp instead of a simplified setter that
-- makes a deep scrolling checkbox pass while the actual game moves it upward.
function ISPanel:getKeepOnScreen() return ISUIElement.getKeepOnScreen(self) end
function ISPanel:setHeight(value) return ISUIElement.setHeight(self, value) end
function ISPanel:addChild(child)
    self.childrenInOrder[#self.childrenInOrder + 1] = child
    child.parent = self
end
function ISPanel:removeChild(child)
    for index, value in ipairs(self.childrenInOrder) do
        if value == child then table.remove(self.childrenInOrder, index) child.parent = nil return end
    end
end
function ISPanel:setVisible(value) self.visible = value end
function ISPanel:getYScroll() return self.yScroll end
function ISPanel:setYScroll(value) self.yScroll = value end
function ISPanel:setScrollWidth(value) self.scrollWidth = value end
function ISPanel:setScrollHeight(value) self.scrollHeight = value end
ISScrollingListBox = ISPanel:derive("ISScrollingListBox")
ISLabel = ISPanel:derive("ISLabel")
function ISLabel:new(x, y, height, name)
    local object = ISPanel.new(self, x, y, #name * fixture.fontHeight / 2, height)
    object.name = name
    return object
end
