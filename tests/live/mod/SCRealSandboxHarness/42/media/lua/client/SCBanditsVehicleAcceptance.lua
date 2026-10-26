-- SPDX-License-Identifier: MIT
-- Real passenger boarding and stock Bandits melee against a stopped car.
if not SCRealSandboxHarnessProbes or not SCRealSandboxHarnessProbes.SCBanditsCloseCombatAcceptance then
    require "SCBanditsCloseCombatAcceptance"
end
local Probe = {}
local CombatProbe = SCRealSandboxHarnessProbes.SCBanditsCombatAcceptance
local Shared = CombatProbe.shared
local Close = SCRealSandboxHarnessProbes.SCBanditsCloseCombatAcceptance
local call, partsHealth = Shared.call, Shared.partsHealth
local function snapshot(f)
    local part = f.car:getPartById("WindowFrontRight")
    local item = call(part, "getInventoryItem")
    local window = call(part, "getWindow")
    local condition = call(part, "getCondition")
    local damage = SurvivorCompanion.BanditsAdapter.status()
    return { condition = condition, item = item, window = window, meleeHits = damage.meleeHits,
        open = call(window, "isOpen") == true,
        intact = item ~= nil and type(condition) == "number" and condition > 0 }
end
local function observe(f, action, task, hitBefore, before, after, healthBefore, healthAfter)
    if action ~= "Smack" or task.eid ~= "lf:" .. f.id or hitBefore == true or task.hit ~= true
        or not before or not after then return end
    local status = SurvivorCompanion.BanditsAdapter.status()
    if before.intact and not before.open and after.intact and healthBefore and healthAfter
        and healthAfter < healthBefore then f.failure = "native wound passed intact closed glass" end
    local wound = healthBefore and healthAfter and healthAfter < healthBefore
        and type(before.meleeHits) == "number" and type(after.meleeHits) == "number"
        and after.meleeHits > before.meleeHits
        and status.lastVictim == "lf:" .. f.id and status.lastModel == "MeleeHit"
    if before.intact and not before.open and after.intact and after.condition < before.condition
        and healthBefore == healthAfter then f.closedProtected = f.closedProtected + 1 end
    if before.intact and before.open and wound then f.openWound = f.openWound + 1 end
    if not after.intact and wound then f.brokenWound = f.brokenWound + 1 end
    print("SC_REAL_SANDBOX|VEHICLE_WINDOW_IMPACT|stage=" .. f.stage .. "|eid=" .. tostring(task.eid)
        .. "|condition=" .. tostring(before.condition) .. "->" .. tostring(after.condition)
        .. "|intact=" .. tostring(before.intact) .. "->" .. tostring(after.intact)
        .. "|open=" .. tostring(before.open) .. "|parts=" .. tostring(healthBefore) .. "->" .. tostring(healthAfter)
        .. "|protected=" .. f.closedProtected .. "|open_wounds=" .. f.openWound .. "|broken_wounds=" .. f.brokenWound)
end
local function finish(H, current, check, result, setPhase, good, why)
    local f = H.banditsVehicle
    if f then
        good = check("window_primary_isolation", Shared.samePlayers(f.primary), "main identity/slots/count unchanged") and good
        good = check("window_stopped_car", SurvivorCompanion.Vehicle.isStationary(f.car)
            and call(f.car, "isEngineRunning") == false, "actual car stationary and engine stopped") and good
        if f.gun then
            good = check("vehicle_hold_fire_retained", (f.lfSpent or 0) == 0,
                "normal Hold Fire retained; actual LF rounds=" .. tostring(f.lfSpent or 0)) and good
        end
        good = not f.failure and not f.leaked and not f.shoveDamage and good
        if f.fireModule then f.fireModule.cleanup(f) CombatProbe.cleanup(f) end
        Close.cleanup(f)
    end
    local label = H.config.bandits_combat_scenario or "vehicle_window"
    getCore():TakeFullScreenshot(tostring(H.config.run_id) .. "-bandits-" .. label .. ".png")
    result(good and "PASS" or "FAIL", "bandits_live_" .. label, why)
    setPhase("finish", current)
