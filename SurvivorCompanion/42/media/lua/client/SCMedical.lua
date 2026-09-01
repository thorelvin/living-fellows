-- SPDX-License-Identifier: MIT

SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
if not SC.GameplayUtil and type(require) == "function" then pcall(require, "SCGameplayUtil") end

SC.Medical = SC.Medical or {}
local Medical = SC.Medical
local downed = setmetatable({}, { __mode = "k" })
local treatmentState = setmetatable({}, { __mode = "k" })

local function U()
    return SC.GameplayUtil
end

local function booleanMethod(value, names)
    local utility = U()
    for _, name in ipairs(names) do
        local result, ok = utility.call(value, name)
        if ok then return result == true end
    end
    return false
end

local function numberMethod(value, names, fallback)
    local utility = U()
    for _, name in ipairs(names) do
        local result, ok = utility.call(value, name)
        if ok and type(result) == "number" then return result end
    end
    return fallback or 0
end

local function bodyDamage(character)
    local body, ok = U().call(character, "getBodyDamage")
    if ok then return body end
    return nil
end

local function partName(part, index)
    local utility = U()
    local partType, ok = utility.call(part, "getType")
    if ok and partType then return tostring(partType) end
    return "part_" .. tostring(index)
end

local function inspectPart(part, index)
    local bleeding = booleanMethod(part, { "bleeding", "isBleeding" })
        or numberMethod(part, { "getBleedingTime" }, 0) > 0
    local bitten = booleanMethod(part, { "bitten", "isBitten" })
    local infected = booleanMethod(part, { "IsInfected", "isInfected", "isInfectedWound" })
    local bandaged = booleanMethod(part, { "bandaged", "isBandaged" })
    local dirtyBandage = booleanMethod(part, { "isBandageDirty" })
    local scratched = booleanMethod(part, { "scratched", "isScratched" })
    local cut = booleanMethod(part, { "isCut" })
    local deep = booleanMethod(part, { "deepWounded", "isDeepWounded" })
    local burned = numberMethod(part, { "getBurnTime" }, 0) > 0
    local fracture = numberMethod(part, { "getFractureTime" }, 0) > 0
    local bullet = booleanMethod(part, { "haveBullet" })
    local glass = booleanMethod(part, { "haveGlass" })
    local lodged = bullet or glass
    local severity = 0
    if bleeding then severity = severity + 28 end
    if bitten then severity = severity + 35 end
    if infected then severity = severity + 30 end
    if deep then severity = severity + 22 end
    if fracture then severity = severity + 18 end
    if burned then severity = severity + 12 end
    if scratched or cut then severity = severity + 8 end
    if lodged then severity = severity + 10 end
    if bandaged and not dirtyBandage then severity = severity - 18 end
    return {
        part = part,
        index = index,
        name = partName(part, index),
        bleeding = bleeding,
        bitten = bitten,
        infected = infected,
        bandaged = bandaged,
        dirtyBandage = dirtyBandage,
        scratched = scratched,
        cut = cut,
        deepWound = deep,
        burned = burned,
        fractured = fracture,
        lodged = lodged,
        bullet = bullet,
        glass = glass,
        severity = severity,
    }
end

