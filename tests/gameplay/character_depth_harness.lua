-- SPDX-License-Identifier: MIT
-- Distinct subject regressions retained from the former gameplay monolith.
local f = assert(SurvivorCompanion.TestFixture)
local check, item, inventory, actor, zombie = f.check, f.item, f.inventory, f.actor, f.zombie
local bodyPart, bodyDamage, buildKit = f.bodyPart, f.bodyDamage, f.buildKit
local cell, registry, player, containerObject = f.cell, f.registry, f.player, f.containerObject
local makeSquare, squares, movementLog, squareKey = f.makeSquare, f.squares, f.movementLog, f.squareKey
function SurvivorCompanion.__testCharacterDepth()
local Background = SurvivorCompanion.Background
local Personality = SurvivorCompanion.Personality
local PersonalItems = SurvivorCompanion.PersonalItems
local Objectives = SurvivorCompanion.Objectives
local Journal = SurvivorCompanion.Journal

local backgroundA = Background.initialize("sc-background-deterministic", {})
local backgroundB = Background.initialize("sc-background-deterministic", {})
check(backgroundA.profession == backgroundB.profession
    and backgroundA.aptitude == backgroundB.aptitude
    and backgroundA.professionId == "base:" .. backgroundA.profession,
    "companion background is deterministic and uses a vanilla Build 42 profession id")
local lumberjackJogger = Background.initialize("explicit-background", {
    profession = "lumberjack", aptitude = "jogger",
})
check(Background.professionLabel(lumberjackJogger) == "Lumberjack"
    and Background.aptitudeLabel(lumberjackJogger) == "Jogger"
    and Background.preferredRole(lumberjackJogger) == "builder"
    and Background.decisionModifier(lumberjackJogger, "combat") == 2
    and Background.decisionModifier(lumberjackJogger, "retreat") == 2
    and Background.objectiveModifier(lumberjackJogger, "improve_shelter") == 26
    and Background.baseJobModifier(lumberjackJogger, "build") == 5
    and string.find(Background.historyText(lumberjackJogger), "logging crews", 1, true) ~= nil,
    "profession and aptitude independently influence role, choices, goals, work, and history")

local oldResourceLocation, oldCharacterProfession = ResourceLocation, CharacterProfession
local oldProfessionDefinition, oldCharacterTrait, oldPerks = CharacterProfessionDefinition,
    CharacterTrait, Perks
local professionObject = { id = "base:lumberjack" }
local professionTrait, aptitudeTrait = { id = "base:axeman" }, { id = "base:jogger" }
local grantedTraits = { professionTrait }
function grantedTraits:size() return #self end
function grantedTraits:get(index) return self[index + 1] end
ResourceLocation = { of = function(id) return id end }
CharacterProfession = { get = function(id) return id == "base:lumberjack" and professionObject or nil end }
-- Every trait id resolves, so band and character traits really reach the actor
-- and can be read back the way the character sheet reads them.
local traitObjects = { ["base:jogger"] = aptitudeTrait }
CharacterTrait = { get = function(id)
    if type(id) ~= "string" then return nil end
    if traitObjects[id] == nil then
        traitObjects[id] = { id = id, getName = function() return id end }
    end
    return traitObjects[id]
end }
CharacterProfessionDefinition = { getCharacterProfessionDefinition = function(profession)
    if profession ~= professionObject then return nil end
    return {
        getGrantedTraits = function() return grantedTraits end,
    }
end }
Perks = { Axe = "Axe", Strength = "Strength", Maintenance = "Maintenance",
    Sprinting = "Sprinting", Fitness = "Fitness", Nimble = "Nimble",
    Cooking = "Cooking", SmallBlade = "SmallBlade" }