end
local function carAtCamp(SC)
    for _, car in ipairs(SC.Vehicle.loadedVehicles()) do
        if call(car, "getSqlId") == 46 and SC.Vehicle.isStationary(car)
            and call(car, "isEngineRunning") == false and call(car, "getCharacter", 1) == nil then
            local part = car:getPartById("WindowFrontRight")
            if part and part:getInventoryItem() and part:getCondition() > 0 and part:getWindow() then return car end
        end
    end
end
local function stageBandit(SC, actor, square)
    if not SC.GameplayUtil.isSquareFree(square) or SC.GameplayUtil.squareOccupyingObject(square) ~= nil then return false end
    local moving = square:getMovingObjects()
    for index = 0, moving:size() - 1 do if moving:get(index) ~= actor then return false end end
    local x, y, z = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
    actor:teleportTo(x, y, z)
    actor:setX(x) actor:setY(y) actor:setLastX(x) actor:setLastY(y) actor:setNextX(x) actor:setNextY(y)
    actor:setCurrentSquareFromPosition() actor:setMovingSquareNow()
    return true
end
local function carFreeRay(shooter, target)
    local x, y, tx, ty = math.floor(shooter:getX()), math.floor(shooter:getY()), math.floor(target:getX()), math.floor(target:getY())
    local z, dx, dy = target:getZ(), math.abs(tx - x), math.abs(ty - y)
    local sx, sy, step = x < tx and 1 or -1, y < ty and 1 or -1, 0
    local err = dx - dy
    while step <= 64 do
        if step > 1 then
            local radius = x == tx and y == ty and 2 or 0
            for ox = -radius, radius do
                for oy = -radius, radius do
                    local square = getCell():getGridSquare(x + ox, y + oy, z)
                    if not square or call(square, "getVehicleContainer") ~= nil then return false end
                end
            end
        end
        if x == tx and y == ty then return true end
        local e2 = err * 2
        if e2 > -dy then err, x = err - dy, x + sx end
        if e2 < dx then err, y = err + dx, y + sy end
        step = step + 1
    end
    return false
end
local function keepsGunRange(actor, shooter, target)
    local ax, ay, bx, by = actor:getX(), actor:getY(), target:getX() + 0.5, target:getY() + 0.5
    local dx, dy, sx, sy = bx - ax, by - ay, shooter:getX(), shooter:getY()
    local length = dx * dx + dy * dy
    if length < 0.01 then return false end
    local t = math.max(0, math.min(1, ((sx - ax) * dx + (sy - ay) * dy) / length))
    return (ax + t * dx - sx)^2 + (ay + t * dy - sy)^2 > 5.25^2
end
local function exposeOnFoot(SC, f)
    local x, y, z = f.actor:getX(), f.actor:getY(), math.floor(f.actor:getZ())
    local best, score
    local mainDistance = SC.GameplayUtil.distance(f.bandit, f.primary.player)
    for index = 0, 63 do
        local angle, radius = math.pi * (index % 32) / 16, index < 32 and 6 or 7
        local square = getCell():getGridSquare(math.floor(f.bandit:getX() + math.cos(angle) * radius),
            math.floor(f.bandit:getY() + math.sin(angle) * radius), z)
        if square and SC.GameplayUtil.isClearActorSpawnSquare(square)
            and keepsGunRange(f.actor, f.bandit, square)
            and carFreeRay(f.bandit, square)
            and tostring(LosUtil.lineClear(getCell(), f.bandit:getX(), f.bandit:getY(), f.bandit:getZ(),
                square:getX() + 0.5, square:getY() + 0.5, z, false)) ~= "Blocked" then
            local distance = math.sqrt((square:getX() + 0.5 - f.bandit:getX())^2 + (square:getY() + 0.5 - f.bandit:getY())^2)
            local move = (square:getX() + 0.5 - x)^2 + (square:getY() + 0.5 - y)^2
            -- Stock Bandits uses the closest visible player and switches to
            -- melee below 4.5 outdoor tiles. Moving far away hands its target
            -- back to the main player who remains in the driver's seat.
            if distance > 5.5 and distance < mainDistance - 0.25 and move <= 121
                and (not score or move < score) then best, score = square, move end
        end
    end
    if not best then return false, "no clear normal foot-exposure route" end
    local ordered, why = SC.Commands.issue(f.id, "set_move_mode", "jog", f.primary.player)
    if not ordered then return false, why end
    ordered, why = SC.Commands.issue(f.id, "set_combat_doctrine", "close_defense", f.primary.player)
    if not ordered then return false, why end
    ordered, why = SC.Commands.issue(f.id, "set_hold_fire", true, f.primary.player)
    if not ordered then return false, why end
    f.exposureTarget = { x = best:getX(), y = best:getY(), z = z }
    return SC.Commands.issue(f.id, "move_to", { x = best:getX(), y = best:getY(), z = z }, f.primary.player)
