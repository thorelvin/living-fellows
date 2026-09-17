-- SPDX-License-Identifier: MIT
--
-- Read-only private diary reader. The reader is bound to the physical book:
-- it is offered only from the item's own inventory context menu, so reading
-- needs ordinary access to wherever the book is (a pack, storage, a corpse).
-- It renders the book's stored plain text line by line; it never generates,
-- rerolls or rewrites a page, grants no XP and changes no relationship.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.DiaryUI = SC.DiaryUI or {}
local DiaryUI = SC.DiaryUI

local FONTS = { "Small", "Medium", "Large" }
local bookmarks = {}
local fontChoice = 1
local privacyAcknowledged = {}

local function text(key, fallback, ...)
    local utility = SC.GameplayUtil
    if utility and type(utility.text) == "function" then return utility.text(key, fallback, ...) end
    return fallback
end

local function font(index)
    return UIFont[FONTS[index] or "Small"] or UIFont.Small
end

local function measure(fontValue, value)
    local ok, width = pcall(function() return getTextManager():MeasureStringX(fontValue, value) end)
    return ok and tonumber(width) or #tostring(value) * 8
end

local function fontHeight(fontValue)
    local ok, height = pcall(function() return getTextManager():getFontHeight(fontValue) end)
    return ok and tonumber(height) or 16
end

