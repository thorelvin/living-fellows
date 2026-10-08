-- SPDX-License-Identifier: MIT
-- Exercise the vanilla right-click Medical Check callback on a native companion.
local Probe = {}

local function call(object, method, ...)
    if not object then return nil end
    local ok, value = pcall(function(...) return object[method](object, ...) end, ...)
    return ok and value or nil
end

local function spawnSafe(square, utility)
    if not square or not utility.isSquareFree(square) then return false end
    local free = call(square, "isFree", true)
    local safe = call(square, "isSafeToSpawn")
    return free ~= false and safe ~= false
end

local function nearbySquares(player, utility)
    local x, y, z = tonumber(call(player, "getX")), tonumber(call(player, "getY")),
        tonumber(call(player, "getZ"))
    if not x or not y or not z then return nil end
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local offsets = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
        { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
    for radius = 1, 8 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local square = utility.gridSquare(x + dx, y + dy, z)
                    if spawnSafe(square, utility) then
                        for _, offset in ipairs(offsets) do
                            local view = utility.gridSquare(x + dx + offset[1],
                                y + dy + offset[2], z)
                            if spawnSafe(view, utility) then return square, view end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function Probe.step(H, current, check, result, setPhase)
    local SC = SurvivorCompanion
    if H.phase == "medical_check_setup" then
        -- The harness closes entry modals for the first 20 seconds.
        if current - H.phaseStartedAt < 22000 then return end
        local square, view = nearbySquares(H.player, SC.GameplayUtil)
        if not check("medical_check_spawn_square", square ~= nil,
            "free tile beside the local player") then
            setPhase("finish", current) return
        end
        local ticket, reason = SC.Actor.beginSpawn(square, {
            recruited = true,
            identity = { forename = "Medical", surname = "Tester",
                gender = "woman", outfit = "Generic01" },
        })
        if not check("medical_check_spawn_requested", ticket ~= nil,
            tostring(reason)) then
            setPhase("finish", current) return
        end
        H.medicalCheckTicket = ticket
        H.medicalCheckView = view
        setPhase("medical_check_spawn", current)
        return
    end
    if H.phase == "medical_check_spawn" then
        local actor, reason = SC.Actor.pollSpawn(H.medicalCheckTicket)
        if not actor then
            if reason ~= "spawn_pending" or current - H.phaseStartedAt > 12000 then
                result("FAIL", "medical_check_spawn", tostring(reason))
                setPhase("finish", current)
            end
            return
        end
        H.medicalCheckActor = actor
        local view = H.medicalCheckView
        local positioned = pcall(function()
            H.player:teleportTo(view:getX() + 0.5, view:getY() + 0.5,
                view:getZ())
        end)
        if not check("medical_check_player_adjacent", positioned
            and (tonumber(call(H.player, "DistTo", actor)) or 99) <= 2.5,
            "player beside spawned companion") then
            setPhase("finish", current) return
        end
        if not check("medical_check_vanilla_hook",
            ISWorldObjectContextMenu.onMedicalCheck == SC.UIContext.onMedicalCheck,
            "right-click callback installed") then
            setPhase("finish", current) return
        end
        local ok, accepted, detail = pcall(ISWorldObjectContextMenu.onMedicalCheck,
            nil, H.player, actor)
        if not check("medical_check_opened", ok and accepted == true
            and detail == "health_opened",
            tostring(detail)) then
            setPhase("finish", current) return
        end
        setPhase("medical_check_capture", current)
        return
    end
    if H.phase == "medical_check_capture" then
        if current - H.phaseStartedAt < 750 then return end
        local root = SC.UI and SC.UI.instance
        local visible = call(root, "isVisible")
        check("medical_check_health_view_visible", root ~= nil
            and root.collapsed ~= true and visible == true
            and root.selectedTab == "loadout"
            and root.selectedRow and root.selectedRow.actor == H.medicalCheckActor
            and root.detail and root.detail.displayedCompanionId
                == SC.Registry.idOf(H.medicalCheckActor),
            "visible=" .. tostring(visible)
                .. " tab=" .. tostring(root and root.selectedTab)
                .. " selected=" .. tostring(root and root.selectedId))
        local name = tostring(H.config.run_id) .. "-medical-check"
        local captured, captureReason = pcall(function()
            getCore():TakeFullScreenshot(name)
        end)
        check("medical_check_screenshot", captured,
            name .. " " .. tostring(captureReason))
        setPhase("medical_check_finish", current)
        return
    end
    if H.phase == "medical_check_finish"
        and current - H.phaseStartedAt > 1200 then
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCMedicalCheckProbe = Probe
return Probe
