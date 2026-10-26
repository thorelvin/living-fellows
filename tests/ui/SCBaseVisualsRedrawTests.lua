-- SPDX-License-Identifier: MIT
local SC, fixture = SurvivorCompanion, SCBaseVisualsFixture
local Visuals = SC.BaseVisuals
local originalHighlight = addAreaHighlightForPlayer
local inUIDraw, uiStamp, retained, submissions = false, 0, {}, 0

-- Match 42.21 FBORenderAreaHighlights: insertions carry UIManager.uiRenderTimeMS;
-- world rendering discards old timestamps, retaining every current insertion.
function addAreaHighlightForPlayer(...)
    assert(inUIDraw, "area highlights must be submitted from the UI redraw, never a world tick")
    local entry = { stamp = uiStamp, args = { ... } }
    retained[#retained + 1] = entry
    submissions = submissions + 1
    originalHighlight(...)
end

local function uiDraw()
    uiStamp = uiStamp + 1
    inUIDraw = true
    Events.OnPreUIDraw.callback()
    inUIDraw = false
    assert(#fixture.reports == 0, "the render callback must not swallow a wrong-phase submission")
end

local function worldDraw(expected)
    local current, signatures = {}, {}
    for _, entry in ipairs(retained) do
        if entry.stamp == uiStamp then
            current[#current + 1] = entry
            local a = entry.args
            local key = table.concat({ a[1], a[2], a[3], a[4], a[5], a[6] }, ":")
            assert(not signatures[key], "a mark accumulated duplicate tint layers between UI redraws")
            signatures[key] = a[10]
        end
    end
    retained = current
    assert(#current == expected, "visible highlights must survive intervening world frames")
    return signatures
end

assert(Visuals.install())
Visuals.setEnabled(true)
local scenarios = 0
for _, worldFps in ipairs({ 30, 60, 120 }) do
    for _, uiFps in ipairs({ 15, 30, 60 }) do
        retained, submissions, fixture.fills = {}, 0, {}
        uiDraw()
        local before = worldDraw(3)
        local nextUI, redraws = 1000 / uiFps, 1
        for frame = 1, worldFps do
            fixture.clock = fixture.clock + 1000 / worldFps
            local current = worldDraw(3)
            for key, alpha in pairs(before) do
                assert(current[key] == alpha, "mark opacity changed with the world/UI frame ratio")
            end
            if frame * 1000 / worldFps + 0.001 >= nextUI then
                uiDraw()
                redraws = redraws + 1
                nextUI = frame * 1000 / worldFps + 1000 / uiFps
            end
            -- The game fires OnRenderTick after its world and UI rendering.
            Events.OnRenderTick.callback()
            if frame % 7 == 0 then Visuals.refresh() end
        end
        assert(submissions == redraws * 3, "each UI redraw submits each mark exactly once")
        scenarios = scenarios + 1
    end
end

-- UI-only updates must also observe invalidations without a preceding world tick.
Visuals.focus("storage", "storage:food")
fixture.fills = {}
uiDraw()
assert(fixture.fills[3].red == 1 and fixture.fills[3].green == 1,
    "storage focus updates the next UI redraw")
local storage = table.remove(fixture.summary.storageRows, 1)
Visuals.refresh()
uiDraw()
worldDraw(2)
table.insert(fixture.summary.storageRows, 1, storage)
Visuals.refresh()
fixture.player.z = 1
uiDraw()
worldDraw(2)
fixture.player.z = 0
uiDraw()
worldDraw(3)
Visuals.setEnabled(false)
uiDraw()
worldDraw(0)

fixture.draft = { kind = "work", first = { x = 11, y = 11, z = 0 },
    lockedEndpoint = { x = 15, y = 14, z = 0 } }
uiDraw()
worldDraw(1)
for index = 1, 8 do Events.OnRenderTick.callback() end
worldDraw(1)
fixture.draft = nil
uiDraw()
worldDraw(0)

fixture.summary.zoneRows[2].roomGroupId = "room:redraw"
Visuals.flashRoom("room:redraw")
uiDraw()
worldDraw(1)
fixture.clock = fixture.clock + 3000
uiDraw()
worldDraw(0)

-- Blueprint fills use the same UI lifetime, including player-zero split guides.
SC.BaseLife.visualRows = function() return fixture.summary end
local originalCell = getCell
getCell = function() return { getGridSquare = function() return {} end } end
SC.ConstructionPlanner = { renderBuildGhost = function() return true end }
fixture.summary.constructionRows = {
    { id = "floor", type = "build", kind = "floor", x = 12, y = 12, z = 0 },
    { id = "wall", type = "build", kind = "wall", x = 14, y = 12, z = 0 },
}
Visuals.refresh()
uiDraw()
worldDraw(1)
fixture.splitScreen = true
uiDraw()
worldDraw(2)
for index = 1, 8 do Events.OnRenderTick.callback() end
worldDraw(2)
fixture.summary.blueprints = false
Visuals.refresh()
uiDraw()
worldDraw(0)

Visuals.remove()
getCell = originalCell
addAreaHighlightForPlayer = originalHighlight
SC_TEST_REPORT = "Base overlay UI-clock retention PASS: " .. scenarios
    .. " world/UI redraw ratios, refresh, focus, removal, floors, previews, room flashes and split blueprints"
