-- SPDX-License-Identifier: MIT
require "SCBugReport"
require "ISUI/ISPanelJoypad"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

local SC = SurvivorCompanion
local UI = {}
SC.BugReportUI = UI
local Form = ISPanelJoypad:derive("LFBugReportForm")
local pad = 18

local function entry(parent, y, height, editable)
    local box = ISTextEntryBox:new("", pad, y, parent.width - pad * 2, height)
    box:initialise()
    parent:addChild(box)
    box:setMultipleLine(true)
    box:setEditable(editable)
    if editable then
        box:setMaxTextLength(500)
        box.target = parent
        box.onTextChangeFunction = function(form) form.message = nil end
    end
    box:addScrollBars()
    return box
end

local function button(parent, x, y, width, height, title, click)
    local control = ISButton:new(x, y, width, height, title, parent, click)
    control:initialise()
    parent:addChild(control)
    return control
end

local function focus(target)
    local joypad = JoypadState.getMainMenuJoypad()
    if joypad then
        joypad.focus = target
        updateJoypadFocus(joypad)
    end
end

function Form:createChildren()
    local small = getTextManager():getFontHeight(UIFont.Small)
    local large = getTextManager():getFontHeight(UIFont.Large)
    local buttonHeight = math.max(30, small + 12)
    local buttonsY = self.height - pad - buttonHeight
    self.messageY = buttonsY - small - 10
    self.headingY = pad + large + 10
    self.firstLabelY = self.headingY + small + 14
    local contentY = self.firstLabelY + small + 4
    local contentBottom = self.messageY - 10
    local fieldHeight = math.floor((contentBottom - contentY - small - 16) / 2)
    self.secondLabelY = contentY + fieldHeight + 12
    self.what = entry(self, contentY, fieldHeight, true)
    self.steps = entry(self, self.secondLabelY + small + 4, fieldHeight, true)
    self.preview = entry(self, self.firstLabelY, contentBottom - self.firstLabelY, false)
    local gap = 10
    local width = math.floor((self.width - pad * 2 - gap * 2) / 3)
    self.cancel = button(self, pad, buttonsY, width, buttonHeight, "Cancel", self.close)
    self.back = button(self, pad, buttonsY, width, buttonHeight, "Edit report", self.edit)
    self.copy = button(self, pad + width + gap, buttonsY, width, buttonHeight, "Copy draft link", self.copyLink)
    self.primary = button(self, self.width - pad - width, buttonsY, width, buttonHeight, "Review draft", self.advance)
    self:edit()
end

function Form:showStage(draft)
    self.what:unfocus()
    self.steps:unfocus()
    self.draft = draft
    self.message = nil
    local editing = draft == nil
    self.what:setVisible(editing)
    self.steps:setVisible(editing)
    self.cancel:setVisible(editing)
    self.preview:setVisible(not editing)
    self.back:setVisible(not editing)
    self.copy:setVisible(not editing)
    self.primary:setTitle(editing and "Review draft" or "Open GitHub draft")
    self:clearJoypadButtonsList()
    if editing then
        self:insertNewLineOfButtons(self.what)
        self:insertNewLineOfButtons(self.steps)
        self:insertNewLineOfButtons(self.cancel, self.primary)
    else
        self:insertNewLineOfButtons(self.back, self.copy, self.primary)
    end
    if self.joyfocus then
        self:setISButtonForB(editing and self.cancel or self.back)
        self:setJoypadFocusTopLeft(self.joyfocus)
    end
end

function Form:onGainJoypadFocus(joypad)
    ISPanelJoypad.onGainJoypadFocus(self, joypad)
    self:setISButtonForB(self.draft and self.back or self.cancel)
    self:restoreJoypadFocus(joypad)
end

function Form:onLoseJoypadFocus(joypad)
    self:clearISButtonB()
    ISPanelJoypad.onLoseJoypadFocus(self, joypad)
end

function Form:onJoypadDown(key, joypad)
    if self.draft and (key == Joypad.LBumper or key == Joypad.RBumper) then
        local box = self.preview
        local view = box:getScrollAreaHeight()
        local bottom = math.min(0, view - box:getScrollHeight())
        local page = math.max(1, view - getTextManager():getFontHeight(UIFont.Small))
        local delta = key == Joypad.RBumper and -page or page
        box:setYScroll(math.max(bottom, math.min(0, box:getYScroll() + delta)))
        return
    end
    ISPanelJoypad.onJoypadDown(self, key, joypad)
