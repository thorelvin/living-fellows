-- SPDX-License-Identifier: MIT
-- Runs only in the isolated live harness, never in the shipped mod.

local Probe = {}

local function call(object, method, ...)
    if object == nil then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    if ok then return value end
    return nil
end

local function bodyName(body)
    local descriptor = call(body, "getDescriptor")
    local first = call(descriptor, "getForename") or ""
    local last = call(descriptor, "getSurname") or ""
    local name = tostring(first) .. " " .. tostring(last)
    return name ~= " " and name or "unknown"
end

local function bodyContents(body, SC)
    local container = call(body, "getContainer")
    if not container then return "empty" end
    local count, diary, personal, owned, owners = 0, 0, 0, 0, {}
    local _, complete = SC.PersonalItems.walkContainer(container, function(item)
        count = count + 1
        if SC.DiaryItem.hasPayload(item) then diary = diary + 1 end
        local record = SC.PersonalItems.personalRecord(item)
        if record then
            personal = personal + 1
            owners[#owners + 1] = tostring(record.ownerId)
                .. "/" .. tostring(record.kind)
        end
        local protected, reason = SC.WorkTransport.foreignProtected(item, nil)
        if protected and reason ~= "favorite_item" then owned = owned + 1 end
    end, { budget = 256 })
    return "items=" .. tostring(count) .. " diary=" .. tostring(diary)
        .. " personal=" .. tostring(personal) .. " protected=" .. tostring(owned)
        .. " complete=" .. tostring(complete)
        .. " owner=" .. table.concat(owners, ",")
end

local function scanBodies(base, SC)
    local rows, seen, scanned = {}, {}, 0
    for _, zone in ipairs(base.zones or {}) do
        if zone.kind == "area" or zone.kind == "lumber" or zone.kind == "burial" then
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local key = tostring(x) .. ":" .. tostring(y) .. ":" .. tostring(zone.z)
                    if not seen[key] and scanned < 5000 then
                        seen[key], scanned = true, scanned + 1
                        local square = getCell():getGridSquare(x, y, zone.z)
                        local objects = call(square, "getStaticMovingObjects")
                        if objects then
                            for index = 0, objects:size() - 1 do
                                local body = objects:get(index)
                                if instanceof(body, "IsoDeadBody") then
                                    rows[#rows + 1] = {
                                        body = body, square = square, x = x, y = y, z = zone.z,
                                        zone = zone.kind, name = bodyName(body),
                                        deathId = SC.Community and select(1,
                                            SC.Community.deathMatching(bodyName(body))) or nil,
                                        playerBody = call(body, "isPlayer") == true,
                                        fake = call(body, "isFakeDead") == true,
                                        animal = call(body, "isAnimal") == true,
                                        contents = bodyContents(body, SC),
                                    }
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return rows, scanned
end

local function describeOrders(SC)
    local rows = {}
    for _, order in ipairs(SC.BaseLife.productionOrders(true) or {}) do
        if order.operation == "collect_bodies" or order.operation == "bury_bodies"
            or order.operation == "dig_graves" then
            rows[#rows + 1] = tostring(order.id) .. ":" .. tostring(order.operation)
                .. ":" .. tostring(order.state) .. ":" .. tostring(order.blocker)
                .. ":withBelongings=" .. tostring(order.settings
                    and order.settings.withBelongings)
        end
    end
    return #rows > 0 and table.concat(rows, "; ") or "none"
end

local function chooseCleaner(SC)
    local reserve
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        local actor = record.actor
        local square = call(actor, "getSquare")
        local resident = SC.BaseLife.resident(record.id)
        if record.recruited == true and actor and square
            and SC.BaseLife.isInside(actor) == true
            and call(square, "getRoom") ~= nil then
            local choice = { actor = actor, id = record.id, square = square }
            if not resident or resident.role ~= "corpsekeeper" then return choice end
            reserve = reserve or choice
        end
    end
    return reserve
end

local function prepareCleaning(H, SC, check, result)
    local cleaner = chooseCleaner(SC)
    if not check("maintenance_indoor_companion", cleaner ~= nil,
        cleaner and cleaner.id or "no recruited resident is indoors in camp") then return nil end
    H.maintenanceCleaner = cleaner
    local accepted, reason = SC.Commands.issue(cleaner.id, "stay", {}, H.player)
    result(accepted and "PASS" or "FAIL", "maintenance_cleaner_stay",
        tostring(reason))
    SC.Downtime.cancel(cleaner.actor, "maintenance_fixture")
    local inventory = cleaner.actor:getInventory()
    cleaner.mop = inventory:AddItem("Base.Mop")
    cleaner.bleach = inventory:AddItem("Base.Bleach")
    local fluid = call(cleaner.bleach, "getFluidContainer")
    cleaner.before = tonumber(call(fluid, "getAmount")) or 0
    local mopTag = ItemTag and ItemTag.CLEAN_STAINS
    local tagged = mopTag and call(cleaner.mop, "hasTag", mopTag) == true
    check("maintenance_spawned_supplies", cleaner.mop ~= nil
        and cleaner.bleach ~= nil and tagged and cleaner.before > 0,
        "mopTag=" .. tostring(tagged) .. " bleach=" .. tostring(cleaner.before)
            .. " minimum=" .. tostring(ZomboidGlobals.CleanBloodBleachAmount))
    local square = cleaner.square
    local stained, stainReason = pcall(function() addBloodSplat(square, 20) end)
    if not stained then
        stained, stainReason = pcall(function()
            square:getChunk():addBloodSplat(square:getX() + 0.5,
                square:getY() + 0.5, square:getZ(), 20)
        end)
    end
    cleaner.stain = call(square, "haveStains") == true
    cleaner.x, cleaner.y, cleaner.z = square:getX(), square:getY(), square:getZ()
    check("maintenance_spawned_stain", cleaner.stain,
        "at=" .. tostring(square:getX()) .. "," .. tostring(square:getY())
            .. " splat=" .. tostring(stained) .. " reason=" .. tostring(stainReason))
    local can, why = SC.Downtime.canPerform(cleaner.actor, "clean_base")
    check("maintenance_cleaning_candidate", can == true, tostring(why))
    return cleaner
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "base_maintenance_setup" then
        local base = SC.BaseLife.active()
        local roster = SC.Registry.snapshot() or {}
        if (not base or #roster == 0) and current - H.phaseStartedAt < 12000 then return end
        if not check("maintenance_base_loaded", base ~= nil,
            base and base.name or "no active base") then setPhase("finish", current) return end
        local zones = {}
        for _, zone in ipairs(base.zones or {}) do
            zones[#zones + 1] = tostring(zone.kind) .. "@" .. tostring(zone.x1)
                .. "," .. tostring(zone.y1) .. "-" .. tostring(zone.x2)
                .. "," .. tostring(zone.y2) .. "," .. tostring(zone.z)
        end
        result("PASS", "maintenance_zones", table.concat(zones, "; "))
        local gravekeepers = {}
        for _, record in ipairs(roster) do
            local resident = SC.BaseLife.resident(record.id)
            if resident and resident.role == "corpsekeeper" then
                gravekeepers[#gravekeepers + 1] = tostring(call(record.actor, "getFullName")
                    or record.id)
                    .. ":duty=" .. tostring(resident.duty)
                    .. ":actor=" .. tostring(record.actor ~= nil)
                    .. ":order=" .. tostring(record.actor
                        and SC.Commands.peek(record.actor).order)
            end
        end
        result("PASS", "maintenance_gravekeepers",
            #gravekeepers > 0 and table.concat(gravekeepers, "; ") or "none")
        local bodies, scanned = scanBodies(base, SC)
        H.maintenanceBodies = bodies
        result("PASS", "maintenance_body_scan",
            "bodies=" .. tostring(#bodies) .. " squares=" .. tostring(scanned))
        local deaths = SC.Community.export().deaths or {}
        local deathRows = {}
        for id, death in pairs(deaths) do
            deathRows[#deathRows + 1] = tostring(id) .. ":"
                .. tostring(death.subjectName)
        end
        table.sort(deathRows)
        result("PASS", "maintenance_known_deaths",
            #deathRows > 0 and table.concat(deathRows, "; ") or "none")
        for index, body in ipairs(bodies) do
            result("PASS", "maintenance_body_" .. tostring(index),
                body.name .. " @" .. tostring(body.x) .. "," .. tostring(body.y)
                    .. "," .. tostring(body.z) .. " zone=" .. body.zone
                    .. " deathId=" .. tostring(body.deathId)
                    .. " player=" .. tostring(body.playerBody)
                    .. " fake=" .. tostring(body.fake)
                    .. " animal=" .. tostring(body.animal)
                    .. " " .. body.contents)
        end
        result("PASS", "maintenance_orders_before", describeOrders(SC))
        local audited, auditReason = SC.BaseLife.auditRoleProduction()
        result((audited or auditReason == "production_order_active"
            or auditReason == "production_worker_busy") and "PASS" or "FAIL",
            "maintenance_role_audit",
            tostring(auditReason))
        result("PASS", "maintenance_orders_after", describeOrders(SC))
        if not prepareCleaning(H, SC, check, result) then
            setPhase("finish", current) return
        end
        setPhase("base_maintenance_clean", current)
        return
    end
    if H.phase == "base_maintenance_clean" then
        local fixture = H.maintenanceCleaner
        local actor = fixture.actor
        if current - H.phaseStartedAt > 100000 then
            local state = SC.Downtime.peek(actor)
            local lastFact = state and state.lastFact
            result("FAIL", "maintenance_cleaning_result",
                "timeout stain=" .. tostring(call(getCell():getGridSquare(
                    fixture.x, fixture.y, fixture.z), "haveStains"))
                    .. " activity=" .. tostring(state and state.active
                        and state.active.kind)
                    .. " lastFact=" .. tostring(lastFact and lastFact.activity)
                    .. " bleach=" .. tostring(call(call(fixture.bleach,
                        "getFluidContainer"), "getAmount")))
            setPhase("base_maintenance_grave_observe", current)
            return
        end
        if current - (fixture.nextUpdate or 0) < 250 then return end
        fixture.nextUpdate = current
        local handled, status = SC.Downtime.update(actor, H.player, {}, "clean_base")
        if not fixture.started and SC.Downtime.peek(actor)
            and SC.Downtime.peek(actor).active
            and SC.Downtime.peek(actor).active.kind == "clean_base" then
            fixture.started = true
            result("PASS", "maintenance_cleaning_started", tostring(status))
        end
        if SC.NativeActions.isWorkActive(actor) == true then
            fixture.native = true
            if not fixture.screenshot then
                fixture.screenshot = true
                pcall(function()
                    getCore():TakeFullScreenshot(tostring(H.config.run_id)
                        .. "-base-cleaning.png")
                end)
            end
        end
        local remaining = tonumber(call(call(fixture.bleach, "getFluidContainer"), "getAmount")) or 0
        local currentSquare = getCell():getGridSquare(fixture.x, fixture.y, fixture.z)
        local state = SC.Downtime.peek(actor)
        local lastFact = state and state.lastFact
        if fixture.stain and call(currentSquare, "haveStains") == false then
            check("maintenance_cleaning_result", remaining < fixture.before
                and lastFact and lastFact.activity == "clean_base",
                "native=" .. tostring(fixture.native)
                    .. " bleach=" .. tostring(fixture.before) .. "->" .. tostring(remaining)
                    .. " lastFact=" .. tostring(lastFact and lastFact.activity)
                    .. " status=" .. tostring(status) .. " handled=" .. tostring(handled))
            setPhase("base_maintenance_grave_observe", current)
        end
        return
    end
    if H.phase == "base_maintenance_grave_observe" then
        if not H.maintenanceGraveStart then
            H.maintenanceGraveStart = current
            result("PASS", "maintenance_grave_observe_start", describeOrders(SC))
        end
        if current - (H.maintenanceNextGraveCheck or 0) < 1000 then return end
        H.maintenanceNextGraveCheck = current
        if current - H.maintenanceGraveStart < 60000 then return end
        local base = SC.BaseLife.active()
        local bodies = base and scanBodies(base, SC) or {}
        local counts = SC.BaseLife.productionCounters()
        result("PASS", "maintenance_grave_observe_end",
            "bodies=" .. tostring(#bodies) .. " buried="
                .. tostring(counts.bodiesBuried) .. " orders=" .. describeOrders(SC))
        for index, body in ipairs(bodies) do
            result("PASS", "maintenance_remaining_body_" .. tostring(index),
                body.name .. " @" .. tostring(body.x) .. "," .. tostring(body.y)
                    .. " zone=" .. body.zone .. " deathId="
                    .. tostring(body.deathId) .. " " .. body.contents)
        end
        setPhase("finish", current)
    end
end

return Probe
