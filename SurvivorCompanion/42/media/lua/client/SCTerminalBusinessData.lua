-- SPDX-License-Identifier: MIT
-- Curated identities. Generic room names are business sectors, not firms.
SurvivorCompanion = SurvivorCompanion or {}
local SC = SurvivorCompanion
SC.TerminalBusinessData = {}
local D = SC.TerminalBusinessData
D.NEW = {
    SunstarMotel={label="Sunstar Motel",kind="hotel",mono=true},
    UStoreIt={label="U-Store It",kind="transport",theme="aqua"},
    Lectromax={label="Lectromax Manufacturing",kind="industry",mono=true},
    PizzaWhirled={label="Pizza Whirled",kind="restaurant",theme="sand"},
    Greenes={label="Greene's",kind="grocery",mono=true},
    RustyRifle={label="The Rusty Rifle",kind="entertainment",mono=true},
    GigaMart={label="GigaMart",kind="grocery",mono=true},
    JackieJaye={label="Jackie Jaye",kind="media",mono=true},
}
D.ART_OVERRIDES={ChiefSteakhouseBar=true,LouisvilleMusicFestival1993=true,LesTartesdeMademoiselleCeline=true,
    RiverwoodBoatClub=true,DiMarcoCoffee=true}
D.PHOSPHOR_INK={OptimaEyes=true,PalettePop=true,TheExquisitePearl=true,TheSlugger=true,
    RiverwoodBoatClub=true,KnoxBank=true}
-- A newspaper's files should describe print reporting, not a television
-- studio. These names share the existing original press-desk story pool.
D.ARCHIVE_BRANDS={LouisvillePostLogo="TheKentuckyHerald",knoxknews="TheKentuckyHerald",
    NewspaperNationalLogo="TheKentuckyHerald",NewspaperNewEraLogo="TheKentuckyHerald",
    LST="TheKentuckyHerald",["932LBMWRadio"]="LBMWNetwork"}
D.ALIASES = { kk="knoxknews",homewardDown="HomewardRealEstate",homewardHouse="HomewardRealEstate",
    homewardMap="HomewardRealEstate",homewardTop="HomewardRealEstate",
    NolanCar1="nolanLogo",NolanCar2="nolanLogo",NolanCar3="nolanLogo",NolanDude="nolanLogo",
    ["TheKentuckyHerald - Copy"]="TheKentuckyHerald",kentucky_herald_logo="TheKentuckyHerald",
    RustyRifleImage="RustyRifle",reporterImage="_media",brochureLogoTest2="_office",Windows="_office" }
D.LABELS = { nolanLogo="Nolan's Used Cars",SkyBlueBanking="Sky Blue Banking",
    MindPeaceInsurance="Mind Peace Insurance",ValuInsurance="Valu Insurance",Spiffos="Spiffo's",
    FinneganResearchGroup="Finnegan Research Group",FamilyDentistry="Family Dentistry",
    MedicalCentre="Medical Centre",OptimaEyes="Optima Eyes",LBMWNetwork="LBMW Network",
    ["932LBMWRadio"]="93.2 LBMW Radio",KYTransit="KY Transit",ENewsNowNetwork="ENews Now",
    LouisvilleStateUniversity="Louisville State University",McCoyLogging="McCoy Logging Co.",
    KnoxBank="Knox Bank",MassGenfacCo="Mass-Genfac Co.",SleepEazzzeInn="Sleep Eazzze Inn",
    HavishamHotelSuites="Havisham Hotel Suites",FossoilField="Fossoil Field" }
