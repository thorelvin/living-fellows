-- SPDX-License-Identifier: MIT
require "SCActionFeedback"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UIAttention = SC.UIAttention or {}
local A = SC.UIAttention
local rows, nextAt, banner, currentSignature = {}, 0, nil, ""
local function text(key, fallback, ...) return SC.ActionFeedback.text(key, fallback, ...) end
local function clock() return SC.GameplayUtil and SC.GameplayUtil.nowMs() or 0 end
local function player() return type(getSpecificPlayer) == "function" and getSpecificPlayer(0) or nil end

function A.update(force)
    local current = clock()
    if not force and current < nextAt then return rows end
    nextAt = current + 1000
    local updated = {}
    local summary = SC.InfectionCrisis and SC.InfectionCrisis.summary(player()) or { rows = {} }
    for _, row in ipairs(summary.rows or {}) do
        updated[#updated + 1] = { id = row.id, subjectId = row.subjectId, crisis = row,
            title = row.subjectName or row.subjectId, body = SC.ActionFeedback.crisis(row),
            urgent = row.urgent, unread = row.unread,
            revision = row.noticeRevision or 0 }
    end
    -- Job records are retained domain state. Do not call the camp stock/operation
    -- summary here: opening a notification must never scan storage or the world.
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    local settings = SC.UI and SC.UI.getSettings and SC.UI.getSettings() or {}
    local acknowledged, retained = settings.attentionAcknowledged or {}, {}
    local count = 0
    for _, job in ipairs(base and base.jobs or {}) do
        if count >= 32 then break end
        if job.state == "blocked" and (job.autoRetry == false
            or SC.BaseLife.jobParked and SC.BaseLife.jobParked(job)) then
            count = count + 1
            local revision = tostring(job.blocker or "unknown") .. ":" .. tostring(job.attempts or 0)
            local id = "job:" .. tostring(job.id)
            local reason = SC.ActionFeedback.reason(job.blocker)
            updated[#updated + 1] = { id = id, jobId = job.id,
                subjectId = job.reservedBy or job.assignedId,
                title = SC.UI and SC.UI.stateText(job.type) or text("work", "Camp work"),
                body = SC.ActionFeedback.describe(reason), revision = revision,
                urgent = false,
                unread = acknowledged[id] ~= revision }
            retained[id] = acknowledged[id]
        end
    end
    settings.attentionAcknowledged = retained
    table.sort(updated, function(left, right)
        if left.urgent ~= right.urgent then return left.urgent == true end
        return tostring(left.id) < tostring(right.id)
    end)
    rows = updated
    local signature = {}
    for _, row in ipairs(rows) do
        signature[#signature + 1] = row.id .. ":" .. tostring(row.revision)
            .. ":" .. tostring(row.unread) .. ":" .. tostring(row.body)
    end
    currentSignature = table.concat(signature, "|")
    return rows
end

function A.signature() A.update(); return currentSignature end
function A.count() A.update(); return #rows end
function A.urgent()
    A.update()
    return rows[1] and rows[1].urgent == true or false
end
function A.bannerVisible() return banner ~= nil and banner:isVisible() end

local function review(_, button)
    local row = button.scAttention
    if row and SC.UI then SC.UI.reviewAttention(row) end
end
local function acknowledge(_, button)
    local row = button.scAttention
    if not row then return end
    if row.crisis then SC.InfectionCrisis.acknowledge(row.id, row.revision)
    else SC.UI.getSettings().attentionAcknowledged[row.id] = row.revision end
    A.update(true)
    SC.UI.refresh()
end

local function addButton(panel, label, callback, row, x, y, width, height)
    local button = ISButton:new(x, y, width, height, label, nil, callback)
    button:initialise()
    button.scAttention = row
    panel:addChild(button)
    return button
end

function A.build(detail, panel, y, selected)
    A.update()
    if #rows == 0 then return y end
    y = detail:addSection(panel, y, "UI_SC_Feedback_attention")
    local shown = 0
    for _, row in ipairs(rows) do
        if shown < 3 or selected and row.subjectId == selected.id then
            shown = shown + 1
            y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", row.title .. ": " .. row.body)
            local height = (detail.metrics or SC.UI.layoutMetrics()).buttonHeight
            local width = math.max(80, (panel:getWidth() - 32) / 2)
            addButton(panel, text("review", "Review"), review, row, 8, y, width, height)
            if row.unread then
                addButton(panel, text("acknowledge", "Acknowledge"), acknowledge, row, 16 + width, y, width, height)
            end
            y = y + height + 8
        end
    end
    return y + 4
end

function A.present(anchor)
    A.update()
    local item
    for _, row in ipairs(rows) do if row.unread then item = row; break end end
    if not item or not anchor:isVisible() then
        if banner then banner:setVisible(false) end
        return
    end
    if not banner then
        banner = ISPanel:new(0, 0, 300, 130)
        banner:initialise(); banner:instantiate(); banner:addToUIManager()
        banner:setAlwaysOnTop(true)
        banner.backgroundColor = { r = .10, g = .11, b = .10, a = .96 }
        banner.borderColor = { r = .85, g = .53, b = .23, a = .85 }
        banner.render = function(self)
            for index, line in ipairs(self.scLines or {}) do
                self:drawText(line, 10, 8 + (index - 1) * self.scLineHeight,
                    .95, .92, .85, 1, UIFont.Small)
            end
        end
        banner.scReview = addButton(banner, text("review", "Review"), review, item, 8, 90, 136, 28)
        banner.scAcknowledge = addButton(banner, text("acknowledge", "Acknowledge"), acknowledge, item, 152, 90, 140, 28)
    end
    local screen = getCore()
    local lineHeight = getTextManager():getFontHeight(UIFont.Small)
    local width = math.min(screen:getScreenWidth() - 24, math.max(300, math.floor(lineHeight * 18.75)))
    local key = currentSignature .. ":" .. width
    if banner.scKey ~= key then
        banner.scKey, banner.scLineHeight = key, lineHeight
        local title = item.title .. (#rows > 1 and ("  (+" .. tostring(#rows - 1) .. ")") or "")
        local lines = SC.UI.wrapText(UIFont.Small, title .. ": " .. item.body, width - 20)
        banner.scLines = {}
        for index = 1, math.min(4, #lines) do banner.scLines[index] = lines[index] end
        local top = 14 + #banner.scLines * lineHeight
        local height = math.max(28, lineHeight + 12)
        banner:setWidth(width); banner:setHeight(top + height + 8)
        for index, button in ipairs({ banner.scReview, banner.scAcknowledge }) do
            button:setY(top); button:setX(index == 1 and 8 or width / 2 + 4)
            button:setWidth(width / 2 - 12); button:setHeight(height)
            button.scAttention = item
        end
    end
    local side = anchor.dockSide or (anchor.root and anchor.root.dockSide) or "right"
    local x = side == "left" and anchor:getX() + anchor:getWidth() + 8 or anchor:getX() - width - 8
    banner:setX(math.max(6, math.min(screen:getScreenWidth() - width - 6, x)))
    banner:setY(math.max(6, math.min(screen:getScreenHeight() - banner:getHeight() - 6, anchor:getY())))
    banner:setVisible(true)
end

function A.reset()
    if banner then banner:removeFromUIManager() end
    banner, rows, nextAt, currentSignature = nil, {}, 0, ""
end
return A
