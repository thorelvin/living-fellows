-- SPDX-License-Identifier: MIT
-- The camp computer window: which objects count as computers, the menu
-- entry, walking over and sitting down, the boot screen, the thinking pause
-- and typewriter on a fake clock, Enter to skip, history, clear, exit,
-- walking away, losing power, Escape, wrapping, and memory kept in the
-- computer's mod data across sessions.
local T, SC = TERMINAL_TEST, SurvivorCompanion
local Terminal, Brain = SC.Terminal, SC.TerminalBrain
local check = T.check

-- Camp facts for the brain; the live adapter has its own harness.
SC.TerminalWorld.new = function()
    return {
        camp = function() return { configured = true, inside = true } end,
        clock = function() return { hour = 9, minute = 0, day = 1, month = 6, year = 1993,
            worldHours = T.hours, days = 4 } end,
        power = function() return { source = "generator", fuel = 80, condition = 90 } end,
        people = function() return { { id = "a", name = "Kate Miller", health = 90, doing = "Idle" } } end,
        storage = function() return { containers = 1, items = 216, groups = {
            { name = "Nails", type = "Base.Nails", category = "Material", count = 216,
                where = { "crate (tools)" } } } } end,
    }
end
Terminal._clock = function() return T.now end

local function rowsText(window)
    local result = {}
    for _, row in ipairs(window.rows) do result[#result + 1] = row.text end
    return table.concat(result, "\n")
end
local function shows(window, fragment)
    return string.find(rowsText(window), fragment, 1, true) ~= nil
end
local function run(window, milliseconds)
    local stop = T.now + milliseconds
    while T.now < stop and not window.closed do
        T.now = T.now + 50
        window:update()
        window:prerender()
    end
end
local function settle(window)
    for _ = 1, 2000 do
        if window.closed or (window.state == "idle" and #window.queue == 0 and not window.typing) then return end
        T.now = T.now + 50
        window:update()
    end
end
local function enter(window, value)
    if window.state == "booting" then window:flush() end
    if value ~= "" then window:setFocusMode("chat") end
    window.entry:setText(value)
    window:submit()
end

-- Computers and the menu ------------------------------------------------------
local desk = T.square(100, 100, 0, true)
local computer = T.computer(desk)
local tv = T.computer(T.square(90, 90, 0, true), "Television")
check(Terminal.isComputer(computer) and not Terminal.isComputer(tv) and not Terminal.isComputer(nil),
    "a computer is known by its CustomName")
local floor = { getSquare = function() return desk end }
check(Terminal.findComputer({ floor }) == computer, "clicking the desk under it still finds the computer")
check(Terminal.findComputer({ tv }) == nil, "other appliances are not computers")

local player = T.player(101, 100, 0)
local menu = { options = {} }
function menu:addOption(name, target, callback, param)
    local option = { name = name, target = target, onSelect = callback, param1 = param }
    self.options[#self.options + 1] = option
    return option
end
check(Terminal.fillWorldObjectContextMenu(0, menu, { computer }, player) == true
    and #menu.options == 1 and menu.options[1].name == "Use computer"
    and menu.options[1].target == player and menu.options[1].param1 == computer
    and not menu.options[1].notAvailable, "a powered computer offers Use computer")
check(Terminal.fillWorldObjectContextMenu(1, { options = {}, addOption = menu.addOption },
    { computer }, player) == false, "only the first, keyboard player sits at a terminal")
check(Terminal.fillWorldObjectContextMenu(0, { options = {}, addOption = menu.addOption },
    { tv }, player) == false, "no computer, no entry")
desk.generatorPower = false
local dark = { options = {}, addOption = menu.addOption }
Terminal.fillWorldObjectContextMenu(0, dark, { computer }, player)
check(#dark.options == 0, "an unpowered computer has no Use computer entry")
local distantMenu = { options = {}, addOption = menu.addOption }
check(not Terminal.fillWorldObjectContextMenu(0, distantMenu, { computer }, T.player(110, 100, 0))
    and #distantMenu.options == 0, "Use computer requires standing near the desktop")
desk.gridPower = true
check(not Terminal.powered(computer), "grid power outside a room does not run it")
desk.room = {}
check(Terminal.powered(computer), "grid power inside a building runs it")
desk.gridPower, desk.room, desk.generatorPower = false, nil, true

-- Walking over and sitting down -----------------------------------------------
local far = T.player(110, 100, 0)
menu.options[1].onSelect(far, computer)
check(#T.walked == 1 and T.walked[1].square == desk and #T.queued == 1,
    "a far player walks over first, then sits down")
menu.options[1].onSelect(player, computer)
check(#T.walked == 1 and #T.queued == 2, "a near player sits down at once")
T.walkable = false
check(select(2, Terminal.use(far, computer)) == "unreachable" and #T.queued == 2,
    "an unreachable desk queues nothing")
T.walkable = true
local action = T.queued[2]
check(action.object == computer and action.maxTime > 0 and action.stopOnWalk == true
    and action:isValid() == true, "the sit-down action is a short, walk-cancelled action")
action:waitToStart()
action:start()
check(player.faced >= 1 and action.anim == "Loot", "the player faces the screen")
desk.generatorPower = false
check(action:isValid() == false, "the action stops if the power goes")
desk.generatorPower = true

-- Boot -------------------------------------------------------------------------
action:perform()
local window = Terminal.window
check(window ~= nil and T.performed == 1 and window.inUI and window.entry.focused,
    "finishing the action opens the terminal with the keyboard on the prompt")
check(window.entry.maxLength == Brain.MAX_INPUT and window.entry.placeholder ~= nil,
    "the prompt is bounded and explains itself")
check(window.state == "booting" and #window.rows == 0, "hardware POST starts before EMMA")
run(window, 300)
check(window.state == "booting" and window.session == nil,
    "the animated memory check does not start an EMMA session early")
settle(window)
check(shows(window, "EMMA 0.9.3 BETA") and shows(window, "2 local records")
    and shows(window, "generator, fuel 80%"), "the boot screen reports the population and power")
check(window.rows[1].kind == "system" and window.rows[#window.rows].kind == "emma",
    "boot lines are system text and the greeting is EMMA")
check(computer.data.LF_Emma and computer.data.LF_Emma.visits == 1
    and computer.data.LF_Emma.lastSeen == T.hours, "the visit is written to the computer")

-- A question -------------------------------------------------------------------
enter(window, "how many nails")
check(shows(window, "> how many nails") and window.state == "thinking" and window.entry.text == "",
    "the question echoes, clears the prompt and EMMA thinks")
run(window, 200)
check(window.state == "thinking" and not shows(window, "216 nails"), "no answer during the pause")
settle(window)
check(shows(window, "216 nails in camp storage.") and shows(window, "Stored in: crate (tools)."),
    "the answer types out after the pause")
check(window.rows[#window.rows].text == "", "a blank row separates replies")

enter(window, "status")
enter(window, "")
check(window.state == "idle" and shows(window, "Camp report"), "Enter during a reply skips to its end")
enter(window, "remember gate code 4512")
settle(window)
check(computer.data.LF_Emma.notes[1] == "gate code 4512", "a note is saved on the computer")
enter(window, "call me Ragnar")
settle(window)
check(computer.data.LF_Emma.operator == "Ragnar", "a chosen name is saved on the computer")

-- History ------------------------------------------------------------------------
window:recall(1)
check(window.entry.text == "call me Ragnar", "up recalls the last line")
window:recall(1)
check(window.entry.text == "remember gate code 4512", "up again goes further back")
window:recall(-1)
check(window.entry.text == "call me Ragnar", "down comes forward")
window:recall(-1)
check(window.entry.text == "", "down past the newest clears the prompt")
for index = 1, 40 do window.history[#window.history + 1] = "x" .. index end
enter(window, "clear")
check(#window.history <= Terminal.HISTORY, "history is bounded")

-- Clear and scroll --------------------------------------------------------------
check(#window.rows == 0 and window.state == "idle", "clear wipes the screen at once")
for index = 1, 80 do window:print("line " .. index) end
window:onMouseWheel(1)
check(window.scroll == 0, "the view cannot scroll below the newest line")
window:onMouseWheel(-5)
check(window.scroll == 15, "wheel up scrolls back")
window:otherKey(Keyboard.KEY_PRIOR)
check(window.scroll == 15 + window:visibleRows() - 2, "Page Up scrolls a screen back")
window:onMouseWheel(-1000)
check(window.scroll == #window.rows - window:visibleRows(), "scrolling stops at the oldest line")
window:prerender()
check(T.lastDrawn == "-- more below --", "scrolled back, the view says there is more")
window:print("new")
check(window.scroll == 0, "new output returns to the bottom")
for index = 1, Terminal.SCROLLBACK_ROWS + 50 do window:print("flood " .. index) end
check(#window.rows == Terminal.SCROLLBACK_ROWS, "scrollback is bounded")

-- Exit ---------------------------------------------------------------------------
enter(window, "exit")
settle(window)
check(not window.closed and window.closeAt ~= nil, "EMMA finishes her goodbye before closing")
run(window, 1000)
check(window.closed and Terminal.window == nil and not window.inUI and not window.entry.focused,
    "the window closes after goodbye and hands the keyboard back")

-- Walking away, power loss, Escape ------------------------------------------------
Terminal.open(player, computer)
window = Terminal.window
settle(window)
player.x = 106
run(window, 600)
check(window.closed and Terminal.window == nil, "walking away closes the terminal")
player.x = 101

Terminal.open(player, computer)
window = Terminal.window
settle(window)
desk.generatorPower = false
run(window, 600)
check(not window.closed and window.state == "closing" and shows(window, "*** POWER FAILURE ***"),
    "losing power shows the failure first")
run(window, 2000)
check(window.closed, "then the screen goes dark")
desk.generatorPower = false
local opened, refusal = Terminal.open(player, computer)
check(opened == false and refusal == "no_power" and Terminal.window == nil, "a dark computer will not open")
desk.generatorPower = true

Terminal.open(player, computer)
window = Terminal.window
window:otherKey(Keyboard.KEY_ESCAPE)
check(window.closed and Terminal.window == nil, "Escape leaves")
Terminal.open(player, computer)
local first = Terminal.window
Terminal.open(player, computer)
check(first.closed and Terminal.window ~= first, "only one terminal is open at a time")
Terminal.window:close()
computer.index = -1
Terminal.open(player, computer)
check(Terminal.window == nil, "a removed computer cannot be used")
computer.index = 3

-- Memory across sessions -------------------------------------------------------------
Terminal.resetSessions()
T.hours = T.hours + 30
Terminal.open(player, computer)
window = Terminal.window
settle(window)
check(window.session.operator == "Ragnar" and window.session.notes[1] == "gate code 4512"
    and shows(window, "Ragnar") and shows(window, "30 hours"),
    "a new session remembers the name, the notes and the time away")
enter(window, "what did i tell you")
settle(window)
check(shows(window, "1. gate code 4512"), "old notes are read back")
window:close()
computer.data.LF_Emma = { operator = { "bad" }, notes = "broken", visits = "many", lastSeen = -5 }
computer.data.movableData.LF_Emma = computer.data.LF_Emma
Terminal.resetSessions()
Terminal.open(player, computer)
window = Terminal.window
settle(window)
check(window.session.operator == "Thor" and #window.session.notes == 0 and shows(window, "EMMA"),
    "damaged memory on a computer is ignored, not trusted")
window:close()

-- Wrapping -------------------------------------------------------------------------
local rows = Terminal.wrap("one two three four", 10)
check(#rows == 2 and rows[1] == "one two" and rows[2] == "three four", "words wrap at the edge")
rows = Terminal.wrap(string.rep("a", 20), 8)
check(#rows == 3 and rows[1] == "aaaaaaaa" and rows[3] == "aaaa", "a long word is split")
rows = Terminal.wrap("  1. first second third", 12)
check(rows[1] == "  1. first" and string.sub(rows[2], 1, 2) == "  ", "indented rows keep their indent")
rows = Terminal.wrap("a\n\nb", 20)
check(#rows == 3 and rows[2] == "", "blank lines are kept")

SC_TEST_REPORT = "Camp computer terminal: " .. T.checks .. " checks passed"
