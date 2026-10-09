-- SPDX-License-Identifier: MIT

require "SCNamespace"
require "SCCall"
require "SCConfig"
require "SCRegistry"
require "SCDiagnostics"
require "SCGameplayUtil"

local SC = SurvivorCompanion
SC.Spawn = SC.Spawn or {}

local spawn = SC.Spawn
local lastDebugAttempt = -math.huge
local productionStartedAt = nil
local lastProductionAttempt = -math.huge
local sequence = 0
local lastGeneratedIdentityKey = nil
local pendingSpawn = nil

-- Genre-inspired given names are mixed independently from an original/common
-- surname pool and vanilla appearances. The generator does not recreate a
-- character's full name, dialogue, costume, or likeness.
local firstNames = {
    { name = "Abby", gender = "female" },
    { name = "Ada", gender = "female" },
    { name = "Addy", gender = "female" },
    { name = "Alice", gender = "female" },
    { name = "Amy", gender = "female" },
    { name = "Ana", gender = "female" },
    { name = "Andrea", gender = "female" },
    { name = "Anna", gender = "female" },
    { name = "Barbara", gender = "female" },
    { name = "Beth", gender = "female" },
    { name = "Carol", gender = "female" },
    { name = "Christa", gender = "female" },
    { name = "Claire", gender = "female" },
    { name = "Connie", gender = "female" },
    { name = "Dianne", gender = "female" },
    { name = "Dina", gender = "female" },
    { name = "Ellie", gender = "female" },
    { name = "Enid", gender = "female" },
    { name = "Hannah", gender = "female" },
    { name = "Jess", gender = "female" },
    { name = "Jill", gender = "female" },
    { name = "Judith", gender = "female" },
    { name = "Kate", gender = "female" },
    { name = "Kelly", gender = "female" },
    { name = "Liz", gender = "female" },
    { name = "Lori", gender = "female" },
    { name = "Lydia", gender = "female" },
    { name = "Maggie", gender = "female" },
    { name = "Maria", gender = "female" },
    { name = "Marlene", gender = "female" },
    { name = "Mel", gender = "female" },
    { name = "Michonne", gender = "female" },
    { name = "Monica", gender = "female" },
    { name = "Naomi", gender = "female" },
    { name = "Nicole", gender = "female" },
    { name = "Nora", gender = "female" },
    { name = "Rebecca", gender = "female" },
    { name = "Rikki", gender = "female" },
    { name = "Riley", gender = "female" },
    { name = "Rochelle", gender = "female" },
    { name = "Rosita", gender = "female" },
    { name = "Sarah", gender = "female" },
    { name = "Sasha", gender = "female" },
    { name = "Scarlet", gender = "female" },
    { name = "Selena", gender = "female" },
    { name = "Tammy", gender = "female" },
    { name = "Tara", gender = "female" },
    { name = "Tess", gender = "female" },
    { name = "Yara", gender = "female" },
    { name = "Yvonne", gender = "female" },
    { name = "Zoey", gender = "female" },
    { name = "Aaron", gender = "male" },
    { name = "Abraham", gender = "male" },
    { name = "Andre", gender = "male" },
    { name = "Andy", gender = "male" },
    { name = "Ben", gender = "male" },
    { name = "Bill", gender = "male" },
    { name = "Carl", gender = "male" },
    { name = "Carlos", gender = "male" },
    { name = "Chris", gender = "male" },
    { name = "Dale", gender = "male" },
    { name = "Daryl", gender = "male" },
    { name = "David", gender = "male" },
    { name = "Deacon", gender = "male" },
    { name = "Don", gender = "male" },
    { name = "Doyle", gender = "male" },
    { name = "Duane", gender = "male" },
    { name = "Dwight", gender = "male" },
    { name = "Ed", gender = "male" },
    { name = "Ellis", gender = "male" },
    { name = "Eugene", gender = "male" },
    { name = "Ezekiel", gender = "male" },
    { name = "Francis", gender = "male" },
    { name = "Frank", gender = "male" },
    { name = "Gabriel", gender = "male" },
    { name = "Gerry", gender = "male" },
    { name = "Glenn", gender = "male" },
    { name = "Henry", gender = "male" },
    { name = "Hershel", gender = "male" },
    { name = "Isaac", gender = "male" },
    { name = "Jesse", gender = "male" },
    { name = "Jim", gender = "male" },
    { name = "Joel", gender = "male" },
    { name = "Kenneth", gender = "male" },
    { name = "Leon", gender = "male" },
    { name = "Lev", gender = "male" },
    { name = "Lionel", gender = "male" },
    { name = "Louis", gender = "male" },
    { name = "Manny", gender = "male" },
    { name = "Merle", gender = "male" },
    { name = "Michael", gender = "male" },
    { name = "Morgan", gender = "male" },
    { name = "Negan", gender = "male" },
    { name = "Nick", gender = "male" },
    { name = "Owen", gender = "male" },
    { name = "Paul", gender = "male" },
    { name = "Pete", gender = "male" },
    { name = "Philip", gender = "male" },
    { name = "Rick", gender = "male" },
    { name = "Roger", gender = "male" },
    { name = "Sam", gender = "male" },
    { name = "Sanghwa", gender = "male" },
    { name = "Seokwoo", gender = "male" },
    { name = "Shane", gender = "male" },
    { name = "Shaun", gender = "male" },
    { name = "Stephen", gender = "male" },
    { name = "Steve", gender = "male" },
    { name = "Tommy", gender = "male" },
    { name = "Tucker", gender = "male" },
    { name = "Tyreese", gender = "male" },
    { name = "Yongguk", gender = "male" },
}

