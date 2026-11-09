-- SPDX-License-Identifier: MIT

require "ISUI/ISContextMenu"
require "ISUI/ISWorldObjectContextMenu"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISTextBox"
require "BuildingObjects/ISBuildingObject"
require "SCInteraction"
require "SCConstructionPlanner"
require "SCGameplayUtil"
require "SCContextMenu"

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UIContext = SC.UIContext or {}
local Context = SC.UIContext
local Menus = SC.ContextMenu

Context._installed = Context._installed or false
Context.maximumShortcutDistance = 16

-- Vanilla routes readable letters through this one entry point, including
-- the multi-item Read action. Keep the original callback and restore it when
-- UI hooks are removed so sealed post is detected without changing other
-- literature or keeping a stale wrapper after returning to the main menu.
function Context.readItemWithOddballMail(item, playerIndex)
    if SC.OddballVirgil and type(SC.OddballVirgil.isSealedMail) == "function"
        and SC.OddballVirgil.isSealedMail(item) == true
        and type(SC.OddballVirgil.openMailFor) == "function" then
        local player = type(getSpecificPlayer) == "function"
            and getSpecificPlayer(playerIndex) or nil
        SC.OddballVirgil.openMailFor(item, player)
    end
    if type(Context._originalReadItem) == "function" then
        return Context._originalReadItem(item, playerIndex)
    end
end

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

-- Vanilla's Medical Check sends a consent request to another player. Native
-- companions are IsoPlayers but cannot answer it. Route the real right-click
-- option directly to a local-player check and treatment session instead.
function Context.medicalCheckCompanion(requester, target)
    local function reject(reason, argument)
        if requester then safeMethod(requester, "setHaloNote",
            argument and text(reason, argument) or text(reason)) end
        return false, reason
    end
    if not requester or not target or not SC.Actor
        or type(SC.Actor.isCompanion) ~= "function" then
        return reject("UI_SC_Disabled_InvalidActor")
    end
    local valid, companion = pcall(SC.Actor.isCompanion, target)
    if not valid or companion ~= true or safeMethod(target, "isDead") == true then
        return reject("UI_SC_Disabled_InvalidActor")
    end
    if not SC.UI or type(SC.UI.openHealth) ~= "function" then
        return reject("UI_SC_Disabled_HealthUnavailable")
    end
    local ok, opened, reason, argument = pcall(SC.UI.openHealth, target, requester)
    if not ok or opened ~= true then
        return reject(reason or "UI_SC_Disabled_HealthUnavailable", argument)
    end
    safeMethod(requester, "setHaloNote", text("UI_SC_MedicalCheck_Opened"))
    return true, "health_opened"
end

-- The vanilla option may be omitted for a native companion or another mod may
-- have captured its callback before our wrapper was installed. Bind the actual
-- clicked menu option as well, without adding a duplicate Medical Check entry.
function Context.ensureCompanionMedicalOption(context, worldObjects, player, row)
    if not context then return nil end
    local name = getText and getText("ContextMenu_Medical_Check") or "Medical Check"
    local option = type(context.getOptionFromName) == "function"
        and context:getOptionFromName(name) or nil
    local wrapped = option and type(context.onGetUpAndThen) == "function"
        and option.onSelect == context.onGetUpAndThen
    if option then
        -- The native body hit-test can identify a patient while the clicked
        -- floor square misses their feet. Keep that exact patient rather than
        -- substituting the companion selected for ground orders, even when a
        -- later floor hit finds a different companion. Existing human-player,
        -- other-requester and unrelated options retain their native callback.
        local callback = wrapped and option.param1 or option.onSelect
        local requester = wrapped and option.param3 or option.param1
        local patient = wrapped and option.param4 or option.param2
        local medicalCallback = type(callback) == "function"
            and (callback == Context.onMedicalCheck
                or callback == Context._originalMedicalCheck
                or ISWorldObjectContextMenu
                    and callback == ISWorldObjectContextMenu.onMedicalCheck)
        local ok, companion = pcall(function()
            return medicalCallback and requester == player and SC.Actor
                and type(SC.Actor.isCompanion) == "function"
                and SC.Actor.isCompanion(patient) == true
        end)
        if not ok or companion ~= true then return nil end
        if not row or row.actor ~= patient then row = { actor = patient } end
    end
    if not row or not row.actor then return nil end
    if not option then
        option = context:addOption(name, worldObjects, Context.onMedicalCheck,
            player, row.actor)
    elseif wrapped then
        -- Retain the native stand-up action before examining the patient.
        option.target = context
        option.param1 = Context.onMedicalCheck
        option.param2 = worldObjects
        option.param3 = player
        option.param4 = row.actor
    else
        option.target = worldObjects
        option.onSelect = Context.onMedicalCheck
        option.param1 = player
        option.param2 = row.actor
    end
    local available, reason, argument
    if SC.MedicalUI and type(SC.MedicalUI.availability) == "function" then
        available, reason, argument = SC.MedicalUI.availability(row.actor, player)
    else
        available, reason = false, "UI_SC_Disabled_HealthUnavailable"
    end
    option.notAvailable = available ~= true
    if option.notAvailable and type(ISToolTip) == "table" then
        local tooltip = ISToolTip:new()
        tooltip:initialise()
        tooltip:setVisible(false)
        if reason == "UI_SC_Disabled_TooFar" then
            local patientName = SC.UI and type(SC.UI.displayName) == "function"
                and SC.UI.displayName(row.actor, row.name) or row.name
            tooltip.description = text("UI_SC_MedicalCheck_TooFar",
                patientName or text("UI_SC_Value_UnknownCompanion"), argument)
        else
            tooltip.description = argument and text(reason, argument) or text(reason)
        end
        option.toolTip = tooltip
    else
        option.toolTip = nil
    end
    return option
end

function Context.onMedicalCheck(worldObjects, requester, target)
    local valid, companion = pcall(function()
        return SC.Actor and type(SC.Actor.isCompanion) == "function"
            and SC.Actor.isCompanion(target) == true
    end)
    if valid and companion then
        return Context.medicalCheckCompanion(requester, target)
    end
    if Context._originalMedicalCheck then
        return Context._originalMedicalCheck(worldObjects, requester, target)
    end
end

local function hasMethod(object, methodName)
    if not object then return false end
    local ok, value = pcall(function() return object[methodName] end)
    return ok and type(value) == "function"
end

local function currentRecord(row, player)
    local record = row and SC.Registry and SC.Registry.byId and SC.Registry.byId(row.id)
    if record and record.actor == row.actor and safeMethod(row.actor, "isDead") ~= true then
        return record
    end
    if player then safeMethod(player, "setHaloNote", text("UI_SC_Disabled_InvalidActor")) end
end

local function executeFromContext(companionId, command, payload, player)
    if payload == nil and SC.Interaction and SC.Interaction.descriptor(command)
        and SC.Registry and type(SC.Registry.byId) == "function" then
        local record = SC.Registry.byId(companionId)
        local row = record and SC.UI and SC.UI.describeEntry
            and SC.UI.describeEntry(record, player) or nil
        local accepted, reason = SC.Interaction.issue(row, command, player)
        if player then safeMethod(player, "setHaloNote", accepted
            and text(reason == "home_recall_staged" and "UI_SC_HomeTrip_CalledOff" or "UI_SC_CommandAccepted")
            or SC.Interaction.reasonText(reason)) end
        if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
        return
    end
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
        elseif (command == "designate_target" or command == "avoid_target"
            or command == "assign_objective") and player then
            local acceptedKey = command == "assign_objective" and "UI_SC_Objective_Assigned"
                or command == "designate_target" and second == "target_pushed"
                    and "UI_SC_Target_Pushed"
                or command == "designate_target" and "UI_SC_Target_Designated"
                or "UI_SC_Target_Avoided"
            local rejectedKey = command == "assign_objective"
                and "UI_SC_Objective_Rejected" or "UI_SC_Target_Rejected"
            safeMethod(player, "setHaloNote", ok and first == true
                and text(acceptedKey)
                or text(rejectedKey, tostring(second or first or "unavailable")))
            if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
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
            if SC.Names and type(SC.Names.displayName) == "function" then
                local show = not SC.UI or type(SC.UI.getSettings) ~= "function"
                    or SC.UI.getSettings().showNicknames ~= false
                local named, display = pcall(SC.Names.displayName, record, show)
                if named and type(display) == "string" and display ~= "" then
                    return display
                end
            end
            local name = safeMethod(record.actor, "getFullName")
                or safeMethod(record.actor, "getDisplayName")
            if name and name ~= "" then return name end
        end
    end
    return companionId
end

local function nicknameRecord(row)
    if type(row) ~= "table" or type(row.id) ~= "string"
        or not SC.Registry or type(SC.Registry.byId) ~= "function" then return nil end
    local ok, record = pcall(SC.Registry.byId, row.id)
    if not ok or type(record) ~= "table" or record.recruited ~= true
        or record.actor == nil or row.actor ~= record.actor then return nil end
    return record
end

function Context.nicknameValid(_target, candidate)
    return SC.Names and type(SC.Names.normalize) == "function"
        and type(SC.Names.normalize(candidate)) == "string"
end

local function acknowledgeNickname(record, nickname)
    local actor = record and record.actor
    if not actor then return end
    local likes = type(record.nickname) == "table" and record.nickname.likes ~= false
    local topic = likes and "nickname.player.accept" or "nickname.player.reject"
    if SC.Dialogue and type(SC.Dialogue.has) == "function"
        and SC.Dialogue.has(topic) == true and type(SC.Dialogue.say) == "function" then
        local ok, spoken = pcall(SC.Dialogue.say, actor, topic, nil, { nickname },
            { salt = tostring(record.id) .. ":" .. tostring(nickname) })
        if ok and spoken == true then return end
    end
    if SC.GameplayUtil and type(SC.GameplayUtil.say) == "function" then
        SC.GameplayUtil.say(actor, likes and (nickname .. "? Alright. I'll answer to it.")
            or ("I'm not answering to " .. nickname .. ". Try again."))
    end
end

function Context.onNicknameTextBox(_target, button, row, player)
    if not button or button.internal ~= "OK" then return end
    local record = nicknameRecord(row)
    if not record or not SC.Names or type(SC.Names.setNickname) ~= "function" then return end
    local input = button.parent and button.parent.entry
        and button.parent.entry:getText() or nil
    local nickname = type(SC.Names.normalize) == "function"
        and SC.Names.normalize(input) or nil
    if type(nickname) ~= "string" then
        if player then safeMethod(player, "setHaloNote", text("UI_SC_Nickname_Invalid")) end
        return
    end
    local ok, accepted = pcall(SC.Names.setNickname, record, nickname, "player", nil)
    if not ok or accepted == false or accepted == nil then
        if player then safeMethod(player, "setHaloNote", text("UI_SC_Nickname_Invalid")) end
        return
    end
    acknowledgeNickname(record, nickname)
    if SC.UIBridge and type(SC.UIBridge.invalidateNearbyInventoryLabels) == "function" then
        SC.UIBridge.invalidateNearbyInventoryLabels()
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function giveNicknameFromContext(_target, row, player)
    local record = nicknameRecord(row)
    if not record or not SC.Names or type(SC.Names.normalize) ~= "function" then return end
    local current = type(record.nickname) == "table" and record.nickname.text or ""
    local playerNum = tonumber(safeMethod(player, "getPlayerNum")) or 0
    local modal = ISTextBox:new(0, 0, 300, 170,
        text("UI_SC_Nickname_Prompt"), current, nil,
        Context.onNicknameTextBox, playerNum, row, player)
    modal:initialise()
    modal.maxChars = tonumber(SC.Config and SC.Config.get
        and SC.Config.get("nicknameMaxLength")) or 16
    modal.noEmpty = true
    modal:setValidateFunction(nil, Context.nicknameValid)
    modal:setValidateTooltipText(text("UI_SC_Nickname_Invalid"))
    modal:addToUIManager()
end

local function clearNicknameFromContext(_target, row)
    local record = nicknameRecord(row)
    if not record or not SC.Names or type(SC.Names.clearNickname) ~= "function" then
        return
    end
    local ok, cleared = pcall(SC.Names.clearNickname, record)
    if not ok or cleared == false then return end
    if SC.UIBridge and type(SC.UIBridge.invalidateNearbyInventoryLabels) == "function" then
        SC.UIBridge.invalidateNearbyInventoryLabels()
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function addNicknameActions(menu, row, player)
    if SC.Config and type(SC.Config.get) == "function"
        and SC.Config.get("nicknamesEnabled") == false then return end
    if not SC.Names or type(SC.Names.setNickname) ~= "function" then return end
    local record = nicknameRecord(row)
    if not record then return end
    menu:addOption(text("UI_SC_Nickname_Give"), nil,
        giveNicknameFromContext, row, player)
    if type(record.nickname) == "table" and type(record.nickname.text) == "string"
        and record.nickname.text ~= "" then
        menu:addOption(text("UI_SC_Nickname_Clear"), nil,
            clearNicknameFromContext, row)
    end
