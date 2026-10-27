-- SPDX-License-Identifier: MIT

-- Camp computers. Right-click a powered desktop computer, choose "Use
-- computer", and the player faces EMMA's local terminal: a phosphor-screen
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
require "Moveables/ISMoveableSpriteProps"

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
Terminal.BOOT_SOUND = "LFTerminalBoot"
Terminal.MEMORY_KEY = "LF_Emma"
Terminal.SESSIONS = 16

local sessions, sessionOrder = {}, {}
local computerSerial = 0

local function U() return SC.GameplayUtil end
local function Brain() return SC.TerminalBrain end
local function World() return SC.TerminalWorld end
local function Lines() return SC.TerminalLines end
local function System() return SC.TerminalSystem end
local function Presentation() return SC.TerminalPresentation end

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
    for objectIndex, object in ipairs(worldObjects or {}) do
        if objectIndex > 48 then break end
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

-- A read-only eligibility check for ambient NPC use. A portable lock is never
-- bypassed, and the player's active window always takes precedence.
function Terminal.companionAvailable(object)
    if not Terminal.isComputer(object) or not Terminal.powered(object)
        or Terminal.window and Terminal.window.object == object then return false end
    local data = call(object, "getModData")
    local portable = type(data) == "table" and data.movableData
    if type(data) ~= "table" or portable ~= nil and type(portable) ~= "table" then return false end
    local stored
    if type(portable) == "table" then stored = portable[System().MEMORY_KEY] end
    if stored == nil then return true end
    local state = System().normalize(stored)
    return state ~= nil and state.locked ~= true
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

local function portableData(object, create)
    local data = call(object, "getModData")
    if type(data) ~= "table" then return nil end
    -- Vanilla furniture pickup/placement copies movableData, not arbitrary
    -- object mod data. Both the OS and EMMA travel with that native payload.
    if data.movableData == nil and create then data.movableData = {} end
    return type(data.movableData) == "table" and data.movableData or nil
end

function Terminal.readMemory(object)
    local data = call(object, "getModData")
    local portable = portableData(object, false)
    return Brain().normalizeMemory(portable and portable[Terminal.MEMORY_KEY]
        or (type(data) == "table" and data[Terminal.MEMORY_KEY] or nil))
end

function Terminal.writeMemory(object, session, worldHours)
    local data = call(object, "getModData")
    if type(data) ~= "table" then return false end
    local memory = Brain().exportMemory(session, worldHours)
    local portable = portableData(object, true)
    if not portable then return false end
    data[Terminal.MEMORY_KEY] = {
        operator = memory.operator, notes = memory.notes,
        lastSeen = memory.lastSeen, visits = memory.visits,
    }
    portable[Terminal.MEMORY_KEY] = data[Terminal.MEMORY_KEY]
    return true
end

