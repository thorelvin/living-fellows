-- SPDX-License-Identifier: MIT
-- Real transfer/relationship paths, with only perception held quiet at the edge.
local SC, f = SurvivorCompanion, SurvivorCompanion.TestFixture
local check, player = f.check, f.player
local guest = f.actor("essential-help-guest", 1, 1, { recruited = false })
f.registry[guest.id] = { actor = guest, runtime = {} }
guest.hunger, guest.thirst = .8, .8
local senses = SC.Senses.snapshot
SC.Senses.snapshot = function() return { valid = true, time = f.clock, threatCount = 0, pressure = 0,
    immediateCount = 0, scanComplete = true, scanDiscoveryComplete = true,
    scanVisualComplete = true, player = { danger = 0 } } end
local peach = f.item("Base.HelpPeach", "Food", { hungerChange = -.2 })
local maggots = f.item("Base.HelpMaggots", "Food", { hungerChange = -.01 })
function maggots:getFoodType() return "insect" end
local spoiled = f.item("Base.HelpRotten", "Food", { hungerChange = -.2, rotten = true })
local favourite = f.item("Base.HelpFavourite", "Food", { hungerChange = -.2, favorite = true })
local bag = f.item("Base.HelpBag", "Container")
bag.nestedInventory = f.inventory({ peach, maggots, spoiled, favourite })
function bag.nestedInventory:getContainingItem() return bag end
player.inventory:AddItem(bag)
local catalog, reason = SC.RelationshipHelp.catalog(guest.id, "food", player)
check(catalog and #catalog >= 2 and catalog[1].item == peach,
    "help finds food inside bags and ranks normal food ahead of emergency food: " .. tostring(reason))
local selected
for _, row in ipairs(catalog) do
    check(row.item ~= spoiled, "rotten food is never offered as help")
    check(row.item ~= favourite, "favourite food stays protected")
    if row.item == peach then selected = row end