local descriptor = { profession = nil }
function descriptor:setCharacterProfession(profession) self.profession = profession end
function descriptor:getCharacterProfession() return self.profession end
function descriptor:setProfessionSkills() self.skillsSet = true end
local known = { rows = {}, set = {} }
function known:add(trait) self.rows[#self.rows + 1] = trait; self.set[trait] = true; return true end
function known:size() return #self.rows end
function known:get(index) return self.rows[index + 1] end
local nativeBackgroundActor = { levels = {}, traits = known }
function nativeBackgroundActor:getDescriptor() return descriptor end
function nativeBackgroundActor:getCharacterTraits()
    return { getKnownTraits = function() return known end }
end
function nativeBackgroundActor:hasTrait(trait) return known.set[trait] == true end
function nativeBackgroundActor:modifyTraitXPBoost() return true end
function nativeBackgroundActor:getPerkLevel(perk) return self.levels[perk] or 0 end
function nativeBackgroundActor:setPerkLevelDebug(perk, level) self.levels[perk] = level end
function nativeBackgroundActor:applyProfessionRecipes() self.professionRecipes = true end
function nativeBackgroundActor:applyCharacterTraitsRecipes() self.traitRecipes = true end
local nativeApplied, nativeReason = Background.applyNative(nativeBackgroundActor, lumberjackJogger)
check(nativeApplied and nativeReason == "native_background_applied"
    and descriptor.profession == professionObject and descriptor.skillsSet == true
    and nativeBackgroundActor:hasTrait(professionTrait)
    and nativeBackgroundActor:hasTrait(aptitudeTrait)
    and nativeBackgroundActor.levels.Axe == 2
    and nativeBackgroundActor.professionRecipes and nativeBackgroundActor.traitRecipes,
    "native background application assigns profession, traits, recipes, and conservative skills")

local lumberjackAbilities = Background.abilities(lumberjackJogger)
check((nativeBackgroundActor.levels.Strength or 0) == lumberjackAbilities.Strength
        and (nativeBackgroundActor.levels.Fitness or 0) == lumberjackAbilities.Fitness
        and (nativeBackgroundActor.levels.Nimble or 0) == lumberjackAbilities.Nimble
        and (nativeBackgroundActor.levels.Sprinting or 0) == lumberjackAbilities.Sprinting,
    "the four ability scores reach the actor exactly as the background rolled them")

do
    local carried = { weight = 9 }
    function carried:getCapacityWeight() return self.weight end
    function carried:getEffectiveCapacity() return 50 end
    local person = { capacity = 8, strengthModifier = 1.58,
        penalty = 0, carryTrait = nil, maxWeightDelta = 1, deltaWrites = 0 }
    local body = {}
    -- BodyDamage.UpdateStrength as Build 42.21 runs it on every character
    -- update: base 8 x Strength modifier, minus moodle penalties, then x the
    -- IsoPlayer maxWeightDelta field.
    function body:UpdateStrength()
        person.capacity = math.max(0, math.floor(8 * person.strengthModifier)
            - person.penalty)
        person.capacity = math.floor(person.capacity * person.maxWeightDelta)
    end
    function person:getBodyDamage() return body end
    function person:getMaxWeight() return self.capacity end
    function person:setMaxWeight(value) self.capacity = value end
    -- The engine stores the delta as a float: 0.9 reads back as 0.8999999761.
    function person:getMaxWeightDelta() return self.maxWeightDelta - 0.0000000239 end
    function person:setMaxWeightDelta(value)
        self.maxWeightDelta, self.deltaWrites = value, self.deltaWrites + 1
    end
    function person:getInventory() return carried end
    function person:hasTrait(trait)
        return trait and trait.id == "base:" .. tostring(self.carryTrait)
    end
    check(Background.refreshCarryCapacity(person) == true
            and person.capacity == 12,
        "ordinary Strength uses the native carrying calculation")
    person.strengthModifier, person.carryTrait = 2.09, "stout"
    check(Background.refreshCarryCapacity(person) == true
            and person.capacity == 20
            and Background.refreshCarryCapacity(person) == true
            and person.capacity == 20,
        "Stout uses the player multiplier without compounding on refresh")
    body:UpdateStrength()
    check(person.capacity == 20,
        "the engine's next Strength update keeps the Stout multiplier: "
            .. tostring(person.capacity))
    person.penalty = 2
    check(Background.refreshCarryCapacity(person) == true
            and person.capacity == 17,
        "current condition reduces the companion carrying limit")
    local writes = person.deltaWrites
    person.carryTrait = "feeble"
    Background.refreshCarryCapacity(person)
    Background.refreshCarryCapacity(person)
    check(person.deltaWrites == writes + 1 and person.capacity == 12,
        "a float read-back of the Feeble multiplier is not rewritten on every pulse")
    person.carryTrait = "stout"
    Background.refreshCarryCapacity(person)
    local weight, capacity, ratio = SurvivorCompanion.GameplayUtil.inventoryLoad(person)
    check(weight == 9 and capacity == 50 and ratio > 0.17 and ratio < 0.19,
        "physical load uses the inventory's hard limit")
    local carryWeight, carryLimit, carryRatio =
        SurvivorCompanion.GameplayUtil.carryLoad(person)
    check(carryWeight == 9 and carryLimit == 17 and carryRatio > 0.52
            and carryRatio < 0.54,
        "carry load uses the character's Strength and condition limit")
    local shown = actor("sc-carry-summary", 0, 0)
    function shown.inventory:getCapacityWeight() return carryWeight end
    function shown.inventory:getEffectiveCapacity() return capacity end
    function shown:getMaxWeight() return carryLimit end
    registry[shown.id] = shown
    local summary = SurvivorCompanion.Commands.describe(shown.id, player)
    check(summary.loadWeight == carryWeight and summary.loadCapacity == carryLimit
            and summary.loadRatio == carryRatio
            and summary.loadRole == SurvivorCompanion.Logistics.roleOf(shown),
        "Loadout describes actual carrying weight, Strength capacity and ratio without changing the role")
    registry[shown.id] = nil
    table.remove(shown.square.moving)
end

-- Build 42.20.4 seeds Strength and Fitness at 5 during character creation, and
-- getClimbingFailChanceFloat is int(sqrt(2*Fitness + 2*Strength + 2*Nimble -
-- moodle penalties)). A companion left at 0/0 scores 0, which
-- ClimbOverWallState.setParams turns into an unconditional climb failure once
-- any heavy-load moodle is present. 24 of the 31 backgrounds name neither perk,
-- so the baseline has to come from the seed rather than from the skill map.
local cookOrganized = Background.initialize("explicit-background", {
    profession = "burgerflipper", aptitude = "organized",
})
local cookProfession = { id = "base:burgerflipper" }
local organizedTrait = { id = "base:organized" }
CharacterProfession = { get = function(id)
    return id == "base:burgerflipper" and cookProfession or nil
end }
traitObjects["base:organized"] = organizedTrait
CharacterProfessionDefinition = { getCharacterProfessionDefinition = function() return nil end }
local cookDescriptor = { profession = nil }
function cookDescriptor:setCharacterProfession(profession) self.profession = profession end
function cookDescriptor:getCharacterProfession() return self.profession end
function cookDescriptor:setProfessionSkills() self.skillsSet = true end
local cookKnown = { rows = {}, set = {} }
function cookKnown:add(trait) self.rows[#self.rows + 1] = trait; self.set[trait] = true; return true end
local cookActor = { levels = {} }
function cookActor:getDescriptor() return cookDescriptor end
function cookActor:getCharacterTraits() return { getKnownTraits = function() return cookKnown end } end
function cookActor:hasTrait(trait) return cookKnown.set[trait] == true end
function cookActor:modifyTraitXPBoost() return true end
function cookActor:getPerkLevel(perk) return self.levels[perk] or 0 end
function cookActor:setPerkLevelDebug(perk, level) self.levels[perk] = level end
function cookActor:applyProfessionRecipes() self.professionRecipes = true end
function cookActor:applyCharacterTraitsRecipes() self.traitRecipes = true end
local cookApplied, cookReason = Background.applyNative(cookActor, cookOrganized)
local cookAbilities = Background.abilities(cookOrganized)
check(cookApplied and cookReason == "native_background_applied"
    and (cookActor.levels.Strength or 0) == cookAbilities.Strength
    and (cookActor.levels.Fitness or 0) == cookAbilities.Fitness
    and cookActor.levels.Cooking == 2 and cookActor.levels.SmallBlade == 1,
    "a background naming neither physical perk still receives scored abilities")

-- Ability scores and character traits
do
    -- No companion may spawn unable to cross a fence. Build 42.20.4 scores a
    -- climb as int(sqrt(2*Fitness + 2*Strength + 2*Nimble - penalties)), and
    -- ClimbOverWallState.setParams turns a 0 there plus any heavy-load moodle
    -- into an unconditional failure -- a survivor stranded by the first fence.
    local floorHeld, varied, seen = true, false, {}
    local first
    for index = 1, 40 do
        local background = Background.initialize("ability-spread-" .. index, {})
        local scores = Background.abilities(background)
        if scores.Strength < 3 or scores.Fitness < 3 then floorHeld = false end
        if scores.Strength > 10 or scores.Fitness > 10
            or scores.Nimble > 10 or scores.Sprinting > 10 then floorHeld = false end
        local signature = scores.Strength .. ":" .. scores.Fitness
            .. ":" .. scores.Nimble .. ":" .. scores.Sprinting
        first = first or signature
        if signature ~= first then varied = true end
        seen[signature] = true
    end
    check(floorHeld, "every rolled companion stays inside the climbable ability range")
    check(varied, "companions do not all roll the same ability scores")

    local stable = Background.initialize("ability-stability", {})
    local once, twice = Background.abilities(stable), Background.abilities(stable)
    check(once.Strength == twice.Strength and once.Fitness == twice.Fitness
            and once.Nimble == twice.Nimble and once.Sprinting == twice.Sprinting,
        "a companion rolls the same ability scores every time they are asked for")
    -- Character traits are reproduced from the persisted seed rather than
    -- stored, so a reload must roll the same person from the same record.
    local reloaded = Background.initialize("a-different-identity-entirely", stable)
    local beforeTraits, afterTraits = "", ""
    for _, entry in ipairs((Background.characterTraits(stable))) do
        beforeTraits = beforeTraits .. entry.id .. ","
    end
    for _, entry in ipairs((Background.characterTraits(reloaded))) do
        afterTraits = afterTraits .. entry.id .. ","
    end
    check(reloaded.abilitySeed == stable.abilitySeed
            and Background.abilities(reloaded).Strength == once.Strength
            and Background.abilities(reloaded).Fitness == once.Fitness
            and afterTraits == beforeTraits,
        "a restored background keeps its own seed instead of rerolling the survivor")

    -- The mapping is Build 42.20.4's own, from XpUpdate.lua's LevelPerk
    -- listener, so the traits the engine reads agree with the levels the mod
    -- writes with setPerkLevelDebug (which does not fire that event).
    check(Background.bandTrait("Strength", 0).id == "base:weak"
            and Background.bandTrait("Strength", 4).id == "base:feeble"
            and Background.bandTrait("Strength", 5) == nil
            and Background.bandTrait("Strength", 7).id == "base:stout"
            and Background.bandTrait("Strength", 10).id == "base:strong"
            and Background.bandTrait("Fitness", 1).id == "base:unfit"
            and Background.bandTrait("Fitness", 9).id == "base:athletic",
        "band traits follow the engine's own level mapping")

    local budgetHeld, mismatchHeld, traitsVaried = true, true, false
    local firstTraits
    for index = 1, 40 do
        local background = Background.initialize("trait-spread-" .. index, {})
        local traits, spent = Background.characterTraits(background)
        if spent > 6 or spent < -6 then budgetHeld = false end
        local signature, chosen = "", {}
        for _, entry in ipairs(traits) do
            signature = signature .. entry.id .. ","
            chosen[entry.id] = true
        end
        if chosen["base:brave"] and chosen["base:cowardly"] then mismatchHeld = false end
        if chosen["base:inconspicuous"] and chosen["base:conspicuous"] then mismatchHeld = false end
        firstTraits = firstTraits or signature
        if signature ~= firstTraits then traitsVaried = true end
    end
    check(budgetHeld, "character traits stay inside the points budget")
    check(mismatchHeld, "mutually exclusive traits are never taken together")
    check(traitsVaried, "companions do not all roll the same character traits")

    local officer = Background.initialize("mismatch-check",
        { profession = "fireofficer", aptitude = "brave" })
    local officerTraits = Background.characterTraits(officer)
    local cowardly = false
    for _, entry in ipairs(officerTraits) do
        if entry.id == "base:cowardly" or entry.id == "base:smoker" then cowardly = true end
    end
    check(not cowardly, "a profession never rolls a trait that contradicts it")

    local sheet = Background.sheet(nativeBackgroundActor, lumberjackJogger)
    local sheetStrength
    for _, entry in ipairs(sheet.abilities) do
        if entry.name == "Strength" then sheetStrength = entry end
    end
    check(sheet.profession == "Lumberjack" and #sheet.abilities == 4
            and sheetStrength ~= nil
            and sheetStrength.level == lumberjackAbilities.Strength,
        "the character sheet reports the live actor's ability scores")

    -- The band trait the engine derives from a level, and this companion's own
    -- rolled traits, both have to actually reach the actor: the sheet reads the
    -- actor back, so anything it shows is something the engine can also see.
    local expectedBand = Background.bandTrait("Strength", lumberjackAbilities.Strength)
    local rolled = Background.characterTraits(lumberjackJogger)
    local onActor = {}
    for _, trait in ipairs(sheet.traits) do onActor[trait.id] = true end
    local rolledPresent = #rolled == 0
    for _, entry in ipairs(rolled) do
        if onActor[entry.id] then rolledPresent = true end
    end
    check((expectedBand == nil or onActor[expectedBand.id] == true) and rolledPresent
            and sheetStrength.band == (expectedBand and expectedBand.label or nil),
        "band traits and rolled character traits are applied to the actor, not just computed")
    check(Background.traitLabel("base:thickskinned") == "Thick Skinned"
            and Background.traitLabel("base:strong") == "Strong"
            and Background.traitLabel("base:jogger") == "Jogger"
            and Background.traitLabel("Nutritionist2") == "Nutritionist"
            and Background.traitLabel("base:unmapped") == "Unmapped",
        "every trait on the sheet reads as words rather than a script id")
end

ResourceLocation, CharacterProfession = oldResourceLocation, oldCharacterProfession
CharacterProfessionDefinition, CharacterTrait, Perks = oldProfessionDefinition,
    oldCharacterTrait, oldPerks

local profileA = Personality.initialize("sc-depth-deterministic",
    { occupation = "mechanic", home = "rosewood" })
local profileB = Personality.initialize("sc-depth-deterministic",
    { occupation = "mechanic", home = "rosewood" })
check(profileA.archetype == profileB.archetype
    and profileA.courage == profileB.courage
    and profileA.caution == profileB.caution
    and profileA.compassion == profileB.compassion
    and profileA.practicality == profileB.practicality,
    "personality profile is deterministic for a stable identity and background")
local primaryValues = {
    brave = profileA.courage,
    cautious = profileA.caution,
    caring = profileA.compassion,
    practical = profileA.practicality,
}
local primary = primaryValues[profileA.archetype]
check(primary >= 76 and primary > math.max(
    profileA.archetype == "brave" and -1 or profileA.courage,
    profileA.archetype == "cautious" and -1 or profileA.caution,
    profileA.archetype == "caring" and -1 or profileA.compassion,
    profileA.archetype == "practical" and -1 or profileA.practicality),
    "generated personality has a bounded deterministic primary lead")

local brave = { version = 1, archetype = "brave", courage = 100, caution = 0,
    compassion = 50, practicality = 50 }
local cautious = { version = 1, archetype = "cautious", courage = 0, caution = 100,
    compassion = 50, practicality = 50 }
local braveCombat = Personality.adjustDecision(brave, { kind = "combat" }, {})
local cautiousCombat = Personality.adjustDecision(cautious, { kind = "combat" }, {})
local braveRetreat = Personality.adjustDecision(brave, { kind = "retreat" }, {})
local cautiousRetreat = Personality.adjustDecision(cautious, { kind = "retreat" }, {})
check(braveCombat > cautiousCombat and cautiousRetreat > braveRetreat
    and math.abs(braveCombat) <= 8 and math.abs(cautiousRetreat) <= 8,
    "brave/cautious soft preferences are monotonic and capped")
check(Personality.overrunThresholdDelta(brave, { escapeCount = 2, support = 1 }) <= 4
    and Personality.overrunThresholdDelta(cautious, { escapeCount = 2, support = 1 }) >= -4
    and Personality.overrunThresholdDelta(brave, { escapeCount = 0, support = 1 }) <= 0,
    "personality overrun threshold delta is capped and cannot reward a missing exit")

local satisfiedActor = actor("sc-objective-filter", 1, 4, { inventory = inventory({
    item("Base.Bandage", "Item"), item("Base.RippedSheets", "Item"),
    item("Base.Book", "Literature", { pages = 200 }),
    item("Base.Axe", "Weapon", { condition = 9, conditionMax = 10 }),
}) })
registry[satisfiedActor.id] = satisfiedActor
local satisfiedPossessions = PersonalItems.ensure(satisfiedActor, nil)
local satisfiedState = {
    personalityProfile = { archetype = "practical", courage = 50, caution = 50,
        compassion = 50, practicality = 100 },
    background = { occupation = "mechanic" }, possessions = satisfiedPossessions,
    objectives = { version = 1, serial = 0, history = {}, nextEligibleAt = 0 },
}
Objectives.initialize(satisfiedActor, satisfiedState)
check(satisfiedState.objectives.active.kind ~= "keep_medical_ready"
    and satisfiedState.objectives.active.kind ~= "find_something_to_read"
    and satisfiedState.objectives.active.kind ~= "put_gear_in_order"
    and satisfiedState.objectives.active.kind ~= "recover_keepsake",
    "objective generation filters inventory and keepsake goals that are already satisfied")
registry[satisfiedActor.id] = nil

local depthActor = actor("sc-character-depth", 2, 4, { inventory = inventory() })
registry[depthActor.id] = depthActor
local possessions, assignmentReason = PersonalItems.ensure(depthActor, nil)
local keepsake = possessions and possessions.keepsake
local keepsakeItem = keepsake and PersonalItems.find(depthActor, keepsake.key) or nil
check(possessions ~= nil and assignmentReason == "personal_item_assigned"
    and keepsakeItem ~= nil and keepsakeItem:isFavorite()
    and PersonalItems.personalRecord(keepsakeItem).ownerId == depthActor.id,
    "personal item assignment creates and verifies one favourite owned keepsake")
local beforeEnsureCount = #depthActor.inventory.items
local possessionsAgain = PersonalItems.ensure(depthActor, possessions)
check(possessionsAgain ~= nil and #depthActor.inventory.items == beforeEnsureCount,
    "personal item normalization is idempotent and does not duplicate the keepsake")
local rejectingInventory = inventory()
function rejectingInventory:AddItem() error("injected item-script rejection") end
local optionalKeepsakeActor = actor("sc-optional-keepsake", 2, 5, {
    inventory = rejectingInventory,
})
registry[optionalKeepsakeActor.id] = optionalKeepsakeActor
local optionalPossessions, optionalReason = PersonalItems.ensure(optionalKeepsakeActor, nil)
check(optionalPossessions ~= nil and optionalPossessions.keepsake == nil
    and string.find(optionalReason, "personal_item_deferred:", 1, true) == 1,
    "optional keepsake rejection cannot roll back an otherwise healthy companion")
registry[optionalKeepsakeActor.id] = nil
check(PersonalItems.isProtected(keepsakeItem, depthActor, "craft_material")
    and PersonalItems.isProtected(keepsakeItem, depthActor, "medical_consume")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "read")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "repair")
    and not PersonalItems.isProtected(keepsakeItem, depthActor, "transactional_move"),
    "personal item protection blocks automated consumption but permits reading, repair, and manual movement")
