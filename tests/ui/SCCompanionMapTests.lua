-- SPDX-License-Identifier: MIT

local Map = SurvivorCompanion and SurvivorCompanion.CompanionMap
assert(Map, "SCCompanionMap must be loaded before this test")

local fixture = SCCompanionMapFixture
fixture.records[1] = {
    id = "joined-alice", recruited = true,
    identity = { forename = "Alice" },
    actor = { x = 10, y = 20, z = 0, name = "Wrong Name" },
}
fixture.records[2] = {
    id = "neutral-bob", recruited = false,
    identity = { forename = "Bob" },
    actor = { x = 12, y = 22, z = 0, name = "Bob Neutral" },
}
fixture.records[3] = {
    id = "dead-cara", recruited = true,
    identity = { forename = "Cara" },
    actor = { x = 14, y = 24, z = 0, name = "Cara Dead", dead = true },
}
fixture.records[4] = {
    id = "joined-daryl", recruited = true, factionId = "departed-household",
    actor = { x = 30, y = 40, z = 0, name = "Daryl Dixon" },
}

local rows = Map.rows()
assert(#rows == 2, "only living recruited companions belong on the minimap")
assert(rows[1].name == "Alice" and rows[1].id == "joined-alice")
assert(rows[2].name == "Daryl" and rows[2].id == "joined-daryl")

local map = {
    width = 180,
    height = 120,
    mapAPI = {
        worldToUIX = function(_, x) return x + 5 end,
        worldToUIY = function(_, _, y) return y + 5 end,
    },
    rectangles = {},
    labels = {},
}

function map:drawRect(x, y, width, height, alpha, red, green, blue)
    self.rectangles[#self.rectangles + 1] = {
        x = x, y = y, width = width, height = height,
        alpha = alpha, red = red, green = green, blue = blue,
    }
end

function map:drawText(value, x, y)
    self.labels[#self.labels + 1] = { value = value, x = x, y = y }
end

local installed, installReason = Map.install()
assert(installed == true and installReason == "installed")
ISMiniMapInner.render(map)
assert(map.baseRendered == true and fixture.baseRenderCount == 1,
    "the vanilla multiplayer-style map render must remain in the chain")
assert(#map.rectangles == 4, "each recruited companion needs one red dot with a core")
assert(#map.labels == 4, "each recruited companion needs a shadowed first-name label")
assert(map.labels[1].value == "Alice" and map.labels[3].value == "Daryl")
assert(#fixture.reports == 0, "the minimap overlay must render without diagnostics")

local removed, removeReason = Map.remove()
assert(removed == true and removeReason == "removed")
assert(ISMiniMapInner.render ~= nil)
