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

local function executeFromContext(companionId, command, payload, player)
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
                SC.UI.open("status", companionId)
            end
        elseif SC.UI and type(SC.UI.refresh) == "function" then
            SC.UI.refresh()
        end
    end
end

local function companionName(companionId)
    if SC.UI and SC.UI.instance and SC.UI.instance.selectedRow
        and SC.UI.instance.selectedRow.id == companionId then
        return SC.UI.instance.selectedRow.name
    end
    if SC.Registry and type(SC.Registry.byId) == "function" then
        local ok, record = pcall(SC.Registry.byId, companionId)
        if ok and type(record) == "table" and record.actor then
            local name = safeMethod(record.actor, "getFullName")
                or safeMethod(record.actor, "getDisplayName")
            if name and name ~= "" then return name end
        end
    end
    return companionId
end

local function issueFromContext(target, companionId, command, payload, player)
    if command == "dismiss" and SC.UI and type(SC.UI.confirmDismiss) == "function" then
        SC.UI.confirmDismiss(companionName(companionId), function()
            executeFromContext(companionId, command, payload, player)
        end)
        return
    end
    executeFromContext(companionId, command, payload, player)
end

local function issueSignalFromContext(target, signal, player)
    if not SC.Commands then return end
    local ok, accepted, reason
    if signal == "whistle" and type(SC.Commands.whistle) == "function" then
        ok, accepted, reason = pcall(SC.Commands.whistle, player)
    elseif type(SC.Commands.handSign) == "function" then
        ok, accepted, reason = pcall(SC.Commands.handSign, player, signal)
    end
    if player then
        safeMethod(player, "setHaloNote", ok and accepted ~= false
            and text("UI_SC_CommandAccepted")
            or text("UI_SC_CommandRejectedDetail", tostring(reason or signal)))
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
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

local function addNamedCategory(menu, labelKey, value)
    local option = menu:addOption(text(labelKey, value), nil, nil)
    local category = ISContextMenu:getNew(menu)
    menu:addSubMenu(option, category)
    return category
end

local pendingContractWithdrawals = {}

local function contextNowMs()
    if SC.GameplayUtil and type(SC.GameplayUtil.nowMs) == "function" then
        return SC.GameplayUtil.nowMs()
    end
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        if ok and tonumber(value) then return tonumber(value) end
    end
    return 0
end

local function pendingContractWithdrawal(factionId, contractId)
    local pending = pendingContractWithdrawals[factionId]
    if not pending or pending.contractId ~= contractId
        or contextNowMs() > (tonumber(pending.untilMs) or 0) then
        pendingContractWithdrawals[factionId] = nil
        return false
    end
    return true
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
    elseif action == "accept_contract" then
        pendingContractWithdrawals[factionId] = nil
        local contractSummary = SC.FactionContracts.summary(factionId)
        local offer = contractSummary and contractSummary.offer or nil
        if offer and (offer.kind == "retrieve_item" or offer.kind == "clear_horde")
            and SC.UI and type(SC.UI.openQuestOffer) == "function" then
            SC.UI.openQuestOffer(factionId)
            return
        end
        ok, accepted, detail = pcall(
            SC.FactionContracts.accept, factionId, player, false)
    elseif action == "fulfill_contract" then
        local contractSummary = SC.FactionContracts.summary(factionId)
        local active = contractSummary and contractSummary.active or nil
        if active and (active.kind == "retrieve_item" or active.kind == "clear_horde")
            and contractSummary.progress and contractSummary.progress.ready == true
            and SC.UI and type(SC.UI.openQuestTurnIn) == "function" then
            SC.UI.openQuestTurnIn(factionId)
            return
        end
        ok, accepted, detail = pcall(
            SC.FactionContracts.fulfill, factionId, player, false)
        if ok and accepted == true then pendingContractWithdrawals[factionId] = nil end
    elseif action == "withdraw_contract" then
        local summary = SC.Factions and SC.Factions.summary(factionId) or nil
        local contract = summary and summary.social and summary.social.active or nil
        local contractId = contract and contract.id or nil
        if contractId and pendingContractWithdrawal(factionId, contractId) then
            pendingContractWithdrawals[factionId] = nil
            ok, accepted, detail = pcall(
                SC.FactionContracts.withdraw, factionId, player, false)
        else
            if contractId then
                pendingContractWithdrawals[factionId] = {
                    contractId = contractId, untilMs = contextNowMs() + 8000,
                }
                if player then
                    safeMethod(player, "setHaloNote", text("UI_SC_Faction_WithdrawConfirm"))
                end
                if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
                return
            end
            ok, accepted, detail = true, false, "no_active_contract"
        end
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