local rejectedMarker = item("Base.RejectedMemento", "Item", { rejectSetFavorite = true })
local rejected, rejectedReason = PersonalItems.restoreMarker(rejectedMarker, {
    ownerId = depthActor.id, key = depthActor.id .. ":keepsake:rejected", kind = "memento",
}, true)
check(not rejected and rejectedReason == "personal_favorite_not_retained"
    and PersonalItems.personalRecord(rejectedMarker) == nil,
    "failed favourite verification rolls back a partially written personal marker")

local absoluteSnapshot = {
    threats = {}, immediateAttackers = {}, immediateCount = 3, closeImmediateCount = 3,
    closeThreatCount = 3, occupiedThreatSectors = 3, pressure = 0,
    escapeSquares = { { square = depthActor.square } }, allies = {},
}
check(SurvivorCompanion.Combat.assessOverrun(depthActor, absoluteSnapshot, nil,
        { combatMode = "defensive", personalityProfile = brave }).overrun
    and SurvivorCompanion.Combat.assessOverrun(depthActor, absoluteSnapshot, nil,
        { combatMode = "defensive", personalityProfile = cautious }).overrun,
    "absolute three-attacker/sector overrun remains true for every personality")

local depthState = {
    personality = profileA.archetype,
    personalityProfile = profileA,
    trust = 0, bond = 0, morale = 55, stress = 12,
    memories = {}, care = {},
    background = { occupation = "mechanic", home = "rosewood", value = "loyalty",
        fear = "being_trapped", habit = "checks_tools" },
    reveals = { background = 0, keepsake = false },
    timeTogetherMs = 0,
    possessions = possessions,
    objectives = {
        version = 1, serial = 1, history = {}, nextEligibleAt = 0,
        active = { version = 1, id = depthActor.id .. ":objective:1",
            kind = "share_a_proper_meal", status = "active", revealed = false,
            progress = 0, createdAt = 1 },
    },
}
SurvivorCompanion.Relationship.initialize(depthActor, depthState)
local hiddenJournal = Journal.build(depthActor, depthState, { name = "Depth Fellow" })
check(hiddenJournal.objective.known == false and hiddenJournal.keepsake.known == false
    and #hiddenJournal.background == 0 and depthState.objectives.active.revealed == false,
    "Journal is mutation-free and does not reveal hidden objective, keepsake, or background data")
