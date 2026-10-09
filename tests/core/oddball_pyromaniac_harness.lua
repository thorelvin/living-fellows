-- SPDX-License-Identifier: MIT
local F = PyroFixture
local Pyro = SurvivorCompanion.OddballPyromaniac
local checks = 0
local function check(value, message)
    checks = checks + 1
    assert(value, "pyromaniac check " .. checks .. ": " .. message)
end
local seeded = Pyro.onSpawn(F.group, F.earl)
check(seeded == true and #F.worldItems == 3,
    "scene places three genuine world fuel cans")
for index, world in ipairs(F.worldItems) do
    check(world.item.data.lfPyroFuelGroupId == F.group.id
        and world.item.data.lfPyroFuelIndex == index,
        "every can has its own persistent scene tag")
end
Pyro.onSpawn(F.group, F.earl)
check(#F.worldItems == 3, "reawaken does not duplicate fuel")
F.player.inventory[1] = { kind = "Base.PetrolCan", data = {} }
Pyro.pulse(F.group, F.player, 1000)
check(F.group.oddball.stage == "unmet" and F.fires == 0,
    "ordinary player fuel does not trigger the scene")
F.player.inventory[2] = F.worldItems[2].item
Pyro.pulse(F.group, F.player, 1100)
check(F.group.oddball.stage == "warning" and F.fires == 0,
    "taking a tagged can triggers a curse before ignition")
check(Pyro.canRecruit(F.group) == false,
    "Earl cannot be recruited before surviving")
Pyro.pulse(F.group, F.player, 3000)
check(F.group.oddball.stage == "burning" and F.fires == 3,
    "all placed can sites start real fires")
local intent = Pyro.intentFor(F.earl, F.player, nil, F.group)
check(intent.mode == "pyromaniac_stay"
    and Pyro.update(F.earl, F.player, nil, intent, F.group) == true
    and F.stopCalls == 1, "Earl holds his room while it burns")
Pyro.pulse(F.group, F.player, 10000)
check(F.fires == 3 and F.group.oddball.stage == "burning",
    "later pulses never relight the fire")
for _, square in pairs(F.squares) do square.fire = false end
Pyro.pulse(F.group, F.player, 30000)
Pyro.pulse(F.group, F.player, 40000)
check(F.group.oddball.stage == "survived" and F.group.standing == "Trusted",
    "survival follows extinguished fire, not an arbitrary timer alone")
check(F.earl.stats.UNHAPPINESS >= 70 and Pyro.canRecruit(F.group) == true,
    "survivor is depressed and recruitable")
check(Pyro.menuOptions(F.group, F.player)[1].id == "recruit",
    "recruitment appears in the encounter menu")
check(Pyro.action(F.group, "recruit", F.player) == true
    and F.recruitment == 2,
    "recruitment uses the faction trial flow")
check(#F.diagnostics == 0, "normal scene reports no failures")
print("PASS: " .. checks .. " pyromaniac encounter checks")
