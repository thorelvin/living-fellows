-- SPDX-License-Identifier: MIT

-- Camp computers. Right-click a powered desktop computer, choose "Use
-- computer", and the player walks over and sits down at EMMA: a green-screen
-- terminal that answers plain English about the camp (SCTerminalBrain) from
-- live facts (SCTerminalWorld). Nothing leaves the game; there is no network.
--
-- The window owns no tick: the UI manager's per-frame update animates the
-- thinking pause and the typewriter, and checks every half second that the
-- player is still at the keyboard and the power is still on. EMMA's memory
-- of an operator (name, notes, last visit) lives in the computer's own mod
-- data, bounded and normalized on every read.

require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"
require "TimedActions/ISBaseTimedAction"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion

SC.Terminal = SC.Terminal or {}
local Terminal = SC.Terminal

Terminal.USE_DISTANCE = 2.5
Terminal.CHARS_PER_SECOND = 140
Terminal.BOOT_CHARS_PER_SECOND = 420
Terminal.SCROLLBACK_ROWS = 400
Terminal.HISTORY = 30
Terminal.WATCH_MS = 500
Terminal.MEMORY_KEY = "LF_Emma"
Terminal.SESSIONS = 16

local sessions, sessionOrder = {}, {}

local function U() return SC.GameplayUtil end
local function Brain() return SC.TerminalBrain end
local function World() return SC.TerminalWorld end
local function Lines() return SC.TerminalLines end

local function call(object, method, ...)
    if object == nil then return nil end
    local value, ok = U().call(object, method, ...)
    if ok then return value end
    return nil
end

local function text(key, fallback)
    return U().text(key, fallback)
end

local function nowMs()
    if Terminal._clock then return Terminal._clock() end
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function diagnostic(message, detail)
    if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
        pcall(SC.Diagnostics.report, "terminal", nil, message, detail)
    end
end

-- ---------------------------------------------------------------------------
-- Which objects are computers, and whether one can be used
-- ---------------------------------------------------------------------------

function Terminal.isComputer(object)
    if object == nil then return false end
    local properties = call(object, "getProperties")
    if properties == nil then
        properties = call(call(object, "getSprite"), "getProperties")
    end
    return properties ~= nil and call(properties, "get", "CustomName") == "Computer"
end

function Terminal.findComputer(worldObjects)
    local checked = 0
    for _, object in ipairs(worldObjects or {}) do
        if Terminal.isComputer(object) then return object end
        local square = call(object, "getSquare")
        local objects = square and call(square, "getObjects")
        local size = objects and tonumber(call(objects, "size")) or 0
        for index = 0, math.min(size, 16) - 1 do
            checked = checked + 1
            local candidate = call(objects, "get", index)
            if Terminal.isComputer(candidate) then return candidate end
        end
        if checked >= 48 then break end
    end
    return nil
end

function Terminal.present(object)
    return object ~= nil and call(object, "getSquare") ~= nil
        and (tonumber(call(object, "getObjectIndex")) or -1) >= 0
end

function Terminal.powered(object)
    return Terminal.present(object) and World().powered(call(object, "getSquare")) == true
end

function Terminal.near(player, object)
    local square = call(object, "getSquare")
    if not player or not square then return false end
    local x, y, z = U().position(player)
    local sx, sy, sz = call(square, "getX"), call(square, "getY"), call(square, "getZ")
    if x == nil or sx == nil or math.floor(z or 0) ~= math.floor(sz or 0) then return false end
    local dx, dy = x - (sx + 0.5), y - (sy + 0.5)
    return dx * dx + dy * dy <= Terminal.USE_DISTANCE * Terminal.USE_DISTANCE
end

-- ---------------------------------------------------------------------------
-- Memory kept in the computer's mod data
-- ---------------------------------------------------------------------------

local function computerKey(object)
    local square = call(object, "getSquare")
    if not square then return nil end
    return tostring(call(square, "getX")) .. "," .. tostring(call(square, "getY"))
        .. "," .. tostring(call(square, "getZ"))
end

