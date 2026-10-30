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

window = open() window:flush()
check(window.closeButton.sounds.activate==Terminal.CLICK_SOUND,"the native close button uses the supplied click instead of a second default sound")
local count=#manager.plays
local menu=window:menuLayout()[2]
window:onMouseDown(menu.x+1,menu.y+1)
check(#manager.plays==count+1 and manager.plays[#manager.plays]==Terminal.CLICK_SOUND and window.menuPage=="files",
    "a mouse menu press plays the supplied click exactly once")
count=#manager.plays
window:setFocusMode("menu") window.entry:setText("1") window:submit()
check(#manager.plays==count+1 and manager.plays[#manager.plays]==Terminal.CLICK_SOUND,
    "a keyboard menu selection plays that same click once")
count=#manager.plays
window.entry:setText("9") window:submit()
for _=1,3 do window:prerender() end
check(#manager.plays==count,"invalid menu numbers and repainting do not trigger click sounds")
window.entry:onMouseDown(1,1)
check(#manager.plays==count+1 and window.focusMode=="chat","clicking the input line gives local click feedback")
window:close()

local locked=T.computer(T.square(100,100,0,true))
Terminal.computerState(player,locked).locked=true
check(Terminal.open(player,locked),"feedback fixture opens a locked desktop")
window=Terminal.window window:flush() window:drawSecurity()
local wrong
for _,hit in ipairs(window.securityHits) do
    if hit.value:match("^[A-Z]+$") and hit.value~=window.system.puzzle.answer then wrong=hit break end
end
check(wrong~=nil,"feedback fixture has a visible wrong candidate")
count=#manager.plays
window:onMouseDown(wrong.x+1,wrong.y+1)
check(#manager.plays==count+1 and manager.plays[#manager.plays]==Terminal.CLICK_SOUND,
    "a wrong password gives one click without the login cue")
window:drawSecurity()
local correct
for _,hit in ipairs(window.securityHits) do if hit.value==window.system.puzzle.answer then correct=hit break end end
check(correct~=nil,"the actual password has a visible native hit target")
count=#manager.plays
window:onMouseDown(correct.x+1,correct.y+1)
check(not window.system.locked and #manager.plays==count+2
    and manager.plays[count+1]==Terminal.CLICK_SOUND and manager.plays[count+2]==Terminal.LOGIN_SOUND,
    "clicking the correct password gives one click followed by one login cue")
count=#manager.plays
window:flush() window:prerender() window:close()
Terminal.open(player,locked) window=Terminal.window window:flush()
check(#manager.plays==count+1 and manager.plays[#manager.plays]==Terminal.BOOT_SOUND,
    "redraw and reopening an unlocked computer do not replay the successful login")
window:close()

local typed=T.computer(T.square(100,100,0,true))
Terminal.computerState(player,typed).locked=true
Terminal.open(player,typed) window=Terminal.window window:flush()
count=#manager.plays
window:setFocusMode("chat") window.entry:setText(window.system.puzzle.answer) window:submit()
check(not window.system.locked and #manager.plays==count+1 and manager.plays[#manager.plays]==Terminal.LOGIN_SOUND,
    "typing a correct password gives the same single successful-login cue")
window:close()

getSoundManager = function() return {playUISound=function() return 0 end} end
window = open()
check(window.bootSoundId == nil and not window.closed, "muted or disabled audio needs no cleanup handle")
window:close()
getSoundManager = function() return {playUISound=function() error("test unavailable audio device") end} end
window = open()
check(window.bootSoundId == nil and window.state == "booting", "audio errors leave the computer usable")
window:flush() window:setFocusMode("menu") window.entry:setText("2")
check(pcall(window.submit,window) and window.menuPage=="files","failed click audio does not block the selected menu action")
window:close()
getSoundManager = previousManager
SC_TEST_REPORT = SC_TEST_REPORT .. "; Terminal boot audio: " .. (T.checks-before) .. " checks passed"
