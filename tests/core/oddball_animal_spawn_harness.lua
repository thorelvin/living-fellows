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

-- The first normal spawn starts in "unmet". Chris must enter his bin run,
-- and a failed transfer must leave the find in the bin for a later retry.
local U = SC.GameplayUtil
local bin = { items = {} }
local trash = { kind = "Base.SheetPaper2", container = bin }
bin.items[1] = trash
function trash:getContainer() return self.container end
local bagInventory = { items = {} }
local bag = { kind = "Base.Bag_TrashBag" }
function bag:getInventory() return bagInventory end
local chris = { id = "chris-test", x = 5, y = 5, z = 0,
    items = { bag } }
local chrisGroup = { id = "chris-group", members = {
    { actorId = chris.id } }, oddball = {
    id = "big_chris_rascal", stage = "unmet", binIndex = 1,
    site = { bins = { { x = 5, y = 5, z = 0 } } } } }
SC.Registry = { byId = function(id)
    return id == chris.id and { actor = chris } or nil
end }
SC.Factions = { resolveQuestContainer = function() return bin end }
SC.NativeActions = {
    visualStatus = function() return "completed" end,
    clearVisual = function() return true end,
}
function U.idOf(value) return value and value.id end
function U.isValidActor(value) return value == chris end
function U.inventory(value) return value end
function U.inventoryItemsDeep(value) return value and value.items or {} end
function U.itemType(value) return value and value.kind end
function U.say(value, line) value.lastLine = line return true end
local transferAllowed = false
function U.transferItemVerified(source, target, item)
    if not transferAllowed or source ~= bin then return false end
    source.items[1] = nil
    target.items[1] = item
    item.container = target
    return true
end
local intent = SC.OddballBigChris.intentFor(chris, nil, {}, chrisGroup)
check(intent and intent.mode == "chris_search_bins"
    and chrisGroup.oddball.stage == "trash_run",
    "an ordinary new Chris begins his bin run")
chrisGroup.oddball.searchingBin = 1
local moved, reason = SC.OddballBigChris.update(chris, nil, {}, intent,
    chrisGroup)
check(moved == false and reason == "trash_transfer_failed"
    and trash.container == bin and chrisGroup.oddball.binIndex == 1,
    "a failed bin transfer neither claims nor advances the find")
transferAllowed = true
chrisGroup.oddball.searchingBin = 1
moved = SC.OddballBigChris.update(chris, nil, {}, intent, chrisGroup)
check(moved == true and trash.container == bagInventory
    and chris.lastLine == "Finders keepers! Useful trash right here.",
    "Chris announces a find only after verified transfer")
local firstBin = F.square(13, 10, 0, nil)
local secondBin = F.square(7, 10, 0, nil)
local function binFixture()
    return { getContainer = function()
        return { getType = function() return "bin" end }
    end }
end
firstBin.objects, secondBin.objects = { binFixture() }, { binFixture() }
function U.squareObjects(square, callback)
    for index, object in ipairs(square.objects or {}) do
        callback(object, index - 1)
    end
end
chrisGroup.oddball.site.bins = nil
chrisGroup.oddball.site.house = { anchor = { x = 10, y = 10, z = 0 } }
SC.OddballBigChris.pulse(chrisGroup, nil, 1000)
check(chrisGroup.oddball.site.bins
    and #chrisGroup.oddball.site.bins >= 2,
    "an old save with missing bin targets recovers loaded shop bins")

SC_TEST_REPORT = "Oddball animal spawn PASS: " .. checks .. " checks"