local function wrap(value, maximumWidth, fontValue)
    local result, line = {}, ""
    for word in string.gmatch(tostring(value or ""), "%S+") do
        local candidate = line == "" and word or line .. " " .. word
        if line ~= "" and measure(fontValue, candidate) > maximumWidth then
            result[#result + 1], line = line, word
        else
            line = candidate
        end
    end
    if line ~= "" then result[#result + 1] = line end
    return result
end

local SCDiaryReader = ISPanel:derive("SCDiaryReader")

function SCDiaryReader:new(item, payload)
    local core = getCore and getCore() or nil
    local screenWidth = core and tonumber(core:getScreenWidth()) or 1280
    local screenHeight = core and tonumber(core:getScreenHeight()) or 720
    local width = math.min(560, screenWidth - 32)
    local height = math.min(640, screenHeight - 32)
    local object = ISPanel.new(self, math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2), width, height)
    object.item, object.payload = item, payload
    object.moveWithMouse = true
    object.background = false
    object.scroll = bookmarks[payload.diaryId] or 0
    object.lines = {}
    return object
end

function SCDiaryReader:layout()
    local body, heading = font(fontChoice), font(math.min(#FONTS, fontChoice + 1))
    local bodyHeight, headingHeight = fontHeight(body), fontHeight(heading)
    local width = self:getWidth() - 48
    local lines = {}
    if #self.payload.entries == 0 then
        lines[#lines + 1] = { text = text("UI_SC_Diary_Empty", "The pages are still blank."),
            font = body, height = bodyHeight, muted = true }
    end
    for index, entry in ipairs(self.payload.entries) do
        local dateLabel, passage = SC.DiaryItem.parseEntry(entry)
        if index > 1 then lines[#lines + 1] = { gap = true, height = bodyHeight } end
        lines[#lines + 1] = { text = dateLabel or "", font = heading, height = headingHeight + 4,
            heading = true }
        for paragraph in string.gmatch((passage or "") .. "\n", "([^\n]*)\n") do
            if paragraph == "" then
                lines[#lines + 1] = { gap = true, height = math.floor(bodyHeight / 2) }
            else
                for _, line in ipairs(wrap(paragraph, width, body)) do
                    lines[#lines + 1] = { text = line, font = body, height = bodyHeight + 2 }
                end
            end
        end
    end
    local total = 0
    for _, line in ipairs(lines) do total = total + line.height end
    self.lines, self.contentHeight = lines, total
    self:clampScroll()
end

function SCDiaryReader:viewTop() return 58 end
function SCDiaryReader:viewHeight() return self:getHeight() - 58 - 56 end

function SCDiaryReader:clampScroll()
    local maximum = math.max(0, (self.contentHeight or 0) - self:viewHeight())
    self.scroll = math.max(0, math.min(maximum, self.scroll or 0))
    bookmarks[self.payload.diaryId] = self.scroll
end

function SCDiaryReader:createChildren()
    ISPanel.createChildren(self)
    local y, h = self:getHeight() - 42, 28
    local function button(x, width, label, action)
        local value = ISButton:new(x, y, width, h, label, self, SCDiaryReader.onButton)
        value.scAction = action
        value:initialise()
        value:instantiate()
        self:addChild(value)
        return value
    end
    button(18, 44, text("UI_SC_Diary_TextSmaller", "A-"), "smaller")
    button(68, 44, text("UI_SC_Diary_TextLarger", "A+"), "larger")
    button(128, 88, text("UI_SC_Diary_PageUp", "Page up"), "up")
    button(222, 88, text("UI_SC_Diary_PageDown", "Page down"), "down")
    button(self:getWidth() - 110, 92, text("UI_SC_Diary_Close", "Close"), "close")
    self:layout()
end

function SCDiaryReader:onButton(button)
    local action = button.scAction
    if action == "close" then return self:close() end
    if action == "smaller" then fontChoice = math.max(1, fontChoice - 1); self:layout() end
    if action == "larger" then fontChoice = math.min(#FONTS, fontChoice + 1); self:layout() end
    if action == "up" then self.scroll = self.scroll - self:viewHeight() * 0.85; self:clampScroll() end
    if action == "down" then self.scroll = self.scroll + self:viewHeight() * 0.85; self:clampScroll() end
end

function SCDiaryReader:onMouseWheel(delta)
    self.scroll = (self.scroll or 0) + (tonumber(delta) or 0) * 48
    self:clampScroll()
    return true
end

function SCDiaryReader:close()
    bookmarks[self.payload.diaryId] = self.scroll
    self:setVisible(false)
    self:removeFromUIManager()
    if DiaryUI.reader == self then DiaryUI.reader = nil end
end

function SCDiaryReader:prerender()
    ISPanel.prerender(self)
    local width, height = self:getWidth(), self:getHeight()
    self:drawRect(0, 0, width, height, 0.97, 0.13, 0.11, 0.09)
    self:drawRectBorder(0, 0, width, height, 0.95, 0.52, 0.44, 0.31)
    local title = SC.DiaryItem.displayName(self.payload.authorName)
    self:drawText(title, 24, 16, 0.95, 0.89, 0.74, 1, UIFont.Medium)
    self:drawRect(24, 46, width - 48, 1, 0.6, 0.52, 0.44, 0.31)
    local top, bottom = self:viewTop(), self:viewTop() + self:viewHeight()
    local y = top - (self.scroll or 0)
    for _, line in ipairs(self.lines or {}) do
        if y >= top and y + line.height <= bottom and not line.gap then
            if line.heading then
                self:drawText(line.text, 24, y, 0.93, 0.78, 0.50, 1, line.font)
            elseif line.muted then
                self:drawText(line.text, 24, y, 0.62, 0.60, 0.56, 1, line.font)
            else
                self:drawText(line.text, 24, y, 0.90, 0.88, 0.83, 1, line.font)
            end
        end
        y = y + line.height
        if y > bottom then break end
    end
    local maximum = math.max(0, (self.contentHeight or 0) - self:viewHeight())
    if maximum > 0 then
        local track = self:viewHeight()
        local thumb = math.max(24, track * self:viewHeight() / self.contentHeight)
        local offset = (track - thumb) * ((self.scroll or 0) / maximum)
        self:drawRect(width - 12, top, 4, track, 0.35, 0.52, 0.44, 0.31)
        self:drawRect(width - 12, top + offset, 4, thumb, 0.9, 0.80, 0.66, 0.42)
    end
end

local function open(item)
    local payload = SC.DiaryItem.read(item)
    if not payload then return false end
    if DiaryUI.reader then DiaryUI.reader:close() end
    local reader = SCDiaryReader:new(item, payload)
    reader:initialise()
    reader:addToUIManager()
    if type(reader.setAlwaysOnTop) == "function" then reader:setAlwaysOnTop(true) end
    DiaryUI.reader = reader
    return true
end

local function privacyAnswer(request, answer)
    if answer and answer.internal == "YES" and request then
        privacyAcknowledged[request.diaryId] = true
        open(request.item)
    end
end

-- A living author's diary is still private. Reading it is allowed after one
-- explicit confirmation per book per session; no one in the world is told.
function DiaryUI.read(item)
    local payload = SC.DiaryItem.read(item)
    if not payload then return false end
    local alive = SC.Diary and type(SC.Diary.authorAlive) == "function"
        and SC.Diary.authorAlive(payload.authorId) == true
    if alive and privacyAcknowledged[payload.diaryId] ~= true and ISModalDialog then
        local modal = ISModalDialog:new(0, 0, 380, 160,
            text("UI_SC_Diary_PrivacyPrompt",
                payload.authorName .. " is still alive, and this diary is private. Read it anyway?",
                payload.authorName),
            true, { diaryId = payload.diaryId, item = item }, privacyAnswer, nil)
        modal:initialise()
        modal.moveWithMouse = true
        modal:addToUIManager()
        if type(modal.setAlwaysOnTop) == "function" then modal:setAlwaysOnTop(true) end
        return true
    end
    return open(item)
end

local function onReadOption(item)
    local ok, reason = pcall(DiaryUI.read, item)
    if not ok and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        SC.Diagnostics.report("diary-ui", nil, "diary reader failed", reason)
    end
end

function DiaryUI.fillInventoryContextMenu(playerIndex, context, items)
    if type(items) ~= "table" or context == nil or not SC.DiaryItem then return end
    for _, entry in ipairs(items) do
        local item = entry
        if type(entry) == "table" and type(entry.items) == "table" then item = entry.items[1] end
        if item ~= nil and SC.DiaryItem.hasPayload(item) then
            local payload = SC.DiaryItem.read(item)
            if payload then
                context:addOption(text("UI_SC_Diary_Read", "Read " .. SC.DiaryItem.displayName(payload.authorName),
                    SC.DiaryItem.displayName(payload.authorName)), item, onReadOption)
            else
                local option = context:addOption(text("UI_SC_Diary_Unreadable",
                    "The pages of this diary cannot be read."), nil, nil)
                if option then option.notAvailable = true end
            end
            return
        end
    end
end

function DiaryUI.install()
    if DiaryUI._installed then return true end
    if Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(DiaryUI.fillInventoryContextMenu)
        DiaryUI._installed = true
    end
    return DiaryUI._installed == true
end

function DiaryUI.remove()
    if not DiaryUI._installed then return true end
    if Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Remove(DiaryUI.fillInventoryContextMenu)
    end
    DiaryUI._installed = false
    return true
end

DiaryUI.install()

return DiaryUI
