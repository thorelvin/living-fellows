-- SPDX-License-Identifier: MIT
-- Stock 42.21 logo filenames; textures remain supplied by the game.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalBrands = SC.TerminalBrands or {}
local B = SC.TerminalBrands
if type(require) == "function" then require "SCTerminalBusinessData" end
local D = SC.TerminalBusinessData
B.STOCK = {
    "5BuxOrLess",
    "932LBMWRadio",
    "AARonHuntingSupply",
    "AmericanEats",
    "AmericanTire",
    "AmeriglobeCommunications",
    "BBBQ",
    "BeBeauty",
    "BetterBedThanDead",
    "BetterFurnishings",
    "BloominCoffee",
    "BluePlateDiner",
    "BodyChisel",
    "BowWowWowDogNutrition",
    "BoxpopBrewery",
    "BrightedWhites",
    "brochureLogoTest2",
    "CafedEris",
    "CafeOle",
    "CandytownUSA",
    "CantoRecords",
    "CarFixation",
    "ChiefSteakhouseBar",
    "Chuggs",
    "CoffeeNirvana",
    "ConvenUMart",
    "DeepFriedHeaven",
    "DiMarcoCoffee",
    "DiscountAccount",
    "DogsAFlamin",
    "Dotty4Donuts",
    "DressedToThe90s",
    "DuCaseApartments",
    "EconoRoom",
    "EdensOasis",
    "Egenerex",
    "ElectronHouse",
    "ElveeArena",
    "ENewsNowNetwork",
    "ExpressoEspress",
    "FamilyDentistry",
    "FamilyFunzone",
    "FinneganResearchGroup",
    "FornoDellaMamma",
    "Fossoil",
    "FossoilField",
    "FromTheDugout",
    "FryerTooksFishNChips",
    "Fun23Childcare",
    "FunXtreme",
    "GennysDiner",
    "GenteelyUsed",
    "Go2Bread",
    "GoldenDragonBuffet",
    "GustoDItalia",
    "H2Quavia",
    "HappyRestaurant",
    "HavishamHotelSuites",
    "HitVids",
    "homewardDown",
    "homewardHouse",
    "homewardMap",
    "HomewardRealEstate",
    "homewardTop",
    "IceIceTasty",
    "IHeartWokRolls",
    "InkrAlley",
    "IvanovFactoryShowroom",
    "JaysChicken",
    "JennysTable",
    "JukeBoxBowling",
    "KeepAfloatDebtConsolidation",
    "Kegsplosion",
    "kentucky_herald_logo",
    "KittenKnives",
    "kk",
    "KnoxDistillery",
    "knoxknews",
    "KnoxPackKitchens",
    "KnoxTalkRadio",
    "KYTransit",
    "LaVieEnGastronomie",
    "LBMWNetwork",
    "LesTartesdeMademoiselleCeline",
    "LineByLineDesign",
    "LiquortySplit",
    "LiveMusic",
    "LoansCashJewelry",
    "LouisvilleBoat Club",
    "LouisvilleBruiser",
    "LouisvilleMusicFestival1993",
    "LouisvillePostLogo",
    "LouisvilleStateUniversity",
    "LST",
    "MaisonDuBouef",
    "MapsUnlimited",
    "MashieSignsPainting",
    "MassGenfacCo",
    "MeadDrinkandBloodyMerry",
    "MedicalCentre",
    "MilkMonarchy",
    "MilkNMore",
    "MindPeaceInsurance",
    "NailsandNuts",
    "NatsCafe",
    "NeonFlowerSalon",
    "NewspaperNationalLogo",
    "NewspaperNewEraLogo",
    "NiteGlo",
    "NolanCar1",
    "NolanCar2",
    "NolanCar3",
    "NolanDude",
    "nolanLogo",
    "Noteworthy",
    "NourishFoodMart",
    "OlympiaDepartmentStore",
    "OnyxDriveInTheater",
    "OptimaEyes",
    "PalettePop",
    "PawnShop",
    "PerfickPotatoCo",
    "PetHealthPawmise",
    "PoshBox",
    "PurpleBlack",
    "PurrfectBarkner",
    "ReadyPrep",
    "RedOwlInn",
    "reporterImage",
    "RiparianEntertainment",
    "RiverwoodBoatClub",
    "RustyRifleImage",
    "Sammies",
    "SanguineSpirits",
    "SashaSashay",
    "ScarletOakDistillery",
    "ScenicMileCarDealership",
    "ShakenAndStirred",
    "SilkenBelles",
    "SkyBlueBanking",
    "SleepEazzzeInn",
    "Slimtax",
    "SmokeysSaloonRestaurant",
    "SpeedyLegal",
    "Spiffos",
    "SpitfireFashion",
    "StarsStripes",
    "SucrafruitCircus",
    "Superklean",
    "SweetEats",
    "SweetPeaRestaurant",
    "SweetSugarBeauty",
    "TacoDelPancho",
    "TheBlackSaddle",
    "TheBlueFox",
    "TheCosyCrockpot",
    "TheExquisitePearl",
    "TheHardyHarBar",
    "TheKentuckyHerald - Copy",
    "TheKentuckyHerald",
    "TheOrangeAnchor",
    "ThePlumpCornucopia",
    "TheRealSweat",
    "TheSeaShanty",
    "TheSlugger",
    "TheStraightShooter",
    "TheTopHanger",
    "TheVelvetTassel",
    "TheWanderingSashimi",
    "TheWoodenStein",
    "ThumbsOfGreen",
    "TitaMariasCantina",
    "TopcrownPlaza",
    "TurboTV",
    "UnitedShippingLogistics",
    "ValuInsurance",
    "Valutech",
    "WestMapleCountryClub",
    "Windows",
    "WormOfBooks",
    "YourCloset",
    "YuriDesign",
    "ZacsHardware",
    "Zlatkos",
}
B.BY_ID = {}
for _, name in ipairs(B.STOCK) do
    B.BY_ID[name] = { label = name, texture = "media/textures/printMedia/logos/" .. name .. ".png" }
