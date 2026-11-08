-- SPDX-License-Identifier: MIT
-- Quiet camp use of EMMA. This never opens a player window or submits an
-- assistant request. The shared downtime supervisor owns movement and pose.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.ComputerUse = SC.ComputerUse or {}
local Use = SC.ComputerUse
local owners = setmetatable({}, { __mode = "k" })
local function U() return SC.GameplayUtil end
local function camp(value)
    return SC.BaseLife and type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(value) == true
end
local function ownerOf(object)
    local actor = owners[object]
    local state = actor and SC.Downtime and SC.Downtime.peek(actor)
    local active = state and state.active
    local working = actor and SC.RadioWork and SC.RadioWork.owns(actor, object)
    if actor and (not U().isValidActor(actor) or U().isDead(actor)
        or not working and (not active or active.kind ~= "computer_use" or active.object ~= object)) then
        owners[object], actor = nil, nil
    end
    return actor
end
local function eligible(actor, object)
    local terminal = SC.Terminal
    local working = SC.RadioWork and SC.RadioWork.owns(actor, object)
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or not working and base.settings and base.settings.routines == false then return false end
    if CharacterTrait and CharacterTrait.ILLITERATE
        and select(1, U().call(actor, "hasTrait", CharacterTrait.ILLITERATE)) == true then return false end
    if not actor or not U().isValidActor(actor) or U().isDead(actor) or not terminal
        or type(terminal.companionAvailable) ~= "function"
        or (working and SC.RadioWork.available(object) ~= true)
        or (not working and terminal.companionAvailable(object) ~= true) then return false end
    -- Availability checks native presence before camp coordinate reads: a
    -- removed IsoObject must never reach its unsafe getX/getY accessors.
    if not camp(actor) or not camp(object) then return false end
    local a, b = U().squareOf(actor), U().squareOf(object)
    local room = select(1, U().call(a, "getRoom"))
    local owner = ownerOf(object)
    return (working or room ~= nil and room == select(1, U().call(b, "getRoom"))
        and U().sameFloor(actor, object)) and (owner == nil or owner == actor)
end

function Use.candidate(actor, state, now, hooks)
    if not SC.Terminal or not camp(actor) or (state and now < (state.computerRetryAt or 0))
        or not hooks or hooks.seatingStatus(actor) ~= "standing" then return nil end
    local x, y, z = U().position(actor)
    if x == nil then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z or 0)
    local best, score, checked = nil, nil, 0
    -- At most 81 loaded squares and 256 objects, once per throttled probe.
    for dx = -4, 4 do for dy = -4, 4 do
        local square = U().gridSquare(x+dx, y+dy, z)
        if square and checked < 256 then
            U().squareObjects(square, function(object)
                checked = checked + 1
                if checked > 256 then return false end
                if not SC.Terminal.isComputer(object) or not eligible(actor, object)
                    or hooks.reserved(object, actor, now) then return true end
                local arrived, targets = U().directInteractionAccess(actor, object)
                if not arrived and #(targets or {}) == 0 then return true end
                local distance = U().distance(actor, object)
                if not best or distance < score then
                    best, score = { kind="computer_use", object=object, square=square,
                        score=23-distance*0.25, durationMs=18000,
                        deadlines={approaching=30000,animating=45000},
                        fact={activity="computer_use"} }, distance
                end
                return true
            end, math.min(32, 256-checked))
        end
    end end
    return best
end

function Use.claim(actor, activity)
    if not eligible(actor, activity.object) then return false, "computer_unavailable" end
    owners[activity.object] = actor
    return true
end

local function keyboardAccess(actor, activity)
    local chair = activity.chair
    if chair and activity.seatRequested
        and select(1,U().call(actor,"getSitOnFurnitureObject"))==chair
        and select(1,U().call(actor,"isSittingOnFurniture"))==true then
        if select(1,U().call(chair,"getObjectIndex"))==-1
            or not U().sameFloor(actor,activity.object) or U().distance(actor,activity.object)>2.1 then return false end
        local seat,pc = U().squareOf(chair),U().squareOf(activity.object)
        if not seat or not pc or select(1,U().call(seat,"getRoom"))~=select(1,U().call(pc,"getRoom"))
            or not SC.Topology or not SC.Topology.barrierBetween then return false end
        -- A real seated worker occupies the chair's blocked tile. Test the
        -- keyboard edge itself, rather than asking for a free standing tile.
        local barrier,kind = SC.Topology.barrierBetween(seat,pc)
        return kind=="open" or kind=="door" and barrier~=nil
            and select(1,U().call(barrier,"IsOpen"))==true
    end
    return U().directInteractionAccess(actor,activity.object)==true
