-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, TERMINAL_TEST
local Terminal, System, Files = SC.Terminal, SC.TerminalSystem, SC.TerminalFiles
local check, beforeChecks = T.check, T.checks
local oldWorld, oldRand, oldCore, oldPerks = SC.TerminalWorld.new, ZombRand, getCore, Perks
local camp, peopleReads, storageReads = false, 0, 0
SC.TerminalWorld.new = function(...)
    local world = oldWorld(...)
    local people, storage = world.people, world.storage
    world.camp = function() return { configured = true, inside = camp, name = "Home" } end
    world.people = function() peopleReads = peopleReads + 1 return people() end
    world.storage = function() storageReads = storageReads + 1 return storage() end
    return world
end
ZombRand = function(maximum) return maximum > 1000000 and 19 or 0 end
Perks = { Electricity = "Electricity" }
local player = T.player(101, 100, 0)
local xp = 0
function player:getPerkLevel() return 0 end
function player:getXp()
    return { AddXP = function(_, perk, amount)
        check(perk == Perks.Electricity and amount == 5, "recovery uses native Electrical XP")
        xp = xp + amount
    end }
end
local function enter(window, raw)
    if window.state == "booting" then window:flush() end
    window:setFocusMode(raw:match("^%d+$") and "menu" or "chat")
    window.entry:setText(raw)
    window:submit()