end

local fallbacks = { camp = "EMMA Camp System", home = "Personal Computer", county = "County Services",
    police = "Public Safety", fire = "Fire and Rescue", education = "School and Library",
    office = "Local Business", medical = "Medical Services", lab = "Research Terminal",
    industry = "Operations and Security", post = "Post and Transport", media = "Communications Terminal",
    retail = "Local Shop", food = "Food Service", hotel = "Guest Services", electronics = "Electronic Services" }
for key, label in pairs(fallbacks) do
    B.BY_ID["_" .. key] = { label = label, texture = "media/textures/Terminal/" .. key .. ".png" }
end

local function call(object, method, ...)
    if not object or not SC.GameplayUtil then return nil end
    local value, okay = SC.GameplayUtil.call(object, method, ...)
    return okay and value or nil
end

local siteSource, sites
local function locationSites()
    local definitions = PrintMediaDefinitions and PrintMediaDefinitions.MiscDetails
    if not definitions and type(require) == "function" then
        pcall(require,"PrintMedia/PrintMediaDefinitions")
        definitions = PrintMediaDefinitions and PrintMediaDefinitions.MiscDetails
    end
    if sites and definitions == siteSource then return sites end
    sites, siteSource = {}, definitions
    if type(definitions) ~= "table" then return sites end
    local keys={}
    for key in pairs(D.POI_BRANDS) do keys[#keys+1]=key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local entry=definitions[key]
        for index,rect in ipairs(type(entry)=="table" and type(entry.location1)=="table" and entry.location1 or {}) do
            if index>8 or #sites>=256 then break end
            if type(rect)=="table" and type(rect.x1)=="number" and type(rect.y1)=="number"
                and type(rect.x2)=="number" and type(rect.y2)=="number" and rect.x2>=rect.x1 and rect.y2>=rect.y1 then
                sites[#sites+1]={brand=D.POI_BRANDS[key],x1=rect.x1,y1=rect.y1,x2=rect.x2,y2=rect.y2}
            end
        end
    end
    return sites
end
function B.canonical(id)
    for _=1,4 do
        if not D.ALIASES[id] then return id end
        id=D.ALIASES[id]
    end
    return id
end
function B.kind(id)
    local info=B.BY_ID[B.canonical(id)]
    return info and info.kind
end
function B.label(id)
    id=B.canonical(id)
    local info=B.BY_ID[id]
    return info and info.label or "Local computer"
end
function B.isMonochrome(id)
    id=B.canonical(id)
    local info=B.BY_ID[id]
    if D.PHOSPHOR_INK[id] then return true end
    return info and info.mono==true or false
end
local function firmAtPoint(square,roomName)
    local x,y=call(square,"getX"),call(square,"getY")
    if type(x)~="number" or type(y)~="number" then return nil end
    local found
    for _,site in ipairs(locationSites()) do
        if x>=site.x1 and x<=site.x2 and y>=site.y1 and y<=site.y2 then
            -- A business advert cannot claim an upstairs private home.
            local home=SC.TerminalFiles.classify(roomName)=="home"
            if not home or B.kind(site.brand)=="hotel" then
                if found and found~=site.brand then return nil end
                found=site.brand
            end
        end
    end
    return found
end
local function roomNameOf(room)
    return string.lower(tostring(call(call(room,"getRoomDef") or room,"getName") or call(room,"getName") or ""))
end
local function ownRoomSign(square,room)
    if not room then return nil end
    local x,y,z=call(square,"getX"),call(square,"getY"),call(square,"getZ")
    if type(x)~="number" or type(y)~="number" or type(z)~="number" then return nil end
    local found,objects= nil,0
    -- Local signs only. Never take a sign across a road, floor, or shop wall.
    for dx=-4,4 do for dy=-4,4 do
        local candidate=SC.GameplayUtil.gridSquare and SC.GameplayUtil.gridSquare(x+dx,y+dy,z)
        if candidate and call(candidate,"getRoom")==room then
            local list=call(candidate,"getObjects")
            local size=math.min(32,tonumber(call(list,"size")) or 0)
            for index=0,size-1 do
                objects=objects+1
                if objects>512 then return nil end
                local props=call(call(list,"get",index),"getProperties")
                local custom=string.lower(tostring(call(props,"get","CustomName") or ""))
                local group=string.lower(tostring(call(props,"get","GroupName") or ""))
                local brand=custom:find("sign",1,true) and D.SIGN_BRANDS[group]
                if brand then
                    if found and found~=brand then return nil end
                    found=brand
                end
            end
        end
    end end
    return found
end
function B.identify(object)
    local data = call(object, "getModData")
    local explicit = type(data) == "table" and data.LF_ComputerBrand
    if type(explicit) == "string" and B.BY_ID[B.canonical(explicit)] then return B.canonical(explicit) end
    local square=call(object,"getSquare")
    local room=call(square,"getRoom")
    local name=roomNameOf(room)
    if D.ROOM_BRANDS[name] then return D.ROOM_BRANDS[name] end
    local sign=ownRoomSign(square,room)
    if sign then return sign end
    local site=firmAtPoint(square,name)
    if site then return site end
    -- A unique branded room can identify its own building's back office.
    -- Mixed businesses stay unassigned instead of borrowing a neighbour's name.
    local building=call(room,"getBuilding") or call(square,"getBuilding")
    local rooms=call(call(building,"getDef") or building,"getRooms")
    local branded,conflict
    for index=0,math.min(64,tonumber(call(rooms,"size")) or 0)-1 do
        local brand=D.ROOM_BRANDS[roomNameOf(call(rooms,"get",index))]
        if brand then if branded and branded~=brand then conflict=true end branded=brand end
    end
    local kind=SC.TerminalFiles.classify(name)
    if branded and not conflict and (kind=="office" or kind=="general") then return branded end
    if D.KIND_FALLBACK[kind] then return D.KIND_FALLBACK[kind] end
    if name == "broadcasting" or name == "newsroom" or name == "communications"
        or name == "studio" or name == "jackiejayestudio" then return "_media" end
    if name:find("police", 1, true) or name == "detectiveoffice" then return "_police" end
    if name == "firestation" or name == "firestorage" or name == "fireoffice"
        or name == "firegarage" then return "_fire" end
    if name:find("school", 1, true) or name:find("classroom", 1, true)
        or name:find("library", 1, true) then return "_education" end
    if name:find("lab", 1, true) then return "_lab" end
    if name:find("medical", 1, true) or name:find("clinic", 1, true)
        or name:find("hospital", 1, true) or name == "dentist" or name == "optometrist" then return "_medical" end
    if name:find("bedroom", 1, true) or name == "livingroom" or name == "kitchen" or name == "attic" then return "_home" end
    if name == "post" or name:find("transport", 1, true) then return "_post" end
    if name:find("factory", 1, true) or name == "controlroom" or name == "security"
        or name == "warehouse" then return "_industry" end
    if name:find("government", 1, true) or name == "townhall" then return "_county" end
    return "_office"
end

local textures = {}
B.BY_ID.Fossoil = { label = "Fossoil", texture = "media/textures/Terminal/Fossoil.png" }
B.BY_ID.McCoyLogging = { label = "McCoy Logging Co.", texture = "media/textures/Terminal/McCoyLogging.png" }
B.BY_ID.KnoxBank = { label = "Knox Bank", texture = "media/textures/Terminal/KnoxBank.png" }
for id,info in pairs(D.NEW) do
    B.BY_ID[id]={label=info.label,kind=info.kind,mono=info.mono,texture="media/textures/Terminal/"..id..".png"}
end
for id in pairs(D.ART_OVERRIDES) do B.BY_ID[id].texture="media/textures/Terminal/"..id..".png" end
for kind,ids in pairs(D.KIND_GROUPS) do
    for _,id in ipairs(ids) do if B.BY_ID[id] then B.BY_ID[id].kind=kind end end
end
for id,info in pairs(B.BY_ID) do
    if id:sub(1,1)~="_" then
        info.label=D.LABELS[id] or info.label:gsub("(%l)(%u)","%1 %2")
        info.kind=info.kind or "office"
    end
end
for _,id in ipairs({"_retail","_food","_hotel","_electronics"}) do B.BY_ID[id].mono=true end
-- The original camp atlas already contains matching phosphor variants. The
-- rare purple mark has its own generated asset. Business marks retain theirs.
B.CAMP_CROPS = { green = {443,14,862,275}, sand = {443,307,862,275},
    aqua = {443,599,862,275}, purple = {288,108,1562,490} }
function B.crop(id, theme)
    id=B.canonical(id)
    if id == "_camp" then return B.CAMP_CROPS[theme] or B.CAMP_CROPS.green end
    return B.CROPS and B.CROPS[id]
end
function B.texture(id, theme)
    id=B.canonical(id)
    local info = type(id) == "string" and B.BY_ID[id]
    if not info or type(getTexture) ~= "function" then return nil end
    local purple = id == "_camp" and theme == "purple"
    local key = purple and "_camp:purple" or id
    if textures[key] ~= nil then return textures[key] or nil end
    local okay, texture = pcall(getTexture, purple and "media/textures/Terminal/camp-purple.png" or info.texture)
    if okay and texture then
        textures[key] = texture
        return texture
    end
    textures[key] = false
    return nil
end
