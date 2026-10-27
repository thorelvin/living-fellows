-- SPDX-License-Identifier: MIT
local fixture = BasePolicyFixture
local UI = SurvivorCompanion.UI
assert(type(ISUIElement.setHeight) == "function" and type(ISUIElement.getKeepOnScreen) == "function",
    "installed stock UIElement positioning methods are loaded")
-- Negative control: the exact stock addOption -> setHeight path reproduces the
-- screenshot's misplaced first line before any mod-specific geometry is used.
local unclipped = ISTickBox:new(12, 2200, 172, 18, "", nil, nil)
unclipped:initialise()
unclipped:addOption("Native negative control")
assert(unclipped.y == fixture.screenHeight - unclipped:getHeight() and unclipped.y ~= 2200,
    "unparented stock checkbox clamps deep content coordinates to the physical screen")
local attached = ISTickBox:new(12, 2200, 172, 18, "", nil, nil)
attached:initialise()
ISPanel:new(0, 0, 200, 300):addChild(attached)
attached:addOption("Parented native control")
assert(attached.y == 2200, "fixture parenting preserves the stock getKeepOnScreen contract")
UI.text = function(key) return key end
for _, reason in ipairs({ "floor_pickup_animation_replaced", "floor_pickup_animation_failed",
    "floor_pickup_animation_rejected" }) do
    assert(UI.baseFailureReason(reason, true) == "UI_SC_Base_Reason_work_pickup_interrupted",
        "pickup interruptions have a player-facing explanation instead of animation diagnostics")
end
assert(UI.baseFailureReason("path_blocked:blocked_static", true) == "UI_SC_Base_Reason_work_path_blocked",
    "path details do not leak through a compound blocker code")
assert(UI.baseFailureReason("floor_pickup_unverified", true) == "UI_SC_Base_Reason_work_item_unconfirmed",
    "unconfirmed item ownership stays distinct from an interrupted pickup")
assert(UI.baseFailureReason("future_native_callback_failed", true) == nil
    and UI.baseFailureReason("future_native_callback_failed") == "Future native callback failed",
    "terminal callers can refuse unknown diagnostics without changing general menu fallback")
