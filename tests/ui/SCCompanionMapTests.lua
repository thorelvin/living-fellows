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
fixture.factions[1] = {
    id = "faction-rangers", name = "Ashwood Rangers", discovered = true,
    lifecycle = "settled", standing = "Trusted",
    location = { coordinates = { x = 60, y = 35, z = 0 } },
    house = { anchor = { x = 1, y = 1, z = 0 } },
}
fixture.factions[2] = {
    id = "faction-hidden", name = "Hidden Household", discovered = false,
    lifecycle = "settled", standing = "Wary",
    location = { coordinates = { x = 70, y = 45, z = 0 } },
}
fixture.factions[3] = {
    id = "faction-destroyed", name = "Lost Patrol", discovered = true,
    lifecycle = "destroyed", standing = "Wary",
    house = { anchor = { x = 80, y = 55, z = 0 } },
}
fixture.factions[4] = {
    id = "faction-hostile", name = "Red Knives", discovered = true,
    lifecycle = "hostile", standing = "Hostile",
    house = { anchor = { x = 95, y = 65, z = 0 } },
}
fixture.factions[5] = {
    id = "faction-bandit", name = "The Ash Creek Jackals", discovered = true,
    archetype = "bandit_camp", lifecycle = "settled", standing = "Hostile",
    location = { coordinates = { x = 120, y = 75, z = 0 } },
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
    textures = {},
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


function map:drawTextureScaled(texture, x, y, width, height, alpha, red, green, blue)
    self.textures[#self.textures + 1] = {
        texture = texture, x = x, y = y, width = width, height = height,
        alpha = alpha, red = red, green = green, blue = blue,
    }
end

local factionRows = Map.factionRows()
assert(#factionRows == 3, "only known living factions belong on the world map")
assert(factionRows[1].name == "Ashwood Rangers" and factionRows[1].x == 60,
    "persisted location coordinates must take precedence over the house fallback")
assert(factionRows[2].name == "Red Knives" and factionRows[2].x == 95,
    "the house anchor must remain a compatibility fallback")
assert(factionRows[3].name == "The Ash Creek Jackals"
        and factionRows[3].archetype == "bandit_camp",
    "discovered bandit camps retain their archetype in map rendering data")

local installed, installReason = Map.install()
assert(installed == true and installReason == "installed")
ISMiniMapInner.render(map)
assert(map.baseRendered == true and fixture.baseRenderCount == 1,
    "the vanilla multiplayer-style map render must remain in the chain")
assert(#map.rectangles == 4, "each recruited companion needs one red dot with a core")
assert(#map.labels == 4, "each recruited companion needs a shadowed first-name label")
assert(map.labels[1].value == "Alice" and map.labels[3].value == "Daryl")
assert(#fixture.reports == 0, "the minimap overlay must render without diagnostics")

ISWorldMap.render(map)
assert(map.worldMapBaseRendered == true and fixture.worldMapBaseRenderCount == 1,
    "the vanilla full world-map render must remain in the chain")
assert(#map.textures == 3, "each known living faction needs one native house symbol")
assert(map.textures[1].texture.path == "media/ui/LootableMaps/map_house.png")
assert(map.textures[1].width == 16 and map.textures[1].height == 16)
assert(map.textures[2].red > map.textures[2].green,
    "hostile faction houses must be visually distinguishable")
assert(map.textures[3].red > map.textures[2].red,
    "bandit camps need a stronger red house marker than other hostile factions")
assert(#map.labels == 10, "faction names need the same readable small-font shadow treatment")
assert(map.labels[5].value == "Ashwood Rangers" and map.labels[7].value == "Red Knives")
assert(map.labels[9].value == "The Ash Creek Jackals")
assert(#fixture.reports == 0, "the world-map overlay must render without diagnostics")
assert(Map.lastFactionDrawCount == 3,
    "the live harness must be able to confirm the actual world-map draw count")

local removed, removeReason = Map.remove()
assert(removed == true and removeReason == "removed")
assert(ISMiniMapInner.render ~= nil)
assert(ISWorldMap.render ~= nil)