end

function Use.valid(actor, activity, atKeyboard)
    if not activity or ownerOf(activity.object) ~= actor
        or not eligible(actor, activity.object) then return false end
    if atKeyboard then
        if activity.seated and (select(1,U().call(activity.chair,"getObjectIndex"))==-1
            or select(1,U().call(actor,"getSitOnFurnitureObject"))~=activity.chair
            or select(1,U().call(actor,"isSittingOnFurniture"))~=true) then return false end
        return keyboardAccess(actor,activity)
    end
    return true
end

local function deskChair(actor, activity)
    if not activity.radioWork or not SeatingManager or not SeatingManager.getInstance then return end
    local okay, manager = pcall(SeatingManager.getInstance)
    if not okay or not manager then return end
    local pc = activity.object
    local x,y,z = U().position(pc)
    if not x then return end
    local room = select(1,U().call(U().squareOf(pc),"getRoom"))
    local directions = { N={0,-1}, S={0,1}, W={-1,0}, E={1,0} }
    local best, score, checked
    checked = 0
    -- One local probe per staffed visit: 25 loaded tiles, at most 96 objects.
    for dx=-2,2 do for dy=-2,2 do
        local square = U().gridSquare(math.floor(x)+dx,math.floor(y)+dy,math.floor(z or 0))
        if square and checked<96 and select(1,U().call(square,"getRoom"))==room then
            U().squareObjects(square,function(object)
                checked=checked+1
                if checked>96 then return false end
                if object==pc or select(1,U().call(object,"getObjectIndex"))==-1
                    or select(1,U().call(object,"isFurnitureOccupied",actor))==true then return end
                local count = select(1,U().call(manager,"getTilePositionCount",object))
                if (tonumber(count) or 0)<1 then return end
                local props = select(1,U().call(object,"getProperties"))
                local name = tostring(select(1,U().call(props,"get","CustomName")) or ""):lower()
                if not name:find("chair",1,true) and not name:find("stool",1,true) then return end
                local facing = directions[tostring(select(1,U().call(manager,"getFacingDirection",object)))]
                local cx,cy = U().position(object)
                local ddx,ddy = cx and x-cx,cy and y-cy
                local distance = ddx and ddy and math.sqrt(ddx*ddx+ddy*ddy) or 100
                -- The chair must face the keyboard, not merely be near a desk.
                if not facing or distance<.5 or distance>1.6
                    or (ddx*facing[1]+ddy*facing[2])/distance<.8 then return end
                if not best or distance<score then best,score=object,distance end
            end,math.min(16,96-checked))
        end
    end end
    if best and SC.ActionSupervisor.reserve(activity.supervisorToken,best,"computer_chair") then return best end
end

local function takeDeskSeat(actor, activity)
    local native = SC.NativeActions
    if not activity.radioWork or not native or not native.furnitureStatus then return end
    if not activity.chairChecked then
        activity.chairChecked = true
        activity.chair = deskChair(actor, activity)
    end
    if not activity.chair then return end
    local now = U().nowMs()
    if activity.seatRequested then
        local state = native.furnitureStatus(actor)
        local seated = select(1,U().call(actor,"getSitOnFurnitureObject"))==activity.chair
            and select(1,U().call(actor,"isSittingOnFurniture"))==true
        if state=="entered" and seated and keyboardAccess(actor,activity) then
            local phase = native.activityStatus and native.activityStatus(actor)
            if phase==nil or phase=="none" then
                activity.seated = true
                return true,"arrived"
            end
            if now-activity.seatRequested<15000 then return true,"settling_at_keyboard" end
        end
        if state=="entering" and now-activity.seatRequested<12000 then return true,"taking_seat" end
        activity.chairFailed = true
    end
    if activity.chairFailed then
        local standing = native.leaveSeating(actor)
        if not standing then return true,"leaving_desk_seat" end
        SC.ActionSupervisor.release(activity.supervisorToken,activity.chair,"computer_seat_unavailable")
        activity.chair,activity.seated = nil,nil
        return
    end
    local accepted = U().move(actor,"walk",{action="sit",object=activity.chair,
        supervisorToken=activity.supervisorToken})
    if accepted then activity.seatRequested=now;return true,"taking_seat" end
    activity.chairFailed=true
end

