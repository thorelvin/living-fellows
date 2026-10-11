-- SPDX-License-Identifier: MIT
-- A cloned source save may already contain either authored oddball. Each
-- focused probe removes only its own character before constructing a scene.
local Probe = SCRealSandboxHarnessProbes.SCOddballCoreyEarlProbe

-- A native-safe chair square is still unsuitable for Earl's actor. The live
-- room selector must pick clear floor for him and the spread fuel posts.
local fixtureRoom, fixtureSquares = {}, {}
for x = -2, 2 do
    for y = -2, 2 do
        local square = { x = x, y = y, z = 0,
            occupied = x == 0 and y == 0 or x == 1 and y == 0 }
        function square:getX() return self.x end
        function square:getY() return self.y end
        function square:getRoom() return fixtureRoom end
        fixtureSquares[x .. ":" .. y] = square
    end
end
local fixtureU = {
    position = function(object) return object.x, object.y, object.z end,
    gridSquare = function(x, y, z)
        return z == 0 and fixtureSquares[x .. ":" .. y] or nil
    end,
    isClearActorSpawnSquare = function(square)
        return square ~= nil and square.occupied ~= true
    end,
}
local origin, room, posts = Probe.findEarlRoom(fixtureU,
    { x = 0, y = 0, z = 0 })
assert(origin ~= nil and room == fixtureRoom and #posts >= 2
    and fixtureU.isClearActorSpawnSquare(origin) == true,
    "Earl room selector skips furniture for the actor post")
for index, post in ipairs(posts) do
    assert(fixtureU.isClearActorSpawnSquare(post) == true,
        "Earl fuel post is clear: " .. index)
    local dx, dy = post.x - origin.x, post.y - origin.y
    assert(dx * dx + dy * dy >= 4,
        "Earl fuel stays away from actor: " .. index)
    for previous = 1, index - 1 do
        local other = posts[previous]
        dx, dy = post.x - other.x, post.y - other.y
        assert(dx * dx + dy * dy >= 4,
            "Earl fuel posts stay spread: " .. index)
    end
end

-- The hit handler replaces igniteAt with the hit time. Compare the result
-- against the theft deadline captured before the native hit, not that field.
local warningIgniteAt = 2800
local afterHit = { stage = "burning", attackTriggered = true,
    ignitedAt = 1000, igniteAt = 1000 }
assert(Probe.attackPreempted(afterHit, warningIgniteAt) == true,
    "native hit preempts the saved warning deadline")
assert(Probe.attackPreempted(afterHit, afterHit.igniteAt) == false,
    "mutated igniteAt cannot prove warning preemption")
assert(Probe.attackPreempted({ stage = "warning", attackTriggered = true,
    ignitedAt = 1000 }, warningIgniteAt) == false,
    "warning alone is not an ignited attack")

local other = { id = "faction-other", oddball = { id = "somebody_else" } }
local groups, currentDefinition, restoredFactions, restoredOddballs
local factionExports, oddballExports = 0, 0
local SC = {
    Factions = {
        list = function() return groups end,
        export = function()
            factionExports = factionExports + 1
            local document = { schema = 1, groups = {}, order = {} }
            for _, group in ipairs(groups) do
                document.groups[group.id] = group
                document.order[#document.order + 1] = group.id
            end
            return document
        end,
        restore = function(document)
            restoredFactions = document
            return true, 1
        end,
    },
    Oddballs = {
        export = function()
            oddballExports = oddballExports + 1
            return { version = 1,
                seeded = { [currentDefinition] = { groupId = groups[1].id } },
                retired = { [currentDefinition] = "old" },
                pending = { id = currentDefinition,
                    groupId = groups[1].id } }
        end,
        restore = function(document)
            restoredOddballs = document
            return true
        end,
    },
}

for _, fixture in ipairs({
    { id = "pyromaniac_earl_kessler", groupId = "faction-earl" },
    { id = "fan_corey_biggs", groupId = "faction-corey" },
    { id = "milli_tea_and_trouble", groupId = "faction-milli" },
}) do
    local existing = { id = fixture.groupId, oddball = { id = fixture.id } }
    groups, currentDefinition = { existing, other }, fixture.id
    local beforeFactions, beforeOddballs = factionExports, oddballExports
    local okay, reason = Probe.clearExistingOddball(SC, fixture.id)
    assert(okay == true and reason == "removed_existing_" .. fixture.id
            .. ":" .. fixture.groupId,
        "existing character is isolated in the disposable clone: " .. fixture.id)
    assert(factionExports == beforeFactions + 1
            and oddballExports == beforeOddballs + 1,
        "faction and ledger were exported once: " .. fixture.id)
    assert(restoredFactions.groups[existing.id] == nil
        and restoredFactions.groups[other.id] == other
        and #restoredFactions.order == 1
        and restoredFactions.order[1] == other.id,
        "only target was removed; other factions stay in order: " .. fixture.id)
    assert(restoredOddballs.seeded[fixture.id] == nil
        and restoredOddballs.retired[fixture.id] == nil
        and restoredOddballs.pending == nil,
        "target's unique ledger no longer conflicts: " .. fixture.id)
    groups = { other }
    okay, reason = Probe.clearExistingOddball(SC, fixture.id)
    assert(okay == true and reason == "no_existing_" .. fixture.id
        and factionExports == beforeFactions + 1
        and oddballExports == beforeOddballs + 1,
        "clean clones retain factions without needless restore: " .. fixture.id)
end
local okay, reason = Probe.clearExistingOddball(SC, nil)
assert(okay == false and reason == "invalid_fixture_definition",
    "invalid test definition fails closed")

-- Exercise Milli's prepare phase, not just the shared helper. It must clear
-- the clone collision before asking the native faction layer to spawn her.
local MilliProbe = SCRealSandboxHarnessProbes.SCMilliLiveProbe
local milli = { id = "faction-milli",
    oddball = { id = "milli_tea_and_trouble" } }
groups, currentDefinition = { milli, other }, "milli_tea_and_trouble"
SC.Oddballs.definition = function(id)
    if id == currentDefinition then return { id = id } end
end
SC.OddballMilli = { siteFor = function() end }
SurvivorCompanion = SC
local phase, isolatedCheck
MilliProbe.step({ phase = "milli_prepare", phaseStartedAt = 0,
    config = { milli_site_x = 0, milli_site_y = 0 }, player = {} },
    2000, function(name, accepted)
        if name == "milli_clone_scene_isolated" then
            isolatedCheck = accepted
        end
        return accepted
    end, function() end, function(nextPhase) phase = nextPhase end)
assert(isolatedCheck == true and phase == "milli_find_room"
    and restoredFactions.groups[milli.id] == nil,
    "Milli prepare clears existing clone collision before scene search")
SC_TEST_REPORT = "Oddball live probe clone-isolation regression passed"