end
local function spawnPassenger(SC, f)
    local car = f.car
    local spawn
    for _, square in ipairs(SC.Vehicle.safeExitSquares(car, 1) or {}) do
        if SC.GameplayUtil.isClearActorSpawnSquare(square) then spawn = square break end
    end
    if not spawn then return false, "no native passenger-door spawn" end
    local ticket, reason = SC.Actor.beginSpawn(spawn, { recruited = true, identity = SC.Spawn.generateIdentity(),
        background = { profession = "unemployed" } })
    if not ticket then return false, reason end
    f.ticket, f.stage = ticket, "spawn_lf"
    return true
end
local function beginPassenger(SC, f, current)
    local car, primary = f.car, f.primary
    if primary.player:getVehicle() ~= nil or car:getCharacter(0) ~= nil
        or car:enter(0, primary.player) ~= true or car:getCharacter(0) ~= primary.player then
        return false, "native observer driver boarding unavailable"
    end
    car:playPassengerAnim(0, "idle")
    local part = car:getPassengerDoor(1)
    local door = call(part, "getDoor")
    if door and call(door, "isLocked") == true then
        ISVehicleMenu.onUnlockDoor(primary.player, part)
        f.unlockPart, f.unlockAt, f.stage = part, current, "unlock_passenger"
        return true
    end
    return spawnPassenger(SC, f)
end
local function unloadObserver(player, square)
    local inventory, limit = player:getInventory(), tonumber(call(player, "getMaxWeight"))
    if not limit or limit <= 0 then return false, "observer native carry limit unavailable" end
    local initial, moved = inventory:getCapacityWeight(), 0
    local function unload(container, depth)
        local items = container:getItems()
        for index = items:size() - 1, 0, -1 do
            if inventory:getCapacityWeight() <= limit * 0.8 then return true end
            if moved >= 512 or depth > 4 then return false end
            local item = items:get(index)
            local bag = call(item, "getItemContainer")
            if bag and not unload(bag, depth + 1) then return false end
            if inventory:getCapacityWeight() > limit * 0.8
                and player:isEquippedClothing(item) ~= true and player:isEquipped(item) ~= true then
                local id = item:getID()
                container:Remove(item)
                square:AddWorldInventoryItem(item, 0.5, 0.5, 0)
                local world = call(item, "getWorldItem")
                if not world or call(world, "getItem") ~= item or item:getID() ~= id then return false end
                moved = moved + 1
                print("SC_REAL_SANDBOX|VEHICLE_OBSERVER_UNLOAD|id=" .. tostring(id)
                    .. "|type=" .. item:getFullType() .. "|exact_world_item=true")
            end
        end
        return true
    end
    local good = unload(inventory, 0) and inventory:getCapacityWeight() <= limit
    print("SC_REAL_SANDBOX|VEHICLE_OBSERVER_LOAD|weight=" .. initial .. "->" .. inventory:getCapacityWeight()
        .. "|limit=" .. limit .. "|real_items_dropped=" .. moved .. "|before_hostility=true")
    return good, good and "observer load prepared" or "observer remains overloaded"