D.KIND_GROUPS = {
    bank={"KnoxBank","SkyBlueBanking"},
    clinic={"MedicalCentre","FamilyDentistry","OptimaEyes","PetHealthPawmise"},
    education={"LouisvilleStateUniversity","Fun23Childcare"},
    research={"FinneganResearchGroup"},
    media={"932LBMWRadio","LBMWNetwork","KnoxTalkRadio","ENewsNowNetwork","TheKentuckyHerald",
        "NewspaperNationalLogo","NewspaperNewEraLogo","knoxknews","LouisvillePostLogo"},
    utilities={"AmeriglobeCommunications","H2Quavia"},
    electronics={"Valutech","ElectronHouse","TurboTV","Egenerex"},
    industry={"MassGenfacCo","McCoyLogging","KnoxPackKitchens","IvanovFactoryShowroom","KittenKnives",
        "MapsUnlimited","BoxpopBrewery","ScarletOakDistillery","KnoxDistillery","Kegsplosion"},
    transport={"KYTransit","UnitedShippingLogistics","RiverwoodBoatClub","LouisvilleBoat Club"},
    fuel={"Fossoil"},
    hotel={"HavishamHotelSuites","SleepEazzzeInn","EconoRoom","RedOwlInn","DuCaseApartments"},
    mechanic={"CarFixation","AmericanTire","nolanLogo","ScenicMileCarDealership"},
    hardware={"NailsandNuts","ZacsHardware","ReadyPrep"},
    agriculture={"ThumbsOfGreen","EdensOasis"},
    grocery={"NourishFoodMart","MilkNMore","MilkMonarchy","PerfickPotatoCo"},
    cafe={"BloominCoffee","CafedEris","CafeOle","CoffeeNirvana","DiMarcoCoffee","ExpressoEspress","NatsCafe"},
    restaurant={"Spiffos","AmericanEats","BBBQ","BluePlateDiner","ChiefSteakhouseBar","DeepFriedHeaven",
        "DogsAFlamin","Dotty4Donuts","FornoDellaMamma","FryerTooksFishNChips","GennysDiner","Go2Bread",
        "GoldenDragonBuffet","GustoDItalia","HappyRestaurant","IceIceTasty","IHeartWokRolls","JaysChicken",
        "JennysTable","LaVieEnGastronomie","LesTartesdeMademoiselleCeline","MaisonDuBouef","Sammies",
        "SmokeysSaloonRestaurant","SucrafruitCircus","SweetEats","SweetPeaRestaurant","TacoDelPancho",
        "TheCosyCrockpot","ThePlumpCornucopia","TheSeaShanty","TheWanderingSashimi","TitaMariasCantina"},
    entertainment={"BodyChisel","ElveeArena","FamilyFunzone","FunXtreme","HitVids","JukeBoxBowling",
        "LiveMusic","LouisvilleBruiser","LouisvilleMusicFestival1993","MeadDrinkandBloodyMerry","NiteGlo",
        "OnyxDriveInTheater","RiparianEntertainment","SanguineSpirits","ShakenAndStirred","TheBlackSaddle",
        "TheBlueFox","TheHardyHarBar","TheOrangeAnchor","TheRealSweat","TheSlugger","TheWoodenStein",
        "WestMapleCountryClub","FossoilField"},
    retail={"5BuxOrLess","AARonHuntingSupply","BeBeauty","BetterBedThanDead","BetterFurnishings",
        "BowWowWowDogNutrition","BrightedWhites","CandytownUSA","CantoRecords","Chuggs","ConvenUMart",
        "DressedToThe90s","FromTheDugout","GenteelyUsed","InkrAlley","LineByLineDesign","LiquortySplit",
        "LoansCashJewelry","LST","MashieSignsPainting","NeonFlowerSalon","Noteworthy","OlympiaDepartmentStore","WormOfBooks",
        "PalettePop","PawnShop","PoshBox","PurpleBlack","PurrfectBarkner","SashaSashay","SilkenBelles",
        "SpitfireFashion","StarsStripes","Superklean","SweetSugarBeauty","TheExquisitePearl","TheStraightShooter",
        "TheTopHanger","TheVelvetTassel","TopcrownPlaza","YourCloset","YuriDesign","Zlatkos"},
}
D.ROOM_BRANDS = {office_herald="TheKentuckyHerald",newspaperprint_herald="TheKentuckyHerald",
    spiffos="Spiffos",spiffoskitchen="Spiffos",spiffosaesthetic="Spiffos",gigamart="GigaMart",
    jackiejayeoffice="JackieJaye",jackiejayestudio="JackieJaye"}
-- Only explicit firm names. Ordinary labels such as 'Insurance' or 'Mall'
-- deliberately convey no brand.
D.SIGN_BRANDS = {["spiffos"]="Spiffos",["spiffos logo"]="Spiffos",["fossoil"]="Fossoil",
    ["sunstar motel"]="SunstarMotel",["greene's"]="Greenes",["optima eyes"]="OptimaEyes"}
-- Keys in the installed stock PrintMediaDefinitions.MiscDetails. Wide mall,
-- event, house-for-sale and shopping-plaza rectangles are excluded.
D.POI_BRANDS = {mccoyloggingcorp="McCoyLogging",nolansusedcars="nolanLogo",westmaplecountryclub="WestMapleCountryClub",
    ustoreitriverside="UStoreIt",ustoreitlouisville="UStoreIt",ustoreitmuldraugh="UStoreIt",
    fossoil1="Fossoil",fossoil2="Fossoil",fossoil3="Fossoil",fossoil4="Fossoil",fossoil5="Fossoil",
    fossoil6="Fossoil",fossoil7="Fossoil",fossoil8="Fossoil",fossoilfield="FossoilField",
    sunstarmotel="SunstarMotel",havishamsuites="HavishamHotelSuites",louisvillebruiser="LouisvilleBruiser",
    theseashanty="TheSeaShanty",scarletoakdistillery="ScarletOakDistillery",readyprep="ReadyPrep",
    lsu="LouisvilleStateUniversity",lectromaxmanufacturingjobad="Lectromax",spiffoshiringdixie="Spiffos",
    spiffoshiringlouisville="Spiffos",spiffoshiringwestpoint="Spiffos",pizzawhirledjobadrosewood="PizzaWhirled",
    hitvidsjobadmarchridge="HitVids",knoxbankjobadrosewood="KnoxBank",onyxdriveintheater="OnyxDriveInTheater",
    ducaseapartments="DuCaseApartments",elveearena="ElveeArena",knoxpackkitchens="KnoxPackKitchens",
    greenesjobadekron="Greenes",carfixation="CarFixation",nailsandnuts="NailsandNuts",rustyrifle="RustyRifle",
    americantire="AmericanTire",sammies="Sammies",sleepeazzzeinn="SleepEazzzeInn"}
D.KIND_FALLBACK = {police="_police",clinic="_medical",pharmacy="_medical",education="_education",
    research="_lab",home="_home",media="_media",industry="_industry",security="_industry",
    military="_industry",government="_county",community="_county",utilities="_industry",
    transport="_post",agriculture="_industry",bank="_office",fuel="_industry",mechanic="_industry",
    hardware="_industry",restaurant="_food",cafe="_food",grocery="_retail",retail="_retail",
    hotel="_hotel",entertainment="_media",electronics="_electronics",emergency="_fire"}
return D