local function addUnavailableOption(menu, label)
    local option = menu:addOption(label, nil, nil)
    if option then option.notAvailable = true end
    return option
end

local function addFactionContractMenu(menu, group, summary, player)
    local contractMenu = addCategory(menu, "UI_SC_Faction_Contract")
    local social = summary and summary.social or nil
    local active = social and social.active or nil
    local offer = social and social.offer or nil
    local contract = active or offer
    if not contract then
        addUnavailableOption(contractMenu, text("UI_SC_Faction_NoContract"))
        return
    end
    if offer and offer.revealed ~= true then
        addUnavailableOption(contractMenu, text("UI_SC_Faction_AskNeedFirst"))
        contractMenu:addOption(text("UI_SC_Faction_AskNeeds"), nil,
            factionConversationAction, group.id, "talk", "needs", player)
        return
    end
    addUnavailableOption(contractMenu,
        text("UI_SC_Faction_ContractTitle", tostring(contract.title or contract.kind)))
    addUnavailableOption(contractMenu,
        text("UI_SC_Faction_ContractStatus", tostring(contract.status or "offered")))
    if offer then
        if (offer.kind == "retrieve_item" or offer.kind == "clear_horde")
            and offer.preparation ~= "ready" then
            addUnavailableOption(contractMenu, text("UI_SC_Quest_TargetPreparing"))
            return
        end
        contractMenu:addOption(text("UI_SC_Faction_AcceptContract"), nil,
            factionConversationAction, group.id, "accept_contract", nil, player)
        return
    end
    contractMenu:addOption(text("UI_SC_Faction_FulfillContract"), nil,
        factionConversationAction, group.id, "fulfill_contract", nil, player)
    local withdrawKey = pendingContractWithdrawal(group.id, active.id)
        and "UI_SC_Faction_WithdrawConfirmAction" or "UI_SC_Faction_WithdrawContract"
    contractMenu:addOption(text(withdrawKey), nil,
        factionConversationAction, group.id, "withdraw_contract", nil, player)
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
        addFactionContractMenu(menu, group, summary, player)
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

-- World-object lists can begin with the player or another moving object. Base
-- placement instead uses the immutable screen coordinates captured at click.
local function clickedWorldSquare(playerIndex, context, player, fallback)
    if type(screenToIsoX) ~= "function" or type(screenToIsoY) ~= "function"
        or type(getCell) ~= "function" or type(context) ~= "table"
        or tonumber(context.x) == nil or tonumber(context.y) == nil then
        return fallback
    end
    local z = tonumber(safeMethod(player, "getZ"))
    if z == nil then return fallback end
    local okX, worldX = pcall(screenToIsoX, playerIndex, context.x, context.y, z)
    local okY, worldY = pcall(screenToIsoY, playerIndex, context.x, context.y, z)
    if not okX or not okY or tonumber(worldX) == nil or tonumber(worldY) == nil then
        return fallback
    end
    local okCell, cell = pcall(getCell)
    if not okCell or not cell then return fallback end
    return safeMethod(cell, "getGridSquare", math.floor(tonumber(worldX)),
        math.floor(tonumber(worldY)), math.floor(z)) or fallback
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
    elseif action == "zone_remove" then ok, result = SC.BaseLife.removeZone(payload.id)
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

