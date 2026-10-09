-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local actors, groups = {}, {}
local now, finalCalls = 1000, 0
local function actor(id, x)
    local value = { id = id, x = x, y = 0, z = 0, inv = { items = {} },
        medical = { alive = true, bites = 0, knoxInfected = false } }
    actors[id] = value
    return value
end
local function group(id)
    local g = { id = id, standing = "Wary", members = {},
        oddball = { id = "knox_defense_league", stage = "unmet",
            site = { memberSpawns = {} } } }
    for index = 1, 4 do
        local a = actor(id .. ":" .. index, index - 1)
        g.members[index] = { key = "member-" .. index, actorId = a.id,
            role = index == 1 and "leader" or index == 2
                and "inspector" or "rifleman" }
        g.oddball.site.memberSpawns[index] = { x = index - 1, y = 0, z = 0 }
    end
    groups[id] = g
    return g
end
local player = actor("player", 1)
SC.GameplayUtil = {
    idOf = function(value) return value.id end,
    isValidActor = function(value) return value and not value.dead end,
    isDead = function(value) return value.dead == true end,
    canSee = function() return true end,
    nowMs = function() return now end,
    position = function(value) return value.x, value.y, value.z end,
    distance = function(a, b)
        return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    end,
    inventory = function(value) return value.inv end,
    inventoryItemsDeep = function(value) return value.items end,
    itemType = function(value) return value.kind end,
    addItem = function(inv, kind)
        local item = { kind = kind }
        inv.items[#inv.items + 1] = item
        return item
    end,
    call = function(value, name, ...)
        if not value then return nil, false end
        if name == "setName" then value.name = (...) return true, true end
        if name == "setCurrentAmmoCount" then value.ammo = (...) return true, true end
        if name == "setPrimaryHandItem" then value.primary = (...) return true, true end
        if name == "setSecondaryHandItem" then value.secondary = (...) return true, true end
        return nil, false
    end,
    say = function(value, line) value.lastLine = line return true end,
}
SC.Registry = {
    byId = function(id)
        return actors[id] and { id = id, actor = actors[id],
            recruited = id == "bitten" or id == "clean" }
    end,
    living = function()
        local result = {}
        for id, value in pairs(actors) do
            if (id == "bitten" or id == "clean") and not value.dead then
                result[#result + 1] = value
            end
        end
        return result
    end,
}
SC.Medical = { assess = function(value) return value.medical end }
SC.Factions = { forceStanding = function(id, standing)
    groups[id].standing = standing
    return true
end }
SC.NativeActions = { performEndOfLife = function(inspector, outcome, target)
    assert(inspector == actors["infected:1"])
    assert(outcome == "mercy")
    finalCalls = finalCalls + 1
    if finalCalls == 1 then return true, "native_final_attack_started" end
    target.dead = true
    return true, "native_final_injury_applied"
end }

local League = SC.OddballDefenseLeague
local cleanGroup = group("clean_group")
for _, member in ipairs(cleanGroup.members) do
    assert(League.onSpawn(cleanGroup, actors[member.actorId]))
end
assert(#actors["clean_group:1"].inv.items == 2)
assert(actors["clean_group:1"].inv.items[1].ammo == 20)
assert(actors["clean_group:2"].inv.items[1].ammo == 6)
assert(League.onSpawn(cleanGroup, actors["clean_group:1"]))
assert(#actors["clean_group:1"].inv.items == 2, "weapon must not duplicate")
actor("clean", 1)
assert(League.pulse(cleanGroup, player, now))
assert(cleanGroup.oddball.stage == "inspection")
assert(League.action(cleanGroup, "submit_check", player))
assert(cleanGroup.oddball.stage == "passed")
assert(#player.inv.items == 1 and player.inv.items[1].kind == "Base.Badge")

local infected = group("infected")
local patient = actor("bitten", 1)
patient.medical.knoxInfected = true -- hidden infection counts even without visible bite
League.pulse(infected, player, now)
assert(League.action(infected, "submit_check", player))
assert(infected.oddball.stage == "demand")
assert(League.action(infected, "lie", player))
assert(infected.oddball.stage == "demand", "lying must not bypass examination")
assert(League.action(infected, "surrender", player))
assert(infected.oddball.stage == "execution")
assert(League.pulse(infected, player, now + 500))
assert(League.pulse(infected, player, now + 1000))
assert(patient.dead == true and infected.oddball.executionApplied == true)
assert(League.pulse(infected, player, now + 1500))
assert(infected.oddball.stage == "passed")
assert(finalCalls == 2, "native action must finish exactly once")

local refused = group("refused")
patient.dead = false
League.pulse(refused, player, now)
assert(League.action(refused, "submit_check", player))
assert(League.action(refused, "refuse", player))
assert(refused.standing == "Hostile" and refused.permanentHostility)
print("Defense League PASS: clean pass, four weapons, hidden bite, lie, surrender, refusal")
