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
do
    local items, visits = {}, {}
    for index = 1, 20 do items[index] = f.item("Base.SearchSlice" .. index, "Item", {}) end
    local cupboard = f.containerObject(follower.square, items)
    local search, precise, count, found = {}, 0, 0, nil
    local clock, score, inside = SC.Performance.preciseNowMs, SC.Logistics.itemNeedScore, SC.BaseLife.isInside
    SC.Performance.preciseNowMs = function() precise = precise + .6 return precise end
    SC.BaseLife.isInside = function() return false end
    SC.Logistics.itemNeedScore = function(_, item)
        count, visits[item] = count + 1, (visits[item] or 0) + 1
        return item == items[20] and 100 or 0, "general"
    end
    SC.Encounter._noteContainerOpened(search, cupboard, f.clock)
    for _ = 1, 20 do
        count = 0
        local _, selected = SC.Encounter.stickyContainer(follower, search, {}, {},
            { items = {}, shouldUnload = false }, f.clock)
        check(count > 0 and count <= 3, "expensive scavenging yields after a bounded item slice")
        if selected then found = selected break end
        check(search.openContainer == cupboard, "a partly read cupboard remains open for the next slice")
    end
    check(found == items[20] and #cupboard.items == 20,
        "time-sliced scavenging reaches the late useful item without moving stock")
    for _, item in ipairs(items) do check(visits[item] == 1, "scavenging resumes without rescoring the prefix") end
    SC.Performance.preciseNowMs, SC.Logistics.itemNeedScore, SC.BaseLife.isInside = clock, score, inside
end
do
    local originalFaction = SC.FactionBehavior
    local guest = f.actor("essential-car-resident", 0, 0, {recruited=false})
    f.registry[guest.id] = guest
    guest.vehicle = {getCurrentSpeedKmHour=function() return 0 end,getSqlId=function() return 97 end}
    local storyUpdates = 0
    SC.FactionBehavior = {
        intentFor=function(who) if who==guest then return {mode="loretta_wait",priority=90} end end,
        update=function(who) if who==guest then storyUpdates=storyUpdates+1; return true,"waiting_in_car" end end,
    }
    local quiet = {threats={},threatCount=0,immediateCount=0,pressure=0,allies={},player={danger=0}}
    local guestHandled,guestReason
    for _=1,3 do
        f.clock=f.clock+1000
        guestHandled,guestReason=SC.Decision.update(guest,player,{snapshot=quiet},f.clock)
        if storyUpdates>0 then break end
    end
    check(storyUpdates==1 and guest.vehicle~=nil,
        "a seated unrecruited car resident keeps her authored policy while the player is on foot: "..tostring(guestHandled).."/"..tostring(guestReason).." updates="..storyUpdates.." recruited="..tostring(SC.Commands.peek(guest).recruited))
    SC.FactionBehavior = originalFaction
    local passenger = f.actor("essential-party-passenger", 0, 0, {})
    f.registry[passenger.id] = passenger
    passenger.vehicle=guest.vehicle
    local first=#f.movementLog
    SC.Decision.update(passenger,player,{snapshot=quiet},f.clock+1000)
    local exited=false
    for i=first+1,#f.movementLog do local move=f.movementLog[i]
        if move.actor==passenger and move.intent.action=="exit_vehicle" then exited=true end
    end
    check(exited,"ordinary recruited passengers still leave after the player gets out")
end
print("BEHAVIOUR_NAVIGATION_PASS checks=" .. tostring(f.checks()))
