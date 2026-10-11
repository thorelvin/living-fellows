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
check(F.group.oddball.fuelSpawned[1] == true
    and F.group.oddball.fuelSpawned[2] == true
    and F.group.oddball.fuelSpawned[3] == true,
    "native InventoryItem return marks each can as seeded")
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
local attacked = { id = "attacked-pyro-group", standing = "Wary",
    members = { { actorId = "earl" } },
    oddball = { id = "pyromaniac_earl_kessler", stage = "unmet",
        site = { spawn = { x = 31, y = 30, z = 0 },
            fuelPosts = { { x = 30, y = 31, z = 0 },
                { x = 32, y = 31, z = 0 } } } } }
F.group = attacked
F.player.inventory = {}
check(Pyro.onSpawn(attacked, F.earl) == true,
    "attacked encounter seeds fuel before the player can strike")
F.now = 45000
local fireBefore, linesBefore = F.fires, #F.lines
local handled, attackReason = Pyro.action(attacked, "hurt", F.player)
check(handled == true and attackReason == "house_ignited"
    and attacked.oddball.stage == "burning" and F.fires == fireBefore + 2,
    "first player hit ignites the prepared room synchronously")
check(#F.lines == linesBefore + 1
    and F.lines[#F.lines]:find("funeral pyre", 1, true) ~= nil,
    "Earl shouts a furious attack line without a laugh overwriting it")
Pyro.action(attacked, "hurt", F.player)
Pyro.pulse(attacked, F.player, F.now + 1000)
check(F.fires == fireBefore + 2 and #F.lines == linesBefore + 1,
    "repeat hits and pulses do not restart the fire or repeat the shout")
local retry = { id = "retry-pyro-group", standing = "Wary",
    members = { { actorId = "earl" } },
    oddball = { id = "pyromaniac_earl_kessler", stage = "unmet",
        site = { spawn = { x = 41, y = 40, z = 0 },
            fuelPosts = { { x = 40, y = 41, z = 0 },
                { x = 42, y = 41, z = 0 } } } } }
F.group = retry
check(Pyro.onSpawn(retry, F.earl) == true,
    "retry encounter seeds prepared fuel")
F.now = 47000
local nativeFire, firesBeforeRetry = IsoFireManager, F.fires
IsoFireManager = nil
check(Pyro.action(retry, "hurt", F.player) == true
    and retry.oddball.stage == "warning" and F.fires == firesBeforeRetry,
    "temporary native fire failure leaves attack armed for retry")
IsoFireManager = nativeFire
Pyro.pulse(retry, F.player, F.now + 1000)
check(retry.oddball.stage == "burning" and F.fires == firesBeforeRetry + 2,
    "next encounter pulse lights fuel once fire API returns")
local legacy = { id = "legacy-pyro-group", standing = "Wary",
    members = { { actorId = "earl" } },
    oddball = { id = "pyromaniac_earl_kessler", stage = "unmet",
        site = { spawn = { x = 21, y = 20, z = 0 },
            fuelPosts = { { x = 20, y = 21, z = 0 },
                { x = 22, y = 21, z = 0 } } } } }
local oldSquare = SurvivorCompanion.GameplayUtil.gridSquare(20, 21, 0)
local otherSquare = SurvivorCompanion.GameplayUtil.gridSquare(22, 21, 0)
local priorCount = #F.worldItems
oldSquare:AddWorldInventoryItem("Base.PetrolCan")
oldSquare:AddWorldInventoryItem("Base.PetrolCan")
otherSquare:AddWorldInventoryItem("Base.PetrolCan")
local legacyCount = #F.worldItems
check(legacyCount == priorCount + 3,
    "fixture starts with duplicate untagged cans from an old save")
F.group = legacy
check(Pyro.onSpawn(legacy, F.earl) == true
    and #F.worldItems == legacyCount,
    "old untagged cans are adopted without spawning more")
for _, world in ipairs(oldSquare.worldObjects) do
    check(world.item.data.lfPyroFuelGroupId == legacy.id,
        "every old piled can becomes a scene trigger")
end
F.player.inventory = { oldSquare.worldObjects[2].item }
table.remove(oldSquare.worldObjects, 2)
Pyro.pulse(legacy, F.player, 50000)
check(legacy.oddball.stage == "warning"
    and #oldSquare.worldObjects == 1,
    "taking either formerly untagged can triggers Earl")
F.now = 50020
local fireAfterTheft = F.fires
local lineAfterTheft = #F.lines
check(Pyro.action(legacy, "hurt", F.player) == true
    and legacy.oddball.stage == "burning"
    and F.fires == fireAfterTheft + 2,
    "attacking after stealing fuel ignites immediately, before warning timer")
check(#F.lines == lineAfterTheft + 1,
    "the attack shout replaces the delayed warning's opening laugh")
check(#F.diagnostics == 1
    and F.diagnostics[1]:find("native fire API unavailable", 1, true) ~= nil,
    "only the simulated native fire failure is reported")
print("PASS: " .. checks .. " pyromaniac encounter checks")