function Use.approach(actor, activity)
    if not Use.valid(actor, activity, false) then return false, "computer_unavailable" end
    -- Renew only the upper-body action. Re-running seat entry would apply its
    -- short entry timeout to a companion who has already worked here for hours.
    if activity.seated and Use.valid(actor,activity,true) then return true,"arrived" end
    local seating,seatReason = takeDeskSeat(actor,activity)
    if seating then return seating,seatReason end
    local arrived, targets = U().directInteractionAccess(actor, activity.object)
    if arrived then return true, "arrived" end
    if not SC.Navigation or type(SC.Navigation.requestAny) ~= "function"
        or #(targets or {}) == 0 then return false, "computer_no_access" end
    return SC.Navigation.requestAny(actor, targets, "walk", {
        action="move_to_computer", targetSquare=activity.square,
        object=activity.object, requireSameSquare=true, arrivalDistance=0.35,
        continuousApproach=true, workCampOnly=true,
        supervisorToken=activity.supervisorToken,
    })
end

function Use.start(actor, activity, now)
    if not Use.valid(actor, activity, true) then return false, "computer_unavailable" end
    local system
    if activity.radioWork then
        -- Monitoring a staffed radio must not replace the player's live system
        -- record every time the operator renews a short typing animation.
        local data = select(1,U().call(activity.object,"getModData"))
        system = data and data.movableData and data.movableData[SC.TerminalSystem.MEMORY_KEY]
    else system = SC.Terminal.computerState(actor, activity.object) end
    if not system or system.locked == true then return false, "computer_locked" end
    local service, token = SC.ActionSupervisor, activity.supervisorToken
    if service and token and SC.NativeActions and SC.NativeActions.visualStatus then
        local expected, reason = service.expectVisual(token, {action="computer_use"})
        if expected ~= true then return false, reason or "computer_visual_rejected" end
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        SC.Navigation.cancel(actor, "computer_interaction")
    end
    if not activity.seated then U().call(actor, "faceThisObject", activity.object) end
    local animated, animationReason = U().move(actor, "walk", {action="computer_use",object=activity.object,
        downtime=true,durationMs=activity.durationMs,supervisorToken=token,seated=activity.seated})
    if not animated then
        if SC.Diagnostics and SC.Diagnostics.report then
            SC.Diagnostics.report("computer_use",U().idOf(actor),"keyboard action rejected",tostring(animationReason))
        end
        return false, "computer_animation_rejected"
    end
    activity.approaching, activity.startedAt, activity.actionAccepted = nil, now, true
    if service and token then
        local accepted, reason = service.transition(token, "animating", {action="computer_use"})
        if accepted ~= true then return false, reason or "computer_transition_rejected" end
    end
    return true, "computer_use"
end

function Use.finish(actor, activity)
    if activity.actionAccepted ~= true or not Use.valid(actor, activity, true) then return false end
    local files = SC.TerminalLore and SC.TerminalLore.REFERENCE
    if type(files) ~= "table" or #files == 0 then return false end
    local seed = math.abs(tonumber(U().stableHash(tostring(U().idOf(actor))
        .. ":computer:" .. tostring(activity.startedAt))) or 0)
    local entry = files[seed % #files + 1]
    if type(entry) ~= "table" or type(entry.id) ~= "string"
        or type(entry.title) ~= "string" or type(entry.text) ~= "string" then return false end
    activity.fact.referenceId, activity.fact.title = entry.id, entry.title
    if SC.Dialogue and type(SC.Dialogue.say) == "function" then
        pcall(SC.Dialogue.say, actor, "downtime.computer", {
            "The machine is very calm about all this.",
            "Found an old county notice. Still trying to sound in charge.",
            "It remembers more than I do. That is not much of a competition.",
        })
    end
    return true
end

function Use.release(actor, activity)
    if activity and activity.chair and activity.seatRequested and SC.NativeActions and SC.NativeActions.leaveSeating then
        -- Only release the chair claimed by this visit; never eject a newer owner.
        local current = SC.ActionSupervisor and SC.ActionSupervisor.current(actor)
        if (current==nil or current==activity.supervisorToken)
            and select(1,U().call(actor,"getSitOnFurnitureObject"))==activity.chair then
            SC.NativeActions.leaveSeating(actor)
        end
    end
    if activity and owners[activity.object] == actor then owners[activity.object] = nil end
end

function Use.yieldToPlayer(object)
    local actor = ownerOf(object)
    if not actor then return true end
    -- A player may monitor an explicit radio shift without logging its operator
    -- out. Optional ambient computer use still yields the keyboard immediately.
    if SC.RadioWork and SC.RadioWork.owns(actor, object) then return true end
    return SC.Downtime.cancel(actor, "computer_player_priority") == true
end

function Use.reset()
    owners = setmetatable({}, { __mode = "k" })
end
return Use
