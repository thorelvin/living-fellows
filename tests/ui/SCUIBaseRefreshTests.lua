-- SPDX-License-Identifier: MIT
local SC, UI = SurvivorCompanion, SurvivorCompanion.UI
local savedCrisis = SC.InfectionCrisis
local crises = { rows = {}, history = {} }
SC.InfectionCrisis = { summary = function() return crises end }
local base = { configured = true, name = "Camp", zoneRows = {}, storageRows = {},
    residentRows = { { id = "resident", role = "generalist", duty = true } },
    rows = { { id = "sort", state = "blocked", autoRetry = true, retryRemainingMs = 180000 } },
    operations = { policies = { allowNight = true } } }
SC.BaseLife.summary = function() return base end
local row = { id = "resident", name = "Alice", order = "base_duty", recruited = true,
    health = 77.01, hunger = 45.01, activity = "Scavenging", distance = 0.5 }
local roster = { items = { { item = row, text = row.name } }, selected = 1 }
function roster:getYScroll() return -64 end
local root = setmetatable({ roster = roster, selectedId = row.id, selectedTab = "base" },
    { __index = BasePolicyFixture.classes.SCUIRoot })
local rebuilds, refreshes = 0, 0
root.detail = { tab = "base" }
function root.detail:rebuild(preserveScroll)
    assert(preserveScroll, "scheduled updates preserve the current scroll position")
    rebuilds = rebuilds + 1
    self.displayedCompanionId = root.selectedId
    self.displayedTab = self.tab
end
function root.detail:refreshValues() refreshes = refreshes + 1 return true end
root:onRosterSelectionChanged(1, true)
assert(rebuilds == 1)
local function refresh()
    local copy = {}
    for key, value in pairs(row) do copy[key] = value end
    root.preparedRefreshEntries = { copy }
    root:refreshRoster(nil, nil, true)
    row = copy
end
for index = 1, 12 do
    row.health, row.hunger, row.distance = 77 + index / 100, 45 + index / 100, index * 3
    row.activity = index % 2 == 0 and "Scavenging" or "Base work"
    row.actionSummary = { phase = "moving", remainingMs = index * 100 }
    base.rows[1].retryRemainingMs = 180000 - index * 500
    refresh()
    assert(rebuilds == 1, "ordinary roster values must not rebuild the Base page")
    assert(roster.items[1].item.health == row.health and root.selectedRow.activity == row.activity,
        "keeping Base controls must still update live roster data")
end
assert(refreshes == 12, "the existing controls still refresh values and availability")
local function changed(message)
    local before = rebuilds
    refresh()
    assert(rebuilds == before + 1, message)
end
row.name = "Alice Smith"
changed("renaming the selected resident updates Base")
row.order = "follow"
changed("leaving base duty updates the role controls")
base.residentRows[1].role = "woodcutter"
changed("a base role change updates the page")
base.operations.policies.allowNight = false
changed("base policy changes still update the page")
base.zoneRows[1] = { id = "zone", kind = "work", x1 = 10, y1 = 10, x2 = 12, y2 = 12, z = 0 }
changed("marking an area updates Base management")
base.storageRows[1] = { id = "storage", category = "tools", x = 10, y = 10, z = 0 }
changed("marking storage updates Base management")
base.rows[1].retryRemainingMs = 120000
changed("the displayed retry-minute boundary still refreshes")
local before = rebuilds
refresh()
assert(rebuilds == before, "an unchanged base reuses the existing controls")
local crisis = { id = "crisis-1", subjectId = "resident", subjectName = "Alice Smith",
    phase = "deliberating", strategy = "watch", infectionLevel = 89.1,
    knownToViewer = true, finalAuthorized = false, subjectIsPlayer = false }
crises.rows = { crisis }
changed("a new crisis appears without depending on another base change")
local function unchanged(message)
    local count = rebuilds
    refresh()
    assert(rebuilds == count, message)
end
crisis.infectionLevel = 89.9
row.health, row.hunger = 74.9, 46.1
unchanged("fractional infection and ordinary health changes keep the existing Base controls")
crisis.infectionLevel = 90
changed("crossing the infection threshold refreshes newly eligible crisis actions")
crisis.infectionLevel = 90.2
crises.history = { { id = crisis.id, at = 1001 } }
unchanged("unchanged displayed infection and historical timestamps do not rebuild Base")
crisis.infectionLevel = 91
changed("the displayed infection percentage remains current")
crisis.phase = "resolved"
changed("crisis phase changes refresh its actions")
crisis.outcome = "quarantine"
changed("a changed crisis outcome refreshes its actions")
crisis.finalAuthorized = true
changed("final authorization retires the obsolete crisis choices")
crisis.knownToViewer = false
changed("changed crisis knowledge refreshes the visible details and controls")
crisis.restriction = "quarantine"
changed("crisis restrictions refresh even without a resident-row change")
crisis.subjectName = "Alice"
changed("crisis subject names refresh independently of the selected resident")
crises.rows = {}
changed("a closed crisis disappears without an unrelated roster change")
unchanged("a stable crisis list retains Base controls")
SC.InfectionCrisis = savedCrisis
SC_TEST_REPORT = SC_TEST_REPORT .. "; Base refresh PASS: ordinary live values retain controls; identity, duty, roles, policies, markings, retry text and crisis changes refresh"