function Medical.assess(character)
    local utility = U()
    local body = bodyDamage(character)
    local health = body and numberMethod(body, { "getHealth" }, utility.nativeHealth(character))
        or utility.nativeHealth(character)
    local wounds, bleedingCount, dirtyBandages, bites = {}, 0, 0, 0
    local bodyParts = body and select(1, utility.call(body, "getBodyParts")) or nil
    utility.each(bodyParts, 32, function(part, index)
        local wound = inspectPart(part, index)
        if wound.severity > 0 or wound.bandaged then wounds[#wounds + 1] = wound end
        if wound.bleeding and not wound.bandaged then bleedingCount = bleedingCount + 1 end
        if wound.dirtyBandage then dirtyBandages = dirtyBandages + 1 end
        if wound.bitten then bites = bites + 1 end
    end)
    table.sort(wounds, function(a, b) return a.severity > b.severity end)

    local infected = body and booleanMethod(body, { "IsInfected", "isInfected" }) or false
    local infectionLevel = body and numberMethod(body, { "getApparentInfectionLevel" }, 0) or 0
    local terminalKnox = infected and infectionLevel >= 99.5
    local state = downed[character]
    return {
        actor = character,
        bodyDamage = body,
        health = health,
        alive = health > 0 and not utility.isDead(character),
        wounds = wounds,
        woundCount = #wounds,
        bleedingCount = bleedingCount,
        dirtyBandages = dirtyBandages,
        bites = bites,
        knoxInfected = infected,
        infectionLevel = infectionLevel,
        terminalKnox = terminalKnox,
        downed = state ~= nil,
        critical = health > 0 and health <= (utility.config("medicalCriticalHealth") or 35),
        needsBandage = bleedingCount > 0,
        needsBandageChange = dirtyBandages > 0,
    }
end

local inventoryContains

local function inventoryRemove(inventory, item)
    local utility = U()
    local result, ok = utility.call(inventory, "Remove", item)
    if ok then return result ~= false and not inventoryContains(inventory, item) end
    if type(inventory) == "table" and type(inventory.items) == "table" then
        for index, value in ipairs(inventory.items) do
            if value == item then table.remove(inventory.items, index) return true end
        end
    end
    return false
end

inventoryContains = function(inventory, item)
    if not inventory or not item then return false end
    local contains, ok = U().call(inventory, "contains", item)
    if ok then return contains == true end
    for _, value in ipairs(U().inventoryItems(inventory, 160)) do
        if value == item then return true end
    end
    return false
end

local function restoreInventoryItem(inventory, item)
    if not inventory or not item then return false end
    if inventoryContains(inventory, item) then return true end
    return U().addItem(inventory, item) ~= nil
end

local function bandageRank(item)
    local utility = U()
    local itemType = string.lower(utility.itemType(item))
    local dirty = booleanMethod(item, { "isDirty", "isBloody" })
        or string.find(itemType, "dirty", 1, true) ~= nil
    if dirty then return nil end
    local alcoholic = booleanMethod(item, { "isAlcoholic" })
    if string.find(itemType, "steril", 1, true) or alcoholic then return 1 end
    if string.find(itemType, "bandage", 1, true) then return 2 end
    if string.find(itemType, "rippedsheet", 1, true)
        or string.find(itemType, "ripped_sheet", 1, true) then return 3 end
    if utility.itemHasTag(item, "CanBandage") then return 4 end
    return nil
end

local function findBandage(character)
    local utility = U()
    local inventory = utility.inventory(character)
    local best, bestRank
    for _, item in ipairs(utility.inventoryItems(inventory, 100)) do
        local protected = SC.PersonalItems and SC.PersonalItems.isProtected(
            item, character, "medical_consume")
        local rank = not protected and bandageRank(item) or nil
        if rank and (not bestRank or rank < bestRank) then
            best, bestRank = item, rank
            if rank == 1 then break end
        end
    end
    return best, inventory
end

local essentialClothingTerms = {
    "coat", "jacket", "parka", "trouser", "pants", "shoe", "boot",
    "underwear", "bullet", "firefighter", "hazmat",
}

local expendableWornTerms = { "tshirt", "shirt_", "socks", "scarf" }

local function isRecruitedTeam(character)
    if SC.Commands and type(SC.Commands.peek) == "function" then
        local ok, state = pcall(SC.Commands.peek, character)
        if ok and type(state) == "table" then return state.recruited == true end
    end
    local data = U().modData(character)
    return type(data) == "table" and data.SC_Recruited == true
end

local function isWorn(character, item)
    local utility = U()
    local equipped, equippedOk = utility.call(character, "isEquippedClothing", item)
    if equippedOk and equipped then return true end
    local wornItems, wornOk = utility.call(character, "getWornItems")
    if wornOk and wornItems then
        local contains, containsOk = utility.call(wornItems, "contains", item)
        if containsOk and contains then return true end
    end
    return false
end

local function restoreWornItem(character, item, location)
    if not location then return false end
    local result, called = U().call(character, "setWornItem", location, item)
    if not called or result == false then return false end
    return isWorn(character, item)
end

local function isExpendableClothing(character, item)
    local utility = U()
    if SC.PersonalItems and SC.PersonalItems.isProtected(item, character, "clothing_tear") then
        return false
    end
    local category, categoryOk = utility.call(item, "getCategory")
    local itemType = string.lower(utility.itemType(item))
    if (not categoryOk or tostring(category) ~= "Clothing")
        and not string.find(itemType, "shirt", 1, true)
        and not string.find(itemType, "socks", 1, true)
        and not string.find(itemType, "scarf", 1, true) then return false end
    for _, term in ipairs(essentialClothingTerms) do
        if string.find(itemType, term, 1, true) then return false end
    end
    local primary, primaryOk = utility.call(character, "getPrimaryHandItem")
    local secondary, secondaryOk = utility.call(character, "getSecondaryHandItem")
    if (primaryOk and primary == item) or (secondaryOk and secondary == item) then return false end
    local worn = isWorn(character, item)
    if worn then
        if not isRecruitedTeam(character) then return false end
        local whitelisted = false
        for _, term in ipairs(expendableWornTerms) do
            if string.find(itemType, term, 1, true) then whitelisted = true break end
        end
        if not whitelisted then return false end
        local location, locationOk = utility.call(item, "getBodyLocation")
        if not locationOk or location == nil then return false end
        return true, true, location
    end
    return true, false, nil
end

local function emergencyClothing(character)
    local utility = U()
    if not utility.isCompanion(character) then return nil, nil, nil, "not_companion" end
    local inventory = utility.inventory(character)
    if not inventory then return nil, nil, nil, "inventory_unavailable" end
    for _, item in ipairs(utility.inventoryItems(inventory, 100)) do
        local expendable, worn, wornLocation = isExpendableClothing(character, item)
        if expendable then
            return item, inventory, {
                character = character,
                clothing = item,
                worn = worn == true,
                wornLocation = wornLocation,
            }, nil
        end
    end
    return nil, inventory, nil, "no_expendable_clothing"
end

local function commitEmergencyBandage(inventory, candidate)
    if type(candidate) ~= "table" or not candidate.clothing then
        return nil, nil, "invalid_emergency_clothing"
    end
    local utility = U()
    local item = candidate.clothing
    if not inventoryContains(inventory, item) then return nil, nil, "clothing_missing" end
    if candidate.worn then
        local result, removed = utility.call(candidate.character, "removeWornItem", item, false)
        if not removed or result == false or isWorn(candidate.character, item) then
            return nil, nil, "clothing_unequip_failed"
        end
    end
    if not inventoryRemove(inventory, item) then
        local restored = not candidate.worn
            or restoreWornItem(candidate.character, item, candidate.wornLocation)
        return nil, nil, restored and "clothing_remove_failed"
            or "clothing_remove_rollback_failed"
    end
    local rag = utility.addItem(inventory, "Base.RippedSheets")
    if not rag then
        local restored = restoreInventoryItem(inventory, item)
        if candidate.worn then
            restored = restoreWornItem(candidate.character, item,
                candidate.wornLocation) and restored
        end
        return nil, nil, restored and "rag_creation_failed"
            or "rag_creation_rollback_failed"
    end
    return rag, {
        character = candidate.character,
        clothing = item,
        rag = rag,
        wornLocation = candidate.wornLocation,
    }, nil
end

local function rollbackEmergencyBandage(inventory, transaction)
    if type(transaction) ~= "table" then return true end
    local ok = true
    if transaction.rag and inventoryContains(inventory, transaction.rag) then
        ok = inventoryRemove(inventory, transaction.rag) and ok
    end
    if transaction.clothing then
        ok = restoreInventoryItem(inventory, transaction.clothing) and ok
        if transaction.wornLocation then
            ok = restoreWornItem(
                transaction.character,
                transaction.clothing,
                transaction.wornLocation
            ) and ok
        end
    end
    return ok
end

local function chooseWound(assessment, allowDirty)
    for _, wound in ipairs(assessment.wounds) do
        if wound.bleeding and not wound.bandaged then return wound end
    end
    if allowDirty then
        for _, wound in ipairs(assessment.wounds) do
            if wound.dirtyBandage then return wound end
        end
    end
    return nil
end

local function bandageSnapshot(wound)
    local previous = {
        bandaged = wound.bandaged == true,
        dirty = wound.dirtyBandage == true,
        life = numberMethod(wound.part, { "getBandageLife" }, 0),
        alcoholic = booleanMethod(wound.part, { "isAlcoholicBandage" }),
        bandageType = nil,
    }
    local bandageType, typeOk = U().call(wound.part, "getBandageType")
    if typeOk then previous.bandageType = bandageType end
    return previous
end

local function restoreBandage(body, wound, previous)
    if not body or not wound or not previous then return false end
    local _, restored = U().call(
        body,
        "SetBandaged",
        wound.index,
        previous.bandaged,
        previous.life or 0,
        previous.alcoholic == true,
        previous.bandageType
    )
    return restored
end

local function commitBandage(patient, assessment, wound, bandage, inventory,
        emergencyTransaction)
    local utility = U()
    if not assessment.bodyDamage or not wound or not bandage then return false, "invalid_treatment" end
    if not inventoryContains(inventory, bandage) then
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction)
        return false, rolledBack and "bandage_missing" or "treatment_rollback_failed"
    end
    local bandageLife = numberMethod(bandage, { "getBandagePower", "getCondition" }, 10)
    bandageLife = math.max(1, bandageLife)
    local alcoholic = booleanMethod(bandage, { "isAlcoholic" })
    local fullType = utility.itemType(bandage)
    local previous = bandageSnapshot(wound)
    local _, applied = utility.call(
        assessment.bodyDamage,
        "SetBandaged",
        wound.index,
        true,
        bandageLife,
        alcoholic,
        fullType
    )
    if not applied then
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction)
        return false, rolledBack and "native_bandage_failed" or "treatment_rollback_failed"
    end
    if not utility.consumeItem(inventory, bandage) then
        local nativeRestored = restoreBandage(assessment.bodyDamage, wound, previous)
        local rolledBack = rollbackEmergencyBandage(inventory, emergencyTransaction) and nativeRestored
        return false, rolledBack and "bandage_consume_failed" or "treatment_rollback_failed"
    end
    return true, "bandaged"
