-- SPDX-License-Identifier: MIT
local SC, fixture = SurvivorCompanion, BasePolicyFixture
local UI, A, B = SC.UI, SC.UIAttention, SC.UIBounds
local saved = { crisis = SC.InfectionCrisis, base = SC.BaseLife, open = UI.open,
    font = fixture.fontHeight, review = UI.reviewAttention }
local opened, scans = 0, 0
UI.open = function() opened = opened + 1 end
local crisis = { id = "crisis:1", subjectId = "alice", subjectName = "Alice", knownToViewer = true,
    stage = "route_pending", pendingReason = "quarantine_area_missing", restriction = "watch",
    unread = true, noticeRevision = 1 }
SC.InfectionCrisis = { summary = function() return { rows = { crisis } } end }
SC.BaseLife = { active = function() return { jobs = {} } end,
    summary = function() scans = scans + 1 error("notification scanned camp supplies") end }
A.reset()
A.update(true)
local signature = A.signature()
assert(A.count() == 1 and opened == 0 and scans == 0,
    "incoming alerts use retained state without opening UI, focusing or scanning supplies")
A.update(true)
assert(A.signature() == signature, "unchanged crises do not produce new notices")
crisis.unread = false
A.update(true)
assert(A.count() == 1 and A.signature() ~= signature, "acknowledgement retains the outstanding issue badge")
crisis.noticeRevision, crisis.unread = 2, true
A.update(true)
assert(A.count() == 1, "a changed decision updates one issue instead of duplicating it")
SC.InfectionCrisis.summary = function() return { rows = {} } end
A.update(true)
assert(A.count() == 0, "resolved decisions clear the badge")

fixture.fontHeight = 16
local w, h = B.collapsedSize(1920, 1080)
assert(w == 64 and h == 80)
local wideW, wideH = B.collapsedSize(3840, 2160)
assert(wideW == w and wideH == h, "resolution alone does not make the launcher oversized")
fixture.fontHeight = 24
local largeW, largeH = B.collapsedSize(1920, 1080)
assert(largeW == 96 and largeH == 120, "launcher scales with the user's text size")
fixture.fontHeight = 16
assert(B.collapsedRect(1920, 1080, "left", 200).x == 6
    and B.collapsedRect(1920, 1080, "right", 200).x == 1850, "both docks retain the small inset")
assert(not UI.launcherContains(0, 0, 64, 80) and UI.launcherContains(32, 40, 64, 80),
    "transparent corners reject clicks while the visible tab accepts them")
local expanded = 0
local launcher = fixture.classes.SCUICollapsedLauncher:new(
    { x = 6, y = 200, width = 64, height = 80, dockSide = "left" },
    { setCollapsed = function() expanded = expanded + 1 end, saveSettings = function() end })
launcher.setCapture = function() end
assert(launcher:onMouseDown(0, 0) == false and not launcher.dragging)
launcher:onMouseDown(32, 40)
launcher:onMouseUp(32, 40)
assert(expanded == 1, "a deliberate click opens the existing roster")
launcher:onMouseDown(32, 40)
launcher.dragDistance = 12
launcher:onMouseUp(32, 40)
assert(expanded == 1, "drag release does not accidentally open the roster")

-- Click the real irreversible-action callback: review is not authorization.
local savedModal, savedRefresh, savedEscape, savedReturn = ISModalDialog, UI.refresh,
    Keyboard.KEY_ESCAPE, Keyboard.KEY_RETURN
local modal, authorized = nil, {}
Keyboard.KEY_ESCAPE, Keyboard.KEY_RETURN = 1, 2
UI.refresh = function() end
ISModalDialog = { new = function(_, x, y, w, h, message, yesNo, target, callback)
    modal = { callback = callback, initialise = function() end,
        addToUIManager = function() end, setVisible = function() end,
        removeFromUIManager = function() end }
    return modal
end }
SC.InfectionCrisis.authorize = function(id, outcome, revision)
    authorized[#authorized + 1] = { id, outcome, revision }; return true
end
local detail = fixture.classes.SCUIDetail:new(0, 0, 300, 300, {})
local panel = ISPanel:new(0, 0, 300, 300)
detail:addCrisisAction(panel, 0, "UI_SC_Base_Outcome_mercy", "crisis:1", "mercy", "authorize", 7, "Alice")
local button = panel.childrenInOrder[1]
assert(#authorized == 0)
button.onClick(button.target, button)
assert(#authorized == 0 and modal, "an explicit review opens confirmation without authorizing")
modal:onKeyRelease(Keyboard.KEY_ESCAPE)
assert(#authorized == 0, "Escape never authorizes an irreversible action")
button.onClick(button.target, button)
button.scDecisionRevision = 8
modal.callback(nil, { internal = "YES" })
assert(#authorized == 1 and authorized[1][1] == "crisis:1" and authorized[1][3] == 7,
    "confirmation preserves the reviewed decision; domain validation rejects stale revisions")
ISModalDialog, UI.refresh, Keyboard.KEY_ESCAPE, Keyboard.KEY_RETURN = savedModal, savedRefresh,
    savedEscape, savedReturn
SC.InfectionCrisis, SC.BaseLife, UI.open, UI.reviewAttention = saved.crisis, saved.base, saved.open, saved.review
fixture.fontHeight = saved.font
A.reset()
SC_TEST_REPORT = (SC_TEST_REPORT or "") .. "; Attention/launcher PASS: retained alerts, no focus/scan, acknowledgement, scaling, corners and drag isolation"
