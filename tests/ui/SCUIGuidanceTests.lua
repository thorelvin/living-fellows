-- SPDX-License-Identifier: MIT
-- What the player sees: the launcher line and the Status card report a nudge
-- as shown only when they actually draw it.
local SC = SurvivorCompanion
local checks = 0
local function check(value, message) checks = checks + 1; assert(value, message) end
UIFont = { Small = "small" }
getTextManager = function()
    return { MeasureStringX = function(_, _, text) return #tostring(text) * 7 end,
        getFontHeight = function() return 14 end }
end
getCore = function() return { getScreenWidth = function() return 1920 end } end
local panels = {}
ISPanel = {}
function ISPanel:new(x, y, w, h)
    local o = setmetatable({ x = x, y = y, w = w, h = h, visible = true, children = {} }, { __index = ISPanel })
    panels[#panels + 1] = o
    return o
end
function ISPanel:initialise() end
function ISPanel:instantiate() end
function ISPanel:addToUIManager() self.managed = true end
function ISPanel:removeFromUIManager() self.managed = false end
function ISPanel:setAlwaysOnTop() end
function ISPanel:setVisible(value) self.visible = value end
function ISPanel:isVisible() return self.visible end
function ISPanel:setWidth(value) self.w = value end
function ISPanel:setHeight(value) self.h = value end
function ISPanel:setX(value) self.x = value end
function ISPanel:setY(value) self.y = value end
function ISPanel:getX() return self.x end
function ISPanel:getY() return self.y end
function ISPanel:getWidth() return self.w end
function ISPanel:getHeight() return self.h end
function ISPanel:addChild(child) self.children[#self.children + 1] = child end
function ISPanel:drawRectBorder() end
function ISPanel:drawText(text) self.drawn = self.drawn or {}; self.drawn[#self.drawn + 1] = text end
function ISPanel.prerender() end
ISButton = { new = function(_, x, y, w, h, title)
    local b = { title = title }
    function b:initialise() end
    function b:setTitle(value) self.title = value end
    return b
end }
SC.GameplayUtil = { nowMs = function() return 0 end, text = function(_, fallback) return fallback end }
local item, view, shown, opened = nil, nil, {}, nil
SC.Guidance = {
    notice = function() return nil end, tracker = function() return item end, view = function() return view end,
    shown = function(id) shown[#shown + 1] = id end, report = function() end,
    steps = {}, list = function() return {} end, text = function(id) return id end,
}
SC.UI = { open = function(tab) opened = tab end, layoutMetrics = function() return { buttonHeight = 20 } end }

local launcher = ISPanel:new(1880, 300, 40, 40)
launcher.dockSide = "right"
item = { id = "nudge_expeditions", kind = "nudge", title = "Expeditions", tab = "expeditions",
    text = "Your camp has a crew now. Expeditions can send them scouting, looting, fishing or collecting wood." }
SC.UIGuidance.launcher(launcher)
local tracker = panels[#panels]
check(tracker.visible and #shown == 1 and shown[1] == "nudge_expeditions",
    "a nudge drawn beside the launcher counts as shown")
tracker.drawn = {}; tracker:render()
check(#tracker.drawn == 4 and tracker.drawn[1] == "Expeditions",
    "the nudge shows its title and its text wrapped to three lines")
check(tracker.x + tracker.w <= launcher.x and tracker.y == launcher.y, "the line sits beside the launcher")
tracker:onMouseUp(); check(opened == "expeditions", "clicking a feature nudge opens its tab")
item = { id = "meet", kind = "step", title = "Meet a survivor" }; shown = {}
SC.UIGuidance.launcher(launcher); tracker.drawn = {}; tracker:render()
check(#shown == 0 and #tracker.drawn == 1, "a checklist step is one line and spends nothing")
tracker:onMouseUp(); check(opened == "status", "clicking a step opens Status")
launcher.visible = false; SC.UIGuidance.launcher(launcher)
check(not tracker.visible, "the line hides with the launcher")
item, launcher.visible = nil, true; SC.UIGuidance.launcher(launcher)
check(not tracker.visible, "nothing to say hides the line")

local detail = {
    metrics = { buttonHeight = 20 },
    addSection = function(_, _, y) return y + 14 end,
    addInformationLine = function(_, _, y) return y + 14 end,
}
local status = ISPanel:new(0, 0, 400, 600)
view = { id = "nudge_jobs", kind = "nudge", title = "Camp jobs", text = "Residents can help." }
shown = {}
SC.UIGuidance.build(detail, status, 7)
local card = status.children[1]
check(#shown == 0, "building the card off screen spends nothing")
card:prerender()
check(#shown == 1 and shown[1] == "nudge_jobs", "a nudge on the drawn Status card counts as shown")
view = { id = "camp", kind = "step", title = "Set a camp core", text = "Right-click the ground." }
shown = {}
status = ISPanel:new(0, 0, 400, 600)
SC.UIGuidance.build(detail, status, 7)
status.children[1]:prerender()
check(#shown == 0, "a checklist step on the card spends nothing")
SC.UIGuidance.reset()
check(not tracker.managed, "a world reset removes the launcher line")
print("UI_GUIDANCE_PASS checks=" .. checks)
