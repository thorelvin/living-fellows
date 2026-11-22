-- SPDX-License-Identifier: MIT

local SC, T = SurvivorCompanion, TERMINAL_TEST
local Terminal, Access, Actions = SC.Terminal, SC.EmmaAccess, SC.TerminalActions
local square = T.square(100, 100, 0, true)
local player = T.player(100.5, 100.5, 0)
local computer = T.computer(square)
function player:getSquare() return square end
getSpecificPlayer = function(index) return index == 0 and player or nil end

local menu = { options = {} }
function menu:addOption(label, target, callback, object)
    local option = { name = label, target = target, onSelect = callback, param1 = object }
    self.options[#self.options + 1] = option
    return option
end
menu:addOption("Walk to")

T.check(Access.enabled(), "missing SandboxVars defaults to enabled")
local settings = { LockedComputerPercent = 0 }
SandboxVars = { LivingFellows = settings }
T.check(Terminal.fillWorldObjectContextMenu(0, menu, { computer }, player),
    "an existing world without the option can use a powered computer")
local use = menu.options[2]
T.check(use.scMenuKey == "terminal.use", "enabled computers show Use computer")
use.onSelect(use.target, use.param1)
local queuedUse = T.queued[#T.queued]
T.check(queuedUse and queuedUse:isValid(), "enabled world menu queues the native interaction")

SC.ContextMenu.action(menu, "drawer.force", "Force the drawer")
settings.EmmaEnabled = false
T.check(not Terminal.fillWorldObjectContextMenu(0, menu, { computer }, player)
    and #menu.options == 1 and menu.options[1].name == "Walk to",
    "disabling removes all retained computer entries and keeps the ordinary world menu")
local queueSize = #T.queued
use.onSelect(use.target, use.param1)
T.check(#T.queued == queueSize, "an old Use computer option cannot queue another action")
T.check(not queuedUse:isValid(), "disabling invalidates a queued Use computer action")
queuedUse:perform()
local opened, reason = Terminal.open(player, computer)
T.check(not opened and reason == "emma_disabled" and not Terminal.window and not computer.data.movableData,
    "disabled computer access leaves the screen and unvisited computer state untouched")
local jumped, jumpReason = SC.EmmaJump.use(player, computer)
T.check(not jumped and jumpReason == Access.disabledText(), "a retained jump-start action is refused")

settings.EmmaEnabled = true
T.check(Terminal.open(player, computer), "turning EMMA back on restores computer use")
local window = Terminal.window
window:flush()
window.session.operator, window.session.namedOperator = "Casey", true
local identity = window.system.identity
local confirm = Actions.prepare(window, { kind = "factory_reset" })
T.check(confirm ~= nil, "an enabled terminal can prepare a confirmation")
local installed = false
local function effect() installed = true return true end
local queuedInstall, _, installAction = SC.TerminalServices.install(player, computer, effect)
T.check(queuedInstall and installAction:isValid(), "an enabled installation can be queued")

settings.EmmaEnabled = false
T.check(not SC.TerminalServices.install(player, computer, effect)
    and not installAction:isValid(), "disabled maintenance refuses new and queued installations")
installAction:perform()
T.check(not installed, "the queued installation has no completion effects")
T.check(not Actions.execute(window, confirm), "old confirmations cannot apply after disabling")
window:update()
T.check(window.closed and not Terminal.window and not window.entry.focused,
    "disabling closes the open screen and releases the keyboard")
T.check(Terminal.readMemory(computer).operator == "Casey", "closing preserves the operator's saved memory")

settings.EmmaEnabled = true
T.check(Terminal.open(player, computer) and Terminal.window.system.identity == identity,
    "re-enabling resumes the same computer record")
T.check(not Actions.execute(Terminal.window, confirm), "re-enabling cannot revive an old confirmation")
Terminal.window:close()
SC_TEST_REPORT = "EMMA_SANDBOX_ACCESS_PASS checks=" .. T.checks