local reservedSentence, _, reservedChanged = Objectives.respondPlans(depthState)
check(type(reservedSentence) == "string" and reservedChanged == false
    and depthState.objectives.active.revealed == false,
    "plans conversation respects its trust threshold without revealing early")
depthState.trust = 10
local planSentence, _, planChanged = Objectives.respondPlans(depthState)
-- The wording is one varied pool line (clock-salted); every variant names the
-- meal, so the check must not pin a single phrasing.
check(type(planSentence) == "string" and planChanged == true
    and depthState.objectives.active.revealed == true
    and (string.find(planSentence, "meal", 1, true) ~= nil
        or string.find(planSentence, "eat", 1, true) ~= nil
        or string.find(planSentence, "supper", 1, true) ~= nil),
    "plans conversation reveals exactly the existing objective with personality wording: "
        .. tostring(planSentence))
local revealedJournal = Journal.build(depthActor, depthState, { name = "Depth Fellow" })
check(revealedJournal.objective.known == true
    and revealedJournal.objective.kind == "share_a_proper_meal",
    "Journal reflects an already revealed objective without advancing it")
check(Objectives.noteEvent(depthState, "meal", {})
    and not Objectives.noteEvent(depthState, "meal", {})
    and depthState.objectives.active == nil and #depthState.objectives.history == 1
    and depthState.memories[#depthState.memories].kind == "goal_completed"
    and depthState.care.goalsCompleted == 1,
    "objective completion memory and bounded reward commit exactly once")
local cooldownUntil = depthState.objectives.nextEligibleAt
local _, generatedDuringCooldown = Objectives.initialize(depthActor, depthState)
check(not generatedDuringCooldown and depthState.objectives.active == nil,
    "completed objective cannot regenerate during its six-hour in-game cooldown")
f.clock = f.clock + 21600001
local _, generatedAfterCooldown = Objectives.initialize(depthActor, depthState)
check(generatedAfterCooldown and depthState.objectives.active ~= nil
    and depthState.objectives.active.kind ~= "share_a_proper_meal"
    and depthState.objectives.active.createdAt >= cooldownUntil,
    "objective generation resumes after six in-game hours and filters recent repeats")
for serial = 2, 10 do
    depthState.objectives.active = {
        version = 1, id = depthActor.id .. ":objective:" .. tostring(serial),
        kind = "share_a_proper_meal", status = "active", revealed = true,
        progress = 0, createdAt = serial,
    }
    check(Objectives.noteEvent(depthState, "meal", {}),
        "objective history accepts a distinct verified completion")
end
check(#depthState.objectives.history == 8,
    "objective completion history remains capped at eight rows")

do
    local mealActor = actor("sc-capped-meal-objective", 1, 1, { inventory = inventory() })
    mealActor.hunger = 0.6
    local mealMemories = {}
    local mealMemoryCap = tonumber(SurvivorCompanion.GameplayUtil.config("maxMemories")) or 24
    for index = 1, mealMemoryCap do
        mealMemories[index] = { kind = "older_memory", at = f.clock - index }
    end
    local mealRecord = {
        id = mealActor.id, actor = mealActor, recruited = true,
        state = {
            recruited = true, trust = 10, bond = 10, morale = 55, stress = 12,
            memories = mealMemories, care = {}, reveals = {}, timeTogetherMs = 0,
            objectives = {
                version = 1, serial = 1, history = {}, nextEligibleAt = 0,
                active = { version = 1, id = mealActor.id .. ":objective:1",
                    kind = "share_a_proper_meal", status = "active", revealed = true,
                    progress = 0, createdAt = f.clock },
            },
        },
    }
    registry[mealActor.id] = mealRecord
    check(SurvivorCompanion.Commands.restore(mealActor, mealRecord),
        "capped-meal fixture restores one companion relationship state")
    local restoredMealState = SurvivorCompanion.Commands.peek(mealActor)
    restoredMealState.memories = mealMemories
    SurvivorCompanion.Commands.observeRelationship(mealActor, player, {})
    f.clock = f.clock + 2000
    mealActor.hunger = 0.2
    local mealChanged = SurvivorCompanion.Commands.observeRelationship(mealActor, player, {})
    local mealState = SurvivorCompanion.Commands.peek(mealActor)
    check(mealChanged and #mealState.memories == mealMemoryCap
            and mealState.objectives.active == nil
            and #mealState.objectives.history == 1,
        "a meal event completes exactly once even when capped memories retain the same length: "
            .. tostring(mealChanged) .. "/" .. tostring(#mealState.memories)
            .. "/" .. tostring(mealState.objectives.active)
            .. "/" .. tostring(#mealState.objectives.history))
    SurvivorCompanion.Commands.reset(mealActor)
    registry[mealActor.id] = nil
end

depthState.reveals.background = 2
local publicSummary = SurvivorCompanion.Relationship.summary(depthActor, depthState, {})
check(publicSummary.background.occupation == "Mechanic"
    and string.find(publicSummary.background.history, "old cars", 1, true) ~= nil
    and publicSummary.background.home == nil
    and publicSummary.profession == "Mechanic"
    and type(publicSummary.backgroundLabel) == "string",
    "relationship summary returns only staged revealed background facts")

depthActor.inventory:Remove(keepsakeItem)
local absentPossessions, leftInventory = PersonalItems.observe(depthActor, depthState.possessions)
depthState.possessions = absentPossessions
check(leftInventory and depthState.possessions.keepsake.status == "not_carried",
    "manual keepsake removal remains allowed and is observed as not carried")
local countWhileMissing = #depthActor.inventory.items
local stillMissing = PersonalItems.ensure(depthActor, depthState.possessions)
check(stillMissing.keepsake.status == "not_carried"
    and #depthActor.inventory.items == countWhileMissing,
    "a genuinely absent keepsake is never silently replaced")
depthState.objectives = {
    version = 1, serial = 11, history = {}, nextEligibleAt = 0,
    active = { version = 1, id = depthActor.id .. ":objective:11",
        kind = "recover_keepsake", status = "active", revealed = true,
        progress = 0, createdAt = 11 },
}
local unrelatedPhoto = item("Base.Photo", "Item", { memento = true })
check(Objectives.itemBonus(depthState.objectives, unrelatedPhoto) == 0,
    "same-type unmarked item cannot satisfy the recover-keepsake preference")
depthActor.inventory:AddItem(keepsakeItem)
PersonalItems.reset(depthActor)
depthState.possessions = PersonalItems.observe(depthActor, depthState.possessions)
Objectives.reset(depthActor)
check(Objectives.update(depthActor, depthState)
    and depthState.objectives.active == nil and #depthState.objectives.history == 1,
    "returning the exact marked keepsake completes its objective once")

local privateMeal = item("Base.PrivateMeal", "Food", { hungerChange = -0.4 })
check(PersonalItems.restoreMarker(privateMeal, {
        ownerId = depthActor.id, key = depthActor.id .. ":keepsake:test-meal", kind = "memento",
    }, true), "test personal meal marker is verified")
local hungryActor = actor("sc-protected-needs", 3, 4,
    { inventory = inventory({ privateMeal }) })
hungryActor.hunger = 0.8
registry[hungryActor.id] = hungryActor
local privateRuntime={snapshot={threats={},threatCount=0,immediateCount=0,pressure=0}}
local privateOptions={commands={recruited=true,order="base_duty"}}
SurvivorCompanion.Needs.update(hungryActor,player,privateRuntime,privateOptions)
SurvivorCompanion.Needs.update(hungryActor,player,privateRuntime,privateOptions)
local consumedPrivate,privateReason=SurvivorCompanion.Needs.update(hungryActor,player,privateRuntime,privateOptions)
check(not consumedPrivate and privateReason == "safe_food_unavailable" and not privateMeal.used,
    "needs automation refuses to consume a marked personal item")
local normalMeal = item("Base.NormalMeal", "Food", { hungerChange = -0.4 })
hungryActor.inventory:AddItem(normalMeal)
check(SurvivorCompanion.Needs.update(hungryActor,player,privateRuntime,privateOptions)
    and hungryActor.lastIntent.item == normalMeal,
    "needs automation still selects an ordinary safe item beside a protected one")

registry[depthActor.id] = nil
registry[hungryActor.id] = nil
end
SurvivorCompanion.__testCharacterDepth()
SurvivorCompanion.__testCharacterDepth = nil

print("SUBJECT_PASS checks=" .. tostring(f.checks()))
