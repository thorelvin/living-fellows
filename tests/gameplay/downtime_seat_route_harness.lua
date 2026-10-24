-- SPDX-License-Identifier: MIT
-- Real Downtime + Supervisor, with deterministic furniture and route adapters.
local SC, D, S = SurvivorCompanion, SurvivorCompanion.Downtime, SurvivorCompanion.ActionSupervisor
local U, checks, routes, cancelled = SC.GameplayUtil, 0, {}, 0
local _, _, _, begin, _, _, _, _, _, _, _, stateFor = D._furnitureForTests()
local quiet = { snapshot = { indoors=true, threatCount=0, immediateCount=0 } }
local function check(value, message)
    checks = checks + 1
    assert(value, "downtime seat route " .. checks .. ": " .. message)
end
U.distance = function(first, second)
    return math.sqrt((first.x-second.x)^2+(first.y-second.y)^2)
end
U.movingBlocker = function() return nil end
U.stableHash = function() return 1 end
U.directInteractionAccess = function(actor, object)
    return actor.access == true, {object.useSquare}, "approaching"
end
local originalMove = U.move
U.move = function(actor, mode, intent)
    if intent.action == "sit" or intent.action == "rest_bed" then
        actor.entryCalls = (actor.entryCalls or 0) + 1
        actor.routeDuringEntry = routes[actor]
    end
    return originalMove(actor, mode, intent)
end
SC.NativeActions.seatingStatus = function(actor) return actor.seatState or "standing" end
SC.NativeActions.furnitureStatus = function(actor)
    return actor.entered and "entered" or "entering"
end
SC.NativeActions.leaveSeating = function(actor)
    actor.seatState, actor.entered = "standing", false
    actor.leaveCalls = (actor.leaveCalls or 0) + 1
    return true
end
SC.Navigation = {
    peek = function(actor) return routes[actor] end,
    cancel = function(actor)
        if actor.rejectRouteCancel then return false, "test_route_cancel_rejected" end
        cancelled, routes[actor] = cancelled+1, nil
        return true
    end,
    requestAny = function(actor, targets, _, intent)
        if routes[actor] == nil then
            routes[actor] = { goalAction=intent.action, goalSquare=targets[1],
                actionTokenSerial=intent.supervisorToken.serial,
                lastApproachRequest={goal=targets[1],intent=intent},
                nativeLease={ultimateGoal=targets[1],supervisorToken=intent.supervisorToken} }
        end
        return true, actor.exactArrival and "arrived" or "native_path_owned"
    end,
}
local function start(id)
    SC_READING_CLOCK = SC_READING_CLOCK + 10000
    local actor = SC_READING_ACTOR("seat:"..id)
    local object = {x=11,y=10,z=0,useSquare={x=11,y=10,z=0}}
    local activity = {kind="sit",object=object,square=object,fact={activity="sit"}}
    local okay, why = begin(actor,stateFor(actor),activity,actor.commands,SC_READING_CLOCK)
    check(okay and activity.approaching and routes[actor] ~= nil,
        "a real supervised furniture activity starts its owned approach: "..tostring(why))
    return actor, activity
end

local actor, activity = start("access")
local originalRoute, before = routes[actor], cancelled
D.update(actor,nil,quiet,"sit")
check(routes[actor] == originalRoute and cancelled == before and actor.entryCalls == nil,
    "an unfinished approach keeps its live route and does not enter furniture")
actor.access = true
D.update(actor,nil,quiet,"sit")
check(routes[actor] == nil and cancelled == before+1 and actor.entryCalls == 1
        and actor.routeDuringEntry == nil and activity.approaching == nil,
    "physical furniture access retires the old exact-tile lease before native chair entry")
actor.entered, actor.seatState = true, "furniture"
D.update(actor,nil,quiet,"sit")
check(S.current(actor) and S.current(actor).phase == "waiting"
        and D.peek(actor).active == activity and routes[actor] == nil,
    "a fully entered chair waits under its controller without any leftover approach")
local player = SC_READING_ACTOR("seat:player")
player.x = actor.x + 1
actor.commands.order, actor.commands.commandSerial = "follow", actor.commands.commandSerial+1
local _, why = D.update(actor,player,quiet)
check(why == "cancelled_for_order" and D.peek(actor).active == nil
        and S.current(actor) == nil and actor.seatState == "standing"
        and actor.commands.order == "follow" and cancelled == before+1,
    "public update accepts a newer Follow order, releases the chair and keeps no obsolete route")

-- A pre-fix runtime can already have entered while its approach remains.
actor, activity = start("legacy_wait")
activity.approaching, activity.actionAccepted, activity.startedAt = nil, true, SC_READING_CLOCK
before = cancelled
D.cancel(actor,"new_player_order")
check(routes[actor] == nil and cancelled == before+1 and S.current(actor) == nil,
    "cancelling an already-entered legacy activity still retires its exact owned chair route")

-- A newer route/owner must survive old furniture cleanup, including when the
-- old controller still says it was approaching.
for _, kind in ipairs({"follow","new_token","new_object","foreign_lease","unidentified"}) do
    actor, activity = start(kind)
    local route = routes[actor]
    if kind == "follow" then route.goalAction = "follow_formation"
    elseif kind == "new_token" then route.lastApproachRequest.intent.supervisorToken = {}
    elseif kind == "new_object" then route.lastApproachRequest.intent.object = {}
    elseif kind == "foreign_lease" then route.nativeLease.supervisorToken = {}
    elseif kind == "unidentified" then route.lastApproachRequest = nil end
    before = cancelled
    local okay = D.cancel(actor,"old_activity_cleanup")
    check(okay and routes[actor] == route and cancelled == before,
        "old furniture cleanup preserves a "..kind.." route")
    routes[actor] = nil
end

actor, activity = start("exact_arrival")
actor.exactArrival = true
before = cancelled
D.update(actor,nil,quiet,"sit")
check(routes[actor] == nil and cancelled == before+1 and actor.entryCalls == 1,
    "Navigation's own exact arrival retires the matching route before chair entry as well")
D.cancel(actor,"fixture_done")

actor, activity = start("cancel_rejected")
actor.access, actor.rejectRouteCancel = true, true
before = cancelled
local okay, rejected = D.update(actor,nil,quiet,"sit")
check(okay == false and rejected == "test_route_cancel_rejected" and actor.entryCalls == nil
        and routes[actor] ~= nil and cancelled == before,
    "a refused route stop cannot start a competing furniture animation")
actor.rejectRouteCancel = false
D.cancel(actor,"fixture_done")
SC_TEST_REPORT = "DOWNTIME_SEAT_ROUTE_PASS checks="..checks
