-- SPDX-License-Identifier: MIT
-- Exercise the actual body right-click Medical Check and native treatment panel.
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

local function menuOption(menu, name)
    if not menu then return nil end
    local option = call(menu, "getOptionFromName", name)
    if option then return option end
    for _, entry in ipairs(menu.options or {}) do
        if entry.name == name then return entry end
    end
    return nil
end

local function selectOption(option)
    if not option or type(option.onSelect) ~= "function" then
        return false, "missing menu callback"
    end
    local ok, value = pcall(option.onSelect, option.target,
        option.param1, option.param2, option.param3, option.param4)
    return ok, value
end

local function position(actor)
    return tostring(call(actor, "getX")) .. ","
        .. tostring(call(actor, "getY")) .. ","
        .. tostring(call(actor, "getZ"))
end

local function queueState(player)
    local queue = ISTimedActionQueue and ISTimedActionQueue.queues
        and ISTimedActionQueue.queues[player]
    local types = {}
    for _, action in ipairs(queue and queue.queue or {}) do
        types[#types + 1] = tostring(action.Type)
    end
    return #types > 0 and table.concat(types, ",") or "empty", queue
end

local function splintState(H)
    local SC = SurvivorCompanion
    local actor, doctor = H.medicalCheckActor, H.player
    local window = ISMedicalCheckAction
        and ISMedicalCheckAction.getHealthWindowForPlayer(actor)
    local session = SC.MedicalUI and SC.MedicalUI.current()
    local supply = H.medicalChosenSplint
    local container = call(supply, "getContainer")
    local queueTypes = queueState(doctor)
    return "patient=" .. position(actor)
        .. " doctor=" .. position(doctor)
        .. " distance=" .. tostring(call(doctor, "DistTo", actor))
        .. " windowVisible=" .. tostring(call(window, "getIsVisible"))
        .. " session=" .. tostring(session and session.phase or nil)
        .. " sessionPatient=" .. tostring(session and session.actor == actor)
        .. " held=" .. tostring(SC.Commands.isTemporaryStay(actor))
        .. " fracture=" .. tostring(call(H.medicalFracture, "getFractureTime"))
        .. " splintFactor=" .. tostring(call(H.medicalFracture, "getSplintFactor"))
        .. " supplyType=" .. tostring(call(supply, "getFullType"))
        .. " supplyId=" .. tostring(call(supply, "getID"))
        .. " supplyContainer=" .. tostring(container)
        .. " supplyDirect=" .. tostring(container == call(doctor, "getInventory"))
        .. " queue=" .. queueTypes
end

local function observeSplintAction(H)
    local _, queue = queueState(H.player)
    for _, action in ipairs(queue and queue.queue or {}) do
        if action.Type == "HealthPanelAction" then
            H.medicalSplintSawMenuAction = true
        elseif action.Type == "ISSplint" then
            H.medicalSplintSawNativeAction = true
            H.medicalSplintActionPatientAtStart = tostring(action.bandagedPlayerX)
                .. "," .. tostring(action.bandagedPlayerY)
            local delta = tonumber(call(action, "getJobDelta")) or 0
            H.medicalSplintMaxDelta = math.max(H.medicalSplintMaxDelta or 0, delta)
        end
    end
end

local function playerOwnsSupply(player, item)
    local root = call(player, "getInventory")
    local container = call(item, "getContainer")
    for _ = 1, 8 do
        if container == root then return true end
        local parent = call(container, "getContainingItem")
        container = parent and call(parent, "getContainer") or nil
        if not container then return false end
    end
    return false
end

local function countPlayerSupplyType(player, fullType)
    if not fullType then return 0 end
    local utility = SurvivorCompanion.GameplayUtil
    local count = 0
    for _, item in ipairs(utility.inventoryItemsDeep(player:getInventory(), 1000)) do
        if call(item, "getFullType") == fullType then count = count + 1 end
    end
    return count
end

local function selectTreatment(panel, part, label, playerNum, doctor, desiredType)
    local ok, menuError = pcall(panel.doBodyPartContextMenu, panel, part, 32, 32)
    if not ok then return false, "body part context failed: " .. tostring(menuError) end
    -- doBodyPartContextMenu already populated the player's root menu.
    -- ISContextMenu.get() clears that menu, so inspect the existing one.
    local menu = getPlayerContextMenu(playerNum)
    local option = menuOption(menu, label)
    if not option then return false, "missing option " .. tostring(label) end
    local sub = option.subOption and call(menu, "getSubMenu", option.subOption)
    if not sub then return false, "missing treatment item submenu" end
    local root = doctor:getInventory()
    local callbackError
    for pass = 1, 2 do
        for _, itemOption in ipairs(sub.options or {}) do
            local supply = itemOption.itemForTexture
            local fullType = call(supply, "getFullType")
            local direct = call(supply, "getContainer") == root
            if supply and playerOwnsSupply(doctor, supply)
                and (not desiredType or fullType == desiredType)
                and ((pass == 1 and direct) or (pass == 2 and not direct)) then
                local selected, callbackResult = selectOption(itemOption)
                if selected then
                    return true, tostring(itemOption.name or "") .. " type="
                        .. tostring(fullType) .. " direct=" .. tostring(direct), supply
                end
                callbackError = tostring(callbackResult)
            end
        end
    end
    return false, "no player-owned treatment item " .. tostring(desiredType)
        .. " callbackError=" .. tostring(callbackError)
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
            and (tonumber(call(H.player, "DistTo", actor)) or 99) <= 1.9,
            "player beside spawned companion") then
            setPhase("finish", current) return
        end
        if not check("medical_check_vanilla_hook",
            ISWorldObjectContextMenu.onMedicalCheck == SC.UIContext.onMedicalCheck,
            "right-click callback installed") then
            setPhase("finish", current) return
        end
        local body = call(actor, "getBodyDamage")
        H.medicalScratch = body and call(body, "getBodyPart", BodyPartType.ForeArm_L)
        H.medicalFracture = body and call(body, "getBodyPart", BodyPartType.LowerLeg_R)
        local scratched = H.medicalScratch and pcall(H.medicalScratch.setScratched,
            H.medicalScratch, true, true)
        local fractured = H.medicalFracture and pcall(H.medicalFracture.setFractureTime,
            H.medicalFracture, 30)
        local inventory = call(H.player, "getInventory")
        H.medicalBandage = inventory and call(inventory, "AddItem", "Base.Bandage")
        H.medicalSplint = inventory and call(inventory, "AddItem", "Base.Splint")
        -- The source save may already have splints in several bags. The
        -- native menu groups identical types under one representative item;
        -- keep the newly added root splint as its deterministic test supply.
        for _, item in ipairs(SC.GameplayUtil.inventoryItemsDeep(inventory, 1000)) do
            if item ~= H.medicalSplint
                and call(item, "getFullType") == "Base.Splint" then
                local owner = call(item, "getContainer")
                if owner then call(owner, "Remove", item) end
            end
        end
        if not check("medical_check_wounds_and_supplies",
            scratched and fractured and H.medicalBandage ~= nil
                and H.medicalSplint ~= nil,
            "scratch, fracture, bandage, splint") then
            setPhase("finish", current) return
        end
        local px = getPlayerScreenLeft(0) + 250
        local py = getPlayerScreenTop(0) + 200
        local okMenu, menu = pcall(ISWorldObjectContextMenu.createMenu,
            0, { actor }, px, py, false)
        local option = okMenu and menuOption(menu,
            getText("ContextMenu_Medical_Check")) or nil
        if not check("medical_check_actual_right_click_option",
            option ~= nil and option.onSelect == SC.UIContext.onMedicalCheck
                and option.param2 == actor,
            "actual world menu callback and patient") then
            setPhase("finish", current) return
        end
        -- Match a real click: the world menu closes before the timed action
        -- opens the health panel and its own body-part menu.
        if menu and type(menu.closeAll) == "function" then menu:closeAll() end
        if not check("medical_check_queued", selectOption(option)
            and SC.MedicalUI.current() ~= nil,
            "player-doctor medical action queued") then
            setPhase("finish", current) return
        end
        setPhase("medical_check_capture", current)
        return
    end
    if H.phase == "medical_check_capture" then
        local window = ISMedicalCheckAction.getHealthWindowForPlayer(H.medicalCheckActor)
        local panel = window and window.nested
        local visible = call(window, "getIsVisible")
        if panel == nil or visible ~= true then
            if current - H.phaseStartedAt > 16000 then
                result("FAIL", "medical_check_treatment_panel", "timed action did not open")
                setPhase("finish", current)
            end
            return
        end
        if not H.medicalPanelReadyAt then
            H.medicalPanelReadyAt = current
            return
        end
        -- Full screenshots capture the last rendered frame. Allow the newly
        -- opened native window to draw before documenting its appearance.
        if current - H.medicalPanelReadyAt < 700 then return end
        if not check("medical_check_treatment_panel",
            panel.character == H.medicalCheckActor
                and panel.otherPlayer == H.player
                and type(panel.doBodyPartContextMenu) == "function",
            "patient is companion; doctor is player") then
            setPhase("finish", current) return
        end
        local parts = panel:getDamagedParts()
        local hasScratch, hasFracture = false, false
        for _, part in ipairs(parts) do
            if part == H.medicalScratch then hasScratch = true end
            if part == H.medicalFracture then hasFracture = true end
        end
        check("medical_check_body_parts", hasScratch and hasFracture,
            "both injured body parts are shown")
        local name = tostring(H.config.run_id) .. "-medical-check"
        local captured, captureReason = pcall(function()
            getCore():TakeFullScreenshot(name)
        end)
        check("medical_check_screenshot", captured,
            name .. " " .. tostring(captureReason))
        local chosen, detail, supply = selectTreatment(panel, H.medicalScratch,
            getText("ContextMenu_Bandage"), H.player:getPlayerNum(), H.player)
        H.medicalChosenBandage = supply
        if not check("medical_check_bandage_from_panel", chosen, detail) then
            setPhase("finish", current) return
        end
        setPhase("medical_check_bandage", current)
        return
    end
    if H.phase == "medical_check_bandage" then
        if not call(H.medicalScratch, "bandaged") then
            if current - H.phaseStartedAt > 14000 then
                result("FAIL", "medical_check_bandage_applied", "timed treatment stalled")
                setPhase("finish", current)
            end
            return
        end
        check("medical_check_bandage_applied",
            H.medicalChosenBandage ~= nil
                and call(H.medicalChosenBandage, "getContainer") == nil,
            "selected player-owned bandage consumed on companion wound")
        local window = ISMedicalCheckAction.getHealthWindowForPlayer(H.medicalCheckActor)
        local panel = window and window.nested
        H.medicalSplintClickPatient = position(H.medicalCheckActor)
        H.medicalSplintClickDoctor = position(H.player)
        H.medicalSplintWindowVisibleAtClick = call(window, "getIsVisible")
        H.medicalSplintHeldAtClick = SC.Commands.isTemporaryStay(H.medicalCheckActor)
        local chosen, detail, supply
        if panel then
            chosen, detail, supply = selectTreatment(panel,
                H.medicalFracture, getText("ContextMenu_Splint"),
                H.player:getPlayerNum(), H.player, "Base.Splint")
        end
        H.medicalChosenSplint = supply
        H.medicalChosenSplintType = call(supply, "getFullType")
        H.medicalSplintCountBefore = countPlayerSupplyType(H.player,
            H.medicalChosenSplintType)
        observeSplintAction(H)
        if not check("medical_check_splint_from_panel", chosen,
            tostring(detail) .. " " .. splintState(H)) then
            setPhase("finish", current) return
        end
        setPhase("medical_check_splint", current)
        return
    end
    if H.phase == "medical_check_splint" then
        observeSplintAction(H)
        if (tonumber(call(H.medicalFracture, "getSplintFactor")) or 0) <= 0 then
            if current - H.phaseStartedAt > 14000 then
                result("FAIL", "medical_check_splint_applied",
                    "timed treatment stalled clickPatient="
                        .. tostring(H.medicalSplintClickPatient)
                        .. " clickDoctor=" .. tostring(H.medicalSplintClickDoctor)
                        .. " clickWindowVisible=" .. tostring(H.medicalSplintWindowVisibleAtClick)
                        .. " clickHeld=" .. tostring(H.medicalSplintHeldAtClick)
                        .. " sawMenuAction=" .. tostring(H.medicalSplintSawMenuAction)
                        .. " sawISSplint=" .. tostring(H.medicalSplintSawNativeAction)
                        .. " actionPatientStart=" .. tostring(H.medicalSplintActionPatientAtStart)
                        .. " maxDelta=" .. tostring(H.medicalSplintMaxDelta)
                        .. " " .. splintState(H))
                setPhase("finish", current)
            end
            return
        end
        local after = countPlayerSupplyType(H.player,
            H.medicalChosenSplintType)
        check("medical_check_splint_applied",
            H.medicalChosenSplint ~= nil
                and (call(H.medicalChosenSplint, "getContainer") == nil
                    or after < (H.medicalSplintCountBefore or 0)),
            "player splint count " .. tostring(H.medicalSplintCountBefore)
                .. " -> " .. tostring(after) .. " on companion fracture")
        local window = ISMedicalCheckAction.getHealthWindowForPlayer(H.medicalCheckActor)
        call(window, "setVisible", false)
        setPhase("medical_check_finish", current)
        return
    end
    if H.phase == "medical_check_finish" then
        local state = SC.MedicalUI.current()
        if state and current - H.phaseStartedAt < 3500 then return end
        check("medical_check_stay_released", state == nil,
            "companion movement hold ended on panel close")
        setPhase("finish", current)
    end
end

SCRealSandboxHarnessProbes = SCRealSandboxHarnessProbes or {}
SCRealSandboxHarnessProbes.SCMedicalCheckProbe = Probe
return Probe
