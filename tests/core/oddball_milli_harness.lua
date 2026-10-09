-- SPDX-License-Identifier: MIT
-- Behavioral checks for the authored Milli encounter, including negative
-- controls for duplicate native animals and false baby-death attribution.

local SC = SurvivorCompanion
local Milli = SC.OddballMilli
local F = SC_MILLI_FIXTURE
local checks = 0

local function check(name, okay, detail)
    checks = checks + 1
    if not okay then
        error('MILLI_FAIL ' .. name .. ' ' .. tostring(detail or ''), 2)
    end
end

local function option(options, id)
    for _, value in ipairs(options or {}) do
        if value.id == id then return value end
    end
    return nil
end

local smallHouse = F.house(false, false)
check('small_house_rejected', Milli.siteFor(smallHouse, nil, true) == nil)

local fallbackHouse = F.house(false, true)
local fallback = Milli.siteFor(fallbackHouse, nil, true)
check('large_house_bedroom_fallback', fallback and fallback.spawn
    and fallback.spawn.x >= 14 and fallback.spawn.y == 10)

local preferredHouse = F.house(true, true)
local preferred = Milli.siteFor(preferredHouse, nil, true)
check('kidsbedroom_preferred', preferred and preferred.spawn
    and preferred.spawn.x <= 11 and preferred.spawn.y <= 11)
local kidsBed = SC.GameplayUtil.gridSquare(10, 10, 0)
kidsBed.objects = {}
local withoutKidsBed = Milli.siteFor(preferredHouse, nil, true)
check('unfurnished_kids_room_rejected', withoutKidsBed
    and withoutKidsBed.spawn and withoutKidsBed.spawn.x >= 14)

preferredHouse = F.house(true, true)
preferred = Milli.siteFor(preferredHouse, nil, true)
local group, actor, player = F.scene(preferred)
local started, spawnReason = Milli.onSpawn(group, actor)
check('scene_spawned', started == true, spawnReason)
check('two_real_babies', F.spawnCalls == 2
    and F.animals[1] and F.animals[1].name == 'Dumpling'
    and F.animals[2] and F.animals[2].name == 'Bandit')
