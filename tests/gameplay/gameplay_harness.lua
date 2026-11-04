-- SPDX-License-Identifier: MIT
-- Production follow dispatch, bounded obstacle routing and verified door access.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check = f.check
local follower = f.actor("essential-follower", 0, 0, {})
f.registry[follower.id] = follower
local player = f.player
player.square = f.cell:getGridSquare(8, 0, 0)
local playerMoves, playerHealth = player.movementCalls or 0, player.body.health
local obstacle = f.cell:getGridSquare(2, 0, 0)
obstacle.solid = true
local goal = f.cell:getGridSquare(4, 0, 0)
local nodeBudget = SC.Config.get("navigationNodeBudget")
local path, reason, expanded = SC.Navigation.findPath(follower.square, goal,
    { actor = follower, nodeBudget = nodeBudget })
check(path and #path >= 5 and type(expanded) == "number" and expanded > 0
        and expanded <= nodeBudget,
    "bounded production routing finds a detour: " .. tostring(reason))
local limited, limitReason, limitedExpanded = SC.Navigation.findPath(follower.square, goal,
    { actor = follower, nodeBudget = 1 })
check(not limited and limitReason == "budget" and limitedExpanded == 1,
    "the production path search stops at its explicit expansion budget")
for _, node in ipairs(path or {}) do
    local x, y = SC.GameplayUtil.position(node.square or node)
    check(x ~= nil and (math.floor(x) ~= obstacle.x or math.floor(y) ~= obstacle.y),
        "the route never enters the solid obstacle")
end
obstacle.solid = false
local handled, followReason = SC.Decision._doFollowForTests(follower, player, {},
    { recruited = true, order = "follow", moveMode = "walk", followDistance = 3,
        commandSerial = 1 }, { threats = {}, threatCount = 0, immediateCount = 0,
        player = { danger = 0 } })
local route = SC.Navigation.peek(follower)
check(handled and route and route.goalAction == "follow_formation",
    "Follow reaches the production route controller: " .. tostring(followReason))

local from, to = f.cell:getGridSquare(0, 2, 0), f.cell:getGridSquare(1, 2, 0)
local door = { open = false, locked = true }
function door:IsOpen() return self.open end
function door:isLocked() return self.locked end
function door:ToggleDoor() self.open = not self.open end
function from:isDoorTo(other) return other == to end
function to:isDoorTo(other) return other == from end
function to:getDoor(north) if north == false then return door end end
local edge = SC.Topology.classifyEdge(follower, from, to, {})
check(not edge.traversable and edge.reason == "door_locked",
    "a locked doorway cannot become a traversable follow edge")
local context = {
    objectOpen = SC.Topology.objectOpen, objectLocked = SC.Topology.objectLocked,
    actorCanUnlock = function() return false end,
}
local state = { openedDoors = {} }
local opened, doorReason = SC.NavTraversal.handleDoor(follower, state, door, from, to, f.clock, context)
check(not opened and doorReason == "locked_door" and not door.open,
    "door traversal preserves a lock the actor cannot open")
door.locked = false
opened = SC.NavTraversal.handleDoor(follower, state, door, from, to, f.clock, context)
check(opened and door.open and #state.openedDoors == 1,
    "an unlocked route door opens and records its verified passage")
SC.NavTraversal.release(door, follower)
check((player.movementCalls or 0) == playerMoves and player.body.health == playerHealth,
    "companion routing never moves or damages the local player")
print("BEHAVIOUR_NAVIGATION_PASS checks=" .. tostring(f.checks()))
