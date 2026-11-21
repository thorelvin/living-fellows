-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local calls = {made=0, opened=0, copied=0}
local checked = 0
local function check(value, message)
    checked = checked + 1
    assert(value, "report form "..checked..": "..message)
end
function SC.BugReport.buildDraft(what, steps)
    calls.made = calls.made + 1
    if what == "" or steps == "" then return nil, "Complete both fields." end
    return {body="Reviewed "..what.." / "..steps, url="draft"..calls.made}
end
function SC.BugReport.openDraft(draft)
    calls.opened = calls.opened + 1
    calls.lastOpen = draft
    return false, "Browser unavailable. Copy the draft link."
end
Clipboard = {setClipboard=function(url)
    calls.copied = calls.copied + 1
    calls.lastCopy = url
end}
local main = SC_TEST_REPORT_SCREEN(false)
SC.BugReportUI.install(main)
check(not main.lfBugReportButton, "title screen excluded")
local menu = SC_TEST_REPORT_SCREEN(true)
SC.BugReportUI.install(menu)
local launch = menu.lfBugReportButton
SC.BugReportUI.install(menu)
check(launch and #menu.children == 1, "one separate in-game entry")
check(launch:getRight() == menu.modListDetail:getRight() and launch:getY()+launch:getHeight()<menu.modListDetail:getY(), "separate from stock buttons")
menu.bottomPanel:setVisible(false)
check(not launch:isVisible(), "hidden in stock submenus")
menu.bottomPanel:setVisible(true)
menu:onJoypadDown("A", {})
check(menu.stockJoypad, "ordinary menu input delegated")
menu:onJoypadDown("Y", {})
local f = menu.lfBugReportForm
check(f and not launch:isVisible() and f.what.focused, "report opens from pause menu")
check(f.what.limit == 500 and f.steps.multiline and not f.preview.editable, "entry and preview controls")
f.primary:forceClick()
check(f.message == "Complete both fields." and not f.draft, "validation keeps editor open")
f.what:setText("First")
check(not f.message, "editing clears prior validation feedback")
f.steps:setText("Steps")
f.primary:forceClick()
local first = f.draft
check(first and f.preview:getText()==first.body and f.preview:isVisible(), "exact draft preview")
check(not f.what:isVisible() and not f.steps:isVisible(), "preview cannot diverge from editable form")
check(calls.opened==0 and calls.copied==0, "opening, validation and preview stay local")
f:onJoypadDown(Joypad.RBumper, {})
check(f.preview:getYScroll() < 0, "controller can read the next page of the draft")
f:onJoypadDown(Joypad.LBumper, {})
check(f.preview:getYScroll() == 0, "controller can return to the top")
f.back:forceClick()
check(not f.draft and f.what:getText()=="First" and f.steps:getText()=="Steps", "editing retains the fields and clears snapshot")
f.what:setText("Revised")
f.primary:forceClick()
check(f.draft ~= first and f.preview:getText()==f.draft.body, "revised snapshot shown")
f.primary:forceClick()
check(calls.opened==1 and calls.lastOpen==f.draft and calls.copied==0 and f.message=="Browser unavailable. Copy the draft link.", "explicit open with failure preserves draft")
f.copy:forceClick()
check(calls.copied==1 and calls.lastCopy==f.draft.url and calls.opened==1, "explicit copy of same draft")
f:onReturnToGame()
check(not menu.lfBugReportForm and launch:isVisible(), "resume closes form and restores menu")
launch:forceClick()
f = menu.lfBugReportForm
check(f.what:getText()=="" and f.steps:getText()=="" and not f.draft, "closed report text discarded")
f.cancel:forceClick()
check(not menu.lfBugReportForm and calls.opened==1, "cancel opens nothing")
SC_TEST_REPORT = tostring(checked).." report form checks passed"
