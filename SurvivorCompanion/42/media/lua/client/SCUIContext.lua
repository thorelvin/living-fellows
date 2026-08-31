-- SPDX-License-Identifier: MIT

require "ISUI/ISContextMenu"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UIContext = SC.UIContext or {}
local Context = SC.UIContext

Context._installed = Context._installed or false
Context.maximumShortcutDistance = 16

local function text(key, ...)
    if SC.UI and type(SC.UI.text) == "function" then
        return SC.UI.text(key, ...)
    end
    if getText then
        return getText(key, ...)
    end
    return key
end

local function safeMethod(object, methodName, ...)
    if not object then
        return nil
    end
    local method = object[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, object, ...)
    if ok then
        return value
    end
    return nil
end

local function hasMethod(object, methodName)
    if not object then return false end
    local ok, value = pcall(function() return object[methodName] end)
    return ok and type(value) == "function"
end

local function issueFromContext(target, companionId, command, payload, player)
    if SC.Commands and type(SC.Commands.issue) == "function" then
        local ok, first, second, third = pcall(SC.Commands.issue, companionId, command, payload, player)
        if command == "status" and ok and first ~= false and SC.UI then
            local description = nil
            if type(first) == "table" then description = first end
            if type(second) == "table" then description = second end
            if type(third) == "table" then description = third end
            if description and type(SC.UI.showStatus) == "function" then
                SC.UI.showStatus(description)
            elseif type(SC.UI.open) == "function" then
                SC.UI.open("overview", companionId)
            end
        elseif SC.UI and type(SC.UI.refresh) == "function" then
            SC.UI.refresh()
        end
    end
end

local function addCommand(menu, labelKey, id, command, payload, player)
    return menu:addOption(text(labelKey), nil, issueFromContext, id, command, payload, player)
end

local function addCategory(menu, labelKey)
    local option = menu:addOption(text(labelKey), nil, nil)
    local category = ISContextMenu:getNew(menu)
    menu:addSubMenu(option, category)
    return category
end