local function toggleBaseLayout(_, player)
    if SC.UI and type(SC.UI.toggleBaseLayout) == "function" then
        SC.UI.toggleBaseLayout(player)
    end
end

local function zonesAtSquare(square)
    local point = squarePayload(square)
    if not point or not SC.BaseLife or type(SC.BaseLife.visualRows) ~= "function" then
        return {}
    end
    local ok, rows = pcall(SC.BaseLife.visualRows)
    rows = ok and type(rows) == "table" and rows.zoneRows or nil
    local result = {}
    for _, zone in ipairs(type(rows) == "table" and rows or {}) do
        local x1, x2 = tonumber(zone.x1), tonumber(zone.x2)
        local y1, y2 = tonumber(zone.y1), tonumber(zone.y2)
        local z = tonumber(zone.z)
        if x1 and x2 and y1 and y2 and z == tonumber(point.z)
            and point.x >= math.min(x1, x2) and point.x <= math.max(x1, x2)
            and point.y >= math.min(y1, y2) and point.y <= math.max(y1, y2) then
            result[#result + 1] = zone
        end
    end
    -- In overlaps, put the smallest/specific zone before the broad camp area.
    table.sort(result, function(left, right)
        local leftArea = (math.abs((tonumber(left.x2) or 0) - (tonumber(left.x1) or 0)) + 1)
            * (math.abs((tonumber(left.y2) or 0) - (tonumber(left.y1) or 0)) + 1)
        local rightArea = (math.abs((tonumber(right.x2) or 0) - (tonumber(right.x1) or 0)) + 1)
            * (math.abs((tonumber(right.y2) or 0) - (tonumber(right.y1) or 0)) + 1)
        if leftArea == rightArea then return tostring(left.id) < tostring(right.id) end
        return leftArea < rightArea
    end)
    return result
end

local function removeZoneFromContext(_, zone, player)
    if type(zone) ~= "table" or not zone.id then return end
    local execute = function()
        baseAction(nil, "zone_remove", { id = zone.id }, player)
    end
    if SC.UI and type(SC.UI.confirmBaseAction) == "function" then
        SC.UI.confirmBaseAction(text("UI_SC_Base_RemoveZoneConfirm",
            zone.name or zone.kind or zone.id), execute)
    end
end

local function baseMenuRelevant(square)
    if not square or not SC.BaseLife or type(SC.BaseLife.active) ~= "function" then
        return false
    end
    if not SC.BaseLife.active() then return true end
    if type(SC.BaseLife.zoneDraft) == "function" and SC.BaseLife.zoneDraft() then
        return true
    end
    if type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(square) == true then return true end
    -- Lumber areas may be marked in the bounded reach band outside the camp.
    return type(SC.BaseLife.withinWorkReach) == "function"
        and SC.BaseLife.withinWorkReach(square) == true
end

local function addBaseMenu(context, square, containerTarget, barricadeTarget, player)
    if not square or not SC.BaseLife then return false end
    if not baseMenuRelevant(square) then return false end
    local rootOption = context:addOption(text("UI_SC_Context_BaseLife"), nil, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, menu)
    if not SC.BaseLife.active() then
        menu:addOption(text("UI_SC_Base_SetCamp"), nil, baseAction, "create",
            { square = square }, player)
        return true
    end
    local layoutShown = SC.BaseVisuals and type(SC.BaseVisuals.status) == "function"
        and SC.BaseVisuals.status().enabled == true
    menu:addOption(text(layoutShown and "UI_SC_Base_Visual_Hide" or "UI_SC_Base_Visual_Show"),
        nil, toggleBaseLayout, player)
    if layoutShown then
        for _, zone in ipairs(zonesAtSquare(square)) do
            menu:addOption(text("UI_SC_Base_RemoveZone", zone.name or zone.kind or zone.id),
                nil, removeZoneFromContext, zone, player)
        end
    end
    local draft = SC.BaseLife.zoneDraft()
    local inside = type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(square) == true
    if draft then
        menu:addOption(text("UI_SC_Base_FinishZone"), nil, baseAction, "zone_finish",
            { square = square, name = draft.kind }, player)
        menu:addOption(text("UI_SC_Base_CancelZone"), nil, baseAction, "zone_cancel", {}, player)
    else
        local zoneOption = menu:addOption(text("UI_SC_Base_StartZone"), nil, nil)
        local zoneMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(zoneOption, zoneMenu)
        -- Outside the camp only bounded reach zones may start, inside
        -- the bounded reach band around the camp.
        local kinds = inside and { "area", "work", "lumber", "farm", "burial", "pyre", "rest",
            "social", "guard", "rally", "quarantine" }
            or { "lumber", "farm", "burial", "pyre" }
        for _, kind in ipairs(kinds) do
            zoneMenu:addOption(text("UI_SC_Base_Zone_" .. kind), nil, baseAction, "zone_begin",
                { square = square, kind = kind }, player)
        end
    end
    if inside and containerTarget then
        local storageOption = menu:addOption(text("UI_SC_Base_MarkStorage"), nil, nil)
        local storageMenu = ISContextMenu:getNew(menu)
        menu:addSubMenu(storageOption, storageMenu)
        for _, category in ipairs({ "food", "water", "medical", "tools", "construction",
            "crafting", "literature", "weapons", "ammunition", "general", "output",
            "memorial", "farming" }) do
            storageMenu:addOption(text("UI_SC_Base_Storage_" .. category), nil, baseAction,
                "storage", { object = containerTarget, category = category }, player)
        end
    end
    if inside and barricadeTarget then
        menu:addOption(text("UI_SC_Base_MaintainBarricade"), nil, baseAction, "maintenance",
            { object = barricadeTarget, kind = "barricade" }, player)
    end
    if inside then
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

local function descriptorGroup(name, fallback)
    local groups = SC.UI and SC.UI.commandGroups or nil
    return type(groups) == "table" and type(groups[name]) == "table"
        and groups[name] or fallback
end

local function addDescriptorCommands(menu, row, player, descriptors)
    for _, descriptor in ipairs(descriptors or {}) do
        addCommand(menu, descriptor.key, row.id, descriptor.command,
            descriptor.payload, player)
    end
end

local function addConversation(menu, row, player)
    if row.recruited ~= true then return end
    addDescriptorCommands(menu, row, player, descriptorGroup("essentialTalk", {
        { key = "UI_SC_Action_Doing", command = "doing" },
        { key = "UI_SC_Action_Status", command = "status" },
        { key = "UI_SC_Action_Needs", command = "needs" },
        { key = "UI_SC_Action_Encourage", command = "encourage" },
        { key = "UI_SC_Action_Praise", command = "praise" },
    }))
end

local function addDirectOrders(menu, row, player)
    addDescriptorCommands(menu, row, player, descriptorGroup("personalOrders", {
        { key = "UI_SC_Action_Follow", command = "follow" },
        { key = "UI_SC_Action_Stay", command = "stay" },
        { key = "UI_SC_Action_Guard", command = "guard" },
        { key = "UI_SC_Action_Regroup", command = "regroup" },
        { key = "UI_SC_Action_Retreat", command = "retreat" },
    }))
    if type(row.vehicleStatus) == "table"
        and row.vehicleStatus.status == "in_vehicle"
        and row.vehicleStatus.canExitNow == true then
        addCommand(menu, "UI_SC_Action_ExitVehicleNow", row.id,
            "exit_vehicle", nil, player)
    end
end

local function addWorldOrders(menu, row, targetSquare, targetPayload, door, doorPayload,
        barricadeTarget, barricadePayload, removeBarricadeTarget,
        removeBarricadePayload, dismantleTarget, dismantlePayload, player)
    if targetPayload then
        addCommand(menu, "UI_SC_Action_MoveHere", row.id, "move_to", targetPayload, player)
    end
    if targetPayload and targetSquare and safeMethod(targetSquare, "getRoom") ~= nil then
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
end

-- Offer Bandage when the player can treat this companion now. When it has a
-- wound to dress but the player carries no bandage or stands too far away, show
-- the option disabled with the reason instead of hiding it.
local function addCare(menu, row, player)
    if not SC.Medical or type(SC.Medical.playerBandagePreflight) ~= "function" then return end
    if not SC.Registry or type(SC.Registry.byId) ~= "function" then return end
    local ok, record = pcall(SC.Registry.byId, row.id)
    if not ok or type(record) ~= "table" or not record.actor then return end
    local ready, reason = SC.Medical.playerBandagePreflight(record.actor, player)
    if ready == true then
        addCommand(menu, "UI_SC_Action_Bandage", row.id, "bandage", nil, player)
        return
    end
    local reasonText
    if reason == "no_bandage" then
        reasonText = text("UI_SC_Disabled_NoBandage")
    elseif reason == "out_of_range" then
        local limit = SC.Config and type(SC.Config.get) == "function"
            and tonumber(SC.Config.get("medicalPlayerBandageRange")) or 2
        reasonText = text("UI_SC_Disabled_TooFar", limit)
    else
        return
    end
    local option = addUnavailableOption(menu, text("UI_SC_Action_Bandage"))
    if option and type(ISToolTip) == "table" then
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        tooltip.description = reasonText
        option.toolTip = tooltip
    end
end

local function selectedNearbyRow(rows)
    local selectedId = SC.UI and SC.UI.instance and SC.UI.instance.selectedId or nil
    if not selectedId then return nil end
    for _, row in ipairs(rows or {}) do
        if row.id == selectedId then return row end
    end
    return nil
end

local function addNamedShortcut(context, row, labelKey, command, payload, player)
    local label = text("UI_SC_Context_NamedAction", row.name, text(labelKey))
    return context:addOption(label, nil, issueFromContext,
        row.id, command, payload, player)
end

local function addPriorityShortcut(context, row, targetSquare, door, doorPayload,
        barricadeTarget, barricadePayload, removeBarricadeTarget,
        removeBarricadePayload, dismantleTarget, dismantlePayload, player)
    if removeBarricadeTarget and removeBarricadePayload then
        return addNamedShortcut(context, row, "UI_SC_Action_RemoveBarricade",
            "remove_barricade", removeBarricadePayload, player)
    end
    if door and doorPayload then
        local isOpen = safeMethod(door, "IsOpen")
        return addNamedShortcut(context, row,
            isOpen and "UI_SC_Action_CloseDoor" or "UI_SC_Action_OpenDoor",
            isOpen and "close_door" or "open_door", doorPayload, player)
    end
    if barricadeTarget and barricadePayload then
        return addNamedShortcut(context, row, "UI_SC_Action_Barricade",
            "barricade", barricadePayload, player)
    end
    if dismantleTarget and dismantlePayload then
        return addNamedShortcut(context, row, "UI_SC_Action_Dismantle",
            "dismantle", dismantlePayload, player)
    end
    if targetSquare and safeMethod(targetSquare, "getRoom") ~= nil then
        return addNamedShortcut(context, row, "UI_SC_Action_CheckRoom",
            "check_room", squarePayload(targetSquare), player)
    end
    return nil
end

local function addCompanionCare(menu, row, player)
    addCare(menu, row, player)
    addViews(menu, row, player)
end

local function addSquadMenu(menu, player)
    for _, descriptor in ipairs({
        { key = "UI_SC_Action_WhistleRegroup", signal = "whistle" },
        { key = "UI_SC_Action_HandSignHold", signal = "hold" },
        { key = "UI_SC_Action_HandSignFallBack", signal = "fall_back" },
        { key = "UI_SC_Action_HandSignCeaseFire", signal = "cease_fire" },
        { key = "UI_SC_Action_HandSignFire", signal = "fire" },
    }) do
        menu:addOption(text(descriptor.key), nil, issueSignalFromContext,
            descriptor.signal, player)
    end
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
    local clickSquare = clickedWorldSquare(playerIndex, context, player, square)
    local rows = nearbyRows(player)
    local factions = talkableFactions(player)
    local baseRelevant = baseMenuRelevant(clickSquare)
    if #rows == 0 and #factions == 0 and not baseRelevant then return end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
    end
    if test ~= true and clickSquare and SC.BaseLife
        and type(SC.BaseLife.zoneDraft) == "function"
        and SC.BaseLife.zoneDraft()
        and type(SC.BaseLife.lockZoneEndpoint) == "function" then
        SC.BaseLife.lockZoneEndpoint(clickSquare)
    end
    local selected = selectedNearbyRow(rows)
    if selected and targetPayload then
        addNamedShortcut(context, selected, "UI_SC_Action_MoveHere",
            "move_to", targetPayload, player)
        addPriorityShortcut(context, selected, square, door, doorPayload,
            barricadeTarget, barricadePayload, removeBarricadeTarget,
            removeBarricadePayload, dismantleTarget, dismantlePayload, player)
    end

    local rootOption = context:addOption(text("UI_SC_Context_LivingFellows"), nil, nil)
    local rootMenu = ISContextMenu:getNew(context)
    context:addSubMenu(rootOption, rootMenu)

    if selected and selected.recruited == true then
        local selectedMenu = addNamedCategory(rootMenu,
            "UI_SC_Context_SelectedCompanion", selected.name)
        addDirectOrders(selectedMenu, selected, player)
        addConversation(addCategory(selectedMenu, "UI_SC_Context_Talk"), selected, player)
        local targetMenu = addCategory(selectedMenu, "UI_SC_Context_TargetActions")
        addWorldOrders(targetMenu, selected, square, targetPayload, door, doorPayload,
            barricadeTarget, barricadePayload, removeBarricadeTarget,
            removeBarricadePayload, dismantleTarget, dismantlePayload, player)
        addCompanionCare(addCategory(selectedMenu, "UI_SC_Context_Care"), selected, player)
        addCommand(selectedMenu, "UI_SC_Action_Dismiss", selected.id,
            "dismiss", nil, player)
    end

    local otherRows = {}
    for _, row in ipairs(rows) do
        if row.recruited == true and (not selected or row.id ~= selected.id) then
            otherRows[#otherRows + 1] = row
        end
    end
    if #otherRows > 0 then
        local otherMenu = addCategory(rootMenu, "UI_SC_Context_OtherCompanions")
        for _, row in ipairs(otherRows) do
            local companionOption = otherMenu:addOption(row.name, nil, nil)
            local companionMenu = ISContextMenu:getNew(otherMenu)
            otherMenu:addSubMenu(companionOption, companionMenu)
            addDirectOrders(companionMenu, row, player)
            addConversation(addCategory(companionMenu, "UI_SC_Context_Talk"), row, player)
            addCompanionCare(addCategory(companionMenu, "UI_SC_Context_Care"), row, player)
            addCommand(companionMenu, "UI_SC_Action_Dismiss", row.id,
                "dismiss", nil, player)
        end
    end

    if #rows > 0 then
        addSquadMenu(addCategory(rootMenu, "UI_SC_Context_Squad"), player)
    end
    if baseRelevant then
        addBaseMenu(rootMenu, clickSquare, containerTarget, barricadeTarget, player)
    end
    if #factions > 0 then
        addFactionConversations(addCategory(rootMenu, "UI_SC_Context_Households"),
            factions, player)
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
