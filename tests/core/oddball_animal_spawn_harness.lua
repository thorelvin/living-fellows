local SC = SurvivorCompanion
local Animals = SC.OddballAnimals
local F = SC_ANIMAL_SPAWN_FIXTURE
local checks = 0
local function check(okay, message)
    checks = checks + 1
    assert(okay, "animal spawn check " .. checks .. ": " .. message)
end

local bedroom = {}
for x = 10, 14 do F.square(x, 10, 0, bedroom) end
F.square(15, 10, 0, {})
local site = { spawn = { x = 10, y = 10, z = 0 },
    petSpawns = { { x = 11, y = 10, z = 0 },
        { x = 12, y = 10, z = 0 } },
    toySpawns = { { x = 10, y = 10, z = 0 },
        { x = 11, y = 10, z = 0 }, { x = 12, y = 10, z = 0 },
        { x = 13, y = 10, z = 0 }, { x = 15, y = 10, z = 0 },
        { x = 14, y = 10, z = 0 } } }
local group = { id = "milli-pet-posts", oddball = {
    id = "milli_tea_and_trouble", site = site } }
local rabbit = { kind = "rabdoe", breed = "swamp", name = "Dumpling" }
local raccoon = { kind = "rac", breed = "normal", name = "Bandit" }
F.squares["11:10:0"].chair = true
local okay, first = Animals.spawn(group, 1, rabbit, site.petSpawns[1])
check(okay and first.x >= 13 and first.x < 14
    and group.oddball.animals.slots[1].x == 13,
    "a newly blocked saved rabbit post uses clear floor in the bedroom")
local before = #F.animals
okay, first = Animals.spawn(group, 1, rabbit, site.petSpawns[1])
check(okay and #F.animals == before,
    "the alternate pet site remains single-spawn after a retry")
okay, first = Animals.spawn(group, 2, raccoon, site.petSpawns[2])
check(okay and group.oddball.animals.slots[2].x == 12
    and #F.animals == before + 1,
    "the other baby keeps its own clear post without overlapping")

local blocked = { id = "blocked-milli-pets", oddball = {
    id = "milli_tea_and_trouble", site = site } }
F.squares["12:10:0"].chair = true
F.squares["13:10:0"].chair = true
F.squares["14:10:0"].chair = true
before = #F.animals
okay = Animals.spawn(blocked, 1, rabbit, site.petSpawns[1])
check(okay == false and #F.animals == before,
    "all blocked bedroom posts defer instead of spawning on a chair")
local other = { id = "other-animal", oddball = { id = "other" } }
okay = Animals.spawn(other, 1, rabbit, site.petSpawns[1])
check(okay == false and #F.animals == before,
    "other encounters also reject furniture on their animal posts")

SC_TEST_REPORT = "Oddball animal spawn PASS: " .. checks .. " checks"
