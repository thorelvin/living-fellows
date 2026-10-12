-- SPDX-License-Identifier: MIT
-- Disposable-save check for the two VanSeats rear seats without outside doors.
local Probe = {}

local function fail(result, setPhase, current, name, reason)
    result("FAIL", name, tostring(reason))
    setPhase("finish", current)
end

local function doorSquare(vehicle, seat, U)
    local outside = vehicle:getPassengerPosition(seat, "outside")
    if not outside or not outside:getArea() or outside:getArea() == "" then
        return nil
    end
    local world = vehicle:getPassengerPositionWorldPos(outside, Vector3f.new())
    local x, y = math.floor(world:x()), math.floor(world:y())
    for dx = -2, 2 do
        for dy = -2, 2 do
            local square = U.gridSquare(x + dx, y + dy, 0)
            local distance = square and vehicle:getEnterSeatDistance(seat,
                square:getX() + 0.5, square:getY() + 0.5) or nil
            if square and square:isOutside() and square:getRoom() == nil
                and square:getBuilding() == nil
                and square:getRoofHideBuilding() == nil
                and not square:isSolid() and not square:isSolidTrans()
                and square:TreatAsSolidFloor() and square:isFree(true)
                and square:getVehicleContainer() == nil
                and distance and distance >= 0 and distance <= 2.56 then
                return square
            end
        end
    end
    return nil
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    local vehicle = H.passengerVehicle
    local state = H.sixSeatState
    if H.phase == "six_seat_setup" then
        if current - H.phaseStartedAt < 700 then return end
        if not SC.Vehicle.isStationary(vehicle) then
            if current - H.phaseStartedAt > 15000 then
                fail(result, setPhase, current, "six_seat_settled", "van did not stop")
            end
            return
        end
        local script = vehicle:getScript()
        local rearLeft = script and script:getPassenger(4)
        local rearRight = script and script:getPassenger(5)
        local leftOutside = rearLeft and rearLeft:getPositionById("outside")
        local rightOutside = rearRight and rearRight:getPositionById("outside")
        local leftArea = leftOutside and leftOutside:getArea() or nil
        local rightArea = rightOutside and rightOutside:getArea() or nil
        local middleLeft = script:getPassenger(2):getPositionById("outside")
        local middleRight = script:getPassenger(3):getPositionById("outside")
        local switchLeft, switchRight = vehicle:canSwitchSeat(2, 4),
            vehicle:canSwitchSeat(3, 5)
        local blockedLeft = vehicle:isEnterBlocked(H.passengerActor, 4)
        local blockedRight = vehicle:isEnterBlocked(H.passengerActor, 5)
        if not check("six_seat_native_layout", vehicle:getMaxPassengers() == 6
            and switchLeft and switchRight,
            "script=" .. tostring(vehicle:getScriptName())
                .. " areas=" .. tostring(middleLeft and middleLeft:getArea())
                .. "," .. tostring(middleRight and middleRight:getArea())
                .. "," .. tostring(leftArea) .. "," .. tostring(rightArea)
                .. " blocked=" .. tostring(blockedLeft) .. ","
                .. tostring(blockedRight)
                .. " switches=" .. tostring(switchLeft) .. ","
                .. tostring(switchRight)) then
            setPhase("finish", current)
            return
        end
        -- Fresh debug-spawned cars can have every door locked. The boarding
        -- fixture exercises seat routing, so unlock only this disposable van.
        for seat = 0, 3 do
            local part = vehicle:getPassengerDoor(seat)
            local door = part and part:getDoor() or nil
            if door then
                door:setLocked(false)
                vehicle:transmitPartDoor(part)
            end
        end
        local locked, bothLocked = {}, true
        for rear = 4, 5 do
            local part = vehicle:getPassengerDoor(rear)
            local door = part and part:getDoor() or nil
            if door then
                door:setLocked(true)
                vehicle:transmitPartDoor(part)
            end
            bothLocked = bothLocked and door ~= nil and door:isLocked()
            locked[#locked + 1] = tostring(part and part:getId())
                .. ":" .. tostring(door and door:isLocked())
        end
        if not check("six_seat_rear_door_fixture",
            bothLocked,
            table.concat(locked, ",")) then
            setPhase("finish", current)
            return
        end
        local driverSquare = doorSquare(vehicle, 0, SC.GameplayUtil)
        if not check("six_seat_driver_door", driverSquare ~= nil,
            "outside driver seat reachable") then
            setPhase("finish", current)
            return
        end
        H.player:teleportTo(driverSquare:getX() + 0.5,
            driverSquare:getY() + 0.5, 0)
        local entered = vehicle:enter(0, H.player)
        if not check("six_seat_player_drives", entered == true
            and vehicle:getSeat(H.player) == 0,
            "seat=" .. tostring(vehicle:getSeat(H.player))) then
            setPhase("finish", current)
            return
        end
        state = { actors = { H.passengerActor }, index = 2 }
        H.sixSeatState = state
        local id = SC.Registry.idOf(H.passengerActor)
        local issued, why = SC.Commands.issue(id, "follow", nil, H.player)
        if not check("six_seat_follow_1", issued == true, tostring(why)) then
            setPhase("finish", current)
            return
        end
        setPhase("six_seat_spawn", current)
        return
    end
    if H.phase == "six_seat_spawn" then
        if state.ticket then
            local actor, reason = SC.Actor.pollSpawn(state.ticket)
            if not actor then
                if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                    fail(result, setPhase, current, "six_seat_spawn_" .. state.index,
                        reason)
                end
                return
            end
            state.actors[state.index] = actor
            local id = SC.Registry.idOf(actor)
            local issued, why = SC.Commands.issue(id, "follow", nil, H.player)
            if not check("six_seat_follow_" .. state.index, issued == true,
                tostring(why)) then setPhase("finish", current) return end
            state.index = state.index + 1
            state.ticket = nil
        end
        if state.index > 5 then
            -- The seed save can contain unrelated Follow companions. Keep
            -- their own ride policy out of this five-passenger fixture.
            local selected = {}
            for _, passenger in ipairs(state.actors) do
                selected[passenger] = true
            end
            local excluded = 0
            for _, candidate in ipairs(SC.Registry.living()) do
                if not selected[candidate] then
                    local id = SC.Registry.idOf(candidate)
                    local commands = id and SC.Commands.peek(candidate) or nil
                    if commands and commands.recruited == true
                        and commands.rideWithPlayer ~= false then
                        local issued = SC.Commands.issue(id,
                            "set_ride_with_player", { enabled = false }, H.player)
                        if issued then excluded = excluded + 1 end
                    end
                end
            end
            result("PASS", "six_seat_other_followers_excluded",
                "count=" .. tostring(excluded))
            SC.Vehicle.invalidateManifests(vehicle)
            table.sort(state.actors, function(left, right)
                local leftStatus = SC.Vehicle.statusFor(left, H.player)
                local rightStatus = SC.Vehicle.statusFor(right, H.player)
                return (leftStatus.seat or 99) < (rightStatus.seat or 99)
            end)
            state.index = 1
            setPhase("six_seat_board", current)
            return
        end
        local ticket, why
        local cx, cy = math.floor(vehicle:getX()), math.floor(vehicle:getY())
        for radius = 4, 9 do
            if ticket then break end
            for dx = -radius, radius do
                if ticket then break end
                for dy = -radius, radius do
                    if math.abs(dx) == radius or math.abs(dy) == radius then
                        local square = SC.GameplayUtil.gridSquare(cx + dx,
                            cy + dy, 0)
                        if square and square:isOutside() and not square:isSolid()
                            and square:getVehicleContainer() == nil
                            and square ~= H.player:getCurrentSquare() then
                            ticket, why = SC.Actor.beginSpawn(square, {
                                recruited = true,
                                identity = { forename = "Van",
                                    surname = "Passenger" .. state.index,
                                    gender = "man", outfit = "Generic01" },
                            })
                            if ticket then break end
                        end
                    end
                end
            end
        end
        if not ticket then
            fail(result, setPhase, current, "six_seat_spawn_" .. state.index, why)
            return
        end
        state.ticket = ticket
        setPhase("six_seat_spawn", current)
        return
    end
    if H.phase == "six_seat_board" then
        local actor = state.actors[state.index]
        local assignment, why = SC.Vehicle.assignmentFor(actor, vehicle, H.player)
        if not assignment then
            fail(result, setPhase, current, "six_seat_assignment_" .. state.index, why)
            return
        end
        local square, _, doorReason = SC.Vehicle.boardingSquare(actor,
            vehicle, assignment.seat)
        if not square then
            fail(result, setPhase, current, "six_seat_door_" .. state.index,
                "seat " .. assignment.seat .. ": " .. tostring(doorReason))
            return
        end
        local placed, placementReason = H.placeCombatActor(actor, {
            x = square:getX() + 0.5, y = square:getY() + 0.5, z = 0 })
        if not placed then
            fail(result, setPhase, current, "six_seat_place_" .. state.index,
                placementReason)
            return
        end
        local boarded, status = SC.Vehicle.board(actor, vehicle, assignment.seat,
            { allowVirtualSeat = false })
        local actualSeat = vehicle:getSeat(actor)
        if not check("six_seat_board_" .. state.index,
            boarded == true and status == "native_seat"
                and SC.Vehicle.isNativeSeated(actor),
            "requested=" .. tostring(assignment.seat)
                .. " actual=" .. tostring(actualSeat)
                .. " status=" .. tostring(status)) then
            setPhase("finish", current)
            return
        end
        state.index = state.index + 1
        if state.index > 5 then
            local all = vehicle:getSeat(H.player) == 0
            local seated = {}
            for seat = 1, 5 do
                local occupant = vehicle:getCharacter(seat)
                all = all and occupant ~= nil
                    and occupant:getVehicle() == vehicle
                seated[seat] = tostring(occupant and SC.Registry.idOf(occupant))
            end
            if not check("six_seat_five_native_passengers", all,
                table.concat(seated, ",")) then
                setPhase("finish", current)
                return
            end
            state.exitQueue = {}
            for seat = 1, 5 do
                state.exitQueue[#state.exitQueue + 1] = vehicle:getCharacter(seat)
            end
            state.index = 1
            setPhase("six_seat_exit", current)
        end
        return
    end
    if H.phase == "six_seat_exit" then
        local actor = state.exitQueue[state.index]
        local exited, why = SC.Vehicle.exit(actor, vehicle)
        if not check("six_seat_exit_" .. state.index,
            exited == true and actor:getVehicle() == nil,
            tostring(why)) then setPhase("finish", current) return end
        -- A real follower walks away after getting out; make the next door
        -- square available without placing anyone in a wall or in the van.
        state.awayUsed = state.awayUsed or {}
        local cx, cy = math.floor(vehicle:getX()), math.floor(vehicle:getY())
        local moved = false
        for radius = 7, 12 do
            if moved then break end
            for dx = -radius, radius do
                if moved then break end
                for dy = -radius, radius do
                    if math.abs(dx) == radius or math.abs(dy) == radius then
                        local square = SC.GameplayUtil.gridSquare(cx + dx,
                            cy + dy, 0)
                        local key = tostring(cx + dx) .. ":" .. tostring(cy + dy)
                        if square and not state.awayUsed[key]
                            and square:isOutside() and square:getRoom() == nil
                            and square:getBuilding() == nil
                            and not square:isSolid() and not square:isSolidTrans()
                            and square:TreatAsSolidFloor() and square:isFree(true)
                            and square:getVehicleContainer() == nil
                            and square ~= H.player:getCurrentSquare() then
                            moved = H.placeCombatActor(actor, {
                                x = square:getX() + 0.5,
                                y = square:getY() + 0.5, z = 0 }) == true
                            if moved then state.awayUsed[key] = true break end
                        end
                    end
                end
            end
        end
        if not check("six_seat_exit_clear_" .. state.index, moved,
            "exited companion moved to a checked clear outdoor square") then
            setPhase("finish", current)
            return
        end
        state.index = state.index + 1
        if state.index > 5 then setPhase("finish", current) end
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCSixSeatProbe = Probe