-- Additional main-character given names from zombie films, television and
-- games. Kept separate from the existing list so older names remain intact.
local additionalFemaleNames = {
    "Alicia", "Althea", "Angela", "Ashley", "Barbra", "Bonnie", "Carla",
    "Carley", "Caroline", "Casey", "Cassandra", "Cherry", "Clementine",
    "Dakota", "Dani", "Debra", "Eleanor", "Francine", "Helen", "Helena",
    "Holly", "Isabela", "Jade", "Jane", "Jessica", "Jinhee", "Judy",
    "Julie", "Juliet", "June", "Karin", "Karlee", "Lilly", "Lily", "Lisa",
    "Liv", "Luciana", "Madison", "Mariana", "Maya", "Megan", "Melanie",
    "Mia", "Mindy", "Minjung", "Moira", "Norma", "Ofelia", "Purna",
    "Regina", "Roberta", "Rose", "Samantha", "Seongkyeong", "Sheva",
    "Sherry", "Stacey", "Sydney", "Tina", "Violet", "Xian", "Yoobin",
    "Zelda",
}
local additionalMaleNames = {
    "Aiden", "Barry", "Bart", "Billy", "Brad", "Bruno", "Burt", "Charlie",
    "Chuck", "Cliff", "Dan", "Daniel", "Dieter", "Doug", "Eddie",
    "Edward", "Elijah", "Ernie", "Ethan", "Evangelo", "Flynn", "Freddy",
    "Gary", "Grant", "Harry", "Hector", "Herbert", "Howard", "Jacob",
    "Jake", "James", "Jamie", "Jason", "Javier", "John", "Johnny",
    "Joonwoo", "Juan", "Julius", "Jungseok", "Karl", "Kenny", "Kieran",
    "Kyle", "Lance", "Larry", "Lazaro", "Lee", "Logan", "Luke", "Mack",
    "Marcus", "Mark", "Marlon", "Matthew", "Miguel", "Mike", "Nikolai",
    "Omid", "Otis", "Perry", "Peter", "Piers", "Rahim", "Robert",
    "Ronnie", "Ryan", "Scott", "Takeo", "Terry", "Theodore", "Thierry",
    "Thomas", "Tom", "Travis", "Victor", "Wade", "Walter", "Wendell",
    "William",
}
for _, name in ipairs(additionalFemaleNames) do
    firstNames[#firstNames + 1] = { name = name, gender = "female" }
end
for _, name in ipairs(additionalMaleNames) do
    firstNames[#firstNames + 1] = { name = name, gender = "male" }
end

local surnames = {
    "Baker", "Bennett", "Carter", "Ellis", "Foster", "Grant", "Hayes",
    "Holland", "Lane", "Nolan", "Parker", "Reed", "Rowan", "Shaw",
    "Sutton", "Turner", "Walker",
    "Abel", "Aldemir", "Alomar", "Alvarez", "Anderson", "Andrews",
    "Belinski", "Belmont", "Birkin", "Block", "Bowman", "Brecken",
    "Briar", "Burton", "Cain", "Caldwell", "Campbell", "Carver", "Caul",
    "Chambers", "Chambler", "Chang", "Clark", "Coen", "Cooper",
    "Cosgrove", "Creed", "Cruz", "Darling", "DeMarco", "Dempsey",
    "Denbo", "Dixon", "Dorie", "Douglas", "Espinosa", "Everett",
    "Fairburne", "Fincher", "Ford", "Forrester", "Forsythe", "Galvez",
    "Gallagher", "Garcia", "Garrison", "Gomez", "Graham", "Gray",
    "Green", "Greene", "Grigio", "Grimes", "Hall", "Halsey", "Harper",
    "Harris", "Harrison", "Hawthorne", "Hoffman", "Horvath", "James",
    "Jones", "Justineau", "Kaufman", "Kelvin", "Kennedy", "Keyes",
    "Levy", "Logan", "MacFarlane", "Manawa", "Marcus", "Marston",
    "Masaki", "Mazzy", "McCarney", "McDermott", "Miller", "Moore",
    "Morrison", "Moynihan", "Muller", "Murphy", "Neville", "Nivans",
    "Oliveira", "Overbeck", "Parks", "Peletier", "Peterson", "Porter",
    "Ramos", "Redfield", "Rhodes", "Richtofen", "Riley", "Ritter",
    "Robertson", "Robinson", "Rogan", "Rose", "Salazar", "Schow",
    "Starling", "Stewart", "Stokes", "Strand", "Taylor", "Thompson",
    "Torres", "Valentine", "Vickers", "Vogel", "Walsh", "Warren",
    "Washington", "West", "Whitaker", "Wilcox", "Williams", "Wilson",
    "Winston", "Winters", "Wong",
}

local koreanSurnames = { "Rhee", "Kim", "Oh", "Yoon", "Seo", "Park" }
local koreanGivenNames = {
    Seokwoo = true, Sanghwa = true, Yongguk = true, Jinhee = true,
    Seongkyeong = true, Minjung = true, Yoobin = true, Joonwoo = true,
    Jungseok = true,
}
local koreanSurnameSet = {}
for _, name in ipairs(koreanSurnames) do koreanSurnameSet[name] = true end

-- Exact source-character names are excluded even though their components can
-- be used independently. The optional namesake roll draws only from pairs
-- whose two components are present in the new pools.
local sourcePairs = {
    "Harry:Cooper", "Helen:Cooper", "Peter:Washington",
    "Roger:DeMarco", "Stephen:Andrews", "Francine:Parker",
    "Sarah:Bowman", "Bill:McDermott", "Miguel:Salazar",
    "Matthew:Logan", "Burt:Wilson", "Herbert:West", "Dan:Cain",
    "Megan:Halsey", "Regina:Belmont", "Samantha:Belmont",
    "Hector:Gomez", "Lionel:Cosgrove", "Henry:West",
    "Shaun:Riley", "Ana:Clark", "Kenneth:Hall", "Michael:Schow",
    "Steve:Marcus", "Riley:Denbo", "Paul:Kaufman",
    "Don:Harris", "Alice:Harris", "Tammy:Harris", "Andy:Harris",
    "Scarlet:Levy", "Jason:Creed", "Debra:Moynihan",
    "Robert:Neville", "Cherry:Darling", "Dakota:Block",
    "William:Block", "Grant:Mazzy", "Sydney:Briar",
    "Gerry:Lane", "Karin:Lane", "Julie:Grigio", "Perry:Kelvin",
    "Wade:Vogel", "Maggie:Vogel", "Seokwoo:Seo",
    "Sanghwa:Yoon", "Helen:Justineau", "Eddie:Parks",
    "Caroline:Caldwell", "Kieran:Gallagher", "Cliff:Robertson",
    "Ronnie:Peterson", "Mindy:Morrison", "Zelda:Winston",
    "Joonwoo:Oh", "Yoobin:Kim", "Scott:Ward", "Kate:Ward",
    "Maria:Cruz",
    "Rick:Grimes", "Lori:Grimes", "Carl:Grimes", "Judith:Grimes",
    "Shane:Walsh", "Glenn:Rhee", "Maggie:Greene", "Beth:Greene",
    "Hershel:Greene", "Daryl:Dixon", "Merle:Dixon",
    "Carol:Peletier", "Andrea:Harrison", "Dale:Horvath",
    "Morgan:Jones", "Michonne:Hawthorne", "Tyreese:Williams",
    "Sasha:Williams", "Abraham:Ford", "Rosita:Espinosa",
    "Eugene:Porter", "Tara:Chambler", "Gabriel:Stokes",
    "Theodore:Douglas", "Madison:Clark", "Nick:Clark",
    "Alicia:Clark", "Travis:Manawa", "Victor:Strand",
    "Daniel:Salazar", "Ofelia:Salazar", "John:Dorie",
    "Luciana:Galvez", "Roberta:Warren", "Addy:Carver",
    "Mack:Thompson", "Julius:James", "Liv:Moore",
    "Chris:Redfield", "Claire:Redfield", "Jill:Valentine",
    "Leon:Kennedy", "Ada:Wong", "Barry:Burton", "Moira:Burton",
    "Rebecca:Chambers", "Carlos:Oliveira", "Sheva:Alomar",
    "Ethan:Winters", "Mia:Winters", "Ashley:Graham",
    "Sherry:Birkin", "Billy:Coen", "Piers:Nivans",
    "Jake:Muller", "Helena:Harper", "Brad:Vickers",
    "Bill:Overbeck", "Joel:Miller", "Tommy:Miller",
    "Ellie:Williams", "Riley:Abel", "Abby:Anderson",
    "Owen:Moore", "Manny:Alvarez", "Nora:Harris",
    "Isaac:Dixon", "Frank:West", "Isabela:Keyes",
    "Brad:Garrison", "Jessica:McCarney", "Otis:Washington",
    "Chuck:Greene", "Stacey:Forsythe", "Rebecca:Chang",
    "Nick:Ramos", "Lee:Everett", "Lilly:Caul", "Larry:Caul",
    "Javier:Garcia", "Marcus:Campbell", "Maya:Torres",
    "Ed:Jones", "Lily:Ritter", "Deacon:StJohn",
    "William:Gray", "Sarah:Whitaker", "Mike:Wilcox",
    "Kyle:Crane", "Jade:Aldemir", "Rahim:Aldemir",
    "Harris:Brecken", "Aiden:Caldwell", "Logan:Carter",
    "Elijah:Walker", "Holly:Forrester", "Howard:Hoffman",
    "Karlee:Fincher", "Tank:Dempsey", "Nikolai:Belinski",
    "Takeo:Masaki", "Edward:Richtofen", "Thomas:Rogan",
    "James:Taylor", "Gary:Stewart", "Kate:Green",
    "John:Marston", "Bonnie:MacFarlane", "Karl:Fairburne",
    "Juliet:Starling",
}

local strangeFolkPairs = {
    "Red:Pruitt", "Kevin:Dupree", "Wendell:Skaggs", "Gale:Mercer",
    "Ambrose:Kittredge", "Cecil:Haskins", "Rhonda:Vance",
    "Silas:Crane", "Ada:Flint", "Jonah:Vale", "Morris:Pike",
    "Rusty:Pell", "Lonnie:Tackett", "Virgil:Toombs",
    "Clem:Sutter", "Harlan:Purdy", "Ellis:Purdy", "Wade:Purdy",
    "Vernon:Ashby", "Kris:Kimbrough", "Prentice:Hollowell",
    "Pettigrew:Lusk", "Velma:Crisp", "Corey:Biggs",
    "Royce:Pickett", "Mose:Calloway", "Amos:Teague",
    "Lester:Voss", "Dalton:Reese", "Skeeter:Bowles",
    "Merle:Lusby", "Hollis:Burkett", "Jedediah:Cole",
    "June:Whitlock", "Tommy:Beaumont", "Gordon:Pettibone",
    "Morton:Feeney", "Mien:Ward", "Grinder:Berg",
}
local reservedSurnames = {
    Cole = true, Mercer = true, Ward = true, Crane = true,
    Pruitt = true, Dupree = true, Skaggs = true, Kittredge = true,
    Haskins = true, Vance = true, Flint = true, Vale = true, Pike = true,
    Pell = true, Tackett = true, Toombs = true, Sutter = true, Purdy = true,
    Ashby = true, Kimbrough = true, Hollowell = true, Lusk = true,
    Crisp = true, Biggs = true, Pickett = true, Calloway = true,
    Teague = true, Voss = true, Bledsoe = true, Reese = true,
    Bowles = true, Lusby = true, Burkett = true, Crabtree = true,
    Whitlock = true, Tolliver = true, Beaumont = true, Pettibone = true,
    Feeney = true, Berg = true,
    Hemingway = true, Hass = true, Watts = true, Kormick = true,
    Jaye = true,
    Wilson = true, Sutton = true, Vickers = true,
}
local reservedFullNames, famousPairs = {}, {}
local givenByName, availableSurnames = {}, {}
for _, row in ipairs(firstNames) do givenByName[row.name] = row end
for _, name in ipairs(surnames) do availableSurnames[name] = true end
for _, name in ipairs(koreanSurnames) do availableSurnames[name] = true end
local function pairKey(forename, surname)
    return string.lower(forename) .. ":" .. string.lower(surname)
end
for _, pair in ipairs(sourcePairs) do
    local forename, surname = pair:match("^([^:]+):([^:]+)$")
    reservedFullNames[pairKey(forename, surname)] = true
    local given = givenByName[forename]
    if given and availableSurnames[surname] and not reservedSurnames[surname]
        and (koreanGivenNames[forename] == true) == (koreanSurnameSet[surname] == true)
        and string.lower(forename) ~= string.lower(surname) then
        famousPairs[#famousPairs + 1] = { given = given, surname = surname }
    end
end
for _, pair in ipairs(strangeFolkPairs) do
    local forename, surname = pair:match("^([^:]+):([^:]+)$")
    reservedFullNames[pairKey(forename, surname)] = true
end

function spawn.isReservedFullName(forename, surname)
    return type(forename) == "string" and type(surname) == "string"
        and reservedFullNames[pairKey(forename, surname)] == true
end

-- Stock 42.20.4 outfits present in both male and female OutfitManager catalogs.
-- The mundane pool keeps encounters grounded and prevents unclothed descriptors.
local survivorOutfits = {
    "Generic01", "Generic02", "Generic03", "Generic04", "Generic05",
    "Grunge", "Hobbyist", "Backpacker", "Camper", "Evacuee",
}

-- Only rooms with a recognisable occupation influence an ordinary survivor's
-- clothes. Keep the vanilla outfit pool as the fallback for other rooms and
-- for the 40% who happened to be dressed for something else that day.
local themedOutfits = {
    police = { "Police", "PoliceState", "Sheriff_Deputy", "Detective" },
    prison = { "InmateEscaped", "Inmate", "InmateKhaki", "PrisonGuard" },
    church = { "Priest", "Classy", "Retiree" },
    hospital = { "Doctor", "Nurse", "HospitalPatient", "HospitalPatientBathrobe", "AmbulanceDriver" },
    medical = { "Doctor", "Nurse", "HospitalPatient", "HospitalPatientBathrobe", "AmbulanceDriver" },
    pharmacy = { "Pharmacist" },
    spiffos = { "Cook_Spiffos", "Waiter_Spiffo" },
    jays = { "Cook_Jays", "Waiter_Jays" },
    grocery = { "GigaMart_Employee" },
    gas = { "Fossoil", "Gas2Go", "ThunderGas" },
    garage = { "Mechanic", "MetalWorker" },
    firehouse = { "Fireman", "FiremanFullSuit" },
    army = { "ArmyCamoGreen", "ArmyInstructor", "ArmyServiceUniform" },
    school = { "Teacher", "Student" },
    bar = { "Biker", "Redneck", "Rocker" },
    bowling = { "Bowling" },
    gym = { "FitnessInstructor", "BoxingRed", "BoxingBlue" },
    lab = { "Doctor", "HazardSuit" },
    motel = { "Tourist", "Trucker", "Hobbo" },
    music = { "GuitarGuy", "Rocker" },
    farm = { "Farmer", "Redneck" },
    barn = { "Farmer", "Redneck" },
    farmstorage = { "Farmer", "Redneck" },
    hunting = { "Hunter" },
}

local roomAliases = {
    policestation = "police", policeoffice = "police", cells = "prison",
    jail = "prison", prisoncell = "prison", chapel = "church",
    clinic = "medical", surgery = "medical", doctor = "medical",
    drugstore = "pharmacy", pharmacyshop = "pharmacy",
    supermarket = "grocery", gigamart = "grocery", grocerystorage = "grocery",
    gasstation = "gas", gasstore = "gas", mechanic = "garage",
    firestation = "firehouse", classroom = "school",
    pub = "bar", bowlingalley = "bowling", fitness = "gym",
    laboratory = "lab", motelroom = "motel", musicstore = "music",
    barnstorage = "barn", farmhouse = "farm",
}

local function normalizeRoomGroup(value)
    if type(value) ~= "string" then return nil end
    local name = string.lower(value):gsub("[^%a%d]", "")
    return roomAliases[name] or name
end

function spawn.isThemedRoom(name)
    local group = normalizeRoomGroup(name)
    return group ~= nil and themedOutfits[group] ~= nil
end

-- New, unaffiliated survivors are not trained soldiers. Half of them begin
-- with one plausible household/tool weapon; everyone else must find one in
-- the world. The identity seed keeps the roll stable across native retries.
local weakStarterMeleeWeapons = {
    "Base.RollingPin",
    "Base.Saucepan",
    "Base.WoodenMallet",
    "Base.KitchenKnife",
    "Base.Screwdriver",
}

local function method(object, name)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[name] end)
    return ok and type(value) == "function" and value or nil
end

local function invoke(object, name, ...)
    return SC.Call.method(object, name, ...)
end

local function nowMs()
    if type(getTimestampMs) == "function" then
        local ok, value = pcall(getTimestampMs)
        local numeric = ok and tonumber(value) or nil
        if numeric ~= nil then return numeric end
    end
    return math.floor(os.clock() * 1000)
end

local function randomBetween(minimum, maximum)
    if type(ZombRand) == "function" then
        local ok, value = pcall(ZombRand, math.floor(minimum), math.floor(maximum) + 1)
        if ok and type(value) == "number" then return value end
    end
    sequence = sequence + 1
    return minimum + (sequence * 1103515245 % math.max(1, maximum - minimum + 1))
end

function spawn.starterMeleeWeapon(identity)
    identity = type(identity) == "table" and identity or {}
    local seed = tonumber(identity.visualSeed)
    if seed == nil or seed ~= seed or seed == math.huge or seed == -math.huge then
        seed = randomBetween(1, 999999999)
    end
    seed = math.floor(math.abs(seed))
    if seed % 100 >= 50 then return nil end
    local index = math.floor(seed / 100) % #weakStarterMeleeWeapons + 1
    return weakStarterMeleeWeapons[index]
end

local function prepareNeutralStarterWeapon(profile)
    if type(profile) ~= "table" or profile.recruited == true or profile.restored == true
        or profile.factionId ~= nil or profile._starterMeleePrepared == true then
        return profile
    end
    profile._starterMeleePrepared = true
    local identity = type(profile.identity) == "table" and profile.identity or profile
    local itemType = spawn.starterMeleeWeapon(identity)
    profile.starterMeleeWeapon = itemType or false
    if itemType == nil then return profile end

    local previousInitialize = profile.initialize
    profile.initialize = function(actor, recordInput)
        if type(previousInitialize) == "function" then
            local result, reason = previousInitialize(actor, recordInput)
            if result == false then return false, reason end
        end
        local inventoryOk, inventory = invoke(actor, "getInventory")
        local addedOk, added = false, nil
        if inventoryOk and inventory then
            addedOk, added = invoke(inventory, "AddItem", itemType)
        end
        if not addedOk or added == nil then
            if SC.Diagnostics and type(SC.Diagnostics.report) == "function" then
                local name = tostring(identity.forename or identity.name or "unknown")
                SC.Diagnostics.report("spawn-starter-weapon", name,
                    "weak starter melee weapon was unavailable", itemType)
            end
            -- Active mods may remove an item type. In that case the actor still
            -- spawns and naturally enters the unarmed scavenging branch.
            return true
        end
        return true
    end
    return profile
end

local function livingNameUsage(options)
    local usedGiven, usedSurnames = {}, {}
    local function include(identity)
        if type(identity) ~= "table" then return end
        local given = identity.forename or identity.name
        if type(given) == "string" and given ~= "" then
            usedGiven[string.lower(given)] = true
        end
        if type(identity.surname) == "string" and identity.surname ~= "" then
            usedSurnames[string.lower(identity.surname)] = true
        end
    end
    local registry = SC.Registry
    if registry and type(registry.snapshot) == "function" then
        local ok, records = pcall(registry.snapshot)
        if ok and type(records) == "table" then
            for _, record in ipairs(records) do
                local actor = type(record) == "table" and record.actor or nil
                local alive = actor ~= nil and not (type(record.runtime) == "table"
                    and record.runtime.inactive == true)
                if alive and type(actor.isDead) == "function" then
                    local deadOk, dead = pcall(actor.isDead, actor)
                    alive = not deadOk or dead ~= true
                end
                if alive then include(record.identity) end
            end
        end
    elseif registry and type(registry.living) == "function" then
        local ok, actors = pcall(registry.living)
        if ok and type(actors) == "table" then
            for _, actor in ipairs(actors) do
                local identity = type(actor) == "table" and actor.identity or nil
                if identity == nil and type(actor.getDescriptor) == "function" then
                    local descOk, descriptor = pcall(actor.getDescriptor, actor)
                    if descOk and descriptor then
                        local firstOk, first = pcall(descriptor.getForename, descriptor)
                        local lastOk, last = pcall(descriptor.getSurname, descriptor)
                        if firstOk and lastOk then
                            identity = { forename = first, surname = last }
                        end
                    end
                end
                include(identity)
            end
        end
    end
    if SC.Vehicle and type(SC.Vehicle.exportStored) == "function" then
        local ok, stored = pcall(SC.Vehicle.exportStored)
        if ok and type(stored) == "table" then
            for _, record in pairs(stored) do include(record.identity) end
        end
    end
    if SC.Factions and type(SC.Factions.list) == "function" then
        local ok, groups = pcall(SC.Factions.list)
        if ok and type(groups) == "table" then
            for _, group in ipairs(groups) do
                for _, member in ipairs(type(group.members) == "table" and group.members or {}) do
                    if member.alive ~= false then include(member.identity) end
                end
            end
        end
    end
    local pendingProfile = pendingSpawn and pendingSpawn.ticket
        and pendingSpawn.ticket.profile
    if type(pendingProfile) == "table" then include(pendingProfile.identity) end
    for name, used in pairs(options.usedFirstNames or {}) do
        if used then usedGiven[string.lower(tostring(name))] = true end
    end
    for name, used in pairs(options.usedSurnames or {}) do
        if used then usedSurnames[string.lower(tostring(name))] = true end
    end
    return usedGiven, usedSurnames
end

function spawn.generateIdentity(options)
    options = type(options) == "table" and options or { roomGroup = options }
    local themedPool = themedOutfits[normalizeRoomGroup(options.roomGroup) or ""]
    local usedGiven, usedSurnames = livingNameUsage(options)
    local forcedSurname = options.surname or options.familySurname
    local allowSurnameReuse = options.allowSurnameReuse == true
        and type(forcedSurname) == "string"
    local function available(given, surname, allowReserved)
        if type(given) ~= "table" or type(surname) ~= "string"
            or not availableSurnames[surname] or reservedSurnames[surname]
            or usedGiven[string.lower(given.name)]
            or (usedSurnames[string.lower(surname)] and not allowSurnameReuse)
            or (koreanGivenNames[given.name] == true)
                ~= (koreanSurnameSet[surname] == true)
            or string.lower(given.name) == string.lower(surname) then return false end
        local key = pairKey(given.name, surname)
        return key ~= lastGeneratedIdentityKey
            and (allowReserved or not reservedFullNames[key])
    end
    local chosen, surname
    if SC.Config.get("famousNamesakes") == true and options.allowFamous ~= false
        and randomBetween(1, 50) == 1 and #famousPairs > 0 then
        local start = randomBetween(1, #famousPairs)
        for step = 0, #famousPairs - 1 do
            local pair = famousPairs[((start + step - 1) % #famousPairs) + 1]
            if (forcedSurname == nil or forcedSurname == pair.surname)
                and available(pair.given, pair.surname, true) then
                chosen, surname = pair.given, pair.surname
                break
            end
        end
    end
    if chosen == nil then
        for _ = 1, 32 do
            local candidate = firstNames[randomBetween(1, #firstNames)]
            local pool = koreanGivenNames[candidate.name] and koreanSurnames or surnames
            local candidateSurname = forcedSurname or pool[randomBetween(1, #pool)]
            if available(candidate, candidateSurname, false) then
                chosen, surname = candidate, candidateSurname
                break
            end
        end
    end
    if chosen == nil then
        -- A deterministic full scan guarantees progress when a fixed test RNG
        -- or a crowded roster repeatedly presents the same invalid pair.
        local start = sequence % #firstNames
        for offset = 0, #firstNames - 1 do
            local candidate = firstNames[((start + offset) % #firstNames) + 1]
            local pool = koreanGivenNames[candidate.name] and koreanSurnames or surnames
            local surnameStart = sequence % #pool
            for surnameOffset = 0, #pool - 1 do
                local candidateSurname = forcedSurname
                    or pool[((surnameStart + surnameOffset) % #pool) + 1]
                if available(candidate, candidateSurname, false) then
                    chosen, surname = candidate, candidateSurname
                    break
                end
                if forcedSurname then break end
            end
            if chosen then break end
        end
    end
    if chosen == nil then return nil, "identity_name_pool_exhausted" end
    lastGeneratedIdentityKey = pairKey(chosen.name, surname)
    local outfitPool = themedPool and randomBetween(1, 100) <= 60
        and themedPool or survivorOutfits
    return {
        forename = chosen.name,
        surname = surname,
        gender = chosen.gender,
        outfit = outfitPool[randomBetween(1, #outfitPool)],
        visualSeed = randomBetween(1, 999999999),
    }
end

local function roomGroupNear(square)
    local function roomName(candidate)
        local roomOk, room = invoke(candidate, "getRoom")
        if not roomOk or not room then return nil end
        local nameOk, name = invoke(room, "getName")
        if nameOk and spawn.isThemedRoom(name) then return name end
        return nil
    end
    local name = roomName(square)
    if name then return name end
    local cellOk, cell = invoke(square, "getCell")
    local xOk, x = invoke(square, "getX")
    local yOk, y = invoke(square, "getY")
    local zOk, z = invoke(square, "getZ")
    if not cellOk or not xOk or not yOk or not zOk then return nil end
    for radius = 1, 2 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                if math.max(math.abs(dx), math.abs(dy)) == radius then
                    local candidateOk, candidate = invoke(cell, "getGridSquare", x + dx, y + dy, z)
                    if candidateOk then
                        name = roomName(candidate)
                        if name then return name end
                    end
                end
            end
        end
    end
    return nil
end

local function safeSquare(square, player, requireUnseen)
    if square == nil then return false end
    local chunkOk, chunk = invoke(square, "getChunk")
    local solidOk, solid = invoke(square, "isSolid")
    local transOk, trans = invoke(square, "isSolidTrans")
    local floorOk, floor = invoke(square, "TreatAsSolidFloor")
    local freeOk, free = invoke(square, "isFree", true)
    local safeOk, safe = invoke(square, "isSafeToSpawn")
    if not chunkOk or chunk == nil or not solidOk or solid == true or not transOk or trans == true
        or not floorOk or floor ~= true or not freeOk or free ~= true or not safeOk or safe ~= true then
        return false
    end
    if requireUnseen ~= false then
        local indexOk, playerIndex = invoke(player, "getPlayerNum")
        if not indexOk or tonumber(playerIndex) == nil then return false end
        local visibleOk, visible = invoke(square, "isCanSee", math.floor(playerIndex))
        if not visibleOk or visible == true then return false end
    end
    local objectsOk, moving = invoke(square, "getMovingObjects")
    if objectsOk and moving ~= nil then
        local sizeOk, size = invoke(moving, "size")
        if sizeOk and tonumber(size) and tonumber(size) > 0 then return false end
    end
    local cellOk, cell = invoke(square, "getCell")
    local xOk, x = invoke(square, "getX")
    local yOk, y = invoke(square, "getY")
    local zOk, z = invoke(square, "getZ")
    if not cellOk or not xOk or not yOk or not zOk then return false end
    local radius = SC.Config.get("spawnLocalSafetyRadius")
    local zombies = 0
    for dx = -radius, radius do
        for dy = -radius, radius do
            local nearbyOk, nearby = invoke(cell, "getGridSquare", x + dx, y + dy, z)
            local listOk, list = false, nil
            if nearbyOk then listOk, list = invoke(nearby, "getMovingObjects") end
            if listOk and list ~= nil then
                local sizeOk, size = invoke(list, "size")
                for index = 0, (sizeOk and math.min(tonumber(size) or 0, 16) or 0) - 1 do
                    local getOk, value = invoke(list, "get", index)
                    if getOk and SC.GameplayUtil.isZombie(value) then
                        zombies = zombies + 1
                        if zombies > SC.Config.get("spawnMaxNearbyZombies") then return false end
                    end
                end
            end
        end
    end
    return true
end

local function fallbackSquare(player, minimum, maximum, requireUnseen)
    local xOk, playerX = invoke(player, "getX")
    local yOk, playerY = invoke(player, "getY")
    local zOk, playerZ = invoke(player, "getZ")
    local cellOk, cell = invoke(player, "getCell")
    if not xOk or not yOk or not zOk or not cellOk or cell == nil then return nil end
    minimum = tonumber(minimum) or SC.Config.get("spawnMinDistance")
    maximum = tonumber(maximum) or SC.Config.get("spawnMaxDistance")
    for _ = 1, SC.Config.get("spawnSampleCount") do
        local distance = randomBetween(minimum, maximum)
        local octant = randomBetween(0, 7)
        local axis = randomBetween(math.floor(distance * 0.35), distance)
        local other = math.floor(math.sqrt(math.max(0, distance * distance - axis * axis)))
        local dx, dy = axis, other
        if octant % 2 == 1 then dx, dy = dy, dx end
        if octant >= 4 then dx = -dx end
        if octant == 2 or octant == 3 or octant == 6 or octant == 7 then dy = -dy end
        local squareOk, square = invoke(cell, "getGridSquare",
            math.floor(playerX + dx), math.floor(playerY + dy), math.floor(playerZ))
        if squareOk and safeSquare(square, player, requireUnseen) then return square end
    end
    return nil
end

function spawn.chooseSquare(player, runtime)
    if player == nil then return nil, "player is unavailable" end
    if SC.Encounter ~= nil and type(SC.Encounter.chooseSpawnSquare) == "function" then
        local ok, square = pcall(SC.Encounter.chooseSpawnSquare, player, runtime or {})
        if ok and square ~= nil and safeSquare(square, player) then return square end
    end
    local square = fallbackSquare(player, nil, nil, true)
    return square, (not square) and "no valid loaded unseen spawn square" or nil
end

function spawn.chooseDebugSquare(player)
    if SC.Config.get("debugSpawnEnabled") ~= true then
        return nil, "debug spawning disabled"
    end
    if player == nil then return nil, "player is unavailable" end
    local minimum = SC.Config.get("debugSpawnMinDistance")
    local maximum = SC.Config.get("debugSpawnMaxDistance")
    local square = fallbackSquare(player, minimum, maximum, true)
    if square ~= nil then return square end
    square = fallbackSquare(player, minimum, maximum, false)
    return square, square and "visible debug fallback" or "no valid loaded debug spawn square"
end

local function recordFor(actor)
    if actor == nil or type(SC.Registry) ~= "table"
        or type(SC.Registry.idOf) ~= "function" or type(SC.Registry.byId) ~= "function" then
        return nil
    end
    local ok, id = pcall(SC.Registry.idOf, actor)
    if not ok or id == nil then return nil end
    local recordOk, record = pcall(SC.Registry.byId, id)
    return recordOk and record or nil
end

function spawn.isDebugActor(actor)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false end
    local record = recordFor(actor)
    return record ~= nil and type(record.runtime) == "table"
        and record.runtime.debugSpawn == true
end

function spawn.isDebugProtected(actor)
    if not spawn.isDebugActor(actor) then return false end
    local record = recordFor(actor)
    return record.runtime.debugDiscovered ~= true
end

function spawn.markDebugDiscovered(actor)
    if not spawn.isDebugActor(actor) then return false end
    local record = recordFor(actor)
    if record.runtime.debugDiscovered == true then return false end
    record.runtime.debugDiscovered = true
    return true
end

local function finiteCoordinate(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end

function spawn.debugDescription(actor, currentPlayer)
    if not spawn.isDebugActor(actor) then return nil end
    local record = recordFor(actor)
    local identity = type(record.identity) == "table" and record.identity or {}
    local name = tostring(identity.forename or identity.name or "Unknown")
    if type(identity.surname) == "string" and identity.surname ~= "" then
        name = name .. " " .. identity.surname
    end
    local xOk, x = invoke(actor, "getX")
    local yOk, y = invoke(actor, "getY")
    local zOk, z = invoke(actor, "getZ")
    x, y, z = xOk and finiteCoordinate(x) or nil,
        yOk and finiteCoordinate(y) or nil, zOk and finiteCoordinate(z) or nil
    local position = x and y and string.format("%.1f,%.1f,%.1f", x, y, z or 0) or "unavailable"
    local distance = "unavailable"
    if x and y and currentPlayer ~= nil then
        local pxOk, px = invoke(currentPlayer, "getX")
        local pyOk, py = invoke(currentPlayer, "getY")
        local pzOk, pz = invoke(currentPlayer, "getZ")
        px, py, pz = pxOk and finiteCoordinate(px) or nil,
            pyOk and finiteCoordinate(py) or nil, pzOk and finiteCoordinate(pz) or nil
        if px and py then
            local dx, dy, dz = x - px, y - py, (z or 0) - (pz or 0)
            distance = string.format("%.1f", math.sqrt(dx * dx + dy * dy + dz * dz * 9))
        end
    end
    return "id=" .. tostring(record.id) .. " name=\"" .. name .. "\" at=" .. position
        .. " distance=" .. distance
end

function spawn.debugLog(event, actor, currentPlayer, reason)
    local description = spawn.debugDescription(actor, currentPlayer)
    if description == nil then return false end
    local suffix = reason ~= nil and " reason=" .. tostring(reason):gsub("[\r\n]", " ") or ""
    print("[SurvivorCompanion][debug-spawn] event=" .. tostring(event)
        .. " " .. description .. suffix)
    return true
end

function spawn.attempt(player, profile, runtime, source)
    if pendingSpawn ~= nil then return nil, "spawn_pending" end
    if #SC.Registry.living() + (SC.Vehicle and SC.Vehicle.storedCount() or 0)
        >= SC.Config.get("maxCompanions") then
        return nil, "companion cap reached"
    end
    local spawnSource = tostring(source or "encounter")
    local privateDebug = spawnSource == "debug" and SC.Config.get("debugSpawnEnabled") == true
    local square, reason
    if privateDebug then
        square, reason = spawn.chooseDebugSquare(player)
    else
        square, reason = spawn.chooseSquare(player, runtime)
    end
    if square == nil then return nil, reason end
    profile = type(profile) == "table" and profile or {
        recruited = false,
        identity = spawn.generateIdentity({ roomGroup = roomGroupNear(square) }),
    }
    profile = prepareNeutralStarterWeapon(profile)
    if privateDebug then
        profile.debugSpawn = true
        profile.debugDiscovered = false
    end
    if type(SC.Actor.beginSpawn) ~= "function" then
        return SC.Actor.spawn(square, profile)
    end
    local ticket, result = SC.Actor.beginSpawn(square, profile)
    if ticket == nil then return nil, result end
    pendingSpawn = {
        ticket = ticket,
        source = spawnSource,
        startedAt = nowMs(),
    }
    local status, detail = spawn.pollPending()
    if status == "spawned" then return detail end
    if status == "failed" then return nil, detail end
    return nil, "spawn_pending"
end

function spawn.pollPending()
    if pendingSpawn == nil then return "idle", "no spawn request is pending" end
    if SC.Actor == nil or type(SC.Actor.pollSpawn) ~= "function" then
        local source = pendingSpawn.source
        pendingSpawn = nil
        return "failed", "spawn polling is unavailable", source
    end
    local actor, result = SC.Actor.pollSpawn(pendingSpawn.ticket)
    if actor ~= nil then
        local source = pendingSpawn.source
        pendingSpawn = nil
        return "spawned", actor, source
    end
    if result == "spawn_pending" then return "pending", result, pendingSpawn.source end
    local source = pendingSpawn.source
    pendingSpawn = nil
    return "failed", result, source
end

function spawn.hasPending()
    return pendingSpawn ~= nil
end

function spawn.debugPulse(player, runtime, current)
    if SC.Config.get("debugSpawnEnabled") ~= true then return false, "debug spawning disabled" end
    if type(runtime) == "table" and runtime.active == false then
        local ready, reason = SC.Actor.checkBridge(false)
        if ready ~= true then return false, reason or runtime.disabledReason end
        runtime.active = true
        runtime.disabledReason = nil
    end
    current = current or nowMs()
    if current - lastDebugAttempt < SC.Config.get("debugSpawnIntervalMs") then
        return false, "debug spawn cooldown"
    end
    if #SC.Registry.living() > 0 or (SC.Vehicle and SC.Vehicle.storedCount() > 0) then
        return false, "a living or vehicle-stored companion already exists"
    end
    if player == nil then return false, "player is unavailable" end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason end
    lastDebugAttempt = current
    local actor, reason = spawn.attempt(player, nil, runtime, "debug")
    return actor ~= nil, actor or reason
end

function spawn.productionPulse(player, runtime, current)
    if SC.Config.get("productionEncounterEnabled") ~= true then
        return false, "production encounters disabled"
    end
    if type(runtime) == "table" and runtime.active == false then
        local ready, reason = SC.Actor.checkBridge(false)
        if ready ~= true then return false, reason or runtime.disabledReason end
        runtime.active = true
        runtime.disabledReason = nil
    end
    current = current or nowMs()
    if productionStartedAt == nil then productionStartedAt = current end
    if current - productionStartedAt < SC.Config.get("productionSpawnInitialDelayMs") then
        return false, "production encounter initial delay"
    end
    if current - lastProductionAttempt < SC.Config.get("productionSpawnCooldownMs") then
        return false, "production encounter cooldown"
    end
    if player == nil then return false, "player is unavailable" end
    local ready, providerReason = SC.Actor.checkBridge(false)
    if ready ~= true then return false, providerReason end

    local neutral = 0
    for _, record in ipairs(SC.Registry.records()) do
        if record.actor ~= nil and record.recruited ~= true
            and type(record.factionId) ~= "string"
            and not (type(record.runtime) == "table" and record.runtime.inactive == true) then
            neutral = neutral + 1
        end
    end
    if neutral >= SC.Config.get("maxNeutralEncounters") then
        return false, "neutral encounter already active"
    end
    if SC.Encounter ~= nil and type(SC.Encounter.canSpawnEncounter) == "function" then
        local ok, eligible, reason = pcall(SC.Encounter.canSpawnEncounter, player, runtime or {})
        if not ok or eligible ~= true then
            return false, ok and (reason or "encounter eligibility rejected") or tostring(eligible)
        end
    end

    -- Record every bounded attempt, successful or not, so an unavailable square
    -- never turns the cadence into broad repeated world scans.
    lastProductionAttempt = current
    local actor, reason = spawn.attempt(player, nil, runtime, "production")
    return actor ~= nil, actor or reason
end

function spawn.reset()
    if pendingSpawn ~= nil and SC.Actor ~= nil and type(SC.Actor.cancelSpawn) == "function" then
        pcall(SC.Actor.cancelSpawn, pendingSpawn.ticket)
    end
    pendingSpawn = nil
    lastDebugAttempt = -math.huge
    productionStartedAt = nil
    lastProductionAttempt = -math.huge
    sequence = 0
    lastGeneratedIdentityKey = nil
end

return spawn
