-- SPDX-License-Identifier: MIT

local Visuals = SurvivorCompanion and SurvivorCompanion.BaseVisuals
assert(Visuals, "SCBaseVisuals must be loaded before this test")
local fixture = SCBaseVisualsFixture

local installed, reason = Visuals.install()
assert(installed == true and reason == "installed")
assert(Events.OnRenderTick.callback == Visuals.onRenderTick)
assert(Events.OnPreUIDraw.callback == Visuals.onPreUIDraw)
assert(Visuals.isInstalled() == true)

Events.OnPreUIDraw.callback()
assert(#fixture.labels == 2 and fixture.labels[1].value == "Addy"
        and fixture.labels[2].value == "Addy",
    "a recruited visible companion needs one shadowed first-name label even when base visuals are hidden; labels="
        .. tostring(#fixture.labels) .. " report="
        .. tostring(fixture.reports[1] and fixture.reports[1][4]))
assert(fixture.labels[2].x == 321 - fixture.companion.renderOffsetX / fixture.zoom
        and fixture.labels[2].y == 222
            - (fixture.companion.renderOffsetY
                + fixture.config.companionNameLabelHeadClearance) / fixture.zoom
            - 14 - fixture.config.companionNameLabelOffsetY
        and fixture.nameCoordsCall == nil,
    "companion names must project through the player's explicit camera")
assert(fixture.labels[2].red == 0.84 and fixture.labels[2].green == 0.92,
    "unselected companion names must keep their usual blue color")
fixture.labels = {}

fixture.splitScreen = true
SurvivorCompanion.UI = { instance = { selectedId = "sc-addy" } }
Events.OnPreUIDraw.callback()
assert(#fixture.labels == 4 and fixture.labels[2].x == 318
        and fixture.labels[4].x == 1278
        and fixture.labels[2].y == fixture.labels[4].y,
    "each split-screen view must anchor the same companion over its own camera")
assert(fixture.labels[2].red == 0.99 and fixture.labels[2].green == 0.86
        and fixture.labels[4].red == 0.99 and fixture.labels[4].green == 0.86,
    "the roster-selected companion's overhead name must be gold in each view")
fixture.labels = {}
fixture.cameraShift[0] = 1000
Events.OnPreUIDraw.callback()
assert(#fixture.labels == 2 and fixture.labels[2].x == 1278,
    "a name outside the first viewport must not fly across the second view")
fixture.cameraShift[0] = nil
local originalSecondPlayer = fixture.secondPlayer
fixture.secondPlayer = fixture.companion
fixture.otherCompanion = setmetatable({ x = 13, y = 11, z = 0,
    square = fixture.companion.square, speech = "",
    renderOffsetX = 6, renderOffsetY = -10 },
    { __index = fixture.companion })
fixture.records[2] = { id = "sc-beth", actor = fixture.otherCompanion,
    recruited = true, identity = { forename = "Beth" }, runtime = {} }
SurvivorCompanion.UI.instance.selectedId = "sc-beth"
fixture.labels = {}
Events.OnPreUIDraw.callback()
assert(#fixture.labels == 6 and fixture.labels[2].value == "Addy"
        and fixture.labels[4].value == "Beth"
        and fixture.labels[6].value == "Beth"
        and fixture.labels[6].x > 960,
    "a companion leading the second view sees teammates' names there, not her own")
assert(fixture.labels[2].red == 0.84 and fixture.labels[4].red == 0.99
        and fixture.labels[6].red == 0.99,
    "changing roster selection must return the old name to blue and turn the new one gold")
fixture.records[2] = nil
fixture.otherCompanion = nil
fixture.secondPlayer = originalSecondPlayer
fixture.splitScreen = false
SurvivorCompanion.UI = nil
fixture.labels = {}

Events.OnRenderTick.callback()
assert(#fixture.lines == 0, "the persistent layout must be opt-in")
assert(#fixture.foodObject.calls == 0, "disabled visualization must not touch storage")

local enabled, enabledState = Visuals.setEnabled(true)
assert(enabled == true and enabledState == true)
Events.OnRenderTick.callback()
local status = Visuals.status()
assert(status.enabled == true and status.visibleZones == 2 and status.visibleStorages == 1,
    "only nearby records on the player's floor may enter the render cache")
assert(#fixture.lines == 8, "each visible zone needs a four-line isometric perimeter")
assert(#fixture.foodObject.calls == 2, "storage needs an outline and category color")
assert(#fixture.upperObject.calls == 0, "storage on another floor must remain untouched")
assert(fixture.foodObject.calls[1].name == "setOutlineHighlight"
        and fixture.foodObject.calls[1].args[1] == 0
        and fixture.foodObject.calls[1].args[2] == true,
    "storage highlight must be scoped to the local player")

Events.OnPreUIDraw.callback()
assert(#fixture.labels == 8, "base records and the recruited companion need shadowed labels")
assert(fixture.labels[1].value == "Camp area"
        and fixture.labels[3].value == "Workshop"
        and fixture.labels[5].value == "Food" and fixture.labels[7].value == "Addy",
    "labels must identify zones, localized storage categories, and the companion first name")

assert(#fixture.fills == 3 and fixture.fills[1].player == 0
        and fixture.fills[1].x1 == 8 and fixture.fills[1].x2 == 19
        and fixture.fills[1].alpha < fixture.fills[2].alpha
        and fixture.fills[2].red == 0.96,
    "each visible zone needs a colored floor tint, fainter for the camp area")
assert(fixture.fills[3].x1 == 13 and fixture.fills[3].y1 == 13
        and fixture.fills[3].x2 == 14 and fixture.fills[3].y2 == 14
        and fixture.fills[3].green == 0.86,
    "registered storage needs a tile in its category color under the container")
for _, line in ipairs(fixture.lines) do
    assert(line.thickness == math.floor(line.thickness),
        "Build 42 renderIsoLine takes a whole-number thickness")
end
assert(#fixture.legend == 4 and fixture.legend[1].value == "Base layout"
        and fixture.legend[2].value == "  Area" and fixture.legend[3].value == "  Work"
        and fixture.legend[3].red == 0.96 and fixture.legend[4].value == "  Food storage",
    "the legend must name each visible zone kind and storage category in its color")
fixture.legend = {}

fixture.splitScreen = true
fixture.config.baseLayoutLegendX = 1100
fixture.lines, fixture.fills, fixture.labels = {}, {}, {}
Events.OnRenderTick.callback()
Events.OnPreUIDraw.callback()
assert(#fixture.lines == 0 and #fixture.fills == 3
        and fixture.fills[1].player == 0
        and fixture.fills[2].player == 0
        and fixture.fills[3].player == 0,
    "split-screen areas must use player-zero highlights without current-camera lines")
local splitOutline = fixture.foodObject.calls[#fixture.foodObject.calls - 1]
assert(splitOutline.name == "setOutlineHighlight"
        and splitOutline.args[1] == 0 and splitOutline.args[2] == true,
    "storage object outlines must remain scoped to the primary player in split screen")
assert(#fixture.labels == 10 and fixture.labels[1].value == "Camp area"
        and fixture.labels[3].value == "Workshop"
        and fixture.labels[5].value == "Food"
        and fixture.labels[1].x < 960 and fixture.labels[3].x < 960
        and fixture.labels[5].x < 960
        and fixture.labels[10].x > 960,
    "base area labels must stay in the primary viewport while companion names remain per view")
assert(#fixture.legend == 4 and fixture.legend[1].x < 960
        and fixture.legend[4].x < 960,
    "the base legend must move inside the narrower primary viewport")
fixture.splitScreen = false
fixture.config.baseLayoutLegendX = nil
fixture.lines, fixture.fills, fixture.labels, fixture.legend = {}, {}, {}, {}

fixture.companion.square.visible = false
fixture.labels = {}
Events.OnPreUIDraw.callback()
assert(#fixture.labels == 6,
    "companion names must not render through a wall or outside the player's visible squares")
fixture.companion.square.visible = true
fixture.companion.speech = "One zombie ahead."
fixture.labels = {}
Events.OnPreUIDraw.callback()
assert(#fixture.labels == 6, "active overhead speech must own the companion head-text lane")
fixture.companion.speech = ""

Visuals.focus("zone", "zone:work")
fixture.lines = {}
Events.OnRenderTick.callback()
local focusedLines = 0
for _, line in ipairs(fixture.lines) do
    if line.thickness == 4 then focusedLines = focusedLines + 1 end
end
assert(focusedLines == 4, "the selected zone must use a stronger perimeter")

Visuals.focus("storage", "storage:food")
fixture.foodObject.calls = {}
Events.OnRenderTick.callback()
local finalColor = fixture.foodObject.calls[#fixture.foodObject.calls]
assert(finalColor.name == "setOutlineHighlightCol"
        and finalColor.args[2] == 1 and finalColor.args[3] == 1
        and finalColor.args[4] == 1,
    "the selected storage container must use a white focus outline")

Visuals.setEnabled(false)
local clearCall = fixture.foodObject.calls[#fixture.foodObject.calls]
assert(clearCall.name == "setOutlineHighlight" and clearCall.args[2] == false,
    "turning visualization off must clear owned object outlines")
assert(Visuals.status().focusId == nil, "turning visualization off must clear focus")

fixture.draft = { kind = "work", first = { x = 11, y = 11, z = 0 } }
fixture.lines, fixture.circles = {}, {}
Events.OnRenderTick.callback()
assert(#fixture.lines == 4 and #fixture.circles == 2,
    "zone creation needs a live perimeter and two corner markers even while layout is hidden")
assert(fixture.lines[1].red < 1,
    "a valid draft inside the camp must retain its zone color")

fixture.draft.lockedEndpoint = { x = 15, y = 14, z = 0 }
fixture.mouseX, fixture.mouseY = 500, 500
fixture.lines, fixture.circles = {}, {}
Events.OnRenderTick.callback()
assert(#fixture.lines == 4 and #fixture.circles == 2
        and fixture.circles[2].x == 15.5 and fixture.circles[2].y == 14.5
        and fixture.lines[1].red < 1,
    "a right-clicked endpoint must remain fixed while the mouse navigates the menu")

fixture.draft.lockedEndpoint = nil
fixture.mouseX, fixture.mouseY = 500, 500
fixture.lines, fixture.circles = {}, {}
Events.OnRenderTick.callback()
assert(#fixture.lines == 4 and fixture.lines[1].red == 1
        and fixture.lines[1].green == 0.08,
    "an invalid draft outside the camp must preview in red")

ISCoordConversion = nil
IsoUtils = {
    XToIso = function(x) return x / 10 end,
    YToIso = function(_, y) return y / 10 end,
    XToScreen = function(x) return x * 10 + 3 end,
    YToScreen = function(_, y) return y * 10 + 4 end,
}
function getCameraOffX() return 3 end
function getCameraOffY() return 4 end
fixture.mouseX, fixture.mouseY = 140, 160
fixture.lines, fixture.circles = {}, {}
Events.OnRenderTick.callback()
assert(#fixture.lines == 4 and #fixture.circles == 2
        and fixture.lines[1].red < 1,
    "native IsoUtils projection must support clients without the server-side helper")

fixture.draft = nil
local previousCell = getCell
getCell = function() return { getGridSquare = function(_, x, y, z)
    if x == 12 and y == 12 and z == 0 then return {} end
    return nil
end } end
local ghosts, barricadeGhosts = 0, 0
SurvivorCompanion.ConstructionPlanner = {
    renderBuildGhost = function(recipe, face, x, y, z)
        assert((recipe == "wood_wall" and face == 2
                or recipe == "wood_floor" and face == 1)
            and x == 12 and y == 12 and z == 0)
        ghosts = ghosts + 1
        return true
    end,
    renderBarricadeGhost = function(row, color, alpha)
        assert(row.type == "barricade" and row.x == 12 and row.y == 12
            and row.z == 0 and row.north == true and row.side == "opposite"
            and color.r > 0 and alpha > 0)
        barricadeGhosts = barricadeGhosts + 1
        return true
    end,
}
fixture.summary.constructionRows = { {
    id = "job:barricade", type = "barricade",
    x = 12, y = 12, z = 0, north = true, side = "opposite",
    state = "pending",
}, {
    id = "job:blueprint", type = "build", kind = "wall",
    x = 12, y = 12, z = 0, face = 2,
    stages = { "wood_frame", "wood_wall" }, state = "pending",
}, {
    id = "job:floor", type = "build", kind = "floor",
    x = 12, y = 12, z = 0, face = 1,
    stages = { "wood_floor" }, state = "pending",
} }
fixture.summary.blueprints = true
fixture.clock = fixture.clock + 500
fixture.lines, fixture.fills = {}, {}
Events.OnRenderTick.callback()
assert(ghosts == 2 and barricadeGhosts == 1,
    "queued builds and barricades must render outside Base Layout mode")
assert(#fixture.lines == 8 and #fixture.fills == 1
        and fixture.lines[1].x1 == 12 and fixture.lines[1].y1 == 12
        and fixture.lines[1].x2 == 13 and fixture.lines[1].y2 == 12
        and fixture.lines[2].z1 == 1 and fixture.lines[3].z2 == 1
        and fixture.fills[1].x1 == 12 and fixture.fills[1].x2 == 13,
    "wall plans need an upright edge and floor plans a filled tile after placement")
fixture.splitScreen = true
fixture.clock = fixture.clock + 500
fixture.lines, fixture.fills = {}, {}
Events.OnRenderTick.callback()
assert(ghosts == 2 and barricadeGhosts == 1
        and #fixture.lines == 0 and #fixture.fills == 3
        and fixture.fills[1].player == 0
        and fixture.fills[2].player == 0
        and fixture.fills[3].player == 0,
    "split-screen construction guides must stay in the player view without shared ghost sprites")
fixture.splitScreen = false
fixture.summary.blueprints = false
fixture.clock = fixture.clock + 500
fixture.lines, fixture.fills = {}, {}
Events.OnRenderTick.callback()
assert(ghosts == 2 and barricadeGhosts == 1
        and #fixture.lines == 0 and #fixture.fills == 0,
    "hidden construction blueprints must stop rendering")
assert(#fixture.reports == 0, "normal rendering must not emit diagnostics")
fixture.summary.blueprints = true
SurvivorCompanion.ConstructionPlanner.renderBarricadeGhost = function()
    error("test sprite failure")
end
fixture.clock = fixture.clock + 500
Events.OnRenderTick.callback()
assert(ghosts == 4 and #fixture.reports == 1
        and fixture.reports[1][1] == "base-visuals-barricade",
    "one broken barricade ghost must not suppress the next build ghost")
fixture.summary.constructionRows = {}
Visuals.refresh()
fixture.clock = fixture.clock + 500
fixture.lines, fixture.fills = {}, {}
Events.OnRenderTick.callback()
assert(#fixture.lines == 0 and #fixture.fills == 0 and ghosts == 4,
    "removing a saved plan must clear its persistent guide")
fixture.reports = {}
SurvivorCompanion.ConstructionPlanner = nil
getCell = previousCell
local removed, removeReason = Visuals.remove()
assert(removed == true and removeReason == "removed")
assert(Events.OnRenderTick.callback == nil and Events.OnPreUIDraw.callback == nil)
assert(Visuals.isInstalled() == false)
assert(#fixture.reports == 0, "normal rendering must not emit diagnostics")