end

function Form:edit()
    self.preview:setText("")
    self:showStage(nil)
end

function Form:advance()
    if self.draft then
        local opened, reason = SC.BugReport.openDraft(self.draft)
        self.message = opened and "Finish reviewing your report on GitHub." or reason
        return
    end
    local draft, reason = SC.BugReport.buildDraft(self.what:getText(), self.steps:getText())
    if not draft then
        self.message = reason
        return
    end
    self.preview:setText(draft.body)
    self.preview:setCursorPos(0)
    self.preview:setYScroll(0)
    self:showStage(draft)
end

function Form:copyLink()
    if not self.draft then return end
    local copied = Clipboard and pcall(Clipboard.setClipboard, self.draft.url)
    self.message = copied and "Draft link copied. Paste it into your browser." or "Could not copy the link."
end

function Form:prerender()
    ISPanelJoypad.prerender(self)
    self:drawText("Report a Living Fellows bug", pad, pad, 1, 1, 1, 1, UIFont.Large)
    if self.draft then
        self:drawText("Review what will open on GitHub. You submit the issue there.", pad, self.headingY, .85, .86, .85, 1, UIFont.Small)
    else
        self:drawText("Leave out names, save names and file paths.", pad, self.headingY, .85, .86, .85, 1, UIFont.Small)
        self:drawText("What happened?", pad, self.firstLabelY, 1, 1, 1, 1, UIFont.Small)
        self:drawText("How can we reproduce it?", pad, self.secondLabelY, 1, 1, 1, 1, UIFont.Small)
    end
    if self.message then
        self:drawText(self.message, pad, self.messageY, 1, .86, .6, 1, UIFont.Small)
    elseif self.draft and self.joyfocus then
        self:drawText("Use the shoulder buttons to scroll through the draft.", pad, self.messageY, .85, .86, .85, 1, UIFont.Small)
    end
end

function Form:close()
    self.what:unfocus()
    self.steps:unfocus()
    local screen = self.parent
    screen:removeChild(self)
    screen.lfBugReportForm = nil
    screen.bottomPanel:setVisible(true)
    if screen:isVisible() then focus(screen) end
end

-- The vanilla Escape action removes MainScreen, then notifies its children.
Form.onReturnToGame = Form.close

local function showForm(screen)
    if screen.lfBugReportForm or not screen.bottomPanel:isVisible() then return end
    local width = math.min(680, screen:getWidth() - 24)
    local height = math.min(480, screen:getHeight() - 24)
    local form = Form:new((screen:getWidth() - width) / 2, (screen:getHeight() - height) / 2, width, height)
    form.backgroundColor = {r=.07, g=.08, b=.07, a=.98}
    form:initialise()
    screen:addChild(form)
    screen.lfBugReportForm = form
    screen.bottomPanel:setVisible(false)
    focus(form)
    if not form.joyfocus then form.what:focus() end
end

function UI.install(screen)
    if not screen or not screen.inGame or screen.lfBugReportButton or not screen.bottomPanel then return end
    local anchor = screen.modListDetail or screen.reportBug
    if not anchor then return end
    local title = "Report a Living Fellows bug"
    local width = math.max(anchor:getWidth(), getTextManager():MeasureStringX(UIFont.Small, title) + 44)
    local item = button(screen, anchor:getRight() - width, anchor:getY() - anchor:getHeight() - 10,
        width, anchor:getHeight(), title, showForm)
    item:setAnchorLeft(false)
    item:setAnchorTop(false)
    item:setAnchorRight(true)
    item:setAnchorBottom(true)
    screen.lfBugReportButton = item
    local setVisible = screen.bottomPanel.setVisible
    screen.bottomPanel.setVisible = function(panel, visible)
        setVisible(panel, visible)
        item:setVisible(visible)
    end
    item:setVisible(screen.bottomPanel:isVisible())
    local onJoypadDown = screen.onJoypadDown
    screen.onJoypadDown = function(menu, key, joypad)
        if key == Joypad.YButton and item:isVisible() then item:forceClick(); return end
        return onJoypadDown(menu, key, joypad)
    end
    local render = item.prerender
    item.prerender = function(control)
        if screen.joyfocus then control:setJoypadButton(Joypad.Texture.YButton) else control:clearJoypadButton() end
        render(control)
    end
end

return UI