end
local function settle(window) window:flush() end
local function transcript(window)
    local rows = {}
    for _, row in ipairs(window.rows) do rows[#rows + 1] = row.text end
    return table.concat(rows, "\n")
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
local square = T.square(100, 100, 0, true)
square.room = { getRoomDef = function() return { getName = function() return "policestorage" end } end }
local computer = T.computer(square)
local oldMoveables = ISMoveableSpriteProps
local picked, pickCalls, tail
ISMoveableSpriteProps = { pickUpMoveableInternal = function(self, actor, at, object, ...)
    pickCalls = (pickCalls or 0) + 1
    check(actor == player and at == object.square, "pickup arguments remain unchanged")
    tail = { ... }
    picked = copy(object.data.movableData)
    return "item", nil, "tail"
end }
check(Terminal.installMoveHook(), "native pickup adapter installs")
local wrapper = ISMoveableSpriteProps.pickUpMoveableInternal
check(Terminal.installMoveHook() and ISMoveableSpriteProps.pickUpMoveableInternal == wrapper,
    "repeated initialization never stacks pickup wrappers")
local unopened = T.computer(T.square(100, 100, 0, true))
unopened.square.generatorPower = false
local first, second, third = ISMoveableSpriteProps:pickUpMoveableInternal(player, unopened.square,
    unopened, "sprite-instance", "sprite-name", true, false)
check(first == "item" and second == nil and third == "tail"
    and pickCalls == 1 and tail[1] == "sprite-instance" and tail[4] == false,
    "pickup return values and trailing arguments are chained exactly once")
check(picked.LF_LarchOS.locked and unopened.data.LF_Emma == nil,
    "unopened, unpowered outside computers receive their lock before native pickup")
local remembered = T.computer(T.square(100, 100, 0, true))
remembered.data.LF_Emma = { visits = 2, operator = "Terry", notes = { "old note" } }
ISMoveableSpriteProps:pickUpMoveableInternal(player, remembered.square, remembered)
check(not picked.LF_LarchOS.locked and picked.LF_Emma.operator == "Terry"
    and picked.LF_Emma.notes[1] == "old note", "pickup migrates legacy access and notes before copying")
ISMoveableSpriteProps = oldMoveables
Terminal._moveHook = nil
check(Terminal.open(player, computer), "an outside desktop opens its locked OS")
local window = Terminal.window
check(window.system.locked and window.session == nil and computer.data.LF_Emma == nil,
    "a locked machine gives no EMMA session or visit")
check(Files.get(window.system.archive).kind == "police", "files come from the computer's room")
local answer, archive = window.system.puzzle.answer, window.system.archive
local identity = window.system.identity
local words = table.concat(window.system.puzzle.words, ",")
enter(window, "who is here")
check(peopleReads == 0 and storageReads == 0 and window.system.locked,
    "chat cannot bypass the whole-computer lock")
window:prerender()
local hit
for _, box in ipairs(window.securityHits) do
    if box.value:match("^[A-Z]+$") and box.value ~= answer then hit = box break end
end
check(hit ~= nil, "the recovery screen exposes visible word hit targets")
local tries = window.system.puzzle.tries
window:onMouseDown(hit.x + 1, hit.y + 1)
check(window.system.puzzle.tries == tries - 1 and window.securityMessage:find("/6", 1, true),
    "clicking a word gives likeness and spends one attempt")
local group = System.brackets(window.system)[1]
enter(window, group)
check(window.securityMessage:find("removed", 1, true), "typed bracket groups work")
local remaining = window.system.puzzle.tries
window:close()
Terminal.resetSessions()
Terminal.open(player, computer)
window = Terminal.window
check(window.system.locked and window.system.puzzle.tries == remaining
    and table.concat(window.system.puzzle.words, ",") == words,
    "closing and reopening preserves the board and attempts")

-- Vanilla pickup and placement carry the movableData payload, not flat mod data.
local carried = copy(computer.data.movableData)
local placed = T.computer(T.square(100, 100, 0, true))
placed.data.movableData = copy(carried)
placed.square.room = { getRoomDef = function() return { getName = function() return "bedroom" end } end }
camp = true
Terminal.open(player, placed)
window = Terminal.window
check(window.system.locked and window.system.archive == archive and window.system.puzzle.answer == answer
    and window.system.identity == identity,
    "moving into camp neither bypasses the lock nor replaces the old owner's files")
enter(window, answer)
settle(window)
check(not window.system.locked and window.session ~= nil and xp == 5,
    "successful recovery starts EMMA and awards XP once")
check(not Terminal.awardHackXP(player, placed, window.system) and xp == 5, "an award cannot repeat")
enter(window, "remember spare key in the jar")
settle(window)
enter(window, "call me Sam")
settle(window)
check(placed.data.movableData.LF_Emma.operator == "Sam"
    and placed.data.movableData.LF_Emma.notes[1] == "spare key in the jar",
    "EMMA's name and notes use the portable native payload")
enter(window, "2")
check(window.menuPage == "files", "a number opens personal files")
enter(window, "1")
check(transcript(window):find("1993-07-", 1, true)
    and transcript(window):find(Files.get(archive).entries[1].text:sub(1, 20), 1, true),
    "a numbered file displays its real date and original text")
window:otherKey(Keyboard.KEY_ESCAPE)
check(window.menuPage == nil and not window.closed, "Escape returns from files before logging off")
local boxes = window:menuLayout()
window:onMouseDown(boxes[2].x + 1, boxes[2].y + 1)
check(window.menuPage == "files", "clicking the system menu works")
enter(window, "menu")
enter(window, "how many nails")
settle(window)
check(transcript(window):find("216 nails", 1, true), "ordinary text still reaches EMMA")
local reads = peopleReads + storageReads
for index = 1, 60 do T.now = T.now + 16 window:update() window:prerender() end
check(peopleReads + storageReads == reads, "typewriter and rendering never rescan camp records")
window:close()

carried = copy(placed.data.movableData)
local outside = T.computer(T.square(100, 100, 0, true))
outside.data.movableData = copy(carried)
camp = false
Terminal.resetSessions()
Terminal.open(player, outside)
window = Terminal.window
settle(window)
check(not window.system.locked and window.system.xpAwarded and xp == 5
    and window.session.operator == "Sam" and #window.session.notes == 1,
    "unlocks, XP receipt, name and notes survive movement and a new session")
reads = peopleReads + storageReads
enter(window, "who is here")
settle(window)
enter(window, "how many nails")
settle(window)
check(peopleReads + storageReads == reads and transcript(window):find("outside", 1, true),
    "an unlocked outside computer still cannot read camp people or storage")
window:close()

-- Existing computers stay accessible. A different computer on the same tile
-- gets a different in-memory conversation, even when fixture randomness repeats.
local legacy = T.computer(T.square(100, 100, 0, true))
legacy.data.LF_Emma = { operator = "Pat", visits = 3, notes = {} }
Terminal.open(player, legacy)
window = Terminal.window
settle(window)
check(not window.system.locked and window.session.operator == "Pat", "legacy access migrates without locking")
check(window.session ~= Terminal.sessionFor(player, outside), "sessions do not alias by reused coordinates")
check(window.system.identity ~= outside.data.movableData.LF_LarchOS.identity,
    "a replacement computer keeps a distinct persistent identity even with repeated fixture randomness")
local oldSession = window.session
check(Terminal.reset() and window.closed and Terminal.window == nil,
    "world teardown closes the computer window and returns the keyboard")
check(Terminal.sessionFor(player, legacy) ~= oldSession,
    "world teardown releases cached conversations without changing portable memory")

-- Power and proximity are checked again when applying input, between watch pulses.
local dark = T.computer(T.square(100, 100, 0, true))
Terminal.open(player, dark)
window = Terminal.window
local darkAnswer = window.system.puzzle.answer
dark.square.generatorPower = false
enter(window, darkAnswer)
check(window.system.locked and xp == 5 and window.state == "closing",
    "power loss prevents recovery and XP even before the next watch pulse")
window:close()

local corrupt = T.computer(T.square(100, 100, 0, true))
corrupt.data.movableData = { LF_LarchOS = { schema = 999, locked = true } }
local originalRecord = corrupt.data.movableData.LF_LarchOS
check(not Terminal.open(player, corrupt) and Terminal.window == nil
    and corrupt.data.movableData.LF_LarchOS == originalRecord,
    "unsupported system records are preserved and never rerolled or unlocked")

-- Geometry uses real character widths, wraps the menu and reserves its space.
camp = true
for _, size in ipairs({ {480, 480}, {640, 480}, {1280, 720}, {1920, 1080} }) do
    getCore = function()
        return { getScreenWidth = function() return size[1] end,
            getScreenHeight = function() return size[2] end }
    end
    local item = T.computer(T.square(100, 100, 0, true))
    Terminal.open(player, item)
    window = Terminal.window
    settle(window)
    window:prerender()
    for _, page in ipairs({ "root", "files" }) do
        window.menuPage = page == "files" and "files" or nil
        for _, box in ipairs(window:menuLayout()) do
            check(box.x + box.width <= window:getWidth() - 12 and box.y + box.height <= window:viewBottom(),
                "all numbered menu choices fit above the input")
            for _, line in ipairs(box.lines) do
                check(#line * window.charWidth <= box.width, "menu text stays inside its reserved column")
            end
        end
    end
    window:close()
end
SC.TerminalWorld.new, ZombRand, getCore, Perks = oldWorld, oldRand, oldCore, oldPerks
SC_TEST_REPORT = SC_TEST_REPORT .. "; LARCH/OS terminal: " .. (T.checks - beforeChecks)
    .. " security, menu, movement, XP, offline-data and geometry checks passed"
