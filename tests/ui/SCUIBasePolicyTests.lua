-- SPDX-License-Identifier: MIT
local fixture = BasePolicyFixture
local UI = SurvivorCompanion.UI
UI.text = function(key) return key end
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
SC_TEST_REPORT = "Base policy native checkbox and job retry UI interactions PASS"
