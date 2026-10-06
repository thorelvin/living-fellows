-- SPDX-License-Identifier: MIT
-- Disposable-save probe: a real thirsty companion uses a clean world water
-- source with the game's timed action. The seed save is never changed.

local Probe = {}

local function call(object, method, ...)
    local utility = SurvivorCompanion.GameplayUtil
    return select(1, utility.call(object, method, ...))
end

local function number(value)
    return value ~= nil and tonumber(tostring(value)) or nil
end

local function label(object)
    local utility = SurvivorCompanion.GameplayUtil
    local sprite = call(call(object, "getSprite"), "getName")
    local x, y, z = utility.position(object)
    return tostring(sprite or "water") .. "@" .. tostring(x) .. ","
        .. tostring(y) .. "," .. tostring(z)
end

local function fixtures(SC)
    local utility = SC.GameplayUtil
    local base = SC.BaseLife.active()
    local sources, seen = {}, {}
    for _, zone in ipairs(base and base.zones or {}) do
        if zone.kind == "area" then
            for y = zone.y1, zone.y2 do
                for x = zone.x1, zone.x2 do
                    local square = utility.gridSquare(x, y, zone.z)
                    utility.squareObjects(square, function(object)
                        if seen[object] then return true end
                        seen[object] = true
                        if not utility.hasMethod(object, "hasFluid")
                            or call(object, "hasFluid") ~= true then return true end
                        local amount = number(call(object, "getFluidAmount")) or 0
                        if amount <= 0.05
                            or call(object, "isTaintedWater") == true then return true end
                        sources[#sources + 1] = { object = object,
                            square = square, amount = amount,
                            label = label(object) }
                        return true
                    end, 48)
                end
            end
        end
    end
    return sources
end

local function setup(H, SC, check, result, setPhase, current)
    local utility = SC.GameplayUtil
    local base = SC.BaseLife.active()
    if not check("water_source_base", base ~= nil,
        base and base.name or "no active camp") then
        setPhase("finish", current) return
    end
    local sources = fixtures(SC)
    local labels = {}
    for _, source in ipairs(sources) do labels[#labels + 1] = source.label end
    result("PASS", "water_source_inventory",
        "count=" .. tostring(#sources) .. " " .. table.concat(labels, "; "))
    local best, bestDistance
    for _, record in ipairs(SC.Registry.snapshot() or {}) do
        local actor = record.actor
        if record.recruited == true and actor
            and call(actor, "isDead") ~= true
            and SC.BaseLife.isInside(actor) == true then
            for _, source in ipairs(sources) do
                if utility.sameFloor(actor, source.object) then
                    local atSource, targets = utility.directInteractionAccess(actor,
                        source.object)
                    local distance = utility.distance(actor, source.object)
                    if (atSource == true or #(targets or {}) > 0)
                        and distance <= 6
                        and (not best or distance < bestDistance) then
                        best = { actor = actor, source = source,
                            name = call(actor, "getFullName") or record.id }
                        bestDistance = distance
                    end
                end
            end
        end
    end
    if not best then
        result("SKIP", "water_source_live_drink",
            "no resident is within six tiles of a valid sink or well use side")
        setPhase("finish", current) return
    end
    local stats = call(best.actor, "getStats")
    local changed, valid = utility.call(stats, "set", CharacterStat.THIRST, 0.78)
    if not check("water_source_thirst_fixture", valid == true,
        best.name .. " " .. best.source.label) then
        setPhase("finish", current) return
    end
    SC.Needs.reset(best.actor)
    best.beforeThirst = utility.characterStatValue(best.actor, "THIRST", 0)
    best.beforeWater = number(call(best.source.object, "getFluidAmount")) or 0
    best.startedAt = current
    H.waterSource = best
    result("PASS", "water_source_actor",
        best.name .. " " .. best.source.label
            .. " distance=" .. tostring(bestDistance)
            .. " thirst=" .. tostring(best.beforeThirst))
    setPhase("water_source_drink", current)
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "water_source_setup" then
        if (not SC.BaseLife.active() or #(SC.Registry.snapshot() or {}) == 0)
            and current - H.phaseStartedAt < 12000 then return end
        setup(H, SC, check, result, setPhase, current)
        return
    end
    if H.phase ~= "water_source_drink" then return end
    local test = H.waterSource
    if current - (test.nextAt or 0) < 250 then return end
    test.nextAt = current
    local accepted, reason = SC.Needs.update(test.actor, H.player, {
        snapshot = { immediateCount = 0, pressure = 0 },
    })
    local chosen = SC.Needs.peek(test.actor)
    chosen = chosen and chosen.waterSource or nil
    if chosen and chosen ~= test.source.object then
        test.source = { object = chosen, label = label(chosen) }
        test.beforeWater = number(call(chosen, "getFluidAmount")) or 0
        result("PASS", "water_source_selected",
            test.name .. " " .. test.source.label)
    end
    local thirst = SC.GameplayUtil.characterStatValue(test.actor, "THIRST", 0)
    local amount = number(call(test.source.object, "getFluidAmount")) or 0
    if thirst <= test.beforeThirst - 0.05 then
        check("water_source_live_drink", accepted == true
                or reason == "needs_satisfied" or reason == "drinking",
            test.name .. " source=" .. test.source.label
                .. " thirst=" .. tostring(test.beforeThirst) .. "->"
                    .. tostring(thirst)
                .. " water=" .. tostring(test.beforeWater) .. "->"
                    .. tostring(amount) .. " update=" .. tostring(reason))
        setPhase("finish", current)
    elseif current - test.startedAt > 25000 then
        result("FAIL", "water_source_live_drink",
            test.name .. " source=" .. test.source.label
                .. " thirst=" .. tostring(test.beforeThirst) .. "->"
                    .. tostring(thirst)
                .. " water=" .. tostring(test.beforeWater) .. "->"
                    .. tostring(amount) .. " update=" .. tostring(accepted)
                    .. "/" .. tostring(reason))
        setPhase("finish", current)
    end
end

return Probe