function Terminal.readMemory(object)
    local data = call(object, "getModData")
    return Brain().normalizeMemory(type(data) == "table" and data[Terminal.MEMORY_KEY] or nil)
end

function Terminal.writeMemory(object, session, worldHours)
    local data = call(object, "getModData")
    if type(data) ~= "table" then return false end
    local memory = Brain().exportMemory(session, worldHours)
    data[Terminal.MEMORY_KEY] = {
        operator = memory.operator, notes = memory.notes,
        lastSeen = memory.lastSeen, visits = memory.visits,
    }
    return true
end

local function operatorName(player)
    local descriptor = call(player, "getDescriptor")
    local forename = descriptor and call(descriptor, "getForename")
    return type(forename) == "string" and forename ~= "" and forename or "operator"
end

-- One session per computer while the game runs, so EMMA keeps the thread of
-- a conversation across a quick trip to the shelves. Bounded; oldest drops.
function Terminal.sessionFor(player, object)
    local key = computerKey(object) or "unknown"
    local session = sessions[key]
    if session then return session end
    session = Brain().newSession({ operator = operatorName(player),
        memory = Terminal.readMemory(object) })
    sessions[key] = session
    sessionOrder[#sessionOrder + 1] = key
    while #sessionOrder > Terminal.SESSIONS do
        sessions[table.remove(sessionOrder, 1)] = nil
    end
    return session
end

function Terminal.resetSessions()
    sessions, sessionOrder = {}, {}
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    return tonumber(call(getGameTime(), "getWorldAgeHours"))
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local COLORS = {
    background = { 0.97, 0.015, 0.045, 0.025 },
    border = { 0.75, 0.20, 0.75, 0.32 },
    title = { 0.95, 0.45, 0.95, 0.55 },
    emma = { 1.0, 0.40, 1.0, 0.50 },
    input = { 1.0, 0.85, 1.0, 0.85 },
    system = { 1.0, 0.25, 0.70, 0.35 },
    alert = { 1.0, 1.0, 0.55, 0.30 },
}

local function terminalFont()
    return UIFont.Code or UIFont.Small
end

local function fontHeight(font)
    local ok, value = pcall(function() return getTextManager():getFontHeight(font) end)
    return ok and tonumber(value) or 16
end

local function charWidth(font)
    local ok, value = pcall(function() return getTextManager():MeasureStringX(font, "MMMMMMMMMM") end)
    local width = ok and tonumber(value) or 80
    return math.max(4, width / 10)
end

-- Hard wrap for a fixed-width font: words where possible, long words split.
function Terminal.wrap(value, columns)
    columns = math.max(8, math.floor(columns or 80))
    local rows = {}
    for paragraph in string.gmatch(tostring(value or "") .. "\n", "([^\n]*)\n") do
        if paragraph == "" then
            rows[#rows + 1] = ""
        else
            local indent = string.match(paragraph, "^(%s*)") or ""
            local line = ""
            for word in string.gmatch(paragraph, "%S+") do
                while #word > columns do
                    if line ~= "" then rows[#rows + 1] = line line = "" end
                    rows[#rows + 1] = string.sub(word, 1, columns)
                    word = string.sub(word, columns + 1)
                end
                local candidate = line == "" and (indent .. word) or (line .. " " .. word)
                if #candidate > columns and line ~= "" then
                    rows[#rows + 1] = line
                    line = indent .. word
                else
                    line = candidate
                end
            end
            if line ~= "" then rows[#rows + 1] = line end
        end
    end
    return rows
end

local SCTerminalWindow = ISPanel:derive("SCTerminalWindow")
Terminal.Window = SCTerminalWindow

function SCTerminalWindow:new(player, object)
    local core = getCore and getCore() or nil
    local screenWidth = core and tonumber(core:getScreenWidth()) or 1280
    local screenHeight = core and tonumber(core:getScreenHeight()) or 720
    local width = math.min(780, screenWidth - 32)
    local height = math.min(500, screenHeight - 32)
    local window = ISPanel.new(self, math.floor((screenWidth - width) / 2),
        math.floor((screenHeight - height) / 2), width, height)
    window.player, window.object = player, object
    window.square = call(object, "getSquare")
    window.moveWithMouse = true
    window.background = false
    window.font = terminalFont()
    window.rowHeight = fontHeight(window.font) + 2
    window.charWidth = charWidth(window.font)
    window.rows = {}
    window.queue = {}
    window.history = {}
    window.scroll = 0
    window.state = "idle"
    window.lastWatch = 0
    window.lastFrame = nowMs()
    return window
end

function SCTerminalWindow:columns()
    return math.floor((self:getWidth() - 36) / self.charWidth)
end

function SCTerminalWindow:viewTop() return 34 end
function SCTerminalWindow:viewBottom() return self:getHeight() - self.rowHeight - 26 end

function SCTerminalWindow:visibleRows()
    return math.max(1, math.floor((self:viewBottom() - self:viewTop()) / self.rowHeight))
end

function SCTerminalWindow:createChildren()
    ISPanel.createChildren(self)
    local close = ISButton:new(self:getWidth() - 30, 6, 22, 20, "X", self, SCTerminalWindow.onClose)
    close:initialise()
    close:instantiate()
    close.borderColor = { r = 0.2, g = 0.75, b = 0.32, a = 0.8 }
    close.backgroundColor = { r = 0, g = 0.1, b = 0.04, a = 0.9 }
    close.textColor = { r = 0.45, g = 0.95, b = 0.55, a = 1 }
    self:addChild(close)
    local height = self.rowHeight + 6
    local entry = ISTextEntryBox:new("", 12, self:getHeight() - height - 10, self:getWidth() - 24, height)
    entry.font = self.font
    entry:initialise()
    entry:instantiate()
    entry.backgroundColor = { r = 0, g = 0.06, b = 0.02, a = 1 }
    entry.borderColor = { r = 0.2, g = 0.75, b = 0.32, a = 0.6 }
    pcall(function() entry:setTextRGBA(0.85, 1.0, 0.85, 1) end)
    pcall(function() entry:setMaxTextLength(Brain().MAX_INPUT) end)
    pcall(function() entry:setPlaceholderText(text("UI_SC_Terminal_Placeholder",
        "Type to EMMA. Enter sends, Esc leaves.")) end)
    entry.terminal = self
    entry.onCommandEntered = function(box) box.terminal:submit() end
    entry.onPressUp = function(box) box.terminal:recall(1) end
    entry.onPressDown = function(box) box.terminal:recall(-1) end
    entry.onOtherKey = function(box, key) box.terminal:otherKey(key) end
    self:addChild(entry)
    self.entry = entry
end

function SCTerminalWindow:onClose()
    self:close()
end

function SCTerminalWindow:otherKey(key)
    if type(Keyboard) ~= "table" then return end
    if key == Keyboard.KEY_ESCAPE then return self:close() end
    if key == Keyboard.KEY_PRIOR then self:scrollBy(self:visibleRows() - 2) end
    if key == Keyboard.KEY_NEXT then self:scrollBy(-(self:visibleRows() - 2)) end
end

function SCTerminalWindow:scrollBy(rows)
    local maximum = math.max(0, #self.rows - self:visibleRows())
    self.scroll = math.max(0, math.min(maximum, self.scroll + rows))
end

function SCTerminalWindow:onMouseWheel(delta)
    self:scrollBy(-(tonumber(delta) or 0) * 3)
    return true
end

function SCTerminalWindow:onMouseDown(x, y)
    ISPanel.onMouseDown(self, x, y)
    if self.entry then pcall(function() self.entry:focus() end) end
    return true
end

function SCTerminalWindow:pushRow(value, kind)
    self.rows[#self.rows + 1] = { text = value, kind = kind or "emma" }
    while #self.rows > Terminal.SCROLLBACK_ROWS do table.remove(self.rows, 1) end
    self.scroll = 0
end

function SCTerminalWindow:print(value, kind)
    for _, row in ipairs(Terminal.wrap(value, self:columns())) do self:pushRow(row, kind) end
end

-- Queue text for the typewriter.
function SCTerminalWindow:enqueue(lines, kind, speed)
    for _, line in ipairs(lines) do
        for _, row in ipairs(Terminal.wrap(line, self:columns())) do
            self.queue[#self.queue + 1] = { text = row, kind = kind or "emma",
                speed = speed or Terminal.CHARS_PER_SECOND }
        end
    end
end

function SCTerminalWindow:startReply(reply)
    self.pendingCommand = reply.command
    local lines = {}
    for _, line in ipairs(reply.lines or {}) do lines[#lines + 1] = line end
    if #lines > 0 then lines[#lines + 1] = "" end
    local speed = #lines > 12 and Terminal.CHARS_PER_SECOND * 3 or Terminal.CHARS_PER_SECOND
    self:enqueue(lines, "emma", speed)
    local wait = tonumber(reply.thinkMs) or 0
    if wait > 0 then
        self.state = "thinking"
        self.thinkStart, self.thinkEnd = nowMs(), nowMs() + wait
        self.thinkSteps = reply.think or {}
    else
        self.state = "typing"
    end
end

function SCTerminalWindow:boot()
    self.session = Terminal.sessionFor(self.player, self.object)
    self.world = World().new(self.player, self.object)
    local reply = Brain().boot(self.session, self.world)
    Terminal.writeMemory(self.object, self.session, worldHours())
    local lines = reply.lines or {}
    local count = #(Lines().BOOT or {})
    local bootLines, greeting = {}, {}
    for index, line in ipairs(lines) do
        if index <= count then bootLines[#bootLines + 1] = line else greeting[#greeting + 1] = line end
    end
    self:enqueue(bootLines, "system", Terminal.BOOT_CHARS_PER_SECOND)
    if #greeting > 0 then greeting[#greeting + 1] = "" end
    self:enqueue(greeting, "emma", Terminal.CHARS_PER_SECOND)
    self.state = "typing"
end

function SCTerminalWindow:flush()
    if self.typing then
        self:pushRow(self.typing.text, self.typing.kind)
        self.typing = nil
    end
    for _, row in ipairs(self.queue) do self:pushRow(row.text, row.kind) end
    self.queue = {}
    self.state = "idle"
    self:finishCommand()
end

function SCTerminalWindow:finishCommand()
    local command = self.pendingCommand
    self.pendingCommand = nil
    if command == "close" then
        self.closeAt = nowMs() + 900
    end
end

function SCTerminalWindow:submit()
    local raw = self.entry and self.entry:getText() or ""
    if self.entry then self.entry:setText("") end
    if self.state == "closing" then return end
    -- Enter while EMMA is still talking skips to the end of her reply.
    if self.state ~= "idle" then
        self:flush()
        if string.find(raw, "^%s*$") then return end
    end
    if not string.find(raw, "^%s*$") then
        table.insert(self.history, 1, raw)
        while #self.history > Terminal.HISTORY do table.remove(self.history) end
    end
    self.historyIndex = nil
    self:print("> " .. raw, "input")
    local ok, reply = pcall(Brain().respond, self.session, raw, self.world)
    if not ok then
        diagnostic("terminal reply failed", reply)
        reply = { lines = { "[SYSTEM ERROR] Please try again." }, thinkMs = 0 }
    end
    if reply.memoryChanged then Terminal.writeMemory(self.object, self.session, worldHours()) end
    if reply.command == "clear" then
        self.rows, self.scroll = {}, 0
        return
    end
    self:startReply(reply)
end

function SCTerminalWindow:recall(direction)
    if #self.history == 0 or not self.entry then return end
    local index = (self.historyIndex or 0) + direction
    if index < 1 then
        self.historyIndex = nil
        self.entry:setText("")
        return
    end
    index = math.min(index, #self.history)
    self.historyIndex = index
    self.entry:setText(self.history[index])
end

-- Leave the window. A power failure leaves the warning on screen briefly.
function SCTerminalWindow:close()
    if self.closed then return end
    self.closed = true
    -- Hand the keyboard back to the game before the prompt disappears.
    if self.entry then pcall(function() self.entry:unfocus() end) end
    if self.session then
        pcall(Terminal.writeMemory, self.object, self.session, worldHours())
    end
    self:setVisible(false)
    self:removeFromUIManager()
    if Terminal.window == self then Terminal.window = nil end
end

function SCTerminalWindow:watch(now)
    if now - self.lastWatch < Terminal.WATCH_MS then return end
    self.lastWatch = now
    if self.state == "closing" then return end
    if not Terminal.present(self.object) or not Terminal.near(self.player, self.object)
        or call(self.player, "isDead") == true then
        return self:close()
    end
    if not Terminal.powered(self.object) then
        self:flush()
        self:print(Lines().T.power_failure, "alert")
        self.state = "closing"
        self.closeAt = now + 1500
    end
end

function SCTerminalWindow:advance(now)
    local elapsed = math.max(0, math.min(250, now - (self.lastFrame or now)))
    self.lastFrame = now
    if self.state == "thinking" and now >= (self.thinkEnd or 0) then self.state = "typing" end
    if self.state ~= "typing" then return end
    if not self.typing then
        if #self.queue == 0 then
            self.state = "idle"
            return self:finishCommand()
        end
        self.typing = table.remove(self.queue, 1)
        self.typing.shown = 0
    end
    local row = self.typing
    row.shown = row.shown + row.speed * elapsed / 1000
    if row.shown >= #row.text then
        self:pushRow(row.text, row.kind)
        self.typing = nil
    end
end

function SCTerminalWindow:update()
    ISPanel.update(self)
    if self.closed then return end
    local now = nowMs()
    self:watch(now)
    if self.closed then return end
    if self.closeAt and now >= self.closeAt then return self:close() end
    self:advance(now)
end

local SPINNER = { "|", "/", "-", "\\" }

function SCTerminalWindow:drawRow(value, y, kind)
    local color = COLORS[kind] or COLORS.emma
    self:drawText(value, 18, y, color[2], color[3], color[4], color[1], self.font)
end

function SCTerminalWindow:prerender()
    local width, height = self:getWidth(), self:getHeight()
    local background, border, title = COLORS.background, COLORS.border, COLORS.title
    self:drawRect(0, 0, width, height, background[1], background[2], background[3], background[4])
    self:drawRectBorder(0, 0, width, height, border[1], border[2], border[3], border[4])
    self:drawText(Lines().TITLE, 14, 8, title[2], title[3], title[4], title[1], UIFont.Small)
    self:drawRect(10, 29, width - 20, 1, 0.5, 0.2, 0.75, 0.32)
    local top, bottom = self:viewTop(), self:viewBottom()
    local now = nowMs()
    local extra = {}
    if self.typing then
        local shown = math.floor(self.typing.shown or 0)
        local cursor = math.floor(now / 400) % 2 == 0 and "_" or " "
        extra[#extra + 1] = { text = string.sub(self.typing.text, 1, shown) .. cursor, kind = self.typing.kind }
    elseif self.state == "thinking" then
        local steps = self.thinkSteps or {}
        local span = math.max(1, (self.thinkEnd or now) - (self.thinkStart or now))
        local step = steps[math.min(#steps, math.floor((now - (self.thinkStart or now)) / span * #steps) + 1)]
        local dots = string.rep(".", math.floor(now / 300) % 4)
        extra[#extra + 1] = { text = SPINNER[math.floor(now / 120) % 4 + 1] .. " " .. tostring(step or "Thinking") .. dots,
            kind = "system" }
    elseif self.state == "idle" and #self.rows == 0 then
        extra[#extra + 1] = { text = math.floor(now / 500) % 2 == 0 and "_" or " ", kind = "emma" }
    end
    local visible = self:visibleRows()
    local total = #self.rows + #extra
    local last = total - self.scroll
    local first = math.max(1, last - visible + 1)
    local y = top
    for index = first, last do
        local row = index <= #self.rows and self.rows[index] or extra[index - #self.rows]
        if row and y + self.rowHeight <= bottom + 2 then self:drawRow(row.text, y, row.kind) end
        y = y + self.rowHeight
    end
    -- Faint scanlines, for the phosphor.
    for line = top, bottom, 3 do
        self:drawRect(1, line, width - 2, 1, 0.08, 0, 0, 0)
    end
    if self.scroll > 0 then
        self:drawText("-- more below --", width - 140, bottom - self.rowHeight + 2,
            0.2, 0.75, 0.32, 0.9, UIFont.Small)
    end
end

-- ---------------------------------------------------------------------------
-- Opening, the timed action and the context menu
-- ---------------------------------------------------------------------------

function Terminal.open(player, object)
    if not Terminal.powered(object) then return false, "no_power" end
    if Terminal.window then Terminal.window:close() end
    local window = SCTerminalWindow:new(player, object)
    window:initialise()
    window:addToUIManager()
    if type(window.setAlwaysOnTop) == "function" then window:setAlwaysOnTop(true) end
    Terminal.window = window
    local ok, failure = pcall(function() window:boot() end)
    if not ok then
        diagnostic("terminal boot failed", failure)
        window:close()
        return false, "boot_failed"
    end
    if window.entry then pcall(function() window.entry:focus() end) end
    return true
end

SCUseTerminalAction = ISBaseTimedAction:derive("SCUseTerminalAction")

function SCUseTerminalAction:isValid()
    return Terminal.powered(self.object)
end

function SCUseTerminalAction:waitToStart()
    pcall(function() self.character:faceThisObject(self.object) end)
    return self.character:shouldBeTurning()
end

function SCUseTerminalAction:update()
    pcall(function() self.character:faceThisObject(self.object) end)
end

function SCUseTerminalAction:start()
    pcall(function() self:setActionAnim("Loot") end)
    pcall(function() self.character:SetVariable("LootPosition", "Mid") end)
end

function SCUseTerminalAction:perform()
    local ok, failure = pcall(Terminal.open, self.character, self.object)
    if not ok then diagnostic("terminal open failed", failure) end
    ISBaseTimedAction.perform(self)
end

function SCUseTerminalAction:new(character, object)
    local action = ISBaseTimedAction.new(self, character)
    action.object = object
    action.maxTime = 30
    action.stopOnWalk = true
    action.stopOnRun = true
    return action
end

function Terminal.use(player, object)
    if not player or not Terminal.powered(object) then return false, "no_power" end
    if type(ISTimedActionQueue) ~= "table" or type(luautils) ~= "table" then
        return false, "timed_actions_unavailable"
    end
    if not Terminal.near(player, object) then
        local square = call(object, "getSquare")
        if not square or not luautils.walkAdj(player, square) then return false, "unreachable" end
    end
    ISTimedActionQueue.add(SCUseTerminalAction:new(player, object))
    return true
end

function Terminal.onUseOption(player, object)
    local ok, failure = pcall(Terminal.use, player, object)
    if not ok then diagnostic("terminal use failed", failure) end
end

-- Called from SCUIContext's world-object menu. Only the keyboard player in a
-- single-player game sits at a terminal.
function Terminal.fillWorldObjectContextMenu(playerIndex, context, worldObjects, player)
    if context == nil or player == nil or playerIndex ~= 0 then return false end
    local computer = Terminal.findComputer(worldObjects)
    if not computer then return false end
    local option = context:addOption(text("UI_SC_Terminal_Use", "Use computer"), player,
        Terminal.onUseOption, computer)
    if option and not Terminal.powered(computer) then
        option.notAvailable = true
        if ISWorldObjectContextMenu and type(ISWorldObjectContextMenu.addToolTip) == "function" then
            local tooltip = ISWorldObjectContextMenu.addToolTip()
            tooltip.description = text("UI_SC_Terminal_NoPower",
                "The screen is dark. This computer has no power.")
            option.toolTip = tooltip
        end
    end
    return true
end

return Terminal
