-- SPDX-License-Identifier: MIT
local SC, UI, F = SurvivorCompanion, SurvivorCompanion.UI, BasePolicyFixture
local saved = { factions = SC.Factions, recruitment = SC.FactionRecruitment,
    util = SC.GameplayUtil }
SC.GameplayUtil = { text = function(_, fallback, ...)
    local text = fallback
    for i, value in ipairs({ ... }) do
        text = string.gsub(text, "%%" .. tostring(i), function() return tostring(value) end)
    end
    return text
end }
local group = { id = "house", name = "The household", standing = "Wary" }
local summary = { status = "available", canAsk = false, contractsCompleted = 0,
    contractsRequired = 2, cooldownHours = 0, hoursUntilDecision = 0 }
SC.Factions = { group = function(id) return id == group.id and group end }
SC.FactionRecruitment = { summary = function() return summary end,
    requirements = function() return { "trusted_standing_required", "more_contracts_required" } end }
local row = { id = "guest", name = "Alex", recruited = false, factionId = group.id,
    hunger = .8, thirst = .8, woundCount = 1, wounds = { {} },
    relationshipProgress = { stage = "ally", nextStage = "trusted", fraction = .25 },
    relationshipReasons = { "You gave me food when I was hungry." } }
local detail = setmetatable({}, { __index = F.classes.SCUIDetail })
for _, width in ipairs({ 280, 420, 760 }) do
    for _, font in ipairs({ 16, 22 }) do
        F.fontHeight = font
        detail.metrics = UI.layoutMetrics()
        local panel = ISPanel:new(0, 0, width, 700)
        local bottom = SC.UISocial.build(detail, panel, 8, row)
        local joining, food, water, medical, percent = false, false, false, false, false
        for _, child in ipairs(panel.childrenInOrder) do
            assert(child.y >= 0 and child.y + child.height <= bottom + 8,
                "social controls stay within the scrollable content")
            if child.name then
                assert(child.x + child.width <= width - 8, "social text wraps before the panel edge")
                assert(not string.find(child.name, "%%", 1, true), "progress contains one percent sign")
                if string.find(child.name, "25%", 1, true) then percent = true end
            end
            joining = joining or child.title == "Ask about joining"
            food = food or child.tooltip == "Offer food..."
            water = water or child.tooltip == "Offer drinking water..."
            medical = medical or child.tooltip == "Help with injuries..."
        end
        assert(joining and food and water and medical and percent,
            "pre-recruit Talk exposes each real need and joining even before household eligibility")
    end
end
local signature = SC.UISocial.signature(row)
group.standing = "Tolerated"
assert(SC.UISocial.signature(row) ~= signature, "household standing refreshes the Talk card")
signature = SC.UISocial.signature(row)
summary.contractsCompleted = 1
assert(SC.UISocial.signature(row) ~= signature, "household contract progress refreshes the Talk card")
signature = SC.UISocial.signature(row)
row.relationshipProgress.fraction = .26
assert(SC.UISocial.signature(row) ~= signature, "personal progress refreshes without a stage change")
signature = SC.UISocial.signature(row)
row.thirst = .2
assert(SC.UISocial.signature(row) ~= signature, "a satisfied need refreshes its help action")
local help,commands,interaction,refresh,combo=SC.RelationshipHelp,SC.Commands,SC.Interaction,UI.refresh,ISComboBox
local methods={}
for _,key in ipairs({"instantiate","addToUIManager","removeFromUIManager","setAlwaysOnTop","setHeight"}) do
    methods[key]={value=ISPanel[key]};ISPanel[key]=function() end
end
ISComboBox=ISPanel:derive("ISComboBox")
function ISComboBox:addOptionWithData(label,data) self.options=self.options or {};self.options[#self.options+1]={data=data};self.selected=1 end
SC.Interaction=nil;UI.refresh=function() end
SC.GameplayUtil.call=function() return true end
local transfers=0
SC.RelationshipHelp={catalog=function() return {{name="Peach",item={},tier=1}} end,
    describe=function() return {row=row} end,
    give=function() transfers=transfers+1;return true,"help_appreciated" end}
SC.Commands={describe=function() return nil end}
local picker=SC.UISocial.offer(row.id,"food")
local giveButton
for _,child in ipairs(picker.childrenInOrder) do if child.title=="Give selected item" then giveButton=child end end
assert(giveButton,"actual offer panel exposes its confirmation button")
giveButton.onClick(giveButton.target,giveButton)
assert(transfers==1 and SC.UISocial.picker==nil,"a recipient disappearing after handover cannot crash or replay the transfer")
SC.RelationshipHelp,SC.Commands,SC.Interaction,UI.refresh,ISComboBox=help,commands,interaction,refresh,combo
for key,entry in pairs(methods) do ISPanel[key]=entry.value end
SC.Factions, SC.FactionRecruitment, SC.GameplayUtil = saved.factions, saved.recruitment, saved.util
F.fontHeight = 16
print("UI_SOCIAL_PASS: need actions, readable bounded layouts, joining gates and meaningful refresh")
