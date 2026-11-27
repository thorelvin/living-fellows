-- SPDX-License-Identifier: MIT
-- Run with PrepareWorld.ps1 in an approved, disposable PZO fixture.
local SC = LivingFellows
local phase, at, checks, opens = "menu", 0, 0, 0
local menu, form, expectedUrl, originalCall
local function check(ok, reason)
    checks = checks + 1
    assert(ok, "report check "..checks..": "..reason)
end
local function nextPhase(name)
    phase, at = name, getTimestampMs()
end
local function finish(ok, reason)
    if originalCall then SC.Call.static = originalCall end
    local out = assert(getFileWriter("pzo-bug-report-result.txt", true, false))
    out:write("result="..(ok and "PASS" or "FAIL").."\nphase="..phase.."\nchecks="..checks
        .."\nreason="..tostring(reason).."\n")
    out:close()
    phase = "done"
end
local function toggleMenu()
    local key = getCore():getKey(KeybindId.MAIN_MENU)
    ToggleEscapeMenu(key ~= 0 and key or Keyboard.KEY_ESCAPE)
end
Events.OnMainMenuEnter.Add(function()
    MainScreen.continueLatestSave("Sandbox", "PzoRestoreFixture")
end)
local seenModal = {}
Events.OnGameStart.Add(function() nextPhase("started") end)
local function step()
    if phase == "menu" then
        local modal = MainScreen.instance and MainScreen.instance.checkSavefileModal
        if modal and modal.yes and not seenModal[modal] then seenModal[modal] = true; modal:onClick(modal.yes) end
        return
    end
    if getTimestampMs() - at < 650 then return end
    if phase == "started" then
        local brain = SC.TerminalBrain
        local session = brain.newSession({})
        local world = SC.TerminalWorld.new(getSpecificPlayer(0), nil)
        local reply = brain.respond(session, "I can't see any way through another day", world)
        check(reply.intent == "care_check" and reply.private, "private check through ordinary terminal reply")
        check(brain.respond(session, "no", world).intent == "comfort", "negative answer continues with comfort")
        session = brain.newSession({})
        reply = brain.respond(session, "I just need someone to hear me", world)
        check(reply.intent == "care_gentle" and reply.private, "gentle first-person disclosure")
        check(brain.respond(session, "what time is it", world).intent == "time", "ordinary clock question still works")
        reply = brain.respond(brain.newSession({}), "Inside I feel forgotten whenever it gets dark", world)
        check(reply.intent == "care_gentle" and reply.private, "contextual disclosure stays private")
        menu = MainScreen.instance
        check(menu and menu.inGame and not menu:isVisible(), "gameplay menu starts closed")
        check(type(SCBridge.openBugReportDraft) == "function", "dedicated native opener is exposed")
        -- Observe the final OS handoff without sending a draft or changing the user's clipboard.
        originalCall = SC.Call.static
        SC.Call.static = function(object, method, ...)
            if object == SCBridge and method == "openBugReportDraft" then
                opens = opens + 1
                local link = ...
                check(expectedUrl and link == expectedUrl, "only the previewed link reaches native handoff")
                return true, false
            end
            return originalCall(object, method, ...)
        end
        SC.Diagnostics.report("persistence", "private-report-canary", "OnSave failed", "C:/private/profile.txt")
        toggleMenu()
        nextPhase("paused")
    elseif phase == "paused" then
        check(menu:isVisible() and menu.reportBug:isVisible(), "stock pause menu still present")
        local entry = menu.lfBugReportButton
        check(entry and entry:isVisible() and entry:getBottom() < menu.modListDetail:getY(), "separate report entry")
        getCore():TakeFullScreenshot("lf-report-native-menu.png")
        entry:forceClick()
        form = menu.lfBugReportForm
        check(form and form:isReallyVisible() and not entry:isVisible(), "report entry opens a single form")
        form.primary:forceClick()
        check(form.message and not form.draft and opens == 0, "empty report remains local")
        form.what:setText("The camp list displayed a file path.")
        form.steps:setText("Open C:/private/profile.txt")
        form.primary:forceClick()
        check(form.message and not form.draft and opens == 0, "sensitive free text rejected")
        form.what:setText("The camp list stopped updating.")
        form.steps:setText("Open the camp list twice after a companion returns.")
        -- Programmatic SetText differs from typing. Dispatch the stock widget's change event.
        form.what:onTextChange()
        check(not form.message, "typing clears the old validation feedback")
        nextPhase("edited")
    elseif phase == "edited" then
        getCore():TakeFullScreenshot("lf-report-native-edit.png")
        form.primary:forceClick()
        check(form.draft and form.preview:getText() == form.draft.body, "review contains exact draft")
        local safe = assert(getFileWriter("pzo-bug-report-version-check.txt", true, false))
        safe:write("mod="..tostring(form.draft.body:match("Living Fellows version\n([^\n]+)"))
            .."\ngame="..tostring(form.draft.body:match("Project Zomboid version\n([^\n]+)"))
            .."\nloaded="..tostring(form.draft.body:match("Bridge protocol %(loaded%): ([^\n]+)"))
            .."\nexpected="..tostring(form.draft.body:match("Bridge protocol %(expected%): ([^\n]+)")).."\n")
        safe:close()
        check(form.draft.body:find(SC.Identity.release,1,true), "mod version displayed")
        check(form.draft.body:find("42.22.2",1,true), "native game version displayed")
        check(form.draft.body:find("Bridge protocol (loaded): "..SCBridge.getProtocol(),1,true), "native bridge protocol displayed")
        check(form.draft.body:find("OnSave failed",1,true) and not form.draft.body:find("private",1,true),
            "latest diagnostic keeps safe literal and omits identity and path")
        check(form.draft.url:find("template=bug_report.yml",1,true) and opens == 0, "preview stays local")
        nextPhase("reviewed")
    elseif phase == "reviewed" then
        getCore():TakeFullScreenshot("lf-report-native-review.png")
        check(form.preview:getScrollHeight() > form.preview:getScrollAreaHeight(), "draft actually extends past the preview")
        form:onJoypadDown(Joypad.RBumper, {})
        check(form.preview:getYScroll() < 0, "controller callback scrolls actual native draft")
        nextPhase("review-bottom")
    elseif phase == "review-bottom" then
        check(form.preview:getYScroll() < 0, "new page remains visible across native render frames")
        getCore():TakeFullScreenshot("lf-report-native-log.png")
        form:onJoypadDown(Joypad.LBumper, {})
        check(form.preview:getYScroll() == 0, "controller callback returns to the beginning")
        form.back:forceClick()
        check(form.what:getText() == "The camp list stopped updating." and not form.draft, "edit retains report")
        form.what:setText("The camp list was blank on reopening.")
        form.primary:forceClick()
        expectedUrl = form.draft.url
        form.primary:forceClick()
        check(opens == 1 and form.message and form.copy:isVisible(), "browser failure leaves copy option")
        toggleMenu()
        check(not menu:isVisible() and not menu.lfBugReportForm, "return to game closes the draft")
        toggleMenu()
        menu.lfBugReportButton:forceClick()
        check(menu.lfBugReportForm.what:getText() == "", "reopening starts a fresh report")
        menu.lfBugReportForm.cancel:forceClick()
        check(menu.bottomPanel:isVisible() and menu.reportBug:isVisible() and opens == 1, "cancel restores vanilla menu")
        finish(true, "native UI, EMMA reply path, reviewed browser handoff")
    end
end
Events.OnRenderTick.Add(function()
    if phase == "done" then return end
    local ok, why = pcall(step)
    if not ok then finish(false, why) end
end)