check('toys_are_visible_world_items', #F.worldItems >= 5
    and #F.worldItems <= 8)
local firstWeapon = group.oddball.weapon
local firstPetIds = { F.animals[1].id, F.animals[2].id }
local firstInventoryCount = #actor.inv.items
local firstToyCount = #F.worldItems
Milli.onSpawn(group, actor)
check('spawn_once', F.spawnCalls == 2 and #F.worldItems == firstToyCount
    and #actor.inv.items == firstInventoryCount
    and group.oddball.weapon == firstWeapon
    and F.animals[1].id == firstPetIds[1]
    and F.animals[2].id == firstPetIds[2])
check('no_bonus_health', actor.maxHealth == 100)
check('vanilla_skills_and_trait', actor.perks.Strength == 9
    and actor.perks.Fitness == 4 and actor.perks.Blunt == 8
    and actor.perks.SmallBlunt == 8 and actor.perks.SmallBlade == 6
    and actor.perks.Sneak == 8 and actor.perks.Lightfoot == 7
    and actor.perks.Nimble == 5
    and actor.traits:contains('base:strong'))
local colored = 0
for _, item in ipairs(actor.inv.items) do
    if item.visual.tint then colored = colored + 1 end
end
check('three_tinted_clothes', colored == 3)

local intent = Milli.intentFor(actor, player, nil, group)
check('floor_sit_intent', intent and intent.mode == 'milli_floor')
check('native_ground_sit', Milli.update(actor, player, nil, intent, group)
    and actor.sitting == true)

F.now = 1200
Milli.pulse(group, player, F.now)
check('no_startle_from_afar', group.oddball.startled ~= true)
player.x, player.y = preferred.spawn.x + 1, preferred.spawn.y + 1
F.now = 2200
local beforeScare = #F.lines
Milli.pulse(group, player, F.now)
check('first_room_entry_startles', group.oddball.startled == true
    and #F.lines > beforeScare and actor.sitting == false)
local firstScareLines = #F.lines
F.now = 5000
Milli.pulse(group, player, F.now)
check('startle_does_not_repeat', group.oddball.startled == true
    and #F.lines <= firstScareLines + 2)
check('guard_released_once', F.guardReleases == 1)

local tea = option(Milli.menuOptions(group, player), 'have_tea')
check('tea_available_after_meeting', tea and tea.enabled == true)
local muffins = 0
for _, item in ipairs(actor.inv.items) do
    if item.kind == 'Base.MuffinGeneric'
        or item.kind == 'Base.MuffinFruit' then muffins = muffins + 1 end
end
check('three_muffins_carried', muffins == 3)
local firstTea = Milli.action(group, 'have_tea', player)
check('tea_shared', firstTea == true and group.oddball.teas == 1)
check('one_real_muffin_given', player.inv.items[1] ~= nil
    and (player.inv.items[1].kind == 'Base.MuffinGeneric'
        or player.inv.items[1].kind == 'Base.MuffinFruit'))
check('same_day_tea_rejected', Milli.action(group, 'have_tea', player) == false
    and group.oddball.teas == 1)
F.hour = F.hour + 24
check('second_day_tea', Milli.action(group, 'have_tea', player) == true
    and group.oddball.teas == 2)
F.hour = F.hour + 24
check('third_day_dear_stage', Milli.action(group, 'have_tea', player) == true
    and group.oddball.teas == 3)
F.hour = F.hour + 24
local beforeEmpty = #player.inv.items
check('tea_can_continue_without_duplication',
    Milli.action(group, 'have_tea', player) == true
    and #player.inv.items == beforeEmpty)

local dumpling = F.animals[1]
local bandit = F.animals[2]
local priorLines = #F.lines
dumpling.holder = player
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('gentle_line_on_pickup', #F.lines == priorLines + 1)
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('holding_does_not_repeat_line', #F.lines == priorLines + 1)
dumpling.holder = nil
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
dumpling.holder = player
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('new_lift_gets_new_line', #F.lines == priorLines + 2)
dumpling.holder = nil

F.unloaded[1] = true
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('unloaded_baby_is_not_dead', group.standing ~= 'Hostile'
    and group.oddball.grudge ~= true)
F.unloaded[1] = nil

local healthBeforeBlockedSwing = dumpling.health
local hurt, hurtReason = Milli.action(group, 'animal_hurt', player,
    { target = dumpling, damage = 10 })
check('predamage_hit_defers_debt', hurt == true
    and hurtReason == 'milli_baby_hit_pending_damage'
    and group.oddball.reimbursement == nil, hurtReason)
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('blocked_swing_does_not_charge', dumpling.health == healthBeforeBlockedSwing
    and group.oddball.reimbursement == nil)
Milli.action(group, 'animal_hurt', player,
    { target = dumpling, damage = 10 })
dumpling.health = 90
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('health_loss_opens_five_dollar_debt', group.oddball.reimbursement ~= nil)
check('injury_not_immediate_hostility', group.standing ~= 'Hostile')
local reputationBeforeDebtDay = group.reputation
F.hour = F.hour + 24
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('unpaid_debt_reduces_standing_gradually',
    group.reputation < reputationBeforeDebtDay
    and group.reputation >= -20 and group.standing ~= 'Hostile')
local payOption = option(Milli.menuOptions(group, player), 'pay_damage')
check('payment_option_visible', payOption ~= nil)
local paidWithoutMoney = Milli.action(group, 'pay_damage', player)
check('unfunded_payment_rejected', paidWithoutMoney == false
    and group.oddball.reimbursement ~= nil)
for _ = 1, 5 do player.inv:AddItem('Base.Money') end
local paid = Milli.action(group, 'pay_damage', player)
check('five_real_dollars_paid', paid == true
    and F.deliveries == 1 and group.receivedMoney == 5
    and group.oddball.reimbursement == nil)
check('cannot_repay_twice', Milli.action(group, 'pay_damage', player) == false
    and F.deliveries == 1)

bandit.health = 0
F.now = F.now + 1000
Milli.pulse(group, player, F.now)
check('unattributed_death_only_grieves', group.standing ~= 'Hostile'
    and group.oddball.grudge ~= true)

-- Reload the original scene state with native IDs intact. A repeated onSpawn
-- may restore cosmetics, but it must not create a replacement pet or toy.
local persisted = group.oddball
local loadedGroup = { id = group.id, standing = group.standing,
    members = group.members, oddball = persisted }
F.group = loadedGroup
local beforeReloadSpawn = F.spawnCalls
Milli.onSpawn(loadedGroup, actor)
check('save_load_keeps_native_ids', F.spawnCalls == beforeReloadSpawn
    and persisted.animals.slots[1].id == firstPetIds[1]
    and persisted.animals.slots[2].id == firstPetIds[2])

-- A separate scene proves a player's fatal blow is never mistaken for the
-- unattributed death above. Hostility and the grudge are irreversible.
local fatalSite = Milli.siteFor(F.house(true, true), nil, true)
local fatalGroup, fatalActor, fatalPlayer = F.scene(fatalSite)
Milli.onSpawn(fatalGroup, fatalActor)
fatalPlayer.x, fatalPlayer.y = fatalSite.spawn.x + 1, fatalSite.spawn.y
local fatalPet = F.animals[1]
fatalPet.health = 0
local killed = Milli.action(fatalGroup, 'animal_hurt', fatalPlayer,
    { target = fatalPet, damage = 100, killed = true })
check('player_kill_immediately_hostile', killed == true
    and fatalGroup.standing == 'Hostile'
    and fatalGroup.oddball.grudge == true)
check('grudge_blocks_recruitment', Milli.canRecruit(fatalGroup) == false)

local fellowSite = Milli.siteFor(F.house(true, true), nil, true)
local fellowGroup, fellowActor = F.scene(fellowSite)
Milli.onSpawn(fellowGroup, fellowActor)
local fellowPet = F.animals[2]
fellowPet.health = 0
local fellowKilled = Milli.action(fellowGroup, 'animal_hurt',
    F.companion, { target = fellowPet, damage = 100, killed = true })
check('companion_kill_is_player_party_kill', fellowKilled == true
    and fellowGroup.standing == 'Hostile'
    and fellowGroup.oddball.grudge == true)

local strangerSite = Milli.siteFor(F.house(true, true), nil, true)
local strangerGroup, strangerActor = F.scene(strangerSite)
Milli.onSpawn(strangerGroup, strangerActor)
local strangerPet = F.animals[1]
local stranger = F.actor(10, 10, 0)
stranger.id = 'unrecruited-stranger'
strangerPet.health = 70
check('unrecruited_actor_not_blamed',
    Milli.action(strangerGroup, 'animal_hurt', stranger,
        { target = strangerPet, damage = 30 }) == false
    and strangerGroup.oddball.reimbursement == nil)

local unrelated = F.animals[2]
unrelated.data.lfOddballGroupId = 'unrelated-group'
unrelated.health = 0
local unrelatedDeath, unrelatedReason = Milli.onAnimalDeath(unrelated, stranger)
check('unrelated_native_animal_death_ignored', unrelatedDeath == false
    and unrelatedReason == 'not_milli_baby'
    and strangerGroup.standing ~= 'Hostile'
    and strangerGroup.oddball.babyDead[2] ~= true)

local zombieSite = Milli.siteFor(F.house(true, true), nil, true)
local zombieGroup, zombieActor, zombiePlayer = F.scene(zombieSite)
Milli.onSpawn(zombieGroup, zombieActor)
local zombie = F.actor(8, 8, 0)
zombie.id = 'zombie-fixture'
zombie.class = 'IsoZombie'
local zombiePet = F.animals[1]
zombiePet.health = 0
local zombieDeath, zombieReason = Milli.onAnimalDeath(zombiePet, zombie)
check('zombie_kill_grieves_without_hostility', zombieDeath == true
    and zombieReason == 'milli_baby_killed_by_other'
    and zombieGroup.standing ~= 'Hostile'
    and zombieGroup.oddball.grudge ~= true
    and zombieGroup.oddball.babyDead[1] == true)

local campSite = Milli.siteFor(F.house(true, true), nil, true)
local campGroup, campActor, campPlayer = F.scene(campSite)
Milli.onSpawn(campGroup, campActor)
campGroup.oddball.startled = true
campGroup.recruitment = { joinedActorId = campActor.id }
campPlayer.x, campPlayer.y = campActor.x + 1, campActor.y
F.atCamp = true
F.token = { owner = 'downtime', action = 'sit' }
F.hour, F.clockHour, F.now = 240, 14, F.now + 1000
local beforeCampLines = #F.lines
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('recruited_milli_offers_camp_tea', #F.lines == beforeCampLines + 1
    and F.lines[#F.lines]:find('Cold tea again', 1, true) ~= nil
    and option(Milli.menuOptions(campGroup, campPlayer), 'have_tea').enabled == true)
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 1000)
check('camp_tea_offer_once_per_day', #F.lines == beforeCampLines + 1)
check('camp_offer_leads_to_real_tea_action',
    Milli.action(campGroup, 'have_tea', campPlayer) == true
    and campGroup.oddball.teas == 1)
local afterTeaLines = #F.lines
F.hour = F.hour + 24
F.token = { owner = 'combat', action = 'aim' }
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 2000)
check('no_tea_offer_during_combat', #F.lines == afterTeaLines)
F.token = { owner = 'downtime', action = 'sit' }
F.atCamp = false
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 3000)
check('no_tea_offer_away_from_camp', #F.lines == afterTeaLines)
F.atCamp = true
campActor.asleep = true
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 4000)
check('asleep_milli_does_not_offer_tea', #F.lines == afterTeaLines)
campActor.asleep = false
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 5000)
check('next_camp_day_offers_again', #F.lines == afterTeaLines + 1)
F.hour = F.hour + 24
F.now = F.now + 7000
F.token = nil
F.downtime = { safeSince = F.now - 6000 }
local beforeIdleOffer = #F.lines
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('stable_camp_idle_also_offers_tea', #F.lines == beforeIdleOffer + 1)
F.hour = F.hour + 24
F.now = F.now + 7000
campActor.moving = true
local beforeMovingOffer = #F.lines
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('moving_companion_does_not_offer_tea', #F.lines == beforeMovingOffer)
campActor.moving = false
F.token = { owner = 'downtime', action = 'sit' }
F.downtime = nil

local firstCampBaby, secondCampBaby = F.animals[1], F.animals[2]
firstCampBaby.x, firstCampBaby.y = campActor.x + 0.5, campActor.y
secondCampBaby.x, secondCampBaby.y = campActor.x + 5, campActor.y
F.clockHour, F.now = 22, F.now + 20000
local beforeSettle, beforePath, beforeNightSpawns =
    F.settleCalls, F.pathCalls, F.spawnCalls
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('near_baby_sits_at_night', firstCampBaby.sitting == true
    and F.settleCalls == beforeSettle + 1)
check('far_baby_paths_to_milli_at_night', secondCampBaby.pathTarget == campActor
    and F.pathCalls == beforePath + 1)
secondCampBaby.x, secondCampBaby.y = campActor.x + 0.5, campActor.y + 0.5
F.now = F.now + 16000
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('second_baby_settles_after_arrival', secondCampBaby.sitting == true
    and F.settleCalls == beforeSettle + 2)
F.clockHour = 12
F.now = F.now + 32000
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now)
check('daylight_wakes_the_two_settled_babies', firstCampBaby.sitting == false
    and secondCampBaby.sitting == false
    and campGroup.oddball.dumplingNightSat == nil
    and campGroup.oddball.banditNightSat == nil
    and F.settleCalls == beforeSettle + 4
    and F.spawnCalls == beforeNightSpawns)
Milli.pulseRecruited(campGroup, campActor, campPlayer, F.now + 1000)
check('daylight_wake_does_not_repeat', F.settleCalls == beforeSettle + 4)

local orphanSite = Milli.siteFor(F.house(true, true), nil, true)
local orphanGroup, orphanActor = F.scene(orphanSite)
Milli.onSpawn(orphanGroup, orphanActor)
F.relation = { familiarity = 5, trust = 5, opinion = 5,
    tension = 0 }
local orphanPetIds = { orphanGroup.oddball.animals.slots[1].id,
    orphanGroup.oddball.animals.slots[2].id }
local beforeKeeperDeathSpawns = F.spawnCalls
-- The loaded group may have lost its member row; its keeper ID in story
-- state still identifies Milli, without mistaking a bystander for her.
orphanGroup.members = {}
local bystander = F.actor(9, 9, 0)
bystander.id = 'unrelated-actor'
local wrongDeath, wrongReason = Milli.onKeeperDeath(bystander, orphanGroup)
check('unrelated_actor_death_does_not_orphan', wrongDeath == false
    and wrongReason == 'not_milli'
    and orphanGroup.oddball.keeperDead ~= true)
local keeperDeath, keeperReason = Milli.onKeeperDeath(orphanActor, orphanGroup)
check('persistent_keeper_id_marks_orphaned', keeperDeath == true
    and keeperReason == 'milli_babies_left_alive'
    and orphanGroup.oddball.keeperDead == true
    and orphanGroup.oddball.stage == 'orphaned'
    and orphanGroup.oddball.caregiverActorId == nil)
check('keeper_death_preserves_live_native_babies',
    F.spawnCalls == beforeKeeperDeathSpawns
    and orphanGroup.oddball.animals.slots[1].id == orphanPetIds[1]
    and orphanGroup.oddball.animals.slots[2].id == orphanPetIds[2]
    and orphanGroup.oddball.babyDead[1] ~= true
    and orphanGroup.oddball.babyDead[2] ~= true)

local distantSite = Milli.siteFor(F.house(true, true), nil, true)
local distantGroup, distantActor = F.scene(distantSite)
Milli.onSpawn(distantGroup, distantActor)
F.relation = { familiarity = 90, trust = 90, opinion = 90,
    tension = 0 }
F.companion.x = distantActor.x + 20
local distantDeath, distantReason =
    Milli.onKeeperDeath(distantActor, distantGroup)
check('distant_friend_does_not_take_babies', distantDeath == true
    and distantReason == 'milli_babies_left_alive'
    and distantGroup.oddball.caregiverActorId == nil)

local careSite = Milli.siteFor(F.house(true, true), nil, true)
local careGroup, careActor, carePlayer = F.scene(careSite)
Milli.onSpawn(careGroup, careActor)
careGroup.recruitment = { joinedActorId = careActor.id }
careGroup.oddball.stage = 'recruited'
F.relation = { familiarity = 35, trust = 30, opinion = 25,
    tension = 5 }
local careIds = { careGroup.oddball.animals.slots[1].id,
    careGroup.oddball.animals.slots[2].id }
local beforeCareSpawns, beforeCareFollows = F.spawnCalls, F.followCalls
local careDeath, careReason = Milli.onKeeperDeath(careActor, careGroup)
check('close_recruited_friend_takes_in_babies', careDeath == true
    and careReason == 'milli_babies_taken_in'
    and careGroup.oddball.caregiverActorId == F.companion.id
    and careGroup.oddball.stage == 'orphaned')
F.relation = nil
local repeatedCareDeath, repeatedCareReason =
    Milli.onKeeperDeath(careActor, careGroup)
check('death_callback_does_not_reassign_caregiver', repeatedCareDeath == true
    and repeatedCareReason == 'milli_babies_taken_in'
    and careGroup.oddball.caregiverActorId == F.companion.id)
check('wrong_caregiver_cannot_activate_orphans',
    Milli.pulseRecruited(careGroup, careActor, carePlayer, F.now) == false)
local carePulse = Milli.pulseRecruited(careGroup, F.companion,
    carePlayer, F.now + 6000)
check('caregiver_leads_same_two_native_babies', carePulse == true
    and F.followCalls == beforeCareFollows + 2
    and F.spawnCalls == beforeCareSpawns
    and careGroup.oddball.animals.slots[1].id == careIds[1]
    and careGroup.oddball.animals.slots[2].id == careIds[2]
    and careGroup.oddball.stage == 'orphaned')

-- Milli's room invitation uses the ordinary faction access query without
-- creating a random household social contract for this authored encounter.
local guestHouse = F.house(true, true)
local guestSite = Milli.siteFor(guestHouse, nil, true)
local guestGroup, _, guestPlayer = F.scene(guestSite)
guestGroup.house = guestHouse
guestPlayer.x, guestPlayer.y = guestSite.spawn.x, guestSite.spawn.y
local Contracts = SC.FactionContracts
check('no_guest_access_before_invitation',
    Contracts.hasAccess(guestGroup, guestPlayer) == false
    and guestGroup.social == nil)
guestGroup.standing = 'Tolerated'
guestGroup.oddball.guestAccess = true
local safe, safeReason = Contracts.safeRestStatus(guestGroup, guestPlayer)
check('milli_guest_room_allows_safe_rest',
    Contracts.hasAccess(guestGroup, guestPlayer) == true
    and safe == true and safeReason == 'safe_rest_available'
    and guestGroup.social == nil)
guestGroup.standing = 'Wary'
check('guest_access_revoked_with_low_standing',
    Contracts.hasAccess(guestGroup, guestPlayer) == false
    and Contracts.safeRestStatus(guestGroup, guestPlayer) == false)

SC_TEST_REPORT = 'MILLI_PASS checks=' .. checks