end

local function supportsVisualLifecycle()
    return type(SC.NativeActions) == "table"
        and type(SC.NativeActions.visualStatus) == "function"
        and type(SC.NativeActions.clearVisual) == "function"
end

local function supervisor()
    return type(SC.ActionSupervisor) == "table" and SC.ActionSupervisor or nil
end

local function supervisedTransition(state, phase, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true, phase end
    return service.transition(state.supervisorToken, phase, detail)
end

local function supervisedCommit(state, operation, detail)
    local service = supervisor()
    if service and state and state.supervisorToken
        and type(service.commit) == "function" then
        return service.commit(state.supervisorToken, operation, detail)
    end
    if type(operation) ~= "function" then return true, "committed", operation end
    local ok, accepted, reason, receipt = pcall(operation, state and state.supervisorToken)
    if not ok then return false, "commit_callback_failed", { error = tostring(accepted) } end
    return accepted == true, reason, receipt
end

local function supervisedProgress(state, signature, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.progress(state.supervisorToken, signature, detail)
end

local function supervisedVisualExpected(state, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.expectVisual(state.supervisorToken, detail)
end

local function supervisedVisualVerified(state, detail)
    local service = supervisor()
    if not service or not state or not state.supervisorToken then return true end
    return service.markVisualVerified(state.supervisorToken, detail)
end

local function treatmentWound(assessment, state)
    for _, wound in ipairs(assessment.wounds or {}) do
        if wound.index == state.woundIndex then
            if state.dirtyOnly then
                if wound.dirtyBandage then return wound end
            elseif (wound.bleeding and not wound.bandaged) or wound.dirtyBandage then
                return wound
            end
        end
    end
    if state.dirtyOnly then
        for _, wound in ipairs(assessment.wounds or {}) do
            if wound.dirtyBandage then return wound end
        end
        return nil
    end
    return chooseWound(assessment, true)
end

local function releaseTreatmentResources(helper, state, reason)
    state = state or treatmentState[helper]
    if not state then return true, reason or "no_treatment" end
    local rolledBack = rollbackEmergencyBandage(state.inventory,
        state.emergencyTransaction)
    if SC.NativeActions and type(SC.NativeActions.cancelVisual) == "function" then
        local visual = state.phase == "ripping" and "rip_clothing_for_bandage"
            or state.phase == "bandaging" and (state.visualAction or "kneel_treat") or nil
        if visual then pcall(SC.NativeActions.cancelVisual, helper,
            reason or "medical_cancelled") end
    end
    if state.phase == "approaching" and SC.Navigation
        and type(SC.Navigation.cancel) == "function" then
        pcall(SC.Navigation.cancel, helper, reason or "medical_cancelled")
    end
    if rolledBack then
        state.emergencyTransaction = nil
        treatmentState[helper] = nil
    end
    return rolledBack, rolledBack and (reason or "cancelled")
        or "treatment_rollback_failed"
end

local function clearTreatment(helper, state, reason, detail)
    local rolledBack, finalReason = releaseTreatmentResources(helper, state, reason)
    if not rolledBack then
        finalReason = "treatment_rollback_failed"
        if state then state.emergencyTransaction = nil end
        treatmentState[helper] = nil
    end
    local service = supervisor()
    local token = state and state.supervisorToken
    if service and token and service.isCurrent(token) then
        service.fail(token, finalReason or reason or "treatment_failed", detail)
    end
    return false, finalReason or reason or "treatment_failed"
end

local function startRipAnimation(helper, state)
    local expected, expectedReason = supervisedVisualExpected(state, {
        action = "rip_clothing_for_bandage",
        itemType = state.emergencyCandidate
            and U().itemType(state.emergencyCandidate.clothing) or nil,
    })
    if expected ~= true then return clearTreatment(helper, state,
        expectedReason or "visual_registration_failed") end
    local accepted, reason = U().move(helper, "walk", {
        action = "rip_clothing_for_bandage",
        item = state.emergencyCandidate and state.emergencyCandidate.clothing,
        emergency = state.emergency == true,
        durationTicks = 120,
        supervisorToken = state.supervisorToken,
    })
    if not accepted then return clearTreatment(helper, state,
        reason or "rip_action_rejected") end
    state.phase = "ripping"
    state.startedAt = U().nowMs()
    treatmentState[helper] = state
    local transitioned, transitionReason = supervisedTransition(state, "animating", {
        action = "rip_clothing_for_bandage",
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "animation_phase_rejected") end
    return true, "ripping_emergency_bandage"
end

local function startBandageAnimation(helper, state)
    local assessment = Medical.assess(state.patient)
    local wound = treatmentWound(assessment, state)
    if not wound then return clearTreatment(helper, state, "wound_no_longer_treatable") end
    if not inventoryContains(state.inventory, state.bandage) then
        return clearTreatment(helper, state, "bandage_missing")
    end
    local expected, expectedReason = supervisedVisualExpected(state, {
        action = state.visualAction or "kneel_treat", woundIndex = wound.index,
    })
    if expected ~= true then return clearTreatment(helper, state,
        expectedReason or "visual_registration_failed") end
    local accepted, reason = U().move(helper, "walk", {
        action = state.visualAction or "kneel_treat",
        patient = state.patient,
        bodyPartIndex = wound.index,
        bodyPart = wound.part,
        itemType = U().itemType(state.bandage),
        humanAnimationOnly = true,
        emergency = state.emergency == true,
        durationTicks = 100,
        supervisorToken = state.supervisorToken,
    })
    if not accepted then
        return clearTreatment(helper, state, reason or "treatment_action_rejected")
    end
    state.phase = "bandaging"
    state.woundIndex = wound.index
    state.startedAt = U().nowMs()
    treatmentState[helper] = state
    local transitioned, transitionReason = supervisedTransition(state, "animating", {
        action = state.visualAction or "kneel_treat",
        woundIndex = wound.index,
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "animation_phase_rejected") end
    return true, "treatment_animation_started"
end

local function beginEmergencyApplyToken(helper, state, parentSerial)
    local service = supervisor()
    if not service then return true, "unsupervised" end
    local token, reason, retry = service.begin(helper, {
        owner = "medical", action = state.supervisorAction or "treat_wound",
        targetKey = state.targetKey,
        targetLabel = tostring(U().nameOf(state.patient)) .. " "
            .. tostring(state.woundName),
        priority = state.supervisorPriority or service.Priority.COMBAT_RESCUE,
        interruptible = true, requiresVisual = false,
        allowedActions = {
            kneel_treat = true, replace_bandage = true,
        },
        onCancel = function(_, cancelReason)
            return releaseTreatmentResources(helper, state,
                cancelReason or "medical_cancelled")
        end,
        metadata = {
            woundIndex = state.woundIndex, emergencyStage = "apply",
            parentCommitSerial = parentSerial,
        },
    })
    if not token then return false, reason or "medical_apply_owner_rejected", retry end
    state.supervisorToken = token
    local reserved, reserveReason = service.reserve(token, state.bandage,
        "emergency_bandage")
    if reserved ~= true then
        service.fail(token, reserveReason or "reservation_lost")
        state.supervisorToken = nil
        return false, reserveReason or "reservation_lost"
    end
    return true, "emergency_apply_selected"
end

local function finishEmergencyRip(helper, state, startVisual)
    local committing, commitReason = supervisedTransition(state, "committing", {
        action = "rip_clothing_for_bandage",
    })
    if committing ~= true then return clearTreatment(helper, state,
        commitReason or "commit_rejected") end

    local rag, transaction
    local committed, reason = supervisedCommit(state, function()
        local failure
        rag, transaction, failure = commitEmergencyBandage(
            state.inventory, state.emergencyCandidate)
        if not rag then
            return false, failure or "rag_creation_failed", {
                stage = "emergency_rip",
            }
        end
        return true, "emergency_bandage_created", {
            stage = "emergency_rip", itemType = U().itemType(rag),
        }
    end)
    if committed ~= true then return clearTreatment(helper, state,
        reason or "rag_creation_failed") end

    state.bandage = rag
    state.emergencyTransaction = transaction
    state.emergencyCandidate = nil
    local verifying, verifyReason = supervisedTransition(state, "verifying", {
        itemType = U().itemType(rag), stage = "emergency_rip",
    })
    if verifying ~= true or not inventoryContains(state.inventory, rag) then
        return clearTreatment(helper, state,
            verifyReason or "rag_verification_failed")
    end

    local service = supervisor()
    local parentToken = state.supervisorToken
    local urgent = service and type(service.urgentStatus) == "function"
        and service.urgentStatus(helper) or nil
    if service and parentToken and service.isCurrent(parentToken) then
        local completed, completeReason = service.complete(parentToken,
            "emergency_bandage_created", {
                itemType = U().itemType(rag), stage = "emergency_rip",
            })
        if completed ~= true then return clearTreatment(helper, state,
            completeReason or "emergency_rip_completion_failed") end
    end
    state.supervisorToken = nil

    -- Completion releases a queued survival intent.  Do not immediately claim
    -- a second token over that hand-off; restore the clothing if treatment was
    -- preempted between the two independently committed physical effects.
    if urgent and (urgent.state == "queued" or urgent.state == "waiting_external") then
        local rolledBack = releaseTreatmentResources(helper, state,
            "urgent_preempted_after_emergency_rip")
        return false, rolledBack and "urgent_preempted_after_emergency_rip"
            or "treatment_rollback_failed"
    end

    local began, beginReason = beginEmergencyApplyToken(helper, state,
        parentToken and parentToken.serial or nil)
    if began ~= true then
        local rolledBack = releaseTreatmentResources(helper, state,
            beginReason or "emergency_apply_owner_rejected")
        return false, rolledBack and (beginReason or "emergency_apply_owner_rejected")
            or "treatment_rollback_failed"
    end
    if startVisual ~= false then return startBandageAnimation(helper, state) end
    return true, "emergency_apply_selected"
end

local function finishTreatment(helper, state)
    local assessment = Medical.assess(state.patient)
    local wound = treatmentWound(assessment, state)
    if not wound then return clearTreatment(helper, state, "wound_no_longer_treatable") end
    local committing, commitReason = supervisedTransition(state, "committing", {
        woundIndex = wound.index, itemType = U().itemType(state.bandage),
    })
    if committing ~= true then return clearTreatment(helper, state,
        commitReason or "commit_rejected") end
    local applied, reason = supervisedCommit(state, function()
        local accepted, result = commitBandage(state.patient, assessment, wound,
            state.bandage, state.inventory, state.emergencyTransaction)
        return accepted, result, {
            stage = "apply_bandage", woundIndex = wound.index,
            itemType = U().itemType(state.bandage),
        }
    end)
    if not applied then return clearTreatment(helper, state, reason) end
    state.emergencyTransaction = nil
    local verifying, verifyReason = supervisedTransition(state, "verifying", {
        woundIndex = wound.index,
    })
    if verifying ~= true then
        treatmentState[helper] = nil
        local service = supervisor()
        if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
            service.fail(state.supervisorToken, verifyReason or "verification_failed")
        end
        return false, verifyReason or "verification_failed"
    end
    local verifiedAssessment = Medical.assess(state.patient)
    local verifiedWound
    for _, candidate in ipairs(verifiedAssessment.wounds or {}) do
        if candidate.index == wound.index then verifiedWound = candidate break end
    end
    if not verifiedWound or verifiedWound.bandaged ~= true
        or verifiedWound.dirtyBandage == true then
        treatmentState[helper] = nil
        local service = supervisor()
        if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
            service.fail(state.supervisorToken, "verification_failed", {
                woundIndex = wound.index,
            })
        end
        return false, "verification_failed"
    end
    treatmentState[helper] = nil
    if SC.NativeActions and type(SC.NativeActions.noteResult) == "function" then
        SC.NativeActions.noteResult(helper, "medical_treatment", "bandaged", {
            kind = "long",
        })
    end
    local service = supervisor()
    if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
        service.complete(state.supervisorToken, "bandaged", {
            woundIndex = wound.index, patientId = U().idOf(state.patient), verified = true,
        })
    end
    return true, "bandaged"
end

local continueTreatmentApproach

local function advanceTreatment(helper, state)
    if state.phase == "approaching" then
        return continueTreatmentApproach(helper, state)
    end
    local expected = state.phase == "ripping" and "rip_clothing_for_bandage"
        or state.visualAction or "kneel_treat"
    local visualState = SC.NativeActions.visualStatus(helper, expected)
    if visualState == "active" then
        supervisedProgress(state, "visual:" .. tostring(state.phase)
            .. ":" .. tostring(state.startedAt), { visual = expected })
        return true, state.phase == "ripping" and "ripping_emergency_bandage"
            or "treatment_animation_active"
    end
    if visualState ~= "completed" then
        if visualState ~= "different" then SC.NativeActions.clearVisual(helper) end
        return clearTreatment(helper, state, "treatment_animation_" .. tostring(visualState))
    end
    SC.NativeActions.clearVisual(helper)
    local verified, verifyReason = supervisedVisualVerified(state, {
        action = expected,
    })
    if verified ~= true then return clearTreatment(helper, state,
        verifyReason or "animation_verification_failed") end
    if state.phase == "ripping" then
        return finishEmergencyRip(helper, state, true)
    end
    return finishTreatment(helper, state)
end

-- Compatibility path for the isolated gameplay harness. The shipping runtime
-- always loads SCNativeActions and therefore always uses the staged lifecycle.
local function immediateTreatment(helper, patient, assessment, wound, bandage,
        inventory, emergencyTransaction, visualAction, state)
    local accepted = U().move(helper, "walk", {
        action = visualAction or "kneel_treat", patient = patient,
        bodyPartIndex = wound.index, bodyPart = wound.part,
        itemType = U().itemType(bandage), humanAnimationOnly = true,
        emergency = wound.bleeding == true,
        supervisorToken = state and state.supervisorToken,
    })
    if not accepted then
        return clearTreatment(helper, state or {
            inventory = inventory, emergencyTransaction = emergencyTransaction,
        }, "treatment_action_rejected")
    end
    state = state or {
        patient = patient, woundIndex = wound.index, bandage = bandage,
        inventory = inventory, emergencyTransaction = emergencyTransaction,
        visualAction = visualAction,
    }
    state.bandage = bandage
    state.emergencyTransaction = emergencyTransaction
    return finishTreatment(helper, state)
end

local function treatmentSquare(helper, patient)
    local utility = U()
    local patientSquare = utility.squareOf(patient)
    local x, y, z = utility.position(patientSquare)
    if not x then return nil end
    local best, bestDistance = nil, math.huge
    for _, delta in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        local square = utility.gridSquare(x + delta[1], y + delta[2], z)
        if square and utility.isSquareFree(square) and not utility.edgeBlocked(square, patientSquare) then
            local distance = utility.distanceSq(helper, square)
            if distance < bestDistance then best, bestDistance = square, distance end
        end
    end
    return best or patientSquare
end

local function rescueViable(helper, snapshot)
    if type(snapshot) ~= "table" then return true end
    local immediate = tonumber(snapshot.immediateCount) or #(snapshot.immediateAttackers or {})
    local escapeCount = #(snapshot.escapeSquares or {})
    if immediate >= 2 then return false end
    if escapeCount == 0 and (tonumber(snapshot.threatCount) or #(snapshot.threats or {})) >= 2 then return false end
    return true
end

local function treatmentCapability(helper, patient, options)
    options = type(options) == "table" and options or {}
    local assessment = Medical.assess(patient)
    local wound
    if options.dirtyOnly then
        for _, value in ipairs(assessment.wounds or {}) do
            if value.dirtyBandage then wound = value break end
        end
    else
        wound = chooseWound(assessment, true)
    end
    if not wound then return nil, "no_treatable_wound" end
    local bandage, inventory = findBandage(helper)
    local clothing, candidate, failure
    if not bandage then
        clothing, inventory, candidate, failure = emergencyClothing(helper)
        if not clothing then
            return {
                assessment = assessment, wound = wound, inventory = inventory,
                dirtyOnly = options.dirtyOnly == true,
            }, options.dirtyOnly and "no_clean_bandage"
                or (failure == "no_expendable_clothing" and "no_bandage" or failure or "no_bandage")
        end
    end
    return {
        assessment = assessment, wound = wound, inventory = inventory,
        bandage = bandage, emergencyCandidate = candidate,
        dirtyOnly = options.dirtyOnly == true,
        visualAction = options.visualAction,
        available = true,
    }
end

function Medical.canReplaceDirtyBandage(actor)
    if not U().isValidActor(actor) then return false, "invalid_actor" end
    local capability, reason = treatmentCapability(actor, actor, {
        dirtyOnly = true, visualAction = "replace_bandage",
    })
    return capability ~= nil and capability.available == true,
        reason or (capability and "ready" or "no_treatable_wound"), capability
end

local function beginTreatmentState(helper, patient, capability)
    local wound = capability.wound
    local action = capability.dirtyOnly and "replace_dirty_bandage" or "treat_wound"
    local targetKey = tostring(U().idOf(patient) or "patient") .. ":"
        .. tostring(wound.index)
    local service = supervisor()
    local priority = service and (wound.bleeding and service.Priority.COMBAT_RESCUE
        or service.Priority.NEEDS) or nil
    local state = {
        phase = "selected", patient = patient, woundIndex = wound.index,
        woundName = wound.name, dirtyOnly = capability.dirtyOnly == true,
        emergency = wound.bleeding == true,
        inventory = capability.inventory, bandage = capability.bandage,
        emergencyCandidate = capability.emergencyCandidate,
        visualAction = capability.visualAction,
        targetKey = targetKey,
        supervisorAction = action, supervisorPriority = priority,
    }
    if service then
        local priorRetry = capability.available == true
            and service.retryStatusAny(helper, action, targetKey) or nil
        if priorRetry and priorRetry.category == "resources"
            and type(service.resetRetry) == "function" then
            service.resetRetry(helper, "medical_resources_available", action, targetKey)
        end
        local token, reason, retry = service.begin(helper, {
            owner = "medical", action = action, targetKey = targetKey,
            targetLabel = tostring(U().nameOf(patient)) .. " " .. tostring(wound.name),
            priority = priority,
            interruptible = true, requiresVisual = false,
            retryCategory = capability.available and nil or "resources",
            allowedActions = {
                move_to_treat = true, kneel_treat = true, replace_bandage = true,
                rip_clothing_for_bandage = true,
            },
            onCancel = function(_, cancelReason)
                return releaseTreatmentResources(helper, state,
                    cancelReason or "medical_cancelled")
            end,
            metadata = { woundIndex = wound.index, dirtyOnly = capability.dirtyOnly == true },
        })
        if not token then return nil, reason or "medical_owner_rejected", retry end
        state.supervisorToken = token
        if capability.available ~= true then
            service.fail(token, capability.dirtyOnly and "no_clean_bandage" or "no_supplies", {
                woundIndex = wound.index,
            })
            return nil, capability.dirtyOnly and "no_clean_bandage" or "no_bandage"
        end
        local resource = capability.bandage
            or capability.emergencyCandidate and capability.emergencyCandidate.clothing
        if resource then
            local reserved, reserveReason = service.reserve(token, resource, "medical_supply")
            if reserved ~= true then
                service.fail(token, reserveReason or "reservation_lost")
                return nil, reserveReason or "reservation_lost"
            end
        end
    elseif capability.available ~= true then
        return nil, capability.dirtyOnly and "no_clean_bandage" or "no_bandage"
    end
    treatmentState[helper] = state
    return state, "selected"
end

continueTreatmentApproach = function(helper, state, runtime)
    local utility = U()
    if not utility.isValidActor(state.patient) then
        return clearTreatment(helper, state, "invalid_target")
    end
    local rootRuntime = utility.actorState(helper, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if not rescueViable(helper, snapshot) then
        return Medical.cancel(helper, "danger_preempted")
    end
    if utility.distance(helper, state.patient) <= (utility.config("medicalRange") or 1.35) then
        utility.stop(helper)
        local settled, settleReason = supervisedTransition(state, "settling", {
            patientId = U().idOf(state.patient),
        })
        if settled ~= true then return clearTreatment(helper, state,
            settleReason or "settle_rejected") end
        if state.emergencyCandidate then
            if supportsVisualLifecycle() then return startRipAnimation(helper, state) end
            local accepted = utility.move(helper, "walk", {
                action = "rip_clothing_for_bandage",
                item = state.emergencyCandidate.clothing,
                emergency = state.emergency,
                supervisorToken = state.supervisorToken,
            })
            if not accepted then return clearTreatment(helper, state, "rip_action_rejected") end
            local finished, finishReason = finishEmergencyRip(helper, state, false)
            if finished ~= true then return false, finishReason end
        end
        if supportsVisualLifecycle() then return startBandageAnimation(helper, state) end
        return immediateTreatment(helper, state.patient, Medical.assess(state.patient),
            treatmentWound(Medical.assess(state.patient), state), state.bandage,
            state.inventory, state.emergencyTransaction, state.visualAction, state)
    end
    local navigation = SC.Navigation
    if type(navigation) ~= "table" or type(navigation.requestAny) ~= "function" then
        return clearTreatment(helper, state, "navigation_unavailable")
    end
    local targets = navigation.interactionTargets(helper, state.patient, {
        snapshot = snapshot, maximum = 4,
    })
    local fallback = treatmentSquare(helper, state.patient)
    if #targets == 0 and fallback then targets[1] = fallback end
    if #targets == 0 then return clearTreatment(helper, state, "no_interaction_point") end
    local transitioned, transitionReason = supervisedTransition(state, "approaching", {
        patientId = U().idOf(state.patient), candidates = #targets,
    })
    if transitioned ~= true then return clearTreatment(helper, state,
        transitionReason or "approach_rejected") end
    state.phase = "approaching"
    local ok, status = navigation.requestAny(helper, targets, "walk", {
        action = "move_to_treat", patient = state.patient, snapshot = snapshot,
        arrivalDistance = 0.9, supervisorToken = state.supervisorToken,
    })
    if not ok then return clearTreatment(helper, state, status or "route_failed") end
    supervisedProgress(state, "approach:" .. tostring(status), {
        status = status, patientId = U().idOf(state.patient),
    })
    return true, status or "approaching_patient"
end

function Medical.treat(helper, patient, runtime, options)
    local utility = U()
    if not utility.isValidActor(helper) or not utility.isValidActor(patient) then return false, "invalid_patient" end
    local active = treatmentState[helper]
    if active then return advanceTreatment(helper, active, runtime) end
    options = type(options) == "table" and options or {}
    local capability, capabilityReason = treatmentCapability(helper, patient, options)
    if not capability then return false, capabilityReason or "no_treatable_wound" end
    local rootRuntime = utility.actorState(helper, runtime)
    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if not rescueViable(helper, snapshot) then return false, "unsafe_rescue" end
    local state, stateReason = beginTreatmentState(helper, patient, capability)
    if not state then return false, stateReason or capabilityReason or "medical_owner_rejected" end
    return continueTreatmentApproach(helper, state, rootRuntime)
end

local function enterDowned(actor, assessment, runtime)
    local utility = U()
    local now = utility.nowMs()
    if not utility.stop(actor) then return false, "downed_stop_rejected" end
    if not utility.move(actor, "walk", {
        action = "downed",
        immobile = true,
        canFight = false,
        nativeHealth = assessment.health,
        humanAnimationOnly = true,
    }) then return false, "downed_action_rejected" end
    downed[actor] = downed[actor] or { since = now }
    downed[actor].health = assessment.health
    if type(runtime) == "table" then
        runtime.downed = true
        runtime.needsRescue = true
    end
    return true, "downed"
end

local function leaveDowned(actor, runtime)
    local utility = U()
    if not utility.move(actor, "walk", { action = "recover_from_downed", immobile = false }) then
        return false, "recovery_action_rejected"
    end
    downed[actor] = nil
    if type(runtime) == "table" then
        runtime.downed = nil
        runtime.needsRescue = nil
    end
    return true, "recovered"
end

function Medical.isDowned(actor)
    return actor ~= nil and downed[actor] ~= nil
end

local function rescueCandidate(actor, player, snapshot)
    local utility = U()
    local best, bestScore
    local function consider(candidate)
        if not candidate or candidate == actor or not utility.isValidActor(candidate) then return end
        local assessment = Medical.assess(candidate)
        if not assessment.needsBandage and not assessment.critical and not assessment.downed then return end
        local score = (assessment.downed and 80 or 0)
            + assessment.bleedingCount * 25
            + math.max(0, 50 - assessment.health)
            - utility.distance(actor, candidate) * 2
        if not bestScore or score > bestScore then best, bestScore = candidate, score end
    end
    consider(player)
    if snapshot and type(snapshot.allies) == "table" then
        for _, ally in ipairs(snapshot.allies) do consider(ally.actor) end
    end
    return best
end

function Medical.update(actor, player, runtime)
    local utility = U()
    if not utility or not utility.isValidActor(actor) then return false, "invalid_actor" end
    local rootRuntime = utility.actorState(actor, runtime)
    local assessment = Medical.assess(actor)
    rootRuntime.medicalAssessment = assessment

    if not assessment.alive or assessment.health <= 0 or assessment.terminalKnox then
        if treatmentState[actor] then Medical.cancel(actor,
            assessment.terminalKnox and "terminal_knox" or "death", true) end
        downed[actor] = nil
        rootRuntime.downed = nil
        return false, assessment.terminalKnox and "terminal_knox" or "dead"
    end

    local downedThreshold = utility.config("downedHealth") or 18
    if assessment.health <= downedThreshold then
        return enterDowned(actor, assessment, rootRuntime)
    end
    if downed[actor] then
        if assessment.health >= (utility.config("downedRecoverHealth") or 25)
            and assessment.bleedingCount == 0 then
            return leaveDowned(actor, rootRuntime)
        end
        return enterDowned(actor, assessment, rootRuntime)
    end

    local snapshot = rootRuntime.senses and rootRuntime.senses.current or rootRuntime.snapshot
    if assessment.needsBandage and rescueViable(actor, snapshot) then
        local ok, reason = Medical.treat(actor, actor, rootRuntime)
        if ok then return true, reason end
    end

    local explicitTarget = rootRuntime.rescueTarget
    local candidate = explicitTarget or rescueCandidate(actor, player, snapshot)
    if candidate and rescueViable(actor, snapshot) then
        local ok, reason = Medical.treat(actor, candidate, rootRuntime)
        if ok then return true, reason end
    end
    return false, "no_medical_action"
end

function Medical.replaceDirtyBandage(actor)
    return Medical.treat(actor, actor, nil, {
        dirtyOnly = true, visualAction = "replace_bandage",
    })
end

function Medical.replaceDirtyBandageAfterVisual(actor)
    -- Kept as a compatibility entry point, but it no longer commits after a
    -- foreign downtime visual. Medical owns selection, animation and commit.
    return Medical.replaceDirtyBandage(actor)
end

function Medical.cancel(actor, reason, force)
    local state = actor and treatmentState[actor] or nil
    if not state then return true, "no_active_treatment" end
    local service = supervisor()
    if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
        return service.cancel(actor, reason or "medical_cancelled", nil, force == true)
    end
    return releaseTreatmentResources(actor, state, reason or "medical_cancelled")
end

function Medical.peek(actor)
    local state = actor and treatmentState[actor] or nil
    if not state then return nil end
    return {
        phase = state.phase, patient = state.patient, woundIndex = state.woundIndex,
        woundName = state.woundName, dirtyOnly = state.dirtyOnly,
        emergency = state.emergency, startedAt = state.startedAt,
        supervisorToken = state.supervisorToken,
    }
end

function Medical.statusText(character)
    local utility = U()
    local assessment = Medical.assess(character)
    if not assessment.alive then return utility.text("UI_SC_Status_Dead", "Dead") end
    if assessment.terminalKnox then return utility.text("UI_SC_Status_TerminalKnox", "Terminal Knox infection") end
    if assessment.knoxInfected then
        return utility.text("UI_SC_Status_Knox", "Knox symptoms") .. " (" .. tostring(math.floor(assessment.infectionLevel)) .. "%)"
    end
    if assessment.downed then return utility.text("UI_SC_Status_Downed", "Downed") end
    if assessment.bleedingCount > 0 then
        return utility.text("UI_SC_Status_Bleeding", "Bleeding") .. " (" .. tostring(assessment.bleedingCount) .. ")"
    end
    if assessment.woundCount > 0 then return utility.text("UI_SC_Status_Wounded", "Wounded") end
    return utility.text("UI_SC_Status_Stable", "Stable")
end

function Medical.reset(actor)
    if actor then
        local state = treatmentState[actor]
        if state then
            local service = supervisor()
            if service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
                service.cancel(actor, "medical_reset", nil, true)
            else
                releaseTreatmentResources(actor, state, "medical_reset")
            end
        end
        downed[actor] = nil
        treatmentState[actor] = nil
    else
        local helpers = {}
        for helper in pairs(treatmentState) do helpers[#helpers + 1] = helper end
        for _, helper in ipairs(helpers) do
            local state = treatmentState[helper]
            local service = supervisor()
            if state and service and state.supervisorToken and service.isCurrent(state.supervisorToken) then
                service.cancel(helper, "medical_reset_all", nil, true)
            elseif state then
                releaseTreatmentResources(helper, state, "medical_reset_all")
            end
        end
        downed = setmetatable({}, { __mode = "k" })
        treatmentState = setmetatable({}, { __mode = "k" })
    end
end

return Medical