end

local function issueFromContext(target, companionId, command, payload, player)
    if type(target) == "table" and target.actor and not currentRecord(target, player) then return end
    if type(payload) == "table" and payload.object then
        local object, square = payload.object, safeMethod(payload.object, "getSquare")
        if not square or payload.objectIndex ~= nil and safeMethod(object, "getObjectIndex") ~= payload.objectIndex
            or payload.x ~= nil and (safeMethod(square, "getX") ~= payload.x
                or safeMethod(square, "getY") ~= payload.y or safeMethod(square, "getZ") ~= payload.z) then
            safeMethod(player, "setHaloNote", text("UI_SC_Context_Changed"))
            return false
        end
    end
    if command == "dismiss" and SC.UI and type(SC.UI.confirmDismiss) == "function" then
        SC.UI.confirmDismiss(companionName(companionId), function()
            if type(target) == "table" and target.actor and not currentRecord(target, player) then return end
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

local function watchFromContext(target, row, player)
    if type(row) ~= "table" or row.actor == nil or not SC.ViewControl then return end
    if not currentRecord(row, player) then return end
    local watched, reason = false, nil
    if type(SC.ViewControl.watch) == "function" then
        watched, reason = SC.ViewControl.watch(row.id, row.actor)
    end
    if player then
        safeMethod(player, "setHaloNote", watched == true
            and text("UI_SC_Watch_Started", row.name)
            or text("UI_SC_Watch_Failed", tostring(reason or "unavailable")))
    end
end

local function stopWatchingFromContext(target, player)
    if not SC.ViewControl or type(SC.ViewControl.stopWatching) ~= "function" then return end
    local stopped = SC.ViewControl.stopWatching()
    if stopped and player then
        safeMethod(player, "setHaloNote", text("UI_SC_Watch_Stopped"))
    end
end

local function addCommand(menu, labelKey, id, command, payload, player)
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(id)
    local bound = { id = id, actor = record and record.actor }
    return Menus.action(menu, "leaf:" .. tostring(id) .. ":" .. command,
        text(labelKey), bound, issueFromContext, id, command, payload, player)
end

local function addChefOrder(menu, row, player)
    local base = SC.BaseLife
    local resident = base and type(base.resident) == "function" and base.resident(row.id)
    if resident and resident.role == "chef" and resident.duty == true
        and base.active() and base.isInside(player) then
        addCommand(menu, "UI_SC_Action_CookMeal", row.id, "cook_meal", nil, player)
    end
end

local function addCategory(menu, labelKey)
    return Menus.group(menu, labelKey, text(labelKey))
end

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
    elseif action == "recruitment_review" then
        if SC.UISocial then SC.UISocial.reviewJoining(factionId) end
        return
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
        if type(group.oddball) ~= "table" then
            local ok, ready = pcall(SC.FactionContracts.canTalk, group, player)
            if ok and ready == true then result[#result + 1] = group end
        end
    end
    return result
end

local function talkableOddballs(player)
    local result = {}
    if not SC.Factions or type(SC.Factions.list) ~= "function"
        or not SC.Registry or type(SC.Registry.byId) ~= "function" then
        return result
    end
    for _, group in ipairs(SC.Factions.list(false) or {}) do
        if type(group.oddball) == "table" and group.lifecycle ~= "destroyed" then
            local added = false
            for _, member in ipairs(group.members or {}) do
                local record = type(member.actorId) == "string"
                    and SC.Registry.byId(member.actorId) or nil
                if record and record.actor and SC.GameplayUtil.distance(player, record.actor) <= 6
                    and (not SC.GameplayUtil.canSee
                        or SC.GameplayUtil.canSee(player, record.actor) == true) then
                    result[#result + 1] = group
                    added = true
                    break
                end
            end
            if not added and SC.OddballLester
                and type(SC.OddballLester.canTalkThroughSlot) == "function"
                and SC.OddballLester.canTalkThroughSlot(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballGordon
                and type(SC.OddballGordon.canTalkThroughSlot) == "function"
                and SC.OddballGordon.canTalkThroughSlot(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballWerewolf
                and type(SC.OddballWerewolf.canTalkThroughDoor) == "function"
                and SC.OddballWerewolf.canTalkThroughDoor(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballLoretta
                and type(SC.OddballLoretta.canTalkFromVehicle) == "function"
                and SC.OddballLoretta.canTalkFromVehicle(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballPurdy
                and type(SC.OddballPurdy.canTalkThroughWindow) == "function"
                and SC.OddballPurdy.canTalkThroughWindow(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballRoom12
                and type(SC.OddballRoom12.canTalkThroughDoor) == "function"
                and SC.OddballRoom12.canTalkThroughDoor(group, player) then
                result[#result + 1] = group
                added = true
            end
            if not added and SC.OddballDehydrated
                and type(SC.OddballDehydrated.canTalkThroughDoor) == "function"
                and SC.OddballDehydrated.canTalkThroughDoor(group, player) then
                result[#result + 1] = group
            end
        end
    end
    return result
end

local function oddballStoryAction(_target, groupId, action, player, payload, sourceRow)
    local group = SC.Factions and SC.Factions.group and SC.Factions.group(groupId)
    local memberCurrent, reachable = sourceRow == nil, sourceRow == nil
    if sourceRow then
        if not currentRecord(sourceRow, player) then return end
        for _, member in ipairs(group and group.members or {}) do
            if member.actorId == sourceRow.id then memberCurrent = true break end
        end
        for _, candidate in ipairs(talkableOddballs(player)) do
            if candidate.id == groupId then reachable = true break end
        end
    end
    local available = false
    for _, choice in ipairs(memberCurrent and reachable and group and group.lifecycle ~= "destroyed"
        and SC.Oddballs and SC.Oddballs.menuOptions and SC.Oddballs.menuOptions(group, player) or {}) do
        if choice.id == action and choice.enabled == true then available = true break end
    end
    if not available then
        safeMethod(player, "setHaloNote", text("UI_SC_Oddball_ChoiceChanged"))
        return
    end
    local ok, accepted, detail = false, false, "story_unavailable"
    if SC.Oddballs and type(SC.Oddballs.storyAction) == "function" then
        ok, accepted, detail = pcall(SC.Oddballs.storyAction,
            groupId, action, player, payload)
    end
    if player then
        local message = detail == "fan_diary_recalled" and text("UI_SC_Oddball_CoreyDiaryRecalled")
            or tostring(detail or "Done")
        safeMethod(player, "setHaloNote", ok and accepted == true
            and text("UI_SC_Oddball_ActionAccepted", message)
            or text("UI_SC_Oddball_ActionFailed", tostring(ok and detail or accepted)))
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function addOddballStoryChoices(menu, group, player, sourceRow, options)
    if not sourceRow then
        local stage = group.oddball and group.oddball.stage or "unmet"
        addUnavailableOption(menu, text("UI_SC_Oddball_Progress", tostring(stage)))
    end
    options = options or SC.Oddballs and type(SC.Oddballs.menuOptions) == "function"
        and SC.Oddballs.menuOptions(group, player) or {}
    if #options == 0 then
        addUnavailableOption(menu, text("UI_SC_Oddball_NoAction"))
    end
    for _, row in ipairs(options) do
        local label = tostring(row.label or row.id or "Speak")
        local item
        if row.enabled ~= true then
            item = addUnavailableOption(menu, label)
        elseif type(row.id) == "string" then
            item = menu:addOption(label, nil, oddballStoryAction,
                group.id, row.id, player, row.payload, sourceRow)
        end
        local detail = row.detail or row.reason
        if item and detail and type(ISToolTip) == "table" then
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip.description = tostring(detail)
            item.toolTip = tooltip
        end
    end
end

local function addOddballConversations(context, groups, player)
    for _, group in ipairs(groups or {}) do
        local option = context:addOption(tostring(group.name or "Stranger"), nil, nil)
        local menu = ISContextMenu:getNew(context)
        context:addSubMenu(option, menu)
        addOddballStoryChoices(menu, group, player)
    end
end

local function addRecruitedOddballAction(menu, row, player)
    if not row or row.recruited ~= true or not SC.FactionRecruitment
        or type(SC.FactionRecruitment.originForActor) ~= "function"
        or not SC.Oddballs or type(SC.Oddballs.menuOptions) ~= "function" then
        return
    end
    local origin = SC.FactionRecruitment.originForActor(row.id)
    local group = origin and origin.group
    if not group or type(group.oddball) ~= "table" then return end
    for _, action in ipairs(SC.Oddballs.menuOptions(group, player) or {}) do
        if action.id == "gut_up" or action.id == "have_tea" then
            local fallback = action.id == "have_tea" and "Have tea" or "Gut up"
            if action.enabled ~= true then
                addUnavailableOption(menu, tostring(action.label or fallback))
            else
                menu:addOption(tostring(action.label or fallback), nil,
                    oddballStoryAction, group.id, action.id, player, action.payload)
            end
            return
        end
    end
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
        elseif recruitment then
            menu:addOption(text("UI_SC_Social_ask"), nil,
                factionConversationAction, group.id, "recruitment_review", nil, player)
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
        or type(getCell) ~= "function" or type(context) ~= "table" then
        return fallback
    end
    local clickX = tonumber(context.requestX) or tonumber(context.x)
    local clickY = tonumber(context.requestY) or tonumber(context.y)
    if clickX == nil or clickY == nil then return fallback end
    local z = tonumber(safeMethod(player, "getZ"))
    if z == nil then return fallback end
    local okX, worldX = pcall(screenToIsoX, playerIndex, clickX, clickY, z)
    local okY, worldY = pcall(screenToIsoY, playerIndex, clickX, clickY, z)
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
    local combatTarget = nil
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
        if not combatTarget then
            local zombie = SC.GameplayUtil.isZombie(object)
            local gone = SC.GameplayUtil and type(SC.GameplayUtil.isGoneTarget) == "function"
                and SC.GameplayUtil.isGoneTarget(object) or false
            if zombie == true and gone ~= true then combatTarget = object end
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
        removeBarricadePayload, dismantleTarget, dismantlePayload, combatTarget
end

local startZoneCursor, stopZoneCursor
local function baseAction(target, action, payload, player)
    if not SC.BaseLife then return end
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        safeMethod(player, "setHaloNote", text("UI_SC_BaseWatch_RadioOnly"))
        return
    end
    local ok, result
    if action == "create" then ok, result = SC.BaseLife.create(payload.square, "Main Camp")
    elseif action == "zone_begin" then ok, result = SC.BaseLife.beginZone(payload.kind, payload.square)
    elseif action == "zone_finish" then ok, result = SC.BaseLife.finishZone(payload.square, payload.name)
    elseif action == "zone_cancel" then ok, result = SC.BaseLife.cancelZone()
    elseif action == "zone_remove" then ok, result = SC.BaseLife.removeZone(payload.id)
    elseif action == "room_mark" then ok, result = SC.BaseLife.markRoom(payload.square, payload.kind)
    elseif action == "abandon" then
        ok, result = SC.BaseLife.abandon()
        if ok and SC.Commands and type(SC.Commands.leaveAbandonedBase) == "function" then
            SC.Commands.leaveAbandonedBase(player)
        end
    elseif action == "storage" then
        ok, result = SC.BaseLife.registerStorage(payload.object, payload.category)
    elseif action == "storage_remove" then
        ok, result = SC.BaseLife.removeStorage(payload.id)
    elseif action == "clean" then
        ok, result = SC.BaseLife.requestCleaning(payload.square)
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
    if ok and action == "zone_begin" then
        if not startZoneCursor(player) then
            SC.BaseLife.cancelZone()
            ok, result = false, "zone_cursor_unavailable"
        end
    elseif ok and (action == "zone_finish" or action == "zone_cancel") then
        stopZoneCursor()
    end
    if player then
        local failure = SC.UI and type(SC.UI.baseFailureReason) == "function"
            and SC.UI.baseFailureReason(result) or tostring(result)
        safeMethod(player, "setHaloNote", ok and action == "zone_begin"
                and text("UI_SC_Base_ZonePickEnd")
            or ok and action == "clean"
                and text("UI_SC_Base_CleaningQueued")
            or ok and action == "room_mark"
                and text("UI_SC_Base_RoomMarked", text(payload.kind == "area"
                    and "UI_SC_Base_RoomZone_area" or "UI_SC_Base_Zone_" .. payload.kind))
            or ok and text("UI_SC_Base_ActionAccepted")
            or text("UI_SC_Base_ActionFailed", failure))
    end
    if SC.BaseVisuals then
        SC.BaseVisuals.refresh()
        if ok and action == "room_mark" and type(result) == "table"
            and result.roomGroupId and type(SC.BaseVisuals.flashRoom) == "function" then
            SC.BaseVisuals.flashRoom(result.roomGroupId)
        end
    end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
    return ok, result
end

local ZoneCursor
local function sameZoneDraft(first, second)
    -- BaseLife exposes defensive copies, never the private draft table.
    return first and second and first.kind == second.kind
        and first.first.x == second.first.x and first.first.y == second.first.y
        and first.first.z == second.first.z
end
stopZoneCursor = function(cursor)
    cursor = cursor or Context._zoneCursor
    if not cursor then return end
    local cell = type(getCell) == "function" and getCell() or nil
    if safeMethod(cell, "getDrag", cursor.player) == cursor then
        cell:setDrag(nil, cursor.player)
    else cursor:deactivate() end
end

startZoneCursor = function(player)
    local draft = SC.BaseLife.zoneDraft()
    local cell = type(getCell) == "function" and getCell() or nil
    local index = safeMethod(player, "getPlayerNum")
    if not draft or index == nil or not cell or type(cell.setDrag) ~= "function"
        or type(ISBuildingObject) ~= "table" then return false end
    if not ZoneCursor then
        ZoneCursor = ISBuildingObject:derive("SCBaseZoneCursor")
        function ZoneCursor:rotateMouse() end
        function ZoneCursor:rotateKey() end
        function ZoneCursor:isValid(square)
            -- Native heights can be boxed Java Floats; compare tile floors.
            local squareZ = tonumber(tostring(safeMethod(square, "getZ")))
            local actorZ = tonumber(tostring(safeMethod(self.character, "getZ")))
            return Context._zoneCursor == self
                and sameZoneDraft(SC.BaseLife.zoneDraft(), self.draft) and square ~= nil
                and squareZ == self.draft.first.z and actorZ ~= nil
                and math.floor(actorZ) == self.draft.first.z
                and safeMethod(self.character, "isDead") ~= true
        end
        function ZoneCursor:render(x, y, z, square)
            if not self:isValid(square) then return end
            local endpoint = self.endpoint
            if not endpoint or endpoint.x ~= x or endpoint.y ~= y or endpoint.z ~= z then
                local ok, point = SC.BaseLife.lockZoneEndpoint(square)
                if ok then self.endpoint = point end
            end
        end
        function ZoneCursor:tryBuild(x, y, z)
            local square = safeMethod(getCell(), "getGridSquare", x, y, z)
            if not self:isValid(square) then return end
            baseAction(nil, "zone_finish", { square = square, name = self.draft.kind }, self.character)
            self:reinit()
        end
        function ZoneCursor:update()
            if Context._zoneCursor ~= self
                or not sameZoneDraft(SC.BaseLife.zoneDraft(), self.draft) then stopZoneCursor(self) end
        end
        function ZoneCursor:deactivate()
            if Context._zoneCursor ~= self then return end
            Context._zoneCursor = nil
            if sameZoneDraft(SC.BaseLife.zoneDraft(), self.draft) then
                SC.BaseLife.cancelZone()
                if SC.BaseVisuals then SC.BaseVisuals.refresh() end
            end
        end
    end
    local cursor = setmetatable({}, ZoneCursor)
    ZoneCursor.__index = ZoneCursor
    cursor:init()
    cursor.character, cursor.player, cursor.draft = player, index, draft
    cursor.skipBuildAction, cursor.noNeedHammer = true, true
    Context._zoneCursor = cursor
    cell:setDrag(cursor, index)
    return true
end

local function toggleBaseLayout(_, player)
    if SC.UI and type(SC.UI.toggleBaseLayout) == "function" then
        SC.UI.toggleBaseLayout(player)
    end
end

-- Halo notes show translated text; internal reason codes never reach the player.
local function planNote(player, message)
    if player then safeMethod(player, "setHaloNote", message) end
end

local function startConstruction(_, kind, player)
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        planNote(player, text("UI_SC_BaseWatch_RadioOnly"))
        return
    end
    local okay, reason = SC.ConstructionPlanner.start(kind, player)
    if not okay then planNote(player, SC.ConstructionPlanner.reasonText(reason)) end
end

local function startBarricadePlan(_, object, player)
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        planNote(player, text("UI_SC_BaseWatch_RadioOnly"))
        return
    end
    local okay, reason = SC.ConstructionPlanner.startBarricade(object, player)
    if not okay then planNote(player, SC.ConstructionPlanner.reasonText(reason)) end
end

local function buildBlueprint(_, id, player)
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        planNote(player, text("UI_SC_BaseWatch_RadioOnly"))
        return
    end
    local okay, reason = SC.ConstructionPlanner.buildSegment(player, id)
    planNote(player, okay and reason ~= "already_built"
        and text("UI_SC_Base_Blueprint_PlayerStarted")
        or SC.ConstructionPlanner.reasonText(reason))
end

local function manageBlueprint(_, action, id, player)
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        planNote(player, text("UI_SC_BaseWatch_RadioOnly"))
        return
    end
    local method = action == "retry" and SC.BaseLife.retryJob or SC.BaseLife.cancelJob
    local okay, reason = method(id)
    planNote(player, okay and text("UI_SC_Base_ActionAccepted")
        or SC.ConstructionPlanner.reasonText(reason))
    if SC.BaseVisuals then SC.BaseVisuals.refresh() end
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
end

local function zonesAtSquare(square)
    local point = squarePayload(square)
    if not point or not SC.BaseLife or type(SC.BaseLife.visualRows) ~= "function" then
        return {}
    end
    local ok, rows = pcall(SC.BaseLife.visualRows)
    rows = ok and type(rows) == "table" and rows.zoneRows or nil
    local result = {}
    local seenGroups = {}
    for _, zone in ipairs(type(rows) == "table" and rows or {}) do
        local x1, x2 = tonumber(zone.x1), tonumber(zone.x2)
        local y1, y2 = tonumber(zone.y1), tonumber(zone.y2)
        local z = tonumber(zone.z)
        if x1 and x2 and y1 and y2 and z == tonumber(point.z)
            and point.x >= math.min(x1, x2) and point.x <= math.max(x1, x2)
            and point.y >= math.min(y1, y2) and point.y <= math.max(y1, y2) then
            if not zone.roomGroupId or not seenGroups[zone.roomGroupId] then
                result[#result + 1] = zone
                if zone.roomGroupId then seenGroups[zone.roomGroupId] = true end
            end
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

local function storageForObject(object)
    if not object or not SC.BaseLife
        or type(SC.BaseLife.storageRows) ~= "function"
        or type(SC.BaseLife.resolveObject) ~= "function" then return nil end
    for _, storage in ipairs(SC.BaseLife.storageRows()) do
        -- Coordinates and a mutable object index can refer to another
        -- container. Only the registered object's identity may offer removal.
        if SC.BaseLife.resolveObject(storage) == object then return storage end
    end
end

local function removeStorageFromContext(_, storage, player)
    if type(storage) ~= "table" or not storage.id then return end
    local execute = function()
        baseAction(nil, "storage_remove", { id = storage.id }, player)
    end
    if SC.UI and type(SC.UI.confirmBaseAction) == "function" then
        SC.UI.confirmBaseAction(text("UI_SC_Base_RemoveStorageConfirm"), execute)
    end
end

-- Abandoning is how a camp moves: once it is gone, "Set camp core here"
-- returns to the menu. Always confirmed first.
local function abandonBaseFromContext(_, player)
    local base = SC.BaseLife and SC.BaseLife.active() or nil
    if not base then return end
    local execute = function()
        baseAction(nil, "abandon", {}, player)
    end
    if SC.UI and type(SC.UI.confirmBaseAction) == "function" then
        SC.UI.confirmBaseAction(text("UI_SC_Base_AbandonConfirm",
            base.name or "Main Camp"), execute)
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
    if type(SC.BaseLife.mayExtendAreaToFloor) == "function"
        and SC.BaseLife.mayExtendAreaToFloor(square) == true then return true end
    if type(SC.BaseLife.parkingCornerRelevant) == "function"
        and SC.BaseLife.parkingCornerRelevant(square) == true then return true end
    -- A large room in the camp's building can be valid beyond the ordinary
    -- work band. Ask the same validator used by the room action itself.
    if safeMethod(square, "getRoomDef")
        and type(SC.BaseLife.roomMarkPreview) == "function"
        and SC.BaseLife.roomMarkPreview(square, "area") == true then return true end
    -- Lumber areas may be marked in the bounded reach band outside the camp.
    return type(SC.BaseLife.withinWorkReach) == "function"
        and SC.BaseLife.withinWorkReach(square) == true
end

local function addCleanStainOption(context, square, player)
    if SC.BaseWatch and type(SC.BaseWatch.isRemote) == "function"
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then return end
    if not square or not SC.BaseLife
        or type(SC.BaseLife.isInside) ~= "function"
        or SC.BaseLife.isInside(square) ~= true
        or safeMethod(square, "haveStains") ~= true
        or type(SC.BaseLife.canRequestCleaning) ~= "function" then return end
    local available, reason = SC.BaseLife.canRequestCleaning(square, nil, true)
    local option = context:addOption(text("UI_SC_Base_CleanStain"), nil,
        baseAction, "clean", { square = square }, player)
    if not available and option then
        option.notAvailable = true
        if type(ISToolTip) == "table" then
            local reasons = {
                cleaning_already_queued = "UI_SC_Base_CleanReason_cleaning_already_queued",
                cleaning_worker_missing = "UI_SC_Base_CleanReason_cleaning_worker_missing",
                cleaning_worker_away = "UI_SC_Base_CleanReason_cleaning_worker_away",
                cleaning_supplies_missing = "UI_SC_Base_CleanReason_cleaning_supplies_missing",
                cleaning_tool_missing = "UI_SC_Base_Reason_cleaning_tool_missing",
                cleaning_cleaner_missing = "UI_SC_Base_Reason_cleaning_cleaner_missing",
                cleaning_carry_capacity_low = "UI_SC_Base_Reason_work_carry_full",
                cleaning_water_or_bucket_missing = "UI_SC_Base_Reason_cleaning_water_or_bucket_missing",
                cleaning_route_unavailable = "UI_SC_Base_CleanReason_cleaning_route_unavailable",
                cleaning_outside_camp = "UI_SC_Base_CleanReason_cleaning_outside_camp",
                cleaning_target_unavailable = "UI_SC_Base_CleanReason_cleaning_target_unavailable",
                cleaning_stain_gone = "UI_SC_Base_CleanReason_cleaning_stain_gone",
            }
            local tooltip = ISToolTip:new()
            tooltip:initialise()
            tooltip:setVisible(false)
            tooltip.description = text(reasons[reason]
                or "UI_SC_Base_CleanReason_generic")
            option.toolTip = tooltip
        end
    end
end

local function addBaseMenu(context, square, containerTarget, barricadeTarget, player)
    if not square or not SC.BaseLife then return false end
    local storage = storageForObject(containerTarget)
    if not baseMenuRelevant(square) and not storage then return false end
    -- These are already inside Living Fellows. A second Camp wrapper makes
    -- storage marking needlessly deep, especially with native cascading menus.
    local menu = context
    if not SC.BaseLife.active() then
        local option=menu:addOption(text("UI_SC_Base_SetCamp"), nil, baseAction, "create",
            { square = square }, player)
        if SC.Guidance then
            SC.Guidance.control(option,"camp",menu,true)
            local hint=SC.Guidance.tip("camp")
            if hint then SC.ContextMenu.hint(option,hint) end
        end
        return true
    end
    addCleanStainOption(menu, square, player)
    local layoutShown = SC.BaseVisuals and type(SC.BaseVisuals.status) == "function"
        and SC.BaseVisuals.status().enabled == true
    menu:addOption(text(layoutShown and "UI_SC_Base_Visual_Hide" or "UI_SC_Base_Visual_Show"),
        nil, toggleBaseLayout, player)
    if SC.BaseWatch and SC.BaseWatch.isRemote
        and SC.BaseWatch.isRemote(type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or player) then
        addUnavailableOption(menu, text("UI_SC_BaseWatch_RadioOnly"))
        return true
    end
    local areas = Menus.group(menu, "camp.areas", text("UI_SC_Context_Areas"))
    local mappedRoom = safeMethod(square, "getRoomDef")
    if not mappedRoom then
        local unavailable = addUnavailableOption(areas, text("UI_SC_Base_MarkRoom"))
        if unavailable and type(ISToolTip) == "table" then
            local tooltip = ISToolTip:new()
            tooltip.description = text("UI_SC_Base_Reason_room_unavailable")
            unavailable.toolTip = tooltip
        end
    else
        local roomOption = areas:addOption(text("UI_SC_Base_MarkRoom"), nil, nil)
        local roomMenu = ISContextMenu:getNew(areas)
        areas:addSubMenu(roomOption, roomMenu)
        for _, kind in ipairs({ "area", "work", "rest", "social", "guard", "rally", "quarantine" }) do
            local available, reason = SC.BaseLife.roomMarkPreview(square, kind)
            local option = roomMenu:addOption(text(kind == "area"
                    and "UI_SC_Base_RoomZone_area" or "UI_SC_Base_Zone_" .. kind), nil,
                baseAction, "room_mark", { square = square, kind = kind }, player)
            if not available and option then
                option.notAvailable = true
                if type(ISToolTip) == "table" then
                    local tooltip = ISToolTip:new()
                    tooltip.description = SC.UI and SC.UI.baseFailureReason
                        and SC.UI.baseFailureReason(reason) or tostring(reason)
                    option.toolTip = tooltip
                end
            end
        end
    end
    if layoutShown then
        -- Ask BaseLife for every refusal rule, not only the last boundary: a
        -- zone pinned by an order or holding other zones would otherwise
        -- offer an option that fails after its confirmation.
        for _, zone in ipairs(zonesAtSquare(square)) do
            local name = zone.name or zone.kind or zone.id
            local removable, refusal = SC.BaseLife.canRemoveZone(zone.id)
            if removable == true then
                areas:addOption(text("UI_SC_Base_RemoveZone", name),
                    nil, removeZoneFromContext, zone, player)
            elseif refusal == "last_base_area" then
                addUnavailableOption(areas, text("UI_SC_Base_LastAreaMenu"))
            else
                addUnavailableOption(areas, text(refusal == "base_area_in_use"
                        and "UI_SC_Base_AreaInUseMenu"
                    or (refusal == "work_order_uses_zone"
                        or refusal == "production_order_uses_zone")
                        and "UI_SC_Base_ZoneBusyMenu"
                    or "UI_SC_Base_ZoneLockedMenu", name))
            end
        end
    end
    local draft = SC.BaseLife.zoneDraft()
    local inside = type(SC.BaseLife.isInside) == "function"
        and SC.BaseLife.isInside(square) == true
    if draft then
        menu:addOption(text("UI_SC_Base_CancelZone"), nil, baseAction, "zone_cancel", {}, player)
    else
        local zoneOption = areas:addOption(text("UI_SC_Base_StartZone"), nil, nil)
        local zoneMenu = ISContextMenu:getNew(areas)
        areas:addSubMenu(zoneOption, zoneMenu)
        -- Outside the camp only bounded reach zones may start, inside
        -- the bounded reach band around the camp.
        local upstairsArea = type(SC.BaseLife.mayExtendAreaToFloor) == "function"
            and SC.BaseLife.mayExtendAreaToFloor(square) == true
        local parkingCorner = type(SC.BaseLife.parkingCornerRelevant) == "function"
            and SC.BaseLife.parkingCornerRelevant(square) == true
        local kinds = inside and { "area", "work", "sorting_floor", "trash_pile", "lumber", "log_yard", "farm", "fishing", "burial", "pyre", "rest",
            "social", "guard", "rally", "quarantine" }
            or upstairsArea and { "area" }
            or { "lumber", "log_yard", "farm", "fishing", "burial", "pyre" }
        if parkingCorner then kinds[#kinds + 1] = "parking" end
        for _, kind in ipairs(kinds) do
            zoneMenu:addOption(text("UI_SC_Base_Zone_" .. kind), nil, baseAction, "zone_begin",
                { square = square, kind = kind }, player)
        end
    end
    local construction = Menus.group(menu, "camp.construction", text("UI_SC_Context_Construction"))
    if inside and barricadeTarget then
        construction:addOption(text("UI_SC_Base_MaintainBarricade"), nil, baseAction, "maintenance",
            { object = barricadeTarget, kind = "barricade" }, player)
        construction:addOption(text("UI_SC_Base_PlanBarricade"), nil,
            startBarricadePlan, barricadeTarget, player)
    end
    if inside then
        local buildOption = construction:addOption(text("UI_SC_Base_QueueBuild"), nil, nil)
        local buildMenu = ISContextMenu:getNew(construction)
        construction:addSubMenu(buildOption, buildMenu)
        for _, kind in ipairs({ "wall_frame", "wall", "floor", "door_frame", "door" }) do
            buildMenu:addOption(text("UI_SC_Base_Build_" .. kind), nil,
                startConstruction, kind, player)
        end
        local plans = SC.BaseLife.constructionAt(square)
        for _, job in ipairs(plans) do
            local label = text("UI_SC_Base_Blueprint_Row",
                text("UI_SC_Base_Build_" .. tostring(job.buildKind or job.type)),
                tostring(job.state), tostring(job.id))
            local planOption = construction:addOption(label, nil, nil)
            local planMenu = ISContextMenu:getNew(construction)
            construction:addSubMenu(planOption, planMenu)
            if job.type == "build" and job.state ~= "manual" then
                planMenu:addOption(text("UI_SC_Base_Blueprint_Build"), nil,
                    buildBlueprint, job.id, player)
            end
            if job.state == "blocked" then
                planMenu:addOption(text("UI_SC_Base_Blueprint_Retry"), nil,
                    manageBlueprint, "retry", job.id, player)
            end
            if job.state ~= "manual" then
                planMenu:addOption(text("UI_SC_Base_Blueprint_Cancel"), nil,
                    manageBlueprint, "cancel", job.id, player)
            end
        end
    end
    menu:addOption(text("UI_SC_Base_Abandon"), nil, abandonBaseFromContext, player)
    if inside and containerTarget then
        local storageMenu = Menus.group(menu, "camp.storage", text("UI_SC_Base_MarkStorage"))
        for _, category in ipairs({ "food", "fresh_food", "water", "medical", "tools", "construction",
            "crafting", "literature", "weapons", "ammunition", "clothing", "valuables", "general", "output",
            "memorial", "farming" }) do
            storageMenu:addOption(text("UI_SC_Base_Storage_" .. category), nil, baseAction,
                "storage", { object = containerTarget, category = category }, player)
        end
    end
    if storage then
        Menus.action(menu, "camp.storage.unmark", text("UI_SC_Base_UnmarkStorage"), nil,
            removeStorageFromContext, storage, player)
    end
    return true
end

local function contextRow(actor, player, states)
    local id = SC.Registry and SC.Registry.idOf and SC.Registry.idOf(actor)
    local record = id and SC.Registry.byId and SC.Registry.byId(id)
    if not record or record.actor ~= actor or safeMethod(actor, "isDead") == true then return nil end
    local ax, ay = tonumber(safeMethod(actor, "getX")), tonumber(safeMethod(actor, "getY"))
    local px, py = tonumber(safeMethod(player, "getX")), tonumber(safeMethod(player, "getY"))
    if not ax or not ay or not px or not py then return nil end
    local distance = math.sqrt((ax-px)^2 + (ay-py)^2)
    if distance > Context.maximumShortcutDistance then return nil end
    if SC.TaxiService and SC.TaxiService.isDriver and SC.TaxiService.isDriver(actor) then return nil end
    local state = states and states[actor]
        or SC.Commands and SC.Commands.peekExisting and SC.Commands.peekExisting(actor) or {}
    local name = safeMethod(actor, "getFullName") or record.name or safeMethod(actor, "getDisplayName")
        or text("UI_SC_Value_UnknownCompanion")
    if SC.UI and SC.UI.displayName then name = SC.UI.displayName(record, name) end
    local faction=record.factionId and SC.Factions and SC.Factions.group and SC.Factions.group(record.factionId)
    local hostile=state.hostileToPlayer==true or type(state.care)=="table" and state.care.playerHostile==true
        or faction and (faction.standing=="Hostile" or faction.lifecycle=="hostile" or faction.permanentHostility==true)
    return { id = id, actor = actor, name = name, recruited = record.recruited == true,
        alive = true, available = true, distance = distance, group = state.group or record.group,
        order = state.order, factionId = record.factionId, factionMember = record.factionMember,
        factionStanding=faction and faction.standing, hostile=hostile==true }
end

local function nearbyRows(player)
    local rows, talkRows, states = {}, {}, {}
    local living = SC.Registry and SC.Registry.living and SC.Registry.living() or {}
    for _, entry in pairs(living) do
        local actor = type(entry) == "table" and entry.actor or entry
        if actor then
            states[actor] = SC.Commands and SC.Commands.peekExisting and SC.Commands.peekExisting(actor) or {}
            local row = contextRow(actor, player, states)
            if row then
                if row.recruited then rows[#rows+1] = row end
                local story = not row.recruited and SC.Oddballs and SC.Oddballs.groupForActor
                    and SC.Oddballs.groupForActor(actor)
                if row.recruited or story or not row.hostile then
                    talkRows[#talkRows+1] = row
                end
            end
        end
    end
    local function byName(a,b)
        if a.name == b.name then return tostring(a.id) < tostring(b.id) end
        return string.lower(tostring(a.name)) < string.lower(tostring(b.name))
    end
    table.sort(rows, byName) table.sort(talkRows, byName)
    return rows, talkRows, living, states
end

local function openTalkFromContext(_, row)
    if not currentRecord(row, getSpecificPlayer and getSpecificPlayer(0)) then return end
    if SC.UI and type(SC.UI.open) == "function" then
        SC.UI.open("talk", row.id)
    end
end

local function addTalkFromContext(menu, row, player, label)
    local group
    if row.recruited ~= true and SC.Oddballs then
        if type(SC.Oddballs.groupForActor) == "function" then
            group = SC.Oddballs.groupForActor(row.actor)
        end
        if not group and SC.Factions and type(SC.Factions.list) == "function" then
            -- A legacy actor record can lack faction flags. The saved member
            -- identity still identifies its authored conversation correctly.
            for _, candidate in ipairs(SC.Factions.list(false) or {}) do
                for _, member in ipairs(candidate.members or {}) do
                    if member.actorId == row.id then group = candidate break end
                end
                if group then break end
            end
        end
    end
    local key = "talk:" .. row.id
    if group and group.oddball then
        local option = Menus.action(menu, key, label, nil, nil)
        local options = group.lifecycle ~= "destroyed" and SC.Oddballs.menuOptions
            and SC.Oddballs.menuOptions(group, player) or {}
        if #options == 0 then
            Menus.reason(option, text("UI_SC_Oddball_NoAction"))
            return option, true
        end
        local choices = Menus.group(menu, key, label)
        addOddballStoryChoices(choices, group, player, row, options)
        return option, true
    end
    return Menus.action(menu, key, label, nil, openTalkFromContext, row), false
end

local function openOrdersFromContext(_, row)
    if not currentRecord(row, getSpecificPlayer and getSpecificPlayer(0)) then return end
    if SC.UI and type(SC.UI.open) == "function" then
        SC.UI.open("orders", row.id)
    end
end

local function addInteractionShortcut(menu, row, action, player, named)
    if action == "send_home" then
        if Context.addHomeTripShortcut then Context.addHomeTripShortcut(menu, row, player) end
        return
    end
    local descriptor = SC.Interaction.descriptor(action)
    if not descriptor then return end
    local label = named and text("UI_SC_Context_QuickNamed", row.name, text(descriptor.key)) or text(descriptor.key)
    local available, reason, argument = SC.Interaction.availability(row, action, player)
    local option = Menus.action(menu, "leaf:" .. row.id .. ":" .. action, label, row,
        available and issueFromContext or nil, row.id, action, nil, player)
    if not available then Menus.reason(option, argument and text(reason, argument) or text(reason)) end
    if row.order == action and type(menu.setOptionChecked) == "function" then menu:setOptionChecked(option, true) end
    return option
end

local function addObjectiveAssignments(menu, row, player)
    if row.recruited ~= true or not SC.Objectives
        or type(SC.Objectives.assignableKinds) ~= "function" then return end
    local state = SC.Commands and type(SC.Commands.peekExisting) == "function"
        and SC.Commands.peekExisting(row.actor) or nil
    local kinds = SC.Objectives.assignableKinds(row.actor, state)
    if type(kinds) ~= "table" or #kinds == 0 then return end
    local category = addCategory(menu, "UI_SC_Context_AssignObjective")
    for _, kind in ipairs(kinds) do
        category:addOption(SC.Objectives.label(kind), row, issueFromContext,
            row.id, "assign_objective", { kind = kind }, player)
    end
end

local function addOrdersShortcut(menu, row, player)
    menu:addOption(text("UI_SC_Talk_OpenOrders"), nil,
        openOrdersFromContext, row)
    if safeMethod(row.actor, "getVehicle") and SC.Vehicle and SC.Vehicle.statusFor then
        local car = safeMethod(row.actor, "getVehicle")
        local speed = tonumber(safeMethod(car, "getCurrentSpeedKmHour"))
        row.vehicleStatus = { status = "in_vehicle", canExitNow = speed ~= nil and math.abs(speed) < .1 }
    end
    if type(row.vehicleStatus) == "table"
        and row.vehicleStatus.status == "in_vehicle"
        and row.vehicleStatus.canExitNow == true then
        addCommand(menu, "UI_SC_Action_ExitVehicleNow", row.id,
            "exit_vehicle", nil, player)
    end
end

local function addWorldOrders(menu, row, targetSquare, targetPayload, door, doorPayload,
        barricadeTarget, barricadePayload, removeBarricadeTarget,
        removeBarricadePayload, dismantleTarget, dismantlePayload, combatTarget, player)
    if targetPayload then
        addCommand(menu, "UI_SC_Action_MoveHere", row.id, "move_to", targetPayload, player)
        addCommand(menu, "UI_SC_Action_GuardHere", row.id, "guard",
            { target = targetPayload }, player)
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
    if combatTarget then
        addCommand(menu, "UI_SC_Action_DesignateTarget", row.id, "designate_target",
            { target = combatTarget }, player)
        addCommand(menu, "UI_SC_Action_AvoidTarget", row.id, "avoid_target",
            { target = combatTarget }, player)
    end
end

local function clickedCompanionRow(rows, worldObjects, clickSquare)
    local matches = {}
    for _, row in ipairs(rows or {}) do
        for _, object in ipairs(worldObjects or {}) do
            if row.actor == object then matches[#matches + 1] = row; break end
        end
    end
    if #matches == 1 then return matches[1], matches end
    if #matches > 1 then return nil, matches end
    if clickSquare then
        for _, row in ipairs(rows or {}) do
            if safeMethod(row.actor, "getSquare") == clickSquare then
                matches[#matches + 1] = row
            end
        end
    end
    return #matches == 1 and matches[1] or nil, matches
end

local function addWatchControl(menu, row, player)
    local status = SC.ViewControl and type(SC.ViewControl.status) == "function"
        and SC.ViewControl.status() or {}
    if status.watching == true
        and (status.watchId == row.id or status.watchActor == row.actor) then
        menu:addOption(text("UI_SC_Action_StopWatching"), nil,
            stopWatchingFromContext, player)
    else
        menu:addOption(text("UI_SC_Action_Watch", row.name), nil,
            watchFromContext, row, player)
    end
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

-- Mirror vanilla's vehicle picker so a click on a car's body resolves that
-- car, even where its origin square is elsewhere in the footprint.
function Context.vehicleAtClick(square)
    local vehicle = square and safeMethod(square, "getVehicleContainer") or nil
    if vehicle then return vehicle end
    if IsoObjectPicker and IsoObjectPicker.Instance
        and type(getMouseXScaled) == "function"
        and type(getMouseYScaled) == "function" then
        local ok, picked = pcall(function()
            return IsoObjectPicker.Instance:PickVehicle(
                getMouseXScaled(), getMouseYScaled())
        end)
        if ok then return picked end
    end
    return nil
end

local function hotwireFromContext(_target, row, vehicle, player)
    if not row or not vehicle or not SC.Commands then return end
    if not currentRecord(row, player) then return end
    local ok, accepted, reason = pcall(SC.Commands.issue, row.id,
        "hotwire_vehicle", { vehicle = vehicle }, player)
    if player then
        safeMethod(player, "setHaloNote", ok and accepted == true
            and text("UI_SC_Vehicle_HotwireOrdered", row.name)
            or text("UI_SC_Vehicle_HotwireRejected", tostring(reason or accepted)))
    end
end

local function addHotwireMenu(context, rows, vehicle, player)
    if not vehicle or not SC.VehicleHotwire
        or type(SC.VehicleHotwire.canHotwire) ~= "function" then return end
    local eligible = {}
    for _, row in ipairs(rows or {}) do
        local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(row.id)
        if row.recruited == true and record and record.actor
            and SC.VehicleHotwire.canHotwire(record.actor) then
            eligible[#eligible + 1] = row
        end
    end
    if #eligible == 0 then return end
    local hotOk, hot = pcall(function() return vehicle:isHotwired() end)
    if not hotOk or hot then return end
    local root = addCategory(context, "UI_SC_Vehicle_CommandHotwire")
    for _, row in ipairs(eligible) do
        root:addOption(row.name, nil, hotwireFromContext, row, vehicle, player)
    end
end

-- A refusal is shown as a sentence, never as an internal reason code.
local function reasonSentence(reason)
    if SC.UI and type(SC.UI.baseFailureReason) == "function" then
        return SC.UI.baseFailureReason(reason)
    end
    return tostring(reason)
end

local function disableWithReason(option, reason)
    return Menus.reason(option, reasonSentence(reason))
end

function Context.openHomeTrip(_target, row)
    local record = currentRecord(row, getSpecificPlayer and getSpecificPlayer(0))
    if not record then return false end
    if SC.UIHomeTrip then return SC.UIHomeTrip.openSheet({ record = record or row }) end
    return false
end

function Context.addHomeTripShortcut(menu, row, player, popupFacts)
    local home = SC.HomeTrip
    if not home or not home.eligibility or not row then return end
    local record = SC.Registry and SC.Registry.byId and SC.Registry.byId(row.id)
    local status = home.eligibility({ record = record or row }, popupFacts)
    if status.hidden then return end
    local option = menu:addOption(text("UI_SC_HomeTrip_Menu"), nil, Context.openHomeTrip, row)
    if SC.Guidance then
        SC.Guidance.control(option,"send_home",menu,true)
        local hint=SC.Guidance.tip("send_home")
        if hint then SC.ContextMenu.hint(option,hint) end
    end
    if not status.canStart then
        disableWithReason(option, home.reasonText(status.blocker or status.reason, row.name))
    end
    return option
end

function Context.openHomeTripCar(_target, selection)
    if SC.UIHomeTrip then return SC.UIHomeTrip.openSheet(selection) end
    return false
end

function Context.addHomeTripCarMenu(context, vehicle, player, living, states, popupFacts)
    local home = SC.HomeTrip
    if not vehicle or not home or not home.eligibility or not SC.Registry or not SC.Registry.living then return end
    local x, y = tonumber(safeMethod(vehicle, "getX")), tonumber(safeMethod(vehicle, "getY"))
    if not x or not y then return end
    local sqlId = safeMethod(vehicle, "getSqlId")
    local carName = SC.ExpeditionCar and SC.ExpeditionCar.displayName and SC.ExpeditionCar.displayName(vehicle)
    local choices, groups, near = {}, {}, false
    for _, actor in ipairs(living or SC.Registry.living() or {}) do
        local data = safeMethod(actor, "getModData")
        local id = type(data) == "table" and data.SC_Id or nil
        local record = id and SC.Registry.byId(id)
        if record and record.recruited == true then
            local state = states and states[actor]
                or SC.Commands and SC.Commands.peekExisting and SC.Commands.peekExisting(actor) or {}
            if state.group and state.group ~= "" then
                groups[state.group] = groups[state.group] or {}
                local captured = {}
                for key, value in pairs(record) do captured[key] = value end
                groups[state.group][#groups[state.group] + 1] = captured
            end
            local ax, ay = tonumber(safeMethod(actor, "getX")), tonumber(safeMethod(actor, "getY"))
            if (state.order == "follow" or state.order == "regroup") and ax and ay
                and (ax - x)^2 + (ay - y)^2 <= 30 * 30 then
                near = true
                local captured = {}
                for key, value in pairs(record) do captured[key] = value end
                local selection = { record = captured, travelMode = "drive", vehicle = vehicle,
                    vehicleSqlId = sqlId, vehicleName = carName, leaderId = id }
                local status = home.eligibility(selection, popupFacts)
                if not status.hidden then
                    local name = safeMethod(actor, "getFullName") or record.name or text("UI_SC_HomeTrip_Member")
                    choices[#choices + 1] = { label = SC.UI and SC.UI.displayName and SC.UI.displayName(record, name) or name,
                        selection = selection, status = status }
                end
            end
        end
    end
    if not near then return end
    for _, group in ipairs({ "alpha", "bravo", "charlie" }) do
        if groups[group] then
            local selection = { records = groups[group], travelMode = "drive", vehicle = vehicle, vehicleSqlId = sqlId }
            local status = home.eligibility(selection, popupFacts)
            if not status.hidden and #(status.records or {}) > 0 then
                local label = text("UI_SC_Select_Group" .. string.upper(string.sub(group, 1, 1)) .. string.sub(group, 2))
                choices[#choices + 1] = { label = text("UI_SC_HomeTrip_GroupCount", label, #status.records), status = status,
                    selection = { group = group, records = groups[group], travelMode = "drive", vehicle = vehicle, vehicleSqlId = sqlId,
                        vehicleName = carName, leaderId = status.leaderId } }
            end
        end
    end
    if #choices == 0 then return end
    local root = addCategory(context, "UI_SC_HomeTrip_CarMenu")
    for _, choice in ipairs(choices) do
        local option = root:addOption(choice.label, nil, Context.openHomeTripCar, choice.selection)
        if not choice.status.canStart then
            disableWithReason(option, home.reasonText(choice.status.blocker or choice.status.reason, choice.label))
        end
    end
    return root
end

local function convoyFromContext(_target, row, vehicle, player, cancel)
    if not currentRecord(row, player) then return end
    local command = cancel and "cancel_follow_car" or "assign_follow_car"
    local accepted, reason = SC.Commands.issue(row.id, command,
        cancel and nil or { vehicle = vehicle }, player)
    if player then
        safeMethod(player, "setHaloNote", accepted
            and text(cancel and "UI_SC_Vehicle_FollowCarCancelled"
                or "UI_SC_Vehicle_FollowCarAssigned", row.name)
            or text("UI_SC_Vehicle_FollowCarRejected", reasonSentence(reason)))
    end
end

local function addConvoyMenu(context, rows, vehicle, player, popupFacts)
    if not vehicle or not SC.Convoy or not SC.Commands then return end
    local recruited = {}
    for _, row in ipairs(rows or {}) do
        if row.recruited == true then recruited[#recruited + 1] = row end
    end
    -- Nobody nearby could take the wheel: no empty submenu on every car.
    if #recruited == 0 then return end
    local root = addCategory(context, "UI_SC_Vehicle_CommandFollowCar")
    local carId = safeMethod(vehicle, "getSqlId")
    for _, row in ipairs(recruited) do
        local actor = SC.Registry.byId(row.id)
        actor = actor and actor.actor or nil
        local state = actor and SC.Commands.peekExisting and SC.Commands.peekExisting(actor) or nil
        local assigned = state and tonumber(state.followCarSqlId) == tonumber(carId)
        if assigned then
            root:addOption(text("UI_SC_Vehicle_CancelFollowCar", row.name), nil,
                convoyFromContext, row, vehicle, player, true)
        else
            local available, reason = SC.Convoy.preflight(actor, vehicle, player, popupFacts)
            local option = root:addOption(row.name, nil,
                convoyFromContext, row, vehicle, player, false)
            if not available then disableWithReason(option, reason) end
        end
    end
end

-- A camp chore belongs on a car or generator the camp can reach. Leave it out
-- elsewhere rather than greying it out on every vehicle in the world.
local CHORE_OUT_OF_SCOPE = {
    base_missing = true, service_cab_reserved = true,
    car_identity_unavailable = true, car_out_of_camp_reach = true,
    generator_missing = true, generator_outside_base = true,
    generator_identity_unavailable = true,
}

local function addChoreOption(context, labelKey, eligible, reason, callback, ...)
    if not eligible and CHORE_OUT_OF_SCOPE[reason] then return nil end
    local option = context:addOption(text(labelKey), nil, callback, ...)
    if not eligible then disableWithReason(option, reason) end
    return option
end

local function unloadVehicleFromContext(_target, vehicleId, player)
    local okay, accepted, reason = pcall(SC.VehicleUnload.queue, vehicleId)
    if player then
        safeMethod(player, "setHaloNote", okay and accepted == true
            and text("UI_SC_Base_UnloadOrdered")
            or text("UI_SC_Base_ActionFailed", tostring(reason or accepted)))
    end
end

local function refuelVehicleFromContext(_target, vehicleId, player)
    local okay, accepted, reason = pcall(SC.VehicleRefuel.queue, vehicleId, true)
    if player then
        safeMethod(player, "setHaloNote", okay and accepted == true
            and text("UI_SC_Base_RefuelOrdered")
            or text("UI_SC_Base_ChoreRejected", reasonSentence(reason or accepted)))
    end
end

local function upkeepVehicleFromContext(_target, kind, vehicleId, player)
    local okay, accepted, reason = pcall(SC.VehicleUpkeep.queue,
        kind, vehicleId, true)
    if player then
        safeMethod(player, "setHaloNote", okay and accepted == true
            and text("UI_SC_Base_UpkeepOrdered")
            or text("UI_SC_Base_ChoreRejected", reasonSentence(reason or accepted)))
    end
end

local function refuelGeneratorFromContext(_target, generator, player)
    local okay, accepted, reason = pcall(SC.GeneratorRefuel.queue,
        generator, true)
    if player then
        safeMethod(player, "setHaloNote", okay and accepted == true
            and text("UI_SC_Base_GeneratorRefuelOrdered")
            or text("UI_SC_Base_ChoreRejected", reasonSentence(reason or accepted)))
    end
end

local function addNamedShortcut(context, row, labelKey, command, payload, player)
    local label = text("UI_SC_Context_NamedAction", row.name, text(labelKey))
    local option = Menus.action(context, "leaf:" .. row.id .. ":" .. command,
        label, row, issueFromContext, row.id, command, payload, player)
    option.scLFWorld = true
    return option
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

local function fieldAction(_target, kind, square, player)
    local ok, reason = SC.FieldWork.start(kind, square, player)
    local message = reason == "field_order_started"
            and text("UI_SC_Field_WorkStarted")
        or reason == "field_trunk_unlocking"
            and text("UI_SC_Field_UnlockingTrunk")
        or reason == "car_trunk_locked_carry_only"
            and text("UI_SC_Field_CarryFallback")
        or reason == "car_trunk_locked_axe_required"
            and text("UI_SC_Field_LockedAxeRequired")
        or reason == "axe_required_without_car"
            and text("UI_SC_Field_AxeRequired")
        or tostring(reason)
    safeMethod(player, "setHaloNote", text(ok and "UI_SC_Field_Started"
        or "UI_SC_Field_Rejected", message))
    if SC.UI and SC.UI.refresh then SC.UI.refresh() end
end

local function addSquadMenu(menu, player, square, fieldFacts)
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
    if square and SC.FieldWork and SC.FieldWork.available(player, nil, fieldFacts) then
        local status = SC.FieldWork.status()
        if status and (status.phase == "working" or status.phase == "unlocking"
            or status.phase == "paused") then
            menu:addOption(text("UI_SC_Field_Stop"), nil, function()
                SC.FieldWork.stop("stopped_by_player")
                if SC.UI and SC.UI.refresh then SC.UI.refresh() end
            end)
            if status.phase == "paused" then
                menu:addOption(text("UI_SC_Field_Resume"), nil, function()
                    local ok, reason = SC.FieldWork.resume()
                    safeMethod(player, "setHaloNote", text(ok and "UI_SC_Field_Started"
                        or "UI_SC_Field_Rejected", tostring(reason)))
                end)
            end
        else
            if SC.FieldWork.available(player, "harvest", fieldFacts) then
                menu:addOption(text("UI_SC_Field_Harvest"), nil,
                    fieldAction, "harvest", square, player)
            end
            if SC.FieldWork.available(player, "chop", fieldFacts) then
                menu:addOption(text("UI_SC_Field_Chop"), nil,
                    fieldAction, "chop", square, player)
            end
        end
    end
end

local function namedGraveMarker(worldObjects)
    for _, object in ipairs(worldObjects or {}) do
        local data = safeMethod(object, "getModData")
        if type(data) == "table" and data.LF_FallenMarker == true then
            local name = data.LF_FallenDisplayName or data.LF_FallenName
            if type(name) == "string" and name ~= "" then return name end
        end
    end
    return nil
end

local function personMenu(parent, row, player, popup, direct)
    local menu = Menus.group(parent, "person:" .. row.id, row.name)
    if not direct then
        addTalkFromContext(menu, row, player, text("UI_SC_Talk_Open"))
    end
    if row.recruited ~= true then return menu end
    addOrdersShortcut(menu, row, player)
    addInteractionShortcut(menu, row, "regroup", player)
    Context.addHomeTripShortcut(menu, row, player, popup.homeFacts)
    if not (popup.watch.watching and (popup.watch.watchId == row.id or popup.watch.watchActor == row.actor)) then
        addWatchControl(menu, row, player)
    end
    addCommand(menu, "UI_SC_Action_OpenInventory", row.id, "open_inventory", nil, player)
    if not popup.medical or popup.medical ~= row.actor then
        addCommand(menu, "UI_SC_Action_OpenHealth", row.id, "open_health", nil, player)
    end
    addCare(menu, row, player)
    if not direct then
        addInteractionShortcut(menu, row, "follow", player)
        addInteractionShortcut(menu, row, "stay", player)
        addInteractionShortcut(menu, row, "retreat", player)
    end
    if popup.location then
        local target = Menus.group(menu, "location:" .. row.id, text("UI_SC_Context_TargetActions"))
        addWorldOrders(target, row, popup.square, popup.targetPayload, popup.door, popup.doorPayload,
            popup.barricade, popup.barricadePayload, popup.removeBarricade, popup.removePayload,
            popup.dismantle, popup.dismantlePayload, popup.combatTarget, player)
    end
    local tasks = Menus.group(menu, "tasks:" .. row.id, text("UI_SC_Context_Tasks"))
    addObjectiveAssignments(tasks, row, player)
    addChefOrder(tasks, row, player)
    addRecruitedOddballAction(tasks, row, player)
    local personal = Menus.group(menu, "personal:" .. row.id, text("UI_SC_Context_Personal"))
    addNicknameActions(personal, row, player)
    addCommand(personal, "UI_SC_Action_Dismiss", row.id, "dismiss", nil, player)
    return menu
end

local function contextProbe(player, context, objects)
    -- Controller availability probes must not initialize command state or run
    -- inventory/route preflights merely to advertise a possible LF action.
    local rows, talkRows, living, states = nearbyRows(player)
    local relevant = #rows > 0 or #talkRows > 0
    for _, object in ipairs(objects or {}) do
        local id = SC.Registry and SC.Registry.idOf and SC.Registry.idOf(object)
        local record = id and SC.Registry.byId and SC.Registry.byId(id)
        if record and record.actor == object then relevant = true end
        if SC.Terminal and SC.Terminal.isComputer and SC.Terminal.isComputer(object) then relevant = true end
        if safeMethod(object, "getVehicleContainer") or safeMethod(object, "getGenerator") then relevant = true end
        if SC.GameplayUtil and (SC.GameplayUtil.instanceOf(object, "IsoGenerator")
            or SC.GameplayUtil.instanceOf(object, "BaseVehicle")) then relevant = true end
    end
    local square = objects and objects[1] and safeMethod(objects[1], "getSquare")
    relevant = relevant or baseMenuRelevant(square)
        or SC.ViewControl and SC.ViewControl.status and SC.ViewControl.status().watching == true
        or namedGraveMarker(objects) ~= nil or #talkableFactions(player) > 0 or #talkableOddballs(player) > 0
        or SC.FieldWork and square and SC.FieldWork.available(player, nil, { living = living, states = states }) == true
        or Context.vehicleAtClick(square) ~= nil
    if not relevant and SC.Oddballs and SC.Oddballs.sealedDoorGroup then
        for _, object in ipairs(objects or {}) do
            if SC.Oddballs.sealedDoorGroup(object, player) then relevant = true break end
        end
    end
    if relevant and ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
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
    if test == true then return contextProbe(player, context, worldObjects) end
    Menus.removeOwned(context, function(option) return option.scLFWorld == true end)
    local medicalOption = Context.ensureCompanionMedicalOption(context, worldObjects, player)
    -- Camp computers work with or without companions, so this runs before
    -- the early return for menus with nothing else of ours on them.
    if test ~= true and SC.Terminal
        and type(SC.Terminal.fillWorldObjectContextMenu) == "function" then
        local ok, failure = pcall(SC.Terminal.fillWorldObjectContextMenu,
            playerIndex, context, worldObjects, player)
        if not ok and SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
            SC.Diagnostics.report("terminal", nil, "computer menu failed", failure)
        end
    end
    local memorialName = namedGraveMarker(worldObjects)
    local square, door, targetPayload, doorPayload, barricadeTarget, barricadePayload,
        containerTarget, removeBarricadeTarget, removeBarricadePayload,
        dismantleTarget, dismantlePayload, combatTarget = findTarget(worldObjects, player)
    local clickSquare = clickedWorldSquare(playerIndex, context, player, square)
    if clickSquare then
        square = clickSquare
        targetPayload = squarePayload(clickSquare) or targetPayload
        if combatTarget == nil and SC.GameplayUtil
            and type(SC.GameplayUtil.squareMovingObjects) == "function" then
            SC.GameplayUtil.squareMovingObjects(clickSquare, function(value)
                if SC.GameplayUtil.isZombie(value)
                    and not SC.GameplayUtil.isGoneTarget(value) then
                    combatTarget = value
                    return false
                end
            end, 16)
        end
    end
    local rows, talkRows, living, states = nearbyRows(player)
    local fieldFacts = { living = living, states = states }
    local fieldAvailable = clickSquare and SC.FieldWork
        and SC.FieldWork.available(player, nil, fieldFacts) == true
    local clickedVehicle = Context.vehicleAtClick(clickSquare)
    local clickedGenerator = clickSquare and safeMethod(clickSquare,
        "getGenerator") or nil
    if not clickedGenerator then
        for _, object in ipairs(worldObjects or {}) do
            if SC.GameplayUtil.instanceOf(object, "IsoGenerator") then
                clickedGenerator = object
                break
            end
        end
    end
    local riddenCar = safeMethod(player, "getVehicle")
    local taxiRide = playerIndex == 0 and riddenCar ~= nil
        and SC.TaxiService and type(SC.TaxiService.isBookedPassenger) == "function"
        and SC.TaxiService.isBookedPassenger(player, riddenCar) == true
        and type(SC.TaxiService.current) == "function"
        and (SC.TaxiService.current() or {}).phase == "ready_to_depart"
    local clickedCompanion, clickedMatches = clickedCompanionRow(talkRows, worldObjects, clickSquare)
    local factions = talkableFactions(player)
    local oddballs = talkableOddballs(player)
    local sealedDoorGroup = SC.Oddballs
        and type(SC.Oddballs.sealedDoorGroup) == "function"
        and SC.Oddballs.sealedDoorGroup(door, player) or nil
    local baseRelevant = baseMenuRelevant(clickSquare) or storageForObject(containerTarget) ~= nil
    local watchStatus = SC.ViewControl and type(SC.ViewControl.status) == "function"
        and SC.ViewControl.status() or {}
    if #rows == 0 and #factions == 0 and #oddballs == 0 and not baseRelevant
        and watchStatus.watching ~= true and not clickedCompanion
        and not (clickedMatches and #clickedMatches > 1)
        and not memorialName and not sealedDoorGroup and not clickedVehicle
        and not clickedGenerator
        and not taxiRide and not fieldAvailable then return end
    if test and ISWorldObjectContextMenu and ISWorldObjectContextMenu.setTest then
        return ISWorldObjectContextMenu.setTest()
    end
    local rootMenu = Menus.group(context, "lf", text("UI_SC_Context_LivingFellows"))
    for _, option in ipairs(context.options) do
        if option.scLFContext and option.scMenuKey == "lf" then option.scLFWorld = true end
    end
    local homeFacts = (#rows > 0 or clickedVehicle) and SC.HomeTrip and SC.HomeTrip.popupFacts and SC.HomeTrip.popupFacts() or nil
    local vehicleMenu = clickedVehicle and Menus.group(rootMenu, "vehicle", text("UI_SC_Context_ThisVehicle"))
    local generatorMenu = clickedGenerator and Menus.group(rootMenu, "generator", text("UI_SC_Context_ThisGenerator"))
    if memorialName then
        local option = Menus.action(context, "memorial", text("UI_SC_Grave_Memorial", memorialName), nil, nil)
        option.scLFWorld = true
        if option then option.notAvailable = true end
    end
    if taxiRide then
        local menu = Menus.group(context, "world.taxi", text("UI_SC_Taxi_Menu"))
        for _, option in ipairs(context.options) do
            if option.scLFContext and option.scMenuKey == "world.taxi" then option.scLFWorld = true end
        end
        menu:addOption(text("UI_SC_Taxi_MapHint"), nil,
            function() safeMethod(player, "setHaloNote",
                text("UI_SC_Taxi_MapHintDetail")) end)
        local destinations = SC.TaxiService.destinations(player, nil) or {}
        for _, destination in ipairs(destinations) do
            menu:addOption(text("UI_SC_Taxi_DriveTo",
                tostring(destination.name),
                tostring(destination.required or "?")), nil,
                Context.taxiCabAction, player, "depart", destination.id)
        end
        local rows = SC.TaxiCab and SC.TaxiCab.looseItems(riddenCar) or nil
        for _, row in ipairs(rows or {}) do
            local value = SC.TaxiFares and SC.TaxiFares.valueFor(row.item)
            if value then
                menu:addOption(text("UI_SC_Taxi_Offer",
                    tostring(safeMethod(row.item, "getDisplayName")
                        or row.itemType), tostring(value)), nil,
                    Context.taxiCabAction, player, "offer", row.item)
            end
        end
    end
    if vehicleMenu then addHotwireMenu(vehicleMenu, rows, clickedVehicle, player) end
    if vehicleMenu then Context.addHomeTripCarMenu(vehicleMenu, clickedVehicle, player, living, states, homeFacts) end
    if vehicleMenu then addConvoyMenu(vehicleMenu, rows, clickedVehicle, player, SC.Convoy and SC.Convoy.popupFacts and SC.Convoy.popupFacts(living, states)) end
    if clickedVehicle and SC.VehicleUnload
        and type(SC.VehicleUnload.eligible) == "function"
        and SC.VehicleUnload.eligible(clickedVehicle) == true then
        local vehicleId = safeMethod(clickedVehicle, "getSqlId")
        if vehicleId then
            vehicleMenu:addOption(text("UI_SC_Base_UnloadToBase"), nil,
                unloadVehicleFromContext, vehicleId, player)
        end
    end
    local clickedVehicleId = clickedVehicle and safeMethod(clickedVehicle, "getSqlId")
    if clickedVehicleId and SC.VehicleRefuel
        and type(SC.VehicleRefuel.eligible) == "function" then
        local eligible, reason = SC.VehicleRefuel.eligible(clickedVehicle, true)
        addChoreOption(vehicleMenu, "UI_SC_Base_RefuelFromBase", eligible, reason,
            refuelVehicleFromContext, clickedVehicleId, player)
    end
    if clickedVehicleId and SC.VehicleUpkeep
        and type(SC.VehicleUpkeep.eligible) == "function" then
        for _, row in ipairs({
            { kind = "inflate_tires", key = "UI_SC_Base_InflateTires" },
            { kind = "wash_vehicle", key = "UI_SC_Base_WashCar" },
        }) do
            local eligible, reason = SC.VehicleUpkeep.eligible(row.kind,
                clickedVehicle, true)
            addChoreOption(vehicleMenu, row.key, eligible, reason,
                upkeepVehicleFromContext, row.kind, clickedVehicleId, player)
        end
    end
    if clickedGenerator and SC.GeneratorRefuel
        and type(SC.GeneratorRefuel.eligible) == "function" then
        local eligible, reason = SC.GeneratorRefuel.eligible(clickedGenerator, true)
        addChoreOption(generatorMenu, "UI_SC_Base_RefuelGeneratorFromBase", eligible,
            reason, refuelGeneratorFromContext, clickedGenerator, player)
    end
    if sealedDoorGroup then
        local option = Menus.action(context, "sealed_door", "Touch the sealed door", nil, oddballStoryAction,
            sealedDoorGroup.id, "touch_door", player)
        option.scLFWorld = true
    end
    local selected = selectedNearbyRow(rows)
    local medicalPatient = medicalOption and (medicalOption.onSelect == context.onGetUpAndThen
        and medicalOption.param4 or medicalOption.param2)
    if medicalPatient and (not clickedMatches or #clickedMatches <= 1) then
        clickedCompanion = contextRow(medicalPatient, player, states) or clickedCompanion
    end
    local ambiguous = clickedMatches and #clickedMatches > 1
    local primary = clickedCompanion or not ambiguous and selected or nil
    if watchStatus.watching == true then
        local option = Menus.action(context, "watch.stop", text("UI_SC_Action_StopWatchingNamed",
            companionName(watchStatus.watchId or "")), nil, stopWatchingFromContext, player)
        option.scLFWorld = true
    end
    if clickedCompanion then
        medicalOption = Context.ensureCompanionMedicalOption(context, worldObjects, player, clickedCompanion)
            or medicalOption
        medicalPatient = medicalOption and (medicalOption.onSelect == context.onGetUpAndThen
            and medicalOption.param4 or medicalOption.param2)
        local talk, storyTalk = addTalkFromContext(context, clickedCompanion, player,
            text("UI_SC_Talk_To", clickedCompanion.name))
        talk.scLFWorld = true
        if not storyTalk and SC.Interaction and SC.Interaction.descriptor and SC.Interaction.descriptor("doing") then
            local available, reason, argument = SC.Interaction.availability(clickedCompanion, "doing", player)
            if not available then Menus.reason(talk, argument and text(reason, argument) or text(reason)) end
        end
        if clickedCompanion.recruited then
            for _, action in ipairs({ "follow", "stay", "retreat" }) do
                local option = addInteractionShortcut(context, clickedCompanion, action, player, true)
                if option then option.scLFWorld = true end
            end
        end
    elseif not ambiguous and selected and targetPayload then
        addNamedShortcut(context, selected, "UI_SC_Action_MoveHere", "move_to", targetPayload, player)
        addPriorityShortcut(context, selected, square, door, doorPayload, barricadeTarget,
            barricadePayload, removeBarricadeTarget, removeBarricadePayload, dismantleTarget,
            dismantlePayload, player)
    end
    local popup = { homeFacts = homeFacts, watch = watchStatus, medical = medicalPatient,
        square = square, targetPayload = targetPayload, door = door, doorPayload = doorPayload,
        barricade = barricadeTarget, barricadePayload = barricadePayload,
        removeBarricade = removeBarricadeTarget, removePayload = removeBarricadePayload,
        dismantle = dismantleTarget, dismantlePayload = dismantlePayload, combatTarget = combatTarget,
        location = not clickedCompanion and not ambiguous }
    if primary then personMenu(rootMenu, primary, player, popup, clickedCompanion ~= nil) end
    if ambiguous then
        local choose = Menus.group(rootMenu, "choose", text("UI_SC_Talk_ChoosePerson"))
        for _, row in ipairs(clickedMatches) do personMenu(choose, row, player, popup, false) end
    else
        local nearby
        for _, row in ipairs(rows) do
            if not primary or row.id ~= primary.id then
                nearby = nearby or Menus.group(rootMenu, "nearby", text("UI_SC_Context_NearbyCompanions"))
                Menus.action(nearby, "orders:" .. row.id, row.name, nil, openOrdersFromContext, row)
            end
        end
    end
    if #rows > 0 or fieldAvailable then
        addSquadMenu(Menus.group(rootMenu, "squad", text("UI_SC_Context_Squad")), player, clickSquare, fieldFacts)
    end
    if #factions > 0 then
        addFactionConversations(Menus.group(rootMenu, "households", text("UI_SC_Context_Households")), factions, player)
    end
    if #oddballs > 0 then
        addOddballConversations(Menus.group(rootMenu, "strange_folk", text("UI_SC_Context_StrangeFolk")), oddballs, player)
    end
    if baseRelevant then addBaseMenu(rootMenu, clickSquare, containerTarget, barricadeTarget, player) end
    -- Prioritize the clicked container inside LF without moving storage
    -- commands above the game's own main-menu options.
    for _, key in ipairs({ "camp.storage.unmark", "camp.storage" }) do
        for index, option in ipairs(rootMenu.options) do
            if option.scLFContext and option.scMenuKey == key then
                table.remove(rootMenu.options, index)
                table.insert(rootMenu.options, 1, option)
                break
            end
        end
    end
    Menus.finish(rootMenu)
    Menus.prune(context)
    for index, option in ipairs(context.options) do
        if option.scLFContext and option.scMenuKey == "lf" then
            table.remove(context.options, index)
            context.options[#context.options+1] = option
            break
        end
    end
    for index, option in ipairs(context.options) do option.id = index end
end

local function returnExpeditionFromRadio(_target, player)
    local expedition = SC.ExpeditionPrototype
    if not expedition or not player then return end
    local ok, accepted, reason = pcall(expedition.sendRadioOrder,
        player, "return_now", "now")
    local feedback = ok and accepted == true
        and text("UI_SC_Expedition_ReturnSent")
        or ok and reason == "radio_no_ack"
            and text("UI_SC_Expedition_NoReceipt")
        or text("UI_SC_Expedition_Failed", tostring(ok and reason or accepted))
    safeMethod(player, "setHaloNote", feedback)
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
    return ok and accepted == true, ok and reason or tostring(accepted)
end

local function progressExpeditionFromRadio(_target, player)
    local expedition = SC.ExpeditionPrototype
    if not expedition or not player then return end
    local ok, accepted, reason = pcall(expedition.sendRadioOrder,
        player, "progress_report", "status")
    local feedback = ok and accepted == true
        and text("UI_SC_Expedition_ProgressAcknowledged")
        or ok and reason == "radio_no_ack"
            and text("UI_SC_Expedition_NoReceipt")
        or text("UI_SC_Expedition_Failed", tostring(ok and reason or accepted))
    safeMethod(player, "setHaloNote", feedback)
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
    return ok and accepted == true, ok and reason or tostring(accepted)
end

local function answerExpeditionFromRadio(_target, player, answer)
    local expedition = SC.ExpeditionPrototype
    if not expedition or not player then return end
    local ok, accepted, reason = pcall(expedition.sendRadioOrder,
        player, "expedition_decision", answer)
    local feedback = ok and accepted == true
        and text("UI_SC_Expedition_OrderSent")
        or ok and reason == "radio_no_ack"
            and text("UI_SC_Expedition_NoReceipt")
        or ok and (reason == "NO_SAFE_ROAD_DETOUR"
            or reason == "NO_ENTRY_CANDIDATE"
            or reason == "no_safe_return")
            and text("UI_SC_Expedition_NoSafeReturn")
        or text("UI_SC_Expedition_Failed", tostring(ok and reason or accepted))
    safeMethod(player, "setHaloNote", feedback)
    if SC.UI and type(SC.UI.refresh) == "function" then SC.UI.refresh() end
    return ok and accepted == true, ok and reason or tostring(accepted)
end

local function answerDistressFromRadio(_target, player, groupId)
    local radio = SC.OddballDistressRadio
    if not radio or type(radio.answer) ~= "function" then return end
    local okay, accepted, reason = pcall(radio.answer, groupId, player)
    local feedback = okay and accepted == true
        and tostring(reason or "Rescue location marked on your map.")
        or "Radio reply failed: " .. tostring(okay and reason or accepted)
    safeMethod(player, "setHaloNote", feedback)
    return okay and accepted == true, reason
end

local function callSoldierFromRadio(_target, player, groupId, topic)
    local soldier = SC.OddballSoldier
    if not soldier or type(soldier.call) ~= "function" then return end
    local okay, accepted, reason = pcall(soldier.call, groupId, topic, player)
    if not okay or accepted ~= true then
        safeMethod(player, "setHaloNote",
            "Radio call failed: " .. tostring(okay and reason or accepted))
    end
    return okay and accepted == true, reason
end

local function stopTaxiCallAudio()
    local sound = Context._taxiCallAudio
    Context._taxiCallAudio = nil
    if not sound then return end
    pcall(function()
        if sound.manager:isPlayingUISound(sound.handle) then
            sound.manager:stopUISound(sound.handle)
        end
    end)
end

local function playTaxiCallAudio()
    stopTaxiCallAudio()
    if type(getSoundManager) ~= "function" then return end
    pcall(function()
        local manager = getSoundManager()
        local handle = manager and manager:playUISound("LFTaxiRadioCall")
        if type(handle) == "number" and handle > 0 then
            Context._taxiCallAudio = { manager = manager, handle = handle }
        end
    end)
end

local function taxiRadioAction(_target, player, radio, action, payload)
    local booking, service = SC.TaxiBooking, SC.TaxiService
    if not booking or booking.dispatchReady ~= true or not service
        or type(service[action]) ~= "function" then return false end
    local primary = type(getSpecificPlayer) == "function"
        and getSpecificPlayer(0) or nil
    if player ~= primary then return false end
    local okay, accepted, reason, state = pcall(service[action],
        player, radio, payload)
    if okay and accepted == true then
        if action == "request" and radio ~= nil
            and (reason == "booking_received" or reason == "taxi_dispatched") then
            playTaxiCallAudio()
        elseif action == "cancel" then
            stopTaxiCallAudio()
        end
    end
    local feedbackKeys = {
        booking_received = "UI_SC_Taxi_booking_received",
        already_booked = "UI_SC_Taxi_already_booked",
        awaiting_pickup = "UI_SC_Taxi_awaiting_pickup",
        pickup_updated = "UI_SC_Taxi_pickup_updated",
        booking_cancelled = "UI_SC_Taxi_booking_cancelled",
        no_booking = "UI_SC_Taxi_no_booking",
        pickup_locked = "UI_SC_Taxi_pickup_locked",
        not_a_radio = "UI_SC_Taxi_not_a_radio",
        radio_not_owned = "UI_SC_Taxi_radio_not_owned",
        radio_not_portable = "UI_SC_Taxi_radio_not_portable",
        radio_receive_only = "UI_SC_Taxi_radio_receive_only",
        radio_off = "UI_SC_Taxi_radio_off",
        radio_flat = "UI_SC_Taxi_radio_flat",
        radio_muted = "UI_SC_Taxi_radio_muted",
        caller_position_unavailable = "UI_SC_Taxi_caller_position_unavailable",
        taxi_dispatched = "UI_SC_Taxi_booking_received",
        cab_unloaded_or_missing = "UI_SC_Taxi_cab_unloaded",
        searching = "UI_SC_Taxi_searching",
        driver_pending = "UI_SC_Taxi_driver_pending",
        board_driver = "UI_SC_Taxi_board_driver",
        pickup_drive = "UI_SC_Taxi_pickup_drive",
        waiting_board = "UI_SC_Taxi_waiting_board",
        ready_to_depart = "UI_SC_Taxi_ready_to_depart",
        in_transit = "UI_SC_Taxi_in_transit",
        waiting_exit = "UI_SC_Taxi_waiting_exit",
        finishing = "UI_SC_Taxi_finishing",
        departing = "UI_SC_Taxi_departing",
        retiring = "UI_SC_Taxi_retiring",
        departure_held = "UI_SC_Taxi_departure_held",
        held = "UI_SC_Taxi_held",
        taxi_departed = "UI_SC_Taxi_departed",
        fare_offered = "UI_SC_Taxi_fare_offered",
        already_offered = "UI_SC_Taxi_already_offered",
    }
    local key = feedbackKeys[okay and reason or nil] or "UI_SC_Taxi_unavailable"
    local message = text(key)
    if message == key then message = text("UI_SC_Taxi_unavailable") end
    if accepted == true and action == "status" and state
        and state.reason == "customer_property_in_cab" then
        message = text("UI_SC_Taxi_luggage_waiting")
    elseif accepted == true and action == "status" and state
        and state.reason == "passengers_still_aboard" then
        message = text("UI_SC_Taxi_passengers_waiting")
    elseif accepted == true and action == "status" and state
        and state.phase == "searching" and state.reason then
        message = message .. " " .. text("UI_SC_Taxi_MoveRoadside")
    elseif accepted == true and state and state.requestedAt then
        message = message .. " (" .. tostring(state.requestedAt.x) .. ", "
            .. tostring(state.requestedAt.y) .. ")"
    elseif accepted == true and action == "status" and state and state.pickup then
        message = message .. " " .. text("UI_SC_Taxi_PickupAt",
            tostring(math.floor(state.pickup.x)),
            tostring(math.floor(state.pickup.y)))
    end
    if accepted ~= true and reason == "fare_waiting" and type(state) == "table" then
        message = text("UI_SC_Taxi_fare_waiting",
            tostring(state.required), tostring(state.offered or 0))
    elseif accepted ~= true and type(reason) == "string"
        and feedbackKeys[reason] == nil then
        message = "Markus: " .. reason:gsub("_", " ")
    end
    safeMethod(player, "setHaloNote", message)
    return okay and accepted == true, reason
end

function Context.taxiCabAction(_target, player, action, payload)
    return taxiRadioAction(nil, player, nil, action, payload)
end

local function addTaxiRadioOptions(context, player, radio)
    local booking, service = SC.TaxiBooking, SC.TaxiService
    if not booking or booking.dispatchReady ~= true
        or not service
        or player ~= (type(getSpecificPlayer) == "function"
            and getSpecificPlayer(0) or nil) then return end
    local current = service.current()
    local car = safeMethod(player, "getVehicle")
    local boarded = current and car ~= nil and service.isBookedPassenger
        and service.isBookedPassenger(player, car) == true
    -- Once the trip starts there are no radio commands to show a seated
    -- passenger. Do not leave an empty taxi submenu in the inventory menu.
    if boarded and current.phase ~= "ready_to_depart" then return end
    local menu = Menus.group(context, "radio.taxi", text("UI_SC_Taxi_Menu"))
    if current then
        if not boarded then
            menu:addOption(text("UI_SC_Taxi_Status"), nil,
                taxiRadioAction, player, radio, "status")
        end
        if current.phase == "searching" then
            menu:addOption(text("UI_SC_Taxi_Update"), nil,
                taxiRadioAction, player, radio, "updatePickup")
        end
        if not boarded and (current.phase == "searching" or current.phase == "pickup_drive"
            or current.phase == "waiting_board"
            or current.phase == "ready_to_depart"
            or current.phase == "held") then
            menu:addOption(text("UI_SC_Taxi_Cancel"), nil,
                taxiRadioAction, player, radio, "cancel")
        end
        if current.phase == "ready_to_depart" then
            menu:addOption(text("UI_SC_Taxi_MapHint"), nil,
                function() safeMethod(player, "setHaloNote",
                    text("UI_SC_Taxi_MapHintDetail")) end)
            local destinations = service.destinations(player, radio) or {}
            for _, destination in ipairs(destinations) do
                local label = text("UI_SC_Taxi_DriveTo",
                    tostring(destination.name),
                    tostring(destination.required or "?"))
                menu:addOption(label, nil, taxiRadioAction,
                    player, radio, "depart", destination.id)
            end
            local car = SC.TaxiCab and select(2, SC.TaxiCab.recover())
            local rows = car and SC.TaxiCab.looseItems(car) or nil
            for _, row in ipairs(rows or {}) do
                local value = SC.TaxiFares and SC.TaxiFares.valueFor(row.item)
                if value then
                    menu:addOption(text("UI_SC_Taxi_Offer",
                        tostring(safeMethod(row.item, "getDisplayName")
                            or row.itemType), tostring(value)), nil,
                        taxiRadioAction, player, radio, "offer", row.item)
                end
            end
        end
    else
        menu:addOption(text("UI_SC_Taxi_Call"), nil,
            taxiRadioAction, player, radio, "request")
    end
end

function Context.fillRadioContextMenu(playerIndex, context, items)
    local player = getSpecificPlayer and getSpecificPlayer(playerIndex)
    if not context or not player or type(items) ~= "table" then return end
    Menus.removeOwned(context, function(option) return option.scLFRadio == true end)
    local mission = SC.ExpeditionPrototype and SC.ExpeditionPrototype.current and SC.ExpeditionPrototype.current()
    local inventory = safeMethod(player, "getInventory")
    local selectedRadio, equipped
    local function equippedRadio(item)
        return item and inventory and SC.GameplayUtil and SC.GameplayUtil.instanceOf(item, "Radio")
            and safeMethod(safeMethod(item, "getDeviceData"), "getIsTelevision") ~= true
            and safeMethod(item, "getContainer") == inventory
            and (item == safeMethod(player, "getPrimaryHandItem")
                or item == safeMethod(player, "getSecondaryHandItem")
                or item == safeMethod(player, "getClothingItem_Back"))
    end
    local function consider(item)
        if not item or not SC.GameplayUtil or not SC.GameplayUtil.instanceOf(item, "Radio")
            or safeMethod(safeMethod(item, "getDeviceData"), "getIsTelevision") == true then return end
        if SC.TaxiBooking and SC.TaxiBooking.checkRadio and SC.TaxiBooking.checkRadio(player, item) == true then
            selectedRadio = item
        end
        if equippedRadio(item) then equipped = item end
    end
    for _, entry in ipairs(items) do
        if type(entry) == "table" and type(entry.items) == "table" then
            for _, item in ipairs(entry.items) do consider(item) end
        else consider(entry) end
    end
    if not selectedRadio and not equipped then return end
    local services = Menus.group(context, "radio", text("UI_SC_Context_Radio"))
    for _, option in ipairs(context.options) do
        if option.scLFContext and option.scMenuKey == "radio" then option.scLFRadio = true end
    end
    local function entry(menu, key, label, callback, ...)
        local arguments, count, radio = { ... }, select("#", ...), equipped
        local expeditionAction = key == "radio.progress" or key == "radio.return"
            or string.sub(key, 1, 13) == "radio.answer."
        local option = Menus.action(menu, key, label, nil, function()
            if not equippedRadio(radio) then
                safeMethod(player, "setHaloNote", text("UI_SC_Context_RadioChanged"))
                return false
            end
            if expeditionAction and (not SC.ExpeditionPrototype
                or SC.ExpeditionPrototype.current() ~= mission
                or hasMethod(player, "getEquipedRadio") and safeMethod(player, "getEquipedRadio") ~= radio) then
                safeMethod(player, "setHaloNote", text("UI_SC_Context_Changed"))
                return false
            end
            return callback(nil, unpack(arguments, 1, count))
        end)
        if menu == context then option.scLFRadio = true end
        return option
    end
    if selectedRadio then addTaxiRadioOptions(services, player, selectedRadio) end
    if equipped then
        if playerIndex == 0 and mission and mission.scout and mission.scout.kind ~= "home" then
            local expedition = Menus.group(services, "radio.expedition", text("UI_SC_Context_RadioExpedition"))
            if mission.scout.search then
                entry(expedition, "radio.progress", text("UI_SC_Expedition_AskProgress"), progressExpeditionFromRadio, player)
            end
            if mission.scout.pause and mission.scout.pause.reported then
                for _, choice in ipairs({ {"Hold", "hold_position"}, {"Push", "push_on"}, {"Return", "return"} }) do
                    entry(context, "radio.answer." .. choice[2], text("UI_SC_Expedition_Answer" .. choice[1]),
                        answerExpeditionFromRadio, player, choice[2])
                end
            elseif mission.scout.phase ~= "inbound" then
                entry(expedition, "radio.return", text("UI_SC_Expedition_ReturnNow"), returnExpeditionFromRadio, player)
            end
        end
        local distress = SC.OddballDistressRadio
        if distress and distress.replyOptions then
            for _, option in ipairs(distress.replyOptions(player) or {}) do
                entry(context, "radio.distress." .. tostring(option.groupId), option.label,
                    answerDistressFromRadio, player, option.groupId)
            end
        end
        local soldier = SC.OddballSoldier
        if soldier and soldier.radioOptions then
            local okay, options = pcall(soldier.radioOptions, player)
            if okay and type(options) == "table" and #options > 0 then
                local stories = Menus.group(services, "radio.stories", text("UI_SC_Context_StrangeFolk"))
                for _, option in ipairs(options) do
                    entry(stories, "radio.soldier." .. tostring(option.groupId) .. ":" .. tostring(option.topic),
                        option.label, callSoldierFromRadio, player, option.groupId, option.topic)
                end
            end
        end
        if playerIndex == 0 and SC.GridControl and SC.GridControl.visible() and SC.GridRadio then
            local emma = Menus.group(services, "radio.emma", text("UI_SC_Context_RadioEmma"))
            entry(emma, "radio.grid", "EMMA: Grid report", function()
                local okay, message = SC.GridRadio.request(player, equipped)
                safeMethod(player, "setHaloNote", message)
            end)
        end
    end
    Menus.finish(services)
    Menus.prune(context)
    for index, option in ipairs(context.options) do
        if option.scLFContext and option.scMenuKey == "radio" then
            table.remove(context.options, index) context.options[#context.options+1] = option break
        end
    end
    for index, option in ipairs(context.options) do option.id = index end
end

function Context.install()
    if Context._installed then
        return
    end
    if ISWorldObjectContextMenu
        and type(ISWorldObjectContextMenu.onMedicalCheck) == "function"
        and ISWorldObjectContextMenu.onMedicalCheck ~= Context.onMedicalCheck then
        Context._originalMedicalCheck = ISWorldObjectContextMenu.onMedicalCheck
        ISWorldObjectContextMenu.onMedicalCheck = Context.onMedicalCheck
    end
    if ISInventoryPaneContextMenu
        and type(ISInventoryPaneContextMenu.readItem) == "function"
        and ISInventoryPaneContextMenu.readItem
            ~= Context.readItemWithOddballMail then
        Context._originalReadItem = ISInventoryPaneContextMenu.readItem
        ISInventoryPaneContextMenu.readItem = Context.readItemWithOddballMail
    end
    if Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Add(Context.fillWorldObjectContextMenu)
        Context._installed = true
    end
    if Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Add(Context.fillRadioContextMenu)
    end
end

function Context.remove()
    stopTaxiCallAudio()
    stopZoneCursor()
    if not Context._installed
        and not (ISInventoryPaneContextMenu
            and ISInventoryPaneContextMenu.readItem
                == Context.readItemWithOddballMail) then
        return
    end
    if Context._installed and Events and Events.OnFillWorldObjectContextMenu then
        Events.OnFillWorldObjectContextMenu.Remove(Context.fillWorldObjectContextMenu)
    end
    if Context._installed and Events and Events.OnFillInventoryObjectContextMenu then
        Events.OnFillInventoryObjectContextMenu.Remove(Context.fillRadioContextMenu)
    end
    if ISWorldObjectContextMenu
        and ISWorldObjectContextMenu.onMedicalCheck == Context.onMedicalCheck then
        ISWorldObjectContextMenu.onMedicalCheck = Context._originalMedicalCheck
    end
    if ISInventoryPaneContextMenu
        and ISInventoryPaneContextMenu.readItem
            == Context.readItemWithOddballMail then
        ISInventoryPaneContextMenu.readItem = Context._originalReadItem
    end
    Context._installed = false
end

Context.install()

return Context
