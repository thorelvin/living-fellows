-- SPDX-License-Identifier: MIT
local SC = SurvivorCompanion
local T = SC_TEST
local rescue = SC.OddballGarageRescue
local group, actor, player = T.group, T.actor, T.player

local ready, reason = rescue.onSpawn(group, actor)
assert(ready == true, tostring(reason))
assert(T.part.fracture == 60 and T.part.scratch == true,
    "the real left leg needs both treatments")
assert(T.door.locked == true and actor.seated == true
    and actor.sheltered == true, "the garage is locked and Eli rests safely")
local waiting = rescue.intentFor(actor, player, { threatCount = 0 }, group)
assert(waiting and waiting.mode == "garage_broken_leg_wait"
    and rescue.update(actor, player, nil, waiting, group) == true,
    "an untreated leg keeps Eli at the wall instead of falling through to generic wandering")
local radio = actor.secondary
assert(radio and radio.fullType == "Base.WalkieTalkie2"
    and radio:getDeviceData():getHasBattery()
    and radio:getDeviceData():getChannel() == 90000,
    "Eli carries a powered and equipped 90 MHz walkie")
rescue.onSpawn(group, actor)
assert(actor.secondary == radio and #actor.inventory.items == 1,
    "repeated spawn cannot duplicate the radio")

local offer = rescue.radioOffer(group, player, 0)
assert(offer and offer.frequency == 90000 and offer.range == 550
    and offer.x == 10 and offer.text:find("splint") == nil,
    "the first distress call is on the real radio without leaking location: "
        .. tostring(offer and offer.frequency) .. " "
        .. tostring(offer and offer.range) .. " "
        .. tostring(offer and offer.x) .. " "
        .. tostring(offer and offer.text))
assert(rescue.radioOffer(group, player, 1000) == nil,
    "broadcasts are timed")
assert(rescue.radioRespond(group, player) == false,
    "an unreceived transmission cannot unlock the reply")
group.oddball.radioHeard = true
local answered, status, response = rescue.radioRespond(group, player)
assert(answered and status == "garage_rescue_location_shared"
    and response:find("10, 10") and group.oddball.radioAnswered,
    "answer gives exact map coordinates to the shared radio service")
assert(rescue.radioOffer(group, player, 90000) == nil,
    "answered distress does not keep broadcasting")

T.ms = 2000
rescue.pulse(group, player, T.ms)
assert(T.door.locked == false and group.oddball.doorUnlocked,
    "Eli unlocks the door when the player reaches it")
T.door.open = true
T.ms = 2500
rescue.pulse(group, player, T.ms)
assert(group.oddball.doorOpened and T.calls.guardRelease == 1
    and actor.sheltered == false,
    "opening the garage ends encounter protection")
player.x = 10
local choices = rescue.menuOptions(group, player)
assert(choices[2] and choices[2].enabled == false,
    "a treatment invitation requires the player's supplies")
local impossible, missing = rescue.action(group, "treat_leg", player)
assert(not impossible and missing == "garage_splint_missing"
    and not group.oddball.rescued,
    "missing supplies never heal the leg")
player.inventory:AddItem("Base.Splint")
player.inventory:AddItem("Base.Bandage")
choices = rescue.menuOptions(group, player)
assert(choices[2].enabled == true,
    "player's splint and clean bandage enable native treatment")
local started = rescue.action(group, "treat_leg", player)
assert(started == true and T.calls.panel == 1,
    "treatment opens the real player-as-doctor health panel")
T.ms = 3000
rescue.pulse(group, player, T.ms)
assert(not group.oddball.rescued,
    "opening a medical panel is not itself a completed treatment")
T.part.bandage = true
T.ms = 3500
rescue.pulse(group, player, T.ms)
assert(not group.oddball.rescued,
    "a bandage without splint does not resolve the rescue")
T.part.factor = 0.8
T.ms = 4000
rescue.pulse(group, player, T.ms)
assert(group.oddball.rescued and actor.lastAction == "stand_ground"
    and T.calls.standing == "Trusted" and rescue.canRecruit(group),
    "only observed native bandage and splint completion frees Eli")
assert(rescue.intentFor(actor, player, { threatCount = 0 }, group).mode
    == "oddball_idle", "treated Eli leaves the forced waiting pose")
local joined = rescue.action(group, "recruit", player)
assert(joined and T.calls.recruited, "treated Eli may join the player")
print("GARAGE_RESCUE_TEST_PASS")