end
local before = SC.Commands.describe(guest.id, player)
-- Personality initialization may provide a private memento. It is unrelated to
-- trade; remove the fixture's initial possession to exercise an empty recipient.
local initial = {}
for _, item in ipairs(guest.inventory.items) do initial[#initial + 1] = item end
for _, item in ipairs(initial) do guest.inventory:Remove(item) end
check(before.recruited == false and #guest.inventory.items == 0,
    "help recipient has no trade stock and is not recruited: recruited=" .. tostring(before.recruited)
        .. " inventory=" .. tostring(#guest.inventory.items))
local accepted, why = SC.RelationshipHelp.give(guest.id, "food", selected, player)
local after = SC.Commands.describe(guest.id, player)
check(accepted and guest.inventory:contains(peach) and not bag.nestedInventory:contains(peach)
    and peach:getContainer() == guest.inventory, "the exact offered food changes owner once: " .. tostring(why))
check(after.trust == before.trust + 3 and after.bond == before.bond + 2
    and after.recruited == false and guest.hunger == .8,
    "a real hungry stranger gains existing meal credit without scripted eating or recruitment")
accepted = SC.RelationshipHelp.give(guest.id, "food", selected, player)
check(not accepted and SC.Commands.describe(guest.id, player).trust == after.trust,
    "a stale or double Give click cannot duplicate the item or relationship credit")
local second = f.item("Base.HelpSecond", "Food", { hungerChange = -.2 })
player.inventory:AddItem(second)
check(SC.RelationshipHelp.give(guest.id, "food", { item = second, container = player.inventory }, player),
    "a second real handover is allowed")
local reduced = SC.Commands.describe(guest.id, player)
check(reduced.trust == after.trust + 1.5 and reduced.bond == after.bond + 1,
    "repeat help has half effect in the saved game-day window")
local third = f.item("Base.HelpThird", "Food", { hungerChange = -.2 })
player.inventory:AddItem(third)
check(SC.RelationshipHelp.give(guest.id, "food", { item = third, container = player.inventory }, player)
    and SC.Commands.describe(guest.id, player).trust == reduced.trust,
    "further help gives supplies without farming trust")
local saved = SC.Commands.export(guest)
check(saved and saved.personality and saved.personality.care or saved and saved.care,
    "help receipts are part of the existing exported relationship state")
SC.Commands.reset(guest)
check(SC.Commands.describe(guest.id, player).trust == reduced.trust
    and SC.Relationship.helpMultiplier(SC.Commands.peek(guest), "food") == 0,
    "reload from persisted command data retains repeat-gift credit and receipts")
SC.Relationship.reset(guest)
SC.Relationship.observe(guest, player, {}, SC.Commands.peek(guest))
guest.hunger, f.clock = .3, f.clock + 2000
SC.Commands.observeRelationship(guest, player, {})
check(SC.Commands.describe(guest.id, player).trust == reduced.trust,
    "using an offered meal does not award the same help twice")
guest.hunger, f.clock = .8, f.clock + 91000
SC.Commands.observeRelationship(guest, player, {})
guest.hunger, f.clock = .3, f.clock + 2000
SC.Commands.observeRelationship(guest, player, {})
check(SC.Commands.describe(guest.id, player).trust == reduced.trust + 3,
    "a later shared meal earns ordinary trust after consuming the single gift receipt")
local foodAfter=SC.Commands.describe(guest.id, player).trust
SC.Relationship.noteHelp(SC.Commands.peek(guest),"water",1)
local waterAfter=SC.Commands.describe(guest.id, player).trust
guest.hunger, f.clock = .8, f.clock + 91000
SC.Commands.observeRelationship(guest, player, {})
guest.hunger, f.clock = .3, f.clock + 2000
SC.Commands.observeRelationship(guest, player, {})
check(waterAfter>=foodAfter and SC.Commands.describe(guest.id, player).trust==waterAfter+3,
    "water handover does not suppress an unrelated shared meal")
local state = SC.Commands.peek(guest)
f.clock = f.clock + 25 * 3600000
check(SC.Relationship.helpMultiplier(state, "food") == 1, "a new game-day window restores ordinary help benefit")
local water = f.item("Base.HelpWater", "Water")
water.fluid = { getAmount = function() return .5 end, getCapacity = function() return 1 end,
    isEmpty = function() return false end, isWaterOnlySource = function() return true end }
function water:getFluidContainer() return self.fluid end
player.inventory:AddItem(water)
local waters = SC.RelationshipHelp.catalog(guest.id, "water", player)
local chosen
for _, row in ipairs(waters or {}) do if row.item == water then chosen = row end end
check(chosen and chosen.litres == .5, "the offered bottle shows its measured contents")
local oldThirst = guest.thirst
check(SC.RelationshipHelp.give(guest.id, "water", chosen, player)
    and guest.inventory:contains(water) and guest.thirst == oldThirst,
    "water hands over the entire exact container; native drinking remains separate")
guest.hunger = .8
local rejected = f.item("Base.HelpRejected", "Food", { hungerChange = -.2 })
player.inventory:AddItem(rejected)
guest.inventory.rejectAdd = true
local prior = SC.Commands.describe(guest.id, player).trust
accepted = SC.RelationshipHelp.give(guest.id, "food", { item = rejected, container = player.inventory }, player)
guest.inventory.rejectAdd = nil
check(not accepted and player.inventory:contains(rejected) and rejected:getContainer() == player.inventory
    and SC.Commands.describe(guest.id, player).trust == prior,
    "a failed native attach rolls back the item and grants no benefit")
guest.worldX = 30
accepted, why = SC.RelationshipHelp.give(guest.id, "food", { item = rejected, container = player.inventory }, player)
check(not accepted and why == "help_too_far" and player.inventory:contains(rejected),
    "confirmation rechecks the current recipient and distance")
check(SC.Interaction.recruitedOnly.relationship ~= true,
    "relationship conversation is available before recruitment")
for _, sample in ipairs({ { 0, "cautious" }, { 10, "ally" }, { 30, "trusted" },
    { 55, "close" }, { 80, "family" } }) do
    local progress = SC.Relationship.progress({ trust = sample[1], bond = sample[1] })
    check(progress.stage == sample[2] and progress.fraction >= 0 and progress.fraction <= 1,
        "relationship stages retain the original threshold " .. tostring(sample[1]))
end
local group = { id = "essential-help-house", name = "Household", discovered = true,
    standing = "Wary", members = { { key = "one", alive = true }, { key = "two", alive = true } } }
local required = SC.FactionRecruitment.requirements(group)
check(group.recruitment==nil,"reading recruitment gates never initializes saved household state")
local summaryFn=SC.FactionRecruitment.summary
SC.FactionRecruitment.summary=function() return nil,"recruitment_summary_copy_failed" end
check(SC.FactionRecruitment.requirements(group)[1]=="recruitment_summary_copy_failed",
    "a failed recruitment snapshot becomes a readable blocker rather than a nil dereference")
SC.FactionRecruitment.summary=summaryFn
local gates = {}; for _, value in ipairs(required) do gates[value] = true end
check(gates.trusted_standing_required and gates.more_contracts_required,
    "household explanations show standing and contract requirements together")
check(SC.FactionRecruitment.summary(group).canAsk == false,
    "personal help does not bypass household recruitment balance")
local oldHostile = SC.Commands.peek(guest).care.playerHostile
SC.Commands.peek(guest).care.playerHostile = true
guest.worldX = nil
accepted, why = SC.RelationshipHelp.give(guest.id, "food", { item = rejected, container = player.inventory }, player)
check(not accepted and why == "help_hostile" and player.inventory:contains(rejected),
    "an individual hostile survivor cannot receive a gift to bypass conflict")
SC.Commands.peek(guest).care.playerHostile = oldHostile
SC.Senses.snapshot = senses
print("BEHAVIOUR_RELATIONSHIP_HELP_PASS checks=" .. tostring(f.checks()))