function Terminal.computerState(player, object)
    local portable = portableData(object, true)
    if not portable then return nil, "Computer memory is unavailable." end
    local stored = portable[System().MEMORY_KEY]
    local state
    if stored ~= nil then
        state = System().normalize(stored)
        if not state then return nil, "Computer system record is unreadable." end
    else
        local legacy = Terminal.readMemory(object)
        if portable[Terminal.MEMORY_KEY] == nil
            and (legacy.operator ~= nil or (legacy.visits or 0) > 0 or #legacy.notes > 0) then
            portable[Terminal.MEMORY_KEY] = legacy
        end
        local provider = World().new(player, object)
        local okay, camp = pcall(provider.camp)
        local seed = type(ZombRand) == "function" and ZombRand(2147483646) + 1
            or math.random(1, 1000000)
        computerSerial = computerSerial + 1
        local brand=SC.TerminalBrands and SC.TerminalBrands.identify(object)
        state = System().create(seed, World().computerKind(object,brand),
            okay and type(camp) == "table" and camp.inside == true,
            legacy.visits ~= nil and legacy.visits > 0,
            "pc:" .. tostring(nowMs()) .. ":" .. seed .. ":" .. computerSerial,brand)
        state.brand=brand
    end
    if not state.brand and SC.TerminalBrands then state.brand = SC.TerminalBrands.identify(object) end
    if state.brand and state.paletteVersion ~= Presentation().PALETTE_VERSION then
        state.theme = Presentation().themeFor(state.seed, state.brand)
        state.paletteVersion = Presentation().PALETTE_VERSION
    end
    portable[System().MEMORY_KEY] = state
    return state
end

function Terminal.installMoveHook()
    local props = ISMoveableSpriteProps
    if type(props) ~= "table" or type(props.pickUpMoveableInternal) ~= "function" then
        return false, "moveable pickup interface unavailable"
    end
    if Terminal._moveHook and Terminal._moveHook.target == props then return true end
    local previous = props.pickUpMoveableInternal
    local wrapper = function(self, character, square, object, ...)
        -- No world scan and no furniture changes. Initialize before vanilla
        -- copies movableData, including pickup of an unpowered/unopened PC.
        if SurvivorCompanion == SC and SC.Terminal == Terminal and Terminal.isComputer(object) then
            local portable = portableData(object, false)
            if not portable or portable[System().MEMORY_KEY] == nil then
                local okay, state, reason = pcall(Terminal.computerState, character, object)
                if not okay or not state then
                    diagnostic("computer pickup memory unavailable", okay and reason or state)
                end
            end
        end
        return previous(self, character, square, object, ...)
    end
    props.pickUpMoveableInternal = wrapper
    Terminal._moveHook = { target = props, previous = previous, wrapper = wrapper }
    return true
end

function Terminal.electricalSkill(player)
    local perk = Perks and Perks.Electricity
    return perk and tonumber(call(player, "getPerkLevel", perk)) or 0
end

function Terminal.awardHackXP(player, object, state)
    local portable = portableData(object, false)
    if not portable or portable[System().MEMORY_KEY] ~= state or state.locked
        or state.xpAwarded or not state.puzzle
        or state.puzzle.guessed[state.puzzle.answer] ~= 6
        or not Terminal.powered(object) or not Terminal.near(player, object)
        or call(player, "isDead") == true then return false end
    -- Mark before the native callback: an exception after applying XP must
    -- never replay an ambiguous award on reopening or reloading.
    state.xpAwarded = true
    local perk, xp = Perks and Perks.Electricity, call(player, "getXp")
    if not perk or not xp then
        diagnostic("computer recovery XP unavailable", nil)
        return false
    end
    local _, okay = U().call(xp, "AddXP", perk, System().XP)
    if not okay then diagnostic("computer recovery XP failed", nil) end
    return okay
end

local function operatorName(player)
    local descriptor = call(player, "getDescriptor")
    local forename = descriptor and call(descriptor, "getForename")
    return type(forename) == "string" and forename ~= "" and forename or "operator"
end

-- One session per computer while the game runs, so EMMA keeps the thread of
-- a conversation across a quick trip to the shelves. Bounded; oldest drops.
function Terminal.sessionFor(player, object)
    -- Coordinates can be reused by a different computer. In-memory sessions
    -- use its persistent identity, without retaining an object/square/world.
    local portable = portableData(object, false)
    local state = portable and portable[System().MEMORY_KEY]
    if not state or state.locked then return nil end
    local key = state.identity
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

function Terminal.reset()
    Terminal.nativeLogoUnavailable=nil
    if SC.TerminalActions then SC.TerminalActions.reset() end
    local window = Terminal.window
    if window then
        if not window.closed then
            local okay, reason = pcall(window.close, window)
            if not okay then return false, tostring(reason) end
        else
            -- Retry a partial native UI close without replaying memory writes.
            local okay, reason = pcall(window.removeFromUIManager, window)
            if not okay then return false, tostring(reason) end
            Terminal.window = nil
        end
    end
    Terminal.resetSessions()
    return true
end

local function worldHours()
    if type(getGameTime) ~= "function" then return nil end
    return tonumber(call(getGameTime(), "getWorldAgeHours"))
end

-- ---------------------------------------------------------------------------
-- The window
-- ---------------------------------------------------------------------------

local function fontHeight(font)
    local ok, value = pcall(function() return getTextManager():getFontHeight(font) end)
    return ok and tonumber(value) or 16
end

local function viewport(player)
    local core = getCore and getCore()
    local view = { x = 0, y = 0, width = core and tonumber(core:getScreenWidth()) or 1280,
        height = core and tonumber(core:getScreenHeight()) or 720 }
    local index = tonumber(call(player, "getPlayerNum")) or 0
    if type(getPlayerScreenWidth) == "function" and type(getPlayerScreenHeight) == "function" then
        local okay, x, y, width, height = pcall(function()
            return getPlayerScreenLeft(index), getPlayerScreenTop(index),
                getPlayerScreenWidth(index), getPlayerScreenHeight(index)
        end)
        if okay and tonumber(width) and tonumber(height) and width > 0 and height > 0 then
            view = { x = x, y = y, width = width, height = height }
        end
    end
    return view
end

local function terminalFont(view)
    local manager = getTextManager()
    local okay, current = pcall(function() return manager:getCurrentCodeFont() end)
    current = okay and current or UIFont.Code or UIFont.Small
    local target = math.max(fontHeight(current), 24)
    local result, largest = current, current
    local best = math.huge
    for _, candidate in ipairs({ UIFont.CodeSmall or current, UIFont.CodeMedium or current,
        UIFont.CodeLarge or current, current }) do
        local height = fontHeight(candidate)
        if height > fontHeight(largest) then largest = candidate end
        if height >= target and height < best then result, best = candidate, height end
    end
    return best == math.huge and largest or result
end

local function inputFontFor(target, fallback)
    local result, distance = fallback, math.abs(fontHeight(fallback) - target)
    for _, font in ipairs({ UIFont.Small or fallback, UIFont.Medium or fallback,
        UIFont.Large or fallback, UIFont.Massive or fallback }) do
        local difference = math.abs(fontHeight(font) - target)
        if difference < distance then result, distance = font, difference end
    end
    return result
end

local function charWidth(font)
    local ok, value = pcall(function() return getTextManager():MeasureStringX(font, "MMMMMMMMMM") end)
    local width = ok and tonumber(value) or 80
    return math.max(4, width / 10)
end

local skinTextures = {}
local function skinTexture(name)
    if type(getTexture) ~= "function" then return nil end
    if skinTextures[name] ~= nil then return skinTextures[name] or nil end
    local okay, texture = pcall(getTexture, "media/textures/Terminal/Skin/crt-" .. name .. ".png")
    skinTextures[name] = okay and texture or false
    if not skinTextures[name] then diagnostic("terminal skin unavailable", name) end
    return skinTextures[name] or nil
end

function Terminal.preloadSkin()
    -- Load while client Lua starts, before a player opens the first computer.
    -- Native texture uploads are asynchronous; POST must not outrun the casing.
    skinTexture("frame")
    skinTexture("glass")
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
    local view = viewport(player)
    local font = terminalFont(view)
    local displayHeight = Presentation().textHeight(view.height, fontHeight(font))
    local zoom = displayHeight / fontHeight(font)
    local inputFont = inputFontFor(displayHeight, font)
    local layout = Presentation().layout(view, displayHeight, charWidth(font) * zoom, fontHeight(inputFont))
    local window = ISPanel.new(self, layout.x, layout.y, layout.width, layout.height)
    window.player, window.object = player, object
    window.square = call(object, "getSquare")
    window.moveWithMouse = false
    window.background = false
    window.font = font
    window.textZoom, window.inputFont = zoom, inputFont
    window.layout = layout
    window.skinFrame, window.skinGlass = skinTexture("frame"), skinTexture("glass")
    window.rowHeight = layout.row
    window.charWidth = charWidth(window.font) * zoom
    window.rows = {}
    window.queue = {}
    window.history = {}
    window.scroll = 0
    window.state = "idle"
    window.lastWatch = 0
    window.lastFrame = nowMs()
    return window
end

function SCTerminalWindow:refreshLayout()
    local view = viewport(self.player)
    local font = terminalFont(view)
    local fh = Presentation().textHeight(view.height, fontHeight(font))
    local zoom = fh / fontHeight(font)
    local cw = charWidth(font) * zoom
    local inputFont = inputFontFor(fh, font)
    local signature = table.concat({ view.x, view.y, view.width, view.height, tostring(font), fh, cw,
        tostring(inputFont), fontHeight(inputFont) }, ":")
    if self.layoutSignature == signature then return end
    self.layoutSignature = signature
    local layout = Presentation().layout(view, fh, cw, fontHeight(inputFont))
    self.layout, self.font, self.rowHeight, self.charWidth = layout, font, layout.row, cw
    self.textZoom, self.inputFont = zoom, inputFont
    self:setWidth(layout.width)
    self:setHeight(layout.height)
    self:setX(layout.x)
    self:setY(layout.y)
    self.renderRows, self.securityBoard, self.securityHits = nil, nil, {}
    if self.entry then
        self.entry:setX(layout.left)
        self.entry:setY(layout.entryY)
        self.entry:setWidth(layout.right - layout.left)
        self.entry:setHeight(layout.entryHeight)
        self.entry:setFont(inputFont)
    end
    if self.closeButton then
        self.closeButton.font = font
        self.closeButton:setX(layout.right - layout.row)
        self.closeButton:setY(layout.titleY)
        self.closeButton:setWidth(layout.row)
        self.closeButton:setHeight(layout.row)
    end
end

function SCTerminalWindow:columns()
    return math.max(8, math.floor(self:contentWidth() / self.charWidth))
end

function SCTerminalWindow:menuOptions()
    if not self.system then return {} end
    if self.system.locked then return { { label = "Log off", systemCommand = "close" } } end
    local profile = SC.TerminalFiles.get(self.system.archive)
    if self.menuPage == "files" then
        local result = {}
        for index, entry in ipairs(profile.entries) do
            result[#result + 1] = { label = entry.title, file = index }
        end
        result[#result + 1] = { label = "Back to EMMA", systemCommand = "back" }
        return result
    end
    if self.menuPage=="lore" then
        local result={}
        local entries=SC.TerminalLore.REFERENCE
        local page=math.max(0,math.min(math.floor((#entries-1)/3),self.referencePage or 0))
        local labels={"EMMA origin","Limits","Offline mode","Voice review","Contacts","Notices","Water","Shelters",
            "Road reports","Family names","Incidents","Power loss","Requests","Handover","Service desk","Review note"}
        for index=page*3+1,math.min(#entries,page*3+3) do
            local entry=entries[index]
            result[#result+1]={label=labels[index] or entry.title,referenceId=entry.id}
        end
        if page>0 then result[#result+1]={label="Previous files",referencePage=page-1} end
        if page*3+3<#entries then result[#result+1]={label="More files",referencePage=page+1} end
        result[#result+1]={label="Back to EMMA",systemCommand="back"}
        return result
    end
    return {
        { label = "Camp report", systemCommand = "report" },
        { label = "Personal files (" .. #profile.entries .. "): " .. profile.owner, systemCommand = "files" },
        { label = "County files and EMMA", systemCommand = "lore" },
        { label = "Log off", systemCommand = "close" },
    }
end

function SCTerminalWindow:sidebarWidth()
    return self.system and self.system.locked and 0 or self.layout.side
end

function SCTerminalWindow:contentWidth()
    return self.layout.right - self.layout.left - self:sidebarWidth()
end

function SCTerminalWindow:menuLayout()
    local side = self:sidebarWidth()
    local pad = self.layout.pad
    local x = side > 0 and math.floor(self.layout.right - side + pad / 2) or self.layout.left
    local width = side > 0 and math.floor(side - pad * 1.5) or self.layout.right - self.layout.left
    local y, result = self.layout.top, {}
    for index, option in ipairs(self:menuOptions()) do
        local lines = Terminal.wrap("[" .. index .. "] " .. option.label,
            math.floor(width / self.charWidth))
        if #lines > 2 then
            lines = { lines[1], string.sub(lines[2], 1, math.max(1, math.floor(width / self.charWidth) - 3)) .. "..." }
        end
        local height = #lines * self.rowHeight
        result[#result + 1] = { x = x, y = y, width = width, height = height,
            lines = lines, index = index }
        y = y + height + math.max(4, math.floor(pad / 2))
    end
    local selected = result[self.menuSelection or 1]
    local offset = selected and math.max(0, selected.y + selected.height - self:viewBottom()) or 0
    local visible = {}
    for _, box in ipairs(result) do
        box.y = box.y - offset
        if box.y >= self:viewTop() and box.y + box.height <= self:viewBottom() then
            visible[#visible + 1] = box
        end
    end
    return visible, y
end

function SCTerminalWindow:menuVisible()
    return self.state ~= "booting" and not (self.system and self.system.locked)
        and (self:sidebarWidth() > 0 or self.focusMode == "menu")
end

function SCTerminalWindow:viewTop()
    return self.layout.top
end
function SCTerminalWindow:viewBottom() return self.layout.bottom end

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
    self.closeButton = close
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
    entry.onPressUp = function(box) box.terminal:navigate(-1) end
    entry.onPressDown = function(box) box.terminal:navigate(1) end
    entry.onOtherKey = function(box, key) box.terminal:otherKey(key) end
    entry.onTextChange = function(box) box.terminal:entryChanged() end
    local previousMouseDown = entry.onMouseDown
    entry.onMouseDown = function(box, ...)
        box.terminal:setFocusMode("chat")
        if previousMouseDown then return previousMouseDown(box, ...) end
        return true
    end
    self:addChild(entry)
    self.entry = entry
    self:refreshLayout()
end

function SCTerminalWindow:setEntryText(value)
    if not self.entry then return end
    self.changingEntry = true
    self.entry:setText(value)
    self.changingEntry = false
end

function SCTerminalWindow:setFocusMode(mode)
    if self.system and self.system.locked then mode = "chat" end
    if mode == self.focusMode then return end
    if self.focusMode == "chat" and self.entry then self.chatDraft = self.entry:getText() end
    self.focusMode = mode
    self:setEntryText(mode == "chat" and (self.chatDraft or "") or "")
    if self.entry then pcall(function() self.entry:focus() end) end
end

function SCTerminalWindow:entryChanged()
    if self.changingEntry or self.state == "booting" or self.state == "closing" then return end
    local raw = self.entry:getText()
    if self.focusMode == "menu" and raw ~= "" then
        if raw:match("^[1-9]$") then
            self.menuSelection = tonumber(raw)
            self:submit()
        else
            -- Starting a sentence is also an intentional move to chat.
            self.focusMode = "chat"
        end
    end
end

function SCTerminalWindow:navigate(direction)
    if self.focusMode ~= "menu" then return self:recall(-direction) end
    local count = #self:menuOptions()
    if count > 0 then self.menuSelection = ((self.menuSelection or 1) - 1 + direction) % count + 1 end
end

function SCTerminalWindow:onClose()
    self:close()
end

function SCTerminalWindow:otherKey(key)
    if type(Keyboard) ~= "table" then return end
    if key == Keyboard.KEY_TAB and self.state ~= "booting" then
        self:setFocusMode(self.focusMode == "menu" and "chat" or "menu")
        return
    end
    if key == Keyboard.KEY_ESCAPE then
        if self.menuPage then
            self.menuPage,self.menuSelection = nil,1
            self:setFocusMode("menu")
            return
        end
        return self:close()
    end
    if key == Keyboard.KEY_PRIOR then self:scrollBy(self:visibleRows() - 2) end
    if key == Keyboard.KEY_NEXT then self:scrollBy(-(self:visibleRows() - 2)) end
end

function SCTerminalWindow:scrollBy(rows)
    if self:sidebarWidth() == 0 and self.focusMode == "menu" and self:menuVisible() then
        return self:navigate(rows > 0 and -1 or 1)
    end
    local count = self.system and self.system.locked and #self:securityRows() or #self:transcriptRows()
    local maximum = math.max(0, count - self:visibleRows())
    self.scroll = math.max(0, math.min(maximum, self.scroll + rows))
end

function SCTerminalWindow:onMouseWheel(delta)
    self:scrollBy(-(tonumber(delta) or 0) * 3)
    return true
end

function SCTerminalWindow:onMouseDown(x, y)
    if self.state ~= "closing" then
        for _, box in ipairs(self:menuVisible() and self:menuLayout() or {}) do
            if x >= box.x and x < box.x + box.width and y >= box.y and y < box.y + box.height then
                self:setFocusMode("menu")
                self:setEntryText(tostring(box.index))
                self:submit()
                return true
            end
        end
        for _, box in ipairs(self.securityHits or {}) do
            if x >= box.x and x < box.x + box.width and y >= box.y and y < box.y + self.rowHeight then
                self:setEntryText(box.value)
                self:submit()
                return true
            end
        end
    end
    ISPanel.onMouseDown(self, x, y)
    if self.entry then pcall(function() self.entry:focus() end) end
    return true
end

function SCTerminalWindow:pushRow(value, kind)
    self.rows[#self.rows + 1] = { text = value, kind = kind or "emma" }
    while #self.rows > Terminal.SCROLLBACK_ROWS do table.remove(self.rows, 1) end
    self.scroll = 0
    self.renderRows = nil
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

function SCTerminalWindow:startEmma()
    self.session = Terminal.sessionFor(self.player, self.object)
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
    self:setFocusMode("menu")
end

function SCTerminalWindow:boot()
    self.world = World().new(self.player, self.object)
    local failure
    self.system, failure = Terminal.computerState(self.player, self.object)
    if not self.system then error(failure) end
    self.colors = Presentation().colors(self.system.theme)
    if SC.TerminalBrands then
        local okay, camp = pcall(self.world.camp)
        self.brand = okay and camp and camp.inside and "_camp" or self.system.brand
        self.logoTexture = SC.TerminalBrands.texture(self.brand, self.system.theme)
    end
    local ink, title, glass = self.colors.input, self.colors.title, self.colors.background
    pcall(function() self.entry:setTextRGBA(ink[2], ink[3], ink[4], ink[1]) end)
    self.entry.backgroundColor = { r = glass[2], g = glass[3], b = glass[4], a = 0.5 }
    self.closeButton.backgroundColor = { r = glass[2], g = glass[3], b = glass[4], a = 0.8 }
    self.entry.borderColor = { r = title[2], g = title[3], b = title[4], a = 0.7 }
    self.closeButton.borderColor = self.entry.borderColor
    self.closeButton.textColor = { r = title[2], g = title[3], b = title[4], a = 1 }
    self.gameHours = worldHours()
    if self.system.locked then
        System().ensurePuzzle(self.system, Terminal.electricalSkill(self.player))
        System().status(self.system, self.gameHours)
        pcall(function() self.entry:setPlaceholderText("Select or type a displayed word or bracket group.") end)
    end
    self.postStarted, self.state = nowMs(), "booting"
    self:setFocusMode("chat")
    self:startBootSound()
end

function SCTerminalWindow:startBootSound()
    if self.bootSoundStarted then return end
    self.bootSoundStarted = true
    if type(getSoundManager) ~= "function" then return end
    local okay, manager, handle = pcall(function()
        local sound = getSoundManager()
        return sound, sound and sound:playUISound(Terminal.BOOT_SOUND)
    end)
    if okay and type(handle) == "number" and handle > 0 then
        self.bootSoundManager, self.bootSoundId = manager, handle
    elseif not okay then
        diagnostic("terminal boot sound unavailable", manager)
    end
end

function SCTerminalWindow:stopBootSound()
    local manager, handle = self.bootSoundManager, self.bootSoundId
    self.bootSoundManager, self.bootSoundId = nil, nil
    if not manager or not handle then return end
    local okay, reason = pcall(function()
        if manager:isPlayingUISound(handle) then manager:stopUISound(handle) end
    end)
    if not okay then diagnostic("terminal boot sound cleanup failed", reason) end
end

function SCTerminalWindow:finishBoot()
    if self.startupReady then return end
    self.startupReady = true
    self.state = "idle"
    if not self.system.locked then
        self:enqueue({ System().COMPANY, System().TITLE .. " - local services ready.", "" },
            "system", Terminal.BOOT_CHARS_PER_SECOND)
        self:startEmma()
    end
end

function SCTerminalWindow:securityRows()
    local result = {}
    local function line(text, kind)
        for _, value in ipairs(Terminal.wrap(text, self:columns())) do
            result[#result + 1] = { text = value, kind = kind }
        end
    end
    line(System().COMPANY, "system")
    line("LOCAL ACCESS LOCKED", "alert")
    local p = self.system.puzzle
    if System().status(self.system, self.gameHours) == "lockout" then
        local minutes = self.gameHours and math.max(0, math.ceil((p.lockoutUntil - self.gameHours) * 60))
        line(minutes and ("Try again in " .. minutes .. " game minutes.")
            or "Recovery clock unavailable.", "alert")
    else
        line("Attempts: " .. p.tries .. "/" .. p.maximum
            .. "  |  Match letters in the same position.", "system")
    end
    for _, line in ipairs(Terminal.wrap("Click or type a word. Bracket groups may help.", self:columns())) do
        result[#result + 1] = { text = line, kind = "system" }
    end
    local columns = self:columns()
    if not self.securityBoard or self.securityColumns ~= columns then
        self.securityBoard = System().board(self.system, columns)
        self.securityColumns = columns
    end
    for _, row in ipairs(self.securityBoard) do
        row.kind = "system"
        result[#result + 1] = row
    end
    if self.securityMessage then
        for _, line in ipairs(Terminal.wrap(self.securityMessage, self:columns())) do
            result[#result + 1] = { text = line, kind = "alert" }
        end
    end
    for _, word in ipairs(p.words) do
        if p.guessed[word] ~= nil then
            result[#result + 1] = { text = word .. "  " .. p.guessed[word] .. "/6 positions match.",
                kind = "input" }
        end
    end
    return result
end

function SCTerminalWindow:askEmma(raw)
    if not self.system or self.system.locked or not self.session then return false end
    self:setFocusMode("chat")
    local ok, reply = pcall(Brain().respond, self.session, raw, self.world)
    if not ok then
        diagnostic("terminal reply failed", reply)
        reply = { lines = { "[SYSTEM ERROR] Please try again." }, thinkMs = 0 }
    end
    if reply.memoryChanged then Terminal.writeMemory(self.object, self.session, worldHours()) end
    if reply.command == "clear" then
        self.rows, self.scroll, self.renderRows = {}, 0, nil
        return
    end
    if reply.proposal and SC.TerminalActions then
        self:cancelRequest()
        local prepared, ticket, prompt = pcall(SC.TerminalActions.prepare, self, reply.proposal)
        if not prepared then
            diagnostic("terminal request preparation failed", ticket)
            prompt, ticket = "I could not prepare that request. Please ask again.", nil
        end
        self.requestTicket = ticket
        reply.lines[#reply.lines + 1] = prompt
    end
    self:startReply(reply)
end

function SCTerminalWindow:cancelRequest()
    if SC.TerminalActions then SC.TerminalActions.cancel(self.requestTicket) end
    self.requestTicket = nil
end

function SCTerminalWindow:displayLocalFile(entry, reference)
    self:flush()
    local header=entry.date.." - "..entry.title
    self:print(header,"system")
    self:print(entry.text,"system")
    local notice=reference and "Archived local file; not a current-world observation." or ""
    self:print(notice,"system")
    local added=#Terminal.wrap(header,self:columns())+#Terminal.wrap(entry.text,self:columns())
        +#Terminal.wrap(notice,self:columns())
    -- Open long records at the beginning. Paging remains available even after
    -- the transcript has reached its bounded scrollback limit.
    self.scroll=math.max(0,added-self:visibleRows())
    if self:sidebarWidth()==0 then self:setFocusMode("chat") end
end

function SCTerminalWindow:systemInput(raw)
    local trimmed = raw:match("^%s*(.-)%s*$")
    local lower = string.lower(trimmed)
    if self.requestTicket then
        local ticket = self.requestTicket
        self.requestTicket = nil
        if lower == "yes" or lower == "y" then
            local called, okay, message = pcall(SC.TerminalActions.execute, self, ticket)
            if not called then
                SC.TerminalActions.cancel(ticket)
                diagnostic("terminal request failed", okay)
                message = "The request could not be completed. Ask about jobs before trying again."
            end
            self:startReply({ lines = { message }, thinkMs = 0 })
            return true
        end
        SC.TerminalActions.cancel(ticket)
        self:print("Request cancelled.", "system")
        if lower == "no" or lower == "n" then return true end
    end
    local number = self.focusMode == "menu" and trimmed:match("^%d+$") and tonumber(trimmed) or nil
    local option = number and self:menuOptions()[number] or nil
    if self.system.locked and lower == "exit" or lower == "log off" or lower == "logoff"
        or option and option.systemCommand == "close" then
        self:close()
        return true
    end
    if self.system.locked then
        self.gameHours = worldHours()
        local code, likeness = System().act(self.system, trimmed, self.gameHours)
        self.securityBoard = nil
        local messages = {
            invalid = "Choose a word or bracket group shown on this screen.",
            used = "That recovery group has already been used.",
            removed = "An incorrect candidate was removed.",
            restored = "Recovery attempts restored.",
            no_candidates = "No unused incorrect candidates remain.",
            removed_word = "That candidate has already been removed.",
            clock_unavailable = "Recovery clock unavailable. Try again shortly.",
            lockout = "Recovery is locked for one game hour after the last failed attempt.",
            failed = "No attempts remain. Recovery is locked for one game hour.",
        }
        self.securityMessage = messages[code]
        if code == "wrong" or code == "repeat" then
            self.securityMessage = string.upper(trimmed) .. ": " .. likeness .. "/6 positions match."
        elseif code == "success" then
            self.securityHits = {}
            Terminal.awardHackXP(self.player, self.object, self.system)
            self:print("6/6 positions match. Access restored. " .. System().TITLE .. " is ready.", "system")
            pcall(function() self.entry:setPlaceholderText("Type a menu number or ask EMMA.") end)
            self:startEmma()
        end
        return true
    end
    if number and not option then self:print("There is no menu item " .. number .. ".", "alert") return true end
    if lower == "files" or lower == "dir" or option and option.systemCommand == "files" then
        self.menuPage = "files"
        self.menuSelection=1
        self:setFocusMode("menu")
        self:print("Personal files: " .. SC.TerminalFiles.get(self.system.archive).owner, "system")
        return true
    end
    if lower=="county files" or lower=="emma files" or option and option.systemCommand=="lore" then
        self.menuPage,self.referencePage,self.menuSelection="lore",0,1
        self:setFocusMode("menu")
        self:print("Local reference archive. These dated files are not live reports.","system")
        return true
    end
    if option and option.referencePage~=nil then
        self.referencePage,self.menuSelection=option.referencePage,1
        return true
    end
    if option and option.referenceId then
        local entry=SC.TerminalLore.reference(option.referenceId)
        self:displayLocalFile(entry,true)
        return true
    end
    if lower == "menu" or lower == "back" or option and option.systemCommand == "back" then
        self.menuPage,self.menuSelection = nil,1
        return true
    end
    if option and option.file then
        local profile = SC.TerminalFiles.get(self.system.archive)
        local entry = profile.entries[option.file]
        self:displayLocalFile(entry,false)
        return true
    end
    if option and option.systemCommand == "report" then self:askEmma("status") return true end
    if lower == "hack" or lower == "password" then
        self:print("Local access is already open on this computer.", "system")
        return true
    end
    return false
end

function SCTerminalWindow:flush()
    if self.state == "booting" then self:stopBootSound() self:finishBoot() end
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
    self:setEntryText("")
    if self.state == "closing" then return end
    if not Terminal.present(self.object) or not Terminal.near(self.player, self.object)
        or call(self.player, "isDead") == true then self:close() return end
    if not Terminal.powered(self.object) then
        self.lastWatch = nowMs() - Terminal.WATCH_MS
        self:watch(nowMs())
        return
    end
    if self.state == "booting" then self:stopBootSound() self:finishBoot() self:flush() return end
    if raw == "" and self.focusMode == "menu" and self.state == "idle" then
        raw = tostring(self.menuSelection or 1)
    end
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
    if self.focusMode == "chat" then self.chatDraft = "" end
    self:print("> " .. raw, "input")
    if not self:systemInput(raw) then self:askEmma(raw) end
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
    self:cancelRequest()
    self:stopBootSound()
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
    self:refreshLayout()
    self.gameHours = worldHours()
    if self.state == "closing" then return end
    if not Terminal.present(self.object) or not Terminal.near(self.player, self.object)
        or call(self.player, "isDead") == true then
        return self:close()
    end
    if not Terminal.powered(self.object) then
        self:cancelRequest()
        self:stopBootSound()
        if self.state == "booting" then self.queue, self.typing = {}, nil else self:flush() end
        self:print(Lines().T.power_failure, "alert")
        self.state = "closing"
        self.closeAt = now + 1500
    end
end

function SCTerminalWindow:advance(now)
    local elapsed = math.max(0, math.min(250, now - (self.lastFrame or now)))
    self.lastFrame = now
    if self.state == "booting" then
        if now - self.postStarted >= Presentation().BOOT_MS then self:finishBoot() end
        return
    end
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
    local colors = self.colors or Presentation().colors("green")
    local color = colors[kind] or colors.emma
    self:drawText(value, self.layout.left, y, color[2], color[3], color[4], color[1], self.font)
end

function SCTerminalWindow:drawText(value, x, y, r, g, b, a, font)
    local glow = self.layout.skin.glow
    -- A restrained halo around a crisp foreground; no changing brightness.
    self:drawTextZoomed(value, x - glow, y, self.textZoom or 1, r, g, b, a * 0.07, font or self.font)
    self:drawTextZoomed(value, x + glow, y + glow, self.textZoom or 1, r, g, b, a * 0.07, font or self.font)
    self:drawTextZoomed(value, x, y, self.textZoom or 1, r, g, b, a, font or self.font)
end

function SCTerminalWindow:transcriptRows()
    if self.renderRows then return self.renderRows end
    local rows = {}
    for _, original in ipairs(self.rows) do
        for _, line in ipairs(Terminal.wrap(original.text, self:columns())) do
            rows[#rows + 1] = { text = line, kind = original.kind }
        end
    end
    self.renderRows = rows
    return rows
end

function SCTerminalWindow:drawHeaderLogo()
    self.lastNativeLogoDraw=false
    if not self.logoTexture or self.layout.brandHeight == 0 then return end
    local width, height = self.logoTexture:getWidth(), self.logoTexture:getHeight()
    if width <= 0 or height <= 0 then return end
    local theme = self.system and self.system.theme or "green"
    local style = Presentation().logoStyle(theme, self.layout.logo, self.layout.unit)
    if SC.TerminalBrands.isMonochrome(self.brand) then
        style.r,style.g,style.b=style.ink[2],style.ink[3],style.ink[4]
    end
    local crop = SC.TerminalBrands and SC.TerminalBrands.crop(self.brand, theme)
    local fit = Presentation().fitImage(crop and crop[3] or width, crop and crop[4] or height, style.box)
    if not fit then return end
    local scale = fit.width / (crop and crop[3] or width)
    -- One display treatment for every brand, including neutral stock marks.
    -- Cropping and soft tube tint never change the source PNG. The generated
    -- scanline glass sits behind the complete live display.
    self:setStencilRect(fit.x, fit.y, fit.width, fit.height)
    local okay, reason = pcall(function()
        local native=SCBridge and SCBridge.drawTerminalLogo
        local canonical=SC.TerminalBrands.canonical(self.brand)
        local backing=SC.TerminalBrands.BACKINGS and SC.TerminalBrands.BACKINGS[canonical]
        if native and self.javaObject and not Terminal.nativeLogoUnavailable then
            local called,drawn=pcall(native,self.javaObject,self.logoTexture,
                fit.x-(crop and crop[1] or 0)*scale,fit.y-(crop and crop[2] or 0)*scale,
                width*scale,height*scale,style.alpha,style.ink[2],style.ink[3],style.ink[4],
                backing and backing[1] or 0,backing and backing[2] or 0,backing and backing[3] or 0,
                backing~=nil,theme=="purple" or SC.TerminalBrands.isMonochrome(self.brand),
                SC.TerminalBrands.DARK_INK and SC.TerminalBrands.DARK_INK[canonical]==true or false)
            if called and drawn then self.lastNativeLogoDraw=true return end
            if not called then
                Terminal.nativeLogoUnavailable=true
                diagnostic("native terminal logo draw unavailable",drawn)
            end
        end
        self:drawTextureScaled(self.logoTexture, fit.x - (crop and crop[1] or 0) * scale,
            fit.y - (crop and crop[2] or 0) * scale, width * scale, height * scale,
            style.alpha, style.r, style.g, style.b)
    end)
    self:clearStencilRect()
    if not okay then
        self.logoTexture = nil
        diagnostic("terminal logo draw failed", reason)
        return
    end
    -- Small phosphor corner marks bind the logo to the terminal's own grid.
    local gap, length, ink = math.max(2, self.layout.unit), style.corner, style.ink
    local left, right = fit.x - gap, fit.x + fit.width + gap
    local top, bottom = fit.y - gap, fit.y + fit.height + gap
    for _, corner in ipairs({ {left,top,1,1}, {right,top,-1,1},
        {left,bottom,1,-1}, {right,bottom,-1,-1} }) do
        self:drawRect(corner[1] + (corner[3] < 0 and -length or 0), corner[2], length, 1,
            0.32, ink[2], ink[3], ink[4])
        self:drawRect(corner[1], corner[2] + (corner[4] < 0 and -length or 0), 1, length,
            0.32, ink[2], ink[3], ink[4])
    end
end

function SCTerminalWindow:drawHints()
    local colors = self.colors or Presentation().colors("green")
    local hint
    if self.state == "booting" then hint = "Enter: skip boot   Esc: log off"
    elseif self.system.locked then hint = "Choose a word or bracket group.  Esc: log off"
    elseif self.focusMode == "menu" then hint = "1-" .. #self:menuOptions() .. ": select   Tab: chat   Esc: back"
    else hint = "Enter: send   Tab: menu   Up/Down: history" end
    local line = Terminal.wrap(hint, math.max(8, math.floor((self.layout.right - self.layout.left) / self.charWidth)))[1]
    self:drawText(line, self.layout.left, self.layout.hintY,
        colors.system[2], colors.system[3], colors.system[4], 0.85, self.font)
end

function SCTerminalWindow:prerender()
    local width, height = self:getWidth(), self:getHeight()
    local colors = self.colors or Presentation().colors("green")
    local background, title = colors.background, colors.title
    self:drawRect(0, 0, width, height, 1, 0, 0, 0)
    local glass = self.layout.skin.glass
    if self.skinGlass then
        self:drawTextureScaled(self.skinGlass, glass.x, glass.y, glass.width, glass.height,
            1, title[2] * 0.62, title[3] * 0.62, title[4] * 0.62)
    else
        self:drawRect(glass.x, glass.y, glass.width, glass.height, 1, background[2], background[3], background[4])
    end
    local pad = self.layout.pad
    local captionRight = self.layout.brandHeight > 0 and self.layout.logo.x - pad
        or self.layout.right - self.rowHeight - pad
    local caption = (captionRight - self.layout.left) / self.charWidth >= 25 and (System().TITLE .. " // EMMA") or "LARCH/OS"
    if self.state == "booting" then caption = "SYSTEM / POWER-ON TEST" end
    self:drawText(caption, self.layout.left, self.layout.titleY,
        title[2], title[3], title[4], title[1], self.font)
    self:drawHeaderLogo()
    if self.layout.brandHeight > 0 then
        local label = self.layout.logo.x - self.layout.left - pad >= self.charWidth * 23 and "EMMA  /  LOCAL TERMINAL" or "EMMA"
        if self.state == "booting" then label = "PERSONAL SYSTEM / 486" end
        self:drawText(label, self.layout.left, self.layout.titleHeight,
            title[2], title[3], title[4], 0.95, self.font)
    end
    self:drawRect(self.layout.left, self.layout.top - pad / 2, self.layout.right - self.layout.left, 1, 0.5, title[2], title[3], title[4])
    local top, bottom = self:viewTop(), self:viewBottom()
    local side = self:sidebarWidth()
    self:drawHints()
    if self.state == "booting" then
        local y = top
        local bootRows = Presentation().bootFrame(nowMs() - self.postStarted, self.system.seed)
        for _, text in ipairs(bootRows) do
            for _, line in ipairs(Terminal.wrap(text, self:columns())) do
                if y + self.rowHeight <= bottom then self:drawRow(line, y, "system") end
                y = y + self.rowHeight
            end
        end
        return
    end
    if side > 0 then self:drawRect(self.layout.right - side, top, 1, math.max(0, bottom - top), 0.5, title[2], title[3], title[4]) end
    for _, box in ipairs(self:menuVisible() and self:menuLayout() or {}) do
        if self.focusMode == "menu" and box.index == (self.menuSelection or 1) then
            self:drawRectBorder(box.x - 2, box.y - 1, box.width + 4, box.height + 2,
                0.9, title[2], title[3], title[4])
        end
        for index, line in ipairs(box.lines) do
            self:drawText(line, box.x, box.y + (index - 1) * self.rowHeight,
                title[2], title[3], title[4], 1, self.font)
        end
    end
    if side == 0 and self.focusMode == "menu" and self:menuVisible() then return end
    local now = nowMs()
    -- Kahlua's large-number remainder is unsafe for epoch-based animation
    -- indices. Cycle on time elapsed since opening instead.
    local animationTime = math.max(0, now - (self.postStarted or now))
    local extra = {}
    local locked = self.system and self.system.locked and self.state ~= "closing"
    local rows = locked and self:securityRows() or self:transcriptRows()
    self.securityHits = {}
    if not locked and self.typing then
        local shown = math.floor(self.typing.shown or 0)
        local cursor = math.floor(animationTime / 400) % 2 == 0 and "_" or " "
        for _, line in ipairs(Terminal.wrap(string.sub(self.typing.text, 1, shown) .. cursor, self:columns())) do
            extra[#extra + 1] = { text = line, kind = self.typing.kind }
        end
    elseif not locked and self.state == "thinking" then
        local steps = self.thinkSteps or {}
        local span = math.max(1, (self.thinkEnd or now) - (self.thinkStart or now))
        local step = steps[math.min(#steps, math.floor((now - (self.thinkStart or now)) / span * #steps) + 1)]
        local thinkingTime = math.max(0, now - (self.thinkStart or now))
        local dots = string.rep(".", math.floor(thinkingTime / 300) % 4)
        extra[#extra + 1] = { text = SPINNER[math.floor(thinkingTime / 120) % 4 + 1] .. " " .. tostring(step or "Thinking") .. dots,
            kind = "system" }
    elseif not locked and self.state == "idle" and #self.rows == 0 then
        extra[#extra + 1] = { text = math.floor(animationTime / 500) % 2 == 0 and "_" or " ", kind = "emma" }
    end
    local visible = self:visibleRows()
    local total = #rows + #extra
    self.scroll = math.min(self.scroll, math.max(0, total - visible))
    local last = total - self.scroll
    local first = math.max(1, last - visible + 1)
    local y = top
    for index = first, last do
        local row = index <= #rows and rows[index] or extra[index - #rows]
        if row and y + self.rowHeight <= bottom + 2 then
            self:drawRow(row.text, y, row.kind)
            for _, span in ipairs(row.spans or {}) do
                if not span.disabled then
                    local x = self.layout.left + (span.start - 1) * self.charWidth
                    local ink = span.tried and colors.input or colors.emma
                    self:drawText(span.value, x, y, ink[2], ink[3], ink[4], 1, self.font)
                    self.securityHits[#self.securityHits + 1] = {
                        x = x, y = y, width = span.length * self.charWidth, value = span.value }
                end
            end
        end
        y = y + self.rowHeight
    end
    if self.scroll > 0 then
        self:drawText("-- more below --", self.layout.left + self:contentWidth() - 16 * self.charWidth, bottom - self.rowHeight + 2,
            title[2], title[3], title[4], 0.9, self.font)
    end
end

function SCTerminalWindow:render()
    -- Only the transparent casing is in front of the children. The glass
    -- texture and its scanlines were already painted behind the live text.
    if not self.skinFrame then return end
    local source = Presentation().SKIN
    local okay, reason = pcall(function()
        for _, part in ipairs(self.layout.skin.patches) do
            local sx, sy = part.width / part.sourceWidth, part.height / part.sourceHeight
            self:setStencilRect(part.x, part.y, part.width, part.height)
            self:drawTextureScaled(self.skinFrame, part.x - part.sourceX * sx,
                part.y - part.sourceY * sy, source.width * sx, source.height * sy, 1, 1, 1, 1)
            self:clearStencilRect()
        end
    end)
    if not okay then
        self:clearStencilRect()
        self.skinFrame = nil
        diagnostic("terminal frame draw failed", reason)
    end
end

-- ---------------------------------------------------------------------------
-- Opening, the timed action and the context menu
-- ---------------------------------------------------------------------------

function Terminal.open(player, object)
    if not Terminal.powered(object) then return false, "no_power" end
    if not Terminal.near(player, object) or call(player, "isDead") == true then
        return false, "operator_unavailable"
    end
    if SC.ComputerUse and SC.ComputerUse.yieldToPlayer(object) ~= true then
        return false, "computer_occupied"
    end
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
    return Terminal.powered(self.object) and Terminal.near(self.character, self.object)
        and call(self.character, "isDead") ~= true
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
    if not computer or not Terminal.powered(computer) or not Terminal.near(player, computer) then return false end
    context:addOption(text("UI_SC_Terminal_Use", "Use computer"), player,
        Terminal.onUseOption, computer)
    return true
end

local moveHookOkay, moveHookReason = Terminal.installMoveHook()
if not moveHookOkay then diagnostic("computer pickup hook unavailable", moveHookReason) end
Terminal.preloadSkin()
return Terminal
