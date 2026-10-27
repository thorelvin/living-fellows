-- SPDX-License-Identifier: MIT
local SC, T = SurvivorCompanion, TERMINAL_TEST
local Terminal, check, before = SC.Terminal, T.check, T.checks
local previousManager = getSoundManager
local manager = { next = 1000, plays = {}, stops = {}, active = { [777] = true } }
function manager:playUISound(name)
    self.next = self.next + 1
    self.plays[#self.plays + 1] = name
    self.active[self.next] = true
    return self.next
end
function manager:isPlayingUISound(handle) return self.active[handle] == true end
function manager:stopUISound(handle)
    self.stops[#self.stops + 1] = handle
    self.active[handle] = nil
end
getSoundManager = function() return manager end
local player = T.player(101,100,0)
local function open()
    local computer = T.computer(T.square(100,100,0,true))
    check(Terminal.open(player,computer), "boot audio does not block opening a computer")
    return Terminal.window, computer
end
local window = open()
local handle = window.bootSoundId
check(handle == 1001 and #manager.plays == 1 and manager.plays[1] == "LFTerminalBoot",
    "boot starts the supplied clip once through the local UI sound manager")
window:startBootSound()
for _=1,5 do window:prerender() window:render() end
check(#manager.plays == 1, "UI refresh and repeated start requests never replay the startup clip")
window:advance(T.now + SC.TerminalPresentation.BOOT_MS + 1)
check(manager.active[handle] and window.state ~= "booting",
    "normal POST completion lets the longer sound finish over the welcome screen")
window:close()
window:close()
check(#manager.stops == 1 and manager.stops[1] == handle and manager.active[777],
    "closing stops only its own handle once and leaves other UI sounds alone")

window = open()
handle = window.bootSoundId
window:submit()
check(window.state ~= "booting" and not manager.active[handle] and window.bootSoundId == nil,
    "Enter skips both POST and its startup sound")
window:close()

local computer
window,computer = open()
handle = window.bootSoundId
computer.square.generatorPower = false
window:watch(T.now + Terminal.WATCH_MS + 1)
check(window.state == "closing" and not manager.active[handle],
    "power loss silences startup immediately before the warning closes")
window:close()

window = open()
handle = window.bootSoundId
Terminal.reset()
check(window.closed and not manager.active[handle] and Terminal.window == nil,
    "world teardown releases an active startup clip")

getSoundManager = function() return {playUISound=function() return 0 end} end
window = open()
check(window.bootSoundId == nil and not window.closed, "muted or disabled audio needs no cleanup handle")
window:close()
getSoundManager = function() return {playUISound=function() error("test unavailable audio device") end} end
window = open()
check(window.bootSoundId == nil and window.state == "booting", "audio errors leave the computer usable")
window:close()
getSoundManager = previousManager
SC_TEST_REPORT = SC_TEST_REPORT .. "; Terminal boot audio: " .. (T.checks-before) .. " checks passed"
