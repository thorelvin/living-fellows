-- SPDX-License-Identifier: MIT
require "SCRelationshipHelp"
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.UISocial = SC.UISocial or {}
local Social = SC.UISocial
local function text(key, fallback, ...)
    if SC.GameplayUtil and SC.GameplayUtil.text then
        return SC.GameplayUtil.text("UI_SC_Social_" .. key, fallback, ...)
    end
    return SC.UI.text("UI_SC_Social_" .. key, ...)
end
local function player() return type(getSpecificPlayer) == "function" and getSpecificPlayer(0) end

local reasons = {
    help_unavailable = "This survivor is no longer available.",
    help_story = "This person has their own story. Talk to them about what they need.",
    help_hostile = "They are hostile. Settle the conflict before offering supplies.",
    help_too_far = "Stand nearby on the same floor to help.",
    too_far_to_trade = "Stand nearby to hand over supplies.",
    help_no_need = "They do not need that right now. Your supplies have been kept.",
    help_item_changed = "The selected item changed. Choose your supplies again.",
    help_busy = "Finish your current action before handing over supplies.",
    danger_nearby = "Nearby threats need to be dealt with before handing over supplies.",
    danger_check_pending = "They are still checking the area. Try again in a moment.",
    danger_check_stale = "They need a fresh look around before it is safe to hand over supplies.",
    line_of_sight_lost = "You need a clear view of each other to hand over supplies.",
    trade_selection_changed = "The selected item moved. Choose your supplies again.",
    protected_trade_item = "That item is equipped, protected or reserved. Choose another item.",
    faction_inventory_full = "They cannot carry that item. Free some space first.",
    trade_recovery_pending = "An earlier handover still needs to settle. Your new supplies have been kept.",
    faction_recruitment_disabled = "Household recruitment is disabled in this world's settings.",
    faction_not_discovered = "Introduce yourself to this household first.",
    faction_hostile = "The household is hostile. Resolve that conflict first.",
    unresolved_offenses = "Resolve your outstanding offenses with the household.",
    trusted_standing_required = "Earn Trusted standing with the household by helping with their requests.",
    more_contracts_required = "Complete more household contracts.",
    last_household_resident = "They cannot leave their last resident alone.",
    oddball_story_incomplete = "Their personal story must be resolved first.",
    recruitment_cooldown = "Give them time before asking again.",
    no_willing_candidate = "Nobody is ready to leave this household yet.",
    family_ties = "Family ties are keeping them here.",
    candidate_unavailable = "The prospective recruit must be nearby and available.",
    candidate_not_loaded = "Visit the household so its members can discuss joining in person.",
    household_refused_recruitment = "Nobody is willing to leave their role or family here. More personal gifts will not change that decision today.",
    household_member_already_joined = "Someone from this household has already joined you.",
    candidate_died = "The prospective recruit has died. This recruitment cannot continue.",
    trial_already_active = "A field trial is already in progress. Review it in the household panel.",
    trial_not_ready = "The field trial needs more time before a decision.",
    candidate_too_far_away = "Meet the prospective recruit in person to continue.",
    candidate_line_of_sight_lost = "Move where the prospective recruit can see you.",
    conversation_unavailable = "The household cannot talk right now. Meet a resident somewhere safe.",
    named_candidate_no_longer_eligible = "Their circumstances changed. Ask the household about a new candidate.",
    name_candidate_first = "Ask the household to name a willing candidate first.",
    trial_actor_unavailable = "The recruit on trial is not currently available. Wait until you can meet them.",
}
function Social.reason(reason)
    local key = tostring(reason or "")
    return text("reason_" .. key, reasons[key]
        or "They cannot do that yet. Check that you are nearby, safe and have room to carry the supplies.")
end

local function report(id, message)
    if SC.Interaction then SC.Interaction.note(id, "system", message) end
    local actor = player()
    if actor then SC.GameplayUtil.call(actor, "setHaloNote", message) end
    if SC.UI then SC.UI.refresh() end
end

