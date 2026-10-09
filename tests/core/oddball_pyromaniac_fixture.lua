-- SPDX-License-Identifier: MIT
SurvivorCompanion = { GameplayUtil = {}, Registry = {}, Factions = {},
    Diagnostics = {}, FactionRecruitment = {} }
local SC, U = SurvivorCompanion, SurvivorCompanion.GameplayUtil
PyroFixture = { now = 1000, squares = {}, worldItems = {}, lines = {},
    fires = 0, stopCalls = 0, recruitment = 0, diagnostics = {} }
local F = PyroFixture
function U.call(object, method, ...)
    local callback = object and object[method]
    if type(callback) ~= "function" then return nil, false end
    return callback(object, ...), true
end
function U.gridSquare(x, y, z)
    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(z)
    if not F.squares[key] then
        local square = { x = x, y = y, z = z }
        function square:AddWorldInventoryItem(kind)
            local item = { kind = kind, data = {} }
            function item:getFullType() return self.kind end
            function item:getModData() return self.data end
            local world = { item = item }
            function world:getItem() return self.item end
            F.worldItems[#F.worldItems + 1] = world
            return world
        end
        function square:haveFire() return self.fire == true end
        F.squares[key] = square
    end
    return F.squares[key]
end
function U.modData(item) return item.data end
function U.inventory(actor) return actor.inventory end
function U.inventoryItemsDeep(inventory) return inventory or {} end
function U.itemType(item) return item.kind end
function U.isValidActor(actor) return actor and not actor.dead end
function U.distance(left, right)
    return math.sqrt((left.x - right.x) ^ 2 + (left.y - right.y) ^ 2)
end
function U.canSee() return true end
function U.say(actor, line) F.lines[#F.lines + 1] = line end
function U.stableHash() return 1 end
function U.stop() F.stopCalls = F.stopCalls + 1; return true end
function SC.Registry.byId() return { actor = F.earl } end
function SC.Factions.forceStanding(_, standing)
    F.group.standing = standing
    return true
end
function SC.Diagnostics.report(_, _, message, detail)
    F.diagnostics[#F.diagnostics + 1] = message .. tostring(detail)
end
function SC.FactionRecruitment.ask() F.recruitment = F.recruitment + 1; return true end
function SC.FactionRecruitment.startTrial() F.recruitment = F.recruitment + 1; return true end
CharacterStat = { UNHAPPINESS = "UNHAPPINESS" }
F.earl = { x = 11, y = 10, stats = { UNHAPPINESS = 10 } }
function F.earl:getStats() return self.stats end
function F.earl.stats:get(name) return self[name] end
function F.earl.stats:set(name, value) self[name] = value end
F.player = { x = 10, y = 10, inventory = {} }
function getSpecificPlayer() return F.player end
function getNumActivePlayers() return 1 end
function getCell() return F.squares end
IsoFireManager = {}
function IsoFireManager.StartFire(cell, square)
    square.fire = true
    F.fires = F.fires + 1
end
F.group = { id = "pyro-group", standing = "Wary", discovered = false,
    members = { { actorId = "earl" } },
    house = { bounds = { x1 = 9, x2 = 13, y1 = 9, y2 = 13 } },
    oddball = { id = "pyromaniac_earl_kessler", stage = "unmet",
        site = { spawn = { x = 11, y = 10, z = 0 },
            house = { bounds = { x1 = 9, x2 = 13, y1 = 9, y2 = 13 } },
            fuelPosts = { { x = 10, y = 11, z = 0 },
                { x = 12, y = 11, z = 0 },
                { x = 12, y = 12, z = 0 } } } } }
