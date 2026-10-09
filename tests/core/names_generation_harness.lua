-- SPDX-License-Identifier: MIT

local SC = SurvivorCompanion
local checked = 0
local function check(value, message)
    checked = checked + 1
    assert(value, "name check " .. tostring(checked) .. " failed: " .. message)
end

local seed = 23
local function seededRand(minimum, maximum)
    seed = (seed * 48271) % 2147483647
    if maximum == nil then return seed % minimum end
    return minimum + (seed % (maximum - minimum))
end
ZombRand = seededRand

local koreanGiven = {
    Seokwoo = true, Sanghwa = true, Yongguk = true, Jinhee = true,
    Seongkyeong = true, Minjung = true, Yoobin = true, Joonwoo = true,
    Jungseok = true,
}
local koreanSurname = {
    Rhee = true, Kim = true, Oh = true, Yoon = true, Seo = true, Park = true,
}
for _, pair in ipairs({
    { "Gerry", "Lane" }, { "Rick", "Grimes" }, { "Glenn", "Rhee" },
    { "Joel", "Miller" }, { "Jill", "Valentine" },
    { "Seokwoo", "Seo" }, { "Sanghwa", "Yoon" },
    { "Maggie", "Greene" }, { "Frank", "West" },
    { "Kate", "Ward" }, { "Jedediah", "Cole" },
}) do
    check(SC.Spawn.isReservedFullName(pair[1], pair[2]),
        "source and Strange Folk full names must be reserved")
end

local originalFactionList = SC.Factions and SC.Factions.list
SC.Registry = { snapshot = function() return {} end,
    living = function() return {} end }
SC.Vehicle = { exportStored = function() return {} end,
    storedCount = function() return 0 end }
SC.Factions = SC.Factions or {}
SC.Factions.list = function() return {} end

for _ = 1, 10000 do
    local identity = SC.Spawn.generateIdentity()
    check(identity ~= nil and not SC.Spawn.isReservedFullName(
        identity.forename, identity.surname),
        "ordinary generator made an exact source name")
    check((koreanGiven[identity.forename] == true)
        == (koreanSurname[identity.surname] == true),
        "Korean given name and surname must stay paired")
    check(identity.forename:match("^[A-Za-z]+$") ~= nil
        and #identity.forename <= 12
        and identity.surname:match("^[A-Za-z]+$") ~= nil
        and #identity.surname <= 12,
        "generated identity must have short ASCII names")
    check(identity.forename:lower() ~= identity.surname:lower(),
        "given name and surname must differ")
    check(identity.surname ~= "Cole" and identity.surname ~= "Mercer"
        and identity.surname ~= "Ward" and identity.surname ~= "Crane",
        "Strange Folk surnames must be excluded")
end

local living = { actor = { isDead = function() return false end },
    identity = { forename = "Abby", surname = "Baker" } }
SC.Registry.snapshot = function() return { living } end
ZombRand = function(minimum) return minimum end
SC.Spawn.reset()
local nextIdentity = SC.Spawn.generateIdentity()
check(nextIdentity.forename ~= "Abby" and nextIdentity.surname ~= "Baker",
    "living roster first and surnames must not repeat")

SC.Registry.snapshot = function() return {} end
SC.Spawn.reset()
local usedGiven = { Abby = true, Ada = true }
local usedSurnames = { Baker = true, Bennett = true }
local excluded = SC.Spawn.generateIdentity({ usedFirstNames = usedGiven,
    usedSurnames = usedSurnames })
check(excluded.forename ~= "Abby" and excluded.forename ~= "Ada"
    and excluded.surname ~= "Baker" and excluded.surname ~= "Bennett",
    "unspawned household members must be excluded")

local koreanFamily = SC.Spawn.generateIdentity({ surname = "Kim",
    allowSurnameReuse = true, usedSurnames = { Kim = true } })
check(koreanFamily.surname == "Kim" and koreanGiven[koreanFamily.forename] == true,
    "shared Korean family surname requires a Korean given name")
local genericFamily = SC.Spawn.generateIdentity({ surname = "Baker",
    allowSurnameReuse = true, usedSurnames = { Baker = true } })
check(genericFamily.surname == "Baker"
    and koreanGiven[genericFamily.forename] ~= true,
    "shared generic family surname requires a generic given name")

local originalGet = SC.Config.get
SC.Config.get = function(key, subkey)
    if key == "famousNamesakes" then return true end
    return originalGet(key, subkey)
end
SC.Spawn.reset()
local famous = SC.Spawn.generateIdentity()
check(famous.forename == "Harry" and famous.surname == "Cooper",
    "opted-in one-in-fifty roll should choose an exact source pair")
seed, ZombRand = 43, seededRand
local namesakes = 0
for _ = 1, 5000 do
    local identity = SC.Spawn.generateIdentity()
    if SC.Spawn.isReservedFullName(identity.forename, identity.surname) then
        namesakes = namesakes + 1
    end
end
check(namesakes >= 50 and namesakes <= 150,
    "opted-in exact names should occur at roughly one in fifty; got "
        .. tostring(namesakes))
SC.Config.get = originalGet

-- Ordinary households share a family surname, while each later member has an
-- independent 20% chance of being an in-law or friend with another surname.
SC.Factions.list = originalFactionList
SC.GameplayUtil = {
    nowMs = function() return 1000 end,
    stableHash = function() return 0 end,
    gridSquare = function(x, y, z) return { x = x, y = y, z = z } end,
    isSafeSpawnSquare = function(square) return square ~= nil end,
    position = function(square) return square.x, square.y, square.z end,
}
SC.Actor = { checkBridge = function() return true end }
local house = {
    id = "names-house", anchor = { x = 10, y = 10, z = 0 },
    bounds = { x1 = 9, y1 = 9, x2 = 12, y2 = 12, z = 0 },
    interior = {
        { x = 10, y = 10, z = 0 }, { x = 11, y = 10, z = 0 },
        { x = 12, y = 10, z = 0 },
    },
    openings = {},
}
SC.Factions.findHouse = function() return house end
SC.Config.get = function(key, subkey)
    if key == "debugSpawnEnabled" then return true end
    return originalGet(key, subkey)
end
ZombRand = function(minimum, maximum)
    if maximum == nil then return minimum - 1 end
    return minimum
end
local created, groupId = SC.Factions.debugSpawnHousehold({}, 3)
check(created == true, "debug household must be created")
local group = SC.Factions.group(groupId)
check(group.members[1].identity.surname == group.members[2].identity.surname
    and group.members[2].identity.surname == group.members[3].identity.surname,
    "family members should share the surname when the exception misses")
check(group.members[1].identity.forename ~= group.members[2].identity.forename
    and group.members[2].identity.forename ~= group.members[3].identity.forename,
    "unspawned family members need distinct given names")

local exceptionRoll = 0
ZombRand = function(minimum, maximum)
    if maximum ~= nil then return minimum end
    if minimum == 100 then
        exceptionRoll = exceptionRoll + 1
        return exceptionRoll == 1 and 0 or 99
    end
    return 0
end
created, groupId = SC.Factions.debugSpawnHousehold({}, 3)
check(created == true, "second debug household must be created")
group = SC.Factions.group(groupId)
check(group.members[1].identity.surname ~= group.members[2].identity.surname
    and group.members[1].identity.surname == group.members[3].identity.surname,
    "exception should give only its rolled member another surname")
SC.Config.get = originalGet
print("names generation harness: " .. tostring(checked) .. " checks passed")
