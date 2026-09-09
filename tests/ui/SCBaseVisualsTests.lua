-- SPDX-License-Identifier: MIT

local Visuals = SurvivorCompanion and SurvivorCompanion.BaseVisuals
assert(Visuals, "SCBaseVisuals must be loaded before this test")
local fixture = SCBaseVisualsFixture

local installed, reason = Visuals.install()
assert(installed == true and reason == "installed")
assert(Events.OnRenderTick.callback == Visuals.onRenderTick)
assert(Events.OnPreUIDraw.callback == Visuals.onPreUIDraw)
assert(Visuals.isInstalled() == true)

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
assert(#fixture.labels == 6, "two zones and one storage need shadowed labels")
assert(fixture.labels[1].value == "Camp area"
        and fixture.labels[3].value == "Workshop"
        and fixture.labels[5].value == "Food",
    "labels must identify both named zones and localized storage categories")

Visuals.focus("zone", "zone:work")
fixture.lines = {}
Events.OnRenderTick.callback()
local focusedLines = 0
for _, line in ipairs(fixture.lines) do
    if line.thickness == 3.0 then focusedLines = focusedLines + 1 end
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
local removed, removeReason = Visuals.remove()
assert(removed == true and removeReason == "removed")
assert(Events.OnRenderTick.callback == nil and Events.OnPreUIDraw.callback == nil)
assert(Visuals.isInstalled() == false)
assert(#fixture.reports == 0, "normal rendering must not emit diagnostics")
