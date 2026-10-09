-- SPDX-License-Identifier: MIT
local SC, F = SurvivorCompanion, DehydratedFixture
local M = SC.OddballDehydrated
local checks = 0
local function check(ok, message)
    checks = checks + 1
    assert(ok, "Nate check " .. checks .. ": " .. message)
end
local ready, reason = M.onSpawn(F.group, F.nate)
check(ready == true and reason == "nate_waiting", "scene enters waiting state")
check(F.nate.stats.thirst == 0.94 and F.nate.sitting == true,
    "Nate is visibly slumped and severely thirsty")
local radio = F.nate.secondary
check(radio and radio.fullType == "Base.WalkieTalkie2"
    and radio.container == F.nate.inventory
    and radio:getDeviceData():getHasBattery()
    and radio:getDeviceData():getChannel() == 90000
    and radio:getDeviceData():getIsTurnedOn(),
    "native walkie is equipped, powered and on ninety")
check(M.zombiesIgnore(F.nate, F.group) == true
    and F.nate.sheltered == true,
    "unopened room shelters Nate")
local offer = M.radioOffer(F.group, F.player, F.now)
check(offer and offer.frequency == 90000 and offer.x == 11
    and offer.guid == "LF-NATE-rescue-nate-group"
    and offer.replyLabel, "distress identifies real channel and location")
check(M.radioOffer(F.group, F.player, F.now + 1) == nil,
    "radio is not spammed every pulse")
local answered, answerReason, answerText = M.radioRespond(F.group, F.player)
check(answered and answerReason == "radio_answered"
    and answerText:find("Bring clean water", 1, true),
    "answer gives useful instructions without creating a map marker here")
check(M.radioOffer(F.group, F.player, F.now + 120000) == nil,
    "answered distress does not keep rebroadcasting")
check(M.action(F.group, "give_water", F.player) == false,
    "cannot pass water through closed door")
F.door.open = true
M.pulse(F.group, F.player, F.now + 1000)
check(F.group.oddball.opened and F.releases == 1
    and F.nate.sheltered == false, "opening door releases shelter")
check(M.zombiesIgnore(F.nate, F.group) == false,
    "opened room is no longer magically safe")
local bad = F.water(1, "Whiskey")
F.player.inventory:add(bad)
check(M.menuOptions(F.group, F.player)[1].enabled == false,
    "nonwater fluid cannot satisfy rescue")
local bag = F.inventory()
local bagItem = F.makeItem("Base.Bag_Schoolbag")
bagItem.inner = bag
F.player.inventory:add(bagItem)
local clean = F.water(1)
bag:add(clean)
local options = M.menuOptions(F.group, F.player)
check(options[1].enabled == true, "clean water inside player's bag is offered")
F.player.x, F.player.y, F.player.square = 11, 10, F.spawnSquare
local given, giveReason = M.action(F.group, "give_water", F.player)
check(given and giveReason == "water_given"
    and F.group.oddball.waterReceived == true,
    "clean water transfer starts recovery")
check(clean.container == F.nate.inventory and clean.fluid.amount == 0.75
    and math.abs(F.nate.stats.thirst - 0.44) < 0.001,
    "real water changes owner, fluid and native thirst")
check(M.canRecruit(F.group) == false and F.nate.sitting,
    "drinking does not cause instant standing or recruitment")
F.paused = true
for _ = 1, 4 do
    F.now = F.now + 2500
    M.pulse(F.group, F.player, F.now)
end
check(F.group.oddball.recoveryElapsedMs == 0,
    "pause does not consume recovery time")
F.paused = false
local saved = {}
for key, value in pairs(F.group.oddball) do saved[key] = value end
F.group = { id = F.group.id, standing = F.group.standing,
    discovered = F.group.discovered, members = F.group.members,
    oddball = saved }
M.onSpawn(F.group, F.nate)
F.now = F.now + 2500
M.pulse(F.group, F.player, F.now)
check(F.group.oddball.recoveryElapsedMs == 0
    and F.group.oddball.waterReceived == true
    and F.group.oddball.radioAnswered == true,
    "save reload preserves rescue but does not count time spent unloaded")
for _ = 1, 48 do
    F.now = F.now + 2500
    M.pulse(F.group, F.player, F.now)
end
check(F.group.oddball.recovered == true and F.nate.sitting == false,
    "Nate stands after two real minutes")
check(M.canRecruit(F.group) == true,
    "recruitment opens after recovery")
check(M.radioOffer(F.group, F.player, F.now) == nil,
    "recovered survivor stops broadcasting distress")
local count = #F.nate.inventory.items
local carryBag = F.inventory()
local carryBagItem = F.makeItem("Base.Bag_Schoolbag")
carryBagItem.inner = carryBag
F.nate.inventory:add(carryBagItem)
F.nate.inventory:remove(radio)
carryBag:add(radio)
M.onSpawn(F.group, F.nate)
check(#F.nate.inventory.items == count + 1
    and radio.container == F.nate.inventory,
    "reload unpacks the existing radio instead of duplicating it")
F.nate.inventory:remove(radio)
local withoutRadio = #F.nate.inventory.items
M.onSpawn(F.group, F.nate)
check(#F.nate.inventory.items == withoutRadio,
    "player taking his radio does not conjure a replacement on reload")
print("PASS: " .. checks .. " dehydrated rescue checks")
