-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.NavTraversal = SC.NavTraversal or {}
local Traversal = SC.NavTraversal
local reservations = setmetatable({}, { __mode = "k" })
local windowTravel = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function invoke(context, name, ...)
    local fn = type(context) == "table" and context[name] or nil
    if type(fn) ~= "function" then return nil end
    return fn(...)
end

function Traversal.reserve(object, actor, now)
    if not object then return true end
    local existing = reservations[object]
    if existing and existing.actor ~= actor and existing.expires > now then return false end
    reservations[object] = {
        actor = actor,
        expires = now + (U().config("navigationReservationMs") or 8000),
    }
    return true
end

function Traversal.release(object, actor)
    local existing = object and reservations[object]
    if existing and existing.actor == actor then reservations[object] = nil end
end

local function windowJourney(actor, goal, intent)
    local commands = SC.Commands and SC.Commands.peek and SC.Commands.peek(actor) or {}
    goal = intent and intent.windowJourneyGoal or goal
    local x, y, z = U().position(goal)
    local action = intent and (intent.followRecovery and "follow" or intent.action) or "move"
    local key = tostring(commands.commandSerial or 0) .. ":" .. tostring(action)
    local journey = windowTravel[actor]
    if not journey or journey.key ~= key or x and journey.x
        and ((journey.x-x)^2+(journey.y-y)^2 > 144 or journey.z ~= math.floor(z or 0)) then
        journey = { key=key, x=x, y=y, z=math.floor(z or 0), portals={} }
        windowTravel[actor] = journey
    end
    return journey
end

function Traversal.windowEdgeHeld(actor, object, fromSquare, now)
    local journey = windowTravel[actor]
    local entry = journey and journey.portals[object]
    return entry ~= nil and entry.blockedFrom == U().squareKey(fromSquare)
        and (tonumber(now) or U().nowMs()) < (entry.blockedUntil or 0)
end

local function refreshWindowHold(entry, now)
    if entry.blockedUntil and now>=entry.blockedUntil then
        entry.blockedFrom,entry.blockedUntil=nil,nil
        entry.progressAt,entry.beganAt,entry.returns=now,now,0
        entry.proof=nil
    end
end

local function windowPortal(actor, object, fromSquare, toSquare, goal, intent, now)
    local journey = windowJourney(actor, goal, intent)
    local entry = journey.portals[object]
    if not entry then
        local count, oldest, time = 0, nil, math.huge
        for candidate, prior in pairs(journey.portals) do
            count=count+1
            if prior.seenAt < time then oldest,time=candidate,prior.seenAt end
        end
        if count >= 16 then journey.portals[oldest]=nil end
        local inside=select(1,U().call(fromSquare,"getRoom")) and fromSquare
            or select(1,U().call(toSquare,"getRoom")) and toSquare or fromSquare
        entry = { object=object, beganAt=now, progressAt=now, returns=0,
            originalFrom=U().squareKey(inside), homeSquare=inside,
            goalDistance=U().distance(actor,goal) }
        journey.portals[object]=entry
    end
    entry.seenAt=now
    refreshWindowHold(entry,now)
    if now-entry.progressAt >= 30000 and now>=(entry.blockedUntil or 0)
        and U().distance(actor, object) <= 4 then
        entry.blockedFrom,entry.blockedUntil=entry.originalFrom,now+120000
        entry.progressAt=now entry.proof=nil
        U().diagnostic("navigation-window-blocked",actor,"reason=window_cycle target="..tostring(U().squareKey(goal)))
    end
    entry.intent, entry.goal = intent or {}, goal
    return entry
end

function Traversal.noteWindowCrossing(actor, record, now)
    if not record or record.effectOnly or not tostring(record.action):find("climb_window",1,true) then return end
    local journey=windowTravel[actor]
    local entry=journey and journey.portals[record.object]
    if not entry then return end
    local from,to=U().squareKey(record.fromSquare),U().squareKey(record.toSquare)
    if entry.lastFrom==to and entry.lastTo==from and to==entry.originalFrom then
        entry.returns=entry.returns+1
        if entry.returns>=2 and now-entry.beganAt<=30000 then
            entry.blockedFrom,entry.blockedUntil=entry.originalFrom,now+120000
            U().diagnostic("navigation-window-blocked",actor,"reason=window_cycle crossings="..entry.returns)
        end
    end
    if now-entry.beganAt>30000 then entry.beganAt,entry.returns=now,0 end
    entry.lastFrom,entry.lastTo=from,to
    entry.proof=nil
end

function Traversal.windowRecoveryTarget(actor, goal, intent, now)
    local journey=windowTravel[actor]
    if not journey then return nil end
    journey=windowJourney(actor,goal,intent)
    for object,entry in pairs(journey.portals) do
        refreshWindowHold(entry,now)
        local distance=U().distance(actor,goal)
        local portalDistance=U().distance(actor,object)
        -- Moving within the threshold or crossing back and forth cannot renew
        -- progress. Reaching the onward route can; a legitimate later return
        -- must not inherit a stale stall timer.
        if portalDistance>4 and distance+1<(entry.goalDistance or math.huge) then
            entry.progressAt,entry.beganAt,entry.returns=now,now,0
            entry.goalDistance=distance
        elseif portalDistance<=4 and now-entry.progressAt>=30000
            and now>=(entry.blockedUntil or 0) then
            entry.blockedFrom,entry.blockedUntil=entry.originalFrom,now+120000
            entry.proof=nil
            U().diagnostic("navigation-window-blocked",actor,"reason=window_no_onward_progress")
        end
        local room=select(1,U().call(entry.homeSquare,"getRoom"))
        if room and now<(entry.blockedUntil or 0) and portalDistance<=4
            and select(1,U().call(U().squareOf(actor),"getRoom"))==nil then
            return entry.homeSquare
        end
    end