function Social.message(message)
    local modal = ISModalDialog:new(0, 0, 440, 180, message, false, nil, nil)
    modal:initialise(); modal:addToUIManager(); modal:setAlwaysOnTop(true)
    return modal
end

function Social.closePicker()
    if Social.picker then Social.picker:removeFromUIManager(); Social.picker = nil end
end

-- The selector is an explicit, bounded inventory query. A single chosen native
-- item is revalidated on Give; refreshing the Talk panel never rebuilds it.
function Social.offer(id, kind)
    local actor = player()
    local rows, reason, complete = SC.RelationshipHelp.catalog(id, kind, actor)
    if not rows then return Social.message(Social.reason(reason)) end
    if #rows == 0 and complete == false then return Social.message(text("search_limited",
        "Your inventory is too large to check everything at once. Move a food item or drinking bottle into your main inventory and try again.")) end
    if #rows == 0 then return Social.message(text("no_supplies",
        "You have no suitable supplies to offer. Check your inventory and bags; equipped, favourite and reserved items stay protected.")) end
    Social.closePicker()
    local core = getCore()
    local width = math.min(520, core:getScreenWidth() - 32)
    local height = math.min(350, core:getScreenHeight() - 32)
    local panel = ISPanel:new((core:getScreenWidth() - width) / 2,
        (core:getScreenHeight() - height) / 2, width, height)
    panel:initialise(); panel:instantiate()
    panel.backgroundColor = { r = .055, g = .065, b = .055, a = .98 }
    panel.borderColor = { r = .85, g = .53, b = .23, a = 1 }
    panel.moveWithMouse = true
    local status = SC.RelationshipHelp.describe(id, actor)
    if not status then return Social.message(Social.reason("help_unavailable")) end
    local metrics = SC.UI.layoutMetrics()
    local y = 16
    local function line(value)
        for _, part in ipairs(SC.UI.wrapText(UIFont.Small, value, width - 32)) do
            local label = ISLabel:new(16, y, metrics.fontHeight, part, .91, .91, .84, 1, UIFont.Small, true)
            label:initialise(); panel:addChild(label); y = y + metrics.infoLineHeight
        end
    end
    line(text("offer_to", "Offer help to %1", status.row.name))
    line(text("one_item", "Choose one item to hand over. It becomes theirs to keep and use."))
    local selector = ISComboBox:new(16, y + 8, width - 32, metrics.comboHeight or metrics.buttonHeight, panel, nil)
    selector:initialise()
    for _, row in ipairs(rows) do
        local label = tostring(row.name) .. " x1"
        if kind == "water" then
            label = text("whole_water", "Whole %1 (%2 L)", row.name,
                string.format("%.2f", row.litres or 0))
        end
        selector:addOptionWithData(label, row)
    end
    panel:addChild(selector)
    y = y + metrics.buttonHeight + 20
    if kind == "water" then line(text("water_warning", "This gives the whole container and all of its water.")) end
    local multiplier = kind == "food" and status.row.helpFoodMultiplier or status.row.helpWaterMultiplier
    if multiplier == 0 then line(text("repeat_none", "More supplies are welcome, but repeated gifts will not build more trust today."))
    elseif multiplier == .5 then line(text("repeat_less", "You already helped with this need today. Another gift has less effect."))
    else line(text("real_need", "Helping a real need builds trust. Small portions have a smaller effect.")) end
    local buttonY = y + 12
    local function give()
        if panel.scDone then return end
        local option = selector.options[selector.selected]
        local chosen = option and option.data
        if not chosen then return end
        panel.scDone = true
        local ok, why = SC.RelationshipHelp.give(id, kind, chosen, actor)
        Social.closePicker()
        local message = ok and (why == "help_appreciated"
            and text("appreciated", "%1 accepted your help. Your relationship improved.", status.row.name)
            or text("supplied", "%1 accepted your supplies. You have already helped with this need today.", status.row.name))
            or Social.reason(why)
        if ok then
            local current = SC.Commands.describe(id, actor)
            if current.relationshipTier ~= status.row.relationshipTier then
                message = message .. " " .. text("new_stage", "Now %1.", SC.UI.stateText(current.relationshipTier))
            end
        end
        report(id, message)
    end
    local giveButton = ISButton:new(16, buttonY, (width - 40) / 2, metrics.buttonHeight,
        text("give", "Give selected item"), nil, give)
    local cancel = ISButton:new(24 + (width - 40) / 2, buttonY, (width - 40) / 2,
        metrics.buttonHeight, text("cancel", "Cancel"), nil, Social.closePicker)
    for _, button in ipairs({ giveButton, cancel }) do button:initialise(); panel:addChild(button) end
    panel:setHeight(buttonY + metrics.buttonHeight + 16)
    panel:addToUIManager(); panel:setAlwaysOnTop(true)
    Social.picker = panel
    return panel
