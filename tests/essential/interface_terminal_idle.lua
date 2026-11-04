-- SPDX-License-Identifier: MIT
-- Invoke the real registered background callback with every terminal closed.
local SC, T = SurvivorCompanion, TERMINAL_TEST
local tasks, transmissions, tick = {}, 0, nil
SC.Config = { get = function() return 1000 end }
SC.State, SC.Identity = {}, { release = "fixture", bridgeProtocol = "fixture", gameVersion = "fixture" }
SC.Actor = { checkBridge = function() return true end }
SC.Persistence = { restore = function() return true end }
SC.Diagnostics = { report = function() end }
SC.Scheduler = { reset = function() tasks = {} end, register = function(name, _, _, callback)
    tasks[name] = callback return true
end }
Events = { OnTick = { Add = function(callback) tick = callback end, Remove = function() tick = nil end } }
ISInventoryPage = { selectContainer = function() end, setNewContainer = function() end }
local ready, reason, started = SC.Runtime.start()
assert(ready and started and tick and tasks["terminal-callback"], tostring(reason))
if SC.Terminal.window then SC.Terminal.window:close() end
assert(SC.Terminal.window == nil, "the background callback has no open terminal")
local ledger, tod = {}, 2.9
ModData = { getOrCreate = function() return ledger end }
getGameTime = function() return { getWorldAgeHours = function() return T.hours end,
    getTimeOfDay = function() return tod end } end
getZomboidRadio = function() return { SendTransmission = function() transmissions = transmissions + 1 end } end
getCell = function() error("closed terminal callback scanned the world") end
SC.BuildingScan = { pulse = function() error("terminal callback started building discovery") end }
SC.TerminalHardware = { pulse = function() error("terminal callback polled unrelated hardware") end }
SC.TerminalLockPhone.reset()
SC.TerminalLockRadio.reset()
SC.TerminalLocks.reset()
T.hours, T.now = 50.9, 1000
local state = { seed = 81731, identity = "interface-radio", lock = { kind = "radio" } }
assert(SC.TerminalLockRadio.register(state), "recovery radio registers its pending serial")
tasks["terminal-callback"](T.now)
assert(transmissions == 0, "a closed terminal does not send before the scheduled recovery night")
T.hours, tod, T.now = 51.01, 3.01, 2000
tasks["terminal-callback"](T.now)
assert(transmissions == 1 and SC.Terminal.window == nil,
    "the scheduled radio broadcast works with the terminal closed and no world discovery")
SC.TerminalLockRadio.reset()
ledger.pending = {}
for index = 1, 10 do tasks["terminal-callback"](T.now + index * 1000) end
assert(transmissions == 1, "an idle callback with no pending calls performs no broadcast or world work")
SC_TEST_REPORT = (SC_TEST_REPORT or "") .. "; Closed terminal PASS: scheduled radio only; idle callback has no world reads"