local function factionConversationAction(target, factionId, action, topic, player)
    if not SC.FactionContracts then return end
    local ok, accepted, detail
    if action == "open" then
        if SC.UI and type(SC.UI.open) == "function" then
            SC.UI.open("factions")
            ok, accepted, detail = true, true, "conversation_opened"
        end
    elseif action == "talk" then
        ok, accepted, detail = pcall(
            SC.FactionContracts.talk, factionId, player, topic, false)
    elseif action == "access" then
        ok, accepted, detail = pcall(
            SC.FactionContracts.requestAccess, factionId, player, false)
    elseif action == "recruitment_ask" then
        ok, accepted, detail = pcall(
            SC.FactionRecruitment.ask, factionId, player, false)
    elseif action == "recruitment_trial" then
        ok, accepted, detail = pcall(
            SC.FactionRecruitment.startTrial, factionId, player, false)
    elseif action == "recruitment_decide" then
        ok, accepted, detail = pcall(
            SC.FactionRecruitment.decide, factionId, player)
    elseif action == "recruitment_return" then
        ok, accepted, detail = pcall(
            SC.FactionRecruitment.returnNow, factionId, player, false)
    end
    if player then
        safeMethod(player, "setHaloNote", ok and accepted == true
            and text("UI_SC_CommandAcceptedResult", text("UI_SC_Context_Household"),
                tostring(detail or "Done"))
            or text("UI_SC_Base_ActionFailed", tostring(detail or accepted)))
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function talkableFactions(player)
    local result = {}
    if not SC.Factions or type(SC.Factions.list) ~= "function"
        or not SC.FactionContracts or type(SC.FactionContracts.canTalk) ~= "function" then
        return result
    end
    for _, group in ipairs(SC.Factions.list(true) or {}) do
        local ok, ready = pcall(SC.FactionContracts.canTalk, group, player)
        if ok and ready == true then result[#result + 1] = group end
    end
    return result
end

local function addFactionConversations(context, factions, player)
    for _, group in ipairs(factions or {}) do
        local option = context:addOption(text("UI_SC_Context_HouseholdNamed", group.name), nil, nil)
        local menu = ISContextMenu:getNew(context)
        context:addSubMenu(option, menu)
        menu:addOption(text("UI_SC_Context_OpenFactionPanel"), nil,
            factionConversationAction, group.id, "open", nil, player)
        for _, row in ipairs({
            { key = "UI_SC_Faction_AskStatus", topic = "status" },
            { key = "UI_SC_Faction_AskNeeds", topic = "needs" },
            { key = "UI_SC_Faction_AskMembers", topic = "members" },
            { key = "UI_SC_Faction_AskTrade", topic = "trade" },
            { key = "UI_SC_Faction_AskDanger", topic = "danger" },
            { key = "UI_SC_Faction_AskRumours", topic = "rumours" },
        }) do
            menu:addOption(text(row.key), nil, factionConversationAction,
                group.id, "talk", row.topic, player)
        end
        menu:addOption(text("UI_SC_Faction_RequestAccess"), nil,
            factionConversationAction, group.id, "access", nil, player)
        local summary = SC.Factions.summary(group.id)
        local recruitment = summary and summary.recruitment or nil
        if recruitment and recruitment.canAsk then
            menu:addOption(text("UI_SC_Faction_RecruitmentAsk"), nil,
                factionConversationAction, group.id, "recruitment_ask", nil, player)
        elseif recruitment and recruitment.canStartTrial then
            menu:addOption(text("UI_SC_Faction_RecruitmentStartTrial"), nil,
                factionConversationAction, group.id, "recruitment_trial", nil, player)
        elseif recruitment and recruitment.status == "trial" then
            if recruitment.canDecide then
                menu:addOption(text("UI_SC_Faction_RecruitmentAskDecision"), nil,
                    factionConversationAction, group.id, "recruitment_decide", nil, player)
            end
            menu:addOption(text("UI_SC_Faction_RecruitmentEndTrial"), nil,
                factionConversationAction, group.id, "recruitment_return", nil, player)
        end
    end
end

local function squarePayload(square)
    if not square then
        return nil
    end
    local x = safeMethod(square, "getX")
    local y = safeMethod(square, "getY")
    local z = safeMethod(square, "getZ")
    if x == nil or y == nil or z == nil then
        return nil
    end
    return { x = x, y = y, z = z }
end

local function findTarget(worldObjects, player)
    local targetSquare = nil
    local door = nil
    local barricadeTarget = nil
    local removeBarricadeTarget = nil
    local dismantleTarget = nil
    local containerTarget = nil
    for _, object in ipairs(worldObjects or {}) do
        if not targetSquare then
            targetSquare = safeMethod(object, "getSquare")
        end
        if not door and instanceof then
            if instanceof(object, "IsoDoor") then
                door = object
            elseif instanceof(object, "IsoThumpable") and safeMethod(object, "isDoor") then
                door = object
            end
        end
        if not barricadeTarget and safeMethod(object, "getObjectIndex") ~= nil
            and hasMethod(object, "getBarricadeForCharacter") then
            local allowed = safeMethod(object, "isBarricadeAllowed")
            local canBarricade = safeMethod(object, "getCanBarricade")
            if allowed == true or canBarricade == true then barricadeTarget = object end
        end
        if not removeBarricadeTarget and player
            and safeMethod(object, "getObjectIndex") ~= nil
            and hasMethod(object, "getBarricadeForCharacter")
            and safeMethod(object, "getBarricadeForCharacter", player) ~= nil then
            removeBarricadeTarget = object
        end
        if not dismantleTarget and safeMethod(object, "getObjectIndex") ~= nil
            and instanceof and instanceof(object, "IsoThumpable")
            and safeMethod(object, "isDismantable") == true then
            dismantleTarget = object
        end
        if not containerTarget and safeMethod(object, "getContainer") ~= nil
            and safeMethod(object, "getObjectIndex") ~= nil then
            containerTarget = object
        end
    end
    local targetPayload = squarePayload(targetSquare)
    local doorPayload = nil
    if door then
        doorPayload = squarePayload(safeMethod(door, "getSquare"))
    end
    if door and doorPayload then
        doorPayload.object = door
        doorPayload.objectIndex = safeMethod(door, "getObjectIndex")
    end
    local barricadePayload
    if barricadeTarget then
        barricadePayload = squarePayload(safeMethod(barricadeTarget, "getSquare"))
        if barricadePayload then
            barricadePayload.object = barricadeTarget
            barricadePayload.objectIndex = safeMethod(barricadeTarget, "getObjectIndex")
        end
    end
    local removeBarricadePayload
    if removeBarricadeTarget then
        removeBarricadePayload = squarePayload(safeMethod(removeBarricadeTarget, "getSquare"))
        if removeBarricadePayload then
            removeBarricadePayload.object = removeBarricadeTarget
            removeBarricadePayload.objectIndex = safeMethod(removeBarricadeTarget, "getObjectIndex")
            local selected = safeMethod(removeBarricadeTarget, "getBarricadeForCharacter", player)
            local same = safeMethod(removeBarricadeTarget, "getBarricadeOnSameSquare")
            removeBarricadePayload.barricadeSide = selected ~= nil and selected == same
                and "same" or "opposite"
        end
    end
    local dismantlePayload
    if dismantleTarget then
        dismantlePayload = squarePayload(safeMethod(dismantleTarget, "getSquare"))
        if dismantlePayload then
            dismantlePayload.object = dismantleTarget
            dismantlePayload.objectIndex = safeMethod(dismantleTarget, "getObjectIndex")
        end
    end
    return targetSquare, door, targetPayload, doorPayload, barricadeTarget,
        barricadePayload, containerTarget, removeBarricadeTarget,
        removeBarricadePayload, dismantleTarget, dismantlePayload
end

local function baseAction(target, action, payload, player)
    if not SC.BaseLife then return end
    local ok, result
    if action == "create" then ok, result = SC.BaseLife.create(payload.square, "Main Camp")
    elseif action == "zone_begin" then ok, result = SC.BaseLife.beginZone(payload.kind, payload.square)
    elseif action == "zone_finish" then ok, result = SC.BaseLife.finishZone(payload.square, payload.name)
    elseif action == "zone_cancel" then ok, result = SC.BaseLife.cancelZone()
    elseif action == "storage" then
        ok, result = SC.BaseLife.registerStorage(payload.object, payload.category)
    elseif action == "maintenance" then
        ok, result = SC.BaseLife.registerMaintenanceTarget(payload.object, payload.kind)
    elseif action == "build" then
        local recipeId = SC.BaseWork and SC.BaseWork.recipeForKind(payload.kind) or nil
        if recipeId then
            ok, result = SC.BaseLife.enqueueJob({
                type = "build", priority = 3, recipeId = recipeId, face = payload.face or 1,
                target = payload.square,
            })
        else
            ok, result = false, "build_recipe_missing"
        end
    end
    if player then
        safeMethod(player, "setHaloNote", ok and text("UI_SC_Base_ActionAccepted")
            or text("UI_SC_Base_ActionFailed", tostring(result)))
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function addBaseMenu(context, square, containerTarget, barricadeTarget, player)
    if not square or not SC.BaseLife then return false end
    local rootOption = context:addOption(text("UI_SC_Context_BaseLife"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)
    if not SC.BaseLife.active() then
        menu:addOption(text("UI_SC_Base_SetCamp"), nil, baseAction, "create",
            { square = square }, player)
        return true
    end
    local draft = SC.BaseLife.zoneDraft()
    if draft then
        menu:addOption(text("UI_SC_Base_FinishZone"), nil, baseAction, "zone_finish",
            { square = square, name = draft.kind }, player)
        menu:addOption(text("UI_SC_Base_CancelZone"), nil, baseAction, "zone_cancel", {}, player)
    else
        local zoneOption = menu:addOption(text("UI_SC_Base_StartZone"), nil, nil)
        local zoneMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(zoneOption, zoneMenu)
        for _, kind in ipairs({ "area", "work", "rest", "social", "guard", "rally", "quarantine" }) do
            zoneMenu:addOption(text("UI_SC_Base_Zone_" .. kind), nil, baseAction, "zone_begin",
                { square = square, kind = kind }, player)
        end
    end
    if containerTarget then
        local storageOption = menu:addOption(text("UI_SC_Base_MarkStorage"), nil, nil)
        local storageMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(storageOption, storageMenu)
        for _, category in ipairs({ "food", "water", "medical", "tools", "construction",
            "crafting", "weapons", "ammunition", "general", "output", "memorial" }) do
            storageMenu:addOption(text("UI_SC_Base_Storage_" .. category), nil, baseAction,
                "storage", { object = containerTarget, category = category }, player)
        end
    end
    if barricadeTarget then
        menu:addOption(text("UI_SC_Base_MaintainBarricade"), nil, baseAction, "maintenance",
            { object = barricadeTarget, kind = "barricade" }, player)
    end
    local buildOption = menu:addOption(text("UI_SC_Base_QueueBuild"), nil, nil)
    local buildMenu = ISContextMenu:getNew(menu)
    menu:addSubMenu(buildOption, buildMenu)
    for _, kind in ipairs({ "wall_frame", "wall", "floor", "door_frame", "door" }) do
        local kindOption = buildMenu:addOption(text("UI_SC_Base_Build_" .. kind), nil, nil)
        local faceMenu = ISContextMenu:getNew(buildMenu)
        buildMenu:addSubMenu(kindOption, faceMenu)
        for face = 1, 4 do
            faceMenu:addOption(text("UI_SC_Base_Face_" .. tostring(face)), nil, baseAction,
                "build", { square = squarePayload(square), kind = kind, face = face }, player)
        end
    end
    return true
end

local function nearbyRows(player)
    local rows = {}
    if not SC.Registry or type(SC.Registry.living) ~= "function" then
        return rows
    end
    local ok, living = pcall(SC.Registry.living)
    if not ok or type(living) ~= "table" then
        return rows
    end
    for _, entry in pairs(living) do
        local row = SC.UI and SC.UI.describeEntry and SC.UI.describeEntry(entry, player) or nil
        local recruited = row and row.recruited == true
        if row and row.id and row.id ~= "" and SC.Registry
            and type(SC.Registry.byId) == "function" then
            local recordOk, record = pcall(SC.Registry.byId, row.id)
            recruited = recordOk and type(record) == "table"
                and record.actor == entry and record.recruited == true
        end
        if recruited and row and row.id and row.id ~= "" then
            local distance = tonumber(row.distance)
            if not distance or distance <= Context.maximumShortcutDistance then
                rows[#rows + 1] = row
            end
        end
    end
    table.sort(rows, function(left, right)
        return string.lower(tostring(left.name)) < string.lower(tostring(right.name))
    end)
    return rows
end

local function addConversation(menu, row, player)
    if row.recruited ~= true then return end
    addCommand(menu, "UI_SC_Action_Doing", row.id, "doing", nil, player)
    addCommand(menu, "UI_SC_Action_Status", row.id, "status", nil, player)
    addCommand(menu, "UI_SC_Action_Needs", row.id, "needs", nil, player)
    addCommand(menu, "UI_SC_Action_Memory", row.id, "memory", nil, player)
    addCommand(menu, "UI_SC_Action_Background", row.id, "background", nil, player)
    addCommand(menu, "UI_SC_Action_Opinion", row.id, "opinion", nil, player)
    addCommand(menu, "UI_SC_Action_Plans", row.id, "plans", nil, player)
    addCommand(menu, "UI_SC_Action_Relationship", row.id, "relationship", nil, player)
    addCommand(menu, "UI_SC_Action_Encourage", row.id, "encourage", nil, player)
    addCommand(menu, "UI_SC_Action_Praise", row.id, "praise", nil, player)
    addCommand(menu, "UI_SC_Action_EmoteGreet", row.id, "emote", { emote = "wavehi" }, player)
    addCommand(menu, "UI_SC_Action_EmoteThank", row.id, "emote", { emote = "thankyou" }, player)
    addCommand(menu, "UI_SC_Action_EmoteCelebrate", row.id, "emote", { emote = "clap" }, player)
end

local function addDirectOrders(menu, row, player)
    addCommand(menu, "UI_SC_Action_Follow", row.id, "follow", nil, player)
    addCommand(menu, "UI_SC_Action_Stay", row.id, "stay", nil, player)
    addCommand(menu, "UI_SC_Action_Guard", row.id, "guard", nil, player)
    addCommand(menu, "UI_SC_Action_Regroup", row.id, "regroup", nil, player)
    addCommand(menu, "UI_SC_Action_Retreat", row.id, "retreat", nil, player)
    addCommand(menu, "UI_SC_Action_WorkAuto", row.id, "set_work_mode", { mode = "auto" }, player)
    addCommand(menu, "UI_SC_Action_WorkIdle", row.id, "set_work_mode", { mode = "idle" }, player)
    addCommand(menu, "UI_SC_Action_WorkCraft", row.id, "set_work_mode", { mode = "craft" }, player)
    if type(row.vehicleStatus) == "table"
        and row.vehicleStatus.status == "in_vehicle"
        and row.vehicleStatus.canExitNow == true then
        addCommand(menu, "UI_SC_Action_ExitVehicleNow", row.id,
            "exit_vehicle", nil, player)
    end
end

local function addWorldOrders(menu, row, targetPayload, door, doorPayload,
        barricadeTarget, barricadePayload, removeBarricadeTarget,
        removeBarricadePayload, dismantleTarget, dismantlePayload, player)
    if targetPayload then
        addCommand(menu, "UI_SC_Action_MoveHere", row.id, "move_to", targetPayload, player)
        addCommand(menu, "UI_SC_Action_CheckRoom", row.id, "check_room", targetPayload, player)
    end
    if door and doorPayload then
        local isOpen = safeMethod(door, "IsOpen")
        if isOpen then
            addCommand(menu, "UI_SC_Action_CloseDoor", row.id, "close_door", doorPayload, player)
        else
            addCommand(menu, "UI_SC_Action_OpenDoor", row.id, "open_door", doorPayload, player)
        end
    end
    if barricadeTarget and barricadePayload then
        addCommand(menu, "UI_SC_Action_Barricade", row.id, "barricade", barricadePayload, player)
    end
    if removeBarricadeTarget and removeBarricadePayload then
        addCommand(menu, "UI_SC_Action_RemoveBarricade", row.id, "remove_barricade", removeBarricadePayload, player)
    elseif dismantleTarget and dismantlePayload then
        addCommand(menu, "UI_SC_Action_Dismantle", row.id, "dismantle", dismantlePayload, player)
    end
end

local function addViews(menu, row, player)
    addCommand(menu, "UI_SC_Action_OpenInventory", row.id, "open_inventory", nil, player)
    addCommand(menu, "UI_SC_Action_OpenHealth", row.id, "open_health", nil, player)
    addCommand(menu, "UI_SC_Action_Dismiss", row.id, "dismiss", nil, player)
end

function Context.fillWorldObjectContextMenu(playerIndex, context, worldObjects, test)
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.Test then
        return true
    end
    if not context then
        return
    end
    local player = getSpecificPlayer and getSpecificPlayer(playerIndex) or (getPlayer and getPlayer() or nil)
    if not player then
        return
    end
    local square, door, targetPayload, doorPayload, barricadeTarget, barricadePayload,
        containerTarget, removeBarricadeTarget, removeBarricadePayload,
        dismantleTarget, dismantlePayload = findTarget(worldObjects, player)
    local rows = nearbyRows(player)
    local factions = talkableFactions(player)
    if #rows == 0 and #factions == 0 and not square then return end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
    end
    addBaseMenu(context, square, containerTarget, barricadeTarget, player)
    addFactionConversations(context, factions, player)
    if #rows == 0 then return end
    local rootOption = context:addOption(text("UI_SC_Context_Companions"), nil, nil)
    local rootMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, rootMenu)
    for _, row in ipairs(rows) do
        -- Re-check immediately before building the submenu so a survivor who
        -- was dismissed during this UI frame cannot retain team commands.
        if row.recruited == true then
            local companionOption = rootMenu:addOption(row.name, nil, nil)
            local companionMenu = ISContextMenu:getNew(rootMenu)
            rootMenu:addSubMenu(companionOption, companionMenu)
            addConversation(addCategory(companionMenu, "UI_SC_Context_Talk"), row, player)
            addDirectOrders(addCategory(companionMenu, "UI_SC_Context_Orders"), row, player)
            local targetMenu = addCategory(companionMenu, "UI_SC_Context_TargetActions")
            addWorldOrders(targetMenu, row, targetPayload, door, doorPayload,
                barricadeTarget, barricadePayload, removeBarricadeTarget,
                removeBarricadePayload, dismantleTarget, dismantlePayload, player)
            addViews(addCategory(companionMenu, "UI_SC_Context_Companion"), row, player)
        end
    end
end

function Context.install()
    if Context._installed then
        return
    end
    if Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldObjectContextMenu)
        Context._installed = true
    end
end

function Context.remove()
    if not Context._installed then
        return
    end
    if Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldObjectContextMenu)
    end
    Context._installed = false
end

Context.install()

return Context
