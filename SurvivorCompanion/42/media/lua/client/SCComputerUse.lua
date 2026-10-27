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
    if actor and (not U().isValidActor(actor) or U().isDead(actor)
        or not active or active.kind ~= "computer_use" or active.object ~= object) then
        owners[object], actor = nil, nil
    end
    return actor
end
local function eligible(actor, object)
    local terminal = SC.Terminal
    local base = SC.BaseLife and SC.BaseLife.active and SC.BaseLife.active()
    if not base or base.settings and base.settings.routines == false then return false end
    if CharacterTrait and CharacterTrait.ILLITERATE
        and select(1, U().call(actor, "hasTrait", CharacterTrait.ILLITERATE)) == true then return false end
    if not actor or not U().isValidActor(actor) or U().isDead(actor) or not terminal
        or type(terminal.companionAvailable) ~= "function"
        or terminal.companionAvailable(object) ~= true then return false end
    -- Availability checks native presence before camp coordinate reads: a
    -- removed IsoObject must never reach its unsafe getX/getY accessors.
    if not camp(actor) or not camp(object) then return false end
    local a, b = U().squareOf(actor), U().squareOf(object)
    local room = select(1, U().call(a, "getRoom"))
    local owner = ownerOf(object)
    return room ~= nil and room == select(1, U().call(b, "getRoom"))
        and U().sameFloor(actor, object) and (owner == nil or owner == actor)
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

function Use.valid(actor, activity, atKeyboard)
    if not activity or ownerOf(activity.object) ~= actor
        or not eligible(actor, activity.object) then return false end
    if atKeyboard then
        return U().directInteractionAccess(actor, activity.object) == true
    end
    return true
end

function Use.approach(actor, activity)
    if not Use.valid(actor, activity, false) then return false, "computer_unavailable" end
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
    local system = SC.Terminal.computerState(actor, activity.object)
    if not system or system.locked == true then return false, "computer_locked" end
    local service, token = SC.ActionSupervisor, activity.supervisorToken
    if service and token and SC.NativeActions and SC.NativeActions.visualStatus then
        local expected, reason = service.expectVisual(token, {action="computer_use"})
        if expected ~= true then return false, reason or "computer_visual_rejected" end
    end
    if SC.Navigation and type(SC.Navigation.cancel) == "function" then
        SC.Navigation.cancel(actor, "computer_interaction")
    end
    U().call(actor, "faceThisObject", activity.object)
    if not U().move(actor, "walk", {action="computer_use",object=activity.object,
        downtime=true,durationMs=activity.durationMs,supervisorToken=token}) then
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
    if activity and owners[activity.object] == actor then owners[activity.object] = nil end
end

function Use.yieldToPlayer(object)
    local actor = ownerOf(object)
    if not actor then return true end
    return SC.Downtime.cancel(actor, "computer_player_priority") == true
end

function Use.reset()
    owners = setmetatable({}, { __mode = "k" })
end
return Use