end
function Probe.step(H, current, check, result, setPhase)
    local SC, f = SurvivorCompanion, H.banditsVehicle
    if not f then
        if current - H.startedAt < 10000 or not SC.State.active or SC.Registry.count() == 0 then return end
        if not check("window_adapter_active", SC.BanditsAdapter.status().active, SC.BanditsAdapter.status().reason) then
            setPhase("finish", current) return
        end
        local primary = Shared.playerState()
        local guns = H.config.bandits_combat_scenario == "vehicle_bullets"
        local car, site
        if guns then
            -- Keep the ordinary population, but use a real new car outside
            -- camp's defence cluster. Near camp, closer resident defenders
            -- legitimately take over the attacker's target after LF exits.
            site = Shared.field(SC, primary.player, 40, 64)
            if not site then finish(H, current, check, result, setPhase, false, "no distant loaded native car scene") return end
            local prepared, why = unloadObserver(primary.player, site.observer)
            if not prepared then finish(H, current, check, result, setPhase, false, tostring(why)) return end
            primary.player:teleportTo(site.observer:getX() + 0.5, site.observer:getY() + 0.5, site.observer:getZ())
            local d = site.direction
            local facing = d[1] == 1 and IsoDirections.E or d[1] == -1 and IsoDirections.W
                or d[2] == 1 and IsoDirections.S or IsoDirections.N
            local okay, created = pcall(addVehicleDebug, "Base.CarNormal", facing, nil, site.fellow)
            if not okay or not created or not created:getSquare() then
                finish(H, current, check, result, setPhase, false, "native new car spawn rejected") return
            end
            car = created
        else
            car = carAtCamp(SC)
            if not car then finish(H, current, check, result, setPhase, false, "saved stopped car46 with intact front-right window unavailable") return end
        end
        f = { car = car, site = site, primary = primary, started = current, stage = "settle_car",
            guns = H.config.bandits_combat_scenario == "vehicle_bullets",
            bindings = {}, bandits = {}, before = {}, retired = {}, closedProtected = 0, openWound = 0, brokenWound = 0,
            incomingMelee = 0, incomingHand = 0, incomingPush = 0, incomingBites = 0 }
        H.banditsVehicle = f
        for id in pairs(BanditZombie.Cache) do f.before[id] = true end
        return
    end
    if f.gun then
        local ammo = f.gun:getCurrentAmmoCount()
        if ammo < f.lastAmmo then f.lfSpent = (f.lfSpent or 0) + f.lastAmmo - ammo end
        f.lastAmmo = ammo
    end
    if f.observerExitRequested and not f.observerWalkQueued and f.primary.player:getVehicle() == nil then
        require "TimedActions/WalkToTimedAction"
        ISTimedActionQueue.add(ISWalkToTimedAction:new(f.primary.player, f.site.observer))
        f.observerWalkQueued = true
        result("PASS", "vehicle_observer_walk_requested", "ordinary native Walk to after driver exit; no teleport after hostility")
    end
    if f.failure or current - f.started > 150000 or call(f.primary.player, "isDead") == true
        or f.actor and call(f.actor, "isDead") == true then
        finish(H, current, check, result, setPhase, false, f.failure or "native death/deadline") return
    end
    if f.stage == "settle_car" then
        if current - f.started < 2000 or not SC.Vehicle.isStationary(f.car) then return end
        local state = snapshot(f)
        if f.car:isEngineRunning() or not state.intact or not state.window then
            finish(H, current, check, result, setPhase, false, "native stopped car/window preflight failed") return
        end
        local started, why = beginPassenger(SC, f, current)
        if not started then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        result("PASS", "window_observer_seated", "actual main in stopped native car; sql=" .. tostring(f.car:getSqlId())
            .. "; normal ride policy; original car parts; " .. (f.guns and "distant field" or "saved car46"))
        return
    end
    if f.stage == "unlock_passenger" then
        if call(call(f.unlockPart, "getDoor"), "isLocked") == false then
            local spawned, why = spawnPassenger(SC, f)
            if not spawned then finish(H, current, check, result, setPhase, false, tostring(why)) return end
            result("PASS", "window_passenger_unlocked", "ordinary driver-seat Unlock door action completed")
        elseif current - f.unlockAt > 15000 then
            finish(H, current, check, result, setPhase, false, "native passenger unlock deadline")
        end
        return
    end
    if f.stage == "spawn_lf" then
        local actor, reason = SC.Actor.pollSpawn(f.ticket)
        if not actor then
            if reason ~= "spawn_pending" then finish(H, current, check, result, setPhase, false, tostring(reason)) end
            return
        end
        f.actor, f.id = actor, SC.Registry.idOf(actor)
        actor:setPrimaryHandItem(nil) actor:setSecondaryHandItem(nil)
        if f.guns then
            local gun, why = Shared.equip(actor)
            if not gun then finish(H, current, check, result, setPhase, false, tostring(why)) return end
            f.gun, f.lastAmmo = gun, gun:getCurrentAmmoCount()
            SC.InventoryIndex.touch(actor)
            local equipped, reason = SC.Combat.equipPreferred(actor, "firearm")
            if not equipped then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
            local held, reason = SC.Commands.issue(f.id, "set_hold_fire", true, f.primary.player)
            if not held then finish(H, current, check, result, setPhase, false, tostring(reason)) return end
            SC.Commands.issue(f.id, "set_scavenge", false, f.primary.player)
        end
        local accepted, why = SC.Commands.issue(f.id, "stay", nil, f.primary.player)
        if not accepted then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        local boarded, boardWhy = SC.Commands.issue(f.id, "board_vehicle", { vehicle = f.car, seat = 1 }, f.primary.player)
        if not boarded then finish(H, current, check, result, setPhase, false, tostring(boardWhy)) return end
        f.stage, f.boardAt = "boarding", current
        result("PASS", "window_boarding_requested", "normal public passenger boarding; car46; actual LF=" .. f.id)
        return
    end
    if f.stage == "boarding" then
        if f.actor:getVehicle() ~= f.car or f.car:getSeat(f.actor) ~= 1 then
            if current - f.boardAt > 30000 then finish(H, current, check, result, setPhase, false, "native passenger boarding deadline") end
            return
        end
        f.seatedAt = f.seatedAt or current
        if current - f.seatedAt < 1500 then return end
        SC.Commands.issue(f.id, "stay", nil, f.primary.player)
        local state = snapshot(f)
        state.window:setOpen(false)
        local squares = SC.Vehicle.safeExitSquares(f.car, 1)
        local selected, distance
        for _, square in ipairs(squares or {}) do
            if SC.GameplayUtil.isClearActorSpawnSquare(square) then
                local d = (square:getX() + 0.5 - f.actor:getX())^2 + (square:getY() + 0.5 - f.actor:getY())^2
                if not distance or d < distance then selected, distance = square, d end
            end
        end
        if not selected then finish(H, current, check, result, setPhase, false, "no clear native outside attack position") return end
        if f.guns then
            local x, y, z = f.actor:getX(), f.actor:getY(), math.floor(f.actor:getZ())
            local dx, dy = selected:getX() + 0.5 - x, selected:getY() + 0.5 - y
            local angle, found = math.atan2(dy, dx), nil
            for _, turn in ipairs({ 0, 0.5, -0.5, 1, -1, math.pi / 2, -math.pi / 2, math.pi }) do
                local square = getCell():getGridSquare(math.floor(x + math.cos(angle + turn) * 7),
                    math.floor(y + math.sin(angle + turn) * 7), z)
                -- Firearm placement requires the original LOS rule, not an
                -- on-foot route through the car's collision footprint.
                if square and SC.GameplayUtil.isClearActorSpawnSquare(square)
                    and SC.GameplayUtil.distance(f.primary.player, square) > SC.GameplayUtil.distance(f.actor, square) + 0.25
                    and tostring(LosUtil.lineClear(getCell(), x, y, z, square:getX() + 0.5,
                        square:getY() + 0.5, z, false)) ~= "Blocked" then found = square break end
            end
            if not found then finish(H, current, check, result, setPhase, false, "no clear seven-tile native firearm position") return end
            selected = found
        end
        print("SC_REAL_SANDBOX|VEHICLE_NATIVE_PLACEMENT|car=" .. f.car:getX() .. "," .. f.car:getY()
            .. "|main=" .. f.primary.player:getX() .. "," .. f.primary.player:getY()
            .. "|LF=" .. f.actor:getX() .. "," .. f.actor:getY()
            .. "|shooter=" .. selected:getX() .. "," .. selected:getY())
        f.banditSpawnSquare = selected
        -- Unchanged stock Officers or armored soldier; native attack choices.
        BanditServer.Spawner.Clan(f.primary.player, { cid = f.guns and "d7ba1cc0-de47-4162-b5bd-6295c47b890d"
            or "a2dec2f0-c76d-4640-8a71-733a547a1ebc", size = 1,
            hostile = false, hostileP = false,
            spawnPoints = { { x = selected:getX(), y = selected:getY(), z = selected:getZ() } } })
        f.spawnAt, f.stage = current, "spawn_bandit"
        result("PASS", "window_native_seated", "native seat1; glass condition=" .. tostring(state.condition)
            .. "; nearest outside distance=" .. math.sqrt(distance) .. "; no health/skill overrides")
        return
    end
    if f.stage ~= "leaving_car" and f.stage ~= "exposed"
        and (f.actor:getVehicle() ~= f.car or f.car:getSeat(f.actor) ~= 1) then
        finish(H, current, check, result, setPhase, false, "LF left the actual passenger seat") return
    end
    if f.stage == "spawn_bandit" then
        local bandit, nearest = f.spawnedBandit, math.huge
        for id, actor in pairs(BanditZombie.Cache) do
            if not bandit and not f.before[id] and SC.BanditsAdapter.owns(actor) then
                local distance = SC.GameplayUtil.distance(actor, f.actor)
                if distance < nearest and distance < 32 then bandit, nearest = actor, distance end
            end
        end
        if bandit then f.spawnedBandit = bandit end
        if not bandit or current - f.spawnAt < 2500 or SC.BanditsAdapter.relationship(bandit, f.actor) ~= "neutral" then
            if current - f.spawnAt > 20000 then
                finish(H, current, check, result, setPhase, false, "native Bandit preparation deadline; loaded=" .. tostring(bandit ~= nil))
            end
            return
        end
        if not stageBandit(SC, bandit, f.banditSpawnSquare) then
            finish(H, current, check, result, setPhase, false, "initial Bandit staging tile became occupied") return
        end
        result("PASS", "window_bandit_ready", "native actor=" .. tostring(Shared.targetID(bandit))
            .. "; distance=" .. SC.GameplayUtil.distance(bandit, f.actor) .. "; initial placement ends before hostility")
        f.bandits[bandit], f.bandit = true, bandit
        f.banditNativeID = call(bandit, "getID")
        local observed, why
        if f.guns then
            require "SCBanditsVehicleFireEvidence"
            f.fireModule = SCRealSandboxHarnessProbes.SCBanditsVehicleFireEvidence
            f.exposureClear = function(shooter)
                return f.actor:getVehicle() == nil and carFreeRay(shooter, f.actor)
            end
            observed, why = f.fireModule.install(f)
            if observed then observed, why = CombatProbe.observeFirearms(f) end
        else
            f.windowSnapshot = function() return snapshot(f) end
            f.windowObserve = function(...) return observe(f, ...) end
            observed, why = Close.observeActions(f)
        end
        if not observed then finish(H, current, check, result, setPhase, false, tostring(why)) return end
        bandit:faceLocationF(f.actor:getX(), f.actor:getY())
        BanditPlayer.CheckFriendlyFire(bandit, f.actor)
        f.stage, f.nextTrace = f.guns and "gunfire" or "closed", current
        return
    end
    if f.guns and f.bandit and (call(f.bandit, "isDead") == true
        or call(f.bandit, "getHealth") == 0 or call(f.bandit, "getID") ~= f.banditNativeID) then
        f.retired[f.bandit] = true
        finish(H, current, check, result, setPhase, false, "native attacker died/retired before the required exposed wound") return
    end
    if f.stage == "gunfire" and (f.vehicleBlocks or 0) > 0 then
        local exited, why = SC.Commands.issue(f.id, "exit_vehicle", { vehicle = f.car }, f.primary.player)
        if not exited then finish(H, current, check, result, setPhase, false, "normal exposed exit: " .. tostring(why)) return end
        f.stage, f.exitStartedAt = "leaving_car", current
        -- The driver also steps back through normal player actions. Leaving
        -- Main closer in seat0 makes the stock closest-player AI legitimately
        -- switch its fire away from LF after the passenger flanks.
        ISVehicleMenu.onExit(f.primary.player, 0)
        f.observerExitRequested = true
        result("PASS", "vehicle_bullet_exposed_exit_requested", "stock part blocked native fire; normal Exit vehicle now requested")
    elseif f.stage == "leaving_car" then
        if f.actor:getVehicle() == nil then
            f.onFootAt = f.onFootAt or current
            if current - f.onFootAt < 750 then return end
            print("SC_REAL_SANDBOX|VEHICLE_NATIVE_EXIT|LF=" .. f.actor:getX() .. "," .. f.actor:getY()
                .. "|shooter=" .. f.bandit:getX() .. "," .. f.bandit:getY()
                .. "|main_distance=" .. SC.GameplayUtil.distance(f.bandit, f.primary.player))
            local moved, why = exposeOnFoot(SC, f)
            if not moved then finish(H, current, check, result, setPhase, false, tostring(why)) return end
            f.stage = "exposed"
            result("PASS", "vehicle_bullet_native_exposed", "native exit; normal jog/close-defense Move here to vehicle-free stock ray="
                .. f.exposureTarget.x .. "," .. f.exposureTarget.y .. "; no repositioning")
        elseif current - f.exitStartedAt > 30000 then
            finish(H, current, check, result, setPhase, false, "native passenger exit deadline") return
        end
    end
    if f.stage == "exposed" and (f.vehicleBlocks or 0) > 0
        and (f.nativeBulletWounds or 0) > 0 and (f.exposedBulletWounds or 0) > 0 then
        finish(H, current, check, result, setPhase, true, "natural vehicle-blocked bullets=" .. f.vehicleBlocks
            .. "; exact LF native bullet wounds=" .. f.nativeBulletWounds
            .. "; wounds on foot with actual vehicle-free ray=" .. f.exposedBulletWounds .. "; final stage=" .. f.stage
            .. "; stock random part selection, accuracy and damage unchanged") return
    end
    if f.stage == "closed" and f.closedProtected > 0 then
        local state = snapshot(f)
        if not state.intact then finish(H, current, check, result, setPhase, false, "glass broke before open-intact phase") return end
        state.window:setOpen(true)
        f.stage = "open"
        result("PASS", "window_opened_intact", "normal window API; remaining condition=" .. state.condition)
    elseif f.stage == "open" and f.openWound > 0 then
        snapshot(f).window:setOpen(false)
        f.stage = "breaking"
        result("PASS", "window_closed_for_native_break", "no repair; stock attacks must break remaining glass")
    elseif f.stage == "breaking" and f.brokenWound > 0 then
        finish(H, current, check, result, setPhase, true, "native closed-glass protection=" .. f.closedProtected
            .. "; open intact wounds=" .. f.openWound .. "; broken-window wounds=" .. f.brokenWound) return
    end
    if current >= (f.nextTrace or current) then
        f.nextTrace = current + 1000
        local state, task = snapshot(f), f.bandit and Bandit.GetTask(f.bandit)
        local decision = SurvivorCompanion.Decision.peek(f.actor) or {}
        print("SC_REAL_SANDBOX|VEHICLE_WINDOW|stage=" .. f.stage .. "|condition=" .. tostring(state.condition)
            .. "|open=" .. tostring(state.open) .. "|parts=" .. tostring(partsHealth(f.actor))
            .. "|task=" .. tostring(task and task.action) .. ":" .. tostring(task and task.eid)
            .. "|vehicle_blocks=" .. tostring(f.vehicleBlocks) .. "|native_bullet_wounds=" .. tostring(f.nativeBulletWounds)
            .. "|lf_vehicle=" .. tostring(call(call(f.actor, "getVehicle"), "getSqlId"))
            .. "|point=" .. tostring(f.actor:getX()) .. "," .. tostring(f.actor:getY()) .. "|intent=" .. tostring(decision.intent)
            .. "|hold_fire=" .. tostring((SC.Commands.peek(f.actor) or {}).holdFire) .. "|lf_rounds=" .. tostring(f.lfSpent or 0)
            .. "|main_distance=" .. tostring(f.bandit and SC.GameplayUtil.distance(f.bandit, f.primary.player))
            .. "|distance=" .. tostring(f.bandit and SC.GameplayUtil.distance(f.actor, f.bandit)))
    end
end
Probe.snapshot, Probe.observe, Probe.carFreeRay, Probe.keepsGunRange = snapshot, observe, carFreeRay, keepsGunRange
Probe.unloadObserver = unloadObserver
SCRealSandboxHarnessProbes.SCBanditsVehicleAcceptance = Probe
return Probe