end

-- Proof searches share the normal retained navigation budget. The crossed
-- window is forbidden, so "go straight back through it" is not onward progress.
function Traversal.admitWindow(actor, state, object, fromSquare, toSquare, now, intent)
    local topology, navigation=SC.Topology,SC.Navigation
    local allowed,why=topology.windowAdmission(actor,object,fromSquare,toSquare,intent)
    if not allowed then return false,why end
    local goal=intent and intent.windowGoal or state and state.goalSquare
        or intent and intent.targetSquare
    if not goal then return false,"window_goal_unknown" end
    local entry=windowPortal(actor,object,fromSquare,toSquare,goal,intent,now)
    if Traversal.windowEdgeHeld(actor,object,fromSquare,now) then return false,"window_cycle" end
    local _,_,z=U().position(fromSquare)
    entry.fromSquare,entry.toSquare=fromSquare,toSquare
    if (z or 0)<=0 then entry.validatedAt=now return true end
    -- A window which opens from this side will be open by the time we cross.
    -- Its return landing must nevertheless remain supported and unobstructed.
    local reverseAllowed,reverseWhy=topology.windowAdmission(actor,object,toSquare,fromSquare,intent)
    if reverseAllowed~=true and reverseWhy~="window_smash_not_emergency" then
        return false,"window_return_unverified:"..tostring(reverseWhy)
    end
    local signature=topology.objectStateSignature(object)..":"..tostring(U().squareKey(fromSquare))
        ..">"..tostring(U().squareKey(toSquare))..":"..tostring(U().squareKey(goal))
    local proof=entry.proof
    if not proof or proof.signature~=signature then
        proof={signature=signature,startedAt=now,stairPlan={}} entry.proof=proof
    end
    if not proof.path and now-proof.startedAt>6500 then return false,"window_exit_unverified" end
    if proof.validatedAt and now-proof.validatedAt<=500 then entry.validatedAt=now return true end
    if not proof.target then
        local gx,gy,gz=U().position(goal)
        if gx==nil then return false,"window_goal_unknown" end
        if math.floor(gz or 0)~=math.floor(z or 0) then
            if not SC.StairTransition then return false,"window_exit_unverified" end
            local point,reason=SC.StairTransition.target(proof.stairPlan,toSquare,{x=gx,y=gy,z=math.floor(gz)},now)
            if not point then return nil,"window_route_verifying" end
            if point.z~=math.floor(z) or not proof.stairPlan.descent then return false,"window_exit_unverified" end
            proof.target=U().gridSquare(point.x,point.y,point.z)
        else proof.target=goal end
        if not proof.target then return false,"window_exit_unverified" end
        proof.options={actor=actor,forbiddenWindow=object,snapshot=intent and intent.snapshot,
            nodeBudget=U().config("navigationNodeBudgetMaximum") or 1200,alternatives=false}
        if intent and intent.workCampOnly then
            proof.options.squareAdmission=function(square)return navigation._workSquareAdmitted(square,intent)end
        end
        proof.job=navigation.beginPathSearch(toSquare,proof.target,nil,proof.options)
    end
    if not proof.path then
        local status,path=navigation.resumePathSearch(proof.job,24)
        if status=="pending" then return nil,"window_route_verifying" end
        if status~="complete" or type(path)~="table" or path[#path]~=proof.target then
            return false,"window_exit_unverified"
        end
        proof.path,proof.index=path,2
    end
    -- Revalidate in slices, including mutable doors and furniture, before a
    -- deferred animation may consume its one-use native permission.
    local used=0
    proof.index=proof.index or 2
    while proof.index<=#proof.path and used<16 do
        local edge=topology.classifyEdge(actor,proof.path[proof.index-1],proof.path[proof.index],proof.options)
        if not edge.traversable then entry.proof=nil return nil,"window_route_verifying" end
        proof.index=proof.index+1 used=used+1
    end
    if proof.index<=#proof.path then return nil,"window_route_verifying" end
    proof.index,proof.validatedAt=2,now
    entry.validatedAt=now
    return true
end

function Traversal.authorizeWindowSubmission(actor, action, intent)
    local journey=windowTravel[actor]
    local entry=journey and journey.portals[intent.object]
    if not entry then return false,"window_approval_missing" end
    local admitted,why=Traversal.admitWindow(actor,nil,intent.object,intent.fromSquare,
        intent.toSquare,U().nowMs(),entry.intent)
    if admitted~=true then return false,admitted==nil and "window_verification_pending" or why end
    if action=="smash_window" and not SC.Topology.windowImmediateDanger(actor,entry.intent) then
        return false,"window_smash_not_emergency"
    end
    if SCBridge==nil or type(SCBridge.approveWindowAction)~="function" then return false,"window_bridge_unavailable" end
    local called,approved=pcall(SCBridge.approveWindowAction,actor,intent.object,
        action=="smash_window" and "smash" or "climb",intent.fromSquare,intent.toSquare)
    return called and approved==true,called and approved==true and "window_approved" or "window_approval_refused"
end

local function beginInteraction(actor, state, object, action, now, extra, executorOwned, context)
    if not Traversal.reserve(object, actor, now) then return false, "reserved" end
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object or pending.action ~= action then
        if executorOwned then
            local movementIntent = U().copyShallow(extra)
            movementIntent.action = action
            movementIntent.object = object
            movementIntent.interaction = true
            movementIntent.targetSquare = U().squareOf(object)
            movementIntent.direction = invoke(
                context, "directionBetween", U().squareOf(actor), movementIntent.targetSquare)
            if not U().move(actor, "walk", movementIntent) then
                Traversal.release(object, actor)
                return false, "action_rejected"
            end
        end
        pending = { object = object, action = action, startedAt = now, extra = extra }
        state.pendingInteraction = pending
        return true, "interacting"
    end
    return true, "pending"
end

local function completeDoorInteraction(actor, state, object, action, fromSquare, toSquare, now, context)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= object then return false, "missing_interaction" end
    if action == "open_door" and not invoke(context, "objectOpen", object) then
        local wasLocked = invoke(context, "objectLocked", object) == true
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or not invoke(context, "objectOpen", object) then
            return false, "door_open_failed"
        end
        if wasLocked then
            utility.diagnostic("navigation-door", actor,
                "action=opened_locked_door by_key_or_inside=true")
        end
        if SC.BaseLife and type(SC.BaseLife.noteWorkAccessChanged) == "function" then
            SC.BaseLife.noteWorkAccessChanged(object)
        end
    elseif action == "close_door" and invoke(context, "objectOpen", object) then
        local result, toggled = utility.call(object, "ToggleDoor", actor)
        if not toggled or result == false or invoke(context, "objectOpen", object) then
            return false, "door_close_failed"
        end
    end
    if action == "open_door" then
        state.openedDoors[#state.openedDoors + 1] = {
            object = object,
            fromSquare = fromSquare,
            toSquare = toSquare,
            openedAt = now,
            expires = now + (utility.config("navigationReservationMs") or 8000),
            passageKey = invoke(context, "actorPassageKey", actor, state),
        }
    else
        Traversal.release(object, actor)
    end
    state.pendingInteraction = nil
    return true, "done"
end

-- Explicit door commands share the same reservation, toggle and verified
-- postcondition as route traversal, but may request either open or closed.
function Traversal.interactDoor(actor, state, door, action, fromSquare, toSquare, now, context)
    if action ~= "open_door" and action ~= "close_door" then
        return false, "unsupported_door_action"
    end
    local desiredOpen = action == "open_door"
    if invoke(context, "objectOpen", door) == desiredOpen then
        return true, "already_set"
    end
    local obstructed, obstructedOk = U().call(door, "isObstructed")
    if obstructedOk and obstructed == true then return false, "obstructed_door" end
    if desiredOpen and invoke(context, "objectLocked", door)
        and not invoke(context, "actorCanUnlock", actor, door, fromSquare) then
        return false, "locked_door"
    end
    local ok, status = beginInteraction(actor, state, door, action, now, {
        fromSquare = fromSquare, toSquare = toSquare,
    }, false, context)
    if not ok then return false, status end
    return completeDoorInteraction(actor, state, door, action,
        fromSquare, toSquare, now, context)
end

function Traversal.handleDoor(actor, state, door, fromSquare, toSquare, now, context)
    if invoke(context, "objectOpen", door) then return true end
    local obstructed, obstructedOk = U().call(door, "isObstructed")
    if obstructedOk and obstructed == true then return false, "obstructed_door" end
    if invoke(context, "objectLocked", door)
        and not invoke(context, "actorCanUnlock", actor, door, fromSquare) then
        return false, "locked_door"
    end
    local ok, status = beginInteraction(actor, state, door, "open_door", now, {
        fromSquare = fromSquare, toSquare = toSquare,
    }, false, context)
    if not ok then return false, status end
    local complete, completeStatus = completeDoorInteraction(
        actor, state, door, "open_door", fromSquare, toSquare, now, context)
    if not complete then return false, completeStatus end
    if completeStatus ~= "done" then return nil, completeStatus end
    return true
end

local function completeWindowAction(actor, state, window, action, now, context)
    local utility = U()
    local pending = state.pendingInteraction
    if not pending or pending.object ~= window then return false, "missing_interaction" end
    local delays = {
        open_window = utility.config("windowOpenMs") or 1300,
        smash_window = utility.config("windowSmashMs") or 900,
        remove_glass = utility.config("windowGlassRemovalMs") or 1400,
    }
    local verified = action == "open_window" and invoke(context, "objectOpen", window)
        or action == "smash_window" and invoke(context, "windowSmashed", window)
        or action == "remove_glass" and invoke(context, "windowGlassRemoved", window)
    if not verified then
        -- The adapter already submitted the native event. Re-submitting here or
        -- toggling the object directly races the animation and duplicates effects.
        if now - pending.startedAt < math.max(3500, (delays[action] or 500) + 1500) then
            return nil, "traversal_starting:" .. action
        end
        Traversal.release(window, actor)
        state.pendingInteraction = nil
        return false, action .. "_verification_timeout"
    end
    if SC.BaseLife and type(SC.BaseLife.noteWorkAccessChanged) == "function" then
        SC.BaseLife.noteWorkAccessChanged(window)
    end
    state.pendingInteraction = nil
    return true, "done"
end

-- Which of the four things to do with a window, given what it is and how long
-- there is. Glass is decided before anything else: IsoWindow stores its
-- smashed state in the same `destroyed` flag that the generic "is this opening
-- passable" test reads as open, so asking that first made the whole glass
-- branch unreachable -- a companion climbed through the window it had just
-- smashed, still full of shards, while the player beside it cleared theirs by
-- hand. Only a real threat close enough to arrive first buys the injury.
function Traversal.chooseWindowAction(window, arrival, context, actor, fromSquare, intent)
    local utility = U()
    local smashed = invoke(context, "windowSmashed", window) == true
    local glassRemoved = invoke(context, "windowGlassRemoved", window) == true
    local open = invoke(context, "objectOpen", window) == true
    local climbMs = utility.config("windowClimbMs") or 1300
    arrival = tonumber(arrival) or math.huge
    if smashed and not glassRemoved then
        if arrival > (utility.config("windowGlassRemovalMs") or 1400) + climbMs then
            return "remove_glass", smashed, glassRemoved, open
        end
        return "climb_window_emergency", smashed, glassRemoved, open
    end
    if open or smashed then return "climb_window", smashed, glassRemoved, open end
    local canOpen=SC.Topology.windowOpensFromSide(window,fromSquare)
    if canOpen
        and arrival > (utility.config("windowOpenMs") or 1300) + climbMs then
        return "open_window", smashed, glassRemoved, open
    end
    if SC.Topology.windowImmediateDanger(actor,intent) then return "smash_window", smashed, glassRemoved, open end
    return canOpen and "open_window" or nil, smashed, glassRemoved, open
end

function Traversal.handleWindow(actor, state, window, fromSquare, toSquare, now, intent, context)
    local utility = U()
    local admitted,why=Traversal.admitWindow(actor,state,window,fromSquare,toSquare,now,intent)
    if admitted~=true then return admitted,why end
    local pending = state.pendingInteraction
    if pending and pending.object == window then
        local complete, status = completeWindowAction(actor, state, window, pending.action, now, context)
        if complete ~= true then return complete, status end
    end
    if invoke(context, "objectBarricaded", window) then return false, "barricaded_window" end
    if invoke(context, "windowInvincible", window)
        and not invoke(context, "objectOpen", window) then return false, "invincible_window" end
    local arrival = invoke(context, "threatArrivalMs", intent, fromSquare) or math.huge
    local action, smashed, glassRemoved, open =
        Traversal.chooseWindowAction(window, arrival, context, actor, fromSquare, intent)
    if action==nil then return false,"window_smash_not_emergency" end

    utility.diagnostic("window", actor, "action=" .. tostring(action)
        .. " smashed=" .. tostring(smashed) .. " glass=" .. tostring(glassRemoved)
        .. " open=" .. tostring(open)
        .. " arrival=" .. (arrival == math.huge and "none" or tostring(math.floor(arrival))))
    if action == "climb_window" or action == "climb_window_emergency" then
        if not invoke(context, "canClimbThrough", window, actor)
            and action ~= "climb_window_emergency" then
            return false, "unsafe_window_frame"
        end
        if not Traversal.reserve(window, actor, now) then return false, "reserved" end
        local accepted = utility.move(actor, intent and intent.mode or "walk", {
            action = action,
            object = window,
            fromSquare = fromSquare,
            toSquare = toSquare,
            nextSquare = toSquare,
            targetSquare = toSquare,
            direction = invoke(context, "directionBetween", fromSquare, toSquare),
            acceptsInjury = action == "climb_window_emergency",
            supervisorToken = intent and intent.supervisorToken,
        })
        if not accepted then
            Traversal.release(window, actor)
            return false, "action_rejected"
        end
        return nil, "climbing"
    end

    local ok, status = beginInteraction(actor, state, window, action, now, {
        fromSquare = fromSquare, toSquare = toSquare,
        supervisorToken = intent and intent.supervisorToken,
    }, true, context)
    if not ok then return false, status end
    local complete, completeStatus = completeWindowAction(actor, state, window, action, now, context)
    if complete == false then return false, completeStatus end
    if complete == nil then return nil, completeStatus end
    return nil, "reconsider_window"
end

function Traversal.handleWindowFrame(actor, frame, fromSquare, toSquare, now, intent, context)
    local utility = U()
    local admitted,why=Traversal.admitWindow(actor,nil,frame,fromSquare,toSquare,now,intent)
    if admitted~=true then return admitted,why end
    if not invoke(context, "canClimbThrough", frame, actor) then
        return false, "blocked_window_frame"
    end
    if not Traversal.reserve(frame, actor, now) then return false, "reserved" end
    local accepted = utility.move(actor, intent and intent.mode or "walk", {
        action = "climb_window",
        object = frame,
        fromSquare = fromSquare,
        toSquare = toSquare,
        nextSquare = toSquare,
        targetSquare = toSquare,
        direction = invoke(context, "directionBetween", fromSquare, toSquare),
        emptyFrame = true,
        supervisorToken = intent and intent.supervisorToken,
    })
    if not accepted then
        Traversal.release(frame, actor)
        return false, "action_rejected"
    end
    return nil, "climbing_frame"
end

function Traversal.doorGeometry(entry, value)
    local utility = U()
    if type(entry) ~= "table" or not entry.fromSquare or not entry.toSquare then return nil end
    local fx, fy, fz = utility.position(entry.fromSquare)
    local tx, ty, tz = utility.position(entry.toSquare)
    local vx, vy, vz = utility.position(value)
    if fx == nil or tx == nil or vx == nil or math.floor(fz or 0) ~= math.floor(tz or 0)
        or math.floor(vz or 0) ~= math.floor(fz or 0) then return nil end
    local dx, dy = tx - fx, ty - fy
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then return nil end
    dx, dy = dx / length, dy / length
    local thresholdX = (fx + tx) * 0.5 + 0.5
    local thresholdY = (fy + ty) * 0.5 + 0.5
    local offsetX, offsetY = vx - thresholdX, vy - thresholdY
    return offsetX * dx + offsetY * dy,
        math.abs(offsetX * -dy + offsetY * dx), dx, dy
end

function Traversal.occupiesDoorway(value, entry)
    local progress, lateral = Traversal.doorGeometry(entry, value)
    if progress == nil then return false end
    local clearance = U().config("doorClearanceDistance") or 0.38
    return math.abs(progress) < clearance and lateral <= 0.55
end

function Traversal.alignDoorApproach(actor, fromSquare, toSquare, intent, affordance, context, state)
    local utility = U()
    local entry = { fromSquare = fromSquare, toSquare = toSquare }
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(entry, actor)
    if progress == nil then return false, "door_geometry_unavailable" end
    local tolerance = utility.config("navigationDoorApproachLateralTolerance") or 0.18
    local fence = affordance == "fence"
    local setback = utility.config("doorClearanceDistance") or 0.38
    local normalTolerance = utility.config("navigationFenceApproachNormalTolerance") or 0.12
    -- Unlike a door, the fence climb must begin beside the rail. Being
    -- centred sideways while still most of a tile away is not an aligned
    -- climb position for the native action.
    if lateral <= tolerance and (not fence
        or math.abs(progress + setback) <= normalTolerance) then
        -- A moving formation should face through the door before the native
        -- crossing takes over. The old room sweep could leave the actor facing
        -- sideways; repeating that turn on every Follow pulse stalled entry.
        if not fence and state and intent and intent.draggingBody ~= true
            and (intent.action == "follow_formation"
            or intent.action == "regroup") then
            local facingX, hasX = utility.call(actor, "getForwardDirectionX")
            local facingY, hasY = utility.call(actor, "getForwardDirectionY")
            if hasX and hasY and type(facingX) == "number"
                and type(facingY) == "number"
                and facingX * forwardX + facingY * forwardY < 0.75 then
                local key = tostring(fromSquare) .. ">" .. tostring(toSquare)
                local now = utility.nowMs()
                if state.doorFacingKey ~= key then
                    state.doorFacingKey = key
                    state.doorFacingUntil = now + 400
                end
                if now < (state.doorFacingUntil or 0) then
                    local actorX, actorY = utility.position(actor)
                    if actorX ~= nil then
                        local requested, accepted = utility.call(actor,
                            "faceLocationF", actorX + forwardX * 2,
                            actorY + forwardY * 2)
                        if accepted and requested ~= false then
                            return nil, "turning_door_approach"
                        end
                    end
                end
            else
                state.doorFacingKey = nil
                state.doorFacingUntil = nil
            end
        end
        return true, "door_approach_aligned"
    end

    local fromX, fromY, fromZ = utility.position(fromSquare)
    local toX, toY = utility.position(toSquare)
    local actorX, actorY = utility.position(actor)
    if fromX == nil or toX == nil or actorX == nil then
        return false, "door_approach_position_unavailable"
    end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local desiredProgress = fence and -setback or math.min(progress, -setback)
    local targetX = thresholdX + forwardX * desiredProgress
    local targetY = thresholdY + forwardY * desiredProgress
    local prefix = affordance == "fence" and "fence" or "door"
    local alignmentIntent = {
        action = prefix .. "_approach",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = fromZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.08, tolerance * 0.5),
        movementTargetTtlMs = 750,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = affordance ~= "fence",
        fenceAlignment = affordance == "fence",
        weaponReady = false,
        draggingBody = intent and intent.draggingBody == true,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", alignmentIntent)
    if accepted ~= true then return false, reason or "door_approach_rejected" end
    invoke(context, "record", actor, prefix .. "_approach", {
        targetSquare = alignmentIntent.targetPosition,
        nextSquare = toSquare,
        status = "aligning_to_threshold",
    })
    return nil, "aligning_" .. prefix .. "_approach"
end

local function cardinalDirection(name)
    local directions = type(_G) == "table" and rawget(_G, "IsoDirections") or nil
    local key = ({ north = "N", south = "S", east = "E", west = "W" })[
        string.lower(tostring(name or ""))]
    if directions == nil or key == nil then return nil end
    local ok, value = pcall(function() return directions[key] end)
    return ok and value or nil
end

function Traversal.alignWindowApproach(actor, fromSquare, toSquare, intent, context)
    local utility = U()
    local entry = { fromSquare = fromSquare, toSquare = toSquare }
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(entry, actor)
    if progress == nil then return false, "window_geometry_unavailable" end
    local lateralTolerance = utility.config("navigationWindowApproachLateralTolerance") or 0.10
    local normalTolerance = utility.config("navigationWindowApproachNormalTolerance") or 0.12
    local setback = utility.config("navigationWindowApproachSetback") or 0.38
    if lateral <= lateralTolerance and math.abs(progress + setback) <= normalTolerance then
        -- ISClimbThroughWindow waits until faceDirection has finished before it
        -- submits the native climb. Do the same for companions so the animation
        -- never begins sideways or from the opposite face of the portal.
        local name = invoke(context, "directionBetween", fromSquare, toSquare)
        local direction = cardinalDirection(name)
        if direction ~= nil then
            utility.call(actor, "faceDirection", direction)
            local turning, observed = utility.call(actor, "shouldBeTurning")
            if observed and turning == true then
                invoke(context, "record", actor, "window_approach", {
                    targetSquare = toSquare, status = "turning_to_window",
                })
                return nil, "turning_window_approach"
            end
        end
        return true, "window_approach_aligned"
    end

    local fromX, fromY, fromZ = utility.position(fromSquare)
    local toX, toY = utility.position(toSquare)
    local actorX, actorY = utility.position(actor)
    if fromX == nil or toX == nil or actorX == nil then
        return false, "window_approach_position_unavailable"
    end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local targetX = thresholdX - forwardX * setback
    local targetY = thresholdY - forwardY * setback
    local alignmentIntent = {
        action = "window_approach",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = fromZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.06, lateralTolerance * 0.5),
        movementTargetTtlMs = 1000,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = true,
        windowAlignment = true,
        weaponReady = false,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", alignmentIntent)
    if accepted ~= true then return false, reason or "window_approach_rejected" end
    invoke(context, "record", actor, "window_approach", {
        targetSquare = alignmentIntent.targetPosition,
        nextSquare = toSquare,
        status = "aligning_to_window",
    })
    return nil, "aligning_window_approach"
end

-- Native window/fence states stop as soon as the collision capsule crosses the
-- tile boundary. Player input immediately supplies the remaining step, but an
-- AI actor can remain with its feet inside the frame while its next decision is
-- pending. Finish that same short step under the traversal's existing owner.
function Traversal.clearTraversalExit(actor, record, now, context)
    if type(record) ~= "table" or record.effectOnly == true or record.rope == true then
        return true, "traversal_exit_not_required"
    end
    local action = tostring(record.action or "")
    if action ~= "climb_window" and action ~= "climb_window_emergency"
        and action ~= "climb_fence" and action ~= "climb_wall" then
        return true, "traversal_exit_not_required"
    end

    local utility = U()
    local progress, lateral, forwardX, forwardY = Traversal.doorGeometry(record, actor)
    local toX, toY, toZ = utility.position(record.toSquare)
    local actorX, actorY, actorZ = utility.position(actor)
    if progress == nil or toX == nil or actorX == nil then
        return true, "traversal_exit_geometry_unavailable"
    end
    if math.floor(actorX) ~= math.floor(toX) or math.floor(actorY) ~= math.floor(toY)
        or math.floor(actorZ or 0) ~= math.floor(toZ or 0) then
        if record.destinationVerifiedAt ~= nil then
            -- Combat or root motion may carry the actor beyond (or briefly
            -- back from) the exact destination cell after the native state
            -- already proved the crossing. Release the portal without
            -- blacklisting a valid edge; the next route pulse starts from the
            -- actor's actual square.
            return true, "traversal_exit_displaced"
        end
        return false, "traversal_destination_not_reached"
    end

    local clearance = math.max(0.10,
        tonumber(utility.config("navigationTraversalExitClearance")) or 0.38)
    local tolerance = math.max(0.02,
        tonumber(utility.config("navigationTraversalExitTolerance")) or 0.08)
    if progress >= clearance - tolerance and lateral <= tolerance then
        return true, "traversal_exit_clear"
    end

    now = tonumber(now) or utility.nowMs()
    record.exitStartedAt = record.exitStartedAt or now
    record.exitDeadline = record.exitDeadline or (record.exitStartedAt
        + (tonumber(utility.config("navigationTraversalExitTimeoutMs")) or 2000))
    if now >= record.exitDeadline then
        -- A successful native crossing must never become an unbounded owner.
        -- The retained route can still pull the actor away on its next edge.
        return true, "traversal_exit_timeout"
    end

    local fromX, fromY = utility.position(record.fromSquare)
    if fromX == nil then return true, "traversal_exit_origin_unavailable" end
    local thresholdX = (fromX + toX) * 0.5 + 0.5
    local thresholdY = (fromY + toY) * 0.5 + 0.5
    local targetX = thresholdX + forwardX * clearance
    local targetY = thresholdY + forwardY * clearance
    local movementIntent = {
        action = "traversal_exit",
        dx = targetX - actorX,
        dy = targetY - actorY,
        targetPosition = { x = targetX, y = targetY, z = toZ or actorZ or 0 },
        targetKind = "world",
        movementArrivalTolerance = math.min(0.06, tolerance),
        movementTargetTtlMs = 1000,
        direct = true,
        collisionValidated = true,
        doorwayAlignment = true,
        traversalExit = true,
        weaponReady = false,
        supervisorToken = record.supervisorToken,
    }
    local accepted, reason = utility.move(actor, record.mode or "walk", movementIntent)
    invoke(context, "record", actor, "traversal_exit", {
        targetSquare = movementIntent.targetPosition,
        nextSquare = record.toSquare,
        status = accepted == true and "clearing_portal" or tostring(reason or "rejected"),
    })
    -- Retry a rejected pulse until the short deadline. This retains the native
    -- traversal reservation but cannot trap the actor indefinitely.
    return nil, accepted == true and "clearing_traversal_exit"
        or "traversal_exit_retry"
end

function Traversal.handleFence(actor, object, fromSquare, toSquare, intent, context)
    local utility = U()
    local isHoppable, hoppableObserved = utility.call(object, "isHoppable")
    local canClimb, climbObserved = utility.call(object, "canClimbOver", actor)
    if object ~= nil and utility.instanceOf(object, "IsoThumpable")
        and hoppableObserved and isHoppable == true
        and climbObserved and canClimb == true then
        -- The player's E action climbs hoppable IsoThumpable objects with
        -- ISClimbThroughWindow, whose perform() calls climbThroughWindow(),
        -- not hopFence/climbOverWall. This covers player-built and modded
        -- climbable fence objects whose collision stays active while that climb
        -- is legal; SCNativeTraversalActions submits the same native call.
        local climbIntent = {
            action = "climb_window",
            object = object,
            fromSquare = fromSquare,
            targetSquare = toSquare,
            nextSquare = toSquare,
            direction = invoke(context, "directionBetween", fromSquare, toSquare),
            nativeAffordance = "fence",
            hoppableThumpable = true,
            humanAnimationOnly = true,
            supervisorToken = intent and intent.supervisorToken,
        }
        local accepted, reason = utility.move(actor, "walk", climbIntent)
        if accepted ~= true then return false, reason or "thumpable_climb_rejected" end
        invoke(context, "record", actor, "fence_climb", {
            targetSquare = toSquare,
            nextSquare = toSquare,
            status = "climb_thumpable",
        })
        return true, "climbing_thumpable"
    end
    local tall, tallOk = utility.call(object, "isTallHoppable")
    local direction = invoke(context, "directionBetween", fromSquare, toSquare)
    local nativeDirection = cardinalDirection(direction)
    if (not tallOk or object == nil) and nativeDirection ~= nil then
        -- This is the same final affordance test used by the player's E action.
        -- It is deliberately only a dispatch-time fallback: arbitrary A-star
        -- nodes are not necessarily adjacent to the actor and cannot safely use
        -- the character-relative canClimbOverWall check.
        local climbable, climbableOk = utility.call(
            actor, "canClimbOverWall", nativeDirection)
        if climbableOk and climbable == true then tall, tallOk = true, true end
    end
    local action = tallOk and tall == true and "climb_wall" or "climb_fence"
    local climbIntent = {
        action = action,
        object = object,
        fromSquare = fromSquare,
        targetSquare = toSquare,
        nextSquare = toSquare,
        direction = direction,
        nativeAffordance = "fence",
        objectlessFenceFallback = object == nil,
        humanAnimationOnly = true,
        supervisorToken = intent and intent.supervisorToken,
    }
    local accepted, reason = utility.move(actor, "walk", climbIntent)
    if accepted ~= true then return false, reason or (action .. "_rejected") end
    invoke(context, "record", actor, "fence_climb", {
        targetSquare = toSquare,
        nextSquare = toSquare,
        status = action,
    })
    return true, action == "climb_wall" and "climbing_wall" or "climbing_fence"
end

local function sameDoorEdge(entry, fromSquare, toSquare, context)
    if type(entry) ~= "table" or fromSquare == nil or toSquare == nil then return false end
    return (invoke(context, "sameSquare", entry.fromSquare, fromSquare)
            and invoke(context, "sameSquare", entry.toSquare, toSquare))
        or (invoke(context, "sameSquare", entry.fromSquare, toSquare)
            and invoke(context, "sameSquare", entry.toSquare, fromSquare))
end

function Traversal.nearbyOpenedDoor(state, actor, context, routeFrom, routeTo)
    local routeKnown = routeFrom ~= nil and routeTo ~= nil
    local nearest, nearestDistance
    local occupied, occupiedDistance
    for _, entry in ipairs(state.openedDoors or {}) do
        local progress, cross = Traversal.doorGeometry(entry, actor)
        if invoke(context, "objectOpen", entry.object) and progress ~= nil
            and math.abs(progress) <= 1.15 and cross <= 1.15 then
            if routeKnown then
                -- Two close thresholds are common in shops and double-door
                -- entrances. Recovery must use the door on the failed route edge;
                -- the first recently opened door can face another direction and
                -- turn a through-door retry into an endless sideways shuffle.
                if sameDoorEdge(entry, routeFrom, routeTo, context) then return entry end
                if Traversal.occupiesDoorway(actor, entry) then
                    local distance = math.abs(progress) + cross
                    if occupiedDistance == nil or distance < occupiedDistance then
                        occupied, occupiedDistance = entry, distance
                    end
                end
            else
                local distance = math.abs(progress) + cross
                if nearestDistance == nil or distance < nearestDistance then
                    nearest, nearestDistance = entry, distance
                end
            end
        end
    end
    -- Once a route edge is known, proximity alone is not enough: a neighboring
    -- doorway may be less than one tile away. The only non-route exception is a
    -- threshold the actor is physically occupying and needs to clear.
    if routeKnown then return occupied end
    return nearest
end

local function actorClearOfDoorway(actor, entry)
    local progress = Traversal.doorGeometry(entry, actor)
    return progress ~= nil and progress >= (U().config("doorClearanceDistance") or 0.38)
end

local function grappleBlocksDoorway(actor, entry)
    local utility = U()
    if utility.call(actor, "isDraggingCorpse") ~= true then return false end
    local body = utility.call(actor, "getGrapplingTarget")
    if not body then return true end
    local bodyProgress, bodyLateral = Traversal.doorGeometry(entry, body)
    local actorProgress = Traversal.doorGeometry(entry, actor)
    if bodyProgress == nil or actorProgress == nil then return true end
    if bodyLateral > 0.55 then return false end
    local clearance = utility.config("doorClearanceDistance") or 0.38
    -- Another survivor may be crossing in either direction through a door
    -- opened by this actor. Their feet can be clear while the body is at the
    -- threshold or still on its opposite side.
    return math.abs(bodyProgress) < clearance or actorProgress * bodyProgress <= 0
end

local function safeToCloseDoor(entry, snapshot, actor, context)
    local utility = U()
    if not actorClearOfDoorway(actor, entry) then return false end
    local dragging = utility.call(actor, "isDraggingCorpse")
    if dragging == true then
        -- A backward hauler can clear the threshold before the grapple target.
        -- Keep the door open until both have crossed; route arrival itself must
        -- still advance by the carrier so the next step can pull the body clear.
        local body = utility.call(actor, "getGrapplingTarget")
        if not body or not actorClearOfDoorway(body, entry) then return false end
    end
    if entry.passageKey and invoke(context, "passageActive", entry.passageKey, utility.nowMs()) then
        return false
    end
    if type(snapshot) ~= "table" then return true end
    for index = 1, math.min(#(snapshot.threats or {}), 12) do
        if utility.distanceSq(entry.object, snapshot.threats[index].actor) <= 4 then return false end
    end
    for _, ally in ipairs(snapshot.allies or {}) do
        local other = ally and (ally.actor or ally) or nil
        if other and other ~= actor and (Traversal.occupiesDoorway(other, entry)
            or grappleBlocksDoorway(other, entry)) then return false end
    end
    local player = snapshot.player
    player = type(player) == "table" and (player.actor or player) or nil
    if player and player ~= actor and (Traversal.occupiesDoorway(player, entry)
        or grappleBlocksDoorway(player, entry)) then return false end
    return true
end

function Traversal.closeOwnedDoors(actor, state, now, snapshot, context)
    local utility = U()
    local write = 1
    for index = 1, #state.openedDoors do
        local entry = state.openedDoors[index]
        local keep = true
        if now >= entry.expires then
            Traversal.release(entry.object, actor)
            keep = false
        elseif invoke(context, "objectOpen", entry.object)
            and not invoke(context, "sameSquare", utility.squareOf(actor), entry.fromSquare)
            and utility.distance(actor, entry.toSquare) <= 2.75
            and now - entry.openedAt >= (utility.config("doorCloseDelayMs") or 700)
            and now >= (state.recoveryDoorHoldUntil or 0)
            and safeToCloseDoor(entry, snapshot, actor, context) then
            local result, toggled = utility.call(entry.object, "ToggleDoor", actor)
            if toggled and result ~= false and not invoke(context, "objectOpen", entry.object) then
                Traversal.release(entry.object, actor)
                keep = false
            end
        elseif not invoke(context, "objectOpen", entry.object) then
            Traversal.release(entry.object, actor)
            keep = false
        end
        if keep then state.openedDoors[write] = entry write = write + 1 end
    end
    for index = #state.openedDoors, write, -1 do state.openedDoors[index] = nil end
end

function Traversal.releaseState(actor, state)
    if type(state) ~= "table" then return end
    for _, entry in ipairs(state.openedDoors or {}) do
        Traversal.release(entry.object, actor)
    end
    if state.pendingInteraction then Traversal.release(state.pendingInteraction.object, actor) end
end

function Traversal.reset()
    reservations = setmetatable({}, { __mode = "k" })
    windowTravel = setmetatable({}, { __mode = "k" })
end

function Traversal.releaseActor(actor)
    if actor == nil then return false end
    windowTravel[actor]=nil
    for object, reservation in pairs(reservations) do
        if reservation and reservation.actor == actor then reservations[object] = nil end
    end
    return true
end

return Traversal