local detail = fixture.classes.SCUIDetail:new(0, 0, 200, 300, {})
local panel = ISPanel:new(0, 0, 200, 300)
local label = "Automatically maintain and sort the base"
local bottom = detail:addBaseToggle(panel, 7, label, "autoMaintain", true)
local tick = panel.childrenInOrder[1]
assert(tick.isTickBox and tick:isSelected(1), "policy uses a selected native checkbox")
assert(tick.tooltip == nil, "fully visible policy has no floating tooltip")
local words = { tick.options[1] }
for index = 2, #panel.childrenInOrder do
    local line = panel.childrenInOrder[index]
    words[#words + 1] = line.name
    assert(line.x == tick.x + tick.boxSize + tick.textGap)
    assert(line.x + line.width <= panel.width - 16, "wrapped label stays in viewport")
    assert(line.y + line.height < bottom, "next policy starts below wrapped label")
end
assert(#words > 1 and table.concat(words, " ") == label, "entire policy label remains visible")
tick:forceClick()
assert(#fixture.calls == 1 and fixture.calls[1].key == "autoMaintain")
assert(fixture.calls[1].selected == false and not tick:isSelected(1))
assert(tick.scSelected == false and detail.feedbackSuccess, "accepted state is remembered")
fixture.accepts = false
tick:forceClick()
assert(not tick:isSelected(1) and not tick.scSelected and not detail.feedbackSuccess,
    "rejected policy edit restores checkbox")
fixture.throws = true
tick:forceClick()
assert(not tick:isSelected(1), "native setter exception restores checkbox")
fixture.throws, fixture.accepts = false, true
fixture.remote = true
local before = #fixture.calls
tick:forceClick()
assert(#fixture.calls == before and not tick:isSelected(1),
    "becoming remote after rendering cannot change policy")
local remotePanel = ISPanel:new(0, 0, 200, 300)
detail:addBaseToggle(remotePanel, 7, "Work outside at night", "allowNight", true)
local disabled = remotePanel.childrenInOrder[1]
assert(not disabled.enable and disabled.disabledOptions[disabled.options[1]])
disabled:forceClick()
assert(#fixture.calls == before and disabled:isSelected(1), "disabled checkbox cannot dispatch")
fixture.remote = false
local setter = SurvivorCompanion.BaseLife.setPolicy
SurvivorCompanion.BaseLife.setPolicy = nil
tick:forceClick()
assert(not tick:isSelected(1), "missing backend restores existing state")
SurvivorCompanion.BaseLife.setPolicy = setter

-- A remote-only tooltip uses native UIManager ownership and must be dismissed
-- when the panel refreshes, even when nested inside a scrolling child.
local tooltip = { visible = true, removed = false }
function tooltip:getIsVisible() return self.visible end
function tooltip:setVisible(value) self.visible = value end
function tooltip:removeFromUIManager() self.removed = true end
disabled.tooltipUI = tooltip
detail.content = remotePanel
detail:addChild(remotePanel)
detail.tab = "unused_for_fixture"
detail:rebuild(true)
assert(not tooltip.visible and tooltip.removed and disabled.tooltipUI == nil,
    "refresh detaches floating checkbox tooltip")
assert(detail.content ~= remotePanel, "refresh replaces old policy controls")
local refreshedPanel = ISPanel:new(0, 0, 200, 300)
detail:addBaseToggle(refreshedPanel, 7, label, "autoMaintain", false)
assert(not refreshedPanel.childrenInOrder[1]:isSelected(1), "refresh reads persisted selection")

UI.text = function(key, ...)
    local arguments = { ... }
    for index, value in ipairs(arguments) do arguments[index] = tostring(value) end
    return key .. (#arguments > 0 and (":" .. table.concat(arguments, ",")) or "")
end
local blocked = { state = "blocked", parked = true, autoRetry = true,
    retryRemainingMs = 180000 }
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobRetryMinutes:3",
    "capped jobs show an automatic retry countdown instead of requiring manual intervention")
blocked.retryRemainingMs = 120001
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobRetryMinutes:3")
blocked.retryRemainingMs = 120000
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobRetryMinutes:2")
blocked.retryRemainingMs = 1
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobRetryMinutes:1")
blocked.retryRemainingMs = 0
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobRetryReady",
    "due work waits for a worker rather than claiming a fresh delay")
blocked.autoRetry = false
assert(UI.baseJobRetryText(blocked) == "UI_SC_Base_JobPaused",
    "manual-only jobs must never promise an automatic retry")
blocked.state = "pending"
assert(UI.baseJobRetryText(blocked) == nil, "pending work has no stale blocked countdown")

local baseRows = {
    { id = "sort", type = "sort_floor", state = "blocked", parked = true,
        autoRetry = true, retryRemainingMs = 180000,
        blocker = "floor_storage_full", target = { floorCategory = "food" } },
    { id = "fire", type = "burn_corpses", state = "blocked",
        autoRetry = false, blocker = "fire_spread" },
    { id = "chef", type = "production", state = "blocked", autoRetry = false,
        blocker = "chef_restart_needs_recovery" },
}
SurvivorCompanion.BaseLife.summary = function()
    return { configured = true, rows = baseRows, jobs = { blocked = 3 } }
end
SurvivorCompanion.BaseLife.blueprintsVisible = function() return false end
UI.humanize = function(value) return tostring(value) end
local information, actions = {}, {}
local function skip(_, _, y) return y end
detail.addMoreNavigation, detail.addSection = skip, skip
detail.buildBaseWatch, detail.addBasePolicySelector = skip, skip
detail.addBaseToggle, detail.buildProductionSection = skip, skip
function detail:addInformationLine(_, y, _, value)
    information[#information + 1] = value
    return y
end
function detail:addBaseManagementAction(_, y, _, action, payload)
    actions[#actions + 1] = { action = action, id = payload.id }
    return y
end
detail:buildBase(panel)
local visible = table.concat(information, "\n")
assert(string.find(visible,
    "UI_SC_Base_FloorStorageFull:food — UI_SC_Base_JobRetryMinutes:3", 1, true),
    "specialized floor-storage reasons retain their automatic retry countdown")
assert(string.find(visible, "fire_spread — UI_SC_Base_JobPaused", 1, true),
    "fire-spread work shows the manual-check state")
assert(not string.find(visible,
    "UI_SC_Base_ChefRestartRecovery — UI_SC_Base_JobPaused", 1, true),
    "uncertain Chef receipts keep their specific recovery instruction without a retry promise")
local manualRetries = {}
for _, action in ipairs(actions) do
    if action.action == "retry_job" then manualRetries[action.id] = true end
end
assert(manualRetries.sort and manualRetries.fire and not manualRetries.chef,
    "Retry now remains available while uncertain Chef receipts retain recovery controls")

ISButton = ISPanel:derive("ISButton")
function ISButton:new(x, y, width, height, title, target, callback)
    local button = ISPanel.new(self, x, y, width, height)
    button.target, button.callback = target, callback
    return button
end
local watchPanel = ISPanel:new(0, 0, 300, 300)
for reason, key in pairs({
    local_view_restore_bridge_unavailable = "UI_SC_View_BridgeUpdateRequired",
    local_view_restore_event_unavailable = "UI_SC_View_RenderUnavailable",
}) do
    SurvivorCompanion.BaseWatch.start = function() return false, reason end
    detail:addBaseWatchAction(watchPanel, 0, "UI_SC_BaseWatch_Start", "start")
    local button = watchPanel.childrenInOrder[#watchPanel.childrenInOrder]
    button.callback(button.target, button)
    assert(detail.feedback == key and not detail.feedbackSuccess,
        "Base Watch capability failures give actionable translated feedback")
end

-- A real camp page exceeds the physical screen before its policies. Exercise
-- every checkbox helper there at both viewport sizes and both font sizes.
local matrixCases = 0
local D = fixture.classes.SCUIDetail
local previousAvailability = UI.commandAvailability
UI.commandAvailability = function() return true end
for _, screenHeight in ipairs({ 720, 1080 }) do
    fixture.screenHeight = screenHeight
    for _, width in ipairs({ 200, 360 }) do
        for _, fontHeight in ipairs({ 16, 24 }) do
            fixture.fontHeight = fontHeight
            local deep = D:new(0, 0, width, 300, { selectedRow = { id = "resident" } })
            local viewport = ISPanel:new(0, 0, width, 300)
            local startY = 2200
            local wrapped = "Allow safe routines and downtime"
            local nextY = deep:addBaseToggle(viewport, startY, wrapped, "allowDowntime", true)
            local policy = viewport.childrenInOrder[1]
            assert(policy.isTickBox and policy.y == startY and policy.parent == viewport,
                "deep native policy checkbox keeps its requested content Y")
            local parts = { policy.options[1] }
            local previousBottom = policy.y + policy:getHeight()
            for index = 2, #viewport.childrenInOrder do
                local continuation = viewport.childrenInOrder[index]
                parts[#parts + 1] = continuation.name
                assert(continuation.y >= previousBottom,
                    "wrapped continuation follows its checkbox without overlap")
                assert(continuation.x == policy.x + policy.boxSize + policy.textGap
                    and continuation.x + continuation.width <= width - 16,
                    "wrapped continuation stays aligned inside the narrow scroll viewport")
                previousBottom = continuation.y + continuation.height
            end
            assert(table.concat(parts, " ") == wrapped and nextY > previousBottom,
                "policy reserves its full actual wrapped height")
            local previousCount = #viewport.childrenInOrder
            local afterSecond = deep:addBaseToggle(viewport, nextY, "Work outside at night", "allowNight", false)
            local second = viewport.childrenInOrder[previousCount + 1]
            assert(second.y == nextY and second.y >= previousBottom and afterSecond > second.y + second:getHeight(),
                "the next policy cannot overlap the preceding checkbox or fragments")
            viewport:setYScroll(-2100)
            assert(policy.y + viewport:getYScroll() == 100
                and second.y + viewport:getYScroll() >= previousBottom - 2100,
                "scrolling preserves one shared offset for checkbox and wrapped label")

            local commandPanel = ISPanel:new(0, 0, width, 300)
            local commandBottom = deep:addBooleanCommand(commandPanel, startY,
                "Follow fan out", "set_follow_fan_out", "fanOut", true)
            local commandTick = commandPanel.childrenInOrder[1]
            assert(commandTick.y == startY and commandBottom > startY + commandTick:getHeight(),
                "boolean command checkboxes keep deep content coordinates")
            local tradePanel = ISPanel:new(0, 0, width, 300)
            local tradeBottom = deep:addTradeChoice(tradePanel, startY, "offer", "faction",
                { item = {}, type = "Log", value = 1 }, true)
            local tradeTick = tradePanel.childrenInOrder[1]
            assert(tradeTick.y == startY and tradeBottom > startY + tradeTick:getHeight(),
                "trade checkboxes keep deep content coordinates")
            assert(tradeTick.x + tradeTick.boxSize + tradeTick.textGap
                + getTextManager():MeasureStringX(UIFont.Small, tradeTick.options[1]) <= width - 16,
                "trade labels fit beside the native checkbox at larger fonts")
            local more = D:new(0, 0, width, 300, {})
            function more:addSection(_, y, key)
                return key == "UI_SC_Section_More" and startY or y + self.metrics.sectionHeight
            end
            function more:addInformationLine(_, y) return y + self.metrics.infoLineHeight end
            local morePanel = ISPanel:new(0, 0, width, 300)
            more:buildMore(morePanel)
            assert(morePanel.childrenInOrder[1].isTickBox and morePanel.childrenInOrder[1].y == startY,
                "nickname visibility checkbox keeps deep content coordinates")
            matrixCases = matrixCases + 1
        end
    end
end
fixture.screenHeight, fixture.fontHeight = 1080, 16
UI.commandAvailability = previousAvailability

-- Readiness and long job queues must never precede the selected companion's
-- job controls. Storage management is the final group even after crisis rows.
local events = {}
local selected = D:new(0, 0, 360, 300, {})
local function record(kind, key, text, payload, confirmation)
    events[#events + 1] = { kind = kind, key = key, text = text,
        payload = payload, confirmation = confirmation }
end
function selected:addMoreNavigation(_, y) record("navigation", "back") return y + 1 end
function selected:addSection(_, y, key) record("section", key) return y + 1 end
function selected:addInformationLine(_, y, key, value) record("information", key, value) return y + 1 end
function selected:addCommandSelector(_, y, _, _, _, command) record("selector", command) return y + 1 end
function selected:addBaseManagementAction(_, y, text, action, payload, confirmation)
    record("action", action, text, payload, confirmation)
    return y + 1
end
function selected:addBaseRecordSelector(_, y, _, _, _, action) record("record", action) return y + 1 end
function selected:addBasePolicySelector(_, y) return y + 1 end
function selected:addBaseToggle(_, y) return y + 1 end
function selected:buildBaseWatch(_, y) return y + 1 end
function selected:buildProductionSection(_, y) record("section", "production") return y + 1 end
local nativeSummary = SurvivorCompanion.BaseLife.summary
local nativeCanRemoveZone = SurvivorCompanion.BaseLife.canRemoveZone
local unnamedZones = {
    { id = "private:zone-parking", name = " \t ", kind = "parking",
        x1 = 10, y1 = 20, x2 = 12, y2 = 22, z = 0 },
    { id = "private:zone-log-yard", kind = "log_yard",
        x1 = 30, y1 = 40, x2 = 32, y2 = 42, z = 0 },
}
UI.booleanText = function(value) return value and "On" or "Off" end
SurvivorCompanion.BaseLife.summary = function()
    return { configured = true, rows = baseRows, jobs = { blocked = 3 },
        zoneRows = unnamedZones,
        storageRows = { { id = "supplies", category = "tools", x = 10, y = 10, z = 0 } } }
end
SurvivorCompanion.BaseLife.canRemoveZone = function() return true end
SurvivorCompanion.BaseLife.resident = function() return { role = "generalist", duty = true } end
selected:buildBase(ISPanel:new(0, 0, 360, 300), { id = "resident", name = "Alice", order = "base_duty" })
local roleIndex, firstAction, firstSection, lastSection
for index, event in ipairs(events) do
    if event.kind == "selector" and event.key == "set_base_role" then roleIndex = index end
    if event.kind == "action" or event.kind == "selector" or event.kind == "record" then firstAction = firstAction or index end
    if event.kind == "section" then firstSection = firstSection or index lastSection = index end
end
assert(roleIndex and firstAction == roleIndex and events[firstSection].key == "UI_SC_Base_Section_Selected",
    "selected companion job selector is first, immediately after More navigation")
assert(events[lastSection].key == "UI_SC_Base_Section_Storages"
    and events[#events].key == "remove_storage",
    "storage management is literally last after maintenance, abandon and crisis groups")
for zoneId, readable in pairs({
    [unnamedZones[1].id] = "Parking area (10, 20, 0)",
    [unnamedZones[2].id] = "Outdoor log yard (30, 40, 0)",
}) do
    local row, focus, remove
    for _, event in ipairs(events) do
        if event.kind == "information" and type(event.text) == "string"
            and string.find(event.text, "UI_SC_Base_ZoneRow:", 1, true)
            and string.find(event.text, readable, 1, true) then row = event end
        if event.payload and event.payload.id == zoneId then
            if event.key == "focus_zone" then focus = event end
            if event.key == "remove_zone" then remove = event end
        end
    end
    assert(row and focus and remove and string.find(focus.text, readable, 1, true)
        and string.find(remove.text, readable, 1, true)
        and string.find(remove.confirmation, readable, 1, true),
        "whitespace and unnamed zones share a readable kind plus coordinates across row, focus, remove and confirmation")
    assert(not string.find(row.text, zoneId, 1, true)
        and not string.find(focus.text, zoneId, 1, true)
        and not string.find(remove.text, zoneId, 1, true)
        and not string.find(remove.confirmation, zoneId, 1, true),
        "zone IDs remain in action data rather than visible management labels")
end
SurvivorCompanion.BaseLife.summary = nativeSummary
SurvivorCompanion.BaseLife.canRemoveZone = nativeCanRemoveZone
SC_TEST_REPORT = "Base policy native checkbox, deep layout (" .. matrixCases .. " cases), section order, zone labels and job retry interactions PASS"