end

local function addButton(detail, panel, y, title, callback)
    local height = (detail.metrics or SC.UI.layoutMetrics()).buttonHeight
    local width, caption = panel:getWidth() - 32, title
    while #caption > 2 and SC.UI.textWidth(UIFont.Small, caption) > width - 16 do
        caption = string.sub(caption, 1, #caption - 1)
    end
    if caption ~= title then caption = string.sub(caption, 1, math.max(1, #caption - 3)) .. "..." end
    local button = ISButton:new(8, y, width, height, caption, nil, callback)
    button.tooltip = title
    button:initialise(); panel:addChild(button)
    return y + height + 5
end

function Social.joining(row)
    local group = row.factionId and SC.Factions and SC.Factions.group(row.factionId)
    if group and SC.FactionRecruitment then
        return SC.FactionRecruitment.summary(group), SC.FactionRecruitment.requirements(group), group
    end
end

function Social.reviewJoining(groupId)
    local group = SC.Factions and SC.Factions.group(groupId)
    if not group then return Social.message(Social.reason("help_unavailable")) end
    if not group.oddball then
        for _, member in ipairs(group.members or {}) do
            local record = member.actorId and SC.Registry and SC.Registry.byId(member.actorId)
            if record and record.actor and not SC.GameplayUtil.isDead(record.actor) then
                return SC.UI.open("talk", member.actorId)
            end
        end
    end
    return SC.UI.open("factions")
end

function Social.addJoiningLink(detail, panel, y, row)
    local id = row.id
    return addButton(detail, panel, y, text("ask", "Ask about joining"), function() SC.UI.open("talk", id) end)
end

function Social.signature(row)
    if not row then return "none" end
    local summary, requirements, group = Social.joining(row)
    return tostring(row.helpFoodMultiplier) .. ":" .. tostring(row.helpWaterMultiplier)
        .. ":" .. tostring(math.floor((row.relationshipProgress and row.relationshipProgress.fraction or 0) * 100))
        .. ":" .. tostring(row.recentMemory) .. ":" .. tostring((row.hunger or 0) >= .62)
        .. ":" .. tostring((row.thirst or 0) >= .62) .. ":" .. tostring(row.woundCount or #(row.wounds or {}))
        .. ":" .. tostring(summary and summary.status) .. ":" .. tostring(summary and summary.canAsk)
        .. ":" .. tostring(summary and summary.canDecide) .. ":" .. table.concat(requirements or {}, ",")
        .. ":" .. tostring(summary and summary.contractsCompleted)
        .. ":" .. tostring(group and group.id) .. ":" .. tostring(group and group.standing)
        .. ":" .. tostring(summary and summary.canStartTrial) .. ":" .. tostring(summary and summary.candidateName)
        .. ":" .. tostring(summary and math.ceil(summary.cooldownHours))
        .. ":" .. tostring(summary and math.ceil(summary.hoursUntilDecision))
end

function Social.build(detail, panel, y, row)
    local id = row.id
    local function line(value) y = detail:addInformationLine(panel, y, "UI_SC_Info_Message", value) end
    y = detail:addSection(panel, y, "UI_SC_Social_relationship")
    local progress = row.relationshipProgress or SC.Relationship.progress(row)
    local stage = SC.UI.stateText(progress.stage)
    line(progress.nextStage and text("progress", "%1: %2 toward %3", stage,
        tostring(math.floor(progress.fraction * 100)) .. "%", SC.UI.stateText(progress.nextStage))
        or text("closest", "%1: your strongest bond", stage))
    local bar = ISPanel:new(8, y + 2, panel:getWidth() - 32, 7)
    bar:initialise()
    function bar:render()
        self:drawRect(0, 0, self:getWidth(), 7, .65, .2, .22, .19)
        self:drawRect(0, 0, self:getWidth() * progress.fraction, 7, .95, .92, .53, .2)
    end
    panel:addChild(bar); y = y + 16
    line(text("guidance", "Help with real needs, keep them safe and spend time together. Repeated gifts have diminishing returns."))
    for _, reason in ipairs(row.relationshipReasons or {}) do line(reason) end
    y = detail:addSection(panel, y + 3, "UI_SC_Social_help")
    if (row.hunger or 0) >= .62 then
        y = addButton(detail, panel, y, text("food", "Offer food..."), function() Social.offer(id, "food") end)
    end
    if (row.thirst or 0) >= .62 then
        y = addButton(detail, panel, y, text("water", "Offer drinking water..."), function() Social.offer(id, "water") end)
    end
    if (tonumber(row.woundCount) or #(row.wounds or {})) > 0 then
        y = addButton(detail, panel, y, text("medical", "Help with injuries..."), function()
            local status, why = SC.RelationshipHelp.describe(id, player())
            if status then SC.UI.openHealth(status.actor, player()) else Social.message(Social.reason(why)) end
        end)
    end
    if (row.hunger or 0) < .62 and (row.thirst or 0) < .62 and #(row.wounds or {}) == 0 then
        line(text("no_need", "They do not need food, water or medical care right now."))
    end
    if row.recruited == true then return y + 4 end
    y = detail:addSection(panel, y + 3, "UI_SC_Social_joining")
    local recruitment, requirements, group = Social.joining(row)
    if recruitment then
        line(text("separate", "Personal trust and household standing are separate. Gifts do not complete household contracts."))
        line(text("household", "%1: %2 standing. Contracts: %3/%4.", group.name or group.id,
            SC.UI.stateText(group.standing), recruitment.contractsCompleted, recruitment.contractsRequired))
        for _, why in ipairs(requirements) do line(Social.reason(why)) end
        if recruitment.cooldownHours > 0 then line(text("cooldown", "Ask again in about %1 game hours.", math.ceil(recruitment.cooldownHours))) end
        if recruitment.candidateName then line(text("candidate", "Prospective recruit: %1", recruitment.candidateName)) end
        if recruitment.status == "trial" then line(text("trial", "Field trial: about %1 game hours until a decision.", math.ceil(recruitment.hoursUntilDecision))) end
        local action, title
        if recruitment.canAsk then action, title = "ask", text("ask", "Ask about joining")
        elseif recruitment.canStartTrial then action, title = "startTrial", SC.UI.text("UI_SC_Faction_RecruitmentStartTrial")
        elseif recruitment.canDecide then action, title = "decide", SC.UI.text("UI_SC_Faction_RecruitmentAskDecision") end
        y = addButton(detail, panel, y, title or text("ask", "Ask about joining"), function()
            if not action then Social.message(table.concat((function()
                local lines = {}; for _, why in ipairs(SC.FactionRecruitment.requirements(group.id)) do lines[#lines+1] = Social.reason(why) end
                if #lines == 0 then lines[1] = text("household_panel", "Open the household panel to review their current recruitment decision.") end
                return lines end)(), "\n")); return end
            local accepted, why = SC.FactionRecruitment[action](group.id, player(), false)
            report(id, accepted and text("joining_updated", "The household's recruitment decision has been updated.") or Social.reason(why))
        end)
    elseif row.factionId then
        line(text("story", "This person has their own joining conditions. Ask about their situation."))
    else
        line(text("independent", "This survivor is independent. You can invite them without a household contract."))
        y = detail:addCommand(panel, y, "UI_SC_Social_ask", "recruit", nil)
    end
    return y + 4
end

return Social
